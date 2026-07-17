# Codogotchi review-gap ledger analysis — 2026-07

Source: `codogotchi` repo, `docs/product/review-gaps/ledger.jsonl` (55 rows at
analysis time, both schema generations — legacy string `reachability` and the
current `{classification, evidence?, promptLesson?}` object form). This
analysis accounts for **every** row and applies the promotion bar from
`docs/product/review-gaps/README.md`: only `review-reachable` rows are
candidates for `adversarial-review-template.md`; the other three
classifications (`spec-gap`, `qa-gap`, `completeness-gap`) route elsewhere by
design and are not promotion candidates regardless of recurrence.

## Row accounting

55 physical lines, 55 rows, machine-counted directly from
`reachability`/`reachability.classification` across both schema generations
(verified with a script reading every line, not by inspection). Two legacy
free-form classifications predate the current four-value enum
(`test-isolation-gap` ×1, `adversarial-review-gap` ×2) — these are also not
promotion candidates; they are noted separately below, not folded into either
bucket, since neither matches the current schema's vocabulary. One row (the
phase-19 "floating-pet right-click actions never notified Settings >
Sessions tab" entry) has a missing top-level `id` field but a well-formed
`reachability.classification` (`completeness-gap`) and is counted normally.

| Classification                  | Count  |
| ------------------------------- | ------ |
| `qa-gap`                        | 22     |
| `review-reachable`              | 11     |
| `completeness-gap`              | 11     |
| `spec-gap`                      | 8      |
| legacy `adversarial-review-gap` | 2      |
| legacy `test-isolation-gap`     | 1      |
| **Total**                       | **55** |

## Review-reachable rows (promotion candidates)

| id              | phase | defect class                                                     | promotion verdict                                     |
| --------------- | ----- | ---------------------------------------------------------------- | ----------------------------------------------------- |
| `codogotchi-01` | 04+06 | compound-widget-cohesion-under-transform                         | not promoted (1× as its own class; see below)         |
| `codogotchi-10` | 10    | control-signal-starved-by-change-gated-callback                  | **promoted** (clause 8)                               |
| `codogotchi-11` | 10    | unguarded-fresh-install-bootstrap                                | not promoted (1×, single occurrence)                  |
| `codogotchi-12` | 10    | doc-vs-code-drift                                                | not promoted (already covered by clause 7)            |
| `codogotchi-13` | 10    | rate-counter-conflates-event-with-time-unit                      | not promoted (1×, single occurrence)                  |
| `codogotchi-20` | 13    | pool-refactor-dropped-single-owner-behavior                      | not promoted (mixed-classification family, see below) |
| `codogotchi-27` | 08    | version-proxy-conflates-binary-internals-with-registration-drift | not promoted (1×, single occurrence)                  |
| `codogotchi-43` | 19    | source-identity-used-instead-of-folded-render-target             | **promoted** (clause 9, with 44/45)                   |
| `codogotchi-44` | 18    | pre-folded-combined-key-loses-winner-origin-on-transition        | **promoted** (clause 9, with 43/45)                   |
| `codogotchi-45` | 16    | session-source-identity-collapsed-into-folded-render-key         | **promoted** (clause 9, with 43/44)                   |
| `codogotchi-46` | 19    | protocol-default-noop-swallows-adapter-forward                   | not promoted (1×, single occurrence)                  |

## Promoted classes

### `control-signal-starved-by-change-gated-callback` → clause 8

**Count verification (ticket-mandated — do not trust the queue without
checking ledger rows directly):** codogotchi's `promotion-queue.md` claims
this class is "AT THRESHOLD (3×)" citing `codogotchi-01` round-1,
`codogotchi-10`, and a "phase-19 QC instance" (commit `2e817a9b`). Checking
that third row directly against the ledger: its
`reachability.classification` is **`completeness-gap`**, not
`review-reachable` — the queue's count claim does not match the ledger. This
is a real discrepancy between the queue and the ledger; per this ticket's
instruction, the ledger wins and the discrepancy is named here rather than
silently accepted.

Net: **2 confirmed `review-reachable` occurrences** (`codogotchi-01`
round-1's bubble re-anchor hung on a `mouseUp`-only persist handler;
`codogotchi-10`'s RPG HUD toggle re-read only inside a delta-gated poll
callback) plus **1 corroborating `completeness-gap` occurrence** (the
`2e817a9b` session-label rename, starved on an unrelated ~1s poll tick — same
causal mechanism, but only detected by manual dogfooding, hence the more
conservative classification).

2 confirmed `review-reachable` occurrences falls within the promotion
queue's own stated bar ("recurs ≥2–3×" — a range starting at 2, not a floor
of 3), and the corroborating third instance strengthens rather than
undermines the case: the same starvation mechanism has now surfaced in three
structurally different subsystems (drag-chrome re-anchoring, a settings
toggle, a session-label cache). Promoted as clause 8 with the count corrected
in-clause rather than repeating the queue's overclaim.

**Caveat not carried into the clause** (from the promotion queue): whether
this belongs as a per-ticket review-prompt clause vs. a phase-integration
checklist item was flagged as an open question when `codogotchi-01`'s
container and overlay shipped in different phases. `codogotchi-10` and the
third instance were both same-diff review-reachable, so the per-ticket clause
form is sound for those; the phase-integration angle remains a live question
for `codogotchi-01`-shaped cases specifically and is not resolved by this
promotion.

### Source-identity-vs-folded-render-target family → clause 9

**Not yet in codogotchi's `promotion-queue.md`** — all three ledger rows
(`codogotchi-43`, `-44`, `-45`) are dated 2026-07-14, after the queue's most
recent update. This is exactly the "queue and ledger disagree" case the
ticket asks to reconcile: the queue simply hasn't caught up to these three
rows yet, so there is no existing verdict to check against — this is a fresh
promotion based on direct ledger reading, not a queue-recorded, at-threshold
class.

All three rows are `review-reachable` and share one mechanism: a source
record (a window, a session, a Sessions-tab row) can fold, cap, or route into
a shared render/output target, and a consumer somewhere acts on the raw
source identity instead of resolving through the same source-to-target
mapping the rendering path uses:

- `codogotchi-43`: a Show/Hide action on an individually-listed row forwarded
  the row's own id to the visibility API, when the persisted visibility guard
  actually belonged to the shared folded key the row rendered into — the
  action silently no-op'd. A bulk "Show All" action had the same shape one
  level up: its target set was derived from a filter that omitted the hidden
  folded key entirely.
- `codogotchi-44`: a transient-gap retention check used an "is any source
  still configured for this fold" predicate instead of consulting the
  actually-retained winner's own persisted identity, so the retained window
  outlived every source that had actually produced it.
- `codogotchi-45`: a rendered/unrendered classification compared a source's
  own key directly against the pool's active _render_ keys, without
  resolving through the fold — so a genuinely-rendered winning source could
  be marked as not-rendered, and labels were requested from the folded key
  instead of the source's own identity. The same identity collapse reached
  menu titles and Show/Hide actions.

3 confirmed `review-reachable` occurrences, all in the same recurrence chain
(`codogotchi-45` explicitly lists `codogotchi-43` and `codogotchi-44` as
`recurrence`), across three different phases (16, 18, 19) and at least two
different consumer shapes (individual actions, bulk actions, classification
logic) — clears the bar cleanly. Promoted as clause 9.

## Not promoting these, and why

**Single-occurrence `review-reachable` rows** (below the ≥2× bar):
`codogotchi-11` (unguarded-fresh-install-bootstrap), `codogotchi-13`
(rate-counter-conflates-event-with-time-unit), `codogotchi-27`
(version-proxy-conflates-binary-internals-with-registration-drift),
`codogotchi-46` (protocol-default-noop-swallows-adapter-forward). Each names
a real, well-articulated pattern (see codogotchi's `promotion-queue.md` for
the full proposed-clause writeups) but has not recurred; promoting a
single-instance clause taxes every future review for a pattern not yet shown
to generalize. Revisit each on a second occurrence.

**`codogotchi-12` — doc-vs-code-drift:** already covered by the existing
clause 7 ("Doc-vs-code drift in the ticket Rationale"); no new clause needed.

**`codogotchi-01` as its own class
(`compound-widget-cohesion-under-transform`):** the promotion queue's own
caveat blocks naive promotion — this class is only review-reachable when the
transformable container and its attached overlay ship in the **same ticket
diff**; here the pet (phase 4) and the bubble (phase 6) shipped in different
phases, so no per-ticket reviewer had both in view. This is a
**phase-integration-pass candidate**, not a per-ticket adversarial-review
clause — flagging it here per this ticket's explicit instruction to name
such cases rather than silently promote or silently drop them. Recommend
routing to a phase-closeout integration-review checklist item instead of
`adversarial-review-template.md`.

**`codogotchi-20` — pool-refactor-dropped-single-owner-behavior:** this row is
part of a 3-occurrence family in codogotchi's promotion queue
(`side-effect-call-dropped-or-mis-targeted-in-refactor`: `codogotchi-15`,
`-18`, `-20`), but only `codogotchi-20` itself is classified
`review-reachable` — `codogotchi-15` is the legacy `adversarial-review-gap`
classification and `codogotchi-18` is `qa-gap` (a dropped callback wiring
buried in an AppKit factory closure, not unit- or diff-reachable). Per the
promotion queue's own analysis, the family splits across two levers (a
diff-visible "regression-smell comment" tell for the review-reachable
instances, and a silent/buried-wiring shape for the qa-gap instances) that
may need two different treatments rather than one prompt clause. Consistent
with this ticket's explicit caveat ("classes only review-reachable when both
halves ship in one diff are flagged as phase-integration-pass candidates, not
silently promoted"), this is flagged as a **mixed review-prompt /
phase-integration-checklist candidate**, not promoted outright pending that
split decision.

**`spec-gap` rows (8):** route to future planning / `/soa plan` / ticket
acceptance criteria per the README's routing table — the gap was in what was
specified, not in what a reviewer could have caught from the diff. Not
adversarial-review-prompt material by definition.

**`qa-gap` rows (22):** route to manual QA / dogfood checklists per the
README's routing table — these require running the app and observing real
behavior (visual sizing, live template-image rendering, filesystem contents
an external process populated, timing under real hardware) that a diff
review cannot reach. The largest single category by count; several form
their own recurring families already tracked in codogotchi's
`promotion-queue.md` (e.g. `user-hide-overwritten-by-periodic-respawn`,
`hide-toggle-conflated-with-pool-slot-release`) as **dogfood-checklist**
candidates, explicitly not adversarial-review-prompt material since the
detection lever is running the app, not reading the diff.

**`completeness-gap` rows (11, including the unlabeled phase-19 row):** route
to future phase shaping or standalone-PR follow-through per the README —
delivered scope was individually valid but missed adjacent, predictable
work. Not a per-ticket review-prompt gap by definition; several are tracked
as their own recurring families in codogotchi's `promotion-queue.md`
(`new-enum-case-skips-existing-transition-matrix`,
`adjacent-consumer-of-changed-key-shape-missed-across-file-boundary`) with
their own phase-integration/checklist routing already reasoned through
there — not duplicated here.

**Legacy classifications (`test-isolation-gap` ×1, `adversarial-review-gap`
×2):** these three rows (`codogotchi-06`, `-14`, `-15`) predate the current
four-value `reachability.classification` enum and use free-form strings that
don't map cleanly onto it. `codogotchi-14`/`-15` form their own 2×
recurrence (`stale-read-target-after-architecture-migration`) that the
promotion queue does not carry a verdict on (it isn't `review-reachable` by
current-schema standards — a stale read target after a migration is not
generally diff-visible from a single ticket's changes). Left un-promoted and
un-reclassified here: relabeling historical rows under the current schema is
outside this ticket's scope and would need its own pass with enough judgment
calls that it should not be done as a side effect of this analysis.

## Phase-integration-pass candidates (not adversarial-review clauses)

Flagged separately per the promotion-queue caveat this ticket calls out —
classes that are only review-reachable when two halves of one causal chain
ship in the same diff, and are not review-reachable when they ship across
separate tickets/phases (the common case for both):

- `compound-widget-cohesion-under-transform` (`codogotchi-01`) — container
  and attached overlay transform cohesion.
- `pool-refactor-dropped-single-owner-behavior` /
  `side-effect-call-dropped-or-mis-targeted-in-refactor`
  (`codogotchi-15`/`-18`/`-20`) — a refactor from a single owner to a
  pool/factory dropping a behavior the old owner performed, when the drop
  isn't visible in the same diff as the refactor.

Recommend a future ticket define a lightweight phase-closeout integration
checklist (distinct from the per-ticket adversarial-review prompt) to carry
these; out of scope to design here.
