#!/usr/bin/env bash
#
# Launch wrapper for the pill launcher. Runs the app, keeps the first 64K of
# its stderr and, when it dies non-zero inside the first seconds, raises a
# critical toast with a Copy action that puts exit code plus full stderr on the
# clipboard. Later exits are the user closing the app and stay silent.
#
# stderr is drained for the whole app lifetime: a reader that quits after the
# cap would hand the app SIGPIPE on its next log line, a plain file would grow
# for hours under chatty apps. So this script lives as long as the app does.
#
# Usage: launch-guard.sh <name> <icon> <workdir> <cmd> [args...]
scripts_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
if [ "$#" -ge 4 ] && [ -r "$scripts_dir/lib/lib-rust.sh" ]; then
	# shellcheck source=lib/lib-rust.sh
	source "$scripts_dir/lib/lib-rust.sh"
	rust_bin="$scripts_dir/bin/silhouette-tools"
	if rust_tools_usable && [ -x "$rust_bin" ] && "$rust_bin" launch-guard --help >/dev/null 2>&1; then
		exec "$rust_bin" launch-guard "$@"
	fi
fi

name="$1" icon="$2" wd="$3"
shift 3
window=5
cap=65536
tmp="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/launch-guard.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
[ -n "$wd" ] && cd "$wd" 2>/dev/null || :

cmd="${1:-}"
if [ -n "$cmd" ] && [ ! -f "$cmd" ]; then
	case "$cmd" in
		*.[Aa]pp[Ii]mage)
			healed="$(bash "$scripts_dir/appimage-install.sh" heal "$cmd" 2>/dev/null || true)"
			if [ -n "$healed" ] && [ -f "$healed" ]; then
				shift
				set -- "$healed" "$@"
			fi
			;;
	esac
fi

SECONDS=0
"$@" 2>&1 >/dev/null | { head -c "$cap" >"$tmp"; cat >/dev/null; }
rc=${PIPESTATUS[0]}
[ "$rc" -ne 0 ] && [ "$SECONDS" -lt "$window" ] || exit 0
err="$(cat "$tmp")"
[ -n "$err" ] || err="(no output)"
tail3="$(printf '%s\n' "$err" | grep -v '^[[:space:]]*$' | tail -n 3)"
picked="$(notify-send -u critical -a SilhouetteShell ${icon:+-i "$icon"} -A copy=Copy \
	"$name failed (exit $rc)" "$tail3")"
[ "$picked" = "copy" ] && printf '%s: exit %s\n%s\n' "$name" "$rc" "$err" | wl-copy
