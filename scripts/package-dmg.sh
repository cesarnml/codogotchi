#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/apps/menubar/Codogotchi.xcodeproj"
DMG_OUT="$REPO_ROOT/builds/Codogotchi.dmg"

# Signing/notarization identity — pulled from .env (never committed) rather
# than hardcoded, so the script works for any Developer ID holder on the team.
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  source <(grep '^APPLE_' "$REPO_ROOT/.env")
  set +a
fi
: "${APPLE_CODE_SIGN_IDENTITY:?Set APPLE_CODE_SIGN_IDENTITY in .env (see \`security find-identity -v -p codesigning\`)}"
NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-codogotchi-notary}"
CLI_ENTITLEMENTS="$REPO_ROOT/apps/menubar/Resources/CLIBinary.entitlements"
APP_ENTITLEMENTS="$REPO_ROOT/apps/menubar/Codogotchi.entitlements"
SPARKLE_HELPER_ENTITLEMENTS="$REPO_ROOT/apps/menubar/Resources/SparkleHelper.entitlements"

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

# --- Sign, notarize, staple --------------------------------------------------
# Nested Mach-O executables must be signed individually before the outer app,
# innermost-first — Apple's notarization service rejects a bundle containing
# any unsigned or non-hardened-runtime executable. The embedded CLI binaries
# (bun --compile output, see scripts/build-binaries.sh) bundle a JS engine that
# needs JIT, so they get their own entitlements distinct from the app's.
APP_PATH_STAGED="$BUILD_DIR/Codogotchi.app"
RESOURCES_DIR="$APP_PATH_STAGED/Contents/Resources"

echo "==> Signing embedded CLI binaries..."
for bin in codogotchi codogotchi-hook; do
  codesign --force --options runtime --timestamp \
    --entitlements "$CLI_ENTITLEMENTS" \
    --sign "$APPLE_CODE_SIGN_IDENTITY" \
    "$RESOURCES_DIR/$bin"
done

# Xcode's automatic "Embed Frameworks" step re-signs Sparkle.framework's nested
# code, but without a secure timestamp and (for the XPC services/Autoupdate)
# without our Developer ID — both fail notarization. Sparkle's documented
# codesigning order is innermost-first: the XPC services and Autoupdate tool
# inside Versions/Current, then the nested Updater.app, then the framework's
# own dylib, then finally the outer app.
SPARKLE_FRAMEWORK="$RESOURCES_DIR/../Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "==> Signing Sparkle.framework nested code..."
  SPARKLE_VERSIONED="$SPARKLE_FRAMEWORK/Versions/Current"
  for helper in \
    "$SPARKLE_VERSIONED/XPCServices/Downloader.xpc" \
    "$SPARKLE_VERSIONED/XPCServices/Installer.xpc" \
    "$SPARKLE_VERSIONED/Autoupdate"
  do
    codesign --force --options runtime --timestamp \
      --entitlements "$SPARKLE_HELPER_ENTITLEMENTS" \
      --sign "$APPLE_CODE_SIGN_IDENTITY" \
      "$helper"
  done
  codesign --force --options runtime --timestamp \
    --sign "$APPLE_CODE_SIGN_IDENTITY" \
    "$SPARKLE_VERSIONED/Updater.app"
  codesign --force --options runtime --timestamp \
    --sign "$APPLE_CODE_SIGN_IDENTITY" \
    "$SPARKLE_FRAMEWORK"
fi

echo "==> Signing app bundle..."
codesign --force --options runtime --timestamp \
  --entitlements "$APP_ENTITLEMENTS" \
  --sign "$APPLE_CODE_SIGN_IDENTITY" \
  "$APP_PATH_STAGED"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH_STAGED"

echo "==> Submitting for notarization (this can take a few minutes)..."
NOTARIZE_ZIP="$BUILD_DIR/Codogotchi-notarize.zip"
ditto -c -k --keepParent "$APP_PATH_STAGED" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH_STAGED"

echo "==> Verifying Gatekeeper acceptance..."
spctl --assess --type execute --verbose=2 "$APP_PATH_STAGED"

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
echo "Done! Notarized, stapled DMG at: $DMG_OUT"
echo ""
echo "Ready to distribute — Gatekeeper accepts it with no user workaround needed."
