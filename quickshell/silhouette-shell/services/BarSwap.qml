pragma Singleton

import QtQuick
import Quickshell
import qs.services

/**
 * The choreography of the swap between the pill and the minimal dwm-style bar.
 *
 * The top edge has one presentation at a time, but the change between them used
 * to be a hard cut: `Flags.barEnabled` flipped, the pill's LazyLoader emptied and
 * the bar's filled in the same frame, and the only thing that crossed the gap
 * was a blank stretch of screen. This service is the clock that gap is played
 * against, so every surface involved in the swap can read the same instant and
 * nothing has to time itself.
 *
 * The order is the one the eye wants. To the bar: the pill leaves first — it
 * flies up off the top edge and fades exactly as it does for a fullscreen
 * window, which is a motion the user already knows — and only once it has gone
 * does the bar drop, as a solid strip with no words in it, with its readouts
 * fading up behind that. To the pill: the same script played backwards, the bar
 * collapsing first and the pill coming down into the space it left.
 *
 * The pill's share of the clock is deliberately short (see `handoff`). It is
 * leaving, not arriving, and the bar is what the eye is meant to be watching.
 *
 * The corners are deliberately *not* on this clock. They used to be — they faded
 * out with the pill and back in with it — but fading them back in over a slice of
 * the swap meant they arrived at full radius and merely faint, which reads as a
 * pop rather than a return. Game mode has always done the better thing: it drives
 * the corner *radius* to zero through `ScreenCornerRoot`'s own
 * `Behavior on cornerSize`, so a corner grows back out of the radius it
 * collapsed into. The bar is folded into that same condition, so turning the bar
 * off plays exactly the motion game mode plays when it is turned off. See
 * `dissolving` in `ScreenCornerRoot`.
 *
 * The whole thing is `PROGRESS` milliseconds and every consumer reads its own
 * slice of it, so the phases cannot drift apart: a change to one duration moves
 * its slice and the boundaries move with it. `Motion.mult` scales the lot, so
 * reduced-motion and the motion-speed slider shorten the swap rather than
 * removing it — the bar still arrives, it just arrives sooner.
 *
 * Presence is derived rather than stored, and that is what lets `shell.qml`
 * build and tear the two trees off the same numbers the surfaces animate with: a
 * tree is alive exactly while it still has somewhere to be seen. The pill is
 * therefore built a moment *after* the swap has been decided and dropped the
 * frame it finishes flying off, which is also why the fly-out can happen at all
 * — under a plain `!Flags.barEnabled` the pill was gone before it could move.
 *
 * A session that starts with the bar already on is not a swap: `progress` opens
 * at 1, so both presences are settled on the first frame and the bar is simply
 * up, the way it is after a config reload rather than after a press.
 */
Singleton {
    id: root

    /** Where the top edge is going: the bar, or the pill. */
    readonly property bool toBar: Flags.barEnabled

    /** The swap's clock, 0 at the moment of the switch and 1 when it has landed. */
    property real progress: 1

    /** True only while the swap is playing. */
    readonly property bool swapping: anim.running

    /** The whole swap, in ms. */
    readonly property int totalMs: Math.round(450 * Motion.mult)

    /**
     * Where the pill's stretch ends and the bar's begins.
     *
     * This is the one dial that decides how the time is spent, and the pill is
     * meant to get the short end of it. Its departure is a dismissal, not an
     * entrance: the pill is being told the top edge is not its home any more, and
     * a long flight gives the eye time to watch something that is only on its way
     * out. So it takes roughly the first quarter and the bar — which is the thing
     * actually arriving — takes the remaining three quarters. The bar needs the
     * room anyway: its strip has to travel the full height and then settle.
     */
    readonly property real handoff: 0.28

    /**
     * The pill's departure, in ms — the width of the slice its tree is kept
     * alive for.
     *
     * The pill's leave is not a slice of this clock: it is two `Behavior`s in
     * `PillOverlay`, a translate and an opacity, each running on its own
     * duration. Left on `Motion.morph` they were longer than the slice, so the
     * tree was torn down part-way through the glide and the pill disappeared in
     * mid-air — a hard cut sitting in the middle of an otherwise continuous
     * move, and a second thing contributing to the flicker at the top edge.
     * Consumers time their leave against this so that it has *finished* by the
     * time the slice ends and the tree goes.
     */
    readonly property int pillExitMs: Math.round(root.handoff * root.totalMs)

    /** The bar has landed and only its words are still coming up. */
    readonly property real wordsAt: 0.62

    /** How present the pill is: 1 drawn, 0 gone. */
    readonly property real pillPresence: root.toBar
        ? 1 - root.seg(root.progress, 0, root.handoff)
        : root.seg(root.progress, root.handoff, 1)

    /** How far the bar has dropped: 0 off-screen, 1 the whole way down. */
    readonly property real barPresence: root.toBar
        ? root.seg(root.progress, root.handoff, 1)
        : 1 - root.seg(root.progress, 0, root.handoff)

    /** The bar's words, which arrive behind the strip rather than with it. */
    readonly property real barWords: root.toBar
        ? root.seg(root.progress, root.wordsAt, 1)
        : 1 - root.seg(root.progress, 0, root.wordsAt)

    /** True while the bar's tree is worth keeping alive. */
    readonly property bool barWanted: root.barPresence > 0

    /** True while the pill's tree is worth keeping alive. */
    readonly property bool pillWanted: root.pillPresence > 0

    /** One slice of the clock, clamped: 0 before `a`, 1 after `b`. */
    function seg(p, a, b) {
        if (b <= a)
            return p >= b ? 1 : 0;
        return Math.max(0, Math.min(1, (p - a) / (b - a)));
    }

    onToBarChanged: root.play()

    /** Re-run the clock from the top whenever the destination changes. */
    function play() {
        root.progress = 0;
        anim.restart();
    }

    NumberAnimation {
        id: anim
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.totalMs
        easing.type: Easing.InOutQuad
    }
}