# hypr-comp shell (see pkgs/hypr-comp-shell), wired for on-demand use under niri.
#
# Stage 0: when enabled, install the `hypr-comp` command + the fonts the shell uses.
# Nothing is autostarted and no keybind is bound yet — run `hypr-comp` in a terminal
# (foreground) to bring it up for testing. The Mod+Shift+D shell switch and the
# popup keybinds are added in Stage 3 once the shell is confirmed to launch.
{ pkgs, lib, osConfig, ... }:
let
  cfg = osConfig.nixcfg-niri.desktop.hyprComp;
  hypr-comp-shell = pkgs.callPackage ../../../pkgs/hypr-comp-shell { };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [
      hypr-comp-shell
      # The shell hardcodes these font families (TopBar/popups).
      pkgs.jetbrains-mono
      pkgs.nerd-fonts.iosevka
    ];

    programs.niri.settings.binds = {
      # Rotate the session shell: DMS -> A (daily + earth) -> B (full
      # competition) -> DMS. Mutually exclusive with Persona (Mod+D); only one
      # shell runs at a time.
      ${cfg.toggleKey} = {
        hotkey-overlay.title = "Rotate shell: DMS -> A -> B";
        action.spawn = lib.getExe' hypr-comp-shell "hypr-comp-rotate";
      };

      # Open the active shell's launcher. DMS forces Mod+P and Persona overrides
      # it (mkOverride 40); take it at a higher priority so this 4-way dispatcher
      # wins while hypr-comp is enabled.
      "Mod+P" = lib.mkOverride 30 {
        hotkey-overlay.title = "App launcher (active shell)";
        action.spawn = lib.getExe' hypr-comp-shell "hypr-comp-launcher";
      };
    };
  };
}
