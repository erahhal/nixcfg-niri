# Cycle a DDC/CI monitor through a list of inputs (VCP feature 0x60).
#
# callPackage returns a function taking the host's monitor data:
#
#   (pkgs.callPackage ./ddc-input-toggle {}) {
#     monitor = "SomeModel-27";
#     inputs = [
#       { code = "0x0f"; label = "DisplayPort-1"; }
#       { code = "0x11"; label = "HDMI-1"; }
#     ];
#   }
#
# Bus lookup is cached in XDG_RUNTIME_DIR, because `ddcutil detect` walks every
# i2c bus and takes seconds. The cache is validated before use and dropped when
# it stops answering -- bus numbers move when monitors or GPUs come and go.
{ lib
, writeShellScript
, coreutils
, ddcutil
, gnugrep
, gnused
, libnotify
}:

{ monitor
, inputs
}:

assert lib.assertMsg (monitor != "")
  "ddc-input-toggle: `monitor` must identify the display in `ddcutil detect` output";
assert lib.assertMsg (lib.length inputs >= 2)
  "ddc-input-toggle: `inputs` must list at least two inputs to cycle between";

let
  codes = lib.concatMapStringsSep " " (i: lib.escapeShellArg i.code) inputs;
  labels = lib.concatMapStringsSep " " (i: lib.escapeShellArg i.label) inputs;
in
writeShellScript "ddc-input-toggle" ''
  set -u

  CODES=(${codes})
  LABELS=(${labels})
  MONITOR=${lib.escapeShellArg monitor}
  CACHE="''${XDG_RUNTIME_DIR:-/tmp}/ddc-input-toggle.$(echo "$MONITOR" | ${gnused}/bin/sed 's/[^A-Za-z0-9]/_/g')"

  notify() {
    ${libnotify}/bin/notify-send -t 3000 "Monitor Input" "$1" 2>/dev/null || true
    echo "$1"
  }

  # Normalise a VCP value to decimal so "0x0f", "0F" and "f" all compare equal.
  norm() {
    local v="''${1#0x}"
    v="''${v#0X}"
    printf '%d' "$((16#$v))" 2>/dev/null || echo "-1"
  }

  bus_works() {
    ${ddcutil}/bin/ddcutil --bus "$1" --skip-ddc-checks getvcp 60 >/dev/null 2>&1
  }

  detect_bus() {
    ${ddcutil}/bin/ddcutil detect 2>/dev/null \
      | ${gnugrep}/bin/grep -B 4 -- "$MONITOR" \
      | ${gnugrep}/bin/grep "I2C bus:" \
      | ${gnused}/bin/sed -E 's|.*/dev/i2c-([0-9]+).*|\1|' \
      | ${coreutils}/bin/head -n 1
  }

  get_bus() {
    if [ -f "$CACHE" ]; then
      local cached
      cached=$(${coreutils}/bin/cat "$CACHE")
      if bus_works "$cached"; then
        echo "$cached"
        return 0
      fi
      rm -f "$CACHE"
    fi

    # A cold i2c-dev sometimes enumerates nothing until it is reloaded, so
    # retry around a module reload before giving up. Needs passwordless sudo;
    # `sudo -n` fails silently rather than blocking on a password prompt that
    # has no terminal to appear on.
    for _ in 1 2 3; do
      local bus
      bus=$(detect_bus)
      if [ -n "$bus" ]; then
        echo "$bus" > "$CACHE"
        echo "$bus"
        return 0
      fi
      if command -v sudo >/dev/null 2>&1; then
        sudo -n /run/current-system/sw/bin/modprobe -r i2c-dev 2>/dev/null || true
        sudo -n /run/current-system/sw/bin/modprobe i2c-dev 2>/dev/null || true
      fi
      ${coreutils}/bin/sleep 1
    done
    return 1
  }

  BUS=$(get_bus) || BUS=""
  if [ -z "$BUS" ]; then
    notify "$MONITOR not detected (DDC/CI unavailable)"
    exit 1
  fi

  CURRENT_RAW=$(${ddcutil}/bin/ddcutil --bus "$BUS" --skip-ddc-checks getvcp 60 2>/dev/null \
    | ${gnugrep}/bin/grep -o "sl=0x[0-9a-fA-F]\+" \
    | ${coreutils}/bin/cut -d'x' -f2)
  CURRENT=$(norm "''${CURRENT_RAW:-}")

  NEXT=0
  for i in "''${!CODES[@]}"; do
    if [ "$(norm "''${CODES[$i]}")" = "$CURRENT" ]; then
      NEXT=$(( (i + 1) % ''${#CODES[@]} ))
      break
    fi
  done

  if ! ${ddcutil}/bin/ddcutil --bus "$BUS" --skip-ddc-checks --noverify setvcp 60 "''${CODES[$NEXT]}" 2>/dev/null; then
    notify "Failed to switch $MONITOR to ''${LABELS[$NEXT]}"
    exit 1
  fi

  notify "Switched to ''${LABELS[$NEXT]}"
''
