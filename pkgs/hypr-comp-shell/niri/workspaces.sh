#!/usr/bin/env bash
# niri port of workspaces.sh.
#
# Emits the SAME contract the top bar expects — $QS_RUN_WORKSPACES/workspaces.json,
# an array of { id, state: "active"|"occupied"|"empty", tooltip } for ids 1..N
# (N = workspaceCount) — but sourced from `niri msg` instead of hyprctl/.socket2.
#
# Caveat: niri workspaces are dynamic and per-output; we map them to the fixed
# 1..N model by their `idx` on the (single) output, so multi-monitor setups will
# be approximate.
source "$(dirname "${BASH_SOURCE[0]}")/caching.sh"
qs_ensure_cache "workspaces"

# Zombie prevention: Quickshell reloads can orphan old listener pipelines.
for pid in $(pgrep -f "workspaces.sh"); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done
cleanup() { pkill -P $$ 2>/dev/null; }
trap cleanup EXIT SIGTERM SIGINT

SETTINGS_FILE="$HOME/.config/hypr-comp/settings.json"
SEQ_END=$(jq -r '.workspaceCount // 8' "$SETTINGS_FILE" 2>/dev/null)
[[ "$SEQ_END" =~ ^[0-9]+$ ]] || SEQ_END=8

print_workspaces() {
    local spaces
    spaces=$(niri msg --json workspaces 2>/dev/null)
    [ -z "$spaces" ] && return
    echo "$spaces" | jq --arg end "$SEQ_END" -c '
        (map({ (.idx|tostring): . }) | add) as $byidx
        | [range(1; ($end|tonumber) + 1)] | map(
            . as $i
            | ($byidx[$i|tostring]) as $w
            | (if $w == null then "empty"
               elif $w.is_focused then "active"
               elif ($w.active_window_id != null) then "occupied"
               else "empty" end) as $state
            | { id: $i, state: $state, tooltip: ($w.name // "Empty") }
        )' > "$QS_RUN_WORKSPACES/workspaces.tmp"
    mv "$QS_RUN_WORKSPACES/workspaces.tmp" "$QS_RUN_WORKSPACES/workspaces.json"
}

print_workspaces

# Event-driven updates: niri's JSON event stream replaces the Hyprland socket.
# Debounce bursts (window moves emit many events) into a single redraw.
while true; do
    niri msg --json event-stream 2>/dev/null | while read -r line; do
        case "$line" in
            *Workspace*|*Window*)
                while read -t 0.05 -r _; do :; done
                print_workspaces
                ;;
        esac
    done
    sleep 1
done
