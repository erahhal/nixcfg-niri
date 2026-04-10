{
  description = "Niri + DMS-Shell desktop configuration modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    dms-shell = {
      url = "github:AvengeMedia/DankMaterialShell/v1.4.4";
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
        dms-shell.nixosModules.default
        dms-shell.nixosModules.greeter
        (import ./modules/desktop/niri)
        (import ./modules/desktop/dms-shell)
        (import ./modules/desktop/startup-apps)
      ];
      # Inject niri-flake + dms-shell home modules into all home-manager users
      home-manager.sharedModules = [
        dms-shell.homeModules.default
        niri-flake.homeModules.niri
      ];
    };

    # Kept for standalone home-manager usage (without NixOS)
    homeModules.default = {
      imports = [
        dms-shell.homeModules.default
        niri-flake.homeModules.niri
      ];
    };
  };
}
