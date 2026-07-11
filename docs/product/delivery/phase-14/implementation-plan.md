# Phase 14 — Per-Platform Pet Identity & Minimalist Display Mode

> Let each AI platform render its own assigned pet (not just its own window) via a new `assignments.json` contract, and add a chromeless Minimalist display mode that renders a compact per-platform badge strip instead of a pet.

## Epic

Product plan: [`docs/product/plans/phase-14-per-platform-pet-identity.md`](../../plans/phase-14-per-platform-pet-identity.md).

## Product contract

When this phase is complete, a user can open Settings > Pet, assign a distinct installed pet to each of `claude_code`, `vscode`, `codex`, `cursor`, and `antigravity` (and to a mandatory **Default** slot), and see each platform's floating pet window render its assigned pet. Any platform left unassigned — and the combined-mode window — renders the Default pet (Maew until reassigned). Each of the 6 badges (5 platforms + Default) lives on exactly one pet; reassigning a badge moves it (and, for Default, the blue selection border). A user can set any platform to **Minimalist** in Settings > Customization and see a compact badges-only window (Platform + Animation + Attention + latest-prompt summary) with no pet sprite and no RPG HUD. An upgrading v2.0.0 user keeps their single pet everywhere as the Default with no setup. The combined window now carries a persistent ⭐ Default badge when idle, resolving the prior badge asymmetry. The app version reads 2.1.0; no DMG is cut this phase.

## Grill-Me decisions locked

- **`assignments.json` is a self-contained contract** → all 6 keys (`claude_code`, `vscode`, `codex`, `cursor`, `antigravity`, `default`) live in one new file with its own `schema_version: 1`. `default` is mandatory; the 5 platform keys are optional overrides. The badge-uniqueness invariant (each badge on exactly one pet) is enforced on write.
- **`config.pet` is retired** → removed from the config Zod schema, `SETTABLE_TOP_LEVEL`, the `config set` allow-list, and `setup.ts` seeds. It became a vestigial tail once `assignments.json` owns selection. Documented CLI breaking change in v2.1.0.
- **Migration is a one-time idempotent Swift seed** → on first read where `assignments.json` is absent, raw-read `config.pet` (schema-independent JSON read; fallback `maew`) → seed `assignments.default`, then never read `config.pet` again. Ships in the same DMG/closeout as the CLI removal, so there is no partial-upgrade window.
- **`PetAssetResolver` caches `petId → (CodexPet, CodogotchiPet?)`** → dedupes spritesheet loads when platforms share a pet, single fallback-to-Maew seam on load failure, evicts on reassignment. Replaces the pool's captured-global pet references.
- **Pool gains per-platform identity routing** → the window factory resolves each origin's pet via `AssignmentsJsonReader.resolve(origin)` + `PetAssetResolver`; `replacePets` becomes per-origin `replacePet(origin:)`; the combined window renders the Default pet. Spawn / TTL / hide-show / last-active lifecycle is unchanged.
- **Minimalist is the 4th `PlatformMode` value** → additive on `customization.json` (stays `schema_version: 1`; unknown modes already degrade to `.own`, so it is forward/back-tolerant without a version bump). Minimalist origins route to a separate `MinimalistWindowControlling` window type behind the existing pool protocol — no sprite, no RPG HUD.
- **Minimalist latest-prompt summary reuses `prompt-attention.json`** → a new Swift `PromptAttentionReader` reads the existing `by_session` store and picks the newest entry whose key is prefixed `<origin>:`. No CLI change, no slice field, no `STATE_JSON_SCHEMA_VERSION` bump.
- **Combined window idle ⭐ Default badge** → the window badge renderer gains a `.default` star case; the combined window applies it persistently when idle, matching own-mode windows that badge always. Same star iconography feeds the Pet-tab Default pill.
- **No state-schema lockstep change** → `STATE_JSON_SCHEMA_VERSION` / `EXPECTED_STATE_SCHEMA_VERSION` are untouched this phase.

## Ticket Order

1. `P14.01 Contracts: assignments.json schema + minimalist customization mode`
2. `P14.02 CLI: retire config.pet`
3. `P14.03 Swift: AssignmentsJsonReader + writer + migration seed`
4. `P14.04 Swift: PetAssetResolver`
5. `P14.05 Swift: Pool per-platform identity routing + combined idle Default badge`
6. `P14.06 Swift: Minimalist window type + PromptAttentionReader summary`
7. `P14.07 Swift: PetTabViewModel assignment model`
8. `P14.08 Swift: Pet tab card view redesign + live-swap wiring`
9. `P14.09 Docs sweep + v2.1.0 bump + retrospective`

## Ticket Files

- `ticket-01-assignments-contract-minimalist-mode.md`
- `ticket-02-retire-config-pet.md`
- `ticket-03-assignments-reader-migration.md`
- `ticket-04-pet-asset-resolver.md`
- `ticket-05-pool-per-platform-identity.md`
- `ticket-06-minimalist-window.md`
- `ticket-07-pet-tab-assignment-model.md`
- `ticket-08-pet-tab-card-redesign.md`
- `ticket-09-docs-retrospective.md`

## Exit Condition

A developer opens Settings > Pet, assigns three different pets to three platforms and leaves two unassigned, then — running those tools — sees each assigned platform render its chosen pet while the unassigned ones render the Default pet (Maew unless reassigned). Switching a platform to Minimalist in Settings > Customization replaces its pet with a compact badge strip showing the platform, current animation/state, attention, and its latest prompt summary, with no sprite and no HUD. Reassigning the Default badge to a different pet moves the blue selection border with it and removes Default from the prior holder. A fresh upgrade from v2.0.0 shows the existing single pet everywhere as the Default with no setup action. The combined-mode window shows a ⭐ Default badge while idle. A cross-agent SoA review briefly surfaces the reviewer platform's pet, which then ages out via the existing TTL. The app version reads 2.1.0.

## CI Baseline

> To be recorded at phase start: `bun run ci:quiet` on the SHA where P14.01 branches from main. Record result and failure count here before the first ticket commit.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- Merge-order dependencies: P14.02 and P14.03 depend on P14.01 (contract). P14.05 depends on P14.03 and P14.04. P14.06 depends on P14.05. P14.07 depends on P14.03. P14.08 depends on P14.05 and P14.07. P14.09 is last and depends on all.
- **Lockstep:** P14.02 (config.pet removal) and P14.03 (migration seed) must land in the same closeout so the "config.pet gone / assignments.json seeded" pair ships atomically. Do not closeout the stack with one but not the other.
- No `STATE_JSON_SCHEMA_VERSION` / `EXPECTED_STATE_SCHEMA_VERSION` change is expected in this phase — flag any ticket that needs one as a stop condition.

## Explicit Deferrals

- **Per-thread (per-`session_id`) pets and the "pet collection per platform" model** → Phase 15. The Minimalist render path built here is the foundation Phase 15 reuses for stacked thread rows.
- **Per-platform active-thread render limit** → Phase 15 with per-thread.
- **SoA gate/ticket badges in Minimalist mode** → deferred; blocked on upstream `cesarnml/son-of-anton` emitting runtime platform + `session_id` attribution with gate signals.
- **Collapsing subagent activity into the primary platform's window** → deferred; blocked on the same upstream SoA parent/subagent attribution.
- **Mirroring `assignments.default` back to `config.pet`** → not done; `config.pet` is removed, not kept in sync.

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Any ticket that appears to need a `STATE_JSON_SCHEMA_VERSION` / `EXPECTED_STATE_SCHEMA_VERSION` bump — pause and confirm, since this phase is scoped to avoid the schema-lockstep gotcha.
- A migration-ordering case where a user's custom default pet could be lost (e.g. evidence the CLI strips `pet` before the Swift seed runs) — pause and confirm the safeguard holds.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: First per-platform pet _identity_ behavior, a second config contract (`assignments.json` alongside `customization.json`), the new chromeless Minimalist render path Phase 15 per-thread will build on, and the baked-in transient-subagent-pet behavior. Durable learning and downstream architectural constraints are likely; the upstream SoA attribution dependency is the headline risk to revisit.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-14-per-platform-pet-identity-retrospective.md`
