pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.services

/**
 * Hotspot credential row: inline label on the left, tappable value on the right.
 * Tapping the value switches to an inline text field; pressing Enter commits.
 *
 * @property field   Key used by the host to identify this row (e.g. "name", "pw")
 * @property label   Uppercase label displayed on the left
 * @property value   Current credential text (or empty for placeholder)
 * @property secret  When true, the value is displayed in flame-core color
 * @property editing Read-only; set by the host when this row's field is active
 * @property scale   Font scale passed in from the parent surface
 * @property draft   Live draft text from the host (bound to hsDraft)
 * @signal  editRequested(field, currentValue)  Host should set hsEdit / hsDraft
 * @signal  committed()                         Host should commit the edit
 * @signal  draftEdited(newText)                Host should update hsDraft
 */
Item {
    id: cr

    property string field: ""
    property string label: ""
    property string value: ""
    property bool secret: false
    property bool editing: false
    property real scale: 1
    property string draft: ""

    signal editRequested(string field, string currentValue)
    signal committed()
    signal draftEdited(string newText)

    /**
     * Begin editing this row the same way a click does: request the edit so
     * the host flips `editing`, then focus the field once it is visible.
     * Used by the host's keyboard navigation.
     */
    function startEdit() {
        cr.editRequested(cr.field, cr.value);
        Qt.callLater(crField.forceActiveFocus);
    }

    width: parent ? parent.width : 0
    height: 22 * cr.scale

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 8 * cr.scale
        anchors.verticalCenter: parent.verticalCenter
        text: cr.label
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 9 * cr.scale
        font.weight: Font.Medium
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1 * cr.scale
    }

    Text {
        visible: !cr.editing
        anchors.right: parent.right
        anchors.rightMargin: 8 * cr.scale
        anchors.verticalCenter: parent.verticalCenter
        text: cr.value.length ? cr.value : "tap to set"
        color: cr.value.length ? (cr.secret ? Theme.flameCore : Theme.cream) : Theme.faint
        font.family: Theme.font
        font.pixelSize: 12 * cr.scale
        font.weight: Font.Medium
        font.features: { "tnum": 1 }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6 * cr.scale
            cursorShape: Qt.PointingHandCursor
            onClicked: cr.startEdit()
        }
    }

    TextField {
        id: crField
        visible: cr.editing
        anchors.right: parent.right
        anchors.rightMargin: 8 * cr.scale
        anchors.verticalCenter: parent.verticalCenter
        width: 150 * cr.scale
        horizontalAlignment: TextInput.AlignRight
        background: null
        padding: 0
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 12 * cr.scale
        placeholderText: cr.field === "pw" ? "8+ characters" : "Name"
        placeholderTextColor: Theme.faint
        selectByMouse: true
        selectionColor: Theme.verm
        text: cr.draft
        onTextEdited: cr.draftEdited(text)
        onAccepted: cr.committed()
    }
}
