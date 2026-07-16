import { describe, expect, it } from 'bun:test';

import {
  extractDeferredRefactorReviewRows,
  formatDeferredRefactorSuggestions,
} from '../refactor-review';

describe('P20.04 — extractDeferredRefactorReviewRows', () => {
  it('extracts the reason from deferred invocations', () => {
    const rows = extractDeferredRefactorReviewRows({
      invocations: [
        {
          outcome: 'deferred',
          reviewedHeadSha: 'sha-1',
          findings: ['not worth the churn this ticket'],
        },
      ],
    });
    expect(rows).toEqual([
      { reason: 'not worth the churn this ticket', reviewedHeadSha: 'sha-1' },
    ]);
  });

  it('returns an empty array when the ledger has zero deferred rows', () => {
    const rows = extractDeferredRefactorReviewRows({
      invocations: [
        { outcome: 'clean', reviewedHeadSha: 'sha-1', findings: [] },
        { outcome: 'patched', reviewedHeadSha: 'sha-2', findings: [] },
      ],
    });
    expect(rows).toEqual([]);
  });

  it('returns an empty array for an empty invocations list', () => {
    expect(extractDeferredRefactorReviewRows({ invocations: [] })).toEqual([]);
  });

  it('falls back to a placeholder reason when findings is empty', () => {
    const rows = extractDeferredRefactorReviewRows({
      invocations: [
        { outcome: 'deferred', reviewedHeadSha: 'sha-1', findings: [] },
      ],
    });
    expect(rows[0]!.reason).toBe('(no reason recorded)');
  });

  it('degrades to no rows for structurally corrupt (but valid-JSON) artifacts, never throws', () => {
    expect(extractDeferredRefactorReviewRows(null)).toEqual([]);
    expect(extractDeferredRefactorReviewRows(42)).toEqual([]);
    expect(extractDeferredRefactorReviewRows({})).toEqual([]);
    expect(extractDeferredRefactorReviewRows({ invocations: null })).toEqual(
      [],
    );
    expect(extractDeferredRefactorReviewRows({ invocations: {} })).toEqual([]);
    expect(
      extractDeferredRefactorReviewRows({ invocations: [null, 42, 'x'] }),
    ).toEqual([]);
  });

  it('falls back to a placeholder reason when findings[0] is not a string', () => {
    const rows = extractDeferredRefactorReviewRows({
      invocations: [
        {
          outcome: 'deferred',
          reviewedHeadSha: 'sha-1',
          findings: [42, 'ignored'],
        },
      ],
    });
    expect(rows[0]!.reason).toBe('(no reason recorded)');
  });
});

describe('P20.04 — formatDeferredRefactorSuggestions', () => {
  it('formats deferred rows with the ticket id and each reason as a bullet', () => {
    const message = formatDeferredRefactorSuggestions('P20.04', [
      { reason: 'extract duplicated retry logic', reviewedHeadSha: 'sha-1' },
      { reason: 'rename doStuff', reviewedHeadSha: 'sha-1' },
    ]);
    expect(message).toContain('P20.04');
    expect(message).toContain('extract duplicated retry logic');
    expect(message).toContain('rename doStuff');
  });

  it('returns undefined (prints nothing extra) for an empty rows array', () => {
    expect(formatDeferredRefactorSuggestions('P20.04', [])).toBeUndefined();
  });
});
