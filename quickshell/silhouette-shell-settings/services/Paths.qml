pragma Singleton

import QtQuick
import Quickshell

/**
 * The Hyprland config files this app edits, in one place. The shell hard-codes
 * these per surface (`…/modules/decoration.lua` for the Look groups, for
 * instance); centralising them here means a config that keeps its values
 * somewhere else — which this one does, see below — is one edit away from
 * working instead of five.
 *
 * Where the values actually are, on this config:
 *   decorations.lua  the `hl.config({ general, decoration, animations })` table
 *                    plus the animation curves and leaves. Everything the Look
 *                    and Motion pages edit lives here.
 *   decoration.lua   only the pill's frost `hl.layer_rule`.
 *   monitors.lua     the monitor blocks and the workspace rules.
 *   input.lua        pointer, keyboard and repeat settings.
 *   env.lua          the cursor size/theme environment.
 *   autostart.lua    the startup `hyprctl setcursor` call.
 *   binds.lua        the keybinds. This app adds and removes the binds a special
 *                    workspace needs; the shell's keybinds editor does the same
 *                    for every other key.
 *   spaces.lua       the user's special workspaces, which the shell reads for
 *                    its workspace name and its app routing. Nothing requires it
 *                    on this config — see Spaces.
 *
 * And one file outside the config tree, because it is a script rather than a
 * config: scripts/ricelin-update.py, the updater the Updates page drives.
 */
QtObject {
    /**
     * The Hyprland config tree. `RICELIN_HYPR_DIR` overrides it for a config
     * that lives outside `~/.config/hypr` — and for an audit run that must not
     * touch the real one.
     */
    readonly property string hypr: Quickshell.env("RICELIN_HYPR_DIR") || (Quickshell.env("HOME") + "/.config/hypr")
    readonly property string modules: hypr + "/modules"

    /** Gaps, rounding, border, blur, shadow, opacity and the animations table. */
    readonly property string decorations: modules + "/decorations.lua"
    /** The pill's frost layer rule, which lives in its own small file. */
    readonly property string pillRule: modules + "/decoration.lua"

    readonly property string monitors: modules + "/monitors.lua"
    readonly property string input: modules + "/input.lua"
    readonly property string env: modules + "/env.lua"
    readonly property string autostart: modules + "/autostart.lua"
    /** The keybinds the Workspaces page writes a space's toggle into. */
    readonly property string binds: modules + "/binds.lua"
    /** The user's special workspaces, as the shell's Spaces store reads them. */
    readonly property string spaces: modules + "/spaces.lua"

    /** The config's own scripts. */
    readonly property string scripts: hypr + "/scripts"
    /**
     * The updater the Updates page runs. It takes one argument — `check`,
     * `apply` or `apply-minimal` — and prints one JSON object; what it updates is
     * the distribution's packages, not this rice (see Updates).
     */
    readonly property string updater: scripts + "/ricelin-update.py"
}
