import { describe, expect, it } from 'bun:test';
import {
  mkdtempSync,
  mkdirSync,
  realpathSync,
  rmSync,
  symlinkSync,
} from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { assertWorktreeGuard } from '../cli-runner';
import { recordPostVerify } from '../cli-runner';
import { advanceToNextTicket, openPullRequest } from '../ticket-flow';
import type { ResolvedOrchestratorConfig } from '../runtime-config';
import type { DeliveryState, TicketState } from '../types';

const planPath = 'docs/product/delivery/phase-03/implementation-plan.md';

const baseConfig: ResolvedOrchestratorConfig = {
  defaultBranch: 'main',
  planRoot: 'docs',
  runtime: 'bun',
  packageManager: 'bun',
  ticketBoundaryMode: 'cook',
  reviewPolicy: { subagentReview: 'skip_doc_only', prReview: 'skip_doc_only' },
};

const baseTicket: TicketState = {
  id: 'P3.01',
  title: 'Guards, signals, and dead code cleanup',
  slug: 'guards-signals-and-dead-code-cleanup',
  ticketFile:
    'docs/product/delivery/phase-03/ticket-01-guards-signals-dead-code.md',
  status: 'in_progress',
  branch: 'agents/p3-01-guards-signals-and-dead-code-cleanup',
  baseBranch: 'main',
  worktreePath: '/Users/cesar/code/son-of-anton_p3_01',
};

const baseState: DeliveryState = {
  planKey: 'phase-03',
  planPath,
  statePath: '.agents/delivery/phase-03/state.json',
  reviewsDirPath: '.agents/delivery/phase-03/reviews',
  handoffsDirPath: '.agents/delivery/phase-03/handoffs',
  reviewPollIntervalMinutes: 6,
  reviewPollMaxWaitMinutes: 12,
  tickets: [baseTicket],
};

// ---------------------------------------------------------------------------
// Worktree guard
// ---------------------------------------------------------------------------

describe('assertWorktreeGuard (P3.01)', () => {
  it('throws when a guarded command is run from outside the ticket worktree', () => {
    expect(() =>
      assertWorktreeGuard(
        '/wrong/path',
        'post-verify',
        [],
        baseState,
        baseConfig,
      ),
    ).toThrow(/P3\.01/);
    expect(() =>
      assertWorktreeGuard(
        '/wrong/path',
        'post-verify',
        [],
        baseState,
        baseConfig,
      ),
    ).toThrow(/son-of-anton_p3_01/);
  });

  it('exposes the wrong-worktree contract code alongside recovery guidance', () => {
    try {
      assertWorktreeGuard(
        '/wrong/path',
        'post-verify',
        [],
        baseState,
        baseConfig,
      );
      throw new Error('Expected assertWorktreeGuard to throw.');
    } catch (error) {
      expect(error).toMatchObject({
        code: 'workflow.worktree_guard.wrong_worktree',
      });
      expect((error as Error).message).toContain('Recovery: cd');
      expect((error as Error).message).toContain('Next command from worktree');
    }
  });

  it('includes the recovery cd command in the error message', () => {
    expect(() =>
      assertWorktreeGuard(
        '/wrong/path',
        'post-verify',
        [],
        baseState,
        baseConfig,
      ),
    ).toThrow(/cd .* && bun run deliver/);
  });

  it('includes positional args in the recovery command', () => {
    expect(() =>
      assertWorktreeGuard(
        '/wrong/path',
        'post-verify',
        ['patched', 'abc123'],
        baseState,
        baseConfig,
      ),
    ).toThrow(/post-verify patched abc123/);
  });

  it('does not throw for exempt command: status', () => {
    expect(() =>
      assertWorktreeGuard('/wrong/path', 'status', [], baseState, baseConfig),
    ).not.toThrow();
  });

  it('does not throw for exempt command: sync', () => {
    expect(() =>
      assertWorktreeGuard('/wrong/path', 'sync', [], baseState, baseConfig),
    ).not.toThrow();
  });

  it('does not throw for exempt command: start', () => {
    expect(() =>
      assertWorktreeGuard('/wrong/path', 'start', [], baseState, baseConfig),
    ).not.toThrow();
  });

  it('accepts a canonical cwd when the saved worktree path is a symlink', () => {
    const tempRoot = mkdtempSync(join(tmpdir(), 'p3-01-worktree-'));
    const realDir = join(tempRoot, 'real');
    const linkDir = join(tempRoot, 'link');

    mkdirSync(realDir);
    symlinkSync(realDir, linkDir);

    const symlinkState: DeliveryState = {
      ...baseState,
      tickets: [{ ...baseTicket, worktreePath: linkDir }],
    };

    try {
      expect(() =>
        assertWorktreeGuard(
          realpathSync(realDir),
          'post-verify',
          [],
          symlinkState,
          baseConfig,
        ),
      ).not.toThrow();
    } finally {
      rmSync(tempRoot, { force: true, recursive: true });
    }
  });
});

// ---------------------------------------------------------------------------
// Wrong-state error messages
// ---------------------------------------------------------------------------

const minimalDeps = {
  assertReviewerFacingMarkdown: () => {},
  buildPullRequestBody: () => '## PR body',
  buildPullRequestTitle: () => 'feat: ticket [P3.01]',
  createPullRequest: () => ({
    number: 1,
    url: 'https://github.com/r/p/pull/1',
  }),
  editPullRequest: () => {},
  ensureBranchPushed: () => {},
  findOpenPullRequest: () => undefined,
};

describe('wrong-state error messages (P3.01)', () => {
  it('open-pr on in_progress ticket: error contains in_progress and post-verify', () => {
    expect(() =>
      openPullRequest(baseState, '/cwd', 'P3.01', {
        ...minimalDeps,
        subagentReviewPolicy: 'skip_doc_only',
      }),
    ).toThrow(/in_progress/);
    expect(() =>
      openPullRequest(baseState, '/cwd', 'P3.01', {
        ...minimalDeps,
        subagentReviewPolicy: 'skip_doc_only',
      }),
    ).toThrow(/post-verify/);
  });

  it('open-pr on verified ticket with subagent enabled: error contains verified and subagent-review', () => {
    const verifiedState: DeliveryState = {
      ...baseState,
      tickets: [{ ...baseTicket, status: 'verified' }],
    };
    expect(() =>
      openPullRequest(verifiedState, '/cwd', 'P3.01', {
        ...minimalDeps,
        subagentReviewPolicy: 'skip_doc_only',
      }),
    ).toThrow(/verified/);
    expect(() =>
      openPullRequest(verifiedState, '/cwd', 'P3.01', {
        ...minimalDeps,
        subagentReviewPolicy: 'skip_doc_only',
      }),
    ).toThrow(/subagent-review/);
  });

  it('advance on in_progress ticket: error contains in_progress and the next valid command', async () => {
    await expect(
      advanceToNextTicket(baseState, '/cwd', {
        updatePullRequestBody: () => {},
      }),
    ).rejects.toThrow(/in_progress/);
  });
});

// ---------------------------------------------------------------------------
// Doc-only early failure
// ---------------------------------------------------------------------------

describe('doc-only early failure (P3.01)', () => {
  it('post-verify on doc-only ticket with no branch commits throws immediately', async () => {
    await expect(
      recordPostVerify(baseState, undefined, 'clean', baseConfig, {
        isLocalBranchDocOnly: () => true,
        hasLocalBranchCommits: () => false,
      }),
    ).rejects.toThrow(/No commits on branch for doc-only ticket P3\.01/);
  });

  it('post-verify on doc-only ticket with branch commits proceeds normally', async () => {
    const nextState = await recordPostVerify(
      baseState,
      undefined,
      undefined,
      baseConfig,
      {
        isLocalBranchDocOnly: () => true,
        hasLocalBranchCommits: () => true,
      },
    );
    expect(nextState.tickets[0]?.status).toBe('verified');
  });
});
