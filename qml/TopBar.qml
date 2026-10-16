import QtQuick
import QtQuick.Layouts
import Neo 1.0

// Title bar: cone, menu, library toggle, show/folder name (opens library), title, window buttons.
Rectangle {
    id: root
    signal menuRequested(Item source)
    signal action(string id, Item source)
    color: Theme.bar
    implicitHeight: Theme.topHeight

    // Drag the window by its title bar (works on Wayland through xdg move).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: win.startSystemMove()
        onDoubleClicked: root.action("maximize", root)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 6
        spacing: 2

        Icon { name: "cone"; size: 16; Layout.rightMargin: 6 }
        IconButton { icon: "ellipsis"; tip: "Menu"; onClicked: root.menuRequested(this) }
        IconButton {
            icon: "panel-left"; tip: "Library (L)"
            checked: win.libraryOpen
            onClicked: root.action("library", this)
        }
        Rectangle { width: 1; height: 16; color: Theme.border; Layout.leftMargin: 4; Layout.rightMargin: 4 }
        Rectangle {
            id: folderChip
            implicitWidth: folderRow.implicitWidth + 12
            implicitHeight: 24
            radius: Theme.radiusSmall
            color: folderMouse.containsMouse ? Theme.hover : "transparent"
            Row {
                id: folderRow
                anchors.centerIn: parent
                spacing: 6
                Icon { name: "folder"; size: 15; anchors.verticalCenter: parent.verticalCenter }
                NText {
                    text: player.folderName.length ? player.folderName : "Library"
                    dim: true
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: folderMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.action("library", folderChip)
            }
        }
        Item { Layout.fillWidth: true }
        IconButton { icon: "picture-in-picture-2"; tip: "Picture in picture"; checked: win.pip; onClicked: root.action("pip", this) }
        IconButton { icon: "minus"; tip: "Minimize"; onClicked: root.action("minimize", this) }
        IconButton { icon: "square"; iconSize: 14; tip: "Maximize"; onClicked: root.action("maximize", this) }
        IconButton { icon: win.fullscreen ? "minimize-2" : "maximize"; tip: "Fullscreen (F)"; onClicked: root.action("fullscreen", this) }
        IconButton { icon: "x"; tip: "Quit"; onClicked: root.action("quit", this) }
    }

    NText {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width * 0.42)
        horizontalAlignment: Text.AlignHCenter
        text: player.title.length ? player.title : "VLC Media Player"
        font.pixelSize: 12
        dim: true
    }
}
