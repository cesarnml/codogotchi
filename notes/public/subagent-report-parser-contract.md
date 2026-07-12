# Subagent report ↔ Advisory-Observations parser: stop the arms race

**Status:** DECIDED (converged design). Supersedes the earlier proposal draft.
**Trigger:** 3rd–5th recurrence of report-format drift breaking the
`Advisory Observations` parser (Phase 05, Phase 17 ×2, Phase 08 ×2).
**Owns:** `docs/template/delivery/adversarial-review-template.md`,
`docs/template/delivery/subagent-review-report-template.md`,
`tools/delivery/reconciliation.ts` (`parseAdvisoryObservations`,
`extractReportSection`), `tools/delivery/advisory-observation-command.ts`,
`tools/delivery/cli-runner.ts` (`subagent-review` record path).

## TL;DR — the decision

Replace the heading-based markdown grammar and its accreted tolerance with a
**tagged contract** plus a **record-time loud floor**:

1. **Contract = a balanced tag block the agent copies verbatim:**

   ```
   <advisory-observations>

   * one observation per bullet
   * another observation

   </advisory-observations>
   ```

   If there is nothing to report, the block contains the single literal line
   `None` (no bullets).

2. **Parser = barebones + strict.** Extract everything between
   `<advisory-observations>` and `</advisory-observations>`; keep `^\*` bullet
   lines; ignore the rest. Delete all the tolerance heuristics that accreted
   across the five failures (multi-style heading recognition, `---` stripping,
   bullet-vs-paragraph fallback, heading aliases, runnerStatus terminator).
   The tag _is_ the boundary, so none of that machinery is needed.

3. **Floor = a zero-parse warning at `subagent-review` record time.** If the
   tag block is present but yields 0 bullets and is not the literal `None`
   (or the tag is malformed / unclosed / misnamed), print a warning **when the
   report lands**, while the primary agent is running that command in-session.

4. **No retry loop. No `## heading` fallback. No XML for the prose.** The rest
   of the report stays human-readable markdown; only the machine-read region
   is tagged.

## The recurring failure (why we are here)

The subagent-review report is consumed by a machine
(`parseAdvisoryObservations`) but written as free-form markdown by an LLM.
Every phase the LLM found a new way to format the section that the regex
grammar did not accept. Each time we patched **both** the parser (a new
defensive heuristic) **and** the template (a new "do not do X" paragraph).
Neither generalized; the template grew; the next drift was uncovered.

| #   | Phase | Drift the agent produced                          | Parser symptom                                                                 | Reactive fix (now retired)                     |
| --- | ----- | ------------------------------------------------- | ------------------------------------------------------------------------------ | ---------------------------------------------- |
| 1   | 05    | `**A1 — Title**` bold prefix on its own line      | every bold line read as a section terminator → **0 observations**              | canonical-heading allowlist + template prose   |
| 2   | 17    | cosmetic `---` rules between sections             | broke all-bullets check → paragraph mode → `- ` prefixes leak into keys        | strip `---` + template prose                   |
| 3   | 17    | `**runnerStatus:**` inline key-value              | section never terminated → runner metadata leaks as fake observations          | runnerStatus terminator regex + template prose |
| 4   | 08    | **plain-text heading** (no `**`/`#`)              | `extractReportSection` finds no heading → **0 observations, silently skipped** | — (this redesign)                              |
| 5   | 08    | `` `runnerStatus`: `` (backtick, no leading `**`) | `^\*\*` terminator didn't fire → leaks again                                   | — (this redesign)                              |

The shared property of **all five**: the parser silently produced the wrong
count (0, or +N) and **no one noticed on the run that produced it** — drift #1
and #4 dropped whole sections, discovered 1–3 phases later during triage. The
template already enumerated #1–#3 as explicit prohibitions, and the agent still
produced #4 and #5. **Enumerating known-bad markdown is unbounded.** Every fix
that made the parser _more tolerant_ also gave the next agent more room to
drift. The redesign reverses both: a contract so simple there is little to drift
toward, and a parser so strict that drift fails _loudly_ instead of silently.

## Why a tag block (not a `## heading`, not the prose ruleset)

A markdown heading has no closing delimiter — the parser must _infer_ the
section end "at the next heading-ish line." That inference is the entire
silent-failure surface: it caused #1 (bold pseudo-heading ends the section
early), #3/#5 (runner metadata past the end leaks in), and the
heading-not-recognized half of #4. A **balanced tag has an explicit open and
close**, so extraction is "take what's between the tags" — no heading
recognition, no terminator regex, no leak surface. Three of the five failure
classes vanish _by construction_, not by rule. LLMs also emit balanced tags
near-perfectly because they are saturated with them in training.

This is the one place tags clearly earn their cost: the machine-read region.
The surrounding report (invariant results, surface probes, actionable findings,
rationale) **stays markdown** — it is read by humans and the agent writes it
better as prose. Do not XML-wrap the whole file. Tag the boundary, not the book.

### Why "point the subagent at the parser" is now correct

The earlier objection was that the parser was a _tolerant regex grimoire_, so
"conform to what it parses" meant targeting its loosest accepted form, which
drifts commit-to-commit. **Making the parser barebones dissolves that
objection:** once the parser accepts exactly one form, the parser _is_ the
contract, and pointing the subagent at it is pointing it at two rules (tag
block, `*` bullets). Put the literal tag block in the template as a **copy-me
skeleton** so the agent copies rather than reconstructs.

## Why the zero-parse floor stays, even with tags

Tags lower the drift _rate_; they do not make it zero. The agent can still
forget the close tag, emit zero bullets, or misname the tag
(`<advisory_observations>` with an underscore). Each of those still lands as a
silent 0-parse — and a _stricter_ parser makes silent-0 **more** likely, not
less, because more inputs map to "nothing matched." Failure #4, from the phase
this note was written in, was exactly a silent 0-parse. So the floor is
non-negotiable, and it is cheap:

- **Not a retry loop. Not a second invocation.** One boolean on output the
  orchestrator already holds at record time.
- **Precise enough not to nag:** `0 bullets + literal "None"` → true-clean,
  silent. `0 bullets + content present / tag malformed / tag missing` → warn.
  No false positive on a genuinely clean review.
- **Fired at the moment it can be fixed.** Wire it into `subagent-review`, not
  only `triage-advisory-observations`. Today the advisory parse runs only at
  post-phase triage — 9 tickets later, worktrees gone, the worst place to
  discover drift. At record time the primary agent is running the command
  in-session, worktree alive, report just landed.

The asymmetry that justifies it: **one printed warning line vs. silently
dropping a whole section's review signal for three phases.**

## The closed loop (operational)

```
tagged contract            → low drift rate (explicit boundary, copy-me skeleton)
record-time zero-parse warn → drift is VISIBLE the instant it happens
primary agent resolves      → in-session, two moves below
```

When the warning fires, the **primary agent** resolves it then and there — it
is present and running `subagent-review`:

- **Re-run `subagent-review`** (fresh one-shot runner). Preferred: keeps the
  report subagent-authored.
- **Hand-normalize the framing** (close the tag, fix the tag name, turn a stray
  paragraph into bullets). Acceptable because it changes _structure only_.

**Bright line:** the primary agent fixes _framing_, never _findings_. The
subagent runner remains advisory-only and stdout-only (a file write still
trips `advisory_violation → skipped`); none of this changes that contract.

## Layering (where each rule lives)

- **Output contract (the tag block / copy-me skeleton):** template only, as a
  declarative artifact the agent copies — never as historical narrative. Delete
  the do/don't prose (current `adversarial-review-template.md` ~183–231 and the
  matching block in `subagent-review-report-template.md`).
- **Strictness + loud validation:** `reconciliation.ts` (tag extraction) +
  `cli-runner.ts` / `advisory-observation-command.ts` (record-time warning).
  This is the durable layer; it is the only thing that catches _unanticipated_
  drift.
- **Rule of thumb:** do not encode in template prose anything the parser can
  detect and report itself. Prose is for humans; the machine boundary defends
  itself.

## Rejected alternatives (ironman + verdict)

- **"Point the subagent at the parser" (literal):** single source of truth,
  cannot go stale against itself. Adopted in spirit — _because the parser is now
  barebones_, pointing at it is fine. Rejected only as "read the `.ts` regex";
  supply the frozen tag block instead.
- **Keep the prose ruleset, each rule was a real bug:** correct that the
  _constraints_ must survive — but keep the constraints, drop the
  _explanations_. The tag block + strict parser encode the same constraints in a
  form both the agent and the machine enforce, without unbounded narrative.
- **Validate-and-retry loop (re-invoke the subagent on parse failure):**
  rejected as churn for a one-shot subagent against a trivial contract, and it
  risks the runner _editing findings_ to satisfy the parser. The record-time
  warning + primary-agent resolution covers the same ground without re-invoking.
- **`## heading` fallback alongside the tag:** rejected — it reintroduces the
  exact heading-recognition wobble the tag removes.
- **Drop the floor now that we have tags:** rejected — tags lower the rate, the
  floor catches the residual (missing/misnamed close tag → silent 0), and it
  costs one line.

## Implementation checklist (son-of-anton, one standalone change)

1. `parseAdvisoryObservations` → extract `<advisory-observations>…
</advisory-observations>` (case-insensitive tag name match; tolerate inner
   whitespace/blank lines; on a missing close tag, fall back to EOF and let the
   warning fire). Keep `^\*` bullets; treat lone `None` as clean-empty. Delete
   the heading/`---`/paragraph/alias/runnerStatus machinery.
2. Templates → replace the prose ruleset with the literal copy-me tag block in
   both `adversarial-review-template.md` and
   `subagent-review-report-template.md`.
3. `subagent-review` record path → run the parse + zero-parse check on the
   captured report and print the warning at record time (keep the existing
   triage-time surfacing as the backstop).
4. Regression tests: (a) tagged block with bullets parses correctly; (b)
   `None` → clean-empty, no warning; (c) missing close tag → parses to EOF,
   warns; (d) misnamed tag / `## heading` / plain-text heading → 0 parse +
   warning (proves the floor catches failures #1 and #4); (e) runnerStatus
   prose outside the tag is ignored (proves #3/#5 can no longer leak).
