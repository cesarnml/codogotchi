# How Son of Anton Works — A Newcomer's Mental Model

> **Who this is for:** anyone seeing this codebase for the first time — especially
> students arriving through an AI-assisted coding course. By the end you should be
> able to explain _what_ Son of Anton (SoA) does, _why_ it's shaped the way it is,
> and _where_ each idea lives in the code — enough to make a confident first
> contribution. **No prior knowledge assumed.** You do not need to read any source
> file to finish this page; the file pointers are there for when you're ready.
>
> This is the **map**. The authoritative references are linked at the end — reach
> for them once the map makes sense.

---

## 1. The one problem it solves

AI coding agents are powerful, but using them tends to collapse into one of two
bad habits:

- **Babysitting** — you approve every line, and the agent never builds momentum.
- **Vibe-coding** — you let it run free, get a giant diff, and rubber-stamp code
  you don't really understand.

SoA's whole thesis is that there are **exactly three moments** where your human
judgment is irreplaceable, and the tool should automate _everything between them_.
You stay in control of the decisions that matter; the agent gets room to actually
work.

> The goal is to be able to say _"I delivered this with AI help"_ — not _"I asked
> an AI to build this and hoped it was right."_ That difference is the entire ethos.

---

## 2. The big picture in one diagram

```
   YOU                          THE ORCHESTRATOR (automated)                 YOU
    │                                                                         │
    ▼                                                                         ▼
┌─────────┐   ┌──────────────┐   ┌──────────────────────────────────┐   ┌──────────┐
│ /soa    │──▶│ /soa         │──▶│ /soa execute                     │──▶│ /soa     │
│ plan    │   │ decompose    │   │  for each ticket:                │   │ closeout │
│         │   │              │   │   red → green → refactor →       │   │          │
│ approve │   │ approve the  │   │   adversarial review → open PR   │   │ approve  │
│ the WHAT│   │ HOW (tickets)│   │   → poll CI/AI review → advance  │   │ DONE     │
└─────────┘   └──────────────┘   └──────────────────────────────────┘   └──────────┘
   GATE 1          GATE 2                  (no human needed)               GATE 3
```

**The three gates are the product.** Everything else — stacked PRs, worktrees,
TDD scaffolding, review runners — is _mechanism_ in service of those gates. If you
remember nothing else, remember: **slice → review gate → explicit advance.**

---

## 3. The vocabulary (learn these 8 words)

| Term                   | Plain meaning                                                                             |
| ---------------------- | ----------------------------------------------------------------------------------------- |
| **Phase**              | One chunk of product work (a "milestone"). Has a plan + a stack of tickets.               |
| **Ticket**             | One thin, reviewable slice of a phase. Becomes one branch + one PR.                       |
| **Plan**               | The approved _what & why_ of a phase. A markdown doc you sign off on (Gate 1).            |
| **Decompose**          | Turning an approved plan into an ordered, dependency-aware ticket stack (Gate 2).         |
| **Gate**               | A point where the workflow **stops and waits for your explicit yes.** There are three.    |
| **The orchestrator**   | The TypeScript CLI that drives the loop _between_ gates.                                  |
| **Skill**              | Markdown instructions an AI agent reads to know _how_ to behave (in `.agents/skills/`).   |
| **Adversarial review** | After a ticket is built, a _second_ AI reads the diff assuming the first one cut corners. |

---

## 4. The two halves of the codebase (this is the key insight)

SoA is **half deterministic program, half agent instructions.** Newcomers get
confused until they see this split:

```
┌────────────────────────────────────┐     ┌────────────────────────────────────┐
│  THE CODE  (tools/delivery/*.ts)    │     │  THE SKILLS  (.agents/skills/*.md)  │
│                                     │     │                                     │
│  Deterministic. Runs on Bun/Node.   │     │  Behavioral. An AI agent reads them │
│  Manages state, branches, PRs,      │ ◀──▶│  and acts. They tell the agent      │
│  worktrees, review artifacts.       │     │  *what to do at each step* and      │
│  Never "thinks" — it bookkeeps.     │     │  *which CLI command to run next*.   │
└────────────────────────────────────┘     └────────────────────────────────────┘
        the rails                                   the driver
```

The CLI is the **rails**: it records that ticket 3 is `verified`, that a PR was
opened, that a review found 2 issues. The skills are the **driver**: they tell the
agent to write the failing test, implement, run the next command, and so on. The
agent and the CLI talk to each other through **durable files on disk**, not through
chat memory — which is the next big idea.

---

## 5. Durable artifacts > chat memory

The classic AI failure mode is that the real state of the work lives only in a
chat thread — close the tab and it's gone. SoA refuses this. **Everything that
matters is written to a file:**

- the plan and ticket docs (`docs/product/...`)
- per-ticket **handoff** docs (so work can resume after a crash or a new session)
- review outcomes and ledgers (`*-subagent-review.{prompt,report,ledger}` files)
- the orchestrator's own **state** (which ticket, what status — see `state.ts`)

This is why you can stop mid-phase, come back tomorrow in a fresh session, run
`status`, and the orchestrator tells you exactly what to do next. The answer to
_"what happened?"_ never lives only in an AI's memory.

---

## 6. The life of a single ticket (the inner loop)

Inside `/soa execute`, every code ticket walks a small **state machine**. The
states are defined in [`tools/delivery/types.ts`](../tools/delivery/types.ts)
(`TicketStatus`):

```
pending → in_progress → red_complete → verified → subagent_review_complete
        → in_review → (needs_patch ⟲ | operator_input_needed) → reviewed → done
```

Mapped to what actually happens (this is just **Test-Driven Development** with a
review gate bolted on):

1. **Red** — write a test that describes the desired behavior and _fails_. (`post-red`)
2. **Green** — implement until the test passes. (`implement` + `verify`)
3. **Refactor** — clean it up with tests still green. (`post-verify`)
4. **Adversarial review** — a _second, cold_ AI reads the diff hunting for holes.
   It is **advisory**: it returns findings as prose only and never edits your
   files. The primary agent decides what to patch.
5. **Reconcile** — a deterministic check (`reconcile-subagent-review`) makes sure
   the recorded review outcome doesn't _lie_ about what's actually in git. This
   gate blocks `open-pr` if the ledger and the diff disagree. Honesty is enforced
   by code, not trust.
6. **Open PR** — the ticket ships as its own stacked PR; CI and external AI
   reviewers are polled; their comments are triaged; then the loop advances to the
   next ticket.

When the whole stack is built, **you** review it and run `/soa closeout`, which
squash-merges the stack onto `main`. Nothing merges without you.

---

## 7. Knobs you'll see (don't memorize — just recognize)

SoA stays opinionated but tunable. Two families of knobs matter:

- **Boundary mode** — `cook` (run ticket-to-ticket without stopping) vs `gated`
  (stop after each ticket and wait for you). Defined in `config.ts`.
- **Review policy** — each review stage can be `required`, `skip_doc_only` (skip
  for docs-only changes), or `disabled`.

These can live in `orchestrator.config.json` _or_ be overridden per-run with a
flag (e.g. `--boundary-mode gated`). Flag beats config beats default — a
precedence pattern you'll see repeated throughout the code.

---

## 8. The ouroboros (why the docs look doubled)

SoA **builds itself using its own orchestrator.** It eats its own dog food. This
explains a layout quirk that trips up newcomers:

- `docs/template/` is the layer that **ships into other repos.** When someone
  installs SoA with `git subtree add --prefix .son-of-anton`, they get those files
  at `.son-of-anton/docs/template/`. The `template/` name is from _their_
  perspective — it's the stuff consumers reference.
- Everything else in `docs/` (including this file) is **about developing SoA
  itself.**

So some docs are simultaneously _this repo's_ working guidance **and** the shipped
product. When in doubt: `template/` = consumer-facing; the rest = contributor-facing.

---

## 9. The code map (where each idea lives)

You rarely need all of these at once. Find the concept you're touching, start there.

| If you're working on…                     | Start in…                                                                                                             |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| The CLI entry point                       | [`scripts/deliver.ts`](../scripts/deliver.ts) → [`tools/delivery/orchestrator.ts`](../tools/delivery/orchestrator.ts) |
| Parsing command-line flags                | [`tools/delivery/cli.ts`](../tools/delivery/cli.ts)                                                                   |
| The vocabulary / all the type definitions | [`tools/delivery/types.ts`](../tools/delivery/types.ts) — **read this first; it's the dictionary**                    |
| Reading/writing durable state             | [`tools/delivery/state.ts`](../tools/delivery/state.ts)                                                               |
| The per-ticket state machine              | [`tools/delivery/ticket-flow.ts`](../tools/delivery/ticket-flow.ts)                                                   |
| Parsing plans & ticket files              | [`tools/delivery/planning.ts`](../tools/delivery/planning.ts)                                                         |
| Adversarial review machinery              | `subagent-prompt.ts`, `subagent-runner.ts`, `review.ts`                                                               |
| The "don't let the ledger lie" gate       | [`tools/delivery/reconciliation.ts`](../tools/delivery/reconciliation.ts)                                             |
| Config & policy resolution                | [`tools/delivery/config.ts`](../tools/delivery/config.ts)                                                             |
| Talking to git / GitHub (`gh`)            | `platform.ts`, `platform-adapters.ts`                                                                                 |
| Squash-merging a finished phase           | [`tools/delivery/closeout-stack.ts`](../tools/delivery/closeout-stack.ts)                                             |
| Agent behavior / what `/soa <cmd>` does   | [`.agents/skills/`](../.agents/skills/) (start with `soa/SKILL.md`)                                                   |
| Docs that ship to consumers               | [`docs/template/`](./template/)                                                                                       |

Tests live next to the code in `tools/delivery/test/` and run with `bun test`.

---

## 10. See it run once (the fastest way to "get it")

Reading about a workflow is no substitute for watching it move. From a clean
clone:

```bash
bun install
bun run ci      # format check + lint + tests — should pass on a fresh clone
```

Then skim [`docs/template/overview/start-here.md`](./template/overview/start-here.md)
and trace one phase that already exists under `docs/product/` from plan → tickets.
Watching one real phase go plan → decompose → execute → closeout will teach you
more than any diagram here.

---

## 11. Your first contribution

1. Read [`CONTRIBUTING.md`](../CONTRIBUTING.md) — setup, dev commands, and the
   **format-before-stage** rule (`bun run format`, then stage, then commit).
2. Browse the
   [`good first issue` label](https://github.com/cesarnml/son-of-anton/labels/good%20first%20issue).
   Each one has a _"Getting oriented"_ section and pointers tuned for newcomers.
3. Pair with your AI agent — but **stay the driver.** That's literally the lesson
   SoA exists to teach: let the AI cook inside boundaries you control.
4. Open one small, focused PR. Smaller PRs move faster. Stuck? Comment on the
   issue — questions are welcome.

> **The meta-lesson:** the discipline SoA enforces on _its users_ is the same
> discipline that makes you a good contributor _to_ it — small reviewable slices,
> durable artifacts over memory, and a human who owns the decisions that matter.

---

## Authoritative references (go deeper)

Read these in order once this map makes sense:

1. [`README.md`](../README.md) — the product pitch and full command surface.
2. [`docs/template/overview/start-here.md`](./template/overview/start-here.md) — onboarding & the four control points.
3. [`docs/template/delivery/son-of-anton.md`](./template/delivery/son-of-anton.md) — the doctrine & philosophy (_why_ it's shaped this way).
4. [`docs/template/delivery/delivery-orchestrator.md`](./template/delivery/delivery-orchestrator.md) — the authoritative CLI command reference.
5. [`docs/template/delivery/tdd-workflow.md`](./template/delivery/tdd-workflow.md) — the Red/Green/Refactor contract.
6. [`docs/README.md`](./README.md) — the full docs index.
