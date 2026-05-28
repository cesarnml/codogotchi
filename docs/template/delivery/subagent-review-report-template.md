# Subagent Adversarial Review Report Template

This is the canonical report shape the **review subagent** writes to
`reviews/<ticket>-subagent-review.report.md` after the primary agent invokes
it via the filled `adversarial-review-template.md` prompt.

**Why this template exists.** Without a canonical shape, subagents drift on
section headings and prose formatting in ways that silently break downstream
tooling — most importantly, the parser that extracts the `Advisory
Observations` section for post-phase triage (`reconciliation.ts`,
`parseAdvisoryObservations`). Section headings that look creative but are not
on the canonical list (e.g. `**A1 — Title**` as an observation prefix instead
of a bullet) used to truncate the section body and silently drop every
observation that followed. This template removes that drift surface.

The primary agent does not edit this report. It is the subagent's
deliverable, and it is appended to the ticket worktree as-is.

---

## Required structure

The report **must** contain exactly these five top-level sections, in this
order, each formatted as a Markdown bold span on its own line (`**Section
Name**`) — or as an `## ATX heading` (also accepted). Do not invent new
top-level sections. Do not nest section headings as bold spans inside another
section's body.

1. **Invariant results**
2. **Surface results**
3. **Actionable findings**
4. **Advisory Observations**
5. **Runner termination**

Anything outside these five sections is ignored by tooling. Keep prose
inside them.

---

## Canonical body

```markdown
**Invariant results**

For each invariant from the prompt: `[held | broken | untested]` — one short
line per invariant explaining what was tried.

1. [held] Implementation calls X exactly when Y, and tests cover both Y=true and Y=false.
2. [broken] Implementation skips the validation step on the empty-string path.
3. [untested] No test exercises the cross-process race window.

**Surface results**

For every attack surface from the prompt — both ticket-spec-derived and the
seven diff-derived classes — emit one line as `[probed | N/A — <reason> |
blocked — missing-input]`. If probed, one to three sentences on what was
tried and what was found.

- Output stability across schema-version drift: [N/A — reason: no persisted
  shape changes in this diff].
- CLI flag/arg symmetry: [probed]. The new `--strict` flag is parsed,
  validated, and threaded into the downstream consumer; help text updated.
- Error-class breadth in `catch` blocks: [probed]. The catch around the
  network read swallows all `Error` instances, including `EPERM` and
  `ETIMEDOUT`, with no rethrow. See Actionable findings.
- Defensive layering at module boundaries: [N/A — reason: no new module
  boundaries crossed].
- Cross-file atomicity windows: [probed]. The state-then-artifact write is
  not wrapped in a recovery path; an interrupt between the two leaves a
  state file pointing at a non-existent artifact.
- Test-contract strength: [probed]. New tests assert the stable code
  identity first, then narrow message content.
- Doc-vs-code drift in the ticket Rationale: [probed]. Rationale claims the
  validation runs unconditionally; the diff makes it conditional on a flag.
  Surfaced under Advisory Observations.

**Actionable findings**

For each finding the primary agent should consider patching, emit a single
paragraph (or a single bullet) containing: file/path, what is wrong, which
invariant or finding-discipline clause applies, and a concrete fix
recommendation. If none, write `None.` on its own line.

- `src/net/fetcher.ts:42` — the `catch` block matches all `Error` instances
  and swallows network-class failures (`EPERM`, `ETIMEDOUT`). Breaks
  invariant 2 (failed reads must surface to the caller). Fix: narrow the
  catch to the known-recoverable error classes and rethrow the rest.

**Advisory Observations**

**One observation per bullet or one observation per paragraph.** Do not use
bold-prefix headers (`**A1 — Title**`) as a separate line before the
observation body — keep the observation prose self-contained in a single
bullet or paragraph so downstream triage tooling extracts each observation
intact. If you want to label observations, write the label inline at the
start of the bullet/paragraph, not on its own line.

If none, write `None.` on its own line.

- A1: The new `--strict` flag is parsed but not surfaced in the
  `validateRunner` error message when validation fails, so operators who hit
  the gate see a generic error. Outside the three finding-discipline
  clauses; consider improving the message in a follow-up.
- A2: `docs/.../ticket-04.md` Rationale claims the validation runs
  unconditionally, but the diff makes it conditional on `--strict`. Doc-vs-
  code drift surfaced under the diff-derived class; primary agent decides
  whether to patch docs or code.

**Runner termination**

`runnerStatus`: one of `completed | rate_limit | sandbox_denied | runner_unavailable`.
`terminatedReason`: one short sentence explaining why this status was reported.

runnerStatus: completed
terminatedReason: review finished against the filled prompt; no premature exit.
```

---

## Subagent format rules (failure modes the parser catches)

These rules exist because each one corresponds to a real failure mode in
downstream tooling, not just style preference.

- **Use the canonical section headings verbatim** (`Actionable findings`,
  `Advisory Observations`, `Runner termination`). Variants like `Findings
for human review` are tolerated as legacy aliases, but the canonical names
  are preferred. New section names are silently ignored by the parser.

- **Do not place bold spans (`**...**`) on a line by themselves inside a
  section body.** Bold prefixes on standalone lines look like section
  headings to a naive reader and used to be treated as section terminators.
  The parser now only terminates on canonical sibling headings, but the
  visual structure still confuses humans.

- **One observation = one bullet or one paragraph.** The Advisory
  Observations parser splits the section body either by bullet (`- ` /
  `* `) when the section is entirely bullets, or by blank-line-separated
  paragraph otherwise. A bold header line followed by a paragraph body is
  parsed as two separate observations, not one labeled observation.

- **Write `None.` on its own line** when a section has no entries. The
  parser recognises `None.` (case-insensitive) and treats the section as
  empty.

- **Do not write files in the worktree.** The runner is advisory-only. Any
  worktree modification triggers `outcome: skipped` with
  `terminatedReason: advisory_violation` in the runner ledger.

---

## How the report is consumed downstream

1. **`reconcile-subagent-review`** reads `Actionable findings`. If the
   section is non-empty and not `None.`, the gate blocks `open-pr` unless
   the primary agent patches with `[subagent-review]` or records a
   `deferred` row via `subagent-review record-deferred`.

2. **`triage-advisory-observations`** (post-phase, after the stacked PR
   chain lands on `main`) reads `Advisory Observations`. Each observation
   must receive an explicit disposition in the dispositions input file:
   `patched`, `rejected`, `already-covered`, or `requires-human-review`. The
   primary agent patches where prudent during this lane.

Keep the report bullet/paragraph format consistent with the
`advisory-observation-dispositions-template.json` you fill in later — the
primary agent matches the dispositions input back to observations by
verbatim text.
