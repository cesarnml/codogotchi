# Phase 01 — CLI + Convex Plumbing (Private XP Validation)

> Wire the XP / HP / loot engine end-to-end through a Bun-powered CLI and Convex backend, validated privately for seven consecutive days by the owner and one buddy against their actual daily Claude Code, Codex, GitHub, and Wakatime activity.

## Epic

Source product plan: [`docs/product/plans/phase-01-cli-convex-plumbing.md`](../../plans/phase-01-cli-convex-plumbing.md).

## Product contract

When this phase is complete:

- Owner and one buddy can each run `codogotchi sync` on a cron/launchd schedule and observe their own XP, HP, stage, and loot history accumulating in real time from Claude Code, Codex, GitHub, and Wakatime activity.
- The hook binary writes a stable, documented animation-state vocabulary to `~/.codogotchi/state.json` on every relevant Claude Code and Codex lifecycle event — ready for the macOS app to consume in later phases.
- Convex is the canonical source of truth for all progression data; `~/.codogotchi/profile.json` is a local cache populated only by sync responses. Two distinct profiles are live in production Convex with verifiably independent state.
- Every product-level decision needed before the macOS app starts (animation vocabulary, HP semantics, IPC contract, loot data shape, weekend/grace/vacation rules) is locked and documented.

## Grill-Me decisions locked

- **Module-by-module rewrite from scratch.** Scaffold-v2 (`notes/private/code/scaffold-v2/`) is reference material only — no bulk import. Every module ticket lands with its own red/green/refactor.
- **3-package workspace + root convex.** `packages/cli/` (`codogotchi`, `codogotchi-hook` bins), `packages/engine/` (pure logic + Bun-only `sources/`), `packages/contracts/` (types/zod for IPC + signal shapes + SoA event mapping), plus `convex/` at repo root.
- **Server-canonical XP computation.** Engine code is isomorphic and runs server-side in Convex `syncProfile`. CLI is a dumb pipe + cache reader. Only `packages/engine/src/sources/*` contains Bun-only I/O (CLI imports), pure logic stays runnable inside Convex's V8 isolate.
- **IPC contract is a standalone early ticket (P1.02) with one allowed revision.** Vocabulary doc + `packages/contracts/` types ship before any consumer. Hook ticket (P1.18) may revise once if implementation forces honest changes; revision captured in ticket rationale.
- **Convex bring-up is three thin tickets**: schema (P1.06), `syncProfile` mutation + HTTP action (P1.07), Cloud production deploy + two-profile smoke (P1.08).
- **Three-tier test strategy.** Engine via `bun test` with fixture inputs. Convex via `convex-test` in-process (in-memory data model, no Cloud round-trip). CLI/hook via tempdir filesystem (redirected with `CODOGOTCHI_HOME` env var) + mocked HTTP at the `convex-sync` boundary + fixture stdin for hook events.
- **SoA event feed contract.** SoA (when its emit ticket lands in its own plan) writes NDJSON lines to `.soa/events.ndjson` at consuming repo root. Codogotchi hook binary reads defensively from `$CLAUDE_PROJECT_DIR/.soa/events.ndjson`, falls back to CWD, silently skips when absent. Contract doc at `docs/contracts/soa-event-feed.md`.
- **Identity: handle + locally-generated UUID, no auth.** `codogotchi setup` prompts for a handle and generates a UUID; both register in Convex via the open HTTP action. OAuth is a Phase 04 precondition for public surface.
- **Sync failure model: per-source isolation.** Each source runs in its own try/catch. Failed sources emit `null` in the payload; Convex treats `null` as "skip, preserve last seen totals." Exit code is 0 if any source succeeded, 1 only if all four failed. Errors append to `~/.codogotchi/sync.log` (10MB rotated).
- **Server schema stores last-seen-totals-per-source.** `profile.xp_by_source = { claude, codex, github, wakatime }`; aggregate XP is the sum. A source going dark for a run does not zero its prior total.
- **Forward-only signal ingest (post-closeout).** No 90-day / 20-PR first-sync backfill. First touch per source uses `since = now`; `syncProfile` accumulates XP per sync. Canonical delta: [`docs/product/plans/phase-01-as-shipped-delta.md`](../../plans/phase-01-as-shipped-delta.md).
- **Health knobs as CLI commands.** `codogotchi config get|set|list` is the primitive; `codogotchi vacation on [--until DATE]|off|status` is sugar over `config set health.vacation_until`. All three knobs (`health.weekend_decay`, `health.grace_days`, `health.vacation_until`) persist in `~/.codogotchi/config.json`.
- **CI scripts land as a pre-phase chore commit to main.** `format:quiet`, `lint:quiet`, `verify:quiet`, `ci`, `ci:quiet` are tooling-only and skip phase ceremony per `.son-of-anton/CLAUDE.md`.
- **Retrospective + doc-drift sweep is a dedicated final ticket (P1.22)** to prevent README/AGENTS/CLAUDE/`docs/` drift after 20+ feature tickets.

## Ticket Order

1. `P1.01 Repo skeleton`
2. `P1.02 IPC contract — animation state vocabulary`
3. `P1.03 Engine: XP`
4. `P1.04 Engine: Health`
5. `P1.05 Engine: Loot`
6. `P1.06 Convex schema`
7. `P1.07 Convex syncProfile mutation + HTTP action`
8. `P1.08 Convex production deploy + two-profile smoke`
9. `P1.09 Source: shared JSONL parser (Claude Code + Codex)`
10. `P1.10 Source: GitHub PRs + rate-limit cap`
11. `P1.11 Source: Wakatime`
12. `P1.12 CLI scaffold + setup command`
13. `P1.13 CLI sync command`
14. `P1.14 CLI status command`
15. `P1.15 CLI loot command`
16. `P1.16 CLI config command`
17. `P1.17 CLI vacation command`
18. `P1.18 Hook binary + state.json writer`
19. `P1.19 SoA gate signal mapping`
20. `P1.20 Ops: scheduled job + scorePR debug log + hook fixtures`
21. `P1.21 7-day validation runbook + execution`
22. `P1.22 Retrospective + doc-drift sweep`

## Ticket Files

- `ticket-01-repo-skeleton.md`
- `ticket-02-ipc-contract.md`
- `ticket-03-engine-xp.md`
- `ticket-04-engine-health.md`
- `ticket-05-engine-loot.md`
- `ticket-06-convex-schema.md`
- `ticket-07-convex-sync-profile.md`
- `ticket-08-convex-deploy.md`
- `ticket-09-source-jsonl-parser.md`
- `ticket-10-source-github.md`
- `ticket-11-source-wakatime.md`
- `ticket-12-cli-setup.md`
- `ticket-13-cli-sync.md`
- `ticket-14-cli-status.md`
- `ticket-15-cli-loot.md`
- `ticket-16-cli-config.md`
- `ticket-17-cli-vacation.md`
- `ticket-18-hook-binary.md`
- `ticket-19-soa-event-feed.md`
- `ticket-20-ops-scheduled-job.md`
- `ticket-21-validation-runbook.md`
- `ticket-22-retrospective-doc-sweep.md`

## Exit Condition

All eight conditions from the product plan are demonstrably true:

1. `codogotchi sync` has run on schedule without crash for seven consecutive days on both users' machines.
2. All four signal sources have produced at least one XP event end-to-end during the window: Claude Code JSONL, Codex JSONL, GitHub merged PR, Wakatime hours.
3. Two distinct profiles are live in production Convex with no cross-profile data bleed (verified by direct Convex query).
4. The HP system has ticked on the seven-day schedule, including at least one verified weekend cycle with no decay, with grace-period configuration honored end-to-end.
5. At least one loot drop has been recorded in `loot_events` from a real signal during the window.
6. At least one stage advancement is observable on at least one profile (seed XP if real activity is insufficient; document if seeded).
7. `codogotchi status` output is clean, readable, and accurate against Convex.
8. The hook binary has emitted the `celebrating` state on at least one real PR merge during the window, demonstrating end-to-end IPC.

P1.21 (validation runbook + execution) is the ticket that verifies these.

## CI Baseline

> Baseline recorded: 2026-05-18 — `bun run ci:quiet` is **GREEN** on `main` after the pre-phase tooling commit. Output:
>
> ```
> $ bun run verify:quiet && bun run spellcheck
> $ biome check . --log-level=error
> Checked 6 files in 6ms. No fixes applied.
> $ cspell lint --no-progress "**/*.{ts,md,json,txt}"
> CSpell: Files checked: 57, Issues found: 0 in 0 files.
> ```
>
> Pre-phase tooling commit added: `format:quiet`, `lint:quiet`, `verify:quiet`, `ci`, `ci:quiet` to `package.json`, plus a cspell dictionary expansion to cover project terms surfaced by the phase-01 ticket docs.

Per-ticket CI diffs are evaluated against this green baseline. Any newly introduced biome diagnostic or cspell issue blocks the ticket.

## Review Rules

- Tickets merge in order. No parallel work.
- Each ticket PR must pass `bun run ci:quiet` before the next ticket starts.
- Pre-existing CI failures recorded in CI Baseline above do not block; new failures do.
- Engine tickets (P1.03–P1.05, P1.09–P1.11) must keep `packages/engine/src/*` (excluding `sources/`) free of Node/Bun-only APIs. Reviewer checks imports: no `node:fs`, no `process.env`, no `bun:*`. Use `packages/engine/src/sources/*` for I/O.
- Convex mutation tickets (P1.06, P1.07) must not introduce direct CLI imports. Convex imports `packages/engine/` (pure) and `packages/contracts/` only.
- Tickets touching the animation state vocabulary or state.json schema reference `packages/contracts/` types — no string literals at call sites.
- P1.18 may revise P1.02's contract once. Revision documented in P1.18 ticket Rationale section and mirrored back into the contract doc.

## Explicit Deferrals

Carried verbatim from the product plan, restated here so they cannot drift into a ticket:

- **Web armory, leaderboard UI, OG image, custom domain, OAuth, install script, README GIF, Vercel deploy** → Phase 04 (Public Launch).
- **macOS Swift menu bar pet and floating window** → Phase 02 + Phase 03.
- **Visible loot rendering on the character sprite** → open strategic question; loot is data + text only this phase.
- **Codogotchi-compatible pet catalog site** → Phase 06.
- **HP UI, death tombstone, dramatic CLI death/revival notifications, friends system, achievements, badges** → Phase 05 (Social Drama).
- **Convex `getLeaderboard` / `getProfile` reactive queries** → speculative without a consumer; add when web/macOS need them.
- **Tuning of XP curves, HP rates, loot probabilities** → ongoing live-ops, not a phase deliverable.
- **Discord bot, guilds, monetization** → Phase 07+.

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Convex schema change required mid-phase that would require backfilling production data (escalate before proceeding).
- Claude Code or Codex hook event format change mid-phase (documented risk; pause to update fixtures + contract).
- SoA gate signal contract change requested by SoA's own plan that would alter `.soa/events.ndjson` shape (escalate; revise P1.19 before continuing).
- `enrichPRQuality()` rate-limit cap inadequate in real-world testing (documented risk; revisit cap rather than disabling enrichment).
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: Phase 01 introduces the entire data model, IPC animation-state contract, four-source signal pipeline, HP/weekend/vacation semantics, Convex schema, and cross-repo discipline with Son-of-Anton. Six or more downstream phases depend on these as foundations; locking durable learning now is materially cheaper than reconstructing it later.
Trigger: durable-learning risk
Artifact: `docs/product/retrospectives/phase-01-cli-convex-plumbing-retrospective.md`

Retrospective writing and the README/AGENTS/CLAUDE/`docs/` drift sweep are executed inside P1.22 via the `soa-write-retrospective` skill at phase closeout.
