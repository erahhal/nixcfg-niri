{ osConfig, lib, pkgs, ... }:

# One persistent notification for the whole time the machine runs on battery,
# stepped through UPower's own low / critical / action levels, plus a short
# "external power connected" confirmation when AC returns. The confirmation is
# what makes a plugged-in-but-not-charging cable visible: it never appears.
#
# Gated on the host actually running upower (i.e. having a battery to watch).
# The thresholds quoted in the text come from the same services.upower options
# that fire the critical-power action, so the warnings can never disagree with
# what upower is about to do. DMS's own battery alerts are switched off in
# ../dms-shell/home.nix while this is active so nothing fires twice.
let
  cfg = osConfig.nixcfg-niri.desktop.batteryNotify;
  upower = osConfig.services.upower;
  enabled = cfg.enable && upower.enable;
  battery-notify = pkgs.callPackage ../../../pkgs/battery-notify { };
in
{
  config = lib.mkIf enabled {
    # On PATH so `battery-notify --test` can walk the ladder on demand.
    home.packages = [ battery-notify ];

    systemd.user.services.battery-notify = {
      Unit = {
        Description = "Persistent desktop notification while on battery power";
        PartOf = [ "graphical-session.target" ];
        # The notification daemon may come up after us; the watcher polls
        # for it and re-posts when it appears, so no ordering on dms.service.
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = lib.concatStringsSep " " [
          "${battery-notify}/bin/battery-notify"
          "--action-percent ${toString upower.percentageAction}"
          "--critical-action ${upower.criticalPowerAction}"
        ];
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
