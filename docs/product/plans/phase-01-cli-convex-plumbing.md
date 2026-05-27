# Phase 01: CLI + Convex Plumbing (Private XP Validation)

**Delivery status:** Pending developer approval. Update when decomposition starts (`/soa decompose`).

## TL;DR

**Goal:** Wire the XP / HP / loot engine end-to-end through a CLI and Convex backend, validated privately by two real developers (owner + one buddy) running it against their actual daily activity for seven consecutive days. No public surface, no Twitter post, no web app, no macOS app.

**Ships:**

- A renamed, npm-installable CLI (`codogotchi`) with `setup`, `sync`, `status`, `loot` commands
- A hook binary (`codogotchi-hook`) that writes a richer-than-Codex animation state vocabulary to `~/.codogotchi/state.json` on every Claude Code and Codex lifecycle event, including Son-of-Anton delivery gates as a bonus signal source
- The XP, HP, and loot engine (`xp.js` + `health.js`) wired into the sync loop, including weekend-aware degradation, configurable grace period, and vacation suspension
- Four live signal sources flowing into XP totals: Claude Code JSONL, Codex JSONL, GitHub merged PRs (with PR-quality enrichment, rate-limit-capped), Wakatime hours
- A Convex backend deployed to Convex Cloud holding the canonical schema (profiles with health fields, loot events, users), a `syncProfile` mutation, and an HTTP action receiving signals from the CLI
- Two distinct profiles flowing through Convex with no cross-profile data bleed

**Defers:**

- Anything user-visible to the public (web armory, leaderboard UI, OG image, OAuth, custom domain, install script, README GIF, Vercel deploy) — moves to the Public Launch phase
- The macOS Swift menu bar pet and floating window — its own multi-phase Swift learning track
- Visible loot rendering on the character sprite — open strategic question, no committed path
- Codogotchi-compatible pet catalog site — its own deferred phase
- HP UI, death tombstone, friends, achievement badges UI — Social Drama phase
- Web-side leaderboard and profile reactive queries (`getLeaderboard`, `getProfile`) — cheap to add when there is a consumer

---

Codogotchi exists to make Codex- and Claude-format pets _feel alive_ by mapping agent-lifecycle context (implementing, verifying, running tests, pushing a PR, conducting an adversarial subagent review, polling CI, hitting a phase closeout) to a richer animation state vocabulary than the floor Codex pets ship with today. The Codex / Claude pet (`pet.json` + `spritesheet.webp`) is the Level 1 character. Codogotchi is the RPG layer on top: agent-aware animation, XP, HP degradation, loot, eventually a public armory and leaderboard. Before any of that user-visible drama can land, the underlying data pipeline has to be trustworthy. Phase 01 is the data pipeline — and only the data pipeline.

The forcing function for doing plumbing first is the macOS app, which is the soul of the product. The owner is new to Swift and intends to take the macOS layer slowly across multiple later phases. Shipping the data plumbing first means the macOS app, when it arrives, consumes a validated, calibrated XP / HP / loot stream rather than an unproven one — and the owner is not learning Swift, Convex schema, and game-feel tuning all simultaneously under launch pressure.

## Phase Goal

This phase should leave the product in a state where:

- The owner and one buddy can each run `codogotchi sync` on a cron / launchd schedule and observe their own XP, HP, stage, and loot history accumulating in real time from their actual Claude Code, Codex, GitHub, and Wakatime activity.
- The hook binary writes a stable, documented animation-state vocabulary to `~/.codogotchi/state.json` on every relevant lifecycle event, ready to be consumed by the macOS app in later phases — even though nothing reads it yet.
- The Convex backend is the canonical source of truth for all progression data, with `profile.json` acting as a local cache. Two distinct profiles are live in production Convex with verifiably independent state.
- Every product-level decision required to safely begin building the macOS app — animation state vocabulary, HP degradation rules, IPC contract, loot data shape, weekend / grace / vacation semantics — is locked and documented, not still being argued.
- The repository is fully renamed from `claude-pet` to `codogotchi` with no stale references in code, configs, package metadata, install paths, or docs.

## Committed Scope

The committed scope is grouped into eight areas. Implementation sequencing is for the decompose phase; this section names _what_ Phase 01 owns, not _how_ it is built.

### Rename pass — first, before any new code

The scaffold uses `claude-pet` throughout. Every reference must move to `codogotchi` before any new logic lands: npm package name, CLI command, hook binary name, profile / state directory (`~/.codogotchi/`), `package.json` fields, `bin` entries, README, install.sh, internal module references. This is non-negotiable and lands as a single atomic change before downstream work begins.

### CLI surface

The CLI is the _only_ operator surface in Phase 01. The committed command set:

- `codogotchi setup` — interactive first-run: installs Claude Code + Codex hooks, prompts for a GitHub Personal Access Token (no OAuth in Phase 01), prompts for Wakatime API key, initializes `~/.codogotchi/` and registers the profile in Convex.
- `codogotchi sync` — pulls signals from all four sources, sends raw signals to Convex, refreshes local `profile.json` cache, ticks HP.
- `codogotchi status` — prints the current state (XP totals by source, stage, HP, recent loot, current SoA-aware animation state if hooked).
- `codogotchi loot` — prints the loot history and current "inventory" as text/icons. No sprite rendering — visible loot is explicitly deferred.

GitHub authentication in Phase 01 is a **Personal Access Token stored in `~/.codogotchi/config.json`**, not OAuth. OAuth via NextAuth.js is a Public-Launch-phase concern.

### Four signal sources

All four signal sources must work end-to-end in Phase 01. None are deferred. None are stubbed.

> **As-shipped (2026-05-20):** Signal ingest is **forward-only** (no historical backfill on first sync) and per-source XP **accumulates** each sync. The bullets below state the **original plan**; see [`phase-01-as-shipped-delta.md`](phase-01-as-shipped-delta.md) for current behavior.

- **Claude Code JSONL** parsing for token counts via `~/.claude/projects/**/*.jsonl`.
- **Codex JSONL** parsing through the same parser path. The two formats are compatible enough to share most logic, and shipping Codex support in Phase 01 doubles the addressable validation surface for almost no cost.
- **GitHub merged PRs** via the GitHub REST API, including `enrichPRQuality()` for review-comment counts and revert detection. _(Original plan: last-90-days OR last-20-PRs cap on first sync — superseded by forward-only ingest.)_
- **Wakatime hours** via the Wakatime API.

### XP / HP / loot engine wiring

`xp.js` and `health.js` exist in scaffold-v2 and are correct. Phase 01 wires them into `profile.js` and the sync loop:

- `tickHealth()` is called on every `sync`.
- `scorePR()` is called inside `applyPRMerge` for every new merged PR.
- Loot rolls via `rollLootDrop()` and `rollPRLootDropWithQuality()` fire on the appropriate events and persist to Convex `loot_events` (Claude/Codex only when that sync reports a positive token total for the source).
- Stage advancement (Stage 1 → 5) is computed and persisted.
- HP, death, and revival logic ticks silently — there is no UI surface for it in Phase 01. The numbers accumulate; the drama is held for the Social Drama phase.

The exact XP curves, HP decay rates, loot drop probabilities, and stage thresholds **are not tuned in Phase 01**. Tuning is treated as ongoing live-ops work for the life of the product, not a Phase 01 deliverable.

### Degradation policy (HP semantics)

Three product-level rules govern HP decay, baked into `health.js` semantics rather than left as implementation details:

- **Weekends are decay-free by default.** No HP loss on Saturday or Sunday in the user's local timezone unless overridden in config.
- **Grace period before idle decay kicks in.** A configurable 1–2 day grace window (default 2 days) of no activity before HP starts dropping.
- **Vacation suspension.** A manual `codogotchi vacation on/off` toggle (or equivalent config flag) that fully suspends HP decay until turned off. Resumes from where it paused, no retroactive damage.

### Hook binary + animation state vocabulary

The hook binary (`codogotchi-hook`) writes `~/.codogotchi/state.json` on every Claude Code and Codex lifecycle event. Phase 01 locks the **animation state vocabulary** that downstream consumers (the macOS app, eventually) will render against. The vocabulary is the IPC contract — it must be stable before any Swift code is written against it.

Signal sources feeding the state vocabulary, in priority order:

1. **Claude Code hooks + tool-call inspection** — `PreToolUse` / `PostToolUse` / etc., with best-effort heuristics from tool name and args (e.g. `Write` / `Edit` → `implementing`; `Bash` matching test patterns → `running-tests`; many sequential `Read`s → `reviewing`; `Bash` with `git push` → `pushing`).
2. **Codex hooks** — analogous to Claude Code.
3. **Son-of-Anton delivery gates** — when SoA is the active orchestrator, its gate transitions (plan approved, ticket started, worktree entered, CI polling, subagent review running, PR merged, phase closeout, Codex rescue, verify red) map to states such as `hyped`, `focused`, `nervous`, `waiting`, `celebrating`, `ascended`, `calling_for_backup`, `panicking`. **SoA is a side-hook**, not the headline differentiator: it sharpens appeal to agentic-dev power users without being load-bearing.
4. **Health / mood overlay** — HP buckets (`thriving`, `getting_sick`, `near_death`, `ghost`) layered over activity states.

Granularity from tool-call inspection is acknowledged as **best-effort heuristic, not ground truth**. Some states will be reliable; others will be approximations. This is a known limitation, not a defect.

### Convex backend

Convex is the canonical source of truth. Phase 01 commits to:

- A schema covering `profiles` (with all health fields — `hp`, `died_at`, `cause`, `death_count`), `loot_events`, and `users`.
- A `syncProfile` mutation that accepts raw signals, computes XP server-side (never trusts client-computed totals), **accumulates** per-source totals each sync, and persists.
- An HTTP action so the CLI can post sync payloads.
- Deployment to Convex Cloud production.

`getLeaderboard` and `getProfile` reactive queries are **explicitly deferred** — they are cheap to add, but writing them with no consumer in Phase 01 is speculative.

### Operational hygiene

- `codogotchi sync` is registered as a scheduled job (cron / launchd) on both Phase 01 users' machines.
- A debug log records every `scorePR()` decision so PR-quality heuristics can be reviewed and tuned post-Phase-01.
- Hook event fixtures are captured against current Claude Code and Codex schemas to make schema drift visible.

## Explicit Deferrals

Each deferral below is named with the reason it is _not_ in Phase 01, not just the future phase it might land in.

- **Web armory, leaderboard UI, OG image, custom domain, NextAuth OAuth, install script, README GIF, Vercel deploy.** All public surface area. Phase 01 has explicitly chosen "no public anything until the macOS pet is near release." These move to the Public Launch phase.
- **macOS Swift menu bar pet and floating window.** Its own multi-phase Swift learning track. Phase 01 produces the data and IPC contract the macOS app will consume; the app itself does not exist yet.
- **Visible loot rendering on the character sprite.** Open strategic question — see "Open Strategic Questions" below. No committed path exists, and Phase 01 ships loot as data + text only.
- **Codogotchi-compatible pet catalog site.** Analogous to `codex-pets.net`, eventually with a paid "lazy-tier" generation service à la `codingpets.dev`. Its own deferred phase. Phase 01 has no pet-format work — the macOS app phases consume a single hand-extended test pet (Mali).
- **HP UI, death tombstone, ghost indicator on leaderboard, dramatic CLI death / revival notifications.** Social Drama phase. HP ticks silently in Phase 01.
- **Friends system, achievements UI, badges, feed events.** Social Drama phase.
- **Convex `getLeaderboard` and `getProfile` reactive queries.** Cheap to add; speculative without a consumer.
- **Tuning of XP curves, HP rates, loot probabilities.** Ongoing live-ops, not a Phase 01 deliverable. Phase 01 ships defaults; tuning iterates forever.
- **Discord bot, guild system, org leaderboards, monetization tiers.** Phase 3+ and beyond.

## Roadmap Context

For situational awareness, here is where Phase 01 sits in the wider plan. Only Phase 01 is locked by this document — later phases are directional and may be re-shaped by their own planning passes.

1. **Phase 01 — CLI + Convex Plumbing (this document).** Private, two users.
2. **Phase 02 — macOS App Foundations: Menu bar pet.** `NSStatusItem` only. Swift learning ramp #1. Reads `state.json` via `FSEvents`. No floating window. Private.
3. **Phase 03 — macOS App: Floating pet + SpriteKit.** `NSPanel` + SpriteKit. Swift learning ramp #2. Full animation atlas, HP states render. Macos app considered "near release" at end of this phase. Private.
4. **Phase 04 — Public Launch: Web Armory + Leaderboard.** First public surface. Twitter post fires here. OAuth, OG image, Vercel deploy, leaderboard, all originally-Phase-1 web items live here.
5. **Phase 05 — Social Drama: HP UI, death, friends.** Originally-Phase-2 content.
6. **Phase 06 — Codogotchi pet catalog.** Catalog site for user-submitted extended pets, including pet selection feeding the macOS app. May need to land at Phase 04 or 05 if launch demand requires it.
7. **Phase 07+ — Premium tier.** Lazy-tier sprite generation as a service. Monetization wedge.

## Cross-Repo Dependency: Son-of-Anton

Phase 01 has a **soft dependency** on a Son-of-Anton-side feature: SoA must emit lifecycle events that codogotchi's hook can consume, and must expose a config toggle to enable / disable those emits. This work is **not in this repo's scope**. SoA changes are made in `~/code/son-of-anton` via SoA's own `/soa plan → /soa decompose → /soa execute` cycle, then synced here via `/soa update`.

**No code changes will be made inside this repo's `.son-of-anton/` git subtree.** That directory is read-only; any change made there is overwritten on the next update.

Phase 01 codogotchi is written **defensively** with respect to this dependency:

- If SoA's emit feature lands first, Phase 01 validation observes rich SoA-driven states firing on real delivery runs.
- If SoA's emit feature lands later, Phase 01 validates without those transitions firing; they retroactively light up after `/soa update`.

Either order is fine. Codogotchi Phase 01 does not block on SoA delivery and vice versa.

## Risk Register

Three product-level risks worth surfacing now:

| Risk | Likelihood | Mitigation |
|---|---|---|
| Claude Code or Codex change hook event format mid-Phase-01 | Medium — both are evolving products | Pin to current schema; capture event fixtures during decompose; document the contract explicitly. |
| `enrichPRQuality()` / GitHub search volume on active accounts | Medium — many merged PRs | _(Original: 90-day / 20-PR first-sync cap.)_ **As-shipped:** forward-only cutoff from install; no backfill. GitHub API rate limits still apply; `scorePR.log` + `sync.log` for ops. |
| PR-quality heuristic produces false-positive HP damage (legitimate reverts, normal review comments mis-scored) | Medium — heuristics are inherently noisy | Log every `scorePR()` decision to a debug file. Review weekly during the 7-day window. Tuning is ongoing post-Phase-01. |

A fourth risk — **owner abandons Phase 01 because it produces nothing shareable** — is real but unmitigated by design. The whole framing of "no public anything until the macOS pet is near release" accepts this as a deliberate trade. If it bites, the response is to revisit the phase ladder, not to half-launch.

## Open Strategic Questions

These are explicitly _not resolved_ by Phase 01 and are flagged here so they do not get forgotten:

- **Visible loot rendering on the character sprite.** Codogotchi drops loot ("Sword of Code Review — Epic" etc.), but the Codex / Claude pet format is a fixed sprite atlas with no equipment slots, outfit variants, or visual modifiers. Loot is data-only in Phase 01 and remains so until this question is resolved. The leading candidate is a future premium tier offering on-demand sprite augmentation via image generation, distributed through the codogotchi-compatible pet catalog (Phase 06 / 07+). No commitment is made in Phase 01.
- **Animation state vocabulary scope** — the codogotchi-compatible pet format will require additional sprite rows beyond the Codex floor (HP buckets, mood overlays). The exact superset is locked during decompose, not now.
- **Codex Pets ecosystem evolution.** Codex Pets just launched with a minimal implementation; Claude has not yet released a native pet. The format and ecosystem may shift. Phase 01 treats `pet.json` + `spritesheet.webp` as the de facto contract and re-evaluates at each macOS-app phase boundary.

## Exit Condition

Phase 01 is done when **all eight** of the following are demonstrably true:

1. `codogotchi sync` has run on schedule (cron / launchd) without crash for **seven consecutive days** on both Phase 01 users' machines.
2. **All four signal sources** have produced at least one XP event end-to-end during the validation window: Claude Code JSONL, Codex JSONL, GitHub merged PR, Wakatime hours.
3. **Two distinct profiles** are live in production Convex with no cross-profile data bleed verified by direct query.
4. The HP system has ticked on the seven-day schedule, including **at least one verified weekend cycle with no decay** and a grace-period configuration honored end-to-end.
5. **At least one loot drop** has been recorded in `loot_events` from a real signal during the window.
6. **At least one stage advancement** is observable on at least one of the two profiles (seed XP if real activity is insufficient; document if seeded).
7. `codogotchi status` output is clean, readable, and accurate against Convex.
8. The hook binary has emitted the **`celebrating` state on at least one real PR merge** during the window, demonstrating end-to-end IPC.

No subjective "feel" criterion. Tuning is not part of the exit condition.

## Retrospective

`required` — Phase 01 introduces the entire data model, the IPC animation-state contract, the four-source signal pipeline, the HP / weekend / vacation semantics, the Convex schema, and the cross-repo discipline with Son-of-Anton. Six or more downstream phases depend on these as foundations. Locking the durable-learning record now (what worked, what bit, what we'd change) is materially cheaper than reconstructing it from memory three phases later.
