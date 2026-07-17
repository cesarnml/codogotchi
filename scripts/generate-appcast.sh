#!/usr/bin/env bash
set -euo pipefail

# Adds the just-built, notarized DMG (scripts/package-dmg.sh's output) to the
# Sparkle appcast feed and stages the updated feed for the website.
#
# The signed archive of every released DMG lives OUTSIDE the repo at
# ~/.codogotchi-release-archive/ — `builds/` is gitignored and gets wiped
# between machines/CI runs, but `generate_appcast` needs every past release
# present to keep emitting full update history (older clients update through
# intermediate versions). Back this directory up; losing it doesn't break
# updates for anyone already current, but it can't be reconstructed for future
# appcast regeneration without re-signing every historical DMG.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG_SRC="$REPO_ROOT/builds/Codogotchi.dmg"
ARCHIVE_DIR="$HOME/.codogotchi-release-archive"
SPARKLE_BIN="$HOME/.sparkle/bin"

[[ -f "$DMG_SRC" ]] || {
  echo "ERROR: $DMG_SRC not found — run scripts/package-dmg.sh first." >&2
  exit 1
}
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || {
  echo "ERROR: $SPARKLE_BIN/generate_appcast not found." >&2
  echo "       Download+extract a Sparkle release tarball's bin/ into $SPARKLE_BIN." >&2
  exit 1
}

mkdir -p "$ARCHIVE_DIR"

APP_PATH=$(find "$REPO_ROOT/build/DerivedData" -name "Codogotchi.app" -path "*/Release/*" | head -1)
[[ -n "$APP_PATH" ]] || {
  echo "ERROR: could not find the built Codogotchi.app to read its version." >&2
  exit 1
}
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")

DMG_DEST="$ARCHIVE_DIR/Codogotchi-$VERSION.dmg"
cp "$DMG_SRC" "$DMG_DEST"
echo "==> Archived $DMG_DEST"

echo "==> Regenerating appcast from $ARCHIVE_DIR..."
"$SPARKLE_BIN/generate_appcast" "$ARCHIVE_DIR"

# generate_appcast's --download-url-prefix is one flat URL applied to every
# item, but each release actually lives at a per-tag GitHub Releases URL
# (scripts/package-dmg.sh's ritual: `gh release create vX.Y.Z Codogotchi.dmg`
# — same asset filename every time, version only in the tag path). Rewrite
# each item's enclosure URL from its own sparkle:shortVersionString instead of
# trusting the tool's single guessed prefix, so multi-version history stays
# correct as more releases accumulate in the archive.
APPCAST_OUT="$REPO_ROOT/web/public/appcast.xml"
python3 - "$ARCHIVE_DIR/appcast.xml" "$APPCAST_OUT" <<'PY'
import re
import sys

src, dst = sys.argv[1:3]
with open(src) as f:
    xml = f.read()


def fix_url(match):
    item = match.group(0)
    version = re.search(r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>", item).group(1)
    new_url = f"https://github.com/cesarnml/codogotchi/releases/download/v{version}/Codogotchi.dmg"
    return re.sub(r'url="[^"]*"', f'url="{new_url}"', item)


xml = re.sub(r"<item>.*?</item>", fix_url, xml, flags=re.DOTALL)
with open(dst, "w") as f:
    f.write(xml)
PY
echo "==> Staged $APPCAST_OUT"
echo ""
echo "Commit + push web/public/appcast.xml so it deploys at https://codogotchi.app/appcast.xml"
