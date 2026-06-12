# Regenerates public/assets/material-symbols-subset.woff2 with only the icon
# glyphs the site uses. Run from web/ after adding or removing an icon:
#
#   uvx --from "fonttools[woff]" --with brotli python3 scripts/subset-icons.py
#
# Icon names are collected from two source patterns:
#   1. literal text inside <span class="material-symbols-outlined">name</span>
#   2. icon: "name" data fields rendered into such spans
# If you add icons through a different pattern, extend the regexes below.
import re
import sys
from pathlib import Path

from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont

WEB = Path(__file__).resolve().parent.parent
SOURCE_FONT = WEB / "node_modules/material-symbols/material-symbols-outlined.woff2"
OUTPUT = WEB / "public/assets/material-symbols-subset.woff2"

TEXT_NODE = re.compile(
    r'material-symbols-outlined[^>]*>\s*\{?"?([a-z_0-9]+)"?\}?\s*<', re.S
)
ICON_FIELD = re.compile(r'\bicon:\s*"([a-z_0-9]+)"')

names: set[str] = set()
for path in WEB.glob("src/**/*"):
    if path.suffix not in {".astro", ".tsx", ".ts"}:
        continue
    text = path.read_text()
    names.update(TEXT_NODE.findall(text))
    names.update(ICON_FIELD.findall(text))

font = TTFont(SOURCE_FONT)
glyph_set = set(font.getGlyphOrder())
missing = sorted(n for n in names if n not in glyph_set)
if missing:
    sys.exit(f"icon names with no glyph in Material Symbols: {missing}")

opts = Options()
opts.layout_features = ["rlig", "rclt"]
opts.layout_closure = False
opts.flavor = "woff2"
subsetter = Subsetter(options=opts)
subsetter.populate(text="".join(sorted(set("".join(names)))), glyphs=sorted(names))
subsetter.subset(font)
font.save(OUTPUT)
print(f"{len(names)} icons -> {OUTPUT.name} ({OUTPUT.stat().st_size:,} bytes)")
