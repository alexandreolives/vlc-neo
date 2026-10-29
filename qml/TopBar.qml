import QtQuick
import QtQuick.Layouts
import QtCore
import Neo 1.0

// Title bar: cone, menu, library toggle, show/folder name (opens library), title, window buttons.
Rectangle {
    id: root
    signal menuRequested(Item source)
    signal action(string id, Item source)
    signal onboardingHoverChanged(bool hovered)
    property bool onboardingMode: false
    property bool compactPreview: false
    readonly property bool compactLibraryActions: win.libraryFullPage
    readonly property string folderLabel: {
        if (player.hasMedia && (!player.hasVideo || win.audioVisualizerActive))
            return "My Songs"
        const path = player.folderPath.length
                ? player.folderPath
                : platform.localPath(StandardPaths.writableLocation(StandardPaths.MoviesLocation))
        const normalized = path.toString().replace(/[\\/]+$/, "")
        const separator = Math.max(normalized.lastIndexOf("/"), normalized.lastIndexOf("\\"))
        const name = normalized.slice(separator + 1)
        return name.length ? name : "Videos"
    }
    property alias titleLabel: appTitle
    property alias pipButton: pipButtonControl
    property alias minimizeButton: minimizeButtonControl
    property alias maximizeButton: maximizeButtonControl
    property alias fullscreenButton: fullscreenButtonControl
    property alias quitButton: quitButtonControl
    color: Theme.bar
    implicitHeight: compactPreview ? 24 : Math.max(Theme.topHeight, Math.round(win.width * 0.021))

    // Drag the window by its title bar (works on Wayland through xdg move).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: win.startSystemMove()
        onDoubleClicked: root.action(win.pip ? "pip" : "maximize", root)
    }

    HoverHandler {
        onHoveredChanged: if (root.onboardingMode && !root.compactPreview)
                              root.onboardingHoverChanged(hovered)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.compactPreview ? 6 : 10
        anchors.rightMargin: root.compactPreview ? 4 : 6
        spacing: 2

        Icon { name: "cone"; size: root.compactPreview ? 12 : 16; Layout.rightMargin: root.compactPreview ? 3 : 6 }
        IconButton { visible: !root.onboardingMode && !win.pip; icon: "ellipsis"; tip: "Menu"; onClicked: root.menuRequested(this) }
        IconButton {
            visible: !root.onboardingMode && !win.pip && !root.compactLibraryActions
            icon: "panel-left"; tip: "Library (L)"
            checked: win.sidePanelOpen
            onClicked: root.action("library", this)
        }
        Rectangle { visible: !root.onboardingMode && !win.pip; width: 1; height: 16; color: Theme.border; Layout.leftMargin: 4; Layout.rightMargin: 4 }
        Rectangle {
            id: folderChip
            objectName: "folder-chip"
            visible: !root.onboardingMode && !win.pip && !root.compactLibraryActions
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
                    objectName: "folder-chip-label"
                    text: root.folderLabel
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
                onClicked: root.action(player.hasMedia && (!player.hasVideo || win.audioVisualizerActive)
                                       ? "music-library" : "folder-sidebar", folderChip)
            }
        }
        Item { Layout.fillWidth: true }
        IconButton { id: pipButtonControl; objectName: "topbar-pip"; visible: !root.onboardingMode; implicitWidth: root.compactPreview ? 18 : 30; implicitHeight: root.compactPreview ? 18 : 28; iconSize: root.compactPreview ? 12 : 18; icon: "picture-in-picture-2"; tip: win.pip ? "Exit picture in picture" : "Picture in picture"; checked: win.pip; onClicked: root.action("pip", this) }
        IconButton { id: minimizeButtonControl; objectName: "topbar-minimize"; visible: !win.pip; implicitWidth: root.compactPreview ? 18 : 30; implicitHeight: root.compactPreview ? 18 : 28; iconSize: root.compactPreview ? 12 : 18; icon: "minimize"; tip: "Minimize"; onClicked: root.action("minimize", this) }
        IconButton { id: maximizeButtonControl; objectName: "topbar-maximize"; visible: !win.pip; implicitWidth: root.compactPreview ? 18 : 30; implicitHeight: root.compactPreview ? 18 : 28; iconSize: root.compactPreview ? 12 : 14; icon: "square"; tip: "Maximize"; onClicked: root.action("maximize", this) }
        IconButton { id: fullscreenButtonControl; objectName: "topbar-fullscreen"; visible: !win.pip; implicitWidth: root.compactPreview ? 18 : 30; implicitHeight: root.compactPreview ? 18 : 28; iconSize: root.compactPreview ? 12 : 18; icon: win.fullscreen ? "minimize-2" : "maximize"; tip: "Fullscreen (F)"; onClicked: root.action("fullscreen", this) }
        IconButton { id: quitButtonControl; objectName: "topbar-quit"; implicitWidth: root.compactPreview ? 18 : 30; implicitHeight: root.compactPreview ? 18 : 28; iconSize: root.compactPreview ? 12 : 18; icon: "x"; tip: "Quit"; onClicked: root.action("quit", this) }
    }

    NText {
        id: appTitle
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width * 0.42)
        horizontalAlignment: Text.AlignHCenter
        text: win.showMediaTitle && player.hasMedia && win.displayMediaTitle.length ? win.displayMediaTitle : "VLC Media Player"
        font.pixelSize: root.compactPreview ? 9 : 12
        dim: true
    }
}
