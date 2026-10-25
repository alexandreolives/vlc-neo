import QtQuick
import QtQuick.Layouts
import Neo 1.0

// Timeline and transport share the compact Player footer row.
Rectangle {
    id: root
    objectName: "timeline-bar"
    property alias contentItem: seekBar
    property alias seekControl: seekBar
    property alias elapsedText: elapsedText
    property alias durationText: durationText
    property bool compact: width < 720
    property bool tiny: width < 400

    color: "transparent"
    implicitWidth: tiny ? 48 : compact ? 150 : 250
    implicitHeight: Theme.barHeight

    RowLayout {
        anchors.fill: parent
        spacing: root.tiny ? 0 : root.compact ? 2 : 8

        NText {
            id: elapsedText
            objectName: "timeline-elapsed"
            visible: !root.tiny
            Layout.preferredWidth: root.compact ? 48 : 64
            Layout.minimumWidth: Layout.preferredWidth
            Layout.alignment: Qt.AlignVCenter
            text: player.formatTime(player.time)
            horizontalAlignment: Text.AlignHCenter
            color: Theme.icon
            font.pixelSize: root.compact ? 10 : 13
            font.features: { "tnum": 1 }
        }

        SeekBar {
            id: seekBar
            objectName: "timeline-seek"
            Layout.fillWidth: true
            Layout.minimumWidth: 32
            enabled: player.seekable
        }

        NText {
            id: durationText
            objectName: "timeline-duration"
            visible: !root.tiny
            Layout.preferredWidth: root.compact ? 48 : 64
            Layout.minimumWidth: Layout.preferredWidth
            Layout.alignment: Qt.AlignVCenter
            text: player.formatTime(player.length)
            horizontalAlignment: Text.AlignHCenter
            color: Theme.icon
            font.pixelSize: root.compact ? 10 : 13
            font.features: { "tnum": 1 }
        }
    }
}
