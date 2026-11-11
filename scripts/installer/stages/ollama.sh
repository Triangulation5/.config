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
#     pulled, and total size is checked against free disk space and RAM/VRAM.
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
OS=""; RAM_BYTES=0; RAM_AVAIL_BYTES=0; INSTALLED_LIST=""
VRAM_BYTES=0; GPU_NAME=""; IS_UNIFIED_MEM=0
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
M_SIZE_FMT=(); M_FIT=()

add_model() { # tier name [recommended]
  M_NAME+=("$2"); M_TIER+=("$1"); M_REC+=("${3:-0}")
  M_SIZE+=("unknown"); M_INST+=(0); M_SEL+=(0)
  M_SIZE_FMT+=("?"); M_FIT+=("unknown")
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

# Pure bash byte formatting (avoids slow subshell & awk forks during interactive rendering)
fmt_bytes() {
  local b="${1:-0}"
  if ! is_num "$b" || [ "$b" -le 0 ]; then
    printf '0 B'
    return 0
  fi
  if [ "$b" -ge 1000000000 ]; then
    local dec=$(( (b + 50000000) / 100000000 ))
    printf '%d.%d GB' $(( dec / 10 )) $(( dec % 10 ))
  elif [ "$b" -ge 1000000 ]; then
    printf '%d MB' $(( (b + 500000) / 1000000 ))
  elif [ "$b" -ge 1000 ]; then
    printf '%d KB' $(( (b + 500) / 1000 ))
  else
    printf '%d B' "$b"
  fi
}

# Hardware detection (RAM, VRAM, and GPU architecture)
detect_vram() {
  VRAM_BYTES=0
  GPU_NAME=""
  IS_UNIFIED_MEM=0

  case "$OS" in
    Linux)
      # 1. NVIDIA
      if have nvidia-smi; then
        local out
        out="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>/dev/null || true)"
        if [ -n "$out" ]; then
          local total_mib=0 g_names=()
          while IFS=',' read -r g_name g_mib; do
            g_name="$(printf '%s' "$g_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            g_mib="$(printf '%s' "$g_mib" | tr -d '[:space:]')"
            if is_num "$g_mib" && [ "$g_mib" -gt 0 ]; then
              total_mib=$(( total_mib + g_mib ))
              g_names+=("$g_name")
            fi
          done <<< "$out"
          if [ "$total_mib" -gt 0 ]; then
            VRAM_BYTES=$(( total_mib * 1024 * 1024 ))
            GPU_NAME="${g_names[0]}"
            if [ "${#g_names[@]}" -gt 1 ]; then
              GPU_NAME="${#g_names[@]}x $GPU_NAME"
            fi
            GPU_NAME="$GPU_NAME ($(fmt_bytes "$VRAM_BYTES"))"
            IS_UNIFIED_MEM=0
            return 0
          fi
        fi
      fi

      # 2. AMD GPU via kernel sysfs DRM or rocm-smi
      local amd_vram=0 amd_name=""
      for f in /sys/class/drm/card*/device/mem_info_vram_total; do
        if [ -r "$f" ]; then
          local bytes
          bytes="$(cat "$f" 2>/dev/null || true)"
          if is_num "$bytes" && [ "$bytes" -gt 1073741824 ]; then
            amd_vram=$(( amd_vram + bytes ))
            local dev_dir
            dev_dir="$(dirname "$f")"
            if [ -r "$dev_dir/product_name" ] && [ -z "$amd_name" ]; then
              amd_name="$(cat "$dev_dir/product_name" 2>/dev/null || true)"
            fi
          fi
        fi
      done
      if [ "$amd_vram" -gt 0 ]; then
        VRAM_BYTES=$amd_vram
        if [ -z "$amd_name" ]; then amd_name="AMD Radeon GPU"; fi
        GPU_NAME="$amd_name ($(fmt_bytes "$VRAM_BYTES"))"
        IS_UNIFIED_MEM=0
        return 0
      fi

      # 3. Integrated GPU / CPU inference fallback
      if have lspci; then
        local gpu_line
        gpu_line="$(lspci 2>/dev/null | grep -i -E "vga|3d|display" | head -n1 || true)"
        if [ -n "$gpu_line" ]; then
          gpu_line="$(printf '%s' "$gpu_line" | sed -E 's/^[0-9a-fA-F:.]+ [^:]+: //; s/ \(rev [0-9a-fA-F]+\)//')"
          GPU_NAME="$gpu_line (CPU inference)"
        fi
      fi
      if [ -z "$GPU_NAME" ]; then
        GPU_NAME="CPU only (No dedicated GPU)"
      fi
      ;;

    Darwin)
      local arch
      arch="$(uname -m)"
      if [ "$arch" = "arm64" ]; then
        # Apple Silicon unified memory (GPU Metal shares RAM)
        local chip wired_limit
        chip="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")"
        wired_limit="$(sysctl -n iogpu.wired_mem_limit 2>/dev/null || true)"
        if is_num "$wired_limit" && [ "$wired_limit" -gt 0 ]; then
          VRAM_BYTES=$wired_limit
        else
          VRAM_BYTES=$(( RAM_BYTES * 3 / 4 ))
        fi
        GPU_NAME="$chip (Unified $(fmt_bytes "$RAM_BYTES"))"
        IS_UNIFIED_MEM=1
      else
        VRAM_BYTES=0
        GPU_NAME="Intel Mac GPU (CPU fallback)"
        IS_UNIFIED_MEM=0
      fi
      ;;

    *)
      GPU_NAME="Generic GPU / CPU"
      ;;
  esac
  return 0
}

detect_system() {
  OS="$(uname -s)"
  RAM_BYTES=0
  RAM_AVAIL_BYTES=0
  case "$OS" in
    Linux)
      if [ -f /proc/meminfo ]; then
        while read -r key val rest; do
          case "$key" in
            MemTotal:)     RAM_BYTES=$(( val * 1024 )) ;;
            MemAvailable:) RAM_AVAIL_BYTES=$(( val * 1024 )) ;;
          esac
        done < /proc/meminfo
      fi
      ;;
    Darwin)
      RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || true)"
      is_num "$RAM_BYTES" || RAM_BYTES=0
      RAM_AVAIL_BYTES=$(( RAM_BYTES * 7 / 10 ))
      ;;
  esac
  is_num "$RAM_BYTES" || RAM_BYTES=0
  is_num "$RAM_AVAIL_BYTES" || RAM_AVAIL_BYTES=$(( RAM_BYTES * 7 / 10 ))

  detect_vram
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

# Model memory fit evaluator
# Returns:
#   vram:    Fits completely in dedicated VRAM (full GPU acceleration)
#   unified: Fits in Apple Silicon unified memory (Metal GPU acceleration)
#   partial: Exceeds VRAM but fits combined VRAM + RAM (partial offload, moderate speed)
#   cpu:     No GPU present; fits in system RAM (pure CPU inference)
#   exceed:  Exceeds total available memory (likely to OOM, crash, or freeze)
model_fit() {
  local s="$1"
  if ! is_num "$s" || [ "$s" -le 0 ]; then
    printf 'unknown'; return 0
  fi

  if [ "$IS_UNIFIED_MEM" -eq 1 ]; then
    if [ "$VRAM_BYTES" -gt 0 ] && [ "$s" -le "$VRAM_BYTES" ]; then
      printf 'unified'
    elif [ "$RAM_BYTES" -gt 0 ] && [ $(( s * 10 )) -le $(( RAM_BYTES * 9 )) ]; then
      printf 'partial'
    else
      printf 'exceed'
    fi
  elif [ "$VRAM_BYTES" -gt 0 ]; then
    # Full VRAM fit threshold: 90% of VRAM (reserves buffer for KV cache and OS display)
    if [ $(( s * 10 )) -le $(( VRAM_BYTES * 9 )) ]; then
      printf 'vram'
    # Partial GPU offload: fits VRAM + 70% of system RAM
    elif [ "$RAM_BYTES" -gt 0 ] && [ "$s" -le $(( VRAM_BYTES + RAM_BYTES * 7 / 10 )) ]; then
      printf 'partial'
    else
      printf 'exceed'
    fi
  else
    # CPU only
    if [ "$RAM_BYTES" -gt 0 ] && [ $(( s * 10 )) -le $(( RAM_BYTES * 7 )) ]; then
      printf 'cpu'
    else
      printf 'exceed'
    fi
  fi
}

too_big_for_ram() { # bytes
  [ "$RAM_BYTES" -gt 0 ] && is_num "$1" && [ $(( $1 * 10 )) -gt $(( RAM_BYTES * 7 )) ]
}

too_big_for_vram() { # bytes
  [ "$VRAM_BYTES" -gt 0 ] && is_num "$1" && [ $(( $1 * 10 )) -gt $(( VRAM_BYTES * 9 )) ]
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
  local i
  for i in "$@"; do
    ( registry_size "${M_NAME[$i]}" >"$WORKDIR/size.$i" 2>/dev/null || true ) &
  done
  wait
  for i in "$@"; do
    if [ -s "$WORKDIR/size.$i" ]; then M_SIZE[$i]="$(cat "$WORKDIR/size.$i")"; fi
    if is_num "${M_SIZE[$i]}"; then
      M_SIZE_FMT[$i]="$(fmt_bytes "${M_SIZE[$i]}")"
      M_FIT[$i]="$(model_fit "${M_SIZE[$i]}")"
    else
      M_SIZE_FMT[$i]="-"
      M_FIT[$i]="unknown"
    fi
  done
}

# Totals & selection state
SEL_COUNT=0; SEL_BYTES=0; SEL_UNK=0; SEL_PARTIAL=0; SEL_EXCEED=0

compute_totals() {
  SEL_COUNT=0; SEL_BYTES=0; SEL_UNK=0; SEL_PARTIAL=0; SEL_EXCEED=0
  local i s
  for i in "${!M_NAME[@]}"; do
    if [ "${M_SEL[$i]}" = "1" ]; then
      SEL_COUNT=$((SEL_COUNT + 1))
      s="${M_SIZE[$i]}"
      if is_num "$s"; then
        SEL_BYTES=$((SEL_BYTES + s))
        case "${M_FIT[$i]:-}" in
          exceed)  SEL_EXCEED=$((SEL_EXCEED + 1)) ;;
          partial) SEL_PARTIAL=$((SEL_PARTIAL + 1)) ;;
        esac
      else
        SEL_UNK=$((SEL_UNK + 1))
      fi
    fi
  done
}

selectable() { # idx
  [ "${M_INST[$1]}" = "0" ] && [ "${M_SIZE[$1]}" != "missing" ]
}

# Checkbox selector UI
ROW_T=(); ROW_I=()
CUR=0; TOP=0; VIEW_H=10; FRAME=16; FREE_BYTES=0

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

# Pure bash in-memory line formatting (no subshells, no slow process forks)
format_item() { # idx is_cursor out_var
  local i="$1" cur="$2" mark=" " box="[ ]" size="?" tag=""
  [ "$cur" = "1" ] && mark=">"
  if [ "${M_INST[$i]}" = "1" ]; then
    box="[=]"
    tag="${DIM}already installed${RESET}"
  elif [ "${M_SIZE[$i]}" = "missing" ]; then
    box="[-]"
    tag="${RED}not found in registry${RESET}"
  elif [ "${M_SEL[$i]}" = "1" ]; then
    box="[x]"
  fi

  size="${M_SIZE_FMT[$i]:-?}"
  [ "${M_SIZE[$i]}" = "missing" ] && size="-"

  if [ -z "$tag" ]; then
    if [ "${M_REC[$i]}" = "1" ]; then
      tag="${GREEN}recommended${RESET}"
    fi
    case "${M_FIT[$i]:-unknown}" in
      vram)
        local t="${GREEN}✓ fits VRAM${RESET}"
        tag="${tag:+$tag · }$t"
        ;;
      unified)
        local t="${GREEN}✓ fits unified RAM${RESET}"
        tag="${tag:+$tag · }$t"
        ;;
      partial)
        local t="${YELLOW}⚠ partial GPU offload${RESET}"
        tag="${tag:+$tag · }$t"
        ;;
      cpu)
        local t="${DIM}CPU only${RESET}"
        tag="${tag:+$tag · }$t"
        ;;
      exceed)
        local t="${RED}✗ exceeds memory${RESET}"
        tag="${tag:+$tag · }$t"
        ;;
    esac
  fi

  local line
  printf -v line '%s %s %-22s %9s  %b' "$mark" "$box" "${M_NAME[$i]}" "$size" "$tag"
  if [ "$cur" = "1" ]; then
    printf -v "$3" '%s%s%s' "$BOLD" "$line" "$RESET"
  else
    printf -v "$3" '%s' "$line"
  fi
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
  adjust_view
  compute_totals

  # Single buffered atomic write to terminal eliminates lag and cursor flicker
  local BUF=""
  if [ "$RENDERED" -eq 1 ]; then
    BUF+=$'\033['"$FRAME"$'\x41'
  fi
  RENDERED=1

  BUF+=$'\r\033[2K'"${BOLD}Select Ollama models to download${RESET}"$'\n'
  BUF+=$'\r\033[2K'"${DIM}Host: RAM $(fmt_bytes "$RAM_BYTES") · GPU: $GPU_NAME${RESET}"$'\n'
  BUF+=$'\r\033[2K'"${DIM}↑/↓ move · space toggle · a tier · r recommended · n clear · enter confirm · q quit${RESET}"$'\n'

  local r i
  for ((r = TOP; r < TOP + VIEW_H; r++)); do
    if [ "$r" -ge "${#ROW_T[@]}" ]; then
      BUF+=$'\r\033[2K\n'
      continue
    fi
    i="${ROW_I[$r]}"
    if [ "${ROW_T[$r]}" = "H" ]; then
      BUF+=$'\r\033[2K'"${BOLD}-- ${TIER_NAMES[$i]}${RESET}${DIM} — ${TIER_DESC[$i]}${RESET}"$'\n'
    else
      local line=""
      format_item "$i" "$([ "$r" -eq "$CUR" ] && echo 1 || echo 0)" line
      BUF+=$'\r\033[2K'"$line"$'\n'
    fi
  done

  local colour="$GREEN" status
  if [ "$FREE_BYTES" -gt 0 ] && [ "$SEL_BYTES" -gt "$FREE_BYTES" ]; then colour="$RED"; fi
  status="Selected: $SEL_COUNT · download ≈ $(fmt_bytes "$SEL_BYTES")"
  if [ "$FREE_BYTES" -gt 0 ]; then status="$status · free disk: $(fmt_bytes "$FREE_BYTES")"; fi
  BUF+=$'\r\033[2K'"${colour}${status}${RESET}"$'\n'

  local w=""
  if [ "$SEL_UNK" -gt 0 ]; then w="$SEL_UNK selected model(s) have unknown size. "; fi
  if [ "$SEL_EXCEED" -gt 0 ]; then
    w="${w}${RED}✗ $SEL_EXCEED model(s) exceed available memory!${RESET} "
  elif [ "$SEL_PARTIAL" -gt 0 ]; then
    w="${w}${YELLOW}⚠ $SEL_PARTIAL model(s) exceed VRAM (partial GPU offload).${RESET} "
  fi
  BUF+=$'\r\033[2K'"$w"$'\n'

  BUF+=$'\r\033[2K'"${DIM}Sizes from registry.ollama.ai · ✓ fits VRAM · ⚠ partial offload · ✗ exceeds memory${RESET}"$'\n'

  printf '%b' "$BUF" >&2
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
      # Escape sequence reader with low latency and clean multi-byte escape handling
      if IFS= read -rsn1 -t 0.02 -u 3 rest 2>/dev/null; then
        if [ "$rest" = "[" ] || [ "$rest" = "O" ]; then
          local rest2=""
          if IFS= read -rsn1 -t 0.02 -u 3 rest2 2>/dev/null; then
            case "$rest$rest2" in
              '[A'|'OA') KEY="up" ;;
              '[B'|'OB') KEY="down" ;;
              '[C'|'OC') KEY="right" ;;
              '[D'|'OD') KEY="left" ;;
              '[H'|'1~'|'[1') KEY="home" ;;
              '[F'|'4~'|'[4') KEY="end" ;;
              '[5')
                IFS= read -rsn1 -t 0.02 -u 3 _ 2>/dev/null || true
                KEY="pageup"
                ;;
              '[6')
                IFS= read -rsn1 -t 0.02 -u 3 _ 2>/dev/null || true
                KEY="pagedown"
                ;;
            esac
          fi
        fi
      else
        KEY="quit"
      fi
      ;;
    k|K) KEY="up" ;;
    j|J) KEY="down" ;;
    a|A) KEY="tier" ;;
    r|R) KEY="rec" ;;
    n|N) KEY="none" ;;
    q|Q) KEY="quit" ;;
  esac
  return 0
}

move_cursor() { # delta (+1, -1, +N, -N)
  local delta=$1
  local step=1
  [ "$delta" -lt 0 ] && step=-1
  local count=$delta
  [ "$count" -lt 0 ] && count=$(( -count ))

  local r=$CUR
  while [ "$count" -gt 0 ]; do
    local next=$(( r + step ))
    if [ "$next" -lt 0 ] || [ "$next" -ge "${#ROW_T[@]}" ]; then break; fi
    r=$next
    if [ "${ROW_T[$r]}" = "M" ]; then
      count=$(( count - 1 ))
      CUR=$r
    fi
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
  local all_sel=1
  for i in "${!M_NAME[@]}"; do
    if [ "${M_TIER[$i]}" = "$t" ] && selectable "$i"; then
      if [ "${M_SEL[$i]}" != "1" ]; then all_sel=0; break; fi
    fi
  done
  local new_val=1
  [ "$all_sel" -eq 1 ] && new_val=0
  for i in "${!M_NAME[@]}"; do
    if [ "${M_TIER[$i]}" = "$t" ] && selectable "$i"; then M_SEL[$i]=$new_val; fi
  done
}

select_recommended() {
  local all_rec_sel=1 i
  for i in "${!M_NAME[@]}"; do
    if [ "${M_REC[$i]}" = "1" ] && selectable "$i"; then
      if [ "${M_SEL[$i]}" != "1" ]; then all_rec_sel=0; break; fi
    fi
  done
  local new_val=1
  [ "$all_rec_sel" -eq 1 ] && new_val=0
  for i in "${!M_NAME[@]}"; do
    if [ "${M_REC[$i]}" = "1" ] && selectable "$i"; then M_SEL[$i]=$new_val; fi
  done
}

clear_all() { local i; for i in "${!M_NAME[@]}"; do M_SEL[$i]=0; done; }

run_menu() {
  [ "$HAVE_TTY" -eq 1 ] || die "No terminal available for the selector. Use --models or --yes."
  case "${TERM:-dumb}" in dumb) die "TERM=dumb can't draw the selector. Use --models or --yes." ;; esac

  build_rows
  local lines="${LINES:-}"
  if ! is_num "$lines" || [ "$lines" -le 0 ]; then
    lines="$(tput lines 2>/dev/null || echo 24)"
  fi
  is_num "$lines" || lines=24
  VIEW_H=$((lines - 9)); [ "$VIEW_H" -lt 6 ] && VIEW_H=6
  [ "$VIEW_H" -gt "${#ROW_T[@]}" ] && VIEW_H=${#ROW_T[@]}
  FRAME=$((VIEW_H + 6))

  CUR=1; TOP=0     # row 0 is a header; row 1 is the first model
  printf '\033[?25l' >&2; CURSOR_HIDDEN=1

  while :; do
    render
    read_key
    case "$KEY" in
      up)       move_cursor -1 ;;
      down)     move_cursor 1 ;;
      pageup)   move_cursor -$(( VIEW_H - 2 )) ;;
      pagedown) move_cursor $(( VIEW_H - 2 )) ;;
      home)     CUR=1 ;;
      end)      CUR=$(( ${#ROW_T[@]} - 1 )); [ "${ROW_T[$CUR]}" = "H" ] && move_cursor -1 ;;
      toggle)   toggle_current ;;
      tier)     select_current_tier ;;
      rec)      select_recommended ;;
      none)     clear_all ;;
      enter)    break ;;
      quit)     printf '\033[?25h' >&2; CURSOR_HIDDEN=0; printf '\n' >&2; info "Aborted. Nothing was downloaded."; exit 0 ;;
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

  printf '\n%sHardware Profile:%s\n' "$BOLD" "$RESET" >&2
  printf '  - RAM: %s total' "$(fmt_bytes "$RAM_BYTES")" >&2
  if [ "$RAM_AVAIL_BYTES" -gt 0 ]; then
    printf ' (%s available)\n' "$(fmt_bytes "$RAM_AVAIL_BYTES")" >&2
  else
    printf '\n' >&2
  fi
  printf '  - GPU: %s\n' "$GPU_NAME" >&2
  if [ "$VRAM_BYTES" -gt 0 ] && [ "$IS_UNIFIED_MEM" -eq 0 ]; then
    printf '  - VRAM: %s dedicated\n' "$(fmt_bytes "$VRAM_BYTES")" >&2
  fi

  printf '\n%sAbout to download:%s\n' "$BOLD" "$RESET" >&2
  for i in "${!M_NAME[@]}"; do
    if [ "${M_SEL[$i]}" = "1" ]; then
      local s="size unknown" fit_str=""
      if is_num "${M_SIZE[$i]}"; then
        s="$(fmt_bytes "${M_SIZE[$i]}")"
        case "${M_FIT[$i]:-unknown}" in
          vram)    fit_str="${GREEN}Full GPU (VRAM)${RESET}" ;;
          unified) fit_str="${GREEN}Unified GPU (Metal)${RESET}" ;;
          partial) fit_str="${YELLOW}Partial GPU offload (GPU+RAM)${RESET}" ;;
          cpu)     fit_str="${DIM}CPU only${RESET}" ;;
          exceed)  fit_str="${RED}Warning: Exceeds available memory!${RESET}" ;;
        esac
      fi
      printf '  - %-22s %9s   %b\n' "${M_NAME[$i]}" "$s" "$fit_str" >&2
    fi
  done
  printf '  %s\n' "----------------------------------------------------" >&2
  printf '  %-22s %9s\n' "Total" "$(fmt_bytes "$SEL_BYTES")" >&2

  local dir need
  dir="$(models_dir)"
  FREE_BYTES="$(free_bytes "$dir")"; is_num "$FREE_BYTES" || FREE_BYTES=0
  printf '\n' >&2
  info "Models are stored in: $dir"
  if [ "$FREE_BYTES" -gt 0 ]; then info "Free disk space there: $(fmt_bytes "$FREE_BYTES")"; fi

  if [ "$SEL_UNK" -gt 0 ]; then
    warn "$SEL_UNK model(s) have unknown size (registry unreachable?); the total is understated."
  fi
  if [ "$SEL_EXCEED" -gt 0 ]; then
    warn "$SEL_EXCEED selected model(s) exceed available memory limit. They may fail to load or cause severe memory thrashing."
  fi
  if [ "$SEL_PARTIAL" -gt 0 ]; then
    info "$SEL_PARTIAL selected model(s) exceed VRAM and will use partial GPU offload (splitting layers with system RAM)."
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
