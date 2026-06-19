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
    };
  };
}
