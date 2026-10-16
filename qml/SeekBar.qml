import QtQuick
import Neo 1.0

// Thick seek bar (Figma): dark track, dimmed-accent progress, narrow accent handle,
// bookmark/chapter ticks and a hover time bubble.
Item {
    id: root
    property real position: player.position
    property bool dragging: mouse.pressed
    property real dragPosition: 0
    implicitHeight: 22

    readonly property real shown: dragging ? dragPosition : position

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 16
        radius: 3
        color: Theme.seekTrack

        Rectangle {
            width: Math.max(0, root.shown * parent.width)
            height: parent.height
            radius: 3
            color: Theme.accentDim
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
        width: 6
        height: track.height + 4
        radius: 2
        color: Theme.accent
        anchors.verticalCenter: parent.verticalCenter
        x: root.shown * (root.width - width)
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
        onReleased: (e) => player.seek(posAt(e.x))
        onWheel: (e) => player.seekBy(e.angleDelta.y > 0 ? 5000 : -5000)
    }
}
