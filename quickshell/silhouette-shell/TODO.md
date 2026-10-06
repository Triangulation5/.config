<!--toc:start-->
- [Project TODO](#project-todo)
  - [Theme Handling Verification](#theme-handling-verification)
    - [AmeBody.qml Canvas Colors](#amebodyqml-canvas-colors)
    - [Broken color strings inside the Theme.qml**Done — both halves, and the blacks are still the default.**](#broken-color-strings-inside-the-themeqmldone-both-halves-and-the-blacks-are-still-the-default)
- [UI / UX Improvements](#ui-ux-improvements)
  - [Clock on the pill Rest surface](#clock-on-the-pill-rest-surface)
- [Notification System Improvements](#notification-system-improvements)
  - [Goal](#goal)
  - [Requirements](#requirements)
    - [Notification Collection](#notification-collection)
    - [Notification Sound](#notification-sound)
    - [Settings Integration](#settings-integration)
- [Toast Surface Artifact Fixes](#toast-surface-artifact-fixes)
  - [Problem](#problem)
  - [Requirements](#requirements-1)
- [Workspace Switching Through Pill Drag](#workspace-switching-through-pill-drag)
  - [Goal](#goal-1)
  - [Interaction Requirements](#interaction-requirements)
    - [Drag Behavior](#drag-behavior)
    - [Visual Behavior](#visual-behavior)
    - [Lazy Loading](#lazy-loading)
    - [Hover Integration](#hover-integration)
- [Documentation](#documentation)
- [Shell Design Language](#shell-design-language)
  - [Goal](#goal-2)
  - [Include](#include)
    - [Design Goals](#design-goals)
    - [Architecture Decisions](#architecture-decisions)
    - [UI Philosophy](#ui-philosophy)
    - [Performance Goals](#performance-goals)
    - [Animation Principles](#animation-principles)
    - [Minimalism vs Functionality](#minimalism-vs-functionality)
    - [Future Feature Guidelines](#future-feature-guidelines)
- [Shell-improvement survey (2026-10-04) — not done](#shell-improvement-survey-2026-10-04-not-done)
  - [Verification setup (needed by both)](#verification-setup-needed-by-both)
  - [1. Toast expansion should follow the notification, not the toast](#1-toast-expansion-should-follow-the-notification-not-the-toast)
  - [2. Real frame rate for the portal recording fallback](#2-real-frame-rate-for-the-portal-recording-fallback)
  - [3. Coalesce the recorder's two pollers](#3-coalesce-the-recorders-two-pollers)
  - [4. A privacy indicator dot (recording, mic, camera)](#4-a-privacy-indicator-dot-recording-mic-camera)
  - [Create documentatoin and note down design style](#create-documentatoin-and-note-down-design-style)
  - [Comment style should be the same everywhere inside the shell](#comment-style-should-be-the-same-everywhere-inside-the-shell)
<!--toc:end-->

<!--toc:start-->
- [Project TODO](#project-todo)
  - [Theme Handling Verification](#theme-handling-verification)
    - [AmeBody.qml Canvas Colors](#amebodyqml-canvas-colors)
    - [Broken color strings inside the
      Theme.qml](#broken-color-strings-inside-the-themeqml)
- [UI / UX Improvements](#ui-ux-improvements)
  - [Clock on the pill Rest surface](#clock-on-the-pill-rest-surface)
- [Notification System Improvements](#notification-system-improvements)
  - [Goal](#goal)
  - [Requirements](#requirements)
    - [Notification Collection](#notification-collection)
    - [Notification Sound](#notification-sound)
    - [Settings Integration](#settings-integration)
- [Toast Surface Artifact Fixes](#toast-surface-artifact-fixes)
  - [Problem](#problem)
  - [Requirements](#requirements-1)
- [Workspace Switching Through Pill
  Drag](#workspace-switching-through-pill-drag)
  - [Goal](#goal-1)
  - [Interaction Requirements](#interaction-requirements)
    - [Drag Behavior](#drag-behavior)
    - [Visual Behavior](#visual-behavior)
    - [Lazy Loading](#lazy-loading)
    - [Hover Integration](#hover-integration)
- [Documentation](#documentation)
- [Shell Design Language](#shell-design-language)
  - [Goal](#goal-2)
  - [Include](#include)
    - [Design Goals](#design-goals)
    - [Architecture Decisions](#architecture-decisions)
    - [UI Philosophy](#ui-philosophy)
    - [Performance Goals](#performance-goals)
    - [Animation Principles](#animation-principles)
    - [Minimalism vs Functionality](#minimalism-vs-functionality)
    - [Future Feature Guidelines](#future-feature-guidelines)
- [Shell-improvement survey (2026-10-04) — not
  done](#shell-improvement-survey-2026-10-04-not-done)
  - [Verification setup (needed by both)](#verification-setup-needed-by-both)
  - [1. Toast expansion should follow the notification, not the
    toast](#1-toast-expansion-should-follow-the-notification-not-the-toast)
  - [2. Real frame rate for the portal recording
    fallback](#2-real-frame-rate-for-the-portal-recording-fallback)
  - [3. Coalesce the recorder's two
    pollers](#3-coalesce-the-recorders-two-pollers)
  - [4. A privacy indicator dot (recording, mic,
    camera)](#4-a-privacy-indicator-dot-recording-mic-camera)
  - [](#) <!--toc:end-->

# Project TODO

## Theme Handling Verification

### AmeBody.qml Canvas Colors

Do not treat the following as a bug:

```qml rgba(...) ```

inside Canvas `fillStyle` values.

Notes:

* These are valid CSS color strings.
* Canvas accepts these values correctly.
* This differs from the broken strings kept in the `legacy` scheme
  (`services/ColorScheme.qml`) and should not be grouped together — those are
  in a `color` property, where Qt's parser rejects them, not in a Canvas
  `fillStyle`, where the browser-style syntax is correct.

### Broken color strings inside the Theme.qml**Done — both halves, and the blacks are still the default.**

Seven color strings were painting pure black because the strings themselves were
broken (`rgba(37,37,48,1.00)` and friends are CSS, not something Qt's color
parser reads). The question was whether to repair them, and the answer turned out
to be *both*: the broken strings were kept **and** a working palette was written.

`flags.json`'s `colorScheme` picks between two static schemes, defined in
`services/ColorScheme.qml`:

- **`legacy`** (default) — the original palette, byte for byte, broken strings
  and all. The default on purpose: the black-bodied look is the one this shell
  has always had, so shipping the flag changes nothing until it is touched.
- **`vague`** — a faithful port of the vague.nvim palette, taken from the
  colorscheme's own defaults rather than from the shell's transcription of them.
  Every token is a color Qt can parse, so the surfaces that used to fall back to
  black paint the vague grey-blue they were written for: the pill's body is
  `#252530`, its tiles `#141415`, its capsules `#1c1c24`.

The dynamic/wallpaper palette was never broken — those tokens are valid hex, so
they always landed — and it still bypasses the scheme entirely, because a
generated palette is not something a flag should get to override.

Switching is instant: the flag is watched, so both the shell and the settings
window re-tint from the same file the moment the row is touched. The row is
Settings › Appearance › Palette › Colorscheme.

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

# Shell Design Language

**Done — [`DESIGN.md`](DESIGN.md).**

The design language is named **Washi**: one body of translucent paper that
morphs into whatever the moment needs, and gets out of the way again.

It replaces the "Shell Design Philosophy Document" this section used to ask for.
That draft wanted seven headings — design goals, architecture decisions, UI
philosophy, performance goals, animation principles, minimalism vs functionality,
future feature guidelines. `DESIGN.md` covers six of them as seven ordered
principles plus a token system, which is the same material organised as rules
rather than as an essay.

One heading was deliberately dropped: **Architecture Decisions**. Module
boundaries, why a singleton owns a value, why the settings app edits flags rather
than defining them — all of that is already written where it is decided, in the
header comment of the file that decides it. Moving it here would have made it
drift, which is the whole reason there is no `docs/` directory.

What `DESIGN.md` adds that the code cannot say is the part nobody would ever
write down: which design systems the shell drew from, **what was refused from
each**, and the checklist a new or redesigned surface is held to.

The philosophy itself is enforced rather than described where it can be. See
"Enforcement" in `DESIGN.md` — `utils/lint_qml.py` now fails the build on a
non-doc comment, which is the one rule of the language that was purely a
convention until now.

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

---

## 4. A privacy indicator dot (recording, mic, camera)

**Done — `services/Privacy.qml` + `modules/pill/widgets/privacy/PrivacyDot.qml`.**

Both rules are enforced rather than merely intended. Fail-visible covers a
missing `wpctl`, a non-zero exit, a hang and unparseable output; each was run
against the real service, and each shows the dot amber rather than blank.
Saying what is capturing comes from the PipeWire stream header: the names are
collected and kept, though the rest surface is 38px tall and has nowhere to
print them, so a surface with room for words still has to read them off.

Two places where reading a live `wpctl status` contradicted the shape it looks
like it should be — both found by measuring, and both corrected:

- **The `*` on a `Sources:` line is not "in use".** It was already set with
  nothing recording, because a consumed monitor marks the source running.
  Reading it pins the indicator permanently on. The real signal is a stream in
  `Streams:` whose links use `<` (capturing); `>` is playback and is ignored.
- **A missing binary never emits `exited`.** The watchdog is therefore armed
  from the cadence timer rather than from `onStarted`. Armed in `onStarted`, a
  machine with no `wpctl` on PATH waits forever and reports all clear — the
  exact inversion rule 1 forbids, and it was observed before being fixed.

Cadence is `Flags.privacyPollMs` — 1 s, floored at 500 ms so a hand-edited
flag cannot turn a spawn-per-tick into a busy loop. It started at 10 s and was
lowered because a dot that takes ten seconds to appear is a post-mortem, not an
indicator; one probe measures 12.9 ms here, so the tick is about 1.3% of a
core. Worth remembering that the first attempt to fix it changed only the
default and appeared to do nothing: the stored value always wins, and the flag
had been written to disk at 10 s already. `Flags` now migrates a row off a
superseded default on load, which is what actually reaches an existing machine.

The dot lives on the rest surface only: a version carrying the application name
was built for the hover face and taken back out, because the hover row is sized
by its contents and reserving room for a name indented the pill on every hover
for a dot that is idle almost always.

The mark is 6.6px, and the two tones are pulled back from full chroma —
`#ff5a4e` → `#e0705f` and `#ffb84d` → `#dfae63`. At full saturation a 7px dot
was the loudest thing on a 38px pill; muted to about two thirds it still reads
across a desk, and the capture tone sits a shade off the rose the download ring
uses so the two are never confused. Both are fixed across the colourschemes and
neither is one of the seven unparseable `legacy` strings.

Deliberately **not** built: a warning for a video-call app running on a
workspace *before* it opens the camera. The dot already lights the moment any
app opens the camera, Jitsi included, and a pre-camera warning would mean
guessing from the app list, which is a guess in the direction of crying wolf.
Asked and declined — recorded so it is not re-litigated as an oversight.

A small always-present indicator — a dot or glyph in the pill or bar — that
takes a distinct colour while something is capturing the user, and is otherwise
invisible. At minimum:

- **screen recording** — `ScreenRec.recording` already exists and is already
  authoritative, so this is the easy one and the right one to build first
- **microphone in use** — PipeWire, via `wpctl status` or the PipeWire node
  list; there is no Quickshell service for it
- **camera in use** — same source as the mic

**The part that matters more than the colours.** A privacy indicator is only
worth having if it cannot be wrong in the reassuring direction. Two rules:

1. **Fail visible.** If the check cannot run — the process is missing, the
parse fails, the service is unreachable — show the dot in an "unknown" colour,
or show it outright. A `try/catch` that leaves the indicator blank turns every
failure into "nothing is recording", which is exactly backwards.
2. **Show what is capturing, not just that something is.** "Something is using
the mic" is much weaker than "Firefox is using the mic". The app name is
available from the PipeWire node description in most cases.

Do not infer this from the notification server, and do not poll it on a fast
timer — that is a process spawn per tick for something that changes rarely.
Watch a PipeWire event or `wpctl status` on a slow interval, and let a
transient parse failure trip rule 1 rather than clear the dot.

**Where it would live.** `modules/pill/widgets/…` next to the other always-on
badges, fed by a small service the way `Notifs`/`ScreenRec` feed theirs. Give
it its own colour constants in `Theme` rather than reusing the alert colours,
so "recording" does not read as "something went wrong".**Note.** The `legacy`
colourscheme in `services/ColorScheme.qml` carries seven
deliberately-unparseable colour strings that paint pure black; see the top of
this file. Whatever colour is chosen for the recording state, check it is not
one of those — or put it on the `vague` scheme, which has no broken tokens at
all. (That is advice for a *new* colour, not a fix: `legacy` is the default,
and its blacks are a look, not a defect.)

## Create documentatoin and note down design style

The shell has many surfaces by now and now we need to define and name our
design style. Like Google's Material 3 Expressive and Apple's Liquid Glass, we
too need to pull from all these sources, chose which ones we are taking
inspiration from and define our own design language that we will meticulously
follow when implementing and redesigning surfaces.

## Comment style should be the same everywhere inside the shell

Everysingle comment in this codebase should be a docstyle comment.
