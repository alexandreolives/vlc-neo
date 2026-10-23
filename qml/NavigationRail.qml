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
    property bool canGoBack: false
    signal navigate(string page)
    signal backRequested()

    width: !shown ? 0 : expanded ? Math.max(112, Math.min(210, Math.round(win.width * 0.11)))
                                 : Math.max(30, Math.min(52, Math.round(win.width * 0.027)))
    opacity: shown ? 1 : 0
    color: Theme.rail
    clip: true
    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 140 } }

    RailButton {
        objectName: "navigation-back"
        anchors.top: parent.top
        anchors.topMargin: 5
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expanded ? root.width - 10 : 26
        height: root.expanded ? 40 : 26
        visible: root.canGoBack
        iconName: "arrow-left"
        label: "Back"
        page: "__back"
        onClicked: root.backRequested()
    }

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
        anchors.topMargin: root.expanded ? 54 : 38
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.expanded ? 2 : 3

        RailButton { iconName: "home"; label: "Home"; page: "home" }
        RailButton { iconName: "videos"; label: "Videos"; page: "videos" }
        RailButton { iconName: "music"; label: "Music"; page: "music" }
        RailButton { iconName: "streaming"; label: "Network"; page: "streaming" }
        RailButton { iconName: "playlist"; label: "Playlists"; page: "playlist" }
        RailButton { iconName: "recent"; label: "Recent"; page: "recent" }

        Item { visible: !root.expanded; Layout.preferredHeight: 1 }
        RailButton { iconName: "add"; label: "Add item"; page: "add" }
    }

    component RailButton: Button {
        id: control
        property string iconName
        property string label
        property string page
        readonly property bool selected: root.currentPage === page

        objectName: "navigation-" + page
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: root.expanded ? root.width - 10 : 26
        Layout.preferredHeight: root.expanded ? 44 : 26
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
                name: control.iconName
                size: 14
                color: control.selected ? Theme.accent : (control.hovered || control.activeFocus ? Theme.text : Theme.icon)
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
