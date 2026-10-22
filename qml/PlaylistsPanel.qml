import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Neo 1.0

Rectangle {
    id: root
    color: Theme.panel
    signal createPlaylist()
    property bool expanded: false
    property bool compactRows: false
    property bool searchOpen: false
    property string searchText: ""
    property bool reverseSort: false

    function matches(name) { return searchText.trim().length === 0 || name.toLowerCase().includes(searchText.trim().toLowerCase()) }
    function fileCount() {
        let count = 0
        for (let i = 0; i < playlists.count; ++i)
            if (matches(playlists.get(i, "fileName"))) ++count
        return count
    }

    FolderListModel {
        id: playlists
        folder: platform.fileUrl(platform.playlistLibraryDirectory())
        nameFilters: ["*.m3u", "*.m3u8", "*.pls", "*.xspf"]
        showDirs: false
        showDotAndDotDot: false
        caseSensitive: false
        sortField: FolderListModel.Name
        sortReversed: root.reverseSort
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 7
            implicitHeight: 38
            spacing: 5
            IconButton { icon: "arrow-left"; tip: "Back"; enabled: false }
            IconButton { icon: "arrow-right"; tip: "Forward"; enabled: false }
            NText {
                text: "Playlists"
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            IconButton { icon: "more"; tip: "Playlist options" }
            IconButton { objectName: "playlist-expand"; icon: root.expanded ? "minimize-2" : "open"; tip: root.expanded ? "Narrow panel" : "Expand panel"; onClicked: root.expanded = !root.expanded }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 7
            implicitHeight: 34
            NText { visible: !root.searchOpen; text: root.fileCount() + (root.fileCount() === 1 ? " item" : " items"); dim: true; font.pixelSize: 10; Layout.fillWidth: true }
            NField {
                visible: root.searchOpen
                Layout.fillWidth: true
                placeholderText: "Search playlists"
                text: root.searchText
                onTextEdited: root.searchText = text
            }
            IconButton { objectName: "playlist-sort"; visible: !root.searchOpen; icon: "sort"; tip: "Reverse name order"; onClicked: root.reverseSort = !root.reverseSort }
            IconButton { objectName: "playlist-view"; visible: !root.searchOpen; icon: "view"; checked: root.compactRows; tip: "Toggle compact rows"; onClicked: root.compactRows = !root.compactRows }
            IconButton { objectName: "playlist-search"; visible: !root.searchOpen; icon: "search"; tip: "Search playlists"; onClicked: root.searchOpen = true }
            IconButton { objectName: "playlist-search-close"; visible: root.searchOpen; icon: "close"; tip: "Close search"; onClicked: { root.searchOpen = false; root.searchText = "" } }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        NButton {
            objectName: "create-playlist"
            text: "Create playlist"
            icon: "plus"
            flat: true
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 10
            Layout.topMargin: 8
            onClicked: root.createPlaylist()
        }

        ListView {
            id: list
            objectName: "playlist-library-list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8
            clip: true
            model: playlists
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                required property string fileName
                required property url fileUrl
                width: ListView.view.width
                height: root.matches(fileName) ? (root.compactRows ? 28 : 34) : 0
                visible: height > 0
                color: rowMouse.containsMouse ? Theme.hover : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 9
                    Item {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Image { id: coverImage; anchors.fill: parent; source: platform.playlistCoverUrl(fileUrl); fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                        Icon { anchors.centerIn: parent; name: "playlist"; size: 14; color: rowMouse.containsMouse ? Theme.accent : Theme.icon; visible: coverImage.status !== Image.Ready }
                    }
                    NText {
                        text: fileName.replace(/\.(m3u8?|pls|xspf)$/i, "")
                        Layout.fillWidth: true
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    IconButton {
                        visible: rowMouse.containsMouse || hovered
                        icon: "play"
                        iconSize: 13
                        tip: "Play playlist"
                        onClicked: player.openUrls([fileUrl], true)
                    }
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    anchors.rightMargin: 34
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: player.openUrls([fileUrl], true)
                    onDoubleClicked: player.openUrls([fileUrl], true)
                }
            }
            NText {
                anchors.centerIn: parent
                visible: root.fileCount() === 0
                text: root.searchText.length ? "No matching playlists" : "Create a playlist from the queue"
                dim: true
                font.pixelSize: 10
            }
        }
    }
}
