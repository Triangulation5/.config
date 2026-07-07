#!/usr/bin/env bash

set -u

# ────────────────────────────────────────
# Fedora Fingerprint Health Check
# ────────────────────────────────────────

QUIET=false

if [[ "${1:-}" == "--quiet" ]]; then
    QUIET=true
fi

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

services=(
    "python3-validity"
    "open-fprintd"
)

all_good=true

ok() {
    $QUIET && return
    echo -e "${GREEN}✔  ${RESET} $1"
}

fail() {
    all_good=false
    $QUIET && return
    echo -e "${RED}✘ ${RESET} $1"
}

info() {
    $QUIET && return
    echo -e "${CYAN}➜${RESET} $1"
}

header() {
    $QUIET && return

    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔════════════════════════════════════╗"
    echo "║   Fedora Fingerprint Health Check  ║"
    echo "╚════════════════════════════════════╝"
    echo -e "${RESET}"
}

section() {
    $QUIET && return

    echo
    echo -e "${BOLD}$1${RESET}"
    echo "────────────────────────────────────"
}

header

# Ensure sudo credentials are available
if ! sudo -v; then
    exit 1
fi

section "[1/4] Restarting fingerprint services"

for service in "${services[@]}"; do
    info "Restarting $service..."

    if sudo systemctl restart "$service" >/dev/null 2>&1; then
        ok "$service restarted"
    else
        fail "$service failed to restart"
    fi
done

sleep 2

section "[2/4] Checking service health"

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        ok "$service is running"
    else
        fail "$service is not running"
    fi
done


section "[3/4] Detecting fingerprint reader"

device_check=$(fprintd-list "$USER" 2>&1)

if echo "$device_check" | grep -qi "no devices available"; then
    fail "No fingerprint device detected"
else
    ok "Fingerprint device detected"

    if ! $QUIET; then
        echo
        echo "$device_check"
    fi
fi


section "[4/4] Fingerprint verification"

if ! $QUIET; then
    echo
    echo -e "${YELLOW}Touch the fingerprint sensor when prompted...${RESET}"
    echo

    if fprintd-verify; then
        ok "Fingerprint verification successful"
    else
        fail "Fingerprint verification failed"
    fi
fi


# Quiet mode returns only status code
if $QUIET; then
    if [ "$all_good" = true ]; then
        exit 0
    else
        exit 1
    fi
fi


echo
echo "════════════════════════════════════"

if [ "$all_good" = true ]; then
    echo -e "${GREEN}${BOLD}"
    echo "✓ Fingerprint system is healthy"
    echo -e "${RESET}"
else
    echo -e "${YELLOW}${BOLD}"
    echo "! Fingerprint system needs attention"
    echo -e "${RESET}"
fi

echo "════════════════════════════════════"
echo
