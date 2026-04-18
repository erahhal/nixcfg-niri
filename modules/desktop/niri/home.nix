{ osConfig, lib, pkgs, ... }:

let
  niri = "${pkgs.niri}/bin/niri";
  jq = "${pkgs.jq}/bin/jq";
  ## @TODO: Move to a service
  dynamic-float-rules = pkgs.callPackage ./dynamic-float-rules.nix {};
  clear-notifications = pkgs.writeShellScript "clear-notifications" ''
    # Close all notifications by iterating through possible IDs
    # freedesktop.org CloseNotification silently ignores non-existent IDs
    for i in $(seq 1 1000); do
      ${pkgs.glib}/bin/gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.CloseNotification "$i" \
        2>/dev/null &
    done
    wait
  '';
  killAppsScript =
    let
      killOne = app: ''
        pkill ${lib.escapeShellArg app} 2>/dev/null || true
        ${pkgs.procps}/bin/pidof ${lib.escapeShellArg app} 2>/dev/null | xargs -r kill 2>/dev/null || true
      '';
    in
      lib.concatStrings (map killOne osConfig.nixcfg-niri.desktop.killOnExit);

  exit-niri = pkgs.writeShellScript "exit-niri" ''
    ${killAppsScript}
    ${niri} msg action quit --skip-confirmation
  '';
  reboot = pkgs.writeShellScript "kill-reboot" ''
    ${killAppsScript}
    systemctl reboot
  '';

  kill-active = pkgs.writeShellScript "niri-kill-active.sh" ''
    if [ "$(${niri} msg -j focused-window | ${jq} -r ".app_id")" = "Steam" ]; then
        ${pkgs.xdotool}/bin/xdotool getactivewindow windowunmap
    elif [ "$(${niri} msg -j focused-window | ${jq} -r ".app_id")" = "foot" ]; then
        echo "Not closing."
    else
        ${niri} msg action close-window
    fi
  '';

  focus-with-overview = pkgs.writeShellScript "focus-with-overview" ''
    # Script to handle focus commands with overview toggling and debouncing
    # Usage: ./niri-focus-with-overview.sh <focus-command>

    TIMESTAMP_FILE="/tmp/niri-focus-timestamp"
    TIMEOUT=0.3  # seconds

    FOCUS_CMD="$1"
    [ -z "$FOCUS_CMD" ] && { echo "Usage: $0 <focus-command>"; exit 1; }
    NO_TOGGLE="$2"

    # Background function to close overview after timeout
    close_after_timeout() {
        local timestamp="$1"
        sleep "$TIMEOUT"

        # Only close if our timestamp is still current
        [ -f "$TIMESTAMP_FILE" ] && [ "$(cat "$TIMESTAMP_FILE" 2>/dev/null)" = "$timestamp" ] && {
            rm -f "$TIMESTAMP_FILE"
            ${niri} msg action close-overview
        }
    }

    # Generate unique timestamp
    TIMESTAMP="$(date +%s%N)"

    # If timestamp file exists, we're already in overview mode
    if [ -f "$TIMESTAMP_FILE" ]; then
        # Just execute focus command and update timestamp
        ${niri} msg action "$FOCUS_CMD"
        echo "$TIMESTAMP" > "$TIMESTAMP_FILE"
    else
        if [ -z "$NO_TOGGLE"]; then
          # First invocation - open overview and execute focus
          ${niri} msg action open-overview
        fi
        ${niri} msg action "$FOCUS_CMD"
        echo "$TIMESTAMP" > "$TIMESTAMP_FILE"
    fi

    # Start timeout with our timestamp
    close_after_timeout "$TIMESTAMP" &
  '';

  switch-preset-column-width-all = pkgs.writeShellScript "switch-preset-column-width-all" ''
    active_workspace=$(${niri} msg -j workspaces | ${jq} -r '.[] | select(.is_active == true) | .id')
    # Get all windows and filter for current workspace
    # Apply width change to each window
    for window_id in $(${niri} msg -j windows | ${jq} -r ".[] | select(.workspace_id == $active_workspace) | .id"); do
        ${niri} msg action switch-preset-window-width --id "$window_id"
    done
  '';

  kill-active-force = pkgs.writeShellScript "niri-kill-active-force.sh" ''
    ${niri} msg -j focused-window | ${jq} '.pid' | ${pkgs.findutils}/bin/xargs -L 1 kill -9
  '';

  workspaceFocusAction = wsName:
    if osConfig.nixcfg-niri.desktop.cycleColumnsOnRepeatedWorkspaceFocus
    then { spawn = [ "${focus-or-cycle-workspace}" wsName ]; }
    else { focus-workspace = wsName; };

  focus-or-cycle-workspace = pkgs.writeShellScript "focus-or-cycle-workspace" ''
    TARGET_WS="$1"
    [ -z "$TARGET_WS" ] && exit 1

    # Get current active workspace name
    CURRENT_WS=$(${niri} msg -j workspaces | ${jq} -r '.[] | select(.is_active == true) | .name')

    if [ "$CURRENT_WS" = "$TARGET_WS" ]; then
      # Already on target workspace - cycle columns with wrap
      BEFORE=$(${niri} msg -j focused-window | ${jq} -r '.id // empty')
      ${niri} msg action focus-column-right
      AFTER=$(${niri} msg -j focused-window | ${jq} -r '.id // empty')
      # If focus didn't change, wrap to first column
      if [ "$BEFORE" = "$AFTER" ]; then
        ${niri} msg action focus-column-first
      fi
    else
      # Different workspace - focus it
      ${niri} msg action focus-workspace "$TARGET_WS"
    fi
  '';

  nag-graphical = pkgs.callPackage ../../../pkgs/nag-graphical {};

  reboot-dialog = pkgs.writeShellScript "reboot-dialog" ''
    ${nag-graphical}/bin/nag-graphical 'Reboot?' '${reboot}'
  '';

  exit-dialog = pkgs.writeShellScript "exit-dialog" ''
    ${nag-graphical}/bin/nag-graphical 'Exit Niri?' '${exit-niri}'
  '';

  adjust-window-sizes = pkgs.writeShellScript "niri-adjust-window-sizes" ''
    last_workspace_id=""
    last_window_count=0
    niri msg --json event-stream | while read -r event; do
      if echo "$event" | ${jq} -e '.WindowOpenedOrChanged or .WindowClosed' > /dev/null 2>&1; then
        sleep 0.05
        focused_workspace_id=$(${niri} msg --json workspaces | ${jq} -r '.[] | select(.is_focused == true) | .id')
        window_count=$(${niri} msg --json windows | $${jq} --argjson ws_id "$focused_workspace_id" '[.[] | select(.workspace_id == $ws_id and .is_floating == false)] | length')
        if [ "$focused_workspace_id" = "$last_workspace_id" ] && [ "$window_count" -eq "$last_window_count" ]; then
            continue
        fi
        echo "Workspace $focused_workspace_id has $window_count windows"
        if [ "$window_count" -eq 1 ]; then
          echo "Setting single window to 100%"
          ${niri} msg action set-column-width "100%"
        elif [ "$window_count" -ge 2 ]; then
          echo "Setting $window_count windows to 50%"
          current_focused_column=$(niri msg --json windows | $${jq} --argjson ws_id "$focused_workspace_id" -r '[.[] | select(.workspace_id == $ws_id and .is_floating == false and .is_focused == true)][0] | .layout.pos_in_scrolling_layout[0]')
          ${niri} msg action focus-column-first
          for i in $(seq 1 "$window_count"); do
            ${niri} msg action set-column-width "50%"
            if [ "$i" -lt "$window_count" ]; then
              ${niri} msg action focus-column-right
            fi
          done
          if [ -n "$current_focused_column" ] && [ "$current_focused_column" -gt 1 ]; then
            ${niri} msg action focus-column-first
            for j in $(seq 2 "$current_focused_column"); do
              ${niri} msg action focus-column-right
            done
          fi
        fi
        last_workspace_id="$focused_workspace_id"
        last_window_count="$window_count"
      fi
    done
  '';
in
{
  imports = [
    ../dms-shell/home.nix
    ./hyprlock.nix
  ];

  home.packages = with pkgs; [
    zenity
    imv
    i3status
    fuzzel
    wl-clipboard
    wdisplays
    wlr-randr
    nag-graphical
  ];

  xdg.configFile."hypr/hyprpaper.conf".text = lib.mkIf (osConfig.hostParams.desktop.wallpaper != null) ''
    splash = false
    preload = ${osConfig.hostParams.desktop.wallpaper}
    wallpaper = ,${osConfig.hostParams.desktop.wallpaper}
  '';

  programs.niri.settings = {
    input = {
      keyboard = {
        xkb.options = "caps:escape";
        repeat-delay = 255;
        repeat-rate = 50;
        numlock = true;
      };
      touchpad = {
        natural-scroll = false;
        click-method = "clickfinger";
        dwt = true;
        dwtp = true;
      };
      mouse = {
        accel-profile = "adaptive";
        accel-speed = -0.8;
      };
      trackpoint = {
        scroll-method = "on-button-down";
      };
    };

    clipboard.disable-primary = true;

    cursor = {
      theme = "Bibata-Modern-Classic";
      size = 16;
    };

    gestures.hot-corners.enable = false;

    layout = {
      always-center-single-column = true;
      gaps = 0;
      center-focused-column = "on-overflow";
      preset-column-widths = [
        { proportion = 1.0; }
        { proportion = 0.5; }
      ];
      preset-window-heights = [
        { proportion = 1.0; }
        { proportion = 0.5; }
      ];
      default-column-width = { proportion = 1.0; };
      struts = { top = 2; bottom = 2; };
      focus-ring = {
        enable = true;
        width = 2;
        active.color = "#00AFFF";
        inactive.color = "#505050";
      };
      border = {
        enable = false;
        width = 2;
        active.color = "#ffc87f";
        inactive.color = "#505050";
        urgent.color = "#9b0000";
      };
      shadow = {
        softness = 30;
        spread = 5;
        offset = { x = 0; y = 5; };
        color = "#0007";
      };
      tab-indicator = {
        place-within-column = true;
        gap = 0;
        width = 24;
        length = { total-proportion = 1.0; };
        position = "top";
        gaps-between-tabs = 0;
        corner-radius = 0;
        active.color = "#4488ff";
        inactive.color = "gray";
        urgent.color = "red";
      };
    };

    spawn-at-startup = [
      { sh = "systemctl --user import-environment && dbus-update-activation-environment --systemd --all && systemctl --user restart dms"; }
      { sh = "systemctl --user restart kanshi &"; }
      { sh = "${dynamic-float-rules}/bin/dynamic-float-rules &"; }
      { sh = "systemctl --user stop xdg-desktop-portal-wlr &"; }
      { sh = "systemctl --user stop xdg-desktop-portal-hyprland &"; }
      { sh = "systemctl --user restart xdg-desktop-portal-gnome &"; }
      { sh = "systemctl --user restart xdg-desktop-portal-gtk &"; }
      { sh = "systemctl --user restart easyeffects &"; }
      { sh = "systemctl --user restart startup-apps"; }
    ];

    hotkey-overlay.skip-at-startup = true;
    prefer-no-csd = true;
    screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

    animations.workspace-switch.kind.spring = {
      stiffness = 10000;
      damping-ratio = 1.0;
      epsilon = 0.0001;
    };

    window-rules = [
      # WezTerm initial configure workaround
      { matches = [{ app-id = "^org\\.wezfurlong\\.wezterm$"; }]; default-column-width = {}; }
      # Firefox picture-in-picture
      { matches = [{ app-id = "firefox$"; title = "^Picture-in-Picture$"; }]; open-floating = true; }
      # Rofi
      { matches = [{ app-id = "Rofi$"; }]; open-floating = true; }
      # EasyEffects
      { matches = [{ app-id = "com.github.wwmm.easyeffects"; }]; open-floating = true; }
      # XEyes
      { matches = [{ app-id = "XEyes$"; }]; open-floating = true; }
      # Blueman
      { matches = [{ app-id = ".blueman-manager-wrapped$"; }]; open-floating = true; }
      # Firefox extensions
      { matches = [{ app-id = "firefox$"; title = "^Extension.*Mozilla Firefox$"; }]; open-floating = true; }
      # Chromium bitwarden extension
      { matches = [{ app-id = ".*-nngceckbapebfimnlniiiahkandclblb-Default$"; }]; open-floating = true; }
      # Empty app-id and title (chromium notifications)
      { matches = [{ app-id = "^$"; title = "^$"; }]; open-floating = true; }
      # Calculator
      {
        matches = [{ app-id = "^org\\.gnome\\.Calculator$"; title = "^Calculator$"; }];
        open-floating = true;
        default-column-width = { fixed = 702; };
        default-window-height = { fixed = 616; };
      }
      # File dialogs
      {
        matches = [{ title = "^(Open File|Save As|Open Folder|Open Workspace.*|Save Workspace.*|Add Folder.*|Save File|Print|Send by Email|Export Image.*)$"; }];
        open-floating = true;
        default-column-width = { fixed = 1000; };
        default-window-height = { fixed = 800; };
      }
      # projectM
      { matches = [{ app-id = "^projectM"; }]; open-fullscreen = true; }
      # Pulse VPN
      {
        matches = [{ app-id = "pulse-vpn-auth$"; }];
        open-floating = true;
        default-column-width = { fixed = 800; };
        default-window-height = { fixed = 600; };
      }
      { matches = [{ app-id = "^steam_app_.*$"; }]; open-fullscreen = true; open-focused = true; }
      { matches = [{ app-id = "^gamescope$"; }]; open-fullscreen = true; open-focused = true; }
    ];

    # recent-windows binds use niri defaults (Alt+Tab, Mod+Tab)

    binds = {
      # Prevent errant middle-click paste
      "MouseMiddle".action.spawn = "true";

      # Show hotkey overlay
      "Mod+Shift+Slash".action.show-hotkey-overlay = {};

      # Programs
      "Mod+Return" = { hotkey-overlay.title = "Open a Terminal: ${osConfig.nixcfg-niri.desktop.terminal}"; action.spawn = osConfig.nixcfg-niri.desktop.terminal; };
      "Mod+Y" = { hotkey-overlay.title = "Run Kanshi"; allow-when-locked = true; action.spawn = [ "systemctl" "--user" "restart" "kanshi" ]; };
      "Super+Alt+S" = { allow-when-locked = true; hotkey-overlay = { hidden = true; }; action.spawn = [ "pkill" "orca" "||" "exec" "orca" ]; };

      # Volume
      "XF86AudioRaiseVolume" = { allow-when-locked = true; action.spawn = [ "${pkgs.wireplumber}/bin/wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.05+" ]; };
      "XF86AudioLowerVolume" = { allow-when-locked = true; action.spawn = [ "${pkgs.wireplumber}/bin/wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.05-" ]; };
      "XF86AudioMute" = { allow-when-locked = true; action.spawn = [ "${pkgs.wireplumber}/bin/wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle" ]; };
      "XF86AudioMicMute" = { allow-when-locked = true; action.spawn = [ "${pkgs.wireplumber}/bin/wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle" ]; };

      "XF86AudioPlay" = { allow-when-locked = true; action.spawn = [ "${pkgs.playerctl}/bin/playerctl" "play-pause" ]; };
      "XF86AudioStop" = { allow-when-locked = true; action.spawn = [ "${pkgs.playerctl}/bin/playerctl" "stop" ]; };
      "XF86AudioPrev" = { allow-when-locked = true; action.spawn = [ "${pkgs.playerctl}/bin/playerctl" "previous" ]; };
      "XF86AudioNext" = { allow-when-locked = true; action.spawn = [ "${pkgs.playerctl}/bin/playerctl" "next" ]; };

      # Brightness
      "XF86MonBrightnessUp" = { allow-when-locked = true; action.spawn = [ "${pkgs.brightnessctl}/bin/brightnessctl" "--class=backlight" "set" "+11%" ]; };
      "XF86MonBrightnessDown" = { allow-when-locked = true; action.spawn = [ "${pkgs.brightnessctl}/bin/brightnessctl" "--class=backlight" "set" "10%-" ]; };

      # Overview
      "Mod+O" = { repeat = false; action.toggle-overview = {}; };

      # Close window
      "Mod+Q" = { repeat = false; hotkey-overlay.title = "Close focused window"; action.spawn = "${kill-active}"; };
      "Mod+Shift+Q" = { repeat = false; hotkey-overlay.title = "Force Close focused window"; action.spawn = "${kill-active-force}"; };

      # Focus & move
      "Mod+Left".action.focus-column-left = {};
      "Mod+Down".action.focus-window-down = {};
      "Mod+Up".action.focus-window-up = {};
      "Mod+Right".action.focus-column-right = {};
      "Mod+H".action.spawn = [ "${focus-with-overview}" "focus-column-or-monitor-left" "true" ];
      "Mod+L".action.spawn = [ "${focus-with-overview}" "focus-column-or-monitor-right" "true" ];
      "Mod+Ctrl+H".action.move-column-left-or-to-monitor-left = {};
      "Mod+Ctrl+J".action.move-window-down-or-to-workspace-down = {};
      "Mod+Ctrl+K".action.move-window-up-or-to-workspace-up = {};
      "Mod+Ctrl+L".action.move-column-right-or-to-monitor-right = {};

      "Mod+Ctrl+R".action.spawn = [ "niri" "msg" "action" "set-dynamic-cast-window" ];

      "Mod+Shift+H".action.focus-monitor-left = {};
      "Mod+Shift+J".action.move-window-down-or-to-workspace-down = {};
      "Mod+Shift+K".action.move-window-up-or-to-workspace-up = {};
      "Mod+Shift+L".action.move-column-right-or-to-monitor-right = {};

      "Mod+J".action.spawn = [ "${focus-with-overview}" "focus-workspace-down" ];
      "Mod+K".action.spawn = [ "${focus-with-overview}" "focus-workspace-up" ];

      "Mod+Home".action.focus-column-first = {};
      "Mod+End".action.focus-column-last = {};
      "Mod+Ctrl+Home".action.move-column-to-first = {};
      "Mod+Ctrl+End".action.move-column-to-last = {};

      "Mod+Shift+Left".action.focus-monitor-left = {};
      "Mod+Shift+Down".action.focus-monitor-down = {};
      "Mod+Shift+Up".action.focus-monitor-up = {};
      "Mod+Shift+Right".action.focus-monitor-right = {};

      "Mod+Shift+Ctrl+Left".action.move-workspace-to-monitor-left = {};
      "Mod+Shift+Ctrl+Down".action.move-workspace-to-monitor-down = {};
      "Mod+Shift+Ctrl+Up".action.move-workspace-to-monitor-up = {};
      "Mod+Shift+Ctrl+Right".action.move-workspace-to-monitor-right = {};
      "Mod+Shift+Ctrl+H".action.move-workspace-to-monitor-left = {};
      "Mod+Shift+Ctrl+J".action.move-workspace-to-monitor-down = {};
      "Mod+Shift+Ctrl+K".action.move-workspace-to-monitor-up = {};
      "Mod+Shift+Ctrl+L".action.move-workspace-to-monitor-right = {};

      "Mod+Ctrl+Page_Down".action.move-column-to-workspace-down = {};
      "Mod+Ctrl+Page_Up".action.move-column-to-workspace-up = {};
      "Mod+Ctrl+U".action.move-column-to-workspace-down = {};
      "Mod+Ctrl+I".action.move-column-to-workspace-up = {};

      "Mod+Shift+Page_Down".action.move-workspace-down = {};
      "Mod+Shift+Page_Up".action.move-workspace-up = {};
      "Mod+Shift+U".action.move-workspace-down = {};
      "Mod+Shift+I".action.move-workspace-up = {};

      # Mouse wheel
      "Mod+WheelScrollDown" = { cooldown-ms = 150; action.focus-workspace-down = {}; };
      "Mod+WheelScrollUp" = { cooldown-ms = 150; action.focus-workspace-up = {}; };
      "Mod+Ctrl+WheelScrollDown" = { cooldown-ms = 150; action.move-column-to-workspace-down = {}; };
      "Mod+Ctrl+WheelScrollUp" = { cooldown-ms = 150; action.move-column-to-workspace-up = {}; };

      "Mod+WheelScrollRight".action.focus-column-right = {};
      "Mod+WheelScrollLeft".action.focus-column-left = {};
      "Mod+Ctrl+WheelScrollRight".action.move-column-right = {};
      "Mod+Ctrl+WheelScrollLeft".action.move-column-left = {};

      "Mod+Shift+WheelScrollDown".action.focus-column-right = {};
      "Mod+Shift+WheelScrollUp".action.focus-column-left = {};
      "Mod+Ctrl+Shift+WheelScrollDown".action.move-column-right = {};
      "Mod+Ctrl+Shift+WheelScrollUp".action.move-column-left = {};

      # Screenshots

      # Workspace focus
      "Mod+1".action = workspaceFocusAction "one";
      "Mod+2".action = workspaceFocusAction "two";
      "Mod+3".action = workspaceFocusAction "three";
      "Mod+4".action = workspaceFocusAction "four";
      "Mod+5".action = workspaceFocusAction "five";
      "Mod+6".action = workspaceFocusAction "six";
      "Mod+7".action = workspaceFocusAction "seven";
      "Mod+8".action = workspaceFocusAction "eight";
      "Mod+9".action = workspaceFocusAction "nine";
      "Mod+0".action = workspaceFocusAction "ten";

      # Move column to workspace
      "Mod+Ctrl+1".action.move-column-to-workspace = "one";
      "Mod+Ctrl+2".action.move-column-to-workspace = "two";
      "Mod+Ctrl+3".action.move-column-to-workspace = "three";
      "Mod+Ctrl+4".action.move-column-to-workspace = "four";
      "Mod+Ctrl+5".action.move-column-to-workspace = "five";
      "Mod+Ctrl+6".action.move-column-to-workspace = "six";
      "Mod+Ctrl+7".action.move-column-to-workspace = "seven";
      "Mod+Ctrl+8".action.move-column-to-workspace = "eight";
      "Mod+Ctrl+9".action.move-column-to-workspace = "nine";
      "Mod+Ctrl+0".action.move-column-to-workspace = "ten";

      # Column/window management
      "Mod+BracketLeft".action.consume-or-expel-window-left = {};
      "Mod+BracketRight".action.consume-or-expel-window-right = {};
      "Mod+Comma".action.consume-window-into-column = {};
      "Mod+Period".action.expel-window-from-column = {};

      "Mod+R".action.switch-preset-column-width = {};
      "Mod+I".action.switch-preset-window-height-back = {};
      "Mod+F".action.maximize-column = {};
      "Mod+Shift+F".action.fullscreen-window = {};
      "Mod+Ctrl+F".action.expand-column-to-available-width = {};
      "Mod+C".action.center-column = {};
      "Mod+Ctrl+C".action.center-visible-columns = {};

      # Size adjustments
      "Mod+Minus".action.set-column-width = "-10%";
      "Mod+Equal".action.set-column-width = "+10%";
      "Mod+Shift+Minus".action.set-window-height = "-10%";
      "Mod+Shift+Equal".action.set-window-height = "+10%";

      # Floating
      "Mod+Space".action.toggle-window-floating = {};
      "Mod+Shift+Space".action.switch-focus-between-floating-and-tiling = {};

      # Tabs
      "Mod+W".action.toggle-column-tabbed-display = {};

      # Built-in screenshots
      "Print".action.screenshot = {};
      "Ctrl+Print".action.screenshot-screen = {};
      "Alt+Print".action.screenshot-window = {};

      # Keyboard shortcuts inhibitor
      "Mod+Escape" = { allow-inhibiting = false; action.toggle-keyboard-shortcuts-inhibit = {}; };

      # Session management
      "Mod+Shift+E".action.spawn = "${exit-dialog}";
      "Mod+Shift+R".action.spawn = "${reboot-dialog}";
      "Mod+Shift+P".action.power-off-monitors = {};

      # Notifications
      "Mod+Shift+N" = { hotkey-overlay.title = "Clear notifications"; action.spawn = "${clear-notifications}"; };
      "Mod+Shift+Ctrl+N" = { hotkey-overlay.title = "Toggle notification do-not-disturb"; action.spawn = [ "${pkgs.swaynotificationcenter}/bin/swaync-client" "-d" "-sw" ]; };

      # Debug
      "Mod+Shift+Ctrl+T" = { hotkey-overlay.title = "Toggle debug tint"; action.toggle-debug-tint = {}; };
    };

    workspaces = {
      "01-one" = { name = "one"; };
      "02-two" = { name = "two"; };
      "03-three" = { name = "three"; };
      "04-four" = { name = "four"; };
      "05-five" = { name = "five"; };
      "06-six" = { name = "six"; };
      "07-seven" = { name = "seven"; };
      "08-eight" = { name = "eight"; };
      "09-nine" = { name = "nine"; };
      "10-ten" = { name = "ten"; };
    };
  };
}
