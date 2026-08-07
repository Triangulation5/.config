#!/bin/sh

mon=$(hyprctl activeworkspace -j | jq -r '.monitor')
qs -c silhouette-shell ipc call pill "$1" "$mon"

# Old monolithic pill
# qs -p ~/.config/quickshell/monolithic-shell/pill ipc call pill "$1" "$mon"
