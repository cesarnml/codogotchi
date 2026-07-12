import { describe, expect, it } from 'bun:test';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  appendReviewGapRecord,
  validateReviewGapRecord,
  type ReviewGapRecordInput,
} from '../review-gap-ledger';

function validRecord(
  overrides: Partial<ReviewGapRecordInput> = {},
): ReviewGapRecordInput {
  return {
    phase: 'phase-19',
    date: '2026-06-28',
    kind: 'review-reachable',
    summary: 'Subagent review missed an append-only ledger invariant.',
    fixCommit: {
      sha: 'abc123def456',
      subject: 'fix: preserve review-gap ledger lines',
    },
    detectionRounds: 2,
    reachability: {
      classification: 'review-reachable',
      evidence:
        'The ticket review prompt included the ledger append invariant and the diff touched the append helper.',
      promptLesson:
        'Check append-only JSONL helpers with pre-existing file bytes, not only parsed records.',
    },
    ...overrides,
  };
}

describe('P19.02 review-gap ledger record helper', () => {
  it('appends one valid JSONL record while preserving existing lines', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p19-02-ledger-'));
    try {
      const ledgerPath = join(tmp, 'ledger.jsonl');
      const existing = '{"phase":"phase-18","summary":"keep me"}\n';
      writeFileSync(ledgerPath, existing);

      appendReviewGapRecord(ledgerPath, validRecord());

      const next = readFileSync(ledgerPath, 'utf8');
      expect(next.startsWith(existing)).toBe(true);
      expect(next.endsWith('\n')).toBe(true);

      const lines = next.trimEnd().split('\n');
      expect(lines).toHaveLength(2);
      expect(JSON.parse(lines[1] ?? '{}')).toMatchObject({
        phase: 'phase-19',
        kind: 'review-reachable',
        detectionRounds: 2,
      });
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('appends on a new line when the existing ledger lacks a trailing newline', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p19-02-ledger-boundary-'));
    try {
      const ledgerPath = join(tmp, 'ledger.jsonl');
      const existing = '{"phase":"phase-18","summary":"keep me"}';
      writeFileSync(ledgerPath, existing);

      appendReviewGapRecord(ledgerPath, validRecord());

      const next = readFileSync(ledgerPath, 'utf8');
      expect(next.startsWith(`${existing}\n`)).toBe(true);
      expect(next.trimEnd().split('\n')).toHaveLength(2);
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('rejects malformed phase attribution', () => {
    expect(() =>
      validateReviewGapRecord(validRecord({ phase: 'p19' })),
    ).toThrow(/phase-NN/);
  });

  it('rejects impossible calendar dates', () => {
    expect(() =>
      validateReviewGapRecord(validRecord({ date: '2026-02-31' })),
    ).toThrow(/calendar date/);
  });

  it('rejects missing commit provenance', () => {
    expect(() =>
      validateReviewGapRecord(
        validRecord({ fixCommit: { sha: '', subject: '' } }),
      ),
    ).toThrow(/commit/i);
  });

  it('rejects unsupported reachability classifications', () => {
    expect(() =>
      validateReviewGapRecord(
        validRecord({
          reachability: {
            classification: 'maybe-reviewable',
            evidence: 'unclear',
          },
        }),
      ),
    ).toThrow(/reachability/i);
  });

  it('rejects kind and reachability mismatches', () => {
    expect(() =>
      validateReviewGapRecord(
        validRecord({
          kind: 'review-reachable',
          reachability: {
            classification: 'spec-gap',
          },
        }),
      ),
    ).toThrow(/must match/);
  });

  it('rejects zero or negative detection rounds', () => {
    expect(() =>
      validateReviewGapRecord(validRecord({ detectionRounds: 0 })),
    ).toThrow(/round/i);
    expect(() =>
      validateReviewGapRecord(validRecord({ detectionRounds: -1 })),
    ).toThrow(/round/i);
  });

  it('rejects unsupported review-gap kinds', () => {
    expect(() =>
      validateReviewGapRecord(validRecord({ kind: 'nice-to-have' })),
    ).toThrow(/kind/i);
  });

  it('requires evidence and a prompt lesson for review-reachable records', () => {
    expect(() =>
      validateReviewGapRecord(
        validRecord({
          reachability: {
            classification: 'review-reachable',
            evidence: '',
            promptLesson: '',
          },
        }),
      ),
    ).toThrow(/prompt lesson/i);
  });

  it('allows non-review-reachable records without prompt lessons', () => {
    expect(() =>
      validateReviewGapRecord(
        validRecord({
          kind: 'spec-gap',
          reachability: {
            classification: 'spec-gap',
            evidence: '',
            promptLesson: '',
          },
        }),
      ),
    ).not.toThrow();
  });

  it('round-trips optional rich-capture fields when supplied', () => {
    const record = validateReviewGapRecord(
      validRecord({
        kind: 'qa-gap',
        reachability: { classification: 'qa-gap' },
        id: 'codogotchi-16',
        problem: 'Menubar icon floated small next to system icons.',
        solution: 'Sized the status item to the menu-bar thickness.',
        defectClass: 'undersized-static-asset',
        testReachability: 'Manual: visible only by running the menubar app.',
        recurrence: ['codogotchi-12'],
      }),
    );

    expect(record).toMatchObject({
      id: 'codogotchi-16',
      problem: 'Menubar icon floated small next to system icons.',
      solution: 'Sized the status item to the menu-bar thickness.',
      defectClass: 'undersized-static-asset',
      testReachability: 'Manual: visible only by running the menubar app.',
      recurrence: ['codogotchi-12'],
    });
  });

  it('omits rich-capture fields from slim records', () => {
    const record = validateReviewGapRecord(validRecord());

    expect(record).not.toHaveProperty('id');
    expect(record).not.toHaveProperty('problem');
    expect(record).not.toHaveProperty('recurrence');
  });

  it('drops a recurrence array down to undefined when empty', () => {
    const record = validateReviewGapRecord(validRecord({ recurrence: [] }));

    expect(record).not.toHaveProperty('recurrence');
  });

  it('rejects a non-array recurrence value', () => {
    expect(() =>
      validateReviewGapRecord(
        validRecord({ recurrence: 'codogotchi-12' as unknown as string[] }),
      ),
    ).toThrow(/recurrence/i);
  });

  it('rejects empty recurrence ids', () => {
    expect(() =>
      validateReviewGapRecord(validRecord({ recurrence: ['  '] })),
    ).toThrow(/recurrence\[0\]/);
  });
});
