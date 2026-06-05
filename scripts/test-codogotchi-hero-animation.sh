#!/usr/bin/env bash
#
# test-codogotchi-hero-animation.sh — choreographed landing-page "hero" demo.
#
# Drives the ALREADY-RUNNING Codogotchi app through a scripted ~13.5s story by
# writing the *real* ~/.codogotchi/state.json (+ gate.json), then restores your
# prior state on exit.
#
# Why the real-state path (not the `tca` preview overrides): when a preview
# override is active the live poller emits `rpgState: nil`, freezing the HUD
# hearts/level. Driving the real files instead makes the pet animation AND the
# HUD hearts / level-up / heal flashes all move together — no app rebuild, no
# HUD changes.
#
# Beats (default 1.5s each; hearts = half-hearts, 6 = full 3 hearts):
#   idle(6) → implementing(6) → ticket_started(5, LEVEL-UP) → reading(4)
#   → testing(3) → editing(2) → thinking(1) → errored(0, DEAD + regen meter)
#   → ticket_completed(1, +½ HEAL, meter vanishes) → restore
#
# The half-heart drains one step per beat from the level-up onward so hearts
# hit 0 exactly on the error beat. The gate beats (ticket_*) require the active
# pet to have a SoA sheet; the default pet "maew" does.
#
# Usage:
#   test-codogotchi-hero-animation.sh [BEAT_SECONDS]   # default 1.5
# Alias: tcha
#
# Note: the live poll loop ticks at 1.0s, so each beat is visible for roughly
# its full duration but transitions land within ~1s. Run with no coding agent
# active in a tracked terminal, or a hook write may clobber a beat mid-run.

set -euo pipefail

BEAT="${1:-1.5}"
if ! awk "BEGIN{exit !(\"$BEAT\"+0 > 0)}" 2>/dev/null; then
	echo "✖ BEAT_SECONDS must be a positive number (got: $BEAT)" >&2
	exit 1
fi

HOME_DIR="${CODOGOTCHI_HOME:-$HOME/.codogotchi}"
STATE="$HOME_DIR/state.json"
GATE="$HOME_DIR/gate.json"
STATE_BAK="$HOME_DIR/state.tcha-backup.json"
GATE_BAK="$HOME_DIR/gate.tcha-backup.json"
# Sentinel the running app watches (0.5s) to force the HUD visible without hover.
PIN="$HOME_DIR/hud-pin"

if ! pgrep -x Codogotchi >/dev/null 2>&1; then
	echo "✖ Codogotchi isn't running. Launch the app first (e.g. open it, or run \`cgi\`/\`tch\`)." >&2
	exit 1
fi
if [[ ! -f "$STATE" ]]; then
	echo "✖ $STATE not found." >&2
	exit 1
fi

# Snapshot real state + gate so we can put everything back exactly as it was.
cp "$STATE" "$STATE_BAK"
GATE_EXISTED=0
if [[ -f "$GATE" ]]; then
	GATE_EXISTED=1
	cp "$GATE" "$GATE_BAK"
fi

restore() {
	rm -f "$PIN"
	cp "$STATE_BAK" "$STATE" 2>/dev/null || true
	rm -f "$STATE_BAK"
	if [[ "$GATE_EXISTED" == "1" ]]; then
		cp "$GATE_BAK" "$GATE" 2>/dev/null || true
		rm -f "$GATE_BAK"
	else
		rm -f "$GATE"
	fi
	echo ""
	echo "↩ restored your real Codogotchi state (HUD back to hover)."
}
trap restore EXIT INT TERM

# Pin the HUD visible for the whole run; restore() removes it.
touch "$PIN"

LEVEL_BASE="$(python3 -c "import json,sys; print(json.load(open('$STATE_BAK')).get('level',1))")"
LEVEL_UP=$((LEVEL_BASE + 1))

# beat <state|gate> <name> <half_hearts> <level> <level_fraction> <origin> <active_minutes>
# Writes the real state.json (atomic); for `gate` beats also writes gate.json
# (which takes render precedence), for `state` beats removes gate.json. `origin`
# sets source_event.origin so the platform-attribution chip cycles per beat.
# `active_minutes` (0…60) sets the regeneration-meter fill; it only renders while
# dead (half_hearts=0), so it matters on the errored beat and is 0 elsewhere.
beat() {
	printf '  %-16s hearts=%s level=%s  [%s]\n' "$2" "$3" "$4" "$6"
	python3 - "$STATE_BAK" "$STATE" "$GATE" "$@" <<'PY'
import json, os, sys
from datetime import datetime, timezone, timedelta

base_path, state_path, gate_path, mode, name, half, level, frac, origin, active = sys.argv[1:11]


def iso(dt):
    return dt.isoformat(timespec="milliseconds").replace("+00:00", "Z")


now_dt = datetime.now(timezone.utc)
now = iso(now_dt)

with open(base_path) as f:
    d = json.load(f)

d["schema_version"] = d.get("schema_version", 5)
d["half_hearts"] = int(half)
d["active_minutes"] = int(active)
d["level"] = int(level)
d["level_fraction"] = float(frac)
d["last_activity_at"] = now
d["updated_at"] = now
# For gate beats the gate sidecar wins; keep a sensible activity fallback.
d["activity_state"] = "implementing" if mode == "gate" else name

# Cycle the platform-attribution chip so the hero reel advertises support for
# every major agent platform (claude_code → codex → cursor → vscode → antigravity).
se = d.get("source_event")
if not isinstance(se, dict):
    se = {}
se["origin"] = origin
d["source_event"] = se


def atomic_write(path, payload):
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(payload, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)


atomic_write(state_path, d)

if mode == "gate":
    atomic_write(
        gate_path,
        {"gate": name, "since": now, "expires_at": iso(now_dt + timedelta(hours=1))},
    )
else:
    try:
        os.remove(gate_path)
    except FileNotFoundError:
        pass
PY
}

TOTAL="$(awk "BEGIN{printf \"%.1f\", $BEAT * 9}")"
echo "▶ Codogotchi hero animation — ~${TOTAL}s, ${BEAT}s/beat. (Ctrl-C restores early.)"

# Platform chip cycles claude_code → codex → cursor → vscode → antigravity,
# wrapping — so an attentive viewer sees we support every major agent platform.
# Trailing column = active_minutes (regen-meter fill); only visible on the dead
# beat, where it sits ~75% to read as "almost revived" before the heal lands.
beat state idle             6 "$LEVEL_BASE" 0.55 claude_code  0;  sleep "$BEAT"
beat state implementing     6 "$LEVEL_BASE" 0.80 codex        0;  sleep "$BEAT"
beat gate  ticket_started   5 "$LEVEL_UP"   0.10 cursor       0;  sleep "$BEAT"   # ← level-up flash
beat state reading          4 "$LEVEL_UP"   0.20 vscode       0;  sleep "$BEAT"
beat state testing          3 "$LEVEL_UP"   0.35 antigravity  0;  sleep "$BEAT"
beat state editing          2 "$LEVEL_UP"   0.50 claude_code  0;  sleep "$BEAT"
beat state thinking         1 "$LEVEL_UP"   0.65 codex        0;  sleep "$BEAT"
beat state errored          0 "$LEVEL_UP"   0.65 cursor       45; sleep "$BEAT"   # ← dead / tombstone + regen meter
beat gate  ticket_completed 1 "$LEVEL_UP"   0.75 vscode       0;  sleep "$BEAT"   # ← +½ heart heal flash (meter vanishes)

echo "✓ hero arc complete."
# trap restores real state on EXIT.
