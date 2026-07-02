#!/bin/bash

player=$(playerctl -l 2>/dev/null | head -n 1)
[[ -z "$player" ]] && exit 0

status=$(playerctl -p "$player" status 2>/dev/null)
[[ "$status" != "Playing" && "$status" != "Paused" ]] && exit 0

title=$(playerctl -p "$player" metadata title 2>/dev/null)
artist=$(playerctl -p "$player" metadata artist 2>/dev/null)

if [[ -z "$artist" || "$artist" == "$title" ]]; then
    artist=$(playerctl -p "$player" metadata xesam:album 2>/dev/null)
fi

[[ -z "$title" ]] && title="Unknown"
[[ -z "$artist" ]] && artist="${player##*.}"

icon=""
case "$player" in
    *spotify*) icon="" ;;
    *firefox*) icon="" ;;
    *chrome*|*chromium*) icon="" ;;
    *brave*) icon="" ;;
    *vlc*) icon="󰕼" ;;
esac

max_title=35
max_artist=25

trim() {
    local s="$1"
    local m="$2"
    [[ ${#s} -gt $m ]] && echo "${s:0:$m}…" || echo "$s"
}

title=$(trim "$title" "$max_title")
artist=$(trim "$artist" "$max_artist")

[[ -z "$title" && -z "$artist" ]] && exit 0

printf "%-40s\n" "${title}  ${icon}  ${artist}"
