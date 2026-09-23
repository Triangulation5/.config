import QtQuick

/**
 * Probe stand-in for PillSurface's planned shape: body authors an inner
 * `fadeWrap` item, and the type's *default* property aliases into it, so
 * subclass content lands on the wrapper instead of on the surface itself.
 */
Item {
    id: surface

    default property alias content: fadeWrap.data
    readonly property alias fadeWrap: fadeWrap

    Item {
        id: fadeWrap
        anchors.fill: parent
    }
}
