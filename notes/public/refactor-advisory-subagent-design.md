# Refactor subagent review: design stance

**Status:** PROPOSED (stance doc — not implemented in orchestrator).
**Added:** 2026-06-03
**One-liner:** **Completely analogous to adversarial subagent review**, but the
second pair of eyes is scoped to the **Refactor** step of TDD — after Red and
Green on `Red: required` tickets.

**Related:** `docs/template/delivery/delivery-orchestrator.md` (adversarial gate),
`docs/template/delivery/tdd-workflow.md`, `notes/public/subagent-report-parser-contract.md`.

## TL;DR

TDD here is **Red → Green → Refactor**. Red is gated (`post-red`). Green is
implement + verify. **Refactor gets the same “two eyes” pattern as adversarial
review** — not post-verify self-audit, not optional primary discretion to skip
the runner.

| TDD step                 | Who / what                                                            |
| ------------------------ | --------------------------------------------------------------------- |
| **Red**                  | Primary writes failing test; `post-red` records it                    |
| **Green**                | Primary minimum implementation; CI / verify                           |
| **Refactor**             | **Refactor subagent** (cold read) + **primary adjudication** (ledger) |
| **Correctness (pre-PR)** | **Adversarial subagent** (existing) + primary adjudication            |

Two subprocesses before `open-pr` when both policies are on: refactor lens first,
adversarial lens second. Same mechanics; different brief.

## Analogy to adversarial review (complete)

|                                | Adversarial subagent review              | Refactor subagent review                               |
| ------------------------------ | ---------------------------------------- | ------------------------------------------------------ |
| **Purpose**                    | Second eyes on **correctness** before PR | Second eyes on **Refactor** after Green                |
| **TDD leg**                    | Cross-cuts Green (whole diff)            | Explicitly the **Refactor** leg                        |
| **When (orchestrated)**        | After `post-verify`, before `open-pr`    | After `post-verify`, **before** adversarial prompt/run |
| **Primary authors**            | Filled `adversarial-review-template.md`  | Filled `refactor-review-template.md` (TBD)             |
| **Record prompt**              | `write-subagent-adversarial-review`      | `write-subagent-refactor-review` (TBD names)           |
| **Run runner**                 | `subagent-review --subagent …`           | `subagent-refactor-review --subagent …` (TBD)          |
| **Runner contract**            | Advisory only — no worktree writes       | Same                                                   |
| **Invocations**                | Once per ticket per HEAD                 | Same                                                   |
| **Primary applies patches**    | Optional; `[subagent-review]` suffix     | Optional; `[refactor-review]` suffix                   |
| **Primary must accept all?**   | **No**                                   | **No**                                                 |
| **Primary must run runner?**   | **Yes** (when policy on)                 | **Yes** (when `refactorReview` on + `Red: required`)   |
| **Reconcile / ledger**         | `reconcile-subagent-review` + artifact   | `reconcile-subagent-refactor-review` + artifact (TBD)  |
| **Policy off**                 | `subagentReview: disabled`               | `refactorReview: disabled`                             |
| **Policy on (default target)** | `skip_doc_only` / `required` (repo)      | `runner_on_red`                                        |
| **Policy strict**              | `required` + `open-pr` fail-closed       | `runner_on_red_strict`                                 |

**Not analogous:** external post-PR vendors (`poll-review`). Refactor review is
pre-PR, same class as adversarial.

## Plain English — who decides what

| Question                                                           | Answer                                                                                                                        |
| ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| Does the primary choose whether to **call** the refactor subagent? | **No** (when `refactorReview` is on and ticket is `Red: required`). Repo policy + orchestrator commands, same as adversarial. |
| Does the primary choose whether to **apply** each suggestion?      | **Yes**, always — with a **reason per item** in the ledger.                                                                   |
| What is “advisory”?                                                | Runner does not commit; only prose. Does **not** mean “skip the runner.”                                                      |
| Why not `post-verify`?                                             | Same actor as Green — execution-context LGTM; does not give second eyes on Refactor.                                          |

## Problem

Docs teach refactor after green; agents skip it or bundle it into Green. Post-verify
is necessary but **one actor** reviewing its own diff. Adversarial review already
fixed “second eyes before PR” for **correctness**; **Refactor** is still uncovered
unless we add a parallel gate.

Adversarial briefs must stay adversarial (invariants, attack surfaces). Refactor
needs its own prompt — same pipeline, different lens.

## Gate placement (`Red: required`)

```
post-red                    ← TDD Red
  → implement + verify      ← TDD Green
  → post-verify             ← primary self-audit (not Refactor gate)
  → write-subagent-refactor-review
  → subagent-refactor-review --subagent <runner>
  → reconcile-subagent-refactor-review
  → write-subagent-adversarial-review
  → subagent-review --subagent <runner>
  → reconcile-subagent-review
  → open-pr
```

Skip refactor runner when `Red: skip`, `refactorReview: disabled`, or doc-only
auto-skip (if policy mirrors `subagentReview`).

## Policy (`reviewPolicy.refactorReview`)

```json
"refactorReview": "disabled | runner_on_red | runner_on_red_strict"
```

| Value                  | Meaning                                                                         |
| ---------------------- | ------------------------------------------------------------------------------- |
| `disabled`             | No refactor subprocess (today’s behavior)                                       |
| `runner_on_red`        | **`Red: required` only:** must run runner + ledger; may reject every suggestion |
| `runner_on_red_strict` | Same + `open-pr` fails closed if step/artifact missing (pilot before default)   |

Rollout: `disabled` → `runner_on_red` → `runner_on_red_strict` if metrics justify.

Mirror `subagentReview` naming/style in orchestrator docs when implemented.

## Artifacts (parallel to adversarial)

| File                                           | Role                    |
| ---------------------------------------------- | ----------------------- |
| `reviews/<ticket>-refactor-review.prompt.md`   | Primary-filled brief    |
| `reviews/<ticket>-refactor-review.report.md`   | Runner prose            |
| `reviews/<ticket>-refactor-review.ledger.json` | Runner artifact + paths |

**Tagged block** in report (e.g. `<refactor-suggestions>` / `None`) per
`subagent-report-parser-contract.md` — do not reuse `<advisory-observations>`.

**Reconcile ledger rows** (primary, after runner):

- `id` — `R1`, `R2`, …
- `summary`
- `decision` — `accepted` | `rejected` | `deferred`
- `reason` — required for reject/defer

**Runner prompt invariant:** each suggestion states behavior preservation and
which tests still cover it.

## Ironman (what remains)

1. **Cost** — second subprocess per ticket; pay when Refactor debt matters.
2. **Noise** — ledger makes rejects visible; tune prompts before strict policy.
3. **Scope** — refactor models over-abstract; patches must stay green.

**Retired:** “post-verify covers Refactor.” **Retired:** “primary can skip runner”
under `runner_on_red`.

Budget-only fallback: refactor block inside adversarial prompt for one phase —
still a cold reader, but shared subprocess. Default remains **dedicated gate** so
Refactor is not drowned by correctness findings.

## Pilot metrics

- % `Red: required` tickets with ≥1 accepted refactor item
- `[refactor-review]` commit count
- Regressions after accepted refactors
- Reject/defer ratio

## Implementation touchpoints

Mirror adversarial paths in:

- `docs/template/delivery/delivery-orchestrator.md`
- `docs/template/delivery/tdd-workflow.md`
- `docs/template/delivery/refactor-review-template.md` (new)
- `tools/delivery/cli-runner.ts`, `format.ts`, reconciliation helpers
- `.agents/skills/son-of-anton-ethos/SKILL.md`
- `orchestrator.config.json` — `refactorReview`

## Open questions

1. `deferred` → follow-up ticket line automatically?
2. Same runner fallback order as `subagent-review`?
3. Cross-model runner ≠ primary — **recommended yes** (same as adversarial).

---

_Origin: take-a-stance — Refactor leg of TDD deserves adversarial-style second eyes._

_2026-06-03: post-verify ≠ Refactor; primary LGTM bias._

_2026-06-03: concurrence — completely analogous to adversarial review; policy
controls invoke; primary controls adopt with per-item reasoning._
