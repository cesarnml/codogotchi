# Adversarial Subagent Review Template

This template is filled in by the **primary execution agent** before invoking the review subagent. It produces the subagent's complete prompt. Do not pass a vague "find holes" directive — fill in every section from the diff and ticket spec before handing off.

**Companion template:** the subagent writes its findings into a report whose
structure is canonical, not free-form. See
[`subagent-review-report-template.md`](./subagent-review-report-template.md)
for the required section headings (`Invariant results`, `Surface results`,
`Actionable findings`, `Advisory Observations`, `Runner termination`) and
the bullet/paragraph rules. The downstream parser
(`tools/delivery/reconciliation.ts`) depends on those headings — drift
silently truncates extracted observations.

---

## How to use this template

1. Read the diff against the base branch (`git diff <base>..<head>`).
2. Read the ticket scope (outcome section and rationale).
3. Fill in the three execution-agent sections below: **Invariants**, **Attack surfaces**, and **Diff context**.
4. Pass the completed prompt to the subagent verbatim. Do not editorialize.
5. Stay idle until the subagent completes. Do not read ahead.
6. When the subagent returns, expect the report shape defined in
   `subagent-review-report-template.md`. The primary agent does not edit
   that file — the subagent owns it.

---

## Subagent prompt (fill in before invoking)

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

<paste the ticket Outcome section and any Rationale notes here>

### Files touched

Implementation:
<list each implementation file changed, one per line>

Tests:
<list each test file changed, one per line>

### Invariants to hold

<The primary agent derives these from the ticket spec. 2–3 max. Write them as testable
assertions, not goals. Example: "open-pr must throw workflow.open_pr.requires_runner_review
when subagentReview is not disabled and ticket has a non-skipped outcome but no artifact." NOT
"the gate should work correctly.">

1. <invariant>
2. <invariant>
3. <invariant if applicable>

### Attack surfaces to probe

<The primary agent derives these from the diff. List 3–6 specific surfaces — the places
in the code where an invariant could break. For each surface, name the function/path and
the class of attack.>

Examples of well-formed attack surfaces:
- `openPullRequest` fallback lookup: does the gate fire for all relevant ticket statuses,
  or can a ticket at status X reach open-pr without an artifact?
- `validateRunnerArtifact`: does passing an empty-string `reviewedHeadSha` return null, or
  does it pass structural validation?
- Path resolution in gate check: if `subagentRunnerArtifactPath` is stored as a relative
  path, does `existsSync` fail silently instead of throwing?

Surfaces for this review:
1. <function/path — class of attack>
2. <function/path — class of attack>
3. <function/path — class of attack>
...

#### Diff-derived attack surfaces

In addition to the ticket-spec-derived surfaces above, probe each of the seven
diff-derived classes below. These are the finding classes external code review
(e.g. CodeRabbit) catches consistently and the prior template did not name. The
primary agent must enumerate concrete surfaces drawn from this diff against each
class. The subagent must report coverage for every class using the form
`[probed]` / `[N/A — reason]` / `[blocked — missing-input]`.

1. **Output stability across schema-version drift** — does any persisted
   artifact, CLI stdout shape, or on-disk JSON format change in a way that
   breaks consumers reading prior-version output? Probe legacy-shape fixtures,
   adapter coverage, and version markers. Output form: `[probed]` / `[N/A —
   reason]` / `[blocked — missing-input]`.
2. **CLI flag/arg symmetry** — for every added or changed CLI flag, is the
   parser, help text, validator, and downstream consumer updated together?
   Probe each flag's read site and each producer site. Output form: `[probed]`
   / `[N/A — reason]` / `[blocked — missing-input]`.
3. **Error-class breadth in `catch` blocks** — does each new or modified
   `catch` distinguish recoverable from non-recoverable errors, or does it
   silently swallow all `Error` instances? Probe error-class matching, rethrow
   paths, and logging fidelity. Output form: `[probed]` / `[N/A — reason]` /
   `[blocked — missing-input]`.
4. **Defensive layering at module boundaries** — at every new cross-module
   call, does the callee revalidate inputs it cannot trust the caller to have
   normalized (paths, identifiers, schema shape)? Probe each new boundary
   crossing in the diff. Output form: `[probed]` / `[N/A — reason]` /
   `[blocked — missing-input]`.
5. **Cross-file atomicity windows** — does any multi-step write (state +
   artifact, commit + push, file-A + file-B) leave an observable
   partially-committed window if interrupted? Probe ordering, error-recovery,
   and re-entrant safety. Output form: `[probed]` / `[N/A — reason]` /
   `[blocked — missing-input]`.
6. **Test-contract strength** — do new tests assert the stable
   machine-readable contract (error codes, structural shape) before asserting
   prose, and do they cover both the omitted-hook and supplied-hook paths for
   optional DI? Probe assertion targets and branch coverage. Output form:
   `[probed]` / `[N/A — reason]` / `[blocked — missing-input]`.
7. **Doc-vs-code drift in the ticket Rationale** — does the ticket's
   `## Rationale`, scope contract, or referenced docs describe behavior that
   does not match what the diff actually does? Read the Rationale and contract
   docs and surface drift in **Advisory Observations** — do not patch
   ticket docs. Output form: `[probed]` / `[N/A — reason]` / `[blocked —
   missing-input]`.

### Diff context

<Paste the relevant diff hunks here, or describe the key logic changes in 3–5 sentences.
This is the starting map, not a boundary. The subagent should still read the relevant
changed files and directly related code before deciding the review is complete.>

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

---

## Notes for the primary agent

**On writing invariants:** An invariant is a machine-verifiable property, not a goal.
"The gate should work" is not an invariant. "Function F must throw error code X when
condition Y is true" is an invariant. Derive them from the ticket outcome section — if the
outcome says "open-pr is blocked unless a valid artifact exists," that is an invariant.

**On writing attack surfaces:** Read the diff for the places where the invariant could
silently fail — missing status checks, unchecked path assumptions, validation that accepts
degenerate inputs, boundary conditions in fallback chains. Name the specific function and
the specific class of failure. "The whole gate" is not a surface. "The fallback ticket
lookup in `openPullRequest` when `ticketId` is undefined" is a surface.

**On surface count:** 3–6 surfaces is the right range. Fewer means you probably missed
something in the diff. More than 6 usually means you're listing generic concerns rather
than diff-specific ones.

**On the subagent model:** Use a different model family from the primary agent when
available — cross-model review breaks shared training-distribution blind spots.
Same-type review is acceptable when cross-model is unavailable; document which was used.
