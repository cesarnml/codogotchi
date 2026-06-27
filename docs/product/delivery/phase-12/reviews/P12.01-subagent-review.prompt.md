```
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

**Outcome (P12.01 — Keyed-slice contract + reducer interface):**

- `packages/contracts` exports a **slice-entry** type representing one agent's current state
  keyed by `(origin, session_id)` — the same fields a single `state.json` carries today
  (activity_state, hp, hp_overlay, source_event, v5 RPG fields, attention, tool_command),
  minus the top-level `schema_version`.
- `STATE_JSON_SCHEMA_VERSION` is bumped to `7`.
- A **reducer interface** `(slices) -> renderTarget(s)` is exported, with two implementations:
  - `globalAggregate` — collapses the slice set to a single resolved state using most-recent
    `updated_at` as the tiebreak; this is what `status` and the renderer logically consume.
  - `perPlatform` — groups slices by `origin` and resolves one state per platform; **pure
    function, exported and tested, but wired to no consumer in this phase.**
- All of the above is pure (no filesystem, no I/O) and fully unit-tested.

**Rationale notes from ticket doc:**
- `sliceEntrySchema` imports shared sub-schemas from existing modules — no field duplication.
- Attention sub-schema defined inline in `slice-entry.ts` to avoid re-exporting it from `state-json.ts`.
- Separate schema is the right seam (vs. `Omit<StateJsonV1, 'schema_version'>`).
- CLI writer still emits `schema_version: 6` (hardcoded, deferred to P12.02).
- Swift `EXPECTED_STATE_SCHEMA_VERSION` bump deferred to P12.03.
- `SliceReducer<T>` is the generic reducer interface; `perThread` would fit identically.

### Files touched

Implementation:
packages/contracts/src/slice-entry.ts (new)
packages/contracts/src/state-json.ts (STATE_JSON_SCHEMA_VERSION 6 → 7)
packages/contracts/src/index.ts (export added)

Tests:
packages/contracts/src/slice-entry.test.ts (new)
packages/contracts/src/state-json.test.ts (version assertions updated, forward-compat corrected)

### Invariants to hold

1. `sliceEntrySchema.parse()` must reject any input missing `origin` or `session_id`, since those are the slice key that makes the directory naming scheme work.
2. `globalAggregate([])` must return a valid `StateJsonV1` with `activity_state === "idle"` — the empty set must never throw or return undefined.
3. `STATE_JSON_SCHEMA_VERSION` is exactly `7`, and `stateJsonV1Schema` accepts `schema_version` values 1–7 and rejects 8+.

### Attack surfaces to probe

1. **`latestSlice` string-comparison tiebreak in `slice-entry.ts`** — ISO 8601 datetime strings are lexicographically ordered only when they use a consistent format (UTC `Z` vs `+00:00`, fractional seconds, etc.). If slices with `+07:00` offset timestamps are compared against `Z`-suffixed ones, the string comparison `>` may produce incorrect tiebreak results. Probe whether the tiebreak is offset-safe.

2. **`IDLE_DEFAULT` object mutability** — `IDLE_DEFAULT` is a module-level constant of type `StateJsonV1`. If a consumer mutates the returned object from `globalAggregate([])`, they mutate the shared constant. Probe whether the empty-set return path returns the literal reference or a copy.

3. **`sliceToStateJson` field completeness** — The function maps a `SliceEntry` to `StateJsonV1`. Check whether all optional fields from `SliceEntry` are forwarded to the output and none are silently dropped. Specifically: `active_minutes`, `revive_until`, `tool_command`, `attention`. Missing a field here would silently lose data when slices pass through the reducer.

4. **`sliceEntrySchema` — attention sub-schema inline vs. legacy `stateJsonV1Schema`** — The attention sub-schema is inlined in `slice-entry.ts` with identical field definitions. If the attention schema in `stateJsonV1Schema` ever diverges (e.g. a new `reason_kind`), the inline copy in `slice-entry.ts` would silently accept fewer reason kinds. Probe whether there's a risk of hidden divergence today or a design pattern that prevents it.

5. **`perPlatform` grouping with mutable intermediate arrays** — `groups.get(origin) ?? []` returns a new array if the key is absent, but `groups.set(slice.origin, group)` sets it. If `groups.get` returns an existing array, pushing to `group` mutates it in place inside the Map. This is correct. Confirm no double-push or missed-push is possible when multiple slices share an origin.

6. **`index.ts` re-export conflict** — `slice-entry.ts` re-exports `SliceReducer` and `SliceEntry`. Check whether any names exported from `slice-entry.ts` conflict with names already exported from the other modules in `index.ts` (e.g. `sliceEntrySchema` conflicting with something in `state-json.ts`).

#### Diff-derived attack surfaces

1. **Output stability across schema-version drift** — does the `STATE_JSON_SCHEMA_VERSION` bump from 6 to 7 break any consumers reading prior-version output (e.g. the CLI test fixture that hardcodes `schema_version: 6`, hook-binary.ts that writes `schema_version: 6`)? Probe whether `stateJsonV1Schema` still accepts schema_version 6 after the bump.

2. **CLI flag/arg symmetry** — N/A for this ticket; no CLI flags added or changed. This is a pure contracts change.

3. **Error-class breadth in `catch` blocks** — N/A; no try/catch blocks introduced. All new code is pure functional Zod schemas and reducers.

4. **Defensive layering at module boundaries** — `sliceToStateJson` is the only new cross-module boundary. It receives a `SliceEntry` (already Zod-validated by the caller if using `sliceEntrySchema.parse()`) and returns a `StateJsonV1`. Probe whether the function defensively handles values that pass TypeScript type-checking but might be semantically invalid (e.g., an `updated_at` string that is a valid datetime but in an unexpected timezone format).

5. **Cross-file atomicity windows** — N/A; pure in-memory functions, no multi-step writes.

6. **Test-contract strength** — Do the new tests assert the tiebreak is order-independent (not just array-order-dependent)? Do they cover the case where two slices have identical `updated_at` strings? Do they test that optional fields pass through `sliceToStateJson` correctly?

7. **Doc-vs-code drift in the ticket Rationale** — The Rationale says the attention sub-schema is "defined inline in `slice-entry.ts` to avoid re-exporting it from `state-json.ts`." Verify this matches the actual implementation. Also verify the Rationale's claim that "the CLI writer still emits `schema_version: 6` (hardcoded)" matches the current `hook-binary.ts`.

### Diff context

Key changes in this diff:

1. **New file `packages/contracts/src/slice-entry.ts`** (101 lines): defines `sliceEntrySchema` (Zod, 14 fields), `SliceEntry` type, `SliceReducer<T>` generic type, `IDLE_DEFAULT` sentinel, `sliceToStateJson` mapper, `latestSlice` string-comparison reducer, and exports `globalAggregate` and `perPlatform` as `SliceReducer<StateJsonV1>` and `SliceReducer<Record<string, StateJsonV1>>` respectively.

2. **`state-json.ts`**: single-line change: `STATE_JSON_SCHEMA_VERSION = 6` → `7`.

3. **`index.ts`**: one export line added (`export * from "./slice-entry"`).

4. **`state-json.test.ts`**: five test description/assertion changes to reflect the v7 bump; forward-compat test updated to accept 7 and reject 8; v5-field-required payloads added for the v7 acceptance tests.

5. **New file `packages/contracts/src/slice-entry.test.ts`** (184 lines): tests for `sliceEntrySchema` validator, `globalAggregate` (empty/single/multi-slice tiebreak cases), and `perPlatform` (distinct origins, multi-session collapse, empty set).

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
- **Do not use `---` horizontal rules anywhere in the report.** A `---`
  inside the `Advisory Observations` body breaks the all-bullets parser
  check, causes fallback to paragraph mode, and preserves `- ` prefixes
  on every observation key — creating verbatim-match churn in the
  downstream dispositions file and forcing `---` itself to be triaged as
  a fake observation. Just omit `---`.
- **`Runner termination` must be the section heading**, not `**runnerStatus:**
  \`completed\`` or any other inline key-value variant. Write it as the bold
  span `**Runner termination**` on its own line, then `runnerStatus:` and
  `terminatedReason:` as plain-text lines below. Any other format leaves the
  termination block inside the `Advisory Observations` body.
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
```
