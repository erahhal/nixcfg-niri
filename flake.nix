{
  description = "Niri + DMS-Shell desktop configuration modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    dms-shell = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The greeter used to ship inside DankMaterialShell as
    # `nixosModules.greeter` / `programs.dank-material-shell.greeter`. Upstream
    # split it out into its own repo; the DMS output is now an empty module that
    # only warns. Options carried over one-to-one under `programs.dms-greeter`.
    dank-greeter = {
      url = "github:AvengeMedia/dank-greeter";
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

  outputs = { self, nixpkgs, dms-shell, dank-greeter, niri-flake, greyline, ... }: {
    # Single import for NixOS modules — includes upstream dms-shell + our config
    nixosModules.default = { ... }: {
      imports = [
        ./modules/options.nix
        dms-shell.nixosModules.default
        dank-greeter.nixosModules.default
        (import ./modules/desktop/niri)
        (import ./modules/desktop/dms-shell)
      ];

      # Thread the greyline flake to downstream modules so
      # modules/desktop/niri/default.nix can import its home-manager module
      # (services.greyline) into the per-user home config.
      _module.args.greyline = greyline;

      # Thread niri-flake through as well so modules/desktop/niri/default.nix
      # can apply its package overlay and pin the compositor to niri-unstable
      # (upstream main) rather than niri-flake's default niri-stable.
      _module.args.niri-flake = niri-flake;

      # And the dms-shell flake itself, so modules/desktop/dms-shell can rebuild
      # the shell from dms-shell.lib.mkDmsShell with our QML patches applied.
      _module.args.dms-shell = dms-shell;
    };

    # Home modules for per-user import (NOT sharedModules — osConfig isn't available there)
    homeModules = {
      dms-shell = dms-shell.homeModules.default;
      niri = niri-flake.homeModules.niri;
      startup-apps = import ./modules/desktop/startup-apps;
    };
  };
}
