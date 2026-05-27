# Codogotchi Phase 04–05 Roadmap Summary

_Recommended ladder as of 2026-05-25_
_Status: Draft — not yet through `/soa plan`_
_Cross-reference: [codogotchi-alignment-draft](../../.son-of-anton/notes/public/codogotchi-alignment-draft.md) (son-of-anton subtree), [Phase 03 plan](../../docs/product/plans/phase-03-soa-aware-pet-animation-coverage.md)_

---

## Recommendation

Renumber the ladder:

- **Phase 04 = SoA hook hardening** (alignment draft)
- **Phase 05 = Floating Pet + SpriteKit** (what the Phase 03 plan called Phase 04)

Push Social Drama and Public Launch later. Do not jump straight to the floating window or the web armory.

---

## What we've done

### Shipped (code exists; closeout may still be pending)

| Phase | Goal | Status |
| --- | --- | --- |
| **01 — CLI + Convex** | XP/HP/loot pipeline, hook binary, contracts, Convex backend | Delivered (P1.01–P1.22) |
| **02 — Menu bar pet** | 4 floor states, failure visuals, demo mode, transition log | Delivered (P2.01–P2.11) |
| **03 — SoA-aware pet** | 15 states render, codogotchi sheet, schema v2, pet config, demo extended | Delivered (P3.01–P3.08) |

### Cross-repo (SoA side, not codogotchi phases)

| Work | Status |
| --- | --- |
| SoA Phase 15 — `.soa/events.ndjson` writer + `codogotchi.enabled` gate | Shipped upstream |
| `codogotchi-alignment-draft.md` written | Draft exists in son-of-anton |
| Codogotchi alignment phase in codogotchi repo | Not planned or delivered |

### Original public-web vision (May 16 drafts)

The three drafts (`phase-1-cli-armory`, `phase-2-social-health-drama`, `phase-3-pet-gallery-community`) describe **codogotchi.pro, OAuth, leaderboard, friends, guilds, Discord bot**. The product pivoted to **macOS-first + SoA soul**. Treat those drafts as **long-horizon backlog**, not the current ladder.

---

## What we haven't done yet

### Phase 03 loose ends (owner work, not new phases)

- [ ] Run `docs/runbooks/phase-03-validation.md` and attest exit conditions 2–4 (live SoA delivery + rare synthetic states)
- [ ] Closeout-stack merge for Phase 03 PRs (#35–#44) if not done yet

### Alignment draft — mostly undone

| # | Item | Done? |
| --- | --- | --- |
| 1 | Hook path resolution audit (`CLAUDE_PROJECT_DIR` / `CODEX_PROJECT_DIR` / cwd) | Partial — some tests, no full audit |
| 2 | Tail/inode integration tests (incremental append, inode reset, partial-line guard) | Partial — tail offset test exists; inode reset + partial line missing |
| 3 | Full read→parse→map pipeline for all 5 Phase 15 gate events | Partial — mapping tested ad hoc, not exhaustive |
| 4 | Precedence rule verification | Partial — a few tests in P3.02 + `hook-binary.test.ts` |
| 5 | Document `codogotchi.enabled` in codogotchi docs/troubleshooting | Not in codogotchi `docs/` |
| 6 | Stale SoA reference audit in contract docs | Partial — P3.08 swept renderer drift, not SoA CLI staleness |

### Deferred from plans (not started)

- Floating window / NSPanel / SpriteKit + mouse-interaction rows (was "Phase 04" in the Phase 03 plan)
- HP overlays, death/ghost visuals (was "Phase 05 Social Drama")
- Pet catalog / picker UI (Phase 06)
- Public launch — web armory, OAuth, Twitter (Phase 04+ in the original ladder)
- Distribution polish — signed installer, Sparkle, launch-at-login
- Everything in the three May 16 web/community drafts

---

## Phase 04 — SoA Hook Hardening

**Why first:** Phase 03 made Mali _look_ right. This phase makes the hook _provably_ right. Small scope (~3 tickets), closes silent-failure risk on the soul path, and builds confidence before adding a second UI surface (floating window).

| Ticket | Ships |
| --- | --- |
| **04.01** | Path resolution + tail semantics — env var resolution tests, incremental append, inode reset, partial-line guard |
| **04.02** | Mapping + precedence — all 5 Phase 15 events through full file-read pipeline; unknown/malformed line handling; precedence matrix |
| **04.03** | Docs — `codogotchi.enabled` troubleshooting in `soa-event-feed.md` + setup guide; stale SoA reference audit on contract docs |

**Exit condition:** Test output demonstrates the hook read path is correct — not just "demo mode looks fine."

**Source:** [`codogotchi-alignment-draft.md`](../../.son-of-anton/notes/public/codogotchi-alignment-draft.md) in the son-of-anton subtree.

---

## Phase 05 — Floating Pet + SpriteKit

**Why second:** Biggest user-visible macOS upgrade after the menu bar. Consumes the three reserved Codex rows (`running-right`, `running-left`, `jumping`). Builds on a hardened hook, not a shaky one.

| Area | Ships |
| --- | --- |
| **Surface** | Float-on-top `NSPanel` / SpriteKit window alongside menu bar |
| **Animation** | Mouse-interaction rows from Codex sheet |
| **Integration** | Same `state.json` polling; shared renderer patterns from Phase 02–03 |
| **Defers** | HP UI, public web, pet catalog |

**Source:** Phase 03 plan deferrals and updated ladder in [`docs/product/plans/phase-03-soa-aware-pet-animation-coverage.md`](../../docs/product/plans/phase-03-soa-aware-pet-animation-coverage.md).

---

## After that (directional, not locked)

| Phase | What | Source |
| --- | --- | --- |
| **06** | Social Drama — HP bar, death/ghost, mood tints on macOS (and eventually web reveal) | Phase 03 deferrals + `phase-2-social-health-drama` draft |
| **07** | Pet catalog — picker UI, multi-pet, displayName | Phase 03 deferrals + `phase-3-pet-gallery-community` draft |
| **08+** | Public launch — codogotchi.pro, OAuth, leaderboard | Original Phase 01/02 ladder + `phase-1-cli-armory` draft |

---

## Ironman (why someone would disagree)

A smart person would say: _"You're n=1. The hook works in practice. Phase 03 already added precedence tests. Floating window is the exciting next thing — alignment is yak-shaving. Fold any missing tests into one ticket and ship the float."_

That doesn't change the recommendation because: (1) alignment is already scoped to ~3 tickets, (2) Phase 03 exit attestation isn't done yet, (3) a floating window doubles the debugging surface — if tail semantics are wrong, you'll chase ghosts across two renderers, and (4) the alignment draft was explicitly written as the next codogotchi phase after SoA Phase 15.

---

## Next move

1. Run the Phase 03 validation runbook once (closes the attestation gap).
2. `/soa plan` the alignment draft as **Phase 04 — SoA Hook Hardening**.
3. Only after Phase 04 merges, `/soa plan` the floating window as **Phase 05**.
