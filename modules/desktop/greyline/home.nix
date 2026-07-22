# greyline live world-time wallpaper (github:cothinking-dev/greyline), wired for
# niri. The upstream home-manager module (services.greyline) is imported by
# modules/desktop/niri/default.nix (it needs the greyline flake, threaded there
# via _module.args); this file maps our nixcfg-niri.desktop.greyline options
# onto it.
#
# Settings are inert while disabled — the upstream module gates all of its
# config (systemd timer/service, swww daemon, config.toml, packages) behind
# services.greyline.enable — so there is no need for a lib.mkIf here.
{ osConfig, ... }:
let
  cfg = osConfig.nixcfg-niri.desktop.greyline;
in
{
  services.greyline = {
    enable = cfg.enable;
    backend = cfg.backend;
    fontFamily = cfg.fontFamily;
    interval = cfg.interval;
    settings = cfg.settings;

    # niri exports graphical-session.target; the module defaults to
    # sway-session.target, which never activates under niri, so the timer (and
    # the swww daemon it pulls in) would never start.
    target = "graphical-session.target";
  };
}
