#!/usr/bin/env bash
#
# test-codogotchi-level.sh — developer convenience leveling animation.
#
# Builds the menubar app (Debug), quits any running instance, and relaunches it
# under the in-app HUD demo with hearts pinned full, so only the level + XP-ring
# sweep plays (no heart drain, no death/revive). This is the "leveling" slice of
# the animation the old `tch` used to serve.
#
#   - level: starts at 1, +1 every Ns (default 8) → at 8s/level it climbs 1 → 16
#            over the 120s run
#   - XP ring: fills 0 → 1 smoothly within each level (in-app 0.05s ticks)
#   - hearts: pinned at full (3 hearts) the whole time
#
# The HUD stays pinned for the 120s run, then returns to hover-only behavior.
#
# Usage:
#   test-codogotchi-level.sh [SECONDS_PER_LEVEL]
#     SECONDS_PER_LEVEL  optional positive number (default 8). e.g. `… 3` for a
#                        smooth ~3s/level fill (level 1 → 41 over 120s).
# Alias: tcl

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
BUILD_LOG="${TMPDIR:-/tmp}/codogotchi-level-build.log"
RUN_LOG="${TMPDIR:-/tmp}/codogotchi-level-demo.log"

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

echo "▶ Relaunching in leveling demo mode…"
osascript -e 'quit app "Codogotchi"' >/dev/null 2>&1 || true
pkill -x Codogotchi >/dev/null 2>&1 || true
sleep 0.7

CODOGOTCHI_HUD_DEMO=1 \
	CODOGOTCHI_HUD_DEMO_LEVEL_SECONDS="$LEVEL_SECONDS" \
	CODOGOTCHI_HUD_DEMO_HEARTS_FULL=1 \
	nohup "$BIN" >"$RUN_LOG" 2>&1 &
disown || true

END_LEVEL="$(awk "BEGIN{printf \"%d\", 1 + int(120 / $LEVEL_SECONDS)}")"
cat <<EOF
✓ Leveling demo running for 120s.
  level 1 → $END_LEVEL  ·  ring fills ${LEVEL_SECONDS}s/level  ·  hearts stay full
  The HUD stays pinned for the whole run, then returns to hover-only behavior.
EOF
