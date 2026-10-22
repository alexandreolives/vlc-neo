import QtQuick
import QtQuick.Controls.Basic
import Neo 1.0

// Drop-down with human words (model: [{label, value}]).
Rectangle {
    id: root
    property var model: []
    property var current
    readonly property bool inheritsSettingRowLabel: true
    readonly property bool expanded: menu.visible
    property string accessibleName: ""
    property int keyboardIndex: -1
    signal picked(var value)
    implicitWidth: 180
    implicitHeight: 32
    radius: 5
    color: Theme.field
    border.width: 1
    border.color: menu.visible || activeFocus ? Theme.accent : Theme.border
    activeFocusOnTab: enabled
    Accessible.name: accessibleName.length ? accessibleName : labelFor(current)
    Accessible.role: Accessible.ComboBox
    Accessible.focusable: enabled

    function labelFor(v) {
        for (const m of model) if (String(m.value) === String(v)) return m.label
        return v === undefined ? "" : String(v)
    }
    function openMenu() {
        if (!model.length) return
        keyboardIndex = model.findIndex(item => String(item.value) === String(current))
        if (keyboardIndex < 0) keyboardIndex = 0
        menu.open()
    }
    NText { text: root.labelFor(root.current); dim: true; x: 10; width: parent.width - 34; anchors.verticalCenter: parent.verticalCenter }
    Icon { name: "chevron-right"; size: 14; rotation: 90; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter }
    Keys.onPressed: (event) => {
        const opens = event.key === Qt.Key_Space || event.key === Qt.Key_Return
                   || event.key === Qt.Key_Enter || event.key === Qt.Key_Down
        if (!menu.visible && opens && root.model.length) {
            root.openMenu()
            event.accepted = true
        } else if (menu.visible && event.key === Qt.Key_Escape) {
            root.forceActiveFocus()
            menu.close()
            event.accepted = true
        } else if (menu.visible && root.model.length && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
            const currentIndex = root.keyboardIndex >= 0 ? root.keyboardIndex
                : root.model.findIndex(item => String(item.value) === String(root.current))
            const direction = event.key === Qt.Key_Down ? 1 : -1
            root.keyboardIndex = (currentIndex + direction + root.model.length) % root.model.length
            event.accepted = true
        } else if (menu.visible && (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            if (root.keyboardIndex >= 0 && root.keyboardIndex < root.model.length)
                root.picked(root.model[root.keyboardIndex].value)
            menu.close()
            event.accepted = true
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus()
            menu.visible ? menu.close() : root.openMenu()
        }
    }

    Popup {
        id: menu
        parent: root.parent
        x: root.x
        y: root.y + root.height + 2
        width: Math.max(root.width, 220)
        height: optionList.implicitHeight + 12
        padding: 6
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        onOpened: Qt.callLater(() => optionList.forceActiveFocus())
        background: Rectangle {
            color: Theme.surface
            radius: Theme.radius
            border.color: Theme.border
        }
        contentItem: Column {
            id: optionList
            spacing: 0
            focus: true
            width: menu.width - menu.leftPadding - menu.rightPadding
            Keys.onPressed: (event) => {
                if (!root.model.length)
                    return
                if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                    const currentIndex = root.keyboardIndex >= 0 ? root.keyboardIndex
                        : root.model.findIndex(item => String(item.value) === String(root.current))
                    const direction = event.key === Qt.Key_Down ? 1 : -1
                    root.keyboardIndex = (currentIndex + direction + root.model.length) % root.model.length
                    event.accepted = true
                } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.keyboardIndex >= 0 && root.keyboardIndex < root.model.length)
                        root.picked(root.model[root.keyboardIndex].value)
                    root.forceActiveFocus()
                    menu.close()
                    event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                    root.forceActiveFocus()
                    menu.close()
                    event.accepted = true
                }
            }
            Repeater {
                model: root.model
                delegate: Rectangle {
                    id: option
                    required property var modelData
                    required property int index
                    width: optionList.width
                    height: 32
                    radius: Theme.radiusSmall
                    color: root.keyboardIndex === index || hover.containsMouse ? Theme.hover : "transparent"
                    Accessible.name: modelData.label
                    Accessible.role: Accessible.ListItem
                    Accessible.focusable: true

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10
                        Item {
                            width: 16
                            height: parent.height
                            Icon {
                                anchors.centerIn: parent
                                name: String(option.modelData.value) === String(root.current) ? "check" : ""
                                size: 15
                                color: Theme.accent
                            }
                        }
                        NText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 46
                            text: option.modelData.label
                            color: Theme.text
                        }
                    }
                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.picked(option.modelData.value)
                            root.forceActiveFocus()
                            menu.close()
                        }
                    }
                }
            }
        }
    }
}
