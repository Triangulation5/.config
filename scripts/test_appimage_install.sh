#!/usr/bin/env bash
#
# A metadata-only AppImage operation must report success when it has no temp
# extraction directory to clean up.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

export XDG_DATA_HOME="$tmp/data"
mkdir -p "$XDG_DATA_HOME/applications" "$XDG_DATA_HOME/silhouette"
desktop="$XDG_DATA_HOME/applications/silhouette-test.desktop"
printf 'Name=Old name\n' > "$desktop"
printf '%s\n' \
    '{"test":{"name":"Old name","appimagePath":"","iconPath":"","desktopPath":"'"$desktop"'","appId":"test"}}' \
    > "$XDG_DATA_HOME/silhouette/appimages.json"

"$here/appimage-install.sh" rename test "New name"
grep -qx 'Name=New name' "$desktop"
[[ "$(jq -r '.test.name' "$XDG_DATA_HOME/silhouette/appimages.json")" == "New name" ]]

printf '%s\n' ok
