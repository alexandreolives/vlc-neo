import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Neo 1.0

// Figma's Home screen: resume local videos, replay indexed music, and reopen
// folders without leaving the playback window.
Rectangle {
    id: root
    objectName: "home-screen"
    color: root.sidePanel ? Theme.librarySidePanel : Theme.window
    property alias miniVideoHost: homeMiniVideoSurface
    property int contentRevision: 0
    property string searchText: ""
    property bool sortByName: false
    property bool compactCards: false
    property bool sidePanel: false
    property bool searchOpen: false
    property bool foldersExpanded: false
    signal indexFolder()
    signal createPlaylist()
    function videoCardWidth() {
        return compactCards ? 190 : Math.min(320, Math.max(220, (pageScroll.availableWidth - 72) / 4))
    }
    function musicCardWidth() {
        return compactCards ? 110 : Math.min(200, Math.max(130, pageScroll.availableWidth * 0.117))
    }
    function folderCardWidth() {
        return Math.min(220, Math.max(150, pageScroll.availableWidth * 0.12))
    }
    function activateRecentVideo(item) {
        win.navigate("player")
        player.openLocation(item.url, true)
        if (item.point > 0) player.jumpTo(item.point)
    }
    function activateRecentMusic(item) {
        win.navigate("player")
        player.openUrls([platform.fileUrl(item.path)], true)
    }
    function activateVisitedFolder(item) { win.openFolderSidePanel(item.path) }
    function activateRecentPlaylist(index) {
        win.navigate("player")
        win.openPlaylist(platform.fileUrl(playlistItems[index].filePath))
    }
    property var videoItems: []
    property var musicItems: []
    property var folderItems: []
    property var playlistItems: []

    function visitStats(kind, path) {
        const property = kind === "playlist" ? "homePlaylistVisitCountsJson" : "homeFolderVisitCountsJson"
        try { return JSON.parse(Theme.store[property] || "{}")[path] || { count: 0, last: 0 } }
        catch (error) { return { count: 0, last: 0 } }
    }
    function visitOrder(kind, a, b) {
        const left = visitStats(kind, a)
        const right = visitStats(kind, b)
        return right.count - left.count || right.last - left.last
    }
    function playlistLabel(name) { return name.replace(/\.(m3u8?|pls|xspf)$/i, "") }
    function frequentFolders() {
        let folders = mediaLibrary.roots.map(path => ({ path: path, title: path.split("/").filter(Boolean).pop() || path }))
        folders.sort((a, b) => visitOrder("folder", a.path, b.path) || a.title.localeCompare(b.title))
        if (sortByName) folders.sort((a, b) => a.title.localeCompare(b.title))
        if (searchText.trim().length)
            folders = folders.filter(item => item.title.toLowerCase().includes(searchText.trim().toLowerCase()))
        return folders
    }
    function frequentPlaylists() {
        let playlists = []
        for (let index = 0; index < homePlaylists.count; ++index)
            playlists.push({ fileName: homePlaylists.get(index, "fileName"), filePath: homePlaylists.get(index, "filePath") })
        playlists.sort((a, b) => visitOrder("playlist", a.filePath, b.filePath)
                       || playlistLabel(a.fileName).localeCompare(playlistLabel(b.fileName)))
        if (sortByName) playlists.sort((a, b) => playlistLabel(a.fileName).localeCompare(playlistLabel(b.fileName)))
        return playlists
    }
    function refreshFrequentVisits() {
        folderItems = frequentFolders()
        playlistItems = frequentPlaylists()
    }

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
        refreshFrequentVisits()
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
    FolderListModel {
        id: homePlaylists
        folder: platform.fileUrl(platform.playlistLibraryDirectory())
        nameFilters: ["*.m3u", "*.m3u8", "*.pls", "*.xspf"]
        showDirs: false
        showDotAndDotDot: false
        caseSensitive: false
        onCountChanged: root.playlistItems = root.frequentPlaylists()
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

            ColumnLayout {
                visible: root.sidePanel
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.sidePanel ? 20 : 12
                    Layout.rightMargin: root.sidePanel ? 17 : 8
                    Layout.preferredHeight: root.sidePanel ? 52 : 36
                    spacing: 3
                    IconButton { icon: "arrow-left"; iconSize: root.sidePanel ? 24 : 18; iconOffsetX: root.sidePanel ? -4 : 0; tip: "Back"; onClicked: win.goBack() }
                    IconButton { icon: "arrow-right"; iconSize: root.sidePanel ? 24 : 18; iconOffsetX: root.sidePanel ? -4 : 0; tip: "Forward"; enabled: false }
                    NText { text: "Home"; font.pixelSize: root.sidePanel ? 14 : 12; color: root.sidePanel ? Theme.librarySideTitle : Theme.text; Layout.leftMargin: root.sidePanel ? 3 : 0; Layout.fillWidth: true }
                    IconButton {
                        id: homeSideMoreButton
                        objectName: root.sidePanel ? "home-sidepanel-more-button" : "home-non-side-more-button"
                        icon: "more"
                        tip: "More options"
                        onClicked: win.openSidePanelActions(homeSideMoreButton)
                    }
                    IconButton { icon: "open"; tip: "Open full page"; onClicked: win.navigate("home") }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; visible: !root.sidePanel }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.sidePanel ? 20 : 12
                    Layout.rightMargin: root.sidePanel ? 17 : 8
                    Layout.preferredHeight: root.sidePanel ? 52 : 34
                    NText { visible: !root.searchOpen; text: mediaLibrary.indexedCount + " items"; color: root.sidePanel ? Theme.librarySideText : Theme.textDim; font.pixelSize: 12; Layout.fillWidth: true }
                    NField {
                        visible: root.searchOpen
                        Layout.fillWidth: true
                        placeholderText: "Search"
                        text: root.searchText
                        onTextEdited: { root.searchText = text; root.refreshContent() }
                    }
                    IconButton { icon: "sort"; tip: "Sort"; onClicked: { root.sortByName = !root.sortByName; root.refreshContent() } }
                    IconButton { icon: "list"; tip: "Toggle compact view"; checked: root.compactCards; onClicked: root.compactCards = !root.compactCards }
                    IconButton { icon: root.searchOpen ? "close" : "search"; tip: root.searchOpen ? "Close search" : "Search"; onClicked: { root.searchOpen = !root.searchOpen; if (!root.searchOpen) { root.searchText = ""; root.refreshContent() } } }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; visible: root.sidePanel }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.sidePanel ? 20 : 16
                    Layout.rightMargin: 18
                    Layout.topMargin: root.sidePanel ? 21 : 18
                    Layout.bottomMargin: root.sidePanel ? 11 : 7
                    NText {
                        text: "Continue Watching"
                        font.pixelSize: root.sidePanel ? 14 : 12
                        color: root.sidePanel ? Theme.librarySideText : Theme.text
                        Layout.fillWidth: true
                    }
                    IconButton {
                        objectName: "home-side-see-all-videos"
                        visible: root.sidePanel
                        icon: "chevron-right"
                        iconSize: 13
                        tip: "See all videos"
                        onClicked: win.navigateFromRail("videos")
                    }
                }
                Repeater {
                    model: root.videoItems.slice(0, root.sidePanel ? 3 : 6)
                    delegate: Item {
                        required property int index
                        required property var modelData
                        objectName: (root.sidePanel ? "home-side-video-" : "home-main-video-") + index
                        Layout.fillWidth: true
                        Layout.leftMargin: root.sidePanel ? 22 : 16
                        Layout.rightMargin: 12
                        Layout.preferredHeight: 42
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.title + ", continue watching"
                        Accessible.focusable: true
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                                root.activateRecentVideo(modelData)
                                event.accepted = true
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSmall
                            color: videoRowHover.hovered ? Theme.hover : "transparent"
                            border.width: parent.activeFocus ? 1 : 0
                            border.color: Theme.accent
                        }
                        RowLayout {
                            anchors.fill: parent
                            spacing: 9
                            Rectangle {
                                width: 32; height: 32; radius: 3; color: Theme.raised; clip: true
                                Image {
                                    anchors.fill: parent
                                    source: "image://thumbnail/frame?path=" + encodeURIComponent(modelData.path)
                                           + "&t=" + Math.floor(modelData.point / 1000)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Rectangle {
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                    height: 2; color: Theme.bar
                                    Rectangle { width: parent.width * modelData.progress; height: parent.height; color: Theme.accent }
                                }
                            }
                            NText { text: modelData.title; font.pixelSize: root.sidePanel ? 13 : 11; color: root.sidePanel ? Theme.librarySideText : Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        HoverHandler { id: videoRowHover }
                        TapHandler { onTapped: { parent.forceActiveFocus(); root.activateRecentVideo(modelData) } }
                    }
                }
                NText {
                    visible: root.videoItems.length === 0
                    text: "No recent videos"
                    color: root.sidePanel ? Theme.librarySideText : Theme.textDim
                    font.pixelSize: root.sidePanel ? 12 : 10
                    Layout.leftMargin: root.sidePanel ? 20 : 16
                    Layout.bottomMargin: 4
                }
                NButton {
                    visible: root.videoItems.length === 0
                    text: "Browse videos"
                    icon: "videos"
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    onClicked: win.navigateFromRail("videos")
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.sidePanel ? 20 : 16
                    Layout.rightMargin: 18
                    Layout.topMargin: root.sidePanel ? 25 : 18
                    Layout.bottomMargin: root.sidePanel ? 16 : 7
                    NText {
                        text: "Listen Again"
                        font.pixelSize: root.sidePanel ? 14 : 12
                        color: root.sidePanel ? Theme.librarySideText : Theme.text
                        Layout.fillWidth: true
                    }
                    IconButton {
                        objectName: "home-side-see-all-music"
                        visible: root.sidePanel
                        icon: "chevron-right"
                        iconSize: 13
                        tip: "See all music"
                        onClicked: win.navigateFromRail("music")
                    }
                }
                Repeater {
                    model: root.musicItems.slice(0, root.sidePanel ? 3 : 6)
                    delegate: Item {
                        required property int index
                        required property var modelData
                        objectName: (root.sidePanel ? "home-side-music-" : "home-main-music-") + index
                        Layout.fillWidth: true
                        Layout.leftMargin: root.sidePanel ? 22 : 16
                        Layout.rightMargin: 12
                        Layout.preferredHeight: 42
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.title + (modelData.artist.length ? " by " + modelData.artist : "")
                        Accessible.focusable: true
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                                root.activateRecentMusic(modelData)
                                event.accepted = true
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSmall
                            color: musicRowHover.hovered ? Theme.hover : "transparent"
                            border.width: parent.activeFocus ? 1 : 0
                            border.color: Theme.accent
                        }
                        RowLayout {
                            anchors.fill: parent
                            spacing: 9
                            Rectangle {
                                width: 32; height: 32; radius: 3; color: Theme.raised; clip: true
                                Image { id: homeMusicCover; anchors.fill: parent; source: modelData.artwork && modelData.artwork.length ? platform.fileUrl(modelData.artwork) : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                                Icon { anchors.centerIn: parent; name: "music"; size: 16; color: Theme.accent; visible: homeMusicCover.status !== Image.Ready }
                            }
                            NText {
                                text: modelData.title + (modelData.artist.length ? " - " + modelData.artist : "")
                                font.pixelSize: root.sidePanel ? 13 : 11
                                color: root.sidePanel ? Theme.librarySideText : Theme.text
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        HoverHandler { id: musicRowHover }
                        TapHandler { onTapped: { parent.forceActiveFocus(); root.activateRecentMusic(modelData) } }
                    }
                }
                NText {
                    visible: root.musicItems.length === 0
                    text: "No indexed music"
                    color: root.sidePanel ? Theme.librarySideText : Theme.textDim
                    font.pixelSize: root.sidePanel ? 12 : 10
                    Layout.leftMargin: root.sidePanel ? 20 : 16
                    Layout.bottomMargin: 4
                }
                NButton {
                    visible: root.musicItems.length === 0
                    text: "Browse music"
                    icon: "music"
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    onClicked: win.navigateFromRail("music")
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.sidePanel ? 20 : 16
                    Layout.rightMargin: 18
                    Layout.topMargin: root.sidePanel ? 24 : 18
                    Layout.bottomMargin: root.sidePanel ? 12 : 7
                    NText {
                        text: "Frequently Visited Folders"
                        font.pixelSize: root.sidePanel ? 14 : 12
                        color: root.sidePanel ? Theme.librarySideText : Theme.text
                        Layout.fillWidth: true
                    }
                    IconButton {
                        objectName: "home-side-expand-folders"
                        visible: root.sidePanel
                        icon: root.foldersExpanded ? "chevron-down" : "chevron-right"
                        iconSize: 13
                        tip: root.foldersExpanded ? "Show fewer folders" : "Show all folders"
                        onClicked: root.foldersExpanded = !root.foldersExpanded
                    }
                }
                Repeater {
                    model: root.folderItems.slice(0, root.foldersExpanded ? root.folderItems.length : (root.sidePanel ? 3 : 6))
                    delegate: Item {
                        required property int index
                        required property var modelData
                        objectName: (root.sidePanel ? "home-side-folder-" : "home-main-folder-") + index
                        Layout.fillWidth: true
                        Layout.leftMargin: root.sidePanel ? 26 : 16
                        Layout.rightMargin: 12
                        Layout.preferredHeight: root.sidePanel ? 42 : 34
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.title + ", folder"
                        Accessible.focusable: true
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                                root.activateVisitedFolder(modelData)
                                event.accepted = true
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSmall
                            color: folderRowHover.hovered ? Theme.hover : "transparent"
                            border.width: parent.activeFocus ? 1 : 0
                            border.color: Theme.accent
                        }
                        RowLayout {
                            anchors.fill: parent
                            spacing: root.sidePanel ? 11 : 9
                            Icon {
                                name: "folder"
                                size: root.sidePanel ? 25 : 16
                                Layout.preferredWidth: size
                                Layout.preferredHeight: size
                                color: Theme.icon
                            }
                            NText { text: modelData.title; font.pixelSize: root.sidePanel ? 13 : 11; color: root.sidePanel ? Theme.librarySideText : Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        HoverHandler { id: folderRowHover }
                        TapHandler { onTapped: { parent.forceActiveFocus(); root.activateVisitedFolder(modelData) } }
                    }
                }
                NText {
                    visible: root.folderItems.length === 0
                    text: "No indexed folders"
                    color: root.sidePanel ? Theme.librarySideText : Theme.textDim
                    font.pixelSize: root.sidePanel ? 12 : 10
                    Layout.leftMargin: root.sidePanel ? 20 : 16
                    Layout.bottomMargin: 4
                }
                NButton {
                    visible: root.folderItems.length === 0
                    text: "Add a media folder"
                    icon: "folder"
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    onClicked: root.indexFolder()
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.sidePanel ? 20 : 16
                    Layout.rightMargin: 18
                    Layout.topMargin: root.sidePanel ? 24 : 18
                    Layout.bottomMargin: root.sidePanel ? 14 : 7
                    NText {
                        text: "Frequently Visited Playlists"
                        font.pixelSize: root.sidePanel ? 14 : 12
                        color: root.sidePanel ? Theme.librarySideText : Theme.text
                        Layout.fillWidth: true
                    }
                    IconButton {
                        objectName: "home-side-see-all-playlists"
                        visible: root.sidePanel
                        icon: "chevron-right"
                        iconSize: 13
                        tip: "See all playlists"
                        onClicked: win.navigateFromRail("playlist")
                    }
                }
                Repeater {
                    model: Math.min(root.playlistItems.length, root.sidePanel ? 3 : 6)
                    delegate: Item {
                        required property int index
                        objectName: (root.sidePanel ? "home-side-playlist-" : "home-main-playlist-") + index
                        readonly property var playlist: root.playlistItems[index]
                        Layout.fillWidth: true
                        Layout.leftMargin: root.sidePanel ? 24 : 16
                        Layout.rightMargin: 12
                        Layout.preferredHeight: root.sidePanel ? 42 : 34
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: root.playlistLabel(playlist.fileName) + ", playlist"
                        Accessible.focusable: true
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                                root.activateRecentPlaylist(index)
                                event.accepted = true
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSmall
                            color: playlistRowHover.hovered ? Theme.hover : "transparent"
                            border.width: parent.activeFocus ? 1 : 0
                            border.color: Theme.accent
                        }
                        RowLayout {
                            anchors.fill: parent
                            spacing: root.sidePanel ? 13 : 9
                            Icon {
                                name: "playlist"
                                size: root.sidePanel ? 25 : 16
                                Layout.preferredWidth: size
                                Layout.preferredHeight: size
                                color: Theme.icon
                            }
                            NText { text: root.playlistLabel(playlist.fileName); font.pixelSize: root.sidePanel ? 13 : 11; color: root.sidePanel ? Theme.librarySideText : Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        HoverHandler { id: playlistRowHover }
                        TapHandler { onTapped: { parent.forceActiveFocus(); root.activateRecentPlaylist(index) } }
                    }
                }
                NText {
                    visible: root.playlistItems.length === 0
                    text: "No playlists yet"
                    dim: true
                    font.pixelSize: 10
                    Layout.leftMargin: 16
                    Layout.bottomMargin: 4
                }
                NButton {
                    visible: root.playlistItems.length === 0
                    text: "Create playlist"
                    icon: "playlist"
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    onClicked: root.createPlaylist()
                }
            }

            RowLayout {
                objectName: "home-toolbar"
                visible: !root.sidePanel
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.preferredHeight: Math.max(46, Math.round(win.width * 0.034))
                spacing: 12
                NText { text: "Home"; font.pixelSize: 13; Layout.fillWidth: true }
                NText { text: mediaLibrary.indexedCount + " items"; dim: true; font.pixelSize: 11 }
                IconButton { objectName: "home-sort"; icon: "sort"; tip: root.sortByName ? "Sort by recent" : "Sort by name"; onClicked: { root.sortByName = !root.sortByName; root.refreshContent() } }
                IconButton { objectName: "home-view"; icon: root.compactCards ? "list" : "grid"; tip: root.compactCards ? "Use comfortable cards" : "Use compact cards"; checked: root.compactCards; onClicked: root.compactCards = !root.compactCards }
                NField {
                    objectName: "home-search"
                    Layout.preferredWidth: Math.min(230, pageScroll.availableWidth * 0.22)
                    placeholderText: "Search"
                    text: root.searchText
                    onTextEdited: { root.searchText = text; root.refreshContent() }
                }
                IconButton {
                    id: homeFullMoreButton
                    objectName: root.sidePanel ? "home-non-fullpage-more-button" : "home-fullpage-more-button"
                    icon: "more"
                    tip: "More options"
                    onClicked: win.openSidePanelActions(homeFullMoreButton)
                }
            }

            Rectangle { visible: !root.sidePanel; Layout.fillWidth: true; height: 1; color: Theme.border }

            ColumnLayout {
                visible: !root.sidePanel
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
                                                win.navigate("player")
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

    Rectangle {
        id: homeMiniPlayer
        objectName: "home-mini-player"
        visible: root.visible && !root.sidePanel && player.hasVideo
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        width: Math.min(380, Math.max(220, root.width * 0.32))
        height: homeMiniVideoSurface.height + 64
        radius: 10
        color: Theme.bar
        border.color: Theme.border
        z: 5

        HoverHandler { id: miniPlayerHover }

        Item {
            id: homeMiniVideoSurface
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            height: width * 9 / 16
            clip: true

            MouseArea {
                anchors.fill: parent
                z: 1
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (event) => {
                    if (event.button === Qt.RightButton) {
                        const point = homeMiniVideoSurface.mapToItem(keyCatcher, event.x, event.y)
                        contextMenu.popup(point.x, point.y)
                    } else {
                        win.navigate("player")
                    }
                }
            }
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            anchors.bottomMargin: 4
            spacing: 6
            NText {
                text: player.title.length ? player.title : "Now playing"
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            IconButton {
                objectName: "home-mini-player-toggle"
                icon: player.playing ? "pause" : "play"
                tip: player.playing ? "Pause" : "Play"
                onClicked: player.togglePause()
            }
        }
        IconButton {
            objectName: "home-mini-player-return"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 8
            anchors.rightMargin: 8
            z: 2
            visible: miniPlayerHover.hovered
            icon: "maximize"
            iconSize: 15
            tip: "Expand player"
            Accessible.name: "Expand player"
            onClicked: win.navigate("player")
        }
    }
}
