# SilhouetteShell

SilhouetteShell is a custom Qt/QML desktop shell designed primarily for
Hyprland.

It provides a complete desktop experience through a dynamic pill interface,
custom system controls, animated UI components, workspace management, and
integrated utilities.

The shell focuses on:
- Custom visual design
- Smooth motion and transitions
- Modular QML architecture
- Dynamic system interaction
- Personalized desktop workflows

Primary target environment:
- Hyprland (currently tested)

---

<!--toc:start-->
- [SilhouetteShell](#silhouetteshell)
  - [Features](#features)
    - [Dependencies](#dependencies)
    - [Core Shell](#core-shell)
      - [Pill/Dynamic Island/Notch](#pilldynamic-islandnotch)
      - [Ame — The Shapeshifter](#ame-the-shapeshifter)
      - [Expanded Pill](#expanded-pill)
    - [Desktop Controls](#desktop-controls)
      - [App Launcher](#app-launcher)
      - [AppImage Installer](#appimage-installer)
      - [Power Menu](#power-menu)
      - [Lockscreen](#lockscreen)
    - [System Integration](#system-integration)
      - [Notifications](#notifications)
      - [Clipboard Manager](#clipboard-manager)
      - [Media System](#media-system)
      - [Tray System](#tray-system)
      - [Mixer Menu](#mixer-menu)
    - [Visualizers](#visualizers)
      - [Music Line Visualizer](#music-line-visualizer)
      - [Music Bars](#music-bars)
    - [Display & Hardware Controls](#display-hardware-controls)
      - [Display Switcher](#display-switcher)
      - [Volume / Brightness OSD](#volume-brightness-osd)
      - [Bluetooth](#bluetooth)
      - [WiFi](#wifi)
      - [Input Controls](#input-controls)
    - [Calendar & Time](#calendar-time)
      - [Calendar](#calendar)
      - [Weather](#weather)
    - [Workspace Management](#workspace-management)
      - [Workspace Switcher](#workspace-switcher)
      - [Special Workspace Toggles](#special-workspace-toggles)
      - [Workspace Rules](#workspace-rules)
      - [Space Apps](#space-apps)
    - [Customization](#customization)
      - [Theme System](#theme-system)
      - [Wallpaper System](#wallpaper-system)
      - [Font Picker](#font-picker)
      - [Hand Drawn SVG Icons](#hand-drawn-svg-icons)
      - [Motion System](#motion-system)
      - [Game Mode](#game-mode)
      - [Rounded Screen Corners](#rounded-screen-corners)
    - [Recording](#recording)
      - [Screen Recorder](#screen-recorder)
      - [Quick Record](#quick-record)
      - [Recorder Integration](#recorder-integration)
    - [System Monitoring](#system-monitoring)
      - [System Monitor](#system-monitor)
    - [Settings](#settings)
      - [Built-in Settings Menu](#built-in-settings-menu)
      - [Custom Updater](#custom-updater)
      - [Persistent Configuration](#persistent-configuration)
    - [Utilities](#utilities)
      - [Calculator](#calculator)
      - [Keybind System](#keybind-system)
      - [Stash](#stash)
      - [Space Apps](#space-apps-1)
      - [Tooltip System](#tooltip-system)
- [Highlights](#highlights)
<!--toc:end-->

---

## Features

A modern Qt/QML desktop shell featuring a dynamic pill/notch interface, custom
animations, system controls, visual effects, and integrated desktop utilities.

### Dependencies

Required:
- Quickshell
- Hyprland
- NetworkManager (`nmcli`)
- BlueZ (`bluetoothctl`)
- cliphist
- wl-clipboard
- cava
- gpu-screen-recorder
- slurp
- jq
- curl
- brightnessctl
- ddcutil

Optional:
- kdialog or zenity (folder picker fallback)
- nvibrant (NVIDIA display saturation)
- xrandr (XWayland display handling)

System Utilities. SilhouetteShell also uses standard system utilities:

- bash
- coreutils
- systemd
- xdg-utils

### Core Shell

#### Pill/Dynamic Island/Notch
A central adaptive interface element that changes shape and behavior based on
system events, applications, and user interactions.

Features:
- Dynamic expansion and contraction
- Multiple display modes:
  - Pill mode
  - Dynamic Island mode
  - Notch mode
- Interactive widgets and tooltips
- Custom animations and transitions
- System status integration

#### Ame — The Shapeshifter
A custom molten glass bead character that acts as the pill's pointer/caret.

Features:
- Breathing animations
- Fluid movement
- Morphing behavior
- Acts as the visual identity of the shell

#### Expanded Pill
An extended pill interface that reveals additional widgets and controls.

Includes:
- Calendar
- Clipboard
- Media controls
- System monitor
- Recorder
- Wallpaper controls
- Workspace controls
- Notifications

---

### Desktop Controls

#### App Launcher
A fast application launcher with search, filtering, and integrated utilities.

Features:
- Application search
- Fuzzy matching
- Calculator integration
- AppImage installation support

#### AppImage Installer
Install AppImage applications by dragging the file onto the pill.

Features:
- Drag-and-drop installation workflow
- Automatic application handling

#### Power Menu
Centralized system power controls.

Actions:
- Lock
- Idle lock
- Sleep
- Logout
- Restart
- Reboot
- Shutdown

#### Lockscreen
A custom animated lockscreen.

Features:
- Authentication handling
- Clock display
- Battery information
- Custom visual surfaces

---

### System Integration

#### Notifications
Custom notification daemon with visual previews.

Features:
- Toast notifications
- Notification previews
- Pill integration

#### Clipboard Manager
Powered by cliphist.

Features:
- Clipboard history
- Clipboard search
- Image thumbnail previews

#### Media System
Integrated media controls.

Features:
- Active player detection
- Play/pause controls
- Media information display

#### Tray System
Custom tray implementation.

Includes:
- System tray
- Minimized applications tray
- Tray interactions

#### Mixer Menu
Audio control interface.

Features:
- Volume controls
- Application mixers
- Audio device handling

---

### Visualizers

#### Music Line Visualizer
A flowing string looking audio visualizer.

Powered by:
- Custom QML rendering
- CAVA integration

#### Music Bars
A classic audio bar visualizer.

Features:
- Real-time audio visualization
- Custom styling

---

### Display & Hardware Controls

#### Display Switcher
Manage connected displays.

Features:
- Display selection
- Display configuration

#### Volume / Brightness OSD
Custom on-screen display notifications.

Includes:
- Volume changes
- Brightness changes
- Mute state changes

#### Bluetooth
Bluetooth device management.

Features:
- Device discovery
- Device linking
- Connection handling

#### WiFi
Wireless network management.

Features:
- Network linking
- Custom designed WiFi icon
- Connection status

#### Input Controls
Keyboard and input configuration.

Includes:
- Input settings
- Custom key handling

---

### Calendar & Time

#### Calendar
Integrated calendar widget.

Features:
- Event tracking
- Weekly events
- Calendar visualization

#### Weather
Weather tracking system.

Features:
- Current weather
- Weekly forecast tracking

---

### Workspace Management

#### Workspace Switcher
Dynamic workspace navigation.

Features:
- Animated workspace indicator
- Transforms into five lines during movement

#### Special Workspace Toggles
Quick workspace actions and controls.

#### Workspace Rules
Configure workspace behavior.

Features:
- Workspace rule management
- Settings integration

#### Space Apps
Workspace application overview.

---

### Customization

#### Theme System
Flexible theme engine.

Supports:
- Static themes
- Dynamic themes
- Manually created themes

#### Wallpaper System
Advanced wallpaper management.

Features:
- Wallpaper cache for instant switching
- Wallpaper search
- Dynamic colors from wallpapers

Sources:
- DuckDuckGo
- MoeWalls
- Personal wallpaper repository

#### Font Picker
Custom font selection interface.

#### Hand Drawn SVG Icons
Custom illustrated icon system.

Features:
- Unique SVG icon style
- Custom WiFi glyph

#### Motion System
Custom animation engine.

Features:
- Adjustable animation styles
- Custom motion profiles

#### Game Mode
Performance focused mode.

Disables:
- Animations
- Extra spacing
- Visual effects

#### Rounded Screen Corners
Dynamic screen decoration system.

Behavior:
- Automatically updates with pill states
- Game mode removes rounding
- Notch mode increases rounding
- Dynamic Island mode uses partial rounding

---

### Recording

#### Screen Recorder
Integrated screen recording system.

Features:
- Recording controls
- Recording previews
- Thumbnail generation

#### Quick Record
Fast recording workflow.

#### Recorder Integration
Recorder controls directly inside the pill.

---

### System Monitoring

#### System Monitor
Live hardware monitoring.

Displays:
- CPU usage
- Memory usage
- GPU usage
- Swap usage
- Disk usage

---

### Settings

#### Built-in Settings Menu
Complete shell configuration interface.

Sections:
- Appearance
- Display
- Fonts
- Input
- Keybinds
- Workspaces
- Updates

#### Custom Updater
Integrated shell update system.

Features:
- Update checking
- Update handling from settings

#### Persistent Configuration
JSON-based configuration storage.

Features:
- Persistent settings
- User customization storage

---

### Utilities

#### Calculator
Built into the application launcher.

Features:
- Quick calculations
- Launcher access

#### Keybind System
Custom keyboard shortcut management.

Features:
- Configurable bindings
- Key chord support

#### Stash
A workspace organization system for managing special, hidden, or minimized
workspaces.

Features:
- Workspace storage
- Minimized workspace handling
- Special workspace workflows

#### Space Apps

A special workspace application system.

Features:
- Application grouping by workspace
- Magic workspace behavior
- Quick workspace access
- Workspace-based app organization

#### Tooltip System
Contextual explanations for pill elements.

Features:
- Hover information
- UI guidance

---

# Highlights

- Fully custom Qt/QML desktop shell
- Dynamic pill/notch interface
- Custom animated visual identity
- Real-time system integration
- Modular feature architecture
- JSON-based persistence
- Custom rendering effects and shaders
- Dynamic themes and wallpapers
- Integrated desktop utilities
