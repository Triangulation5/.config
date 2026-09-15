import QtQuick
import QtQuick.Layouts
import "../config"

RowLayout {
    id: root
    Layout.fillWidth: true

    property string label: ""
    property string caption: ""
    property bool checked: false

    property bool defaultChecked: false
    Component.onCompleted: defaultChecked = checked
    function resetToDefault() { root.commit(defaultChecked) }

    // Store-driven mode: see SettingSlider.onCommit. `checked:` binding
    // survives clicks because writes route through commit().
    property var onCommit: null
    function commit(b) {
        if (onCommit !== null) onCommit(b);
        else checked = b;
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
            text: root.label
            color: Theme.text
            font.pixelSize: Theme.fontSizeNormal
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Text {
            text: root.caption
            visible: root.caption.length > 0
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSection
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    Rectangle {
        id: track
        width: 42
        height: 22
        radius: 11
        color: root.checked ? Theme.accent : "#2a2a2a"
        Behavior on color { ColorAnimation { duration: Theme.animNormal } }

        Rectangle {
            id: knob
            width: 18
            height: 18
            radius: 9
            color: Theme.knob
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 2 : 2
            Behavior on x { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.commit(!root.checked)
        }
    }
}
