# P1.10 Source: GitHub PRs + rate-limit cap

Size: 2 points
Type: feat
Scope: engine

## Outcome

- `packages/engine/src/sources/github.ts` exports `readGithubSignals(opts: { token: string; username: string; since: Date }): Promise<GithubSignalSet>` that:
  - Lists merged PRs authored by `username` via GitHub REST API.
  - Applies the locked rate-limit cap: **on first sync (no prior `last_signal_at`), fetch the smaller of "PRs merged in the last 90 days" or "the last 20 merged PRs."** On subsequent syncs, fetch PRs merged since `last_signal_at`.
  - For each PR, calls `enrichPRQuality(pr, octokit)` which fetches review comment count + checks for revert relationship.
  - Returns `GithubSignalSet` containing the PRs (already scored by `scorePR` from `packages/engine/src/loot.ts`, applied at this boundary so the Convex mutation receives pre-enriched data — or alternatively the raw enrichment, with scoring on the Convex side; lock the choice in implementation and document in Rationale).
  - Logs to a debug sink when the rate-limit cap is hit (consumed by P1.20).
- All HTTP calls go through a single client that surfaces rate-limit headers; module gracefully returns a partial result with `rateLimitHit: true` rather than throwing on 403/secondary-rate-limit.
- Tests use a mocked HTTP client (no real GitHub calls in CI). Fixtures cover: clean PR, heavily-reviewed PR, revert relationship, rate-limit response.

## Red

- Write failing tests with a mock HTTP client returning canned fixtures.
- Assert: cap honored on first sync (≤20 PRs / ≤90d), since-cutoff honored on subsequent syncs, enrichment runs per PR, rate-limit response returns partial with `rateLimitHit: true`.
- Commit: `test(P1.10): GitHub PR source with rate-limit cap + PR quality enrichment [red]`.

## Green

- Implement using `@octokit/rest` or a hand-rolled fetch wrapper (prefer the latter to avoid a heavy dep — confirm with developer if octokit adds value).
- Cap logic is centralized in a `applyFirstSyncCap` helper that's independently testable.
- Enrichment is per-PR (`enrichPRQuality(pr)`) and parallelized with concurrency cap (e.g. 4 concurrent) to respect rate limits.

## Refactor

- Extract `applyFirstSyncCap` if logic clutters the main read function.
- Only refactor what this ticket touches.

## Review Focus

- Rate-limit cap: read the plan's locked spec ("last-90-days OR last-20-PRs whichever is smaller on first sync") and confirm test fixtures exercise both arms of the OR.
- Revert detection: criteria documented (does it check title prefix `Revert:`, look at GitHub's `revert_pull_request`, or both?). Heuristics are inherently noisy — log every `scorePR` decision (P1.20 debug log consumes this).
- HTTP client surfaces rate-limit headers so the cap-hit log is informative.
- No real GitHub API calls in tests.
- PAT is passed as a parameter, not read from env inside this module — keeps it pure-ish at the source layer.
- Decide and document: does enrichment scoring happen here, in `syncProfile`, or split? Whichever path, the Rationale section records the choice.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

- **Scoring runs at the source boundary, not in `syncProfile`.** `readGithubSignals` calls `scorePR` per enriched PR and returns `score` + `scoreExplanation` on `GithubPRSignal`. The Convex mutation receives pre-scored data. This keeps the source layer the single place that knows GitHub's response shape — `syncProfile` stays generic over signal kinds and does not need to import GitHub-specific fields. `scorePR` is a pure engine function so it remains isomorphic; running it source-side does not break the server-canonical engine contract.
- **Cap is enforced by `per_page=20` + `merged:>=NINETY_DAYS_AGO` on the search query.** A single search call expresses both arms of the OR (`last 90 days` and `last 20 PRs`) because the API page cap automatically truncates a busy 90-day window to 20 results, and the date filter automatically truncates a quiet last-20 window to ≤20 within the window. `applyFirstSyncCap` then names which arm dominated (`last-20` when the page filled, `ninety-day` otherwise). On subsequent syncs `per_page=100` is used with the caller-supplied `since`.
- **Revert detection lives in `scorePR`, not in this module.** The source surfaces raw PR fields (title, additions, deletions, review_comments) and `scorePR` matches `/^Revert\s+"/i`. This keeps revert heuristics in one place; if the criteria need to expand later (e.g. GitHub `revert_pull_request` rel), the change lands in `loot.ts` and every source benefits.
- **Hand-rolled `fetch` wrapper, no `@octokit/rest`.** A 60-line wrapper covers what we need (auth header, rate-limit detection on 403/429, JSON parse) and stays injectable for tests via the `http` option. Adding octokit would pull a non-trivial dep tree for one search + one PR-detail endpoint.
- **Rate-limit handling is per-phase.** A 403/429 during search returns `{ prs: [], rateLimitHit: true, capApplied: null }`. A 403/429 during enrichment short-circuits the concurrent worker and returns the partial set of already-enriched PRs with `rateLimitHit: true`. The caller decides what to do with a partial result; this module never throws on rate-limit.
