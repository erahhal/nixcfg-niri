#!/bin/sh
# Mod+D: switch between DankMaterialShell and Persona-Quickshell.
# Only one shell runs at a time under niri:
#   - Persona down -> stop the dms service, then start Persona (daemonized)
#   - Persona up   -> kill Persona, then bring dms back
# Placeholders (@...@) are filled in by the package's installPhase.
if @pgrep@ -f -- "@config@" >/dev/null 2>&1; then
    @qs@ kill -p "@config@"
    # Clear any start-rate-limit trip from quick toggles before restarting.
    @systemctl@ --user reset-failed dms 2>/dev/null || true
    exec @systemctl@ --user restart dms
else
    @systemctl@ --user stop dms
    # hypr-comp variants run as transient systemd units; stop them cleanly
    # (tears down their cgroup, no orphaned watcher subprocesses).
    @systemctl@ --user stop hypr-comp-a hypr-comp-b 2>/dev/null || true
    exec @persona@ -d
fi
