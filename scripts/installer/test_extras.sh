#!/usr/bin/env bash
#
# A failed fetch of the pinned GRUB theme release must not fall back to running
# whatever revision happens to be in an existing checkout as root.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

. "$here/stages/extras.sh"

EVA_DIR="$tmp/Evangelion"
EVA_REF=v2.1.0
EVA_REPO_URL=https://example.invalid/Evangelion.git
mkdir -p "$EVA_DIR/.git"

note() { :; }
warn() { :; }
err() { :; }
progress_run() { return 1; }

if eva_fetch_repo; then
    echo "failed pinned-tag fetch unexpectedly accepted the existing checkout" >&2
    exit 1
fi

printf '%s\n' ok
