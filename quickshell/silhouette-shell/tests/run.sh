#!/bin/sh
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

echo "=== 1. Rust unit tests (sysmon + watchers) ==="
cargo test --manifest-path "$ROOT/utils/sysmon/Cargo.toml"
cargo test --manifest-path "$ROOT/utils/watchers/Cargo.toml"

echo "=== 2. Tool integration tests ==="
python3 "$DIR/test_tools.py"

echo "=== 3. JS utility unit tests ==="
node "$ROOT/utils/keybinds/binds.test.js"
node "$DIR/test_js_utils.js"

echo "=== 4. Shell static & contract integrity tests ==="
python3 "$DIR/test_shell_integrity.py"

echo "=== ALL TESTS PASSED ==="
