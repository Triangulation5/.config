#!/usr/bin/env bash
set -Eeuo pipefail

# Triangulation's customized Pi configuration installer
#
# Repository:
# https://github.com/triangulation5/pi-agent-config
#
# Usage:
#   ./install.sh          Install configuration
#   ./install.sh install  Install configuration
#   ./install.sh update   Update packages and extensions
#   ./install.sh check    Verify installation
#
# Optional:
#   PI_CODING_AGENT_DIR=/custom/path ./install.sh

VERSION="1.2.0"

PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
EXT_DIR="$PI_DIR/extensions"
SKILL_DIR="$PI_DIR/skills/commit"

RAW="https://raw.githubusercontent.com/mitsuhiko/agent-stuff/main"

MODE="${1:-install}"

BACKUP_DIR="$PI_DIR/backups/pi-agent-config/$(date +%Y%m%d-%H%M%S)"

# Packages

packages=(
    "npm:@juicesharp/rpiv-ask-user-question"
    "npm:pi-subagents"
    "npm:pi-claude-code-ui"
)

extensions=(
    "btw"
    "continue"
    "whimsical"
)

# Output

info() {
    printf '\033[1;34m[pi-config]\033[0m %s\n' "$1"
}

success() {
    printf '\033[1;32m[  OK  ]\033[0m %s\n' "$1"
}

warn() {
    printf '\033[1;33m[ WARN ]\033[0m %s\n' "$1"
}

error() {
    printf '\033[1;31m[ERROR ]\033[0m %s\n' "$1" >&2
}

die() {
    error "$1"
    exit 1
}

# Cleanup

TEMP_FILES=()

cleanup() {
    for file in "${TEMP_FILES[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done
}

trap cleanup EXIT

# Dependencies

check_dependencies() {
    for cmd in curl mktemp date cp mv cmp mkdir; do
        command -v "$cmd" >/dev/null 2>&1 ||
            die "Missing required dependency: $cmd"
    done

    case "$(uname -s)" in
        Linux|Darwin)
            ;;
        *)
            die "Unsupported operating system."
            ;;
    esac
}

# Pi installation

ensure_pi() {
    if command -v pi >/dev/null 2>&1; then
        success "Pi is already installed."
        return
    fi

    info "Installing Pi Coding Agent..."

    curl -fsSL https://pi.dev/install.sh | sh

    if ! command -v pi >/dev/null 2>&1; then
        warn "Pi installation may have completed, but pi is not in PATH."
        echo "Restart your shell and run this script again."
        exit 1
    fi

    success "Pi installed."
}

# File installation

download() {
    local url="$1"
    local destination="$2"
    local temporary

    mkdir -p "$(dirname "$destination")"

    temporary="$(mktemp "${destination}.tmp.XXXXXX")"
    TEMP_FILES+=("$temporary")

    info "Downloading $(basename "$destination")..."

    if ! curl -fsSL --retry 3 --retry-delay 2 \
        "$url" -o "$temporary"; then
        die "Download failed: $url"
    fi

    # Preserve files that have not changed.
    if [[ -f "$destination" ]] &&
       cmp -s "$temporary" "$destination"; then
        success "Already up to date: $(basename "$destination")"
        rm -f "$temporary"
        return
    fi

    # Back up existing files before replacing them.
    if [[ -f "$destination" ]]; then
        local relative
        relative="${destination#"$PI_DIR"/}"

        mkdir -p "$BACKUP_DIR/$(dirname "$relative")"

        cp -p "$destination" "$BACKUP_DIR/$relative"

        warn "Backed up existing file: $relative"
    fi

    mv "$temporary" "$destination"

    success "Installed: $(basename "$destination")"
}

# Package installation

install_packages() {
    info "Installing Pi packages..."

    for package in "${packages[@]}"; do
        info "Installing $package"

        pi install "$package"

        success "$package"
    done
}

update_packages() {
    info "Updating installed Pi packages..."

    pi update --extensions

    success "Package updates complete."
}

# Extension installation

install_extensions() {
    info "Installing Mitsuhiko's extensions..."

    mkdir -p "$EXT_DIR"

    for extension in "${extensions[@]}"; do
        download \
            "$RAW/extensions/$extension.ts" \
            "$EXT_DIR/$extension.ts"
    done
}

# Skill installation

install_skills() {
    info "Installing commit skill..."

    mkdir -p "$SKILL_DIR"

    download \
        "$RAW/skills/commit/SKILL.md" \
        "$SKILL_DIR/SKILL.md"
}

# Verification

check_installation() {
    local failed=0

    info "Checking Pi installation..."

    if command -v pi >/dev/null 2>&1; then
        success "Pi executable found."
    else
        error "Pi executable not found."
        failed=1
    fi

    info "Checking extensions..."

    for extension in "${extensions[@]}"; do
        if [[ -f "$EXT_DIR/$extension.ts" ]]; then
            success "$extension.ts"
        else
            error "Missing $extension.ts"
            failed=1
        fi
    done

    info "Checking skills..."

    if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
        success "Commit skill found."
    else
        error "Commit skill missing."
        failed=1
    fi

    if command -v pi >/dev/null 2>&1; then
        info "Installed Pi packages:"
        pi list
    fi

    return "$failed"
}

# Summary

print_summary() {
    echo
    success "Pi configuration $VERSION completed."

    echo
    echo "Installed packages:"

    for package in "${packages[@]}"; do
        echo "  - $package"
    done

    echo
    echo "Installed extensions:"

    for extension in "${extensions[@]}"; do
        echo "  - $extension.ts"
    done

    echo
    echo "Installed skills:"
    echo "  - commit"

    echo
    echo "Pi directory: $PI_DIR"
    echo "Restart Pi to load the extensions."
    echo
}

# Main

main() {
    check_dependencies

    case "$MODE" in
        install)
            ensure_pi
            install_packages
            install_extensions
            install_skills
            print_summary
            ;;

        update)
            command -v pi >/dev/null 2>&1 ||
                die "Pi is not installed. Run ./install.sh first."

            update_packages
            install_extensions
            install_skills
            print_summary
            ;;

        check)
            check_installation
            ;;

        *)
            echo "Triangulation Pi Configuration v$VERSION"
            echo
            echo "Usage: $0 [install|update|check]"
            exit 1
            ;;
    esac
}

main "$@"
