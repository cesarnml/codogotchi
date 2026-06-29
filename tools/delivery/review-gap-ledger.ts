import { appendFileSync, existsSync, readFileSync } from 'node:fs';

export const REVIEW_GAP_KINDS = [
  'review-reachable',
  'spec-gap',
  'qa-gap',
  'completeness-gap',
] as const;

export const REVIEW_GAP_REACHABILITY_CLASSIFICATIONS = [
  'review-reachable',
  'spec-gap',
  'qa-gap',
  'completeness-gap',
] as const;

export type ReviewGapKind = (typeof REVIEW_GAP_KINDS)[number];

export type ReviewGapReachabilityClassification =
  (typeof REVIEW_GAP_REACHABILITY_CLASSIFICATIONS)[number];

export interface ReviewGapCommitReferenceInput {
  sha: string;
  subject: string;
}

export interface ReviewGapReachabilityInput {
  classification: string;
  evidence?: string;
  promptLesson?: string;
}

export interface ReviewGapRecordInput {
  phase: string;
  date: string;
  kind: string;
  summary: string;
  fixCommit: ReviewGapCommitReferenceInput;
  detectionRounds: number;
  reachability: ReviewGapReachabilityInput;
  /**
   * Optional rich-capture fields ported from the pioneering codogotchi ad-hoc
   * quality-control ledger. They carry the experiential detail a one-line
   * `summary` cannot: the precise failure, the fix shape, a defect-class label,
   * how testable the gap was, and prior ledger ids this recurs from. All are
   * optional so slim records stay valid; rich records are preferred when a fix
   * exposes reusable learning.
   */
  id?: string;
  problem?: string;
  solution?: string;
  defectClass?: string;
  testReachability?: string;
  recurrence?: string[];
}

export interface ReviewGapRecord extends Omit<
  ReviewGapRecordInput,
  'kind' | 'reachability'
> {
  kind: ReviewGapKind;
  reachability: {
    classification: ReviewGapReachabilityClassification;
    evidence?: string;
    promptLesson?: string;
  };
}

function assertNonEmptyString(value: string, field: string): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`Review-gap ledger field '${field}' is required.`);
  }

  return value.trim();
}

function assertOneOf<T extends readonly string[]>(
  value: string,
  field: string,
  allowed: T,
): T[number] {
  if (!allowed.includes(value)) {
    throw new Error(
      `Review-gap ledger field '${field}' must be one of: ${allowed.join(', ')}.`,
    );
  }

  return value as T[number];
}

function assertValidDate(value: string): string {
  const date = assertNonEmptyString(value, 'date');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error("Review-gap ledger field 'date' must use YYYY-MM-DD.");
  }

  const parsed = new Date(`${date}T00:00:00.000Z`);
  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== date
  ) {
    throw new Error(
      "Review-gap ledger field 'date' must be a real calendar date.",
    );
  }

  return date;
}

function assertValidPhase(value: string): string {
  const phase = assertNonEmptyString(value, 'phase');
  if (!/^phase-\d{2}$/.test(phase)) {
    throw new Error("Review-gap ledger field 'phase' must use phase-NN form.");
  }

  return phase;
}

function assertValidCommit(
  value: ReviewGapCommitReferenceInput,
): ReviewGapCommitReferenceInput {
  if (!value || typeof value !== 'object') {
    throw new Error(
      "Review-gap ledger field 'fixCommit' must include commit provenance.",
    );
  }

  const sha = assertNonEmptyString(value.sha, 'fixCommit.sha');
  const subject = assertNonEmptyString(value.subject, 'fixCommit.subject');
  if (!/^[0-9a-f]{7,40}$/i.test(sha)) {
    throw new Error(
      "Review-gap ledger field 'fixCommit.sha' must be a commit SHA.",
    );
  }

  return { sha, subject };
}

function assertPositiveInteger(value: number): number {
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(
      "Review-gap ledger field 'detectionRounds' must be a positive round count.",
    );
  }

  return value;
}

function normalizeOptionalString(
  value: string | undefined,
): string | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed === '' ? undefined : trimmed;
}

function assertValidRecurrence(
  value: string[] | undefined,
): string[] | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (!Array.isArray(value)) {
    throw new Error(
      "Review-gap ledger field 'recurrence' must be an array of ledger ids.",
    );
  }

  const ids = value.map((entry, index) =>
    assertNonEmptyString(entry, `recurrence[${index}]`),
  );

  return ids.length > 0 ? ids : undefined;
}

function assertValidReachability(
  value: ReviewGapReachabilityInput,
): ReviewGapRecord['reachability'] {
  if (!value || typeof value !== 'object') {
    throw new Error(
      "Review-gap ledger field 'reachability' must include a classification.",
    );
  }

  const classification = assertOneOf(
    assertNonEmptyString(value.classification, 'reachability.classification'),
    'reachability.classification',
    REVIEW_GAP_REACHABILITY_CLASSIFICATIONS,
  );
  const evidence = normalizeOptionalString(value.evidence);
  const promptLesson = normalizeOptionalString(value.promptLesson);

  if (classification === 'review-reachable' && (!evidence || !promptLesson)) {
    throw new Error(
      'Review-reachable records require a prompt lesson and concrete review evidence.',
    );
  }

  return {
    classification,
    ...(evidence ? { evidence } : {}),
    ...(promptLesson ? { promptLesson } : {}),
  };
}

export function validateReviewGapRecord(
  input: ReviewGapRecordInput,
): ReviewGapRecord {
  const kind = assertOneOf(
    assertNonEmptyString(input.kind, 'kind'),
    'kind',
    REVIEW_GAP_KINDS,
  );
  const reachability = assertValidReachability(input.reachability);

  if (kind !== reachability.classification) {
    throw new Error(
      "Review-gap ledger fields 'kind' and 'reachability.classification' must match.",
    );
  }

  const id = normalizeOptionalString(input.id);
  const problem = normalizeOptionalString(input.problem);
  const solution = normalizeOptionalString(input.solution);
  const defectClass = normalizeOptionalString(input.defectClass);
  const testReachability = normalizeOptionalString(input.testReachability);
  const recurrence = assertValidRecurrence(input.recurrence);

  const record: ReviewGapRecord = {
    ...(id ? { id } : {}),
    phase: assertValidPhase(input.phase),
    date: assertValidDate(input.date),
    kind,
    summary: assertNonEmptyString(input.summary, 'summary'),
    ...(problem ? { problem } : {}),
    ...(solution ? { solution } : {}),
    ...(defectClass ? { defectClass } : {}),
    fixCommit: assertValidCommit(input.fixCommit),
    detectionRounds: assertPositiveInteger(input.detectionRounds),
    reachability,
    ...(testReachability ? { testReachability } : {}),
    ...(recurrence ? { recurrence } : {}),
  };

  return record;
}

function needsLineBoundary(path: string): boolean {
  if (!existsSync(path)) {
    return false;
  }

  const existing = readFileSync(path);
  return existing.length > 0 && existing[existing.length - 1] !== 0x0a;
}

export function appendReviewGapRecord(
  ledgerPath: string,
  input: ReviewGapRecordInput,
): ReviewGapRecord {
  const record = validateReviewGapRecord(input);
  const prefix = needsLineBoundary(ledgerPath) ? '\n' : '';
  appendFileSync(ledgerPath, `${prefix}${JSON.stringify(record)}\n`);

  return record;
}
