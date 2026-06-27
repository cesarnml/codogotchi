# Phase 12 — Keyed-State Refactor (the v2/v3 multi-pet foundation)

> Turn the single-scalar `state.json` into an `(origin, session_id)`-keyed **slice directory** behind a reducer interface, with zero observable change to the pet, so every v2/v3 multi-pet feature becomes a later additive reducer rather than a second schema rewrite. Plus one folded-in cloud item: shared-secret hardening of `/sync`.

## Epic

Product plan: [`docs/product/plans/phase-12-keyed-state-refactor.md`](../../plans/phase-12-keyed-state-refactor.md).
Design stance: [`notes/private/per-thread-vs-per-platform-keyed-state-stance.md`](../../../../notes/private/per-thread-vs-per-platform-keyed-state-stance.md).
Roadmap synthesis: [`notes/private/phase-12-cleanup-and-v2-roadmap-synthesis.md`](../../../../notes/private/phase-12-cleanup-and-v2-roadmap-synthesis.md).

## Product contract

When this phase is complete, the codogotchi IPC substrate stores agent activity as a per-`(origin, session_id)` **slice directory** (`state.d/`) instead of a single clobbered `state.json`, read through a reducer that collapses to today's single pet. Concurrent agents no longer overwrite each other's state. Nothing a user sees changes in the pet, menubar, or gate behavior. Separately, the public `/sync` HTTP endpoint rejects writes lacking a shared secret. Every later v2/v3 surface (per-platform pets, badge-only mode, per-thread pets, the Settings > Customization render-policy picker) becomes an additive reducer + render policy over this foundation — no second schema migration.

## Grill-Me decisions locked

- **Phase identity → narrow spine.** Keyed-state refactor is the success criterion; only the debt it directly touches rides along. → Avoids a sprawling two-stack phase with no clear "done".
- **Behavior-invisible (within-branch).** Build the v2_preview checkout and the pet/menubar/gate render identically to v1.1.1. Visible reducers are later feature phases. → A refactor changes structure, not behavior.
- **Storage grain = `(origin, session_id)`, finest grain, once.** → Keying by platform now forces a second rewrite for per-thread later; the stance research (`claude-status-bar`) proved the granular key is the easy part.
- **Slice directory `state.d/<origin>:<session_id>.json`, NOT one keyed file.** → The CLI writes whole-file via atomic tmp+rename (last-writer-wins); a single keyed file re-introduces the clobber as a read-modify-write race and forces locking into a fire-and-forget hook. A directory gives each writer its own file — existing atomic rename is already correct. Matches `claude-status-bar` prior art.
- **Reducer interface lives in TS; Swift re-implements its one render reducer.** TS gets two impls (`global-aggregate` consumed by `status`; `per-platform` pure/unwired) to falsify the interface. Swift implements only `global-aggregate` for rendering. → Interface proven without dragging UX into the refactor.
- **`per-platform` reducer kept as a pure, unit-tested function, unwired.** → Falsifies the abstraction in code without any UX/Settings/layout surface.
- **Clean bump `schema_version` 6 → 7, no dual-write.** → No DMG/CLI/Convex release ships until v2 GA, so there is no in-the-wild skew window to protect; the additive dual-write was scaffolding for a problem that can't occur pre-GA.
- **Closeout onto `origin/v2_preview`, not `origin/main`; intermediate phases need not be independently shippable.** → Fast v2 development; the one-time v1.1.1→v2 migration is a v2-release-phase concern.
- **Intra-branch lockstep.** TS `STATE_JSON_SCHEMA_VERSION` and Swift `EXPECTED_STATE_SCHEMA_VERSION` bump to 7 in the same phase. → A built checkout never has a writer/reader version mismatch.
- **Stale-slice reaping = both.** `SessionEnd` best-effort deletes own slice + reader ignores slices past an mtime TTL. → Matches `claude-status-bar`; no lifecycle leak.
- **`/sync` = shared-secret hardening only.** Env-var secret + header check + CLI config field. NOT identity auth / spoofing prevention — that needs the enroll/token handshake that is leaderboard-era work. → Closes the open-internet write hole at refactor-phase size; identity-grade auth deferred to the leaderboard phase.
- **Tests = characterization (invisibility) + concurrent-write (the correctness win).** → Characterization pins the slice→state contract a reviewer can read; the concurrent-write test is red today, green after, and proves the refactor bought something.

## Ticket Order

1. `P12.01 Keyed-slice contract + reducer interface`
2. `P12.02 CLI slice-directory writer`
3. `P12.03 Swift slice-directory reader + render`
4. `P12.04 /sync shared-secret hardening`
5. `P12.05 Docs + retrospective`

## Ticket Files

- `ticket-01-keyed-slice-contract.md`
- `ticket-02-cli-slice-writer.md`
- `ticket-03-swift-slice-reader.md`
- `ticket-04-sync-shared-secret.md`
- `ticket-05-docs-retrospective.md`

## Exit Condition

Build the `v2_preview` checkout: the pet animates, the menubar updates, and SoA gates override exactly as on v1.1.1 — while under the hood activity is stored as `state.d/<origin>:<session_id>.json` slices written by the CLI and collapsed through `global-aggregate` on read. Demonstrable: (1) the TS reducer interface with two implementations and passing unit tests; (2) a concurrent-write test showing two origins produce two intact slices (red on the pre-refactor single file); (3) characterization tests mapping slice fixtures to the exact v1.1.1 `ActivityState`, including gate override and stale-TTL; (4) writer/reader both at `schema_version` 7 with no intra-branch mismatch; (5) an unauthenticated `POST /sync` rejected where it previously succeeded. No web, Settings, Swift-art, or `.son-of-anton` files touched. Cross-version v1→v2 migration is explicitly out of scope.

## CI Baseline

> Baseline recorded: 2026-06-28 — `bun run ci:quiet` on freshly-cut `v2_preview` (same SHA as `main` at phase start). Result: **all green** — 552 Swift tests + TS/Bun tests passed, 0 failures. `bun run verify:quiet` (Biome, 358 files) clean. CI = `bun run verify:quiet && bun run test && bun run mac:test`.

## Review Rules

- Tickets merge in order: P12.01 → P12.02 → P12.03, stacked. P12.04 is independent and may proceed in parallel. P12.05 is last.
- Each ticket PR must pass CI before the next stacked ticket starts.
- Pre-existing CI failures recorded in **CI Baseline** do not block a ticket; newly introduced failures do.
- **All PRs target `v2_preview`, not `main`.** Closeout merges the stack onto `v2_preview`.
- P12.03 is the behavior-invisibility gate: its characterization tests must show parity with v1.1.1 rendering.

## Explicit Deferrals

- **Visible reducers** (per-platform / badge-only / per-thread *rendering*), the **Settings > Customization** render-policy picker — later v2/v3 feature phases; reviewed as features, not smuggled into a refactor.
- **gate.json Option 1** (`origin, session_id` stamping) — upstream `cesarnml/son-of-anton` work + needs a stable delivery-time session id; v3 per-thread phase. Phase 12 uses Option 2 (ambient gate on the aggregate), no SoA change.
- **`/sync` identity auth + `profile_id` spoofing prevention** — needs the enroll/token handshake; leaderboard phase.
- **Gallery-ops drift, web dual-install + web tests off CI, Swift TODO remaps** — different stacks; dedicated hygiene phase before the leaderboard.
- **One-time v1.1.1 → v2 migration / gray-out safety** — the only real skew is the single GA jump; handled by the v2 release phase.

## Stop Conditions

- The slice-directory read side surfaces a partial-write or orphan-slice case the mtime-TTL design doesn't cleanly cover — pause and get input rather than inventing locking.
- `/sync` shared-secret hardening turns out to break a live production sync consumer (verify before assuming `/sync` is unused in prod).
- Any pressure to wire a *visible* reducer (per-platform pets) to render — that is out of scope and belongs in a feature phase.
- Broken CI that cannot be resolved within the ticket scope.

## Phase Closeout

Retrospective: required
Why: introduces a durable architectural boundary (the keyed slice directory + reducer seam every v2/v3 feature phase builds on) and changes downstream phase assumptions; capture the slice-directory choice, the v2_preview release model, and the intra-branch lockstep lesson.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-12-keyed-state-refactor-retrospective.md`
