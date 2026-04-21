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
      hiddenTrayIds = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          StatusNotifierItem IDs to hide from the DMS system tray. Written to
          session.json's hiddenTrayIds. Find IDs by hiding an icon via the DMS UI
          then reading ~/.local/state/DankMaterialShell/session.json. Electron/Chromium
          apps often embed window titles or notification counts in their IDs, which
          makes exact-match hides brittle.
        '';
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
    };
  };
}
