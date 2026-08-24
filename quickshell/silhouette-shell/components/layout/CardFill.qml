import QtQuick
import qs.services

/**
 * The standard card fill: a rectangle painted with the shell's cardTop → cardBot
 * gradient. Every surface panel (tooltip bubble, mixer menu, tray card, display
 * picker) uses the same treatment, so the gradient lives here instead of being
 * re-declared per site. Set radius, border and anchors like any Rectangle.
 */
Rectangle {
    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.cardTop }
        GradientStop { position: 1.0; color: Theme.cardBot }
    }
}
