#!/usr/bin/env bash
# niri port of watchers/kb_wait.sh: block until the keyboard layout is switched,
# then exit (one-shot; the top bar re-runs it in a loop). Matching only the
# "KeyboardLayoutSwitched" event (not the initial "KeyboardLayoutsChanged"
# snapshot) avoids returning immediately and busy-looping.
niri msg --json event-stream 2>/dev/null | grep -q -m1 'KeyboardLayoutSwitched'
sleep 0.05
