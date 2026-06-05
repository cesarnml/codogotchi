#!/usr/bin/env bash

set -euo pipefail

PREVIEW_ROOT="${TMPDIR:-$(python3 - <<'PY'
import tempfile
print(tempfile.gettempdir())
PY
)}/codogotchi-preview"
STATE_PATH="${PREVIEW_ROOT}/state-override.json"
GATE_PATH="${PREVIEW_ROOT}/gate-override.json"

# `single` intentionally leaves its preview override in place to expire on its
# own (30s), and a normal `cycle` clears overrides when it finishes. But an
# interrupted `cycle` (Ctrl-C) would otherwise strand an override for up to its
# expiry window, freezing the HUD. Clear overrides on interrupt only — never on
# normal EXIT, so `single`'s deferred-expiry behavior is preserved.
trap 'rm -f "$STATE_PATH" "$GATE_PATH" 2>/dev/null || true' INT TERM

usage() {
	cat <<'EOF'
Usage:
  codogotchi-animation-test.sh single <trigger>
  codogotchi-animation-test.sh cycle soa
  codogotchi-animation-test.sh cycle codex
  codogotchi-animation-test.sh cycle lite

Notes:
  - `single` persists for 30 seconds, then the live app falls back to the real state.
  - cycle commands hold each animation for 10 seconds.
  - These commands only touch preview files under $TMPDIR/codogotchi-preview/.
EOF
}

ensure_root() {
	mkdir -p "$PREVIEW_ROOT"
}

iso_after() {
	local seconds="$1"
	python3 - "$seconds" <<'PY'
from datetime import datetime, timedelta, timezone
import sys

seconds = int(sys.argv[1])
print((datetime.now(timezone.utc) + timedelta(seconds=seconds)).isoformat(timespec="milliseconds").replace("+00:00", "Z"))
PY
}

iso_now() {
	python3 <<'PY'
from datetime import datetime, timezone
print(datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"))
PY
}

cleanup_file_later() {
	local path="$1"
	local token="$2"
	local seconds="$3"
	(
		sleep "$seconds"
		python3 - "$path" "$token" <<'PY'
import json
import os
import sys

path = sys.argv[1]
token = sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except FileNotFoundError:
    raise SystemExit(0)
except Exception:
    raise SystemExit(0)

if payload.get("token") == token:
    try:
        os.remove(path)
    except FileNotFoundError:
        pass
PY
	) >/dev/null 2>&1 &
}

canonical_state() {
	local raw
	raw="$(printf '%s' "${1//-/_}" | tr '[:upper:]' '[:lower:]')"
	case "$raw" in
		idle) echo "idle" ;;
		standby|stop) echo "standby" ;;
		error|errored) echo "errored" ;;
		waiting|waiting_for_input|input|request_input) echo "waiting_for_input" ;;
		implement|implementing|coding|code) echo "implementing" ;;
		edit|editing) echo "editing" ;;
		search|searching) echo "searching" ;;
		web|web_search) echo "web_search" ;;
		verify|verifying) echo "verifying" ;;
		git|git_ops) echo "git_ops" ;;
		test|testing) echo "testing" ;;
		think|thinking) echo "thinking" ;;
		read|reading) echo "reading" ;;
		cram|cramming) echo "cramming" ;;
		ticket_started|ticketstart|ticket_start|started) echo "ticket_started" ;;
		red_tdd|red) echo "red_tdd" ;;
		green_tdd|green) echo "green_tdd" ;;
		adversarial_review|adv_review|adversarial|review) echo "adversarial_review" ;;
		open_pr|openpr|pr) echo "open_pr" ;;
		poll_review|poll|polling) echo "poll_review" ;;
		record_review|record|recording) echo "record_review" ;;
		advance|advancing) echo "advance" ;;
		ticket_completed|ticket_done|completed|done) echo "ticket_completed" ;;
		review_clean|clean) echo "review_clean" ;;
		*)
			return 1
			;;
	esac
}

is_gate_state() {
	case "$1" in
		ticket_started|red_tdd|green_tdd|adversarial_review|open_pr|poll_review|record_review|advance|ticket_completed|review_clean)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

write_state_override() {
	local state="$1"
	local duration="$2"
	local since expires token
	since="$(iso_now)"
	expires="$(iso_after "$duration")"
	token="$(uuidgen 2>/dev/null || python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
	python3 - "$STATE_PATH" "$state" "$since" "$expires" "$token" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = {
    "activity_state": sys.argv[2],
    "since": sys.argv[3],
    "expires_at": sys.argv[4],
    "token": sys.argv[5],
}
path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
PY
	rm -f "$GATE_PATH"
	cleanup_file_later "$STATE_PATH" "$token" $((duration + 2))
}

write_gate_override() {
	local gate="$1"
	local duration="$2"
	local since expires token
	since="$(iso_now)"
	expires="$(iso_after "$duration")"
	token="$(uuidgen 2>/dev/null || python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
	python3 - "$GATE_PATH" "$gate" "$since" "$expires" "$token" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = {
    "gate": sys.argv[2],
    "since": sys.argv[3],
    "expires_at": sys.argv[4],
    "token": sys.argv[5],
}
path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
PY
	rm -f "$STATE_PATH"
	cleanup_file_later "$GATE_PATH" "$token" $((duration + 2))
}

activate_trigger() {
	local trigger="$1"
	local duration="$2"
	local canonical
	canonical="$(canonical_state "$trigger")" || {
		echo "Unknown trigger word: $trigger" >&2
		echo "See notes/public/codogotchi-animation-test-triggers.md for the supported words." >&2
		return 1
	}

	if is_gate_state "$canonical"; then
		write_gate_override "$canonical" "$duration"
	else
		write_state_override "$canonical" "$duration"
	fi

	echo "Codogotchi preview: ${canonical} for ${duration}s"
}

cycle_states() {
	local duration="$1"
	shift
	local state
	for state in "$@"; do
		activate_trigger "$state" "$duration"
		sleep "$duration"
	done
	rm -f "$STATE_PATH" "$GATE_PATH"
}

main() {
	ensure_root

	local command="${1:-}"
	case "$command" in
		single)
			[[ $# -eq 2 ]] || {
				usage >&2
				return 1
			}
			activate_trigger "$2" 30
			;;
		cycle)
			[[ $# -eq 2 ]] || {
				usage >&2
				return 1
			}
			case "$2" in
				soa)
					cycle_states 10 \
						ticket_started \
						red_tdd \
						green_tdd \
						adversarial_review \
						open_pr \
						poll_review \
						review_clean \
						record_review \
						advance \
						ticket_completed
					;;
				codex)
					cycle_states 10 \
						idle \
						standby \
						errored \
						implementing \
						thinking
					;;
				lite)
					cycle_states 10 \
						idle \
						standby \
						thinking \
						searching \
						web_search \
						reading \
						implementing \
						editing \
						git_ops \
						testing \
						verifying \
						cramming \
						errored \
						waiting_for_input
					;;
				*)
					usage >&2
					return 1
					;;
			esac
			;;
		*)
			usage >&2
			return 1
			;;
	esac
}

main "$@"
