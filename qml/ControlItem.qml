import QtQuick
import QtQuick.Layouts
import Neo 1.0

// One element of the control bar, chosen by id (see Theme.controls).
Item {
    id: root
    required property string controlId
    property bool preview: false        // inside the Customize dialog: no actions
    signal action(string id, Item source)
    readonly property bool compact: parent && parent.width < 720

    readonly property bool flexible: controlId === "seek" || controlId === "spacer"
    implicitWidth: loader.item ? loader.item.implicitWidth : 0
    implicitHeight: 28

    function fire() { if (!preview) root.action(controlId, root) }

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: {
            switch (root.controlId) {
            case "play": return playComp
            case "time": return timeComp
            case "length": return lengthComp
            case "seek": return seekComp
            case "volume": return volumeComp
            case "speed": return speedComp
            case "spacer": return spacerComp
            default: return buttonComp
            }
        }
    }

    Component {
        id: buttonComp
        IconButton {
            readonly property var meta: Theme.controls[root.controlId] || { icon: "minus", label: root.controlId }
            icon: root.controlId === "fullscreen" && win.fullscreen ? "minimize-2"
                  : root.controlId === "loop" && player.repeatOne ? "repeat-1" : meta.icon
            tip: meta.label
            iconSize: root.compact ? 20 : 24
            implicitWidth: 30
            implicitHeight: 30
            checked: (root.controlId === "queue" && win.rightPanel === "queue")
                     || (root.controlId === "settings" && win.rightPanel === "settings")
                     || (root.controlId === "loop" && (player.loop || player.repeatOne))
                     || (root.controlId === "shuffle" && player.random)
                     || (root.controlId === "record" && player.recording)
                     || (root.controlId === "library" && win.libraryOpen)
            iconColor: root.controlId === "record" && player.recording ? "#E0453A"
                       : checked ? Theme.accent : (hovered ? Theme.text : Theme.icon)
            onClicked: root.fire()
        }
    }
    Component {
        id: playComp
        Item {
            implicitWidth: root.compact ? 42 : 54
            PlayButton { anchors.centerIn: parent; compact: root.compact; onClicked: root.fire() }
        }
    }
    Component {
        id: timeComp
        Item {
            implicitWidth: root.compact ? 56 : 76
            NText {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                text: player.formatTime(player.time)
                dim: true
                font.pixelSize: root.compact ? 12 : 15
                font.features: { "tnum": 1 }
            }
        }
    }
    Component {
        id: lengthComp
        Item {
            implicitWidth: root.compact ? 56 : 76
            NText {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                text: player.formatTime(player.length)
                dim: true
                font.pixelSize: root.compact ? 12 : 15
                font.features: { "tnum": 1 }
            }
        }
    }
    Component {
        id: seekComp
        SeekBar { implicitWidth: root.compact ? 60 : 120; enabled: !root.preview }
    }
    Component {
        id: volumeComp
        Row {
            spacing: root.compact ? 2 : 8
            IconButton {
                icon: player.muted || player.volume === 0 ? "volume-x" : (player.volume < 0.5 ? "volume-1" : "volume-2")
                tip: "Mute"
                iconSize: root.compact ? 20 : 24
                implicitWidth: 30
                implicitHeight: 30
                anchors.verticalCenter: parent.verticalCenter
                onClicked: if (!root.preview) player.toggleMute()
            }
            ConeVolume { anchors.verticalCenter: parent.verticalCenter; compact: root.compact; enabled: !root.preview }
        }
    }
    Component {
        id: speedComp
        Rectangle {
            implicitWidth: 44
            radius: Theme.radiusSmall
            color: speedMouse.containsMouse ? Theme.hover : "transparent"
            NText {
                anchors.centerIn: parent
                text: player.rate.toFixed(2).replace(/\.?0+$/, "") + "x"
                font.pixelSize: 12
                color: Math.abs(player.rate - 1) > 0.01 ? Theme.accent : Theme.icon
            }
            MouseArea { id: speedMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.fire() }
        }
    }
    Component {
        id: spacerComp
        Item { implicitWidth: 12 }
    }
}
