#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/apps/menubar/Codogotchi.xcodeproj"
DMG_OUT="$REPO_ROOT/builds/Codogotchi.dmg"

# Stage OUTSIDE the repo tree. The staging dir contains an `Applications ->
# /Applications` symlink for the drag-to-install layout; if it lives inside the
# repo, `bun test`'s root-CWD scan follows it into /Applications and exhausts
# file descriptors (EMFILE), breaking the whole test suite. A temp dir keeps the
# symlink off the scanned tree, and the trap removes it even on failure.
BUILD_DIR="$(mktemp -d -t codogotchi-dmg-staging)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "==> Building Codogotchi (Release)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme Codogotchi \
  -configuration Release \
  -derivedDataPath "$REPO_ROOT/build/DerivedData" \
  ONLY_ACTIVE_ARCH=YES \
  build

APP_PATH=$(find "$REPO_ROOT/build/DerivedData" -name "Codogotchi.app" -path "*/Release/*" | head -1)
if [[ -z "$APP_PATH" ]]; then
  echo "ERROR: could not find Release Codogotchi.app" >&2
  exit 1
fi
echo "==> Built: $APP_PATH"

echo "==> Staging DMG contents in ${BUILD_DIR}..."
cp -R "$APP_PATH" "$BUILD_DIR/Codogotchi.app"

# Dev-tool droppings (e.g. Antigravity's .antigravitycli symlink farm) can ride
# along from the checkout into bundled folder references like Resources/maew.
# Broken symlinks inside the bundle make users' `xattr -cr` error out.
find "$BUILD_DIR/Codogotchi.app" -name ".antigravitycli" -prune -exec rm -rf {} +
DANGLING=$(find "$BUILD_DIR/Codogotchi.app" -type l ! -exec test -e {} \; -print)
if [[ -n "$DANGLING" ]]; then
  echo "ERROR: broken symlinks in staged app bundle:" >&2
  echo "$DANGLING" >&2
  exit 1
fi

echo "==> Verifying staged app bundle..."
"$REPO_ROOT/scripts/verify-macos-app-bundle.sh" "$BUILD_DIR/Codogotchi.app"

mkdir -p "$(dirname "$DMG_OUT")"
rm -f "$DMG_OUT"

# --- Styled drag-to-install layout (assets/dmg/) ----------------------------
# We build the styled window (cloud background + "SIMPLY DRAG" arrow + enlarged,
# pinned icons) with `dmgbuild`, which writes the .DS_Store directly. This is
# AppleScript-free on purpose: Finder's `set background picture` property is
# broken on recent macOS (returns -10000), so the classic osascript dance can
# no longer paint the background. See scripts/dmg-settings.py for geometry.
DMG_ASSETS="$REPO_ROOT/assets/dmg"
VOLNAME="Codogotchi"

dmgbuild_available() { python3 -c "import dmgbuild" >/dev/null 2>&1; }

# Prefer the smudge-backed art (white labels land on the brushstroke inside each
# box); fall back to the plain background if it is absent.
BG_SRC="$DMG_ASSETS/background-with-dash.png"
[[ -f "$BG_SRC" ]] || BG_SRC="$DMG_ASSETS/background.png"

if [[ -f "$BG_SRC" ]] && dmgbuild_available; then
  echo "==> Creating styled DMG via dmgbuild ($(basename "$BG_SRC"))..."

  # Derive the HiDPI background TIFF, extending the art with extra cloud bleed at
  # the bottom. The DMG background is drawn top-anchored at its natural height,
  # so if a viewer hides the path/tab bars the content area grows; the bleed
  # keeps the art covering it (never a white strip) at the cost of the boxes
  # sitting slightly off vertical centre. The boxes stay pinned to the top, so
  # the pinned icon coordinates still land inside them. Regenerated each build;
  # not committed. (PIL ships with python3 here and dmgbuild already needs it.)
  python3 - "$BG_SRC" "$BUILD_DIR/bg_1x.png" "$BUILD_DIR/bg_2x.png" <<'PY'
import sys
from PIL import Image
src_path, out1x, out2x = sys.argv[1:4]
src = Image.open(src_path).convert("RGB")
W, H = src.size                  # 2x master (e.g. 1618x972)
ext = 68                         # +34pt logical of cloud bleed at the bottom
strip = src.crop((0, H - ext, W, H)).transpose(Image.FLIP_TOP_BOTTOM)
canvas = Image.new("RGB", (W, H + ext))
canvas.paste(src, (0, 0))
canvas.paste(strip, (0, H))      # mirror the (near-flat) bottom edge -> seamless
canvas.save(out2x)
canvas.resize((W // 2, (H + ext) // 2), Image.LANCZOS).save(out1x)
PY
  tiffutil -cathidpicheck "$BUILD_DIR/bg_1x.png" "$BUILD_DIR/bg_2x.png" \
    -out "$DMG_ASSETS/background.tiff" >/dev/null 2>&1

  python3 -m dmgbuild \
    -s "$REPO_ROOT/scripts/dmg-settings.py" \
    -D app="$BUILD_DIR/Codogotchi.app" \
    -D assets="$DMG_ASSETS" \
    "$VOLNAME" "$DMG_OUT"

  rm -f "$DMG_ASSETS/background.tiff"
else
  if [[ -f "$DMG_ASSETS/background.png" ]]; then
    echo "==> dmgbuild not installed — building plain DMG." >&2
    echo "    Install it for the styled layout:  python3 -m pip install --user dmgbuild" >&2
  else
    echo "==> assets/dmg/background.png not found — building plain DMG."
  fi
  ln -s /Applications "$BUILD_DIR/Applications"
  hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$BUILD_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_OUT"
fi

echo ""
echo "Done! DMG at: $DMG_OUT"
echo ""
echo "Share with your friend. After they drag to /Applications they run:"
echo "  xattr -d com.apple.quarantine /Applications/Codogotchi.app"
