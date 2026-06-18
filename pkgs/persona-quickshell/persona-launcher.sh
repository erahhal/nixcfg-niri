#!/bin/sh
# Mod+P: open whichever shell's launcher is currently active.
#   - Persona running -> toggle Persona's launcher (searchapp IpcHandler)
#   - otherwise        -> toggle the DankMaterialShell spotlight launcher
# `dms` is resolved from PATH (the same way DMS's own keybind spawns it).
# Placeholders (@...@) are filled in by the package's installPhase.
if @pgrep@ -f -- "@config@" >/dev/null 2>&1; then
    exec @qs@ ipc -p "@config@" call searchapp toggle
else
    exec dms ipc call spotlight toggle
fi
