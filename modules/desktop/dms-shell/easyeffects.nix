{ pkgs, ...}:

let
  wait-for-tray = (import ../../../lib/wait-for-tray.nix) pkgs;
in
{
  imports = [
    ./easyeffects-presets.nix
  ];

  # Disable EasyEffects input processing to prevent microphone issues
  dconf.settings = {
    "com/github/wwmm/easyeffects" = {
      process-all-inputs = false;
    };
  };

  systemd.user.services."easyeffects" = {
    Unit = {
      Description = "EasyEffects Audio Filter";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "dms.service" ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
    Service = {
      Restart = "on-failure";
      RestartSec = 2;
      ExecStartPre = "${wait-for-tray}";
      # EasyEffects 8 (Qt) keeps --gapplication-service only as a deprecated
      # alias of --service-mode.
      ExecStart = "${pkgs.easyeffects}/bin/easyeffects --service-mode";
      PassEnvironment = [
        "HOME"
        "XDG_DATA_HOME"
        "XDG_CONFIG_HOME"
        "XDG_CACHE_HOME"
        "XDG_RUNTIME_DIR"
        "DISPLAY"
        "WAYLAND_DISPLAY"
      ];
      Environment = [
        "HOME=%h"
      ];
    };
  };
}
