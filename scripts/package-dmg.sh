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
ln -s /Applications "$BUILD_DIR/Applications"

echo "==> Creating DMG..."
mkdir -p "$(dirname "$DMG_OUT")"
rm -f "$DMG_OUT"
hdiutil create \
  -volname "Codogotchi" \
  -srcfolder "$BUILD_DIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_OUT"

echo ""
echo "Done! DMG at: $DMG_OUT"
echo ""
echo "Share with your friend. After they drag to /Applications they run:"
echo "  xattr -d com.apple.quarantine /Applications/Codogotchi.app"
