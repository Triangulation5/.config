#!/bin/bash

URL="$1"

if [ -z "$URL" ]; then
  echo "Usage: $0 <youtube-url>"
  exit 1
fi

yt-dlp \
--js-runtimes node \
-f bestaudio \
-x \
--add-metadata --embed-thumbnail \
-o "$HOME/Music/youtube/%(upload_date)s - %(title).100s.%(ext)s" \
"$URL"

mpc update
