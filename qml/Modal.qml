import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

Popup {
    id: root
    property string title
    property string subtitle
    property bool closable: true
    property int bodyMargin: 18
    property int titlePixelSize: Theme.fontTitle
    property int titleWeight: Font.DemiBold
    property color titleColor: Theme.text
    property int titleLeftMargin: 18
    property int titleRightMargin: 8
    property int footerSideMargin: 18
    property int footerBottomMargin: 16
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
            Layout.leftMargin: root.titleLeftMargin
            Layout.rightMargin: root.titleRightMargin
            Layout.preferredWidth: root.width - root.titleLeftMargin - root.titleRightMargin
            Layout.topMargin: 10
            implicitHeight: 40
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                Layout.preferredWidth: root.width - root.titleLeftMargin - root.titleRightMargin - 30
                Layout.minimumWidth: 0
                NText { text: root.title; color: root.titleColor; font.pixelSize: root.titlePixelSize; font.weight: root.titleWeight }
                NText { visible: root.subtitle.length > 0; text: root.subtitle; dim: true; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
            IconButton { objectName: "modal-close-button"; visible: root.closable; icon: "x"; onClicked: root.close(); Layout.alignment: Qt.AlignTop }
        }
        Item {
            id: bodyHolder
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: root.bodyMargin
            // Use the body's intrinsic size; childrenRect depends on a child's
            // assigned height and loops when this holder fills the remaining
            // space in the modal layout.
            implicitWidth: children.length > 0 ? children[0].implicitWidth : 0
            implicitHeight: children.length > 0 ? children[0].implicitHeight : 0
        }
        RowLayout {
            id: footerHolder
            visible: children.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: root.footerSideMargin
            Layout.rightMargin: root.footerSideMargin
            Layout.bottomMargin: root.footerBottomMargin
            spacing: 8
        }
    }
}
