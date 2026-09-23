{ stdenv }:

stdenv.mkDerivation {
  pname = "dms-idle-inhibitors";
  version = "1.0.0";
  src = ./plugin;
  installPhase = ''
    mkdir -p $out
    cp -r $src/* $out/
  '';
}
