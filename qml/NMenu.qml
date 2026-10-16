import QtQuick
import QtQuick.Controls.Basic
import Neo 1.0

Menu {
    id: root
    padding: 6
    implicitWidth: 260
    delegate: NMenuItem {}
    background: Rectangle {
        implicitWidth: 260
        color: Theme.surface
        radius: Theme.radius
        border.color: Theme.border
    }
}
