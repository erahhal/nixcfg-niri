//@ pragma UseQApplication
import QtQuick
import Quickshell

// Variant A (hybrid): the daily shell (bar + popups) with the competition
// starfield (Stars) + rotating-earth dashboard (Moon) as bottom-layer
// backgrounds behind it.
ShellRoot {
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
        function onReloadFailed(errorString) { Quickshell.inhibitReloadPopup() }
    }

    Stars {}
    Moon {}
    Main {}
    TopBar {}
    Floating {}
}
