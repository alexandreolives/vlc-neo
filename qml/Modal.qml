import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

Popup {
    id: root
    property string title
    property string subtitle
    property bool closable: true
    default property alias body: bodyHolder.data
    property alias footer: footerHolder.data

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    padding: 0
    closePolicy: closable ? (Popup.CloseOnEscape | Popup.CloseOnPressOutside) : Popup.NoAutoClose
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }

    background: Rectangle { color: Theme.panel; radius: 8; border.color: Theme.border }
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 110 } }

    contentItem: ColumnLayout {
        spacing: 0
        RowLayout {
            visible: root.title.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 8
            Layout.topMargin: 10
            implicitHeight: 40
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                NText { text: root.title; font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold }
                NText { visible: root.subtitle.length > 0; text: root.subtitle; dim: true; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
            IconButton { visible: root.closable; icon: "x"; onClicked: root.close(); Layout.alignment: Qt.AlignTop }
        }
        Item {
            id: bodyHolder
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 18
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
        RowLayout {
            id: footerHolder
            visible: children.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.bottomMargin: 16
            spacing: 8
        }
    }
}
