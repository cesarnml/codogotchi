# P19.03 Quality-control skill and /soa dispatcher

Size: 3 points
Type: feat
Scope: quality-control
Red: required

## Outcome

- `.agents/skills/quality-control/SKILL.md` defines the post-phase quality-control workflow.
- `.agents/skills/soa/SKILL.md` documents `/soa quality-control phase-NN: <description>` and `/soa qc phase-NN: <description>`.
- The entrypoint description includes quality control so the command is discoverable.
- Tests prove the quality-control skill exists and the SoA entrypoint names both command forms.

## Red

- Write a failing test that reads `.agents/skills/quality-control/SKILL.md` and expects the skill metadata and verified-fix sequence.
- Write a failing test that reads `.agents/skills/soa/SKILL.md` and expects `quality-control`, `qc`, the required `phase-NN` argument, and the new command in the description.
- Run the targeted tests and confirm they fail before implementation.
- Commit with suffix `[red]`: `test(P19.03): cover quality-control skill dispatch docs [red]`
- Do not write implementation until this commit exists on the branch.

## Green

- Add the new quality-control skill with triggers, workflow steps, stop conditions, and recording instructions.
- Update the SoA entrypoint command list and dispatcher section for `quality-control` and `qc`.
- Make the skill explicitly use the review-gap scaffold and ledger helper from earlier tickets.
- Keep the command skill-led; do not add it to `bun run deliver` as a delivery-orchestrator command.

## Refactor

- Keep repeated command wording minimal by linking the SoA entrypoint to the dedicated quality-control skill.
- Avoid duplicating the full ledger schema in the SoA entrypoint; the dedicated skill and scaffold README own that detail.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Verify `phase-NN` is required and ambiguity is handled before any fix work begins.
- Verify the skill records only after human verification and a commit.
- Verify the skill does not promise automatic prompt promotion.
- Verify tests check discoverability without overfitting to large prose blocks.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: dispatch-doc tests should fail because the quality-control skill and `/soa qc` entry do not exist today.
Why this path: a skill-led lane matches existing SoA command mechanics without adding a second orchestrator flow.
Alternative considered: add a `bun run deliver quality-control` command; rejected because QC is a guided post-phase fix and record lane, not stacked ticket delivery.
Deferred: detailed routing and promotion discipline are refined in P19.04.
Contract note: none.
