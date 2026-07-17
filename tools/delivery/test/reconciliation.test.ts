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
  parseActionableFindings?: (markdown: string) => {
    found: boolean;
    closed: boolean;
    isExplicitNone: boolean;
    findings: string[];
  };
  isSuspiciousActionableFindingsParse?: (result: {
    found: boolean;
    closed: boolean;
    isExplicitNone: boolean;
    findings: string[];
  }) => boolean;
  parseAdvisoryObservations?: (markdown: string) => string[];
  parseAdvisoryObservationsResult?: (markdown: string) => {
    found: boolean;
    closed: boolean;
    isExplicitNone: boolean;
    observations: string[];
  };
  isSuspiciousAdvisoryObservationsParse?: (result: {
    found: boolean;
    closed: boolean;
    isExplicitNone: boolean;
    observations: string[];
  }) => boolean;
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
    artifactRows: Array<{
      outcome: string;
      reviewedHeadSha?: string;
      acknowledgment?: string;
    }>;
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

describe('P21.01 — parseActionableFindings (tag contract)', () => {
  it('parses a tagged block with bullets to the correct findings', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `<actionable-findings>\n- src/foo.ts: missing null-check\n- src/bar.ts: unbounded loop\n</actionable-findings>`;
    const result = RM.parseActionableFindings!(md);
    expect(result.found).toBe(true);
    expect(result.closed).toBe(true);
    expect(result.isExplicitNone).toBe(false);
    expect(result.findings).toEqual([
      'src/foo.ts: missing null-check',
      'src/bar.ts: unbounded loop',
    ]);
    expect(RM.isSuspiciousActionableFindingsParse!(result)).toBe(false);
  });

  it('treats literal None as clean-empty, not suspicious', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `<actionable-findings>\nNone\n</actionable-findings>`;
    const result = RM.parseActionableFindings!(md);
    expect(result.closed).toBe(true);
    expect(result.isExplicitNone).toBe(true);
    expect(result.findings).toEqual([]);
    expect(RM.isSuspiciousActionableFindingsParse!(result)).toBe(false);
  });

  it('parses to EOF and flags for the warning when the close tag is missing', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `<actionable-findings>\n- src/foo.ts: missing null-check\n\n<advisory-observations>\nNone\n</advisory-observations>`;
    const result = RM.parseActionableFindings!(md);
    expect(result.found).toBe(true);
    expect(result.closed).toBe(false);
    expect(RM.isSuspiciousActionableFindingsParse!(result)).toBe(true);
  });

  it('flags a misnamed tag (underscore) as 0-parse and suspicious', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `<actionable_findings>\n- src/foo.ts: missing null-check\n</actionable_findings>`;
    const result = RM.parseActionableFindings!(md);
    expect(result.found).toBe(false);
    expect(result.findings).toEqual([]);
    expect(RM.isSuspiciousActionableFindingsParse!(result)).toBe(true);
  });

  it('flags legacy **bold** heading format as 0-parse and suspicious', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `**Actionable findings**\n\n- src/foo.ts: missing null-check\n\n**Advisory Observations**\nNone.\n`;
    const result = RM.parseActionableFindings!(md);
    expect(result.found).toBe(false);
    expect(result.findings).toEqual([]);
    expect(RM.isSuspiciousActionableFindingsParse!(result)).toBe(true);
  });

  it('flags legacy ## ATX heading format as 0-parse and suspicious', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `## Actionable findings\n\n- src/foo.ts: missing null-check\n\n## Advisory Observations\nNone.\n`;
    const result = RM.parseActionableFindings!(md);
    expect(result.found).toBe(false);
    expect(RM.isSuspiciousActionableFindingsParse!(result)).toBe(true);
  });

  it('flags plain-text heading format as 0-parse and suspicious', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `Actionable findings\n\n- src/foo.ts: missing null-check\n\nAdvisory Observations\nNone.\n`;
    const result = RM.parseActionableFindings!(md);
    expect(result.found).toBe(false);
    expect(RM.isSuspiciousActionableFindingsParse!(result)).toBe(true);
  });

  it('treats a missing tag entirely as 0-parse (no findings) and suspicious', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const result = RM.parseActionableFindings!('Some prose without any tag');
    expect(result.found).toBe(false);
    expect(result.findings).toEqual([]);
    expect(RM.isSuspiciousActionableFindingsParse!(result)).toBe(true);
  });

  it('ignores runnerStatus: prose outside the tags — it cannot leak into findings', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `<actionable-findings>\nNone\n</actionable-findings>\n\nrunnerStatus: completed\nterminatedReason: finished the review`;
    const result = RM.parseActionableFindings!(md);
    expect(result.isExplicitNone).toBe(true);
    expect(result.findings).toEqual([]);
    expect(RM.isSuspiciousActionableFindingsParse!(result)).toBe(false);
  });

  it('takes the last open tag when a template skeleton example is quoted earlier', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    const md = `Example:\n<actionable-findings>\n- example finding, ignore this\n</actionable-findings>\n\nActual report:\n<actionable-findings>\n- src/real.ts: the real finding\n</actionable-findings>`;
    const result = RM.parseActionableFindings!(md);
    expect(result.findings).toEqual(['src/real.ts: the real finding']);
  });
});

describe('P21.01 — parseAdvisoryObservations (tag contract)', () => {
  it('parses a tagged block with bullets to the correct observations', () => {
    expect(RM.parseAdvisoryObservations).toBeDefined();
    const md = `<advisory-observations>\n- docs: consider clarifying closeout timing.\n- tools: future command should share parser logic.\n</advisory-observations>`;
    expect(RM.parseAdvisoryObservations!(md)).toEqual([
      'docs: consider clarifying closeout timing.',
      'tools: future command should share parser logic.',
    ]);
  });

  it('treats literal None as clean-empty, no warning', () => {
    expect(RM.parseAdvisoryObservationsResult).toBeDefined();
    const md = `<advisory-observations>\nNone\n</advisory-observations>`;
    const result = RM.parseAdvisoryObservationsResult!(md);
    expect(result.isExplicitNone).toBe(true);
    expect(result.observations).toEqual([]);
    expect(RM.isSuspiciousAdvisoryObservationsParse!(result)).toBe(false);
  });

  it('parses to EOF and flags for the warning when the close tag is missing', () => {
    expect(RM.parseAdvisoryObservationsResult).toBeDefined();
    const md = `<advisory-observations>\n- docs: consider clarifying closeout timing.`;
    const result = RM.parseAdvisoryObservationsResult!(md);
    expect(result.closed).toBe(false);
    expect(RM.isSuspiciousAdvisoryObservationsParse!(result)).toBe(true);
  });

  it('flags a misnamed tag (underscore) as 0-parse and suspicious', () => {
    expect(RM.parseAdvisoryObservationsResult).toBeDefined();
    const md = `<advisory_observations>\n- docs: consider clarifying closeout timing.\n</advisory_observations>`;
    const result = RM.parseAdvisoryObservationsResult!(md);
    expect(result.found).toBe(false);
    expect(result.observations).toEqual([]);
    expect(RM.isSuspiciousAdvisoryObservationsParse!(result)).toBe(true);
  });

  it('flags legacy **bold** heading format as 0-parse and suspicious', () => {
    expect(RM.parseAdvisoryObservationsResult).toBeDefined();
    const md = `**Advisory Observations**\n\n- docs: consider clarifying closeout timing.\n`;
    const result = RM.parseAdvisoryObservationsResult!(md);
    expect(result.found).toBe(false);
    expect(RM.isSuspiciousAdvisoryObservationsParse!(result)).toBe(true);
  });

  it('flags legacy ## ATX heading format as 0-parse and suspicious', () => {
    expect(RM.parseAdvisoryObservationsResult).toBeDefined();
    const md = `## Advisory Observations\n\n- docs: consider clarifying closeout timing.\n`;
    const result = RM.parseAdvisoryObservationsResult!(md);
    expect(result.found).toBe(false);
    expect(RM.isSuspiciousAdvisoryObservationsParse!(result)).toBe(true);
  });

  it('flags plain-text heading format as 0-parse and suspicious', () => {
    expect(RM.parseAdvisoryObservationsResult).toBeDefined();
    const md = `Advisory Observations\n\n- docs: consider clarifying closeout timing.\n`;
    const result = RM.parseAdvisoryObservationsResult!(md);
    expect(result.found).toBe(false);
    expect(RM.isSuspiciousAdvisoryObservationsParse!(result)).toBe(true);
  });

  it('returns empty when the tag is missing entirely', () => {
    expect(RM.parseAdvisoryObservations).toBeDefined();
    const md = `<actionable-findings>\nNone\n</actionable-findings>`;
    expect(RM.parseAdvisoryObservations!(md)).toEqual([]);
  });

  it('does not treat advisory observations as actionable findings', () => {
    expect(RM.parseActionableFindings).toBeDefined();
    expect(RM.parseAdvisoryObservations).toBeDefined();
    const md = `<actionable-findings>\nNone\n</actionable-findings>\n\n<advisory-observations>\n- This is triageable later, but not blocking.\n</advisory-observations>`;
    expect(RM.parseActionableFindings!(md).findings).toEqual([]);
    expect(RM.parseAdvisoryObservations!(md)).toEqual([
      'This is triageable later, but not blocking.',
    ]);
  });

  it('ignores runnerStatus: prose outside the tags — it cannot leak into observations', () => {
    expect(RM.parseAdvisoryObservations).toBeDefined();
    const md = `<advisory-observations>\n- a real observation\n</advisory-observations>\n\nrunnerStatus: completed\nterminatedReason: finished the review`;
    expect(RM.parseAdvisoryObservations!(md)).toEqual(['a real observation']);
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
    reportMarkdown: '<actionable-findings>\nNone\n</actionable-findings>\n',
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
        '<actionable-findings>\n- src/foo.ts: missing null-check\n</actionable-findings>\n',
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

  it('does NOT block Condition A when a clean-variant acknowledgment row already exists for the same reviewedHeadSha', () => {
    expect(RM.reconcileReview).toBeDefined();
    const result = RM.reconcileReview!({
      ...baseInput,
      artifactRows: [
        { outcome: 'clean', reviewedHeadSha: 'rev0' },
        {
          outcome: 'clean',
          reviewedHeadSha: 'rev0',
          acknowledgment: 'operator-confirmed-clean',
        },
      ],
      listChangedPathsInRange: () => ['src/foo.ts'],
      listCommitSubjects: () => [{ sha: 'x1', subject: 'fix: no label' }],
      listCommitFiles: () => ['src/foo.ts'],
    });
    expect(result.kind).toBe('clean');
  });

  it('does NOT block Condition B when a clean-variant acknowledgment row already exists for the same reviewedHeadSha', () => {
    expect(RM.reconcileReview).toBeDefined();
    const result = RM.reconcileReview!({
      ...baseInput,
      reportMarkdown:
        '<actionable-findings>\n- src/foo.ts: missing null-check\n</actionable-findings>\n',
      artifactRows: [
        { outcome: 'clean', reviewedHeadSha: 'rev0' },
        {
          outcome: 'clean',
          reviewedHeadSha: 'rev0',
          acknowledgment: 'operator-confirmed-clean',
        },
      ],
    });
    expect(result.kind).toBe('clean');
  });

  it('still blocks Condition B when the clean row is unacknowledged (plain runner "clean" outcome, no operator ack)', () => {
    expect(RM.reconcileReview).toBeDefined();
    const result = RM.reconcileReview!({
      ...baseInput,
      reportMarkdown:
        '<actionable-findings>\n- src/foo.ts: missing null-check\n</actionable-findings>\n',
      artifactRows: [{ outcome: 'clean', reviewedHeadSha: 'rev0' }],
    });
    expect(result.kind).toBe('blocked');
    if (result.kind !== 'blocked') return;
    expect(result.condition).toBe('B');
  });

  it('blocks Condition B when a closed, non-empty, non-None actionable-findings tag contains prose instead of bullets', () => {
    // Regression: the bullet-only tag extractor has no prose fallback by
    // design, so `findings.length > 0` alone let a real finding written as
    // prose (not `- ` bulleted) inside a properly closed tag silently pass
    // reconciliation as clean. Found dogfooding P21.01's own adversarial
    // review — the subagent's real report had this exact shape.
    expect(RM.reconcileReview).toBeDefined();
    const result = RM.reconcileReview!({
      ...baseInput,
      reportMarkdown:
        '<actionable-findings>\nThis is a real finding written as a paragraph, not a bullet.\n</actionable-findings>\n',
    });
    expect(result.kind).toBe('blocked');
    if (result.kind !== 'blocked') return;
    expect(result.condition).toBe('B');
  });

  it('blocks Condition B when the actionable-findings tag is missing entirely from a non-empty report', () => {
    expect(RM.reconcileReview).toBeDefined();
    const result = RM.reconcileReview!({
      ...baseInput,
      reportMarkdown: '**Invariant results**\n1. held.\n',
    });
    expect(result.kind).toBe('blocked');
    if (result.kind !== 'blocked') return;
    expect(result.condition).toBe('B');
  });

  it('does NOT block when reportMarkdown is empty (operator-recorder path — no runner invoked, no report file)', () => {
    expect(RM.reconcileReview).toBeDefined();
    const result = RM.reconcileReview!({
      ...baseInput,
      reportMarkdown: '',
    });
    expect(result).toEqual({ kind: 'clean' });
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
