import QtQuick
import Neo 1.0

Image {
    property string name
    property color color: Theme.icon
    property int size: 18
    width: size
    height: size
    source: name.length ? Theme.iconUrl(name, color) : ""
    sourceSize: Qt.size(size * 2, size * 2)
    smooth: true
    mipmap: true
    asynchronous: false
}
