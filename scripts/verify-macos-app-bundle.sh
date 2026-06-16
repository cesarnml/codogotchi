#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/verify-macos-app-bundle.sh /path/to/Codogotchi.app" >&2
  exit 64
fi

APP_PATH="$1"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
RESOURCES_DIR="$APP_PATH/Contents/Resources"
ICON_NAME="AppIcon"
ICON_FILE="$RESOURCES_DIR/$ICON_NAME.icns"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST" 2>/dev/null || true
}

[[ -d "$APP_PATH" ]] || fail "app bundle not found: $APP_PATH"
[[ -f "$INFO_PLIST" ]] || fail "Info.plist not found: $INFO_PLIST"

bundle_name="$(plist_value CFBundleName)"
bundle_package_type="$(plist_value CFBundlePackageType)"
short_version="$(plist_value CFBundleShortVersionString)"
bundle_version="$(plist_value CFBundleVersion)"
icon_file="$(plist_value CFBundleIconFile)"
icon_name="$(plist_value CFBundleIconName)"

[[ "$bundle_name" == "Codogotchi" ]] || fail "CFBundleName must be Codogotchi, got '${bundle_name:-<missing>}'"
[[ "$bundle_package_type" == "APPL" ]] || fail "CFBundlePackageType must be APPL, got '${bundle_package_type:-<missing>}'"
[[ -n "$short_version" ]] || fail "CFBundleShortVersionString is missing"
[[ -n "$bundle_version" ]] || fail "CFBundleVersion is missing"
[[ "$icon_file" == "$ICON_NAME" ]] || fail "CFBundleIconFile must be $ICON_NAME, got '${icon_file:-<missing>}'"
[[ "$icon_name" == "$ICON_NAME" ]] || fail "CFBundleIconName must be $ICON_NAME, got '${icon_name:-<missing>}'"
[[ -s "$ICON_FILE" ]] || fail "icon file missing or empty: $ICON_FILE"

echo "Verified macOS app bundle:"
echo "  app: $APP_PATH"
echo "  version: $short_version ($bundle_version)"
echo "  icon: $ICON_NAME"
