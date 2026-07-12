# Phase 16: Advisory Observations Triage

**Delivery status:** Product plan approved; delivery decomposition written.

## TL;DR

**Goal:** Make subagent-review `Advisory Observations` actionable after a phase lands by giving SOA a first-class post-phase triage lane with explicit dispositions.

**Ships:**

- A supported `/soa triage-advisory-observations phase-XX` workflow for completed phase work.
- A structured disposition record for each advisory observation: patched, rejected, deferred, already-covered, or converted-to-ticket.
- A post-phase invocation model: run after phase closeout lands on `main`, before the next phase starts.
- Reconciliation visibility for suspicious subagent-review artifacts, especially `clean/completed` ledger rows with empty or missing report prose.
- Documentation that keeps the adversarial review prompt narrow while giving advisory observations a durable follow-up lifecycle.

**Defers:** Any broadening of the adversarial review prompt, automatic patch application, mandatory per-ticket triage before PR open, and general architecture-review behavior.

---

Phase 15 proved that the current subagent-review artifact triplet is honest about runner termination, but incomplete as a delivery audit trail. The ledgers point to raw reports, yet they do not record whether non-blocking advisory observations were patched, rejected, deferred, or converted into follow-up work. The Phase 15 ad-hoc Claude triage on `main` was the right operational pattern, but it lived in a commit message and manual judgment rather than a supported SOA pathway.

This phase turns that pattern into a first-class post-phase workflow. The adversarial review prompt stays ticket-local and focused; SOA adds a separate closure mechanism for non-blocking but real findings after the whole phase is visible.

## Phase Goal

This phase should leave the product in a state where:

- A developer can run a supported SOA triage flow after a completed phase lands on `main` and see every non-empty `Advisory Observations` item grouped by source report.
- Each advisory observation receives an explicit disposition and rationale, so future readers do not have to reconstruct decisions from raw prose and commit history.
- Patched items can reference the relevant commit, while rejected, deferred, already-covered, and converted-to-ticket items are recorded without implying they should have blocked the original ticket.
- Phase-level closeout and follow-up work can detect untriaged advisory observations instead of letting them disappear inside report sidecars.
- Empty or missing report prose behind a `clean/completed` subagent-review ledger row is surfaced as a suspicious artifact that requires human attention.

## Committed Scope

### Post-phase advisory observation triage

- Establish `/soa triage-advisory-observations phase-XX` as the supported pathway for reviewing subagent-review advisory observations after a phase lands on `main`.
- Make the intended invocation point explicit: post-phase, before the next phase begins, not inside the per-ticket pre-PR delivery loop.
- Treat the triage as a decision-recording workflow, not as a second review pass and not as an automatic implementation step.

### Finding dispositions

- Record a disposition for each advisory observation:
  - `patched`
  - `rejected`
  - `deferred`
  - `already-covered`
  - `converted-to-ticket`
- Require concise rationale for non-patched dispositions.
- Allow patched findings to cite the commit that addressed them.
- Preserve the distinction between actionable findings that block reconciliation and advisory observations that deserve phase-level judgment.

### Artifact honesty

- Make advisory-observation triage durable enough that a future reader can answer: what did the subagent flag, what did the primary do, and why?
- Surface suspicious artifact states, especially a `clean/completed` ledger row whose `rawOutput` report is empty or missing.
- Keep the existing subagent-review ledger semantics intact: runner outcome remains runner outcome; advisory-observation disposition is a separate decision record.

### Documentation and operator guidance

- Update SOA docs so operators know when to run the advisory-observation triage flow.
- Document that the correct timing is after phase closeout lands on `main`, matching the Phase 15 ad-hoc triage pattern.
- Clarify that the adversarial review prompt should remain narrow; the advisory-observation triage lifecycle is the pressure-release mechanism for broader observations.

## Explicit Deferrals

- **Prompt broadening:** The adversarial review prompt stays focused on ticket-local invariants and directly related attack surfaces. Broad architecture review remains out of scope.
- **Automatic patching:** The triage flow records and guides decisions; it does not apply patches on its own.
- **Per-ticket pre-PR requirement:** Advisory-observation triage is not added as another gate before every ticket PR opens. That would turn phase-level judgment into ticket-local ceremony.
- **External AI review triage:** This phase is about subagent-review report sidecars, not CodeRabbit/Qodo/GitHub review handling.
- **General retrospective automation:** The workflow may feed retrospectives, but it does not replace phase retrospectives or generate them end to end.
- **Historical backfill across all prior phases:** Phase 15 is the motivating example. Wider historical migration is optional follow-up, not exit scope.

## Exit Condition

Phase 16 is done when SOA has a documented, supported post-phase pathway for triaging `Advisory Observations` from subagent-review reports, recording explicit dispositions and rationales, and surfacing suspicious missing/empty report evidence. A developer should be able to inspect the phase artifacts and know which advisory observations were patched, rejected, deferred, already covered, or converted into future work without relying on commit-message archaeology.

## Retrospective

`required` — This phase changes operator workflow and artifact semantics around subagent-review closure. It should capture whether post-phase timing reduced ceremony while preserving useful review findings.
