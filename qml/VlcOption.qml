import QtQuick
import QtQuick.Layouts
import Neo 1.0

// A VLC core preference (stored in vlcrc). Hidden when this VLC build lacks it.
SettingRow {
    id: root
    property string option
    property string kind: "bool"          // bool | choice | text | number
    property var choices: []              // [{label, value}]
    property int fieldWidth: 160
    property var current: player.config(option)
    visible: current !== undefined

    function save(v) { player.setConfig(option, v); current = v }

    Loader {
        sourceComponent: root.kind === "bool" ? boolComp : root.kind === "choice" ? choiceComp : textComp
    }
    Component {
        id: boolComp
        NSwitch { checked: !!root.current; onToggled: (on) => root.save(on) }
    }
    Component {
        id: choiceComp
        NCombo {
            width: root.fieldWidth
            model: root.choices
            current: root.current
            onPicked: (v) => root.save(v)
        }
    }
    Component {
        id: textComp
        NField {
            width: root.fieldWidth
            text: root.current === undefined ? "" : String(root.current)
            inputMethodHints: root.kind === "number" ? Qt.ImhDigitsOnly : Qt.ImhNone
            onEditingFinished: root.save(root.kind === "number" ? parseInt(text) || 0 : text)
        }
    }
}
