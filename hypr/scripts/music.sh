#!/bin/bash

systemctl --user restart mpd 2>/dev/null || (pkill mpd && mpd ~/.config/mpd/mpd.conf)

mpc update

pkill ncmpcpp

kitty -e ncmpcpp &
