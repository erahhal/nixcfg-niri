# hypr-comp — ilyamiro's Quickshell desktop shell, vendored and (being) ported to niri.
# https://github.com/ilyamiro/nixos-configuration (config/sessions/hyprland/scripts)
#
# The `hypr-comp` repo the user linked is only a competition snapshot; the full,
# runnable shell lives in the author's nixos-configuration, which is what we vendor.
#
# This is a full alternative DE (top bar, notification daemon, tray, lock, ~15
# popups). It is built for Hyprland and hardcodes ~/.config/hypr/... paths in many
# runtime `Process` commands; those are async spawns so they don't block QML load
# (Stage 0 launches; the niri port of those scripts/paths is Stage 1).
#
# Stage 0 deliverable: a self-contained store install + a `hypr-comp` wrapper that
# launches the shell with the Qt6 QtMultimedia fix (same as persona-quickshell) and
# a runtime PATH closure of every CLI tool the widgets shell out to.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  quickshell,
  qt6,
  # runtime closure (tools the QML/scripts invoke at runtime)
  bashInteractive,
  coreutils,
  gnugrep,
  gnused,
  gawk,
  findutils,
  python3,
  jq,
  file,
  curl,
  playerctl,
  pulseaudio,
  wireplumber,
  cava,
  networkmanager,
  bluez,
  iw,
  iproute2,
  brightnessctl,
  libnotify,
  cliphist,
  wl-clipboard,
  imagemagick,
  inotify-tools,
  glib,
  matugen,
  niri,
  procps,
  systemd,
}:

let
  # Everything the shell's Process/execDetached calls expect on PATH.
  runtimeDeps = [
    bashInteractive coreutils gnugrep gnused gawk findutils
    python3 jq file curl
    playerctl pulseaudio wireplumber cava
    networkmanager bluez iw iproute2 brightnessctl
    libnotify cliphist wl-clipboard imagemagick
    inotify-tools glib matugen niri
    # quickshell: qs_manager.sh shells out to `quickshell ipc ...`.
    # procps: workspaces.sh uses pgrep/pkill.
    quickshell procps
  ];

  # Competition entry (the Reddit submission): starfield + rotating-earth
  # dashboard (+ a 3D launcher). Incomplete on its own — it rides on the
  # Caching/MatugenColors/Scaler framework vendored from nixos-configuration above.
  srcComp = fetchFromGitHub {
    owner = "ilyamiro";
    repo = "hypr-comp";
    rev = "fa5b0bb8d7937d2576faef83bc00b672a5c89ad1";
    hash = "sha256-NBg9hHgOu+YdPaEmTV0tob7HLkVXA8pW7nx/4CLaCfw=";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hypr-comp-shell";
  version = "0-unstable-2026-06-03";

  src = fetchFromGitHub {
    owner = "ilyamiro";
    repo = "nixos-configuration";
    rev = "d66c4a5915d2991d2e1cebe16f4c9b21f9fa0e6e";
    hash = "sha256-INKQ4Vl08tpcS9jGdiEB2LnjFh3bhLoGRBCVnQJISys=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    base="$out/share/hypr-comp"
    mkdir -p "$base"
    cp -r config/sessions/hyprland/scripts "$base/scripts"
    chmod -R u+w "$base"

    # ── Stage 1: port Hyprland coupling to niri + repoint hardcoded paths ──────
    qsdir="$base/scripts/quickshell"

    # Config.qml derives settingsJsonPath / qsScriptsDir / weatherEnvPath from
    # hyprDir. Point settings at a writable per-user path; point the scripts dir
    # (used for the TopBar reload IPC) at our store tree.
    substituteInPlace "$qsdir/Config.qml" \
      --replace-fail 'homeDir + "/.config/hypr"' 'homeDir + "/.config/hypr-comp"' \
      --replace-fail 'hyprDir + "/scripts/quickshell"' "\"$qsdir\""

    # Repoint the hardcoded ~/.config/hypr bash literals scattered across the QML
    # Process commands and helper scripts: script refs -> our store tree;
    # settings.json -> a writable per-user path (~/.config/hypr-comp).
    while IFS= read -r f; do
      substituteInPlace "$f" \
        --replace-quiet '~/.config/hypr/scripts' "$base/scripts" \
        --replace-quiet '$HOME/.config/hypr/scripts' "$base/scripts" \
        --replace-quiet '~/.config/hypr/settings.json' '~/.config/hypr-comp/settings.json' \
        --replace-quiet '$HOME/.config/hypr/settings.json' '$HOME/.config/hypr-comp/settings.json'
    done < <(grep -rlF '.config/hypr' "$base/scripts")

    # Swap the compositor-coupled scripts for niri rewrites (workspaces + keyboard).
    cp ${./niri/workspaces.sh} "$base/scripts/workspaces.sh"
    cp ${./niri/kb_fetch.sh}   "$qsdir/watchers/kb_fetch.sh"
    cp ${./niri/kb_wait.sh}    "$qsdir/watchers/kb_wait.sh"

    # qs_manager fast path: Hyprland workspace dispatch -> niri actions.
    # Also make SHELL_QML_PATH dynamic: it hardcodes Shell.qml, but the running
    # shell may be ShellHybrid.qml (A) or ShellFull.qml (B). Detect whichever is
    # live so the in-shell pills/buttons reach the right Quickshell instance.
    substituteInPlace "$base/scripts/qs_manager.sh" \
      --replace-fail 'hyprctl --batch "dispatch $CMD" >/dev/null 2>&1' '{ if [ "$TARGET" = "move" ]; then niri msg action move-window-to-workspace "$ACTION"; else niri msg action focus-workspace "$ACTION"; fi; } >/dev/null 2>&1' \
      --replace-fail 'SHELL_QML_PATH="$SCRIPTS_DIR/Shell.qml"' 'SHELL_QML_PATH=$(pgrep -af quickshell 2>/dev/null | grep -oE "$SCRIPTS_DIR/Shell[A-Za-z]*\.qml" | head -n1); [ -n "$SHELL_QML_PATH" ] || SHELL_QML_PATH="$SCRIPTS_DIR/Shell.qml"'

    # Top-bar keyboard-layout toggle: hyprctl switchxkblayout -> niri switch-layout.
    # Also move the bar to the bottom edge (anchor + margin gap flip).
    substituteInPlace "$qsdir/TopBar.qml" \
      --replace-fail '["hyprctl", "switchxkblayout", "main", "next"]' '["niri", "msg", "action", "switch-layout", "next"]' \
      --replace-fail 'top: true' 'bottom: true' \
      --replace-fail 'margins { top: s(8); bottom: 0; left: s(4); right: s(4) }' 'margins { top: 0; bottom: s(4); left: s(4); right: s(4) }' \
      --replace-fail 'exclusiveZone: barHeight' 'exclusiveZone: barHeight + s(6)'

    # ── Competition pieces (the Reddit look): Stars + rotating-earth Moon ──────
    # Place beside the framework so Caching/MatugenColors/Scaler resolve as
    # same-dir types. PascalCase the filename so it's a valid QML type (Moon).
    cp ${srcComp}/Stars.qml "$qsdir/Stars.qml"
    cp ${srcComp}/moon.qml  "$qsdir/Moon.qml"
    cp ${srcComp}/earth.jpg "$qsdir/earth.jpg"
    cp ${srcComp}/moon.jpg  "$qsdir/moon.jpg"

    # Port Moon.qml: its Caching paths (qsDir/serpantinumDir) aren't defined in the
    # daily Caching, so inline our store tree; bundle the earth/moon images (drop
    # the hardcoded /home/ilyamiro paths); niri keyboard toggle.
    substituteInPlace "$qsdir/Moon.qml" \
      --replace-fail 'paths.qsDir' "\"$qsdir\"" \
      --replace-fail 'paths.serpantinumDir' "\"$base\"" \
      --replace-fail 'file:///home/ilyamiro/Downloads/earth.jpg' 'earth.jpg' \
      --replace-fail 'file:///home/ilyamiro/Downloads/moon.jpg' 'moon.jpg' \
      --replace-fail 'file:///home/ilyamiro/Downloads/hyprland.png' 'moon.jpg' \
      --replace-fail '["hyprctl", "switchxkblayout", "main", "next"]' '["niri", "msg", "action", "switch-layout", "next"]'

    # Variant A entry point: daily shell + Stars + Moon backgrounds.
    cp ${./ShellHybrid.qml} "$qsdir/ShellHybrid.qml"

    # Variant B: the competition 3D app launcher (a plain Item). Place beside the
    # framework (PascalCase: AppLauncher); patch import "../" -> "." (framework is
    # now same-dir); repoint its Caching paths; make Escape close OUR overlay via
    # IPC (the upstream close path targets a qs_manager/Shell.qml that B doesn't run).
    cp ${srcComp}/applauncher.qml "$qsdir/AppLauncher.qml"
    substituteInPlace "$qsdir/AppLauncher.qml" \
      --replace-fail 'import "../"' 'import "."' \
      --replace-fail '["bash", paths.serpantinumDir + "/scripts/qs_manager.sh", "close"]' "[\"qs\", \"ipc\", \"-p\", \"$qsdir/ShellFull.qml\", \"call\", \"applauncher\", \"close\"]" \
      --replace-fail 'paths.qsDir' "\"$qsdir\"" \
      --replace-quiet 'paths.serpantinumDir' "\"$base\""
    cp ${./ShellFull.qml} "$qsdir/ShellFull.qml"

    # Make helper scripts executable; fix #!/usr/bin/env shebangs to store paths.
    find "$base/scripts" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +
    patchShebangs "$base/scripts" || true

    # Shell wrappers. Shared Qt6 env (QtMultimedia/Qt5Compat fix, same as persona)
    # + the full runtime PATH closure. Pass -d to daemonize.
    #   hypr-comp    -> daily Shell.qml (bar + popups, no earth)
    #   hypr-comp-a  -> Variant A: daily shell + Stars + Moon (earth) backgrounds
    #   hypr-comp-b  -> Variant B: competition (Stars + Moon + Main + 3D launcher)
    qtflags=(
      --unset QML2_IMPORT_PATH
      --unset QML_IMPORT_PATH
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : "${qt6.qtmultimedia}/lib/qt-6/qml:${qt6.qt5compat}/lib/qt-6/qml"
      --prefix QT_PLUGIN_PATH : "${qt6.qtmultimedia}/lib/qt-6/plugins:${qt6.qt5compat}/lib/qt-6/plugins"
      --prefix PATH : "${lib.makeBinPath runtimeDeps}"
    )
    makeWrapper ${lib.getExe' quickshell "qs"} "$out/bin/hypr-comp" \
      --add-flags "-p $qsdir/Shell.qml" "''${qtflags[@]}"
    makeWrapper ${lib.getExe' quickshell "qs"} "$out/bin/hypr-comp-a" \
      --add-flags "-p $qsdir/ShellHybrid.qml" "''${qtflags[@]}"
    makeWrapper ${lib.getExe' quickshell "qs"} "$out/bin/hypr-comp-b" \
      --add-flags "-p $qsdir/ShellFull.qml" "''${qtflags[@]}"

    # hypr-comp-rotate (Mod+Shift+D): rotate DMS -> A -> B -> DMS (mutually
    # exclusive with DMS and Persona).
    install -Dm755 ${./hypr-comp-rotate.sh} "$out/bin/hypr-comp-rotate"
    substituteInPlace "$out/bin/hypr-comp-rotate" \
      --replace-fail '@pkill@' '${lib.getExe' procps "pkill"}' \
      --replace-fail '@systemctl@' '${lib.getExe' systemd "systemctl"}' \
      --replace-fail '@systemdrun@' '${lib.getExe' systemd "systemd-run"}' \
      --replace-fail '@hyprcompa@' "$out/bin/hypr-comp-a" \
      --replace-fail '@hyprcompb@' "$out/bin/hypr-comp-b"

    # hypr-comp-launcher (Mod+P): open the active shell's launcher.
    install -Dm755 ${./hypr-comp-launcher.sh} "$out/bin/hypr-comp-launcher"
    substituteInPlace "$out/bin/hypr-comp-launcher" \
      --replace-fail '@pgrep@' '${lib.getExe' procps "pgrep"}' \
      --replace-fail '@qs@' '${lib.getExe' quickshell "qs"}' \
      --replace-fail '@configa@' "$qsdir/ShellHybrid.qml" \
      --replace-fail '@configb@' "$qsdir/ShellFull.qml"

    runHook postInstall
  '';

  meta = {
    description = "ilyamiro hypr-comp Quickshell desktop shell (vendored; porting to niri)";
    homepage = "https://github.com/ilyamiro/nixos-configuration";
    # Upstream is personal dotfiles with no LICENSE file; vendored for personal use.
    platforms = lib.platforms.linux;
    mainProgram = "hypr-comp";
  };
})
