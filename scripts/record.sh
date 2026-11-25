#!/bin/sh

scripts_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -r "$scripts_dir/lib/lib-rust.sh" ]; then
	# shellcheck source=lib/lib-rust.sh
	. "$scripts_dir/lib/lib-rust.sh"
	rust_bin="$scripts_dir/bin/silhouette-tools"
	if rust_tools_usable && [ -x "$rust_bin" ] && "$rust_bin" quick-record --help >/dev/null 2>&1; then
		exec "$rust_bin" quick-record
	fi
fi

mon=$(hyprctl activeworkspace -j | jq -r '.monitor')
qs -c silhouette-shell ipc call pill quickRecord "$mon"
