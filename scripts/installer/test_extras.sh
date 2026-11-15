#!/usr/bin/env bash
#
# A failed fetch of the pinned GRUB theme release must not fall back to running
# whatever revision happens to be in an existing checkout as root.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

. "$here/stages/extras.sh"

EVA_DIR="$tmp/Evangelion"
EVA_REF=v2.1.0
EVA_REPO_URL=https://example.invalid/Evangelion.git
mkdir -p "$EVA_DIR/.git"

note() { :; }
warn() { :; }
err() { :; }
progress_run() { return 1; }

if eva_fetch_repo; then
    echo "failed pinned-tag fetch unexpectedly accepted the existing checkout" >&2
    exit 1
fi

# Test st build dependencies for Fedora and Gentoo
PM=dnf
fedora_deps="$(st_build_deps)"
for dep in gcc make libX11-devel libXft-devel fontconfig-devel harfbuzz-devel; do
    case " $fedora_deps " in
        *" $dep "*) ;;
        *) echo "st_build_deps missing $dep for Fedora" >&2; exit 1 ;;
    esac
done

PM=emerge
gentoo_deps="$(st_build_deps)"
for atom in sys-devel/gcc dev-build/make x11-libs/libX11 x11-libs/libXft media-libs/fontconfig media-libs/harfbuzz; do
    case " $gentoo_deps " in
        *" $atom "*) ;;
        *) echo "st_build_deps missing $atom for Gentoo" >&2; exit 1 ;;
    esac
done

printf '%s\n' ok
