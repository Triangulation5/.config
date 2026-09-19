#!/usr/bin/env bash

# vim: foldmethod=marker foldlevelstart=0

UA="Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/126.0"

GITHUB_REPO="Triangulation5/wallpapers"
GITHUB_BRANCH="main"

# {{{ DO NOT OPEN: Borderline Safety Filter
BLOCKED_TERMS=("nsfw" "n.s.f.w" "n_s_f_w" "n-s-f-w" "not safe for work" "not-safe-for-work" "nude" "nudity" "naked" "nakd" "nak" "undressed" "undress" "topless" "bottomless" "bare" "baring" "exposed" "exposure" "porn" "porno" "pornography" "pornographic" "pornstar" "xxx" "xx" "x-rated" "xrated" "adultvideo" "adultvideos" "sex" "sexual" "sexually" "sexy" "sexgirl" "sexygirl" "sexwoman" "sexmodel" "intercourse" "hookup" "hentai" "hentAI" "h3ntai" "ecchi" "ero" "erotic" "erotica" "eroanime" "adultanime" "18+" "18plus" "18-plus" "18plusonly" "18years" "adultonly" "maturecontent" "adult" "adultcontent" "adult-content" "explicit" "explicitcontent" "explicit-content" "rule34" "rule-34" "rule_34" "r34" "rulethreefour" "booru" "danbooru" "gelbooru" "konachan" "yandere" "safebooru" "zerochan" "e621" "e926" "furry" "furries" "futanari" "futa" "futa-anime" "yaoi" "yuri" "shota" "shotacon" "loli" "lolicon" "lolicorn" "doujin" "doujinshi" "manga18" "adultmanga" "lewd" "lewds" "lewdness" "suggestive" "provocative" "risque" "risqué" "fetish" "bdsm" "bondage" "dominatrix" "dominant" "submission" "submissive" "latex" "roleplay" "onlyfans" "only-fans" "fansly" "camgirl" "cam-girl" "camshow" "webcamgirl" "escort" "stripper" "strip" "stripclub" "pole-dance" "pole-dancing" "lingerie" "underwear" "panties" "bra" "thong" "stockings" "bikini" "swimsuit" "swimwear" "microbikini" "nipple" "nipples" "breast" "breasts" "boob" "boobs" "cleavage" "areola" "genitals" "genital" "vagina" "vaginal" "penis" "dick" "cock" "pussy" "ass" "butt" "cum" "semen" "anal" "blowjob" "handjob" "handbra" "orgasm" "masturbation" "masturbate" "self-pleasure" "pornhub" "xvideos" "xnxx" "redtube" "youporn" "tube8" "spankbang" "xhamster" "brazzers" "nsfwart" "adultart" "rule34art" "lewdart" "hentaiart" "animeporn" "animehentai")
# }}}

# {{{ WARN: DuckDuckGo Safety filter
    # p=0  ⇒ SafeSearch off
    # p=1  ⇒ SafeSearch moderate
    # p=2  ⇒ SafeSearch strict
    # p=-1 ⇒ SafeSearch disabled

DDG_SAFESEARCH=2
# }}}

# {{{ WARN: Wallhaven pacing

# Every wallhaven-bound request in this script — API pages, thumbnail fetches
# and full picks — goes through one shared pace gate, so no part of the UI can
# trip wallhaven's limits again. The documented API cap is 45 calls/min (429
# past it), and a Cloudflare rule has also banned whole IPs on request bursts:
# one such burst here took even a cookie'd browser down with a 403. The gate is
# a rolling-window budget — it lets a burst through, so a fresh page of thumbs
# loads in seconds instead of trickling, but caps everything wallhaven-bound at
# WH_BUDGET (default 30) requests per 60s, shared across processes through a
# timestamp journal, and latches a hard cooling-off period on any throttle or
# block signal.

wh_state() {
    local base="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette"
    mkdir -p "$base"
    printf '%s\n' "$base"
}

# Suspend all wallhaven traffic for `secs` (default 60). Seeded by any 429/403
# the fetchers see, so a throttle resets the whole pipeline's clock instead of
# letting parts of the UI keep slipping requests through.
wh_backoff() {
    local secs="${1:-60}" base
    base=$(wh_state)
    printf '%s\n' "$(( $(date +%s) + secs ))" > "$base/wh-cooldown.until"
}

# `wh_gate` blocks until the request may go out. `wh_gate --nowait` is the same
# accounting but refuses to wait: if the cool-off is latched or the rolling
# budget is spent it gives up immediately and returns 1, spending no slot.
#
# Searches use the nowait form and thumbnails keep the blocking one. A search
# that sits in this queue is a strip frozen behind its own thumbnail traffic —
# a page of thumbs is 24 requests against a 30-per-minute budget, so the second
# query of a minute used to wait out the minute before it could even ask, which
# reads as a broken search box. Failing fast lets the caller answer something
# else instead. A thumbnail can afford to trickle; nobody notices a tile that
# fills in a minute late.
wh_gate() {
    local nowait=false
    [ "${1:-}" = "--nowait" ] && nowait=true
    local base budget now oldest need_ms count
    base=$(wh_state)
    budget="${WH_BUDGET:-30}"
    { [ "$budget" -gt 0 ] 2>/dev/null; } || budget=30
    exec 9>"$base/wh-window.lock"
    flock 9

    # Cooling-off latch: a recent 429/403 parks every wallhaven request until
    # the timestamp passes. The lock is held throughout so the whole pipeline
    # wakes together instead of trickling back in one request at a time.
    local cooldown until now_s
    cooldown="$base/wh-cooldown.until"
    if [ -f "$cooldown" ]; then
        until=$(cat "$cooldown" 2>/dev/null || echo 0)
        now_s=$(date +%s)
        if [ "$now_s" -lt "$until" ]; then
            if [ "$nowait" = true ]; then
                # Still latched: leave the latch for the next caller and bail.
                flock -u 9
                return 1
            fi
            sleep "$(( until - now_s ))"
        fi
        rm -f "$cooldown"
    fi

    window="$base/wh-window.ts"
    while :; do
        now=$(date +%s%N)
        if [ -f "$window" ]; then
            awk -v now="$now" ' $0 + 60000000000 > now ' "$window" > "$window.tmp" \
                && mv "$window.tmp" "$window"
            count=$(wc -l < "$window")
        else
            count=0
        fi
        if [ "$count" -lt "$budget" ]; then
            printf '%s\n' "$now" >> "$window"
            break
        fi
        if [ "$nowait" = true ]; then
            flock -u 9
            return 1
        fi
        # Budget exhausted: wait until the oldest in-window request ages out.
        oldest=$(head -1 "$window")
        need_ms=$(( 60000 - (now - oldest) / 1000000 ))
        if [ "$need_ms" -le 250 ]; then
            # Nearly expired anyway — nudge past without a clever sleep.
            sleep 0.3
        else
            sleep "$(awk -v w="$need_ms" 'BEGIN { printf "%.3f", w/1000 }')"
        fi
    done
    flock -u 9
}

# Wallhaven browse/search. An empty query returns the default hot (toplist)
# feed; a query refines it as a most-favorited search. The third arg picks the
# sorting bucket (hot, latest, top, random, favorites); with a query, favorites
# is implied unless overridden.
#
# This is the *secondary* wall source: the strip searches the web first and only
# asks here when that came back empty, or when the query was typed with a `wh:`
# prefix to ask for wallhaven on purpose. The web endpoint refuses heavy use
# (see the DDG guard above), and a wallpaper picker whose search box goes quiet
# because of that is why this exists at all. Hot and Top deliberately map to DIFFERENT API
# buckets: toplist is dominated by the same mega-popular wallpapers on page one
# whether you ask for a month or a year, which made the two sections return
# identical thumbs, so Top means all-time most-viewed (`views`) instead of a
# redundant toplist range. purity=100 keeps the feed SFW, matching this
# script's posture everywhere else. The API serves ready-made thumbs, so
# results are URLs handed over to `thumbget` for a paced local copy: nothing is
# downloaded until the strip actually shows it.
# One API round trip against wallhaven, no caching: prints the mapped array
# (possibly empty) or the blocked marker that tells the caller to use its other
# source. Everything but the query itself is the caller's business.
wh_fetch() {
    local query="${1:-}" page="${2:-1}" sort="${3:-favorites}" extra="${4:-}"
    local enc raw code mapped

    enc=$(jq -rn --arg q "$query" '$q|@uri') || { printf '[]\n'; return 0; }

    # never_wait: a search answers *something* now (results, or the blocked
    # marker that sends the caller to its other source) instead of queueing
    # behind whatever thumbnails are already in the budget window.
    wh_gate --nowait || { printf '%s\n' '{"wallhaven":"blocked"}'; return 0; }
    raw=$(curl -s --max-time 15 -w $'\n%{http_code}' -A "$UA" \
        "https://wallhaven.cc/api/v1/search?${query:+q=${enc}&}sorting=${sort}&${extra}order=desc&purity=100&page=${page}")
    code="${raw##*$'\n'}"
    raw="${raw%$'\n'*}"
    [ -n "$code" ] || code=000
    if [ "$code" = "000" ]; then
        # No HTTP response at all — offline, DNS failure, or a time-out. That is
        # a network hiccup, not wallhaven blocking us: don't latch a phantom
        # cooldown, just hand back an empty page and let the UI sit idle until
        # connectivity returns, or fall back to its web search.
        printf '[]\n'
        return 0
    fi
    if [ "$code" != "200" ]; then
        # 429 = the documented rate cap (45/min); 403/5xx = WAF block or edge
        # hiccup. Either way latch a hard cooldown so no part of the UI can keep
        # requesting, and hand the UI a pause marker — its fallback owns the
        # re-checks, and this is never cached.
        case "$code" in
            429) wh_backoff 120 ;;
            *)   wh_backoff 60 ;;
        esac
        printf '%s\n' '{"wallhaven":"blocked"}'
        return 0
    fi
    [ -n "$raw" ] || { printf '%s\n' '{"wallhaven":"blocked"}'; return 0; }

    mapped=$(printf '%s' "$raw" | jq -c '
        .data // []
        | map({
            image: .path,
            thumb: (.thumbs.large // .thumbs.original // ""),
            w: (.dimension_x // 0),
            h: (.dimension_y // 0)
          })
        | map(select(.image != null and .image != ""))
    ' 2>/dev/null || true)
    [ -n "$mapped" ] || mapped='[]'
    printf '%s\n' "$mapped"
}

whsearch() {
    local query="${1:-}" page="${2:-1}" want="${3:-}"
    case "$page" in
        ''|*[!0-9]*) page=1 ;;
    esac

    local sort extra mapped words alt plain
    sort="favorites"
    extra=""
    case "$want" in
        latest)    sort="date_added" ;;
        top)       sort="views" ;;
        random)    sort="random" ;;
        favorites) sort="favorites" ;;
    esac
    if [ -z "$want" ] || [ "$want" = "hot" ]; then
        if [ -n "$query" ]; then
            sort="favorites"; extra=""
        else
            sort="toplist"; extra="topRange=1M&"
        fi
    fi

    # No result cache: the same query asks wallhaven again. The strip re-fires
    # the current page on picks, sort changes and surface re-entry, and a
    # replayed answer is the one thing that makes a wallpaper picker feel like
    # it is lying — you cannot tell a cached page from a page that failed to
    # refresh. Round trips are cheap; the pace gate still bounds them.
    mapped=$(wh_fetch "$query" "$page" "$sort" "$extra")

    # A wallhaven tag search ANDs its terms, so a plain-language query of three
    # or more words routinely matches nothing at all — "tight cat noir" is
    # literally zero results while "tight|cat|noir" is thousands. Wallhaven's
    # `|` is OR, so when an AND search comes back empty the same words are asked
    # again as alternatives. Only for plain word lists: a query carrying search
    # syntax (`@user`, `#tag`, `id:`, quotes) means exactly what it says, and
    # rewriting it would answer a question nobody asked. Never for a blocked or
    # empty-query result either — a refused request gets one attempt, not two.
    plain=true
    case "$query" in
        *[!A-Za-z0-9_\ -]*) plain=false ;;
    esac
    words=$(printf '%s' "$query" | wc -w)
    if [ "$plain" = true ] && [ "$words" -gt 1 ] && [ "$mapped" = "[]" ]; then
        alt=$(printf '%s' "$query" | tr -s ' ' '|')
        [ "$alt" = "$query" ] || mapped=$(wh_fetch "$alt" "$page" "$sort" "$extra")
    fi

    case "$mapped" in
        '{"wallhaven":"blocked"}' | '')
            printf '%s\n' '{"wallhaven":"blocked"}'
            ;;
        *)
            printf '%s\n' "$mapped"
            ;;
    esac
}

# Fetch one wallhaven thumb into a disk cache at the same shared pace. Cached
# hits are served instantly with no network and no gate (Qt decodes by content,
# so the extensionless cache name is fine), so scrolling back over a page costs
# zero wallhaven requests. The cache is kept under WH_THUMB_MAX_MB (default 20):
# every fresh store prunes the least-recently used thumbs (the newest just saved
# is kept) until the directory fits again.
thumbget() {
    local url="${1:-}"
    [ -n "$url" ] || exit 1
    local base digest cache tmp
    base="${XDG_CACHE_HOME:-$HOME/.cache}/silhouette/wh-thumbs"
    mkdir -p "$base"
    digest=$(printf '%s\n' "$url" | sha1sum | cut -c1-24)
    cache="$base/$digest"
    [ -s "$cache" ] && { printf '%s\n' "$cache"; exit 0; }
    wh_gate
    tmp="$base/.$digest.tmp"
    trap 'rm -f "$tmp"' EXIT
    curl -fsSL --max-time 25 -A "$UA" -e "https://wallhaven.cc/" -o "$tmp" "$url" \
        || exit 1
    [ -s "$tmp" ] || exit 1
    mv "$tmp" "$cache"
    local max_mb total old
    max_mb="${WH_THUMB_MAX_MB:-20}"
    { [ "$max_mb" -gt 0 ] 2>/dev/null; } || max_mb=20
    total=$(du -sk "$base" 2>/dev/null | awk '{print $1}')
    while [ "${total:-0}" -gt $(( max_mb * 1024 )) ]; do
        old=$(find "$base" -maxdepth 1 -type f ! -name '.*' \
              -printf '%T@ %p\n' | sort -n | head -1 | cut -d' ' -f2-)
        [ -n "$old" ] || break
        rm -f "$old"
        total=$(du -sk "$base" 2>/dev/null | awk '{print $1}')
    done
    printf '%s\n' "$cache"
}

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

# The personal wallpaper repo, the source behind `gh:`. The listing is fetched
# live on every call — nothing is cached, so a wallpaper pushed to the repo is
# in the strip on the next search rather than whenever a cache happens to
# expire.
#
# Matching is per word, not per phrase. The old check required the whole query
# as a substring of the path, so `gh:space city` matched nothing while
# `gh:space` worked — multi-word queries looked broken. Now every word has to
# appear somewhere in the filename, in any order, and the ranking prefers more
# words matched, then the phrase as typed, then shorter names (a tight filename
# is a stronger match than a long one that merely contains the words).
#
# Two cases are deliberately forgiving, because the alternative is an empty
# strip that reads as a broken search:
#
#   * Several words matching nothing relaxes to the words individually. AND-ing
#     three words is a narrow net — `gh:night city` finds nothing when no single
#     filename holds both — and the user's own walls are the most likely useful
#     answer.
#   * A bare `gh:` (empty query) lists the whole repo. That is the only way to
#     browse it, and typing the prefix alone used to return nothing at all.
search_github() {
    local query="${1:-}"

    python3 - "$query" "$GITHUB_REPO" "$GITHUB_BRANCH" <<'PYEOF'
import json
import sys
import urllib.parse
import urllib.request

query = sys.argv[1].lower().strip()
repo = sys.argv[2]
branch = sys.argv[3]

EXTS = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".mp4", ".webm")

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
except Exception:
    print("[]")
    sys.exit(0)

words = [word for word in query.split() if word]


def entries(mode):
    out = []

    for item in tree.get("tree", []):
        path = item.get("path", "")
        low = path.lower()

        if not low.endswith(EXTS):
            continue

        hits = sum(1 for word in words if word in low)

        if words and ((mode == "all" and hits != len(words)) or (mode == "any" and hits == 0)):
            continue

        raw = (
            "https://raw.githubusercontent.com/"
            f"{repo}/{branch}/"
            f"{urllib.parse.quote(path)}"
        )

        out.append({
            "image": raw,
            "thumb": raw,
            "file": path,
            "source": "github",
            "w": 0,
            "h": 0,
            "_hits": hits,
            "_phrase": bool(query) and query in low,
            "_len": len(path)
        })

    if words:
        out.sort(key=lambda entry: (-entry["_hits"], not entry["_phrase"], entry["_len"]))
    else:
        out.sort(key=lambda entry: entry["file"].lower())

    for entry in out:
        del entry["_hits"]
        del entry["_phrase"]
        del entry["_len"]

    return out


results = entries("all")

if not results and len(words) > 1:
    results = entries("any")

print(json.dumps(results[:60]))
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

# Bing image search — the primary web source. It needs no key and its async
# endpoint answers with the image URLs inline: each result is a `class="iusc"`
# element whose `m` attribute is an HTML-escaped JSON blob carrying `murl` (the
# full image) and `turl` (a hosted thumbnail). Parsing that blob is what keeps
# this to one request per query, with no vqd token dance and no cookie jar.
#
# Safe search is pinned on two parameters (`adlt`, `safeSearch`) on top of the
# BLOCKED_TERMS filter every result passes through, matching this script's
# posture everywhere else. The thumbnail is what the strip renders, so a page of
# results stays light — the full-size image is only fetched when a wallpaper is
# actually picked.
search_bing() {
    local query="${1:-}" kind="${2:-all}"

    UA="$UA" KIND="$kind" python3 - "$query" <<'PYEOF'
import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request

query = sys.argv[1].strip()
kind = os.environ.get("KIND", "all")
ua = os.environ.get("UA", "Mozilla/5.0")

url = (
    "https://www.bing.com/images/async?q=" + urllib.parse.quote(query)
    + "&first=1&count=35&mmasync=1&adlt=strict&safeSearch=strict"
)

try:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": ua,
            "Accept-Language": "en-US,en;q=0.9",
        },
    )

    with urllib.request.urlopen(req, timeout=15) as response:
        page = response.read().decode("utf-8", "ignore")
except Exception:
    print("[]")
    sys.exit(0)

results = []
seen = set()

for blob in re.findall(r'\bm="([^"]+)"', page):
    try:
        entry = json.loads(html.unescape(blob))
    except Exception:
        continue

    image = entry.get("murl") or ""

    if not image.startswith("http") or image in seen:
        continue

    if kind == "still" and re.search(r"\.gif(\?|$)", image, re.I):
        continue

    seen.add(image)

    results.append({
        "image": image,
        "thumb": entry.get("turl") or image,
        "source": "bing",
        "w": 0,
        "h": 0,
    })

print(json.dumps(results[:60]))
PYEOF
}


search() {
    local query="${1:-}" kind="${2:-all}"

    # gh: prefix → search only personal GitHub repo
    if [[ "$query" == gh:* ]]; then
        query="${query#gh:}"
        kind="github"
    fi

    for term in "${BLOCKED_TERMS[@]}"; do
        if [[ "${query,,}" == *"$term"* ]]; then
            printf '[]\n'
            exit 0
        fi
    done

    # A bare `gh:` has an empty query on purpose — it lists the whole repo, and
    # it is the only way to browse it. Every other source needs something to
    # search for.
    if [ -z "$query" ] && [ "$kind" != "github" ] && [ "$kind" != "repo" ]; then
        printf '[]\n'
        return 0
    fi

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

    # Web search, two backends. Bing goes first because it answers — the
    # DuckDuckGo image endpoint this script was built around now returns 403 to
    # every request from here, so web search had quietly become "nothing,
    # always", which is what pushed every query onto wallhaven in the first
    # place. DuckDuckGo is kept as the second attempt rather than deleted: the
    # block is at the IP level and may lift, and it costs one request to find
    # out when it does.
    local web
    web=$(search_bing "$query" "$kind" | safe_filter)

    if [ -z "$web" ] || [ "$web" = "[]" ]; then
        web=$(search_ddg "$query" "$kind")
    fi

    [ -n "$web" ] || web='[]'
    printf '%s\n' "$web"
}

# DuckDuckGo image search — now the fallback web source. See the note in
# `search` for why it no longer leads.
search_ddg() {
    local query="${1:-}" kind="${2:-all}"

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

    # The endpoint answers a block, a captcha or a plain refusal with an English
    # sentence instead of JSON ("If this error persists, please let us know…"),
    # and jq on that body prints nothing while still exiting 0. That reached the
    # consumer as *empty stdout* — not "no results" but a JSON parse error, so a
    # search that had been refused looked like a dead script. Anything that is
    # not the expected object now lands as an explicit empty array.
    printf '%s' "$raw" | jq -e 'type == "object"' >/dev/null 2>&1 || {
        printf '[]\n'
        return 0
    }

    # Same guard on the way out: `safe_filter` on an empty pipe prints nothing
    # and exits 0, so the result is captured and defaulted rather than left to
    # an `||` that never fires.
    local mapped
    mapped=$(printf '%s' "$raw" |
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
        ' 2>/dev/null | safe_filter)
    [ -n "$mapped" ] || mapped='[]'
    printf '%s\n' "$mapped"
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


    flags="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"

    # Same folder chain as wallpaper.sh, so a pick always lands in the folder
    # the strip is actually browsing and joins its shuffle bag: the explicit
    # flag, then the folder wallpaper.sh resolved, then ~/Pictures. The state
    # file is the normal answer (the strip resolves on every refresh), so the
    # rest are only first-boot fallbacks.
    wpdir=$(jq -r '.wallpaperDir // ""' "$flags" 2>/dev/null || echo "")

    # The flag is stored exactly as it was typed into the settings field, whose
    # own placeholder is `~/Pictures`. The shell does not expand a tilde that
    # arrived in a variable, so it would be read as a relative path and the
    # download would land somewhere nobody browses.
    case "$wpdir" in
        "~")   wpdir="$HOME" ;;
        "~/"*) wpdir="$HOME/${wpdir#"~/"}" ;;
    esac

    [ -n "$wpdir" ] ||
    wpdir=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/silhouette-wallpaper-dir" 2>/dev/null || true)

    [ -n "$wpdir" ] ||
    wpdir="$HOME/Pictures"


    dir="$wpdir"

    mkdir -p "$dir"


    case "$url" in
        https://w.wallhaven.cc/*)
            # A pick is a wallhaven-bound request too, so it shares the pace
            # gate that protects the API and the thumb CDN. The filename keeps
            # the wallhaven id, so a pick stays recognisable in the folder.
            wh_gate

            fn=$(basename "$url" | tr -d '/\\')

            [ -n "$fn" ] || exit 1

            out="$dir/$fn"

            curl -fsL \
                --max-time 600 \
                -A "$UA" \
                -e "https://wallhaven.cc/" \
                -o "$out" \
                "$url" || exit 1

            [ -s "$out" ] || exit 1

            printf '%s\n' "$out"
            exit 0
            ;;

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
    whsearch)
        whsearch "${2:-}" "${3:-1}" "${4:-}"
        ;;
    thumbget)
        thumbget "${2:-}"
        ;;
    download)
        download "${2:-}"
        ;;
    *)
        printf '[]\n'
        exit 0
        ;;
esac
