# Customization

<!--toc:start-->
- [Customization](#customization)
  - [Theme](#theme)
  - [Wallpaper](#wallpaper)
  - [Icons](#icons)
  - [Motion](#motion)
  - [Rounded screen corners](#rounded-screen-corners)
  - [Game mode](#game-mode)
<!--toc:end-->

## Theme

Every surface reads its colors from one shared token set, so a single swap
re-tints the whole shell. There are three palette modes. Static is a port of
the vague.nvim colorscheme, which replaces the warm vermilion theme Ricelin
shipped. Dynamic follows the live wallpaper-derived palette. Manual picks a
hue on a strip and rebuilds the color set from it, with a dark/light choice.
The UI font is configurable and defaults to Inter.

## Wallpaper

A filmstrip over the wallpaper directory, newest first. The focused thumb is
large and fully lit while the neighbors shrink, dim and desaturate, so the
strip reads as depth. Arrow keys and wheel move focus, Enter applies the pick
through wallpaper.sh, and holding Enter deletes it. The strip stays open so
you can keep trying picks.

Which directory is one resolved folder, shared by the strip, the thumbnail
builder, the shuffle bag and the search downloader: the Folder field in
settings if it is set, otherwise an existing collection in one of the usual
spots (~/Pictures/rice-wallpapers, ~/Pictures/Wallpapers, …), otherwise
~/Pictures. Picks land in whatever it resolves to, so they join the bag.

Typing while the strip is open searches the web first — Bing's image search,
your personal GitHub wallpaper repo with the `gh:` prefix, and moewalls for
motion. Every word of a query has to match something in the filename, in any
order; when that finds nothing the words are tried individually, so a longer
query can't narrow the strip to nothing. A bare `gh:` lists the whole repo.
Nothing is cached anywhere — every search is a live request, so a wallpaper you
just pushed shows up on the next one. DuckDuckGo images is the script's second
attempt when Bing answers nothing.

Wallhaven is the second source: type `wh:` and a tag to ask it directly, or let
an empty web result hand the same query over once (image endpoints refuse heavy
use, and an empty strip is a poor answer when a wallpaper API is sitting right
there). One hop only, in either direction. Its tag search ANDs its terms, which
is why a plain three-word query used to come back empty — when that happens the
same words are asked again as alternatives (`|` is OR to wallhaven), so long
natural-language queries return something instead of nothing. Only for plain
word lists: `@user`, `#tag`, `id:` and quoted syntax are left alone.

Every wallhaven-bound request — API pages, thumbnails and full picks — shares
one rolling rate budget with a cooling-off latch on any 429/403, so browsing
can't trip its Cloudflare rule the way a per-tile hotlink burst did. Searches
never wait in that queue: if the budget is spent they answer immediately and the
result falls back to the web, while thumbnails trickle in around the tile you
are looking at. The script's sort buckets (latest, top, random, favorites) are
available to a future sort control.

Dynamic colors come from a snapshot of the current wallpaper, which is what
the dynamic theme mode feeds on.

## Icons

The icon set is hand drawn SVG, not a stock icon pack. The wifi glyph is the
best example: a custom drawn signal icon instead of a generic asset.

## Motion

Animation durations and easings come from a shared motion module, so every
surface moves with the same feel. A reduce-motion switch and game mode both
cut the animation budget when you want less of it, and because that module is the
only place a duration is handed out, one slider in the settings window's Motion
page speeds the whole shell up or down.

## Rounded screen corners

A decoration layer draws rounded corners over the screen edges. The rounding
follows the pill state: game mode removes it, notch mode increases it, and
dynamic island mode uses partial rounding. Each of those radii, the bezel shadow
inside them and how long the collapse takes are settings — the Corners page —
rather than constants in the layer.

## Game mode

A performance switch that collapses the pill to a flat strip, disables
animations and extra spacing, and trims visual effects. Useful for games or
when you want the GPU to only do actual work.
