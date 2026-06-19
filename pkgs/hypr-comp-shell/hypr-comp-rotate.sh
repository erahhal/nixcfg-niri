#!/bin/sh
# Mod+Shift+D: rotate the session shell  DMS -> A -> B -> DMS.
#   A = hypr-comp-a (daily + earth/stars bg), B = hypr-comp-b (full competition).
# Each variant runs as a transient systemd --user unit (like dms) so that
# stopping it tears down the whole cgroup — including the shell's watcher
# subprocesses (niri msg event-stream, inotifywait, ...) — with no orphans.
# Mutually exclusive with DMS and Persona (Mod+D).
# Placeholders (@...@) are filled in by the package's installPhase.
if @systemctl@ --user is-active --quiet hypr-comp-a; then
    # A -> B
    @systemctl@ --user stop hypr-comp-a
    @systemctl@ --user reset-failed hypr-comp-b 2>/dev/null || true
    exec @systemdrun@ --user --collect --quiet --unit=hypr-comp-b "@hyprcompb@"
elif @systemctl@ --user is-active --quiet hypr-comp-b; then
    # B -> DMS
    @systemctl@ --user stop hypr-comp-b
    @systemctl@ --user reset-failed dms 2>/dev/null || true
    exec @systemctl@ --user restart dms
else
    # DMS (or Persona) -> A
    @systemctl@ --user stop dms
    @pkill@ -f -- 'share/persona-quickshell' 2>/dev/null || true
    @systemctl@ --user reset-failed hypr-comp-a 2>/dev/null || true
    exec @systemdrun@ --user --collect --quiet --unit=hypr-comp-a "@hyprcompa@"
fi
