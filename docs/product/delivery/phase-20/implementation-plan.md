# Phase 20 — Sticky Slice Timestamps

> Durable turn/session/error clocks on every `state.d` slice so PromptTimer elapsed stays correct across windows and relaunches, and Settings > Sessions can show when a session started.

## Epic

None — standalone phase. Lands the Phase 18–deferred “v4 hook-stamped `prompt_started_at` architecture,” expanded to four sticky stamps.

## Product contract

Today the PromptTimer chip derives elapsed from in-memory trackers seeded off slice `updated_at`. Mid-turn tool writes bump `updated_at`, and trackers disappear when a render key leaves TTL eligibility — so elapsed lies or resets across hide/show, fold churn, and app relaunch. Settings > Sessions has no durable “when did this session start?” signal.

When this phase is complete: every slice may carry `prompt_started_at`, `session_started_at`, `errored_since`, and `turn_ended_at`; the hook sets/clears/preserves them at lifecycle edges; PromptTimer hydrates from those stamps (errored 60s freeze remains app-side math from `errored_since`); Settings > Sessions shows relative Started for Active/Live/Archived when the stamp exists; app + hook + five installers ship lockstep with release-note guidance only.

## Grill-Me decisions locked

- **Four stamps:** `prompt_started_at`, `session_started_at`, `errored_since`, `turn_ended_at` (optional ISO-8601 on the slice).
- **Schema bump:** state/slice contract **v9 → v10**; Swift `EXPECTED_STATE_SCHEMA_VERSION` stays lockstep.
- **Writer rule:** each hook write **read-merges** prior sticky fields; mid-turn tool ticks do not rewrite turn-start or session-birth.
- **`turn_ended_at`:** stamped by the hook on clean waiting (`standby` + attention). Not written by the menubar at the 60s errored threshold.
- **Errored freeze:** app-side `errored_since + 60s` (same grace as today); durable across relaunch via the stamp alone.
- **Sessions consumer:** relative Started subtitle on Active + Live + Archived; combine with Idle age when both exist; omit when stamp missing (no fake from `updated_at`).
- **Rollout:** lockstep app + hook + installers; **release notes only** — no in-app “hooks outdated” nudge.
- **Ticket shape:** four fat tickets; installers ship with ticket 1 (contracts + hook).
- **Retrospective:** required.

## Ticket Order

1. `P20.01 Contracts + hook sticky stamps + five installers`
2. `P20.02 Swift decode + PromptTimer hydrate + Force Idle clears`
3. `P20.03 Settings > Sessions Started subtitle`
4. `P20.04 Docs + release notes + retrospective`

## Ticket Files

- `ticket-01-contracts-hook-installers.md`
- `ticket-02-swift-prompt-timer-force-idle.md`
- `ticket-03-sessions-started-subtitle.md`
- `ticket-04-docs-release-notes-retrospective.md`

## Exit Condition

A dogfooded lockstep build (updated app + refreshed hook install) shows matching prompt elapsed on own, minimalist, combined, and session on/off after hide, TTL dismiss, fold churn, and relaunch — including frozen elapsed after waiting (`turn_ended_at`) or long-errored turns (`errored_since` + 60s). Settings > Sessions shows relative Started when stamped and omits it otherwise. Contract docs and release notes describe the bump and lockstep install refresh; retrospective is written before the phase is called closed.

## CI Baseline

`bun run ci:quiet` on `v3_preview` at commit `2f5915ac` (Sessions Refresh affordance tip-of-tree before phase-20 delivery starts): **pass** — biome verify clean, `bun test` clean, mac test suite 1171 tests / 3 skipped / 0 failures.

> Baseline recorded: 2026-07-14 — pass, 1171 mac tests green, no pre-existing failures to account for.

## Review Rules

- Tickets must be merged in order (P20.01 → P20.02 → P20.03 → P20.04).
- Each ticket PR must pass CI before the next ticket starts.
- No pre-existing CI failures to carry forward per the baseline above; any new failure blocks the ticket that introduced it.
- `subagentReview: skip_doc_only`, `ticketBoundaryMode: gated`, `prReview: disabled`, matching recent phases.

## Explicit Deferrals

- Session-end tombstones / `session_end_at` — `session_end` still deletes the slice.
- In-app hook-mismatch UX.
- Stats tab or floating session-age chip beyond Sessions subtitle + PromptTimer.
- Soft-degrade as the success story (omit/fallback may exist for missing stamps; exit is proven on stamped lockstep dogfood).
- Public notarized DMG / Sparkle.

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.
- Discovery that Force Idle’s idle rewrite cannot clear sticky turn stamps without a second full-slice overwrite schema (surface in P20.02 — do not invent a parallel sidecar).
- Discovery that any of the five installers cannot ship the rebuilt hook binary in the same PR as the writer (surface before merging P20.01).

## Phase Closeout

Retrospective: required  
Why: First multi-stamp sticky slice contract; clear/merge edges and timer hydrate set the pattern for later clocks.  
Trigger: Developer approval of final PR merge.  
Artifact: `docs/product/retrospectives/phase-20-sticky-slice-timestamps-retrospective.md`
