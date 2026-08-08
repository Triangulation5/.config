#!/usr/bin/env python3

"""
Generate the rice colour set from a wallpaper and fan it out to the consumers.

One histogram pass yields both the area-dominant chromatic hue, grouped by hue
family so a small vivid accent cannot hijack the entire theme, and the mean
lightness of the wallpaper.

The mean lightness drives the pill's complete tonal direction:
- bright wallpapers produce lighter surfaces with darker text
- dark or OLED-black wallpapers produce near-black surfaces with cream text

Surfaces and text are adjusted together so contrast remains stable across the
entire brightness range. The dominant hue is applied through HSL to every
surface tier. Achromatic wallpapers fall back to a neutral grey ramp.

matugen still generates the dark base16 palette consumed by always-dark
terminals. The pill JSON owns surfaces, accents, and contrast-matched text.
"""

import colorsys
import json
import re
import subprocess
import sys
from pathlib import Path

CACHE = Path.home() / ".cache" / "ricelin"


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
            "skipping fastfetch recolour "
            "(apply the Ricelin update or re-run the installer)",
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

    (fastfetch_dir / "config.jsonc").write_text(output)


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
        chromatic = saturation > 0.02

    else:
        wallpaper = sys.argv[1]

        if not Path(wallpaper).is_file():
            return 0

        hue, saturation, mean_lightness = analyze(wallpaper)

        chromatic = hue is not None

        if not chromatic:
            hue = 0.09
            saturation = 0.0

    CACHE.mkdir(
        parents=True,
        exist_ok=True,
    )

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

    (CACHE / "colors.json").write_text(
        json.dumps(
            pill,
            indent=2,
        )
        + "\n"
    )

    render_fastfetch(pill)

    try:
        base16 = matugen(
            tint(
                hue,
                saturation,
                0.45,
            )
            if chromatic
            else "#787878"
        )["base16"]

        terminal_colors = {key: value["dark"]["color"] for key, value in base16.items()}

    except (
        OSError,
        ValueError,
        KeyError,
        subprocess.SubprocessError,
    ):
        return 0

    (CACHE / "hypr-colors.lua").write_text(
        "return {\n"
        '    active = "%s",\n'
        '    inactive = "%s",\n'
        "}\n"
        % (
            pill["primary"],
            terminal_colors["base01"],
        )
    )

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
    ansi_keys = ("00", "08", "0b", "0a", "0d", "0e", "0c", "05", "03", "08", "0b", "0a", "0d", "0e", "0c", "07")
    for index, key in enumerate(ansi_keys):
        kitty.append(f"color{index} {terminal_colors[f'base{key}']}")

    (CACHE / "kitty-colors").write_text("\n".join(kitty) + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
