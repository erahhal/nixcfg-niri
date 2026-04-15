import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool isDarkMode: true
    property bool isToggling: false

    Process {
        id: getModeProcess
        command: ["dms", "ipc", "call", "theme", "getMode"]
        stdout: SplitParser {
            onRead: data => {
                var mode = data.trim()
                if (mode === "dark" || mode === "light") {
                    root.isDarkMode = (mode === "dark")
                }
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: getModeProcess.running = true
    }

    Process {
        id: toggleProcess
        command: ["toggle-theme"]
        onStarted: root.isToggling = true
        onExited: {
            root.isToggling = false
            getModeProcess.running = true
        }
    }

    pillClickAction: function() {
        if (!root.isToggling) {
            toggleProcess.running = true
        }
    }

    horizontalBarPill: Component {
        Row {
            Item {
                width: root.iconSize
                height: root.iconSize
                anchors.verticalCenter: parent.verticalCenter

                DankIcon {
                    anchors.centerIn: parent
                    name: root.isDarkMode ? "dark_mode" : "light_mode"
                    size: root.iconSize
                    color: Theme.widgetTextColor
                    opacity: root.isToggling ? 0.5 : 1.0
                }
            }
        }
    }

    verticalBarPill: horizontalBarPill
}
