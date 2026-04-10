{
  description = "Niri + DMS-Shell desktop configuration modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    dms-shell = {
      url = "github:AvengeMedia/DankMaterialShell/v1.4.4";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, ... }: {
    nixosModules = {
      niri = import ./modules/desktop/niri;
      dms = import ./modules/desktop/dms-shell;
      startup-apps = import ./modules/desktop/startup-apps;
    };
  };
}
