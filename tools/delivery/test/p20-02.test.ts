import { describe, expect, it } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  deriveRefactorReviewLedgerPath,
  deriveRefactorReviewPromptPath,
  isValidRefactorReviewPromptContent,
  recordRefactorReviewOutcome,
  writeRefactorReviewPrompt,
} from '../refactor-review';
import {
  appendInvocationToArtifact,
  buildRunnerInvocation,
  readSubagentRunnerArtifact,
  runProgrammaticSubagentReview,
} from '../subagent-runner';
import type { DeliveryState, TicketState } from '../types';

const SUBSTANTIVE_PROMPT = [
  '# Refactor review for P20.02',
  '',
  'This is a substantive, filled-in refactor review prompt with enough content',
  'to pass the placeholder-rejection floor used by the write command.',
].join('\n');

function baseTicket(overrides: Partial<TicketState> = {}): TicketState {
  return {
    id: 'P20.02',
    title: 'Refactor-review CLI commands',
    slug: 'refactor-review-cli-commands',
    ticketFile:
      'docs/product/delivery/phase-20/ticket-02-refactor-review-cli-commands.md',
    redPolicy: 'required',
    status: 'verified',
    branch: 'agents/p20-02',
    baseBranch: 'agents/p20-01',
    worktreePath: '/tmp/p20_02',
    verifiedAt: '2026-07-16T00:00:00.000Z',
    verifyOutcome: 'clean',
    ...overrides,
  };
}

function baseState(tickets: TicketState[]): DeliveryState {
  return {
    planKey: 'phase-20',
    planPath: 'docs/product/delivery/phase-20/implementation-plan.md',
    statePath: '.agents/delivery/phase-20/state.json',
    reviewsDirPath: 'docs/product/delivery/phase-20/reviews',
    handoffsDirPath: '.agents/delivery/phase-20/handoffs',
    reviewPollIntervalMinutes: 6,
    reviewPollMaxWaitMinutes: 12,
    tickets,
  };
}

describe('P20.02 — write-subagent-refactor-review persistence', () => {
  it('rejects placeholder-like prompt content', () => {
    expect(isValidRefactorReviewPromptContent('too short')).toBe(false);
    expect(
      isValidRefactorReviewPromptContent(
        'Fill in <list each implementation file changed> here',
      ),
    ).toBe(false);
  });

  it('persists the prompt file and returns its path', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'p20-02-prompt-'));
    try {
      const result = writeRefactorReviewPrompt({
        repoRoot,
        reviewsDirPath: 'docs/product/delivery/phase-20/reviews',
        ticketId: 'P20.02',
        content: SUBSTANTIVE_PROMPT,
      });
      expect(result.relativePath).toBe(
        deriveRefactorReviewPromptPath(
          'docs/product/delivery/phase-20/reviews',
          'P20.02',
        ),
      );
      expect(existsSync(result.absolutePath)).toBe(true);
      expect(readFileSync(result.absolutePath, 'utf-8')).toContain(
        'substantive, filled-in refactor review prompt',
      );
    } finally {
      await rm(repoRoot, { recursive: true });
    }
  });

  it('refuses to write a stub prompt', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'p20-02-prompt-stub-'));
    try {
      expect(() =>
        writeRefactorReviewPrompt({
          repoRoot,
          reviewsDirPath: 'docs/product/delivery/phase-20/reviews',
          ticketId: 'P20.02',
          content: 'stub',
        }),
      ).toThrow(/placeholder/i);
    } finally {
      await rm(repoRoot, { recursive: true });
    }
  });
});

describe('P20.02 — subagent-refactor-review recorder mode (no --subagent)', () => {
  it('records outcome/reviewedHeadSha on the refactor-review ticket-state fields only, without touching status', () => {
    const state = baseState([baseTicket()]);
    const next = recordRefactorReviewOutcome({
      state,
      ticketId: 'P20.02',
      outcome: 'clean',
      reviewedHeadSha: 'sha-abc',
      agentName: 'claude',
      artifactPath: deriveRefactorReviewLedgerPath(
        state.reviewsDirPath,
        'P20.02',
      ),
    });
    const ticket = next.tickets.find((t) => t.id === 'P20.02')!;
    expect(ticket.status).toBe('verified');
    expect(ticket.refactorReviewOutcome).toBe('clean');
    expect(ticket.refactorReviewedHeadSha).toBe('sha-abc');
    expect(ticket.refactorReviewAgent).toBe('claude');
  });

  it('requires at least one patch commit when outcome is patched', () => {
    const state = baseState([baseTicket()]);
    expect(() =>
      recordRefactorReviewOutcome({
        state,
        ticketId: 'P20.02',
        outcome: 'patched',
        reviewedHeadSha: 'sha-abc',
      }),
    ).toThrow(/patch commit/i);
  });
});

describe('P20.02 — subagent-refactor-review record-deferred', () => {
  it('appends a deferred row with the reason captured', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'p20-02-deferred-'));
    try {
      const ledgerPath = join(
        repoRoot,
        deriveRefactorReviewLedgerPath(
          'docs/product/delivery/phase-20/reviews',
          'P20.02',
        ),
      );
      const invocation = buildRunnerInvocation(
        'operator-recorder',
        'sha-abc',
        'deferred',
        { terminatedReason: 'completed', findings: ['not worth the churn'] },
      );
      appendInvocationToArtifact(ledgerPath, 'P20.02', invocation);

      const artifact = readSubagentRunnerArtifact(ledgerPath, 'P20.02');
      const last = artifact.invocations[artifact.invocations.length - 1]!;
      expect(last.outcome).toBe('deferred');
      expect(last.findings).toEqual(['not worth the churn']);
    } finally {
      await rm(repoRoot, { recursive: true });
    }
  });
});

describe('P20.02 — runProgrammaticSubagentReview (generic runner core reuse)', () => {
  it('invokes the requested runner with the exact refactor prompt bytes and reports clean', () => {
    let capturedPrompt: string | undefined;
    const result = runProgrammaticSubagentReview({
      requestedRunner: 'codex-cli',
      reviewPrompt: SUBSTANTIVE_PROMPT,
      worktreePath: '/tmp/p20_02',
      spawn: (bin, args) => {
        capturedPrompt = args[args.length - 1];
        return { status: 0, stdout: 'clean review', stderr: '' };
      },
      readHeadSha: () => 'sha-fixed',
      listDirtyPaths: () => [],
      listDiffPaths: () => [],
      classify: () => ({
        terminatedReason: 'completed',
        runnerSelfReport: 'completed',
      }),
    });

    expect(capturedPrompt).toBe(SUBSTANTIVE_PROMPT);
    expect(result.usedRunner).toBe('codex-cli');
    expect(result.outcome).toBe('clean');
    expect(result.terminatedReason).toBe('completed');
    expect(result.headSha).toBe('sha-fixed');
  });

  it('collapses to skipped/advisory_violation when the runner writes files', () => {
    let dirtyPathsCall = 0;
    const result = runProgrammaticSubagentReview({
      requestedRunner: 'codex-cli',
      reviewPrompt: SUBSTANTIVE_PROMPT,
      worktreePath: '/tmp/p20_02',
      spawn: () => ({ status: 0, stdout: 'clean review', stderr: '' }),
      readHeadSha: () => 'sha-fixed',
      listDirtyPaths: () => {
        dirtyPathsCall += 1;
        // Simulate a new dirty file appearing only after the runner ran.
        return dirtyPathsCall > 2 ? ['tools/delivery/refactor-review.ts'] : [];
      },
      listDiffPaths: () => [],
      classify: () => ({
        terminatedReason: 'completed',
        runnerSelfReport: 'completed',
      }),
    });

    expect(result.outcome).toBe('skipped');
    expect(result.terminatedReason).toBe('advisory_violation');
    expect(result.runnerWroteFiles).toBe(true);
  });

  it('falls back to skipped when the requested runner is unavailable and no fallback succeeds', () => {
    const result = runProgrammaticSubagentReview({
      requestedRunner: 'codex-cli',
      reviewPrompt: SUBSTANTIVE_PROMPT,
      worktreePath: '/tmp/p20_02',
      spawn: () => {
        const error = new Error('not found') as Error & { code?: string };
        error.code = 'ENOENT';
        return { status: null, error };
      },
      readHeadSha: () => 'sha-fixed',
      listDirtyPaths: () => [],
      listDiffPaths: () => [],
      classify: () => ({
        terminatedReason: 'runner_unavailable',
        runnerSelfReport: null,
      }),
    });

    expect(result.usedRunner).toBe('skipped');
    expect(result.outcome).toBe('skipped');
  });

  it('detects a rewrite of an already-dirty path via the worktree fingerprint', () => {
    let fingerprintCall = 0;
    const result = runProgrammaticSubagentReview({
      requestedRunner: 'codex-cli',
      reviewPrompt: SUBSTANTIVE_PROMPT,
      worktreePath: '/tmp/p20_02',
      spawn: () => ({ status: 0, stdout: 'clean review', stderr: '' }),
      readHeadSha: () => 'sha-fixed',
      // Same dirty path before and after — path-membership alone sees no
      // change, but the file's content changed underneath it.
      listDirtyPaths: () => ['already/dirty.ts'],
      listDiffPaths: () => [],
      readWorktreeFingerprint: () => {
        fingerprintCall += 1;
        return fingerprintCall === 1
          ? 'fingerprint-before'
          : 'fingerprint-after';
      },
      classify: () => ({
        terminatedReason: 'completed',
        runnerSelfReport: 'completed',
      }),
    });

    expect(result.runnerWroteFiles).toBe(true);
    expect(result.outcome).toBe('skipped');
    expect(result.terminatedReason).toBe('advisory_violation');
  });

  it('detects writes made by a runner that timed out before a successful fallback', () => {
    let spawnCall = 0;
    let dirtyPathsCall = 0;
    const result = runProgrammaticSubagentReview({
      requestedRunner: 'codex-cli',
      reviewPrompt: SUBSTANTIVE_PROMPT,
      worktreePath: '/tmp/p20_02',
      spawn: () => {
        spawnCall += 1;
        if (spawnCall === 1) {
          // First attempt (codex-cli) times out after writing a file.
          return { status: null, signal: 'SIGTERM', stdout: '', stderr: '' };
        }
        // Fallback attempt (claude-cli) completes cleanly.
        return { status: 0, stdout: 'clean review', stderr: '' };
      },
      readHeadSha: () => 'sha-fixed',
      listDirtyPaths: () => {
        dirtyPathsCall += 1;
        // Only the very first call (the pre-loop snapshot) is clean. Every
        // call after that — including the timed-out attempt's own pre-run
        // snapshot — sees the file the timed-out process left behind,
        // since nothing cleans it up before the whole-invocation check.
        return dirtyPathsCall === 1 ? [] : ['left-behind.ts'];
      },
      listDiffPaths: () => [],
      classify: () => ({
        terminatedReason: 'completed',
        runnerSelfReport: 'completed',
      }),
    });

    expect(result.runnerWroteFiles).toBe(true);
    expect(result.outcome).toBe('skipped');
    expect(result.terminatedReason).toBe('advisory_violation');
  });
});
