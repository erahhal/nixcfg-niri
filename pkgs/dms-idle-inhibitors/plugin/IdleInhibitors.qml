// Drop-in replacement for DMS's stock IdleInhibitor widget that can also say
// *why* the screen is staying awake.
//
// The stock widget only ever reflects SessionService.idleInhibited, the manual
// toggle. Its other source, IdleService.externalInhibitActive, is dead on niri:
// that reads DMSService.screensaverInhibited, fed by the dms backend's
// freedesktop.screensaver subscription, but niri owns org.freedesktop.ScreenSaver
// itself so the backend can never acquire the name. Meanwhile DMS's IdleMonitors
// run with respectInhibitors true, so niri silently withholds idle and the shell
// has no way to report what caused it.
//
// So detect and attribute separately:
//   detect     A pair of IdleMonitors at the same timeout. The one that ignores
//              inhibitors goes idle on input alone; the one that respects them
//              only goes idle when nothing is inhibiting. Input-idle without
//              gated-idle means something is holding the screen up.
//   attribute  `dms-idle-inhibitors` reports D-Bus holders (exact, via the
//              tracker), logind idle blocks (exact), and visible windows from
//              app families known to use zwp_idle_inhibit (candidates only --
//              niri exposes Wayland inhibitors to nobody).
//
// Detection needs probeSeconds of no input to conclude anything, and by
// definition you have just touched the mouse when the popout opens. So every
// detected episode is snapshotted when it starts, and the popout shows that
// history -- which is what makes an intermittent inhibit findable at all.

import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginComponent {
    id: root

    layerNamespacePlugin: "idleInhibitors"

    // How long without input before the probe can judge. Long enough not to
    // flag brief inhibits, short enough to catch one well before the 5 min
    // lock timeout.
    readonly property int probeSeconds: pluginData.probeSeconds ?? 60
    readonly property int maxEpisodes: pluginData.maxEpisodes ?? 10

    readonly property bool manualInhibited: SessionService.idleInhibited

    // Input-idle without gated-idle == something is inhibiting.
    readonly property bool probeConclusive: inputIdleMonitor.isIdle
    readonly property bool compositorInhibited: inputIdleMonitor.isIdle && !gatedIdleMonitor.isIdle

    // Anything at all holding the screen up, manual toggle included.
    readonly property bool anyInhibit: manualInhibited || compositorInhibited

    property var report: null
    property double reportAt: 0
    property var episodes: []

    // Both always armed: the comparison between them is the whole detector,
    // and DMS's own monitors gate on enabled for their own reasons.
    IdleMonitor {
        id: inputIdleMonitor
        enabled: true
        timeout: root.probeSeconds
        respectInhibitors: false
    }

    IdleMonitor {
        id: gatedIdleMonitor
        enabled: true
        timeout: root.probeSeconds
        respectInhibitors: true
    }

    Process {
        id: reportProcess
        command: ["dms-idle-inhibitors"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.report = JSON.parse(text);
                    root.reportAt = Date.now();
                } catch (e) {
                    root.report = null;
                }
                if (root._snapshotPending) {
                    root._snapshotPending = false;
                    root._recordEpisode();
                }
            }
        }
    }

    property bool _snapshotPending: false

    function refreshReport() {
        if (!reportProcess.running)
            reportProcess.running = true;
    }

    // Snapshot who was around the moment an inhibit was detected; without this
    // the culprit is gone by the time anyone opens the popout.
    function _recordEpisode() {
        const r = root.report;
        const names = [];
        if (r) {
            for (const h of (r.dbus ?? []))
                names.push((h.app || h.comm || "?") + " (D-Bus)");
            for (const l of (r.logind?.idle ?? []))
                names.push(l.who + " (logind)");
            for (const c of (r.waylandCandidates ?? []))
                names.push(c.app_id + " (candidate)");
        }
        const next = episodes.slice();
        next.unshift({
            at: Date.now(),
            names: names,
            exact: (r?.dbus?.length ?? 0) > 0 || (r?.logind?.idle?.length ?? 0) > 0
        });
        episodes = next.slice(0, maxEpisodes);
    }

    onCompositorInhibitedChanged: {
        if (compositorInhibited) {
            _snapshotPending = true;
            refreshReport();
        }
    }

    // Keep the report warm while the popout is open.
    Timer {
        running: inhibitorsPopout.shouldBeVisible
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshReport()
    }

    function _agoText(ms) {
        if (!ms)
            return "never";
        const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
        if (s < 60)
            return s + "s ago";
        if (s < 3600)
            return Math.round(s / 60) + "m ago";
        return Math.round(s / 3600) + "h ago";
    }

    function _clockText(ms) {
        return Qt.formatTime(new Date(ms), SettingsData.use24HourClock ? "HH:mm" : "h:mm AP");
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: pillIcon.width
            implicitHeight: root.widgetThickness

            DankIcon {
                id: pillIcon
                anchors.centerIn: parent
                name: root.anyInhibit ? "motion_sensor_active" : "motion_sensor_idle"
                size: root.iconSize
                // Manual inhibit is deliberate, so it gets the normal accent;
                // an inhibit nobody asked for is the thing worth noticing.
                color: root.manualInhibited ? Theme.primary : (root.compositorInhibited ? Theme.error : Theme.widgetTextColor)
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: root.widgetThickness
            implicitHeight: vPillIcon.height

            DankIcon {
                id: vPillIcon
                anchors.centerIn: parent
                name: root.anyInhibit ? "motion_sensor_active" : "motion_sensor_idle"
                size: root.iconSize
                color: root.manualInhibited ? Theme.primary : (root.compositorInhibited ? Theme.error : Theme.widgetTextColor)
            }
        }
    }

    // Left click keeps the stock behaviour.
    pillClickAction: () => SessionService.toggleIdleInhibit()

    // PluginComponent.triggerPopout() defers to pillClickAction when one is
    // set, so it would toggle the inhibit instead of opening anything. Drive a
    // popout of our own instead.
    pillRightClickAction: (x, y, width, section, screen) => {
        const barPosition = root.axis?.edge === "left" ? 2 : (root.axis?.edge === "right" ? 3 : (root.axis?.edge === "top" ? 0 : 1));
        inhibitorsPopout.setTriggerPosition(x, y, width, section, screen, barPosition, root.barThickness, root.barSpacing, root.barConfig);
        inhibitorsPopout.toggle();
    }

    PluginPopout {
        id: inhibitorsPopout
        contentWidth: 400
        pluginContent: inhibitorsContent
    }

    Component {
        id: inhibitorsContent

        PopoutComponent {
            headerText: "Idle inhibitors"
            detailsText: {
                if (root.manualInhibited)
                    return "Inhibited by you — the screen will not lock";
                if (root.compositorInhibited)
                    return "Something is holding the screen awake";
                if (root.probeConclusive)
                    return "Nothing is inhibiting — idle is working";
                return "Idle for less than " + root.probeSeconds + "s; nothing to judge yet";
            }
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // ── Manual toggle ────────────────────────────────────────
                Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    DankIcon {
                        name: root.manualInhibited ? "motion_sensor_active" : "motion_sensor_idle"
                        size: 24
                        color: root.manualInhibited ? Theme.primary : Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            text: "Manual inhibit " + (root.manualInhibited ? "on" : "off")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: "Left-click the bar icon to toggle"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outlineMedium
                }

                // ── D-Bus holders: exact ─────────────────────────────────
                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "D-Bus (org.freedesktop.ScreenSaver)"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        visible: root.report !== null && !root.report.trackerRunning
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Tracker not running — start dms-idle-inhibit-tracker to attribute these."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.error
                    }

                    StyledText {
                        visible: root.report?.trackerRunning === true && (root.report?.dbus?.length ?? 0) === 0
                        text: "No holders"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    Repeater {
                        model: root.report?.dbus ?? []

                        Column {
                            required property var modelData
                            width: parent.width
                            spacing: 0

                            StyledText {
                                text: "• " + (modelData.app || "unknown app")
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            StyledText {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                leftPadding: Theme.spacingM
                                text: (modelData.comm ?? "?") + " (pid " + (modelData.pid ?? "?") + ")" + (modelData.reason ? " — " + modelData.reason : "")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }

                // ── logind idle blocks: exact ────────────────────────────
                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "logind idle blocks"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        visible: (root.report?.logind?.idle?.length ?? 0) === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        // Worth stating: a long systemd-inhibit list is normal and
                        // almost never the reason a screen will not lock.
                        text: "None. (" + (root.report?.logind?.other?.length ?? 0) + " other locks — sleep/power-key, which do not stop a lock.)"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    Repeater {
                        model: root.report?.logind?.idle ?? []

                        StyledText {
                            required property var modelData
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "• " + modelData.who + " (pid " + modelData.pid + ") — " + modelData.why
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
                    }
                }

                // ── Wayland: candidates only ─────────────────────────────
                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Wayland (zwp_idle_inhibit)"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "niri exposes no list of these, so they cannot be named exactly. Visible windows that could hold one:"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        visible: (root.report?.waylandCandidates?.length ?? 0) === 0
                        text: "No candidate windows visible"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    Repeater {
                        model: root.report?.waylandCandidates ?? []

                        StyledText {
                            required property var modelData
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "• " + modelData.app_id + " (pid " + modelData.pid + ")" + (modelData.focused ? " — focused" : "")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outlineMedium
                    visible: root.episodes.length > 0
                }

                // ── History: the part that catches an intermittent inhibit ──
                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: root.episodes.length > 0

                    StyledText {
                        text: "Detected episodes this session"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceVariantText
                    }

                    Repeater {
                        model: root.episodes

                        StyledText {
                            required property var modelData
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "• " + root._clockText(modelData.at) + " (" + root._agoText(modelData.at) + ") — " + (modelData.names.length > 0 ? modelData.names.join(", ") : "nothing identifiable")
                            font.pixelSize: Theme.fontSizeSmall
                            color: modelData.exact ? Theme.surfaceText : Theme.surfaceVariantText
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Probe needs " + root.probeSeconds + "s without input to judge. Report " + root._agoText(root.reportAt) + "."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }
}
