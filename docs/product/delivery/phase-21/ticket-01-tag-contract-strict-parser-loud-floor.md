# P21.01 Tag-based report contract: strict parser, template rewrite, record-time loud floor

Size: 3 points
Type: feat
Scope: review
Red: required

## Outcome

- `parseActionableFindings` and `parseAdvisoryObservations` (`tools/delivery/reconciliation.ts`) extract content exclusively from balanced tag blocks (`<actionable-findings>…</actionable-findings>`, `<advisory-observations>…</advisory-observations>`), modeled on `parseRefactorSuggestions` in `tools/delivery/refactor-review.ts`.
- `parseActionableFindings` returns a structured result carrying the parsed findings list (count available to later tickets), not a bare boolean; existing boolean call sites read from the structured result.
- Runner termination metadata (`runnerStatus`, `terminatedReason`) is read from a `<runner-termination>` tag block; the classification coercers (`coerceCodexCliClassification`, `coerceClaudeCliClassification`, `coerceCursorCliClassification` in `tools/delivery/subagent-runner.ts`) no longer scan prose tails.
- The heading-grammar machinery is deleted: `CANONICAL_REPORT_SECTION_HEADINGS`, `extractReportSection`, `stripHorizontalRules`, the bullet-vs-paragraph fallback, heading aliases, and the runnerStatus terminator regex. No `## heading` fallback exists.
- A zero-parse loud floor fires at `subagent-review` record time (`tools/delivery/cli-runner.ts`): a tag block that is missing, malformed (unclosed/misnamed), or empty without the literal `None` prints a warning while the primary agent is in-session. Literal `None` is silent. Triage-time surfacing remains as backstop.
- `docs/template/delivery/adversarial-review-template.md` and `docs/template/delivery/subagent-review-report-template.md` present copy-me tag skeletons for all three machine-read regions; the prose do/don't ruleset (the enumerated failure-mode paragraphs) is deleted; invariant/surface prose stays markdown.
- `docs/template/delivery/delivery-orchestrator.md` documents the consumer upgrade rule: do not update son-of-anton between a phase's first `subagent-review` and its `triage-advisory-observations`.

## Red

- Write failing tests in `tools/delivery/test/` covering the design note's regression checklist (`notes/public/subagent-report-parser-contract.md` §Implementation checklist item 4):
  - a tagged block with bullets parses to the correct findings/observations;
  - literal `None` inside the tags → clean-empty, no warning;
  - missing close tag → parses to EOF and flags for the warning;
  - misnamed tag (`<advisory_observations>`), legacy `**bold**` heading, `## ATX` heading, and plain-text heading formats → 0 parse + warning flag (proves the floor catches historical failures #1 and #4);
  - `runnerStatus:` prose outside the tags is ignored by section extraction (proves #3/#5 cannot leak).
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P21.01): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Implement tag extraction in `reconciliation.ts` following the `parseRefactorSuggestions` shape: last open tag wins, close tag or EOF, case-insensitive tag-name match, trimmed-line normalization, literal `None` detection.
- Return a parse-health signal (found/closed/explicit-none) alongside content so the record path can warn precisely.
- Wire the warning into the `subagent-review` record path in `cli-runner.ts`; do not add a retry loop or re-invocation.
- Update the two templates and the coercers; delete the retired machinery and its tests.

## Refactor

- Extract any tag-parsing helper shared between `refactor-review.ts` and `reconciliation.ts` only if the two remain genuinely identical after both are in tag form — do not force a premature abstraction.
- Only refactor what you touched — no opportunistic cleanup.

## Review Focus

- Strictness: confirm no tolerance heuristic survives — grep for the deleted identifiers; any heading-recognition remnant reintroduces the silent-failure surface this ticket exists to remove.
- The warning fires exactly when the design note says (present-but-malformed, empty-without-None, missing tag) and never on a genuinely clean `None` report.
- Template skeletons are copy-me literal — an agent following the template verbatim must produce a report the strict parser accepts.
- Downstream consumers of the old boolean `parseActionableFindings` behave identically for the clean/none case.
- Intentionally deferred: legacy heading fallback (rejected by phase decision); the outcome-label change (P21.02).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
