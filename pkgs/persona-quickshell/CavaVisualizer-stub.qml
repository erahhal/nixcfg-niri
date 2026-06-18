// No-op replacement for Persona-Quickshell's CavaVisualizer.
//
// Upstream CavaVisualizer renders an audio spectrum through the external
// Qt6-Cava-plugin (github.com/Yujonpradhananga/Qt6-Cava-plugin), a native QML
// plugin that is not packaged here. The original component's root is a plain
// Item with no public properties, and WallpaperEngine.qml only assigns built-in
// Item members (anchors, height) to it — so this stub keeps the shell loading
// while simply drawing nothing where the visualizer would be.
import QtQuick

Item {
    id: root
    clip: false
}
