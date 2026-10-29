import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Neo 1.0

Modal {
    id: root
    title: "Add Subtitles"
    width: parent ? Math.min(1048, parent.width - 32) : 1048
    height: parent ? Math.min(800, parent.height - 32) : 800
    bodyMargin: 18

    property string target: "folder"
    property string sourceMode: "computer"
    property string sourcePath: ""
    property string linked: ""
    property string onlineQuery: ""
    property string onlineLanguage: "all"
    property int selectedOnlineFileId: 0
    property string onlineApplyError: ""
    property alias resultList: matchList
    property alias onlineSourceSelector: sourceModeCombo
    property var matches: []
    property var candidateFiles: []
    property var selectedSubtitlePaths: []
    readonly property var targetChoices: [
        { label: "To This File", value: "file" },
        { label: "To This Folder", value: "folder" },
        { label: "To This Playlist", value: "playlist" }
    ]
    readonly property var sourceChoices: [
        { label: "From Computer", value: "computer" },
        { label: "From OpenSubtitles", value: "opensubtitles" }
    ]
    readonly property var onlineLanguages: [
        { label: "Any language", value: "all" }, { label: "English", value: "en" },
        { label: "French", value: "fr" }, { label: "Spanish", value: "es" },
        { label: "German", value: "de" }, { label: "Italian", value: "it" },
        { label: "Portuguese", value: "pt" }, { label: "Japanese", value: "ja" }
    ]

    function expandedPath(path) {
        const value = path.trim()
        if (value === "~") return platform.homePath()
        if (value.startsWith("~/")) return platform.homePath() + value.slice(1)
        return value
    }
    function displaySourcePath() {
        const parts = expandedPath(sourcePath).replace(/\\/g, "/").split("/").filter(Boolean)
        return parts.slice(-4).join(" / ")
    }
    function chooseSource() {
        folderDialog.open()
    }
    function refreshMatches() {
        if (!sourcePath.length) {
            matches = []
            candidateFiles = []
            return
        }
        if (target === "file") {
            candidateFiles = player.subtitleFilesForMedia(platform.fileUrl(expandedPath(sourcePath)))
            matches = []
            return
        }
        candidateFiles = []
        matches = player.subtitleFolderMatches(platform.fileUrl(expandedPath(sourcePath)), target)
    }
    function saveSelection() {
        if (!sourcePath.trim()) return
        if (target === "file") {
            let added = false
            for (const subtitlePath of selectedSubtitlePaths)
                added = player.addSubtitleFile(platform.fileUrl(subtitlePath)) || added
            if (added) root.close()
            return
        }
        const path = expandedPath(sourcePath)
        const folderUrl = platform.fileUrl(path)
        if (target === "playlist") {
            player.linkSubtitleFolderToPlaylist(folderUrl)
            root.linked = path
        } else {
            player.linkSubtitleFolder(folderUrl)
            root.linked = path
        }
        root.close()
    }
    function openOpenSubtitles() {
        onlineApplyError = ""
        onlineQuery = player.title.replace(/\.[^.]+$/, "")
        selectedOnlineFileId = 0
        searchOpenSubtitles()
    }
    function scheduleOnlineSearch() {
        onlineApplyError = ""
        if (visible && sourceMode === "opensubtitles" && onlineQuery.trim().length)
            onlineSearchTimer.restart()
    }
    function searchOpenSubtitles() {
        onlineSearchTimer.stop()
        if (onlineQuery.trim().length)
            openSubtitles.search(onlineQuery, onlineLanguage, player.mediaUrl)
    }
    function toggleSubtitle(path) {
        const updated = selectedSubtitlePaths.slice()
        const index = updated.indexOf(path)
        if (index >= 0) updated.splice(index, 1)
        else updated.push(path)
        selectedSubtitlePaths = updated
    }

    onOpened: {
        linked = player.linkedSubtitleFolder()
        sourcePath = target === "file" ? "" : linked
        selectedSubtitlePaths = []
        sourceMode = "computer"
        onlineQuery = player.title.replace(/\.[^.]+$/, "")
        selectedOnlineFileId = 0
        refreshMatches()
    }
    onTargetChanged: refreshMatches()
    onSourcePathChanged: {
        selectedSubtitlePaths = []
        refreshMatches()
    }
    Timer {
        id: onlineSearchTimer
        interval: 500
        repeat: false
        onTriggered: root.searchOpenSubtitles()
    }
    Connections {
        target: openSubtitles
        function onSubtitleReady(fileUrl) {
            if (!root.visible) return
            if (player.addSubtitleFile(fileUrl)) {
                root.close()
            } else {
                root.onlineApplyError = "VLC could not load the downloaded subtitle file."
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: root.target === "playlist" ? 0 : -6
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            NCombo {
                Layout.preferredWidth: 190
                model: root.targetChoices
                current: root.target
                onPicked: (value) => root.target = value
            }
            NCombo {
                id: sourceModeCombo
                Layout.preferredWidth: 198
                model: root.sourceChoices
                current: root.sourceMode
                onPicked: (value) => {
                    root.sourceMode = value
                    if (value === "opensubtitles") {
                        root.sourceMode = value
                        root.openOpenSubtitles()
                    } else {
                        root.sourceMode = value
                        root.chooseSource()
                    }
                }
            }
            IconButton {
                visible: root.sourceMode === "computer"
                icon: "folder"
                tip: root.target === "file" ? "Choose subtitle file" : "Choose subtitles folder"
                onClicked: root.chooseSource()
            }
            NField {
                id: sourcePathField
                visible: root.sourceMode === "computer"
                Layout.fillWidth: true
                text: root.sourcePath.length ? root.displaySourcePath() : ""
                placeholderText: "Choose a subtitles folder"
                onTextEdited: {
                    root.sourcePath = text.split(" / ").join("/")
                }
                Accessible.name: "Subtitle source path"
            }
            NField {
                id: onlineQueryField
                objectName: "opensubtitles-query"
                visible: root.sourceMode === "opensubtitles"
                Layout.fillWidth: true
                text: root.onlineQuery
                placeholderText: "Movie or episode title"
                onTextEdited: {
                    root.onlineQuery = text
                    root.scheduleOnlineSearch()
                }
                onAccepted: root.searchOpenSubtitles()
                Accessible.name: "OpenSubtitles search"
            }
            NCombo {
                id: onlineLanguageCombo
                objectName: "opensubtitles-language"
                visible: root.sourceMode === "opensubtitles"
                Layout.preferredWidth: 180
                model: root.onlineLanguages
                current: root.onlineLanguage
                onPicked: (value) => {
                    root.onlineLanguage = value
                    root.scheduleOnlineSearch()
                }
                Accessible.name: "Subtitle language"
            }
        }

        Item {
            visible: root.target !== "playlist"
            Layout.preferredHeight: root.target === "folder" ? 6 : 1
        }

        NText {
            Layout.fillWidth: true
            visible: root.target === "playlist"
            text: root.target === "file" ? "Subtitle for the current file"
                  : root.target === "folder" ? "Episodes in " + (player.folderName || "this folder")
                  : "Items in the current playlist"
            dim: true
        }

        RowLayout {
            visible: root.target === "playlist"
            Layout.fillWidth: true
            Layout.leftMargin: 40
            Layout.rightMargin: 8
            implicitHeight: 24
            NText { text: "VIDEO"; color: Theme.textFaint; font.pixelSize: 10; Layout.preferredWidth: 128 }
            Item { Layout.preferredWidth: 300; implicitHeight: 1 }
            Item { Layout.preferredWidth: 32; implicitHeight: 1 }
            NText { text: "SUBTITLE"; color: Theme.textFaint; font.pixelSize: 10; Layout.fillWidth: true }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            ListView {
                id: matchList
                anchors.fill: parent
                clip: true
                model: root.sourceMode === "opensubtitles" ? openSubtitles.results
                     : root.target === "file" ? root.candidateFiles : root.matches
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    objectName: onlineTarget ? "opensubtitles-result-" + modelData.fileId : ""
                    width: matchList.width
                    height: 38
                    color: index % 2 ? Theme.bar : "transparent"
                    property bool fileTarget: root.target === "file"
                    property bool subtitleChosen: fileTarget && root.selectedSubtitlePaths.indexOf(modelData.path) >= 0
                    property bool onlineTarget: root.sourceMode === "opensubtitles"
                    property bool onlineChosen: onlineTarget && root.selectedOnlineFileId === modelData.fileId
                    readonly property string displayTitle: onlineTarget
                        ? (modelData.release || modelData.title || "Subtitle release")
                        : fileTarget ? modelData.name : modelData.media
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12
                        Icon { name: fileTarget || onlineTarget ? "subtitle" : "video-file"; size: 20; color: Theme.icon }
                        NText {
                            Layout.leftMargin: -6
                            Layout.preferredWidth: fileTarget || onlineTarget ? -1 : 128
                            Layout.fillWidth: fileTarget || onlineTarget
                            text: displayTitle
                            elide: Text.ElideMiddle
                            font.pixelSize: 12
                        }
                        NText {
                            visible: onlineTarget && modelData.movieHashMatch
                            text: "Exact file"
                            color: Theme.accent
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        Item {
                            id: matchDivider
                            visible: !fileTarget && !onlineTarget
                            Layout.preferredWidth: 279
                            implicitHeight: 1
                            Repeater {
                                model: Math.ceil(matchDivider.width / 14)
                                Rectangle {
                                    x: index * 14
                                    width: 7
                                    height: 1
                                    color: Theme.border
                                }
                            }
                        }
                        RowLayout {
                            visible: !fileTarget && !onlineTarget
                            Layout.fillWidth: true
                            spacing: 12
                            Icon { name: "subtitle"; size: 20; color: Theme.icon }
                            NText {
                                Layout.fillWidth: true
                                text: modelData.subtitle ? modelData.subtitle : "No matching subtitle"
                                color: modelData.matched ? Theme.text : Theme.textFaint
                                elide: Text.ElideMiddle
                                font.pixelSize: 12
                            }
                        }
                        NText {
                            visible: onlineTarget
                            text: modelData.language.toUpperCase() + (modelData.hearingImpaired ? " · SDH" : "")
                            color: Theme.textFaint
                            font.pixelSize: 11
                        }
                        NText {
                            visible: onlineTarget
                            text: modelData.downloadCount.toLocaleString()
                            color: Theme.textFaint
                            font.pixelSize: 11
                        }
                        Icon { visible: fileTarget && subtitleChosen; name: "check"; size: 16; color: Theme.accent }
                        Icon { visible: onlineChosen; name: "check"; size: 16; color: Theme.accent }
                    }
                    MouseArea {
                        anchors.fill: parent
                        visible: fileTarget || onlineTarget
                        enabled: !onlineTarget || !openSubtitles.downloading
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (onlineTarget) {
                                root.onlineApplyError = ""
                                root.selectedOnlineFileId = onlineChosen ? 0 : modelData.fileId
                            } else if (fileTarget) root.toggleSubtitle(modelData.path)
                        }
                    }
                }
            }
            NText {
                anchors.centerIn: parent
                visible: root.sourceMode === "opensubtitles"
                         ? (!openSubtitles.searching && openSubtitles.results.length === 0)
                         : root.target === "file" ? root.candidateFiles.length === 0 : root.matches.length === 0
                text: root.sourceMode === "opensubtitles"
                      ? (root.onlineApplyError.length ? root.onlineApplyError
                         : openSubtitles.error.length ? openSubtitles.error : "Search OpenSubtitles to find subtitles.")
                      : root.sourcePath.length ? (root.target === "file" ? "No subtitle variants found for the current file." : "No local playlist items found for this target.") : "Choose a source to preview matching subtitles."
                color: Theme.textFaint
            }
        }

        RowLayout {
            visible: root.linked.length > 0 && root.target !== "file"
            Layout.fillWidth: true
            NText { text: "Linked: " + root.linked; Layout.fillWidth: true; color: Theme.textFaint; elide: Text.ElideMiddle }
            NButton {
                text: "Unlink"
                flat: true
                onClicked: {
                    if (root.target === "playlist") player.unlinkSubtitleFolderFromPlaylist()
                    else player.unlinkSubtitleFolder()
                    root.linked = ""
                    root.sourcePath = ""
                }
            }
        }
    }

    footer: RowLayout {
        NButton { text: "Cancel"; flat: true; onClicked: root.close() }
        NButton {
            text: root.sourceMode === "opensubtitles"
                  ? openSubtitles.downloading ? "Downloading…" : "Download and add"
                  : "Save"
            primary: true
            enabledState: root.sourceMode === "opensubtitles"
                          ? root.selectedOnlineFileId > 0 && !openSubtitles.downloading
                         : root.target === "file" ? root.selectedSubtitlePaths.length > 0 : root.sourcePath.trim().length > 0
            onClicked: root.sourceMode === "opensubtitles"
                       ? openSubtitles.download(root.selectedOnlineFileId) : root.saveSelection()
        }
    }

    FolderDialog {
        id: folderDialog
        title: "Choose the subtitles folder"
        currentFolder: player.folderPath.length ? platform.fileUrl(player.folderPath) : ""
        onAccepted: {
            root.sourcePath = platform.localPath(selectedFolder)
            root.refreshMatches()
        }
    }
}
