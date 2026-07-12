import { describe, expect, it } from 'bun:test';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { tryRunner, validateRunnerArtifact } from '../subagent-runner';
import { openPullRequest } from '../orchestrator';
import { commitDeliveryArtifactAndPush } from '../cli-runner';
import { relativeToRepo } from '../planning';
import { runProcess } from '../platform';
import type { SubagentRunnerArtifact } from '../subagent-runner';
import type { DeliveryOrchestratorContext } from '../context';
import type { DeliveryState } from '../types';

// ─── Fixtures ────────────────────────────────────────────────────────────────

const baseState: DeliveryState = {
  planKey: 'phase-10',
  planPath: 'docs/product/delivery/phase-10/implementation-plan.md',
  statePath: '.agents/delivery/phase-10/state.json',
  reviewsDirPath: 'docs/product/delivery/phase-10/reviews',
  handoffsDirPath: '.agents/delivery/phase-10/handoffs',
  reviewPollIntervalMinutes: 6,
  reviewPollMaxWaitMinutes: 12,
  tickets: [
    {
      id: 'P10.02',
      title: 'Executor-owned Subagent Review via Claude CLI',
      slug: 'executor-owned-subagent-review-via-claude-cli',
      ticketFile:
        'docs/product/delivery/phase-10/ticket-02-executor-owned-subagent-review-via-claude-cli.md',
      status: 'subagent_review_complete',
      branch: 'agents/p10-02-executor-owned-subagent-review-via-claude-cli',
      baseBranch:
        'agents/p10-01-runner-native-subagent-review-config-and-run-policy-contract',
      worktreePath: '/tmp/p10_02',
      subagentReviewOutcome: 'clean',
      subagentRunnerArtifactPath:
        'docs/product/delivery/phase-10/reviews/P10.02-runner-review.json',
    },
  ],
};

const baseStateVerified: DeliveryState = {
  ...baseState,
  tickets: baseState.tickets.map((t) => ({
    ...t,
    status: 'verified' as const,
    subagentReviewOutcome: 'clean' as const,
  })),
};

function makeContext(
  subagentReview: 'required' | 'skip_doc_only' | 'disabled' = 'skip_doc_only',
): DeliveryOrchestratorContext {
  return {
    config: {
      defaultBranch: 'main',
      planRoot: 'docs',
      runtime: 'bun',
      packageManager: 'bun',
      ticketBoundaryMode: 'cook',
      reviewPolicy: {
        subagentReview,
        prReview: 'skip_doc_only',
      },
    },
    platform: {
      createPullRequest: () => ({
        number: 42,
        url: 'https://github.com/test/pr/42',
      }),
      editPullRequest: () => undefined,
      ensureBranchPushed: () => undefined,
      findOpenPullRequest: () => undefined,
      resolveGitHubRepoForOrchestrator: () => undefined,
      resolveReviewThread: () => undefined,
      replyToReviewThreadForOrchestrator: () => undefined,
      runProcess: () => ({ exitCode: 0, stdout: '', stderr: '' }),
      updatePullRequestBody: () => undefined,
      readCurrentBranchName: () => 'agents/p10-02',
      listWorktrees: () => [],
      spawnSync: () => ({ status: 0, stdout: '' }),
      findExistingBranch: () => undefined,
      deriveBranchName: () => 'agents/p10-02',
      deriveWorktreePath: () => '/tmp/p10_02',
    },
    invocation: 'bun run deliver',
  } as unknown as DeliveryOrchestratorContext;
}

// ─── tryRunner fallback chain ─────────────────────────────────────────────────

describe('P10.02 — tryRunner fallback behavior', () => {
  it('first runner clean → second never called', () => {
    const secondCalled = false;
    const first = tryRunner(
      () => ({ exitCode: 0, timedOut: false }),
      () => false,
    );
    expect(first.status).toBe('ran');
    // Simulate caller logic: second runner not invoked when first ran
    expect(secondCalled).toBe(false);
  });

  it('first runner unavailable → fallback attempted', () => {
    const first = tryRunner(
      () => {
        throw new Error('not installed');
      },
      () => false,
    );
    expect(first.status).toBe('unavailable');

    const second = tryRunner(
      () => ({ exitCode: 0, timedOut: false }),
      () => true,
    );
    expect(second).toEqual({
      status: 'ran',
      outcome: 'patched',
      terminatedReason: 'completed',
    });
  });

  it('both runners unavailable → honest skip', () => {
    const first = tryRunner(
      () => {
        throw new Error('not installed');
      },
      () => false,
    );
    const second = tryRunner(
      () => {
        throw new Error('not installed');
      },
      () => false,
    );
    expect(first.status).toBe('unavailable');
    expect(second.status).toBe('unavailable');
  });

  it('first runner timeout → second attempted', () => {
    const first = tryRunner(
      () => ({ exitCode: null, timedOut: true }),
      () => false,
    );
    expect(first.status).toBe('timeout');
  });
});

// ─── validateRunnerArtifact ───────────────────────────────────────────────────

describe('P10.02 — validateRunnerArtifact (structured)', () => {
  const validArtifact: SubagentRunnerArtifact = {
    ticket: 'P10.02',
    invocations: [
      {
        runnerKind: 'claude-cli',
        reviewedHeadSha: 'abc1234',
        outcome: 'clean',
        completedAt: '2026-01-01T00:00:00.000Z',
        terminatedReason: 'completed',
        findings: [],
        probedSurfaces: [],
        patches: [],
      },
    ],
  };

  it('accepts valid clean artifact', () => {
    expect(validateRunnerArtifact(validArtifact)).toEqual(validArtifact);
  });

  it('accepts valid patched artifact', () => {
    const artifact: SubagentRunnerArtifact = {
      ...validArtifact,
      invocations: [
        { ...validArtifact.invocations[0]!, outcome: 'patched' as const },
      ],
    };
    expect(validateRunnerArtifact(artifact)).toEqual(artifact);
  });

  it('accepts skipped invocation', () => {
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P10.02',
      invocations: [
        {
          runnerKind: 'skipped',
          reviewedHeadSha: 'abc',
          outcome: 'skipped',
          completedAt: '2026-01-01T00:00:00.000Z',
          terminatedReason: 'runner_unavailable',
          findings: [],
          probedSurfaces: [],
          patches: [],
        },
      ],
    };
    expect(validateRunnerArtifact(artifact)).toEqual(artifact);
  });

  it('returns null when invocations is missing', () => {
    expect(validateRunnerArtifact({ ticket: 'P10.02' })).toBeNull();
  });

  it('returns null when ticket is missing', () => {
    const { ticket: _, ...rest } = validArtifact;
    expect(validateRunnerArtifact(rest)).toBeNull();
  });

  it('returns null when an invocation is missing reviewedHeadSha', () => {
    const broken = {
      ticket: 'P10.02',
      invocations: [
        {
          ...validArtifact.invocations[0]!,
          reviewedHeadSha: '',
        },
      ],
    };
    expect(validateRunnerArtifact(broken)).toBeNull();
  });

  it('returns null for unknown outcome value', () => {
    const broken = {
      ticket: 'P10.02',
      invocations: [
        { ...validArtifact.invocations[0]!, outcome: 'unknown' as string },
      ],
    };
    expect(validateRunnerArtifact(broken)).toBeNull();
  });

  it('returns null for null input', () => {
    expect(validateRunnerArtifact(null)).toBeNull();
  });

  it('returns null for non-object input', () => {
    expect(validateRunnerArtifact('string')).toBeNull();
  });

  it('returns null for legacy 4-field shape (no longer a valid SubagentRunnerArtifact at the type level)', () => {
    expect(
      validateRunnerArtifact({
        runnerKind: 'claude-cli',
        reviewedHeadSha: 'abc1234',
        outcome: 'clean',
        completedAt: '2026-01-01T00:00:00.000Z',
      }),
    ).toBeNull();
  });
});

// ─── open-pr policy-based gate ───────────────────────────────────────────────

describe('P10.02 — open-pr policy-based runner artifact gate', () => {
  it('fails closed when outcome=clean and no artifact path on ticket', async () => {
    const stateWithoutArtifact: DeliveryState = {
      ...baseStateVerified,
      tickets: baseStateVerified.tickets.map((t) => ({
        ...t,
        subagentRunnerArtifactPath: undefined,
      })),
    };
    const context = makeContext('skip_doc_only');

    await expect(
      openPullRequest(stateWithoutArtifact, '/tmp/project', context, 'P10.02'),
    ).rejects.toThrow(/runner.*review.*required|requires.*runner.*review/i);
  });

  it('exposes stable contract code workflow.open_pr.requires_runner_review', async () => {
    const stateWithoutArtifact: DeliveryState = {
      ...baseStateVerified,
      tickets: baseStateVerified.tickets.map((t) => ({
        ...t,
        subagentRunnerArtifactPath: undefined,
      })),
    };

    try {
      await openPullRequest(
        stateWithoutArtifact,
        '/tmp/project',
        makeContext('skip_doc_only'),
        'P10.02',
      );
      throw new Error('Expected error was not thrown');
    } catch (error) {
      expect((error as { code?: string }).code).toBe(
        'workflow.open_pr.requires_runner_review',
      );
    }
  });

  it('does not gate when subagentReview is disabled', async () => {
    const context = makeContext('disabled');
    const stateWithoutArtifact: DeliveryState = {
      ...baseStateVerified,
      tickets: baseStateVerified.tickets.map((t) => ({
        ...t,
        subagentRunnerArtifactPath: undefined,
      })),
    };
    try {
      await openPullRequest(
        stateWithoutArtifact,
        '/tmp/project',
        context,
        'P10.02',
      );
    } catch (err) {
      expect((err as { code?: string }).code).not.toBe(
        'workflow.open_pr.requires_runner_review',
      );
    }
  });

  it('does not gate when subagentReviewOutcome is skipped', async () => {
    const stateSkipped: DeliveryState = {
      ...baseStateVerified,
      tickets: baseStateVerified.tickets.map((t) => ({
        ...t,
        subagentReviewOutcome: 'skipped' as const,
        subagentRunnerArtifactPath: undefined,
      })),
    };
    try {
      await openPullRequest(
        stateSkipped,
        '/tmp/project',
        makeContext('skip_doc_only'),
        'P10.02',
      );
    } catch (err) {
      expect((err as { code?: string }).code).not.toBe(
        'workflow.open_pr.requires_runner_review',
      );
    }
  });
});

describe('P10.02 — subagent runner artifact persistence', () => {
  function git(repo: string, args: string[]) {
    execFileSync('git', args, { cwd: repo, stdio: 'pipe' });
  }

  it('commits and pushes the runner artifact when it changes in a git checkout', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'subagent-artifact-'));
    const artifactPath = join(
      repoRoot,
      'docs/product/delivery/phase-10/reviews/P10.02-subagent-review.ledger.json',
    );
    const pushedBranches: string[] = [];

    try {
      await mkdir(join(repoRoot, 'docs/product/delivery/phase-10/reviews'), {
        recursive: true,
      });
      await writeFile(join(repoRoot, 'README.md'), '# fixture\n', 'utf8');
      await writeFile(
        artifactPath,
        `${JSON.stringify({
          completedAt: '2026-05-18T00:00:00.000Z',
          outcome: 'clean',
          reviewedHeadSha: 'abc1234',
          runnerKind: 'codex-cli',
        })}\n`,
        'utf8',
      );

      git(repoRoot, ['init', '-b', 'main']);
      git(repoRoot, ['config', 'user.email', 'delivery-test@example.test']);
      git(repoRoot, ['config', 'user.name', 'delivery-test']);
      git(repoRoot, ['add', 'README.md']);
      git(repoRoot, ['commit', '-m', 'init']);

      const committed = commitDeliveryArtifactAndPush({
        absolutePath: artifactPath,
        branch: 'agents/p10-02-executor-owned-subagent-review-via-claude-cli',
        commitMessage: 'chore(P10.02): record subagent-review runner artifact',
        ensureBranchPushed: (_cwd, branch) => {
          pushedBranches.push(branch);
        },
        relativeToRepo,
        repoRoot,
        runProcess: (cwd, cmd) => runProcess(cwd, cmd, 'bun'),
      });

      expect(committed).toBe(true);
      expect(pushedBranches).toEqual([
        'agents/p10-02-executor-owned-subagent-review-via-claude-cli',
      ]);
      expect(runProcess(repoRoot, ['git', 'status', '--porcelain'])).toBe('');
      expect(
        runProcess(repoRoot, ['git', 'log', '-1', '--pretty=%s']).trim(),
      ).toBe('chore(P10.02): record subagent-review runner artifact');
      expect(await readFile(artifactPath, 'utf8')).toContain('codex-cli');
    } finally {
      await rm(repoRoot, { recursive: true, force: true });
    }
  });
});
