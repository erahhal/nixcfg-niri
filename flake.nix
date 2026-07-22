{
  description = "Niri + DMS-Shell desktop configuration modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    dms-shell = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri-flake = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    greyline = {
      url = "github:cothinking-dev/greyline";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, dms-shell, niri-flake, greyline, ... }: {
    # Single import for NixOS modules — includes upstream dms-shell + our config
    nixosModules.default = { ... }: {
      imports = [
        ./modules/options.nix
        dms-shell.nixosModules.default
        dms-shell.nixosModules.greeter
        (import ./modules/desktop/niri)
        (import ./modules/desktop/dms-shell)
      ];

      # Thread the greyline flake to downstream modules so
      # modules/desktop/niri/default.nix can import its home-manager module
      # (services.greyline) into the per-user home config.
      _module.args.greyline = greyline;
    };

    # Home modules for per-user import (NOT sharedModules — osConfig isn't available there)
    homeModules = {
      dms-shell = dms-shell.homeModules.default;
      niri = niri-flake.homeModules.niri;
      startup-apps = import ./modules/desktop/startup-apps;
    };
  };
}
