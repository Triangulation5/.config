#!/bin/sh
#
# Move the shell's state from the old `ricelin` names to the `silhouette` ones.
#
# This exists because the rename is otherwise a silent amnesia: the shell reads
# flags.json, the calendar's events, the chosen wallpaper and the launcher's
# usage counts by path, and a fresh path means default settings and an empty
# calendar. So the first run after the rename carries the old tree over.
#
# Idempotent by construction: a pair is only moved when the old path exists and
# the new one does not. Run it every session (launch.sh does) and it does
# nothing after the first. If both exist it says so and touches neither, since
# the only safe assumption is that the new one is in use.
#
# What it deliberately does not do:
#   - desktop entries. AppImages installed before the rename are
#     `ricelin-<slug>.desktop`; the launcher detects both prefixes, so there is
#     nothing to rewrite and a stale entry still works. Reinstalling one of
#     those apps writes the new name and drops the old file on its own.
#   - runtime files (the lock trigger and its grabs). They are per-session and
#     recreated by the next lock.
#
# It does reword recorded absolute paths, in the AppImage registry, the desktop
# entries and the wallpaper state, because a path written before the rename
# still names a directory that has moved.
#
# Env: XDG_STATE_HOME, XDG_CACHE_HOME, XDG_DATA_HOME, or their defaults.
set -u

state="${XDG_STATE_HOME:-$HOME/.local/state}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"

move_one() {
    old="$1"
    new="$2"

    [ -e "$old" ] || return 0
    if [ -e "$new" ]; then
        printf 'migrate-state: %s and %s both exist, left the old one alone\n' "$old" "$new" >&2
        return 0
    fi

    mkdir -p "$(dirname "$new")" || return 0
    if mv "$old" "$new" 2>/dev/null; then
        printf 'migrate-state: moved %s to %s\n' "$old" "$new"
    else
        printf 'migrate-state: could not move %s, continuing without it\n' "$old" >&2
    fi
}

# The state directory itself (flags, events, launcher usage, updates, backups,
# the game-mode snapshot), then the files that sit beside it.
move_one "$state/ricelin"              "$state/silhouette"
move_one "$state/ricelin-wallpaper"     "$state/silhouette-wallpaper"
move_one "$state/ricelin-wallpaper-dir" "$state/silhouette-wallpaper-dir"
move_one "$state/ricelin-wallpaper-bag" "$state/silhouette-wallpaper-bag"
move_one "$state/ricelin-wallpaper-bag.lock" "$state/silhouette-wallpaper-bag.lock"

# Caches: the dynamic palette, wallpaper thumbnails, recording thumbnails. All
# of it is rebuilt on demand, so a failed move costs a regeneration, not data.
move_one "$cache/ricelin"          "$cache/silhouette"
move_one "$cache/ricelin-wp-thumbs" "$cache/silhouette-wp-thumbs"

# Reword one old path to its new spelling inside a file, in place, and stay
# quiet when there is nothing to reword. The pattern is escaped so a home
# directory carrying a sed metacharacter (`.` in a dotted username) is matched
# literally instead of as a wildcard.
reword_file() {
    old="$1"
    new="$2"
    file="$3"

    [ -f "$file" ] || return 0
    grep -qF "$old" "$file" 2>/dev/null || return 0

    pattern="$(printf '%s' "$old" | sed 's/[][\\^$.*&|]/\\&/g')"
    repl="$(printf '%s' "$new" | sed 's/[&|\\]/\\&/g')"
    sed -i "s|$pattern|$repl|g" "$file" &&
        printf 'migrate-state: reworded %s in %s\n' "$old" "$file"
}

# Absolute paths written down before the rename point into the old data
# directory, so they are reworded in place: the registry holds each icon's full
# path, and the desktop entries the drop-installer writes repeat it in Icon=.
# Runs against the new directory whether or not this run did the moving, and is
# silent once there is nothing left to reword.
reword_paths() {
    old="$1"
    new="$2"

    reword_file "$old" "$new" "$new/appimages.json"

    applications="$data/applications"
    [ -d "$applications" ] || return 0
    for entry in "$applications"/*.desktop; do
        reword_file "$old" "$new" "$entry"
    done
}

# Data: the AppImage registry and the icons extracted beside it.
move_one "$data/ricelin"           "$data/silhouette"
reword_paths "$data/ricelin" "$data/silhouette"

# The wallpaper collection the drop-a-wallpaper flow creates in the home
# directory. Only that subdirectory moves - ~/Ricelin may also be a checkout of
# the upstream project, and that is not ours to relocate. The paths recorded
# before the rename point into it, so they are reworded too: the folder the
# settings app stores, the chosen wallpaper, the directory wallpapers.sh
# resolved and the shuffle bag. Without this the strip comes up empty and the
# next dropped wallpaper starts a second collection beside the old one.
home_old="$HOME/Ricelin/wallpapers"
home_new="$HOME/Silhouette/wallpapers"
move_one "$home_old" "$home_new"
reword_file "$home_old" "$home_new" "$state/silhouette/flags.json"
reword_file "$home_old" "$home_new" "$state/silhouette-wallpaper"
reword_file "$home_old" "$home_new" "$state/silhouette-wallpaper-dir"
reword_file "$home_old" "$home_new" "$state/silhouette-wallpaper-bag"

# The parent existed to hold that collection, so drop it when the move left it
# empty. rmdir refuses a non-empty directory, which is the case that matters:
# ~/Ricelin may also be an upstream checkout, and that stays put.
if [ -d "$home_new" ]; then
    rmdir "$HOME/Ricelin" 2>/dev/null || true
fi

exit 0
