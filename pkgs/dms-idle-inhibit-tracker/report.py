#!/usr/bin/env python3
"""Collect everything knowable about what is keeping this screen awake.

Three independent sources, because no single one is complete on niri:

  dbus     Exact holders of org.freedesktop.ScreenSaver inhibits, recovered by
           dms-idle-inhibit-tracker. niri owns that bus name and offers no way
           to enumerate holders, so this is the only route to them.
  logind   systemd inhibitor locks. Only `idle` blocks stop a screen lock;
           `sleep` locks (which most apps take) merely delay suspend, so they
           are reported separately rather than mixed in.
  wayland  Candidates only. Clients inhibiting via zwp_idle_inhibit_manager_v1
           are invisible to every client, so the best available answer is the
           set of windows that could be responsible: visible (niri only honours
           an inhibitor on a visible surface) and from an app family known to
           use the protocol.

The widget pairs this with a pair of IdleMonitors that tell it *whether*
something is inhibiting; this tells it *who*.
"""
import json
import os
import re
import subprocess

STATE = os.environ.get(
    "DMS_IDLE_INHIBITORS_STATE",
    os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
                 "dms-idle-inhibit-tracker", "state.json"),
)

# App families whose Wayland clients are known to take zwp_idle_inhibit locks:
# Chromium and anything Electron (Ozone), Firefox, and the media players.
WAYLAND_INHIBIT_FAMILIES = re.compile(
    r"chrom|brave|electron|slack|discord|vesktop|signal|element|telegram|"
    r"spotify|firefox|zoom|teams|mpv|vlc|jellyfin|plex|steam|joplin|obs",
    re.IGNORECASE,
)


def run_json(*cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return None


def dbus_holders():
    try:
        with open(STATE) as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return None  # distinct from []: the tracker is not running
    return data.get("inhibitors", [])


def logind_locks():
    """logind inhibitor locks, split by whether one can hold off a lock screen.

    ListInhibitors over D-Bus rather than `systemd-inhibit --list`: the text
    output is space-separated with spaces inside the WHO column ("Realtime
    Kit"), so it cannot be split reliably.
    """
    data = run_json("busctl", "--system", "--json=short", "call",
                    "org.freedesktop.login1", "/org/freedesktop/login1",
                    "org.freedesktop.login1.Manager", "ListInhibitors")
    idle, other = [], []
    try:
        rows = data["data"][0]
    except (TypeError, KeyError, IndexError):
        return {"idle": idle, "other": other}

    for row in rows:
        try:
            what, who, why, mode, uid, pid = row
        except (TypeError, ValueError):
            continue
        rec = {"who": who, "why": why, "what": what, "mode": mode,
               "uid": uid, "pid": pid}
        # Only an `idle` lock taken in `block` mode can hold off a lock screen;
        # a `sleep` lock (what most apps take) only delays suspend.
        if "idle" in what.split(":") and mode == "block":
            idle.append(rec)
        else:
            other.append(rec)
    return {"idle": idle, "other": other}


def wayland_candidates():
    wins = run_json("niri", "msg", "-j", "windows")
    wss = run_json("niri", "msg", "-j", "workspaces")
    if wins is None or wss is None:
        return None  # not niri, or niri not answering

    active = {w["id"] for w in wss if w.get("is_active")}
    out = []
    for w in wins:
        app_id = w.get("app_id") or ""
        # niri only honours an inhibitor whose surface is visible, so a window
        # parked on another workspace cannot be the one holding the screen up.
        if w.get("workspace_id") not in active:
            continue
        if not WAYLAND_INHIBIT_FAMILIES.search(app_id):
            continue
        out.append({"app_id": app_id, "title": w.get("title"), "pid": w.get("pid"),
                    "focused": bool(w.get("is_focused"))})
    return out


def main():
    dbus = dbus_holders()
    print(json.dumps({
        "trackerRunning": dbus is not None,
        "dbus": dbus or [],
        "logind": logind_locks(),
        "waylandCandidates": wayland_candidates(),
    }, indent=2))


if __name__ == "__main__":
    main()
