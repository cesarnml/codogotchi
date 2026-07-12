import { describe, expect, it } from 'bun:test';

import {
  buildRunnerArtifact,
  buildRunnerInvocation,
  tryRunner,
  validateRunnerArtifact,
} from '../subagent-runner';
import { openPullRequest } from '../orchestrator';
import type { SubagentRunnerArtifact } from '../subagent-runner';
import type { DeliveryOrchestratorContext } from '../context';
import type { DeliveryState } from '../types';

// ─── Fixtures ────────────────────────────────────────────────────────────────

const baseStateVerified: DeliveryState = {
  planKey: 'phase-10',
  planPath: 'docs/product/delivery/phase-10/implementation-plan.md',
  statePath: '.agents/delivery/phase-10/state.json',
  reviewsDirPath: 'docs/product/delivery/phase-10/reviews',
  handoffsDirPath: '.agents/delivery/phase-10/handoffs',
  reviewPollIntervalMinutes: 6,
  reviewPollMaxWaitMinutes: 12,
  tickets: [
    {
      id: 'P10.03',
      title: 'Codex Exec Runner Support',
      slug: 'codex-cli-runner-support',
      ticketFile:
        'docs/product/delivery/phase-10/ticket-03-codex-cli-runner-support-for-programmatic-subagent-review.md',
      status: 'subagent_review_complete',
      branch:
        'agents/p10-03-codex-cli-runner-support-for-programmatic-subagent-review',
      baseBranch: 'agents/p10-02-executor-owned-subagent-review-via-claude-cli',
      worktreePath: '/tmp/p10_03',
      subagentReviewOutcome: 'clean',
      subagentRunnerArtifactPath:
        'docs/product/delivery/phase-10/reviews/P10.03-runner-review.json',
    },
  ],
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
        number: 43,
        url: 'https://github.com/test/pr/43',
      }),
      editPullRequest: () => undefined,
      ensureBranchPushed: () => undefined,
      findOpenPullRequest: () => undefined,
      resolveGitHubRepoForOrchestrator: () => undefined,
      resolveReviewThread: () => undefined,
      replyToReviewThreadForOrchestrator: () => undefined,
      runProcess: () => ({ exitCode: 0, stdout: '', stderr: '' }),
      updatePullRequestBody: () => undefined,
      readCurrentBranchName: () => 'agents/p10-03',
      listWorktrees: () => [],
      spawnSync: () => ({ status: 0, stdout: '' }),
      findExistingBranch: () => undefined,
      deriveBranchName: () => 'agents/p10-03',
      deriveWorktreePath: () => '/tmp/p10_03',
    },
    invocation: 'bun run deliver',
  } as unknown as DeliveryOrchestratorContext;
}

// ─── tryRunner with codex-cli identity ───────────────────────────────────────

describe('P10.03 — tryRunner: outcome detection is runner-agnostic', () => {
  it('returns ran+clean for codex-cli style invocation with no changes', () => {
    const result = tryRunner(
      () => ({ exitCode: 0, timedOut: false }),
      () => false,
    );
    expect(result).toEqual({
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'completed',
    });
  });

  it('returns ran+patched for codex-cli style invocation with changes', () => {
    const result = tryRunner(
      () => ({ exitCode: 0, timedOut: false }),
      () => true,
    );
    expect(result).toEqual({
      status: 'ran',
      outcome: 'patched',
      terminatedReason: 'completed',
    });
  });

  it('returns unavailable for codex-cli style when spawn fails', () => {
    const result = tryRunner(
      () => {
        throw new Error('spawn codex ENOENT');
      },
      () => false,
    );
    expect(result).toEqual({ status: 'unavailable' });
  });
});

// ─── buildRunnerArtifact identity ────────────────────────────────────────────

describe('P10.03 — buildRunnerInvocation + buildRunnerArtifact identity', () => {
  it('builds codex-cli invocation with correct runnerKind', () => {
    const invocation = buildRunnerInvocation('codex-cli', 'sha1234', 'clean');
    const artifact = buildRunnerArtifact('P10.03', [invocation]);
    expect(artifact.ticket).toBe('P10.03');
    expect(artifact.invocations[0]!.runnerKind).toBe('codex-cli');
    expect(artifact.invocations[0]!.outcome).toBe('clean');
    expect(artifact.invocations[0]!.reviewedHeadSha).toBe('sha1234');
    expect(typeof artifact.invocations[0]!.completedAt).toBe('string');
    expect(artifact.invocations[0]!.terminatedReason).toBe('completed');
  });

  it('builds claude-cli invocation with correct runnerKind', () => {
    const invocation = buildRunnerInvocation(
      'claude-cli',
      'sha5678',
      'patched',
    );
    expect(invocation.runnerKind).toBe('claude-cli');
    expect(invocation.outcome).toBe('patched');
  });

  it('builds skipped invocation for honest skip case', () => {
    const invocation = buildRunnerInvocation('skipped', 'sha9012', 'skipped', {
      terminatedReason: 'runner_unavailable',
    });
    expect(invocation.runnerKind).toBe('skipped');
    expect(invocation.outcome).toBe('skipped');
    expect(invocation.terminatedReason).toBe('runner_unavailable');
  });
});

// ─── validateRunnerArtifact with codex-cli ───────────────────────────────────

describe('P10.03 — validateRunnerArtifact accepts codex-cli runnerKind (structured)', () => {
  const validCodexArtifact: SubagentRunnerArtifact = {
    ticket: 'P10.03',
    invocations: [
      {
        runnerKind: 'codex-cli',
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

  it('accepts a valid codex-cli clean artifact', () => {
    expect(validateRunnerArtifact(validCodexArtifact)).toEqual(
      validCodexArtifact,
    );
  });

  it('accepts a valid codex-cli patched artifact', () => {
    const artifact: SubagentRunnerArtifact = {
      ...validCodexArtifact,
      invocations: [
        { ...validCodexArtifact.invocations[0]!, outcome: 'patched' as const },
      ],
    };
    expect(validateRunnerArtifact(artifact)).toEqual(artifact);
  });

  it('returns null when invocation is missing reviewedHeadSha', () => {
    const broken = {
      ticket: 'P10.03',
      invocations: [
        { ...validCodexArtifact.invocations[0]!, reviewedHeadSha: '' },
      ],
    };
    expect(validateRunnerArtifact(broken)).toBeNull();
  });

  it('returns null for invocation with unknown outcome', () => {
    const broken = {
      ticket: 'P10.03',
      invocations: [
        { ...validCodexArtifact.invocations[0]!, outcome: 'unknown' },
      ],
    };
    expect(validateRunnerArtifact(broken)).toBeNull();
  });
});

// ─── open-pr policy-based gate (codex path) ───────────────────────────────────

describe('P10.03 — open-pr policy gate applies to codex-cli artifacts too', () => {
  it('fails closed when outcome=clean and no artifact path', async () => {
    const stateWithoutArtifact: DeliveryState = {
      ...baseStateVerified,
      tickets: baseStateVerified.tickets.map((t) => ({
        ...t,
        status: 'verified' as const,
        subagentReviewOutcome: 'clean' as const,
        subagentRunnerArtifactPath: undefined,
      })),
    };
    const context = makeContext('skip_doc_only');

    await expect(
      openPullRequest(stateWithoutArtifact, '/tmp/project', context, 'P10.03'),
    ).rejects.toThrow(/runner.*review.*required|requires.*runner.*review/i);
  });

  it('exposes stable contract code for codex path', async () => {
    const stateWithoutArtifact: DeliveryState = {
      ...baseStateVerified,
      tickets: baseStateVerified.tickets.map((t) => ({
        ...t,
        status: 'verified' as const,
        subagentReviewOutcome: 'clean' as const,
        subagentRunnerArtifactPath: undefined,
      })),
    };

    try {
      await openPullRequest(
        stateWithoutArtifact,
        '/tmp/project',
        makeContext('skip_doc_only'),
        'P10.03',
      );
      throw new Error('Expected error was not thrown');
    } catch (error) {
      expect((error as { code?: string }).code).toBe(
        'workflow.open_pr.requires_runner_review',
      );
    }
  });

  it('does not gate when subagentReview is disabled (codex path)', async () => {
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
        'P10.03',
      );
    } catch (err) {
      expect((err as { code?: string }).code).not.toBe(
        'workflow.open_pr.requires_runner_review',
      );
    }
  });
});
