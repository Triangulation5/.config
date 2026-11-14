#!/usr/bin/env bash
set -o pipefail

NOTES_DIR="$HOME/Documents/notes/inbox"
CLASS="note-inbox"
MARGIN=40          # Minimum distance from usable monitor edges
CANDIDATES=40      # Random positions to try; the least-overlapping one wins

for cmd in hyprctl jq kitty nvim; do
    command -v "$cmd" >/dev/null || { echo "missing dependency: $cmd" >&2; exit 1; }
done

# Run `hyprctl <query> -j` and print only valid JSON. Warnings or other noise
# that hyprctl prints before the JSON are dropped; if no valid JSON comes back,
# the raw output is shown on stderr so the real problem is visible.
hypr() {
    local raw json
    raw="$(hyprctl "$1" -j 2>&1)"
    json="$(sed -n '/^[[{]/,$p' <<< "$raw")"
    if jq -e . >/dev/null 2>&1 <<< "$json"; then
        printf '%s\n' "$json"
    else
        echo "note-inbox: 'hyprctl $1 -j' did not return JSON. Output was:" >&2
        printf '%s\n' "$raw" | head -n 5 >&2
        return 1
    fi
}

usage() {
    cat <<EOF
Usage: ${0##*/} [-t | --timestamp]

  (no args)        open today's note (e.g. 2026-11-01.md), creating it if needed
  -t, --timestamp  create a new note stamped with the time (e.g. 2026-11-01 4-29 PM.md)
EOF
}

STAMPED=0
case "${1:-}" in
    "")              ;;
    -t|--timestamp)  STAMPED=1 ;;
    -h|--help)       usage; exit 0 ;;
    *)               usage >&2; exit 1 ;;
esac

mkdir -p "$NOTES_DIR"

if (( STAMPED )); then
    # Colons aren't allowed in Obsidian filenames, so the file uses "4-29 PM"
    # while the front matter keeps the readable "4:29 PM".
    STAMP_FILE="$(date '+%Y-%m-%d %-I-%M %p')"
    STAMP_TEXT="$(date '+%Y-%m-%d %-I:%M %p')"
    NOTE="$NOTES_DIR/$STAMP_FILE.md"
    CREATED="$STAMP_TEXT"
else
    DATE="$(date +%Y-%m-%d)"
    NOTE="$NOTES_DIR/$DATE.md"
    CREATED="$(date '+%Y-%m-%d %-I:%M %p')"
fi

# Create the note with front matter if it doesn't exist (or is empty).
# The title is intentionally blank, with a trailing space for immediate typing.
# The body starts with "* " for a new list entry.
if [[ ! -s "$NOTE" ]]; then
    cat > "$NOTE" <<EOF
---
title: 
tags: [inbox]
created: $CREATED
---

EOF
fi

# Snapshot existing note-inbox windows so we can identify the new one later
BEFORE="$(hypr clients | jq -c --arg c "$CLASS" '[.[] | select(.class == $c) | .address]')" || exit 1

# Open Neovim in a floating Kitty window.
# +2 moves the cursor to the blank title line, immediately after "title: ".
kitty --class "$CLASS" \
    --override initial_window_width=87c \
    --override initial_window_height=26c \
    nvim +2 +startinsert! "$NOTE" &

# Wait for the NEW window (one whose address wasn't in the snapshot)
WINDOW=""
for _ in {1..50}; do
    WINDOW="$(hypr clients | jq -r --arg c "$CLASS" --argjson before "$BEFORE" '
        [.[] | select(.class == $c and (.address as $a | $before | index($a) | not))][0].address // empty')"
    [[ -n "$WINDOW" ]] && break
    sleep 0.1
done

[[ -z "$WINDOW" ]] && exit 0

# Wait until Hyprland has applied window rules: size is non-zero and stable
PREV=""
WIN_W=0
WIN_H=0
for _ in {1..30}; do
    CUR="$(hypr clients | jq -r --arg a "$WINDOW" '.[] | select(.address == $a) | "\(.size[0]) \(.size[1])"')"
    if [[ -n "$CUR" && "$CUR" == "$PREV" && "$CUR" != "0 0" ]]; then
        read -r WIN_W WIN_H <<< "$CUR"
        break
    fi
    PREV="$CUR"
    sleep 0.05
done
(( WIN_W > 0 && WIN_H > 0 )) || exit 0

# The monitor the window actually landed on, as logical (scaled/rotated) layout
# coordinates, minus reserved areas (bars, docks): "x y width height workspace_id"
MON_ID="$(hypr clients | jq --arg a "$WINDOW" '.[] | select(.address == $a) | .monitor')"
[[ -n "$MON_ID" ]] || exit 0

read -r MON_X MON_Y MON_W MON_H WS_ID <<< "$(
    hypr monitors | jq -r --argjson id "$MON_ID" '
        .[] | select(.id == $id)
        | (if (.transform % 2) == 1 then [.height, .width] else [.width, .height] end) as $dim
        | ($dim[0] / .scale) as $w
        | ($dim[1] / .scale) as $h
        | .reserved as $r
        | "\(.x + $r[0] | floor) \(.y + $r[1] | floor) \($w - $r[0] - $r[2] | floor) \($h - $r[1] - $r[3] | floor) \(.activeWorkspace.id)"
    '
)"
[[ -n "$MON_X" ]] || exit 0

# Other visible windows on the same workspace (including other note-inbox ones),
# as [[x, y, w, h], ...]
OTHERS="$(hypr clients | jq -c --arg a "$WINDOW" --argjson ws "$WS_ID" '
    [.[] | select(.address != $a and .mapped and (.hidden | not) and .workspace.id == $ws)
         | [.at[0], .at[1], .size[0], .size[1]]]')"

# Usable range for the window's top-left corner
X_MIN=$((MON_X + MARGIN))
Y_MIN=$((MON_Y + MARGIN))
X_RANGE=$((MON_W - WIN_W - MARGIN * 2))
Y_RANGE=$((MON_H - WIN_H - MARGIN * 2))
(( X_RANGE < 0 )) && X_RANGE=0
(( Y_RANGE < 0 )) && Y_RANGE=0

# Generate random candidate positions
CANDS="["
for ((i = 0; i < CANDIDATES; i++)); do
    CANDS+="[$((X_MIN + RANDOM % (X_RANGE + 1))),$((Y_MIN + RANDOM % (Y_RANGE + 1)))],"
done
CANDS="${CANDS%,}]"

# Pick the candidate that overlaps existing windows the least
read -r X Y <<< "$(jq -nr \
    --argjson cands "$CANDS" --argjson others "$OTHERS" \
    --argjson w "$WIN_W" --argjson h "$WIN_H" '
    [ $cands[] as $c
      | { x: $c[0], y: $c[1],
          score: ([ $others[]
                    | (([$c[0] + $w, .[0] + .[2]] | min) - ([$c[0], .[0]] | max)) as $dx
                    | (([$c[1] + $h, .[1] + .[3]] | min) - ([$c[1], .[1]] | max)) as $dy
                    | if $dx > 0 and $dy > 0 then $dx * $dy else 0 end
                  ] | add // 0) } ]
    | min_by(.score) | "\(.x) \(.y)"')"

# Move the window using the Lua dispatcher
hyprctl dispatch "hl.dsp.window.move({ x = $X, y = $Y, window = 'address:$WINDOW' })"
