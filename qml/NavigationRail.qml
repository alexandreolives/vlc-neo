import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

// Persistent primary navigation from the Figma player. Each item uses a
// native Qt button so it remains reachable and activatable from the keyboard.
Rectangle {
    id: root
    property string currentPage: "home"
    property bool expanded: false
    property bool shown: false
    property bool musicCategoryActive: true
    readonly property int railItemHeight: root.expanded ? 44 : Math.max(26, Math.min(44, Math.floor((root.height - 14) / 7)))
    signal navigate(string page)

    width: !shown ? 0 : expanded ? Math.max(112, Math.min(210, Math.round(win.width * 0.11)))
                                 : Math.max(30, Math.min(50, Math.round(win.width * 0.026)))
    opacity: shown ? 1 : 0
    color: Theme.rail
    clip: true
    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 140 } }

    function focusPage(page) {
        for (const button of buttonList.children) {
            if (button.page === page) {
                button.forceActiveFocus()
                return true
            }
        }
        return false
    }
    function labelForPage(page) {
        for (const button of buttonList.children) {
            if (button.page === page)
                return button.label
        }
        return ""
    }
    function expandedRowCenters() {
        const centers = []
        for (const button of buttonList.children) {
            if (button.objectName && button.objectName.indexOf("navigation-") === 0)
                centers.push(Math.round(button.mapToItem(win.contentItem, 0, button.height / 2).y))
        }
        return centers.join("/")
    }

    ColumnLayout {
        id: buttonList
        anchors.top: parent.top
        anchors.topMargin: root.expanded ? 20 : 2
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2

        RailButton { iconName: "home"; activeIconName: "home-active"; label: "Home"; page: "home" }
        RailButton { iconName: "videos"; activeIconName: "videos-active"; label: "Videos"; page: "videos" }
        RailButton { iconName: "songs"; selectedIconName: "songs-selected"; activeIconName: "songs-active"; label: "Music"; page: "music" }
        RailButton { iconName: "streaming"; activeIconName: "streaming-active"; label: "Network"; page: "network" }
        RailButton { iconName: "playlist"; activeIconName: "playlist-active"; label: "Playlists"; page: "playlist" }
        RailButton { iconName: "recent"; label: "Recent"; page: "recent" }

        RailButton { iconName: "add"; label: "Add item"; page: "add" }
    }

    component RailButton: Button {
        id: control
        property string iconName
        property string selectedIconName
        property string activeIconName
        property string label
        property string page
        readonly property bool selected: root.currentPage === page

        objectName: "navigation-" + page
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: root.expanded ? root.width - 10 : 26
        Layout.preferredHeight: root.railItemHeight
        Layout.leftMargin: root.expanded ? 5 : 0
        padding: 0
        focusPolicy: Qt.TabFocus
        Accessible.name: label
        Accessible.description: label
        onClicked: root.navigate(page)

        background: Rectangle {
            radius: 4
            color: control.down ? Theme.raised : (control.hovered ? Theme.hover : "transparent")
            border.width: control.activeFocus ? 1 : 0
            border.color: Theme.accent
        }
        contentItem: RowLayout {
            Layout.leftMargin: root.expanded ? 16 : 0
            spacing: root.expanded ? 8 : 0
            Icon {
                name: control.selected
                      ? (control.page === "music" && !root.musicCategoryActive && control.selectedIconName.length
                         ? control.selectedIconName : (control.activeIconName.length ? control.activeIconName : control.iconName))
                      : control.iconName
                size: 14
                color: control.hovered || control.activeFocus ? Theme.text : Theme.icon
            }
            NText {
                visible: root.expanded
                text: control.label
                Layout.fillWidth: true
                font.pixelSize: 11
                color: control.hovered || control.activeFocus ? Theme.text : Theme.textDim
                elide: Text.ElideRight
            }
        }
        ToolTip.visible: hovered && !root.expanded
        ToolTip.delay: 550
        ToolTip.text: label
    }
}
