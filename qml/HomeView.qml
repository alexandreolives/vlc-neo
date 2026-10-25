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
    property alias miniPlayerItem: homeMiniPlayer
    property alias miniPlayerOverlay: homeMiniPlayerHoverOverlay
    property alias miniPlayerHovered: miniPlayerHover.hovered
    property alias miniPlayerExpandButton: homeMiniPlayerExpandButton
    property alias miniPlayerTransportControls: homeMiniPlayerTransportControls
    property alias miniPlayerQueueButton: homeMiniPlayerQueueButton
    property Item miniPlayerDockParent: null
    property real savedMiniPlayerDragOffsetX: 0
    property real savedMiniPlayerDragOffsetY: 0
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
        return compactCards ? 190 : Math.min(316, Math.max(220, (pageScroll.availableWidth - 72) / 4))
    }
    function musicCardWidth() {
        return compactCards ? 110 : Math.min(198, Math.max(130, pageScroll.availableWidth * 0.116))
    }
    function folderCardWidth() {
        return Math.min(200, Math.max(150, pageScroll.availableWidth * 0.12))
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
    function activateFrequentArtist(item) {
        win.navigate("music")
        mediaLibrary.model.view = "artists"
        mediaLibrary.model.search = item.artist
    }
    function activateVisitedFolder(item) { win.openFolderSidePanel(item.path) }
    function activateRecentPlaylist(index) {
        win.navigate("player")
        win.openPlaylist(platform.fileUrl(playlistItems[index].filePath))
    }
    property var videoItems: []
    property var musicItems: []
    property var artistItems: []
    property var folderItems: []
    property var playlistItems: []

    function artistListenStats() {
        try { return JSON.parse(Theme.store.homeArtistListenCountsJson || "{}") }
        catch (error) { return ({}) }
    }
    function recordArtistListen(artistName, mediaUrl) {
        const artist = String(artistName || "").trim()
        const url = String(mediaUrl || "")
        if (!artist.length || !url.length || Theme.homeLastArtistMediaUrl === url)
            return
        const stats = artistListenStats()
        const entry = stats[artist] || { count: 0, last: 0 }
        stats[artist] = { count: Math.min(1000000, Number(entry.count) + 1 || 1), last: Date.now() }
        const artists = Object.keys(stats).sort((a, b) => Number(stats[b].last) - Number(stats[a].last))
        for (const staleArtist of artists.slice(100)) delete stats[staleArtist]
        Theme.store.homeArtistListenCountsJson = JSON.stringify(stats)
        Theme.homeLastArtistMediaUrl = url
        refreshArtistItems()
    }
    function recordCurrentArtistListen() {
        if (!player.playing || player.hasVideo) return
        recordArtistListen(player.artist, player.mediaUrl.toString())
    }
    function refreshArtistItems() {
        const byArtist = ({})
        for (const item of musicItems) {
            const artist = String(item.artist || "").trim()
            if (!artist.length || byArtist[artist]) continue
            byArtist[artist] = { artist: artist, path: item.path, artwork: item.artwork }
        }
        const stats = artistListenStats()
        const artists = Object.keys(byArtist).map(name => byArtist[name])
        artists.sort((a, b) => {
            const left = stats[a.artist] || { count: 0, last: 0 }
            const right = stats[b.artist] || { count: 0, last: 0 }
            return Number(right.count) - Number(left.count)
                    || Number(right.last) - Number(left.last)
                    || a.artist.localeCompare(b.artist)
        })
        artistItems = artists
    }

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
        refreshArtistItems()
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
        function onRecentMediaChanged() { if (root.visible) root.refreshContent() }
        function onStateChanged() {
            if (player.playing) root.recordCurrentArtistListen()
            else Theme.homeLastArtistMediaUrl = ""
            if (root.visible) root.refreshContent()
        }
        function onMediaChanged() {
            root.recordCurrentArtistListen()
            if (root.visible) root.refreshContent()
        }
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
        function onRootsChanged() { if (root.visible) root.refreshContent() }
        function onIndexedCountChanged() { if (root.visible) root.refreshContent() }
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
                    IconButton { objectName: "home-sidepanel-back"; icon: "arrow-left"; iconSize: root.sidePanel ? 24 : 18; iconOffsetX: root.sidePanel ? -4 : 0; tip: "Back"; enabled: !root.sidePanel || libraryPanel.canGoBackFromSidePanel(); onClicked: libraryPanel.goBackFromSidePanel() }
                    IconButton { objectName: "home-sidepanel-forward"; icon: "arrow-right"; iconSize: root.sidePanel ? 24 : 18; iconOffsetX: root.sidePanel ? -4 : 0; tip: "Forward"; enabled: root.sidePanel && libraryPanel.canGoForwardFromSidePanel(); onClicked: libraryPanel.goForwardFromSidePanel() }
                    NText { text: "Home"; font.pixelSize: root.sidePanel ? 14 : 12; color: root.sidePanel ? Theme.librarySideTitle : Theme.text; Layout.leftMargin: root.sidePanel ? 3 : 0; Layout.fillWidth: true }
                    IconButton {
                        id: homeSideMoreButton
                        objectName: root.sidePanel ? "home-sidepanel-more-button" : "home-non-side-more-button"
                        icon: "more"
                        tip: "More options"
                        onClicked: win.openSidePanelActions(homeSideMoreButton)
                    }
                    IconButton { objectName: root.sidePanel ? "home-sidepanel-open-full-page" : "home-open-full-page"; icon: "open"; tip: "Open full page"; onClicked: win.navigate("folder") }
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
                    Layout.topMargin: root.sidePanel ? 20 : 18
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
                    Layout.topMargin: root.sidePanel ? 28 : 18
                    Layout.bottomMargin: root.sidePanel ? 15 : 7
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
                    Layout.bottomMargin: root.sidePanel ? 13 : 7
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
                    Layout.topMargin: root.sidePanel ? 26 : 18
                    Layout.bottomMargin: root.sidePanel ? 11 : 7
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
                RowLayout {
                    visible: root.artistItems.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: root.sidePanel ? 20 : 16
                    Layout.rightMargin: 18
                    Layout.topMargin: root.sidePanel ? 28 : 18
                    Layout.bottomMargin: root.sidePanel ? 13 : 7
                    NText {
                        text: "Frequently Listened Artists"
                        font.pixelSize: root.sidePanel ? 14 : 12
                        color: root.sidePanel ? Theme.librarySideText : Theme.text
                        Layout.fillWidth: true
                    }
                    IconButton {
                        objectName: "home-side-see-all-artists"
                        visible: root.sidePanel
                        icon: "chevron-right"
                        iconSize: 13
                        tip: "See all artists"
                        onClicked: {
                            win.navigate("music")
                            mediaLibrary.model.view = "artists"
                            mediaLibrary.model.search = ""
                        }
                    }
                }
                Repeater {
                    model: root.artistItems.slice(0, root.sidePanel ? 3 : 6)
                    delegate: Item {
                        required property int index
                        required property var modelData
                        objectName: (root.sidePanel ? "home-side-artist-" : "home-main-artist-") + index
                        Layout.fillWidth: true
                        Layout.leftMargin: root.sidePanel ? 26 : 16
                        Layout.rightMargin: 12
                        Layout.preferredHeight: root.sidePanel ? 42 : 34
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.artist + ", artist"
                        Accessible.focusable: true
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                                root.activateFrequentArtist(modelData)
                                event.accepted = true
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSmall
                            color: artistRowHover.hovered ? Theme.hover : "transparent"
                            border.width: parent.activeFocus ? 1 : 0
                            border.color: Theme.accent
                        }
                        RowLayout {
                            anchors.fill: parent
                            spacing: root.sidePanel ? 11 : 9
                            Icon {
                                name: "artist"
                                size: root.sidePanel ? 20 : 16
                                Layout.preferredWidth: root.sidePanel ? 25 : 20
                                Layout.preferredHeight: root.sidePanel ? 25 : 20
                                color: Theme.icon
                            }
                            NText {
                                text: modelData.artist
                                font.pixelSize: root.sidePanel ? 13 : 11
                                color: root.sidePanel ? Theme.librarySideText : Theme.text
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        HoverHandler { id: artistRowHover }
                        TapHandler { onTapped: { parent.forceActiveFocus(); root.activateFrequentArtist(modelData) } }
                    }
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
                IconButton {
                    objectName: "home-fullpage-back"
                    icon: "arrow-left"
                    iconSize: 24
                    iconOffsetX: -2
                    tip: "Back"
                    enabled: win.canGoBack
                    onClicked: win.goBack()
                }
                IconButton {
                    objectName: "home-fullpage-forward"
                    icon: "arrow-right"
                    iconSize: 24
                    iconOffsetX: -2
                    tip: "Forward"
                    enabled: win.canGoForward
                    onClicked: win.goForward()
                }
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
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                Layout.bottomMargin: 28
                spacing: root.compactCards ? 100 : 75
                Layout.topMargin: Math.max(38, Math.round(win.width * 0.019))

                component ShelfTitle: RowLayout {
                    property string title
                    property string page
                    Layout.fillWidth: true
                    NText { text: parent.title; font.pixelSize: 15; font.weight: Font.Medium }
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
                    spacing: root.compactCards ? 9 : 22
                    ShelfTitle { title: "Continue Watching"; page: "videos" }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.compactCards ? 174 : Math.max(174, root.videoCardWidth() * 0.56 + 34)
                        contentWidth: videoCards.width
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        Row {
                            id: videoCards
                            spacing: root.compactCards ? 14 : 19
                            Repeater {
                                id: videoRepeater
                                model: root.videoItems
                                delegate: Item {
                                    objectName: "home-video-card-" + index
                                    required property int index
                                    required property var modelData
                                    readonly property bool thumbnailReady: videoThumbnail.status === Image.Ready
                                    width: root.videoCardWidth()
                                    height: root.compactCards ? 174 : Math.max(174, width * 0.56 + 34)
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
                                            objectName: (root.sidePanel ? "side-home-video-card-play-" : "home-video-card-play-") + index
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
                                        anchors.topMargin: root.compactCards ? 6 : 20
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
                    spacing: root.compactCards ? 9 : 22
                    Layout.bottomMargin: root.compactCards ? 0 : 6
                    ShelfTitle { title: "Listen Again"; page: "music" }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.musicCardWidth() + (root.compactCards ? 48 : 60)
                        contentWidth: musicCards.width
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        Row {
                            id: musicCards
                            spacing: root.compactCards ? 14 : 20
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
                                        anchors.topMargin: root.compactCards ? 6 : 22
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        text: modelData.title
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                    NText {
                                        anchors.top: coverFrame.bottom
                                        anchors.topMargin: root.compactCards ? 23 : 48
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
                    spacing: root.compactCards ? 9 : 22
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
                            spacing: 20
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

    FocusScope {
        id: homeMiniPlayer
        parent: root.miniPlayerDockParent ? root.miniPlayerDockParent : root
        objectName: root.sidePanel ? "side-home-mini-player" : "home-mini-player"
        visible: root.visible && !root.sidePanel && player.hasVideo
        activeFocusOnTab: true
        Accessible.name: "Mini player"
        property real dragOffsetX: 0
        property real dragOffsetY: 0
        property bool dragging: false
        readonly property real uiScale: Math.min(1, width / 391)
        readonly property real defaultX: root.miniPlayerDockParent
                                         ? Math.max(0, (parent.width - width) / 2)
                                         : parent.width - width - 16
        readonly property real defaultY: parent.height - height - 16
        x: Math.max(0, Math.min(parent.width - width, defaultX + dragOffsetX))
        y: Math.max(0, Math.min(parent.height - height, defaultY + dragOffsetY))
        width: root.miniPlayerDockParent
               ? Math.min(391, Math.max(0, parent.width),
                          Math.max(0, (parent.height - parent.miniPlayerDockTopInset - 16) * 391 / 339))
               : Math.min(Math.min(391, Math.max(220, root.width * 0.32)), Math.max(0, root.width - 32))
        height: width * 339 / 391
        z: 5
        onParentChanged: {
            if (root.miniPlayerDockParent && parent === root.miniPlayerDockParent) {
                root.savedMiniPlayerDragOffsetX = dragOffsetX
                root.savedMiniPlayerDragOffsetY = dragOffsetY
                dragOffsetX = 0
                dragOffsetY = 0
            } else if (!root.miniPlayerDockParent && parent === root) {
                dragOffsetX = root.savedMiniPlayerDragOffsetX
                dragOffsetY = root.savedMiniPlayerDragOffsetY
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 12 * homeMiniPlayer.uiScale
            color: Theme.bar
            border.color: Theme.border
        }

        HoverHandler { id: miniPlayerHover }

        Item {
            id: homeMiniVideoSurface
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8 * homeMiniPlayer.uiScale
            height: width * 9 / 16
            clip: true

            MouseArea {
                id: homeMiniVideoDrag
                objectName: root.sidePanel ? "side-home-mini-player-video-drag" : "home-mini-player-video-drag"
                anchors.fill: parent
                z: 1
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                property real pressX: 0
                property real pressY: 0
                property real pointerOffsetX: 0
                property real pointerOffsetY: 0
                property bool dragStarted: false
                onPressed: (event) => {
                    pressX = event.x
                    pressY = event.y
                    dragStarted = false
                    const point = mapToItem(homeMiniPlayer.parent, event.x, event.y)
                    pointerOffsetX = point.x - homeMiniPlayer.x
                    pointerOffsetY = point.y - homeMiniPlayer.y
                }
                onPositionChanged: (event) => {
                    if (!pressed || !(event.buttons & Qt.LeftButton)) return
                    if (!dragStarted && Math.abs(event.x - pressX) + Math.abs(event.y - pressY) < 8) return
                    dragStarted = true
                    homeMiniPlayer.dragging = true
                    const point = mapToItem(homeMiniPlayer.parent, event.x, event.y)
                    const maxX = Math.max(0, homeMiniPlayer.parent.width - homeMiniPlayer.width)
                    const maxY = Math.max(0, homeMiniPlayer.parent.height - homeMiniPlayer.height)
                    const xNow = Math.max(0, Math.min(maxX, point.x - pointerOffsetX))
                    const yNow = Math.max(0, Math.min(maxY, point.y - pointerOffsetY))
                    homeMiniPlayer.dragOffsetX = xNow - homeMiniPlayer.defaultX
                    homeMiniPlayer.dragOffsetY = yNow - homeMiniPlayer.defaultY
                }
                onReleased: homeMiniPlayer.dragging = false
                onClicked: (event) => {
                    if (event.button === Qt.RightButton) {
                        const point = homeMiniVideoSurface.mapToItem(keyCatcher, event.x, event.y)
                        contextMenu.popup(point.x, point.y)
                    } else if (!dragStarted) {
                        win.navigate("player")
                    }
                }
            }
        }
        Rectangle {
            anchors.fill: homeMiniVideoSurface
            radius: 6 * homeMiniPlayer.uiScale
            color: "transparent"
            border.width: 2
            border.color: Theme.border
            z: 2
        }
        Rectangle {
            id: homeMiniPlayerHoverOverlay
            objectName: root.sidePanel ? "side-home-mini-player-hover-overlay" : "home-mini-player-hover-overlay"
            anchors.fill: homeMiniVideoSurface
            radius: 6
            color: "#99000000"
            opacity: miniPlayerHover.hovered || homeMiniPlayer.activeFocus ? 1 : 0
            visible: opacity > 0.01
            z: 3
            IconButton {
                objectName: root.sidePanel ? "side-home-mini-player-close" : "home-mini-player-close"
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 12 * homeMiniPlayer.uiScale
                icon: "close"
                iconColor: Theme.text
                iconSize: 22 * homeMiniPlayer.uiScale
                implicitWidth: 30 * homeMiniPlayer.uiScale
                implicitHeight: 30 * homeMiniPlayer.uiScale
                tip: "Stop playback"
                Accessible.name: "Stop playback"
                onClicked: player.stop()
            }
            IconButton {
                id: homeMiniPlayerExpandButton
                objectName: root.sidePanel ? "side-home-mini-player-expand" : "home-mini-player-expand"
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12 * homeMiniPlayer.uiScale
                icon: "open"
                iconColor: Theme.text
                iconSize: 22 * homeMiniPlayer.uiScale
                implicitWidth: 30 * homeMiniPlayer.uiScale
                implicitHeight: 30 * homeMiniPlayer.uiScale
                tip: "Expand player"
                Accessible.name: "Expand player"
                onClicked: win.navigate("player")
            }
            Row {
                id: homeMiniPlayerTransportControls
                anchors.centerIn: parent
                spacing: 42 * homeMiniPlayer.uiScale
                IconButton {
                    objectName: root.sidePanel ? "side-home-mini-player-previous" : "home-mini-player-previous"
                    icon: "previous"
                    iconColor: Theme.text
                    iconSize: 26 * homeMiniPlayer.uiScale
                    implicitWidth: 30 * homeMiniPlayer.uiScale
                    implicitHeight: 30 * homeMiniPlayer.uiScale
                    tip: "Previous"
                    Accessible.name: "Previous"
                    onClicked: win.navigateMiniPlayerTrack(-1)
                }
                IconButton {
                    objectName: root.sidePanel ? "side-home-mini-player-toggle" : "home-mini-player-toggle"
                    icon: player.playing ? "pause" : "play"
                    iconColor: Theme.text
                    iconSize: 32 * homeMiniPlayer.uiScale
                    implicitWidth: 36 * homeMiniPlayer.uiScale
                    implicitHeight: 36 * homeMiniPlayer.uiScale
                    tip: player.playing ? "Pause" : "Play"
                    Accessible.name: player.playing ? "Pause" : "Play"
                    onClicked: player.togglePause()
                }
                IconButton {
                    objectName: root.sidePanel ? "side-home-mini-player-next" : "home-mini-player-next"
                    icon: "next"
                    iconColor: Theme.text
                    iconSize: 26 * homeMiniPlayer.uiScale
                    implicitWidth: 30 * homeMiniPlayer.uiScale
                    implicitHeight: 30 * homeMiniPlayer.uiScale
                    tip: "Next"
                    Accessible.name: "Next"
                    onClicked: win.navigateMiniPlayerTrack(1)
                }
            }
        }

        Rectangle {
            id: homeMiniProgress
            objectName: root.sidePanel ? "side-home-mini-player-progress" : "home-mini-player-progress"
            anchors.left: homeMiniVideoSurface.left
            anchors.right: homeMiniVideoSurface.right
            anchors.top: homeMiniVideoSurface.bottom
            anchors.topMargin: 5 * homeMiniPlayer.uiScale
            height: 16 * homeMiniPlayer.uiScale
            radius: 8 * homeMiniPlayer.uiScale
            color: Theme.field
            border.width: homeMiniPlayerSeek.activeFocus ? 1 : 0
            border.color: Theme.accent
            Rectangle {
                width: parent.width * player.position
                height: parent.height
                radius: parent.radius
                color: Theme.accentDim
            }
            Rectangle {
                width: parent.height
                height: parent.height
                radius: parent.height / 2
                x: Math.max(0, Math.min(parent.width - width, parent.width * player.position - width / 2))
                color: Theme.accent
                visible: miniPlayerHover.hovered
                Behavior on x { NumberAnimation { duration: 100 } }
            }
            MouseArea {
                id: homeMiniPlayerSeek
                objectName: root.sidePanel ? "side-home-mini-player-seek" : "home-mini-player-seek"
                anchors.fill: parent
                z: 1
                activeFocusOnTab: true
                Accessible.name: "Seek position"
                Accessible.role: Accessible.Slider
                onPressed: (mouse) => player.seek(Math.max(0, Math.min(1, mouse.x / width)))
                onPositionChanged: (mouse) => { if (pressed) player.seek(Math.max(0, Math.min(1, mouse.x / width))) }
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Left) player.seekBy(-5000)
                    else if (event.key === Qt.Key_Right) player.seekBy(5000)
                    else if (event.key === Qt.Key_Home) player.seek(0)
                    else if (event.key === Qt.Key_End) player.seek(0.99)
                    else return
                    event.accepted = true
                }
            }
        }
        NText {
            objectName: root.sidePanel ? "side-home-mini-player-title" : "home-mini-player-title"
            MouseArea {
                id: homeMiniPlayerTitleDrag
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real pressX: 0
                property real pressY: 0
                property real pointerOffsetX: 0
                property real pointerOffsetY: 0
                property bool dragStarted: false
                onPressed: (mouse) => {
                    pressX = mouse.x
                    pressY = mouse.y
                    dragStarted = false
                    const point = mapToItem(homeMiniPlayer.parent, mouse.x, mouse.y)
                    pointerOffsetX = point.x - homeMiniPlayer.x
                    pointerOffsetY = point.y - homeMiniPlayer.y
                }
                onPositionChanged: (mouse) => {
                    if (!pressed) return
                    if (!dragStarted && Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) < 8) return
                    dragStarted = true
                    homeMiniPlayer.dragging = true
                    const point = mapToItem(homeMiniPlayer.parent, mouse.x, mouse.y)
                    const maxX = Math.max(0, homeMiniPlayer.parent.width - homeMiniPlayer.width)
                    const maxY = Math.max(0, homeMiniPlayer.parent.height - homeMiniPlayer.height)
                    const xNow = Math.max(0, Math.min(maxX, point.x - pointerOffsetX))
                    const yNow = Math.max(0, Math.min(maxY, point.y - pointerOffsetY))
                    homeMiniPlayer.dragOffsetX = xNow - homeMiniPlayer.defaultX
                    homeMiniPlayer.dragOffsetY = yNow - homeMiniPlayer.defaultY
                }
                onReleased: homeMiniPlayer.dragging = false
                onCanceled: homeMiniPlayer.dragging = false
            }
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16 * homeMiniPlayer.uiScale
            anchors.rightMargin: 16 * homeMiniPlayer.uiScale
            anchors.top: homeMiniVideoSurface.bottom
            anchors.topMargin: 45 * homeMiniPlayer.uiScale
            text: player.title.length ? player.title : "Now playing"
            font.pixelSize: 18 * homeMiniPlayer.uiScale
            elide: Text.ElideRight
        }
        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 16 * homeMiniPlayer.uiScale
            anchors.rightMargin: 16 * homeMiniPlayer.uiScale
            anchors.bottomMargin: 16 * homeMiniPlayer.uiScale
            spacing: 10 * homeMiniPlayer.uiScale
            Icon { name: "folder"; size: 20 * homeMiniPlayer.uiScale; color: Theme.textDim }
            NText { text: player.folderName; dim: true; font.pixelSize: 14 * homeMiniPlayer.uiScale; Layout.maximumWidth: 70 * homeMiniPlayer.uiScale; elide: Text.ElideRight }
            Icon { visible: player.artist.length > 0; name: "artist"; size: 20 * homeMiniPlayer.uiScale; color: Theme.textDim }
            NText { visible: player.artist.length > 0; text: player.artist; dim: true; font.pixelSize: 14 * homeMiniPlayer.uiScale; Layout.fillWidth: true; elide: Text.ElideRight }
            Item { Layout.fillWidth: true; visible: player.artist.length === 0 }
            IconButton {
                id: homeMiniPlayerQueueButton
                objectName: root.sidePanel ? "side-home-mini-player-queue" : "home-mini-player-queue"
                icon: "list"
                colorAnimationEnabled: false
                tip: "Show queue"
                Accessible.name: "Show queue"
                iconSize: 18 * homeMiniPlayer.uiScale
                implicitWidth: 30 * homeMiniPlayer.uiScale
                implicitHeight: 30 * homeMiniPlayer.uiScale
                onClicked: win.togglePanel("queue")
            }
        }
    }
}
