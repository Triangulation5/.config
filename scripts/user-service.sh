#!/usr/bin/env bash
#
# Unified user daemon runner for Silhouette.
# Adapts between systemd user units and process-based supervision (OpenRC / non-systemd).
#
# Usage:
#   user-service.sh restart <service>
#   user-service.sh start <service>
#   user-service.sh stop <service>
#   user-service.sh status <service>
#
# Supported services: hypridle, hyprsunset, mpd
#

set -u

cmd="${1:-}"
service="${2:-}"

is_systemd_user_active() {
    [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && \
        systemctl --user is-active --quiet "$1" 2>/dev/null
}

is_systemd_user_enabled() {
    [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && \
        systemctl --user is-enabled --quiet "$1" 2>/dev/null
}

case "$service" in
    hypridle)
        case "$cmd" in
            restart)
                if is_systemd_user_active hypridle || is_systemd_user_enabled hypridle; then
                    exec systemctl --user restart hypridle
                fi
                pkill -x hypridle 2>/dev/null || true
                sleep 0.1
                if command -v hypridle >/dev/null 2>&1; then
                    hypridle & disown
                fi
                ;;
            start)
                if is_systemd_user_active hypridle; then
                    exit 0
                fi
                if is_systemd_user_enabled hypridle; then
                    exec systemctl --user start hypridle
                fi
                if command -v hypridle >/dev/null 2>&1; then
                    pgrep -x hypridle >/dev/null || (hypridle & disown)
                fi
                ;;
            stop)
                if is_systemd_user_active hypridle || is_systemd_user_enabled hypridle; then
                    systemctl --user stop hypridle 2>/dev/null || true
                fi
                pkill -x hypridle 2>/dev/null || true
                ;;
            status)
                if is_systemd_user_active hypridle; then
                    systemctl --user status hypridle
                else
                    pgrep -x hypridle >/dev/null && echo "hypridle is running" || echo "hypridle is stopped"
                fi
                ;;
            *)
                echo "usage: user-service.sh <start|stop|restart|status> hypridle" >&2
                exit 1
                ;;
        esac
        ;;

    hyprsunset)
        case "$cmd" in
            restart)
                if is_systemd_user_active hyprsunset || is_systemd_user_enabled hyprsunset; then
                    exec systemctl --user restart hyprsunset
                fi
                pkill -x hyprsunset 2>/dev/null || true
                sleep 0.1
                if command -v hyprsunset >/dev/null 2>&1; then
                    hyprsunset & disown
                fi
                ;;
            start)
                if is_systemd_user_active hyprsunset; then
                    exit 0
                fi
                if is_systemd_user_enabled hyprsunset; then
                    exec systemctl --user start hyprsunset
                fi
                if command -v hyprsunset >/dev/null 2>&1; then
                    pgrep -x hyprsunset >/dev/null || (hyprsunset & disown)
                fi
                ;;
            stop)
                if is_systemd_user_active hyprsunset || is_systemd_user_enabled hyprsunset; then
                    systemctl --user stop hyprsunset 2>/dev/null || true
                fi
                pkill -x hyprsunset 2>/dev/null || true
                ;;
            status)
                if is_systemd_user_active hyprsunset; then
                    systemctl --user status hyprsunset
                else
                    pgrep -x hyprsunset >/dev/null && echo "hyprsunset is running" || echo "hyprsunset is stopped"
                fi
                ;;
            *)
                echo "usage: user-service.sh <start|stop|restart|status> hyprsunset" >&2
                exit 1
                ;;
        esac
        ;;

    mpd)
        cfg="${XDG_CONFIG_HOME:-$HOME/.config}/mpd/mpd.conf"
        case "$cmd" in
            restart)
                if is_systemd_user_active mpd || is_systemd_user_enabled mpd; then
                    if systemctl --user restart mpd 2>/dev/null; then
                        exit 0
                    fi
                fi
                pkill -x mpd 2>/dev/null || true
                sleep 0.1
                if command -v mpd >/dev/null 2>&1; then
                    if [ -f "$cfg" ]; then
                        mpd "$cfg" & disown
                    else
                        mpd & disown
                    fi
                fi
                ;;
            start)
                if is_systemd_user_active mpd; then
                    exit 0
                fi
                if is_systemd_user_enabled mpd; then
                    exec systemctl --user start mpd
                fi
                if command -v mpd >/dev/null 2>&1; then
                    if ! pgrep -x mpd >/dev/null; then
                        if [ -f "$cfg" ]; then
                            mpd "$cfg" & disown
                        else
                            mpd & disown
                        fi
                    fi
                fi
                ;;
            stop)
                if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
                    systemctl --user stop mpd 2>/dev/null || true
                    systemctl --user disable mpd 2>/dev/null || true
                fi
                pkill -9 mpd 2>/dev/null || true
                ;;
            status)
                if is_systemd_user_active mpd; then
                    systemctl --user status mpd
                else
                    pgrep -x mpd >/dev/null && echo "mpd is running" || echo "mpd is stopped"
                fi
                ;;
            *)
                echo "usage: user-service.sh <start|stop|restart|status> mpd" >&2
                exit 1
                ;;
        esac
        ;;

    *)
        echo "usage: user-service.sh <start|stop|restart|status> <hypridle|hyprsunset|mpd>" >&2
        exit 1
        ;;
esac
