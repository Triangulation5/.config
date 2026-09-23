import QtQuick
import QtQuick.Effects
import qs.services

/**
 * Shared morph-surface base for the pill's standard surfaces. Each surface fills
 * the pill body inset by its own margins (scaled by `s`), fades in with the morph
 * as it nears full openness, and dissolves out with a fast fade + blur so the
 * text clears before the pill body begins shrinking — no text artifacts during
 * the morph. Only enabled while open. The host sets `open`, `s` and
 * `morphCloseness`; the surface sets its own `mTop`/`mLeft`/`mRight`/`mBottom`
 * insets. `active` mirrors `open` for the older `onActiveChanged` hooks.
 * `requestClose()` asks the pill to dismiss.
 *
 * A deriving surface declares its content as usual: it is parented into an
 * inner wrapper (`content`), which is what carries the dissolve fade — see
 * `presence` for why the fade cannot sit on this item's own `opacity`.
 */
Item {
    id: surface

    property real s: 1.1
    property bool open: false
    property real morphCloseness: 1

    property real mTop: 0
    property real mLeft: 0
    property real mRight: 0
    property real mBottom: 0

    signal requestClose()

    /**
     * Ame anchor. Each surface declares the flame's form and dock point (in
     * surface-local coords) for its open state; the host maps the point into
     * pill space and feeds the active surface's pair to Ame. Left non-readonly
     * so a deriving surface can re-bind. Base default is off at the centre.
     */
    property string ameForm: "off"
    property point amePoint: Qt.point(width / 2, height / 2)

    /**
     * Caret docking for the "caret" ame form: returns a text field's insertion
     * point centre in surface coords, re-evaluating as the field's cursor
     * moves, the field resizes, or the surface itself morphs. Surfaces with a
     * query/password field just set `ameForm: "caret"` and
     * `amePoint: caretPointOf(field)`.
     */
    function caretPointOf(field) {
        void width;
        void height;
        void field.width;
        return field.mapToItem(surface,
            field.cursorRectangle.x + field.cursorRectangle.width / 2,
            field.cursorRectangle.y + field.cursorRectangle.height / 2);
    }

    /**
     * Row-seam docking for the "rowseam" ame form: the focused row's left-edge
     * centre in surface coords, falling back to the surface centre while no row
     * is focused. Pass any extra value the caller's binding should re-evaluate
     * on (a list's contentY, a focus index, …) as `extra`. Surfaces with a
     * focusable row registry just set `ameForm: "rowseam"` and
     * `amePoint: rowSeamPoint(focusRowItem, list.contentY)`.
     */
    function rowSeamPoint(focusItem, extra) {
        void width;
        void height;
        void extra;
        if (!focusItem)
            return Qt.point(4 * s, height / 2);
        return focusItem.mapToItem(surface, 4 * s, focusItem.height / 2);
    }

    readonly property bool active: open

    /**
     * Latched true once the open morph has first settled. The morphCloseness
     * gate is only there for the rest-to-surface open fade. After settling,
     * the surface holds full opacity so internal relayouts (collapsible
     * height changes) never cause a flicker. Reset on close so the next open
     * fades in again.
     */
    property bool settled: false
    onOpenChanged: if (!open) settled = false
    onMorphClosenessChanged: if (open && morphCloseness > 0.92) settled = true

    /** True only while the close dissolve is in progress. */
    readonly property bool closing: !open && presence > 0.005

    anchors.fill: parent
    anchors.topMargin: mTop * s
    anchors.leftMargin: mLeft * s
    anchors.rightMargin: mRight * s
    anchors.bottomMargin: mBottom * s

    enabled: open

    /**
     * Dissolve progress: 1 while the surface is fully present, falling to 0
     * across the close. Open: fade in over Motion.standard once the morph
     * nears full size. Close: fast dissolve (Motion.fast, ~140ms) so the text
     * clears well before the pill body begins its 420ms morph — no text
     * artifacts. It also drives the dissolve's blur, and is the value the
     * pill's hover face crossfades against (`Pill.closingOpacity`).
     *
     * The fade cannot ride this item's own `opacity`: once `layer.enabled` is
     * on, the item is drawn from its layer's texture, and the root's opacity
     * is dropped at that seam. The wallpaper surface showed it plainly — with
     * the close's layer up, its strip held at full strength over the shrinking
     * pill until the layer was dropped, which read as the wallpaper flashing
     * over the pill for the first frames of a close. Fading `content` puts the
     * fade inside the texture, which the layer cannot swallow.
     */
    property real presence: open ? (settled ? 1 : Math.pow(morphCloseness, 1.3)) : 0
    visible: presence > 0.005

    Behavior on presence {
        NumberAnimation {
            duration: surface.open ? Motion.standard : Motion.fast
            easing.type: surface.open ? Motion.easeStandard : Easing.OutCubic
        }
    }

    /**
     * Every deriving surface's content is parented here rather than onto the
     * surface itself, so the dissolve fade reaches each child individually.
     * The wrapper fills the inset surface rect, so a child's `parent` is the
     * same-sized item it always was and no geometry shifts.
     */
    default property alias content: fadeWrap.data
    Item {
        id: fadeWrap
        anchors.fill: parent
        opacity: surface.presence
    }

    /**
     * Blur dissolve during the close window. The layer is only enabled while
     * the dissolve is playing, so it costs nothing at rest or while open.
     * Blur ramps from 0→1 inversely with presence for a soft recession effect
     * that clears before the pill body begins its morph.
     */
    layer.enabled: surface.closing
    layer.effect: MultiEffect {
        blurEnabled: surface.closing
        blurMax: 32
        blur: surface.closing ? (1 - surface.presence) : 0
    }
}
