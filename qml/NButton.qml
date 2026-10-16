import QtQuick
import Neo 1.0

Rectangle {
    id: root
    property string text
    property string icon
    property bool primary: false
    property bool flat: false
    property bool enabledState: true
    signal clicked()

    implicitWidth: Math.max(64, row.implicitWidth + 24)
    clip: true
    implicitHeight: 30
    radius: Theme.radiusSmall
    opacity: enabledState ? 1 : 0.45
    color: primary ? (mouse.containsMouse ? Qt.lighter(Theme.accent, 1.12) : Theme.accent)
                   : flat ? (mouse.containsMouse ? Theme.hover : "transparent")
                          : (mouse.containsMouse ? Theme.hover : Theme.raised)
    border.width: primary || flat ? 0 : 1
    border.color: Theme.border

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Icon {
            visible: root.icon.length > 0
            name: root.icon
            size: 15
            color: root.primary ? Theme.accentText : Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
        NText {
            text: root.text
            color: root.primary ? Theme.accentText : Theme.text
            font.weight: root.primary ? Font.DemiBold : Font.Normal
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
