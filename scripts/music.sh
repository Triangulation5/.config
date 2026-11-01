#!/bin/bash

scripts_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
"$scripts_dir/user-service.sh" restart mpd

mpc update

pkill ncmpcpp

kitty -e ncmpcpp &
