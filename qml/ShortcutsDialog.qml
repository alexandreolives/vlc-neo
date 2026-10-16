import QtQuick
import QtQuick.Layouts
import Neo 1.0

Modal {
    id: root
    title: "Keyboard Shortcuts"
    subtitle: "Every other VLC hotkey keeps working too — change them in VLC's hotkey settings (vlcrc)."
    width: 760

    readonly property var shortcuts: [
        ["Play / Pause", ["Space"]], ["Toggle fullscreen", ["F"]],
        ["Seek backward / forward 10 s", ["←", "→"]], ["Volume down / up", ["↓", "↑"]],
        ["Seek 3 s", ["Shift", "← →"]], ["Seek 1 min", ["Ctrl", "← →"]],
        ["Previous / next item", ["P", "N"]], ["Mute", ["M"]],
        ["Cycle subtitle track", ["V"]], ["Cycle audio track", ["B"]],
        ["Subtitle earlier / later", ["G", "H"]], ["Audio earlier / later", ["J", "K"]],
        ["Speed down / up / normal", ["[", "]", "="]], ["Next frame", ["E"]],
        ["Show / hide queue", ["Q"]], ["Show / hide library", ["L"]],
        ["Playback settings", ["Ctrl", "E"]], ["Hide the whole UI", ["Ctrl", "H"]],
        ["Add bookmark", ["Ctrl", "B"]], ["Take a snapshot", ["Shift", "S"]],
        ["Record", ["Shift", "R"]], ["Stop", ["S"]],
        ["Open file", ["Ctrl", "O"]], ["Open network stream", ["Ctrl", "N"]],
        ["Open from clipboard", ["Ctrl", "V"]], ["Preferences", ["Ctrl", "P"]],
        ["This list", ["?"]], ["Leave fullscreen / close panel", ["Esc"]]
    ]

    GridLayout {
        width: root.width - 36
        columns: 2
        columnSpacing: 28
        rowSpacing: 8
        Repeater {
            model: root.shortcuts
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                NText { text: modelData[0]; dim: true; Layout.fillWidth: true }
                Repeater {
                    model: modelData[1]
                    delegate: Rectangle {
                        required property string modelData
                        implicitWidth: Math.max(26, k.implicitWidth + 14)
                        implicitHeight: 24
                        radius: 3
                        color: Theme.raised
                        border.color: Theme.border
                        NText { id: k; anchors.centerIn: parent; text: modelData; font.pixelSize: 11 }
                    }
                }
            }
        }
    }
}
