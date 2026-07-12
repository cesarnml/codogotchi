You are conducting an adversarial review of a code change.
You may add extra attack surfaces when your independent repo read finds a plausible
ticket-relevant failure path.
Findings outside the three finding-discipline clauses belong in **Advisory Observations** —
anything off-scope but real is welcome there.
Your job is not a general code review — it is a targeted attack on the behavior this ticket is supposed to
protect. Start from the invariants and attack surfaces below, then independently inspect
the diff and directly related implementation code for missing ticket-relevant risks. You
are looking for paths where the ticket's intended behavior breaks, not for general
improvements.

### Ticket scope

A new `tools/delivery/codogotchi-gate.ts` module exposes a writer that overwrites
`$CODOGOTCHI_HOME/gate.json` with `{ gate, since, expires_at, plan_key, ticket_id }`.

- Path resolves as `process.env.CODOGOTCHI_HOME ?? join(homedir(), '.codogotchi')`.
- The writer creates the directory if absent.
- `expires_at` is `since + 3 minutes` (flat TTL constant = 180_000 ms).
- Write is gated on `config.codogotchi?.enabled !== false` (absent = enabled).
- Write is best-effort: any filesystem error is swallowed so a caller never throws.
- No existing emit site is rewired in this ticket.

### Files touched

Implementation:
tools/delivery/codogotchi-gate.ts (new file)

Tests:
tools/delivery/test/p17-01.test.ts (new file)

### Invariants to hold

1. `writeGateEvent` must not create any file or directory when `config.codogotchi.enabled` is `false` — the filesystem must remain untouched.
2. When enabled, `writeGateEvent` must write `gate.json` containing exactly `{ gate, since, expires_at, plan_key, ticket_id }` where `expires_at - since === 180_000 ms`.
3. `writeGateEvent` must always resolve to `undefined` and never throw, even when the target path is unwritable.

### Attack surfaces to probe

1. `config.codogotchi?.enabled === false` guard in `writeGateEvent`: the check fires only on _exactly_ `false`. What happens when `config.codogotchi` is `undefined` (optional field absent)? Does the write proceed correctly? Read `config.ts` to confirm the resolved-config shape.
2. `resolveCodogotchiHome()`: reads `process.env['CODOGOTCHI_HOME']` at call time. An empty string `""` is truthy in the `?? ` fallback chain — `"" ?? join(homedir(), '.codogotchi')` returns `""` because `""` is not `null`/`undefined`. Would `join("", "gate.json")` resolve to a relative path rather than the home default?
3. `mkdirSync` before `writeFileSync`: if the directory already exists as a file (or is a symlink to a non-directory), does `mkdirSync({ recursive: true })` throw or silently succeed? The test covers "parent is a file" but not "target itself is a file."
4. `GateJsonPayload` field mapping — camelCase inputs (`planKey`, `ticketId`) mapped explicitly to snake_case JSON fields (`plan_key`, `ticket_id`). Probe that the mapping is correct in the implementation and that tests assert both field names.
5. `writeFileSync` with `JSON.stringify(payload)` — this produces a single-line JSON with no trailing newline. Is this the expected format for the codogotchi renderer, or does it expect pretty-printed JSON?
6. Async wrapper around synchronous fs calls: `writeGateEvent` is `async` but all calls inside are sync. The `try/catch` correctly catches synchronous exceptions. Confirm the catch block does not accidentally catch and re-throw async Promise rejections that shouldn't exist here.

#### Diff-derived attack surfaces

1. **Output stability across schema-version drift** — the new `gate.json` output shape `{ gate, since, expires_at, plan_key, ticket_id }` is introduced here and consumed by codogotchi Phase 07. Probe whether any existing artifact fixtures, test helpers, or consumers already reference a prior gate.json shape that would conflict.
2. **CLI flag/arg symmetry** — no new CLI flags are introduced in this ticket. `[N/A — no CLI changes in this diff]`
3. **Error-class breadth in `catch` blocks** — the `catch {}` block swallows all errors silently with no logging. Probe whether a programming error (e.g., calling `JSON.stringify` on a circular object) would also be silently swallowed, hiding a bug.
4. **Defensive layering at module boundaries** — `writeGateEvent` accepts a free-form `gate: string` field with no validation against the codogotchi schema-v4 ActivityState enum. Probe whether passing an invalid gate name would produce a silently malformed `gate.json`.
5. **Cross-file atomicity windows** — `mkdirSync` followed by `writeFileSync`: if the process is interrupted between these two calls, the directory exists but no `gate.json` exists. Probe whether the caller (future tickets) would observe this partial state.
6. **Test-contract strength** — tests use `process.env['CODOGOTCHI_HOME']` manipulation with try/finally cleanup. Probe whether parallel test runs could observe shared env-var state (test isolation).
7. **Doc-vs-code drift in the ticket Rationale** — the Rationale says "Async `writeFile` — rejected because the sync path is simpler." The implementation uses `writeFileSync`. Check whether the ticket Outcome section says anything that the diff does not implement.

### Diff context

New module `tools/delivery/codogotchi-gate.ts`:

- `GATE_TTL_MS = 180_000` constant
- `resolveCodogotchiHome()` returns `process.env['CODOGOTCHI_HOME'] ?? join(homedir(), '.codogotchi')`
- `writeGateEvent(config, { gate, planKey, ticketId })` — async function that:
  1. Short-circuits early if `config.codogotchi?.enabled === false`
  2. Calls `resolveCodogotchiHome()`
  3. Builds `{ gate, since: new Date().toISOString(), expires_at: new Date(since.getTime() + GATE_TTL_MS).toISOString(), plan_key, ticket_id }`
  4. `mkdirSync(home, { recursive: true })`
  5. `writeFileSync(join(home, 'gate.json'), JSON.stringify(payload), 'utf8')`
  6. Entire body wrapped in `try { ... } catch { /* swallow */ }`

New test file `tools/delivery/test/p17-01.test.ts` with 4 tests covering: full shape, TTL calculation, disabled config, error swallowing.

---

### Your directives

**Scope:** You conduct an adversarial review of the implementation diff and directly
related code paths named in the attack surfaces. Do not expand scope beyond what the
ticket outcome describes.

**Advisory-only — no file writes:** You must not create, modify, or delete any file in
the repository. Your entire deliverable is findings prose in the required output format
below. The primary execution agent owns all patches.

**Read boundary for delivery docs:** Do not write files under `docs/product/delivery/**`
(or anywhere else). You **must** still read the ticket Rationale and any referenced
contract docs as part of probing the "Doc-vs-code drift in the ticket Rationale"
diff-derived surface above. If you find drift — the Rationale claims a behavior the diff
does not implement, or the diff implements behavior the Rationale does not describe —
surface it under **Advisory Observations** with the specific file, the conflicting
claim, and what the diff actually does. The primary agent decides whether to patch docs
or code.

**Coverage mandate:** For each attack surface listed above, you must either probe it and
report what you found, or explain in one sentence why it does not apply. "I didn't check"
is not acceptable. A clean result on a surface you probed is a valid and valuable outcome.
Keep any added surfaces tied to the ticket behavior; do not turn this into broad style,
cleanup, or architecture review.

**Finding discipline:** Report a finding when one of the following holds:

1. The code breaks a stated invariant.
2. The code introduces a correctness gap you can demonstrate.
3. **Spec-permits-real-bug:** the ticket's stated contract literally permits the
   behavior, but that behavior is nevertheless unsafe in production (data loss,
   unrecoverable state, silent-failure exposure, security regression). Name which spec
   clause permitted the unsafe behavior so the primary agent can decide whether to update
   the spec.

Do not report style, preference, or hypothetical future requirements as blocking findings.
If you notice something worth flagging but it is outside these three clauses, put it in
**Advisory Observations** only.

**No fabrication pressure:** If all invariants hold and all attack surfaces are sound, your
correct output is a clean report. Do not invent findings to justify the review step.

---

### Required output format

After completing your review, report in this exact structure (prose only — no file edits).
The structure is canonical and machine-parsed by downstream tooling — see
`docs/template/delivery/subagent-review-report-template.md` for the full
rules. Two rules that catch the most common drift bugs:

- Use exactly these five top-level section headings, in this order:
  `Invariant results`, `Surface results`, `Actionable findings`,
  `Advisory Observations`, `Runner termination`.
- Inside `Advisory Observations`, write **one observation per bullet or one
  observation per paragraph**. Do NOT use a bold span (`**A1 — Title**`) on a
  line by itself before the observation body — that visually mimics a
  section heading and splits one labeled observation into two parsed
  observations.

**Invariant results**
For each invariant: `[held | broken | untested]` — one line explaining what you tried.

**Surface results**
For each attack surface (both ticket-spec-derived and the seven diff-derived classes):
`[probed | N/A — <reason> | blocked — missing-input]`
If probed: what you tried and what you found (one to three sentences).

**Actionable findings**
For each finding the primary agent should consider patching: file/path, what is wrong,
which invariant or finding-discipline clause applies, and a concrete fix recommendation.
If none: "None."

**Advisory Observations**
Things you noticed that are outside the three finding-discipline clauses, including any
doc-vs-code drift surfaced under the diff-derived "Doc-vs-code drift in the ticket
Rationale" class. One bullet or one paragraph per observation. If none: "None."

**Runner termination**
`runnerStatus`: one of `completed | rate_limit | sandbox_denied | runner_unavailable`.
`terminatedReason`: one short sentence explaining why this status was reported.

`completed` means you finished the review per this template. The other three values are
honest failure modes — the CLI refuses to record `outcome: clean` for any non-`completed`
`terminatedReason`, so do not claim `completed` if you stopped early.
