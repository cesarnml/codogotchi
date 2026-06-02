# Phase 09 — Extended platform hooks retrospective

Source plan: [`docs/product/plans/phase-09-extended-platform-hooks.md`](../plans/phase-09-extended-platform-hooks.md).
Delivery plan: [`docs/product/delivery/phase-09/implementation-plan.md`](../delivery/phase-09/implementation-plan.md).

## Scope delivered

Tickets P9.01 → P9.04 (4/4) landed, opening PRs
[#91](https://github.com/cesarnml/codogotchi/pull/91) through
[#94](https://github.com/cesarnml/codogotchi/pull/94). Delivered:

- Schema extension: `vscode` and `antigravity` added to `sourceEventOriginSchema`;
  `PlatformAttribution` extended with `.vscode` and `.antigravity` cases, display names,
  and asset-catalog imagesets for the GitHub Copilot and Antigravity SVGs (P9.01);
- VS Code / GitHub Copilot native hooks end-to-end: installer writing
  `~/.copilot/hooks/codogotchi.json`, event adapter for the seven Copilot lifecycle events,
  tool-name alias map (bash→Bash, view→Read, task→Grep, etc.), `CODOGOTCHI_ORIGIN=vscode` env
  injection, and `hooksStatus` reporting `vscode` platform (P9.02);
- Antigravity native hooks end-to-end: installer writing `~/.gemini/config/hooks.json`
  under the `codogotchi` named-hook key, event adapter for `PreToolUse` / `PostToolUse` / `Stop`,
  tool-name alias map, `CODOGOTCHI_ORIGIN=antigravity` env injection, `fullyIdle` terminal signal,
  and dropped stepIdx Pre/Post correlation (P9.03);
- Platform parity matrix, updated README and install runbook, and this retrospective (P9.04).

## Build-from-docs + empirical-validation playbook

Both Copilot and Antigravity publish their hook schemas in public documentation with example payloads.
The approach taken: build the adapter from docs first, write doc-derived fixture tests that capture
the published payload shapes, land with CI green, and patch any schema drift after real-usage
validation. This replaced the previous "no code before fixtures" gate with a "fixtures first, real
captures second" model.

The playbook in practice:

1. **Read the published hook schema.** Extract event names, payload fields, and example payloads.
   Record any ambiguity (e.g. does `postToolUse` carry a tool name or only stepIdx?) as an explicit
   decision in the ticket rationale.
2. **Write fixture tests from the published examples.** These tests run without network and give CI
   a baseline. They do not prove the live integration is correct; they prove the adapter handles the
   documented shape correctly.
3. **Land and validate empirically.** Real agent sessions may surface payload drift (fields present
   in docs but not sent, or fields sent but not documented). Capture the drift, update the adapter
   and fixtures, and re-land.
4. **Record support level honestly.** `documented` means fixtures pass; `verified` means real-usage
   captures confirm the adapter. Do not upgrade to `verified` without live validation.

## Antigravity is structurally different

The most important lesson from Phase 09: Antigravity is not "the same adapter pattern as Copilot."
Three structural departures required explicit design decisions:

**No prompt-submit event.** Copilot has `userPromptSubmitted`; Claude Code has `UserPromptSubmit`;
Codex has `UserPromptSubmit`; Cursor has `beforeSubmitPrompt`. Antigravity has none. The first
observable edge is `PreToolUse`. The pet does not transition to `thinking` at the start of an
Antigravity turn — it transitions when the first tool fires.

**`fullyIdle` semantics on `Stop`.** For every other platform, `Stop` (or `agentStop`) means the
agent finished its turn: map to `standby`. For Antigravity, `Stop { fullyIdle: false }` means
background tasks are still running — it is not a clean-finish signal. The correct mapping is
`thinking`. Only `Stop { fullyIdle: true }` maps to `standby`. Ignoring this distinction would have
left the pet stuck in `standby` while Antigravity was still active.

**PostToolUse carries no tool name.** Copilot, Codex, and Claude Code all carry a tool name (or
a field that identifies the tool) on their PostToolUse equivalent. Antigravity `PostToolUse` carries
only `stepIdx` and an optional `error` field — no tool name, no correlation to the preceding
`PreToolUse`. The decision: `PreToolUse` does all tool classification; `PostToolUse` resolves to
`thinking` (or `errored` when `error` is non-empty). The stepIdx Pre/Post correlation machinery was
designed and then dropped as unnecessary complexity.

## Copilot dual-dialect normalization

GitHub Copilot's hook payload uses camelCase field names (`toolName`, `toolArgs`) rather than
Claude Code's snake_case (`tool_name`, `tool_input`). The hook binary already handled multiple
dialects; adding Copilot required:

1. Reading `toolName` and `toolArgs.command` alongside `tool_name` and `tool_input.command`.
2. Mapping Copilot's tool names to internal names: `bash`→`Bash`, `create`/`edit`→`Edit`,
   `view`→`Read`, `grep`→`Grep`, `glob`→`Glob`, `web_fetch`→`WebFetch`, `task`→`Grep`.
3. Normalizing the prompt-submit event name: `userPromptSubmitted` (Copilot's `-ted` suffix variant)
   alongside `userPromptSubmit`, `beforeSubmitPrompt`, and the existing set.

The `PROMPT_SUBMIT_TOKENS` set in `hook-binary.ts` now covers all four dialects. The alias map in
`resolveCopilotToolAlias` is the single authoritative translation table.

## Origin detection and env-var disambiguation

The `rawHookOrigin` function already used a heuristic (PascalCase → claude\_code, snake\_case →
codex, camelCase/lowercase → cursor). Both Codex and Antigravity use PascalCase event names, which
would misidentify them as `claude_code` without an explicit signal. The fix was established in
Phase 06 for Codex (`CODOGOTCHI_ORIGIN=codex` env var injected by the installer). Phase 09 extends
this pattern: the Copilot and Antigravity installers inject `CODOGOTCHI_ORIGIN=vscode` and
`CODOGOTCHI_ORIGIN=antigravity` respectively. The heuristic remains as a fallback for hook payloads
that carry an explicit origin field.

## What went well

- **Parallel platform delivery in one phase held.** Both adapters landed cleanly because the
  foundation (P9.01 enum + badges) was atomic: all downstream tickets could assume the five-origin
  schema and the new imagesets without waiting on each other.
- **Dropping stepIdx correlation before shipping.** The decision to not build Pre/Post correlation
  for Antigravity was made early and held. A working `thinking`-on-PostToolUse result is correct
  and simple; a broken correlation would have been wrong and complicated.
- **Installer idempotency extended cleanly.** The existing `withCopilotCodogotchiEntries` / named-hook
  patterns kept the installer correct under re-run without special-casing. `hooks install --platform
  vscode` and `--platform antigravity` both deduplicate correctly.
- **SVG template rendering.** The two new imagesets use the same `Contents.json` shape as
  `PlatformCursor.imageset` — `template-rendering-intent` set, single universal scale. The logos tint
  with the badge text color without extra configuration.

## Pain points

- **No real-usage validation before closeout.** Both `vscode` and `antigravity` ship at support level
  `documented`. The adapter is built from published schemas and passes doc-derived fixture tests, but
  live event captures have not confirmed the implementation. Schema drift is a known risk — the
  published payload shapes may not match what the runtime actually sends.
- **Antigravity hook structure is nested (named-hook map), Copilot is flat array.** The two installer
  shapes required separate code paths with no shared abstraction. This is acceptable at four
  platforms; it will need a factory or strategy pattern if the platform count grows significantly.
- **`fullyIdle` semantics required a platform-specific branch in `classifyEvent`.** The Antigravity
  `Stop` branch is the first case where the same event name on different platforms requires completely
  different logic. This is contained, but it is a pattern to watch.

## Surprises

- **`task` in Copilot's tool list is a planning/think tool, not a shell command.** The initial
  assumption was that Copilot's `task` tool would map to `Bash`/`Shell`. Reading the docs revealed
  it is a planning-step tool — mapping to `Grep` (thinking) is more accurate. This was the one
  non-obvious alias decision and is called out in the hook binary.
- **Antigravity's `permissionRequest` event was not in the initial schema read.** It is not listed in
  the published Phase 09 draft. The adapter normalizes `permissionRequest` via the existing
  `isPermissionRequestEvent` path, which handles all PascalCase variants. No special-casing needed,
  but it was not planned explicitly.

## What we'd do differently

- **Schedule a real-usage validation session for both platforms immediately after landing T02 and T03.**
  Even a 15-minute session with a real Copilot or Antigravity agent session would catch payload drift
  before the retrospective. "Ship and see" is fine; "ship and forget" leaves `documented` platforms
  permanently at risk.
- **Write the payload shape expectation as a fixture comment, not just as a test.** The `describe`
  blocks in the adapter tests identify the event, but a single-line comment explaining *where* the
  expected shape came from (e.g. "from Copilot hooks schema v1, published 2025-12") would make
  future drift easier to diagnose.
- **Extract the tool-alias maps into a shared data file.** `resolveCopilotToolAlias` and
  `resolveAntigravityToolAlias` are switch statements in `hook-binary.ts`. Moving them to
  `PLATFORM_TOOL_ALIASES` maps would make the translation table visible to tests without importing
  implementation details and would scale more cleanly when the next platform is added.

## Post-phase advisory triage and a reconciliation-gate gap

After the stack landed on `main`, `/soa tao phase-09` triaged the 12 advisory
observations from the P9.01–P9.03 subagent reviews: 6 patched (test-coverage
strengthening plus the hook stdout-contract doc fix), 3 rejected, 3
already-covered, 0 left for human review. See
[`advisory-observation-triage.json`](../delivery/phase-09/advisory-observation-triage.json).

The triage surfaced a process gap worth recording. The P9.03 subagent report
listed **three actionable findings**, but only one fix commit existed for the
ticket (the `toolCall.name` Pre/Post scoping fix). The other two had cleared the
`reconcile-subagent-review` gate without a patch *or* a recorded `deferred` row:

- **Finding #1 (hook emits no stdout)** turned out to be a *misclassified*
  finding — Codogotchi is observe-only by design and correctly emits nothing;
  the ticket-03 Outcome line was wrong, not the code. Resolved as a doc fix.
- **Finding #3 (in-place config write race)** was a *real* latent robustness
  bug: `writeText` did `mkdir` + `writeFile` straight onto the live hooks file,
  so a crash mid-write could truncate a user's `~/.gemini` / `~/.copilot` /
  `~/.cursor` / `~/.claude` hooks file. Recoverable via the `backupIfExists`
  snapshot, and pre-existing across all installers (not P9-introduced), but it
  should not have passed the gate silently. Fixed post-phase with an atomic
  temp-file + `rename` write (shared `writeText`, so all installers hardened at
  once), plus a no-temp-litter test.

The lesson is about the **gate**, not the fix: an actionable finding reached
`open-pr` with neither a qualifying patch commit nor a `deferred` ledger row,
and the ledger's `findings: []` array did not reflect the report's three
actionable entries. Reconciliation's Condition B (report lists actionable
findings but no patch/deferral) should have blocked or forced an explicit
disposition. Whether the gate's report-parsing missed the findings or an ack
slipped through is worth a second look before the next phase relies on it.

## Net assessment

Phase 09 achieves its product goal: a developer can install native hooks for VS Code (Copilot) and
Antigravity and see the menubar pet animate with correct `source_origin` attribution and the correct
platform logo for all five origins. The installer is idempotent across five platforms. The parity
matrix records the as-shipped config paths, event sets, and tool-name mappings for future reference.
The adapter architecture is platform-specific where the platforms differ (Antigravity `fullyIdle`,
Copilot camelCase aliases) and shared where they converge (origin env-var injection, hooksStatus
pattern). The main gap is real-usage validation: both new platforms are `documented`, not `verified`.
Patch any schema drift when it surfaces; the fixture tests will catch regressions in the known shape.

## Follow-up

- Schedule live validation of the Copilot adapter with a real VS Code + Copilot session; upgrade
  support level from `documented` to `verified` when confirmed.
- Schedule live validation of the Antigravity adapter with a real Antigravity session; confirm
  `fullyIdle` semantics, `PreToolUse` tool-name capture, and `PostToolUse` no-name behavior.
- Extract `resolveCopilotToolAlias` and `resolveAntigravityToolAlias` to shareable maps if a third
  custom-alias platform is added.
- Phase 10+: RPG and XP/sync ingestion for the two new platforms (separate epic, not a prerequisite
  for Phase 09 exit).
- OpenCode: revisit when a stable external plugin API is published.
- **Audit the `reconcile-subagent-review` gate** against the P9.03 case: an
  actionable finding (in-place write race) reached `open-pr` with no patch and
  no `deferred` row, and the ledger `findings` array was empty despite three
  actionable entries in the report. Confirm whether report-parsing or an ack
  path let it through, and tighten Condition B so a real finding cannot clear
  the gate without an explicit disposition.

_Created: 2026-06-02. Phase 09 tickets P9.01–P9.04 delivered; PRs #91–#94._
_Addendum 2026-06-02: post-phase `/soa tao` triage (6 patched, 3 rejected,
3 already-covered) plus atomic-write fix for P9.03 finding #3._
