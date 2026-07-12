import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import { getUsage, parseCliArgs } from '../cli';
import {
  runAdvisoryObservationTriage,
  type AdvisoryObservationDispositionInput,
} from '../advisory-observation-command';
import type { DeliveryState } from '../types';

const PLAN_KEY = 'phase-16';
const REVIEWS_DIR = `docs/product/delivery/${PLAN_KEY}/reviews`;
const TRIAGE_ARTIFACT = `docs/product/delivery/${PLAN_KEY}/advisory-observation-triage.json`;

function makeState(repoRoot: string): DeliveryState {
  return {
    planKey: PLAN_KEY,
    planPath: `docs/product/delivery/${PLAN_KEY}/implementation-plan.md`,
    statePath: `.agents/delivery/${PLAN_KEY}/state.json`,
    reviewsDirPath: REVIEWS_DIR,
    handoffsDirPath: `.agents/delivery/${PLAN_KEY}/handoffs`,
    reviewPollIntervalMinutes: 6,
    reviewPollMaxWaitMinutes: 12,
    tickets: [
      {
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
        worktreePath: repoRoot,
        subagentRunnerArtifactPath: `${REVIEWS_DIR}/P16.01-subagent-review.ledger.json`,
      },
    ],
  };
}

async function writeSubagentArtifacts(
  repoRoot: string,
  ticketId: string,
  report: string,
): Promise<string> {
  const reportPath = `${REVIEWS_DIR}/${ticketId}-subagent-review.report.md`;
  const ledgerPath = `${REVIEWS_DIR}/${ticketId}-subagent-review.ledger.json`;
  await mkdir(join(repoRoot, REVIEWS_DIR), { recursive: true });
  await writeFile(join(repoRoot, reportPath), report, 'utf8');
  await writeFile(
    join(repoRoot, ledgerPath),
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

async function withRepo<T>(fn: (repoRoot: string) => Promise<T>): Promise<T> {
  const repoRoot = await mkdtemp(join(tmpdir(), 'p16-03-'));
  try {
    return await fn(repoRoot);
  } finally {
    await rm(repoRoot, { force: true, recursive: true });
  }
}

describe('P16.03 advisory observation triage command', () => {
  it('lists and parses triage-advisory-observations', () => {
    const usage = getUsage('bun run deliver');
    expect(usage).toContain('triage-advisory-observations');

    const parsed = parseCliArgs(
      [
        '--plan',
        'docs/product/delivery/phase-16/implementation-plan.md',
        'triage-advisory-observations',
        '--dispositions',
        'decisions.json',
      ],
      usage,
    );

    expect(parsed.command).toBe('triage-advisory-observations');
    expect(parsed.dispositionsPath).toBe('decisions.json');
  });

  it('groups advisory observations by ticket and writes the triage artifact', async () => {
    await withRepo(async (repoRoot) => {
      const sourceReportPath = await writeSubagentArtifacts(
        repoRoot,
        'P16.01',
        [
          '**Actionable findings**',
          'None.',
          '',
          '**Advisory Observations**',
          '- Consider documenting the closeout operator decision.',
          '- Keep this flow post-phase only.',
          '',
        ].join('\n'),
      );
      const dispositions: AdvisoryObservationDispositionInput[] = [
        {
          source: { reportPath: sourceReportPath, ticketId: 'P16.01' },
          observation: 'Consider documenting the closeout operator decision.',
          disposition: 'rejected',
          rationale:
            'Filed as a follow-up ticket; not patched in this triage pass.',
          followUpReference:
            'docs/product/delivery/phase-16/ticket-05-docs-soa-wrapper-guidance-and-retrospective.md',
        },
        {
          source: { reportPath: sourceReportPath, ticketId: 'P16.01' },
          observation: 'Keep this flow post-phase only.',
          disposition: 'already-covered',
          rationale: 'The implementation plan locks this as post-phase.',
        },
      ];

      const result = await runAdvisoryObservationTriage({
        repoRoot,
        state: makeState(repoRoot),
        dispositions,
      });

      expect(result.groups).toEqual([
        {
          ticketId: 'P16.01',
          sourceReportPath,
          observations: [
            'Consider documenting the closeout operator decision.',
            'Keep this flow post-phase only.',
          ],
        },
      ]);
      expect(result.artifactPath).toBe(TRIAGE_ARTIFACT);

      const artifact = JSON.parse(
        await readFile(join(repoRoot, TRIAGE_ARTIFACT), 'utf8'),
      ) as {
        schemaVersion: number;
        summary: { total: number; rejected: number; 'already-covered': number };
        dispositions: Array<{ observation: string; disposition: string }>;
      };
      expect(artifact.schemaVersion).toBe(2);
      expect(artifact.summary.total).toBe(2);
      expect(artifact.summary.rejected).toBe(1);
      expect(artifact.summary['already-covered']).toBe(1);
      expect(artifact.dispositions.map((entry) => entry.observation)).toEqual([
        'Consider documenting the closeout operator decision.',
        'Keep this flow post-phase only.',
      ]);
    });
  });

  it('keeps actionable findings outside the advisory-observation disposition path', async () => {
    await withRepo(async (repoRoot) => {
      const sourceReportPath = await writeSubagentArtifacts(
        repoRoot,
        'P16.01',
        [
          '**Actionable findings**',
          '- Fix the broken state transition.',
          '',
          '**Advisory Observations**',
          '- Consider a follow-up dashboard.',
          '',
        ].join('\n'),
      );

      await runAdvisoryObservationTriage({
        repoRoot,
        state: makeState(repoRoot),
        dispositions: [
          {
            source: { reportPath: sourceReportPath, ticketId: 'P16.01' },
            observation: 'Consider a follow-up dashboard.',
            disposition: 'requires-human-review',
            rationale: 'Operator must decide whether to file a tracking issue.',
          },
        ],
      });

      const artifact = await readFile(join(repoRoot, TRIAGE_ARTIFACT), 'utf8');
      expect(artifact).toContain('Consider a follow-up dashboard.');
      expect(artifact).not.toContain('Fix the broken state transition.');
    });
  });

  it('fails clearly when advisory observations lack disposition data', async () => {
    await withRepo(async (repoRoot) => {
      await writeSubagentArtifacts(
        repoRoot,
        'P16.01',
        [
          '**Actionable findings**',
          'None.',
          '',
          '**Advisory Observations**',
          '- Needs an explicit operator decision.',
          '',
        ].join('\n'),
      );

      await expect(
        runAdvisoryObservationTriage({
          repoRoot,
          state: makeState(repoRoot),
          dispositions: [],
        }),
      ).rejects.toThrow(/Missing advisory observation disposition data/);
    });
  });

  it('is idempotent when rerun with the same disposition data', async () => {
    await withRepo(async (repoRoot) => {
      const sourceReportPath = await writeSubagentArtifacts(
        repoRoot,
        'P16.01',
        [
          '**Actionable findings**',
          'None.',
          '',
          '**Advisory Observations**',
          '- Already tracked elsewhere.',
          '',
        ].join('\n'),
      );
      const dispositions: AdvisoryObservationDispositionInput[] = [
        {
          source: { reportPath: sourceReportPath, ticketId: 'P16.01' },
          observation: 'Already tracked elsewhere.',
          disposition: 'rejected',
          rationale: 'Duplicate of an existing workflow.',
        },
      ];

      await runAdvisoryObservationTriage({
        repoRoot,
        state: makeState(repoRoot),
        dispositions,
      });
      await runAdvisoryObservationTriage({
        repoRoot,
        state: makeState(repoRoot),
        dispositions,
      });

      const artifact = JSON.parse(
        await readFile(join(repoRoot, TRIAGE_ARTIFACT), 'utf8'),
      ) as { dispositions: unknown[] };
      expect(artifact.dispositions).toHaveLength(1);
    });
  });
});
