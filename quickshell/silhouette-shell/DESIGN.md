# Washi

**The design language of SilhouetteShell.**

One body of translucent paper that morphs into whatever the moment needs, and
gets out of the way again.

That sentence is the whole language. Everything below is what it commits to, so
that a surface built today and one rebuilt next year read as the same shell.

This is the document the `TODO.md` design-philosophy goal asked for. It is a
root file, not something under `docs/`, for the reason the README gives: prose
written a directory away from the code is prose that drifts. The rules that can be
mechanically checked are checked — see [Enforcement](#enforcement).

---

## What we took, and what we refused

A design language is a set of refusals as much as a set of choices. Each source
below was studied, and only the parts that survive contact with a top edge were
kept.

### Ricelin and Ukishima — the base

Gakuseei's [Ricelin](https://github.com/Gakuseei/Ricelin) gave us the pill: a
single element at the top edge that grows into whatever surface you need.
[Ukishima](https://github.com/amanhex/ukishima) shares that base.

- **Taken:** the pill as the shell's one body. Not a bar with windows opening
  from it — an object that *is* the menu, the mixer and the clock, in different
  states.
- **Refused:** nothing. This is the origin, and everything else is measured
  against it.

### Material 3 Expressive

Google's expressive branch of Material 3 argues that shape, colour and motion
should carry feeling, not just hierarchy.

- **Taken:** shape as expression. The silhouette is a decision, not a default —
  a stadium for a capsule, a square for a search field, a squircle for a card.
  And the discipline underneath it: a design system is a token table, and a
  component that invents a colour is a bug.
- **Refused:** density, and the conviction that everything is a card. Material
  stacks surfaces; we have one, and the pill is at the top of the screen where
  it will occlude whatever is behind it. It also refuses material translucency
  — its surfaces are opaque by design.

### Liquid Glass

Apple's rendering of depth through layered, light-catching material.

- **Taken:** translucency as *depth*, not decoration. The glass tells you what is
  behind it, so a surface has depth and an edge reads as a lift. Also the
  specular highlight — a thin bright rim where light catches a rounded edge.
- **Refused:** the refraction. Distortion, lensing and the constant float turn a
  working desktop into a showroom, and they cost a full-screen blur per frame.
  When legibility and effect disagree, effect loses — see
  [Legibility outranks effect](#1-legibility-outranks-effect).

### Washi — the material itself

Rice paper. The shell's palettes already carry the name; this is where it comes
from.

- **Taken:** uneven translucency. Real washi passes light through with a grain
  and a slight warmth — not a uniform 50% grey scrim. Our equivalent is the
  low-chroma warm-black of the surface ramp and the alpha-derived hairlines
  (`hair`, `sheen`, `frameBg`) rather than a flat overlay.
- **Refused:** the fibre. Literal paper texture is noise, and it fights text.

### Vague.nvim

The palette this shell's colours come from (`services/ColorScheme.qml`).

- **Taken:** palette discipline. A near-neutral grey ramp, exactly one accent,
  and a warm off-white for primary text — so colour in the UI always means
  something.
- **Refused:** syntax colours as UI colours. Vague is an editor theme; its
  dozen hues have no business being surface and state colours in a shell.

### Fluent / acrylic

Microsoft's take on the same translucency problem.

- **Taken:** the economy of a single accent doing all the emphasis work.
- **Refused:** unconditional blur. Acrylic blurs because Windows blurs. Here
  blur is a per-surface choice with a global off switch (`liteMode`), because
  on integrated GPUs it is the entire frame budget.

---

## Principles

Seven. They are ordered: a later one never overrides an earlier one.

### 1. Legibility outranks effect

No effect ships that makes text harder to read. Concretely, and these are all
things the shell already does:

- The ambient aura **ships off**. It is an opt-in, not the look.
- `liteMode` drops every expensive layer — bleeds, blurs, grain, shadows — and
  the shell still works, because the effect was never load-bearing.
- A translucent surface carries its contrast from the *surface behind it*, so
  the palette guarantees the text, not the wallpaper.
- If a rule below this one would dim a failure, an error, or the thing the user
  is looking at, this one wins.

### 2. One body

There is one pill. A surface is a state of it, not a window beside it. Adding a
surface means adding a state and a route, never adding a frame that floats
independently and then has to be positioned against every other one.

The shell's top edge has exactly one presentation at a time — the pill, or the
minimal bar — and the two never share it.

### 3. Tokens, never literals

A component that needs a colour takes it from `Theme`; a duration from `Motion`;
a size from a flag. If a value is not in a token table it does not belong in a
component.

The test: a component containing a hex literal is unfinished. `ColorScheme.qml`
and `services/Theme.qml` are the only places a hex may appear.

### 4. One accent

Exactly one accent colour in the whole shell, and it means *this is selected, or
this is live, or this is a warning*. Everything else is the grey ramp. The
wallpaper supplies the only other colour, and it arrives through the dynamic
palette rather than by being picked per surface.

Two static schemes ship (`legacy`, `vague`); both are built this way, and
neither adds a hue.

### 5. Motion explains

Motion exists to say what just happened to the object. It does not perform.

- Every duration comes from `services/Motion.qml` and is scaled by the
  reduce-motion flag in one place.
- The morph curve is one curve, not a curve per surface.
- An animation that does not correspond to a state change is decoration; cut it.

### 6. State lives in the shell

One value, one owner, one place it is written. A surface reads flags; it does
not keep a private copy. If the settings app can reach it, it is a flag; if it
cannot, it is a constant in the component that has no business being a
setting — and the fix is to promote it, not to hide it.

This is why `flags.json` exists and why `utils/settings/fields.js` is shared
between the two settings UIs: bounds and defaults are properties of the *field*,
so they are stated once.

### 7. Cost is a design decision

Every blur, shadow, gradient and animated layer is named, and the whole class
can be turned off. A surface that only looks right at full quality has a bug.

---

## The system

Tokens of record. Changing a value here changes the shell.

### Form

| token | value | use |
| --- | --- | --- |
| `Motion.rSmall` | 7 | chips, small capsules |
| `Motion.rTile` | 13 | tiles, rows |
| pill rest corner | 28 | the rest silhouette |
| settings card / row | 14 / 10 | `settingsapp/config/Theme.qml` |

One silhouette language: rounded rectangles that get rounder as they get taller.
A capsule is fully rounded; a card is not. There is no square corner on a
surface and no pill-shaped button.

### Colour

Resolution order, and it never skips a step:

1. `Flags.colorScheme` picks the static scheme (`legacy` or `vague`).
2. `paletteMode` decides whether that scheme is used at all — `static` uses it,
   `dynamic` and `manual` take the wallpaper-generated palette instead.
3. `Theme` hands out the resolved tokens.

A component never branches on any of this. It asks `Theme` and gets a colour.

### Type

`Theme.font` (Inter by default, user-settable) with the Nerd Font for glyphs.
Four roles: title, normal, small, section. Weight carries emphasis; size does
not do the same job twice. A readout that must be legible at a glance — the
bar's clock — is the deliberate exception to a single text colour per strip,
because finding the time in a row of equal weight is the whole point of it.

### Motion

The ladder, from `services/Motion.qml`:

| token | default | notch | use |
| --- | --- | --- | --- |
| `fast` | 140 ms | 160 ms | hover, toggles |
| `standard` | 300 ms | 260 ms | open, close, scroll settle |
| `morph` | 420 ms | 520 ms | the pill changing state |
| `shapeshift` | 820 ms | 700 ms | a full surface swap |
| `heat` | 1100 ms | 900 ms | deliberate long settle |

Notch style swaps in a front-loaded Apple-ish curve with a slight overshoot;
the pill keeps the original. Both are the same `morphCurve` token.

### Density

A row is one line of label, one line of caption, one control. The caption says
*why* — what the setting does, what its bounds are, why the default is what it
is. A row without a caption is a control nobody can decide whether to change.

---

## How the shell is written

### Every comment is a doc comment

**The rule: in QML and JS, every comment is a `/** … */` doc comment.** No `//`
line comments, no plain `/* … */` blocks.

It is a small rule with a large effect. A file whose comments are half one style
and half another reads as though nobody decided, and the next person cannot tell
a deliberate note from a leftover. Doc comments also mean the reasoning sits
*where the code is*, which is the whole point of the README's no-`docs/` policy.

Shape:

```qml
/** One line when it fits. */
readonly property int radiusRow: 10

/**
 * A paragraph when it does not. Explain why, and what the alternative was —
 * a comment that only restates the code is noise. Say what the reader would
 * otherwise get wrong.
 */
readonly property color accent: dyn ? Dyn.primary : "#d8647e"
```

**Scope.** QML and JS. Python (`utils/*.py`), GLSL (`assets/shaders/*.frag`),
shell scripts and the generated `.qsb` files have no doc-comment syntax; their
`#` and `//` comments are exempt and stay as they are. That is a language
constraint, not a carve-out.

This is enforced — see below.

### Reasoning lives next to the code

A header comment states what the file is for and any decision that is not
obvious from reading it. Where two implementations had to be reconciled, the
comment says which won and why. This is why `services/Theme.qml` explains why it
is a façade rather than a palette.

---

## Enforcement

Rules that can be checked are checked, so they survive a bad week.

| rule | enforced by |
| --- | --- |
| every comment is a doc comment | `utils/lint_qml.py`, check `doc-comment` |
| rich text, bound scope, untracked bindings | `utils/lint_qml.py`, checks `rich-text` / `bound-scope` / `untracked` |
| no hex literal outside the theme | by review; `ColorScheme.qml` and `Theme.qml` are the only homes |
| no private state where a flag belongs | by review; anything the settings app cannot reach is flagged in `TODO.md` |

```
python3 utils/lint_qml.py        # exit 0 clean, 1 findings
```

---

## Using it

### Building a new surface

1. **State, not window.** Which state of the pill is this? If it needs its own
   frame, that is the exception and it needs a reason.
2. **Name it in the shell's vocabulary.** Calendar, mixer, recorder — a noun
   the user would use.
3. **Tokens only.** Every colour from `Theme`, every duration from `Motion`,
   every size from a flag. No literals.
4. **One accent.** Decide what, if anything, is live or selected. Usually one
   thing.
5. **Check it at `liteMode` on** and at `reduceMotion` on. If it is broken
   there, it is broken.
6. **Check it over a light wallpaper** if it is translucent. If the text fails
   there, fix the palette, not the text.
7. **Route it, state it, size it, and put it in `flags.json`.** If the settings
   app cannot reach a value you just tuned, that value is a constant in the
   wrong place.
8. **Linter clean.**

### Redesigning an existing surface

Same list, plus:

- **Ask what the surface is a state of.** Most redesign questions are actually
  "which state is this, and why does it look like another one".
- **Do not add a second accent** to solve a hierarchy problem. That is a spacing,
  weight or radius problem wearing a colour problem's clothes.
- **Count the motion.** If two things animate to say one thing, one of them is
  now redundant.
- **Keep the tokens.** A redesign that hard-codes its own colours has forked the
  design language, and the next theme change will not reach it.

### Before you call it done

- [ ] `python3 utils/lint_qml.py` exits 0
- [ ] Correct with `reduceMotion` on
- [ ] Correct with `liteMode` on
- [ ] Every colour, duration and size comes from a token
- [ ] One accent, or none
- [ ] Header comment explains what the file is and any decision that is not obvious
- [ ] Every comment in it is a `/** … */`
- [ ] Anything the user can tune is a flag, and the settings app can reach it