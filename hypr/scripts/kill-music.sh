#!/bin/bash

# stop systemd service first (prevents respawn)
systemctl --user stop mpd 2>/dev/null
systemctl --user disable mpd 2>/dev/null

# kill any remaining mpd processes
pkill -9 mpd 2>/dev/null

# kill client UI
pkill -9 ncmpcpp 2>/dev/null

# ensure port is free
fuser -k 6600/tcp 2>/dev/null
