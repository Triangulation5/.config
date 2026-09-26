# Project TODO

## Core Architecture & Features

---

# Minimal DWM-Style Bar

## Goal

Create a minimal, toggleable DWM-style status bar that can be enabled and
disabled from the Settings application.

## Requirements

* Target extremely low resource usage (~100–150 MB RAM).
* Keep interaction surface minimal.
* Avoid unnecessary clickable UI elements.
* Follow a `dwmblocks`-inspired philosophy:

  * Simple.
  * Modular.
  * Efficient.
  * State-driven.
* Reuse or adapt concepts from the previous implementation if applicable.
* Review git history to recover useful ideas from the previous bar
  implementation.

---

# Code Cleanup & Maintenance

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

# Wallpaper Search Improvements

## Problem

The custom wallpaper searcher no longer displays all results when searching:

``` gh: ```

## Requirements

* Restore full result visibility.
* Allow manually browsing through all available results.
* Do not limit results unnecessarily.
* Ensure searching and scrolling behavior remain consistent.

---

# Peripheral Status Handling

## Goal

Improve hardware detection and status presentation.

## Current Problems

* Bluetooth devices are represented incorrectly.
* Charging states are unclear.
* Connected Bluetooth devices may appear multiple times.
* Duplicate or conflicting information is displayed.

## Requirements

* Show accurate connection state.
* Show charging state clearly.
* Remove duplicate peripheral entries.
* Create a consistent peripheral status model.

---

# Timer Surface Redesign

## Goal

Redesign the timer surface to match the quality and interaction style of Tide
Island's timer interface.

## Requirements

* Cleaner visual hierarchy.
* Improved animations.
* More polished interactions.
* Better alignment with Silhouette Shell's design language.

Focus areas:

* Surface transitions.
* Information hierarchy.
* User interaction flow.
* Motion quality.

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
