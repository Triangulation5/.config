#!/bin/bash

pkill waybar
pkill swaync
pkill qs

# /usr/bin/waybar & disown
bash ~/.config/quickshell/reload.sh & disown
/usr/bin/swaync & disown
