import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import {
  computeAdvisoryObservationWarnings,
  formatAdvisoryObservationWarnings,
} from '../advisory-observation-warnings';
import { formatCloseoutSummary } from '../closeout-stack';
import { reconcileReview } from '../reconciliation';
import type { DeliveryState, TicketState } from '../types';

const PLAN_KEY = 'phase-16';
const REVIEWS_DIR = `docs/product/delivery/${PLAN_KEY}/reviews`;

function createTicket(overrides: Partial<TicketState>): TicketState {
  return {
    id: 'P16.01',
    title: 'Parse Advisory Observations and Report Evidence',
    slug: 'parse-advisory-observations-and-report-evidence',
    ticketFile:
      'docs/product/delivery/phase-16/ticket-01-parse-advisory-observations-and-report-evidence.md',
    type: 'feat',
    scope: 'delivery',
    redPolicy: 'required',
    status: 'done',
    branch: 'agents/p16-01-parse-advisory-observations-and-report-evidence',
    baseBranch: 'main',
    worktreePath: '/tmp/p16-01',
    prNumber: 63,
    prUrl: 'https://github.com/example/repo/pull/63',
    subagentRunnerArtifactPath: `${REVIEWS_DIR}/P16.01-subagent-review.ledger.json`,
    ...overrides,
  };
}

function createState(tickets: TicketState[]): DeliveryState {
  return {
    planKey: PLAN_KEY,
    planPath: `docs/product/delivery/${PLAN_KEY}/implementation-plan.md`,
    statePath: `.agents/delivery/${PLAN_KEY}/state.json`,
    reviewsDirPath: REVIEWS_DIR,
    handoffsDirPath: `.agents/delivery/${PLAN_KEY}/handoffs`,
    reviewPollIntervalMinutes: 6,
    reviewPollMaxWaitMinutes: 12,
    tickets,
  };
}

async function withRepo<T>(fn: (repoRoot: string) => Promise<T>): Promise<T> {
  const repoRoot = await mkdtemp(join(tmpdir(), 'p16-04-'));
  try {
    return await fn(repoRoot);
  } finally {
    await rm(repoRoot, { force: true, recursive: true });
  }
}

async function writeSubagentArtifacts(input: {
  repoRoot: string;
  report?: string;
  ticketId?: string;
}): Promise<string> {
  const ticketId = input.ticketId ?? 'P16.01';
  const reportPath = `${REVIEWS_DIR}/${ticketId}-subagent-review.report.md`;
  const ledgerPath = `${REVIEWS_DIR}/${ticketId}-subagent-review.ledger.json`;
  await mkdir(join(input.repoRoot, REVIEWS_DIR), { recursive: true });
  if (input.report !== undefined) {
    await writeFile(join(input.repoRoot, reportPath), input.report, 'utf8');
  }
  await writeFile(
    join(input.repoRoot, ledgerPath),
    `${JSON.stringify({
      ticket: ticketId,
      invocations: [
        {
          runnerKind: 'codex-cli',
          outcome: 'clean',
          reviewedHeadSha: '0123456789abcdef0123456789abcdef01234567',
          terminatedReason: 'completed',
          rawOutput: reportPath,
        },
      ],
    })}\n`,
    'utf8',
  );
  return reportPath;
}

describe('P16.04 advisory observation warnings', () => {
  it('emits a warning for completed phases with untriaged advisory observations', async () => {
    await withRepo(async (repoRoot) => {
      const reportPath = await writeSubagentArtifacts({
        repoRoot,
        report: [
          '## Actionable findings',
          'None.',
          '',
          '## Advisory Observations',
          '',
          '- Record this operator decision after closeout.',
          '',
        ].join('\n'),
      });

      const warnings = await computeAdvisoryObservationWarnings({
        repoRoot,
        state: createState([createTicket({})]),
      });

      expect(warnings).toEqual([
        {
          kind: 'untriaged_observation',
          ticketId: 'P16.01',
          sourceReportPath: reportPath,
          observationText: 'Record this operator decision after closeout.',
        },
      ]);
    });
  });

  it('does not warn when all advisory observations have dispositions', async () => {
    await withRepo(async (repoRoot) => {
      const reportPath = await writeSubagentArtifacts({
        repoRoot,
        report: [
          '## Actionable findings',
          'None.',
          '',
          '## Advisory Observations',
          '',
          '- Already covered elsewhere.',
          '',
        ].join('\n'),
      });
      await writeFile(
        join(
          repoRoot,
          `docs/product/delivery/${PLAN_KEY}/advisory-observation-triage.json`,
        ),
        `${JSON.stringify({
          schemaVersion: 1,
          recordedAt: '2026-05-24T00:00:00.000Z',
          observations: [
            {
              sourceReportPath: reportPath,
              ticketId: 'P16.01',
              observationText: 'Already covered elsewhere.',
              disposition: 'already-covered',
              rationale: 'Covered by the closeout checklist.',
            },
          ],
        })}\n`,
        'utf8',
      );

      const warnings = await computeAdvisoryObservationWarnings({
        repoRoot,
        state: createState([createTicket({})]),
      });

      expect(warnings).toEqual([]);
    });
  });

  it('emits suspicious-evidence warnings for clean completed rows with missing report prose', async () => {
    await withRepo(async (repoRoot) => {
      await writeSubagentArtifacts({ repoRoot });

      const warnings = await computeAdvisoryObservationWarnings({
        repoRoot,
        state: createState([createTicket({})]),
      });

      expect(warnings).toEqual([
        {
          kind: 'suspicious_evidence',
          ticketId: 'P16.01',
          evidenceKind: 'missing_report',
          rawOutput: `${REVIEWS_DIR}/P16.01-subagent-review.report.md`,
        },
      ]);
    });
  });

  it('surfaces advisory-observation warnings in closeout summary output', () => {
    const state = createState([createTicket({})]);
    const output = formatCloseoutSummary(
      { merged: [], skippedMerged: [] },
      state,
      {
        defaultBranch: 'main',
        planRoot: 'docs',
        runtime: 'bun',
        packageManager: 'bun',
        ticketBoundaryMode: 'cook',
        reviewPolicy: { subagentReview: 'skip_doc_only', prReview: 'disabled' },
        prReviewAgents: [],
      },
      [
        {
          kind: 'untriaged_observation',
          ticketId: 'P16.01',
          sourceReportPath: `${REVIEWS_DIR}/P16.01-subagent-review.report.md`,
          observationText: 'Record this operator decision after closeout.',
        },
      ],
    );

    expect(output).toContain('Advisory Observation Warnings');
    expect(output).toContain('P16.01');
    expect(output).toContain('Record this operator decision after closeout.');
  });

  it('keeps reconcile-subagent-review non-blocking for advisory observations', () => {
    const result = reconcileReview({
      artifactRows: [],
      reportMarkdown: [
        '## Actionable findings',
        'None.',
        '',
        '## Advisory Observations',
        '',
        '- This needs post-phase triage, not pre-PR blocking.',
        '',
      ].join('\n'),
      reviewedHeadSha: 'aaa',
      headSha: 'aaa',
      reviewedPaths: ['tools/delivery/reconciliation.ts'],
      listCommitSubjects: () => [],
      listCommitFiles: () => [],
      listChangedPathsInRange: () => [],
    });

    expect(result).toEqual({ kind: 'clean' });
  });

  it('formats advisory-observation warnings for operators', () => {
    expect(
      formatAdvisoryObservationWarnings([
        {
          kind: 'suspicious_evidence',
          ticketId: 'P16.01',
          evidenceKind: 'empty_report',
          rawOutput: `${REVIEWS_DIR}/P16.01-subagent-review.report.md`,
        },
      ]),
    ).toContain('empty_report');
  });

  it('formats advisory warning computation failures as non-blocking warnings', () => {
    expect(
      formatAdvisoryObservationWarnings([
        {
          kind: 'warning_error',
          message: 'Malformed advisory-observation triage artifact.',
        },
      ]),
    ).toContain('warning computation failed');
  });
});
