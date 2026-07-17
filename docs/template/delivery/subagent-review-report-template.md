# Subagent Adversarial Review Report Template

This is the canonical report shape the **review subagent** writes to
`reviews/<ticket>-subagent-review.report.md` after the primary agent invokes
it via the filled `adversarial-review-template.md` prompt.

**Why this template exists.** The report is consumed by a machine
(`tools/delivery/reconciliation.ts`, `tools/delivery/subagent-runner.ts`) but
written as free-form markdown by an LLM. Every phase the LLM found a new way
to format the machine-read sections that the old heading-based grammar did
not accept — see
[`notes/public/subagent-report-parser-contract.md`](../../../notes/public/subagent-report-parser-contract.md)
for the five recorded drift incidents. The fix is a **tagged contract**: the
three machine-read regions are balanced tag blocks the subagent copies
verbatim, extracted with no heading recognition at all. There is no
`## heading` fallback — a missing or malformed tag prints a loud warning at
`subagent-review` record time instead of silently dropping content.

The primary agent does not edit this report. It is the subagent's
deliverable, and it is appended to the ticket worktree as-is.

---

## Required structure

The report contains five regions, in this order. `Invariant results` and
`Surface results` stay free-form markdown prose — they are read by humans.
The other three are **copy-me tag skeletons** — balanced tags the subagent
copies verbatim and fills in between:

1. **Invariant results** (prose)
2. **Surface results** (prose)
3. `<actionable-findings>` … `</actionable-findings>` (tagged)
4. `<advisory-observations>` … `</advisory-observations>` (tagged)
5. `<runner-termination>` … `</runner-termination>` (tagged)

The parser reads **only** what is between each tag's open and close —
nothing outside them. Do not invent new tags. Do not nest a tag inside
another tag's body.

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
nine diff-derived classes — emit one line as `[probed | N/A — <reason> |
blocked — missing-input]`. If probed, one to three sentences on what was
tried and what was found.

- Output stability across schema-version drift: [N/A — reason: no persisted
  shape changes in this diff].
- CLI flag/arg symmetry: [probed]. The new `--strict` flag is parsed,
  validated, and threaded into the downstream consumer; help text updated.
- Error-class breadth in `catch` blocks: [probed]. The catch around the
  network read swallows all `Error` instances, including `EPERM` and
  `ETIMEDOUT`, with no rethrow. See actionable findings.
- Defensive layering at module boundaries: [N/A — reason: no new module
  boundaries crossed].
- Cross-file atomicity windows: [probed]. The state-then-artifact write is
  not wrapped in a recovery path; an interrupt between the two leaves a
  state file pointing at a non-existent artifact.
- Test-contract strength: [probed]. New tests assert the stable code
  identity first, then narrow message content.
- Doc-vs-code drift in the ticket Rationale: [probed]. Rationale claims the
  validation runs unconditionally; the diff makes it conditional on a flag.
  Surfaced under advisory observations.

<actionable-findings>

- `src/net/fetcher.ts:42` — the `catch` block matches all `Error` instances
  and swallows network-class failures (`EPERM`, `ETIMEDOUT`). Breaks
  invariant 2 (failed reads must surface to the caller). Fix: narrow the
  catch to the known-recoverable error classes and rethrow the rest.

</actionable-findings>

<advisory-observations>

- A1: The new `--strict` flag is parsed but not surfaced in the
  `validateRunner` error message when validation fails, so operators who hit
  the gate see a generic error. Outside the three finding-discipline
  clauses; consider improving the message in a follow-up.
- A2: `docs/.../ticket-04.md` Rationale claims the validation runs
  unconditionally, but the diff makes it conditional on `--strict`. Doc-vs-
  code drift surfaced under the diff-derived class; primary agent decides
  whether to patch docs or code.

</advisory-observations>

<runner-termination>
runnerStatus: completed
terminatedReason: review finished against the filled prompt; no premature exit.
</runner-termination>
```

When a tagged region has nothing to report, write the single literal line
`None` (no bullets) between the tags:

```markdown
<actionable-findings>
None
</actionable-findings>
```

---

## Subagent format rules (failure modes the parser catches)

These rules exist because each one corresponds to a real failure mode in
downstream tooling, not just style preference.

- **Copy the tag skeletons verbatim** — `<actionable-findings>`,
  `<advisory-observations>`, `<runner-termination>`, each with its matching
  closing tag. The parser is barebones and strict: it extracts everything
  between an open tag and its close tag, keeps `^-`/`^*` bullet lines, and
  ignores everything else. There is no heading recognition, no `---`
  stripping, no bold-prefix tolerance — the tag boundary is the only signal.

- **Always close the tag.** A missing close tag makes the parser read to
  end-of-file, which is always treated as suspicious (even if the body looks
  like a clean `None`) and prints a warning at `subagent-review` record time.

- **`runnerStatus: completed` is not the same fact as a clean review.**
  `completed` in `<runner-termination>` only means you finished the review
  per this template. Whether the review is clean is decided separately from
  the `<actionable-findings>` block: literal `None` records `outcome: clean`;
  one or more findings records `outcome: completed_with_findings` instead —
  the ledger never records `clean` for a report that lists findings, even
  when the runner terminated normally.

- **Write `None` (no trailing period) on its own line** when a tagged region
  has no entries. `None`/`none.`/`None.` are all recognized case-insensitively,
  but only inside a properly closed tag — a literal `None` before a missing
  close tag is still flagged as suspicious.

- **One observation or finding per bullet.** Each bullet (`-` or `*`) is
  parsed as one item. Do not put more than one finding/observation in a
  single bullet, and do not write prose paragraphs inside the tag — only
  bullet lines are extracted.

- **`runnerStatus` and `terminatedReason` live inside `<runner-termination>`,
  nowhere else.** A bare `runnerStatus:` line outside the tag is invisible to
  the parser and cannot leak into (or terminate) the other two regions.

- **Do not write files in the worktree.** The runner is advisory-only. Any
  worktree modification triggers `outcome: skipped` with
  `terminatedReason: advisory_violation` in the runner ledger.

---

## How the report is consumed downstream

1. **`reconcile-subagent-review`** reads `<actionable-findings>`. If the
   block is non-empty and not the literal `None`, the gate blocks `open-pr`
   unless the primary agent patches with `[subagent-review]` or records a
   `deferred` row via `subagent-review record-deferred`.

2. **`triage-advisory-observations`** (post-phase, after the stacked PR
   chain lands on `main`) reads `<advisory-observations>`. Each observation
   must receive an explicit disposition in the dispositions input file:
   `patched`, `rejected`, `already-covered`, or `requires-human-review`. The
   primary agent patches where prudent during this lane.

3. **The zero-parse loud floor** (`subagent-review` record time, in
   `tools/delivery/cli-runner.ts`) checks all three tagged regions the
   moment the report lands and prints a warning if any is missing,
   malformed (unclosed/misnamed), or empty without the literal `None`. This
   is not a retry loop — the primary agent, still in-session, either
   re-runs `subagent-review` or hand-normalizes the framing (structure only,
   never findings).

Keep the report bullet format consistent with the
`advisory-observation-dispositions-template.json` you fill in later — the
primary agent matches the dispositions input back to observations by
verbatim text.
