#!/bin/sh
# Parallel, zero-dependency test runner for silhouette-shell.
#
# Usage:
#   ./tests/run.sh                    # run all suites in parallel
#   ./tests/run.sh --no-clippy        # skip cargo clippy lints
#   ./tests/run.sh rust js qml        # run only selected suites
#
# Suites: rust, clippy, tools, scripts, python, js, qml
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
CONFIG_ROOT="$(cd "$ROOT/../.." && pwd)"
CARGO_BIN="${CARGO_HOME:-${HOME:-}/.cargo}/bin"
if [ -d "$CARGO_BIN" ]; then
    case ":${PATH:-}:" in
        *":$CARGO_BIN:"*) ;;
        *) PATH="$CARGO_BIN${PATH:+:$PATH}"; export PATH ;;
    esac
fi
TMPDIR_RUN="$(mktemp -d "${TMPDIR:-/tmp}/silhouette-tests.XXXXXX")"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

SKIP_CLIPPY=0
SELECTED=""
for arg in "$@"; do
    case "$arg" in
        --no-clippy|--fast) SKIP_CLIPPY=1 ;;
        -h|--help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) SELECTED="$SELECTED $arg" ;;
    esac
done

want() {
    if [ -z "$SELECTED" ]; then
        if [ "$1" = "clippy" ] && [ "$SKIP_CLIPPY" = "1" ]; then
            return 1
        fi
        return 0
    fi
    case " $SELECTED " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

now_ms() {
    python3 -c 'import time; print(int(time.monotonic() * 1000))'
}

PIDS=""
NAMES=""

launch() {
    name="$1"
    shift
    log="$TMPDIR_RUN/$name.log"
    rc_file="$TMPDIR_RUN/$name.rc"
    ms_file="$TMPDIR_RUN/$name.ms"
    (
        t0="$(now_ms)"
        rc=0
        "$@" >"$log" 2>&1 || rc=$?
        t1="$(now_ms)"
        printf '%s\n' "$rc" >"$rc_file"
        printf '%s\n' "$((t1 - t0))" >"$ms_file"
    ) &
    PIDS="$PIDS $!"
    NAMES="$NAMES $name"
}

run_rust_tests() {
    cargo test --manifest-path "$ROOT/utils/sysmon/Cargo.toml" &&
    cargo test --manifest-path "$ROOT/utils/watchers/Cargo.toml" &&
    cargo test --manifest-path "$CONFIG_ROOT/scripts/rust-tools/Cargo.toml"
}

run_clippy() {
    cargo clippy --release --all-targets --manifest-path "$ROOT/utils/sysmon/Cargo.toml" -- -D warnings &&
    cargo clippy --release --all-targets --manifest-path "$ROOT/utils/watchers/Cargo.toml" -- -D warnings &&
    cargo clippy --release --all-targets --manifest-path "$CONFIG_ROOT/scripts/rust-tools/Cargo.toml" -- -D warnings
}

run_js_tests() {
    node "$ROOT/utils/keybinds/binds.test.js" &&
    node "$DIR/test_js_utils.js"
}

T_START="$(now_ms)"

want rust    && launch rust    run_rust_tests
want clippy  && launch clippy  run_clippy
want tools   && launch tools   python3 "$DIR/test_tools.py"
want scripts && launch scripts python3 "$DIR/test_scripts.py"
want python  && launch python  python3 "$DIR/test_python.py"
want js      && launch js      run_js_tests
want qml     && launch qml     python3 "$DIR/test_shell_integrity.py"

for pid in $PIDS; do
    wait "$pid" || true
done

T_TOTAL="$(( $(now_ms) - T_START ))"
FAILED=0

printf "\n=== silhouette-shell test summary ===\n"
for name in $NAMES; do
    rc="$(cat "$TMPDIR_RUN/$name.rc")"
    ms="$(cat "$TMPDIR_RUN/$name.ms")"
    if [ "$rc" = "0" ]; then
        printf "  [PASS] %-8s (%sms)\n" "$name" "$ms"
    else
        printf "  [FAIL] %-8s (%sms, exit %s)\n" "$name" "$ms" "$rc"
        FAILED=1
    fi
done
printf "Total wall time: %sms\n" "$T_TOTAL"

if [ "$FAILED" != "0" ]; then
    for name in $NAMES; do
        rc="$(cat "$TMPDIR_RUN/$name.rc")"
        if [ "$rc" != "0" ]; then
            printf "\n--- Failure output: %s ---\n" "$name"
            cat "$TMPDIR_RUN/$name.log"
        fi
    done
    exit 1
fi

printf "=== ALL TESTS PASSED ===\n"
