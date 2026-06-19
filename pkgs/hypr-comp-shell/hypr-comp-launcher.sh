#!/bin/sh
# Mod+P: open whichever shell is currently active's launcher.
#   B running -> the competition 3D launcher overlay
#   A running -> the daily app launcher (Main.handleCommand)
#   else (DMS / Persona) -> delegate to Persona's dispatcher (searchapp / DMS spotlight)
# Placeholders (@...@) are filled in by the package's installPhase.
if @pgrep@ -f -- "@configb@" >/dev/null 2>&1; then
    exec @qs@ ipc -p "@configb@" call applauncher toggle
elif @pgrep@ -f -- "@configa@" >/dev/null 2>&1; then
    exec @qs@ ipc -p "@configa@" call main handleCommand toggle applauncher ""
elif command -v persona-launcher >/dev/null 2>&1; then
    exec persona-launcher
else
    exec dms ipc call spotlight toggle
fi
