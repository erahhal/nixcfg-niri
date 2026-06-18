#!/bin/sh
# Mod+D: switch between DankMaterialShell and Persona-Quickshell.
# Only one shell runs at a time under niri:
#   - Persona down -> stop the dms service, then start Persona (daemonized)
#   - Persona up   -> kill Persona, then bring dms back
# Placeholders (@...@) are filled in by the package's installPhase.
if @pgrep@ -f -- "@config@" >/dev/null 2>&1; then
    @qs@ kill -p "@config@"
    exec @systemctl@ --user restart dms
else
    @systemctl@ --user stop dms
    exec @persona@ -d
fi
