<!--toc:start-->
- [Project TODO](#project-todo)
- [Shell-improvement survey (2026-10-04) — not done](#shell-improvement-survey-2026-10-04-not-done)
  - [Verification setup (needed by both)](#verification-setup-needed-by-both)
  - [1. Toast expansion should follow the notification, not the toast](#1-toast-expansion-should-follow-the-notification-not-the-toast)
  - [2. Real frame rate for the portal recording fallback](#2-real-frame-rate-for-the-portal-recording-fallback)
  - [3. Coalesce the recorder's two pollers](#3-coalesce-the-recorders-two-pollers)
<!--toc:end-->

# Project TODO

# Shell-improvement survey (2026-10-04) — not done

Two items from the shell-improvement survey are not done. Everything else from
that pass is committed. This section is here so the reasoning survives even
though the implementation did not.

## Verification setup (needed by both)

Both items are recorder/toast work and need more than an offscreen harness:

- The recorder items need a real portal run. The picker is detected with
  `hyprctl clients -j`, and the **user has to click it** — it cannot be
  automated.
- Run the shell's own config so the paths under test are the real ones: `qs -p
  ~/.config/quickshell/silhouette-shell -d`, then watch `quickshell log -i
  <instance>`.
- `console.log` does **not** reach stderr under Quickshell; `console.warn`
  does. Harnesses must use `console.warn` or their output is silently lost.
- For the recorder, the `.capturing` sentinel file and the recent-list entry
  plus thumbnail are the real success signals, not a clean exit code.

---

## 1. Toast expansion should follow the notification, not the toast

**Where:** `modules/pill/widgets/toast/Toast.qml`, and the `toastLoader` in
`modules/pill/Pill.qml` (around line 2046).

**Today.** `Toast.qml:36` has `property bool expanded: false`. The toast
carries it for its own lifetime. The consequence: open a toast to read it, let
it expire, and open the *same notification* again — it comes back collapsed,
because it is a new toast instance. The reader has to re-open the same
notification every single time, which is the exact friction the expansion
feature was added to remove.

It is worse than an annoyance in one case. `Toast.qml:58` gates the expiry
timer on `!root.expanded`, and `Toast.qml:73` resets `expanded` when `notif`
changes. So a toast that was open and is then re-bound to a different
notification drops back to a one-line elided row — the reader's context is gone
the moment the notification is reused.

**What to do.** Hold the open state on `Notifs` keyed by notification id, the
same way `Notifs.expandedEntries` already does for the inbox rows. The inbox
side is done and is the pattern to copy:

- `services/Notifs.qml` — `expandedEntries`, `entryExpanded(e)`,
  `toggleEntry(e)`, `pruneExpandedEntries()`. Reuse it; a notification open in
  the inbox and open in its toast should agree.
- `Toast.qml:36` — replace the local `expanded` with a binding onto that map,
  read **directly** rather than through a function. See the comment at
  `NotifRow.qml` for why: `readonly property bool expanded:
  Notifs.expandedEntries[String(n.id)] === true`. A read hidden inside a called
  function is fine in general (verified — QML captures it), but the direct read
  is what the row does and matching it keeps one idiom.
- `Toast.qml:159` — the tap that toggles should call the service, not assign
  the local property.
- `Toast.qml:73` — the reset-on-`notif`-change must not fire for the *same* id,
  or it fights the reload persistence now in `Flags.notifOpenEntries`.

**Verify.** Expand a toast, let it expire, reopen the same notification: it
should still be open. Then send a *different* notification and confirm it comes
back collapsed. Confirm the expiry timer still holds while open and still fires
when collapsed (that behaviour is already tested — do not regress it).

---

## 2. Real frame rate for the portal recording fallback

**Where:** `utils/recording/portal_capture.py`, and `services/RecEngine.qml` /
`services/ScreenRec.qml` for the flags.

**The measured problem.** The XDG Desktop Portal screencast node on this
machine delivers roughly **1–1.7 fps**. It is damage-driven: it only produces a
frame when the screen content actually changes. A static screen therefore
yields almost nothing, and the recording is choppy even though everything
"works" — the recent-list entry and thumbnail are both produced correctly,
which is why this hid for so long.

The existing code already stopped faking a rate. `portal_capture.py` measures
the true rate from the head of the stream (`RATE_PROBE_SECONDS = 2.0`,
`MAX_PROBE_BYTES`, `RATE_PLACEHOLDER` substituted at line 341) instead of
trusting a fixed `-framerate`. That was the right fix for *lying* about the
rate, and it is why the fallback now produces a correct file. It does not
*create* frames, so a 1.4 fps source still records at 1.4 fps.

**Why it is not a quick fix.** Closing the gap means timestamped frames from a
source that does not timestamp them — i.e. dropping to `pw-loop`/libspa and
self-timestamping on arrival. That is a rewrite of the capture path, not an
adjustment to it, and it changes the failure modes: what happens when the
portal stalls for two seconds, how the file duration is derived, whether `-vf
fps=N` is still wanted, and what `ScreenRec` shows while the real rate is being
measured.

**Suggested order.**

1. Decide whether to hold frames client-side (duplicate the last frame to reach
a target rate) or to let ffmpeg do it (`-vf fps=60`). The latter is a one-line
change and buys smooth playback for a static screen, at the cost of a file
whose wall-clock duration is right but whose content is mostly duplicates.
Worth doing first precisely because it is cheap and reversible.
2. Only then consider `pw-loop`, and measure before and after: record 10s of a
static screen and a 10s scroll, and compare frame counts with `ffprobe`.

**Do not** re-add a hardcoded `-framerate` cap. The probe exists because a
capped rate desynchronised audio from video.

---

## 3. Coalesce the recorder's two pollers

Smaller than the two above, and only listed here for completeness — it is a
tidiness item, not a bug.

`services/RecEngine.qml:295` spawns `pgrep -f
"(^|/)gpu-screen-recorder|portal_capture.py"` on a timer, and the fallback path
separately watches for the `.capturing` sentinel file (`ScreenRec.qml:112`,
`ffMarkerPath`). Two processes and two timers watching the same question — "has
the recorder actually started?" — for one answer.

One watcher answering both would remove a process spawn per tick. Low value on
its own; worth doing if the recorder is ever touched again, since the two
pollers can disagree for a tick and show a contradictory state.
