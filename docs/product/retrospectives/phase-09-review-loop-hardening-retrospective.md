# Phase 09 Retrospective — Review Loop Hardening

## Scope delivered

Three tickets landed via stacked PRs [#30](https://github.com/cesarnml/son-of-anton/pull/30), [#31](https://github.com/cesarnml/son-of-anton/pull/31), and [#32](https://github.com/cesarnml/son-of-anton/pull/32) (squash-closeout to `main`):

- **P9.01 — Billing noise pre-filter** — Structural filter for vendor billing / account-limit noise (bot login + no fenced code block) so triage can return `clean` without manual `record-review` overrides for that class of comment.
- **P9.02 — TDD gate hardening** — `post-red` command and `red_complete` status; orchestrator verifies a failing test run before advancing past red on non-doc-only tickets; closes the `[red]` subject-only loophole.
- **P9.03 — Exit hygiene** — Non-blocking `post-verify` warning when the working tree has uncommitted changes; `cspell.json` ignore path for delivery review artifacts; ticket template doc-only Red exemption; README install note; this retrospective.

## What went well

**Grill-me decisions were written into the plan.** Doc-only classification including `.json`, hard vs warn `post-red`, and the billing heuristic shape reduced mid-flight ambiguity.

**TDD red gate is now machine-checked.** Linking advance to an observed non-zero test exit matches how humans interpret “red means failing tests,” not just a commit message convention.

**Primary vs worktree state.** Mirroring `.agents/delivery/phase-09/state.json` and `docs/.../reviews/` into the primary checkout before closeout avoided stale `state.json` blocking `closeout-stack` — a pattern worth repeating whenever delivery runs from per-ticket worktrees.

## Pain points

**`closeout-stack` and `loadState` return shape.** `loadState` returns `{ state, hadPersistedRunPolicy }`; `closeout-stack` briefly treated the whole object as `DeliveryState`, which crashed at `state.tickets`. Fixed on `main` by destructuring `{ state }`. Lesson: integration tests that invoke `runCloseoutStack` with a real `state.json` would catch this class of drift.

**Uncommitted triage after `record-review patched`.** `updateTriageArtifact` persisted `needs_patch` → `patched` (and thread resolutions / `prBodyRefresh`) to disk but nothing staged or committed, so every `needs_patch` → `record-review` cycle left a dirty `*-ai-review.triage.json`. **Follow-up in this repo:** `record-review` now stages and commits the triage (and paired fetch JSON when present) inside a git checkout, with a mechanical `chore(delivery): ...` subject. Ephemeral cwd / non-repo contexts skip the commit best-effort.

**Stacked delivery and local commits on `main`.** Running `closeout-stack` after a local commit on `main` that was never pushed resets to `origin/main` and drops that commit from the branch tip. Push tooling fixes before closeout, or land them through the stack.

## Surprises

**CodeRabbit “summary” kind vs inline findings.** The billing-noise guardrails relied on comment shape; documenting `kind: "summary"` behavior in the fetcher contract helped keep walkthrough noise out of the billing filter path.

## What we would do differently

**Automate primary mirroring sooner in long sessions.** A single reminder in `status` when worktree `state.json` is ahead of primary would reduce “closeout says incomplete ticket” confusion.

**Consider the same commit behavior after `poll-review` writes fresh artifacts** if dirty trees show up there in practice; this retrospective only required the `record-review` path for the observed regression.

## Net assessment

Phase 09 met its product contract: billing-only escalation is structurally damped, the red gate is enforced with evidence of test failure, `.json`-only branches align with doc-only skips, `post-verify` surfaces uncommitted work as a warning, and CI stayed green through delivery.

## Follow-up

- Optional: extend artifact auto-commit to other orchestrator paths that write review JSON if similar dirtiness appears.
- Consumer repos: run `soa update` / skill sync to pick up ethos and pr-review wording that reflects the new `record-review` commit behavior.

---

_Created: 2026-05-14. Phase closeout completed on `main`._
