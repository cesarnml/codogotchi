# P15.10 Docs sweep + v2.2.0 bump + retrospective

Size: 2 points
Type: docs
Scope: delivery
Red: skip

## Outcome

- App version reads **2.2.0** in every authoritative surface: `Info.plist` (authoritative), `project.yml`, and the download/landing surface (`download.astro`) — kept in lockstep per the macOS release ritual. **No DMG is cut this phase.**
- User-facing docs (README / feature docs / site copy as applicable) describe per-session pets: the opt-in Enable Session Pets setting, Session Cap, per-session rename, Prune Session, and the off-by-default upgrade behavior.
- The Phase 15 retrospective is written to `docs/product/retrospectives/phase-15-per-session-pets-retrospective.md`, covering the session-scoped lifecycle (free-list numbering, sidecar rename persistence, priority eviction, rate-limited conflict bubble) and shaping the named post-Phase-15 follow-up: session-linked SoA gate/ticket attribution across codogotchi + upstream `cesarnml/son-of-anton`.

## Red

- `Red: skip` — doc/version-only ticket; the branch touches `.md`/`.json`/`.plist`/`.astro`/`project.yml` and config only. No automated test asserts doc wording. Human review at the PR is the gate.
- If the version bump touches a value covered by an existing version-consistency test, keep that test green.

## Green

- Bump the version in `Info.plist`, `project.yml`, and `download.astro` to 2.2.0.
- Sweep docs/site copy for the new session-pets behavior and the off-by-default upgrade note.
- Write the retrospective via the `soa-write-retrospective` skill.

## Refactor

- No code refactor. Do not cut, sign, or notarize a DMG — that is a separate human-gated ritual.

## Review Focus

- Version is consistent across `Info.plist` / `project.yml` / `download.astro` (the lockstep gotcha).
- Retrospective explicitly captures the deferred cross-repo SoA-gate-attribution follow-up so the next phase can pick it up.
- Docs state the off-by-default upgrade contract accurately (every platform ships Own mode, session pets unchecked; upgrading is a visual no-op).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `Red: skip` — doc/version-only ticket; no automated test asserts doc wording. Human review at the PR is the gate.
Why this path: Version bumped in all three mirrors (`Info.plist` authoritative, `project.yml`, `download.astro`), matching the exact P14.09 pattern (`CFBundleVersion` build number left at `8` — no DMG is cut this phase, so it doesn't move). README gained a `v2.2.0` paragraph (Enable Session Pets, Session Cap, rename, prune, off-by-default upgrade) following the existing per-version-paragraph convention. START-HERE.md got the version tag bump, a `session-labels.json` line in the mental-model diagram, and the Platform Settings/session-pets addition to the Settings bullet and lockstep-independence invariant — mirroring how `assignments.json` was added to the same diagram in Phase 14. Retrospective written using the `soa-write-retrospective` skill structure (Scope delivered / What went well / Pain points / Surprises / What we'd do differently / Net assessment / Follow-up), grounded directly in ticket Rationale sections and git history (`[subagent-review]`-labeled commits) rather than restating ticket outcomes.
Alternative considered: Splitting README/START-HERE changes into a separate commit from the version bump and retrospective — rejected as unnecessary churn for a doc sweep, consistent with the P14.09 precedent of one combined commit.
Deferred: Marketing site copy (`web/src/pages/index.astro` etc.) — grepped for existing feature-description language (Minimalist, per-platform, Customization) and found none; prior phases (v2.0.0, v2.1.0) didn't add site copy for these settings either, so this phase follows the same precedent and only bumps `download.astro`'s `VERSION` constant. `download.astro` shows v2.2.0 but no new DMG release is cut; the page links to `releases/latest` so the previous DMG remains live until a future release.
Contract note: No deviation from the ticket metadata contract. Discovered while implementing that the orchestrator's `isLocalBranchDocOnly` check only recognizes `.md`/`.json` files — this ticket's `.plist`/`.yml`/`.astro` changes (plus the pre-flight `e08c3c7f` hook-routing cherry-pick onto this branch) meant `post-verify` and `subagent-review` did not auto-skip the way a pure `.md`-only doc ticket would have, even though `Red: skip` correctly auto-skipped `post-red`. Documented as a "Surprises" entry in the retrospective for future doc/version-only tickets.
