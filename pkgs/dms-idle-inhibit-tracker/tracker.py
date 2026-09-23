#!/usr/bin/env python3
"""Track org.freedesktop.ScreenSaver idle inhibitors on the session bus.

niri owns org.freedesktop.ScreenSaver and implements only Inhibit/UnInhibit --
there is no GetActive and no niri IPC call that lists holders, so the set of
things currently keeping the screen awake is unobservable from outside the
compositor. Recover it by eavesdropping on the bus: watch the Inhibit calls
and their replies, pair each cookie with the caller's PID, and drop cookies on
UnInhibit or when the caller disconnects. The result is written as JSON for the
DMS idleInhibitors widget to display.

This sees only the D-Bus half. Wayland clients that inhibit through
zwp_idle_inhibit_manager_v1 (Chromium/Electron, Firefox on Wayland) are
invisible here and to every other client; the widget detects those separately
with a pair of IdleMonitors and falls back to naming candidate windows.
"""
import json
import os
import re
import selectors
import subprocess
import sys
import time

STATE = os.environ.get(
    "DMS_IDLE_INHIBITORS_STATE",
    os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
                 "dms-idle-inhibit-tracker", "state.json"),
)

# Set DMS_IDLE_INHIBIT_DEBUG=1 to trace every bus block and state change.
DEBUG = bool(os.environ.get("DMS_IDLE_INHIBIT_DEBUG"))


def debug(*a):
    if DEBUG:
        print(*a, file=sys.stderr, flush=True)


RULES = [
    "type='method_call',interface='org.freedesktop.ScreenSaver'",
    "type='method_return'",
    "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged'",
]

# cookie -> holder record
held = {}
# (sender, serial) -> Inhibit call still waiting for the reply that carries its cookie
pending = {}


def pid_of(bus_name):
    try:
        out = subprocess.run(
            ["busctl", "--user", "call", "org.freedesktop.DBus",
             "/org/freedesktop/DBus", "org.freedesktop.DBus",
             "GetConnectionUnixProcessID", "s", bus_name],
            capture_output=True, text=True, timeout=3).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return None
    try:
        return int(out[1])
    except (IndexError, ValueError):
        return None


def proc_info(pid):
    if not pid:
        return {"comm": None, "cmdline": None}
    try:
        with open(f"/proc/{pid}/comm") as f:
            comm = f.read().strip()
    except OSError:
        return {"comm": None, "cmdline": None}
    try:
        with open(f"/proc/{pid}/cmdline") as f:
            cmdline = f.read().replace("\0", " ").strip()
    except OSError:
        cmdline = None
    return {"comm": comm, "cmdline": (cmdline or "")[:200]}


def flush():
    # systemd's RuntimeDirectory= makes this for the unit, but the tracker is
    # also runnable by hand.
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    # Per-pid temp name: a shared one races when two instances overlap.
    tmp = f"{STATE}.{os.getpid()}.tmp"
    payload = {
        "inhibited": bool(held),
        "updated": time.time(),
        "inhibitors": sorted(held.values(), key=lambda r: r["since"]),
    }
    with open(tmp, "w") as f:
        json.dump(payload, f, indent=2)
    os.replace(tmp, STATE)
    debug("flush inhibited=%s held=%s" % (bool(held), list(held)))


def field(hdr, key):
    m = re.search(rf"\b{key}=(\S+?)(?:;|\s|$)", hdr)
    return m.group(1) if m else None


def unquote(arg):
    m = re.match(r'string "(.*)"$', arg)
    return m.group(1) if m else None


def handle(hdr, args):
    debug("block", hdr, args)
    member = field(hdr, "member")
    is_call = hdr.startswith("method call")

    if is_call and member == "Inhibit":
        strs = [s for s in (unquote(a) for a in args) if s is not None]
        pending[(field(hdr, "sender"), field(hdr, "serial"))] = {
            "app": strs[0] if strs else "?",
            "reason": strs[1] if len(strs) > 1 else "",
            "sender": field(hdr, "sender"),
        }
        return

    if is_call and member == "UnInhibit":
        for a in args:
            m = re.match(r"uint32 (\d+)$", a)
            if m and m.group(1) in held:
                del held[m.group(1)]
                flush()
        return

    if hdr.startswith("method return"):
        rec = pending.pop((field(hdr, "destination"), field(hdr, "reply_serial")), None)
        if not rec:
            return
        for a in args:
            m = re.match(r"uint32 (\d+)$", a)
            if not m:
                continue
            pid = pid_of(rec["sender"])
            held[m.group(1)] = {**rec, "cookie": int(m.group(1)), "pid": pid,
                                **proc_info(pid), "since": time.time()}
            flush()
        return

    if member == "NameOwnerChanged":
        strs = [unquote(a) for a in args]
        # name, old_owner, new_owner -- an empty new owner means it disconnected,
        # which releases every inhibitor it held.
        if len(strs) >= 3 and strs[0] and strs[2] == "":
            gone = [c for c, r in held.items() if r["sender"] == strs[0]]
            for c in gone:
                del held[c]
            if gone:
                flush()


def main():
    flush()
    # dbus-monitor block-buffers into a pipe, so force line buffering; without
    # it a lone inhibit can sit unread until unrelated traffic fills the buffer.
    mon = subprocess.Popen(["stdbuf", "-oL", "dbus-monitor", "--session"] + RULES,
                           stdout=subprocess.PIPE)

    # A message is a header line plus indented argument lines with no
    # terminator, so a block is only known to be complete once the next one
    # arrives. Waiting for that stalls a capture for as long as the bus stays
    # quiet -- exactly when an inhibit matters -- so treat a read gap as the
    # end of the block.
    #
    # Read the fd directly rather than iterating the pipe: a buffered readline
    # pulls the whole chunk into Python, leaving the fd with nothing pending,
    # so select() would report not-ready and the gap would fire before the
    # argument lines had been consumed. Own the buffering and select is honest.
    fd = mon.stdout.fileno()
    sel = selectors.DefaultSelector()
    sel.register(fd, selectors.EVENT_READ)

    buf = ""
    hdr = None
    args = []

    def feed(line):
        nonlocal hdr, args
        if line[:1].isalpha() and " time=" in line:
            if hdr:
                handle(hdr, args)
            hdr, args = line, []
        elif hdr and line.startswith((" ", "\t")):
            args.append(line.strip())
        elif hdr:
            handle(hdr, args)
            hdr, args = None, []

    while True:
        if sel.select(timeout=0.2):
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            buf += chunk.decode("utf-8", "replace")
            *lines, buf = buf.split("\n")
            for line in lines:
                feed(line)
        else:
            if hdr:
                handle(hdr, args)
                hdr, args = None, []
            if mon.poll() is not None:
                break

    if hdr:
        handle(hdr, args)


if __name__ == "__main__":
    main()
