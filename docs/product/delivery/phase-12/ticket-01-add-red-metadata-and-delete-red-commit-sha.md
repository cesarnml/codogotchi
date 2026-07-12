# P12.01 Add Red metadata field and delete --red-commit-sha

Size: 3 points
Type: feat
Scope: delivery
Red: required

## Outcome

- `parseTicketMetadata` parses a top-level `Red:` field from the ticket-doc metadata block and returns `redPolicy: 'required' | 'skip'`. Missing field defaults to `'required'`. Unrecognized values (anything other than the two exact lowercase literals) throw with an explicit error naming the two valid values.
- `start` lifts `redPolicy` onto the ticket state record; `state.json` persists it alongside existing ticket fields.
- `runPostRed` skips the gate when `redPolicy === 'skip'` OR `isLocalBranchDocOnly` returns true. The log message identifies which signal(s) triggered the skip.
- The `--red-commit-sha` flag is removed from `tools/delivery/cli.ts` (arg parser, `ParsedCliArgs` field, usage string) and from `tools/delivery/cli-runner.ts` (the bypass branch in `runPostRed` that records against a named SHA without HEAD/CI checks).
- `post-red` failure error text enumerates the two honest paths: "author a `[red]` commit before continuing" and "revise the ticket metadata to `Red: skip` if no testable behavior exists." The existing `[red]`-subject and verify-exit-code checks remain.
- All existing tests that supplied `--red-commit-sha` are updated to use the new honest paths (either authoring a `[red]` commit or declaring `Red: skip` in test fixtures).
- `bun run ci:quiet` is green on the ticket branch.

## Red

- **If `Red: skip` is declared in the metadata block above, omit this entire section.** Not applicable here — this ticket is code with testable behavior.
- Write a single failing parser test in `tools/delivery/test/ticket-flow.test.ts` (or a new test file in the same directory): assert that `parseTicketMetadata` returns `redPolicy: 'skip'` for a ticket-doc string that declares `Red: skip` in its top-level metadata block.
- Run `bun run ci:quiet`. Confirm the new test fails because `parseTicketMetadata` does not yet exist or does not yet expose `redPolicy`.
- Commit with subject `test(P12.01): parse Red metadata field [red]`.
- Do not write any implementation until this commit exists on the branch.

## Green

- Implement `parseTicketMetadata` in `tools/delivery/ticket-flow.ts` (or a new dedicated module if `ticket-flow.ts` grows too large during the implementation). Accept exact lowercase `required` and `skip`; reject everything else with an explicit error.
- Extend `tools/delivery/types.ts` with the new `redPolicy` field on the ticket state record (most likely `redPolicy: 'required' | 'skip'`).
- Wire the parser into the `start` code path so `redPolicy` is computed once per ticket and persisted into `state.json` at the existing state-write point.
- Update `runPostRed` in `tools/delivery/cli-runner.ts`: read `target.redPolicy` from state; if `'skip'`, short-circuit to the existing skip-recording branch (mirror today's doc-only skip path). Combine with `isLocalBranchDocOnly` via OR. Adjust the log message to name whichever signal(s) fired.
- Delete the `--red-commit-sha` flag from `tools/delivery/cli.ts`: remove the parser branch, remove `redCommitSha` from `ParsedCliArgs`, remove the mention from the usage string.
- Delete the bypass branch in `runPostRed` (`if (redCommitSha !== undefined) { ... return recordPostRedImpl(state, { headSha: redCommitSha, ... }); }`) — the entire block at the lines that bypass HEAD-subject and CI checks goes away.
- Update `post-red` failure error text in `tools/delivery/ticket-flow.ts` (`recordPostRedImpl`) and any sibling error sites to enumerate the two honest paths.
- Add tests covering: parser accepts `Red: required` and `Red: skip`; parser defaults missing → `'required'`; parser throws on `Red: invalid`, `Red: Required` (case-sensitivity), `Red: ` (empty); `runPostRed` skips when `redPolicy === 'skip'` without invoking the verify command; `runPostRed` skips when `isLocalBranchDocOnly` returns true regardless of `redPolicy`; `parseCliArgs(['post-red', '--red-commit-sha', 'abc'])` throws "unknown argument" or equivalent; `post-red` error text on missing `[red]` HEAD names both honest paths.
- Update existing tests that pass `--red-commit-sha` to use the new paths.

## Refactor

- If the parser grows large enough to deserve its own module, extract to `tools/delivery/ticket-metadata.ts` with corresponding test file. Otherwise leave in `ticket-flow.ts`.
- Only refactor what you touched — no opportunistic cleanup of unrelated post-red or state code.

## Review Focus

- **Parser strictness.** The accepted values are exactly `required` and `skip`, lowercase. Case variants (`Required`, `Skip`, `SKIP`), values with surrounding whitespace, and any trailing tokens or comments on the same line are all rejected. Error message must name both valid literals so the operator knows what to type.
- **Skip-precedence rule.** The OR semantics is non-negotiable: either `redPolicy === 'skip'` or doc-only triggers the skip. `Red: required` on a doc-only branch still skips. Verify the log message clearly identifies which signal(s) triggered.
- **Bypass deletion completeness.** Run `git grep -n 'red-commit-sha\|redCommitSha' -- tools/delivery/ docs/template/` and confirm the only remaining references are the legitimate `redCommitSha` state field (the recorded SHA of the actual `[red]` commit, set by `recordPostRedImpl`). No CLI-flag-supplied references should remain.
- **Error-text wording.** The two honest paths must be actionable. An operator reading the error should know exactly what to do next without consulting the docs.
- **Doc-only edge case.** `Red: required` ticket whose branch is doc-only still skips the gate via `isLocalBranchDocOnly`. Tested explicitly.
- **Strict-reject test surface.** The parser's failure paths (invalid value, wrong casing, empty value) must each have a test.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `parseRedPolicy` unit test (`tools/delivery/test/ticket-metadata.test.ts`) asserting `Red: skip` parses to `'skip'`. Failed because `tools/delivery/ticket-metadata.ts` did not exist. Committed as `113de218`.

Why this path: The parser lives in a dedicated `ticket-metadata.ts` module (rather than inline in `planning.ts` next to `parseTicketType`/`parseTicketScope`) because the strict-throw semantics differ from those lenient parsers. A dedicated module isolates the strict-validation contract and gives it focused tests. `planning.ts` provides a thin `parseTicketRedPolicy` wrapper that handles FS-read failure by returning `'required'` (matches the lenient pattern of its siblings — graceful when ticket files are missing during plan parsing).

Alternative considered: parsing `Red:` at `start`-time inside `ticket-flow.ts` and writing the value directly to `state.json`. Rejected because the existing precedent (Type/Scope lifted by `planning.ts` into `TicketDefinition`) is cleaner — let plan-read populate the definition, then `state.ts` lifts it onto the saved ticket state alongside type/scope. State.json gains `redPolicy` automatically on first save.

Deferred: comprehensive backward-compat for state.json files predating phase-12 (`state.ts` falls back to `definition.redPolicy` when `previous?.redPolicy` is absent — that's sufficient for current consumers since `/soa update` policy requires closing the current phase first).

Skip-precedence implementation: the OR semantics is `redPolicy === 'skip' || isLocalBranchDocOnly`. Both reasons are accumulated into the log message so the operator knows which signal(s) fired (`post-red skipped (Red: skip)`, `post-red skipped (doc-only branch)`, or `post-red skipped (Red: skip, doc-only branch)`).

Bypass deletion completeness verified via `git grep 'red-commit-sha\|redCommitSha'` after the change: all remaining hits are the legitimate `redCommitSha` state field (recorded when post-red passes against a real `[red]` HEAD) plus the rejection error message in `cli.ts`. No CLI-flag-supplied references remain.

Test surface: `ticket-metadata.test.ts` covers parser accept/default/throw/case/empty/extra-tokens paths. `p7-03.test.ts` replaces the `--red-commit-sha flag` describe block with a `--red-commit-sha removed` block that asserts the error names both honest paths. `p9-02.test.ts` replaces the bypass test with a `Red: skip` skip-honoring test. `orchestrator.test.ts` updated to include `redPolicy: 'required'` in expected `parsePlan` output.

Contract note: no deviation from the ticket metadata contract. `Type: feat`, `Scope: delivery`, `Red: required` all matched and were honored. The ticket itself committed `[red]` and `[green]` in sequence and ran `post-red` successfully — eating-own-dogfood through the existing gate (phase-12's reordering is a docs change in T2; the code change lands here).
