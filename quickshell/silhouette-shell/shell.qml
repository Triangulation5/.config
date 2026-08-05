import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs.services
import qs.modules.pill
import qs.modules.lock
import qs.modules.screencorner
import qs.modules.launcher

ShellRoot {
    id: shell

    PillRoot {
        id: pillRoot
    }

    LockRoot {
        id: lockRoot
    }

    ScreenCornerRoot {
        id: cornerRoot
    }

    LauncherRoot {
        id: launcherRoot
    }

    IpcHandler {
        target: "pill"
        function mixer(mon: string): void { pillRoot.toggleSurface(mon, "mixer"); }
        function calendar(mon: string): void { pillRoot.toggleSurface(mon, "calendar"); }
        function launcher(mon: string): void { pillRoot.toggleSurface(mon, "launcher"); }
        function power(mon: string): void { pillRoot.toggleSurface(mon, "power"); }
        function link(mon: string): void { pillRoot.toggleSurface(mon, "link"); }
        function battery(mon: string): void { pillRoot.toggleSurface(mon, "battery"); }
        function settings(mon: string): void { pillRoot.toggleSurface(mon, "settings"); }
        function keybinds(mon: string): void { pillRoot.toggleSurface(mon, "keybinds"); }
        function recorder(mon: string): void { pillRoot.toggleSurface(mon, "recorder"); }
        function screenrec(mon: string): void { pillRoot.toggleSurface(mon, "recorder"); }
        function record(mon: string): void { pillRoot.toggleSurface(mon, "recorder"); }
        function quickRecord(mon: string): void {
            if (ScreenRec.recording) {
                ScreenRec.stop();
            } else if (ScreenRec.counting) {
                ScreenRec.cancel();
            } else if (ScreenRec.quickChoosing) {
                ScreenRec.quickChoosing = false;
                ScreenRec.quickScreenChoosing = false;
            } else {
                ScreenRec.quickMon = mon;
                ScreenRec.quickScreenChoosing = false;
                ScreenRec.quickChoosing = true;
            }
        }
        function gameMode(mon: string): void { Flags.gameMode = !Flags.gameMode; }
        function sysmon(mon: string): void { pillRoot.toggleSurface(mon, "sysmon"); }
        function system(mon: string): void { pillRoot.toggleSurface(mon, "sysmon"); }
        function clipboard(mon: string): void { pillRoot.toggleSurface(mon, "clipboard"); }
        function wallpaper(mon: string): void { pillRoot.toggleSurface(mon, "wallpaper"); }
        function media(mon: string): void {
            if (Players.list.length > 0)
                pillRoot.toggleSurface(mon, "media");
        }
        function peek(mon: string): void { pillRoot.peek(mon); }
        function hide(): void { pillRoot.close(); }
        function page(mon: string, name: string): void { pillRoot.toggleSurface(mon, name); }
        function minimizeWindow(addr: string): void {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:' + addr + '" })');
        }
        function restoreWindow(arg: string): void {
            var p = arg.split("|");
            if (p.length < 2 || p[0].length === 0)
                return;
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + p[1] + ', window = "address:' + p[0] + '" })');
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { lockRoot.doLock(); }
    }

    IpcHandler {
        target: "launcher"
        function show(mon: string): void { launcherRoot.targetMonitor = mon; launcherRoot.shown = true; }
        function hide(): void { launcherRoot.shown = false; }
        function toggle(mon: string): void {
            if (launcherRoot.shown) { launcherRoot.shown = false; return; }
            launcherRoot.targetMonitor = mon;
            launcherRoot.shown = true;
        }
    }
}
