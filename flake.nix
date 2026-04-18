{
  description = "Niri + DMS-Shell desktop configuration modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    dms-shell = {
      url = "github:AvengeMedia/DankMaterialShell/v1.4.4.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri-flake = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, dms-shell, niri-flake, ... }: {
    # Single import for NixOS modules — includes upstream dms-shell + our config
    nixosModules.default = { ... }: {
      imports = [
        ./modules/options.nix
        dms-shell.nixosModules.default
        dms-shell.nixosModules.greeter
        (import ./modules/desktop/niri)
        (import ./modules/desktop/dms-shell)
      ];

    };

    # Home modules for per-user import (NOT sharedModules — osConfig isn't available there)
    homeModules = {
      dms-shell = dms-shell.homeModules.default;
      niri = niri-flake.homeModules.niri;
      startup-apps = import ./modules/desktop/startup-apps;
    };
  };
}
