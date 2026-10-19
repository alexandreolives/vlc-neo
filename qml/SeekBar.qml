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
    function cueAt(timeMs) {
        const cues = player.subtitleCues
        let low = 0, high = cues.length
        while (low < high) {
            const mid = (low + high) >> 1
            if (cues[mid].start <= timeMs) low = mid + 1
            else high = mid
        }
        for (let i = low - 1; i >= 0 && cues[i].maxEnd > timeMs; --i) {
            if (cues[i].end > timeMs) return cues[i]
        }
        return null
    }
    readonly property var hoveredCue: mouse.containsMouse && player.length > 0
                                       ? cueAt(mouse.mouseX / root.width * player.length) : null

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
        Canvas {
            id: subtitleMarks
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (player.length <= 0) return
                ctx.fillStyle = Theme.text
                const cues = player.subtitleCues
                for (let i = 0; i < cues.length; ++i) {
                    const cue = cues[i]
                    const x1 = 2 + cue.start / player.length * (width - 4)
                    const x2 = 2 + cue.end / player.length * (width - 4)
                    ctx.fillRect(Math.floor(x1), height - 5, Math.max(1, Math.ceil(x2 - x1)), 2)
                }
            }
            Connections {
                target: player
                function onSubtitleTimelineChanged() { subtitleMarks.requestPaint() }
                function onTimeChanged() {
                    if (subtitleMarks.renderedLength !== player.length) {
                        subtitleMarks.renderedLength = player.length
                        subtitleMarks.requestPaint()
                    }
                }
            }
            property real renderedLength: player.length
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
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
        width: root.hoveredCue ? Math.min(294, root.width) : bubbleText.implicitWidth + 14
        height: bubbleText.implicitHeight + 12
        y: -height - 6
        x: Math.min(Math.max(mouse.mouseX - width / 2, 0), root.width - width)
        NText {
            id: bubbleText
            anchors.centerIn: parent
            width: Math.min(280, root.width - 14)
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.Wrap
            maximumLineCount: 4
            text: {
                const time = player.formatTime(Math.max(0, Math.min(1, mouse.mouseX / root.width)) * player.length)
                return root.hoveredCue ? time + "\n" + root.hoveredCue.text : time
            }
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
