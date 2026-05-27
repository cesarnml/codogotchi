# P3.08 Retrospective + scoped doc-drift sweep

Size: 1 point
Type: docs
Scope: docs
Red: skip

## Outcome

- `docs/product/retrospectives/phase-03-soa-aware-pet-retrospective.md` is written using the canonical structure from the `soa-write-retrospective` skill. Captures: what went well, what surprised, what was deferred to follow-ups, lessons for future phases (esp. Phase 06 catalog).
- The retrospective explicitly addresses:
  - **Schema v2 bump precedent.** First version bump after the contract's initial lockdown — what we learned about the policy's "exactly one P1.18 revision" clause and how Phase 03 invoked the "further changes require a new ticket" path.
  - **Codogotchi spritesheet commissioning learnings.** Cost (actual vs. ~$11 estimate), turnaround time, frame-quality issues encountered, what would carry forward into Phase 06's catalog where multi-pet asset workflows live.
  - **Cross-repo soul dependency on SoA.** Phase 15's event emission as a satisfied dependency — what worked, what was bumpy, whether the producer/consumer contract held up.
  - **Lockstep vs. renderer-first release.** Phase 03 shipped lockstep (n=1). Document renderer-first as the n>1 default for future phases that have actual external consumers.
- Phase 02's open strategic question is **closed** in the retrospective: "Richer pet format vs. atlas extension vs. premium-tier image generation" → Phase 03 picked the **atlas extension** path (new codogotchi-owned sheet + Codex sheet coverage expansion). Empirical result recorded.
- Scoped doc-drift sweep updates (in-scope per the grilling):
  - `README.md` — new commands, new file paths (`~/.codogotchi/config.json`), new menu items.
  - `docs/contracts/animation-state-vocabulary.md` — cross-reference verification against what the renderer actually implemented. Fix any drift between the spritesheet layout I wrote during this conversation and what P3.04 actually shipped.
  - `.son-of-anton/docs/template/overview/start-here.md` — phase status, delivered scope, current ladder. Per the SoA rule: this file is under `.son-of-anton/` and is read-only — sweep updates target the *consumer-repo equivalent* docs only, not the upstream template. If the consumer repo lacks an `start-here.md` equivalent, this bullet is N/A.
  - `docs/product/plans/phase-02-menu-bar-pet-foundations.md` (or `phase-02-as-shipped-ci-macos-tests.md`) — strike-through or footnote on the closed open strategic question.
- Out-of-scope for the sweep (explicitly): net-new docs that should have been their own ticket, cross-phase doc cleanup unrelated to Phase 03 work, speculative future-phase doc seeding.

## Red

Doc-only ticket. `Red: skip` per the canonical template's doc-only rule.

## Green

- Invoke the `soa-write-retrospective` skill (or follow its canonical section structure manually) to produce the retrospective at `docs/product/retrospectives/phase-03-soa-aware-pet-retrospective.md`.
- Run the doc-drift sweep against the in-scope files listed in Outcome. Each file's diff should be small and surgical — phase status updates, new feature mentions, contract cross-reference corrections. Resist the urge to opportunistically rewrite.
- The Phase 02 plan's open strategic question closure is documented in the Phase 03 retrospective itself — Phase 02's plan file gets a one-line footnote or strike-through, not a rewrite.

## Refactor

- Verify all internal links in updated docs resolve. Run `grep -rn 'docs/contracts/' docs/` against changed paths to spot stale references.
- Confirm the README setup section covers config file editing as a basic-onboarding step now that pet swapping is user-configurable.

## Review Focus

- The retrospective covers the four locked Phase 03 lessons (schema bump precedent, asset commissioning, cross-repo dependency, lockstep vs. renderer-first).
- The Phase 02 open strategic question is closed with an honest empirical answer, not a hand-wave.
- The doc-drift sweep stayed in-scope. Net-new docs or cross-phase cleanup should be deferred to follow-up tickets, not bundled here.
- READMEsetup section, if changed, accurately reflects the post-Phase-03 user workflow: install hook → drop pet in `~/.codex/pets/<name>/` and (optionally) `~/.codogotchi/pets/<name>/` → edit `~/.codogotchi/config.json` → run menubar app.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first — N/A for doc-only]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
