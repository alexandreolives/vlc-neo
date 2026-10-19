import QtQuick
import Neo 1.0

// Thick seek bar (Figma): dark track, dimmed-accent progress, narrow accent handle,
// bookmark/chapter ticks and a hover time bubble.
FocusScope {
    id: root
    property real position: player.position
    property bool dragging: mouse.pressed
    property real dragPosition: 0
    implicitHeight: 28
    activeFocusOnTab: true
    Accessible.name: "Seek position"
    Accessible.role: Accessible.Slider

    readonly property real shown: dragging ? dragPosition : position

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 28
        radius: 6
        color: Theme.seekTrack
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.accent

        Rectangle {
            x: 2
            y: 2
            width: Math.max(0, root.shown * (parent.width - 4))
            height: parent.height - 4
            radius: 4
            color: Theme.seekProgress
        }
        Repeater {
            model: player.length > 0 ? bookmarksModel : []
            delegate: Rectangle {
                required property var modelData
                width: 2; height: parent.height - 6
                y: 3
                x: modelData.time / player.length * track.width
                color: Theme.text
                opacity: 0.55
            }
        }
        Rectangle {
            visible: mouse.containsMouse
            x: mouse.mouseX - 1
            width: 2
            height: parent.height
            color: Theme.text
            opacity: 0.25
        }
    }
    Rectangle {
        width: 8
        height: 24
        radius: 4
        color: Theme.accent
        y: 2
        x: Math.max(2, Math.min(track.width - width - 2, 2 + root.shown * (track.width - 4) - width / 2))
        visible: player.hasMedia
    }

    Rectangle {
        id: bubble
        visible: mouse.containsMouse && player.length > 0
        color: Theme.surface
        border.color: Theme.border
        radius: Theme.radiusSmall
        width: bubbleText.implicitWidth + 14
        height: 22
        y: -height - 6
        x: Math.min(Math.max(mouse.mouseX - width / 2, 0), root.width - width)
        NText {
            id: bubbleText
            anchors.centerIn: parent
            font.pixelSize: Theme.fontSmall
            text: player.formatTime(Math.max(0, Math.min(1, mouse.mouseX / root.width)) * player.length)
        }
    }

    property var bookmarksModel: []
    Connections {
        target: player
        function onBookmarksChanged() { root.bookmarksModel = player.bookmarks() }
        function onMediaChanged() { root.bookmarksModel = player.bookmarks() }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        hoverEnabled: true
        enabled: player.seekable
        cursorShape: Qt.PointingHandCursor
        function posAt(x) { return Math.max(0, Math.min(1, x / root.width)) }
        onPressed: (e) => root.dragPosition = posAt(e.x)
        onPositionChanged: (e) => { if (pressed) root.dragPosition = posAt(e.x) }
        onClicked: root.forceActiveFocus()
        onReleased: (e) => { player.seek(posAt(e.x)); root.forceActiveFocus() }
        onWheel: (e) => player.seekBy(e.angleDelta.y > 0 ? 5000 : -5000)
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Left) {
            player.seekBy(-5000)
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            player.seekBy(5000)
            event.accepted = true
        } else if (event.key === Qt.Key_Home) {
            player.seek(0)
            event.accepted = true
        } else if (event.key === Qt.Key_End) {
            // VLC rejects position 1.0 as outside the valid seek range.
            // Seek just before EOF and let playback finish naturally.
            player.seek(0.99)
            event.accepted = true
        }
    }
}
