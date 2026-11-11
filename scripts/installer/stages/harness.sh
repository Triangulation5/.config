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

VERSION="1.3.0"

PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
EXT_DIR="$PI_DIR/extensions"
SKILL_DIR="$PI_DIR/skills/commit"
PDF_SKILL_DIR="$PI_DIR/skills/pdf-reader"

RAW="https://raw.githubusercontent.com/mitsuhiko/agent-stuff/main"
PDF_REPO="https://codeload.github.com/amosblomqvist/pi-config/tar.gz/refs/heads/main"

MODE="${1:-install}"

BACKUP_DIR="$PI_DIR/backups/pi-agent-config/$(date +%Y%m%d-%H%M%S)"

# Packages
CUSTOM_PI_CC_UI="${PI_CLAUDE_CODE_UI_PATH:-$HOME/Projects/pi-claude-code-ui}"
if [[ -d "$CUSTOM_PI_CC_UI" ]]; then
    PI_CC_UI_PKG="$CUSTOM_PI_CC_UI"
else
    PI_CC_UI_PKG="npm:pi-claude-code-ui"
fi

packages=(
    "npm:@juicesharp/rpiv-ask-user-question"
    # "npm:pi-subagents"
    "$PI_CC_UI_PKG"
)

extensions=(
    "btw"
    "continue"
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
TEMP_DIRS=()

cleanup() {
    for file in "${TEMP_FILES[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done

    for dir in "${TEMP_DIRS[@]}"; do
        [[ -d "$dir" ]] && rm -rf "$dir"
    done
}

trap cleanup EXIT

# Dependencies

check_dependencies() {
    for cmd in curl mktemp date cp mv cmp mkdir tar find python3; do
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

    # If using custom local pi-claude-code-ui, remove npm package if installed
    if [[ "$PI_CC_UI_PKG" != "npm:pi-claude-code-ui" ]] && command -v pi >/dev/null 2>&1; then
        if pi list 2>/dev/null | grep -q "npm:pi-claude-code-ui"; then
            info "Removing npm:pi-claude-code-ui in favor of custom local version ($PI_CC_UI_PKG)..."
            pi remove npm:pi-claude-code-ui || true
        fi
    fi

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

# Commit skill installation

install_skills() {
    info "Installing commit skill..."

    mkdir -p "$SKILL_DIR"

    download \
        "$RAW/skills/commit/SKILL.md" \
        "$SKILL_DIR/SKILL.md"
}

# PDF Reader skill installation

install_pdf_reader() {
    local archive
    local staging
    local staged_skill
    local source
    local relative
    local destination
    local temporary

    info "Installing PDF Reader skill..."

    archive="$(mktemp "${TMPDIR:-/tmp}/pi-pdf-reader.XXXXXX.tar.gz")"
    TEMP_FILES+=("$archive")

    staging="$(mktemp -d "${TMPDIR:-/tmp}/pi-pdf-reader.XXXXXX")"
    TEMP_DIRS+=("$staging")

    info "Downloading upstream PDF Reader skill..."

    if ! curl -fsSL --retry 3 --retry-delay 2 \
        "$PDF_REPO" -o "$archive"; then
        die "Failed to download PDF Reader repository."
    fi

    if ! tar -xzf "$archive" \
        -C "$staging" \
        --strip-components=2 \
        pi-config-main/skills/pdf-reader; then
        die "Failed to extract PDF Reader skill."
    fi

    staged_skill="$staging/pdf-reader"

    [[ -f "$staged_skill/SKILL.md" ]] ||
        die "PDF Reader archive is missing SKILL.md."

    [[ -f "$staged_skill/requirements.txt" ]] ||
        die "PDF Reader archive is missing requirements.txt."

    mkdir -p "$PDF_SKILL_DIR"

    # Merge individual files rather than replacing the skill directory.
    # Unrelated local files are preserved.
    while IFS= read -r -d '' source; do
        relative="${source#"$staged_skill"/}"
        destination="$PDF_SKILL_DIR/$relative"

        mkdir -p "$(dirname "$destination")"

        # Skip unchanged files.
        if [[ -f "$destination" ]] &&
           cmp -s "$source" "$destination"; then
            continue
        fi

        # Back up files before replacing them.
        if [[ -f "$destination" ]]; then
            local backup_relative
            backup_relative="${destination#"$PI_DIR"/}"

            mkdir -p "$BACKUP_DIR/$(dirname "$backup_relative")"
            cp -p "$destination" "$BACKUP_DIR/$backup_relative"

            warn "Backed up existing PDF Reader file: $backup_relative"
        fi

        temporary="$(mktemp "${destination}.tmp.XXXXXX")"
        TEMP_FILES+=("$temporary")

        cp -p "$source" "$temporary"
        mv "$temporary" "$destination"

        success "Installed PDF Reader file: $relative"

    done < <(find "$staged_skill" -type f -print0)

    # Create an isolated virtual environment.
    if [[ ! -x "$PDF_SKILL_DIR/.venv/bin/python" ]]; then
        info "Creating PDF Reader Python virtual environment..."

        python3 -m venv "$PDF_SKILL_DIR/.venv"
    fi

    [[ -x "$PDF_SKILL_DIR/.venv/bin/pip" ]] ||
        die "PDF Reader virtual environment is missing pip."

    info "Installing PDF Reader Python dependencies..."

    "$PDF_SKILL_DIR/.venv/bin/pip" install \
        --disable-pip-version-check \
        -r "$PDF_SKILL_DIR/requirements.txt"

    success "PDF Reader skill installed."
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

    info "Checking commit skill..."

    if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
        success "Commit skill found."
    else
        error "Commit skill missing."
        failed=1
    fi

    info "Checking PDF Reader skill..."

    if [[ -f "$PDF_SKILL_DIR/SKILL.md" ]]; then
        success "PDF Reader SKILL.md found."
    else
        error "PDF Reader SKILL.md missing."
        failed=1
    fi

    if [[ -f "$PDF_SKILL_DIR/requirements.txt" ]]; then
        success "PDF Reader requirements found."
    else
        error "PDF Reader requirements missing."
        failed=1
    fi

    for script in pdf_info.py pdf_extract.py pdf_render.py pdf_search.py; do
        if [[ -f "$PDF_SKILL_DIR/scripts/$script" ]]; then
            success "PDF Reader: $script"
        else
            error "PDF Reader script missing: $script"
            failed=1
        fi
    done

    if [[ -x "$PDF_SKILL_DIR/.venv/bin/python" ]]; then
        success "PDF Reader virtual environment found."
    else
        error "PDF Reader virtual environment missing."
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
    echo "  - pdf-reader"

    echo
    echo "Pi directory: $PI_DIR"
    echo "Restart Pi or run /reload to load the skills and extensions."
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
            install_pdf_reader
            print_summary
            ;;

        update)
            command -v pi >/dev/null 2>&1 ||
                die "Pi is not installed. Run ./install.sh first."

            update_packages
            install_extensions
            install_skills
            install_pdf_reader
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
