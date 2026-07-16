import { describe, expect, it } from 'bun:test';

import {
  isRefactorGateEligible,
  requiresRefactorReviewBeforeAdversarial,
} from '../refactor-review';
import { openPullRequest } from '../orchestrator';
import { resolveNextCommand } from '../format';
import type { DeliveryOrchestratorContext } from '../context';
import type { DeliveryState } from '../types';
import type { ResolvedOrchestratorConfig } from '../runtime-config';

const baseConfig: ResolvedOrchestratorConfig = {
  defaultBranch: 'main',
  deliveryBaseBranch: 'main',
  closeoutBranch: 'main',
  planRoot: 'docs',
  runtime: 'bun',
  packageManager: 'bun',
  ticketBoundaryMode: 'cook',
  reviewPolicy: {
    subagentReview: 'skip_doc_only',
    prReview: 'skip_doc_only',
    refactorReview: 'runner_on_red',
  },
};

describe('P20.03 — requiresRefactorReviewBeforeAdversarial gate-placement predicate', () => {
  it('is true for a Red:required, non-doc-only ticket under runner_on_red with no recorded outcome', () => {
    expect(
      requiresRefactorReviewBeforeAdversarial({
        refactorReviewPolicy: 'runner_on_red',
        redPolicy: 'required',
        isDocOnly: false,
        refactorReviewOutcome: undefined,
      }),
    ).toBe(true);
  });

  it('is false for a Red:skip ticket even under runner_on_red', () => {
    expect(
      requiresRefactorReviewBeforeAdversarial({
        refactorReviewPolicy: 'runner_on_red',
        redPolicy: 'skip',
        isDocOnly: false,
        refactorReviewOutcome: undefined,
      }),
    ).toBe(false);
  });

  it('is false for a doc-only ticket regardless of refactorReview policy', () => {
    expect(
      requiresRefactorReviewBeforeAdversarial({
        refactorReviewPolicy: 'runner_on_red',
        redPolicy: 'required',
        isDocOnly: true,
        refactorReviewOutcome: undefined,
      }),
    ).toBe(false);
  });

  it('is false when refactorReview is disabled, leaving the existing sequence unchanged', () => {
    expect(
      requiresRefactorReviewBeforeAdversarial({
        refactorReviewPolicy: 'disabled',
        redPolicy: 'required',
        isDocOnly: false,
        refactorReviewOutcome: undefined,
      }),
    ).toBe(false);
  });

  it('is false once a refactor-review outcome has been recorded', () => {
    expect(
      requiresRefactorReviewBeforeAdversarial({
        refactorReviewPolicy: 'runner_on_red',
        redPolicy: 'required',
        isDocOnly: false,
        refactorReviewOutcome: 'clean',
      }),
    ).toBe(false);
  });
});

function makeState(overrides: {
  refactorReviewOutcome?: 'clean' | 'patched' | 'deferred' | 'skipped';
  refactorRunnerArtifactPath?: string;
}): DeliveryState {
  return {
    planKey: 'phase-20',
    planPath: 'docs/product/delivery/phase-20/implementation-plan.md',
    statePath: '.agents/delivery/phase-20/state.json',
    reviewsDirPath: 'docs/product/delivery/phase-20/reviews',
    handoffsDirPath: '.agents/delivery/phase-20/handoffs',
    reviewPollIntervalMinutes: 6,
    reviewPollMaxWaitMinutes: 12,
    tickets: [
      {
        id: 'P20.03',
        title: 'Gate placement, guards & core docs',
        slug: 'gate-placement-guards-core-docs',
        ticketFile:
          'docs/product/delivery/phase-20/ticket-03-gate-placement-guards-core-docs.md',
        redPolicy: 'required',
        status: 'subagent_review_complete',
        branch: 'agents/p20-03',
        baseBranch: 'agents/p20-02',
        worktreePath: '/tmp/p20_03',
        subagentReviewOutcome: 'clean',
        subagentRunnerArtifactPath:
          'docs/product/delivery/phase-20/reviews/P20.03-subagent-review.ledger.json',
        ...overrides,
      },
    ],
  };
}

function makeContext(
  refactorReview: 'disabled' | 'runner_on_red',
): DeliveryOrchestratorContext {
  return {
    config: {
      defaultBranch: 'main',
      planRoot: 'docs',
      runtime: 'bun',
      packageManager: 'bun',
      ticketBoundaryMode: 'cook',
      reviewPolicy: {
        subagentReview: 'skip_doc_only',
        prReview: 'skip_doc_only',
        refactorReview,
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
      readCurrentBranchName: () => 'agents/p20-03',
      listWorktrees: () => [],
      spawnSync: () => ({ status: 0, stdout: '' }),
      findExistingBranch: () => undefined,
      deriveBranchName: () => 'agents/p20-03',
      deriveWorktreePath: () => '/tmp/p20_03',
    },
    invocation: 'bun run deliver',
  } as unknown as DeliveryOrchestratorContext;
}

describe('P20.03 — isRefactorGateEligible (shared eligibility for status routing and CLI command guards)', () => {
  it('is true for a Red:required, non-doc-only ticket under runner_on_red', () => {
    expect(
      isRefactorGateEligible({
        refactorReviewPolicy: 'runner_on_red',
        redPolicy: 'required',
        isDocOnly: false,
      }),
    ).toBe(true);
  });

  it('is false when refactorReview is disabled', () => {
    expect(
      isRefactorGateEligible({
        refactorReviewPolicy: 'disabled',
        redPolicy: 'required',
        isDocOnly: false,
      }),
    ).toBe(false);
  });

  it('is false for a Red:skip ticket', () => {
    expect(
      isRefactorGateEligible({
        refactorReviewPolicy: 'runner_on_red',
        redPolicy: 'skip',
        isDocOnly: false,
      }),
    ).toBe(false);
  });

  it('is false for a doc-only ticket', () => {
    expect(
      isRefactorGateEligible({
        refactorReviewPolicy: 'runner_on_red',
        redPolicy: 'required',
        isDocOnly: true,
      }),
    ).toBe(false);
  });
});

describe('P20.03 — resolveVerifiedNextCommand routes through the refactor gate', () => {
  it('routes to write-subagent-refactor-review when eligible and no prompt is recorded yet', () => {
    const next = resolveNextCommand(
      'verified',
      baseConfig,
      'docs/product/delivery/phase-20/implementation-plan.md',
      'P20.03',
      {
        redPolicy: 'required',
        docOnly: false,
        refactorReviewOutcome: undefined,
        refactorReviewPromptPath: undefined,
      },
    );
    expect(next).toContain('write-subagent-refactor-review');
  });

  it('routes to subagent-refactor-review once a prompt is recorded but no outcome yet', () => {
    const next = resolveNextCommand(
      'verified',
      baseConfig,
      'docs/product/delivery/phase-20/implementation-plan.md',
      'P20.03',
      {
        redPolicy: 'required',
        docOnly: false,
        refactorReviewOutcome: undefined,
        refactorReviewPromptPath:
          'docs/product/delivery/phase-20/reviews/P20.03-refactor-review.prompt.md',
      },
    );
    expect(next).toContain('subagent-refactor-review');
    expect(next).not.toContain('write-subagent-refactor-review');
  });

  it('falls through to the existing adversarial routing once a refactor outcome is recorded', () => {
    const next = resolveNextCommand(
      'verified',
      baseConfig,
      'docs/product/delivery/phase-20/implementation-plan.md',
      'P20.03',
      {
        redPolicy: 'required',
        docOnly: false,
        refactorReviewOutcome: 'clean',
        refactorReviewPromptPath:
          'docs/product/delivery/phase-20/reviews/P20.03-refactor-review.prompt.md',
        subagentAdversarialPromptPath: undefined,
        verifyOutcome: 'clean',
      },
    );
    expect(next).toContain('write-subagent-adversarial-review');
  });

  it('falls through to the existing adversarial routing when the ticket is Red:skip, ignoring refactorReview', () => {
    const next = resolveNextCommand(
      'verified',
      baseConfig,
      'docs/product/delivery/phase-20/implementation-plan.md',
      'P20.03',
      {
        redPolicy: 'skip',
        docOnly: false,
        refactorReviewOutcome: undefined,
        refactorReviewPromptPath: undefined,
        subagentAdversarialPromptPath: undefined,
        verifyOutcome: 'clean',
      },
    );
    expect(next).not.toContain('refactor-review');
    expect(next).toContain('write-subagent-adversarial-review');
  });

  it('falls through to the existing adversarial routing when refactorReview is disabled', () => {
    const disabledConfig: ResolvedOrchestratorConfig = {
      ...baseConfig,
      reviewPolicy: { ...baseConfig.reviewPolicy, refactorReview: 'disabled' },
    };
    const next = resolveNextCommand(
      'verified',
      disabledConfig,
      'docs/product/delivery/phase-20/implementation-plan.md',
      'P20.03',
      {
        redPolicy: 'required',
        docOnly: false,
        refactorReviewOutcome: undefined,
        refactorReviewPromptPath: undefined,
        subagentAdversarialPromptPath: undefined,
        verifyOutcome: 'clean',
      },
    );
    expect(next).not.toContain('refactor-review');
    expect(next).toContain('write-subagent-adversarial-review');
  });
});

describe('P20.03 — open-pr soft enforcement under runner_on_red', () => {
  it('does not block open-pr when no refactor-review outcome/artifact was ever recorded', async () => {
    const state = makeState({});
    const context = makeContext('runner_on_red');
    try {
      await openPullRequest(state, '/tmp/project', context, 'P20.03');
    } catch (err) {
      expect(String((err as Error).message)).not.toMatch(/refactor/i);
    }
  });
});
