#!/usr/bin/env bash
#
# test-codogotchi-hud.sh — developer convenience HUD animation.
#
# Builds the menubar app (Debug), quits any running instance, and relaunches it
# under CODOGOTCHI_HUD_DEMO=1. The app then pins the floating pet + HUD and
# sweeps the RPG values for 120 seconds:
#
#   - level: starts at 1, +1 every 8s  -> ends on level 16
#   - XP ring: fills 0 -> 1 within each level (gradual)
#   - hearts: triangle wave 6 -> 0 -> 6, one half-heart every 5s
#            (a full -> empty -> full cycle takes 60s; you see two cycles)
#
# Pair with the `tch` zsh function (see scripts/README or your ~/.zshrc).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/apps/menubar/Codogotchi.xcodeproj"
SCHEME="Codogotchi"
CONFIG="Debug"
BUILD_LOG="${TMPDIR:-/tmp}/codogotchi-hud-build.log"
RUN_LOG="${TMPDIR:-/tmp}/codogotchi-hud-demo.log"

echo "▶ Building $SCHEME ($CONFIG)…"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" build \
	>"$BUILD_LOG" 2>&1; then
	echo "✖ Build failed. Tail of $BUILD_LOG:" >&2
	tail -n 20 "$BUILD_LOG" >&2
	exit 1
fi

PRODUCTS_DIR="$(
	xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
		-showBuildSettings 2>/dev/null |
		awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}'
)"
APP="$PRODUCTS_DIR/$SCHEME.app"
BIN="$APP/Contents/MacOS/$SCHEME"

if [[ ! -x "$BIN" ]]; then
	echo "✖ Could not locate built app binary at: $BIN" >&2
	exit 1
fi

echo "▶ Relaunching in HUD demo mode…"
osascript -e 'quit app "Codogotchi"' >/dev/null 2>&1 || true
pkill -x Codogotchi >/dev/null 2>&1 || true
sleep 0.7

CODOGOTCHI_HUD_DEMO=1 nohup "$BIN" >"$RUN_LOG" 2>&1 &
disown || true

cat <<'EOF'
✓ HUD demo running for 120s.
  level 1 → 16  ·  ring fills 8s/level  ·  hearts cycle 6→0→6 (5s/half-heart, 2 cycles)
  The HUD stays pinned for the whole run, then returns to hover-only behavior.
EOF
