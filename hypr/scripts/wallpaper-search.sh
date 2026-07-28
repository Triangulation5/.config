#!/usr/bin/env bash

# vim: foldmethod=marker foldlevelstart=0

UA="Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/126.0"

GITHUB_REPO="Triangulation5/wallpapers"
GITHUB_BRANCH="main"

# {{{ DO NOT OPEN: Borderline Safety Filter
BLOCKED_TERMS=("semen")
# BLOCKED_TERMS=("nsfw" "n.s.f.w" "n_s_f_w" "n-s-f-w" "not safe for work" "not-safe-for-work" "nude" "nudity" "naked" "nakd" "nak" "undressed" "undress" "topless" "bottomless" "bare" "baring" "exposed" "exposure" "porn" "porno" "pornography" "pornographic" "pornstar" "xxx" "xx" "x-rated" "xrated" "adultvideo" "adultvideos" "sex" "sexual" "sexually" "sexy" "sexgirl" "sexygirl" "sexwoman" "sexmodel" "intercourse" "hookup" "hentai" "hentAI" "h3ntai" "ecchi" "ero" "erotic" "erotica" "eroanime" "adultanime" "18+" "18plus" "18-plus" "18plusonly" "18years" "adultonly" "maturecontent" "adult" "adultcontent" "adult-content" "explicit" "explicitcontent" "explicit-content" "rule34" "rule-34" "rule_34" "r34" "rulethreefour" "booru" "danbooru" "gelbooru" "konachan" "yandere" "safebooru" "zerochan" "e621" "e926" "furry" "furries" "futanari" "futa" "futa-anime" "yaoi" "yuri" "shota" "shotacon" "loli" "lolicon" "lolicorn" "doujin" "doujinshi" "manga18" "adultmanga" "lewd" "lewds" "lewdness" "suggestive" "provocative" "risque" "risqué" "fetish" "bdsm" "bondage" "dominatrix" "dominant" "submission" "submissive" "latex" "roleplay" "onlyfans" "only-fans" "fansly" "camgirl" "cam-girl" "camshow" "webcamgirl" "escort" "stripper" "strip" "stripclub" "pole-dance" "pole-dancing" "lingerie" "underwear" "panties" "bra" "thong" "stockings" "bikini" "swimsuit" "swimwear" "microbikini" "nipple" "nipples" "breast" "breasts" "boob" "boobs" "cleavage" "areola" "genitals" "genital" "vagina" "vaginal" "penis" "dick" "cock" "pussy" "ass" "butt" "cum" "semen" "anal" "blowjob" "handjob" "handbra" "orgasm" "masturbation" "masturbate" "self-pleasure" "pornhub" "xvideos" "xnxx" "redtube" "youporn" "tube8" "spankbang" "xhamster" "brazzers" "nsfwart" "adultart" "rule34art" "lewdart" "hentaiart" "animeporn" "animehentai")
# }}}

# {{{ WARN: DuckDuckGo Safety filter
    # p=0  ⇒ SafeSearch off
    # p=1  ⇒ SafeSearch moderate
    # p=2  ⇒ SafeSearch strict
    # p=-1 ⇒ SafeSearch disabled

DDG_SAFESEARCH=-1
# }}}

safe_filter() {
    jq -c --argjson blocked "$(printf '%s\n' "${BLOCKED_TERMS[@]}" | jq -R . | jq -s .)" '
        map(
            select(
                (
                    (.file // "") +
                    (.image // "") +
                    (.thumb // "") +
                    (.preview // "") +
                    (.source // "")
                )
                | ascii_downcase
                | gsub("[[:space:]_.-]"; "")
                | gsub("[^a-z0-9+]"; "")
                as $text
                |
                [
                    $blocked[]
                    |
                    ascii_downcase
                    | gsub("[[:space:]_.-]"; "")
                    | gsub("[^a-z0-9+]"; "")
                    as $term
                    |
                    select($text | contains($term))
                ]
                | length == 0
            )
        )
    '
}

search_github() {
    local query="${1:-}"

    python3 - "$query" "$GITHUB_REPO" "$GITHUB_BRANCH" <<'PYEOF'
import json
import sys
import urllib.parse
import urllib.request
import re

query = sys.argv[1].lower().strip()
repo = sys.argv[2]
branch = sys.argv[3]

url = f"https://api.github.com/repos/{repo}/git/trees/{branch}?recursive=1"

try:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "Mozilla/5.0"
        }
    )

    with urllib.request.urlopen(req, timeout=20) as response:
        tree = json.load(response)

    results = []

    for item in tree.get("tree", []):
        path = item.get("path", "")

        if not path.lower().endswith(
            (".png", ".jpg", ".jpeg", ".webp", ".gif", ".mp4", ".webm")
        ):
            continue

        if query and query not in path.lower():
            continue

        raw = (
            "https://raw.githubusercontent.com/"
            f"{repo}/{branch}/"
            f"{urllib.parse.quote(path)}"
        )

        results.append({
            "image": raw,
            "thumb": raw,
            "file": path,
            "source": "github",
            "w": 0,
            "h": 0
        })

    print(json.dumps(results))

except Exception:
    print("[]")
PYEOF
}


search_moewalls() {
    local query="${1:-}"
    UA="$UA" python3 - "$query" <<'PYEOF'
import concurrent.futures
import json
import os
import re
import sys
import urllib.parse
import urllib.request

ua = os.environ.get("UA", "Mozilla/5.0")

def fetch(url, timeout=10):
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": ua,
            "Referer": "https://moewalls.com/"
        }
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "ignore")

def post_entry(url):
    html = fetch(url)

    prev = re.search(
        r'<source src="(/wp-content/uploads/preview/[^"]+)"',
        html
    )

    token = re.search(
        r'id="moe-download"[^>]*data-url="([^"]+)"',
        html
    )

    thumb = re.search(
        r'poster="([^"]+)"',
        html
    )

    if not prev or not token:
        return None

    res = re.search(
        r'resolutions-(\d+)x(\d+)',
        html
    )

    return {
        "image": "https://go.moewalls.com/download.php?video=" + token.group(1),
        "thumb": urllib.parse.urljoin(
            "https://moewalls.com/",
            thumb.group(1)
        ) if thumb else "",
        "preview": urllib.parse.urljoin(
            "https://moewalls.com/",
            prev.group(1)
        ),
        "source": "moewalls",
        "w": int(res.group(1)) if res else 0,
        "h": int(res.group(2)) if res else 0,
    }


try:
    q = urllib.parse.quote(sys.argv[1])

    page = fetch(
        "https://moewalls.com/?s=" + q,
        timeout=12
    )

    posts = []

    for m in re.finditer(
        r'href="(https://moewalls\.com/[a-z0-9-]+/[a-z0-9-]+-live-wallpaper/)"',
        page
    ):
        if m.group(1) not in posts:
            posts.append(m.group(1))

    out = []

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        for entry in ex.map(post_entry, posts[:24]):
            if entry:
                out.append(entry)

    print(json.dumps(out))

except Exception:
    print("[]")
PYEOF
}

search() {
    local query="${1:-}" kind="${2:-all}"

    for term in "${BLOCKED_TERMS[@]}"; do
        if [[ "${query,,}" == *"$term"* ]]; then
            printf '[]\n'
            exit 0
        fi
    done

    [ -n "$query" ] || {
        printf '[]\n'
        return 0
    }

    local repo_results

    # Always prioritize personal wallpaper repo, and filter
    repo_results=$(search_github "$query" | safe_filter)

    case "$kind" in
        repo|github)
            printf '%s\n' "$repo_results"
            return 0
            ;;
        motion)
            # Combine repo + Moewalls
            python3 - "$repo_results" <<'PYEOF'
import json
import sys

repo = json.loads(sys.argv[1])
print(json.dumps(repo))
PYEOF

            search_moewalls "$query" | safe_filter
            return 0
            ;;
    esac


    # If repo has matches, return them first
    if [ "$(printf '%s' "$repo_results" | jq 'length')" -gt 0 ]; then
        printf '%s\n' "$repo_results"
        return 0
    fi


    # Fall back to DuckDuckGo
    local q="$query" f=",,,"

    case "$kind" in
        still)
            f="type:photo"
            ;;
    esac


    local enc vqd raw

    enc=$(jq -rn --arg q "$q" '$q|@uri') || {
        printf '[]\n'
        return 0
    }


    vqd=$(curl -s --max-time 10 \
        "https://duckduckgo.com/?q=${enc}&iax=images&ia=images" \
        -A "$UA" |
        grep -oP 'vqd=\\?"?\K[0-9-]+' |
        head -1)


    [ -n "$vqd" ] || {
        printf '[]\n'
        return 0
    }

    raw=$(curl -s --max-time 10 \
        "https://duckduckgo.com/i.js?l=us-en&o=json&q=${enc}&vqd=${vqd}&f=${f}&p=${DDG_SAFESEARCH}" \
        -A "$UA" \
        -H "Referer: https://duckduckgo.com/")

    [ -n "$raw" ] || {
        printf '[]\n'
        return 0
    }


    printf '%s' "$raw" |
    jq -c --arg kind "$kind" '
        (.results // [])
        | if $kind == "still" then
            map(select(.image // "" | test("\\.gif(\\?|$)"; "i") | not))
          else .
          end
        | map({
            image: .image,
            thumb: (.thumbnail // .image),
            source: "duckduckgo",
            w: (.width // 0),
            h: (.height // 0)
          })
        | map(select(.image != null and .image != ""))
        | .[0:60]
    ' 2>/dev/null | safe_filter || printf '[]\n'
}


download() {
    set -euo pipefail

    url="${1:-}"

    for term in "${BLOCKED_TERMS[@]}"; do
        if [[ "${url,,}" == *"$term"* ]]; then
            exit 1
        fi
    done

    [ -n "$url" ] || exit 1


    flags="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin/flags.json"

    wpdir=$(jq -r '.wallpaperDir // ""' "$flags" 2>/dev/null || echo "")

    [ -n "$wpdir" ] ||
    wpdir=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper-dir" 2>/dev/null || true)

    [ -n "$wpdir" ] ||
    wpdir="$HOME/Pictures/rice-wallpapers"


    dir="$wpdir"

    mkdir -p "$dir"


    case "$url" in
        https://go.moewalls.com/download.php*)

            fn=$(curl -fsI \
                --max-time 20 \
                -A "$UA" \
                -e "https://moewalls.com/" \
                "$url" |
                grep -oiP 'filename=\K[^"\r\n;]+' |
                head -1 |
                tr -d '/\\')


            [ -n "$fn" ] ||
            fn="moewalls-$(date +%s).mp4"


            out="$dir/$fn"


            curl -fsL \
                --max-time 600 \
                -A "$UA" \
                -e "https://moewalls.com/" \
                -o "$out" \
                "$url"


            [ -s "$out" ] || exit 1

            printf '%s\n' "$out"
            exit 0
            ;;
    esac


    tmp=$(mktemp "${TMPDIR:-/tmp}/ddg-wp.XXXXXX")

    trap 'rm -f "$tmp" "$tmp.out"' EXIT


    curl -fsL \
        --max-time 60 \
        -A "$UA" \
        -e "https://duckduckgo.com/" \
        -o "$tmp" \
        "$url"


    [ -s "$tmp" ] || exit 1


    export MAGICK_CONFIGURE_PATH="$(dirname "$0")/magick-policy"


    fmt=$(magick identify -format '%m' "${tmp}[0]" 2>/dev/null | head -1) ||
        exit 1


    case "$fmt" in
        JPEG) ext=jpg ;;
        PNG)  ext=png ;;
        GIF)  ext=gif ;;
        WEBP) ext=webp ;;
        *)    ext=png ;;
    esac


    out="$dir/ddg-$(date +%s)-${RANDOM}.${ext}"


    if [ "$ext" = "png" ] && [ "$fmt" != "PNG" ]; then
        magick "${tmp}[0]" -strip "png:$tmp.out" 2>/dev/null ||
            exit 1

        [ -s "$tmp.out" ] || exit 1

        mv "$tmp.out" "$out"
    else
        cp "$tmp" "$out"
    fi


    [ -s "$out" ] || exit 1

    printf '%s\n' "$out"
}


case "${1:-}" in
    search)
        search "${2:-}" "${3:-all}"
        ;;
    download)
        download "${2:-}"
        ;;
    *)
        printf '[]\n'
        exit 0
        ;;
esac
