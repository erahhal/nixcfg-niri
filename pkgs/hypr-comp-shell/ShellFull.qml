//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Variant B (full competition): the rotating-earth Moon dashboard + Stars over
// the desktop, the daily Main as the (hidden) popup host + notification server,
// and the competition 3D app launcher hosted in a toggleable overlay. No daily
// TopBar/Floating — Moon is the bar here.
ShellRoot {
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
        function onReloadFailed(errorString) { Quickshell.inhibitReloadPopup() }
    }

    Stars {}
    Moon {}
    Main {}

    // The competition AppLauncher is a plain Item; host it in an overlay
    // layer-shell window toggled via IPC:
    //   qs ipc -p <ShellFull.qml> call applauncher toggle
    PanelWindow {
        id: launcherWin
        WlrLayershell.namespace: "applauncher-3d"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: launcherWin.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        visible: false

        IpcHandler {
            target: "applauncher"
            function toggle() { launcherWin.visible = !launcherWin.visible }
            function open() { launcherWin.visible = true }
            function close() { launcherWin.visible = false }
        }

        AppLauncher {
            anchors.fill: parent
            // Drive the Item's visible so its intro animation + Escape close fire.
            visible: launcherWin.visible
        }
    }
}
