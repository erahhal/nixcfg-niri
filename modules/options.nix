{ lib, ... }:
{
  options.nixcfg-niri = {
    desktop = {
      wallpaper = lib.mkOption {
        type = lib.types.path;
        default = ../wallpapers/double-arch.jpg;
        description = "Path to the wallpaper file installed to ~/Wallpaper and used by DMS.";
      };
      weather = {
        location = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "City/region display string for DMS weather widget.";
        };
        coordinates = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Latitude, longitude string for DMS weather widget.";
        };
        useFahrenheit = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Use Fahrenheit instead of Celsius in DMS weather widget.";
        };
      };
      killOnExit = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Process names to pkill before session exit/reboot/poweroff.";
      };
      cycleColumnsOnRepeatedWorkspaceFocus = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "When pressing Mod+<N> while already on workspace N, cycle through columns instead of doing nothing.";
      };
      startupAppsForceIntelGpu = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Force the startup-apps systemd service to use the Intel iGPU (DRI_PRIME=0, LIBVA_DRIVER_NAME=iHD, etc.). Intended for hybrid Intel+NVIDIA laptops where screen sharing needs Intel.";
      };
      startupWorkspace = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Named workspace to focus when the session starts, via a
          spawn-at-startup `niri msg action focus-workspace <name>`. Use one of
          the ten workspace names this module declares (one .. ten).

          Note this fires early, right after the compositor comes up. Windows
          that open later can still pull focus away -- see the at-startup
          window rule in modules/desktop/niri/home.nix, which stops startup
          apps from doing exactly that.

          null leaves niri on its default (first) workspace.
        '';
      };
      workspaceOutput = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Output that the ten named workspaces are pinned to, via niri's
          `open-on-output`. Accepts a connector name ("eDP-1") or a
          make/model/serial string.

          Useful on a laptop that docks to varying monitors: pin the named
          workspaces to the built-in panel so they keep their identity no
          matter what else is plugged in. null lets niri place each workspace
          on whatever output is active.
        '';
      };
      blankAtStartupSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = ''
          Power the monitors off this many seconds into a new session, if
          nobody has touched the machine by then. null (default) leaves the
          screen lit until the shell's normal monitor timeout — which on a
          session that comes up locked is several minutes of a lit panel in
          an empty room.

          For autologin hosts that come up locked and spend most of their
          life with nobody in front of them. Any input powers the monitors
          back on; niri does that itself.

          A one-shot, not a second idle policy. swayidle watches for the
          first idle period of the session and fires `power-off-monitors`;
          the `timeout` wrapped around it expires two seconds later, so a
          repeat would need another full countdown that no longer fits. From
          then on the shell's own timeout is the only thing that blanks the
          screen.

          Idle rather than a plain sleep, for two reasons. A boot somebody is
          sitting through should not go dark in their face — input inside the
          window keeps the screen on. And the window outlasts the modesets a
          session start does anyway (output config, kanshi), each of which
          would power a monitor blanked at t=0 straight back on.
        '';
      };
      terminal = lib.mkOption {
        type = lib.types.str;
        default = "foot";
        description = "Terminal command bound to Mod+Return.";
      };
      themeToggleCommand = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Command bound to Mod+Shift+T to toggle dark/light theme. null = no binding (DMS override removed).";
      };
      lidCloseAction = lib.mkOption {
        type = lib.types.enum [
          "compositor" "ignore" "lock" "suspend" "hibernate" "hybrid-sleep"
          "suspend-then-hibernate" "poweroff"
        ];
        default = "compositor";
        description = ''
          Who handles lid close, and what they do. Exactly one handler is ever
          wired up:

          - "compositor" (default): logind's HandleLidSwitch is set to "ignore"
            and niri's switch-events.lid-close spawns the dms-suspend script
            (lock, then plain `systemctl suspend`).
          - anything else: the value is passed straight to logind's
            HandleLidSwitch, and niri's lid-close binding is left unset.

          Do not try to get both: logind freezes user.slice within about a
          second of the lid event, before dms-suspend reaches its `systemctl
          suspend`. The frozen request survives the whole sleep and fires
          milliseconds after the next resume, so opening the lid shows the lock
          screen and then immediately re-suspends the machine.

          Locking is preserved without the compositor handler — hypridle's
          before_sleep_cmd (dmsLockProgram = "hyprlock") or DMS's
          lockBeforeSuspend/loginctlLockIntegration (dmsLockProgram = "dms")
          both lock on the way into sleep regardless of who triggered it.

          "suspend-then-hibernate" additionally needs systemd.sleep settings
          (HibernateDelaySec, and usually HibernateOnACPower) configured on the
          host; this option only selects the lid action.
        '';
      };
      easyeffects = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Enable EasyEffects: the systemd autostart service, the DMS shell
            EasyEffects plugin, and the preset bundles. Set to false to skip
            installing the daemon and DMS integration entirely.

            Disable on hosts where EasyEffects' virtual source intercepts
            Bluetooth headset recording streams and breaks WirePlumber's
            A2DP->HSP autoswitch.
          '';
        };
        generic = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install generic EasyEffects EQ presets (Digitalone1 + JackHack96).";
        };
        headphoneProfiles = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Install headphone-specific EasyEffects presets (Bundy01: Bose, Sony, Music, Video).";
        };
        laptopSpeakers = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Install laptop-speaker EasyEffects presets (Radutek Z13/Surface/ROG + ThinkPadUnsuck).";
        };
        dolbyAtmos = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Install the generic Dolby Atmos impulse response (Convolver effect).";
        };
        thinkpadDolby = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Install ThinkPad-specific Dolby impulse responses (P15 + T14 profiles).";
        };
      };
      persona = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Install Persona-Quickshell (a Persona 3 Reload-styled Quickshell
            shell) for on-demand use alongside DankMaterialShell. Adds the
            `persona` command (run the full shell in the foreground) and two
            niri keybinds: persona.toggleKey switches between DMS and Persona
            (only one shell runs at a time), and persona.launcherKey opens
            Persona's launcher when Persona is running or the DMS launcher
            otherwise.

            DankMaterialShell remains the session shell until you switch;
            nothing is autostarted. Note: Persona is Hyprland-oriented and falls
            back to a generic Wayland toplevel list under niri (no live
            workspace integration).
          '';
        };
        toggleKey = lib.mkOption {
          type = lib.types.str;
          default = "Mod+D";
          description = ''
            Niri keybind that switches shells: stops the dms service and starts
            Persona (daemonized) when Persona is not running, or kills Persona
            and restarts dms when it is. Requires persona.enable.
          '';
        };
        launcherKey = lib.mkOption {
          type = lib.types.str;
          default = "Mod+P";
          description = ''
            Niri keybind for the app launcher. Toggles Persona's launcher when
            the Persona shell is running, otherwise the DankMaterialShell
            spotlight launcher. Requires persona.enable.

            Defaults to Mod+P, which DankMaterialShell also binds with mkForce;
            the persona module overrides that binding (lib.mkOverride) while
            enabled.
          '';
        };
      };
      hyprComp = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Install the ilyamiro "hypr-comp" Quickshell shell (vendored from the
            author's nixos-configuration), ported toward niri, as a third
            on-demand session shell. Adds the `hypr-comp` command (run the full
            shell in the foreground for testing). DankMaterialShell remains the
            session shell; nothing is autostarted.

            This is a full Hyprland-oriented DE; several subsystems are degraded
            or disabled under niri (monitor editor, keybind/submap editor,
            workspace model). See pkgs/hypr-comp-shell.
          '';
        };
        toggleKey = lib.mkOption {
          type = lib.types.str;
          default = "Mod+Shift+D";
          description = ''
            Niri keybind that switches shells to/from hypr-comp: stops the dms
            service and starts hypr-comp (daemonized) when it is not running, or
            kills hypr-comp and restarts dms when it is. Requires hyprComp.enable.
            (Wired in a later stage, once the shell is confirmed to launch.)
          '';
        };
      };

      ddcInputToggle = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Bind a key that cycles an external monitor through its inputs over
            DDC/CI (VCP feature 0x60), for machines sharing one monitor with
            another box. Requires the monitor to speak DDC/CI and the i2c-dev
            module to be loaded with the session user able to reach /dev/i2c-*
            (on NixOS: hardware.i2c.enable, or ddcutil's udev rules).

            The monitor and its input codes are host data -- set
            ddcInputToggle.monitor and ddcInputToggle.inputs.
          '';
        };
        key = lib.mkOption {
          type = lib.types.str;
          default = "Mod+G";
          description = ''
            Niri keybind that advances to the next configured input. Bound with
            mkForce, so picking a key another module already claims is an
            evaluation error rather than a silent no-op.
          '';
        };
        title = lib.mkOption {
          type = lib.types.str;
          default = "Switch monitor input";
          description = "Hotkey-overlay title for the bind.";
        };
        monitor = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            Pattern identifying the monitor in `ddcutil detect` output -- a
            model name is usually enough. The script resolves it to an I2C bus
            number and caches that, re-detecting (with an i2c-dev reload) when
            the cached bus stops answering.
          '';
        };
        inputs = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule {
            options = {
              code = lib.mkOption {
                type = lib.types.str;
                description = "VCP feature 0x60 value for this input, e.g. \"0x0f\" (DisplayPort-1) or \"0x11\" (HDMI-1).";
              };
              label = lib.mkOption {
                type = lib.types.str;
                description = "Human-readable name shown in the notification after switching.";
              };
            };
          });
          default = [];
          description = ''
            Inputs to cycle through, in order. Each press reads the monitor's
            current input and sets the next one in this list, wrapping at the
            end. If the monitor reports an input that isn't listed, the first
            entry is selected.
          '';
        };
      };

      focusedBooster = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Run niri-focused-booster (github:1Naim/niri-focused-booster) as a
            user service: it follows niri's focused window over IPC and raises
            that window's dmem cgroup reservation, so the app you're looking at
            keeps its VRAM under pressure.

            Only useful alongside a kernel with the dmem cgroup controller and
            something that activates it across the hierarchy -- this option
            just runs the niri half. Use afterUnits/wantsUnits to order it
            behind whatever provides that.
          '';
        };
        afterUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Extra user units to order the booster after (e.g. the service that activates the dmem controller).";
        };
        wantsUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Extra user units the booster pulls in. Usually the same units listed in afterUnits.";
        };
      };

      greyline = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Install greyline (github:cothinking-dev/greyline), a live world-time
            desktop wallpaper — a modern recreation of the classic ThinkPad
            "World Time" Active Desktop. Renders a world map with clocks and a
            day/night terminator to a PNG once per minute (systemd user timer),
            then hands it to the wallpaper backend.

            With the default swww backend greyline runs its own swww daemon and
            paints the wallpaper directly, which works well under niri.
            DankMaterialShell also manages the wallpaper, so on a host where
            greyline should be visible disable the DMS wallpaper (e.g. set
            hostParams.desktop.wallpaper = null) to keep two background layers
            from fighting.
          '';
        };
        backend = lib.mkOption {
          type = lib.types.enum [ "auto" "sway" "swww" "hyprpaper" "x11" "command" ];
          default = "swww";
          description = ''
            Wallpaper backend greyline hands each rendered frame to. "swww" (the
            default) makes greyline own the wallpaper via its own swww daemon.
            "command" uses services.greyline.command with {path}/{output}
            substitution to hand off to an external mechanism instead.
          '';
        };
        fontFamily = lib.mkOption {
          type = lib.types.str;
          default = "Aporetic Sans";
          description = "Font family greyline renders clock/label text with (resolved via fontconfig).";
        };
        interval = lib.mkOption {
          type = lib.types.str;
          default = "*:*:00";
          description = "systemd OnCalendar expression controlling how often greyline re-renders. Default is once per minute.";
        };
        settings = lib.mkOption {
          type = lib.types.attrs;
          default = {};
          description = ''
            Freeform greyline settings written to ~/.config/greyline/config.toml
            (theme, format, twilight, home tz, city list, etc.). Empty uses the
            package's bundled defaults. See the greyline README for the schema.
          '';
        };
      };
    };
  };
}
