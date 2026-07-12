import { describe, expect, it } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  buildRunnerInvocation,
  decideSubagentReviewMode,
  validateRunnerArtifact,
} from '../subagent-runner';
import type {
  RunnerAttemptResult,
  SubagentRunnerArtifact,
  SubagentRunnerInvocation,
} from '../subagent-runner';
import type { TicketState } from '../types';

// These two symbols are introduced by P13.03 implementation. They are imported
// dynamically so missing exports manifest as per-test failures rather than a
// file-level load error that masks the rest of the suite.
async function loadDecideAdvisoryRunnerOutcome(): Promise<
  (
    result: Extract<RunnerAttemptResult, { status: 'ran' }>,
    info: { runnerWroteFiles: boolean },
  ) => { outcome: 'clean' | 'patched' | 'skipped'; terminatedReason: string }
> {
  const mod = (await import('../subagent-runner')) as Record<string, unknown>;
  const fn = mod['decideAdvisoryRunnerOutcome'];
  if (typeof fn !== 'function') {
    throw new Error(
      'decideAdvisoryRunnerOutcome is not exported from subagent-runner',
    );
  }
  return fn as never;
}

async function loadRequireSubagentAdversarialPromptForRunner(): Promise<
  (input: { repoRoot: string; ticket: TicketState }) => string
> {
  const mod = (await import('../subagent-prompt')) as Record<string, unknown>;
  const fn = mod['requireSubagentAdversarialPromptForRunner'];
  if (typeof fn !== 'function') {
    throw new Error(
      'requireSubagentAdversarialPromptForRunner is not exported from subagent-prompt',
    );
  }
  return fn as never;
}

// P13.03 — make the subagent runner consume the persisted prompt and refuse
// to record any runner-driven file change as a valid review outcome.
//
// Invariants asserted here:
//   1. Each programmatic runner invocation persists the exact filled prompt
//      inline on the invocation record so audit evidence is byte-for-byte
//      reproducible.
//   2. Runner-attributed file changes are a contract violation, not a valid
//      `patched` outcome — the advisory decision collapses to
//      `outcome=skipped, terminatedReason='advisory_violation'`.
//   3. `'advisory_violation'` is a first-class terminatedReason value and
//      round-trips through artifact validation.
//   4. Primary-agent recorder mode can still record `patched <reviewed-sha>
//      <patch-sha>` even after a runner invocation already exists for the
//      current HEAD.
//   5. The runner-prompt resolver refuses to fall back to a generic
//      changed-files prompt: missing artifact → hard error pointing at
//      `write-subagent-adversarial-review`, present artifact → exact bytes.

function baseTicket(overrides: Partial<TicketState> = {}): TicketState {
  return {
    id: 'P13.03',
    title: 'Make subagent-review consume the written prompt',
    slug: 'make-subagent-review-consume-the-written-prompt',
    ticketFile:
      'docs/product/delivery/phase-13/ticket-03-subagent-review-consumes-prompt-and-enforces-advisory-only.md',
    redPolicy: 'required',
    status: 'verified',
    branch: 'agents/p13-03',
    baseBranch: 'agents/p13-02',
    worktreePath: '/tmp/p13_03',
    verifiedAt: '2026-05-20T00:00:00.000Z',
    verifyOutcome: 'clean',
    ...overrides,
  };
}

describe('P13.03 — runner invocation records prompt and outcome path refs', () => {
  it('round-trips filledPrompt and rawOutput path refs through validateRunnerArtifact', () => {
    const filledPrompt =
      'docs/product/delivery/phase-13/reviews/P13.03-subagent-review.prompt.md';
    const rawOutput =
      'docs/product/delivery/phase-13/reviews/P13.03-subagent-review.report.md';

    const invocation = buildRunnerInvocation('codex-cli', 'abc1234', 'clean', {
      terminatedReason: 'completed',
      fallbackLevel: 'preferred',
      rawOutput,
      filledPrompt,
    });

    expect(invocation.filledPrompt).toBe(filledPrompt);
    expect(invocation.rawOutput).toBe(rawOutput);

    const artifact: SubagentRunnerArtifact = {
      ticket: 'P13.03',
      invocations: [invocation],
    };
    const validated = validateRunnerArtifact(artifact);
    expect(validated).not.toBeNull();
    expect(validated?.invocations[0]?.filledPrompt).toBe(filledPrompt);
    expect(validated?.invocations[0]?.rawOutput).toBe(rawOutput);
  });

  it('rejects non-string filledPrompt values via validateRunnerArtifact', () => {
    const bad = {
      ticket: 'P13.03',
      invocations: [
        {
          runnerKind: 'codex-cli',
          reviewedHeadSha: 'abc1234',
          outcome: 'clean',
          completedAt: '2026-05-20T00:00:00.000Z',
          terminatedReason: 'completed',
          findings: [],
          probedSurfaces: [],
          patches: [],
          filledPrompt: 42,
        },
      ],
    };
    expect(validateRunnerArtifact(bad)).toBeNull();
  });
});

describe('P13.03 — runner is advisory-only (no-write contract)', () => {
  it('accepts advisory_violation as a valid terminatedReason in artifacts', () => {
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P13.03',
      invocations: [
        buildRunnerInvocation('codex-cli', 'abc1234', 'skipped', {
          terminatedReason: 'advisory_violation',
          rawOutput:
            'docs/product/delivery/phase-13/reviews/P13.03-subagent-review.report.md',
        }),
      ],
    };
    expect(validateRunnerArtifact(artifact)).not.toBeNull();
  });

  it('collapses runner-clean to skipped+advisory_violation when runner produced writes', async () => {
    const decideAdvisoryRunnerOutcome = await loadDecideAdvisoryRunnerOutcome();
    const ran: Extract<RunnerAttemptResult, { status: 'ran' }> = {
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'completed',
      rawOutput: 'review prose',
    };
    expect(
      decideAdvisoryRunnerOutcome(ran, { runnerWroteFiles: true }),
    ).toEqual({
      outcome: 'skipped',
      terminatedReason: 'advisory_violation',
    });
  });

  it('collapses runner-patched to skipped+advisory_violation when runner produced writes', async () => {
    const decideAdvisoryRunnerOutcome = await loadDecideAdvisoryRunnerOutcome();
    const ran: Extract<RunnerAttemptResult, { status: 'ran' }> = {
      status: 'ran',
      outcome: 'patched',
      terminatedReason: 'completed',
      rawOutput: 'review prose',
    };
    expect(
      decideAdvisoryRunnerOutcome(ran, { runnerWroteFiles: true }),
    ).toEqual({
      outcome: 'skipped',
      terminatedReason: 'advisory_violation',
    });
  });

  it('never returns outcome=patched from the runner advisory path', async () => {
    const decideAdvisoryRunnerOutcome = await loadDecideAdvisoryRunnerOutcome();
    const ran: Extract<RunnerAttemptResult, { status: 'ran' }> = {
      status: 'ran',
      outcome: 'patched',
      terminatedReason: 'completed',
      rawOutput: 'review prose',
    };
    const decided = decideAdvisoryRunnerOutcome(ran, {
      runnerWroteFiles: false,
    });
    expect(decided.outcome).not.toBe('patched');
  });

  it('preserves non-completed terminatedReason without forcing advisory_violation', async () => {
    const decideAdvisoryRunnerOutcome = await loadDecideAdvisoryRunnerOutcome();
    const ran: Extract<RunnerAttemptResult, { status: 'ran' }> = {
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'rate_limit',
      rawOutput: 'You\u2019ve hit your limit',
    };
    expect(
      decideAdvisoryRunnerOutcome(ran, { runnerWroteFiles: false }),
    ).toEqual({
      outcome: 'skipped',
      terminatedReason: 'rate_limit',
    });
  });

  it('records clean only when runner completed and produced no writes', async () => {
    const decideAdvisoryRunnerOutcome = await loadDecideAdvisoryRunnerOutcome();
    const ran: Extract<RunnerAttemptResult, { status: 'ran' }> = {
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'completed',
      rawOutput: 'review prose',
    };
    expect(
      decideAdvisoryRunnerOutcome(ran, { runnerWroteFiles: false }),
    ).toEqual({
      outcome: 'clean',
      terminatedReason: 'completed',
    });
  });
});

describe('P13.03 — recorder mode still records primary-agent patches after a runner invocation', () => {
  it('routes outcome=patched + sha to recorder even when a runner invocation already exists for HEAD', () => {
    const headSha = 'currentHead';
    const existingArtifact: SubagentRunnerArtifact = {
      ticket: 'P13.03',
      invocations: [
        buildRunnerInvocation('codex-cli', headSha, 'clean', {
          terminatedReason: 'completed',
          rawOutput: 'no issues',
          filledPrompt: 'prompt body',
        }),
      ],
    };

    const decision = decideSubagentReviewMode(
      { outcome: 'patched', reviewedHeadSha: headSha, force: false },
      existingArtifact,
      headSha,
    );

    expect(decision.kind).toBe('recorder');
    if (decision.kind === 'recorder') {
      expect(decision.outcome).toBe('patched');
      expect(decision.reviewedHeadSha).toBe(headSha);
    }
  });

  it('skipped runner invocations never block recorder dispatch', () => {
    const headSha = 'currentHead';
    const skippedInvocation: SubagentRunnerInvocation = buildRunnerInvocation(
      'codex-cli',
      headSha,
      'skipped',
      { terminatedReason: 'advisory_violation' },
    );
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P13.03',
      invocations: [skippedInvocation],
    };

    const decision = decideSubagentReviewMode(
      { outcome: 'patched', reviewedHeadSha: headSha, force: false },
      artifact,
      headSha,
    );
    expect(decision.kind).toBe('recorder');
  });
});

describe('P13.03 — runner-prompt resolver refuses generic fallback', () => {
  it('throws a write-subagent-adversarial-review error when the ticket has no recorded prompt path', async () => {
    const requireSubagentAdversarialPromptForRunner =
      await loadRequireSubagentAdversarialPromptForRunner();
    const repoRoot = await mkdtemp(join(tmpdir(), 'p13-03-prompt-missing-'));
    try {
      const ticket = baseTicket({ subagentAdversarialPromptPath: undefined });
      expect(() =>
        requireSubagentAdversarialPromptForRunner({ repoRoot, ticket }),
      ).toThrow(/write-subagent-adversarial-review/);
    } finally {
      await rm(repoRoot, { recursive: true, force: true });
    }
  });

  it('throws when the recorded prompt path does not exist on disk', async () => {
    const requireSubagentAdversarialPromptForRunner =
      await loadRequireSubagentAdversarialPromptForRunner();
    const repoRoot = await mkdtemp(join(tmpdir(), 'p13-03-prompt-disk-'));
    try {
      const ticket = baseTicket({
        subagentAdversarialPromptPath:
          'docs/product/delivery/phase-13/reviews/P13.03-subagent-review.prompt.md',
      });
      expect(() =>
        requireSubagentAdversarialPromptForRunner({ repoRoot, ticket }),
      ).toThrow(/prompt/i);
    } finally {
      await rm(repoRoot, { recursive: true, force: true });
    }
  });

  it('returns the exact persisted prompt bytes when the artifact exists', async () => {
    const requireSubagentAdversarialPromptForRunner =
      await loadRequireSubagentAdversarialPromptForRunner();
    const repoRoot = await mkdtemp(join(tmpdir(), 'p13-03-prompt-ok-'));
    const reviewsDirPath = 'docs/product/delivery/phase-13/reviews';
    mkdirSync(join(repoRoot, reviewsDirPath), { recursive: true });
    const relativePath = `${reviewsDirPath}/P13.03-subagent-review.prompt.md`;
    const content =
      '# Adversarial review for P13.03\n\n' +
      'Invariants: runner reads this exact file.\n' +
      'Attack surfaces: subagent-review dispatch.\n' +
      'Diff context: tools/delivery/cli-runner.ts.\n';
    await writeFile(join(repoRoot, relativePath), content, 'utf-8');
    try {
      const ticket = baseTicket({
        subagentAdversarialPromptPath: relativePath,
      });
      const resolved = requireSubagentAdversarialPromptForRunner({
        repoRoot,
        ticket,
      });
      expect(resolved).toBe(content);
    } finally {
      await rm(repoRoot, { recursive: true, force: true });
    }
  });
});

describe('P13.03 — generic runner prompt builder is no longer exported from subagent-runner', () => {
  it('subagent-runner.ts does not export buildSubagentReviewPrompt', async () => {
    const mod = (await import('../subagent-runner')) as Record<string, unknown>;
    expect(mod['buildSubagentReviewPrompt']).toBeUndefined();
  });
});
