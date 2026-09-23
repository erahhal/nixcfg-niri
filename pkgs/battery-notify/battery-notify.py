#!/usr/bin/env python3
"""Keep one persistent desktop notification on screen while running on battery.

Why: a charger that is plugged in but not delivering power (dead port, loose
cable, an adapter that dropped its PD contract) is invisible. The embedded
controller reports "no AC" exactly as if nothing were plugged in, the bar's
battery icon quietly changes, and the first unmissable signal is an emergency
hibernate at 2% -- which, with the screen dark for the minutes it takes to
write the image, reads as a lockup. DankMaterialShell's own low-battery alert
is a 5 s toast and its critical alert shells out to notify-send, so neither
was ever seen.

What: watch UPower over D-Bus. For as long as UPower says the machine is on
battery, keep ONE notification up and step it through UPower's own warning
levels (low / critical / action -- the thresholds that fire the critical-power
action, so the text always matches what upower is about to do). Post it with
expire timeout 0, which the notification spec defines as "never expire" and
DMS honours as "stay until closed". If the user dismisses it, stay quiet until
the level changes. When external power returns, close it and show a short
"external power connected" confirmation -- the confirmation is the point: a
charger that is not delivering produces no AC event, so the persistent notice
just stays and the confirmation never appears.

How: standard library only. `gdbus monitor` is the wake-up (it needs no
privileges, unlike `busctl monitor`); the actual state is re-read with
`busctl --json` on every wake-up and on a 60 s fallback poll, so nothing
depends on parsing signal payloads. A second `gdbus monitor` on the session
bus reports NotificationClosed so a user dismissal is respected and a restart
of the notification daemon re-posts what should be showing.
"""

import argparse
import json
import os
import re
import select
import signal
import subprocess
import sys
import time

APP_NAME = "battery-notify"
UPOWER = "org.freedesktop.UPower"
UPOWER_PATH = "/org/freedesktop/UPower"
DISPLAY_DEVICE = "/org/freedesktop/UPower/devices/DisplayDevice"
DEVICE_IFACE = "org.freedesktop.UPower.Device"
NOTIF = "org.freedesktop.Notifications"
NOTIF_PATH = "/org/freedesktop/Notifications"

POLL_SECONDS = 60
TRANSIENT_MS = 5000
URGENCY_NORMAL = 1
URGENCY_CRITICAL = 2

# org.freedesktop.UPower.Device.WarningLevel
LEVELS = {3: "low", 4: "critical", 5: "action"}
# org.freedesktop.UPower.Device.State
STATE_CHARGING = 1
STATE_FULLY_CHARGED = 4
STATE_PENDING_CHARGE = 5

# NotificationClosed reasons
CLOSED_EXPIRED = 1
CLOSED_DISMISSED = 2
CLOSED_BY_CALL = 3

CLOSED_RE = re.compile(r"NotificationClosed \(uint32 (\d+), uint32 (\d+)\)")
NOTIFY_ID_RE = re.compile(r"\(uint32 (\d+),\)")

ACTION_VERBS = {
    "Hibernate": "hibernate",
    "HybridSleep": "hybrid-sleep",
    "PowerOff": "power off",
}


def log(msg):
    print(msg, flush=True)


def run(cmd, timeout=15):
    """Run a command; return stdout or None (logging why) on any failure."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        log(f"{cmd[0]} failed: {e}")
        return None
    if p.returncode != 0:
        log(f"{' '.join(cmd[:3])} exited {p.returncode}: {p.stderr.strip()}")
        return None
    return p.stdout


def busctl_json(args):
    out = run(["busctl", "--system", "--json=short", *args])
    if out is None:
        return None
    try:
        return json.loads(out)
    except ValueError as e:
        log(f"busctl returned non-JSON: {e}")
        return None


def read_state():
    """Snapshot of what UPower currently believes, or None if unavailable."""
    on_battery = busctl_json(["get-property", UPOWER, UPOWER_PATH, UPOWER, "OnBattery"])
    props = busctl_json(["call", UPOWER, DISPLAY_DEVICE, "org.freedesktop.DBus.Properties",
                         "GetAll", "s", DEVICE_IFACE])
    if on_battery is None or props is None:
        return None
    try:
        d = props["data"][0]
        return {
            "on_battery": bool(on_battery["data"]),
            "present": bool(d["IsPresent"]["data"]),
            "state": int(d["State"]["data"]),
            "percentage": float(d["Percentage"]["data"]),
            "warning": int(d["WarningLevel"]["data"]),
            "time_to_empty": int(d["TimeToEmpty"]["data"]),
            "icon": str(d["IconName"]["data"]) or "battery-symbolic",
        }
    except (KeyError, IndexError, TypeError, ValueError) as e:
        log(f"unexpected UPower property shape: {e}")
        return None


def gdbus_call(bus, dest, path, iface_method, *args):
    return run(["gdbus", "call", f"--{bus}", "--dest", dest, "--object-path", path,
                "--method", iface_method, *args])


def notif_owner():
    """Unique bus name of the notification daemon, or None if none is running."""
    out = run(["gdbus", "call", "--session", "--dest", "org.freedesktop.DBus",
               "--object-path", "/org/freedesktop/DBus",
               "--method", "org.freedesktop.DBus.GetNameOwner", NOTIF])
    if out is None:
        return None
    m = re.search(r"'(:[0-9.]+)'", out)
    return m.group(1) if m else None


def notify(replaces_id, icon, summary, body, urgency, timeout_ms):
    """Post or replace a notification; return its id, or None on failure."""
    # gdbus parses each argument as a GVariant of the expected type and falls
    # back to treating it as a plain string, so summary/body need no quoting.
    out = gdbus_call("session", NOTIF, NOTIF_PATH, f"{NOTIF}.Notify",
                     APP_NAME, str(replaces_id), icon, summary, body, "[]",
                     f"{{'urgency': <byte {urgency}>}}", str(timeout_ms))
    if out is None:
        return None
    m = NOTIFY_ID_RE.search(out)
    return int(m.group(1)) if m else None


def close_notification(nid):
    gdbus_call("session", NOTIF, NOTIF_PATH, f"{NOTIF}.CloseNotification", str(nid))


def fmt_time_left(seconds):
    if seconds <= 0:
        return ""
    minutes = int(round(seconds / 60 / 5.0)) * 5
    if minutes < 5:
        return ", under 5 min left"
    h, m = divmod(minutes, 60)
    if h and m:
        return f", about {h} h {m} min left"
    if h:
        return f", about {h} h left"
    return f", about {m} min left"


class Watcher:
    def __init__(self, action_percent, critical_action):
        self.action_percent = action_percent
        self.action_verb = ACTION_VERBS.get(critical_action, "")
        self.owner = None          # notification daemon's unique name
        self.notif_id = 0          # our persistent notification, 0 = none
        self.level = None          # level the persistent notification shows
        self.bucket = None         # 5 % step the text was last written for
        self.dismissed = False     # user closed it; quiet until the level changes
        self.was_on_battery = None  # None until the first successful read

    # ---- text -----------------------------------------------------------

    def compose(self, st, level):
        pct = int(round(st["percentage"]))
        left = fmt_time_left(st["time_to_empty"])
        will = ""
        if self.action_verb and self.action_percent > 0:
            will = f" Below {self.action_percent}% the system will {self.action_verb}."
        if level == "action":
            verb = self.action_verb or "run its critical-power action"
            return (f"Battery empty: {verb} now",
                    f"upower is starting to {verb} at {pct}%. A dark, unresponsive "
                    f"screen for a few minutes is normal while memory is written to disk.",
                    URGENCY_CRITICAL)
        if level == "critical":
            return (f"Battery critical: {pct}%",
                    f"{pct}% left{left}. Plug in now.{will}",
                    URGENCY_CRITICAL)
        if level == "low":
            return (f"Battery low: {pct}%",
                    f"{pct}% left{left}. Plug in soon.{will}",
                    URGENCY_CRITICAL)
        return ("Running on battery",
                f"External power is not being delivered. {pct}% left{left}. "
                f"If a charger is plugged in, it is not charging this machine.",
                URGENCY_NORMAL)

    # ---- state machine --------------------------------------------------

    def post(self, st, level):
        summary, body, urgency = self.compose(st, level)
        nid = notify(self.notif_id, st["icon"], summary, body, urgency, 0)
        if nid is None:
            log("could not post notification; will retry")
            return
        self.notif_id = nid
        self.level = level
        self.bucket = int(st["percentage"] // 5)
        self.dismissed = False
        log(f"posted #{nid} [{level}] {summary}")

    def drop(self):
        if self.notif_id:
            close_notification(self.notif_id)
            log(f"closed #{self.notif_id}")
        self.notif_id = 0
        self.level = None
        self.bucket = None
        self.dismissed = False

    def refresh(self):
        st = read_state()
        if st is None:
            return
        owner = notif_owner()
        if owner is None:
            # No notification daemon yet (session still starting) or it died.
            # Forget the id so a re-post happens once one is back.
            self.notif_id = 0
            self.level = None
            return
        if owner != self.owner:
            if self.owner is not None:
                log(f"notification daemon changed owner ({self.owner} -> {owner}); re-posting")
            self.owner = owner
            self.notif_id = 0
            self.level = None
            self.dismissed = False

        if st["on_battery"] and st["present"]:
            level = LEVELS.get(st["warning"], "none")
            if level != self.level:
                self.post(st, level)
            elif self.notif_id and not self.dismissed and int(st["percentage"] // 5) != self.bucket:
                self.post(st, level)  # same level, refresh the numbers in place
        else:
            came_back = self.was_on_battery is True and not st["on_battery"]
            self.drop()
            if came_back:
                pct = int(round(st["percentage"]))
                if st["state"] == STATE_CHARGING:
                    body = f"{pct}%, charging."
                elif st["state"] == STATE_PENDING_CHARGE:
                    body = f"{pct}%, held at the charge limit."
                elif st["state"] == STATE_FULLY_CHARGED:
                    body = f"{pct}%, fully charged."
                else:
                    body = f"{pct}%."
                notify(0, st["icon"], "External power connected", body, URGENCY_NORMAL, TRANSIENT_MS)
                log(f"external power back at {pct}%")
        self.was_on_battery = st["on_battery"]

    def on_session_line(self, line):
        m = CLOSED_RE.search(line)
        if not m:
            return
        nid, reason = int(m.group(1)), int(m.group(2))
        if nid != self.notif_id or reason == CLOSED_BY_CALL:
            return
        # Dismissed (or expired, which timeout 0 should never do): the user has
        # seen it. Stay quiet until the level changes or power comes back.
        self.notif_id = 0
        self.dismissed = True
        log(f"#{nid} closed by user (reason {reason}); quiet until the next level")


# ---- process plumbing -----------------------------------------------------

class LineReader:
    """Non-blocking line splitter over a pipe fd, for use with select()."""

    def __init__(self, proc):
        assert proc.stdout is not None
        self.proc = proc
        self.fd = proc.stdout.fileno()
        self.buf = b""

    def read_lines(self):
        chunk = os.read(self.fd, 65536)
        if not chunk:
            return None  # EOF: the monitor died
        self.buf += chunk
        *lines, self.buf = self.buf.split(b"\n")
        return [l.decode("utf-8", "replace") for l in lines]


def spawn_monitor(bus, dest):
    return subprocess.Popen(["gdbus", "monitor", f"--{bus}", "--dest", dest],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)


def self_test(w):
    """Walk the notification ladder against the live daemon, then clean up."""
    st = read_state()
    if st is None:
        log("self-test: UPower not reachable")
        return 1
    if notif_owner() is None:
        log("self-test: no notification daemon on the session bus")
        return 1
    for level in ("none", "low", "critical"):
        w.post(st, level)
        time.sleep(3)
    w.drop()
    notify(0, st["icon"], "External power connected", "Self-test finished.", URGENCY_NORMAL, TRANSIENT_MS)
    return 0


def main():
    ap = argparse.ArgumentParser(
        prog="battery-notify",
        description="Keep one persistent desktop notification on screen while running on battery.")
    ap.add_argument("--action-percent", type=int, default=0,
                    help="upower PercentageAction, quoted in the warning text (0 = omit)")
    ap.add_argument("--critical-action", default="",
                    help="upower CriticalPowerAction (Hibernate, HybridSleep, PowerOff)")
    ap.add_argument("--test", action="store_true",
                    help="post the on-battery, low and critical notifications for 3 s each, then exit")
    args = ap.parse_args()

    w = Watcher(args.action_percent, args.critical_action)
    if args.test:
        return self_test(w)

    # systemd kills the whole cgroup on stop; this is for foreground runs, so
    # the finally: below still reaches the two gdbus children.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    sysmon = spawn_monitor("system", UPOWER)
    sessmon = spawn_monitor("session", NOTIF)
    sysr, sessr = LineReader(sysmon), LineReader(sessmon)
    readers = {sysr.fd: sysr, sessr.fd: sessr}

    w.refresh()
    log(f"watching UPower (on battery: {w.was_on_battery}, action at {args.action_percent}%)")
    try:
        while True:
            ready, _, _ = select.select(list(readers), [], [], POLL_SECONDS)
            if not ready:
                w.refresh()
                continue
            wake = False
            for fd in ready:
                lines = readers[fd].read_lines()
                if lines is None:
                    log("a gdbus monitor exited; restarting")
                    return 1
                for line in lines:
                    if fd == sysr.fd:
                        # Any UPower change is cheap to re-read; do not parse payloads.
                        wake = wake or "PropertiesChanged" in line
                    elif "NotificationClosed" in line:
                        w.on_session_line(line)
                    elif "is owned by" in line:
                        wake = True  # daemon (re)appeared
            if wake:
                w.refresh()
    finally:
        for p in (sysmon, sessmon):
            p.terminate()


if __name__ == "__main__":
    sys.exit(main())
