{ stdenv }:

stdenv.mkDerivation {
  pname = "dms-theme-toggle";
  version = "1.0.0";
  src = ./plugin;
  installPhase = ''
    mkdir -p $out
    cp -r $src/* $out/
  '';
}
