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
          sourceReportPath,
          ticketId: 'P16.01',
          observationText:
            'Consider documenting the closeout operator decision.',
          disposition: 'converted-to-ticket',
          rationale: 'Tracked in the docs ticket.',
          followUpReference:
            'docs/product/delivery/phase-16/ticket-05-docs-soa-wrapper-guidance-and-retrospective.md',
        },
        {
          sourceReportPath,
          ticketId: 'P16.01',
          observationText: 'Keep this flow post-phase only.',
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
      ) as { observations: Array<{ observationText: string }> };
      expect(
        artifact.observations.map((entry) => entry.observationText),
      ).toEqual([
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
            sourceReportPath,
            ticketId: 'P16.01',
            observationText: 'Consider a follow-up dashboard.',
            disposition: 'deferred',
            rationale: 'Out of scope for this phase.',
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
          sourceReportPath,
          ticketId: 'P16.01',
          observationText: 'Already tracked elsewhere.',
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
      ) as { observations: unknown[] };
      expect(artifact.observations).toHaveLength(1);
    });
  });
});
