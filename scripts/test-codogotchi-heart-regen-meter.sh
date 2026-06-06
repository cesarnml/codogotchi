#!/usr/bin/env bash
#
# test-codogotchi-heart-regen-meter.sh — alive-state heart-regen-bar demo.
#
# The sibling of test-codogotchi-hud.sh (the *dead*-state REGENERATION meter):
# this one exercises the *alive*-state heart-regen bar — the slim red gauge that
# sits between the hearts and the XP ring while the pet is alive but below max
# health, and vanishes at full health.
#
# Builds the menubar app (Debug), quits any running instance, relaunches it in
# NORMAL mode, pins the floating pet + HUD, then drives the *running* app by
# writing the real ~/.codogotchi/state.json:
#
#   - half_hearts = 1            → pet alive at ½ heart; regen bar shows
#   - active_minutes 0 → 60      → bar fills over FILL_SECONDS (default 5)
#   - half_hearts += 1           → ½ heart earned: bar resets, heal flash fires
#   - … repeat 1 → 6 half-hearts → climbs from ½ heart to full
#   - half_hearts = 6            → full health: bar vanishes (nothing to regen)
#
# Runs once from ½ heart to full, holds ~1s at full health (bar hidden), then
# restores your real state on exit.
#
# Idempotent: each run rebuilds, quits any prior instance, and — if a previous
# run was interrupted before it could restore — recovers your real state from its
# leftover backup *before* taking a new snapshot. So repeated `tchrm` invocations
# never lose your real state.
#
# Usage:
#   test-codogotchi-heart-regen-meter.sh [FILL_SECONDS]
#     FILL_SECONDS  optional positive number (default 5). Seconds for the bar to
#                   climb 0 → full (one half-heart). e.g. `… 3` fills in ~3s and
#                   the pet gains ½ heart per fill.
# Alias: tchrm
#
# Note: the live poll loop ticks at ~1.0s, so the bar advances in ~1s steps.
# Run with no coding agent active in a tracked terminal, or a hook write may
# clobber a frame mid-cycle.

set -euo pipefail

FILL="${1:-5}"
if ! awk "BEGIN{exit !(\"$FILL\"+0 > 0)}" 2>/dev/null; then
	echo "✖ FILL_SECONDS must be a positive number (got: $FILL)" >&2
	exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/apps/menubar/Codogotchi.xcodeproj"
SCHEME="Codogotchi"
CONFIG="Debug"
BUILD_LOG="${TMPDIR:-/tmp}/codogotchi-hrm-build.log"
RUN_LOG="${TMPDIR:-/tmp}/codogotchi-hrm-demo.log"

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

HOME_DIR="${CODOGOTCHI_HOME:-$HOME/.codogotchi}"
STATE="$HOME_DIR/state.json"
STATE_BAK="$HOME_DIR/state.tchrm-backup.json"
# Sentinel the running app watches (0.5s) to force the HUD visible without hover.
PIN="$HOME_DIR/hud-pin"

echo "▶ Relaunching in normal mode…"
osascript -e 'quit app "Codogotchi"' >/dev/null 2>&1 || true
pkill -x Codogotchi >/dev/null 2>&1 || true
sleep 0.7

if [[ ! -f "$STATE" ]]; then
	echo "✖ $STATE not found. Launch the app once so it writes state, then retry." >&2
	exit 1
fi

# Idempotent snapshot: a leftover backup means a prior run was interrupted before
# it restored — recover the real state from it first, then reuse it. Otherwise
# snapshot the current (real) state. Either way STATE_BAK ends up holding the
# user's true state, never a mid-demo frame.
if [[ -f "$STATE_BAK" ]]; then
	cp "$STATE_BAK" "$STATE"
else
	cp "$STATE" "$STATE_BAK"
fi

# Atomically rewrite the real state.json as a clean idle frame, preserving real
# progression (level / hearts / hp) from the pre-run snapshot when available.
write_idle() {
	python3 - "$STATE_BAK" "$STATE" <<'PY'
import json, os, sys
from datetime import datetime, timezone

bak, state = sys.argv[1], sys.argv[2]
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

d = {}
for src in (bak, state):
    try:
        with open(src) as f:
            d = json.load(f)
        break
    except (FileNotFoundError, ValueError):
        continue

out = {"schema_version": d.get("schema_version", 5), "activity_state": "idle", "active_minutes": 0}
for k in ("level", "level_fraction", "half_hearts", "hp", "hp_overlay"):
    if k in d:
        out[k] = d[k]
out["updated_at"] = now
out["last_activity_at"] = now
out["source_event"] = {"origin": "manual", "kind": "cli", "name": "reset-idle"}

tmp = state + ".tmp"
with open(tmp, "w") as f:
    json.dump(out, f, indent=2, sort_keys=True)
    f.write("\n")
os.replace(tmp, state)
PY
}

# On teardown — normal end, Ctrl-C, or kill — leave the pet at a clean idle
# resting state instead of a stranded mid-regen frame. Cleanup runs exactly once,
# only from the EXIT trap; INT/TERM convert to a clean exit so it fires reliably.
cleanup() {
	[[ -n "${CLEANED:-}" ]] && return
	CLEANED=1
	rm -f "$PIN"
	write_idle || true
	rm -f "$STATE_BAK"
	echo ""
	echo "↩ Codogotchi reset to idle (HUD back to hover)."
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

CODOGOTCHI_HOME="$HOME_DIR" nohup "$BIN" >"$RUN_LOG" 2>&1 &
disown || true

# Wait for the app to come up so the first written frame is actually polled.
for _ in $(seq 1 50); do
	pgrep -x Codogotchi >/dev/null 2>&1 && break
	sleep 0.1
done

# Pin the HUD visible for the whole run; cleanup removes it.
touch "$PIN"

# write_frame <half_hearts> <active_minutes> — atomically patch the real
# state.json, refreshing timestamps so the live poller treats it as a fresh
# change and so wall-clock decay never eats the value.
write_frame() {
	python3 - "$STATE" "$1" "$2" <<'PY'
import json, os, sys, datetime

path, half, active = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

with open(path) as f:
    d = json.load(f)

d["schema_version"] = d.get("schema_version", 5)
d["activity_state"] = "idle"
d["half_hearts"] = half
d["active_minutes"] = active
d["last_activity_at"] = now
d["updated_at"] = now

tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(d, fh, indent=2, sort_keys=True)
    fh.write("\n")
os.replace(tmp, path)
PY
}

# Step the bar once per ~second (the poll cadence); sub-second writes coalesce.
STEPS="$(awk "BEGIN{s=int($FILL+0.5); print (s<1)?1:s}")"
SLEEP="$(awk "BEGIN{printf \"%.3f\", $FILL/$STEPS}")"

# Heart label for a given half-heart count (e.g. 3 → "♥♥½", 6 → "♥♥♥").
heart_label() {
	awk "BEGIN{h=$1; for(i=0;i<3;i++){r=h-2*i; printf (r>=2)?\"❤️\":(r==1)?\"💔\":\"🩶\"}}"
}

MAX_HALF=6

# Start at ½ heart with an empty bar.
write_frame 1 0
echo "✓ Heart-regen demo — ½ heart every ${FILL}s, climbing ½ → full. (Ctrl-C aborts.)"
sleep "$SLEEP"

# Climb one half-heart per fill: 1 → 2 → … → 6. Each cycle ramps the bar 0 → full
# over FILL seconds, then pops the next half-heart (bar resets, heal flash fires).
for ((target = 2; target <= MAX_HALF; target++)); do
	prev=$((target - 1))
	for ((k = 1; k <= STEPS; k++)); do
		active="$(awk "BEGIN{printf \"%d\", 60*$k/$STEPS}")"
		pct="$(awk "BEGIN{printf \"%d\", 100*$k/$STEPS}")"
		write_frame "$prev" "$active"
		printf '\r  %s  regen %3d%%   ' "$(heart_label "$prev")" "$pct"
		sleep "$SLEEP"
	done
	write_frame "$target" 0
	printf '\r  %s  +½ heart!     ' "$(heart_label "$target")"
done

# Full health: the bar vanishes. Hold ~1s on the full frame, then exit (cleanup).
printf '\r  %s  full health — meter vanished   \n' "$(heart_label "$MAX_HALF")"
sleep 1
