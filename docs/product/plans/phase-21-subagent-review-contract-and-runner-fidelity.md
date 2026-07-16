# Phase 21: Subagent-Review Contract and Runner Fidelity

**Delivery status:** Decomposition complete, preflight PASS — ready for `/soa execute phase-21`.

Origin issue: #78
Origin issue: #83
Origin issue: #84
Origin issue: #87
Origin issue: #105

> Multi-issue note: `parseOriginIssueNumber` supports a single issue today. This
> phase extends the mechanism to accept multiple `Origin issue: #<N>` lines (see
> Committed Scope); until that ticket lands, only the first line is honored.

## TL;DR

**Goal:** Make the subagent-review lane trustworthy end to end — the report parses by explicit contract instead of heading inference, the recorded outcome tells the truth, the fallback chain actually falls back, the operator controls (and the ledger records) which model reviewed at what effort, and the developer hears about the outcome without watching the terminal.

**Ships:**

- Tag-based machine-read contract for `subagent-review.report.md` (`<actionable-findings>`, `<advisory-observations>`, tagged runner-termination block) with a strict, barebones parser and a record-time zero-parse loud floor — per the converged design in `notes/public/subagent-report-parser-contract.md`, extended to all three machine-read regions.
- Honest outcome classification (#83): `clean` is recorded only when the report's actionable-findings block is genuinely empty; a completed review with findings gets a distinct label.
- Subagent-review milestone notification (#87): one notification per recorded outcome, with clean vs. has-findings clearly differentiated.
- Per-platform model and thinking-effort selection for subagent runners (#78): flag > config > platform default precedence, fail-fast validation, resolved model/effort recorded on every ledger invocation row.
- Fallback correctness (#105): a runner that spawns and exits but produces no usable review advances the chain; `skipped` is reserved for exhaustion of every runner.
- Review-gap ledger absorption (#84): a promotion writeup mined from codogotchi's 54-row ledger, and promotion of any class at the ≥2–3× bar (currently `control-signal-starved-by-change-gated-callback`, 3×) onto the freshly-tagged `adversarial-review-template.md`.
- Multi-issue Origin-close support: multiple `Origin issue: #<N>` lines yield one `Closes #<N>` bullet each on the final ticket's PR body; preflight format check updated to match.

**Defers:** Legacy heading-format parsing fallback, cross-family review enforcement, auto model selection from diff stats, red/green TDD gate notifications, a phase-level integration review pass, Discord notification transport (#86).

---

Phase 20 shipped the refactor-review gate with a tag-based `<refactor-suggestions>` contract; the adversarial gate still parses its report by markdown-heading inference, which has broken five documented times across phases 05, 08, and 17 — each failure silent, some discovered phases later. Meanwhile codogotchi's 120 subagent-review invocations exposed three fidelity gaps in the same lane: `clean` recorded despite findings, a broken preferred runner ending the chain without fallback, and no record of which model actually reviewed. The parser redesign is already converged in `notes/public/subagent-report-parser-contract.md`; this phase implements it and fixes the fidelity gaps on top of it, in dependency order.

## Phase Goal

This phase should leave the product in a state where:

- A subagent-review report's machine-read regions are extracted by balanced tags with no heading recognition, and a malformed or empty-but-not-`None` block warns loudly at `subagent-review` record time — never a silent zero-parse.
- A ledger row reading `clean` guarantees the report listed no actionable findings; a completed-with-findings review is distinguishable at a glance.
- With a deliberately broken preferred runner, the orchestrator visibly attempts the next runner in `PROGRAMMATIC_SUBAGENT_RUNNERS` order before ever recording `skipped`.
- An operator can pin model and effort per platform via config or flag, invalid values fail fast, and every ledger invocation row shows the model/effort actually used.
- The developer's phone shows the subagent-review outcome (clean vs. N findings) as a delivery milestone.
- The adversarial-review prompt carries every codogotchi review-gap class that met the promotion bar, and a written analysis accounts for every review-reachable ledger row — including the ones not promoted and why.
- A phase resolving multiple GitHub issues closes all of them via `Closes` bullets on the final PR.

## Committed Scope

### Report contract migration (tags + strict parser + loud floor)

- Replace heading-based extraction in `reconciliation.ts` with balanced-tag extraction for all three machine-read regions: actionable findings, advisory observations, runner termination.
- Delete the accreted tolerance heuristics (heading aliases, `---` stripping, bullet-vs-paragraph fallback, runnerStatus terminator regex). Forward-only: no legacy heading fallback.
- Zero-parse loud floor at `subagent-review` record time: tag missing/malformed/empty-without-`None` prints a warning while the primary agent is in-session; triage-time surfacing remains as backstop.
- Rewrite `adversarial-review-template.md` and `subagent-review-report-template.md`: copy-me tag skeletons replace the prose do/don't ruleset.
- Documented upgrade rule for consumers: do not update son-of-anton between a phase's first `subagent-review` and its `triage-advisory-observations`.

### Outcome honesty (#83)

- Cross-check runner self-report against the tag-parsed actionable-findings block; `runnerStatus: completed` no longer maps to `clean` when findings exist.
- Terminology pass: templates and orchestrator docs consistently distinguish "runner completed" from "review clean."

### Subagent-review milestone notification (#87)

- New delivery notification event for the recorded subagent-review outcome, emitted best-effort from the `subagent-review` command path, with message text that differs meaningfully between clean and has-findings. Built after #83 so the notification carries the honest label.

### Runner invocation controls (#78)

- Per-platform model and effort selection: CLI flag > `orchestrator.config.json` > platform default; forwarded into each platform CLI's documented flags.
- Invalid model/effort values fail fast with actionable errors.
- Ledger invocation rows record resolved model and effort (or explicit default/null).

### Fallback correctness (#105)

- A `ran` result whose `terminatedReason` indicates no usable review (at minimum `runner_failed`) triggers fallback to the next runner; `skipped` only after the whole chain is exhausted.

### Review-gap ledger absorption (#84)

- Analysis writeup accounting for every review-reachable row in codogotchi's `ledger.jsonl`, recurrence counts verified, promotion-bar verdict per class, and an explicit not-promoting list with reasons.
- Promote classes at the ≥2–3× bar as probeable attack-surface clauses in `adversarial-review-template.md` — sequenced after the template's tag migration so the template churns once.

### Multi-issue Origin close

- `parseOriginIssueNumber` (or successor) accepts multiple `Origin issue: #<N>` lines; final ticket's PR body carries one `Closes` bullet per issue; preflight's format check covers the multi-line form.

## Explicit Deferrals

- **Legacy heading-format parsing fallback** — rejected by decision, not deferred by omission: any heading-inference path reintroduces the silent-failure surface the redesign removes; the loud floor plus the upgrade rule cover the transition.
- **Cross-family review enforcement** (primary agent ≠ subagent platform as a hard gate) — remains operator choice plus ledger audit, per #78's own scope line.
- **Auto-selecting model/effort from ticket size or diff stats** — no evidence yet on which knob correlates with review quality; revisit once ledger rows carry model/effort data this phase adds.
- **Red/green TDD gate notifications** — fire many times per ticket; explicitly excluded by #87 as noise, owned by the animation layer.
- **Phase-level integration review pass** — the promotion-queue caveat that some gaps are only review-reachable when both halves ship in one diff is real, but it is a new review lane, not a prompt clause; needs its own design before any phase commits to it.
- **Discord notification transport** — tracked separately as #86; #87 ships against the existing notifier.

## Exit Condition

A delivery run on this repo completes a subagent review whose report is extracted purely by tag contract, records an outcome that matches the report body, notifies the outcome, and shows resolved model/effort on the ledger row. The later tickets of phase-21 itself are reviewed under the contract shipped by its earlier tickets — the phase dogfoods its own gate. Killing the configured preferred runner mid-phase demonstrates fallback advancing instead of recording `skipped`. The final PR closes #78, #83, #84, #87, and #105 via generated `Closes` bullets, and `adversarial-review-template.md` carries the promoted `control-signal-starved-by-change-gated-callback` clause (plus any other class the verified counts put at the bar).

## Retrospective

`required` — this phase replaces a durable boundary (the report parser contract every future review crosses) and changes operator workflow twice (notifications, model/effort config); the parser-contract note makes a falsifiable prediction — that the tag contract plus loud floor ends the drift arms race — and the retrospective is where that verdict lands. Trigger: architecture/process impact.
