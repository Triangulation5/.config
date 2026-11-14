#!/usr/bin/env bash
#
# Regression tests for the Gentoo installer flow. No root access or Portage
# installation is needed; privileged commands and overlay state are mocked.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# shellcheck source=gentoo.sh
. "$here/gentoo.sh"

ST_OK=0
ST_FAIL=1
DRY_RUN=0
OUTSIDE_TXN_CHANGES=0
GENTOO_PORTAGE_DIR="$tmp/etc/portage"
TEMP_PATHS=()
temp_register() { TEMP_PATHS+=("$1"); }
gentoo_root() { "$@"; }
gentoo_check_privilege() { return 0; }
gentoo_repo_enabled() { return 0; }
note() { :; }
err() { printf '%s\n' "$*" >&2; }
priv_progress() {
    shift
    printf '%s\n' "$*" >> "$tmp/sync.calls"
}

mkdir -p "$GENTOO_PORTAGE_DIR/package.accept_keywords"
printf '# user entry\ncat/pkg ~amd64' > "$GENTOO_PORTAGE_DIR/package.accept_keywords/silhouette"
export TMPDIR="$tmp"

gentoo_enable_repos
grep -qx 'emaint sync -r hyproverlay' "$tmp/sync.calls"
grep -qx 'emaint sync -r guru' "$tmp/sync.calls"

grep -qx '# user entry' "$GENTOO_PORTAGE_DIR/package.accept_keywords/silhouette"
grep -qx 'cat/pkg ~amd64' "$GENTOO_PORTAGE_DIR/package.accept_keywords/silhouette"
grep -qxF '*/*::hyproverlay' "$GENTOO_PORTAGE_DIR/package.accept_keywords/silhouette"
grep -qxF '*/*::guru' "$GENTOO_PORTAGE_DIR/package.accept_keywords/silhouette"
cp "$GENTOO_PORTAGE_DIR/package.accept_keywords/silhouette" "$tmp/expected"
gentoo_accept_overlay_keywords
cmp -s "$tmp/expected" "$GENTOO_PORTAGE_DIR/package.accept_keywords/silhouette"

printf '%s\n' ok
