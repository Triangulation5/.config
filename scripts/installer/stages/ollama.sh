#!/usr/bin/env bash
#
# Install Ollama (if missing) and pull the models you pick
# for the pi agent harness.
#
# Usage:
#   ./setup-ollama.sh                       interactive checkbox selector
#   ./setup-ollama.sh --yes                 recommended models only, no prompts
#   ./setup-ollama.sh --models a:1b,b:7b    explicit list, no selector
#   ./setup-ollama.sh --dry-run             show what would happen, change nothing
#
# Options:
#   -y, --yes          Don't ask questions (installs Ollama if missing, picks
#                      the recommended models unless --models is given).
#       --models LIST  Comma-separated model tags to pull.
#       --skip-install Never try to install Ollama.
#       --dry-run      Don't install, start servers, or pull anything.
#       --force        Continue even if free disk space looks insufficient.
#       --keep-server  Leave an `ollama serve` that this script started running.
#   -h, --help         Show this help.
#
# Safety notes:
#   * Download sizes are read live from registry.ollama.ai before anything is
#     pulled, and total size is checked against free disk space and RAM.
#   * The Ollama installer is downloaded to a temp file first, so you can view
#     it before it runs. Nothing is piped straight into a shell.
#   * Model names are validated; no eval; all variables are quoted.
#
# Works with bash 3.2+ (macOS default).

set -euo pipefail
IFS=$' \t\n'

# Settings
REGISTRY="https://registry.ollama.ai"
OLLAMA_URL="${OLLAMA_HOST_URL:-http://127.0.0.1:11434}"
BIG_DOWNLOAD_BYTES=40000000000   # above this, you must type "yes" to continue
MAX_PULL_ATTEMPTS=3

# Output
if [ -t 2 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi

info() { printf '%s==>%s %s\n' "$GREEN" "$RESET" "$*" >&2; }
warn() { printf '%s!! %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
err()  { printf '%sxx %s%s\n' "$RED" "$*" "$RESET" >&2; }
die()  { err "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
is_num() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# State
ASSUME_YES=0; SKIP_INSTALL=0; DRY_RUN=0; FORCE=0; KEEP_SERVER=0
EXPLICIT_MODELS=""
WORKDIR=""; SERVER_PID=""; CURSOR_HIDDEN=0; HAVE_TTY=0
OS=""; RAM_BYTES=0; INSTALLED_LIST=""
RENDERED=0

cleanup() {
  local rc=$?
  if [ "$CURSOR_HIDDEN" -eq 1 ]; then printf '\033[?25h' >&2; fi
  if [ -n "$SERVER_PID" ] && [ "$KEEP_SERVER" -eq 0 ]; then
    if kill "$SERVER_PID" 2>/dev/null; then
      info "Stopped the Ollama server this script started (use --keep-server to leave it running)."
    fi
  fi
  if [ -n "$WORKDIR" ]; then rm -rf "$WORKDIR"; fi
  return "$rc"
}
trap cleanup EXIT
trap 'printf "\n" >&2; warn "Interrupted."; exit 130' INT TERM

# Model list
# Tiers: 0 extra small, 1 small, 2 medium, 3 high, 4 extra high, 5 custom
TIER_NAMES=("Extra small" "Small" "Medium" "High" "Extra high" "Custom")
TIER_DESC=(
  "tiny models, smoke tests"
  "testing, subagents, quick tasks"
  "everyday local agents"
  "capable, reasonably sized agents"
  "workstation-class, very large downloads"
  "from --models"
)

M_NAME=(); M_TIER=(); M_REC=(); M_SIZE=(); M_INST=(); M_SEL=()

add_model() { # tier name [recommended]
  M_NAME+=("$2"); M_TIER+=("$1"); M_REC+=("${3:-0}")
  M_SIZE+=("unknown"); M_INST+=(0); M_SEL+=(0)
}

build_catalog() {
  # Extra small
  add_model 0 "qwen3:0.6b"
  add_model 0 "gemma3:270m"
  add_model 0 "gemma3:1b"
  add_model 0 "llama3.2:1b"
  # Small (testing, subagents, etc.)
  add_model 1 "qwen3:1.7b"
  add_model 1 "qwen3:4b" 1
  add_model 1 "qwen3.5:2b"
  add_model 1 "qwen3.5:4b"
  add_model 1 "gemma4:e4b"
  add_model 1 "gemma4:e2b"
  add_model 1 "ministral-3:3b"
  add_model 1 "nemotron-3-nano:4b"
  add_model 1 "deepseek-r1:7b"
  # Medium
  add_model 2 "qwen3:8b"
  add_model 2 "llama3.1:8b"
  add_model 2 "gemma3:12b"
  add_model 2 "qwen3:14b"
  add_model 2 "deepseek-r1:14b"
  # High (reasonable sized agents)
  add_model 3 "gpt-oss:20b" 1
  add_model 3 "glm-4.7-flash"
  add_model 3 "qwen3:30b-a3b"
  add_model 3 "qwen3-coder:30b"
  add_model 3 "qwen3.6:27b-q4_K_M"
  add_model 3 "qwen3.6:35b-a3b"
  add_model 3 "qwen3:32b"
  add_model 3 "gemma3:27b"
  add_model 3 "deepseek-r1:32b"
  # Extra high
  add_model 4 "gpt-oss:120b"
  add_model 4 "llama3.3:70b"
  add_model 4 "deepseek-r1:70b"
  add_model 4 "qwen3:235b-a22b"
}

find_model() { # name -> prints index, returns 1 if absent
  local i
  for i in "${!M_NAME[@]}"; do
    if [ "${M_NAME[$i]}" = "$1" ]; then printf '%s' "$i"; return 0; fi
  done
  return 1
}

# Utilities
fmt_bytes() {
  awk -v b="$1" 'BEGIN { if (b >= 1e9) printf "%.1f GB", b/1e9; else printf "%.0f MB", b/1e6 }'
}

detect_system() {
  OS="$(uname -s)"
  RAM_BYTES=0
  case "$OS" in
    Linux)  RAM_BYTES="$(awk '/^MemTotal:/ {printf "%.0f", $2*1024}' /proc/meminfo 2>/dev/null || true)" ;;
    Darwin) RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || true)" ;;
  esac
  is_num "$RAM_BYTES" || RAM_BYTES=0
}

models_dir() {
  if [ -n "${OLLAMA_MODELS:-}" ]; then printf '%s' "$OLLAMA_MODELS"
  elif [ "$OS" = "Linux" ] && [ -d /usr/share/ollama/.ollama/models ]; then
    printf '%s' /usr/share/ollama/.ollama/models
  else printf '%s' "$HOME/.ollama/models"; fi
}

free_bytes() { # path (walks up to an existing parent)
  local d="$1"
  while [ ! -d "$d" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done
  df -Pk "$d" 2>/dev/null | awk 'NR==2 { printf "%.0f", $4*1024 }'
}

# Is the model bigger than ~70% of system RAM?
too_big_for_ram() { # bytes
  [ "$RAM_BYTES" -gt 0 ] && is_num "$1" && [ $(( $1 * 10 )) -gt $(( RAM_BYTES * 7 )) ]
}

# Terminal I/O
open_tty() {
  if ( : </dev/tty ) 2>/dev/null; then exec 3</dev/tty; HAVE_TTY=1; fi
}

ask() { # prompt -> REPLY
  REPLY=""
  if [ "$HAVE_TTY" -ne 1 ]; then return 1; fi
  printf '%s' "$1" >&2
  IFS= read -r -u 3 REPLY || REPLY=""
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Install step
install_ollama() {
  if have ollama; then
    info "Ollama already installed: $(ollama --version 2>&1 | head -n1)"
    return 0
  fi
  if [ "$SKIP_INSTALL" -eq 1 ]; then die "Ollama not found and --skip-install was given."; fi
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] Ollama not found; would install it."; return 0; fi

  warn "Ollama is not installed."
  case "$OS" in
    Linux)
      have curl || die "curl is required to download the Ollama installer."
      local script="$WORKDIR/ollama-install.sh" sum="" ans
      info "Downloading the official installer (https://ollama.com/install.sh) ..."
      curl -fsSL --proto '=https' --tlsv1.2 -o "$script" https://ollama.com/install.sh \
        || die "Could not download the installer."
      [ -s "$script" ] || die "Installer download is empty."
      head -n1 "$script" | grep -q '^#!' || die "Downloaded installer doesn't look like a script; aborting."
      if have sha256sum; then sum="$(sha256sum "$script" | cut -d' ' -f1)"
      elif have shasum;  then sum="$(shasum -a 256 "$script" | cut -d' ' -f1)"; fi
      [ -n "$sum" ] && info "Installer sha256: $sum"
      while :; do
        if [ "$ASSUME_YES" -eq 1 ]; then break; fi
        ask "Run the installer now? It will use sudo. [y/N/v=view first] " \
          || die "No terminal to confirm with. Re-run with --yes to allow the install."
        ans="$(lower "$REPLY")"
        case "$ans" in
          y|yes) break ;;
          v|view) "${PAGER:-less}" "$script" || true ;;
          *) die "Aborted: Ollama is required." ;;
        esac
      done
      sh "$script"
      ;;
    Darwin)
      if have brew; then
        if [ "$ASSUME_YES" -ne 1 ]; then
          ask "Install Ollama with Homebrew (brew install ollama)? [y/N] " \
            || die "No terminal to confirm with. Re-run with --yes."
          case "$(lower "$REPLY")" in y|yes) ;; *) die "Aborted: Ollama is required." ;; esac
        fi
        brew install ollama
      else
        die "Homebrew not found. Install Ollama from https://ollama.com/download and re-run."
      fi
      ;;
    *)
      die "Unsupported OS for auto-install ($OS). On Windows: winget install Ollama.Ollama, or see https://ollama.com/download"
      ;;
  esac

  have ollama || die "Install finished but 'ollama' is not on PATH. Open a new shell and re-run."
  info "Installed: $(ollama --version 2>&1 | head -n1)"
}

server_up() { curl -fs --max-time 2 "$OLLAMA_URL/api/version" >/dev/null 2>&1; }

ensure_server() {
  if [ "$DRY_RUN" -eq 1 ]; then return 0; fi
  if server_up; then info "Ollama server is running."; return 0; fi

  info "Starting a temporary 'ollama serve' ..."
  nohup ollama serve >"$WORKDIR/ollama-serve.log" 2>&1 &
  SERVER_PID=$!

  local i
  for i in $(seq 1 30); do
    if server_up; then info "Ollama server is up."; return 0; fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  tail -n 20 "$WORKDIR/ollama-serve.log" >&2 || true
  die "Ollama server did not start."
}

load_installed() {
  INSTALLED_LIST=""
  if [ "$DRY_RUN" -eq 1 ] || ! have ollama; then return 0; fi
  INSTALLED_LIST="$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' || true)"
}

mark_installed() {
  local i n
  for i in "${!M_NAME[@]}"; do
    n="${M_NAME[$i]}"
    if printf '%s\n' "$INSTALLED_LIST" | grep -Fxq -- "$n"; then
      if [ "${M_SEL[$i]}" = "1" ] && [ -n "$EXPLICIT_MODELS" ]; then info "$n is already installed; skipping."; fi
      M_INST[$i]=1; M_SEL[$i]=0
    fi
  done
}

# Registry sizes
# Prints total download size in bytes, "missing" (404), or "unknown".
registry_size() {
  local name="$1" repo tag code total body="$WORKDIR/manifest.$$.$RANDOM"
  repo="${name%%:*}"; tag="latest"
  case "$name" in *:*) tag="${name#*:}" ;; esac
  case "$repo" in */*) ;; *) repo="library/$repo" ;; esac

  code="$(curl -s --max-time 10 --proto '=https' -o "$body" -w '%{http_code}' \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "$REGISTRY/v2/$repo/manifests/$tag" 2>/dev/null)" || code=000

  case "$code" in
    200)
      total="$( { grep -o '"size":[[:space:]]*[0-9]*' "$body" | grep -o '[0-9]*$' \
        | awk '{ s += $1 } END { if (NR > 0) printf "%.0f", s }'; } 2>/dev/null || true )"
      if is_num "$total" && [ "$total" -gt 0 ]; then printf '%s' "$total"; else printf 'unknown'; fi
      ;;
    404) printf 'missing' ;;
    *)   printf 'unknown' ;;
  esac
  rm -f "$body"
}

fetch_sizes() { # indices...
  if [ "$#" -eq 0 ]; then return 0; fi
  info "Checking download sizes on registry.ollama.ai ..."
  local i n=0
  for i in "$@"; do
    ( registry_size "${M_NAME[$i]}" >"$WORKDIR/size.$i" 2>/dev/null || true ) &
    n=$((n + 1))
    if [ $((n % 8)) -eq 0 ]; then wait; fi
  done
  wait
  for i in "$@"; do
    if [ -s "$WORKDIR/size.$i" ]; then M_SIZE[$i]="$(cat "$WORKDIR/size.$i")"; fi
  done
}

# Totals/flags
SEL_COUNT=0; SEL_BYTES=0; SEL_UNK=0; SEL_BIG=0

compute_totals() {
  SEL_COUNT=0; SEL_BYTES=0; SEL_UNK=0; SEL_BIG=0
  local i
  for i in "${!M_NAME[@]}"; do
    if [ "${M_SEL[$i]}" = "1" ]; then
      SEL_COUNT=$((SEL_COUNT + 1))
      if is_num "${M_SIZE[$i]}"; then
        SEL_BYTES=$((SEL_BYTES + ${M_SIZE[$i]}))
        if too_big_for_ram "${M_SIZE[$i]}"; then SEL_BIG=$((SEL_BIG + 1)); fi
      else
        SEL_UNK=$((SEL_UNK + 1))
      fi
    fi
  done
}

selectable() { # idx
  [ "${M_INST[$1]}" = "0" ] && [ "${M_SIZE[$1]}" != "missing" ]
}

# Checkbox selector
ROW_T=(); ROW_I=()
CUR=0; TOP=0; VIEW_H=10; FRAME=15; FREE_BYTES=0

build_rows() {
  ROW_T=(); ROW_I=()
  local t i
  for t in 0 1 2 3 4; do
    ROW_T+=("H"); ROW_I+=("$t")
    for i in "${!M_NAME[@]}"; do
      if [ "${M_TIER[$i]}" = "$t" ]; then ROW_T+=("M"); ROW_I+=("$i"); fi
    done
  done
}

emit() { printf '\r\033[2K%s\n' "$1" >&2; }

item_line() { # idx is_cursor
  local i="$1" cur="$2" mark=" " box="[ ]" size="?" tag=""
  if [ "$cur" = "1" ]; then mark=">"; fi
  if [ "${M_INST[$i]}" = "1" ]; then box="[=]"; tag="${DIM}already installed${RESET}"
  elif [ "${M_SIZE[$i]}" = "missing" ]; then box="[-]"; tag="${RED}not found in registry${RESET}"
  elif [ "${M_SEL[$i]}" = "1" ]; then box="[x]"; fi

  if is_num "${M_SIZE[$i]}"; then size="$(fmt_bytes "${M_SIZE[$i]}")"
  elif [ "${M_SIZE[$i]}" = "missing" ]; then size="-"; fi

  if [ -z "$tag" ]; then
    if [ "${M_REC[$i]}" = "1" ]; then tag="${GREEN}recommended${RESET}"; fi
    if too_big_for_ram "${M_SIZE[$i]}"; then tag="${tag:+$tag }${YELLOW}! may exceed RAM${RESET}"; fi
  fi

  local line
  line="$(printf '%s %s %-22s %9s  %s' "$mark" "$box" "${M_NAME[$i]}" "$size" "$tag")"
  if [ "$cur" = "1" ]; then line="${BOLD}${line}${RESET}"; fi
  printf '%s' "$line"
}

adjust_view() {
  local total=${#ROW_T[@]}
  if [ "$CUR" -lt "$TOP" ]; then
    TOP=$CUR
    if [ "$TOP" -gt 0 ] && [ "${ROW_T[$((TOP - 1))]}" = "H" ]; then TOP=$((TOP - 1)); fi
  fi
  if [ "$CUR" -ge $((TOP + VIEW_H)) ]; then TOP=$((CUR - VIEW_H + 1)); fi
  if [ $((TOP + VIEW_H)) -gt "$total" ]; then TOP=$((total - VIEW_H)); fi
  if [ "$TOP" -lt 0 ]; then TOP=0; fi
}

render() {
  if [ "$RENDERED" -eq 1 ]; then printf '\033[%dA' "$FRAME" >&2; fi
  RENDERED=1
  adjust_view
  compute_totals

  emit "${BOLD}Select the Ollama models to download${RESET}"
  emit "${DIM}↑/↓ move · space toggle · a select tier · n clear all · enter confirm · q quit${RESET}"

  local r i t
  for ((r = TOP; r < TOP + VIEW_H; r++)); do
    if [ "$r" -ge "${#ROW_T[@]}" ]; then emit ""; continue; fi
    i="${ROW_I[$r]}"
    if [ "${ROW_T[$r]}" = "H" ]; then
      emit "${BOLD}-- ${TIER_NAMES[$i]}${RESET}${DIM} — ${TIER_DESC[$i]}${RESET}"
    else
      if [ "$r" -eq "$CUR" ]; then emit "$(item_line "$i" 1)"; else emit "$(item_line "$i" 0)"; fi
    fi
  done

  local colour="$GREEN" status
  if [ "$FREE_BYTES" -gt 0 ] && [ "$SEL_BYTES" -gt "$FREE_BYTES" ]; then colour="$RED"; fi
  status="Selected: $SEL_COUNT · download ≈ $(fmt_bytes "$SEL_BYTES")"
  if [ "$FREE_BYTES" -gt 0 ]; then status="$status · free disk: $(fmt_bytes "$FREE_BYTES")"; fi
  emit "${colour}${status}${RESET}"

  local w=""
  if [ "$SEL_UNK" -gt 0 ]; then w="$SEL_UNK selected model(s) have unknown size. "; fi
  if [ "$SEL_BIG" -gt 0 ]; then w="${w}! $SEL_BIG selected model(s) may not fit in RAM."; fi
  if [ -n "$w" ]; then emit "${YELLOW}${w}${RESET}"; else emit ""; fi

  emit "${DIM}Sizes are live from registry.ollama.ai · ! = over ~70% of RAM ($(fmt_bytes "$RAM_BYTES")); GPU VRAM not checked${RESET}"
}

KEY=""
read_key() {
  local ch rest=""
  KEY=""
  IFS= read -rsn1 -u 3 ch || { KEY="quit"; return 0; }
  case "$ch" in
    "")   KEY="enter" ;;
    " ")  KEY="toggle" ;;
    $'\033')
      IFS= read -rsn2 -t 0.05 -u 3 rest 2>/dev/null \
        || IFS= read -rsn2 -t 1 -u 3 rest 2>/dev/null \
        || rest=""
      case "$rest" in
        '[A'|'OA') KEY="up" ;;
        '[B'|'OB') KEY="down" ;;
      esac
      ;;
    k|K) KEY="up" ;;
    j|J) KEY="down" ;;
    a|A) KEY="tier" ;;
    n|N) KEY="none" ;;
    q|Q) KEY="quit" ;;
  esac
  return 0
}

move_cursor() { # +1 / -1
  local r=$CUR
  while :; do
    r=$((r + $1))
    if [ "$r" -lt 0 ] || [ "$r" -ge "${#ROW_T[@]}" ]; then return 0; fi
    if [ "${ROW_T[$r]}" = "M" ]; then CUR=$r; return 0; fi
  done
}

toggle_current() {
  local i="${ROW_I[$CUR]}"
  if selectable "$i"; then
    if [ "${M_SEL[$i]}" = "1" ]; then M_SEL[$i]=0; else M_SEL[$i]=1; fi
  fi
}

select_current_tier() {
  local i t="${M_TIER[${ROW_I[$CUR]}]}"
  for i in "${!M_NAME[@]}"; do
    if [ "${M_TIER[$i]}" = "$t" ] && selectable "$i"; then M_SEL[$i]=1; fi
  done
}

clear_all() { local i; for i in "${!M_NAME[@]}"; do M_SEL[$i]=0; done; }

run_menu() {
  [ "$HAVE_TTY" -eq 1 ] || die "No terminal available for the selector. Use --models or --yes."
  case "${TERM:-dumb}" in dumb) die "TERM=dumb can't draw the selector. Use --models or --yes." ;; esac

  build_rows
  local lines
  lines="$(tput lines 2>/dev/null || echo 24)"; is_num "$lines" || lines=24
  VIEW_H=$((lines - 8)); [ "$VIEW_H" -lt 6 ] && VIEW_H=6
  [ "$VIEW_H" -gt "${#ROW_T[@]}" ] && VIEW_H=${#ROW_T[@]}
  FRAME=$((VIEW_H + 5))

  CUR=1; TOP=0     # row 0 is a header; row 1 is the first model
  printf '\033[?25l' >&2; CURSOR_HIDDEN=1

  while :; do
    render
    read_key
    case "$KEY" in
      up)     move_cursor -1 ;;
      down)   move_cursor 1 ;;
      toggle) toggle_current ;;
      tier)   select_current_tier ;;
      none)   clear_all ;;
      enter)  break ;;
      quit)   printf '\033[?25h' >&2; CURSOR_HIDDEN=0; printf '\n' >&2; info "Aborted. Nothing was downloaded."; exit 0 ;;
    esac
  done
  printf '\033[?25h\n' >&2; CURSOR_HIDDEN=0
}

# Model input
NAME_RE='^[A-Za-z0-9][A-Za-z0-9._/-]*(:[A-Za-z0-9._-]+)?$'

apply_explicit() {
  local raw n idx
  local IFS=','
  # shellcheck disable=SC2206
  local list=($EXPLICIT_MODELS)
  IFS=$' \t\n'
  for raw in "${list[@]}"; do
    n="$(printf '%s' "$raw" | tr -d '[:space:]')"
    [ -n "$n" ] || continue
    [[ "$n" =~ $NAME_RE ]] || die "Invalid model name: '$n'"
    if idx="$(find_model "$n")"; then :; else
      add_model 5 "$n"; idx=$(( ${#M_NAME[@]} - 1 ))
    fi
    M_SEL[$idx]=1
  done
}

select_recommended() {
  local i
  for i in "${!M_NAME[@]}"; do
    if [ "${M_REC[$i]}" = "1" ]; then M_SEL[$i]=1; fi
  done
}

# Review + confirm
review_and_confirm() {
  compute_totals
  local i
  # Drop anything already installed, and anything not in the registry.
  for i in "${!M_NAME[@]}"; do
    if [ "${M_SEL[$i]}" = "1" ] && [ "${M_SIZE[$i]}" = "missing" ]; then
      warn "Skipping ${M_NAME[$i]}: not found in the Ollama registry."; M_SEL[$i]=0
    fi
  done
  compute_totals
  if [ "$SEL_COUNT" -eq 0 ]; then info "Nothing to download."; exit 0; fi

  printf '\n%sAbout to download:%s\n' "$BOLD" "$RESET" >&2
  for i in "${!M_NAME[@]}"; do
    if [ "${M_SEL[$i]}" = "1" ]; then
      local s="size unknown"
      if is_num "${M_SIZE[$i]}"; then s="$(fmt_bytes "${M_SIZE[$i]}")"; fi
      printf '  - %-24s %10s\n' "${M_NAME[$i]}" "$s" >&2
    fi
  done
  printf '  %s\n' "------------------------------------" >&2
  printf '  %-24s %10s\n' "Total" "$(fmt_bytes "$SEL_BYTES")" >&2

  local dir need
  dir="$(models_dir)"
  FREE_BYTES="$(free_bytes "$dir")"; is_num "$FREE_BYTES" || FREE_BYTES=0
  info "Models are stored in: $dir"
  if [ "$FREE_BYTES" -gt 0 ]; then info "Free disk space there: $(fmt_bytes "$FREE_BYTES")"; fi

  if [ "$SEL_UNK" -gt 0 ]; then
    warn "$SEL_UNK model(s) have unknown size (registry unreachable?); the total is understated."
  fi
  if [ "$SEL_BIG" -gt 0 ]; then
    warn "$SEL_BIG model(s) are larger than ~70% of your RAM ($(fmt_bytes "$RAM_BYTES")); they may be slow or fail to load without a big GPU."
  fi

  need=$(( SEL_BYTES + SEL_BYTES / 10 ))
  if [ "$FREE_BYTES" -gt 0 ] && [ "$need" -gt "$FREE_BYTES" ]; then
    if [ "$FORCE" -eq 1 ]; then
      warn "Not enough free disk space ($(fmt_bytes "$need") needed incl. 10% margin). Continuing due to --force."
    else
      die "Not enough free disk space: need about $(fmt_bytes "$need") (incl. 10% margin), have $(fmt_bytes "$FREE_BYTES"). Free some space or use --force."
    fi
  fi

  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] Would download the models above. Nothing was changed."; exit 0; fi
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi

  if [ "$SEL_BYTES" -ge "$BIG_DOWNLOAD_BYTES" ]; then
    warn "This is a very large download ($(fmt_bytes "$SEL_BYTES"))."
    ask "Type 'yes' to continue: " || die "No terminal to confirm with."
    [ "$(lower "$REPLY")" = "yes" ] || { info "Aborted. Nothing was downloaded."; exit 0; }
  else
    ask "Download $(fmt_bytes "$SEL_BYTES") now? [y/N] " || die "No terminal to confirm with. Use --yes."
    case "$(lower "$REPLY")" in y|yes) ;; *) info "Aborted. Nothing was downloaded."; exit 0 ;; esac
  fi
}

# Pulling
pull_one() {
  local n=1
  while [ "$n" -le "$MAX_PULL_ATTEMPTS" ]; do
    if ollama pull "$1"; then return 0; fi
    warn "Attempt $n/$MAX_PULL_ATTEMPTS failed for $1"
    n=$((n + 1)); sleep 3
  done
  return 1
}

pull_all() {
  local OK=() FAILED=() i
  for i in "${!M_NAME[@]}"; do
    if [ "${M_SEL[$i]}" = "1" ]; then
      info "Pulling ${M_NAME[$i]} ..."
      if pull_one "${M_NAME[$i]}"; then OK+=("${M_NAME[$i]}"); else FAILED+=("${M_NAME[$i]}"); fi
    fi
  done

  printf '\n%sSummary%s\n' "$BOLD" "$RESET" >&2
  if [ "${#OK[@]}" -gt 0 ]; then
    printf '%sDownloaded:%s\n' "$GREEN" "$RESET" >&2; printf '  + %s\n' "${OK[@]}" >&2
  fi
  if [ "${#FAILED[@]}" -gt 0 ]; then
    printf '%sFailed:%s\n' "$RED" "$RESET" >&2; printf '  - %s\n' "${FAILED[@]}" >&2
  fi
  printf '\n' >&2
  ollama list || true
  if [ -n "$SERVER_PID" ] && [ "$KEEP_SERVER" -eq 0 ]; then
    info "Tip: start the server again later with 'ollama serve' (or your OS service)."
  fi
  [ "${#FAILED[@]}" -eq 0 ]
}

# Main
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes)       ASSUME_YES=1 ;;
      --skip-install) SKIP_INSTALL=1 ;;
      --dry-run)      DRY_RUN=1 ;;
      --force)        FORCE=1 ;;
      --keep-server)  KEEP_SERVER=1 ;;
      --models)       [ $# -ge 2 ] || die "--models needs a value"; EXPLICIT_MODELS="$2"; shift ;;
      --models=*)     EXPLICIT_MODELS="${1#*=}" ;;
      -h|--help)      usage ;;
      *)              die "Unknown option: $1 (try --help)" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  have curl || die "curl is required."
  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/setup-ollama.XXXXXX")"
  detect_system
  open_tty
  build_catalog

  install_ollama
  ensure_server
  load_installed

  local i idxs=()
  if [ -n "$EXPLICIT_MODELS" ]; then
    apply_explicit
  elif [ "$ASSUME_YES" -eq 1 ]; then
    select_recommended
  else
    select_recommended          # pre-checked; you can untick them
  fi
  mark_installed

  if [ -z "$EXPLICIT_MODELS" ] && [ "$ASSUME_YES" -ne 1 ]; then
    for i in "${!M_NAME[@]}"; do idxs+=("$i"); done          # menu needs every size
  else
    for i in "${!M_NAME[@]}"; do
      if [ "${M_SEL[$i]}" = "1" ]; then idxs+=("$i"); fi
    done
  fi
  fetch_sizes ${idxs[@]+"${idxs[@]}"}

  # Missing-from-registry entries can't be selected.
  for i in "${!M_NAME[@]}"; do
    if [ "${M_SIZE[$i]}" = "missing" ]; then
      if [ "${M_SEL[$i]}" = "1" ]; then warn "Skipping ${M_NAME[$i]}: not found in the Ollama registry."; fi
      M_SEL[$i]=0
    fi
  done

  if [ -z "$EXPLICIT_MODELS" ] && [ "$ASSUME_YES" -ne 1 ]; then
    FREE_BYTES="$(free_bytes "$(models_dir)")"; is_num "$FREE_BYTES" || FREE_BYTES=0
    run_menu
  fi

  review_and_confirm
  pull_all
}

main "$@"
