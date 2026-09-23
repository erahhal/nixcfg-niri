{ lib, stdenvNoCC, python3, systemd, glib, makeWrapper }:

# Persistent on-battery desktop notification. See battery-notify.py for the
# rationale and the state machine; modules/desktop/battery-notify/home.nix
# runs it as a user service. Standard-library Python driving busctl (JSON
# state reads) and gdbus (signal wake-ups, notifications), so the only
# runtime inputs are systemd and glib.
stdenvNoCC.mkDerivation {
  pname = "battery-notify";
  version = "1";

  src = ./battery-notify.py;
  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper python3 ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/battery-notify
    patchShebangs $out/bin/battery-notify
    wrapProgram $out/bin/battery-notify \
      --prefix PATH : ${lib.makeBinPath [ systemd glib.bin ]}
    runHook postInstall
  '';

  # Smoke test through the wrapper: imports the module and runs argparse, so a
  # syntax error or a bad shebang fails the build without touching D-Bus.
  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/battery-notify --help > /dev/null
  '';

  meta = {
    description = "Keep a persistent desktop notification up while running on battery";
    mainProgram = "battery-notify";
    platforms = lib.platforms.linux;
  };
}
