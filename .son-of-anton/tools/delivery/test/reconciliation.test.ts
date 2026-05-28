import { describe, expect, it } from 'bun:test';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// P14.03 — `reconciliation.ts` module does not yet exist. Dynamic import so
// the test file still parses while helpers are being authored (red state).
const rec = await import('../reconciliation').catch(() => null as never);
const RM = rec as unknown as {
  detectLabeledCommits?: (input: {
    reviewedHeadSha: string;
    headSha: string;
    reviewedPaths: string[];
    listCommitSubjects: (
      from: string,
      to: string,
    ) => { sha: string; subject: string }[];
    listCommitFiles: (sha: string) => string[];
  }) => string[];
  parseActionableFindings?: (markdown: string) => boolean;
  parseAdvisoryObservations?: (markdown: string) => string[];
  inspectSubagentReviewEvidence?: (input: {
    repoRoot: string;
    rows: Array<{
      outcome: string;
      terminatedReason?: string;
      rawOutput?: string;
    }>;
  }) => Array<{
    kind: 'missing_report' | 'empty_report';
    rawOutput?: string;
  }>;
  reconcileReview?: (input: {
    artifactRows: Array<{ outcome: string; reviewedHeadSha?: string }>;
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
  }) =>
    | { kind: 'clean' }
    | { kind: 'patched'; commitShas: string[] }
    | { kind: 'blocked'; condition: 'A' | 'B'; message: string };
  RECONCILIATION_BLOCKED_MESSAGE_A?: string;
  RECONCILIATION_BLOCKED_MESSAGE_B?: string;
  ReconciliationBlockedError?: new (
    condition: 'A' | 'B',
    message: string,
  ) => Error & { condition: 'A' | 'B' };
  recordDeferred?: (input: {
    artifactPath: string;
    ticket: string;
    reviewedHeadSha: string;
    reason: string;
    primaryAgent?: string;
  }) => void;
  recordAcknowledgment?: (input: {
    artifactPath: string;
    ticket: string;
    reviewedHeadSha: string;
    variant: 'patched' | 'deferred' | 'clean';
    commitSha?: string;
    reason?: string;
    primaryAgent?: string;
  }) => void;
};

function freshArtifact(ticket: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'p14-03-reconciliation-'));
  const path = join(dir, `${ticket}-subagent-review.ledger.json`);
  const initial = {
    ticket,
    invocations: [
      {
        runnerKind: 'claude-cli',
        reviewedHeadSha: 'reviewedsha000',
        outcome: 'clean',
        completedAt: '2026-05-22T00:00:00.000Z',
        terminatedReason: 'completed',
        findings: [],
        probedSurfaces: [],
        patches: [],
        schemaVersion: 1,
        primaryAgent: 'claude',
        runnerSelfReport: 'completed',
        fallbackFrom: null,
      },
    ],
  };
  writeFileSync(path, JSON.stringify(initial, null, 2) + '\n', 'utf-8');
  return path;
}

function readArtifact(path: string): {
  ticket: string;
  invocations: Array<Record<string, unknown>>;
} {
  return JSON.parse(readFileSync(path, 'utf-8'));
}

describe('P14.03 — detectLabeledCommits', () => {
  it('returns commit SHAs of [subagent-review]-labeled commits that touch reviewed paths', () => {
    expect(RM.detectLabeledCommits).toBeDefined();
    const result = RM.detectLabeledCommits!({
      reviewedHeadSha: 'rev0',
      headSha: 'head0',
      reviewedPaths: ['src/foo.ts', 'src/bar.ts'],
      listCommitSubjects: () => [
        { sha: 'abc1', subject: 'fix(F): patch [subagent-review]' },
        { sha: 'def2', subject: 'chore: tidy' },
        { sha: 'ghi3', subject: 'feat: B [subagent-review]' },
      ],
      listCommitFiles: (sha) =>
        sha === 'abc1'
          ? ['src/foo.ts']
          : sha === 'ghi3'
            ? ['src/bar.ts']
            : ['unrelated.txt'],
    });
    expect(result).toEqual(['abc1', 'ghi3']);
  });

  it('returns empty when no labeled commit touches reviewed paths', () => {
    expect(RM.detectLabeledCommits).toBeDefined();
    const result = RM.detectLabeledCommits!({
      reviewedHeadSha: 'rev0',
      headSha: 'head0',
      reviewedPaths: ['src/foo.ts'],
      listCommitSubjects: () => [
        { sha: 'a', subject: 'fix: x' },
        { sha: 'b', subject: 'chore: y' },
      ],
      listCommitFiles: () => ['src/foo.ts'],
    });
    expect(result).toEqual([]);
  });

  it('ignores labeled commits that do not touch reviewed paths', () => {
    expect(RM.detectLabeledCommits).toBeDefined();
    const result = RM.detectLabeledCommits!({
      reviewedHeadSha: 'rev0',
      headSha: 'head0',
      reviewedPaths: ['src/foo.ts'],
      listCommitSubjects: () => [
        { sha: 'a', subject: 'docs: unrelated [subagent-review]' },
      ],
      listCommitFiles: () => ['docs/README.md'],
    });
    expect(result).toEqual([]);
  });
});

describe('P14.03 — parseActionableFindings', () => {
  it('returns false when section says None.', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `**Actionable findings**\nNone.\n\n**Findings for human review**`;
    expect(RM.parseActionableFindings!(md)).toBe(false);
  });

  it('returns true when section has content', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `**Actionable findings**\n\n- file.ts: bug here\n\n**Findings for human review**`;
    expect(RM.parseActionableFindings!(md)).toBe(true);
  });

  it('tolerates minor format variations (extra blank lines, trailing whitespace)', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `**Actionable findings**   \n\n\nNone.   \n`;
    expect(RM.parseActionableFindings!(md)).toBe(false);
  });

  it('treats missing section as false (no findings)', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    expect(RM.parseActionableFindings!('Some prose without the section')).toBe(
      false,
    );
  });

  it('accepts ATX heading drift for actionable findings', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `## Actionable findings\n\n- src/foo.ts: bug here\n\n## Advisory Observations\nNone.`;
    expect(RM.parseActionableFindings!(md)).toBe(true);
  });

  it('does not treat inline bold prose as an actionable findings section', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md =
      'The phrase **Actionable findings** appears inline, but this is not a report section.';
    expect(RM.parseActionableFindings!(md)).toBe(false);
  });
});

describe('P16.01 — parseAdvisoryObservations', () => {
  it('returns bullet items from the Advisory Observations section', () => {
    expect(RM.parseAdvisoryObservations).toBeDefined();
    const md = `**Actionable findings**\nNone.\n\n**Advisory Observations**\n\n- docs: consider clarifying closeout timing.\n- tools: future command should share parser logic.\n\n**Runner status**\ncompleted`;
    expect(RM.parseAdvisoryObservations!(md)).toEqual([
      'docs: consider clarifying closeout timing.',
      'tools: future command should share parser logic.',
    ]);
  });

  it('returns prose paragraphs from the Advisory Observations section', () => {
    expect(RM.parseAdvisoryObservations).toBeDefined();
    const md = `**Advisory Observations**\n\nThe parser should keep this as a triageable note.\n\nA second paragraph remains a separate observation.\n\n**Runner status**\ncompleted`;
    expect(RM.parseAdvisoryObservations!(md)).toEqual([
      'The parser should keep this as a triageable note.',
      'A second paragraph remains a separate observation.',
    ]);
  });

  it('returns empty when Advisory Observations says None.', () => {
    expect(RM.parseAdvisoryObservations).toBeDefined();
    const md = `**Advisory Observations**\n\nNone.\n\n**Runner status**\ncompleted`;
    expect(RM.parseAdvisoryObservations!(md)).toEqual([]);
  });

  it('returns empty when Advisory Observations is missing', () => {
    expect(RM.parseAdvisoryObservations).toBeDefined();
    const md = `**Actionable findings**\nNone.\n\n**Runner status**\ncompleted`;
    expect(RM.parseAdvisoryObservations!(md)).toEqual([]);
  });

  it('does not treat advisory observations as actionable findings', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    expect(RM.parseAdvisoryObservations).toBeDefined();
    const md = `**Actionable findings**\nNone.\n\n**Advisory Observations**\n\n- This is triageable later, but not blocking.\n`;
    expect(RM.parseActionableFindings!(md)).toBe(false);
    expect(RM.parseAdvisoryObservations!(md)).toEqual([
      'This is triageable later, but not blocking.',
    ]);
  });

  it('accepts ATX heading drift for advisory observations', () => {
    expect(RM.parseAdvisoryObservations).toBeDefined();
    const md = `## Actionable findings\nNone.\n\n## Advisory Observations\n\n- Keep this note triageable.\n\n## Runner status\ncompleted`;
    expect(RM.parseAdvisoryObservations!(md)).toEqual([
      'Keep this note triageable.',
    ]);
  });

  it('does not treat bold observation-prefix lines as section terminators', () => {
    // Regression: in Phase 05 P5.06 the subagent used `**A1 — Title**` as an
    // observation prefix inside the Advisory Observations section. The prior
    // parser called isSectionHeadingLine() on every line and terminated the
    // section extraction at `**A1 — ...**`, silently dropping every
    // observation. Only canonical sibling headings should terminate the body.
    // The canonical report template instructs the subagent to keep each
    // observation as one bullet or one paragraph — the test below verifies the
    // parser preserves all content under that mixed-bold format rather than
    // truncating at the first bold line.
    expect(RM.parseAdvisoryObservations).toBeDefined();
    const md = [
      '**Actionable findings**',
      'None.',
      '',
      '**Advisory Observations**',
      '',
      '**A1 — getEvent fallback logic**',
      '',
      'The fallback returns nil silently when the event row is missing.',
      '',
      '**A2 — Schema drift in event types**',
      '',
      'The EventV2 type does not match the migration in 0042.',
      '',
      '**Runner termination**',
      'completed',
    ].join('\n');
    const observations = RM.parseAdvisoryObservations!(md);
    // Crucial: the parser must not return [] (the pre-fix behavior). With
    // mixed-bold content it returns all paragraphs in the section body, which
    // the canonical report template avoids by recommending one paragraph or
    // bullet per observation.
    expect(observations.length).toBeGreaterThan(0);
    const joined = observations.join('\n');
    expect(joined).toContain('A1');
    expect(joined).toContain('fallback returns nil silently');
    expect(joined).toContain('A2');
    expect(joined).toContain('Schema drift');
    // And critically: the section did not get truncated at `**Runner termination**`.
    expect(joined).not.toContain('completed');
  });
});

describe('P16.01 — inspectSubagentReviewEvidence', () => {
  it('flags clean/completed rows with missing or empty rawOutput reports as suspicious evidence', () => {
    expect(RM.inspectSubagentReviewEvidence).toBeDefined();
    const dir = mkdtempSync(join(tmpdir(), 'p16-01-evidence-'));
    const emptyReport = join(dir, 'empty.report.md');
    writeFileSync(emptyReport, '   \n', 'utf-8');

    expect(
      RM.inspectSubagentReviewEvidence!({
        repoRoot: dir,
        rows: [
          {
            outcome: 'clean',
            terminatedReason: 'completed',
            rawOutput: 'missing.report.md',
          },
          {
            outcome: 'clean',
            terminatedReason: 'completed',
            rawOutput: 'empty.report.md',
          },
          {
            outcome: 'skipped',
            terminatedReason: 'runner_unavailable',
            rawOutput: 'also-missing.report.md',
          },
        ],
      }),
    ).toEqual([
      { kind: 'missing_report', rawOutput: 'missing.report.md' },
      { kind: 'empty_report', rawOutput: 'empty.report.md' },
    ]);
  });
});

describe('P14.03 — reconcileReview', () => {
  const baseInput = {
    artifactRows: [{ outcome: 'clean', reviewedHeadSha: 'rev0' }],
    reportMarkdown: '**Actionable findings**\nNone.\n',
    reviewedHeadSha: 'rev0',
    headSha: 'head0',
    reviewedPaths: ['src/foo.ts'],
    listCommitSubjects: () => [],
    listCommitFiles: () => [] as string[],
    listChangedPathsInRange: () => [] as string[],
  };

  it('returns { kind: "clean" } when nothing was modified and no findings', () => {
    expect(RM.reconcileReview).toBeDefined();
    expect(RM.reconcileReview!(baseInput)).toEqual({ kind: 'clean' });
  });

  it('returns { kind: "patched", commitShas } when [subagent-review] commits touched reviewed paths', () => {
    expect(RM.reconcileReview).toBeDefined();
    const result = RM.reconcileReview!({
      ...baseInput,
      listCommitSubjects: () => [
        { sha: 'fix1', subject: 'fix: patch [subagent-review]' },
        { sha: 'fix2', subject: 'feat: more [subagent-review]' },
      ],
      listCommitFiles: () => ['src/foo.ts'],
      listChangedPathsInRange: () => ['src/foo.ts'],
    });
    expect(result).toEqual({ kind: 'patched', commitShas: ['fix1', 'fix2'] });
  });

  it('returns Condition A blocked when reviewed paths modified, no labeled commit, no deferred row', () => {
    expect(RM.reconcileReview).toBeDefined();
    const result = RM.reconcileReview!({
      ...baseInput,
      listChangedPathsInRange: () => ['src/foo.ts'],
      listCommitSubjects: () => [{ sha: 'x1', subject: 'fix: no label' }],
      listCommitFiles: () => ['src/foo.ts'],
    });
    expect(result.kind).toBe('blocked');
    if (result.kind !== 'blocked') return;
    expect(result.condition).toBe('A');
    expect(result.message).toBe(RM.RECONCILIATION_BLOCKED_MESSAGE_A);
  });

  it('returns Condition B blocked when actionable findings exist with no commit and no deferred row', () => {
    expect(RM.reconcileReview).toBeDefined();
    const result = RM.reconcileReview!({
      ...baseInput,
      reportMarkdown:
        '**Actionable findings**\n\n- src/foo.ts: missing null-check\n\n**Findings for human review**\nNone.\n',
    });
    expect(result.kind).toBe('blocked');
    if (result.kind !== 'blocked') return;
    expect(result.condition).toBe('B');
    expect(result.message).toBe(RM.RECONCILIATION_BLOCKED_MESSAGE_B);
  });

  it('does NOT block when a deferred row already exists for the same reviewedHeadSha', () => {
    expect(RM.reconcileReview).toBeDefined();
    const result = RM.reconcileReview!({
      ...baseInput,
      artifactRows: [
        { outcome: 'clean', reviewedHeadSha: 'rev0' },
        { outcome: 'deferred', reviewedHeadSha: 'rev0' },
      ],
      listChangedPathsInRange: () => ['src/foo.ts'],
      listCommitSubjects: () => [{ sha: 'x1', subject: 'fix: no label' }],
      listCommitFiles: () => ['src/foo.ts'],
    });
    expect(result.kind).toBe('clean');
  });
});

describe('P14.03 — recordDeferred', () => {
  it('appends a deferred row with the reason captured', () => {
    expect(RM.recordDeferred).toBeDefined();
    const path = freshArtifact('P14.03');
    RM.recordDeferred!({
      artifactPath: path,
      ticket: 'P14.03',
      reviewedHeadSha: 'rev0',
      reason: 'External vendor will catch this on the open PR.',
      primaryAgent: 'claude',
    });
    const a = readArtifact(path);
    const last = a.invocations[a.invocations.length - 1]!;
    expect(last['outcome']).toBe('deferred');
    expect(last['reason']).toBe(
      'External vendor will catch this on the open PR.',
    );
    expect(last['primaryAgent']).toBe('claude');
  });

  it('rejects empty reason', () => {
    expect(RM.recordDeferred).toBeDefined();
    const path = freshArtifact('P14.03');
    expect(() =>
      RM.recordDeferred!({
        artifactPath: path,
        ticket: 'P14.03',
        reviewedHeadSha: 'rev0',
        reason: '',
      }),
    ).toThrow(/reason/);
  });

  it('rejects whitespace-only reason', () => {
    expect(RM.recordDeferred).toBeDefined();
    const path = freshArtifact('P14.03');
    expect(() =>
      RM.recordDeferred!({
        artifactPath: path,
        ticket: 'P14.03',
        reviewedHeadSha: 'rev0',
        reason: '    ',
      }),
    ).toThrow(/reason/);
  });
});

describe('P14.03 — recordAcknowledgment', () => {
  it('--ack-reconciliation patched --commit <sha> appends patched row with the SHA', () => {
    expect(RM.recordAcknowledgment).toBeDefined();
    const path = freshArtifact('P14.03');
    RM.recordAcknowledgment!({
      artifactPath: path,
      ticket: 'P14.03',
      reviewedHeadSha: 'rev0',
      variant: 'patched',
      commitSha: 'operator-supplied-sha',
    });
    const a = readArtifact(path);
    const last = a.invocations[a.invocations.length - 1]!;
    expect(last['outcome']).toBe('patched');
    expect(last['patches']).toEqual(['operator-supplied-sha']);
  });

  it('--ack-reconciliation deferred --reason "X" appends deferred row', () => {
    expect(RM.recordAcknowledgment).toBeDefined();
    const path = freshArtifact('P14.03');
    RM.recordAcknowledgment!({
      artifactPath: path,
      ticket: 'P14.03',
      reviewedHeadSha: 'rev0',
      variant: 'deferred',
      reason: 'follow-up captured in ticket',
    });
    const a = readArtifact(path);
    const last = a.invocations[a.invocations.length - 1]!;
    expect(last['outcome']).toBe('deferred');
    expect(last['reason']).toBe('follow-up captured in ticket');
  });

  it('--ack-reconciliation clean --reason "X" appends clean row with acknowledgment field', () => {
    expect(RM.recordAcknowledgment).toBeDefined();
    const path = freshArtifact('P14.03');
    RM.recordAcknowledgment!({
      artifactPath: path,
      ticket: 'P14.03',
      reviewedHeadSha: 'rev0',
      variant: 'clean',
      reason: 'modification was unrelated whitespace cleanup',
    });
    const a = readArtifact(path);
    const last = a.invocations[a.invocations.length - 1]!;
    expect(last['outcome']).toBe('clean');
    expect(last['acknowledgment']).toBe('operator-confirmed-clean');
    expect(last['reason']).toBe(
      'modification was unrelated whitespace cleanup',
    );
  });

  it('--ack-reconciliation patched requires --commit', () => {
    expect(RM.recordAcknowledgment).toBeDefined();
    const path = freshArtifact('P14.03');
    expect(() =>
      RM.recordAcknowledgment!({
        artifactPath: path,
        ticket: 'P14.03',
        reviewedHeadSha: 'rev0',
        variant: 'patched',
      }),
    ).toThrow(/commit/);
  });

  it('--ack-reconciliation clean requires non-empty --reason', () => {
    expect(RM.recordAcknowledgment).toBeDefined();
    const path = freshArtifact('P14.03');
    expect(() =>
      RM.recordAcknowledgment!({
        artifactPath: path,
        ticket: 'P14.03',
        reviewedHeadSha: 'rev0',
        variant: 'clean',
        reason: '   ',
      }),
    ).toThrow(/reason/);
  });

  it('--ack-reconciliation deferred requires non-empty --reason', () => {
    expect(RM.recordAcknowledgment).toBeDefined();
    const path = freshArtifact('P14.03');
    expect(() =>
      RM.recordAcknowledgment!({
        artifactPath: path,
        ticket: 'P14.03',
        reviewedHeadSha: 'rev0',
        variant: 'deferred',
        reason: '   ',
      }),
    ).toThrow(/reason/);
  });
});
