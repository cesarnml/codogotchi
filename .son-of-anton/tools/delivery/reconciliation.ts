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
 * Canonical sibling section headings used by the subagent review report. The
 * parser terminates a section extraction only when it encounters another of
 * these headings — not on every `**bold**` or `# heading` line. Without this
 * list, observation-prefix lines like `**A1 — Title**` were being read as
 * section terminators, silently dropping all observations that followed them.
 *
 * Heading aliases (`Runner status` ↔ `Runner termination`) tolerate light
 * subagent drift across runners.
 */
const CANONICAL_REPORT_SECTION_HEADINGS = [
  'Invariant results',
  'Surface results',
  'Actionable findings',
  'Advisory Observations',
  'Findings for human review', // legacy alias of Advisory Observations
  'Runner termination',
  'Runner status', // tolerated drift
] as const;

/**
 * Parses the `Actionable findings` section of the subagent report markdown
 * and returns true if it contains any actionable content (anything other than
 * `None.` or whitespace). Tolerates extra blank lines, trailing whitespace,
 * and slight heading-format drift.
 */
export function parseActionableFindings(markdown: string): boolean {
  const body = extractReportSection(markdown, 'Actionable findings');
  if (body === undefined) return false;
  const normalized = normalizeSectionBody(body);
  if (normalized === '') return false;
  if (/^none\.?$/i.test(normalized)) return false;
  return true;
}

export function parseAdvisoryObservations(markdown: string): string[] {
  const body = extractReportSection(markdown, 'Advisory Observations');
  if (body === undefined) return [];
  const normalized = normalizeSectionBody(body);
  if (normalized === '') return [];
  if (/^none\.?$/i.test(normalized)) return [];

  const nonEmptyLines = normalized.split('\n');
  const bulletLines = nonEmptyLines.filter((line) => /^[-*]\s+/.test(line));
  if (bulletLines.length > 0 && bulletLines.length === nonEmptyLines.length) {
    return bulletLines.map((line) => line.replace(/^[-*]\s+/, '').trim());
  }

  return body
    .trim()
    .split(/\n{2,}/)
    .map((paragraph) => paragraph.replace(/\n/g, ' ').trim())
    .filter((paragraph) => paragraph.length > 0);
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

function extractReportSection(
  markdown: string,
  heading: string,
): string | undefined {
  const lines = markdown.split('\n');
  const startIndex = lines.findIndex((line) => isHeadingFor(line, heading));
  if (startIndex === -1) return undefined;
  const bodyLines: string[] = [];
  for (const line of lines.slice(startIndex + 1)) {
    // Only terminate the section on a canonical sibling section heading. Bold
    // observation prefixes (e.g. `**A1 — Title**`) are content, not section
    // boundaries, and must not silently truncate the section body.
    if (isCanonicalSectionHeadingLine(line, heading)) break;
    bodyLines.push(line);
  }
  return bodyLines.join('\n');
}

function normalizeSectionBody(body: string): string {
  return body
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join('\n')
    .trim();
}

function isHeadingFor(line: string, heading: string): boolean {
  const escapedHeading = heading
    .trim()
    .split(/\s+/)
    .map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
    .join('\\s+');
  return (
    new RegExp(`^\\s*\\*\\*\\s*${escapedHeading}\\s*\\*\\*\\s*$`, 'i').test(
      line,
    ) ||
    new RegExp(`^\\s{0,3}#{1,6}\\s+${escapedHeading}\\s*#*\\s*$`, 'i').test(
      line,
    )
  );
}

/**
 * Returns true only when `line` is a heading that matches one of the canonical
 * sibling section headings (`Actionable findings`, `Advisory Observations`,
 * `Runner termination`, etc.) and is not the heading we are currently
 * extracting. This keeps non-canonical bold prefixes inside the section body
 * where they belong.
 */
function isCanonicalSectionHeadingLine(
  line: string,
  currentHeading: string,
): boolean {
  return CANONICAL_REPORT_SECTION_HEADINGS.some(
    (candidate) =>
      candidate.toLowerCase() !== currentHeading.toLowerCase() &&
      isHeadingFor(line, candidate),
  );
}

type ArtifactRow = { outcome: string; reviewedHeadSha?: string };

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

  const changedInRange =
    input.reviewedHeadSha === input.headSha
      ? []
      : input.listChangedPathsInRange(input.reviewedHeadSha, input.headSha);
  const reviewedSet = new Set(input.reviewedPaths);
  const reviewedPathTouched = changedInRange.some((p) => reviewedSet.has(p));

  if (reviewedPathTouched && !hasDeferredRowForSha) {
    return {
      kind: 'blocked',
      condition: 'A',
      message: RECONCILIATION_BLOCKED_MESSAGE_A,
    };
  }

  const findingsExist = parseActionableFindings(input.reportMarkdown);
  if (findingsExist && !hasDeferredRowForSha) {
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
