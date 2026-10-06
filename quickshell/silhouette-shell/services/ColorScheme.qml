pragma Singleton

import QtQuick
import Quickshell
import qs.services

/**
 * The shell's colour schemes, and the one place that decides which of them is
 * live. `Theme` reads every colour from here and nothing else in the shell names
 * a palette, so picking a scheme re-tints every surface at once without a single
 * consumer being edited.
 *
 * Two schemes ship:
 *
 *   - `legacy` (default) — what the shell shipped before, byte for byte,
 *     including the seven unparseable `rgba(...)` strings described on the object
 *     below. Kept verbatim rather than repaired so the option is a true A/B
 *     against the old render instead of an approximation of it, and so shipping
 *     this flag changes nothing at all for a session that never touches it.
 *   - `vague` — a faithful port of the vague.nvim palette this shell's look was
 *     always reaching for, taken from the colorscheme's own defaults rather than
 *     from the shell's transcription of them. Every token is a colour Qt can
 *     parse, so the surfaces that used to fall back to black paint the vague
 *     grey-blue they were written for.
 *
 * `Flags.colorScheme` picks between them; it has no effect on dynamic or manual
 * palette mode, because those are generated from the wallpaper by
 * `wallcolors.py` and the generated tokens already land on valid colours. So the
 * scheme decides the *static* palette, and only the static palette — which is
 * also why the settings app reaches its own copy of this decision through its
 * store rather than importing this file (they are separate processes).
 *
 * What is a palette's and what is not: every colour that a scheme can be said to
 * choose lives in one of the two objects below, including the ones both schemes
 * currently agree on — a scheme file that stated only its differences would be a
 * patch, and the next scheme would have nothing to copy. What stays out is
 * genuinely not a palette choice and is fixed below: `error` (the shell's alarm
 * tone, which has never followed the accent), `shadow`, and the family of
 * translucent inks (`hair`, `sheen`, `frameBg`, `trackBg`, …) that is derived
 * from `cream` by an alpha rather than picked, so it re-tints with the text it
 * sits under instead of needing to be restated per scheme.
 */
Singleton {
    id: root

    /** True while the palette follows the wallpaper or the manual hue. */
    readonly property bool dyn: Flags.paletteMode !== "static"

    /**
     * The selected scheme, `"legacy"` or `"vague"`.
     *
     * Anything that is not explicitly `vague` reads as `legacy`, which is the
     * scheme the flag defaults to: a value that is neither name is a typo or a
     * flag file written by a newer shell, and the safest answer to both is the
     * one the shell already looked like.
     */
    readonly property string name: (Flags.colorScheme === "vague") ? "vague" : "legacy"

    /** The scheme `name` selects, as a whole — read the tokens off this. */
    readonly property var palette: root.name === "legacy" ? root.legacy : root.vague

    /**
     * -- the schemes -------------------------------------------------------
     */

    /**
     * `vague`: the vague.nvim palette, ported honestly. Not the default — the
     * blacks below are the look this shell has always had, and turning them into
     * a scheme rather than a bug is what makes them a choice instead of a change.
     *
     * Each token below names the vague colour it came from, because that is the
     * part a future edit needs and the hex alone does not say. The shell had
     * been carrying a transcription of this palette for a while, and the
     * transcription was the bug — see the note on `legacy` below — so this is a
     * re-read of the source rather than a repair of the copy.
     *
     * One token is not from vague: `placeholder`. The shell had already settled
     * it on `#6a6a7a`, a step above vague's `comment`, and a text placeholder
     * wants that gap to be legible rather than as invisible as a comment; vague
     * has no placeholder of its own to port.
     */
    readonly property QtObject vague: QtObject {

        /**
         * Accent — vague's `error`, which is the rose this palette is named
         * for.
         */
        readonly property string onGlow: "#d8647e"  /** error */
        readonly property string verm: "#d8647e"  /** error */
        readonly property string vermLit: "#d8647e"  /** error */
        readonly property string vermDeep: "#d8647e"  /** error */
        readonly property string vermBurn: "#d8647e"  /** error */
        readonly property string vermDim: "#606079"  /** comment */
        readonly property string vermDimDeep: "#606079"  /** comment */

        /**
         * Text — vague's `fg` for the reading tone, `floatBorder` for the
         * secondary and `comment` for the third step down.
         */
        readonly property string cream: "#cdcdcd"  /** fg */
        readonly property string bright: "#cdcdcd"  /** fg */
        readonly property string dim: "#878787"  /** floatBorder */
        readonly property string subtle: "#878787"  /** floatBorder */
        readonly property string iconDim: "#878787"  /** floatBorder */
        readonly property string faint: "#606079"  /** comment */
        readonly property string tickRest: "#cdcdcd"  /** fg */
        readonly property string placeholder: "#6a6a7a"

        /**
         * Surfaces — the ramp vague draws its own panes on: `bg` for the
         * backdrop, `inactiveBg` for a capsule, `line` for a raised card and
         * `visual` for the highlight of a selection.
         */
        readonly property string tileBg: "#141415"  /** bg */
        readonly property string capsule: "#1c1c24"  /** inactiveBg */
        readonly property string cardTop: "#252530"  /** line */
        readonly property string cardBot: "#252530"  /** line */
        readonly property string ghost: "#333738"  /** visual */

        /** Edges — vague's `comment`, the one outline it has. */
        readonly property string border: "#606079"  /** comment */
        readonly property string capsuleBorder: "#606079"  /** comment */

        /** The flame, and the calendar's warm day marker. */
        readonly property string flameCore: "#d8647e"  /** error */
        readonly property string flameGlow: "#d8647e"  /** error */
        readonly property string flameInk: "#d8647e"  /** error */
        readonly property string flameEmber: "#d8647e"  /** error */
        readonly property string flameBurn: "#d8647e"  /** error */
        readonly property string flameTip: "#cdcdcd"  /** fg */
        readonly property string todayWarm: "#f3be7c"  /** warning */
    }

    /**
     * `legacy`: the shell's original static palette, preserved exactly.
     *
     * Seven of the strings below are CSS `rgba(r,g,b,a)` rather than something
     * Qt's colour parser reads. Assigned to a `color` property they do not fail
     * loudly and they do not render as the colour they were written for — they
     * resolve to transparent black, so the pill's body, its cards, its capsules
     * and both outlines have all painted flat black since the theme was ported.
     * That was left alone on purpose: the look it produces is liked, and
     * "repair" was the wrong word for it. Here it is a scheme in its own right
     * rather than a bug, which is what makes it worth keeping.
     *
     * The seven, by what they were meant to be: `cardTop`, `cardBot` and `ghost`
     * are `rgba(37,37,48,1)` — `#252530`, the same `line` the vague scheme reads;
     * `border` and `capsuleBorder` are `rgba(96,96,121,1)` — `#606079`, its
     * `comment`; `tileBg` is `rgba(20,20,21,1)` — `#141415`, its `bg`; and
     * `capsule` is `rgba(34,34,44,1)`, which the port had rounded off to a
     * colour vague does not actually publish. Every one of them is reachable on
     * the `vague` scheme, so nothing this object holds is lost by switching —
     * which is also why it is worth keeping: the two schemes are not "broken"
     * and "fixed", they are the look the shell has and the look it can have.
     *
     * Do not repair these strings here. Repairing them here changes what
     * `legacy` *is*, and this file is the reason it is still available.
     */
    readonly property QtObject legacy: QtObject {

        readonly property string onGlow: "#d8647e"
        readonly property string verm: "#d8647e"
        readonly property string vermLit: "#d8647e"
        readonly property string vermDeep: "#d8647e"
        readonly property string vermBurn: "#d8647e"
        readonly property string vermDim: "#606079"
        readonly property string vermDimDeep: "#606079"

        readonly property string cream: "#cdcdcd"
        readonly property string bright: "#cdcdcd"
        readonly property string dim: "#878787"
        readonly property string subtle: "#878787"
        readonly property string iconDim: "#878787"
        readonly property string faint: "#606079"
        readonly property string tickRest: "#cdcdcd"
        readonly property string placeholder: "#6a6a7a"

        readonly property string tileBg: "rgba(20,20,21,1.00)"
        readonly property string capsule: "rgba(34,34,44,1.00)"
        readonly property string cardTop: "rgba(37,37,48,1.00)"
        readonly property string cardBot: "rgba(37,37,48,1.00)"
        readonly property string ghost: "rgba(37,37,48,1.00)"

        readonly property string border: "rgba(96,96,121,1.00)"
        readonly property string capsuleBorder: "rgba(96,96,121,1.00)"

        readonly property string flameCore: "#d8647e"
        readonly property string flameGlow: "#d8647e"
        readonly property string flameInk: "#d8647e"
        readonly property string flameEmber: "#d8647e"
        readonly property string flameBurn: "#d8647e"
        readonly property string flameTip: "#cdcdcd"
        readonly property string todayWarm: "#f3be7c"
    }

    /**
     * -- the live palette --------------------------------------------------
     *
     * Dynamic and manual mode bypass the scheme entirely and take the generated
     * palette: those tokens are real hex, so they have always landed, and they
     * are what re-tints the shell when the wallpaper changes.
     *
     * Every scheme token is declared as a `string`, and that is load-bearing
     * rather than incidental. QML parses a string *literal* assigned straight
     * to a `color` property at compile time and rejects what it cannot read,
     * but it converts a value arriving at the property at runtime and accepts
     * anything, falling back to an invalid — and therefore transparent black —
     * colour. So `legacy` could only ever have reached a `color` property
     * through the `dyn ? … : …` shape below, and it still does. Declaring the
     * schemes as strings rather than colours is what keeps that path available
     * to the next scheme someone writes.
     */

    readonly property color onGlow: dyn ? Dyn.primary : palette.onGlow
    readonly property color verm: dyn ? Qt.darker(Dyn.primary, 1.18) : palette.verm
    readonly property color vermLit: dyn ? Dyn.primary : palette.vermLit
    readonly property color vermDeep: dyn ? Dyn.primaryContainer : palette.vermDeep

    readonly property color cream: dyn ? Dyn.cream : palette.cream
    readonly property color bright: dyn ? Dyn.bright : palette.bright
    readonly property color dim: dyn ? Dyn.dim : palette.dim

    readonly property color cardTop: dyn ? Dyn.surfaceContainerHigh : palette.cardTop
    readonly property color cardBot: dyn ? Dyn.surfaceContainerLow : palette.cardBot

    readonly property color border: dyn ? Qt.rgba(Dyn.outlineVariant.r, Dyn.outlineVariant.g, Dyn.outlineVariant.b, 1.00) : palette.border

    readonly property color tileBg: dyn ? Dyn.surface : palette.tileBg

    readonly property color subtle: dyn ? Dyn.subtle : palette.subtle
    readonly property color faint: dyn ? Dyn.faint : palette.faint
    readonly property color iconDim: dyn ? Dyn.iconDim : palette.iconDim

    readonly property color vermDim: dyn ? Qt.darker(Dyn.primary, 1.5) : palette.vermDim
    readonly property color vermDimDeep: dyn ? Qt.darker(Dyn.primary, 2.2) : palette.vermDimDeep
    readonly property color vermBurn: dyn ? Qt.darker(Dyn.primaryContainer, 1.1) : palette.vermBurn

    readonly property color tickRest: dyn ? Dyn.tickRest : palette.tickRest

    readonly property color ghost: dyn ? Dyn.surfaceContainerHighest : palette.ghost

    readonly property color capsule: dyn ? Dyn.surfaceContainerHigh : palette.capsule
    readonly property color capsuleBorder: dyn ? Qt.rgba(Dyn.outline.r, Dyn.outline.g, Dyn.outline.b, 1.00) : palette.capsuleBorder

    readonly property color placeholder: dyn ? Dyn.dim : palette.placeholder

    readonly property color flameCore: dyn ? Qt.lighter(onGlow, 1.03) : palette.flameCore
    readonly property color flameGlow: dyn ? onGlow : palette.flameGlow
    readonly property string flameInk: dyn ? Dyn.primary : palette.flameInk
    readonly property string flameEmber: dyn ? Dyn.primaryContainer : palette.flameEmber
    readonly property string flameBurn: dyn ? Dyn.primaryContainer : palette.flameBurn
    readonly property string flameTip: dyn ? Dyn.primaryContainerInk : palette.flameTip

    readonly property color todayWarm: dyn ? onGlow : palette.todayWarm

    /**
     * -- what no scheme gets a vote on -------------------------------------
     *
     * The alarm tone is the shell's own and has never followed the accent: it
     * is what a failed recording or a denied polkit request reads as, and a
     * scheme that dimmed it would be hiding a failure rather than styling it.
     */

    readonly property color error: "#e0533f"

    /**
     * Privacy: something is capturing, and we could not find out.
     *
     * These two are fixed in every scheme *and* in dynamic mode, which is the
     * opposite of every token above and deliberate. A capture indicator that
     * takes its colour from the wallpaper can be made invisible by a pale
     * desktop, and an indicator that can be made invisible by the wallpaper is
     * not an indicator. The same reasoning that puts `error` outside the
     * schemes applies harder here: this is a safety signal, not a style.
     *
     * `privacyCapture` is a soft coral — warm like `flameGlow` and `todayWarm`
     * so it sits in the palette rather than on top of it, but a shade off the
     * rose the download ring uses, so "recording" is never confused with a
     * download and never reads as "something went wrong". `privacyUnknown` is
     * amber, the universal "?": clearly not the capture tone, and clearly not
     * idle either.
     *
     * Both were pulled back from fully saturated vermilion and amber. At full
     * chroma a 7px dot is the loudest thing on a 38px pill; muted to roughly
     * two-thirds they still read at a glance across a desk, which is the whole
     * job, without the pill looking like an alarm.
     *
     * Checked against the note on `legacy` above: neither is one of the seven
     * unparseable strings, so both render identically on both schemes.
     */
    readonly property color privacyCapture: "#e0705f"
    readonly property color privacyUnknown: "#dfae63"

    /**
     * Translucent inks, derived from `cream` rather than picked. A hairline is
     * the text colour at low alpha, so it stays legible against whatever it sits
     * on instead of being a second, separately-tuned grey that drifts from the
     * text it is drawing.
     */
    readonly property color hair: Qt.alpha(cream, 0.13)
    readonly property color hairSoft: Qt.alpha(cream, 0.08)
    readonly property color sheen: Qt.alpha(cream, 0.07)
    readonly property color threadBg: Qt.alpha(cream, 0.13)
    readonly property color trackBg: Qt.alpha(cream, 0.10)
    readonly property color frameBg: Qt.alpha(cream, 0.055)
    readonly property color frameBorder: Qt.alpha(cream, 0.10)
    readonly property color creamMenu: Qt.alpha(cream, 0.82)
}
