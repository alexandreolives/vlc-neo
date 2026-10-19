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
    signal navigate(string page)

    width: expanded ? 112 : 30
    color: Theme.rail

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

    ColumnLayout {
        id: buttonList
        anchors.top: parent.top
        anchors.topMargin: 30
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 3

        RailButton { iconName: "home"; label: "Home"; page: "home" }
        RailButton { iconName: "videos"; label: "Videos"; page: "videos" }
        RailButton { iconName: "folder"; label: "Browse"; page: "folder" }
        RailButton { iconName: "streaming"; label: "Network"; page: "streaming" }
        RailButton { iconName: "playlist"; label: "Queue"; page: "playlist" }
        RailButton { iconName: "recent"; label: "Recent"; page: "recent" }

        Item { Layout.preferredHeight: 1 }
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
        Layout.preferredHeight: 26
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
