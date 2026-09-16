# Silhouette Settings

The shell's settings window: a dark, macOS-System-Settings-inspired control panel
with a rail of pages and one card per group of settings.

This tree is the **standalone config**, kept as the backup while the app is folded
into the shell. The copy that keeps changing is
`silhouette-shell/modules/settingsapp/`; everything below still describes a config
you run on its own, with `qs -p ~/.config/quickshell/silhouette-shell-settings`.

It edits the same state the shell does:

- the shell's own flags in `~/.local/state/ricelin/flags.json`, which the running
  shell watches, so an edit applies live — no reload, no IPC round trip;
- the Hyprland config it is built around (`~/.config/hypr/modules/*.lua`), written
  in place and applied with a reload, the way the shell's own settings surfaces do
  it.

## Running

```bash
qs -p ~/.config/quickshell/silhouette-shell-settings
```

Which opens the window: running this config *is* the launch. To drive an instance
that is already up instead:

```bash
qs -c silhouette-shell-settings ipc call settings hide   # show / hide / toggle
```

`SUPER+comma` does **not** run any of these any more. The bind points at the
shell's `settings` target (`qs -c silhouette-shell ipc call settings toggle`),
because the shell hosts a copy of this app and is always alive — and because
`qs ipc call` reaches a running instance only, it never starts one, so a bind
aimed at a config nobody launched is a bind that does nothing.

`Escape` closes the window. `RICELIN_HYPR_DIR` overrides where the Hyprland
config is looked for (see `services/Paths.qml`).

## Layout

A `qmldir` per directory, one type per file, `qs.*` imports, and a composition
root that names modules rather than implementing them — the shell's conventions.

```
shell.qml                  entry point: ShellRoot + FloatingWindow + Panel + IPC
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
utils/lua/                 the Lua field read/write helpers (see "Lua helpers")
utils/keybinds/            keychord.js (key capture) and spacebinds.js, this app's
                           special-workspace bind editor
pages/                     qs.pages — what is configurable
  Pages.qml                  the index: pages, search, row flattening
  BarIsland.qml … Updates.qml  one singleton per page (Look, Input, Displays, …)
  DisplaysView.qml            the displays body (rows built at runtime)
  WorkspacesView.qml          the spaces body (list, apps, create form)
  UpdatesView.qml             the updates body (status, pending, results)
components/                qs.components — chrome and layout primitives
  Panel.qml                  the window surface (square, opaque) + open tween
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

A page is either data (`groups`) or a `view`: the three pages whose controls
cannot be written as row descriptors — Displays (one card per monitor), Workspaces
(a list that carries its own create/remove state) and Updates (a status and a
pending list) — declare `view: Qt.resolvedUrl("…View.qml")` and own their body.
Their rows still go through the same door: a row built at runtime carries `get` and
`set` closures, which `Sources` prefers over a named source.

Displays also shows *what* it is configuring, which the other pages do not have to:
`DisplayMap` draws the arrangement and each monitor gets a `DisplayHeader` portrait
above its card. Both are built out of one component, `DisplayShape`, which is a pure
view of a live monitor — the same piece of hardware at two sizes, so the map tile
and the portrait cannot disagree.

## The rail

`Pages.navEntries(query)` returns `{ index, page, hits, nameMatch }` per page: the
page itself when its name or `keywords` match, and `hits` — the rows of that page
that match the whole query. So the rail lists pages, and under a matching page the
settings inside it, which is what makes "search a setting" mean opening the setting
rather than the page it lives on.

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
| `label` / `caption` | the two text lines of the row |
| `type` | `toggle`, `slider`, `segmented` or `text` |
| `min` / `max` / `step` | slider bounds (step 0 = continuous) |
| `unit` / `displayScale` | value formatting; `displayScale: 100` turns 0.7 into `70 %`. An empty `unit` is meaningful: bare fractions |
| `format` | `"time"` renders a minutes-of-day value as `HH:MM` |
| `options` / `names` | segmented values and their labels (equal lengths) |
| `reset` | the shipped default Reset writes back |

## Adding things

**A page.** Write `pages/Whatever.qml` (copy a neighbour: `pragma Singleton`, a
`name`/`icon`, and `groups`), add one line to `pages/qmldir`, and one entry to
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

`shell.qml` hosts the app in a `FloatingWindow` — a compositor-managed window, not
a layer surface — so the corner radius and the 1px edge are Hyprland's, from
`decoration.rounding` (12 on this config) and `col.active_border`. `Panel` therefore
paints a **square, opaque** surface out to the window's edges and animates the
content rather than the surface.

That being the case, the dialog shape is the config's to decide, and
`~/.config/hypr/modules/window-rules.lua` has a `settings-dialog` rule that matches
this window (Quickshell's app id plus this title) and makes it float, 900x560, centred:

```lua
hl.window_rule({
    name  = "settings-dialog",
    match = { class = "org.quickshell", title = "Silhouette Settings" },
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
- **Updates.** The shell's Updates surface drives a rice-engine contract
  (`behind`, `changelog`, `conflicts`, `missingDeps`, `version`, then a shell
  relaunch). The script this config ships — `scripts/ricelin-update.py` — is a
  *package* updater with a different contract entirely (`check` → `updates` +
  `packages`; `apply` → `results` + `rebootNeeded`). Pointing the shell's view at
  it reads fields that never arrive: no `behind` reads as "0 updates", so it would
  say "Up to date" with a pending upgrade in front of it. This page reads the
  contract the script defines, which is why it offers a check, an upgrade, a
  security-only upgrade and a reboot hint, and nothing about conflicts or shell
  relaunches.
- **Animation style, not bezier handles.** The config defines a whole curve and
  leaf set per style (`animationStyle = "liquid" | "pill" | "macos"`), so the
  Motion page offers the style, the master switch and the speed — which is
  branch-aware: it reads the active style's leaves, and writes the speed to every
  leaf.
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
