import QtQuick
import QtQuick.Effects
import Neo 1.0

// Audio-only playback: massive cover art over a blurred copy of itself.
Item {
    id: root
    readonly property bool hasArt: player.artworkUrl.length > 0
    readonly property real coverScale: 0.75
    property real bottomTimelineInset: 0
    readonly property int titleGap: 72
    property alias artworkItem: coverArt
    property alias infoLabel: trackInfo

    Image {
        id: bg
        anchors.fill: parent
        source: player.artworkUrl
        fillMode: Image.PreserveAspectCrop
        // Keep the source drawable so MultiEffect can sample it. The effect is
        // layered above this item and fully covers its sharp copy.
        opacity: 1
    }
    MultiEffect {
        anchors.fill: parent
        source: bg
        autoPaddingEnabled: false
        visible: root.hasArt
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        brightness: -0.75
    }

    Column {
        id: musicContent
        anchors.centerIn: parent
        spacing: root.titleGap
        Rectangle {
            id: coverArt
            objectName: "music-player-artwork"
            // The Figma player gives the artwork most of the available height.
            // Keep it responsive to narrow windows while matching that larger
            // 1920×1080 presentation.
            width: Math.min(root.width, root.height + root.bottomTimelineInset) * root.coverScale
            height: width
            radius: 16
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
            id: trackInfo
            objectName: "music-player-track-info"
            text: player.artist.length > 0 ? player.title + " - " + player.artist : player.title
            font.pixelSize: 22
            font.weight: Font.DemiBold
            color: Theme.icon
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, root.width - 40)
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
