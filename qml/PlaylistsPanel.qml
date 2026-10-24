import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Neo 1.0

Rectangle {
    id: root
    color: Theme.librarySidePanel
    signal createPlaylist()
    signal openLibraryPage()
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
            Layout.leftMargin: 18
            Layout.rightMargin: 17
            Layout.preferredHeight: 52
            spacing: 6
            IconButton { icon: "arrow-left"; tip: "Back"; enabled: false }
            IconButton { icon: "arrow-right"; tip: "Forward"; enabled: false }
            NText {
                text: "Playlists"
                font.pixelSize: 14
                color: Theme.librarySideTitle
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            IconButton { icon: "more"; tip: "Playlist options" }
            IconButton { objectName: "playlist-expand"; icon: "open"; tip: "Open full library page"; onClicked: root.openLibraryPage() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 17
            Layout.preferredHeight: 52
            spacing: 5
            NText { visible: !root.searchOpen; text: root.fileCount() + (root.fileCount() === 1 ? " item" : " items"); color: Theme.librarySideText; font.pixelSize: 12; Layout.fillWidth: true }
            NField {
                visible: root.searchOpen
                Layout.fillWidth: true
                placeholderText: "Search playlists"
                text: root.searchText
                onTextEdited: root.searchText = text
            }
            IconButton { objectName: "playlist-sort"; visible: !root.searchOpen; icon: "sort"; tip: "Reverse name order"; onClicked: root.reverseSort = !root.reverseSort }
            IconButton { objectName: "playlist-view"; visible: !root.searchOpen; icon: "list"; checked: root.compactRows; tip: "Toggle compact rows"; onClicked: root.compactRows = !root.compactRows }
            IconButton { objectName: "playlist-search"; visible: !root.searchOpen; icon: "search"; tip: "Search playlists"; onClicked: root.searchOpen = true }
            IconButton { objectName: "playlist-search-close"; visible: root.searchOpen; icon: "close"; tip: "Close search"; onClicked: { root.searchOpen = false; root.searchText = "" } }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        Rectangle {
            objectName: "create-playlist"
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 10
            Layout.topMargin: 16
            Layout.preferredHeight: 36
            radius: Theme.radiusSmall
            color: createPlaylistMouse.containsMouse ? Theme.hover : "transparent"
            border.width: activeFocus ? 1 : 0
            border.color: Theme.accent
            activeFocusOnTab: true
            Accessible.name: "Create playlist"
            Accessible.role: Accessible.Button
            Accessible.focusable: true
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (!event.isAutoRepeat) root.createPlaylist()
                    event.accepted = true
                }
            }
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 20
                Icon { name: "plus"; size: 16; color: createPlaylistMouse.containsMouse ? Theme.accent : Theme.icon; anchors.verticalCenter: parent.verticalCenter }
                NText { text: "Create playlist"; font.pixelSize: 13; color: Theme.librarySideText; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                id: createPlaylistMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { parent.forceActiveFocus(); root.createPlaylist() }
            }
        }

        ListView {
            id: list
            objectName: "playlist-library-list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 3
            clip: true
            model: playlists
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                required property int index
                required property string fileName
                required property url fileUrl
                objectName: "playlist-side-item-" + index
                width: ListView.view.width
                height: root.matches(fileName) ? (root.compactRows ? 34 : 42) : 0
                visible: height > 0
                color: rowMouse.containsMouse ? Theme.hover : "transparent"
                border.width: activeFocus ? 1 : 0
                border.color: Theme.accent
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: fileName.replace(/\.(m3u8?|pls|xspf)$/i, "") + ", playlist"
                Accessible.focusable: true
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                        win.openPlaylist(fileUrl)
                        event.accepted = true
                    }
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 26
                    anchors.rightMargin: 12
                    spacing: 16
                    Item {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Image { id: coverImage; anchors.fill: parent; source: platform.playlistCoverUrl(fileUrl); fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                        Icon { anchors.centerIn: parent; name: "playlist"; size: 20; color: rowMouse.containsMouse ? Theme.accent : Theme.icon; visible: coverImage.status !== Image.Ready }
                    }
                    NText {
                        text: fileName.replace(/\.(m3u8?|pls|xspf)$/i, "")
                        Layout.fillWidth: true
                        font.pixelSize: 13
                        color: Theme.librarySideText
                        elide: Text.ElideRight
                    }
                    IconButton {
                        visible: rowMouse.containsMouse || hovered
                        icon: "play"
                        iconSize: 13
                        tip: "Play playlist"
                        onClicked: win.openPlaylist(fileUrl)
                    }
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    anchors.rightMargin: 34
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { parent.forceActiveFocus(); win.openPlaylist(fileUrl) }
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
