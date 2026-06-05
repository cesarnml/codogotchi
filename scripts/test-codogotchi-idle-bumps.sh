#!/usr/bin/env bash
#
# test-codogotchi-idle-bumps.sh — developer convenience idle-bump tester.
#
# Builds the menubar app (Debug), quits any running instance, and relaunches it
# in *normal* mode — no scripted HUD/RPG demo — but with the idle clock backdated
# so she starts in the FRUSTRATED idle state instead of making you wait out the
# real 30-minute escalation window.
#
# Everything after launch is exactly how she behaves outside this tester:
#   - production escalation timing (impatient at 10 min, frustrated at 30 min)
#   - real hover-driven HUD, real state.json polling
#   - the floating-pet click-hold de-escalation ("bump"): hold a click on her
#     body for 5s to step down one level (frustrated → impatient → idle), and
#     keep holding for another bump every 5s. Holding works whether you keep
#     still (jumping) or drag her (running-left/right).
#
# Use it to exercise the click-hold bump fix on a frustrated pet immediately:
#   1. Hold (no drag) ~5s  → frustrated → impatient
#   2. Keep holding ~5s    → impatient → idle
#   3. Try again while dragging her around → same bump cadence
#
# Usage:
#   test-codogotchi-idle-bumps.sh [START_LEVEL]
#     START_LEVEL  optional: idle | impatient | frustrated (default frustrated)
# Alias: tcib

set -euo pipefail

START_LEVEL="${1:-frustrated}"

# Production escalation thresholds (must mirror IdleEscalationConfig.production):
#   impatient at 10 min, frustrated at 30 min. We backdate the idle clock to just
#   past the chosen level's floor so she launches there under normal timing.
case "$START_LEVEL" in
idle) BACKDATE_MS=0 ;;
impatient) BACKDATE_MS=660000 ;;  # 11 min → past the 10 min impatient floor
frustrated) BACKDATE_MS=1860000 ;; # 31 min → past the 30 min frustrated floor
*)
	echo "✖ START_LEVEL must be one of: idle | impatient | frustrated (got: $START_LEVEL)" >&2
	exit 1
	;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/apps/menubar/Codogotchi.xcodeproj"
SCHEME="Codogotchi"
CONFIG="Debug"
BUILD_LOG="${TMPDIR:-/tmp}/codogotchi-idle-bumps-build.log"
RUN_LOG="${TMPDIR:-/tmp}/codogotchi-idle-bumps.log"

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

echo "▶ Relaunching in normal mode, starting ${START_LEVEL}…"
osascript -e 'quit app "Codogotchi"' >/dev/null 2>&1 || true
pkill -x Codogotchi >/dev/null 2>&1 || true
sleep 0.7

# CODOGOTCHI_IDLE_BACKDATE_MS backdates the idle clock; CODOGOTCHI_FLOAT_ON_LAUNCH
# guarantees the floating pet is on screen without the pinned HUD-demo mode.
# No CODOGOTCHI_IDLE_*_MS overrides → production escalation timing.
CODOGOTCHI_IDLE_BACKDATE_MS="$BACKDATE_MS" \
	CODOGOTCHI_FLOAT_ON_LAUNCH=1 \
	nohup "$BIN" >"$RUN_LOG" 2>&1 &
disown || true

cat <<EOF
✓ Codogotchi running in normal mode — starting $START_LEVEL.
  Bump her down a level: click-hold her body 5s (frustrated → impatient → idle).
  Keep holding for another bump every 5s. Holding still OR dragging both count.
  After bumps she re-escalates on the normal cadence (impatient 10m, frustrated 30m).
EOF
