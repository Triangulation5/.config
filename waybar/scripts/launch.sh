#!/bin/bash

pkill waybar
pkill swaync

# /usr/bin/waybar & disown
/usr/bin/swaync & disown
