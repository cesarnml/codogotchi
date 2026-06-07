# P11.04 Download endpoint + catalog queries

Size: 2 points
Type: feat
Scope: convex
Red: required

## Outcome

- A public HTTP action `GET /pets/<petId>/download` streams the stored canonical `.codogotchi-pet.zip` with appropriate headers and **increments `downloadCount`**. This single endpoint is the target for all three install paths (npx, curl, direct download).
- A paginated `listPets` query returns **Newest-first** results, **excluding any pet where `listed: false`** (the operator kill-switch), with the fields the gallery grid needs (petId, displayName, authorUsername, tiers, thumbnail URL, downloadCount).
- A `getPet` query returns a single pet's detail payload (including the sheet/zip download URL and per-tier sizes) for the detail page, and returns not-found for unlisted/missing pets.
- An unlisted pet is reachable by neither `listPets` nor `getPet` nor a successful download.

## Red

- Tests: download streams the stored zip and bumps `downloadCount`; `listPets` paginates Newest and hides `listed: false`; `getPet` returns detail for a listed pet and not-found for an unlisted/unknown one; downloading an unlisted pet fails.
- Run the suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P11.04): download endpoint + listed-aware catalog queries [red]`
- Do not write implementation until this commit exists on the branch.

## Green

- Implement the HTTP action and the two queries with the minimal logic to pass; reuse the `pets` shape from P11.02/P11.03.

## Refactor

- Factor the "listed + not-found" guard so `getPet`, `listPets`, and the download action share one visibility rule.

## Review Focus

- The `listed` kill-switch must be enforced on **every** read path (list, detail, download) — a pet unlisted by the operator must be fully unreachable, not just hidden from the grid.
- `downloadCount` increment correctness under the HTTP action (no double-count on range requests / retries if relevant).
- Verify the download URL the queries hand the client matches what the curl one-liner and CLI expect (check both sides of the boundary, not each in isolation).
- Deferred: likes/views/comments and their sorts; signed/expiring URLs.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [any deviation from the ticket metadata contract]
