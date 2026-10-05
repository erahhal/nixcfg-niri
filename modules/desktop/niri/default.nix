{ config, inputs, lib, pkgs, greyline, niri-flake, ... }:
let
  userParams = config.hostParams.user;

  # Single source of truth for which niri is used. Everything -- the niri-script
  # wrapper, programs.niri.package, KDL validation and portal configPackages --
  # resolves to this one package.
  #
  # niri-unstable tracks niri's main branch. Its source is this repo's own
  # `niri-unstable` flake input (niri-flake's is made to follow it), so
  # `nix flake update` here moves it forward; without that follows, the rev
  # stays at whatever niri-flake last locked. The two alternatives are both
  # worse here:
  #   * niri-flake's default (niri-stable) is pinned to v25.08 inside
  #     niri-flake's own flake.nix. niri has since shipped v25.11 and v26.04,
  #     so it is two releases behind and `nix flake update` here does NOT move
  #     it -- the pin is not in this repo's lock.
  #   * pkgs.niri is nixpkgs' packaging of the latest tagged release; it only
  #     advances when nixpkgs bumps it.
  #
  # Historically niri-script ran pkgs.niri while programs.niri.package was left
  # at niri-flake's v25.08 default, so the session ran one binary while the KDL
  # config was validated by another and a 25.08 closure was built every rebuild
  # and never executed.
  niriPackage = pkgs.niri-unstable;

  niri-script = pkgs.writeShellScriptBin "niri" ''
    export NIRI_SOCKET=$(${pkgs.findutils}/bin/find /run/user/$(id -u) -name "niri.wayland-*.sock" 2>/dev/null | head -1)
     ${niriPackage}/bin/niri "$@"
  '';
  niri-sddm = pkgs.writeShellScriptBin "niri-sddm" ''
    # Brief delay to let SDDM release the device
    sleep 1
    export __GL_SHADER_DISK_CACHE=1
    cache_root=''${XDG_CACHE_HOME:-$HOME/.cache}
    cache_dir="$cache_root/nvidia-shader-cache"
    mkdir -p "$cache_dir"
    export __GL_SHADER_DISK_CACHE_PATH="$cache_dir"
    exec niri --session
  '';
  cfg = config.nixcfg.desktop.niri;
  boosterCfg = config.nixcfg-niri.desktop.focusedBooster;
  niri-focused-booster = pkgs.callPackage ../../../pkgs/niri-focused-booster {};
in
{
  key = "nixcfg/desktop/niri";

  options.nixcfg.desktop.niri.enable = lib.mkEnableOption "Niri wayland compositor";

  config = lib.mkIf cfg.enable {
    ## Not using as services.displayManager.sessionPackages needs to be overridden
    # programs.niri = {
    #   enable = true;
    # };

    nixpkgs.overlays = [
      # nixpkgs removed `libdisplay-info_0_2` (2026-08-04; the attr is now a
      # throwing alias), but niri-flake's make-niri still takes it as a
      # callPackage arg and asserts version == "0.2.0" -- stale even for the
      # niri main rev it pins, whose Cargo.lock uses the libdisplay-info 0.3
      # crate. Resurrect the attr as 0.3 (what nixpkgs' own niri 25.11 links
      # against) with a faked version string to get past the assert. It has
      # to happen at the pkgs level, before niri-flake's overlay: the assert
      # sits in front of the derivation, so a later `.override` on the
      # package forces it with the original throwing arg before the override
      # can replace anything. Drop this once niri-flake moves off 0.2.
      (final: prev: {
        libdisplay-info_0_2 = final.libdisplay-info_0_3 // { version = "0.2.0"; };
      })

      # Provides pkgs.niri-stable / pkgs.niri-unstable, built against our
      # nixpkgs rather than niri-flake's own.
      niri-flake.overlays.niri

      (final: prev: {
        # Alias nixpkgs' niri to the same package. Several helper scripts across
        # this repo and nixcfg call `${pkgs.niri}/bin/niri msg ...` (dms-shell
        # idle handlers, niri-kill-active, exit-niri, mkGamescopeScript). Without
        # this they drag a second, unpatched niri into the system closure and
        # talk IPC to a different build than the one running the session.
        # Aliasing here fixes every call site at once instead of editing each.
        niri = final.niri-unstable;
      })
    ];

    services.displayManager.sessionPackages = [
      (pkgs.runCommand "niri-session" {
        passthru.providedSessions = [ "niri" ];
      } ''
        mkdir -p $out/share/wayland-sessions
        cat > $out/share/wayland-sessions/niri.desktop << EOF
        [Desktop Entry]
        Name=Niri
        Comment=Niri Wayland Compositor
        Exec=${niri-sddm}/bin/niri-sddm
        Type=Application
      '')
    ];

    services.gnome.gnome-keyring.enable = lib.mkDefault true;

    security = {
      polkit.enable = true;
      pam.services.swaylock = { };
    };

    programs = {
      niri = {
        enable = true;
        # See niriPackage above. Setting this makes niri-flake validate the KDL
        # config with, and point xdg.portal.configPackages at, the same binary
        # the session actually runs.
        package = niriPackage;
      };
      dconf.enable = true;
      xwayland.enable = true;
    };

    # Window manager only sessions (unlike DEs) don't handle XDG
    # autostart files, so force them to run the service
    services.xserver.desktopManager.runXdgAutostartIfNone = lib.mkDefault true;

    environment.systemPackages = with pkgs; [
      niri-script
      evremap
      libinput
      xwayland-satellite  # This may or may not be available depending on your channel
      xdg-desktop-portal
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
      # xdg-desktop-portal-wlr
      nautilus  # Required for GNOME portal
      pipewire
      wireplumber
      gnome-keyring
      bibata-cursors  # referenced by programs.niri.settings.cursor.theme
      kanshi  # referenced by Mod+Y binding + spawn-at-startup for monitor autoconfig
    ] ++ lib.optional boosterCfg.enable niri-focused-booster;

    # Follows niri's focused window over IPC and raises its dmem cgroup
    # reservation. Inert unless something else activates the dmem controller --
    # order behind that provider with focusedBooster.afterUnits/wantsUnits.
    systemd.user.services.niri-focused-booster = lib.mkIf boosterCfg.enable {
      description = "Boost dmem.low for the niri-focused window";
      after = [ "graphical-session.target" ] ++ boosterCfg.afterUnits;
      wants = boosterCfg.wantsUnits;
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = lib.getExe niri-focused-booster;
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    xdg.portal = {
      enable = true;
      configPackages = [ config.programs.niri.package ];
      config = {
        #common.default = "*";
        common = {
          default = [ "gtk"];
          "org.freedesktop.impl.portal.FileChooser" = "gtk";
          "org.freedesktop.impl.portal.Settings" = "gtk;gnome;";
          "org.freedesktop.impl.portal.ScreenCast" = "gnome";
          "org.freedesktop.impl.portal.RemoteDesktop" = "gnome";
          "org.freedesktop.impl.portal.InputCapture" = "gnome";
          # "org.freedesktop.impl.portal.ScreenCast" = "wlr";
          # "org.freedesktop.impl.portal.RemoteDesktop" = "wlr";
        };
      };
      # xdgOpenUsePortal = true;
      # configPackages = [config.programs.niri.package];
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-gnome
        xdg-desktop-portal
        gnome-keyring
        # xdg-desktop-portal-wlr
      ];
    };

    # Lid switch. Default ("compositor") ignores it here so the wm handles it
    # via switch-events.lid-close (see dms-shell/home.nix); any other value
    # hands the lid to logind and drops that binding. Never both -- see
    # nixcfg-niri.desktop.lidCloseAction for why the two race.
    services.logind.settings.Login.HandleLidSwitch =
      let action = config.nixcfg-niri.desktop.lidCloseAction;
      in if action == "compositor" then "ignore" else action;

    ## See: https://yalter.github.io/niri/Nvidia.html
    environment.etc."nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json" = {
      text = builtins.toJSON {
        rules = [{
          pattern = {
            feature = "procname";
            matches = "niri";
          };
          profile = "Limit Free Buffer Pool On Wayland Compositors";
        }];
        profiles = [{
          name = "Limit Free Buffer Pool On Wayland Compositors";
          settings = [{
            key = "GLVidHeapReuseRatio";
            value = 0;
          }];
        }];
      };
    };

    home-manager.users.${userParams.username} = { pkgs, ... }: {
      imports = [
        ./home.nix
        # Upstream greyline home-manager module (services.greyline), threaded
        # from flake.nix via _module.args. Our option mapping lives in
        # ../greyline/home.nix (imported through ./home.nix).
        greyline.homeManagerModules.default
      ];

      ## These need to be installed as well as the ones at the system level
      ## because xdg-desktop-portal is going to look in
      ## /etc/profiles/per-user/<username>/share/xdg-desktop-portal/portals
      ## first, which will exist because hyprland.portal is there as well.
      ## Installing here adds these portals there as well.
      home.packages = with pkgs; [
        xdg-desktop-portal-gnome
        xdg-desktop-portal-gtk
        # xdg-desktop-portal-wlr
        xdg-desktop-portal
        gnome-keyring
      ];
    };
  };
}
