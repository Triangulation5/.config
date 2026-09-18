#!/bin/bash

pkill qs

bash ~/.config/hypr/scripts/launch.sh & disown

# Old monolithic pill
# qs -p ~/.config/quickshell/monolithic-shell/pill/shell.qml & disown
# qs -p ~/.config/quickshell/monolithic-shell/lock/ & disown
# qs -p ~/.config/quickshell/monolithic-shell/screencorner/ & disown
