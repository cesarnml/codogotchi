# Phase 03 validation runbook

Phase 03 is "done" when all five exit conditions in `docs/product/plans/phase-03.md` are demonstrably true. This runbook covers the two exit conditions that require deliberate operator action: triggering the four rare SoA-driven states (EC3) and triggering the two `v2`-only states via real Claude/Codex events (EC4). EC1, EC2, and EC5 are verified by reading existing artifacts.

The runbook is a one-session procedure. Owner runs it top-to-bottom once per machine, capturing evidence as they go.

**Prerequisites:** the menubar app is running with a valid `~/.codex/pets/<pet>/` spritesheet and a valid `~/.codogotchi/pets/<pet>/codogotchi-spritesheet.webp`. Confirm with `ls ~/.codex/pets/maew/` and `ls ~/.codogotchi/pets/maew/`. If either is missing, run demo mode to at least verify sprite plumbing (`CODOGOTCHI_DEMO=1 open /path/to/Menubar.app`) before proceeding.

---

## EC1. All 15 activity states paint the correct sprite row

**How to check:** Start the app in demo mode and observe one full cycle (15 states × ~3 seconds per state ≈ 45 seconds).

```bash
CODOGOTCHI_DEMO=1 open /Applications/Menubar.app
# Or from the build output:
CODOGOTCHI_DEMO=1 open .build/debug/Menubar.app
```

Watch the menu bar through one full rotation. Cross-reference each state to the row tables in [`docs/contracts/animation-state-vocabulary.md`](../contracts/animation-state-vocabulary.md#codex-sheet) (Codex sheet) and the [Codogotchi Sheet section](../contracts/animation-state-vocabulary.md#codogotchi-sheet--codogotchipets-spritesheetwebp).

**Pass:** Each of the 15 states paints a visually distinct animation without freezing or reverting to the idle pose.

**Tip:** Set `CODOGOTCHI_DEMO_FRAME_MS=83` (12 fps) to slow the frame rate and inspect individual frames:

```bash
CODOGOTCHI_DEMO=1 CODOGOTCHI_DEMO_FRAME_MS=83 open /Applications/Menubar.app
```

---

## EC2. `state.json` schema version is 2

**How to check:**

```bash
jq '.schema_version' ~/.codogotchi/state.json
```

**Pass:** Output is `2`.

---

## EC3. Rare SoA-driven states trigger via synthetic NDJSON events

The four states below are rarely seen in normal delivery because they require specific SoA gate events. Use the synthetic recipes below to trigger each one, observe the sprite, and capture the transition log evidence.

### Background: how the hook reads SoA events

The codogotchi hook binary reads `.soa/events.ndjson` at invocation time. For local synthetic testing, create the file at the path the hook resolves — typically the current working directory `.soa/events.ndjson`, or `$CLAUDE_PROJECT_DIR/.soa/events.ndjson` if Claude Code is active.

Run the hook manually after appending each synthetic line:

```bash
codogotchi-hook PostToolUse '{"tool_name": "Edit"}'
```

The hook reads `.soa/events.ndjson`, classifies the freshest unprocessed event, and writes `state.json`. The menubar polls `state.json` at ~1 Hz and updates the sprite within one second.

### 3a. `nervous` (SoA `risky_diff_detected`, codogotchi sheet row 3)

**Recipe:**

```bash
mkdir -p .soa
echo '{"name":"risky_diff_detected","ts":"2026-05-24T00:00:00.000Z","plan_key":"phase-03","ticket_id":"P3.07"}' >> .soa/events.ndjson
codogotchi-hook PostToolUse '{"tool_name": "Edit"}'
```

**Expected `state.json`:**

```json
{
  "schema_version": 2,
  "activity_state": "nervous",
  "source_event": { "origin": "soa", "kind": "gate", "name": "risky_diff_detected" }
}
```

**Expected sprite:** codogotchi sheet row 3 (`nervous` — see [Codogotchi Sheet table](../contracts/animation-state-vocabulary.md#codogotchi-sheet--codogotchipets-spritesheetwebp)).

**Expected transition log line** (`~/.codogotchi/state-transitions.log`):

```json
{"prev":"<prior_state>","schema_version":1,"source_kind":"gate","source_name":"risky_diff_detected","source_origin":"soa","state":"nervous","ts":"..."}
```

**Evidence to capture:** screenshot of menubar showing the `nervous` animation, plus the transition log line above.

### 3b. `ascended` (SoA `stage_advanced`, codogotchi sheet row 4)

**Recipe:**

```bash
echo '{"name":"stage_advanced","ts":"2026-05-24T00:01:00.000Z","plan_key":"phase-03","ticket_id":"P3.07"}' >> .soa/events.ndjson
codogotchi-hook PostToolUse '{"tool_name": "Edit"}'
```

**Expected `state.json`:**

```json
{
  "schema_version": 2,
  "activity_state": "ascended",
  "source_event": { "origin": "soa", "kind": "gate", "name": "stage_advanced" }
}
```

**Expected sprite:** codogotchi sheet row 4 (`ascended`).

**Expected transition log line:**

```json
{"prev":"nervous","schema_version":1,"source_kind":"gate","source_name":"stage_advanced","source_origin":"soa","state":"ascended","ts":"..."}
```

### 3c. `calling_for_backup` (SoA `subagent_invoked`, codogotchi sheet row 5)

**Recipe:**

```bash
echo '{"name":"subagent_invoked","ts":"2026-05-24T00:02:00.000Z","plan_key":"phase-03","ticket_id":"P3.07"}' >> .soa/events.ndjson
codogotchi-hook PostToolUse '{"tool_name": "Edit"}'
```

**Expected `state.json`:**

```json
{
  "schema_version": 2,
  "activity_state": "calling_for_backup",
  "source_event": { "origin": "soa", "kind": "gate", "name": "subagent_invoked" }
}
```

**Expected sprite:** codogotchi sheet row 5 (`calling_for_backup`).

**Expected transition log line:**

```json
{"prev":"ascended","schema_version":1,"source_kind":"gate","source_name":"subagent_invoked","source_origin":"soa","state":"calling_for_backup","ts":"..."}
```

### 3d. `panicking` (SoA `verification_failed`, codogotchi sheet row 6)

**Recipe:**

```bash
echo '{"name":"verification_failed","ts":"2026-05-24T00:03:00.000Z","plan_key":"phase-03","ticket_id":"P3.07"}' >> .soa/events.ndjson
codogotchi-hook PostToolUse '{"tool_name": "Edit"}'
```

**Expected `state.json`:**

```json
{
  "schema_version": 2,
  "activity_state": "panicking",
  "source_event": { "origin": "soa", "kind": "gate", "name": "verification_failed" }
}
```

**Expected sprite:** codogotchi sheet row 6 (`panicking`).

**Expected transition log line:**

```json
{"prev":"calling_for_backup","schema_version":1,"source_kind":"gate","source_name":"verification_failed","source_origin":"soa","state":"panicking","ts":"..."}
```

### Post-validation cleanup

After capturing evidence for all four states, remove the synthetic lines from `.soa/events.ndjson` so they do not pollute future delivery runs. The simplest approach is to delete the synthetic lines using grep:

```bash
# Preview what will be removed
grep -n "risky_diff_detected\|stage_advanced\|subagent_invoked\|verification_failed" .soa/events.ndjson

# Remove the synthetic lines (macOS BSD sed)
sed -i '' '/risky_diff_detected\|stage_advanced\|subagent_invoked\|verification_failed/d' .soa/events.ndjson
```

If `.soa/events.ndjson` contained **only** the synthetic lines (no real SoA delivery events), you can remove the file entirely:

```bash
rm .soa/events.ndjson
```

**Confirm the cleanup worked:**

```bash
grep -c "risky_diff_detected\|stage_advanced\|subagent_invoked\|verification_failed" .soa/events.ndjson 2>/dev/null
# Expected output: 0 (or "No such file" if deleted)
```

---

## EC4. `requesting_input` and `errored` fire from real Claude/Codex events

These two states are triggered by the hook's tool-call heuristics, not SoA gate events. They require deliberately inducing the conditions that the hook classifies as "agent awaiting input" and "agent response failure."

### 4a. `requesting_input` — agent paused awaiting user response

**Trigger mechanism:** Claude Code emits a `Stop` event when it stops to wait for user input. The hook intercepts this event type and writes `requesting_input` to `state.json`.

**Reliable recipe:** Ask Claude Code to stop and wait mid-task. In a Claude Code session, run a task that ends with a question requiring your input, then observe the hook fire when Claude Code reaches its stop point. Example prompt that reliably triggers a stop-with-input:

> "Run a bash command to count the files in this directory and pause before doing anything else — wait for me to approve."

When Claude Code stops and shows its input prompt, the hook fires. The hook binary receives a `Stop` event from the Claude Code event stream.

**Expected `state.json`:**

```json
{
  "schema_version": 2,
  "activity_state": "requesting_input",
  "source_event": { "origin": "claude_code", "kind": "stop", "name": "requesting_input" }
}
```

**Expected sprite:** Codex sheet row 3 (the `requesting_input` / `waving` row — see [Codex Sheet table](../contracts/animation-state-vocabulary.md#codex-sheet--codexpetsmalispritesheetwebp)).

**Evidence to capture:** screenshot of menubar showing the `requesting_input` animation and `jq '.activity_state' ~/.codogotchi/state.json` output.

**Note on finickiness:** The hook only fires when Claude Code actually invokes the hook binary via `settings.json`. If the hook is not wired into `~/.claude/settings.json`, this test cannot fire. Verify with:

```bash
jq '.hooks' ~/.claude/settings.json | grep codogotchi-hook
```

### 4b. `errored` — agent response cycle did not complete

**Trigger mechanism:** The hook classifies a response-failure event as `errored`. This fires when the agent's round-trip does not complete — rate limit, network error, or a hard stop mid-response.

**Reliable recipe (rate limit simulation):** Use a Claude Code session at near the rate limit and issue a rapid burst of requests. Alternatively, disconnect the network mid-response:

```bash
# Option 1: Disconnect network mid-response
# Start a Claude Code task that will take 3–5 seconds, then immediately run:
networksetup -setairportpower en0 off
# Wait 2 seconds, then re-enable:
sleep 2 && networksetup -setairportpower en0 on
# The hook fires with the incomplete response event.

# Option 2 (simpler, less reliable): Use the hook's test fixture path
# Construct a PostToolUse payload that matches the errored detection heuristic:
codogotchi-hook PostToolUse '{"tool_name": "Bash", "error": "network error: connection refused"}'
```

**Expected `state.json`:**

```json
{
  "schema_version": 2,
  "activity_state": "errored",
  "source_event": { "origin": "claude_code", "kind": "error", "name": "errored" }
}
```

**Expected sprite:** Codex sheet row 5 (the `errored` / `failed` row — see [Codex Sheet table](../contracts/animation-state-vocabulary.md#codex-sheet--codexpetsmalispritesheetwebp)).

**Evidence to capture:** screenshot of menubar showing the `errored` animation (pet looks distressed) and `jq '.activity_state' ~/.codogotchi/state.json` output.

**Note on finickiness:** The network-disconnect approach is hardware-dependent and may not work on machines with multiple network interfaces. The fixture path (Option 2) is more repeatable for local validation but bypasses the real hook invocation path. Document which method you used in the validation log.

---

## EC5. No regression on Phase 02 states

**How to check:** Run one full demo cycle and confirm `.idle`, `.implementing`, `.runningTests`, and `.celebrating` all paint without reverting to the idle pose unexpectedly.

```bash
CODOGOTCHI_DEMO=1 open /Applications/Menubar.app
```

Then trigger one live cycle of the Phase 02 floor states using the existing Phase 01 fixture approach. Any unexpected idle fallback counts as a regression.

**Pass:** No Phase 02 state regresses to idle. All Codex-sheet states (rows 0, 3, 5, 6, 7, 8) paint distinct animations.

---

## What counts as evidence (EC3 and EC4)

For each state, capture:

1. **Timestamp:** The `ts` field from the relevant `state-transitions.log` line.
2. **Observed state:** `jq '.activity_state' ~/.codogotchi/state.json` immediately after the hook fires.
3. **Transition log line:** The full NDJSON line from `~/.codogotchi/state-transitions.log` showing the state change.
4. **Screenshot:** A screenshot (or photo) of the macOS menu bar showing the correct sprite animation for that state.

Paste these four items per state into the validation log or a comment in the phase closeout PR. Owner's judgment on what constitutes a clear screenshot — the animation sprite should be visibly distinct from the idle pose.
