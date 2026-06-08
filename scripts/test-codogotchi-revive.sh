#!/usr/bin/env bash
#
# test-codogotchi-revive.sh — dead → revive → full-health regen demo.
#
# The capstone of the RPG-meter demos. Where test-codogotchi-hud.sh shows the
# *dead*-state REGENERATION meter and test-codogotchi-heart-regen-meter.sh shows
# the *alive*-state heart-regen bar, this one drives the whole arc end to end and
# exercises the v6 *revive animation* (revive_until) on every half-heart gain.
#
# Builds the menubar app (Debug), quits any running instance, relaunches it in
# NORMAL mode, pins the floating pet + HUD, then drives the *running* app by
# writing the real ~/.codogotchi/state.json:
#
#   - half_hearts = 0            → pet DEAD: grayscale + tombstone; the green
#                                  REGENERATION meter shows and fills 0 → full
#   - half_hearts 0 → 1          → REVIVE: revive_until fires (revive animation),
#                                  pet comes alive, the dead regen meter vanishes
#                                  and the alive heart-regen bar appears
#   - half_hearts 1 → 6          → each fill climbs the heart-regen bar, then pops
#                                  the next half-heart (bar resets, revive fires)
#   - half_hearts = 6            → FULL health: the heart-regen bar vanishes
#
# So you should see, in order: regen meter (dead only) → revive animation on the
# first ½-heart → heart-regen bar (alive, below max) climbing with a revive flash
# on each ½-heart → both meters gone at full health.
#
# Runs once from dead to full, holds ~1s at full health, then restores your real
# state on exit.
#
# Idempotent: each run rebuilds, quits any prior instance, and — if a previous
# run was interrupted before it could restore — recovers your real state from its
# leftover backup *before* taking a new snapshot. So repeated `tcr` invocations
# never lose your real state.
#
# Usage:
#   test-codogotchi-revive.sh [FILL_SECONDS]
#     FILL_SECONDS  optional positive number (default 3). Seconds for one meter to
#                   climb 0 → full (one half-heart gained). e.g. `tcr 2` gains a
#                   ½ heart every ~2s. The revive animation has a fixed 5s TTL, so
#                   at fast rates (≤5s) revives overlap into a continuous loop;
#                   pass a larger value (e.g. `tcr 6`) to see it lapse between gains.
# Alias: tcr
#
# Note: the live poll loop ticks at ~1.0s, so meters advance in ~1s steps. Run
# with no coding agent active in a tracked terminal, or a hook write may clobber
# a frame mid-cycle.

set -euo pipefail

FILL="${1:-3}"
if ! awk "BEGIN{exit !(\"$FILL\"+0 > 0)}" 2>/dev/null; then
	echo "✖ FILL_SECONDS must be a positive number (got: $FILL)" >&2
	exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/apps/menubar/Codogotchi.xcodeproj"
SCHEME="Codogotchi"
CONFIG="Debug"
BUILD_LOG="${TMPDIR:-/tmp}/codogotchi-revive-build.log"
RUN_LOG="${TMPDIR:-/tmp}/codogotchi-revive-demo.log"

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
STATE_BAK="$HOME_DIR/state.tcr-backup.json"
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

out = {"schema_version": d.get("schema_version", 6), "activity_state": "idle", "active_minutes": 0}
for k in ("level", "level_fraction", "half_hearts", "hp", "hp_overlay"):
    if k in d:
        out[k] = d[k]
out["updated_at"] = now
out["last_activity_at"] = now
out["revive_until"] = None
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

# write_frame <half_hearts> <active_minutes> <revive:0|1|2> — atomically patch the
# real state.json, refreshing timestamps so the live poller treats it as a fresh
# change and wall-clock decay never eats the value. <revive> controls revive_until:
#   0 → clear (null)                    — dead phase; no revive
#   1 → set now + 5s (the writer's TTL) — a half-heart gain just happened
#   2 → preserve the existing value     — climb frames between gains
# Preserving on climb frames is the crux: a gain sets revive_until = now+5s, and the
# ~1s climb writes keep it in the future so the 1Hz poller actually catches the
# revive (instead of it being nulled within milliseconds). It then lapses on its own
# only when the next gain is >5s away (slow rates like `tcr 6`).
write_frame() {
	python3 - "$STATE" "$1" "$2" "$3" <<'PY'
import json, os, sys, datetime

path, half, active, revive = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
now_dt = datetime.datetime.now(datetime.timezone.utc)
now = now_dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")

with open(path) as f:
    d = json.load(f)

# v6 so revive_until is honored by the renderer's schema gate.
d["schema_version"] = 6
d["activity_state"] = "idle"  # dead frames + revive override drive the visual.
d["half_hearts"] = half
d["active_minutes"] = active
hp = int(round(100 * half / 6))
d["hp"] = hp
# Keep hp_overlay consistent with hp (mirrors contracts hpToOverlay) so the
# sickness tint clears as health returns: ghost → near_death → getting_sick → thriving.
d["hp_overlay"] = (
    "ghost" if hp <= 0 else "near_death" if hp <= 25 else "getting_sick" if hp <= 75 else "thriving"
)
d["last_activity_at"] = now
d["updated_at"] = now
if revive == 1:
    d["revive_until"] = (now_dt + datetime.timedelta(seconds=5)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
elif revive == 0:
    d["revive_until"] = None
# revive == 2: leave any existing revive_until in place.

tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(d, fh, indent=2, sort_keys=True)
    fh.write("\n")
os.replace(tmp, path)
PY
}

# Step each meter once per ~second (the poll cadence); sub-second writes coalesce.
STEPS="$(awk "BEGIN{s=int($FILL+0.5); print (s<1)?1:s}")"
SLEEP="$(awk "BEGIN{printf \"%.3f\", $FILL/$STEPS}")"

# Heart label for a given half-heart count (e.g. 3 → "❤️💔🩶", 6 → "❤️❤️❤️").
heart_label() {
	awk "BEGIN{h=$1; for(i=0;i<3;i++){r=h-2*i; printf (r>=2)?\"❤️\":(r==1)?\"💔\":\"🩶\"}}"
}

MAX_HALF=6

echo "✓ Revive demo — dead → revive → full, ½ heart every ${FILL}s. (Ctrl-C aborts.)"

# --- Dead phase: half_hearts 0, the green REGENERATION meter fills 0 → full. ---
write_frame 0 0 0
printf '\r  🪦 %s  dead — regen   0%%   ' "$(heart_label 0)"
sleep "$SLEEP"
for ((k = 1; k <= STEPS; k++)); do
	active="$(awk "BEGIN{printf \"%d\", 60*$k/$STEPS}")"
	pct="$(awk "BEGIN{printf \"%d\", 100*$k/$STEPS}")"
	write_frame 0 "$active" 0
	printf '\r  🪦 %s  dead — regen %3d%%   ' "$(heart_label 0)" "$pct"
	sleep "$SLEEP"
done

# --- Revive: first ½ heart. revive_until fires; pet comes alive. ---
write_frame 1 0 1
printf '\r  ✨ %s  REVIVE! +½ heart     ' "$(heart_label 1)"

# --- Alive phase: climb one half-heart per fill, 1 → 6. Each cycle ramps the
#     heart-regen bar 0 → full, then pops the next ½-heart with a revive flash. ---
for ((target = 2; target <= MAX_HALF; target++)); do
	prev=$((target - 1))
	for ((k = 1; k <= STEPS; k++)); do
		active="$(awk "BEGIN{printf \"%d\", 60*$k/$STEPS}")"
		pct="$(awk "BEGIN{printf \"%d\", 100*$k/$STEPS}")"
		# Preserve revive_until so the prior gain's revive stays visible across the
		# climb (it lapses on its own when the next gain is >5s away).
		write_frame "$prev" "$active" 2
		printf '\r  %s  heart-regen %3d%%   ' "$(heart_label "$prev")" "$pct"
		sleep "$SLEEP"
	done
	write_frame "$target" 0 1
	printf '\r  ✨ %s  +½ heart!     ' "$(heart_label "$target")"
done

# Full health: both meters vanish. Hold ~1s on the full frame, then exit (cleanup).
printf '\r  %s  full health — meters vanished   \n' "$(heart_label "$MAX_HALF")"
sleep 1
