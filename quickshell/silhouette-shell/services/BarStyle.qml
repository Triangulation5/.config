pragma Singleton
import QtQuick
import Quickshell
import qs.services

/**
 * The minimal bar's palette, derived from the shell theme so the strip follows
 * the live palette the same way the pill does — on a dynamic palette every token
 * below is the generated colour, on static it is the shipped one. One choice
 * (`Flags.barStyle`) re-tints the whole bar: `theme` keeps the palette backdrop,
 * `accent` fills the strip with the palette accent, `plain` drops the backdrop so
 * the wallpaper shows through.
 *
 * Read by Bar.qml and every block, so no block has to know which style is on.
 *
 * Beyond the trio above it also carries the strip's per-readout roles: the bar is
 * one row of text but not one colour, so the title, the two halves of the clock
 * and each status readout have a token of their own, and the `level()`
 * ladder gives the load readouts a shared way to climb from cream to accent to
 * warning without naming a colour of their own. Everything below is derived from
 * Theme, so a dynamic palette re-tints the whole strip at once; a block that
 * wanted a hue of its own would be the one thing that did not.
 *
 * The static Theme tokens are CSS `rgba(...)` strings Qt's parser does not read,
 * so they come back as an invalid colour (all-zero components). `flat()` pulls
 * the components through `Qt.rgba` to get a definite, opaque colour instead of
 * whatever an unparseable colour would otherwise render as.
 */
Singleton {
    id: root

    /** `theme` (palette backdrop), `accent` (accent fill) or `plain` (none). */
    readonly property string mode: Flags.barStyle
    /**
     * Whether the strip itself is the accent. Deliberately *not* named `onAccent`:
     * a property whose name is `on` plus a capital is read as a signal handler, and
     * one declared that way keeps whatever it computed at creation — so the flag was
     * read before the flags file had loaded and the accent style never came up.
     */
    readonly property bool accented: mode === "accent"

    /** Opaque dark ink that sits on an accent fill. */
    readonly property color ink: flat(Theme.tileBg)

    /**
     * What reads *on* the accent fill rather than under it — the digit of the lit
     * workspace tag. Normally that is the dark ink above; with the whole strip
     * filled with the accent it is the accent itself, so a blocked tag inverts
     * against the strip instead of vanishing into it.
     */
    readonly property color accentInk: accented ? flat(Theme.vermLit) : ink

    /** The strip's backdrop. */
    readonly property color bg: mode === "plain" ? "transparent"
        : (accented ? Theme.vermLit : flat(Theme.tileBg))

    /** Primary text. */
    readonly property color fg: accented ? ink : Theme.cream

    /** Secondary text: labels, a muted sink, inactive workspaces. */
    readonly property color dim: accented ? Qt.rgba(ink.r, ink.g, ink.b, 0.62) : Theme.dim

    /** The emphasis colour: the lit workspace, a charging pack. */
    readonly property color accent: accented ? ink : Theme.vermLit

    /** Warning text, e.g. a battery at the low mark. */
    readonly property color warn: accented ? ink : Theme.error

    /** The focused window's title: the strip's one long reading. */
    readonly property color title: fg

    /** The clock is two tones — the time is the reading, the date recedes. */
    readonly property color clockTime: fg
    readonly property color clockDate: dim

    /**
     * A readout's colour for a load in 0..1: the readable cream until it is worth
     * noticing, the accent past `hot`, the warning tone past `boil`. CPU and
     * memory climb the same ladder so the two blocks speak one language.
     */
    function level(frac, hot, boil) {
        if (frac >= boil)
            return warn;
        if (frac >= hot)
            return accent;
        return fg;
    }

    /** Opt-in chips behind the status readouts (`Flags.barChips`). */
    readonly property bool chips: Flags.barChips
    readonly property color chipFill: accented ? Qt.rgba(ink.r, ink.g, ink.b, 0.16) : Theme.hair
    readonly property color chipEdge: accented ? Qt.rgba(ink.r, ink.g, ink.b, 0.28) : Theme.hairSoft

    /** Flatten a Theme token into a definite, opaque colour. */
    function flat(c) {
        return Qt.rgba(c.r, c.g, c.b, 1);
    }
}
