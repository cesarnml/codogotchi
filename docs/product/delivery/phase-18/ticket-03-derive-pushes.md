# P18.03 Derive pushes — combined folding and the fat push spec

Size: 3 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- `derive` completes the fat `DesiredWindows` spec: combined folding with winner election (freshest folded `updated_at`), the combined window's TTL/transient-gap/mode-switch-away rules (Step 8's three branches, including the last-active tie-break trap documented there), renderer-kind resolution (own / minimalist / combined-normal / combined-minimalist with the style-toggle respawn rule), platform-chip attribution (idle → Default vs. driving origin), label precedence (rename → retrieved title → "Session N" → platform display name), session tooltips, gate badges, prompt-timer status (observe-before-guards ordering preserved: hidden/capped/TTL'd keys still observe every tick), HUD gating (`all`/`hidden`/`mostRecent` vs. the sticky bearer), RPG flags, conflict-bubble targeting/re-homing/rate-limit (the re-home path must not consume the one-hour limit), monochrome-changed, and idle-escalation config propagation.
- The title-resolution effect seam exists: `PoolTickInput` carries known titles; `derive` emits `titleResolutionRequests` for rendered session-keyed windows lacking one; the resolved-title cache field in `PoolMemory` receives results. The ~1-tick first-title delay is documented at the seam as the phase's one accepted divergence.
- A **step-mapping artifact** exists (doc or doc-comment table): every step of the former `update()` (1 through 9, including sub-steps) mapped to its derive site — the review evidence for exit condition 3 ("no hidden policy").
- Remaining gap-class table rows land (combined-window teardown-on-mode-switch-away; HUD stickiness across background updates).
- Still unwired; live pipeline untouched; full existing suite green; purity gate green.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- Failing tables first: combined winner election and tie hazards, label precedence including the combined window's idle "Combined" vs. driving-platform default, conflict-bubble rate-limit vs. re-home distinction, HUD-bearer stickiness, timer observation while hidden/capped/TTL'd.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P18.03): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Transcribe Steps 7–9 push semantics and Step 8's combined branches from `FloatingPetWindowPool`, moving every policy decision found in push code into derive as data.
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- The step-mapping artifact is the ticket's real deliverable for exit condition 3 — review it against the actual `update()` source line by line, hunting for policy with no derive home (that is a finding, not a footnote).
- Conflict bubble: re-homing a bubble whose host died must not consume/extend the rate limit — distinct branches, distinct table rows.
- Combined Step 8 branches: the mode-switch-away branch deliberately ignores last-active immunity while the transient-gap branch honors it — verify the transcription keeps them distinct.
- Title seam: confirm nothing else impure crept into derive under the same justification.
- Intentionally deferred: executing any push (P18.04); comparing against the live pipeline (P18.05).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: The new fat-payload table failed to compile because `PoolTickInput` had no pure seams for labels, known titles, prompt summaries, or HUD mode.
Why this path: Extend the existing pure fold additively and construct every controller payload beside membership, preserving the legacy winner, timer, badge, label, HUD, and conflict rules without wiring the live pool.
Alternative considered: Resolving titles and HUD configuration inside `derive` was rejected because disk/process reads would violate the purity contract; the shell supplies values and receives deterministic title requests instead.
Deferred: Executing/diffing payloads remains P18.04; live-pipeline comparison remains P18.05.
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
