import QtQuick
import QtQuick.Controls.Basic
import Neo 1.0

TextField {
    id: root
    color: Theme.text
    placeholderTextColor: Theme.textFaint
    selectionColor: Theme.accent
    font.pixelSize: Theme.fontBody
    leftPadding: 10
    implicitHeight: 30
    background: Rectangle {
        radius: Theme.radiusSmall
        color: Theme.field
        border.color: root.activeFocus ? Theme.accent : Theme.border
    }
}
