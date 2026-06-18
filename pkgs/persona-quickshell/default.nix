# Persona-Quickshell — a Persona 3 Reload-styled Quickshell desktop shell.
# https://github.com/Yujonpradhananga/Persona-Quickshell
#
# Packaged for on-demand use alongside DankMaterialShell (DMS). Installs the QML
# config tree into the store and exposes:
#   persona           - run the full shell in the foreground (qs -p <config>);
#                       handy for debugging. Does NOT touch DMS.
#   persona-toggle    - Mod+D shell switch: only one shell runs at a time.
#                       Persona down -> stop the dms service, start Persona.
#                       Persona up   -> kill Persona, restart the dms service.
#   persona-launcher  - Mod+P dispatcher: Persona's launcher when Persona runs,
#                       otherwise the DMS spotlight launcher.
#
# Nothing is autostarted — DMS remains the session shell until Mod+D switches.
# The `-p <config>` selector identifies Persona's quickshell instance (DMS runs
# its own), so kills and IPC calls target Persona explicitly.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  quickshell,
  qt6,
  procps,
  systemd,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "persona-quickshell";
  version = "0-unstable-2026-06-17";

  src = fetchFromGitHub {
    owner = "Yujonpradhananga";
    repo = "Persona-Quickshell";
    rev = "5eff42a06b2302b9395f50b73f1a697f368125d1";
    # Large source (~126 MB) — bundled videos/PNG sequences and image assets.
    hash = "sha256-bfl327+2/uWbvoBgBZys2vwPc2kmreftNJYk4WSZu2w=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # CavaVisualizer needs the external Qt6-Cava-plugin (a native QML plugin).
  # Swap it for a no-op Item exposing the same (empty) public surface so the
  # `CavaVisualizer { anchors {...}; height: 555 }` use-site in WallpaperEngine.qml
  # still resolves — without pulling in the plugin.
  postPatch = ''
    cp ${./CavaVisualizer-stub.qml} Widgets/CavaVisualizer.qml
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    config="$out/share/persona-quickshell"
    mkdir -p "$config"
    cp -r . "$config/"

    # persona: run the full shell in the foreground.
    # Persona's video backgrounds import QtMultimedia, which quickshell's Qt6
    # build does not bundle. Supply the matching Qt6 QtMultimedia QML module +
    # backend plugin, and drop the session's QML2_IMPORT_PATH / QML_IMPORT_PATH:
    # those leak a Qt5 QtMultimedia plugin that cannot load into this Qt6 process
    # (the "uses incompatible Qt library (5.15.0)" error). quickshell finds its
    # own modules via NIXPKGS_QT6_QML_IMPORT_PATH, so unsetting the Qt5 vars is safe.
    makeWrapper ${lib.getExe' quickshell "qs"} "$out/bin/persona" \
      --add-flags "-p $config" \
      --unset QML2_IMPORT_PATH \
      --unset QML_IMPORT_PATH \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : "${qt6.qtmultimedia}/lib/qt-6/qml" \
      --prefix QT_PLUGIN_PATH : "${qt6.qtmultimedia}/lib/qt-6/plugins"

    # persona-toggle (Mod+D) and persona-launcher (Mod+P): install the templates
    # and substitute absolute tool paths + the config path baked above.
    install -Dm755 ${./persona-toggle.sh} "$out/bin/persona-toggle"
    install -Dm755 ${./persona-launcher.sh} "$out/bin/persona-launcher"

    substituteInPlace "$out/bin/persona-toggle" \
      --replace-fail '@pgrep@' '${lib.getExe' procps "pgrep"}' \
      --replace-fail '@qs@' '${lib.getExe' quickshell "qs"}' \
      --replace-fail '@systemctl@' '${lib.getExe' systemd "systemctl"}' \
      --replace-fail '@persona@' "$out/bin/persona" \
      --replace-fail '@config@' "$config"

    substituteInPlace "$out/bin/persona-launcher" \
      --replace-fail '@pgrep@' '${lib.getExe' procps "pgrep"}' \
      --replace-fail '@qs@' '${lib.getExe' quickshell "qs"}' \
      --replace-fail '@config@' "$config"

    runHook postInstall
  '';

  meta = {
    description = "Persona 3 Reload-styled Quickshell desktop shell";
    homepage = "https://github.com/Yujonpradhananga/Persona-Quickshell";
    # README declares MIT; the repository has no LICENSE file.
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "persona";
  };
})
