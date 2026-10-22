import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

// Figma's Home screen: resume local videos, replay indexed music, and reopen
// folders without leaving the playback window.
Rectangle {
    id: root
    objectName: "home-screen"
    color: Theme.window
    property int contentRevision: 0
    property string searchText: ""
    property bool sortByName: false
    property bool compactCards: false
    function videoCardWidth() {
        return compactCards ? 190 : Math.min(320, Math.max(220, (pageScroll.availableWidth - 72) / 4))
    }
    function musicCardWidth() {
        return compactCards ? 110 : Math.min(200, Math.max(130, pageScroll.availableWidth * 0.117))
    }
    function folderCardWidth() {
        return Math.min(220, Math.max(150, pageScroll.availableWidth * 0.12))
    }
    property var videoItems: []
    property var musicItems: []
    property var folderItems: []

    function refreshContent() {
        contentRevision++
        const supportedVideo = ["mkv", "mp4", "avi", "mov", "webm", "m4v", "wmv", "flv", "ts", "m2ts", "mpg", "mpeg", "3gp", "ogv"]
        let videos = []
        const recents = player.recentMedia()
        for (let i = 0; i < recents.length && videos.length < 8; ++i) {
            const url = recents[i]
            const path = platform.localPath(url)
            if (!path.length) continue
            const name = path.split("/").pop()
            const dot = name.lastIndexOf(".")
            const extension = dot >= 0 ? name.slice(dot + 1).toLowerCase() : ""
            if (supportedVideo.indexOf(extension) < 0) continue
            const resume = player.resumePointFor(url)
            const duration = player.resumeDurationFor(url)
            videos.push({ url: url, path: path, title: decodeURIComponent(name), point: resume,
                          duration: duration, progress: duration > 0 ? Math.min(1, resume / duration) : 0 })
        }
        if (sortByName) videos.sort((a, b) => a.title.localeCompare(b.title))
        if (searchText.trim().length)
            videos = videos.filter(item => item.title.toLowerCase().includes(searchText.trim().toLowerCase()))
        videoItems = videos

        if (mediaLibrary.model.view !== "tracks") mediaLibrary.model.view = "tracks"
        let tracks = []
        for (let j = 0; j < mediaLibrary.model.itemCount() && tracks.length < 8; ++j) {
            const item = mediaLibrary.model.itemAt(j)
            if (item.kind === "audio" && !item.isGroup)
                tracks.push(item)
        }
        if (sortByName) tracks.sort((a, b) => a.title.localeCompare(b.title))
        if (searchText.trim().length)
            tracks = tracks.filter(item => [item.title, item.artist, item.album, item.genre, item.path]
                .join(" ").toLowerCase().includes(searchText.trim().toLowerCase()))
        musicItems = tracks
        let folders = mediaLibrary.roots.map(path => ({ path: path, title: path.split("/").filter(Boolean).pop() || path }))
        if (sortByName) folders.sort((a, b) => a.title.localeCompare(b.title))
        if (searchText.trim().length)
            folders = folders.filter(item => item.title.toLowerCase().includes(searchText.trim().toLowerCase()))
        folderItems = folders.slice(0, 8)
    }
    function videoThumbnailReady(index) {
        const card = videoRepeater.itemAt(index)
        return !!card && card.thumbnailReady
    }

    Component.onCompleted: refreshContent()
    onVisibleChanged: if (visible) refreshContent()
    Connections {
        target: player
        function onRecentMediaChanged() { root.refreshContent() }
        function onStateChanged() { root.refreshContent() }
    }
    Connections {
        target: mediaLibrary
        function onRootsChanged() { root.refreshContent() }
        function onIndexedCountChanged() { root.refreshContent() }
    }

    ScrollView {
        id: pageScroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ColumnLayout {
            width: pageScroll.availableWidth
            spacing: 0

            RowLayout {
                objectName: "home-toolbar"
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.preferredHeight: Math.max(46, Math.round(win.width * 0.034))
                spacing: 12
                NText { text: "Home"; font.pixelSize: 13; Layout.fillWidth: true }
                NText { text: mediaLibrary.indexedCount + " items"; dim: true; font.pixelSize: 11 }
                IconButton { objectName: "home-sort"; icon: "sort"; tip: root.sortByName ? "Sort by recent" : "Sort by name"; onClicked: { root.sortByName = !root.sortByName; root.refreshContent() } }
                IconButton { objectName: "home-view"; icon: "view"; tip: root.compactCards ? "Use comfortable cards" : "Use compact cards"; checked: root.compactCards; onClicked: root.compactCards = !root.compactCards }
                NField {
                    objectName: "home-search"
                    Layout.preferredWidth: Math.min(230, pageScroll.availableWidth * 0.22)
                    placeholderText: "Search"
                    text: root.searchText
                    onTextEdited: { root.searchText = text; root.refreshContent() }
                }
                IconButton { icon: "more"; tip: "More options" }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.bottomMargin: 28
                spacing: 100
                Layout.topMargin: Math.max(36, Math.round(win.width * 0.0245))

                component ShelfTitle: RowLayout {
                    property string title
                    property string page
                    Layout.fillWidth: true
                    NText { text: parent.title; font.pixelSize: 15; font.weight: Font.Medium; Layout.fillWidth: true }
                    IconButton {
                        icon: "chevron-right"
                        tip: "Open " + parent.title
                        onClicked: {
                            if (parent.page === "music") win.navigate("music")
                            else if (parent.page === "videos") win.navigate("videos")
                            else win.navigate("folder")
                        }
                    }
                }

                ColumnLayout {
                    objectName: "home-continue-shelf"
                    visible: root.videoItems.length > 0
                    Layout.fillWidth: true
                    spacing: 9
                    ShelfTitle { title: "Continue Watching"; page: "videos" }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.compactCards ? 174 : Math.max(174, root.videoCardWidth() * 0.56 + 36)
                        contentWidth: videoCards.width
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        Row {
                            id: videoCards
                            spacing: 14
                            Repeater {
                                id: videoRepeater
                                model: root.videoItems
                                delegate: Item {
                                    objectName: "home-video-card-" + index
                                    required property int index
                                    required property var modelData
                                    readonly property bool thumbnailReady: videoThumbnail.status === Image.Ready
                                    width: root.videoCardWidth()
                                    height: root.compactCards ? 174 : Math.max(174, width * 0.56 + 36)
                                    Rectangle {
                                        id: thumbnailFrame
                                        width: parent.width
                                        height: width * 0.56
                                        radius: 7
                                        color: Theme.raised
                                        clip: true
                                        Image {
                                            id: videoThumbnail
                                            anchors.fill: parent
                                            source: "image://thumbnail/frame?path=" + encodeURIComponent(modelData.path)
                                                   + "&t=" + Math.floor(modelData.point / 1000)
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: true
                                            visible: status === Image.Ready
                                        }
                                        Icon { anchors.centerIn: parent; name: "film"; size: 27; color: Theme.icon; visible: videoThumbnail.status !== Image.Ready }
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 3
                                            color: Theme.bar
                                            Rectangle { width: parent.width * modelData.progress; height: parent.height; color: Theme.accent }
                                        }
                                        MouseArea {
                                            objectName: "home-video-card-play-" + index
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                win.navigationPage = "player"
                                                player.openLocation(modelData.url, true)
                                                if (modelData.point > 0) player.jumpTo(modelData.point)
                                            }
                                        }
                                    }
                                    NText {
                                        anchors.top: thumbnailFrame.bottom
                                        anchors.topMargin: 6
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        text: modelData.title
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    objectName: "home-listen-shelf"
                    visible: root.musicItems.length > 0
                    Layout.fillWidth: true
                    spacing: 9
                    ShelfTitle { title: "Listen Again"; page: "music" }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.musicCardWidth() + 48
                        contentWidth: musicCards.width
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        Row {
                            id: musicCards
                            spacing: 14
                            Repeater {
                                model: root.musicItems
                                delegate: Item {
                                    objectName: "home-music-card-" + index
                                    required property int index
                                    required property var modelData
                                    width: root.musicCardWidth()
                                    height: root.musicCardWidth() + 48
                                    Rectangle {
                                        id: coverFrame
                                        width: parent.width
                                        height: parent.width
                                        radius: 7
                                        color: Theme.raised
                                        clip: true
                                        Image {
                                            id: musicCover
                                            anchors.fill: parent
                                            source: modelData.artwork.length ? platform.fileUrl(modelData.artwork) : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            visible: status === Image.Ready
                                        }
                                        Icon { anchors.centerIn: parent; name: "music"; size: 25; color: Theme.icon; visible: musicCover.status !== Image.Ready }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: player.openUrls([platform.fileUrl(modelData.path)], true)
                                        }
                                    }
                                    NText {
                                        anchors.top: coverFrame.bottom
                                        anchors.topMargin: 6
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        text: modelData.title
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                    NText {
                                        anchors.top: coverFrame.bottom
                                        anchors.topMargin: 23
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        text: modelData.artist
                                        font.pixelSize: 10
                                        dim: true
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    objectName: "home-folder-shelf"
                    visible: root.folderItems.length > 0
                    Layout.fillWidth: true
                    spacing: 9
                    ShelfTitle { title: "Frequently Visited Folders"; page: "folders" }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.folderCardWidth() * 0.84 + 20
                        contentWidth: folderCards.width
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        Row {
                            id: folderCards
                            spacing: 14
                            Repeater {
                                model: root.folderItems
                                delegate: Rectangle {
                                    objectName: "home-folder-card-" + index
                                    required property int index
                                    required property var modelData
                                    width: root.folderCardWidth()
                                    height: width * 0.84
                                    radius: 7
                                    color: Theme.panel
                                    border.width: 1
                                    border.color: Theme.border
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 8
                                        Icon { name: "folder"; size: 25; color: Theme.icon }
                                        NText { text: modelData.title; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            libraryPanel.folder = platform.fileUrl(modelData.path)
                                            win.navigate("folder")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 180
                    visible: !root.videoItems.length && !root.musicItems.length && !root.folderItems.length
                    NText { anchors.centerIn: parent; text: "Add a media folder to build your library"; dim: true }
                }
            }
        }
    }
}
