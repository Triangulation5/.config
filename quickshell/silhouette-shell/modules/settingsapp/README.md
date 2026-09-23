# Silhouette Settings

The shell's settings window: a dark, macOS-System-Settings-inspired control panel
with a rail of pages and one card per group of settings. It is a **module of the
shell** now — `modules/settingsapp/`, declared in its own `qmldir` and
instantiated by the shell's `shell.qml` — so the window that edits the flags and
the process that reads them are one instance instead of two watching the same
file. Its entry point is `SettingsApp.qml` (an `Item`, not a `ShellRoot`: there is
one root per process and it belongs to the shell), which owns the lifecycle and
the IPC; the window itself is `SettingsWindow.qml`, which the entry point builds
when the dialog is first opened and destroys five seconds after it closes (see
"The window itself"). The standalone config it grew up as is gone: it was the same
tree a second time, so keeping it meant two copies to change and a window that
could be launched with nothing listening behind it.

It edits the same state the shell does:

- the shell's own flags in `~/.local/state/silhouette/flags.json`, which the running
  shell watches, so an edit applies live — no reload, no IPC round trip;
- the Hyprland config it is built around (`~/.config/hypr/modules/*.lua`), written
  in place and applied with a reload, the way the shell's own settings surfaces do
  it.

## Running

Hosted by the shell — the live route, and the one the module's IPC target serves:

```bash
qs -c silhouette-shell ipc call settings toggle
```

`SUPER+comma` in the shell's `binds.lua` runs the call above — the shell is always
alive, so the bind always lands. That matters more than it looks: **`qs ipc call`
reaches a running instance only, it never starts one**, so a bind aimed at a config
that is not running does nothing at all. It is also why the app lives inside the
shell rather than beside it: there is no way to launch this window into a state
where nothing is listening for it.

Opening the dialog is `open` and not `show` because **`qs ipc` has a `show`
subcommand of its own and swallows the word**: `ipc call settings show` prints the
target list instead of reaching the app. `hide` and `toggle` are unaffected —
`toggle` is what the keybind runs.

`Escape` closes the window. `SILHOUETTE_HYPR_DIR` overrides where the Hyprland
config is looked for (see `services/Paths.qml`).

The window has an icon of its own — `assets/silhouette-settings.svg`: a cog in the
shell's accent with the shell's own pill cut out of its middle, one solid
silhouette so it still reads at 16px. Nothing inside the window draws it — the window
carries neither the mark nor a wordmark of its own — but it is what a dock, a taskbar
or the pill's own window list draws for the dialog. Both files have to be installed for that to show, since a Wayland toplevel
carries no icon of its own and the icon theme is what supplies one (`-D` creates
the parent directories):

```bash
cd ~/.config/quickshell/silhouette-shell/modules/settingsapp/assets
install -Dm644 silhouette-settings.svg ~/.local/share/icons/hicolor/scalable/apps/silhouette-settings.svg
install -Dm644 org.quickshell.desktop  ~/.local/share/applications/org.quickshell.desktop
```

**The entry is named for the app id, and that name is the point of it.** Quickshell
reports its toplevels as `org.quickshell` — a constant in the library, not something
a config can set — and everything that puts an icon beside a window resolves that id
as a *desktop entry id*. `MinimizedTray` does it in two steps: the entry whose id
equals the window class, then that entry's `Icon` from the icon theme. (That scan
reads a bound copy of the entry list — Quickshell fills `DesktopEntries.applications`
only once something binds to it, and a read from inside the function would have seen
an empty list and fallen back for every window.) A file named
`silhouette-settings.desktop` is never found by that lookup, so the icon falls back
to `application-x-executable`, the generic that reads as "no icon here" — which is
exactly what the dialog used to wear. Launchers match on the entry's `Name` instead,
so nothing is lost by naming the file for the id: it still lists as *Silhouette
Settings*, with this icon beside it.

The entry's `Exec` is the IPC call the keybind runs
(`qs -c silhouette-shell ipc call settings toggle`), so it opens the dialog the
shell already hosts rather than starting a second one. Its `StartupWMClass` and the
window rule in `modules/window-rules.lua` both say the same thing about the class,
for the matchers that read those rather than the entry id.

## Layout

A `qmldir` per directory, one type per file, `qs.*` imports, and a composition
root that names modules rather than implementing them — the shell's conventions.

```
SettingsApp.qml            the controller: open/hide/toggle, the IPC target and the
                           window's lifecycle (build on first open, tear down after close)
SettingsWindow.qml         the window itself: FloatingWindow + Panel + rail + content
config/                    qs.config — state and the row→value door
  Theme.qml                  the panel's palette, radii, type, motion
  Store.qml                  the shell's flags.json as a live, writable document
  Sources.qml                where a row's value lives, and the only way to read/write it
services/                  qs.services — one file per config document
  Paths.qml                  every Hyprland file this app edits, in one place
  Hypr.qml                   the shared debounced `hyprctl reload`
  Deco.qml                   decorations.lua: gaps, rounding, border, blur, shadow,
                             opacity, animations; plus the pill's layer rule
  Input.qml                  input.lua + env.lua + autostart.lua
  Monitors.qml               live monitors from hyprctl + the monitors.lua writer
  Spaces.qml                 spaces.lua (the user's special workspaces) and the
                             binds.lua pair that toggles each one
  Updates.qml                the config's own updater script, check and apply
  Backups.qml                the shell's *own* config: snapshot, list, restore, delete
utils/lua/                 the Lua field read/write helpers (see "Lua helpers")
utils/keybinds/            keychord.js (key capture) and spacebinds.js, this app's
                           special-workspace bind editor
pages/                     qs.pages — what is configurable
  Pages.qml                  the index: pages, search, row flattening
  Appearance.qml … Backups.qml  one singleton per page, in rail order
                             (Appearance, Look, Pill shape, Corners, Motion,
                             Timers, Bar & Island, … see Pages.qml)
  DisplaysView.qml            the displays body (rows built at runtime)
  WorkspacesView.qml          the spaces body (list, apps, create form)
  UpdatesView.qml             the updates body (status, pending, results)
  Backups.qml / BackupsView.qml  the backups page and its body (status, archives)
assets/                    the app's own icon, and the entry that points at it
  silhouette-settings.svg      the cog with the pill cut out of it (dock, taskbar,
                               window list, and the name the entry's Icon= gives)
  org.quickshell.desktop       the launcher/window entry — named for the app id,
                               which is how a window list finds its icon
components/                qs.components — chrome and layout primitives
  Panel.qml                  the window surface (square, opaque) + open tween
  Hint.qml                   the hover hint's state (a singleton: no items)
  HintLayer.qml              the one bubble every row's caption is shown by:
                             the shell's own Tooltip, worn by the hovered row
  SectionLabel.qml           a faint heading inside a card
  SettingGroup.qml           one card: heading + a row per entry
  SettingRow.qml             the row skeleton every editor is built on
  SettingResetButton.qml     the floating "Reset to Defaults"
  DisplayShape.qml           one output drawn as the hardware it is
  DisplayMap.qml             the arrangement peek: every output to scale, in place
  DisplayHeader.qml          a monitor's portrait above its card
  rows/                    qs.components.rows — one editor per row type
    SettingRowEditor.qml       dispatcher: row.type → editor
    SettingToggle.qml … SettingText.qml
modules/
  sidebar/                 qs.modules.sidebar — the rail (search + page list)
  content/                 qs.modules.content — the content column (header, body, reset)
```

Dependencies point one way: `services` (files) ← `config` (row→value) ←
`components` (rendering) ← `modules` (composition) ← `shell.qml` (wiring).
Nothing in `components/` names a page; nothing in `pages/` names a control;
**services never import `qs.config`** — that is what keeps the app loadable.

A page is either data (`groups`) or a `view`: the four pages whose controls
cannot be written as row descriptors — Displays (one card per monitor), Workspaces
(a list that carries its own create/remove state), Updates (a status and a pending
list) and Backups (the saved archives, and two actions per archive) — declare
`view: Qt.resolvedUrl("…View.qml")` and own their body.
Their rows still go through the same door: a row built at runtime carries `get` and
`set` closures, which `Sources` prefers over a named source.

Displays also shows *what* it is configuring, which the other pages do not have to:
`DisplayMap` draws the arrangement and each monitor gets a `DisplayHeader`portrait above its card. Both are built out of one component, `DisplayShape`, which is a pure
view of a live monitor — the same piece of hardware at two sizes, so the map tile
and the portrait cannot disagree.

A page's rows are built a frame's worth at a time: the content area walks the open
page's flattened rows into `SettingGroup.visibleRows`, and the view pages load
through `asynchronous: true` loaders, so a switch delegates over a few frames instead
of stalling on one. Measured, the worst hitch on a page change went from 55ms (215ms
on the first build) to under ~20ms (87ms on the first build). The budget per pass is
9ms — the larger half of a frame at 60Hz, since a pass runs about once per frame —
which is what it takes for the biggest page here (Pill shape, 45 rows) to settle in
about a quarter of a second instead of longer.

**What a card is handed has to describe the page that is open *now*.** The builder
counts rows into `builtRows`, and each card is told how many of them are its own by
subtracting its offset within the page. Those offsets were once *recorded* when the
page changed, and the page-change handler runs before the binding that fills
`pageGroups` has re-evaluated — so the offsets a card received were the outgoing
page's. Every card past the end of that shorter array read `undefined`, `Math.max`
made the sum NaN, and the `int` property truncated it to 0: a section that came up
empty and stayed empty until you left the page and came back. The offsets are
derived from `pageGroups` now, so they cannot lag the page they describe, and the
card's own row count is derived the same way. A sweep of all 18 pages, checking
every card of every page once it had settled, went from 43 failures in 44 checks to
none.


## The rail

`Pages.navEntries(query)` returns `{ index, page, hits, nameMatch }` per page: the
page itself when its name or `keywords` match, and `hits` — the rows of that page
that match the whole query. So the rail lists pages, and under a matching page the
settings inside it, which is what makes "search a setting" mean opening the setting
rather than the page it lives on.

A page is its `name`, `icon` and either `groups` or a `view`, plus `keywords` for
the pages that cannot be found by their rows (the four with a `view`, which have no
row labels for the rail to match on). There is no summary line to write: the
content header prints the open page's name and nothing beside it, because what the
page holds is already on screen under it, row by row — and the rail's own header is
gone too, so the search field is the top of the rail.

The rail's order is the subject order `Pages.qml` describes: what the shell is drawn
as, then the bar, then the input and outputs it is attached to, then the session and
its upkeep. Pages used to be appended as they were written, which is why the newest
ones — Pill shape, Backups, Corners, Timers — sat at the end beside nothing they
belong with.

A page row emits `pageSelected(index)`; a hit emits `rowRequested(index, rowKey)`.
Both go to the host, which moves the rail's own `currentIndex` — see the navigation
rule below — and sets `ContentArea.targetKey` for a hit. The content area then
scrolls that row into view and the row's card rings it, retrying briefly because
the delegate exists only once the new page has been built.

Rows are named by key (`Pages.rowKey`: the flag name, or the config field) because it
is the one identifier that survives the copies the model hands out.

The list scrolls (a `ScrollView`): at fourteen pages the tail of the rail used to be
simply unreachable, and every page added from here would have made that worse. The
search field stays fixed above it.

The rail also keeps the open page's row in view, and rolls to it when it is not
(`Sidebar.rollToCurrent`): the page can be moved from the content area's chevrons,
which never touch this list, so page eleven can be open while the rail still shows
page one. The roll is the pill calendar's wheel — a short OutBack with overshoot,
targeting the middle of the list rather than the nearest edge — and a row that is
already wholly in view is left exactly where it is, so a click never moves the rail
out from under the pointer.

Neither the rail nor the content column draws a scrollbar (`ScrollBar.vertical.policy:
AlwaysOff`, the same for horizontal): Qt's default is a light grey slab drawn *over*
the rows, which is foreign to this panel. Both still scroll — wheel, trackpad, and a
drag started over the surface — and a row cut off at the edge is the hint that there
is more.

## Where a row's value lives

A row descriptor names its value with `source` (or carries its own
`get`/`set` closures); `config/Sources.qml` resolves that to a reader and a
writer:

| source | value | written by |
| --- | --- | --- |
| `flags` (default) | a key in `Store` (the shell's `flags.json`) | `Store.set` |
| `deco` | a field in `decorations.lua` | `Deco.write`, then reload |
| `input` | a field in `input.lua` / `env.lua` | `Input.write`, then reload or `hyprctl setcursor` |
| closures | anything a page can only build at runtime | the row's own `set` |

Reads happen inside bindings, so they touch the underlying property directly
(`Deco[row.field]`) — that is what makes a row update when the shell, the
compositor or another surface changes the value.

## Row descriptors

| field | meaning |
| --- | --- |
| `key` / `field` | the flag name, or the source's field name |
| `source` | `flags` (default), `deco`, `input`, or omitted with `get`/`set` |
| `label` / `caption` | the row's name, and the caption its hover hint shows (never a line of its own) |
| `type` | `toggle`, `slider`, `segmented`, `text` or `action` |
| `min` / `max` / `step` | slider bounds (step 0 = continuous) |
| `unit` / `displayScale` | value formatting; `displayScale: 100` turns 0.7 into `70 %`. An empty `unit` is meaningful: bare fractions |
| `format` | `"time"` renders a minutes-of-day value as `HH:MM` |
| `options` / `names` | segmented values and their labels (equal lengths) |
| `reset` | the shipped default Reset writes back |
| `button` / `done` | an `action` row's button text, and the word it flips to for a moment after a press |
| `action` | the function an `action` row's button runs |

## Adding things

**A page.** Write `pages/Whatever.qml` (copy a neighbour: `pragma Singleton`, a
`name`, an `icon`, and `groups`), add one line to `pages/qmldir`, and one entry to
`pages/Pages.qml`'s `pages` array — in the position you want in the rail. The
rail, its search, the content column and Reset all read that index.

**A page with a body of its own.** If the rows cannot be written as data — they
are a list that grows, or a status, or one card per device — declare
`view: Qt.resolvedUrl("WhateverView.qml")` instead of `groups`, give the page
`keywords` so the rail can still find it, and write the body as a `ColumnLayout`
of cards (see `DisplaysView.qml`, `WorkspacesView.qml`, `UpdatesView.qml`). Rows
built in a body still go through the row editors: give a row `get`/`set` closures
and `Sources` uses them ahead of a named source.

A body that has something to *show* as well as set keeps the two apart: the
picture is a view component of its own (`DisplayShape`, `DisplayMap`,
`DisplayHeader`) that reads a model object and writes nothing, and the controls
stay the same row descriptors as everywhere else. The page's only job is the
wiring between them — a click on a map tile sets the page's `selected`, and that
is what marks the matching portrait and scrolls to it.

**A row.** Drop a descriptor into a group's `rows`:

```qml
{ source: "deco", field: "gapsIn", type: "slider", label: "Gaps inner",
  min: 0, max: 40, step: 1, unit: "px", caption: "Space between tiled windows",
  reset: 6 }
```

A `flags` row is the same with `key` instead of `field`/`source`.

**A row type.** Write `components/rows/SettingWhatever.qml` deriving from
`SettingRow`, give it a `row` property, read it through `Sources.read(root.row)`
and expose the one write path:

```qml
function commit(value) { Sources.write(root.row, value) }
```

then add it to `SettingRowEditor.qml`'s `editors` map and to
`components/rows/qmldir`. An unknown `type` is not silent: the dispatcher renders
the row's name with "No editor for row type …" and logs it.

An `action` row is the exception to that shape: it edits no value, so it reads
no source and has no `commit`. Its button runs `row.action()`, which the page
supplies as a closure — the one kind of row whose subject is the running shell
rather than a file (`SettingAction`, used by the Timers page's unload button).

**A source.** Add an entry to `Sources.handlers` and the service behind it.

**A config file.** Add it to `Paths.qml`, and give it its own service: two
services writing one file would clobber each other, which is why `decorations.lua`
(decoration table *and* animations table) is owned by `Deco` alone.

## Lua helpers

`utils/lua/*.js` are the shell's own helpers, copied so the same edits produce
byte-identical files: `fields.js` (a `name = value` field), `deco.js`
(block-scoped fields, named `hl.layer_rule`s), `input.js` (env calls, the
setcursor line), `anim.js` (the animations table, leaf speeds, a curve's
control points), `monitors.js` (parse `hyprctl monitors -j`, rewrite a monitor
block). Keep them in sync with `silhouette-shell/utils/lua/`.

`monitors.js` has grown two things the shell's copy does not have, both for the
Displays page: `parseWorkspaces` + `monitorOfWorkspace` (which output a workspace
is on — how "main" is answered when the config does not say, and one reason the
copy drifts from the shell's) and the `make`/`model`/`focused` fields it now keeps
from `hyprctl monitors -j` for a monitor's portrait. Its workspace parser reads the
number from `id` when the report has one and from `name` when it does not: current
Hyprland names a numbered workspace `"1"` with no numeric field, and a parser that
only looked for `id` silently empties the list.

`utils/keybinds/` holds `keychord.js` (the shell's captured-key mapping, for the
create form's key capture) and `spacebinds.js`, which is this app's addition: it
lists a binds file's special workspaces, and adds or removes the toggle/move pair
one space needs, reading the modifier variable off the file rather than assuming
`mod` (see the parity notes). The shell's `binds.js` is deliberately *not* copied —
its combo resolution only knows the variable name `mod`, and this config declares
`mainMod`, so it reports a taken key as free.

`insert.js` is this app's addition: it adds a field that is not in the file yet.
The shell's `setField` no-ops when the field is missing, which is right for a
hand-trimmed config but means a control that accepts a drag and changes nothing —
this config's `input.lua`, for instance, carries no `accel_profile`,
`repeat_rate`, `repeat_delay` or `numlock_by_default`. Those rows insert the
entry inside the `input` block instead and say so in the note line.

## The window itself

`SettingsWindow.qml` is a `FloatingWindow` — a compositor-managed window, not a
layer surface — so the corner radius and the 1px edge are Hyprland's, from
`decoration.rounding` (12 on this config) and `col.active_border`. `Panel` therefore
paints a **square, opaque** surface out to the window's edges and animates the
content rather than the surface.

Nothing of it exists until the dialog is first opened. `SettingsApp.qml` keeps a
bool (`built`) and a `Loader`: the first `open` flips it, which builds the whole
window — the rail, its eighteen page singletons, the content column — and closing
the dialog starts a five-second timer that flips it back, destroying the tree and
returning the memory. That is not the same thing as hiding it: a hidden window is
still a live item tree, and this one is the largest in the shell, so a dialog
opened once at the start of a session used to stay resident for the whole of it.

The loader is `asynchronous: true`, the way the pill builds its own heavy
surfaces: the first open is the only one that pays for that tree, and it pays off
the GUI thread instead of stalling every other surface while it compiles. The
host wires the two directions the window cannot own — the `open` it should draw,
and the `closeRequested` its Escape key raises — from `onItemChanged`.

The five seconds are the point at which the two behaviours meet. Close the dialog
and reopen it within them and nothing was ever torn down, so the rail is still on
the page you left it on and the search still holds its text — the quick reopen
keeps what you had. Past them the dialog is gone, and the next open builds a fresh
one: first page, empty search. The window's own `Escape` does not close anything
itself; it raises `closeRequested` and the host decides, which is what keeps one
owner of the lifecycle.

That being the case, the dialog shape is the config's to decide, and
`~/.config/hypr/modules/window-rules.lua` has a `settings-dialog` rule that matches
this window (Quickshell's app id plus this title) and makes it float, 900x560 and
centred:

```lua
hl.window_rule({
    name  = "settings-dialog",
    match = { class = "org.quickshell", title = "Silhouette Settings.*" },
    float  = true,
    size   = { 900, 560 },
    center = true,
})
```

Without it the window is a tile: it joined whatever the workspace layout was doing and
came up at the tiled size (measured here: 1258x672 beside a terminal, against the
900x560 the app lays out for). `float = true` alone is not enough either — a toplevel
floated without a size keeps the size it had, so the rule needs `size` to give the app
the dialog it was built as. Both were measured against the running compositor: with
the rule `floating=true size=[900, 560] at=[190, 96]` (centred in the usable area, i.e.
below the pill), and with `size` removed `floating=true size=[1258, 672]`.

The title is what identifies the window from out here: Quickshell's toplevels carry no
pid, so the app finds its own window in the compositor's list by title, and the rule
matches on the same string — exactly, since Hyprland anchors rule regexes. It read
`Silhouette Settings.*` while there was also a standalone copy of the app, which
appended `(standalone)` to its title so the two could tell each other's window apart;
that copy is gone, and the wildcard with it. Measured with the exact title: the dialog
comes up `floating=true size=[900, 560] at=[190, 96]`, the same numbers the wildcard
produced.

`pin = true` is deliberately absent. It is what this rule used to carry, and it
bought the wrong thing: a pinned dialog is drawn on *every* workspace, so it stacked
over whatever you switched to and would not go away. A dialog belongs to the
workspace it was opened on, like any other window.

The key stays honest without it because of how the dialog is summoned. Hyprland maps
a window on whichever workspace is focused when it maps, so opening the dialog always
lands it in front of you — measured: closed while on workspace 2, opened from
workspace 4, and it comes up on workspace 4. That leaves the one case of a dialog
left open and then walked away from, where `shown` is still true while nothing is on
screen. `show` and `toggle` therefore ask the compositor where the dialog's own
toplevel is — matched on the same title this rule matches on — and if it is not on
the focused workspace they hide and show again, which re-maps it where you are.
Measured: open on workspace 2, walk to 4, one press and the dialog is standing on 4,
where it used to take two (the first closing the invisible one). The re-map is not a
blink: sampled every 7ms right through a summon, the window never once disappears
from the compositor's client list — it moves, and with its item tree intact, so the
rail comes back on the page you left it on.

Both halves of that are load-bearing. A surface that rounds its own corners cannot
line up with the compositor's cut: a 24px arc against a 12px cut leaves a crescent of
*unpainted* pixels inside the window, and the compositor blurs the wallpaper behind an
unpainted pixel. That was a real bug here — a bluish smear in the top-right and
bottom-right corners, invisible on the left because the rail's own opaque rectangle
covered the same crescent. Measured on screen, the corner used to carry blurred
wallpaper (`max 91,111,138`, stdev 34 in blue) and now reads flat (`max 58,59,63`,
stdev 6), matching the left side. A surface caught mid-scale is the same bug in
motion, which is why the tween moves the content instead.

If the whole window ever looks faintly blurred — not just a corner — that is this
config's `decoration:inactive_opacity` (0.95), which applies to every window while it
is unfocused, and nothing the app can set from inside.

## The theme

`config/Theme.qml` is the panel's own palette — the dark surfaces and the row
metrics it was designed around — with two tokens taken from the pill, because a
settings window that highlights in a different colour from the thing it
configures reads as a different app: `accent` (the pill's `#d8647e` on the static
palette, the generated `Dyn.primary` otherwise) and `window`/`sidebar`, the
backdrop the rail and the cards sit on.

On the static palette that backdrop is **black**, and deliberately so: it is what
the pill actually paints. The shell assigns its static surfaces the string
`"rgba(37,37,48,1.00)"`, which Qt's colour parser cannot read, so `Theme.cardTop`
keeps its black default and the pill, its cards, its tiles and its capsules all
come out black. Matching the pill means matching the pixels, so `window` is
`#000000` until those strings are repaired; the note on the token itself says so,
where the next person will look. On dynamic or manual the pill paints the
generated palette — valid hex, so it lands — and this window follows it token for
token. The cards stay the app's own `#100d0d` either way.

Two tokens are worth knowing: `knob` is the ink that sits on a solid accent fill
(the toggle knob, a lit chip's label), and `border` is a hairline meant to be
barely seen. Neither is a text colour; use `text`/`textSecondary` for that.

## What the shell keeps as a constant

Every flag the shell has was already a row. What was *not* — until this pass —
were the shell's own constants: the numbers and durations living inside the
components that use them, which look like code until the first person wants a
squarer screen. They are flags now, so the settings app reaches them, and the
affected components read them the way they read every other flag:

| what | where it was | flag(s) | page |
| --- | --- | --- | --- |
| Screen-corner radii, bezel shadow, collapse time | `modules/screencorner/ScreenCornerRoot.qml` | `cornerNotchRadius`, `cornerNormalRadius`, `cornerGameRadius`, `cornerShadowSize`, `cornerMorphMs` | Corners |
| Every shell animation duration | one multiplier in `services/Motion.qml` | `motionSpeed` | Motion |
| Pill eviction sweep, hover grace, game mode's harsher override | `modules/pill/Pill.qml` timers | `pillCleanupSec`, `pillGameUnloadMs`, `pillGameSweepSec`, `pillHoverGraceMs` | Timers |
| OSD hold | `widgets/osd/Osd.qml` | `osdHoldMs` | Timers |
| Notification popup life | `services/Notifs.qml` | `notifMs`, `notifLowMs` | Timers |
| Lock field and avatar, backdrop blur and grade, bead timeline | `modules/lock/*`, `assets/shaders/grade.frag` | `lockPillW`, `lockPillH`, `lockAvatarSize`, `lockBlurSpread`, `lockBlurDarken`, `lockBlurSaturation`, `lockBlurVignette`, `lockBlurGrain`, `lockBeadMs` | Lock Screen |
| Failed-password escalation (new): log out, restart or shut down, and how many wrong tries | the lock's auth daemon, `modules/lock/Auth.qml` | `lockFailAction`, `lockFailLimit` | Lock Screen |

The motion one is worth a sentence: **one flag scales the whole shell**, because
`services/Motion.qml` is the single place durations are handed out — every
surface reads `Motion.morph`, `Motion.fast` and friends rather than a literal.
That is the shape to aim for with the rest of the list: a flag is cheap where
something already funnels, and expensive where thirty call sites each hold a
number (`notifMs` had two).

## Backups

The one page that records rather than edits. A backup is the shell's **own**
config: the tree this app is a module of (`~/.config/quickshell/silhouette-shell`)
and the state the shell keeps beside the flags — `flags.json`, the calendar's
`events.json`, the chosen wallpaper's path. It is deliberately not the Hyprland
config the rest of the app writes: those files belong to the compositor, and the
pages that edit them already own them.

One archive per backup, `silhouette-YYYY-MM-DDTHH-MM-SS.tar.gz` under
`~/.local/state/silhouette/backups/`. The work is a script — `utils/backup.py`, in
the shell tree because that tree is what it copies — and it answers the way
`silhouette-update.py` does: one JSON object per run, `create` / `list` / `restore` /
`remove`, with `status` and, on a refusal, `error`. `Backups.qml` runs it and reads
that and nothing else. Every path is overrideable (`SILHOUETTE_SHELL_DIR`,
`XDG_STATE_HOME`, `SILHOUETTE_BACKUP_DIR`, or `--shell --state --dir`), which is what
let the page be driven end to end against a scratch tree.

Three things about it are load-bearing:

- **A restore cannot leave the backup directory.** Only a bare file name of an
  archive this script wrote is accepted, and every member is checked before
  anything is extracted: an absolute path, a `..`, a symlink, or any member that
  is not the shell tree or one of the state files refuses the whole archive,
  which is then left alone.
- **A restore rolls back; it does not mirror.** Files the archive holds are
  overwritten, files it is missing are added back, and a file that arrived after
  the backup was taken is kept — restoring an old snapshot cannot take a newer
  file with it.
- **Nothing restarts.** The shell watches both halves of what a restore writes,
  so the QML hot-reloads and `flags.json` is re-read as the write lands (see
  Store). A page that killed the process it was drawn in, in order to "apply" the
  restore, would be a page that vanished mid-restore.

Restore and delete are both two-step, and the question is asked in the row it is
about: that row's buttons become the question and a cancel, and every other row
stops responding while one is asking — the same shape the Updates page uses for
the one control that changes the machine. A run that was refused says why in the
status card rather than staying silent.

## Parity with the shell's settings

Every flag the shell exposes is here, plus the Hyprland settings the shell's own
Look, Input, Animation, Display and Workspaces surfaces cover. The differences are
deliberate, and the first one in each list is the interesting kind: the shell's
surface reads a file or a contract that this config does not have.

- **Decorations.** The shell reads `modules/decoration.lua` for the Look fields;
  this config keeps them in `modules/decorations.lua` and leaves only the pill's
  layer rule in `decoration.lua`. `Paths.qml` names both, so the app edits the
  files that actually hold the values.
- **Spaces.** The shell's Workspaces page owns `spaces.lua` and expects the config
  to `require` it, so that the file binds each space's key itself. Nothing requires
  it here — this config keeps its one special workspace (`magic`, Super+S)
  hand-written in `modules/binds.lua` — so a space created in the app would toggle
  nothing. Creating or removing a space therefore also writes (or removes) its
  `toggle_special` pair in `binds.lua`, read off the file's own modifier variable,
  and never touches the config's load order. `spaces.lua` is still written in the
  shell's exact shape, because the shell does read it: for the name it shows for a
  space, and for the window classes that route into it.
- **Updates, twice.** Two updaters ship in `scripts/`, because they answer two
  different questions. `rice-update.py` is the *rice* one: which commits the
  config is behind, what the changelog is, which files clash with upstream, and
  a shell relaunch once the new code lands. The shell's own Updates surface
  drives that contract, and nothing on this page touches it.
  `silhouette-update.py` is the *package* one: `check` → `updates` +
  `packages`, `apply` → `results` + `rebootNeeded`, under pkexec. That is the
  only thing here that can truthfully answer "what updates are there", which is
  why this page reads its contract and offers a check, an upgrade, a
  security-only upgrade and a reboot hint, and nothing about conflicts or shell
  relaunches. Pointing either page at the other script reads fields that never
  arrive: no `behind` reads as "0 updates", so the surface would say "Up to
  date" with a pending upgrade in front of it.
- **Animation style, not bezier handles.** The config defines a whole curve and
  leaf set per style (`animationStyle = "liquid" | "pill" | "macos"`), so the
  Motion page offers the style, the master switch and the speed — which is
  branch-aware: it reads the active style's leaves, and writes the speed to every
  leaf.
- **Visualizer styles, including the string.** `vizStyle` picks the pill's bars, the
  mirrored bars or `FastMusicLine`'s string, so the row offers all three. The string
  runs its own cava and the shell stands the bars pipeline down when it is picked,
  rather than running two captures for one visible visualizer.
- **The pill's box is flags now.** Rest width, height and corner, the notch corner,
  hover padding, and the size of every surface (`pillLauncherW`, `pillMixerH`, …) were
  readonly constants in `Pill.qml`; they are flags the shell reads with the same
  defaults, which is what makes the Pill shape page (45 of them, six cards) a plain
  page of sliders.
- **Displays apply directly.** The shell routes a mode change through
  `scripts/display-apply.sh` with a 12-second watchdog and a confirm step. Here a
  change writes the monitor block and reloads; the watchdog is not ported, which
  is why every mode offered comes from `availableModes` and an unsupported one
  cannot be asked for. The arrangement is *read* only — clicking a tile jumps to
  that monitor's settings, but there is no drag-to-place, so a position is typed
  into the Position row. The main-monitor swap and the xrandr primary flag are not
  ported; main is shown, not settable (see below).
- **Main is read, and from three places.** Hyprland has no main-monitor setting,
  so `Monitors.mainName` answers in this order: the output a workspace_rule *loop*
  hands workspace 1 to in `monitors.lua` (what the shell reads, and what its own
  main-swap rewrites); failing that, the output `hyprctl` says workspace 1 is on
  now; failing that, the output holding the cursor. The middle step is not
  decoration — this config declares its workspaces as individual rules with
  `monitor = ""`, so the first answer is empty here and the shell's own Display
  surface marks no main at all.
- **Installing asks twice.** The upgrade is the only control here that escalates
  through pkexec and changes the machine rather than a config file, so it is behind
  a confirm step, and a failed or cancelled run is reported per command rather than
  silently retried.
- **Backups are this app's only.** Every other page here mirrors something the
  shell's own surfaces can reach; recording the shell's own tree and state, and
  putting an archive back, is not a surface the shell has at all. It is the shape
  of a settings app rather than a settings surface — you reach for it when
  something is already wrong — and it is the reason this page has a body of its
  own instead of rows.
- **Not built:** the keybind editor and the submap manager. (`spacebinds.js` covers
  the one keybind this app has to write; a full editor is the shell's surface, with
  the shell's `utils/keybinds/binds.js` behind it — which resolves combos through a
  variable named `mod`, so it does not fit a config that declares `mainMod`.)

## Conventions

**Values are bindings; writes go through one door.** Every editor reads through
`Sources.read(row)` and writes in `commit()` through `Sources.write(row, value)`.
Nothing assigns to a property that is bound from outside — an assignment deletes
the binding for good — which is why the rail's selection and the content area's
`onNavigate` work the way they do.

**Address pages by index, never by object.** An element read out of a `var` array
(or a Repeater's `modelData`) is a copy, so `indexOf` on pages silently returns
-1; the index is the page's real position in `Pages.pages`. The same reason names a
**row by its key** (`Pages.rowKey`) — the rail's hits carry it and the content area
reveals the row that answers to it.

**Replace lists, never mutate them.** A `var` property notifies on assignment, so
`list.push(...)` changes the data without re-evaluating a single binding. Services
assign a fresh array (`Spaces.list = parse(text)`, `Updates.packages = data.packages`)
for exactly this reason.

**The host owns the selection.** `shell.qml` binds `ContentArea.pageIndex` to
`sidebar.currentIndex`. The chevrons report a step through
`ContentArea.onNavigate` instead of assigning to `pageIndex`, and the rail's rows
set `currentIndex`. A direct assignment anywhere in that chain disconnects the
rail permanently.

**Layout children need real containers.** `Layout.fillWidth` is ignored inside a
plain `Column`, and a child of a plain `Item` keeps its own zero size. Slots that
hold a control are `Layout`s.

**A model-driven row must survive reuse.** Delegates are rebuilt on page
switches, so an editor derives everything from its `row` reactively rather than
being configured once at load time.

**A background belongs beside the layout, not in it.** A `Rectangle` that paints
behind a row cannot be a child of the row's layout (the layout positions it like
any other child), which is why `SettingGroup` wraps each row in a slot: the ring is
the slot's backdrop, and the slot's identity is what the reveal scrolls to.

## Behaviour worth knowing

`Store.set` updates the mirrored document and debounces a write to disk (120 ms,
so slider drags coalesce). `Store.keys` lists every mirrored flag; the shell's
internal bookkeeping keys are deliberately absent from the index.

On Displays, the arrangement map and the portraits are wired both ways: clicking a
tile (or a portrait's screen) marks that output and scrolls to its card, and the
marked tile wears the accent. The pick writes the scroll *through* the flickable
found by walking up from the page, so the page keeps working if it is ever
previewed outside a scroll view — and a pick for an output that is not on the page
(the last frame after unplugging one) does nothing instead of scrolling to nowhere.

Search matches on word starts and splits camelCase names, so "city" finds the
weather row without matching "Pill opa-city", and "gaps in" finds `gapsIn`.
Results keep the page's real index, so opening a hit lands on the page that holds
it — and on the row itself: a hit opens the page, scrolls to the row and rings it.
A view page has no row labels to find, so it carries `keywords` instead
("resolution", "scale" for Displays; "dnf", "packages" for Updates).

Reset walks the open page's rows and writes each `reset` back through its source
— flags into `flags.json`, Hyprland fields into their files. A row without a
`reset` is skipped.

A refused write is never silent: the services put a line ("Hyprland reload
failed", "Could not find … in …") in their `note`, and the content area prints it
under the cards.

A field a file does not carry yet is inserted into its block rather than refused
(`insert.js`), by the services that expect that (`Input`) and reported in their
note line. The rest refuse — `Deco`'s rule is "refuse a field the file does not
have" — because for their targets a missing field means the config was
trimmed by hand.

On Backups the list is re-read after every run instead of being patched in
memory, one tick later (a refresh refuses while a run is in flight): the directory
is the truth, and an archive can also be added or removed by hand. The two
processes are `list` and a single `run` whose command is built from its verb and
target, so the page cannot leave a run behind by navigating away — the run is the
service's, not the view's.
