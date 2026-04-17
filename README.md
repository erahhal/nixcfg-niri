# nixcfg-niri

Niri + DankMaterialShell desktop configuration modules for NixOS and home-manager.

## Why `niri-flake` instead of nixpkgs' niri?

`nixpkgs` provides the niri *package* (`pkgs.niri`) and the system-level NixOS module (`programs.niri.enable`), but it does **not** provide a home-manager module for declaratively generating `config.kdl`.

`niri-flake` is used specifically for its home-manager module (`homeModules.niri`), which powers the structured `programs.niri.settings = { ... }` option in [`modules/desktop/niri/home.nix`](modules/desktop/niri/home.nix). That option serializes Nix-native binds, window-rules, layout, and input config into valid KDL and runs `niri validate` at build time — catching schema mismatches before a rebuild lands.

Without `niri-flake`, the ~375 lines of structured config in `home.nix` would have to be written as a raw KDL string (e.g. via `xdg.configFile."niri/config.kdl".text`), losing Nix-native composition and build-time validation.

Note: the niri *binary* is still resolved from `pkgs.niri` (nixpkgs) — we don't pull niri itself from the flake, only its home-manager module.
