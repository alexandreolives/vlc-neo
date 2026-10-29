import QtQuick
import QtQuick.Layouts
import Neo 1.0

// Thick seek bar (Figma): dark track, dimmed-accent progress, narrow accent handle,
// bookmark/chapter ticks and a hover time bubble.
FocusScope {
    id: root
    property real position: player.position
    property bool dragging: mouse.pressed
    property real dragPosition: 0
    readonly property bool onboardingCompact: win.onboardingActive && onboarding.step === 1
    implicitHeight: onboardingCompact ? 18 : 28
    activeFocusOnTab: true
    Accessible.name: "Seek position"
    Accessible.role: Accessible.Slider

    readonly property real shown: dragging ? dragPosition : position
    readonly property bool pointerHovered: mouse.containsMouse
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
    readonly property int hoveredTimeMs: player.length > 0
                                        ? Math.round(mouse.mouseX / root.width * player.length) : 0
    property string thumbnailSource: ""
    property string waveformSource: ""
    property int pendingThumbnailSecond: -1
    property int requestedThumbnailSecond: -1
    property int displayedThumbnailSecond: -1
    property int pendingThumbnailTimeMs: -1
    property int requestedThumbnailTimeMs: -1
    property int displayedThumbnailTimeMs: -1
    property bool thumbnailRequestInFlight: false
    readonly property bool thumbnailPreviewEnabled: Theme.store.showSeekThumbnails
    readonly property bool thumbnailReady: thumbnail.status === Image.Ready
    readonly property bool waveformReady: waveform.status === Image.Ready

    function requestThumbnail(timeMs) {
        if (!thumbnailPreviewEnabled || !player.hasVideo || !player.mediaUrl.toString().startsWith("file:")) {
            thumbnailSource = ""
            pendingThumbnailSecond = -1
            pendingThumbnailTimeMs = -1
            return false
        }
        const path = platform.localPath(player.mediaUrl)
        if (!path.length) {
            thumbnailSource = ""
            pendingThumbnailSecond = -1
            pendingThumbnailTimeMs = -1
            return false
        }
        // Five preview samples per second keep fast scrubbing responsive without
        // starting an extraction for every pointer pixel.
        const frameTimeMs = Math.max(0, Math.floor(timeMs / 200) * 200)
        if (!thumbnailRequestInFlight && frameTimeMs === displayedThumbnailTimeMs) {
            pendingThumbnailSecond = -1
            pendingThumbnailTimeMs = -1
            return true
        }
        pendingThumbnailTimeMs = frameTimeMs
        pendingThumbnailSecond = Math.floor(frameTimeMs / 1000)
        if (!thumbnailRequestInFlight && frameTimeMs !== displayedThumbnailTimeMs) {
            if (!thumbnailRequestTimer.running) thumbnailRequestTimer.start()
        }
        return true
    }

    function pumpThumbnailRequest() {
        if (thumbnailRequestInFlight || pendingThumbnailTimeMs < 0 || !mouse.containsMouse
                || !thumbnailPreviewEnabled || !player.hasVideo)
            return
        const frameTimeMs = pendingThumbnailTimeMs
        pendingThumbnailSecond = -1
        pendingThumbnailTimeMs = -1
        if (frameTimeMs === displayedThumbnailTimeMs)
            return
        const path = platform.localPath(player.mediaUrl)
        if (!path.length)
            return
        requestedThumbnailTimeMs = frameTimeMs
        requestedThumbnailSecond = Math.floor(frameTimeMs / 1000)
        thumbnailRequestInFlight = true
        thumbnailSource = "image://thumbnail/frame?path=" + encodeURIComponent(path)
                + "&tms=" + frameTimeMs
        thumbnailRequestInFlight = thumbnail.status === Image.Loading
        if (!thumbnailRequestInFlight)
            thumbnailRequestFinished()
    }

    function thumbnailRequestFinished() {
        thumbnailRequestInFlight = false
        if (thumbnail.status === Image.Ready || thumbnail.status === Image.Error) {
            displayedThumbnailTimeMs = requestedThumbnailTimeMs
            displayedThumbnailSecond = Math.floor(requestedThumbnailTimeMs / 1000)
        }
        if (pendingThumbnailTimeMs === displayedThumbnailTimeMs) {
            pendingThumbnailSecond = -1
            pendingThumbnailTimeMs = -1
        }
        if (pendingThumbnailTimeMs >= 0 && pendingThumbnailTimeMs !== displayedThumbnailTimeMs
                && mouse.containsMouse && thumbnailPreviewEnabled && !thumbnailRequestTimer.running)
            thumbnailRequestTimer.start()
    }

    function requestWaveform() {
        if (!player.hasMedia || !player.mediaUrl.toString().startsWith("file:") || player.length <= 0)
            return false
        const path = platform.localPath(player.mediaUrl)
        if (!path.length)
            return false
        const duration = Math.ceil(player.length / 1000)
        waveformSource = "image://thumbnail/wave?path=" + encodeURIComponent(path) + "&duration=" + duration
        return true
    }

    Timer {
        id: thumbnailRequestTimer
        interval: 45
        onTriggered: root.pumpThumbnailRequest()
    }
    Timer {
        id: thumbnailHoverTicker
        interval: 140
        repeat: true
        running: mouse.containsMouse && player.hasVideo && root.thumbnailPreviewEnabled
        onTriggered: root.requestThumbnail(root.hoveredTimeMs)
    }
    onHoveredTimeMsChanged: {
        if (mouse.containsMouse && player.hasVideo && thumbnailPreviewEnabled)
            requestThumbnail(hoveredTimeMs)
    }
    Connections {
        target: Theme.store
        function onShowSeekThumbnailsChanged() {
            if (!root.thumbnailPreviewEnabled) {
                thumbnailRequestTimer.stop()
                root.pendingThumbnailSecond = -1
                root.pendingThumbnailTimeMs = -1
                root.requestedThumbnailSecond = -1
                root.displayedThumbnailSecond = -1
                root.requestedThumbnailTimeMs = -1
                root.displayedThumbnailTimeMs = -1
                root.thumbnailRequestInFlight = false
                root.thumbnailSource = ""
            }
        }
    }
    Connections {
        target: player
        function onMediaChanged() {
            thumbnailRequestTimer.stop()
            root.pendingThumbnailSecond = -1
            root.pendingThumbnailTimeMs = -1
            root.displayedThumbnailSecond = -1
            root.requestedThumbnailSecond = -1
            root.displayedThumbnailTimeMs = -1
            root.requestedThumbnailTimeMs = -1
            root.thumbnailRequestInFlight = false
            root.thumbnailSource = ""
            root.waveformSource = ""
        }
        function onTimeChanged() {
            if (!root.waveformSource.length && player.length > 0)
                root.requestWaveform()
        }
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.onboardingCompact ? 12 : 28
        radius: 6
        color: Theme.seekTrack
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.accent

        Rectangle {
            x: 2
            y: root.onboardingCompact ? 1 : 2
            width: Math.max(0, root.shown * (parent.width - 4))
            height: parent.height - (root.onboardingCompact ? 2 : 4)
            radius: 4
            color: Theme.seekProgress
        }
        Image {
            id: waveform
            anchors.centerIn: parent
            z: 3
            width: parent.width - 4
            height: root.onboardingCompact ? 8 : 20
            source: root.waveformSource
            sourceSize: Qt.size(768, 28)
            fillMode: Image.Stretch
            smooth: false
            cache: false
            asynchronous: true
            opacity: 0.82
            visible: status === Image.Ready
        }
        Canvas {
            id: subtitleMarks
            z: 2
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
        width: root.onboardingCompact ? 6 : 8
        height: root.onboardingCompact ? 14 : 24
        radius: 4
        color: Theme.accent
        y: root.onboardingCompact ? 7 : 2
        x: Math.max(2, Math.min(track.width - width - 2, 2 + root.shown * (track.width - 4) - width / 2))
        visible: player.hasMedia
    }

    Rectangle {
        id: bubble
        visible: mouse.containsMouse && player.length > 0
        color: Theme.surface
        border.color: Theme.border
        radius: Theme.radiusSmall
        width: root.hoveredCue || thumbnail.visible ? Math.min(294, root.width) : bubbleText.implicitWidth + 14
        height: bubbleColumn.implicitHeight + 12
        y: -height - 6
        x: Math.min(Math.max(mouse.mouseX - width / 2, 0), root.width - width)
        ColumnLayout {
            id: bubbleColumn
            anchors.fill: parent
            anchors.margins: 6
            spacing: 5
            Image {
                id: thumbnail
                objectName: "seek-thumbnail-preview"
                Layout.fillWidth: true
                Layout.preferredHeight: 158
                visible: root.thumbnailPreviewEnabled && root.thumbnailSource.length > 0 && status !== Image.Error
                source: root.thumbnailSource
                sourceSize: Qt.size(320, 180)
                fillMode: Image.PreserveAspectFit
                cache: false
                asynchronous: true
                retainWhileLoading: true
                onStatusChanged: {
                    if (status === Image.Loading)
                        root.thumbnailRequestInFlight = true
                    else if (root.thumbnailRequestInFlight)
                        root.thumbnailRequestFinished()
                }
            }
            NText {
                id: bubbleText
                Layout.fillWidth: true
                font.pixelSize: Theme.fontSmall
                wrapMode: Text.Wrap
                maximumLineCount: 4
                text: {
                    const time = player.formatTime(root.hoveredTimeMs)
                    return root.hoveredCue ? time + "\n" + root.hoveredCue.text : time
                }
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
        onEntered: if (player.hasVideo && root.thumbnailPreviewEnabled) root.requestThumbnail(root.hoveredTimeMs)
        onExited: {
            root.pendingThumbnailSecond = -1
            root.pendingThumbnailTimeMs = -1
            thumbnailRequestTimer.stop()
        }
        onPositionChanged: (e) => {
            if (pressed) root.dragPosition = posAt(e.x)
            if (containsMouse && player.hasVideo && root.thumbnailPreviewEnabled)
                root.requestThumbnail(root.hoveredTimeMs)
        }
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
