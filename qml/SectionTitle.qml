import QtQuick
import Neo 1.0

NText {
    property bool advanced: false
    visible: !advanced || Theme.store.advancedOptions
    font.pixelSize: Theme.fontTitle
    font.weight: Font.DemiBold
    topPadding: 6
    bottomPadding: 2
}
