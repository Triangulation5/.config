pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons
import qs.modules.pill.widgets.osd

/**
 * Level OSD face: a glyph at the left, a percentage at the right and a fill
 * bar between them that tracks `fill`. Shared by the volume, brightness and
 * power-source faces, which only differ in glyph, glyph colour, percentage and
 * fill styling: `fillGradient` wins over `fillColor`, and `shimmerOn` runs
 * the charging sweep the battery face uses. Driven by the Osd root through
 * `active`.
 */
OsdFace {
    id: face

    property string glyph: ""
    property string title: "Level"
    property color glyphColor: Theme.iconDim
    property real glyphProgress: 1

    property string pctText: ""
    property color pctColor: Theme.cream
    property real pctWidth: 32 * face.s

    property real fill: 0
    property color fillColor: Theme.vermLit
    property Gradient fillGradient: null
    property color materialFillColor: Theme.primary
    property bool levelInteractive: false
    property bool iconInteractive: false
    signal levelRequested(real value)
    signal iconClicked()
    property real dragValue: 0
    property bool dragging: false
    readonly property real displayFill: dragging ? dragValue : fill

    /** Runs the charging sweep along the filled bar; the battery face sets this while the pack takes charge. */
    property bool shimmerOn: false

    Rectangle {
        id: iconContainer
        visible: Theme.material
        anchors.left: parent.left
        anchors.leftMargin: 4 * face.s
        anchors.verticalCenter: parent.verticalCenter
        width: 38 * face.s
        height: width
        radius: 14 * face.s
        color: face.fillColor === Theme.error ? Qt.alpha(Theme.error, 0.16) : Theme.primaryContainer

        MouseArea {
            anchors.fill: parent
            enabled: face.iconInteractive
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: face.iconClicked()
        }
    }

    GlyphIcon {
        id: levelGlyph
        anchors.left: Theme.material ? undefined : parent.left
        anchors.leftMargin: 0
        anchors.centerIn: Theme.material ? iconContainer : undefined
        anchors.verticalCenter: Theme.material ? undefined : parent.verticalCenter
        width: 18 * face.s
        height: 17 * face.s
        name: face.glyph
        progress: face.glyphProgress
        color: face.glyphColor
        stroke: 1.7
    }

    Text {
        id: titleLabel
        visible: Theme.material
        anchors.left: iconContainer.right
        anchors.leftMargin: 12 * face.s
        anchors.top: parent.top
        anchors.topMargin: 7 * face.s
        text: face.title
        color: Theme.onSurfaceVariant
        font.family: Theme.font
        font.pixelSize: 11 * face.s
        font.weight: Font.Medium
    }

    Text {
        id: pctLabel
        anchors.right: parent.right
        anchors.left: Theme.material ? titleLabel.right : undefined
        anchors.leftMargin: Theme.material ? 6 * face.s : 0
        anchors.top: Theme.material ? parent.top : undefined
        anchors.topMargin: Theme.material ? 7 * face.s : 0
        anchors.verticalCenter: Theme.material ? undefined : parent.verticalCenter
        anchors.rightMargin: Theme.material ? 5 * face.s : 0
        width: face.pctWidth
        horizontalAlignment: Text.AlignRight
        text: face.pctText
        color: face.pctColor
        font.family: Theme.font
        font.pixelSize: (Theme.material ? 12 : 11) * face.s
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        Behavior on color {
            enabled: Style.transitioning
            ColorAnimation { duration: Style.transitionDuration; easing.type: Easing.InOutCubic }
        }
    }

    Rectangle {
        anchors.left: Theme.material ? iconContainer.right : levelGlyph.right
        anchors.leftMargin: (Theme.material ? 12 : 12) * face.s
        anchors.right: Theme.material ? parent.right : pctLabel.left
        anchors.rightMargin: (Theme.material ? 5 : 12) * face.s
        anchors.bottom: Theme.material ? parent.bottom : undefined
        anchors.bottomMargin: Theme.material ? 9 * face.s : 0
        anchors.verticalCenter: Theme.material ? undefined : parent.verticalCenter
        height: (Theme.material ? 8 : 4) * face.s
        radius: height / 2
        color: Theme.material ? Theme.surfaceContainerHighest : Theme.threadBg
        clip: true
        Behavior on height {
            enabled: Style.transitioning
            NumberAnimation { duration: Style.transitionDuration; easing.type: Easing.InOutCubic }
        }
        Behavior on color {
            enabled: Style.transitioning
            ColorAnimation { duration: Style.transitionDuration; easing.type: Easing.InOutCubic }
        }

        Rectangle {
            id: levelFill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * face.displayFill
            radius: parent.radius
            gradient: Theme.material ? null : face.fillGradient
            color: Theme.material ? face.materialFillColor
                                  : (face.fillGradient ? "transparent" : face.fillColor)
            Behavior on width { NumberAnimation { duration: Motion.fast } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width - width / 2
                width: 10 * face.s
                height: width
                radius: width / 2
                color: face.materialFillColor
                visible: Theme.material && face.displayFill > 0
                Behavior on color {
                    enabled: Style.transitioning
                    ColorAnimation { duration: Style.transitionDuration; easing.type: Easing.InOutCubic }
                }
            }

            /**
             * The charging sweep: a soft warm band travelling along the filled
             * bar while the pack takes charge, looping for as long as the face
             * is active and `shimmerOn` holds. The gradient runs horizontal so
             * the glint sweeps along the bar (the original OsdBattery face's
             * behaviour, which a level-face merge silently flattened into a
             * 4px vertical sliver). Restarting the flash mid-charge would
             * reset the sweep, which is why battery edges never preempt a
             * running battery flash (see Osd.flash).
             */
            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 34 * face.s
                visible: face.shimmerOn && !Theme.material
                color: "transparent"
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00ffffff" }
                    GradientStop { position: 0.5; color: "#55ffe6d6" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
                NumberAnimation on x {
                    from: -34 * face.s
                    to: levelFill.width
                    duration: 1200
                    loops: Animation.Infinite
                    running: face.active && face.shimmerOn
                }
            }

        }

        MouseArea {
            anchors.fill: parent
            enabled: Theme.material && face.levelInteractive && face.active
            preventStealing: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

            function setFromX(x) {
                face.dragValue = Math.max(0, Math.min(1, x / width));
            }

            onPressed: mouse => {
                face.dragging = true;
                setFromX(mouse.x);
            }
            onPositionChanged: mouse => {
                if (pressed)
                    setFromX(mouse.x);
            }
            onReleased: {
                face.levelRequested(face.dragValue);
                face.dragging = false;
            }
            onCanceled: face.dragging = false
        }
    }
}
