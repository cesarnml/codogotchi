# Review-Gap Ledger

A ledger of **review gaps** — places where the phase pipeline (plan → decompose
→ adversarial subagent review → `/soa tao`) let something through, surfaced when
a fix lands on `main` *after* a phase shipped.

The patch is the symptom; the **gap** is the lesson. Every entry is pointed at
one question: *why didn't we catch this, and what would have?* The eventual
payoff is empirical: when a `defect_class` recurs across phases (and across
repos), it earns a slot in the upstream adversarial-review prompt. Until then it
sits in [`promotion-queue.md`](./promotion-queue.md) as evidence, not doctrine.

> **Status:** dogfooded ad-hoc in codogotchi. The schema below is expected to
> change as real fixes get tagged — the `defect_class` vocabulary in particular
> is still backend-shaped and is growing UI-family classes. Do **not** freeze
> this into an upstream `/soa quality-control` skill until the vocab has taken a
> phase or two of real fixes. See the design notes in memory.

## Files

- **`ledger.jsonl`** — canonical store. One fix per line, append-only. JSONL so
  ledgers from multiple repos can be `cat`-ed together for cross-repo analysis.
  This is the source of truth; any per-phase narrative is a *render* of these
  rows, never a separately-maintained doc.
- **`promotion-queue.md`** — candidate prompt clauses distilled from
  `review_reachable` fixes. A class is promoted to the upstream adversarial
  prompt only after it recurs (≥2–3× across phases/repos).

## Record schema (one JSON object per line in `ledger.jsonl`)

| Field | Values / form | Purpose |
|---|---|---|
| `id` | `<repo>-<NN>` (e.g. `codogotchi-01`) | stable handle; `recurrence` links to it |
| `date` | `YYYY-MM-DD` | when the fix landed |
| `phase` | phase the fix corrects (e.g. `"06"`, or `"04+06"` for an integration gap) | attribution |
| `commit` | short SHA + subject of the `fix(...)`/`feat(...)` commit | provenance |
| `kind` | `bug-patch` · `completeness-feature` · `polish-parity` | separates real defects from sanctioned mini-features and taste-tuning |
| `problem` | prose — what a human observed as wrong | the symptom |
| `solution` | prose — what the patch did (+ any "do not reintroduce") | the fix |
| `defect_class` | one of the 7 diff-derived classes from the adversarial-review template, **or** `NEW: <name>` | the empirical signal — recurring `NEW:` classes are promotion candidates |
| `reachability` | `review-reachable` · `spec-gap` · `experiential-only` · `completeness-gap` | the **router**: which upstream lever (if any) this should move |
| `prompt_lesson` | prose — only when `review-reachable`: the reusable invariant/attack-surface clause | raw material for `promotion-queue.md` |
| `test_reachability` | prose — could a cheap unit test catch a regression here? | honesty about coverage; many UI bugs are integration-only |
| `recurrence` | list of prior `id`s of the same class, or `[]` | counts toward the ≥2–3× promotion bar |

### `reachability` — the router (bias *against* blaming review)

A fix is only `review-reachable` if you can cite the **specific diff hunk + ticket
clause a per-ticket reviewer had in front of them**. No demonstration → it is
`spec-gap` or `experiential-only`. Over-crediting review-reachability bloats the
prompt and teaches it nothing; default to "the review couldn't have seen this"
and make the fix *earn* the blame.

- **`review-reachable`** — a reviewer reading that ticket's diff + spec could have
  demonstrated it. → feeds the **adversarial-review prompt**.
- **`spec-gap`** — neither agent could know; the ticket/plan was underspecified.
  → feeds **`/soa plan` / `decompose`**, not review.
- **`experiential-only`** — only discoverable by using the running product (feel,
  timing, visual rightness). → **QA-lane, permanent.** Not a prompt failure.
- **`completeness-gap`** — obvious-once-you-use-it feature addition. → feeds
  **ideation**.

### `defect_class` — the 7 named classes (extend with `NEW:` honestly)

From `.son-of-anton/docs/template/delivery/adversarial-review-template.md`:
output-stability, cli-symmetry, error-class-breadth, defensive-layering,
cross-file-atomicity, test-contract-strength, doc-vs-code-drift.

These are backend/CLI-shaped. UI bugs in this repo have no word here yet — tag
them `NEW: <name>` (e.g. `NEW: compound-widget-cohesion-under-transform`). The
whole point is to discover which UI-family classes recur enough to deserve a
permanent slot.

## Routing on capture (suggestions, not gates)

When a QC item is larger than a small fix, **suggest** a path with one line of
justification — never hard-stop:

- **ticket-sized** → the orchestrator's standalone-PR path.
- **architectural / phase-sized** → `/soa plan`.

The only real gate is the repo's existing pre-commit law (`bun run format` →
stage → commit; `bun run verify`), since these land on `main`.
