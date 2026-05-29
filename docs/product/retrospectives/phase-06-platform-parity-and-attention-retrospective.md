# Phase 06 — Platform parity and attention UX retrospective

Source plan: [`docs/product/plans/phase-06-platform-parity-and-attention.md`](../plans/phase-06-platform-parity-and-attention.md).
Delivery plan: [`docs/product/delivery/phase-06/implementation-plan.md`](../delivery/phase-06/implementation-plan.md).

## Scope delivered

Tickets P6.01 → P6.09 (9/9) landed on `main` as nine squash commits
(`d163993` … `98333e7`), closing PRs
[#67](https://github.com/cesarnml/codogotchi/pull/67) through
[#75](https://github.com/cesarnml/codogotchi/pull/75). Delivered:

- Schema v3: `requesting_input` → `standby`, optional `attention` payload,
  `work_mode` stub; renderer and fixtures updated in the same ticket (P6.01);
- Sticky gate mechanic: SoA gate states persist through `tool_use` until the
  next gate or session end (P6.02);
- Bash 3-bucket heuristic + Cursor `Shell` normalization (P6.03);
- Standby attention payload, fixed summary strings, `tool.command` on
  transitions (P6.04);
- Cursor origin fix (`source_origin: "cursor"`), shell hooks, `workspace_roots`
  fallback (P6.05);
- Native `~/.cursor/hooks.json` installer + bridge vs native runbook copy
  (P6.06);
- Renderer TTL at read time via `attention.expires_at` (P6.07);
- Attention bubble UI on the floating pet with local dismiss (P6.08);
- Exit validation doc sweep, README v3, product plan marked Delivered (P6.09).

## What went well

- **Grill-me decisions held under delivery pressure.** Storing `last_gate` in
  `.hook-counters.json` (not re-reading `state.json` per hook), bundling
  contracts + renderer rename in P6.01, and fixed attention strings by
  `reason_kind` each avoided follow-on tickets or hot-path I/O that would have
  bloated the stack. The decisions were narrow enough that implementers did not
  re-litigate them mid-ticket.
- **Contracts-first gate (P6.01) matched the dependency graph.** Every hook
  ticket could assume `standby`, schema v3, and renderer row mapping without a
  broken intermediate where the hook emitted states the app could not render.
- **Renderer read-only TTL policy (P6.07).** Expiry at read time kept write
  ownership with the hook binary, reused the existing poll loop, and paired
  cleanly with P6.08 local dismiss — no competing writers on `state.json`.
- **Classification reuse for Bash and Cursor Shell (P6.03).** One prefix-match
  path for both tool names avoided a parallel `classifyShell` abstraction that
  would have drifted within a phase.
- **Cursor adapter split (P6.05 origin/shell vs P6.06 installer) matched risk.**
  Signal correctness landed before touching `~/.cursor/hooks.json`, so bridge
  users kept working while native install was opt-in via `--platform cursor`.

## Pain points

- **Closeout conflict with live main docs (avoidable waste).** While the stacked
  PRs were open, Phase 07 planning updated
  `notes/public/phase-06-animation-and-signal-research.md` on `main` (locked
  Tier 1 row mapping). Every squash merge and cherry-pick against ticket
  branches hit the same conflict; resolution was always “keep main’s locked
  spec.” Automated closeout could not finish without manual intervention.
- **Stacked-branch squash after partial landing (avoidable waste).** P6.01–P6.03
  squash-merged cleanly once the research doc was resolved; P6.04+ squash merges
  saw add/add conflicts on review ledgers and hook files because branch tips
  still contained the full stack history relative to an already-advanced `main`.
  Recovery required cherry-picking only the delta commits between adjacent
  ticket branches — correct, but not what `closeout-stack` did out of the box.
- **Nine ticket worktrees (expected cost).** Same pattern as Phase 05: gated
  delivery hygiene at the cost of disk, DerivedData, and artifact mirroring
  before closeout.
- **Exit validation attestation gap (expected cost).** P6.09 confirmed
  implementation coverage by doc sweep and unit tests; live SoA gate persistence
  and end-to-end bubble TTL sessions remain manual until a cross-process harness
  exists (called out in ticket rationale).

## Surprises

- **Phase 07 research landed on `main` before Phase 06 closeout.** The
  animation research doc was no longer a safe merge base for stacked branches
  even though ticket code did not touch most of the conflicting prose — a
  planning/doc parallel track created closeout friction unrelated to ticket
  correctness.
- **`closeout-stack` retried a manually landed P6.01.** After squash-merge +
  `gh pr close` (not GitHub merge), PR #67 stayed `CLOSED` / not `MERGED`, so a
  re-run attempted P6.01 again and cherry-picked stack commits onto already
  merged code. Future closeouts need idempotency against closed-but-not-merged
  PRs when landing manually.
- **GitHub reported PR #67 `CONFLICTING` while branch-vs-main squash was fine
  with one doc resolution.** Merge UI conflict status reflected doc drift on
  `main`, not a fundamental inability to land the ticket — easy to misread as a
  blocked stack.
- **Cursor bridge was already animating in dogfooding (Phase 05 carryover).**
  Phase 06’s win was honest `source_origin` and shell classification, not
  “Cursor works at all” — native install was additive for users who want correct
  attribution without Third-party skills.

## What we'd do differently

- **Freeze or branch shared research docs while a stacked phase is open.** If
  Phase 07 planning needs to lock animation rows before Phase 06 lands, either
  defer those commits to `main` until closeout or rebase the entire stack once
  — not both in parallel.
- **Teach closeout a “delta cherry-pick” path when squash conflicts after prior
  tickets merged.** For consumer repos with long stacks, landing ticket N via
  `git rev-list parent..branch` is more reliable than repeated squash of stale
  stacked tips; worth upstreaming to `closeout-stack` after this recovery.
- **Record per-gate live validation during delivery, not only at P6.09.** A short
  checklist row per stage gate (G1–G4) with pass/deferred would have made exit
  attestation faster and separated “code merged” from “behavior observed.”
- **Bump README / start-here when P6.06 ships native Cursor install, not only at
  P6.09.** Operators hitting `main` mid-stack still saw Phase 05 bridge-first
  copy until the doc sweep landed.

## Net assessment

Phase 06 achieved its stated product goal: stuck waving is addressed by
`standby` + attention TTL + bubble UI; gate animations can persist through
tool traffic; Cursor sessions can log honest `source_origin` and richer shell
signal; Bash explore loops map to `reviewing` instead of idle noise. The
architecture boundaries are sound — hook owns writes, renderer owns read-time
TTL, UI owns local dismiss — and deliberately set up Phase 07 (`work_mode`,
gate vocabulary, SoA direct write) without a schema v4. Closeout was messier
than delivery because doc parallel work diverged on `main`, not because the
ticket stack was wrong. Live end-to-end confirmation of gate windows and bubble
decay remains operator-manual until Phase 07’s integration harness; that gap is
acceptable for a single-operator repo but should not be mistaken for automated
proof.

## Follow-up

- Phase 07: populate `work_mode`, gate TTL on `last_gate.fired_at`, SoA direct
  write to `~/.codogotchi/state.json`, richer attention copy — per product plan
  deferrals.
- Add a minimal cross-process validation harness (hook binary → `state.json` →
  renderer read) so exit conditions 1–4 can be attested in CI, not only in
  P6.09 prose.
- Upstream to Son-of-Anton: `closeout-stack` delta cherry-pick fallback when
  squash conflicts after sequential lands; treat `CLOSED` + commits-on-main as
  skip-merged.
- Keep bridge vs native Cursor guidance prominent in README until distribution
  bundles the CLI (still deferred past Phases 05–14).

_Created: 2026-05-29. Phase closed on `main` at `98333e7`; PRs #67–#75 closed._
