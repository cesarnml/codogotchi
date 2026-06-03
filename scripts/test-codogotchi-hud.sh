#!/usr/bin/env bash
#
# test-codogotchi-hud.sh — developer convenience HUD animation.
#
# Builds the menubar app (Debug), quits any running instance, and relaunches it
# under CODOGOTCHI_HUD_DEMO=1. The app then pins the floating pet + HUD and
# sweeps the RPG values for 120 seconds:
#
#   - level: starts at 1, +1 every Ns (default 8) -> faster N = more level-ups
#   - XP ring: fills 0 -> 1 within each level (gradual)
#   - hearts: triangle wave 6 -> 0 -> 6, one half-heart every N×5/8 s
#            (the cycle scales with level speed, keeping the 5:8 heart:level ratio)
#
# Usage:
#   test-codogotchi-hud.sh [SECONDS_PER_LEVEL]
#     SECONDS_PER_LEVEL  optional positive number (default 8). e.g. `… 3` for a
#                        punchier ~3s/level demo (~1.9s per half-heart tick).
#
# Pair with the `tch` zsh function — make sure it forwards args, e.g.
#   tch() { "$HOME/code/codogotchi/scripts/test-codogotchi-hud.sh" "$@" }

set -euo pipefail

LEVEL_SECONDS="${1:-8}"
if ! awk "BEGIN{exit !(\"$LEVEL_SECONDS\"+0 > 0)}" 2>/dev/null; then
	echo "✖ SECONDS_PER_LEVEL must be a positive number (got: $LEVEL_SECONDS)" >&2
	exit 1
fi

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

CODOGOTCHI_HUD_DEMO=1 CODOGOTCHI_HUD_DEMO_LEVEL_SECONDS="$LEVEL_SECONDS" \
	nohup "$BIN" >"$RUN_LOG" 2>&1 &
disown || true

HEART_SECONDS="$(awk "BEGIN{printf \"%.2f\", $LEVEL_SECONDS * 5 / 8}")"
END_LEVEL="$(awk "BEGIN{printf \"%d\", 1 + int(120 / $LEVEL_SECONDS)}")"
cat <<EOF
✓ HUD demo running for 120s.
  level 1 → $END_LEVEL  ·  ring fills ${LEVEL_SECONDS}s/level  ·  hearts ${HEART_SECONDS}s/half-heart
  The HUD stays pinned for the whole run, then returns to hover-only behavior.
EOF
