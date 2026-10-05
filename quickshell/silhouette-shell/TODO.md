# Project TODO

## Theme Handling Verification

### AmeBody.qml Canvas Colors

Do not treat the following as a bug:

```qml rgba(...) ```

inside Canvas `fillStyle` values.

Notes:

* These are valid CSS color strings.
* Canvas accepts these values correctly.
* This differs from the incorrect `Theme.qml` usage and should not be grouped
  together.

### Broken color strings inside the Theme.qml

Seven or so color strings inside the Theme.qml paint pure black this is because
the theming string for them is broken. Instead of faking it just make it print
pure black this would make it much nicer to look at but would these broken
theming strings make it so that the dynamic theme that matches the wallpaper
breaks? If so keep them for that. Don't fix them and get the other colors I
like having those blacks, but for the dynamic theme fix them for that and make
it match up nicely so that the theme is not horrid.

---

# UI / UX Improvements

---

## Clock on the pill Rest surface

The clock on the rest surface of the pill gets recalculated/moved everytime a
surface closes and it goes back to the rest surfface, why is this the case? I
understand while audio is playing it makes sense but at all times like when
closing the mixer, power, or any other surface and closing the surface back
into the rest surface causes this.

# Notification System Improvements

## Goal

Expand notification support and improve notification presentation.

## Requirements

### Notification Collection

Support collecting notifications from more sources, including:

* Applications.
* Git-related tools.
* Other system integrations.

How would we do this? If it is too hard let's try not to add to much complexity
to an already working thing.

### Notification Sound

Add an optional notification received sound effect.

Requirements:

* Sound should be configurable.
* Investigate the notification sound implementation used by ChillPill-shell as
  inspiration, or just use their sound.

### Settings Integration

Add notification controls inside Settings:

* Notification system toggle.
* Default state: disabled.

---

# Toast Surface Artifact Fixes

## Problem

Notification and music toast surfaces can leave visual artifacts when closing.

## Requirements

* Prevent surfaces from closing before important visual elements disappear.
* Cover art must fully disappear before surface destruction.
* Create custom transition logic between:

  * Toast surface.
  * Workspace switcher.

Goal:

* Eliminate leftover rendering artifacts.
* Ensure smooth surface replacement.

---

# Workspace Switching Through Pill Drag

## Goal

Allow workspace switching through dragging/swiping on the pill rest surface.

## Interaction Requirements

### Drag Behavior

Dragging horizontally on the rest surface should:

* Open workspace switching.
* Move toward the selected direction.

Example:

* Drag left → move right.
* Drag right → move left.

(The directional mapping should follow the current intended interaction model.)

### Visual Behavior

The physical pill capsule should not move.

Instead:

* Only internal pill content should respond.
* On click-and-hold:

  * Open workspace surface.
  * Display the Ame bead movement animation already used.

### Lazy Loading

Workspace drag functionality should:

* Be lazy-loaded.
* Avoid loading until interaction begins.
* Reload only when the user clicks and holds the pill.

### Hover Integration

Current behavior:

* Hovering over the pill opens the hover surface.

Required:

* Make drag interaction available through the hover surface as well.
* Maintain consistent behavior between click-hold and hover interactions.

---

# Documentation

---

# Shell Design Philosophy Document

## Goal

Create a single Markdown document describing the principles behind Silhouette
Shell.

Suggested file:

``` DESIGN_PHILOSOPHY.md ```

## Include

### Design Goals

Document:

* What the shell is trying to achieve.
* What problems it solves.
* What it intentionally avoids.

### Architecture Decisions

Explain:

* Why systems are separated.
* Why certain modules exist.
* Why certain approaches were rejected.

### UI Philosophy

Document:

* Interaction principles.
* Visual hierarchy.
* Minimal interaction philosophy.
* Relationship between information density and usability.

### Performance Goals

Include:

* Memory targets.
* Startup expectations.
* Runtime efficiency principles.

### Animation Principles

Document:

* Motion philosophy.
* Timing principles.
* How transitions should feel.
* When animation should and should not be used.

### Minimalism vs Functionality

Explain:

* How features should justify their existence.
* How complexity should be controlled.
* How useful functionality can exist without becoming clutter.

### Future Feature Guidelines

Define:

* How new features should integrate.
* What standards new modules must meet.
* How future expansion should preserve the shell's identity.

---

# Shell-improvement survey (2026-10-04) — not done

Two items from the shell-improvement survey are not done. Everything else from
that pass is committed. This section is here so the reasoning survives even
though the implementation did not.

## Verification setup (needed by both)

Both items are recorder/toast work and need more than an offscreen harness:

- The recorder items need a real portal run. The picker is detected with
  `hyprctl clients -j`, and the **user has to click it** — it cannot be
  automated.
- Run the shell's own config so the paths under test are the real ones:
  `qs -p ~/.config/quickshell/silhouette-shell -d`, then watch
  `quickshell log -i <instance>`.
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

- `services/Notifs.qml` — `expandedEntries`, `entryExpanded(e)`, `toggleEntry(e)`,
  `pruneExpandedEntries()`. Reuse it; a notification open in the inbox and
  open in its toast should agree.
- `Toast.qml:36` — replace the local `expanded` with a binding onto that map,
  read **directly** rather than through a function. See the comment at
  `NotifRow.qml` for why: `readonly property bool expanded:
  Notifs.expandedEntries[String(n.id)] === true`. A read hidden inside a called
  function is fine in general (verified — QML captures it), but the direct read
  is what the row does and matching it keeps one idiom.
- `Toast.qml:159` — the tap that toggles should call the service, not assign
  the local property.
- `Toast.qml:73` — the reset-on-`notif`-change must not fire for the *same*
  id, or it fights the reload persistence now in `Flags.notifOpenEntries`.

**Verify.** Expand a toast, let it expire, reopen the same notification: it
should still be open. Then send a *different* notification and confirm it comes
back collapsed. Confirm the expiry timer still holds while open and still fires
when collapsed (that behaviour is already tested — do not regress it).

---

## 2. Real frame rate for the portal recording fallback

**Where:** `utils/recording/portal_capture.py`, and
`services/RecEngine.qml` / `services/ScreenRec.qml` for the flags.

**The measured problem.** The XDG Desktop Portal screencast node on this
machine delivers roughly **1–1.7 fps**. It is damage-driven: it only produces a
frame when the screen content actually changes. A static screen therefore
yields almost nothing, and the recording is choppy even though everything
"works" — the recent-list entry and thumbnail are both produced correctly, which
is why this hid for so long.

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
portal stalls for two seconds, how the file duration is derived, whether
`-vf fps=N` is still wanted, and what `ScreenRec` shows while the real rate is
being measured.

**Suggested order.**

1. Decide whether to hold frames client-side (duplicate the last frame to reach
   a target rate) or to let ffmpeg do it (`-vf fps=60`). The latter is a
   one-line change and buys smooth playback for a static screen, at the cost of
   a file whose wall-clock duration is right but whose content is mostly
   duplicates. Worth doing first precisely because it is cheap and reversible.
2. Only then consider `pw-loop`, and measure before and after: record 10s of a
   static screen and a 10s scroll, and compare frame counts with `ffprobe`.

**Do not** re-add a hardcoded `-framerate` cap. The probe exists because a
capped rate desynchronised audio from video.

---

## 3. Coalesce the recorder's two pollers

Smaller than the two above, and only listed here for completeness — it is a
tidiness item, not a bug.

`services/RecEngine.qml:295` spawns `pgrep -f "(^|/)gpu-screen-recorder|portal_capture.py"`
on a timer, and the fallback path separately watches for the `.capturing`
sentinel file (`ScreenRec.qml:112`, `ffMarkerPath`). Two processes and two
timers watching the same question — "has the recorder actually started?" — for
one answer.

One watcher answering both would remove a process spawn per tick. Low value on
its own; worth doing if the recorder is ever touched again, since the two
pollers can disagree for a tick and show a contradictory state.
