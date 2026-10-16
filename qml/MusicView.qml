import QtQuick
import QtQuick.Effects
import Neo 1.0

// Audio-only playback: massive cover art over a blurred copy of itself.
Item {
    id: root
    readonly property bool hasArt: player.artworkUrl.length > 0

    Image {
        id: bg
        anchors.fill: parent
        source: player.artworkUrl
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: bg
        visible: root.hasArt
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        brightness: -0.45
    }

    Column {
        anchors.centerIn: parent
        spacing: 18
        Rectangle {
            width: Math.min(root.width, root.height) * 0.52
            height: width
            radius: Theme.radius
            color: Theme.bar
            anchors.horizontalCenter: parent.horizontalCenter
            clip: true
            Image {
                anchors.fill: parent
                source: player.artworkUrl
                fillMode: Image.PreserveAspectCrop
                visible: root.hasArt
            }
            Icon {
                anchors.centerIn: parent
                visible: !root.hasArt
                name: "music"
                size: parent.width * 0.32
                color: Theme.textFaint
            }
        }
        NText {
            text: player.title
            font.pixelSize: 18
            font.weight: Font.DemiBold
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, root.width - 40)
            horizontalAlignment: Text.AlignHCenter
        }
        NText {
            visible: player.artist.length > 0
            text: player.artist
            dim: true
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
