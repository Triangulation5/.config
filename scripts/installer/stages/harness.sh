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
#   PI_HARMONY_PATH=/custom/checkout ./install.sh
#   PI_CLAUDE_CODE_UI_PATH=/custom/checkout ./install.sh (legacy override)

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
CUSTOM_PI_HARMONY="${PI_HARMONY_PATH:-${PI_CLAUDE_CODE_UI_PATH:-$HOME/Projects/pi-claude-code-ui}}"
CUSTOM_PI_HARMONY_REPO="${PI_HARMONY_REPO:-${PI_CLAUDE_CODE_UI_REPO:-https://github.com/Triangulation5/pi-harmony.git}}"
PI_HARMONY_PKG="$CUSTOM_PI_HARMONY"

packages=(
    "$PI_CC_UI_PKG"
)

optional_packages=(
    "npm:pi-subagents"
    "npm:@tychenjiajun/pi-voice"
)

extensions=(
    "btw"
    "continue"
)

# Output

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    E_RED=$'\033[31m'; E_YELLOW=$'\033[33m'; E_RESET=$'\033[0m'
else
    E_RED=""; E_YELLOW=""; E_RESET=""
fi

section() {
    printf '\n  %s%s%s\n' "$BOLD" "$*" "$RESET"
}

info() {
    printf '    %s\n' "$*"
}

success() {
    printf '    %s%s%s\n' "$DIM" "$*" "$RESET"
}

ui_status() {
    local kind="$1" title="$2" detail="${3:-}" tag color=""
    case "$kind" in
        ok)   tag="   Ok   "; color="$GREEN" ;;
        fail) tag=" Failed "; color="$RED" ;;
        warn) tag="  Warn  "; color="$YELLOW" ;;
        skip) tag="  Skip  "; color="$DIM" ;;
        *)    tag="   ??   " ;;
    esac
    printf '[%s%s%s] %s' "$color" "$tag" "$RESET" "$title"
    if [ -n "$detail" ]; then
        printf ' %s(%s)%s' "$DIM" "$detail" "$RESET"
    fi
    printf '\n'
}

warn() {
    printf '%s  ! %s%s\n' "$E_YELLOW" "$*" "$E_RESET" >&2
}

error() {
    printf '%s  x %s%s\n' "$E_RED" "$*" "$E_RESET" >&2
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

ensure_custom_pi_harmony() {
    local package_name

    if [[ ! -d "$CUSTOM_PI_HARMONY" ]]; then
        command -v git >/dev/null 2>&1 ||
            die "git is required to clone the Pi Harmony repository."
        mkdir -p "$(dirname "$CUSTOM_PI_HARMONY")"
        info "Cloning Pi Harmony from $CUSTOM_PI_HARMONY_REPO..."
        git clone --depth 1 -- "$CUSTOM_PI_HARMONY_REPO" "$CUSTOM_PI_HARMONY" ||
            die "Failed to clone the Pi Harmony repository."
    fi

    [[ -f "$CUSTOM_PI_HARMONY/package.json" ]] ||
        die "Pi Harmony checkout has no package.json: $CUSTOM_PI_HARMONY"
    package_name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name", ""))' \
        "$CUSTOM_PI_HARMONY/package.json")"
    [[ "$package_name" == "pi-harmony" ]] ||
        die "Expected pi-harmony at $CUSTOM_PI_HARMONY, found package '$package_name'."

    if [[ ! -d "$PI_HARMONY_PKG/node_modules" ]]; then
        command -v npm >/dev/null 2>&1 ||
            die "npm is required to install dependencies for $PI_HARMONY_PKG."
        info "Installing dependencies for Pi Harmony..."
        (cd "$PI_HARMONY_PKG" && npm install)
    fi

    return 0
}

remove_npm_pi_claude_code_ui() {
    if command -v pi >/dev/null 2>&1 && pi list 2>/dev/null | grep -q "npm:pi-claude-code-ui"; then
        info "Removing the old npm pi-claude-code-ui package in favor of $PI_HARMONY_PKG..."
        pi remove npm:pi-claude-code-ui ||
            die "Could not remove npm:pi-claude-code-ui before installing the custom version."
    fi
}

remove_npm_rpiv_ask_user_question() {
    if command -v pi >/dev/null 2>&1 &&
       pi list 2>/dev/null | grep -q "npm:@juicesharp/rpiv-ask-user-question"; then
        info "Removing npm:@juicesharp/rpiv-ask-user-question in favor of the bundled extension..."
        pi remove npm:@juicesharp/rpiv-ask-user-question ||
            die "Could not remove npm:@juicesharp/rpiv-ask-user-question before installing the bundled extension."
    fi
}

# Package installation

install_packages() {
    local package answer
    local -a selected_optional=()

    info "Installing Pi packages..."
    ensure_custom_pi_harmony
    remove_npm_pi_claude_code_ui
    remove_npm_rpiv_ask_user_question

    if [[ -t 0 ]]; then
        for package in "${optional_packages[@]}"; do
            if read -r -p "    Install optional package $package? [y/N] " answer; then
                case "$answer" in
                    [yY]*) selected_optional+=("$package") ;;
                esac
            fi
        done
    fi

    for package in "${packages[@]}"; do
        info "Installing $package"

        pi install "$package"

        success "$package"
    done

    for package in "${selected_optional[@]}"; do
        info "Installing optional package $package"

        pi install "$package"

        success "$package"
    done
}

update_packages() {
    info "Updating installed Pi packages..."

    ensure_custom_pi_harmony
    remove_npm_pi_claude_code_ui
    remove_npm_rpiv_ask_user_question
    pi update --extensions
    info "Reinstalling Pi Harmony from $PI_HARMONY_PKG..."
    pi install "$PI_HARMONY_PKG"

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

    section "Checking Pi installation"

    if command -v pi >/dev/null 2>&1; then
        ui_status ok "Pi executable" "$(command -v pi)"
    else
        ui_status fail "Pi executable" "not found"
        failed=1
    fi

    for extension in "${extensions[@]}"; do
        if [[ -f "$EXT_DIR/$extension.ts" ]]; then
            ui_status ok "Extension $extension.ts"
        else
            ui_status fail "Extension $extension.ts" "missing"
            failed=1
        fi
    done

    if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
        ui_status ok "Commit skill"
    else
        ui_status fail "Commit skill" "missing"
        failed=1
    fi

    if [[ -f "$PDF_SKILL_DIR/SKILL.md" ]]; then
        ui_status ok "PDF Reader SKILL.md"
    else
        ui_status fail "PDF Reader SKILL.md" "missing"
        failed=1
    fi

    if [[ -f "$PDF_SKILL_DIR/requirements.txt" ]]; then
        ui_status ok "PDF Reader requirements"
    else
        ui_status fail "PDF Reader requirements" "missing"
        failed=1
    fi

    for script in pdf_info.py pdf_extract.py pdf_render.py pdf_search.py; do
        if [[ -f "$PDF_SKILL_DIR/scripts/$script" ]]; then
            ui_status ok "PDF Reader: $script"
        else
            ui_status fail "PDF Reader: $script" "missing"
            failed=1
        fi
    done

    if [[ -x "$PDF_SKILL_DIR/.venv/bin/python" ]]; then
        ui_status ok "PDF Reader virtual environment"
    else
        ui_status fail "PDF Reader virtual environment" "missing"
        failed=1
    fi

    if command -v pi >/dev/null 2>&1; then
        section "Installed Pi packages"
        pi list
    fi

    return "$failed"
}

# Summary

print_summary() {
    section "Pi configuration $VERSION completed"
    info "packages     ${packages[*]}"
    info "extensions   ${extensions[*]}"
    info "skills       commit, pdf-reader"
    info "directory    $PI_DIR"
    success "Restart Pi or run /reload to load the skills and extensions."
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
