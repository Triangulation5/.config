#set page(
  paper: "a4",
  margin: (top: 40pt, bottom: 40pt, left: 45pt, right: 45pt),
)

#set text(
  font: "FiraCode Nerd Font Mono",
  size: 11pt,
)

#set heading(
  numbering: "1.",
)

#align(center)[
  #text(size: 22pt, weight: 700)[Lockscreen Settings Surface]
  \
  #text(size: 11pt, fill: gray)[Design and implementation plan]
]

#v(24pt)

= Overview

The lockscreen settings surface will provide a compact control panel for changing
visual preferences, time formatting, display behavior, network connections, and
system actions.

The design should match the existing pill and lockscreen surfaces:

- Rounded capsule/container design
- Screen rounded border, morphs into a screen rounded border on the side after clicked
- Dynamic wallpaper-based colors
- GlyphIcon-based navigation
- Smooth open/close animations
- Minimal system resource usage
- No dependency on external icon themes

= Layout

The settings menu should appear as a floating surface in the bottom-right corner
of the lockscreen.

#table(
  columns: (1fr, 2fr),
  inset: 10pt,
  align: left,
  [Property], [Value],
  [Position], [Bottom-right corner],
  [Surface], [Rounded capsule panel],
  [Width], [320-400px],
  [Height], [Dynamic based on content],
  [Theme], [Shared Theme.qml colors],
  [Icons], [Internal GlyphIcon renderer],
)

= Navigation Structure

The settings surface should use category sections.

Each category contains rows with:

- Glyph icon
- Setting name
- Current value/state
- Toggle, button, or selector where required

Example:

#box(
  width: 100%,
  inset: 12pt,
)[
  #text(weight: 700)[Appearance]
  \
  #text(size: 10pt)[
    ✦ Music Visualizer
    \
    Enabled
  ]
]

= Categories

== Appearance

Purpose: Control lockscreen visual effects.

#table(
  columns: (1fr, 2fr, 1fr),
  inset: 8pt,
  align: left,
  [Setting], [Description], [Control],
  [Music Visualizer], [Enable animated visualizer effects], [Toggle],
)

Implementation:

- Connect to existing Cava/Music service.
- Store preference in flags.json.
- Animate changes without rebuilding surface.

== Time & Date

Purpose: Control clock presentation.

#table(
  columns: (1fr, 2fr, 1fr),
  inset: 8pt,
  align: left,
  [Setting], [Description], [Control],
  [Show seconds], [Display seconds on lockscreen clock], [Toggle],
  [Date format], [Change date formatting style], [Selector],
)

Possible date formats:

- Monday, July 30
- Jul 30, 2026
- 30/07/2026
- 2026-07-30

Implementation:

- Store settings in Flags.qml.
- Update clock surface reactively.

== Display

Purpose: Control screen behavior.

#table(
  columns: (1fr, 2fr, 1fr),
  inset: 8pt,
  align: left,
  [Setting], [Description], [Control],
  [Brightness], [Adjust monitor brightness], [Slider],
  [Night Light], [Toggle warm color mode], [Toggle],
)

Implementation:

Brightness:

- Use existing Backlight singleton.
- Provide animated slider.
- Show current percentage.

Night Light:

- Connect to NightLight singleton.
- Toggle active state.

== Network

Purpose: Manage connectivity.

#table(
  columns: (1fr, 2fr, 1fr),
  inset: 8pt,
  align: left,
  [Setting], [Description], [Control],
  [WiFi toggle], [Enable/disable wireless networking], [Toggle],
  [Current network], [Display connected network], [Status],
  [Bluetooth search], [Find available devices], [Action],
)

Implementation:

WiFi:

- Use NetworkManager integration.
- Show connection state.

Bluetooth:

- Open Bluetooth device discovery.
- Display paired and available devices.

== System

Purpose: Power management actions.

#table(
  columns: (1fr, 2fr, 1fr),
  inset: 8pt,
  align: left,
  [Setting], [Description], [Control],
  [Sleep], [Suspend system], [Button],
  [Restart], [Reboot system], [Button],
  [Shutdown], [Power off system], [Button],
)

Implementation:

Use existing power commands:

- systemctl suspend
- systemctl reboot
- systemctl poweroff

Require confirmation for destructive actions.

= Component Structure

Recommended files:

- `SettingsSurface.qml`
  - Root floating settings container
  - Handles visibility and animations

- `SettingsCategory.qml`
  - Category header and section layout

- `SettingsRow.qml`
  - Reusable setting item component
  - Icon, label, state, and control handling

- `SettingsToggle.qml`
  - Toggle switch component

- `SettingsSlider.qml`
  - Slider-based controls such as brightness

- `SettingsSelector.qml`
  - Dropdown/selector component

- `SettingsActions.qml`
  - System power action handlers

- `Flags.qml`
  - Persistent user preferences

- `Theme.qml`
  - Shared colors and styling

= Implementation Notes

- Keep all settings reactive through existing QML singletons.
- Avoid spawning processes from UI components where possible.
- Keep destructive actions behind confirmation prompts.
- Match existing lockscreen animation timing and easing curves.
- Reuse GlyphIcon infrastructure instead of introducing new assets.
- Ensure the surface can open and close without affecting lockscreen performance.
