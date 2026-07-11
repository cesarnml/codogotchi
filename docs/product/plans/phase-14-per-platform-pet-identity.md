# Phase 14: Per-Platform Pet Identity & Minimalist Display Mode

**Delivery status:** Decomposed 2026-06-29 — target app **v2.1.0**. Delivery plan: `docs/product/delivery/phase-14/implementation-plan.md` (9 tickets). Next: `/soa preflight phase-14`.

## TL;DR

**Goal:** Let each AI platform render its *own* selected pet (not just its own window), and add a chromeless "Minimalist" display mode that shows a compact per-platform badge strip instead of a pet.

**Ships:**

- Per-platform pet **assignment** — any installed pet can be assigned to any of the 5 platforms (claude_code, vscode, codex, cursor, antigravity) and/or to a mandatory **Default** slot. A pet may hold multiple assignments; each platform/Default badge lives on exactly one pet at a time.
- A redesigned **Settings > Pet** card grid: per-card assign multiselect (platform logos + Default), import icon centered beneath the portrait (importable codex pets only), right-aligned assign icon (installed pets only), assigned logo-pills under a full-width description, and the Default-holding pet carrying the blue selection border.
- A new **Minimalist** value on the per-platform display mode (Own / Combined / Off / **Minimalist**), set in Settings > Customization. Minimalist renders a badges-only window — no pet sprite, no RPG HUD — carrying Platform Badge + Animation Badge + Attention Bubble + a per-platform **latest-prompt summary** badge.
- The **"Default pet"** concept — today's single global pet is renamed and repurposed as the mandatory fallback that own-mode platforms without an explicit assignment inherit, and that the combined-mode window renders. Backward-compatible: an upgrading v2.0.0 user keeps one pet everywhere until they override a platform.
- Documented **cross-agent visualization** behavior: a subagent on another platform (e.g. a codex review spawned by claude_code) legitimately spawns that platform's transient pet window, which ages out via the existing TTL.

**Defers:**

- **Per-thread (per-`session_id`) pets** → Phase 15. Including the "pet collection per platform" idea, the per-platform active-thread render limit, and where a per-thread setting lives.
- **SoA gate/ticket badges in Minimalist mode** → later. Blocked on upstream `cesarnml/son-of-anton` emitting runtime platform + `session_id` attribution with its gate signals.
- **Collapsing subagent activity back into the primary window** (pre-Phase-13 badge-swap feel) → blocked on the same upstream SoA parent/child attribution.

---

Phase 13 shipped one floating pet *window* per active platform, but every window renders the same single global pet. The natural completion is to let each platform render a *different* pet — the per-platform `state.d/` slices and per-origin windows already exist; this phase makes pet *identity* per-platform, not just window presence. Minimalist mode ships alongside it as the chromeless render path that Phase 15's per-thread rows will reuse.

## Phase Goal

This phase should leave the product in a state where:

- A user can open Settings > Pet, assign a distinct pet to each of claude_code, vscode, codex, cursor, and antigravity, and see each platform's floating pet window render its assigned pet.
- A "Default" pet is always assigned to exactly one installed pet (starting on Maew); any platform left unassigned renders the Default pet, and the combined-mode window renders the Default pet.
- A user can set any platform to **Minimalist** in Settings > Customization and see that platform render a compact badges-only window (Platform + Animation + Attention + latest-prompt summary) with no pet sprite and no RPG HUD.
- Reassigning the Default badge — or any platform badge — from one pet to another removes it from the previously-holding pet (each badge lives on exactly one pet).
- An upgrading v2.0.0 user, who had one global pet, sees that pet as the Default and rendering on every platform until they explicitly override a platform — no migration action required.
- During a cross-agent SoA review, the user sees the subagent's platform pet appear transiently and age out — documented, expected behavior, not a bug.

## Committed Scope

### Per-platform pet identity (Settings > Pet)

- Pet **assignment map**: `{claude_code, vscode, codex, cursor, antigravity, default} → petId`. `default` is mandatory and always resolves to an installed pet (seeded to Maew). The 5 platform keys are optional overrides.
- Resolution: an own-mode platform with an assignment renders that pet; without one, it renders the Default pet. The combined-mode window renders the Default pet.
- Assignment uniqueness: each of the 6 badges (5 platforms + Default) is held by exactly one pet; assigning a badge to a new pet removes it from the previous holder.
- Settings > Pet card redesign:
  - Portrait keeps its current (non-circle) treatment, raised to align with the pet name.
  - Import icon horizontally centered beneath the portrait, shown **only** for codex pets present in `~/.codex/pets` but not yet imported into `~/.codogotchi/pets`.
  - Assign icon: small, right-aligned on the pet-name row, shown **only** on installed pets (never on importable ones). Opens a multiselect dropdown of the 5 platform logo badges + Default.
  - Assigned badges render as compact logo-pills (Default as a labeled pill) beneath a full-width pet description.
  - The pet holding the Default badge receives the same blue selection border that the active pet uses today.
- Live-swap: changing an assignment updates the affected visible window(s) without an app restart (extends the existing `replacePets` path to be per-window rather than global).

### Minimalist display mode (Settings > Customization)

- New `minimalist` value on the per-platform display mode, alongside `own` / `combined` / `off`, set per-platform in the existing Customization tab.
- Minimalist window renders, per platform: Platform Badge + Animation Badge + Attention Bubble + a **latest-prompt summary** badge sourced from that platform's most recent slice (analogous to the attention-bubble summary; not a thread).
- Minimalist windows have no pet sprite and no RPG HUD.
- Minimalist participates in the existing pool lifecycle (spawn on activity, idle-dismiss TTL, user hide/show, last-active immunity) the same way Own windows do.

### Mode × identity interaction

- Pet assignment renders only in **Own** mode. In Combined the platform folds into the shared Default-pet window; in Minimalist there is no sprite; in Off nothing renders.
- Assignments are **latent and silent**: a Pet tab assignment always persists and takes visual effect if/when the platform is in Own mode. No cross-tab warnings, no disabling.

### Cross-agent visualization

- A subagent slice on a different platform spawns that platform's own (transient) pet window, rendering that platform's assigned/Default pet, and ages out via the existing TTL. This is the documented expected behavior for Phase 14; no min-lifetime guard.

## Explicit Deferrals

- **Per-thread (per-`session_id`) pets and the "pet collection per platform" model** — deferred to Phase 15. Threads are ephemeral; the rotation/collection abstraction has no consumer until per-thread rendering exists. The minimalist render path built here is the foundation Phase 15 reuses for stacked thread rows.
- **Per-platform active-thread render limit** ("how many threads to render per platform") — a per-thread concern; deferred to Phase 15 with per-thread.
- **SoA gate/ticket badges in Minimalist mode** — deferred. SoA does not yet emit runtime agent platform or `session_id` attribution with its gate signals; this is upstream work in `cesarnml/son-of-anton` that must land before gate/ticket badges can be correctly attributed in a per-platform/per-thread world.
- **Collapsing subagent activity into the primary platform's window** (the pre-Phase-13 single-window badge-swap feel) — deferred; blocked on the same upstream SoA parent/subagent attribution.

## Exit Condition

A developer can open Settings > Pet, assign three different pets to three platforms and leave two unassigned, and then — running those tools — see each assigned platform render its chosen pet while the unassigned ones render the Default pet (Maew unless reassigned). Switching a platform to Minimalist in Settings > Customization replaces its pet with a compact badge strip showing the platform, current animation/state, attention, and its latest prompt summary. Reassigning the Default badge to a different pet moves the blue border with it. A fresh upgrade from v2.0.0 shows the user's existing single pet everywhere as the Default with no setup. A cross-agent SoA review briefly surfaces the reviewer platform's pet, which then disappears on its own.

## Retrospective

`required` — Phase 14 introduces the first per-platform pet *identity* behavior and a second config contract (the pet-assignment map alongside `customization.json`), establishes the chromeless Minimalist render path that Phase 15 per-thread will build on, and bakes in the transient-subagent-pet behavior. Durable learning and downstream architectural constraints are likely. Headline risk to revisit: the upstream SoA attribution dependency (disclosed, non-blocking for Phase 14's committed scope).
