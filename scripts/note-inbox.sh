
#!/usr/bin/env bash

NOTES_DIR="$HOME/Documents/notes/inbox"

# Create the directory if it doesn't exist
mkdir -p "$NOTES_DIR"

# Generate today's filename
DATE="$(date +%Y-%m-%d)"
NOTE="$NOTES_DIR/$DATE.md"

# Create the note if it doesn't exist
touch "$NOTE"

# Open Neovim in a floating Kitty window
kitty --class note-inbox \
    --override initial_window_width=87c \
    --override initial_window_height=26c \
    nvim "$NOTE" &

# Wait until the window appears
for i in {1..50}; do
    WINDOW=$(hyprctl clients -j | jq -r '.[] | select(.class == "note-inbox") | .address' | tail -n 1)

    if [[ -n "$WINDOW" ]]; then
        break
    fi

    sleep 0.1
done

# Random position on the current monitor
if [[ -n "$WINDOW" ]]; then
    MONITOR=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name' | head -n 1)

    read -r WIDTH HEIGHT <<< "$(hyprctl monitors -j | jq -r --arg monitor "$MONITOR" '.[] | select(.name == $monitor) | "\(.width) \(.height)"')"

    # Keep the window within monitor boundaries
    X_MAX=$((WIDTH - 696))
    Y_MAX=$((HEIGHT - 416))

    (( X_MAX < 0 )) && X_MAX=0
    (( Y_MAX < 0 )) && Y_MAX=0

    X=$((RANDOM % (X_MAX + 1)))
    Y=$((RANDOM % (Y_MAX + 1)))

    # Move the window to its random position
    hyprctl dispatch movewindowpixel "exact $X $Y,address:$WINDOW"
fi
