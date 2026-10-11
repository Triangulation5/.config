#!/usr/bin/env bash

set -Eeuo pipefail

MUSIC_DIR="$HOME/Music/youtube"

[[ $# -eq 1 && -n $1 ]] || { echo "Usage: ${0##*/} <youtube-url>" >&2; exit 1; }
command -v yt-dlp >/dev/null || { echo "yt-dlp not installed" >&2; exit 1; }

yt-dlp \
    --js-runtimes node \
    --no-playlist \
    -f bestaudio \
    -x \
    --embed-metadata \
    --embed-thumbnail --convert-thumbnails jpg \
    -o "$MUSIC_DIR/%(upload_date)s - %(title).100s.%(ext)s" \
    "$1"

mpc update --wait
