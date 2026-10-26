#!/usr/bin/env python3

"""
Generate the rice colour set from a wallpaper and fan it out to the consumers.

Dynamic mode is Material You. `matugen image` extracts a source colour from the
wallpaper and runs it through a Material 3 scheme, and the flags decide which
one: the scheme variant (tonal spot, vibrant, expressive, …), the contrast
level, light/dark/smart mode, and which colour matugen should prefer when the
image offers several. One invocation yields every role the shell and this app
need, so the M3 palette is the single source of truth rather than a main hue
run through a second, hand-written tonal ramp.

Manual mode stays on the old HSL path: there is no image to extract from, the
hue is chosen by hand, and the existing ramp is what the mode was designed
around.

matugen's base16 JSON still generates the terminal palette, kept dark: the
terminals are always-dark consumers even when the shell is in Material light
mode. The pill JSON owns surfaces, accents and contrast-matched text.
"""

import colorsys
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

CACHE = Path.home() / ".cache" / "silhouette"
FLAGS = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    / "silhouette"
    / "flags.json"
)

# matugen spells its scheme types `scheme-tonal-spot`; the flag stores the
# short name so a settings row can show the human label.
SCHEMES = {
    "tonal-spot",
    "vibrant",
    "expressive",
    "fidelity",
    "content",
    "fruit-salad",
    "rainbow",
    "neutral",
    "monochrome",
}

PREFERS = {
    "saturation",
    "less-saturation",
    "lightness",
    "darkness",
    "value",
}


def read_flags():
    """The shell's flag document, or an empty map when it has not been written."""
    try:
        data = json.loads(FLAGS.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


SURF_NAMES = [
    "surface",
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
    "outline_variant",
]

DARK_STEPS = [
    0.000,
    0.022,
    0.038,
    0.065,
    0.100,
    0.225,
]

LIGHT_STEPS = [
    0.000,
    -0.045,
    -0.075,
    -0.115,
    -0.160,
    -0.340,
]


TEXT_KEYS = [
    "cream",
    "bright",
    "subtle",
    "dim",
    "faint",
    "icon_dim",
    "tick_rest",
]


DARK_TEXT = [
    (0.90, 0.05),
    (0.97, 0.03),
    (0.73, 0.07),
    (0.54, 0.06),
    (0.44, 0.05),
    (0.81, 0.07),
    (0.75, 0.08),
]


LIGHT_TEXT = [
    (0.20, 0.18),
    (0.10, 0.20),
    (0.36, 0.14),
    (0.48, 0.10),
    (0.56, 0.08),
    (0.28, 0.12),
    (0.34, 0.12),
]


def analyze(wallpaper):
    """
    Extract the dominant usable hue and average wallpaper lightness.

    Small saturated regions are intentionally prevented from dominating by
    weighting hue families by occupied pixel area and saturation together.
    """
    out = subprocess.run(
        [
            "magick",
            wallpaper,
            "-alpha",
            "off",
            "-resize",
            "200x200",
            "-colors",
            "48",
            "-format",
            "%c",
            "histogram:info:-",
        ],
        capture_output=True,
        text=True,
        check=False,
    ).stdout

    buckets = {}
    total = 0
    lum = 0.0
    chroma = 0

    for line in out.splitlines():
        match = re.search(
            r"\s*(\d+):\s*\([^)]*\)\s*#([0-9A-Fa-f]{6})",
            line,
        )

        if not match:
            continue

        count = int(match.group(1))
        hex_str = match.group(2)

        r, g, b = (int(hex_str[index : index + 2], 16) / 255 for index in (0, 2, 4))

        hue, lightness, saturation = colorsys.rgb_to_hls(r, g, b)

        total += count
        lum += count * lightness

        if saturation < 0.15 or lightness < 0.05 or lightness > 0.92:
            continue

        chroma += count

        bucket = buckets.setdefault(
            (int(hue * 360) // 30) % 12,
            {
                "wsat": 0.0,
                "best": None,
            },
        )

        bucket["wsat"] += count * saturation

        score = count * saturation * (1 if 0.12 < lightness < 0.55 else 0.4)

        if not bucket["best"] or score > bucket["best"][0]:
            bucket["best"] = (
                score,
                hue,
                saturation,
            )

    mean_lightness = lum / total if total else 0.0

    if not buckets or chroma < 0.08 * total:
        return None, 0.0, mean_lightness

    winner = max(
        buckets.values(),
        key=lambda value: value["wsat"],
    )

    return (
        winner["best"][1],
        winner["best"][2],
        mean_lightness,
    )


def sample_pixels(image, size=16):
    """Decode a tiny grid of the image as 0..1 RGB triples."""
    out = subprocess.run(
        [
            "magick",
            image,
            "-alpha",
            "off",
            "-resize",
            f"{size}x{size}!",
            "-depth",
            "8",
            "rgb:-",
        ],
        capture_output=True,
        check=False,
    )
    raw = out.stdout
    return [
        (raw[index] / 255, raw[index + 1] / 255, raw[index + 2] / 255)
        for index in range(0, len(raw) - 2, 3)
    ]


def wallpaper_thumbnail(wallpaper):
    """
    Return a 128px copy of the wallpaper to feed matugen.

    `matugen image` spends almost all of its time quantising the full-size
    decode: a 1920x1080 photo takes ~1.4s, the same image at 128px takes ~0.04s
    and yields the same source colour. ImageMagick can make the thumbnail from
    the JPEG's embedded preview (`jpeg:size`) in under 0.1s, so this is the main
    reason a wallpaper switch now re-tints in a fraction of the old time.

    The copy is cached by path + mtime + size, so re-running for an option
    change does no image work at all. If ImageMagick is missing or the format is
    unreadable, the original wallpaper is used and matugen still works.
    """
    try:
        stat = Path(wallpaper).stat()
        key = hashlib.sha1(
            f"{wallpaper}|{stat.st_mtime_ns}|{stat.st_size}".encode()
        ).hexdigest()
        thumbs = CACHE / "thumbs"
        dest = thumbs / f"{key}.png"
        if dest.is_file() and dest.stat().st_size > 0:
            return str(dest)

        thumbs.mkdir(parents=True, exist_ok=True)
        made = subprocess.run(
            [
                "magick",
                "-define",
                "jpeg:size=256x256",
                wallpaper,
                "-alpha",
                "off",
                "-resize",
                "128x128!",
                str(dest),
            ],
            capture_output=True,
            check=False,
        )
        if made.returncode != 0 or not dest.is_file() or dest.stat().st_size == 0:
            dest.unlink(missing_ok=True)
            return wallpaper

        # Keep the cache bounded: wallpapers are cheap to re-thumb, and a
        # session that cycles through a large collection should not grow this
        # folder forever. 128 entries is several months of picks at ~35KB each.
        try:
            cached = sorted(
                thumbs.glob("*.png"), key=lambda path: path.stat().st_mtime
            )
            for stale in cached[:-128]:
                stale.unlink(missing_ok=True)
        except OSError:
            pass

        return str(dest) if dest.is_file() else wallpaper
    except OSError:
        return wallpaper


def smart_mode_variant(image):
    """
    Detect light/dark mode and scheme variant from the wallpaper.

    This mirrors caelestia's "smart" idea: the mean tone decides light or dark,
    and the spread of the opponent-colour axes decides how colourful the
    wallpaper is. A flat, near-grey image gets the neutral schemes; a colourful
    one gets tonal spot. Sampling a 16x16 grid is enough and stays under 20ms.
    Returns (mode, variant) where mode is "light" or "dark" and variant is one
    of the SCHEMES.
    """
    pixels = sample_pixels(image)
    if not pixels:
        return "dark", "tonal-spot"

    # Mean tone: HLS lightness is a close enough stand-in for an HCT tone.
    red = sum(pixel[0] for pixel in pixels) / len(pixels)
    green = sum(pixel[1] for pixel in pixels) / len(pixels)
    blue = sum(pixel[2] for pixel in pixels) / len(pixels)
    lightness = (max(red, green, blue) + min(red, green, blue)) / 2
    mode = "light" if lightness > 0.60 else "dark"

    # Caelestia's colourfulness metric: spread of red-green and yellow-blue,
    # plus a smaller vote for the mean chroma. A single averaged colour would
    # lose the spread and call every photo neutral, so use the whole grid.
    rg = [abs(r - g) for r, g, b in pixels]
    yb = [abs(0.5 * (r + g) - b) for r, g, b in pixels]

    def std(values):
        mean = sum(values) / len(values)
        return (sum((value - mean) ** 2 for value in values) / len(values)) ** 0.5

    def mean(values):
        return sum(values) / len(values)

    colourfulness = (
        (std(rg) ** 2 + std(yb) ** 2) ** 0.5
        + 0.3 * (mean(rg) ** 2 + mean(yb) ** 2) ** 0.5
    )

    if colourfulness < 0.02:
        variant = "neutral"
    elif colourfulness < 0.05:
        variant = "content"
    else:
        variant = "tonal-spot"

    return mode, variant


def matugen(source_hex):
    """
    Generate the terminal palette through matugen.

    The terminal remains dark-mode oriented while the pill palette is generated
    independently from the wallpaper analysis above.
    """
    out = subprocess.run(
        [
            "matugen",
            "color",
            "hex",
            source_hex,
            "-m",
            "dark",
            "-j",
            "hex",
        ],
        capture_output=True,
        text=True,
        check=True,
    )

    return json.loads(out.stdout)


def tint(hue, saturation, lightness):
    """
    Convert an HSL colour into a hexadecimal RGB string.
    """
    r, g, b = colorsys.hls_to_rgb(
        hue % 1.0,
        max(0.0, min(1.0, lightness)),
        max(0.0, min(1.0, saturation)),
    )

    return "#%02x%02x%02x" % (
        round(r * 255),
        round(g * 255),
        round(b * 255),
    )


def lerp(value, start, end, low, high):
    """
    Linear interpolation with clamped input.
    """
    amount = max(
        0.0,
        min(
            1.0,
            (value - start) / (end - start),
        ),
    )

    return low + amount * (high - low)


def hex_rgb(value):
    """`#rrggbb` to three 0..1 floats."""
    return tuple(int(value[index : index + 2], 16) / 255 for index in (1, 3, 5))


def mix_hex(first, second, amount):
    """Blend two hex colours; `amount` 0 is the first, 1 the second."""
    a = hex_rgb(first)
    b = hex_rgb(second)
    rgb = tuple(x + (y - x) * amount for x, y in zip(a, b))
    return "#%02x%02x%02x" % tuple(round(channel * 255) for channel in rgb)


def is_light(hex_color):
    """Relative luminance, good enough to tell a Material light scheme apart."""
    r, g, b = hex_rgb(hex_color)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.5


def write_atomic(path, text):
    """
    Replace a file in one step.

    The shell and the settings app both watch `colors.json` and re-read it on
    every change. A plain `write_text` truncates first, so a watcher can land
    between the truncate and the write and read an empty or half-written
    document — which is exactly the sort of intermittent "the theme did not
    change" glitch that is hard to reproduce. A sibling temp file plus
    `os.replace` is atomic on the same filesystem, so a reader sees either the
    old document or the new one.
    """
    path = Path(path)
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def matugen_image(wallpaper, flags):
    """Run matugen's image extractor with the Dynamic options from the flags."""
    scheme = flags.get("dynamicScheme", "tonal-spot")
    if scheme not in SCHEMES:
        scheme = "tonal-spot"

    try:
        contrast = float(flags.get("dynamicContrast", 0) or 0)
    except (TypeError, ValueError):
        contrast = 0.0
    contrast = max(-1.0, min(1.0, contrast))

    mode = flags.get("dynamicMode", "auto")
    mode = "smart" if mode not in ("light", "dark") else mode

    prefer = flags.get("dynamicPrefer", "saturation")
    if prefer not in PREFERS:
        prefer = "saturation"

    out = subprocess.run(
        [
            "matugen",
            "image",
            wallpaper,
            "--type",
            f"scheme-{scheme}",
            "--contrast",
            f"{contrast:g}",
            "--mode",
            mode,
            "--prefer",
            prefer,
            "--json",
            "hex",
        ],
        capture_output=True,
        text=True,
        check=True,
    )

    data = json.loads(out.stdout)
    colors = {
        key: value["default"]["color"]
        for key, value in data["colors"].items()
        if "default" in value
    }
    return colors


def hsl_to_rgb_hex(h, s, l):
    """Convert HSL (hue 0..1, sat 0..1, light 0..1) to #rrggbb."""
    r, g, b = colorsys.hls_to_rgb(h % 1.0, max(0.0, min(1.0, l)), max(0.0, min(1.0, s)))
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def vague_style_transform(colors, light_mode):
    """
    Apply vague.nvim-inspired styling to a Material 3 palette.

    Vague characteristics:
    - Hue shifted toward blue-grey (~240° / 0.66)
    - Chroma heavily reduced (muted)
    - Surfaces are cool greys, not warm
    - Primary is desaturated, not vivid
    - Text is vague's `text` (#c8c6d1) / `subtext1` (#b8b6c6) tones
    """
    # Vague's anchor hue (blue-grey)
    VAGUE_HUE = 0.66  # ~240°
    VAGUE_CHROMA_MULT = 0.35  # heavily desaturate

    def desaturate_toward_vague(hex_color, chroma_mult=VAGUE_CHROMA_MULT, hue_shift=VAGUE_HUE):
        r, g, b = hex_rgb(hex_color)
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        # Shift hue toward vague's blue-grey, reduce chroma
        new_h = h + (hue_shift - h) * 0.6
        new_s = s * chroma_mult
        return hsl_to_rgb_hex(new_h, new_s, l)

    # Transform key roles
    vague_primary = desaturate_toward_vague(colors["primary"], 0.45, VAGUE_HUE)
    vague_secondary = desaturate_toward_vague(colors["secondary"], 0.4, VAGUE_HUE)
    vague_tertiary = desaturate_toward_vague(colors["tertiary"], 0.35, VAGUE_HUE)

    # Surfaces: cool greys with vague's blue tint
    def cool_surface(hex_color, light_mode):
        r, g, b = hex_rgb(hex_color)
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        # Shift toward blue-grey, very low chroma
        new_h = VAGUE_HUE
        new_s = min(s * 0.15, 0.08)
        return hsl_to_rgb_hex(new_h, new_s, l)

    vague_surface = cool_surface(colors["surface"], light_mode)
    vague_surface_low = cool_surface(colors["surface_container_low"], light_mode)
    vague_surface_container = cool_surface(colors["surface_container"], light_mode)
    vague_surface_high = cool_surface(colors["surface_container_high"], light_mode)
    vague_surface_highest = cool_surface(colors["surface_container_highest"], light_mode)

    # Text: vague's text/subtext tones (cool grey-blue)
    vague_on_surface = "#c8c6d1" if not light_mode else "#2d2b3d"
    vague_on_surface_variant = "#b8b6c6" if not light_mode else "#5d5b6d"

    # Outline: vague's `comment` / `inactive` tones
    vague_outline = "#606079" if not light_mode else "#a0a0b8"
    vague_outline_variant = "#4a4a5e" if not light_mode else "#78788c"

    # Primary container: desaturated primary with vague tint
    pc_r, pc_g, pc_b = hex_rgb(colors["primary_container"])
    pc_h, pc_l, pc_s = colorsys.rgb_to_hls(pc_r, pc_g, pc_b)
    vague_primary_container = hsl_to_rgb_hex(VAGUE_HUE, pc_s * 0.4, pc_l)

    def cool_container(key, chroma_mult=0.4):
        r, g, b = hex_rgb(colors[key])
        _, l, s = colorsys.rgb_to_hls(r, g, b)
        return hsl_to_rgb_hex(VAGUE_HUE, s * chroma_mult, l)

    vague_secondary_container = cool_container("secondary_container")
    vague_tertiary_container = cool_container("tertiary_container")

    # On primary container: vague text tone
    vague_on_primary_container = "#c8c6d1" if not light_mode else "#2d2b3d"

    return {
        "surface": vague_surface,
        "surface_container_low": vague_surface_low,
        "surface_container": vague_surface_container,
        "surface_container_high": vague_surface_high,
        "surface_container_highest": vague_surface_highest,
        "primary": vague_primary,
        "primary_container": vague_primary_container,
        "secondary_container": vague_secondary_container,
        "tertiary_container": vague_tertiary_container,
        "on_primary_container": vague_on_primary_container,
        "outline": vague_outline,
        "outline_variant": vague_outline_variant,
        "cream": vague_on_surface,
        "bright": "#e0dff0" if not light_mode else "#181628",
        "subtle": "#b8b6c6" if not light_mode else "#686678",
        "dim": vague_on_surface_variant,
        "faint": "#8a8896" if not light_mode else "#787688",
        "icon_dim": vague_on_surface_variant,
        "tick_rest": "#b8b6c6" if not light_mode else "#585668",
        "light": light_mode,
        "on_surface": vague_on_surface,
        "on_surface_variant": vague_on_surface_variant,
        "on_primary": "#c8c6d1" if not light_mode else "#2d2b3d",
        "secondary": vague_secondary,
        "tertiary": vague_tertiary,
    }


CONTAINER_KEYS = [
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
    "primary_container",
    "secondary_container",
    "tertiary_container",
]

# Which Material 3 role becomes the shell's base `surface`. The neutral roles
# are the M3 elevation ramp; the container roles are the tinted ones, which is
# what makes this a palette choice rather than just another theme.
SURFACE_ROLES = {
    "default": "surface",
    "surface": "surface",
    "surface_container_low": "surface_container_low",
    "surface_container": "surface_container",
    "surface_container_high": "surface_container_high",
    "surface_container_highest": "surface_container_highest",
    "primary_container": "primary_container",
    "secondary_container": "secondary_container",
    "tertiary_container": "tertiary_container",
}


def hex_hls(hex_color):
    """`#rrggbb` to (hue, lightness, saturation) in 0..1."""
    return colorsys.rgb_to_hls(*hex_rgb(hex_color))


def with_lightness(hex_color, lightness):
    """Keep a colour's hue and saturation, replace its lightness."""
    hue, _, saturation = hex_hls(hex_color)
    return hsl_to_rgb_hex(hue, saturation, max(0.02, min(0.98, lightness)))


def scale_saturation(hex_color, amount):
    """Multiply a colour's HSL saturation, clamped to a legal value."""
    hue, lightness, saturation = hex_hls(hex_color)
    return hsl_to_rgb_hex(hue, max(0.0, min(1.0, saturation * amount)), lightness)


def relative_luminance(hex_color):
    """WCAG relative luminance, for contrast checks on generated roles."""
    channels = []
    for channel in hex_rgb(hex_color):
        channels.append(
            channel / 12.92
            if channel <= 0.03928
            else ((channel + 0.055) / 1.055) ** 2.4
        )
    r, g, b = channels
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(first, second):
    """WCAG contrast ratio between two hex colours."""
    a = relative_luminance(first)
    b = relative_luminance(second)
    light, dark = (a, b) if a >= b else (b, a)
    return (light + 0.05) / (dark + 0.05)


def best_extreme(backgrounds):
    """
    Black or white, whichever reads better on every one of `backgrounds`.

    The obvious `luminance > 0.5 ? black : white` test fails in the mid-tones:
    #7e7e7e is "dark" by that test, but white on it is only 4.1:1 while black
    is 5.2:1. A material surface role can easily land there, so compare the
    ratios instead of guessing from the tone.
    """
    def worst(ink):
        return min(contrast_ratio(ink, background) for background in backgrounds)

    return "#000000" if worst("#000000") >= worst("#ffffff") else "#ffffff"


def retone_text(palette, ink, base):
    """Rebuild the text ramp from `ink` so it reads on the chosen base surface."""
    extreme = best_extreme((base,))
    palette["cream"] = ink
    palette["on_surface"] = ink
    palette["bright"] = mix_hex(ink, extreme, 0.32)
    palette["subtle"] = mix_hex(ink, base, 0.38)
    palette["dim"] = mix_hex(ink, base, 0.58)
    palette["faint"] = mix_hex(ink, base, 0.72)
    palette["icon_dim"] = palette["subtle"]
    palette["tick_rest"] = palette["subtle"]


def material_palette(colors, flags=None):
    """Map a Material 3 role set onto the keys the shell and app already read."""
    flags = flags or {}
    surface = colors["surface"]
    on_surface = colors["on_surface"]
    on_surface_variant = colors["on_surface_variant"]
    light_mode = is_light(surface)

    # Get the raw Material 3 mapping first
    raw = {
        "surface": surface,
        "surface_container_low": colors["surface_container_low"],
        "surface_container": colors["surface_container"],
        "surface_container_high": colors["surface_container_high"],
        "surface_container_highest": colors["surface_container_highest"],
        "primary": colors["primary"],
        "primary_container": colors["primary_container"],
        "secondary_container": colors["secondary_container"],
        "tertiary_container": colors["tertiary_container"],
        "on_primary_container": colors["on_primary_container"],
        "outline": colors["outline"],
        "outline_variant": colors["outline_variant"],
        "cream": on_surface,
        "bright": mix_hex(on_surface, "#ffffff" if not light_mode else "#000000", 0.32),
        "subtle": mix_hex(on_surface, on_surface_variant, 0.50),
        "dim": on_surface_variant,
        "faint": mix_hex(on_surface_variant, surface, 0.42),
        "icon_dim": on_surface_variant,
        "tick_rest": on_surface_variant,
        "light": light_mode,
        "on_surface": on_surface,
        "on_surface_variant": on_surface_variant,
        "on_primary": colors["on_primary"],
        "secondary": colors["secondary"],
        "tertiary": colors["tertiary"],
    }

    # Apply vague-style transformation to make it feel like our shell
    vague = vague_style_transform(colors, light_mode)

    # Blend: 70% vague style, 30% raw Material — keeps wallpaper personality but
    # guarantees the shell's signature muted blue-grey character
    def blend_raw_vague(key):
        if key not in vague:
            return raw[key]
        # Skip boolean 'light' key
        if key == "light":
            return raw[key]
        return mix_hex(raw[key], vague[key], 0.7)

    palette = {k: blend_raw_vague(k) for k in raw}

    # Container saturation: the one slider that walks from flat greys (0) back
    # to Material's own tint (2). Only the container roles move; the base
    # surface and the accent keep their vague character.
    try:
        container_saturation = float(flags.get("containerSaturation", 1) or 0)
    except (TypeError, ValueError):
        container_saturation = 1.0
    container_saturation = max(0.0, min(2.0, container_saturation))
    if abs(container_saturation - 1.0) > 0.001:
        for key in CONTAINER_KEYS:
            palette[key] = scale_saturation(palette[key], container_saturation)

    # Surface role: re-centre the elevation ramp on whichever M3 role the user
    # picked. The other surfaces keep their original distance from the base, so
    # cards and capsules stay one or two steps above the window instead of
    # collapsing onto it.
    role = flags.get("surfaceRole", "default") or "default"
    role_key = SURFACE_ROLES.get(role, "surface")
    base = palette[role_key]

    if role_key != "surface":
        base_lightness = hex_hls(base)[1]
        deltas = {
            key: hex_hls(palette[key])[1] - hex_hls(palette["surface"])[1]
            for key in (
                "surface_container_low",
                "surface_container",
                "surface_container_high",
                "surface_container_highest",
            )
        }
        palette["surface"] = base
        for key, delta in deltas.items():
            palette[key] = with_lightness(base, base_lightness + delta)

        # A container role can land in the mid-tones, where a wide elevation
        # ramp has no ink that clears 4.5:1 on *every* step — #6c6c6c to #828282
        # needs text lighter than white and darker than black at once. Tighten
        # the ramp until the best ink clears it. Collapsing to the base always
        # works (every tone supports at least ~4.58:1 with black or white), so
        # this terminates; in practice one halving is enough.
        scale = 1.0
        for _ in range(4):
            ramp = (
                palette["surface"],
                palette["surface_container_low"],
                palette["surface_container"],
                palette["surface_container_high"],
                palette["surface_container_highest"],
            )
            ink = best_extreme(ramp)
            if min(contrast_ratio(ink, bg) for bg in ramp) >= 4.5:
                break
            scale *= 0.5
            for key, delta in deltas.items():
                palette[key] = with_lightness(base, base_lightness + delta * scale)

        # Coloured containers are not neutral, so on_surface is no longer the
        # right ink; neutral roles can still drift low-contrast at the ends of
        # the ramp. Use the role's own on-container ink for the tinted roles,
        # and fall back to black/white only when a neutral role would otherwise
        # put light ink on a light surface (or the reverse).
        if role_key in ("primary_container", "secondary_container", "tertiary_container"):
            ink = colors.get(f"on_{role_key}") or (
                "#1c1b1f" if is_light(base) else "#e6e1e5"
            )
            retone_text(palette, ink, base)
        elif contrast_ratio(palette["cream"], base) < 4.5:
            ink = "#151317" if is_light(base) else "#f7f4f8"
            retone_text(palette, ink, base)

        palette["light"] = is_light(base)

    # The on-* inks are designed for matugen's own fills, but the roles we paint
    # them over are blended 70% toward the vague palette and may be re-toned for
    # the surface role, which can leave an ink almost the same tone as its fill —
    # the app's lit chips and the toggle knobs are the visible cases.
    def walk_ink(ink, backgrounds, target):
        """Step `ink` toward black or white until it clears `target` on all backgrounds."""
        if all(contrast_ratio(ink, bg) >= target for bg in backgrounds):
            return ink
        extreme = best_extreme(backgrounds)
        for amount in (0.12, 0.24, 0.36, 0.48, 0.6, 0.75, 0.9, 1.0):
            candidate = mix_hex(ink, extreme, amount)
            if all(contrast_ratio(candidate, bg) >= target for bg in backgrounds):
                return candidate
        return extreme

    ramp = (
        palette["surface_container_low"],
        palette["surface"],
        palette["surface_container_high"],
        palette["surface_container_highest"],
    )

    # The accent is text and icons in the shell, and a fill under on_primary in
    # the app. Move its tone (same hue) until it reads on every surface step,
    # then re-derive the ink that sits on it — otherwise a coloured surface role
    # can put primary at 1.1:1 against its own window.
    palette["primary"] = walk_ink(palette["primary"], ramp, 3.0)
    for fill_key, ink_key in (
        ("primary", "on_primary"),
        ("primary_container", "on_primary_container"),
    ):
        palette[ink_key] = walk_ink(palette[ink_key], (palette[fill_key],), 4.5)

    # Text: the app prints body copy straight from the two on-surface inks on a
    # card, and the shell uses the ramp below for main/secondary/tertiary copy.
    # Material budgets 4.5 against `surface`, not against every elevated step, so
    # walk each ink until it reads on the whole ramp. `faint` is decorative and
    # `tick_rest` is a 1px mark, so those settle for a lower bar.
    targets = {
        "on_surface": 4.5,
        "on_surface_variant": 4.5,
        "cream": 4.5,
        "bright": 4.5,
        "subtle": 4.5,
        "dim": 4.5,
        "icon_dim": 3.5,
        "tick_rest": 3.5,
        "faint": 3.0,
    }
    for key, target in targets.items():
        palette[key] = walk_ink(palette[key], ramp, target)

    return palette


def render_fastfetch(pill):
    """
    Recolour the fastfetch readout from the same pill palette.

    fastfetch has no daemon, so writing the rendered configuration is enough;
    the next invocation automatically picks up the updated colours.

    The accent drives keys and the torii logo, the surface ramp drives the
    lantern body, and muted text tones drive separators and supporting details.
    This keeps fastfetch visually synchronized with the wallpaper, pill, and
    terminal palette.
    """
    fastfetch_dir = Path.home() / ".config" / "fastfetch"
    template = fastfetch_dir / "config.jsonc.in"

    if not template.is_file():
        print(
            "wallcolors: config.jsonc.in missing in ~/.config/fastfetch, "
            "skipping fastfetch recolour (re-run the installer)",
            file=sys.stderr,
        )
        return

    def ansi_rgb(hex_color):
        return "%d;%d;%d" % tuple(
            int(hex_color[index : index + 2], 16) for index in (1, 3, 5)
        )

    replacements = {
        "__LANTERN__": str(fastfetch_dir / "lantern.txt"),
        "__KEYS__": ansi_rgb(pill["primary"]),
        "__SEP__": ansi_rgb(pill["dim"]),
        "__LOGO1__": ansi_rgb(pill["primary"]),
        "__LOGO2__": ansi_rgb(pill["on_primary_container"]),
        "__LOGO3__": ansi_rgb(pill["surface_container"]),
        "__LOGO4__": ansi_rgb(pill["surface_container_high"]),
        "__LOGO5__": ansi_rgb(pill["subtle"]),
        "__LOGO6__": ansi_rgb(pill["outline"]),
        "__LOGO7__": ansi_rgb(pill["bright"]),
    }

    output = template.read_text()

    for key, value in replacements.items():
        output = output.replace(key, value)

    write_atomic(fastfetch_dir / "config.jsonc", output)


def hsl_palette(hue, saturation, mean_lightness):
    """The pre-Material ramp, kept for manual mode and as a generator fallback."""
    chromatic = saturation > 0.02
    light_mode = mean_lightness >= 0.40

    surface_saturation = (
        min(saturation, 0.26)
        if light_mode
        else min(
            max(
                saturation,
                0.30 if chromatic else 0.0,
            ),
            0.45,
        )
    )

    accent_saturation = (
        (
            min(saturation + 0.18, 0.85)
            if light_mode
            else min(
                max(saturation, 0.30) + 0.12,
                0.82,
            )
        )
        if chromatic
        else 0.05
    )

    if light_mode:
        base = lerp(
            mean_lightness,
            0.40,
            0.66,
            0.80,
            0.93,
        )

        steps = LIGHT_STEPS
        text = LIGHT_TEXT
        accent_lightness = 0.42
        deep_lightness = 0.30
        glow_lightness = 0.55

    else:
        base = lerp(
            mean_lightness,
            0.0,
            0.40,
            0.045,
            0.20,
        )

        steps = DARK_STEPS
        text = DARK_TEXT
        accent_lightness = 0.70
        deep_lightness = 0.34
        glow_lightness = 0.86

    pill = {
        name: tint(
            hue,
            surface_saturation,
            base + step,
        )
        for name, step in zip(SURF_NAMES, steps)
    }

    pill["primary"] = tint(
        hue,
        accent_saturation,
        accent_lightness,
    )

    pill["primary_container"] = tint(
        hue,
        min(accent_saturation + 0.08, 0.9),
        deep_lightness,
    )

    pill["on_primary_container"] = tint(
        hue,
        min(accent_saturation, 0.45),
        glow_lightness,
    )

    pill["outline"] = tint(
        hue,
        surface_saturation,
        base + (-0.35 if light_mode else 0.35),
    )

    for key, (lightness, saturation) in zip(TEXT_KEYS, text):
        pill[key] = tint(
            hue,
            saturation,
            lightness,
        )

    pill["light"] = light_mode
    return pill


def main():
    """
    Generate all colour consumers from either a wallpaper or a manual hue.
    """

    if len(sys.argv) < 2:
        return 1

    if sys.argv[1] == "--hue":
        hue = (float(sys.argv[2]) % 360) / 360.0
        mode = sys.argv[3] if len(sys.argv) > 3 else "dark"
        saturation = float(sys.argv[4]) if len(sys.argv) > 4 else 0.5

        saturation = max(
            0.0,
            min(1.0, saturation),
        )

        mean_lightness = 0.85 if mode == "light" else 0.12
        pill = hsl_palette(hue, saturation, mean_lightness)
        source_hex = tint(
            hue,
            saturation,
            0.45,
        ) if saturation > 0.02 else "#787878"

    else:
        wallpaper = sys.argv[1]

        if not Path(wallpaper).is_file():
            return 0

        flags = read_flags()

        # Accented keeps the selected static scheme's surfaces and text and
        # takes only the accent tokens from the generated palette. Both static
        # schemes are dark, so ask matugen for the dark-scheme accent whatever
        # the Appearance option says: a light-scheme accent is a dark colour
        # that would disappear on those surfaces. The surface role is pinned to
        # the neutral default for the same reason — its ramp is not painted
        # here, and a colour role chosen for Dynamic would otherwise re-tone the
        # accent against a surface nobody sees.
        if flags.get("paletteMode") == "accented":
            flags["dynamicMode"] = "dark"
            flags["surfaceRole"] = "default"

        image = wallpaper_thumbnail(wallpaper)

        # Smart variant: only the scheme needs deciding here. DynamicMode
        # "auto" is handed to matugen as `smart`, which already picks light or
        # dark from the wallpaper; overriding it here would duplicate that.
        if flags.get("dynamicScheme") == "auto":
            _, variant = smart_mode_variant(image)
            flags["dynamicScheme"] = variant

        try:
            colors = matugen_image(image, flags)
            pill = material_palette(colors, flags)
            source_hex = colors.get("source_color", pill["primary"])
        except (
            OSError,
            ValueError,
            KeyError,
            subprocess.SubprocessError,
        ):
            # matugen missing or the image unreadable: keep the shell usable
            # with the ramp it painted before Material You was an option.
            hue, saturation, mean_lightness = analyze(wallpaper)
            if hue is None:
                hue, saturation = 0.09, 0.0
            if flags.get("paletteMode") == "accented":
                # Same reasoning as the matugen override above: the accent is
                # painted on a dark static scheme, so the fallback has to be a
                # dark-scheme ramp too.
                mean_lightness = 0.12
            pill = hsl_palette(hue, saturation, mean_lightness)
            source_hex = tint(
                hue,
                saturation,
                0.45,
            ) if saturation > 0.02 else "#787878"

    CACHE.mkdir(
        parents=True,
        exist_ok=True,
    )

    write_atomic(
        CACHE / "colors.json",
        json.dumps(
            pill,
            indent=2,
        )
        + "\n",
    )

    render_fastfetch(pill)

    try:
        base16 = matugen(source_hex)["base16"]

        terminal_colors = {key: value["dark"]["color"] for key, value in base16.items()}

    except (
        OSError,
        ValueError,
        KeyError,
        subprocess.SubprocessError,
    ):
        return 0

    kitty = [
        f"background {terminal_colors['base00']}",
        f"foreground {terminal_colors['base07']}",
        f"cursor {pill['primary']}",
        f"cursor_text_color {terminal_colors['base00']}",
        f"selection_background {terminal_colors['base02']}",
        f"selection_foreground {terminal_colors['base07']}",
    ]

    # base16 -> ANSI: 0-7 are black/red/green/yellow/blue/magenta/cyan/white on
    # the scheme hues; 8-15 repeat them with base03 (comments) as bright black
    # and base07 as bright white, matching kitty's 16-slot color0..15 palette.
    # matugen base16 JSON keys are lowercase hex (base0b, base0a, ...);
    # keep the letters lowercase so the lookups match.
    ansi_keys = (
        "00",
        "08",
        "0b",
        "0a",
        "0d",
        "0e",
        "0c",
        "05",
        "03",
        "08",
        "0b",
        "0a",
        "0d",
        "0e",
        "0c",
        "07",
    )
    for index, key in enumerate(ansi_keys):
        kitty.append(f"color{index} {terminal_colors[f'base{key}']}")

    write_atomic(CACHE / "kitty-colors", "\n".join(kitty) + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
