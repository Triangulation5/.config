#!/usr/bin/env bash
#
# Safer wrapper around awww-daemon.
#
# The daemon can fail silently or leave a stale socket behind (as happened
# after a version bump). This wrapper checks the Wayland socket it owns,
# restarts the daemon cleanly when requested, and reports problems both on
# stderr and as desktop notifications via lib-notify.sh.
#
# Usage:
#   awww-daemon-wrapper.sh status   # report daemon + socket state, exit 0/1
#   awww-daemon-wrapper.sh start    # start daemon if not already usable
#   awww-daemon-wrapper.sh restart  # kill and start fresh, cleaning the socket
#   awww-daemon-wrapper.sh stop     # stop daemon and clean the socket
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/lib-notify.sh"

DAEMON_CMD="${DAEMON_CMD:-awww-daemon}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
SOCK_PATH="${XDG_RUNTIME_DIR}/wayland-1-awww-daemon.sock"
PID_FILE="${STATE_DIR}/awww-daemon-wrapper.pid"
LOG_FILE="${STATE_DIR}/awww-daemon-wrapper.log"

find_daemon_pids() {
    pgrep -x "$(basename "$DAEMON_CMD")" 2>/dev/null || true
}

socket_ok() {
    [ -S "${SOCK_PATH}" ] && awww query >/dev/null 2>&1
}

cleanup_socket() {
    if [ -e "${SOCK_PATH}" ]; then
        rm -f "${SOCK_PATH}" || {
            notify_warn "awww" "Could not remove stale socket ${SOCK_PATH}"
            return 1
        }
        notify_debug "awww" "Removed stale socket ${SOCK_PATH}"
    fi
}

wait_for_daemon() {
    local pid="$1"
    local spins=25
    local i
    for ((i = 0; i < spins; i++)); do
        if socket_ok; then
            echo "$pid" > "${PID_FILE}"
            notify_info "awww-daemon" "Daemon ready (PID ${pid})"
            return 0
        fi
        if ! kill -0 "${pid}" 2>/dev/null; then
            notify_error "awww-daemon" "Daemon exited during startup; see ${LOG_FILE}" "${pid}"
            return 1
        fi
        sleep 0.2
    done
    notify_error "awww-daemon" "Daemon did not create its socket within ~5s; see ${LOG_FILE}"
    return 1
}

start_daemon() {
    if socket_ok; then
        notify_info "awww-daemon" "Daemon already running and socket OK"
        return 0
    fi

    mkdir -p "${STATE_DIR}"
    cleanup_socket || true

    notify_info "awww-daemon" "Starting daemon..."
    : > "${LOG_FILE}"
    "${DAEMON_CMD}" >> "${LOG_FILE}" 2>&1 &
    local pid=$!
    wait_for_daemon "${pid}"
}

stop_daemon() {
    local pids
    pids="$(find_daemon_pids)"
    if [ -z "${pids}" ]; then
        notify_info "awww-daemon" "No daemon running"
        cleanup_socket || true
        rm -f "${PID_FILE}"
        return 0
    fi
    # Deliberate, logged signal so we can see who we stopped.
    notify_warn "awww-daemon" "Stopping daemon (PIDs: $(echo ${pids} | tr '\n' ' '))"
    kill -TERM ${pids} 2>/dev/null || true
    local i
    for ((i = 0; i < 10; i++)); do
        if [ -z "$(find_daemon_pids)" ]; then
            cleanup_socket || true
            rm -f "${PID_FILE}"
            return 0
        fi
        sleep 0.2
    done
    notify_error "awww-daemon" "Daemon did not stop on SIGTERM; not killing forcefully"
    return 1
}

status_daemon() {
    local pids
    pids="$(find_daemon_pids)"
    if [ -n "${pids}" ] && socket_ok; then
        echo "awww-daemon: running (pids: $(echo ${pids} | tr '\n' ' ')), socket OK"
        return 0
    elif [ -n "${pids}" ]; then
        echo "awww-daemon: running but socket is unusable — try 'restart'"
        notify_warn "awww-daemon" "Daemon is running but its socket is unusable"
        return 1
    else
        echo "awww-daemon: not running"
        return 1
    fi
}

case "${1:-status}" in
    start)   start_daemon ;;
    restart) stop_daemon || true; start_daemon ;;
    stop)    stop_daemon ;;
    status)  status_daemon ;;
    *)
        echo "usage: $0 {status|start|restart|stop}" >&2
        exit 2
        ;;
esac
