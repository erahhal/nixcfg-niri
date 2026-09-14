{ config, dms-shell, lib, pkgs, ... }:
let
  userParams = config.hostParams.user;
  cfg = config.nixcfg.desktop.dms;
  easyeffectsEnabled = config.nixcfg-niri.desktop.easyeffects.enable;
  dms-command-runner = pkgs.fetchFromGitHub {
    owner = "devnullvoid";
    repo = "dms-command-runner";
    rev = "f5f676fe49d2cde86054a28ed06f824319cd5193";
    hash = "sha256-oIzhogusDzXJ7KH/Kmu3euuBCiTJ5GAH8ho24MmXARI=";
  };

  dms-easyeffects = pkgs.applyPatches {
    src = pkgs.fetchFromGitHub {
      owner = "jonkristian";
      repo = "dms-easyeffects";
      rev = "f50fdb7a110ddb90b7625bc143884fd773c3d5c7";
      hash = "sha256-q0Xp4RzHd0HgtUZEM4hIES6SDyN8R4lPgQe5aeLMh4c=";
    };
    patches = [
      ./patches/dms-easyeffects-fix-hang.patch
    ];
  };

  dms-network-monitor = pkgs.callPackage ../../../pkgs/dms-network-monitor {};
  dms-theme-toggle = pkgs.callPackage ../../../pkgs/dms-theme-toggle {};

  # Who the greeter runs as, resolved exactly the way dank-greeter's own module
  # resolves it, so the sweep below can never disagree with the tmpfiles rule
  # that creates the directory.
  greeterCacheDir = "/var/lib/dms-greeter";
  greeterUser = config.services.greetd.settings.default_session.user;
  greeterGroup =
    let
      group = config.users.users.${greeterUser}.group;
    in
    if group != "" then group else "greeter";

  # DMS keys each tray item by `id::tooltipTitle`, and that key indexes the
  # user's saved order in ~/.local/state/DankMaterialShell/session.json. But
  # tooltipTitle is mutable per the StatusNotifierItem spec: fcitx5 sets it to
  # the active input method, so switching language changes the key, the saved
  # order no longer matches, and the icon jumps to the end of the tray and back.
  # Slack (notification count) and Element (unread marker) drift the same way.
  # The patch keeps the exact-key match first and falls back to an id-only
  # match before ranking an item into the unsorted tail.
  #
  # mkDmsShell is the flake's sanctioned entry point for building against our
  # own pkgs, so this stays a single dms-shell derivation rather than pulling in
  # a second one. Expect `patch` to fail loudly if upstream rewrites
  # sortByPreferredOrder -- that is the signal to drop this and take theirs.
  dms-shell-patched = (dms-shell.lib.mkDmsShell pkgs).overrideAttrs (old: {
    postInstall = old.postInstall + ''
      chmod -R u+w $out/share/quickshell/dms
      patch -p1 -d $out/share/quickshell/dms < ${./patches/dms-tray-stable-order.patch}
    '';
  });
in
{
  key = "nixcfg/desktop/dms";

  options.nixcfg.desktop.dms.enable = lib.mkEnableOption "DMS shell desktop environment";

  config = lib.mkIf cfg.enable {
    programs.dank-material-shell = {
      enable = true;
      package = dms-shell-patched;
      systemd = {
        enable = true;
        restartIfChanged = true;
      };
      plugins = {
        CommandRunner = {
          enable = true;
          src = dms-command-runner;
        };
        NetworkMonitor = {
          enable = true;
          src = dms-network-monitor;
        };
        EasyEffects = {
          enable = easyeffectsEnabled;
          src = dms-easyeffects;
        };
        ThemeToggle = {
          enable = true;
          src = dms-theme-toggle;
        };
      };
      enableSystemMonitoring = true;
      enableVPN = true;
      enableDynamicTheming = true;
      enableAudioWavelength = true;
      enableCalendarEvents = false; # khal 0.13.0 fails to build (sphinx bug)
    };

    # Was programs.dank-material-shell.greeter until upstream split the greeter
    # into the dank-greeter repo. Same options, new namespace.
    programs.dms-greeter = lib.mkIf (!config.hostParams.desktop.autoLogin) {
      enable = true;
      compositor.name = "niri";
      logs.save = true;
      compositor.customConfig = ''
        hotkey-overlay {
            // disable the "Important Hotkeys" pop-up at startup.
            skip-at-startup
        }

        // Blank the monitor after 60s of inactivity at the greeter and power
        // it back on when input resumes. niri has no built-in idle timer, so
        // drive it with swayidle (the desktop session uses hypridle the same
        // way). Absolute store paths since the greeter runs with a minimal PATH.
        spawn-at-startup "${pkgs.swayidle}/bin/swayidle" "-w" "timeout" "60" "${pkgs.niri}/bin/niri msg action power-off-monitors" "resume" "${pkgs.niri}/bin/niri msg action power-on-monitors"
      '';
    };

    # Enable automatic keyring/wallet unlock via PAM when logging in through DMS greeter
    security.pam.services.dms-greeter = {
      enableGnomeKeyring = true;
      enableKwallet = true;
    };

    services.greetd = {
      enable = true;
      settings = lib.mkIf config.hostParams.desktop.autoLogin {
        default_session = {
          command = "niri-session";
          user = userParams.username;
        };
      };
    };

    systemd.services.greetd = lib.mkIf (!config.hostParams.desktop.autoLogin) {
      # dank-greeter's preStart ends with a `chown <user>: *`, which is
      # neither recursive nor matched by dotted names -- and the greeter
      # unpacks its embedded QML UI into <cache>/.cache/dms-greeter-shell and
      # keeps state under <cache>/.local. Anything under there left owned by
      # another uid (a file the root-run preStart wrote into a subdirectory, a
      # leftover from before the greeter moved out of DankMaterialShell onto
      # the `greeter` user) makes the greeter fail to unpack its UI and exit
      # before it can create a session. Sweep the whole tree so a stale owner
      # heals itself on the next start, instead of needing a hand-typed
      # `chown -R` from a machine that has no login screen.
      preStart = lib.mkAfter ''
        chown -R ${greeterUser}:${greeterGroup} ${greeterCacheDir}
      '';

      # greetd exits 0 when the greeter dies without creating a session, so
      # Restart=on-success fires straight away; five of those inside systemd's
      # default 10s window latch the unit `failed`, and only `systemctl
      # reset-failed greetd` clears it. Back off between restarts and drop the
      # limit, so a failing greeter keeps retrying and recovers by itself once
      # the cause is gone. A permanently broken greeter then loops on tty1
      # rather than dying, which is the better of the two: tty2-6 still have a
      # getty either way.
      serviceConfig.RestartSec = "2s";
      startLimitIntervalSec = 0;
    };
  };
}
