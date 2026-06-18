# Persona-Quickshell, wired for on-demand use (see pkgs/persona-quickshell).
#
# When enabled this installs the persona commands and two niri keybinds. It does
# NOT autostart anything — DankMaterialShell stays the session shell until the
# toggle switches to Persona:
#   toggleKey (Mod+D)   - switch shells: stop DMS + start Persona, or vice versa.
#   launcherKey (Mod+P) - open Persona's launcher if Persona is running, else DMS's.
{ pkgs, lib, osConfig, ... }:
let
  cfg = osConfig.nixcfg-niri.desktop.persona;
  persona-quickshell = pkgs.callPackage ../../../pkgs/persona-quickshell { };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ persona-quickshell ];

    programs.niri.settings.binds = {
      # Switch between DMS and Persona (only one shell runs at a time).
      ${cfg.toggleKey} = {
        hotkey-overlay.title = "Switch DMS <-> Persona shell";
        action.spawn = lib.getExe' persona-quickshell "persona-toggle";
      };

      # Launcher for whichever shell is active. DankMaterialShell binds this key
      # (Mod+P) with lib.mkForce, so override at a higher priority to win.
      ${cfg.launcherKey} = lib.mkOverride 40 {
        hotkey-overlay.title = "App launcher (Persona / DMS)";
        action.spawn = lib.getExe' persona-quickshell "persona-launcher";
      };
    };
  };
}
