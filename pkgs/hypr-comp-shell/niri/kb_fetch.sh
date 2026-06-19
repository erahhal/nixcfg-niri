#!/usr/bin/env bash
# niri port of watchers/kb_fetch.sh: print the current keyboard layout as a
# 2-letter uppercase code (e.g. "EN"), matching the upstream output contract.
layout=$(niri msg --json keyboard-layouts 2>/dev/null | jq -r '.names[.current_idx] // empty')
[[ -z "$layout" || "$layout" == "null" ]] && layout="US"
echo "${layout:0:2}" | tr '[:lower:]' '[:upper:]'
