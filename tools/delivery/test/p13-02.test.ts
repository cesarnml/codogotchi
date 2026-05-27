import { describe, expect, it } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { getUsage, parseCliArgs } from '../cli';
import { resolveNextCommand } from '../format';
import type { ResolvedOrchestratorConfig } from '../runtime-config';
import type { TicketState } from '../types';
import {
  assertSubagentAdversarialPromptPresent,
  deriveSubagentAdversarialPromptPath,
  isValidSubagentAdversarialPromptContent,
  writeSubagentAdversarialPrompt,
} from '../subagent-prompt';

// P13.02 — adversarial review prompt-authoring step.
//
// Invariants:
//   1. CLI surface exposes `write-subagent-adversarial-review` and parses it.
//   2. A `verified` code ticket with subagentReview enabled and no recorded
//      adversarial prompt routes to `write-subagent-adversarial-review` before
//      `subagent-review`.
//   3. Once the prompt is recorded, the next command becomes `subagent-review`.
//   4. Doc-only tickets that auto-skipped post-verify (verifyOutcome=skipped)
//      remain routed to `subagent-review` (which auto-records skipped) and do
//      not require an adversarial prompt.
//   5. With `subagentReview: disabled`, the prompt step is bypassed.
//   6. The prompt-gate helper raises a clear error for code tickets that lack
//      a persisted prompt artifact, and is a no-op when the prompt exists.
//   7. The prompt content validator rejects empty or placeholder-only content
//      and accepts filled prompts.

const baseConfig: ResolvedOrchestratorConfig = {
  defaultBranch: 'main',
  planRoot: 'docs',
  runtime: 'bun',
  packageManager: 'bun',
  ticketBoundaryMode: 'cook',
  reviewPolicy: {
    subagentReview: 'skip_doc_only',
    prReview: 'disabled',
  },
};

const configSubagentDisabled: ResolvedOrchestratorConfig = {
  ...baseConfig,
  reviewPolicy: { subagentReview: 'disabled', prReview: 'disabled' },
};

const planPath = 'docs/product/delivery/phase-13/implementation-plan.md';

function baseTicket(overrides: Partial<TicketState> = {}): TicketState {
  return {
    id: 'P13.02',
    title: 'Add write-subagent-adversarial-review prompt step',
    slug: 'add-write-subagent-adversarial-review-prompt-step',
    ticketFile:
      'docs/product/delivery/phase-13/ticket-02-write-subagent-adversarial-review-step.md',
    redPolicy: 'required',
    status: 'verified',
    branch: 'agents/p13-02-add-write-subagent-adversarial-review-prompt-step',
    baseBranch:
      'agents/p13-01-fix-runner-invocation-and-capture-raw-runner-evidence',
    worktreePath: '/tmp/p13_02',
    verifiedAt: '2026-05-20T00:00:00.000Z',
    verifyOutcome: 'clean',
    ...overrides,
  };
}

describe('P13.02 — CLI surface', () => {
  it('lists write-subagent-adversarial-review in usage between post-verify and subagent-review', () => {
    const usage = getUsage('bun run deliver');
    expect(usage).toContain('write-subagent-adversarial-review');
    const subagentReviewIdx = usage.indexOf('subagent-review ');
    const promptIdx = usage.indexOf('write-subagent-adversarial-review');
    expect(promptIdx).toBeGreaterThan(-1);
    expect(promptIdx).toBeLessThan(subagentReviewIdx);
  });

  it('parses the write-subagent-adversarial-review command with an optional ticket id', () => {
    const parsed = parseCliArgs(
      ['--plan', planPath, 'write-subagent-adversarial-review', 'P13.02'],
      getUsage('bun run deliver'),
    );
    expect(parsed.command).toBe('write-subagent-adversarial-review');
    expect(parsed.positionals).toEqual(['P13.02']);
    expect(parsed.planPath).toBe(planPath);
  });

  it('parses the bare write-subagent-adversarial-review command (no ticket id)', () => {
    const parsed = parseCliArgs(
      ['--plan', planPath, 'write-subagent-adversarial-review'],
      getUsage('bun run deliver'),
    );
    expect(parsed.command).toBe('write-subagent-adversarial-review');
    expect(parsed.positionals).toEqual([]);
  });
});

describe('P13.02 — resolveNextCommand routes verified code tickets through write-subagent-adversarial-review', () => {
  it('verified + subagentReview enabled + no prompt artifact → write-subagent-adversarial-review', () => {
    const ticket = baseTicket({ subagentAdversarialPromptPath: undefined });
    expect(
      resolveNextCommand('verified', baseConfig, planPath, ticket.id, ticket),
    ).toBe(
      `bun run deliver --plan ${planPath} write-subagent-adversarial-review`,
    );
  });

  it('verified + subagentReview enabled + prompt artifact recorded → subagent-review', () => {
    const ticket = baseTicket({
      subagentAdversarialPromptPath:
        'docs/product/delivery/phase-13/reviews/P13.02-subagent-review.prompt.md',
    });
    expect(
      resolveNextCommand('verified', baseConfig, planPath, ticket.id, ticket),
    ).toBe(`bun run deliver --plan ${planPath} subagent-review`);
  });

  it('verified + subagentReview enabled + verifyOutcome=skipped (doc-only) → subagent-review (auto-skip path)', () => {
    const ticket = baseTicket({ verifyOutcome: 'skipped' });
    expect(
      resolveNextCommand('verified', baseConfig, planPath, ticket.id, ticket),
    ).toBe(`bun run deliver --plan ${planPath} subagent-review`);
  });

  it('verified + subagentReview disabled → open-pr (prompt step bypassed)', () => {
    const ticket = baseTicket();
    expect(
      resolveNextCommand(
        'verified',
        configSubagentDisabled,
        planPath,
        ticket.id,
        ticket,
      ),
    ).toBe(`bun run deliver --plan ${planPath} open-pr`);
  });
});

describe('P13.02 — adversarial prompt helper', () => {
  it('derives a deterministic ticket-scoped prompt path under the reviews dir', () => {
    expect(
      deriveSubagentAdversarialPromptPath(
        'docs/product/delivery/phase-13/reviews',
        'P13.02',
      ),
    ).toBe(
      'docs/product/delivery/phase-13/reviews/P13.02-subagent-review.prompt.md',
    );
  });

  it('rejects empty, whitespace-only, or placeholder-like prompt content', () => {
    expect(isValidSubagentAdversarialPromptContent('')).toBe(false);
    expect(isValidSubagentAdversarialPromptContent('   \n\t')).toBe(false);
    expect(
      isValidSubagentAdversarialPromptContent('Some prompt with <TODO> left'),
    ).toBe(false);
    expect(
      isValidSubagentAdversarialPromptContent(
        '# Adversarial review for P13.02\n\n' +
          'Invariants: foo must hold.\n' +
          'Attack surfaces: bar parsing path.\n' +
          'Diff context: tools/delivery/cli.ts.\n',
      ),
    ).toBe(true);
  });

  it('writeSubagentAdversarialPrompt persists the content and returns relative path metadata', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'p13-02-prompt-'));
    const reviewsDirPath = 'docs/product/delivery/phase-13/reviews';
    mkdirSync(join(repoRoot, reviewsDirPath), { recursive: true });
    try {
      const content =
        '# Adversarial review for P13.02\n\n' +
        'Invariants: prompt artifact must exist before runner invocation.\n' +
        'Attack surfaces: cli-runner subagent-review dispatch, status next command.\n' +
        'Diff context: tools/delivery/format.ts, tools/delivery/cli-runner.ts.\n';

      const result = writeSubagentAdversarialPrompt({
        repoRoot,
        reviewsDirPath,
        ticketId: 'P13.02',
        content,
      });

      expect(result.relativePath).toBe(
        'docs/product/delivery/phase-13/reviews/P13.02-subagent-review.prompt.md',
      );
      expect(result.absolutePath).toBe(join(repoRoot, result.relativePath));
      expect(typeof result.writtenAt).toBe('string');
    } finally {
      await rm(repoRoot, { recursive: true, force: true });
    }
  });

  it('writeSubagentAdversarialPrompt refuses invalid prompt content', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'p13-02-prompt-bad-'));
    try {
      expect(() =>
        writeSubagentAdversarialPrompt({
          repoRoot,
          reviewsDirPath: 'docs/product/delivery/phase-13/reviews',
          ticketId: 'P13.02',
          content: '',
        }),
      ).toThrow(/prompt/i);
    } finally {
      await rm(repoRoot, { recursive: true, force: true });
    }
  });
});

describe('P13.02 — subagent-review gate refuses to run runner without a recorded prompt', () => {
  it('throws for a code ticket when the prompt artifact path is unset and subagentReview is enabled', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'p13-02-gate-'));
    try {
      const ticket = baseTicket({ subagentAdversarialPromptPath: undefined });
      expect(() =>
        assertSubagentAdversarialPromptPresent({
          repoRoot,
          ticket,
          isDocOnly: false,
          policy: 'skip_doc_only',
        }),
      ).toThrow(/write-subagent-adversarial-review/);
    } finally {
      await rm(repoRoot, { recursive: true, force: true });
    }
  });

  it('throws when the recorded prompt path does not exist on disk', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'p13-02-gate-missing-'));
    try {
      const ticket = baseTicket({
        subagentAdversarialPromptPath:
          'docs/product/delivery/phase-13/reviews/P13.02-subagent-review.prompt.md',
      });
      expect(() =>
        assertSubagentAdversarialPromptPresent({
          repoRoot,
          ticket,
          isDocOnly: false,
          policy: 'skip_doc_only',
        }),
      ).toThrow(/prompt/i);
    } finally {
      await rm(repoRoot, { recursive: true, force: true });
    }
  });

  it('is a no-op when the prompt artifact exists on disk', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'p13-02-gate-ok-'));
    const reviewsDirPath = 'docs/product/delivery/phase-13/reviews';
    mkdirSync(join(repoRoot, reviewsDirPath), { recursive: true });
    const promptPath = join(
      repoRoot,
      reviewsDirPath,
      'P13.02-subagent-review.prompt.md',
    );
    await writeFile(
      promptPath,
      '# Adversarial review for P13.02\n\nInvariants...\nAttack surfaces...\nDiff context...\n',
      'utf-8',
    );
    try {
      const ticket = baseTicket({
        subagentAdversarialPromptPath: `${reviewsDirPath}/P13.02-subagent-review.prompt.md`,
      });
      expect(() =>
        assertSubagentAdversarialPromptPresent({
          repoRoot,
          ticket,
          isDocOnly: false,
          policy: 'skip_doc_only',
        }),
      ).not.toThrow();
    } finally {
      await rm(repoRoot, { recursive: true, force: true });
    }
  });

  it('is a no-op for doc-only tickets under skip_doc_only (auto-skip path)', () => {
    const ticket = baseTicket({ subagentAdversarialPromptPath: undefined });
    expect(() =>
      assertSubagentAdversarialPromptPresent({
        repoRoot: '/tmp',
        ticket,
        isDocOnly: true,
        policy: 'skip_doc_only',
      }),
    ).not.toThrow();
  });

  it('is a no-op when subagentReview is disabled', () => {
    const ticket = baseTicket({ subagentAdversarialPromptPath: undefined });
    expect(() =>
      assertSubagentAdversarialPromptPresent({
        repoRoot: '/tmp',
        ticket,
        isDocOnly: false,
        policy: 'disabled',
      }),
    ).not.toThrow();
  });
});
