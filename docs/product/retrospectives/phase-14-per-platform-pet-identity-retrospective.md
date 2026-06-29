# Phase 14 — Per-Platform Pet Identity & Minimalist Display Mode Retrospective

## Scope delivered

9 tickets, PRs [#139](https://github.com/cesarnml/codogotchi/pull/139) – [#147](https://github.com/cesarnml/codogotchi/pull/147). Branch stack: `agents/p14-01-*` → `agents/p14-09-*` stacked on `main`.

- `assignments.json` contract: 6-key schema (5 platforms + Default), badge-uniqueness invariant enforced on write, `schema_version: 1`
- CLI: `config.pet` removed from Zod schema, `SETTABLE_TOP_LEVEL`, and seed — documented breaking change in v2.1.0
- Swift: `AssignmentsJsonReader` + writer + one-time idempotent migration seed from `config.pet`
- Swift: `PetAssetResolver` caching `petId → (CodexPet, CodogotchiPet?)` with per-origin eviction
- Swift: pool per-platform identity routing via `AssignmentsJsonReader.resolve(origin:)` + `replacePet(origin:)` per-origin replacement; combined window renders Default pet
- Swift: combined window persistent ⭐ Default badge when idle
- Swift: `MinimalistWindowController` (4th `PlatformMode` value) + `PromptAttentionReader` reading `prompt-attention.json`
- Swift: `PetTabViewModel` assignment model; Pet tab card view redesign with live-swap wiring
- Docs, version bump to **2.1.0**, retrospective (this ticket)

## What went well

**Two-file contract split kept scope clean.** `assignments.json` and `customization.json` have fully orthogonal concerns (pet identity vs. display behavior). Keeping them separate prevented any schema-version entanglement and meant `assignments.json` could start at `schema_version: 1` without touching the customization schema. Future phases that add per-platform behavior should default to a new contract file rather than extending existing ones — the isolation pays off at the spec level before a line is written.

**Additive `PlatformMode` value with no version bump.** Minimalist ships as `schema_version: 1` in `customization.json` — the same version as the existing modes — because unknown modes already degrade to `.own`. This means a downgraded client silently falls back to the own-mode window rather than erroring or showing nothing. The forward/back tolerance was free and required no migration. Pattern: if the failure mode of an unknown enum value is graceful degradation, don't bump the schema version.

**`PetAssetResolver` as the deduplication seam.** Caching `petId → (CodexPet, CodogotchiPet?)` at the resolver level means platforms that share a pet do not load duplicate spritesheets, and the fallback-to-Maew path has one authoritative entry point. Prior to this the pool captured global pet references with no eviction path. Future multi-window work (per-thread in Phase 15) inherits the clean eviction-on-reassignment pattern.

**Migration seed is unambiguously idempotent.** The seed fires once — on first read where `assignments.json` is absent — raw-reads `config.pet` (schema-independent, fallback `maew`), writes `assignments.default`, and never reads `config.pet` again. Because the CLI removal and Swift seed shipped in the same closeout, there was no partial-upgrade window where a user could have `config.pet` gone but `assignments.json` not yet seeded. Pairing the breaking removal with the migration seed in a lockstep slice requirement (stated in the implementation plan) made this safe.

**Subagent reviews clean across all 8 code tickets.** No actionable findings required patching. This is partly because the spec was tight — each ticket had a precise exit condition and the attack surfaces were narrow. It also validates the grill-me pass at plan time: the Phase 14 architecture decisions were stress-tested before decomposition, so individual tickets didn't inherit architectural ambiguity.

## Pain points

**`replacePets` → per-origin `replacePet(origin:)` required touching every call site in the pool.** This was expected cost — the global replacement API was a Phase 12 artifact built for a world with one pet. The rename + per-origin routing touched more code than any other ticket in the phase. The fix was correct but the blast radius was real. Avoidable in retrospect: a per-origin shim could have shipped in Phase 12 alongside the global API so Phase 14 only needed to flip the default.

**`PromptAttentionReader` reuses an existing file contract (`prompt-attention.json`) with no CLI awareness.** The reader picks the newest `<origin>:` prefixed key from `by_session`. This is correct but it means the Minimalist window's "latest prompt" summary can show a stale entry if a session was long-lived and the key order within a session doesn't reflect recency. Expected cost: the `by_session` store was designed for a different consumer. Phase 15 (per-thread) will likely need a dedicated recency index or timestamp field; the current reader is a pragmatic first approximation.

## Surprises

**Transient subagent pet window is expected behavior, not a bug.** When a SoA review subagent runs on a non-primary platform (e.g. Codex subagent in a Claude Code primary session), it legitimately fires hook events from that platform origin — which spawns that platform's transient pet window and renders whatever pet is assigned to `codex`. That window ages out via the existing TTL. This is architecturally correct: the pool doesn't distinguish primary agents from subagents, and `assignments.json` doesn't need to either. The behavior surprised developers in early testing but is documented here so future agents don't treat it as a bug. The "collapse subagent activity into the primary window" ask is deferred — it's blocked on upstream SoA parent/subagent attribution.

**`DEFAULT` badge asymmetry in the combined window was pre-existing.** The combined window didn't carry a persistent ⭐ Default badge when idle while own-mode windows badge always. This was a pre-existing gap that Phase 14 fixed as a scope addition (it was listed in the implementation plan but was not in the original product plan). It was the right call — the badge asymmetry was confusing to users who had just reassigned the Default pet. The lesson: when a ticket's exit condition requires a UI element to be visually symmetric with existing behavior, check for asymmetry across all surfaces at spec time.

**No `STATE_JSON_SCHEMA_VERSION` bump needed.** The plan's explicit stop condition was "any ticket that needs a lockstep bump — pause and confirm." None did. `assignments.json` carries its own `schema_version` independently. Stating this as a stop condition (not just a note) meant every ticket author consciously verified it before implementation.

## What we'd do differently

**Specify the `PlatformMode` additive extension pattern earlier.** The decision that "additive enum values are forward/back-tolerant if the degradation path is graceful" was made during the grill-me pass and locked in. But it was written into the implementation plan rather than the contracts doc (`customization-json.md`). Future phases extending `PlatformMode` will re-derive this reasoning from scratch. The pattern belongs in the contract doc as a standing convention.

**Add a `subagentOrigin` flag to the `assignments.json` write-guard.** Right now the uniqueness invariant (each badge on exactly one pet) is enforced on write but there's no concept of "transient" vs. "persistent" assignment. If Phase 15 adds per-thread assignment, the current write-guard may need to distinguish between a user-assigned Default and a session-scoped assignment. Modeling this as a single flat contract may have been premature; a `scope: "persistent" | "session"` field would preserve the invariant while allowing per-thread overrides.

## Net assessment

Phase 14 delivered its stated goals without schema-lockstep complications and without a single actionable subagent finding. The architectural bets — two-file contract split, additive PlatformMode, idempotent migration seed, PetAssetResolver as the deduplication seam — held through 8 code tickets. The Minimalist render path is the foundation Phase 15 per-thread rows will build on. The headline deferred dependency (upstream SoA parent/subagent attribution for collapsing cross-agent windows) is correctly scoped as a blocker for future phases, not this one.

## Follow-up

- **Phase 15:** Extend Minimalist window with per-thread (`session_id`) rows, reusing the `MinimalistWindowController` and `PromptAttentionReader` infrastructure built here.
- **`customization-json.md` contract doc:** Add the "additive enum values are forward-tolerant when degradation is graceful" convention so future Phase-N authors don't re-derive it.
- **Upstream SoA attribution:** `cesarnml/son-of-anton` needs to emit runtime platform + `session_id` attribution with gate signals before "collapse subagent window into primary" and "SoA gate badges in Minimalist mode" can be unblocked. Track as a dependency, not a Phase 15 ticket.
- **`assignments.json` scope field:** Consider adding `scope: "persistent" | "session"` before Phase 15 per-thread assignment to avoid a breaking schema change mid-phase.

---

_Created: 2026-06-30. PRs #139–#147 open, awaiting developer closeout approval._
