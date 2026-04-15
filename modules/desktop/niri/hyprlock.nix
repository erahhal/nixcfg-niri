{ osConfig, lib, pkgs, ... }:
let
  date-cmd = "${pkgs.coreutils}/bin/date";
in
{
  programs.hyprlock = {
    enable = true;
    package = pkgs.hyprlock;

    settings = {
      # Colors handled by Stylix — only structural/layout settings here
      background = lib.mkIf (osConfig.hostParams.desktop.wallpaper != null) {
        monitor = "";
        path = lib.mkDefault (toString osConfig.hostParams.desktop.wallpaper);
        blur_passes = lib.mkDefault 2;
        contrast = lib.mkDefault 1;
        brightness = lib.mkDefault "0.5";
        vibrancy = lib.mkDefault "0.2";
        vibrancy_darkness = lib.mkDefault "0.2";
      };

      general = {
        hide_cursor = true;
      };

      input-field = {
        monitor = "";
        size = lib.mkDefault "250, 60";
        outline_thickness = lib.mkDefault 2;
        dots_size = lib.mkDefault "0.2";
        dots_spacing = lib.mkDefault "0.35";
        dots_center = lib.mkDefault true;
        fade_on_empty = lib.mkDefault false;
        rounding = lib.mkDefault (-1);
        hide_input = lib.mkDefault false;
        position = lib.mkDefault "0, -200";
        halign = lib.mkDefault "center";
        valign = lib.mkDefault "center";
      };

      label = [
        {
          monitor = "";
          text = ''cmd[update:1000] echo "$(${date-cmd} +"%A, %B %d")"'';
          font_size = lib.mkDefault 22;
          position = lib.mkDefault "0, 350";
          halign = lib.mkDefault "center";
          valign = lib.mkDefault "center";
        }
        {
          monitor = "";
          text = ''cmd[update:1000] echo "$(${date-cmd} +"%-I:%M")"'';
          font_size = lib.mkDefault 95;
          position = lib.mkDefault "0, 200";
          halign = lib.mkDefault "center";
          valign = lib.mkDefault "center";
        }
      ];
    };
  };
}
