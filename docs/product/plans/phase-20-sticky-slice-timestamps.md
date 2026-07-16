# Phase 20: Sticky Slice Timestamps

**Delivery status:** Delivery complete — all 4 tickets shipped (P20.01 [PR #186](https://github.com/cesarnml/codogotchi/pull/186), P20.02 [PR #187](https://github.com/cesarnml/codogotchi/pull/187), P20.03 [PR #188](https://github.com/cesarnml/codogotchi/pull/188), P20.04 docs/retrospective this PR). Retrospective at `docs/product/retrospectives/phase-20-sticky-slice-timestamps-retrospective.md`. Awaiting developer review and `closeout-stack`.

## TL;DR

**Goal:** Make every `state.d` slice carry durable turn/session/error clocks so the prompt timer (and related freezes) stay correct on any rendering window after hide, TTL, fold churn, or app relaunch — and so Settings > Sessions can show when a session started.

**Ships:**

- Schema bump of the on-disk slice contract with four sticky optional timestamps: `prompt_started_at`, `session_started_at`, `errored_since`, `turn_ended_at`.
- Hook writers that set/clear/preserve those stamps at the right lifecycle edges (not on every mid-turn tool tick).
- Prompt timer that reads those stamps so elapsed (running or frozen) matches across own / minimalist / combined and session pets on / off.
- Settings > Sessions subtitle showing relative “Started …” for Active, Live, and Archived when the stamp exists (combined with existing Idle age when both apply).
- Lockstep ship of contracts, hook binary, five platform installers, menubar, fixtures, and contract docs — called out in release notes only (no in-app “hooks outdated” nudge).

**Defers:**

- `session_end_at` / session-end tombstone slices (today `session_end` deletes the file).
- In-app upgrade/mismatch UX for old hooks.
- Stats-tab or floating-window session-age chrome beyond Settings > Sessions and the existing PromptTimer chip.
- Soft-degrade as the *success* story (pre-stamp slices may still omit “Started” and fall back for the timer during transition; exit assumes lockstep dogfood).
- Public notarized DMG / Sparkle mass rollout (still Track 2 / v3 release work).

---

Phase 18 deferred the “v4 hook-stamped `prompt_started_at` architecture.” Phase 19 (fold-window session identity) is closed on `v3_preview` — all tickets done, retrospective and advisory triage landed, feat commits on the branch — so this phase is unblocked. Today the PromptTimer starts from in-memory trackers keyed off slice `updated_at`, which advances on every tool write and is lost when a render key leaves TTL eligibility; that is why elapsed time lies or resets across windows and relaunches. Sticky on-slice clocks are the durable fix.

## Phase Goal

This phase should leave the product in a state where:

- After a prompt starts, any floating pet window that shows that session — any window kind, after hide/show, idle TTL dismiss, fold winner changes, or app relaunch — shows the **same running prompt elapsed** as if the timer never left memory.
- After a turn freezes (waiting for input, or errored long enough to count as terminal), any window / relaunch shows the **same frozen duration**, driven by on-disk `turn_ended_at` / `errored_since` semantics — not by whether a particular panel happened to own the tracker.
- Settings > Sessions lists Active, Live, and Archived rows with a relative **Started** line when `session_started_at` is present (e.g. `Started · 2h ago`, or combined with Idle age when both exist); pre-stamp rows simply omit it.
- Shipping assumes a clean cut for today’s tiny user set: app + hook + installers together, documented in release notes — not an in-app migration wizard.

## Committed Scope

### Sticky clocks on every slice

- Each `state.d` slice may carry: when the current prompt/turn started, when this session file was first born, when the slice entered a lasting error, and when the current turn’s clock froze/ended.
- Mid-turn activity must not rewrite turn-start or session-birth stamps; only the defined lifecycle edges may set or clear them.
- Force Idle and other user “go idle” paths clear turn clocks the same way the prompt timer resets today.

### Prompt timer truthfulness

- The PromptTimer chip hydrates from those stamps so running and frozen elapsed stay correct across every render surface and process lifetime covered above.
- This is the forcing function of the phase — Settings “Started” is a co-shipped consumer, not a substitute for timer correctness.

### Settings > Sessions “Started”

- Relative started-at copy under the session title for Active, Live, and Archived when the stamp exists.
- Missing stamp → omit (no fake time from `updated_at`).
- When Idle age is already shown, combine into one subtitle line rather than inventing a second row of chrome.

### Lockstep delivery + docs

- Contracts, hook, five installers, menubar readers/writers, fixtures, and animation-state vocabulary updated together.
- Release notes (and dogfood instructions) state that hook install must be refreshed with the app; no in-app outdated-hooks banner.

## Explicit Deferrals

- **Session-end tombstones / `session_end_at`** — `session_end` still deletes the slice; history-of-ended-sessions stays out of this contract.
- **In-app hook-mismatch UX** — lockstep + release notes only until notarized v3 / Sparkle makes mass upgrades real.
- **Extra clocks UI** — no Stats tab clocks, no new floating “session age” chip; only Sessions subtitle + existing PromptTimer.
- **Treating soft fallback as “done”** — optional omit/fallback for missing stamps may exist for parse safety; phase exit is proven on the stamped lockstep path.
- **Mass public release** — notarization and Sparkle remain outside this phase.

## Exit Condition

A dogfooded lockstep build (updated app + refreshed hook install) shows matching prompt elapsed on own, minimalist, combined, and session on/off after hide, TTL dismiss, fold churn, and relaunch — including frozen elapsed after waiting or long-errored turns. Settings > Sessions shows relative Started for rows that have the stamp and omits it otherwise. Contract docs and fixtures describe the new schema; retrospective is written before the phase is called closed.

## Retrospective

`required` — first multi-stamp sticky slice contract; clear/merge edges and timer hydrate will set the pattern for later clocks. Worth capturing while the surprises are fresh.
