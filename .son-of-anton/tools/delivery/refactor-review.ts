/**
 * P20.01 — Refactor-review parsing, ledger shape, and reconciliation.
 *
 * Analogous to the adversarial gate's `reconciliation.ts`, but scoped to the
 * Refactor leg of TDD (duplication, naming, dead code, complexity,
 * test-name/behavior alignment) instead of correctness/attack-surface
 * hunting. This module is intentionally independent from
 * `reconciliation.ts` — it does not import or modify
 * `parseAdvisoryObservations`, `extractReportSection`,
 * `CANONICAL_REPORT_SECTION_HEADINGS`, or `parseActionableFindings`. The two
 * gates' parsing logic stay fully separate per the design stance in
 * `notes/public/refactor-advisory-subagent-design.md`.
 *
 * The `<refactor-suggestions>` tag contract follows
 * `notes/public/subagent-report-parser-contract.md`: a balanced tag block
 * the subagent copies verbatim, extracted with no heading-recognition
 * machinery.
 *
 * P20.02 — CLI-facing helpers (prompt path derivation, prompt validity, and
 * ticket-state recording) live here too, reusing the generic runner core in
 * `subagent-runner.ts` (spawn/fallback/ledger primitives) rather than
 * duplicating it. These helpers do not transition `TicketState.status` — gate
 * placement into the main ticket-status machine is ticket 20.03's job.
 */

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

import type { DeliveryState, InternalReviewPatchCommit } from './types';
import type { SubagentRunnerOutcome } from './subagent-runner';
import type { RefactorReviewValue } from './config';
import type { RedPolicy } from './ticket-metadata';

const REFACTOR_REVIEW_SUBJECT_PATTERN = /\[refactor-review\]/i;

const OPEN_TAG = /<refactor-suggestions>/i;
const CLOSE_TAG = /<\/refactor-suggestions>/i;

export type RefactorSuggestionDecisionValue =
  | 'accepted'
  | 'rejected'
  | 'deferred';

export type RefactorSuggestionDecision = {
  id: string;
  summary: string;
  decision: RefactorSuggestionDecisionValue;
  reason?: string;
};

/**
 * Throws when a suggestion decision is structurally invalid: `reason` is
 * required (non-blank) for `rejected` and `deferred` decisions so the ledger
 * always carries an audit-visible rationale for suggestions the primary
 * agent did not accept.
 */
const VALID_DECISION_VALUES: readonly RefactorSuggestionDecisionValue[] = [
  'accepted',
  'rejected',
  'deferred',
];

const SUGGESTION_ID_PATTERN = /^R[1-9]\d*$/;

export function validateRefactorSuggestionDecision(
  row: RefactorSuggestionDecision,
): void {
  if (!row.id || !SUGGESTION_ID_PATTERN.test(row.id)) {
    throw new Error(
      `Refactor suggestion decision id "${String(row.id)}" is invalid. Expected the form "R1", "R2", ...`,
    );
  }
  if (!row.summary || row.summary.trim() === '') {
    throw new Error(
      `Refactor suggestion decision ${row.id} requires a non-blank summary.`,
    );
  }
  if (!VALID_DECISION_VALUES.includes(row.decision)) {
    throw new Error(
      `Refactor suggestion decision ${row.id} has invalid decision "${String(row.decision)}". Expected one of: ${VALID_DECISION_VALUES.join(', ')}`,
    );
  }
  if (
    (row.decision === 'rejected' || row.decision === 'deferred') &&
    (!row.reason || row.reason.trim() === '')
  ) {
    throw new Error(
      `Refactor suggestion decision ${row.id} is "${row.decision}" and requires a non-blank reason.`,
    );
  }
}

export type RefactorSuggestionsParseResult = {
  /** Whether an opening `<refactor-suggestions>` tag was found at all. */
  found: boolean;
  /** Whether a matching closing tag was found (false = parsed to EOF). */
  closed: boolean;
  /** True only for the literal `None` body — a clean report, not a drift warning. */
  isExplicitNone: boolean;
  /** Parsed bullet lines, trimmed and de-prefixed. Empty when none found. */
  suggestions: string[];
};

/**
 * Extracts the `<refactor-suggestions>` tagged block from a refactor-review
 * report. Barebones and strict by design: no heading recognition, no
 * terminator regex — the tag boundary is the only signal.
 *
 * When more than one `<refactor-suggestions>` open tag appears (e.g. a
 * template skeleton example quoted earlier in the report), the **last**
 * occurrence is treated as authoritative — a report's real output section
 * follows any quoted example, not the other way around.
 *
 * - Tagged block with bullets: `found=true, closed=true, suggestions=[...]`.
 * - Literal `None` body (only when the tag is properly closed): `closed=true,
 *   isExplicitNone=true, suggestions=[]` — clean, not a drift warning.
 * - Missing close tag: `closed=false`, parses everything after the open tag
 *   to end-of-file. Always treated as suspicious regardless of body content —
 *   the parser contract requires a balanced block before a `None` body can be
 *   trusted as an honest clean signal.
 * - Empty body (no content at all) is distinct from the literal `None` and is
 *   never `isExplicitNone` — a genuinely clean report must say so explicitly.
 * - Tag missing or misnamed entirely: `found=false, suggestions=[]` — a
 *   0-parse the caller should treat as suspicious, distinct from a genuine
 *   clean `None` report.
 */
export function parseRefactorSuggestions(
  markdown: string,
): RefactorSuggestionsParseResult {
  const openMatches = [...markdown.matchAll(new RegExp(OPEN_TAG, 'gi'))];
  if (openMatches.length === 0) {
    return {
      found: false,
      closed: false,
      isExplicitNone: false,
      suggestions: [],
    };
  }
  const openMatch = openMatches[openMatches.length - 1]!;

  const afterOpen = markdown.slice(
    (openMatch.index ?? 0) + openMatch[0].length,
  );
  const closeMatch = CLOSE_TAG.exec(afterOpen);
  const closed = closeMatch !== null;
  const body = closed ? afterOpen.slice(0, closeMatch.index) : afterOpen;

  const normalized = body
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join('\n')
    .trim();

  if (closed && /^none\.?$/i.test(normalized)) {
    return { found: true, closed, isExplicitNone: true, suggestions: [] };
  }

  if (normalized === '') {
    return { found: true, closed, isExplicitNone: false, suggestions: [] };
  }

  const bulletLines = normalized
    .split('\n')
    .filter((line) => /^[-*]\s+/.test(line));

  return {
    found: true,
    closed,
    isExplicitNone: false,
    suggestions: bulletLines.map((line) => line.replace(/^[-*]\s+/, '').trim()),
  };
}

/**
 * True when the parse result should be treated as a silent-drift warning at
 * record time: the tag was missing/misnamed, the closing tag was absent, or
 * the tag was present but yielded zero bullets without the literal `None`
 * clean-signal.
 */
export function isSuspiciousRefactorSuggestionsParse(
  result: RefactorSuggestionsParseResult,
): boolean {
  if (!result.found || !result.closed) return true;
  return result.suggestions.length === 0 && !result.isExplicitNone;
}

export function detectRefactorReviewLabeledCommits(input: {
  reviewedHeadSha: string;
  headSha: string;
  reviewedPaths: string[];
  listCommitSubjects: (
    from: string,
    to: string,
  ) => { sha: string; subject: string }[];
  listCommitFiles: (sha: string) => string[];
}): string[] {
  if (input.reviewedHeadSha === input.headSha) return [];
  const commits = input.listCommitSubjects(
    input.reviewedHeadSha,
    input.headSha,
  );
  const reviewedSet = new Set(input.reviewedPaths);
  const result: string[] = [];
  for (const { sha, subject } of commits) {
    if (!REFACTOR_REVIEW_SUBJECT_PATTERN.test(subject)) continue;
    const files = input.listCommitFiles(sha);
    if (files.some((f) => reviewedSet.has(f))) {
      result.push(sha);
    }
  }
  return result;
}

export const REFACTOR_RECONCILIATION_BLOCKED_MESSAGE_A =
  'reconcile-subagent-refactor-review: Condition A — files in the reviewed ' +
  'paths were modified since the refactor-review row but no ' +
  '`[refactor-review]`-labeled commit touches them, and no `deferred` row ' +
  'exists. Resolve via:\n' +
  '  1. amend the patch commit subject to include `[refactor-review]`, or\n' +
  '  2. `bun run deliver subagent-refactor-review record-deferred --reason "<rationale>"`.';

export const REFACTOR_RECONCILIATION_BLOCKED_MESSAGE_B =
  'reconcile-subagent-refactor-review: Condition B — the refactor-review ' +
  'report lists suggestions but no commit modified the reviewed paths and ' +
  'no `deferred` row exists. Resolve via:\n' +
  '  1. apply the prudent refactor and commit with `[refactor-review]` in ' +
  'the subject, or\n' +
  '  2. `bun run deliver subagent-refactor-review record-deferred --reason "<rationale>"`.';

export class RefactorReconciliationBlockedError extends Error {
  readonly condition: 'A' | 'B';
  constructor(condition: 'A' | 'B', message: string) {
    super(message);
    this.condition = condition;
    this.name = 'RefactorReconciliationBlockedError';
  }
}

type RefactorArtifactRow = {
  outcome: string;
  reviewedHeadSha?: string;
};

export function reconcileRefactorReview(input: {
  artifactRows: RefactorArtifactRow[];
  reportMarkdown: string;
  reviewedHeadSha: string;
  headSha: string;
  reviewedPaths: string[];
  listCommitSubjects: (
    from: string,
    to: string,
  ) => { sha: string; subject: string }[];
  listCommitFiles: (sha: string) => string[];
  listChangedPathsInRange: (from: string, to: string) => string[];
}):
  | { kind: 'clean' }
  | { kind: 'patched'; commitShas: string[] }
  | { kind: 'blocked'; condition: 'A' | 'B'; message: string } {
  const hasDeferredRowForSha = input.artifactRows.some(
    (row) =>
      row.outcome === 'deferred' &&
      row.reviewedHeadSha === input.reviewedHeadSha,
  );

  const labeledShas = detectRefactorReviewLabeledCommits({
    reviewedHeadSha: input.reviewedHeadSha,
    headSha: input.headSha,
    reviewedPaths: input.reviewedPaths,
    listCommitSubjects: input.listCommitSubjects,
    listCommitFiles: input.listCommitFiles,
  });

  const changedInRange =
    input.reviewedHeadSha === input.headSha
      ? []
      : input.listChangedPathsInRange(input.reviewedHeadSha, input.headSha);
  const reviewedSet = new Set(input.reviewedPaths);
  const reviewedPathsChanged = changedInRange.filter((p) => reviewedSet.has(p));

  if (reviewedPathsChanged.length > 0 && !hasDeferredRowForSha) {
    // Every changed reviewed path must be covered by a labeled commit —
    // one qualifying commit does not vouch for reviewed-path changes made
    // by a *different*, unlabeled commit in the same range.
    const coveredPaths = new Set<string>();
    for (const sha of labeledShas) {
      for (const f of input.listCommitFiles(sha)) coveredPaths.add(f);
    }
    const uncoveredReviewedPaths = reviewedPathsChanged.filter(
      (p) => !coveredPaths.has(p),
    );
    if (uncoveredReviewedPaths.length > 0) {
      return {
        kind: 'blocked',
        condition: 'A',
        message: REFACTOR_RECONCILIATION_BLOCKED_MESSAGE_A,
      };
    }
  }

  if (labeledShas.length > 0) {
    return { kind: 'patched', commitShas: labeledShas };
  }

  const parsed = parseRefactorSuggestions(input.reportMarkdown);
  const suggestionsExist = parsed.suggestions.length > 0;
  if (suggestionsExist && !hasDeferredRowForSha) {
    return {
      kind: 'blocked',
      condition: 'B',
      message: REFACTOR_RECONCILIATION_BLOCKED_MESSAGE_B,
    };
  }

  return { kind: 'clean' };
}

export const REFACTOR_REVIEW_PROMPT_SUFFIX = '-refactor-review.prompt.md';
export const REFACTOR_REVIEW_OUTCOME_SUFFIX = '-refactor-review.report.md';
export const REFACTOR_REVIEW_TRACE_SUFFIX = '-refactor-review.trace.log';
export const REFACTOR_REVIEW_LEDGER_SUFFIX = '-refactor-review.ledger.json';

export function deriveRefactorReviewPromptPath(
  reviewsDirPath: string,
  ticketId: string,
): string {
  return `${reviewsDirPath}/${ticketId}${REFACTOR_REVIEW_PROMPT_SUFFIX}`;
}

export function deriveRefactorReviewOutcomePath(
  reviewsDirPath: string,
  ticketId: string,
): string {
  return `${reviewsDirPath}/${ticketId}${REFACTOR_REVIEW_OUTCOME_SUFFIX}`;
}

export function deriveRefactorReviewTracePath(
  reviewsDirPath: string,
  ticketId: string,
): string {
  return `${reviewsDirPath}/${ticketId}${REFACTOR_REVIEW_TRACE_SUFFIX}`;
}

export function deriveRefactorReviewLedgerPath(
  reviewsDirPath: string,
  ticketId: string,
): string {
  return `${reviewsDirPath}/${ticketId}${REFACTOR_REVIEW_LEDGER_SUFFIX}`;
}

/**
 * Reject stub/placeholder prompt content, same discipline as the adversarial
 * gate's `isValidSubagentAdversarialPromptContent` — a one-line prompt or an
 * uncustomized template skeleton must not silently pass as a real brief.
 */
export function isValidRefactorReviewPromptContent(content: string): boolean {
  if (typeof content !== 'string') return false;
  const trimmed = content.trim();
  if (trimmed.length === 0) return false;
  if (trimmed.length < 80) return false;
  if (/<paste\b|<list each|<file\/function/i.test(content)) return false;
  return true;
}

export type RefactorReviewPromptWriteResult = {
  absolutePath: string;
  relativePath: string;
  writtenAt: string;
};

export function writeRefactorReviewPrompt(input: {
  repoRoot: string;
  reviewsDirPath: string;
  ticketId: string;
  content: string;
  now?: () => string;
}): RefactorReviewPromptWriteResult {
  if (!isValidRefactorReviewPromptContent(input.content)) {
    throw new Error(
      `Refusing to write empty or placeholder-like refactor-review prompt for ticket ${input.ticketId}. ` +
        `Fill in the local-quality-signal brief and diff context before recording.`,
    );
  }
  const relativePath = deriveRefactorReviewPromptPath(
    input.reviewsDirPath,
    input.ticketId,
  );
  const absolutePath = join(input.repoRoot, relativePath);
  mkdirSync(dirname(absolutePath), { recursive: true });
  const body = input.content.endsWith('\n')
    ? input.content
    : `${input.content}\n`;
  writeFileSync(absolutePath, body, 'utf-8');
  const writtenAt = (input.now ?? (() => new Date().toISOString()))();
  return { absolutePath, relativePath, writtenAt };
}

/**
 * Updates the P20.01 refactor-review ticket-state fields only. Deliberately
 * does not touch `TicketState.status` — the refactor gate is not yet wired
 * into the main ticket-status machine (that lands in ticket 20.03), so these
 * commands must remain independently invocable without perturbing the
 * existing `verified` -> `subagent_review_complete` transition owned by the
 * adversarial gate.
 */
export function recordRefactorReviewOutcome(input: {
  state: DeliveryState;
  ticketId?: string;
  outcome: SubagentRunnerOutcome;
  reviewedHeadSha: string;
  patchCommits?: InternalReviewPatchCommit[];
  agentName?: string;
  artifactPath?: string;
  now?: () => string;
}): DeliveryState {
  const target =
    (input.ticketId
      ? input.state.tickets.find((t) => t.id === input.ticketId)
      : input.state.tickets.find((t) => t.status === 'verified')) ?? undefined;
  if (!target) {
    throw new Error(
      input.ticketId
        ? `Unknown ticket ${input.ticketId}.`
        : 'No ticket at verified status found to record refactor review.',
    );
  }
  if (
    input.outcome === 'patched' &&
    (!input.patchCommits || input.patchCommits.length === 0)
  ) {
    throw new Error(
      `Refactor review outcome "patched" for ${target.id} requires at least one patch commit.`,
    );
  }
  const completedAt = (input.now ?? (() => new Date().toISOString()))();
  return {
    ...input.state,
    tickets: input.state.tickets.map((t) =>
      t.id === target.id
        ? {
            ...t,
            refactorReviewOutcome: input.outcome,
            refactorReviewCompletedAt: completedAt,
            refactorReviewPatchCommits: input.patchCommits,
            refactorReviewAgent: input.agentName,
            refactorRunnerArtifactPath: input.artifactPath,
            refactorReviewedHeadSha: input.reviewedHeadSha,
          }
        : t,
    ),
  };
}

/**
 * P20.03 — shared eligibility predicate: does the refactor gate apply to
 * this ticket at all? `true` only when `refactorReviewPolicy` is
 * `"runner_on_red"` (the repo default, `"disabled"`, always resolves
 * `false`), the ticket is `Red: required`, and it is not doc-only. Used both
 * to decide `status`'s next-command routing and to gate each of the three
 * refactor CLI commands (`write-subagent-refactor-review`,
 * `subagent-refactor-review`, `reconcile-subagent-refactor-review`) so a
 * `Red: skip` or doc-only ticket cannot have any of those steps attempted
 * even when invoked directly and `refactorReview` is `"runner_on_red"`.
 */
export function isRefactorGateEligible(input: {
  refactorReviewPolicy: RefactorReviewValue;
  redPolicy: RedPolicy;
  isDocOnly: boolean;
}): boolean {
  return (
    input.refactorReviewPolicy === 'runner_on_red' &&
    input.redPolicy === 'required' &&
    !input.isDocOnly
  );
}

/**
 * P20.03 — gate-placement predicate: does `write-subagent-adversarial-review`
 * need to block until the refactor gate has recorded an outcome first?
 *
 * `true` only when the ticket is eligible for the refactor gate (see
 * {@link isRefactorGateEligible}) and no refactor-review outcome has been
 * recorded yet.
 */
export function requiresRefactorReviewBeforeAdversarial(input: {
  refactorReviewPolicy: RefactorReviewValue;
  redPolicy: RedPolicy;
  isDocOnly: boolean;
  refactorReviewOutcome: SubagentRunnerOutcome | undefined;
}): boolean {
  if (!isRefactorGateEligible(input)) return false;
  return input.refactorReviewOutcome === undefined;
}

/**
 * P20.04 — advance-time surfacing of deferred refactor suggestions.
 *
 * A `deferred` ledger invocation carries its rationale in `findings[0]`
 * (the `--reason` given to `record-deferred`). Extracting this as a pure
 * function keeps the "which rows count as deferred" logic testable
 * independent of file I/O.
 */
export type DeferredRefactorReviewRow = {
  reason: string;
  reviewedHeadSha: string;
};

/**
 * Accepts an arbitrary parsed value, not a typed shape — this reads
 * untrusted on-disk JSON (a hand-editable ledger file), and a structurally
 * corrupt-but-valid-JSON artifact (non-array `invocations`, null rows,
 * non-string `findings`) must degrade to "no deferred rows found", not
 * throw. `advance` has already changed and saved delivery state by the time
 * this runs; a crash here must not be possible.
 */
export function extractDeferredRefactorReviewRows(
  artifact: unknown,
): DeferredRefactorReviewRow[] {
  if (typeof artifact !== 'object' || artifact === null) return [];
  const invocations = (artifact as { invocations?: unknown }).invocations;
  if (!Array.isArray(invocations)) return [];

  const rows: DeferredRefactorReviewRow[] = [];
  for (const row of invocations) {
    if (typeof row !== 'object' || row === null) continue;
    const r = row as Record<string, unknown>;
    if (r.outcome !== 'deferred') continue;
    const reviewedHeadSha =
      typeof r.reviewedHeadSha === 'string' ? r.reviewedHeadSha : '';
    const firstFinding = Array.isArray(r.findings) ? r.findings[0] : undefined;
    const reason =
      (typeof firstFinding === 'string' ? firstFinding.trim() : '') ||
      '(no reason recorded)';
    rows.push({ reason, reviewedHeadSha });
  }
  return rows;
}

/**
 * Formats deferred rows for `advance`'s console output. Returns `undefined`
 * (not an empty string) when there is nothing to print, so the caller can
 * skip printing entirely — a ticket with no refactor-review ledger, or a
 * ledger with zero `deferred` rows, must produce no extra output at all.
 */
export function formatDeferredRefactorSuggestions(
  ticketId: string,
  rows: DeferredRefactorReviewRow[],
): string | undefined {
  if (rows.length === 0) return undefined;
  const lines = rows.map((row) => `  - ${row.reason}`);
  return [
    `Deferred refactor-review suggestions for ${ticketId} (not silently lost):`,
    ...lines,
  ].join('\n');
}
