# P11.06 Marketplace SPA — shell, gallery grid, pet detail + install card

Size: 5 points
Type: feat
Scope: web
Red: skip

## Outcome

- A single static Astro route hosts a **React SPA island** wired to the Convex client, with **client-side routing** for the gallery list, pet detail, and (placeholder for) upload — no SSR adapter; static hosting preserved.
- **Gallery grid:** cards rendering the static idle-frame thumbnail, `displayName`, `by <username>`, **tier badges** (Codex / Lite-Basic / Lite-Enhanced / SoA present), and download count; with **search** and **Newest** sort and **pagination**, fed by `listPets` (P11.04).
- **Pet detail:** the install card with the **three install paths** — `npx codogotchi add <id>`, the curl one-liner, and the direct `.zip` download — plus a **per-tier readout** (which tiers + sizes) and **client-side sprite animation** that cycles the 8 atlas frames of the downloaded sheet (looks like the codex-pets animation grid; no GIF files).
- `web/src/pages/pets.astro` **redirects to `/gallery`**; a footer disclaimer is present ("pets are community-shared, may be inspired by existing characters or brands; we don't claim rights to them").

## Red

- **`Red: skip`** — this ticket is predominantly UI scaffolding/integration with no isolated business logic that warrants a failing-test-first gate.
- **Testing strategy (still required, as unit tests, not a Red gate):** add focused unit tests for the three pure pieces and call them out in Review Focus —
  1. the **install-command string builder** (given a `petId` + endpoint base, produces the exact npx/curl strings the CLI/endpoint expect),
  2. the **sprite-frame slicer** (given sheet dimensions + cell size, yields correct per-frame crop coordinates),
  3. the **client-side router** path↔view mapping.
- These ship in the Green commit (no separate `[red]` commit, since the ticket is UI-scaffold classified).

## Green

- Scaffold the Astro route + React island + Convex client; implement routing, the grid (search/sort/pagination), and the detail/install-card with the sprite animation; wire the `pets.astro` redirect and footer.

## Refactor

- Extract the install-string builder and sprite-slicer as standalone tested utilities (imported by the components) rather than inline logic.

## Review Focus

- **Cross-boundary correctness:** the install strings and download URL the detail page renders must exactly match P11.04's endpoint and P11.05's `add` expectations — verify both sides, not each alone.
- Static-hosting integrity: confirm no SSR/adapter crept in and arbitrary `/gallery/<unknown-id>` resolves via client routing, not a 404 from the static host.
- Grid performance: cards use the small thumbnail blob, not full atlases; the detail page downloads the full sheet once.
- The three extracted utilities have unit tests (the testing strategy above).
- Deferred: likes/views/comments, tag/category filters, Collections/Creators, GIF-file export.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first — or N/A, UI-scaffold ticket]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [any deviation from the ticket metadata contract]
