#!/bin/bash

scripts_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
"$scripts_dir/user-service.sh" stop mpd

# kill client UI
pkill -9 ncmpcpp 2>/dev/null

# ensure port is free
fuser -k 6600/tcp 2>/dev/null
