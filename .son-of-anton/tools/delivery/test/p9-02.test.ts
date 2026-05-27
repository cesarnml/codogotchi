import { describe, expect, it } from 'bun:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { recordPostRed, recordPostVerify } from '../cli-runner';
import { createDeliveryOrchestratorContext } from '../context';
import { isLocalBranchDocOnly } from '../platform';
import type { ResolvedOrchestratorConfig } from '../runtime-config';
import type { DeliveryState } from '../types';

const baseConfig: ResolvedOrchestratorConfig = {
  defaultBranch: 'main',
  planRoot: 'docs',
  runtime: 'bun',
  packageManager: 'bun',
  ticketBoundaryMode: 'cook',
  reviewPolicy: {
    subagentReview: 'skip_doc_only',
    prReview: 'skip_doc_only',
  },
};

const baseState: DeliveryState = {
  planKey: 'phase-09',
  planPath: 'docs/product/delivery/phase-09/implementation-plan.md',
  statePath: '.agents/delivery/phase-09/state.json',
  reviewsDirPath: '.agents/delivery/phase-09/reviews',
  handoffsDirPath: '.agents/delivery/phase-09/handoffs',
  reviewPollIntervalMinutes: 6,
  reviewPollMaxWaitMinutes: 12,
  tickets: [
    {
      id: 'P9.02',
      title: 'TDD Gate Hardening',
      slug: 'tdd-gate-hardening',
      ticketFile:
        'docs/product/delivery/phase-09/ticket-02-tdd-gate-hardening.md',
      status: 'in_progress',
      branch: 'agents/p9-02-tdd-gate-hardening',
      baseBranch: 'agents/p9-01-billing-noise-pre-filter',
      worktreePath: '/tmp/p9_02',
    },
  ],
};

describe('P9.02 tdd gate hardening', () => {
  it('rejects post-verify on in_progress code tickets before post-red', async () => {
    await expect(
      recordPostVerify(baseState, undefined, 'clean', baseConfig, {
        isLocalBranchDocOnly: () => false,
      }),
    ).rejects.toThrow(/post-red/);
  });

  it('records red_complete with the red commit sha after a failing verify run', async () => {
    const nextState = await recordPostRed(
      baseState,
      'P9.02',
      createDeliveryOrchestratorContext(baseConfig),
      {
        isLocalBranchDocOnly: () => false,
        readHeadSha: () => 'abc123def456',
        readLatestCommitSubject: () => 'test(P9.02): red gate [red]',
        runVerify: () => ({ exitCode: 1, stderr: '', stdout: '' }),
      },
    );

    expect(nextState.tickets[0]).toMatchObject({
      status: 'red_complete',
      redCommitSha: 'abc123def456',
    });
  });

  it('rejects post-red when the verify run exits zero', async () => {
    await expect(
      recordPostRed(
        baseState,
        'P9.02',
        createDeliveryOrchestratorContext(baseConfig),
        {
          isLocalBranchDocOnly: () => false,
          readHeadSha: () => 'abc123def456',
          readLatestCommitSubject: () => 'test(P9.02): red gate [red]',
          runVerify: () => ({ exitCode: 0, stderr: '', stdout: '' }),
        },
      ),
    ).rejects.toThrow(/requires a failing verification run/);
  });

  it('allows post-verify after post-red on a code ticket', async () => {
    const nextState = await recordPostVerify(
      {
        ...baseState,
        tickets: baseState.tickets.map((ticket) => ({
          ...ticket,
          status: 'red_complete',
          redCommitSha: 'abc123def456',
        })),
      },
      'P9.02',
      'clean',
      baseConfig,
      {
        isLocalBranchDocOnly: () => false,
      },
    );

    expect(nextState.tickets[0]).toMatchObject({
      status: 'verified',
      verifyOutcome: 'clean',
      redCommitSha: 'abc123def456',
    });
  });

  it('rejects explicit skipped for post-verify on a code ticket', async () => {
    await expect(
      recordPostVerify(
        {
          ...baseState,
          tickets: baseState.tickets.map((ticket) => ({
            ...ticket,
            status: 'red_complete',
            redCommitSha: 'abc123def456',
          })),
        },
        'P9.02',
        'skipped',
        baseConfig,
        {
          isLocalBranchDocOnly: () => false,
        },
      ),
    ).rejects.toThrow(/cannot record `skipped`/);
  });

  it('returns early when post-red is rerun for an already red_complete ticket', async () => {
    const state = {
      ...baseState,
      tickets: baseState.tickets.map((ticket) => ({
        ...ticket,
        status: 'red_complete' as const,
        redCommitSha: 'abc123def456',
      })),
    };

    const nextState = await recordPostRed(
      state,
      'P9.02',
      createDeliveryOrchestratorContext(baseConfig),
      {
        isLocalBranchDocOnly: () => false,
        runVerify: () => {
          throw new Error('should not run');
        },
      },
    );

    expect(nextState).toBe(state);
  });

  it('skips post-red entirely when ticket declares Red: skip', async () => {
    const skipState = {
      ...baseState,
      tickets: baseState.tickets.map((ticket) => ({
        ...ticket,
        redPolicy: 'skip' as const,
      })),
    };

    const nextState = await recordPostRed(
      skipState,
      'P9.02',
      createDeliveryOrchestratorContext(baseConfig),
      {
        isLocalBranchDocOnly: () => false,
        runVerify: () => {
          throw new Error('should not run verify when Red: skip declared');
        },
      },
    );

    expect(nextState.tickets[0]?.status).toBe('red_complete');
    expect(nextState.tickets[0]?.redCommitSha).toBeUndefined();
  });

  it('rejects post-red when HEAD commit subject lacks [red]', async () => {
    await expect(
      recordPostRed(
        baseState,
        'P9.02',
        createDeliveryOrchestratorContext(baseConfig),
        {
          isLocalBranchDocOnly: () => false,
          readHeadSha: () => 'abc123',
          readLatestCommitSubject: () => 'feat(P9.02): green implementation',
          runVerify: () => ({ exitCode: 1, stderr: '', stdout: '' }),
        },
      ),
    ).rejects.toThrow(/\[red\]/);
  });

  it('treats .json-only branches as doc-only but not mixed code branches', () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'p9-02-doc-only-'));
    const remoteDir = mkdtempSync(join(tmpdir(), 'p9-02-doc-only-remote-'));

    try {
      spawnSync('git', ['init', '--bare'], { cwd: remoteDir });
      spawnSync('git', ['init'], { cwd: tempDir });
      spawnSync('git', ['config', 'user.email', 'test@test.com'], {
        cwd: tempDir,
      });
      spawnSync('git', ['config', 'user.name', 'Test'], { cwd: tempDir });

      writeFileSync(join(tempDir, 'README.md'), '# base\n');
      spawnSync('git', ['add', '.'], { cwd: tempDir });
      spawnSync('git', ['commit', '-m', 'initial'], { cwd: tempDir });
      spawnSync('git', ['branch', '-M', 'main'], { cwd: tempDir });
      spawnSync('git', ['remote', 'add', 'origin', remoteDir], {
        cwd: tempDir,
      });
      spawnSync('git', ['push', '-u', 'origin', 'main'], { cwd: tempDir });

      writeFileSync(join(tempDir, 'cspell.json'), '{}\n');
      spawnSync('git', ['add', 'cspell.json'], { cwd: tempDir });
      spawnSync('git', ['commit', '-m', 'docs: add cspell config'], {
        cwd: tempDir,
      });
      expect(isLocalBranchDocOnly(tempDir, 'main', 'node')).toBe(true);

      writeFileSync(join(tempDir, 'code.ts'), 'export const x = 1;\n');
      spawnSync('git', ['add', 'code.ts'], { cwd: tempDir });
      spawnSync('git', ['commit', '-m', 'feat: add code file'], {
        cwd: tempDir,
      });
      expect(isLocalBranchDocOnly(tempDir, 'main', 'node')).toBe(false);
    } finally {
      rmSync(tempDir, { force: true, recursive: true });
      rmSync(remoteDir, { force: true, recursive: true });
    }
  });
});
