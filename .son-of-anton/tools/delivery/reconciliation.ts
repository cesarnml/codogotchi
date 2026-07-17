/**
 * P14.03 — Outcome derivation and PR-open reconciliation.
 *
 * Detects `[subagent-review]`-labeled commits between the runner's
 * `reviewedHeadSha` and HEAD, derives reconciliation outcomes from observed
 * git state, and exposes operator-explicit acknowledgment helpers so the
 * ledger can be brought into honest agreement with reality before `open-pr`
 * publishes the PR.
 *
 * The reconciliation gate is the load-bearing silent-lie-prevention mechanism
 * promised by the Phase 14 product contract.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join } from 'node:path';

const SUBAGENT_REVIEW_SUBJECT_PATTERN = /\[subagent-review\]/i;

/**
 * Stable error-message format documented for headless integrations (CI, alerts).
 * Do NOT change this string without a deliberate contract bump.
 */
export const RECONCILIATION_BLOCKED_MESSAGE_A =
  'reconcile-subagent-review: Condition A — files in the reviewed paths were ' +
  'modified since the subagent-review row but no `[subagent-review]`-labeled commit ' +
  'touches them, and no `deferred` row exists. Resolve via:\n' +
  '  1. amend the patch commit subject to include `[subagent-review]`, or\n' +
  '  2. `bun run deliver subagent-review record-deferred --reason "<rationale>"`, or\n' +
  '  3. `bun run deliver open-pr --ack-reconciliation <patched|deferred|clean> [--commit <sha>] [--reason "<text>"]`.';

export const RECONCILIATION_BLOCKED_MESSAGE_B =
  'reconcile-subagent-review: Condition B — the subagent report lists actionable ' +
  'findings but no commit modified the reviewed paths and no `deferred` row exists. ' +
  'Resolve via:\n' +
  '  1. apply the prudent patches and commit with `[subagent-review]` in the subject, or\n' +
  '  2. `bun run deliver subagent-review record-deferred --reason "<rationale>"`, or\n' +
  '  3. `bun run deliver open-pr --ack-reconciliation <patched|deferred|clean> [--commit <sha>] [--reason "<text>"]`.';

export class ReconciliationBlockedError extends Error {
  readonly condition: 'A' | 'B';
  constructor(condition: 'A' | 'B', message: string) {
    super(message);
    this.condition = condition;
    this.name = 'ReconciliationBlockedError';
  }
}

export function detectLabeledCommits(input: {
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
    if (!SUBAGENT_REVIEW_SUBJECT_PATTERN.test(subject)) continue;
    const files = input.listCommitFiles(sha);
    if (files.some((f) => reviewedSet.has(f))) {
      result.push(sha);
    }
  }
  return result;
}

/**
 * P21.01 — tag-based report contract.
 *
 * Replaces the heading-grammar machinery (`CANONICAL_REPORT_SECTION_HEADINGS`,
 * `extractReportSection`, `stripHorizontalRules`, `isHeadingFor`,
 * `isCanonicalSectionHeadingLine`) with balanced-tag extraction, per
 * `notes/public/subagent-report-parser-contract.md`. Modeled directly on
 * `parseRefactorSuggestions` in `refactor-review.ts`: last-open-tag-wins,
 * close-tag-or-EOF, case-insensitive tag-name match, trimmed-line
 * normalization, literal `None` detection. No heading recognition, no
 * terminator regex — the tag boundary is the only signal.
 */

type TaggedBulletParseResult = {
  /** Whether an opening tag was found at all. */
  found: boolean;
  /** Whether a matching closing tag was found (false = parsed to EOF). */
  closed: boolean;
  /** True only for the literal `None` body — a clean report, not a drift warning. */
  isExplicitNone: boolean;
  /** Parsed bullet lines, trimmed and de-prefixed. Empty when none found. */
  items: string[];
};

/**
 * Extracts a tagged block (`<tagName>…</tagName>`) and its `^[-*]` bullet
 * lines. When more than one open tag appears (e.g. a template skeleton
 * example quoted earlier in the report), the **last** occurrence is
 * authoritative — a report's real output section follows any quoted example.
 */
function parseTaggedBulletBlock(
  markdown: string,
  openTag: RegExp,
  closeTag: RegExp,
): TaggedBulletParseResult {
  const openMatches = [...markdown.matchAll(new RegExp(openTag, 'gi'))];
  if (openMatches.length === 0) {
    return { found: false, closed: false, isExplicitNone: false, items: [] };
  }
  const openMatch = openMatches[openMatches.length - 1]!;

  const afterOpen = markdown.slice(
    (openMatch.index ?? 0) + openMatch[0].length,
  );
  const closeMatch = closeTag.exec(afterOpen);
  const closed = closeMatch !== null;
  const body = closed ? afterOpen.slice(0, closeMatch.index) : afterOpen;

  const normalized = body
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join('\n')
    .trim();

  if (closed && /^none\.?$/i.test(normalized)) {
    return { found: true, closed, isExplicitNone: true, items: [] };
  }

  if (normalized === '') {
    return { found: true, closed, isExplicitNone: false, items: [] };
  }

  const bulletLines = normalized
    .split('\n')
    .filter((line) => /^[-*]\s+/.test(line));

  return {
    found: true,
    closed,
    isExplicitNone: false,
    items: bulletLines.map((line) => line.replace(/^[-*]\s+/, '').trim()),
  };
}

const ACTIONABLE_FINDINGS_OPEN_TAG = /<actionable-findings>/i;
const ACTIONABLE_FINDINGS_CLOSE_TAG = /<\/actionable-findings>/i;

export type ActionableFindingsParseResult = {
  found: boolean;
  closed: boolean;
  isExplicitNone: boolean;
  findings: string[];
};

/**
 * Extracts the `<actionable-findings>` tagged block from a subagent-review
 * report. Returns a structured parse-health signal (found/closed/
 * isExplicitNone) alongside the parsed findings so the caller — the
 * `subagent-review` record path — can warn precisely on drift instead of
 * silently treating a 0-parse as "no findings."
 */
export function parseActionableFindings(
  markdown: string,
): ActionableFindingsParseResult {
  const result = parseTaggedBulletBlock(
    markdown,
    ACTIONABLE_FINDINGS_OPEN_TAG,
    ACTIONABLE_FINDINGS_CLOSE_TAG,
  );
  return {
    found: result.found,
    closed: result.closed,
    isExplicitNone: result.isExplicitNone,
    findings: result.items,
  };
}

/**
 * True when the parse result should be treated as a silent-drift warning at
 * `subagent-review` record time: the tag was missing/misnamed, the closing
 * tag was absent, or the tag was present but yielded zero findings without
 * the literal `None` clean-signal.
 */
export function isSuspiciousActionableFindingsParse(
  result: ActionableFindingsParseResult,
): boolean {
  if (!result.found || !result.closed) return true;
  return result.findings.length === 0 && !result.isExplicitNone;
}

const ADVISORY_OBSERVATIONS_OPEN_TAG = /<advisory-observations>/i;
const ADVISORY_OBSERVATIONS_CLOSE_TAG = /<\/advisory-observations>/i;

export type AdvisoryObservationsParseResult = {
  found: boolean;
  closed: boolean;
  isExplicitNone: boolean;
  observations: string[];
};

/**
 * Extracts the `<advisory-observations>` tagged block, structured parse
 * result. `parseAdvisoryObservations` (below) is the array-returning
 * convenience wrapper existing call sites use.
 */
export function parseAdvisoryObservationsResult(
  markdown: string,
): AdvisoryObservationsParseResult {
  const result = parseTaggedBulletBlock(
    markdown,
    ADVISORY_OBSERVATIONS_OPEN_TAG,
    ADVISORY_OBSERVATIONS_CLOSE_TAG,
  );
  return {
    found: result.found,
    closed: result.closed,
    isExplicitNone: result.isExplicitNone,
    observations: result.items,
  };
}

export function parseAdvisoryObservations(markdown: string): string[] {
  return parseAdvisoryObservationsResult(markdown).observations;
}

/**
 * True when the parse result should be treated as a silent-drift warning at
 * `subagent-review` record time — symmetric to
 * `isSuspiciousActionableFindingsParse`.
 */
export function isSuspiciousAdvisoryObservationsParse(
  result: AdvisoryObservationsParseResult,
): boolean {
  if (!result.found || !result.closed) return true;
  return result.observations.length === 0 && !result.isExplicitNone;
}

export type SuspiciousSubagentReviewEvidence = {
  kind: 'missing_report' | 'empty_report';
  rawOutput?: string;
};

export function inspectSubagentReviewEvidence(input: {
  repoRoot: string;
  rows: Array<{
    outcome: string;
    terminatedReason?: string;
    rawOutput?: string;
  }>;
}): SuspiciousSubagentReviewEvidence[] {
  const warnings: SuspiciousSubagentReviewEvidence[] = [];
  for (const row of input.rows) {
    if (row.outcome !== 'clean' || row.terminatedReason !== 'completed') {
      continue;
    }
    const rawOutput = row.rawOutput;
    if (!rawOutput || rawOutput.trim() === '') {
      warnings.push({ kind: 'missing_report', rawOutput });
      continue;
    }
    const reportPath = isAbsolute(rawOutput)
      ? rawOutput
      : join(input.repoRoot, rawOutput);
    if (!existsSync(reportPath)) {
      warnings.push({ kind: 'missing_report', rawOutput });
      continue;
    }
    const report = readFileSync(reportPath, 'utf-8');
    if (report.trim() === '') {
      warnings.push({ kind: 'empty_report', rawOutput });
    }
  }
  return warnings;
}

type ArtifactRow = {
  outcome: string;
  reviewedHeadSha?: string;
  acknowledgment?: string;
};

export function reconcileReview(input: {
  artifactRows: ArtifactRow[];
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
  const labeledShas = detectLabeledCommits({
    reviewedHeadSha: input.reviewedHeadSha,
    headSha: input.headSha,
    reviewedPaths: input.reviewedPaths,
    listCommitSubjects: input.listCommitSubjects,
    listCommitFiles: input.listCommitFiles,
  });
  if (labeledShas.length > 0) {
    return { kind: 'patched', commitShas: labeledShas };
  }

  const hasDeferredRowForSha = input.artifactRows.some(
    (row) =>
      row.outcome === 'deferred' &&
      row.reviewedHeadSha === input.reviewedHeadSha,
  );

  // `--ack-reconciliation clean` records an operator-confirmed-clean row via
  // recordAcknowledgment(). It must unblock reconciliation the same way a
  // `deferred` row does — otherwise the documented escape valve is a no-op
  // and `record-deferred` becomes the only working path even when the honest
  // answer is "no patch needed."
  const hasCleanAckRowForSha = input.artifactRows.some(
    (row) =>
      row.outcome === 'clean' &&
      row.acknowledgment === 'operator-confirmed-clean' &&
      row.reviewedHeadSha === input.reviewedHeadSha,
  );

  const isAcknowledged = hasDeferredRowForSha || hasCleanAckRowForSha;

  const changedInRange =
    input.reviewedHeadSha === input.headSha
      ? []
      : input.listChangedPathsInRange(input.reviewedHeadSha, input.headSha);
  const reviewedSet = new Set(input.reviewedPaths);
  const reviewedPathTouched = changedInRange.some((p) => reviewedSet.has(p));

  if (reviewedPathTouched && !isAcknowledged) {
    return {
      kind: 'blocked',
      condition: 'A',
      message: RECONCILIATION_BLOCKED_MESSAGE_A,
    };
  }

  // Block on suspicious parses too, not only on successfully-extracted
  // bullets: a closed, non-empty, non-`None` `<actionable-findings>` tag
  // whose body is prose rather than `- ` bullets parses to zero findings
  // (the barebones bullet-only extractor has no prose fallback by design),
  // so `findings.length > 0` alone would silently wave through a report that
  // has real actionable content just because the subagent didn't bullet it.
  // Gated on a report actually existing: the operator-recorder path (no
  // `--subagent` runner invoked) legitimately has no report file at all, and
  // that empty-markdown case must stay non-blocking exactly as before.
  const hasReport = input.reportMarkdown.trim() !== '';
  const actionableParse = parseActionableFindings(input.reportMarkdown);
  const findingsExist =
    actionableParse.findings.length > 0 ||
    (hasReport && isSuspiciousActionableFindingsParse(actionableParse));
  if (findingsExist && !isAcknowledged) {
    return {
      kind: 'blocked',
      condition: 'B',
      message: RECONCILIATION_BLOCKED_MESSAGE_B,
    };
  }

  return { kind: 'clean' };
}

function appendRow(
  artifactPath: string,
  ticket: string,
  row: Record<string, unknown>,
): void {
  let parsed: { ticket: string; invocations: Record<string, unknown>[] };
  if (existsSync(artifactPath)) {
    parsed = JSON.parse(readFileSync(artifactPath, 'utf-8'));
  } else {
    parsed = { ticket, invocations: [] };
  }
  parsed.invocations.push(row);
  mkdirSync(dirname(artifactPath), { recursive: true });
  writeFileSync(artifactPath, JSON.stringify(parsed, null, 2) + '\n', 'utf-8');
}

const SCHEMA_VERSION = 1;

export function recordDeferred(input: {
  artifactPath: string;
  ticket: string;
  reviewedHeadSha: string;
  reason: string;
  primaryAgent?: string;
}): void {
  if (!input.reason || input.reason.trim() === '') {
    throw new Error(
      'record-deferred requires a non-empty --reason; the rationale is captured on the ledger for audit.',
    );
  }
  appendRow(input.artifactPath, input.ticket, {
    runnerKind: 'operator-recorder',
    reviewedHeadSha: input.reviewedHeadSha,
    outcome: 'deferred',
    completedAt: new Date().toISOString(),
    terminatedReason: 'completed',
    findings: [],
    probedSurfaces: [],
    patches: [],
    reason: input.reason.trim(),
    schemaVersion: SCHEMA_VERSION,
    primaryAgent: input.primaryAgent ?? 'unknown',
    runnerSelfReport: null,
    fallbackFrom: null,
  });
}

export function recordAcknowledgment(input: {
  artifactPath: string;
  ticket: string;
  reviewedHeadSha: string;
  variant: 'patched' | 'deferred' | 'clean';
  commitSha?: string;
  reason?: string;
  primaryAgent?: string;
}): void {
  const now = new Date().toISOString();
  const base: Record<string, unknown> = {
    runnerKind: 'operator-recorder',
    reviewedHeadSha: input.reviewedHeadSha,
    completedAt: now,
    terminatedReason: 'completed',
    findings: [],
    probedSurfaces: [],
    patches: [],
    schemaVersion: SCHEMA_VERSION,
    primaryAgent: input.primaryAgent ?? 'unknown',
    runnerSelfReport: null,
    fallbackFrom: null,
  };

  if (input.variant === 'patched') {
    if (!input.commitSha || input.commitSha.trim() === '') {
      throw new Error(
        '--ack-reconciliation patched requires --commit <sha> so the audit trail names the actual patch SHA.',
      );
    }
    appendRow(input.artifactPath, input.ticket, {
      ...base,
      outcome: 'patched',
      patches: [input.commitSha.trim()],
    });
    return;
  }

  if (input.variant === 'deferred') {
    if (!input.reason || input.reason.trim() === '') {
      throw new Error(
        '--ack-reconciliation deferred requires a non-empty --reason; the rationale is captured on the ledger for audit.',
      );
    }
    appendRow(input.artifactPath, input.ticket, {
      ...base,
      outcome: 'deferred',
      reason: input.reason.trim(),
    });
    return;
  }

  if (input.variant === 'clean') {
    if (!input.reason || input.reason.trim() === '') {
      throw new Error(
        '--ack-reconciliation clean requires a non-empty --reason explaining why post-review modifications do not require a re-review.',
      );
    }
    appendRow(input.artifactPath, input.ticket, {
      ...base,
      outcome: 'clean',
      acknowledgment: 'operator-confirmed-clean',
      reason: input.reason.trim(),
    });
    return;
  }

  throw new Error(
    `Unknown ack-reconciliation variant: ${String(input.variant)}`,
  );
}
