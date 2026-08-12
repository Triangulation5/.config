#!/usr/bin/env python3
"""
Generate emojis.js from the system's emoji data (emoji.json.gz from
ibus-typing-booster). Run after system package updates to refresh
the launcher's emoji picker with the latest Unicode set.

Output: utils/launcher/emojis.js — a JS array of {e, n} objects.
"""

import gzip, json, sys, os

EMOJI_JSON = "/usr/share/ibus-typing-booster/data/emoji.json.gz"
OUT_FILE = os.path.join(os.path.dirname(__file__), "emojis.js")

def main():
    if not os.path.exists(EMOJI_JSON):
        print(f"Error: emoji data not found at {EMOJI_JSON}", file=sys.stderr)
        print("Install ibus-typing-booster or provide emoji.json.gz", file=sys.stderr)
        sys.exit(1)

    with gzip.open(EMOJI_JSON, "rt", encoding="utf-8") as f:
        raw = json.load(f)

    entries = []
    for cp_hex, meta in raw.items():
        try:
            code = int(cp_hex, 16)
            emoji = chr(code)
        except (ValueError, OverflowError):
            continue
        name = meta.get("name", "").strip().lower()
        if not name:
            continue
        entries.append({ "e": emoji, "n": name })

    entries.sort(key=lambda x: x["n"])

    with open(OUT_FILE, "w", encoding="utf-8") as f:
        f.write("/**\n")
        f.write(f" * System emoji database — generated from {EMOJI_JSON}\n")
        f.write(f" * {len(entries)} emojis. Re-run utils/launcher/gen_emojis.py to refresh.\n")
        f.write(" */\n")
        f.write("var Emojis = [\n")
        for i, entry in enumerate(entries):
            comma = "," if i < len(entries) - 1 else ""
            f.write(f'    {{ e: "{entry["e"]}", n: "{entry["n"]}" }}{comma}\n')
        f.write("];\n")

    print(f"Generated {OUT_FILE} with {len(entries)} emojis")

if __name__ == "__main__":
    main()
