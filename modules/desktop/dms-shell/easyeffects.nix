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
      # --service-mode alone does NOT hide the window in EasyEffects 8: it only
      # sets enableServiceMode (keep running after the window closes). The
      # deprecated --gapplication-service also emitted onHideWindow, so
      # swapping it for bare --service-mode made the GUI open at every login.
      # --hide-window sets show_window=false before Main.qml loads.
      # (src/command_line_parser.cpp, process_hide_window / process_events)
      ExecStart = "${pkgs.easyeffects}/bin/easyeffects --service-mode --hide-window";
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
