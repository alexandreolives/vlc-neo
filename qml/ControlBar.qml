import QtQuick
import QtQuick.Layouts
import Neo 1.0

Rectangle {
    id: root
    property var items: Theme.layoutList()
    property bool preview: false
    signal action(string id, Item source)

    color: Theme.bar
    implicitHeight: Theme.barHeight

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 4
        Repeater {
            model: root.items
            delegate: ControlItem {
                required property string modelData
                controlId: modelData
                preview: root.preview
                Layout.fillWidth: flexible
                Layout.preferredWidth: implicitWidth
                Layout.minimumWidth: controlId === "seek" ? 80 : implicitWidth
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: controlId === "seek" ? 4 : 0
                Layout.rightMargin: controlId === "seek" ? 4 : 0
                onAction: (id, source) => root.action(id, source)
            }
        }
    }
}
