import QtQuick
import Neo 1.0

Text {
    property bool dim: false
    color: dim ? Theme.textDim : Theme.text
    font.pixelSize: Theme.fontBody
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
