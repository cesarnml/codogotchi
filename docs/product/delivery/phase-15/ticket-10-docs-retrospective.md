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

Red first: [n/a — doc/version-only ticket]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [record any deviation from the ticket metadata contract here]
