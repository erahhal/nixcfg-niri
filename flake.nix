{
  description = "Niri + DMS-Shell desktop configuration modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    dms-shell = {
      url = "github:AvengeMedia/DankMaterialShell/v1.4.4";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, dms-shell, ... }: {
    # Single import for NixOS modules — includes upstream dms-shell + our config
    nixosModules.default = { ... }: {
      imports = [
        dms-shell.nixosModules.default
        dms-shell.nixosModules.greeter
        (import ./modules/desktop/niri)
        (import ./modules/desktop/dms-shell)
        (import ./modules/desktop/startup-apps)
      ];
    };

    # Single import for home-manager modules
    homeModules.default = dms-shell.homeModules.default;
  };
}
