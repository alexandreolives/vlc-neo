import QtQuick
import QtQuick.Layouts
import Neo 1.0

Rectangle {
    id: root
    property var items: Theme.layoutList()
    property bool preview: false
    signal action(string id, Item source)

    function findControl(id) {
        for (let i = 0; i < controls.count; ++i) {
            const item = controls.itemAt(i)
            if (item && item.controlId === id)
                return item
        }
        return null
    }
    function focusControl(id) {
        const item = findControl(id)
        if (!item || !item.contentItem)
            return false
        item.contentItem.forceActiveFocus()
        return item.contentItem.activeFocus
    }

    color: Theme.bar
    implicitHeight: Theme.barHeight

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.width < 720 ? 6 : 20
        anchors.rightMargin: root.width < 720 ? 6 : 20
        spacing: root.width < 720 ? 2 : 8
        Repeater {
            id: controls
            model: root.items
            delegate: ControlItem {
                required property string modelData
                controlId: modelData
                preview: root.preview
                Layout.fillWidth: flexible
                Layout.preferredWidth: implicitWidth
                Layout.minimumWidth: controlId === "seek" ? (compact ? 48 : 80) : implicitWidth
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: controlId === "time" || controlId === "volume" || controlId === "audio" ? 12 : 0
                onAction: (id, source) => root.action(id, source)
            }
        }
    }
}
