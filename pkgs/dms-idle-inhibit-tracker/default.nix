{ lib
, coreutils
, dbus
, makeWrapper
, niri
, python3
, stdenvNoCC
, systemd
}:

stdenvNoCC.mkDerivation {
  pname = "dms-idle-inhibit-tracker";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];

  # dbus-monitor (dbus), busctl (systemd), stdbuf (coreutils) and niri msg are
  # all resolved on PATH at runtime, and neither the user manager's PATH nor
  # the DMS shell's is guaranteed to hold them.
  installPhase = ''
    runHook preInstall

    install -Dm755 $src/tracker.py $out/bin/dms-idle-inhibit-tracker
    install -Dm755 $src/report.py $out/bin/dms-idle-inhibitors

    for prog in dms-idle-inhibit-tracker dms-idle-inhibitors; do
      wrapProgram $out/bin/$prog \
        --prefix PATH : ${lib.makeBinPath [ coreutils dbus niri systemd ]} \
        --set PYTHONUNBUFFERED 1
    done

    runHook postInstall
  '';

  meta = {
    description = "Report what is holding a niri session's screen awake";
    mainProgram = "dms-idle-inhibitors";
    platforms = lib.platforms.linux;
  };
}
