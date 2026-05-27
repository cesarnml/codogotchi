import { describe, expect, it } from 'bun:test';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import type { DeliveryState } from '../types';
import { getUsage, parseCliArgs } from '../cli';
import {
  applyAdvanceBoundaryMode,
  copyLocalBootstrapFilesIfPresent,
  createOptions,
  derivePlanKey,
  openPullRequest,
  parsePlan,
  pollReview,
  reconcileLateReview,
  recordPostVerify,
  recordReview,
  resolvePlanPathForBranch,
  resolveReviewFetcher,
  resolveReviewTriager,
  runStandaloneAiReview,
  summarizeStateDifferences,
  syncStateFromExisting,
} from '../cli-runner';
import { formatStatus } from '../format';
import {
  eventsForAdvanceCommand,
  eventsForOpenPrCommand,
  eventsForPollReviewCommand,
  eventsForReconcileLateReviewCommand,
  eventsForRecordReviewCommand,
  eventsForStartCommand,
  formatNotificationMessage,
  formatReviewWindowMessage,
  notifyBestEffort,
  resolveNotifier,
} from '../notifications';
import { parseGitWorktreeList } from '../platform';
import { createPlatformAdapters } from '../platform-adapters';
import {
  assertReviewerFacingMarkdown,
  buildExternalAiReviewSection,
  buildPullRequestBody,
  buildPullRequestTitle,
  buildReviewMetadataRefreshBody,
  buildStandaloneAiReviewSection,
  mergeStandaloneAiReviewSection,
} from '../pr-metadata';
import {
  buildReviewPollCheckMinutes,
  parseAiReviewFetcherOutput,
  parseAiReviewTriagerOutput,
  parseResolveReviewThreadOutput,
  resolveNativeReviewThreads,
} from '../review';
import {
  generateRunDeliverInvocation,
  type ResolvedOrchestratorConfig,
} from '../runtime-config';
import {
  normalizeDeliveryStateFromPersisted,
  syncStateFromScratch,
} from '../state';
import {
  advanceToNextTicket,
  buildTicketHandoff,
  canAdvanceTicket,
  findTicketByBranch,
} from '../ticket-flow';
import { createDeliveryOrchestratorContext } from '../context';

async function readArtifactJson(cwd: string, relativePath: string) {
  return JSON.parse(await readFile(join(cwd, relativePath), 'utf8')) as Record<
    string,
    unknown
  >;
}

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

function testConfig(
  overrides: Partial<ResolvedOrchestratorConfig> = {},
): ResolvedOrchestratorConfig {
  return {
    ...baseConfig,
    ...overrides,
    reviewPolicy: overrides.reviewPolicy ?? baseConfig.reviewPolicy,
  };
}

function testContext(overrides: Partial<ResolvedOrchestratorConfig> = {}) {
  return createDeliveryOrchestratorContext(testConfig(overrides));
}

describe('delivery orchestrator', () => {
  it('parses an implementation plan into ordered tickets', () => {
    const tickets = parsePlan(
      `
# Phase 02 Implementation Plan

## Ticket Order

1. \`P2.01 Enclosure-First Feed Parsing\`
2. \`P2.02 Movie Matcher Allows Missing Codec\`

## Ticket Files

- \`ticket-01-enclosure-first-feed-parsing.md\`
- \`ticket-02-movie-matcher-allows-missing-codec.md\`

## Exit Condition
`,
      'docs/product/delivery/phase-02/implementation-plan.md',
    );

    expect(tickets).toEqual([
      {
        id: 'P2.01',
        title: 'Enclosure-First Feed Parsing',
        slug: 'enclosure-first-feed-parsing',
        redPolicy: 'required',
        ticketFile:
          'docs/product/delivery/phase-02/ticket-01-enclosure-first-feed-parsing.md',
      },
      {
        id: 'P2.02',
        title: 'Movie Matcher Allows Missing Codec',
        slug: 'movie-matcher-allows-missing-codec',
        redPolicy: 'required',
        ticketFile:
          'docs/product/delivery/phase-02/ticket-02-movie-matcher-allows-missing-codec.md',
      },
    ]);
  });

  it('parses ticket type and scope relative to the provided repo root', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'pr-title-scope-'));
    const planDir = join(repoRoot, 'docs/product/delivery/phase-99');

    try {
      await mkdir(planDir, { recursive: true });
      await writeFile(
        join(planDir, 'ticket-01-fix-relative-scope.md'),
        ['# P9.01 Relative Scope', '', 'Type: FIX', 'Scope: CLI', ''].join(
          '\n',
        ),
      );

      const tickets = parsePlan(
        `
# Phase 99 Implementation Plan

## Ticket Order

1. \`P9.01 Relative Scope\`

## Ticket Files

- \`ticket-01-fix-relative-scope.md\`

## Exit Condition
`,
        'docs/product/delivery/phase-99/implementation-plan.md',
        repoRoot,
      );

      expect(tickets).toEqual([
        {
          id: 'P9.01',
          title: 'Relative Scope',
          slug: 'relative-scope',
          type: 'fix',
          scope: 'cli',
          redPolicy: 'required',
          ticketFile:
            'docs/product/delivery/phase-99/ticket-01-fix-relative-scope.md',
        },
      ]);
    } finally {
      await rm(repoRoot, { recursive: true, force: true });
    }
  });

  it('builds options from a plan path', () => {
    expect(
      createOptions({
        planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      }),
    ).toMatchObject({
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      planKey: 'phase-03',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: 'docs/product/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
    });
  });

  it('parses boundary-mode CLI override', () => {
    const parsed = parseCliArgs(
      [
        '--plan',
        'docs/product/delivery/phase-03/implementation-plan.md',
        '--boundary-mode',
        'gated',
        'status',
      ],
      getUsage('bun run deliver'),
    );

    expect(parsed).toEqual({
      command: 'status',
      positionals: [],
      flags: new Set<string>(),
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      prNumber: undefined,
      boundaryMode: 'gated',
    });
  });

  it('normalizes legacy review command aliases to triage commands', () => {
    expect(
      parseCliArgs(['ai-review', '--pr', '19'], getUsage('bun run deliver')),
    ).toMatchObject({
      command: 'triage-standalone',
      prNumber: 19,
    });
    expect(
      parseCliArgs(
        [
          '--plan',
          'docs/product/delivery/phase-03/implementation-plan.md',
          'reconcile-late-review',
          'P3.01',
        ],
        getUsage('bun run deliver'),
      ),
    ).toMatchObject({
      command: 'triage-ticket',
      positionals: ['P3.01'],
    });
  });

  it('documents canonical triage commands in usage while keeping aliases visible', () => {
    const usage = getUsage('bun run deliver');

    expect(usage).toContain('triage-standalone [--pr <number>]');
    expect(usage).toContain('triage-ticket <ticket-id>');
    expect(usage).toContain('ai-review -> triage-standalone');
    expect(usage).toContain('reconcile-late-review -> triage-ticket');
  });

  it('rejects invalid boundary-mode CLI override', () => {
    expect(() =>
      parseCliArgs(
        [
          '--plan',
          'docs/product/delivery/phase-03/implementation-plan.md',
          '--boundary-mode',
          'sprint',
          'status',
        ],
        getUsage('bun run deliver'),
      ),
    ).toThrow(/Pass --boundary-mode <cook\|gated>/);
  });

  it('rejects missing boundary-mode CLI value with a specific error', () => {
    expect(() =>
      parseCliArgs(
        [
          '--plan',
          'docs/product/delivery/phase-03/implementation-plan.md',
          '--boundary-mode',
        ],
        getUsage('bun run deliver'),
      ),
    ).toThrow(/Missing value for --boundary-mode/);
  });

  it('formats status with the configured boundary mode', () => {
    expect(
      formatStatus(
        {
          planKey: 'engineering-epic-07',
          planPath:
            'docs/product/delivery/engineering-epic-07/implementation-plan.md',
          statePath: '.agents/delivery/engineering-epic-07/state.json',
          reviewsDirPath: '.agents/delivery/engineering-epic-07/reviews',
          handoffsDirPath: '.agents/delivery/engineering-epic-07/handoffs',
          reviewPollIntervalMinutes: 6,
          reviewPollMaxWaitMinutes: 12,
          tickets: [],
        },
        {
          defaultBranch: 'main',
          planRoot: 'docs',
          runtime: 'bun',
          packageManager: 'bun',
          ticketBoundaryMode: 'gated',
          reviewPolicy: {
            subagentReview: 'skip_doc_only',
            prReview: 'skip_doc_only',
          },
        },
      ),
    ).toContain('boundary_mode=gated');
  });

  it('syncs state while preserving runtime metadata and inferred branch chaining', () => {
    const options = createOptions({
      planPath: 'docs/product/delivery/phase-02/implementation-plan.md',
    });
    const existing: DeliveryState = {
      planKey: 'phase-02',
      planPath: options.planPath,
      statePath: options.statePath,
      reviewsDirPath: options.reviewsDirPath,
      handoffsDirPath: options.handoffsDirPath,
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P2.01',
          title: 'Enclosure-First Feed Parsing',
          slug: 'enclosure-first-feed-parsing',
          ticketFile:
            'docs/product/delivery/phase-02/ticket-01-enclosure-first-feed-parsing.md',
          status: 'done',
          branch: 'agents/p2-01-enclosure-first-feed-parsing',
          baseBranch: 'main',
          worktreePath: '/tmp/p2_01',
          handoffPath: '.agents/delivery/phase-02/handoffs/p2-01-handoff.md',
          handoffGeneratedAt: '2026-04-01T00:00:00.000Z',
          prNumber: 14,
          prUrl: 'https://example.test/pull/14',
        },
      ],
    };

    const synced = syncStateFromExisting(
      existing,
      [
        {
          id: 'P2.01',
          title: 'Enclosure-First Feed Parsing',
          slug: 'enclosure-first-feed-parsing',
          ticketFile:
            'docs/product/delivery/phase-02/ticket-01-enclosure-first-feed-parsing.md',
        },
        {
          id: 'P2.02',
          title: 'Movie Matcher Allows Missing Codec',
          slug: 'movie-matcher-allows-missing-codec',
          ticketFile:
            'docs/product/delivery/phase-02/ticket-02-movie-matcher-allows-missing-codec.md',
        },
      ],
      '/workspace/test_project',
      options,
      baseConfig,
    );

    expect(synced.tickets[0]?.status).toBe('done');
    expect(synced.tickets[0]?.prNumber).toBe(14);
    expect(synced.tickets[1]).toMatchObject({
      status: 'pending',
      branch: 'agents/p2-02-movie-matcher-allows-missing-codec',
      baseBranch: 'agents/p2-01-enclosure-first-feed-parsing',
    });
  });

  it('preserves subagent adversarial prompt fields through state roundtrip', () => {
    // Regression: syncStateWithPlan explicitly constructs each ticket object
    // and previously omitted subagentAdversarialPromptPath /
    // subagentAdversarialPromptWrittenAt, so the path written by
    // `write-subagent-adversarial-review` was silently dropped on the next
    // command's load → `subagent-review` then threw
    // "requires a subagent adversarial review prompt" even though the file
    // was on disk and the path was persisted in state.json.
    const options = createOptions({
      planPath: 'docs/product/delivery/phase-02/implementation-plan.md',
    });
    const writtenAt = '2026-05-20T17:31:26.246Z';
    const promptPath =
      'docs/product/delivery/phase-02/reviews/P2.01-subagent-review.prompt.md';

    const existing: DeliveryState = {
      planKey: 'phase-02',
      planPath: options.planPath,
      statePath: options.statePath,
      reviewsDirPath: options.reviewsDirPath,
      handoffsDirPath: options.handoffsDirPath,
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P2.01',
          title: 'Enclosure-First Feed Parsing',
          slug: 'enclosure-first-feed-parsing',
          ticketFile:
            'docs/product/delivery/phase-02/ticket-01-enclosure-first-feed-parsing.md',
          status: 'verified',
          branch: 'agents/p2-01-enclosure-first-feed-parsing',
          baseBranch: 'main',
          worktreePath: '/tmp/p2_01',
          verifyOutcome: 'clean',
          subagentAdversarialPromptPath: promptPath,
          subagentAdversarialPromptWrittenAt: writtenAt,
        },
      ],
    };

    const synced = syncStateFromExisting(
      existing,
      [
        {
          id: 'P2.01',
          title: 'Enclosure-First Feed Parsing',
          slug: 'enclosure-first-feed-parsing',
          ticketFile:
            'docs/product/delivery/phase-02/ticket-01-enclosure-first-feed-parsing.md',
        },
      ],
      '/workspace/test_project',
      options,
      baseConfig,
    );

    expect(synced.tickets[0]?.subagentAdversarialPromptPath).toBe(promptPath);
    expect(synced.tickets[0]?.subagentAdversarialPromptWrittenAt).toBe(
      writtenAt,
    );
  });

  it('builds a handoff artifact that resets context and carries forward prior review state', () => {
    const handoff = buildTicketHandoff(
      {
        planKey: 'phase-02',
        planPath: 'docs/product/delivery/phase-02/implementation-plan.md',
        statePath: '.agents/delivery/phase-02/state.json',
        reviewsDirPath: '.agents/delivery/phase-02/reviews',
        handoffsDirPath: '.agents/delivery/phase-02/handoffs',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
        tickets: [
          {
            id: 'P2.01',
            title: 'Enclosure-First Feed Parsing',
            slug: 'enclosure-first-feed-parsing',
            ticketFile:
              'docs/product/delivery/phase-02/ticket-01-enclosure-first-feed-parsing.md',
            status: 'done',
            branch: 'agents/p2-01-enclosure-first-feed-parsing',
            baseBranch: 'main',
            worktreePath: '/tmp/p2_01',
            prUrl: 'https://example.test/pull/14',
            reviewFetchArtifactPath:
              '.agents/delivery/phase-02/reviews/P2.01-pr-review.fetch.json',
            reviewOutcome: 'patched',
            reviewNote: 'patched the two actionable correctness issues',
          },
          {
            id: 'P2.02',
            title: 'Movie Matcher Allows Missing Codec',
            slug: 'movie-matcher-allows-missing-codec',
            ticketFile:
              'docs/product/delivery/phase-02/ticket-02-movie-matcher-allows-missing-codec.md',
            status: 'pending',
            branch: 'agents/p2-02-movie-matcher-allows-missing-codec',
            baseBranch: 'agents/p2-01-enclosure-first-feed-parsing',
            worktreePath: '/tmp/p2_02',
          },
        ],
      },
      {
        id: 'P2.02',
        title: 'Movie Matcher Allows Missing Codec',
        ticketFile:
          'docs/product/delivery/phase-02/ticket-02-movie-matcher-allows-missing-codec.md',
        branch: 'agents/p2-02-movie-matcher-allows-missing-codec',
        baseBranch: 'agents/p2-01-enclosure-first-feed-parsing',
        worktreePath: '/tmp/p2_02',
      },
    );

    expect(handoff).toContain('# Ticket Handoff');
    expect(handoff).toContain('## Required Reads');
    expect(handoff).toContain('docs/template/overview/start-here.md');
    expect(handoff).toContain('Start from the current repository state');
    expect(handoff).toContain('Previous PR: https://example.test/pull/14');
    expect(handoff).toContain('Review outcome: `patched`');
    expect(handoff).toContain(
      'Review fetch artifact: `.agents/delivery/phase-02/reviews/P2.01-pr-review.fetch.json`',
    );
  });

  it('derives plan keys from implementation plan directories', () => {
    expect(
      derivePlanKey('docs/product/delivery/phase-03/implementation-plan.md'),
    ).toBe('phase-03');
    expect(derivePlanKey('./plans/custom/implementation-plan.md')).toBe(
      'custom',
    );
  });

  it('parses git worktree porcelain output and finds branch metadata', () => {
    expect(
      parseGitWorktreeList(
        [
          'worktree /Users/cesar/code/test_project',
          'HEAD abc123',
          'branch refs/heads/main',
          '',
          'worktree /tmp/worktrees/3cc9/test_project',
          'HEAD def456',
          'branch refs/heads/agents/ai-code-review-template-boundary',
          '',
        ].join('\n'),
      ),
    ).toEqual([
      {
        path: '/Users/cesar/code/test_project',
        branch: 'refs/heads/main',
      },
      {
        path: '/tmp/worktrees/3cc9/test_project',
        branch: 'refs/heads/agents/ai-code-review-template-boundary',
      },
    ]);
  });

  it('finds the tracked ticket for the current branch', () => {
    expect(
      findTicketByBranch(
        {
          planKey: 'phase-03',
          planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
          statePath: '.agents/delivery/phase-03/state.json',
          reviewsDirPath: '.agents/delivery/phase-03/reviews',
          handoffsDirPath: '.agents/delivery/phase-03/handoffs',
          reviewPollIntervalMinutes: 6,
          reviewPollMaxWaitMinutes: 12,
          tickets: [
            {
              id: 'P3.01',
              title: 'Persist Transmission Identity For Queued Torrents',
              slug: 'persist-transmission-identity-for-queued-torrents',
              ticketFile:
                'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
              status: 'done',
              branch:
                'agents/p3-01-persist-transmission-identity-for-queued-torrents',
              baseBranch: 'main',
              worktreePath: '/tmp/p3_01',
            },
            {
              id: 'P3.02',
              title: 'Reconcile Torrent Lifecycle From Transmission',
              slug: 'reconcile-torrent-lifecycle-from-transmission',
              ticketFile:
                'docs/product/delivery/phase-03/ticket-02-reconcile-torrent-lifecycle-from-transmission.md',
              status: 'in_review',
              branch:
                'agents/p3-02-reconcile-torrent-lifecycle-from-transmission',
              baseBranch:
                'agents/p3-01-persist-transmission-identity-for-queued-torrents',
              worktreePath: '/tmp/p3_02',
            },
          ],
        },
        'agents/p3-02-reconcile-torrent-lifecycle-from-transmission',
      )?.id,
    ).toBe('P3.02');
  });

  it('resolves a delivery plan from the current branch when the match is unique', () => {
    expect(
      resolvePlanPathForBranch(
        [
          {
            planPath: 'docs/product/delivery/phase-02/implementation-plan.md',
            tickets: [
              {
                id: 'P2.02',
                title: 'Movie Matcher Allows Missing Codec',
                slug: 'movie-matcher-allows-missing-codec',
                ticketFile:
                  'docs/product/delivery/phase-02/ticket-02-movie-matcher-allows-missing-codec.md',
              },
            ],
          },
          {
            planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
            tickets: [
              {
                id: 'P3.02',
                title: 'Reconcile Torrent Lifecycle From Transmission',
                slug: 'reconcile-torrent-lifecycle-from-transmission',
                ticketFile:
                  'docs/product/delivery/phase-03/ticket-02-reconcile-torrent-lifecycle-from-transmission.md',
              },
            ],
          },
        ],
        'agents/p3-02-reconcile-torrent-lifecycle-from-transmission',
      ),
    ).toBe('docs/product/delivery/phase-03/implementation-plan.md');
  });

  it('fails plan inference cleanly when no plan matches the current branch', () => {
    expect(() =>
      resolvePlanPathForBranch(
        [
          {
            planPath: 'docs/product/delivery/phase-02/implementation-plan.md',
            tickets: [
              {
                id: 'P2.02',
                title: 'Movie Matcher Allows Missing Codec',
                slug: 'movie-matcher-allows-missing-codec',
                ticketFile:
                  'docs/product/delivery/phase-02/ticket-02-movie-matcher-allows-missing-codec.md',
              },
            ],
          },
        ],
        'agents/not-a-ticket-branch',
      ),
    ).toThrow(
      'Could not infer a delivery plan for agents/not-a-ticket-branch. Pass --plan <plan-path>.',
    );
  });

  it('allows advance after clean, patched, or skipped review outcomes', () => {
    expect(
      canAdvanceTicket({
        id: 'P2.02',
        title: 'Movie Matcher Allows Missing Codec',
        slug: 'movie-matcher-allows-missing-codec',
        ticketFile:
          'docs/product/delivery/phase-02/ticket-02-movie-matcher-allows-missing-codec.md',
        status: 'reviewed',
        branch: 'agents/p2-02-movie-matcher-missing-codec',
        baseBranch: 'agents/p2-01-enclosure-first-feed-parsing',
        worktreePath: '/tmp/p2_02',
        reviewOutcome: 'clean',
      }),
    ).toBe(true);

    expect(
      canAdvanceTicket({
        id: 'P2.02',
        title: 'Movie Matcher Allows Missing Codec',
        slug: 'movie-matcher-allows-missing-codec',
        ticketFile:
          'docs/product/delivery/phase-02/ticket-02-movie-matcher-allows-missing-codec.md',
        status: 'reviewed',
        branch: 'agents/p2-02-movie-matcher-missing-codec',
        baseBranch: 'agents/p2-01-enclosure-first-feed-parsing',
        worktreePath: '/tmp/p2_02',
        reviewOutcome: 'skipped',
      }),
    ).toBe(true);

    expect(
      canAdvanceTicket({
        id: 'P2.02',
        title: 'Movie Matcher Allows Missing Codec',
        slug: 'movie-matcher-allows-missing-codec',
        ticketFile:
          'docs/product/delivery/phase-02/ticket-02-movie-matcher-allows-missing-codec.md',
        status: 'reviewed',
        branch: 'agents/p2-02-movie-matcher-missing-codec',
        baseBranch: 'agents/p2-01-enclosure-first-feed-parsing',
        worktreePath: '/tmp/p2_02',
        reviewOutcome: undefined,
      }),
    ).toBe(false);
  });

  it('uses the repo delivery PR title format from ticket metadata', () => {
    expect(
      buildPullRequestTitle({
        id: 'P3.02',
        title: 'Reconcile Torrent Lifecycle From Transmission',
        ticketFile: 'ticket-02-feat-torrent-lifecycle.md',
        type: 'feat',
      }),
    ).toBe('feat: reconcile torrent lifecycle from transmission [P3.02]');
    expect(
      buildPullRequestTitle({
        id: 'P3.02',
        title: 'Reconcile Torrent Lifecycle From Transmission',
        ticketFile: 'ticket-02-feat-torrent-lifecycle.md',
        type: 'feat',
        scope: 'transmission',
      }),
    ).toBe(
      'feat(transmission): reconcile torrent lifecycle from transmission [P3.02]',
    );
  });

  it('builds PR title from ticket metadata type and scope field', () => {
    expect(
      buildPullRequestTitle({
        id: 'P1.01',
        title: 'Fix state.json sync in advance',
        ticketFile: 'ticket-01-fix-state-sync.md',
        type: 'fix',
        scope: 'cli',
      }),
    ).toBe('fix(cli): fix state.json sync in advance [P1.01]');
    expect(
      buildPullRequestTitle({
        id: 'P1.01',
        title: 'Fix state.json sync in advance',
        ticketFile: 'ticket-01-fix-state-sync.md',
        type: 'fix',
      }),
    ).toBe('fix: fix state.json sync in advance [P1.01]');
  });

  it('does not derive PR title type from ticket filename', () => {
    expect(
      buildPullRequestTitle({
        id: 'P1.01',
        title: 'Fix state.json sync in advance',
        ticketFile: 'ticket-01-fix-state-sync.md',
      }),
    ).toBe('feat: fix state.json sync in advance [P1.01]');
  });

  const syncDeps = {
    cwd: '/tmp',
    defaultBranch: 'main',
    deriveBranchName: (d: { id: string; slug: string }) =>
      `agents/${d.id.toLowerCase()}-${d.slug}`,
    deriveWorktreePath: (cwd: string, id: string) =>
      `${cwd}/worktree-${id.toLowerCase()}`,
  };

  it('includes type and scope in PR title when TicketDefinition has both', () => {
    const state = syncStateFromScratch(
      [
        {
          id: 'P5.03',
          title: 'PR Scope Propagation From Ticket Metadata',
          slug: 'pr-scope-propagation-from-ticket-metadata',
          ticketFile:
            'docs/product/delivery/phase-05/ticket-03-pr-scope-propagation.md',
          type: 'fix',
          scope: 'pr-metadata',
        },
      ],
      createOptions({
        planPath: 'docs/product/delivery/phase-05/implementation-plan.md',
      }),
      undefined,
      syncDeps,
    );
    expect(buildPullRequestTitle(state.tickets[0])).toBe(
      'fix(pr-metadata): pr scope propagation from ticket metadata [P5.03]',
    );
  });

  it('type from ticket metadata overrides filename-derived type', () => {
    const state = syncStateFromScratch(
      [
        {
          id: 'P5.03',
          title: 'PR Scope Propagation From Ticket Metadata',
          slug: 'pr-scope-propagation-from-ticket-metadata',
          ticketFile:
            'docs/product/delivery/phase-05/ticket-03-pr-scope-propagation.md',
          type: 'fix',
        },
      ],
      createOptions({
        planPath: 'docs/product/delivery/phase-05/implementation-plan.md',
      }),
      undefined,
      syncDeps,
    );
    expect(buildPullRequestTitle(state.tickets[0])).toBe(
      'fix: pr scope propagation from ticket metadata [P5.03]',
    );
  });

  it('omits scope parens in PR title when TicketDefinition has no scope', () => {
    const state = syncStateFromScratch(
      [
        {
          id: 'P5.03',
          title: 'PR Scope Propagation From Ticket Metadata',
          slug: 'pr-scope-propagation-from-ticket-metadata',
          ticketFile:
            'docs/product/delivery/phase-05/ticket-03-pr-scope-propagation.md',
        },
      ],
      createOptions({
        planPath: 'docs/product/delivery/phase-05/implementation-plan.md',
      }),
      undefined,
      syncDeps,
    );
    expect(buildPullRequestTitle(state.tickets[0])).not.toContain('(');
  });

  it('resolves the notifier from Telegram env vars', () => {
    const originalToken = process.env.TELEGRAM_BOT_TOKEN;
    const originalChatId = process.env.TELEGRAM_CHAT_ID;
    delete process.env.TELEGRAM_BOT_TOKEN;
    delete process.env.TELEGRAM_CHAT_ID;

    expect(resolveNotifier()).toEqual({
      kind: 'noop',
      enabled: false,
    });

    process.env.TELEGRAM_BOT_TOKEN = 'bot-token';
    process.env.TELEGRAM_CHAT_ID = 'chat-id';

    expect(resolveNotifier()).toEqual({
      kind: 'telegram',
      enabled: true,
      botToken: 'bot-token',
      chatId: 'chat-id',
    });

    process.env.TELEGRAM_BOT_TOKEN = originalToken;
    process.env.TELEGRAM_CHAT_ID = originalChatId;
  });

  it('formats notification messages for milestone events', () => {
    expect(
      formatNotificationMessage('/tmp/test_project', {
        kind: 'ticket_started',
        planKey: 'phase-03',
        ticketId: 'P3.01',
        ticketTitle: 'Persist Transmission Identity For Queued Torrents',
        branch:
          'agents/p3-01-persist-transmission-identity-for-queued-torrents',
      }),
    ).toContain('Son of Anton\nP3.01 underway for phase-03.');
    expect(
      formatNotificationMessage('/tmp/test_project', {
        kind: 'run_blocked',
        planKey: 'phase-03',
        command: 'open-pr',
        reason: 'No in-progress ticket found to open as a PR.',
      }),
    ).toContain('Son of Anton\nStopped in phase-03.');
    expect(
      formatNotificationMessage('/tmp/test_project', {
        kind: 'standalone_review_started',
        prNumber: 32,
        prUrl: 'https://example.test/pull/32',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
      }),
    ).toContain('Son of Anton PR #32\nAI review started.');
    expect(
      formatNotificationMessage('/tmp/test_project', {
        kind: 'standalone_review_recorded',
        prNumber: 32,
        prUrl: 'https://example.test/pull/32',
        outcome: 'operator_input_needed',
        note: 'Actionable AI review findings were detected and still need follow-up.',
      }),
    ).toContain('AI review complete.');
  });

  it('merges the standalone triage section into a pr body', () => {
    const section = buildStandaloneAiReviewSection({
      outcome: 'operator_input_needed',
      note: 'Actionable AI review findings were detected.',
      vendors: ['coderabbit', 'qodo'],
      actionSummary: 'Flagged 2 finding comments for follow-up.',
      nonActionSummary: 'Ignored 1 summary comment.',
    });

    expect(
      mergeStandaloneAiReviewSection('## Summary\n- existing body', section),
    ).toContain('<!-- ai-review:start -->');
    expect(
      mergeStandaloneAiReviewSection(
        '## Summary\n- existing body\n\n<!-- ai-review:start -->\nold\n<!-- ai-review:end -->\n',
        section,
      ),
    ).not.toContain('\nold\n');
    const sanitized = mergeStandaloneAiReviewSection(
      '## Summary\n- existing body\n\n## Summary by CodeRabbit\n- noisy recap\n\n## Verification\n- bun run verify\n',
      section,
    );
    expect(sanitized).not.toContain('Summary by CodeRabbit');
    expect(sanitized).not.toContain('## Verification');
    const replaced = mergeStandaloneAiReviewSection(
      '## Summary\n- existing body\n\n<!-- ai-review:start -->\n## External AI Review\n\n## Verification\n- stale\n<!-- ai-review:end -->\n',
      section,
    );
    expect(replaced.match(/<!-- ai-review:start -->/g)?.length ?? 0).toBe(1);
    expect(replaced).not.toContain('- stale');
    const deduped = mergeStandaloneAiReviewSection(
      '## Summary\n- existing body\n\n<!-- ai-review:start -->\nold-1\n<!-- ai-review:end -->\n\n<!-- ai-review:start -->\nold-2\n<!-- ai-review:end -->\n',
      section,
    );
    expect(deduped.match(/<!-- ai-review:start -->/g)?.length ?? 0).toBe(1);
    expect(deduped).not.toContain('old-1');
    expect(deduped).not.toContain('old-2');
  });

  it('removes stale manual external review prose when refreshing standalone review metadata', () => {
    const merged = mergeStandaloneAiReviewSection(
      [
        '## Summary',
        '- add stacked closeout support',
        '',
        '## External AI Review',
        '',
        '- original outcome on reviewed head: `operator_input_needed`',
        '- reviewed commit: `df8c35128bd2`',
        '- current branch head: `f238a1f`',
        '- vendors: `coderabbit`',
        '',
        '### Patched Follow-Up',
        '',
        '- [coderabbit] Persist replacement PR metadata before continuing.',
        '',
        '<!-- ai-review:start -->',
        'old managed block',
        '<!-- ai-review:end -->',
      ].join('\n'),
      buildStandaloneAiReviewSection({
        outcome: 'clean',
        note: 'External AI review completed without prudent follow-up changes.',
        reviewedHeadSha: '80026dbdebbb18fa6017dc522c2a0fc916927367',
        vendors: ['coderabbit', 'greptile'],
      }),
    );

    expect(merged.match(/^## External AI Review$/gm)?.length ?? 0).toBe(1);
    expect(merged).not.toContain('original outcome on reviewed head');
    expect(merged).not.toContain('Patched Follow-Up');
    expect(merged).toContain('## Summary');
    expect(merged).toContain('- add stacked closeout support');
    expect(merged).toContain('<!-- ai-review:start -->');
    expect(merged).toContain('`coderabbit`, `greptile`');
  });

  it('renders final standalone triage outcomes accurately', () => {
    expect(
      buildStandaloneAiReviewSection({
        outcome: 'patched',
        note: 'Patched the prudent AI review follow-up.',
        reviewedHeadSha: 'abcdef1234567890',
        comments: [
          {
            vendor: 'coderabbit',
            channel: 'inline_review',
            authorLogin: 'coderabbitai',
            authorType: 'Bot',
            body: 'Guard the null return here.',
            kind: 'finding',
            path: 'src/example.ts',
            line: 42,
            url: 'https://example.test/comment/1',
          },
        ],
        vendors: ['coderabbit'],
      }),
    ).toContain('## External AI Review');

    expect(
      buildStandaloneAiReviewSection({
        outcome: 'clean',
        note: 'External AI review completed without prudent follow-up changes.',
        vendors: ['qodo'],
      }),
    ).toContain('no prudent follow-up changes were required.');
    expect(
      buildStandaloneAiReviewSection({
        outcome: 'clean',
        note: 'External AI review completed without prudent follow-up changes.',
        vendors: ['qodo'],
      }),
    ).toContain('- outcome: `clean`');
  });

  it('preserves incomplete agents in standalone review sections', () => {
    const body = buildStandaloneAiReviewSection({
      outcome: 'clean',
      note: 'External AI review completed without prudent follow-up changes.',
      incompleteAgents: ['coderabbit', 'greptile'],
      vendors: ['coderabbit', 'greptile'],
    });

    expect(body).toContain(
      '- incomplete agents at timeout: `coderabbit, greptile`',
    );
  });

  it('renders the same external review section content for ticketed and standalone flows', () => {
    const section = buildExternalAiReviewSection(
      {
        outcome: 'patched',
        note: 'Patched the prudent AI review follow-up.',
        reviewedHeadSha: 'abcdef1234567890',
        comments: [
          {
            vendor: 'coderabbit',
            channel: 'inline_review',
            authorLogin: 'coderabbitai',
            authorType: 'Bot',
            body: 'Guard the null return here.',
            kind: 'finding',
            path: 'src/example.ts',
            line: 42,
            threadId: 'thread_example_1',
            url: 'https://example.test/comment/1',
          },
        ],
        threadResolutions: [
          {
            status: 'resolved',
            threadId: 'thread_example_1',
            url: 'https://example.test/comment/1',
            vendor: 'coderabbit',
          },
        ],
        vendors: ['coderabbit'],
      },
      {
        actionCommits: [
          {
            sha: 'c87f955ca43a1234',
            subject: 'resolve null-guard follow-up',
            vendors: ['coderabbit'],
          },
        ],
        currentHeadSha: 'fedcba0987654321',
        maxWaitMinutes: 8,
      },
    );

    expect(section).toContain('## External AI Review');
    expect(section).toContain('- outcome: `patched`');
    expect(section).toContain('### Resolved Review Findings');
    expect(section).toContain(
      '[coderabbit] Guard the null return here. (native GitHub thread resolved)',
    );
    expect(section).toContain(
      'patch commits after `abcdef123456` address all findings from that review.',
    );
    expect(section).toContain(
      'the latest recorded external AI review applies to an older branch head',
    );
    expect(section).not.toContain('### Actions Taken');
  });

  it('uses the shared refresh adapter while preserving ticketed and standalone body ownership', () => {
    const reviewState = {
      actionSummary: 'Patched the null-guard regression and tightened tests.',
      comments: [
        {
          vendor: 'coderabbit',
          channel: 'inline_review' as const,
          authorLogin: 'coderabbitai',
          authorType: 'Bot',
          body: 'Guard the null return here.',
          kind: 'finding' as const,
          path: 'src/example.ts',
          line: 42,
          threadId: 'thread_example_1',
          url: 'https://example.test/comment/1',
        },
      ],
      note: 'Patched the prudent AI review follow-up.',
      outcome: 'patched' as const,
      reviewedHeadSha: 'abcdef1234567890',
      threadResolutions: [
        {
          status: 'resolved' as const,
          threadId: 'thread_example_1',
          url: 'https://example.test/comment/1',
          vendor: 'coderabbit',
        },
      ],
      vendors: ['coderabbit'],
    };
    const refreshContext = {
      actionCommits: [
        {
          sha: 'c87f955ca43a1234',
          subject: 'resolve null-guard follow-up',
          vendors: ['coderabbit'],
        },
      ],
      currentHeadSha: 'fedcba0987654321',
    };
    const expectedReviewSection = buildExternalAiReviewSection(reviewState, {
      ...refreshContext,
      maxWaitMinutes: 8,
    });

    const ticketBody = buildReviewMetadataRefreshBody(
      {
        mode: 'ticketed',
        state: {
          planKey: 'engineering-epic-02',
          planPath:
            'docs/product/delivery/engineering-epic-02/implementation-plan.md',
          statePath: '.agents/delivery/engineering-epic-02/state.json',
          reviewsDirPath: '.agents/delivery/engineering-epic-02/reviews',
          handoffsDirPath: '.agents/delivery/engineering-epic-02/handoffs',
          reviewPollIntervalMinutes: 6,
          reviewPollMaxWaitMinutes: 12,
          tickets: [],
        },
        ticket: {
          id: 'E2.05',
          title: 'Shared Review Metadata Refresh Adapter',
          ticketFile:
            'docs/product/delivery/engineering-epic-02/ticket-05-shared-review-metadata-refresh-adapter.md',
          baseBranch: 'agents/e2-04-shared-clean-and-timeout-recording-core',
          verifiedAt: '2026-04-07T00:00:00.000Z',
          verifyOutcome: 'clean',
          reviewActionSummary: reviewState.actionSummary,
          reviewIncompleteAgents: undefined,
          reviewComments: reviewState.comments,
          reviewHeadSha: reviewState.reviewedHeadSha,
          reviewNonActionSummary: undefined,
          reviewNote: reviewState.note,
          reviewOutcome: reviewState.outcome,
          reviewThreadResolutions: reviewState.threadResolutions,
          reviewVendors: reviewState.vendors,
          status: 'reviewed',
        },
      },
      refreshContext,
    );

    const standaloneBody = buildReviewMetadataRefreshBody(
      {
        mode: 'standalone',
        body: [
          '## Summary',
          '- preserve this author-owned context',
          '',
          '## Notes',
          '- keep this section too',
        ].join('\n'),
        result: {
          ...reviewState,
          prNumber: 32,
          prUrl: 'https://example.test/pull/32',
        },
      },
      refreshContext,
    );

    expect(ticketBody).toContain(
      '- delivery ticket: `E2.05 Shared Review Metadata Refresh Adapter`',
    );
    expect(ticketBody).toContain(
      '- post-verify: outcome `clean` completed at 2026-04-07 00:00 UTC',
    );
    expect(ticketBody).toContain(expectedReviewSection);
    expect(standaloneBody).toContain('- preserve this author-owned context');
    expect(standaloneBody).toContain('- keep this section too');
    expect(standaloneBody).toContain(expectedReviewSection);
    expect(standaloneBody).toContain('<!-- ai-review:start -->');
  });

  it('keeps standalone pr bodies free of artifact paths', () => {
    const body = buildStandaloneAiReviewSection({
      outcome: 'patched',
      note: 'Patched the prudent AI review follow-up.',
      vendors: ['coderabbit'],
    });

    expect(body).not.toContain('artifact (json)');
    expect(body).not.toContain('artifact (text)');
  });

  it('renders internal review outcomes and linked patch commits in ticket pr bodies', () => {
    const body = buildPullRequestBody(
      {
        planKey: 'engineering-epic-08',
        planPath:
          'docs/product/delivery/engineering-epic-08/implementation-plan.md',
        statePath: '.agents/delivery/engineering-epic-08/state.json',
        reviewsDirPath: '.agents/delivery/engineering-epic-08/reviews',
        handoffsDirPath: '.agents/delivery/engineering-epic-08/handoffs',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
        tickets: [],
      },
      {
        id: 'EE8.04',
        title: 'PR body internal review observability',
        ticketFile:
          'docs/product/delivery/engineering-epic-08/ticket-04-pr-body-internal-review-observability.md',
        baseBranch: 'main',
        verifiedAt: '2026-04-14T08:33:00.000Z',
        verifyOutcome: 'patched',
        verifyPatchCommits: [
          {
            sha: 'aaaaaaaaaaaa1111111111111111111111111111',
            subject: 'fix: clarify PR body review state [post-verify]',
          },
        ],
        subagentReviewCompletedAt: '2026-04-14T08:48:00.000Z',
        subagentReviewOutcome: 'patched',
        subagentReviewPatchCommits: [
          {
            sha: 'bbbbbbbbbbbb2222222222222222222222222222',
            subject:
              'fix: surface subagent review patch commits [subagent-review]',
          },
        ],
        status: 'subagent_review_complete',
      },
      {
        githubRepo: {
          owner: 'cesarnml',
          name: 'Test-Project',
          defaultBranch: 'main',
        },
      },
    );

    expect(body).toContain(
      '- post-verify: outcome `patched` completed at 2026-04-14 08:33 UTC',
    );
    expect(body).toContain(
      '- subagentReview: outcome `patched` completed at 2026-04-14 08:48 UTC',
    );
    expect(body).toContain('### Post-Verify Patch Commits');
    expect(body).toContain('### Subagent Review Patch Commits');
    expect(body).toContain(
      '[`aaaaaaaaaaaa`](https://github.com/cesarnml/Test-Project/commit/aaaaaaaaaaaa1111111111111111111111111111) fix: clarify PR body review state [post-verify]',
    );
    expect(body).toContain(
      '[`bbbbbbbbbbbb`](https://github.com/cesarnml/Test-Project/commit/bbbbbbbbbbbb2222222222222222222222222222) fix: surface subagent review patch commits [subagent-review]',
    );
  });

  it('rejects patched internal review outcomes without recorded patch commits in ticket pr bodies', () => {
    expect(() =>
      buildPullRequestBody(
        {
          planKey: 'engineering-epic-08',
          planPath:
            'docs/product/delivery/engineering-epic-08/implementation-plan.md',
          statePath: '.agents/delivery/engineering-epic-08/state.json',
          reviewsDirPath: '.agents/delivery/engineering-epic-08/reviews',
          handoffsDirPath: '.agents/delivery/engineering-epic-08/handoffs',
          reviewPollIntervalMinutes: 6,
          reviewPollMaxWaitMinutes: 12,
          tickets: [],
        },
        {
          id: 'EE8.04',
          title: 'PR body internal review observability',
          ticketFile:
            'docs/product/delivery/engineering-epic-08/ticket-04-pr-body-internal-review-observability.md',
          baseBranch: 'main',
          verifiedAt: '2026-04-14T08:33:00.000Z',
          verifyOutcome: 'patched',
          verifyPatchCommits: [],
          status: 'verified',
        },
      ),
    ).toThrow(/Post-verify PR metadata requires recorded patch commits/);
  });

  it('tolerates legacy patched internal review states with no recorded patch commits', () => {
    const body = buildPullRequestBody(
      {
        planKey: 'engineering-epic-08',
        planPath:
          'docs/product/delivery/engineering-epic-08/implementation-plan.md',
        statePath: '.agents/delivery/engineering-epic-08/state.json',
        reviewsDirPath: '.agents/delivery/engineering-epic-08/reviews',
        handoffsDirPath: '.agents/delivery/engineering-epic-08/handoffs',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
        tickets: [],
      },
      {
        id: 'EE8.04',
        title: 'PR body internal review observability',
        ticketFile:
          'docs/product/delivery/engineering-epic-08/ticket-04-pr-body-internal-review-observability.md',
        baseBranch: 'main',
        verifiedAt: '2026-04-14T08:33:00.000Z',
        verifyOutcome: 'patched',
        status: 'verified',
      },
    );

    expect(body).toContain(
      '- post-verify: outcome `patched` completed at 2026-04-14 08:33 UTC',
    );
    expect(body).not.toContain('### Post-Verify Patch Commits');
  });

  it('does not include external summary-only noise in the ticket pr body', () => {
    const body = buildPullRequestBody(
      {
        planKey: 'phase-03',
        planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
        statePath: '.agents/delivery/phase-03/state.json',
        reviewsDirPath: '.agents/delivery/phase-03/reviews',
        handoffsDirPath: '.agents/delivery/phase-03/handoffs',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
        tickets: [],
      },
      {
        id: 'P3.01',
        title: 'Persist Transmission Identity For Queued Torrents',
        ticketFile:
          'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
        baseBranch: 'main',
        status: 'reviewed',
        reviewOutcome: 'clean',
        reviewNote:
          'External AI review completed without prudent follow-up changes.',
        reviewNonActionSummary: undefined,
        reviewActionSummary: undefined,
        reviewVendors: ['coderabbit', 'qodo'],
      },
    );

    expect(body).toContain('no prudent follow-up changes were required.');
    expect(body).not.toContain('Ignored 1 summary comment');
    expect(body).not.toContain('### Vendor Summary Noise');
    expect(body).not.toContain('non-action summary:');
    expect(body).not.toContain('summary-only updates');
    expect(body).not.toContain('## Verification');
  });

  it('omits the external ai review section when review outcome is skipped', () => {
    const body = buildPullRequestBody(
      {
        planKey: 'phase-03',
        planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
        statePath: '.agents/delivery/phase-03/state.json',
        reviewsDirPath: '.agents/delivery/phase-03/reviews',
        handoffsDirPath: '.agents/delivery/phase-03/handoffs',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
        tickets: [],
      },
      {
        id: 'P3.01',
        title: 'Persist Transmission Identity For Queued Torrents',
        ticketFile:
          'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
        baseBranch: 'main',
        status: 'reviewed',
        reviewOutcome: 'skipped',
        reviewNote: 'external AI review disabled by policy',
      },
    );

    expect(body).not.toContain('## External AI Review');
  });

  it('renders no-action rationale when non-action summary exists on clean outcome', () => {
    const body = buildStandaloneAiReviewSection({
      outcome: 'clean',
      note: 'External AI review completed without prudent follow-up changes.',
      nonActionSummary:
        'Ignored 2 vendor summary comments and 1 stale recommendation.',
      vendors: ['qodo'],
    });

    expect(body).toContain('### No-Action Rationale');
    expect(body).toContain(
      'Ignored 2 vendor summary comments and 1 stale recommendation.',
    );
  });

  it('omits summary noise and renders actions taken for reviewers', () => {
    const body = buildPullRequestBody(
      {
        planKey: 'phase-03',
        planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
        statePath: '.agents/delivery/phase-03/state.json',
        reviewsDirPath: '.agents/delivery/phase-03/reviews',
        handoffsDirPath: '.agents/delivery/phase-03/handoffs',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
        tickets: [],
      },
      {
        id: 'P3.01',
        title: 'Persist Transmission Identity For Queued Torrents',
        ticketFile:
          'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
        baseBranch: 'main',
        reviewActionSummary: 'Patched 1 finding comment.',
        reviewComments: [
          {
            vendor: 'coderabbit',
            channel: 'inline_review',
            authorLogin: 'coderabbitai',
            authorType: 'Bot',
            body: 'Guard the null return here.',
            kind: 'finding',
            path: 'src/example.ts',
            line: 42,
            threadId: 'thread_example_1',
            url: 'https://example.test/comment/1',
          },
          {
            vendor: 'qodo',
            channel: 'review_summary',
            authorLogin: 'qodo-bot',
            authorType: 'Bot',
            body: 'Overall this looks good.',
            kind: 'summary',
            url: 'https://example.test/comment/2',
          },
          {
            vendor: 'qodo',
            channel: 'review_summary',
            authorLogin: 'qodo-bot',
            authorType: 'Bot',
            body: 'No blocking issues found.',
            kind: 'summary',
            url: 'https://example.test/comment/3',
          },
          {
            vendor: 'coderabbit',
            channel: 'inline_review',
            authorLogin: 'coderabbitai',
            authorType: 'Bot',
            body: 'Previous concern already resolved.',
            isResolved: true,
            kind: 'finding',
            path: 'src/example.ts',
            line: 30,
            threadId: 'thread_example_2',
            url: 'https://example.test/comment/4',
          },
        ],
        reviewHeadSha: 'abcdef1234567890',
        reviewNote: 'Patched the prudent AI review follow-up.',
        reviewOutcome: 'patched',
        reviewThreadResolutions: [
          {
            status: 'resolved',
            threadId: 'thread_example_1',
            url: 'https://example.test/comment/1',
            vendor: 'coderabbit',
          },
        ],
        reviewVendors: ['coderabbit', 'qodo'],
        status: 'reviewed',
      },
      {
        actionCommits: [
          {
            sha: 'c87f955ca43a1234',
            subject: 'resolve null-guard follow-up',
            vendors: ['coderabbit'],
          },
        ],
        currentHeadSha: 'abcdef1234567890',
      },
    );

    expect(body).toContain('## External AI Review');
    expect(body).toContain('### Actions Taken');
    expect(body).toContain(
      '`c87f955ca43a` [coderabbit] resolve null-guard follow-up',
    );
    expect(body).not.toContain('### Vendor Summary Noise');
    expect(body).not.toContain('[qodo] compressed 2 summary-only updates.');
    expect(body).not.toContain('Overall this looks good.');
    expect(body).not.toContain('### Resolved Review Findings');
    expect(body).not.toContain(
      '[coderabbit] Previous concern already resolved.',
    );
    expect(body).toContain('- outcome: `patched`');
  });

  it('keeps reviewed findings current when the current head sha is unknown', () => {
    const body = buildStandaloneAiReviewSection({
      outcome: 'operator_input_needed',
      note: 'Actionable AI review findings were detected and still need follow-up.',
      reviewedHeadSha: 'abcdef1234567890',
      comments: [
        {
          vendor: 'coderabbit',
          channel: 'inline_review',
          authorLogin: 'coderabbitai',
          authorType: 'Bot',
          body: 'Guard the null return here.',
          kind: 'finding',
          path: 'src/example.ts',
          line: 42,
          url: 'https://example.test/comment/1',
        },
      ],
      vendors: ['coderabbit'],
    });

    expect(body).toContain('### Unresolved Review Findings');
    expect(body).not.toContain('### Resolved Review Findings');
    expect(body).not.toContain(
      'the latest recorded external AI review applies to an older branch head',
    );
  });

  it('renders sonarqube failed-check annotations as unresolved review findings', () => {
    const body = buildStandaloneAiReviewSection({
      outcome: 'operator_input_needed',
      note: 'SonarQube annotations need manual triage.',
      reviewedHeadSha: 'abcdef1234567890',
      comments: [
        {
          vendor: 'sonarqube',
          channel: 'inline_review',
          authorLogin: 'sonarqubecloud',
          authorType: 'Bot',
          body: 'Refactor this function to reduce its Cognitive Complexity from 19 to the 15 allowed.',
          kind: 'unknown',
          path: 'tools/delivery/pr-metadata.ts',
          line: 596,
          url: 'https://sonarcloud.io/project/issues?id=example&issues=abc',
        },
      ],
      vendors: ['sonarqube'],
    });

    expect(body).toContain('### Unresolved Review Findings');
    expect(body).toContain(
      '[sonarqube] Refactor this function to reduce its Cognitive Complexity from 19 to the 15 allowed.',
    );
    expect(body).toContain('`tools/delivery/pr-metadata.ts:596`');
    expect(body).toContain('- vendors: `sonarqube`');
  });

  it('omits the stale-sha patch resolution sentence when outcome is not patched', () => {
    const section = buildExternalAiReviewSection(
      {
        outcome: 'clean',
        note: 'External AI review completed without prudent follow-up changes.',
        reviewedHeadSha: 'abcdef1234567890',
        vendors: ['coderabbit'],
      },
      {
        currentHeadSha: 'fedcba0987654321',
        maxWaitMinutes: 8,
      },
    );

    expect(section).not.toContain('patch commits after');
  });

  it('renders stale ai review history separately from current head status', () => {
    const body = buildPullRequestBody(
      {
        planKey: 'phase-03',
        planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
        statePath: '.agents/delivery/phase-03/state.json',
        reviewsDirPath: '.agents/delivery/phase-03/reviews',
        handoffsDirPath: '.agents/delivery/phase-03/handoffs',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
        tickets: [],
      },
      {
        id: 'P3.01',
        title: 'Persist Transmission Identity For Queued Torrents',
        ticketFile:
          'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
        baseBranch: 'main',
        reviewActionSummary: 'Patched 1 finding comment.',
        reviewComments: [
          {
            vendor: 'coderabbit',
            channel: 'inline_review',
            authorLogin: 'coderabbitai',
            authorType: 'Bot',
            body: 'Guard the null return here.',
            kind: 'finding',
            path: 'src/example.ts',
            line: 42,
            threadId: 'thread_example_1',
            url: 'https://example.test/comment/1',
          },
        ],
        reviewHeadSha: 'abcdef1234567890',
        reviewNonActionSummary: undefined,
        reviewNote: 'Patched the prudent AI review follow-up.',
        reviewOutcome: 'patched',
        reviewThreadResolutions: [
          {
            status: 'resolved',
            threadId: 'thread_example_1',
            url: 'https://example.test/comment/1',
            vendor: 'coderabbit',
          },
        ],
        reviewVendors: ['coderabbit'],
        status: 'reviewed',
      },
      {
        currentHeadSha: 'fedcba0987654321',
      },
    );

    expect(body).toContain(
      'the latest recorded external AI review applies to an older branch head',
    );
    expect(body).not.toContain(
      'patch commits after `abcdef123456` address all findings from that review.',
    );
    expect(body).toContain('### Resolved Review Findings');
    expect(body).toContain('[coderabbit] Guard the null return here.');
    expect(body).toContain('[thread](https://example.test/comment/1)');
  });

  it('surfaces the review wait window after opening a PR', () => {
    const message = formatReviewWindowMessage(
      {
        planKey: 'phase-03',
        planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
        statePath: '.agents/delivery/phase-03/state.json',
        reviewsDirPath: '.agents/delivery/phase-03/reviews',
        handoffsDirPath: '.agents/delivery/phase-03/handoffs',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
        tickets: [
          {
            id: 'P3.01',
            title: 'Persist Transmission Identity For Queued Torrents',
            slug: 'persist-transmission-identity-for-queued-torrents',
            ticketFile:
              'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
            status: 'in_review',
            branch:
              'agents/p3-01-persist-transmission-identity-for-queued-torrents',
            baseBranch: 'main',
            worktreePath: '/tmp/p3_01',
            prUrl: 'https://example.test/pull/20',
            prNumber: 20,
            prOpenedAt: '2026-04-01T10:00:00.000Z',
          },
        ],
      },
      'P3.01',
    );

    expect(message).toContain('AI Review Window');
    expect(message).toContain(
      'polling cadence: every 6 minutes up to 12 minutes',
    );
    expect(message).toContain('checks at: 6, 12 minutes after PR open');
    expect(message).toContain('first check at: 2026-04-01T10:06:00.000Z');
    expect(message).toContain('final check at: 2026-04-01T10:12:00.000Z');
    expect(message).toContain('the orchestrator records `clean` and continues');
  });

  it('maps orchestrator commands to notification events', () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
          reviewOutcome: 'clean',
        },
        {
          id: 'P3.02',
          title: 'Reconcile Torrent Lifecycle From Transmission',
          slug: 'reconcile-torrent-lifecycle-from-transmission',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-02-reconcile-torrent-lifecycle-from-transmission.md',
          status: 'pending',
          branch: 'agents/p3-02-reconcile-torrent-lifecycle-from-transmission',
          baseBranch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          worktreePath: '/tmp/p3_02',
        },
      ],
    };

    expect(
      eventsForStartCommand(state, 'P3.01').map((event) => event.kind),
    ).toEqual(['ticket_started']);
    expect(
      eventsForOpenPrCommand(state, 'P3.01').map((event) => event.kind),
    ).toEqual(['pr_opened', 'review_window_ready']);
    expect(
      eventsForRecordReviewCommand(state, 'P3.01').map((event) => event.kind),
    ).toEqual(['review_recorded']);
    expect(
      eventsForPollReviewCommand(
        {
          ...state,
          tickets: [
            {
              ...state.tickets[0]!,
              status: 'reviewed',
              reviewNote:
                'No AI review feedback was detected within the 12-minute polling window.',
            },
            state.tickets[1]!,
          ],
        },
        'P3.01',
      ).map((event) => event.kind),
    ).toEqual(['review_recorded']);
    expect(
      eventsForPollReviewCommand({
        ...state,
        tickets: [
          {
            ...state.tickets[0]!,
            status: 'reviewed',
            reviewOutcome: 'clean',
            reviewNote:
              'No AI review feedback was detected within the 12-minute polling window.',
          },
          state.tickets[1]!,
        ],
      }).map((event) => event.kind),
    ).toEqual(['review_recorded']);
    expect(
      eventsForPollReviewCommand({
        ...state,
        tickets: [
          {
            ...state.tickets[0]!,
            status: 'needs_patch',
            reviewOutcome: undefined,
            reviewNote:
              'Actionable AI review findings were detected and still need follow-up.',
          },
          state.tickets[1]!,
        ],
      }).map((event) => event.kind),
    ).toEqual(['review_recorded']);
    expect(
      eventsForAdvanceCommand(state, {
        ...state,
        tickets: [
          {
            ...state.tickets[0]!,
            status: 'done',
          },
          {
            ...state.tickets[1]!,
            status: 'in_progress',
          },
        ],
      }).map((event) => event.kind),
    ).toEqual(['ticket_completed', 'ticket_started']);
  });

  it('summarizes stale-state mismatches against repo reality', () => {
    const changes = summarizeStateDifferences(
      {
        planKey: 'phase-03',
        planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
        statePath: '.agents/delivery/phase-03/state.json',
        reviewsDirPath: '.agents/delivery/phase-03/reviews',
        handoffsDirPath: '.agents/delivery/phase-03/handoffs',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
        tickets: [
          {
            id: 'P3.01',
            title: 'Persist Transmission Identity For Queued Torrents',
            slug: 'persist-transmission-identity-for-queued-torrents',
            ticketFile:
              'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
            status: 'in_review',
            branch:
              'agents/p3-01-persist-transmission-identity-for-queued-torrents',
            baseBranch: 'main',
            worktreePath: '/tmp/old_p3_01',
            prUrl: 'https://example.test/pull/20',
          },
        ],
      },
      {
        planKey: 'phase-03',
        planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
        statePath: '.agents/delivery/phase-03/state.json',
        reviewsDirPath: '.agents/delivery/phase-03/reviews',
        handoffsDirPath: '.agents/delivery/phase-03/handoffs',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
        tickets: [
          {
            id: 'P3.01',
            title: 'Persist Transmission Identity For Queued Torrents',
            slug: 'persist-transmission-identity-for-queued-torrents',
            ticketFile:
              'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
            status: 'pending',
            branch:
              'agents/p3-01-persist-transmission-identity-for-queued-torrents',
            baseBranch: 'main',
            worktreePath: '/tmp/new_p3_01',
          },
        ],
      },
    );

    expect(changes).toContain('P3.01: status in_review -> pending');
    expect(changes).toContain(
      'P3.01: worktree /tmp/old_p3_01 -> /tmp/new_p3_01',
    );
    expect(changes).toContain('P3.01: pr https://example.test/pull/20 -> none');
  });

  it('copies allowed ignored bootstrap files into a fresh ticket worktree when missing', async () => {
    const sourceDir = await mkdtemp(join(tmpdir(), 'orchestrator-source-'));
    const targetDir = await mkdtemp(join(tmpdir(), 'orchestrator-target-'));

    try {
      await writeFile(
        join(sourceDir, '.env'),
        'TELEGRAM_CHAT_ID=123\n',
        'utf8',
      );
      await writeFile(join(sourceDir, '.env.local'), 'LOCAL_ONLY=1\n', 'utf8');
      await writeFile(join(sourceDir, '.gitignore'), '.agents/\n', 'utf8');

      await copyLocalBootstrapFilesIfPresent(sourceDir, targetDir);

      expect(await readFile(join(targetDir, '.env'), 'utf8')).toBe(
        'TELEGRAM_CHAT_ID=123\n',
      );
      expect(await readFile(join(targetDir, '.env.local'), 'utf8')).toBe(
        'LOCAL_ONLY=1\n',
      );
      expect(await readFile(join(targetDir, '.gitignore'), 'utf8')).toBe(
        '.agents/\n',
      );
    } finally {
      await rm(sourceDir, { recursive: true, force: true });
      await rm(targetDir, { recursive: true, force: true });
    }
  });

  it('does not overwrite existing ignored bootstrap files in the target worktree', async () => {
    const sourceDir = await mkdtemp(join(tmpdir(), 'orchestrator-source-'));
    const targetDir = await mkdtemp(join(tmpdir(), 'orchestrator-target-'));

    try {
      await writeFile(join(sourceDir, '.env'), 'SOURCE=1\n', 'utf8');
      await writeFile(join(sourceDir, '.gitignore'), '.agents/\n', 'utf8');
      await writeFile(join(targetDir, '.env'), 'TARGET=1\n', 'utf8');
      await writeFile(join(targetDir, '.gitignore'), 'node_modules/\n', 'utf8');

      await copyLocalBootstrapFilesIfPresent(sourceDir, targetDir);

      expect(await readFile(join(targetDir, '.env'), 'utf8')).toBe(
        'TARGET=1\n',
      );
      expect(await readFile(join(targetDir, '.gitignore'), 'utf8')).toBe(
        'node_modules/\n',
      );
    } finally {
      await rm(sourceDir, { recursive: true, force: true });
      await rm(targetDir, { recursive: true, force: true });
    }
  });

  it('builds the 2/4/6/8/10-minute review polling schedule', () => {
    expect(buildReviewPollCheckMinutes(2, 10)).toEqual([2, 4, 6, 8, 10]);
    expect(() => buildReviewPollCheckMinutes(0, 10)).toThrow(
      'Review polling interval and max wait must be positive.',
    );
  });

  it('parses the ai review fetcher contract', () => {
    expect(
      parseAiReviewFetcherOutput(
        JSON.stringify({
          agents: [
            {
              agent: 'coderabbit',
              state: 'findings_detected',
              findingsCount: 1,
              note: 'actionable findings captured',
            },
            {
              agent: 'qodo',
              state: 'completed',
              note: 'review completed without actionable findings',
            },
            {
              agent: 'sonarqube',
              state: 'findings_detected',
              findingsCount: 1,
              note: 'actionable findings captured',
            },
          ],
          detected: true,
          reviewed_head_sha: 'abcdef1234567890',
          vendors: ['coderabbit', 'qodo', 'sonarqube'],
          comments: [
            {
              vendor: 'coderabbit',
              channel: 'inline_review',
              author_login: 'coderabbitai',
              author_type: 'Bot',
              body: 'Guard the null return here.',
              is_outdated: false,
              is_resolved: false,
              path: 'src/example.ts',
              line: 42,
              thread_id: 'thread_example_1',
              thread_viewer_can_resolve: true,
              url: 'https://example.test/comment/1',
              updated_at: '2026-04-04T10:00:00.000Z',
              kind: 'finding',
            },
            {
              vendor: 'qodo',
              channel: 'review_summary',
              author_login: 'qodo-bot',
              author_type: 'Bot',
              body: 'Overall this looks good.',
              kind: 'summary',
            },
            {
              vendor: 'sonarqube',
              channel: 'inline_review',
              author_login: 'sonarqubecloud',
              author_type: 'Bot',
              body: 'Refactor this function to reduce its Cognitive Complexity from 19 to the 15 allowed.',
              is_outdated: false,
              is_resolved: false,
              path: 'tools/delivery/pr-metadata.ts',
              line: 596,
              url: 'https://sonarcloud.io/project/issues?id=example&issues=abc',
              kind: 'unknown',
            },
          ],
        }),
      ),
    ).toEqual({
      agents: [
        {
          agent: 'coderabbit',
          state: 'findings_detected',
          findingsCount: 1,
          note: 'actionable findings captured',
        },
        {
          agent: 'qodo',
          state: 'completed',
          note: 'review completed without actionable findings',
        },
        {
          agent: 'sonarqube',
          state: 'findings_detected',
          findingsCount: 1,
          note: 'actionable findings captured',
        },
      ],
      detected: true,
      reviewedHeadSha: 'abcdef1234567890',
      vendors: ['coderabbit', 'qodo', 'sonarqube'],
      comments: expect.arrayContaining([
        expect.objectContaining({
          vendor: 'coderabbit',
          channel: 'inline_review',
          authorLogin: 'coderabbitai',
          authorType: 'Bot',
          body: 'Guard the null return here.',
          path: 'src/example.ts',
          line: 42,
          kind: 'finding',
        }),
        expect.objectContaining({
          vendor: 'qodo',
          channel: 'review_summary',
          authorLogin: 'qodo-bot',
          authorType: 'Bot',
          body: 'Overall this looks good.',
          kind: 'summary',
        }),
        expect.objectContaining({
          vendor: 'sonarqube',
          channel: 'inline_review',
          authorLogin: 'sonarqubecloud',
          authorType: 'Bot',
          body: 'Refactor this function to reduce its Cognitive Complexity from 19 to the 15 allowed.',
          path: 'tools/delivery/pr-metadata.ts',
          line: 596,
          kind: 'unknown',
        }),
      ]),
    });

    expect(() => parseAiReviewFetcherOutput('not json')).toThrow(
      'AI review fetcher must emit JSON.',
    );

    expect(() =>
      parseAiReviewFetcherOutput(
        JSON.stringify({
          agents: [{ agent: 'coderabbit', state: 'unknown' }],
          detected: 'true',
          vendors: 'coderabbit',
          comments: {},
        }),
      ),
    ).toThrow(
      'AI review fetcher output must be JSON with `agents`, boolean `detected`, string[] `vendors`, and array `comments` fields.',
    );
  });

  it('parses the ai review triager contract', () => {
    expect(
      parseAiReviewTriagerOutput(
        JSON.stringify({
          outcome: 'needs_patch',
          note: 'Actionable comments still need follow-up.',
          action_summary: 'Flagged 2 finding comments for follow-up.',
          non_action_summary: 'Ignored 1 summary comment.',
          vendors: ['coderabbit', 'qodo'],
        }),
      ),
    ).toEqual({
      outcome: 'needs_patch',
      note: 'Actionable comments still need follow-up.',
      actionSummary: 'Flagged 2 finding comments for follow-up.',
      nonActionSummary: 'Ignored 1 summary comment.',
      vendors: ['coderabbit', 'qodo'],
    });
  });

  it('records post-verify before opening a PR', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'red_complete',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          redCommitSha: 'red123',
        },
      ],
    };

    const nextState = await recordPostVerify(
      state,
      'P3.01',
      undefined,
      baseConfig,
    );

    expect(nextState.tickets[0]?.status).toBe('verified');
    expect(nextState.tickets[0]?.verifiedAt).toBeTruthy();
  });

  it('normalizes legacy persisted ticket status and timestamps', () => {
    const raw = {
      planKey: 'p',
      planPath: 'plan.md',
      statePath: 's.json',
      reviewsDirPath: 'r',
      handoffsDirPath: 'h',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'T1',
          title: 't',
          slug: 's',
          ticketFile: 'f.md',
          status: 'internally_reviewed',
          branch: 'b',
          baseBranch: 'main',
          worktreePath: '/w',
          internalReviewCompletedAt: '2026-01-01T00:00:00.000Z',
        },
      ],
    };
    const next = normalizeDeliveryStateFromPersisted(raw);
    expect(next.tickets[0]?.status).toBe('verified');
    expect(next.tickets[0]?.verifiedAt).toBe('2026-01-01T00:00:00.000Z');
  });

  it('rejects pr bodies that contain literal escaped newlines', () => {
    expect(() =>
      assertReviewerFacingMarkdown('## Summary\\n- malformed'),
    ).toThrow(
      'PR body guard failed: body contains likely-escaped newline formatting sequences.',
    );
  });

  it('rejects pr bodies that contain unmatched markdown fenced code blocks', () => {
    expect(() =>
      assertReviewerFacingMarkdown('## Summary\n```md\n- item\n'),
    ).toThrow(
      'PR body guard failed: markdown contains an unmatched fenced code block.',
    );
  });

  it('accepts reviewer-facing markdown with proper headings and lists', () => {
    expect(() =>
      assertReviewerFacingMarkdown(
        '## Summary\n\n- item\n\n## External AI Review\n',
      ),
    ).not.toThrow();
  });

  it('allows literal \\n text when it appears inside inline code', () => {
    expect(() =>
      assertReviewerFacingMarkdown(
        '## Summary\n\n- guard against literal `\\\\n` in malformed generated bodies\n',
      ),
    ).not.toThrow();
  });

  it('rejects pr bodies that contain banned headings', () => {
    expect(() =>
      assertReviewerFacingMarkdown('## Summary by CodeRabbit\n\n- noisy recap'),
    ).toThrow('PR body guard failed: banned section heading');
    expect(() =>
      assertReviewerFacingMarkdown('## Verification\n\n- bun run verify'),
    ).toThrow('PR body guard failed: banned section heading');
    expect(() =>
      assertReviewerFacingMarkdown('## Verification ##\n\n- bun run verify'),
    ).toThrow('PR body guard failed: banned section heading');
    expect(() =>
      assertReviewerFacingMarkdown('## Summary by: Qodo\n\n- noisy recap'),
    ).toThrow('PR body guard failed: banned section heading');
    expect(() =>
      assertReviewerFacingMarkdown('Verification\n---\n\n- bun run verify'),
    ).toThrow('PR body guard failed: banned section heading');
  });

  it('does not strip banned-looking headings inside fenced code blocks', () => {
    const merged = mergeStandaloneAiReviewSection(
      '## Summary\n\n~~~md\n```ts\n## Verification\n```\n- example snippet\n~~~\n',
      buildStandaloneAiReviewSection({
        outcome: 'clean',
        note: 'External AI review completed without prudent follow-up changes.',
        vendors: ['coderabbit'],
      }),
    );
    expect(merged).toContain('~~~md');
    expect(merged).toContain('```ts');
    expect(merged).toContain('## Verification');
    expect(merged).toContain('- example snippet');
    expect(() =>
      assertReviewerFacingMarkdown(
        '## Summary\n\n~~~md\n```ts\n## Verification\n```\n- example snippet\n~~~\n',
      ),
    ).not.toThrow();
  });

  it('requires post-verify before opening a ticket-linked PR', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_progress',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
        },
      ],
    };

    await expect(
      openPullRequest(state, '/tmp/test_project', testContext(), 'P3.01'),
    ).rejects.toThrow(
      'Ticket P3.01 is at status in_progress. Complete post-verify before opening a PR.',
    );
  });

  it('parses native review-thread resolution responses', () => {
    expect(
      parseResolveReviewThreadOutput(
        JSON.stringify({
          data: {
            resolveReviewThread: {
              thread: {
                id: 'thread_example_1',
                isResolved: true,
              },
            },
          },
        }),
      ),
    ).toEqual({ resolved: true });

    expect(
      parseResolveReviewThreadOutput(
        JSON.stringify({
          errors: [{ message: 'thread is already resolved' }],
        }),
      ),
    ).toEqual({
      resolved: false,
      message: 'thread is already resolved',
    });
  });

  it('waits for all detected agents before triage and saves the artifact', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
        },
      ],
    };
    const cwd = await mkdtemp(join(tmpdir(), 'orchestrator-poll-'));
    const sleeps: number[] = [];
    let fetchCount = 0;

    try {
      const nextState = await pollReview(state, cwd, testContext(), 'P3.01', {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async (milliseconds) => {
          sleeps.push(milliseconds);
        },
        fetcher: () => {
          fetchCount += 1;
          return fetchCount === 1
            ? {
                agents: [
                  {
                    agent: 'coderabbit',
                    state: 'started',
                    note: 'review still in progress',
                  },
                  {
                    agent: 'qodo',
                    state: 'findings_detected',
                    findingsCount: 1,
                    note: 'actionable findings captured',
                  },
                ],
                detected: true,
                artifactText: '',
                vendors: ['coderabbit', 'qodo'],
                comments: [],
              }
            : {
                agents: [
                  {
                    agent: 'coderabbit',
                    state: 'completed',
                    note: 'review completed without actionable findings',
                  },
                  {
                    agent: 'qodo',
                    state: 'findings_detected',
                    findingsCount: 1,
                    note: 'actionable findings captured',
                  },
                ],
                detected: true,
                artifactText: 'normalized ai review artifact',
                reviewedHeadSha: 'abcdef1234567890',
                vendors: ['coderabbit', 'qodo'],
                comments: [
                  {
                    vendor: 'coderabbit',
                    channel: 'inline_review',
                    authorLogin: 'coderabbitai',
                    authorType: 'Bot',
                    body: 'Guard the null return here.',
                    threadId: 'thread_example_1',
                    threadViewerCanResolve: true,
                    kind: 'finding',
                  },
                  {
                    vendor: 'qodo',
                    channel: 'review_summary',
                    authorLogin: 'qodo-bot',
                    authorType: 'Bot',
                    body: 'Overall this looks good.',
                    kind: 'summary',
                  },
                ],
              };
        },
        triager: () => ({
          outcome: 'needs_patch',
          note: 'Actionable AI review findings were detected and still need follow-up.',
          actionSummary: 'Flagged 1 finding comment for follow-up.',
          nonActionSummary: 'Ignored 1 summary comment.',
          vendors: ['coderabbit', 'qodo'],
        }),
      });

      expect(sleeps).toEqual([360000, 720000]);
      expect(fetchCount).toBe(2);
      expect(nextState.tickets[0]?.status).toBe('needs_patch');
      expect(nextState.tickets[0]?.reviewFetchArtifactPath).toBe(
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.fetch.json',
      );
      expect(nextState.tickets[0]?.reviewTriageArtifactPath).toBe(
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
      );
      expect(nextState.tickets[0]?.reviewHeadSha).toBe('abcdef1234567890');
      expect(
        await readArtifactJson(
          cwd,
          '.agents/delivery/phase-03/reviews/P3.01-pr-review.fetch.json',
        ),
      ).toMatchObject({
        agents: [
          {
            agent: 'coderabbit',
            state: 'completed',
          },
          {
            agent: 'qodo',
            state: 'findings_detected',
          },
        ],
        detected: true,
        reviewedHeadSha: 'abcdef1234567890',
        vendors: ['coderabbit', 'qodo'],
      });
      expect(
        await readArtifactJson(
          cwd,
          '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
        ),
      ).toMatchObject({
        outcome: 'needs_patch',
        actionSummary: 'Flagged 1 finding comment for follow-up.',
        nonActionSummary: 'Ignored 1 summary comment.',
      });
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  it('records patched review outcomes immediately when the triager resolves them', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
        },
      ],
    };
    const prBodyUpdates: string[] = [];

    const nextState = await pollReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher: () => ({
          agents: [
            {
              agent: 'coderabbit',
              state: 'findings_detected',
              findingsCount: 1,
              note: 'actionable findings captured',
            },
          ],
          detected: true,
          artifactText: 'normalized ai review artifact',
          reviewedHeadSha: 'abcdef1234567890',
          vendors: ['coderabbit'],
          comments: [
            {
              vendor: 'coderabbit',
              channel: 'inline_review',
              authorLogin: 'coderabbitai',
              authorType: 'Bot',
              body: 'Guard the null return here.',
              threadId: 'thread_example_1',
              threadViewerCanResolve: true,
              kind: 'finding',
            },
          ],
        }),
        triager: () => ({
          outcome: 'patched',
          note: 'Patched the prudent AI review follow-up.',
          actionSummary: 'Patched 1 finding comment.',
          nonActionSummary: undefined,
          vendors: ['coderabbit'],
        }),
        resolveThreads: () => [
          {
            status: 'resolved',
            threadId: 'thread_example_1',
            url: 'https://example.test/comment/1',
            vendor: 'coderabbit',
          },
        ],
        updatePullRequestBody: async (updatedState, ticket) => {
          prBodyUpdates.push(`${updatedState.planKey}:${ticket.reviewOutcome}`);
        },
      },
    );

    expect(nextState.tickets[0]).toMatchObject({
      status: 'done',
      reviewOutcome: 'patched',
      reviewFetchArtifactPath:
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.fetch.json',
      reviewTriageArtifactPath:
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
    });
    expect(prBodyUpdates).toEqual(['phase-03:patched']);
  });

  it('extends review polling by one interval when an agent is still in flight', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
        },
      ],
    };
    const sleeps: number[] = [];

    const nextState = await pollReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async (milliseconds) => {
          sleeps.push(milliseconds);
        },
        fetcher: () => ({
          agents: [
            {
              agent: 'coderabbit',
              state: 'started',
              note: 'review still in progress',
            },
          ],
          detected: true,
          artifactText: 'started only artifact',
          vendors: ['coderabbit'],
          comments: [],
        }),
        updatePullRequestBody: async () => undefined,
      },
    );

    expect(sleeps).toEqual([360000, 720000]);
    expect(nextState.tickets[0]).toMatchObject({
      status: 'done',
      reviewOutcome: 'clean',
      reviewTriageArtifactPath:
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
    });
    expect(
      await readArtifactJson(
        '/tmp/test_project',
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
      ),
    ).toMatchObject({
      incompleteAgents: ['coderabbit'],
      note: 'AI review reached the 12-minute limit while waiting on: coderabbit. No actionable findings were captured. Rerun manually if needed.',
      outcome: 'clean',
    });
  });

  it('auto-records clean when no ai review appears by the final check', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
        },
      ],
    };
    const sleeps: number[] = [];
    const prBodyUpdates: string[] = [];

    const nextState = await pollReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async (milliseconds) => {
          sleeps.push(milliseconds);
        },
        fetcher: () => ({
          agents: [],
          detected: false,
          artifactText: '',
          vendors: [],
          comments: [],
        }),
        updatePullRequestBody: async (updatedState, ticket) => {
          prBodyUpdates.push(`${updatedState.planKey}:${ticket.reviewOutcome}`);
        },
      },
    );

    expect(sleeps).toEqual([360000, 720000]);
    expect(nextState.tickets[0]).toMatchObject({
      status: 'done',
      reviewOutcome: 'clean',
      reviewTriageArtifactPath:
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
    });
    expect(
      await readArtifactJson(
        '/tmp/test_project',
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
      ),
    ).toMatchObject({
      note: 'No AI review feedback was detected within the 12-minute polling window.',
      outcome: 'clean',
    });
    expect(prBodyUpdates).toEqual(['phase-03:clean']);
  });

  it('preserves patched as the cumulative outcome when a later poll is clean', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
          reviewOutcome: 'patched',
          reviewNote: 'Patched the prudent AI review follow-up.',
        },
      ],
    };

    const nextState = await pollReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher: () => ({
          agents: [
            {
              agent: 'coderabbit',
              state: 'completed',
              note: 'review completed without actionable findings',
            },
          ],
          detected: true,
          artifactText: 'normalized ai review artifact',
          reviewedHeadSha: 'abcdef1234567890',
          vendors: ['coderabbit'],
          comments: [],
        }),
        triager: () => ({
          outcome: 'clean',
          note: 'External AI review completed without prudent follow-up changes.',
          vendors: ['coderabbit'],
        }),
        updatePullRequestBody: async () => {},
      },
    );

    expect(nextState.tickets[0]).toMatchObject({
      status: 'done',
      reviewOutcome: 'patched',
      reviewTriageArtifactPath:
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
    });
    expect(
      await readArtifactJson(
        '/tmp/test_project',
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
      ),
    ).toMatchObject({
      note: 'External AI review completed without prudent follow-up changes. Earlier review cycles led to prudent follow-up patches, and the latest review pass found no additional prudent follow-up changes.',
      outcome: 'patched',
    });
  });

  it('preserves patched as the cumulative outcome when a later poll finds no ai review', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
          reviewOutcome: 'patched',
          reviewNote: 'Patched the prudent AI review follow-up.',
        },
      ],
    };

    const nextState = await pollReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher: () => ({
          agents: [],
          detected: false,
          artifactText: '',
          vendors: [],
          comments: [],
        }),
        updatePullRequestBody: async () => {},
      },
    );

    expect(nextState.tickets[0]).toMatchObject({
      status: 'done',
      reviewOutcome: 'patched',
      reviewTriageArtifactPath:
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
    });
    expect(
      await readArtifactJson(
        '/tmp/test_project',
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
      ),
    ).toMatchObject({
      note: 'No AI review feedback was detected within the 12-minute polling window. Earlier review cycles led to prudent follow-up patches, and the latest review pass found no additional prudent follow-up changes.',
      outcome: 'patched',
    });
  });

  it('matches standalone cumulative patched semantics when a later review pass is clean', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
          reviewOutcome: 'patched',
          reviewNote: 'Patched the prudent AI review follow-up.',
        },
      ],
    };
    const fetcher = () => ({
      agents: [
        {
          agent: 'coderabbit' as const,
          state: 'completed' as const,
          note: 'review completed without actionable findings',
        },
      ],
      detected: true,
      artifactText: 'normalized ai review artifact',
      reviewedHeadSha: 'abcdef1234567890',
      vendors: ['coderabbit'],
      comments: [],
    });
    const triager = () => ({
      outcome: 'clean' as const,
      note: 'External AI review completed without prudent follow-up changes.',
      vendors: ['coderabbit'],
    });

    const nextState = await pollReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher,
        triager,
        updatePullRequestBody: async () => {},
      },
    );
    const standaloneResult = await runStandaloneAiReview(
      '/tmp/test_project',
      { kind: 'noop', enabled: false },
      testContext(),
      undefined,
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher,
        triager,
        previousOutcome: 'patched',
        pullRequest: {
          body: 'existing body',
          createdAt: '2026-04-01T10:00:00.000Z',
          headRefName:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          headRefOid: 'fedcba0987654321',
          number: 20,
          title:
            'feat: persist transmission identity for queued torrents [P3.01]',
          url: 'https://example.test/pull/20',
        },
        updatePullRequestBody: () => {},
        writeNote: async () => {},
      },
    );

    expect(standaloneResult.outcome).toBe('patched');
    expect(nextState.tickets[0]?.reviewOutcome).toBe('patched');
    expect(standaloneResult.note).toBe(
      'External AI review completed without prudent follow-up changes. Earlier review cycles led to prudent follow-up patches, and the latest review pass found no additional prudent follow-up changes.',
    );
  });

  it('matches standalone cumulative patched semantics when no later ai review appears', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
          reviewOutcome: 'patched',
          reviewNote: 'Patched the prudent AI review follow-up.',
        },
      ],
    };
    const fetcher = () => ({
      agents: [],
      detected: false,
      artifactText: '',
      vendors: [],
      comments: [],
    });

    const nextState = await pollReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher,
        updatePullRequestBody: async () => {},
      },
    );
    const standaloneResult = await runStandaloneAiReview(
      '/tmp/test_project',
      { kind: 'noop', enabled: false },
      testContext(),
      undefined,
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher,
        previousOutcome: 'patched',
        pullRequest: {
          body: 'existing body',
          createdAt: '2026-04-01T10:00:00.000Z',
          headRefName:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          headRefOid: 'fedcba0987654321',
          number: 20,
          title:
            'feat: persist transmission identity for queued torrents [P3.01]',
          url: 'https://example.test/pull/20',
        },
        updatePullRequestBody: () => {},
        writeNote: async () => {},
      },
    );

    expect(standaloneResult.outcome).toBe('patched');
    expect(nextState.tickets[0]?.reviewOutcome).toBe('patched');
    expect(standaloneResult.note).toBe(
      'No AI review feedback was detected within the 12-minute polling window. Earlier review cycles led to prudent follow-up patches, and the latest review pass found no additional prudent follow-up changes.',
    );
  });

  it('matches standalone timeout note semantics when agents stay in flight without findings', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
        },
      ],
    };
    const fetcher = () => ({
      agents: [
        {
          agent: 'coderabbit' as const,
          state: 'started' as const,
          note: 'review still in progress',
        },
      ],
      detected: true,
      artifactText: 'started only artifact',
      vendors: ['coderabbit'],
      comments: [],
    });

    const nextState = await pollReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher,
        updatePullRequestBody: async () => {},
      },
    );
    const standaloneResult = await runStandaloneAiReview(
      '/tmp/test_project',
      { kind: 'noop', enabled: false },
      testContext(),
      undefined,
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher,
        previousOutcome: 'clean',
        pullRequest: {
          body: 'existing body',
          createdAt: '2026-04-01T10:00:00.000Z',
          headRefName:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          headRefOid: 'fedcba0987654321',
          number: 20,
          title:
            'feat: persist transmission identity for queued torrents [P3.01]',
          url: 'https://example.test/pull/20',
        },
        updatePullRequestBody: () => {},
        writeNote: async () => {},
      },
    );

    expect(standaloneResult.outcome).toBe('clean');
    expect(nextState.tickets[0]?.reviewOutcome).toBe('clean');
    expect(standaloneResult.note).toBe(
      'AI review reached the 12-minute limit while waiting on: coderabbit. No actionable findings were captured. Rerun manually if needed.',
    );
  });

  it('uses the standalone pull request createdAt to timeout mixed vendor states immediately on late reruns', async () => {
    const sleeps: number[] = [];
    const standaloneResult = await runStandaloneAiReview(
      '/tmp/test_project',
      { kind: 'noop', enabled: false },
      testContext(),
      undefined,
      {
        now: () => Date.parse('2026-04-01T10:12:00.000Z'),
        sleep: async (milliseconds) => {
          sleeps.push(milliseconds);
        },
        fetcher: () => ({
          agents: [
            {
              agent: 'coderabbit' as const,
              state: 'started' as const,
              note: 'review still in progress',
            },
            {
              agent: 'greptile' as const,
              state: 'findings_detected' as const,
              findingsCount: 1,
              note: 'actionable findings captured',
            },
          ],
          detected: true,
          artifactText: 'mixed vendor artifact',
          reviewedHeadSha: 'abcdef1234567890',
          vendors: ['coderabbit', 'greptile'],
          comments: [
            {
              vendor: 'greptile',
              channel: 'inline_review' as const,
              authorLogin: 'greptile-apps[bot]',
              authorType: 'Bot' as const,
              body: 'Guard the null return here.',
              kind: 'unknown' as const,
              path: 'tools/delivery/review.ts',
              line: 700,
            },
          ],
        }),
        triager: () => ({
          outcome: 'needs_patch' as const,
          note: 'AI review comments were detected, but at least one item still needs manual judgment.',
          actionSummary: 'Escalated 1 unclear comment for follow-up.',
          vendors: ['greptile'],
        }),
        pullRequest: {
          body: 'existing body',
          createdAt: '2026-04-01T10:00:00.000Z',
          headRefName: 'codex/sonarqube-standalone-triage',
          headRefOid: 'abcdef1234567890',
          number: 75,
          title: 'feat: add SonarQube support to standalone triage flow',
          url: 'https://example.test/pull/75',
        },
        updatePullRequestBody: () => {},
        writeNote: async () => {},
      },
    );

    expect(sleeps).toEqual([]);
    expect(standaloneResult.outcome).toBe('operator_input_needed');
    expect(standaloneResult.incompleteAgents).toEqual(['coderabbit']);
    expect(standaloneResult.vendors).toEqual(['coderabbit', 'greptile']);
    expect(standaloneResult.note).toBe(
      'AI review reached the 12-minute limit while waiting on: coderabbit. Triage the captured findings and rerun manually if needed.',
    );
  });

  it('maps standalone needs-patch triage to operator input at the shared accumulation seam', async () => {
    const fetcher = () => ({
      agents: [
        {
          agent: 'coderabbit' as const,
          state: 'findings_detected' as const,
          findingsCount: 1,
          note: 'actionable findings captured',
        },
      ],
      detected: true,
      artifactText: 'normalized ai review artifact',
      reviewedHeadSha: 'abcdef1234567890',
      vendors: ['coderabbit'],
      comments: [
        {
          vendor: 'coderabbit',
          channel: 'inline_review' as const,
          authorLogin: 'coderabbitai',
          authorType: 'Bot' as const,
          body: 'Guard the null return here.',
          kind: 'finding' as const,
        },
      ],
    });
    const triager = () => ({
      outcome: 'needs_patch' as const,
      note: 'Actionable AI review findings were detected and still need follow-up.',
      actionSummary: 'Flagged 1 finding comment for follow-up.',
      vendors: ['coderabbit'],
    });

    const standaloneResult = await runStandaloneAiReview(
      '/tmp/test_project',
      { kind: 'noop', enabled: false },
      testContext(),
      undefined,
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher,
        triager,
        pullRequest: {
          body: 'existing body',
          createdAt: '2026-04-01T10:00:00.000Z',
          headRefName:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          headRefOid: 'fedcba0987654321',
          number: 20,
          title:
            'feat: persist transmission identity for queued torrents [P3.01]',
          url: 'https://example.test/pull/20',
        },
        updatePullRequestBody: () => {},
        writeNote: async () => {},
      },
    );

    expect(standaloneResult.outcome).toBe('operator_input_needed');
    expect(standaloneResult.note).toBe(
      'Actionable AI review findings were detected and still need follow-up.',
    );
  });

  it('does not resolve standalone review threads when outcome mapping changes needs-patch to operator input', async () => {
    let resolveThreadsCalls = 0;
    const fetcher = () => ({
      agents: [
        {
          agent: 'coderabbit',
          state: 'findings_detected' as const,
          findingsCount: 1,
          note: 'actionable findings captured',
        },
      ],
      detected: true,
      artifactText: 'normalized ai review artifact',
      reviewedHeadSha: 'abcdef1234567890',
      vendors: ['coderabbit'],
      comments: [
        {
          vendor: 'coderabbit',
          channel: 'inline_review' as const,
          authorLogin: 'coderabbitai',
          authorType: 'Bot' as const,
          body: 'Guard the null return here.',
          kind: 'finding' as const,
          threadId: 'thread_example_1',
          url: 'https://example.test/comment/1',
        },
      ],
    });
    const triager = () => ({
      outcome: 'needs_patch' as const,
      note: 'Actionable AI review findings were detected and still need follow-up.',
      actionSummary: 'Flagged 1 finding comment for follow-up.',
      vendors: ['coderabbit'],
    });

    const standaloneResult = await runStandaloneAiReview(
      '/tmp/test_project',
      { kind: 'noop', enabled: false },
      testContext(),
      undefined,
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher,
        triager,
        pullRequest: {
          body: 'existing body',
          createdAt: '2026-04-01T10:00:00.000Z',
          headRefName:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          headRefOid: 'fedcba0987654321',
          number: 20,
          title:
            'feat: persist transmission identity for queued torrents [P3.01]',
          url: 'https://example.test/pull/20',
        },
        resolveThreads: () => {
          resolveThreadsCalls += 1;
          return [
            {
              status: 'resolved' as const,
              threadId: 'thread_example_1',
              url: 'https://example.test/comment/1',
              vendor: 'coderabbit',
            },
          ];
        },
        updatePullRequestBody: () => {},
        writeNote: async () => {},
      },
    );

    expect(standaloneResult.outcome).toBe('operator_input_needed');
    expect(standaloneResult.threadResolutions).toBeUndefined();
    expect(resolveThreadsCalls).toBe(0);
  });

  it('uses the normal polling cadence when prOpenedAt is missing', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
        },
      ],
    };
    const sleeps: number[] = [];

    await pollReview(state, '/tmp/test_project', testContext(), 'P3.01', {
      now: () => Date.parse('2026-04-01T10:00:00.000Z'),
      sleep: async (milliseconds) => {
        sleeps.push(milliseconds);
      },
      fetcher: () => ({
        agents: [
          {
            agent: 'coderabbit',
            state: 'findings_detected',
            findingsCount: 1,
            note: 'actionable findings captured',
          },
        ],
        detected: true,
        artifactText: 'normalized ai review artifact',
        reviewedHeadSha: 'abcdef1234567890',
        vendors: ['coderabbit'],
        comments: [
          {
            vendor: 'coderabbit',
            channel: 'inline_review',
            authorLogin: 'coderabbitai',
            authorType: 'Bot',
            body: 'Guard the null return here.',
            threadId: 'thread_example_1',
            kind: 'finding',
          },
        ],
      }),
      triager: () => ({
        outcome: 'needs_patch',
        note: 'Actionable AI review findings were detected and still need follow-up.',
        actionSummary: 'Flagged 1 finding comment for follow-up.',
        nonActionSummary: undefined,
        vendors: ['coderabbit'],
      }),
    });

    expect(sleeps).toEqual([360000]);
  });

  it('triage-ticket keeps done status when triage resolves to needs_patch', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'done',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
          reviewOutcome: 'patched',
        },
      ],
    };
    const cwd = await mkdtemp(join(tmpdir(), 'orchestrator-reconcile-'));
    const sleeps: number[] = [];
    let fetchCount = 0;

    try {
      const nextState = await reconcileLateReview(
        state,
        cwd,
        testContext(),
        'P3.01',
        {
          now: () => Date.parse('2026-04-01T10:00:00.000Z'),
          sleep: async (milliseconds) => {
            sleeps.push(milliseconds);
          },
          fetcher: () => {
            fetchCount += 1;
            return {
              agents: [
                {
                  agent: 'coderabbit',
                  state: 'completed',
                  note: 'review completed',
                },
              ],
              detected: true,
              artifactText: 'late review artifact',
              reviewedHeadSha: 'abcdef1234567890',
              vendors: ['coderabbit'],
              comments: [
                {
                  vendor: 'coderabbit',
                  channel: 'inline_review',
                  authorLogin: 'coderabbitai',
                  authorType: 'Bot',
                  body: 'Late follow-up.',
                  threadId: 'thread_late_1',
                  threadViewerCanResolve: true,
                  kind: 'finding',
                },
              ],
            };
          },
          triager: () => ({
            outcome: 'needs_patch',
            note: 'Actionable AI review findings were detected and still need follow-up.',
            actionSummary: 'Flagged 1 finding comment for follow-up.',
            nonActionSummary: undefined,
            vendors: ['coderabbit'],
          }),
        },
      );

      expect(sleeps).toEqual([]);
      expect(fetchCount).toBe(1);
      expect(nextState.tickets[0]?.status).toBe('done');
      expect(nextState.tickets[0]?.reviewOutcome).toBe('needs_patch');
      expect(nextState.tickets[0]?.reviewFetchArtifactPath).toBe(
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.fetch.json',
      );
      expect(nextState.tickets[0]?.reviewHeadSha).toBe('abcdef1234567890');
      expect(
        eventsForReconcileLateReviewCommand(nextState, 'P3.01').map(
          (event) => event.kind,
        ),
      ).toEqual(['review_recorded']);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  it('triage-ticket rejects when the ticket is not done', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'in_review',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
        },
      ],
    };

    await expect(
      reconcileLateReview(state, '/tmp/test_project', testContext(), 'P3.01', {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher: () => ({
          agents: [],
          detected: false,
          artifactText: '',
          vendors: [],
          comments: [],
        }),
      }),
    ).rejects.toThrow(/must be done before ticket PR triage/);
  });

  it('triage-ticket keeps done and preserves prior artifacts on clean timeout', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'done',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          prUrl: 'https://example.test/pull/20',
          prNumber: 20,
          prOpenedAt: '2026-04-01T10:00:00.000Z',
          reviewOutcome: 'patched',
          reviewFetchArtifactPath:
            '.agents/delivery/phase-03/reviews/P3.01-pr-review.fetch.json',
          reviewTriageArtifactPath:
            '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
          reviewNote: 'Earlier patched note.',
        },
      ],
    };

    const nextState = await reconcileLateReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      {
        now: () => Date.parse('2026-04-01T10:00:00.000Z'),
        sleep: async () => {},
        fetcher: () => ({
          agents: [
            {
              agent: 'coderabbit',
              state: 'started',
              note: 'still running',
            },
          ],
          detected: false,
          artifactText: '',
          vendors: [],
          comments: [],
        }),
      },
    );

    expect(nextState.tickets[0]?.status).toBe('done');
    expect(nextState.tickets[0]?.reviewTriageArtifactPath).toBe(
      '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
    );
    expect(
      await readArtifactJson(
        '/tmp/test_project',
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
      ),
    ).toMatchObject({
      note: 'No AI review feedback was detected within the 1-minute polling window. Earlier review cycles led to prudent follow-up patches, and the latest review pass found no additional prudent follow-up changes.',
      outcome: 'patched',
    });
  });

  it('preserves the triage note when recording a final review outcome without a new note', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'needs_patch',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          reviewComments: [
            {
              vendor: 'coderabbit',
              channel: 'inline_review',
              authorLogin: 'coderabbitai',
              authorType: 'Bot',
              body: 'Guard the null return here.',
              kind: 'finding',
              threadId: 'thread_example_1',
              url: 'https://example.test/comment/1',
            },
          ],
          reviewNote:
            'Actionable AI review findings were detected and still need follow-up.',
        },
      ],
    };

    const nextState = await recordReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      'patched',
      undefined,
      {
        resolveThreads: () => [
          {
            status: 'resolved',
            threadId: 'thread_example_1',
            url: 'https://example.test/comment/1',
            vendor: 'coderabbit',
          },
        ],
        updatePullRequestBody: async () => {},
      },
    );

    expect(nextState.tickets[0]).toMatchObject({
      status: 'done',
      reviewOutcome: 'patched',
      reviewRecordedAt: expect.any(String),
    });
    expect(
      await readArtifactJson(
        '/tmp/test_project',
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
      ),
    ).toMatchObject({
      note: 'Actionable AI review findings were detected and still need follow-up.',
      outcome: 'patched',
      threadResolutions: [
        {
          status: 'resolved',
          threadId: 'thread_example_1',
          url: 'https://example.test/comment/1',
          vendor: 'coderabbit',
        },
      ],
    });
  });

  it('does not downgrade a patched review outcome when recording clean later', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'operator_input_needed',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          reviewOutcome: 'patched',
          reviewNote: 'Patched the prudent AI review follow-up.',
        },
      ],
    };

    const nextState = await recordReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      'clean',
      'External AI review completed without prudent follow-up changes.',
      {
        updatePullRequestBody: async () => {},
      },
    );

    expect(nextState.tickets[0]).toMatchObject({
      status: 'done',
      reviewOutcome: 'patched',
      reviewRecordedAt: expect.any(String),
    });
    expect(
      await readArtifactJson(
        '/tmp/test_project',
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
      ),
    ).toMatchObject({
      note: 'External AI review completed without prudent follow-up changes. Earlier review cycles led to prudent follow-up patches, and the latest review pass found no additional prudent follow-up changes.',
      outcome: 'clean',
    });
  });

  it('does not reuse a stale unresolved note when recording clean after operator input', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'operator_input_needed',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          reviewOutcome: 'patched',
          reviewNote:
            'Actionable AI review findings were detected and still need follow-up.',
        },
      ],
    };

    const nextState = await recordReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      'clean',
      undefined,
      {
        updatePullRequestBody: async () => {},
      },
    );

    expect(nextState.tickets[0]).toMatchObject({
      status: 'done',
      reviewOutcome: 'patched',
      reviewRecordedAt: expect.any(String),
    });
    expect(
      await readArtifactJson(
        '/tmp/test_project',
        '.agents/delivery/phase-03/reviews/P3.01-pr-review.triage.json',
      ),
    ).toMatchObject({
      note: 'External AI review completed without prudent follow-up changes. Earlier review cycles led to prudent follow-up patches, and the latest review pass found no additional prudent follow-up changes.',
      outcome: 'clean',
    });
  });

  it('reuses existing thread resolutions instead of resolving twice', async () => {
    const state: DeliveryState = {
      planKey: 'phase-03',
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
      statePath: '.agents/delivery/phase-03/state.json',
      reviewsDirPath: '.agents/delivery/phase-03/reviews',
      handoffsDirPath: '.agents/delivery/phase-03/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P3.01',
          title: 'Persist Transmission Identity For Queued Torrents',
          slug: 'persist-transmission-identity-for-queued-torrents',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-persist-transmission-identity-for-queued-torrents.md',
          status: 'needs_patch',
          branch:
            'agents/p3-01-persist-transmission-identity-for-queued-torrents',
          baseBranch: 'main',
          worktreePath: '/tmp/p3_01',
          reviewComments: [
            {
              vendor: 'coderabbit',
              channel: 'inline_review',
              authorLogin: 'coderabbitai',
              authorType: 'Bot',
              body: 'Guard the null return here.',
              kind: 'finding',
              threadId: 'thread_example_1',
              url: 'https://example.test/comment/1',
            },
          ],
          reviewThreadResolutions: [
            {
              status: 'resolved',
              threadId: 'thread_example_1',
              url: 'https://example.test/comment/1',
              vendor: 'coderabbit',
            },
          ],
        },
      ],
    };
    let resolveCalls = 0;

    const nextState = await recordReview(
      state,
      '/tmp/test_project',
      testContext(),
      'P3.01',
      'patched',
      undefined,
      {
        resolveThreads: () => {
          resolveCalls += 1;
          return [];
        },
        updatePullRequestBody: async () => {},
      },
    );

    expect(resolveCalls).toBe(0);
    expect(nextState.tickets[0]?.reviewThreadResolutions).toEqual([
      {
        status: 'resolved',
        threadId: 'thread_example_1',
        url: 'https://example.test/comment/1',
        vendor: 'coderabbit',
      },
    ]);
  });

  it('keeps notification failures best-effort', async () => {
    const originalToken = process.env.TELEGRAM_BOT_TOKEN;
    const originalChatId = process.env.TELEGRAM_CHAT_ID;
    const originalFetch = globalThis.fetch;

    process.env.TELEGRAM_BOT_TOKEN = 'bot-token';
    process.env.TELEGRAM_CHAT_ID = 'chat-id';
    globalThis.fetch = (async () =>
      new Response('nope', { status: 500 })) as unknown as typeof fetch;

    const warning = await notifyBestEffort(
      resolveNotifier(),
      '/tmp/test_project',
      {
        kind: 'ticket_started',
        planKey: 'phase-03',
        ticketId: 'P3.01',
        ticketTitle: 'Persist Transmission Identity For Queued Torrents',
        branch:
          'agents/p3-01-persist-transmission-identity-for-queued-torrents',
      },
    );

    expect(warning).toContain('Notification warning:');
    expect(warning).toContain('Telegram sendMessage failed with 500');

    process.env.TELEGRAM_BOT_TOKEN = originalToken;
    process.env.TELEGRAM_CHAT_ID = originalChatId;
    globalThis.fetch = originalFetch;
  });

  it('sends standalone telegram notifications with a linked pr label instead of a raw url', async () => {
    const originalToken = process.env.TELEGRAM_BOT_TOKEN;
    const originalChatId = process.env.TELEGRAM_CHAT_ID;
    const originalFetch = globalThis.fetch;
    const requests: string[] = [];

    process.env.TELEGRAM_BOT_TOKEN = 'bot-token';
    process.env.TELEGRAM_CHAT_ID = 'chat-id';
    globalThis.fetch = (async (
      _input: RequestInfo | URL,
      init?: RequestInit,
    ) => {
      requests.push(String(init?.body ?? ''));
      return new Response('{}', { status: 200 });
    }) as unknown as typeof fetch;

    await notifyBestEffort(resolveNotifier(), '/tmp/test_project', {
      kind: 'standalone_review_started',
      prNumber: 33,
      prUrl: 'https://example.test/pull/33',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
    });

    expect(requests).toHaveLength(1);
    expect(JSON.parse(requests[0] ?? '{}')).toMatchObject({
      text: 'Son of Anton PR #33\nAI review started.',
      entities: [
        {
          type: 'text_link',
          offset: 13,
          length: 6,
          url: 'https://example.test/pull/33',
        },
      ],
    });

    process.env.TELEGRAM_BOT_TOKEN = originalToken;
    process.env.TELEGRAM_CHAT_ID = originalChatId;
    globalThis.fetch = originalFetch;
  });

  it('prefers an explicit review fetcher environment variable', () => {
    const original = process.env.AI_CODE_REVIEW_FETCHER;
    try {
      process.env.AI_CODE_REVIEW_FETCHER = '/tmp/fetch_ai_review.sh';

      expect(resolveReviewFetcher()).toBe('/tmp/fetch_ai_review.sh');
    } finally {
      if (typeof original === 'undefined') {
        delete process.env.AI_CODE_REVIEW_FETCHER;
      } else {
        process.env.AI_CODE_REVIEW_FETCHER = original;
      }
    }
  });

  it('prefers an explicit review triager environment variable', () => {
    const original = process.env.AI_CODE_REVIEW_TRIAGER;
    try {
      process.env.AI_CODE_REVIEW_TRIAGER = '/tmp/triage_ai_review.sh';

      expect(resolveReviewTriager()).toBe('/tmp/triage_ai_review.sh');
    } finally {
      if (typeof original === 'undefined') {
        delete process.env.AI_CODE_REVIEW_TRIAGER;
      } else {
        process.env.AI_CODE_REVIEW_TRIAGER = original;
      }
    }
  });

  it('prefers subtree review hooks when the repo also has its own .agents directory', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'review-hooks-'));
    const originalCwd = process.cwd();
    const originalFetcher = process.env.AI_CODE_REVIEW_FETCHER;
    const originalTriager = process.env.AI_CODE_REVIEW_TRIAGER;

    try {
      delete process.env.AI_CODE_REVIEW_FETCHER;
      delete process.env.AI_CODE_REVIEW_TRIAGER;
      await mkdir(join(repoRoot, '.agents/skills/pr-review/scripts'), {
        recursive: true,
      });
      await mkdir(
        join(repoRoot, '.son-of-anton/.agents/skills/pr-review/scripts'),
        { recursive: true },
      );
      await writeFile(
        join(
          repoRoot,
          '.son-of-anton/.agents/skills/pr-review/scripts/fetch_pr_review_comments.sh',
        ),
        '#!/usr/bin/env bash\n',
      );
      await writeFile(
        join(
          repoRoot,
          '.son-of-anton/.agents/skills/pr-review/scripts/triage_pr_review.sh',
        ),
        '#!/usr/bin/env bash\n',
      );

      process.chdir(repoRoot);

      expect(resolveReviewFetcher()).toBe(
        '.son-of-anton/.agents/skills/pr-review/scripts/fetch_pr_review_comments.sh',
      );
      expect(resolveReviewTriager()).toBe(
        '.son-of-anton/.agents/skills/pr-review/scripts/triage_pr_review.sh',
      );
    } finally {
      process.chdir(originalCwd);
      if (typeof originalFetcher === 'undefined') {
        delete process.env.AI_CODE_REVIEW_FETCHER;
      } else {
        process.env.AI_CODE_REVIEW_FETCHER = originalFetcher;
      }
      if (typeof originalTriager === 'undefined') {
        delete process.env.AI_CODE_REVIEW_TRIAGER;
      } else {
        process.env.AI_CODE_REVIEW_TRIAGER = originalTriager;
      }
      await rm(repoRoot, { recursive: true, force: true });
    }
  });

  it('falls back to source-repo review hooks when no subtree exists', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'source-review-hooks-'));
    const originalCwd = process.cwd();
    const originalFetcher = process.env.AI_CODE_REVIEW_FETCHER;
    const originalTriager = process.env.AI_CODE_REVIEW_TRIAGER;

    try {
      delete process.env.AI_CODE_REVIEW_FETCHER;
      delete process.env.AI_CODE_REVIEW_TRIAGER;
      process.chdir(repoRoot);

      expect(resolveReviewFetcher()).toBe(
        '.agents/skills/pr-review/scripts/fetch_pr_review_comments.sh',
      );
      expect(resolveReviewTriager()).toBe(
        '.agents/skills/pr-review/scripts/triage_pr_review.sh',
      );
    } finally {
      process.chdir(originalCwd);
      if (typeof originalFetcher === 'undefined') {
        delete process.env.AI_CODE_REVIEW_FETCHER;
      } else {
        process.env.AI_CODE_REVIEW_FETCHER = originalFetcher;
      }
      if (typeof originalTriager === 'undefined') {
        delete process.env.AI_CODE_REVIEW_TRIAGER;
      } else {
        process.env.AI_CODE_REVIEW_TRIAGER = originalTriager;
      }
      await rm(repoRoot, { recursive: true, force: true });
    }
  });

  it('renders npm deliver invocations with a separator', () => {
    expect(generateRunDeliverInvocation('npm')).toBe('npm run deliver --');
    expect(generateRunDeliverInvocation('bun')).toBe('bun run deliver');
    expect(generateRunDeliverInvocation('pnpm')).toBe('pnpm run deliver');
  });

  it('surfaces node spawn startup errors in stderr', () => {
    const result = createPlatformAdapters({
      ...baseConfig,
      runtime: 'node',
    }).runProcessResult(process.cwd(), ['__codex_missing_binary_for_test__']);

    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain('__codex_missing_binary_for_test__');
  });

  it('replies to a thread before resolving when databaseId is present', () => {
    const calls: string[] = [];
    const finding = {
      vendor: 'coderabbit',
      channel: 'inline_review' as const,
      authorLogin: 'a',
      authorType: 'Bot',
      body: 'Fix this',
      kind: 'finding' as const,
      databaseId: 42,
      threadId: 't1',
      threadViewerCanResolve: true,
    };
    resolveNativeReviewThreads('/tmp/wt', [finding], {
      relativeToRepo: () => '',
      resolveReviewFetcher: () => '',
      resolveReviewTriager: () => '',
      runProcess: () => '',
      replyToReviewThread: (wp, id) => {
        calls.push(`reply:${id}`);
      },
      resolveReviewThread: () => {
        calls.push('resolve');
        return '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}';
      },
    });
    expect(calls).toEqual(['reply:42', 'resolve']);
  });

  it('still resolves when replyToReviewThread throws', () => {
    const calls: string[] = [];
    const finding = {
      vendor: 'coderabbit',
      channel: 'inline_review' as const,
      authorLogin: 'a',
      authorType: 'Bot',
      body: 'Fix this',
      kind: 'finding' as const,
      databaseId: 42,
      threadId: 't1',
      threadViewerCanResolve: true,
    };
    resolveNativeReviewThreads('/tmp/wt', [finding], {
      relativeToRepo: () => '',
      resolveReviewFetcher: () => '',
      resolveReviewTriager: () => '',
      runProcess: () => '',
      replyToReviewThread: () => {
        throw new Error('reply failed');
      },
      resolveReviewThread: () => {
        calls.push('resolve');
        return '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}';
      },
    });
    expect(calls).toEqual(['resolve']);
  });

  it('skips reply when databaseId is absent', () => {
    const calls: string[] = [];
    const finding = {
      vendor: 'coderabbit',
      channel: 'inline_review' as const,
      authorLogin: 'a',
      authorType: 'Bot',
      body: 'Fix this',
      kind: 'finding' as const,
      threadId: 't1',
      threadViewerCanResolve: true,
    };
    resolveNativeReviewThreads('/tmp/wt', [finding], {
      relativeToRepo: () => '',
      resolveReviewFetcher: () => '',
      resolveReviewTriager: () => '',
      runProcess: () => '',
      replyToReviewThread: () => {
        calls.push('reply');
      },
      resolveReviewThread: () => {
        calls.push('resolve');
        return '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}';
      },
    });
    expect(calls).toEqual(['resolve']);
  });

  describe('advanceToNextTicket (EE6: no auto-start)', () => {
    const baseTicket = {
      branch: 'agents/p1-01-foo',
      baseBranch: 'main',
      slug: 'foo',
      ticketFile: 'docs/product/delivery/phase-01/ticket-01-foo.md',
      worktreePath: '/tmp/p1_01',
    };

    const reviewedState: DeliveryState = {
      planKey: 'phase-1',
      planPath: 'docs/product/delivery/phase-01/implementation-plan.md',
      statePath: '.agents/delivery/phase-1/state.json',
      reviewsDirPath: '.agents/delivery/phase-1/reviews',
      handoffsDirPath: '.agents/delivery/phase-1/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          ...baseTicket,
          id: 'P1.01',
          title: 'Ticket One',
          status: 'reviewed',
          reviewOutcome: 'clean',
        },
        {
          id: 'P1.02',
          title: 'Ticket Two',
          slug: 'bar',
          ticketFile: 'docs/product/delivery/phase-01/ticket-02-bar.md',
          branch: 'agents/p1-02-bar',
          baseBranch: 'agents/p1-01-foo',
          worktreePath: '/tmp/p1_02',
          status: 'pending',
        },
      ],
    };

    it('marks the reviewed ticket done without starting the next ticket', async () => {
      const nextState = await advanceToNextTicket(reviewedState, '/tmp', {
        updatePullRequestBody: () => {},
      });

      const done = nextState.tickets.find((t) => t.id === 'P1.01');
      const pending = nextState.tickets.find((t) => t.id === 'P1.02');

      expect(done?.status).toBe('done');
      expect(pending?.status).toBe('pending');
    });

    it('throws when no reviewed ticket is ready', async () => {
      const noReviewedState: DeliveryState = {
        ...reviewedState,
        tickets: reviewedState.tickets.map((t) =>
          t.id === 'P1.01' ? { ...t, status: 'in_progress' as const } : t,
        ),
      };

      try {
        await advanceToNextTicket(noReviewedState, '/tmp', {
          updatePullRequestBody: () => {},
        });
        throw new Error('Expected advanceToNextTicket to reject.');
      } catch (error) {
        expect(error).toMatchObject({
          code: 'workflow.advance.requires_reviewed_ticket',
        });
        expect((error as Error).message).toContain(
          'No reviewed ticket is ready to advance.',
        );
      }
    });
  });

  describe('applyAdvanceBoundaryMode (EE7 cook continuation)', () => {
    const baseState: DeliveryState = {
      planKey: 'engineering-epic-07',
      planPath:
        'docs/product/delivery/engineering-epic-07/implementation-plan.md',
      statePath: '.agents/delivery/engineering-epic-07/state.json',
      reviewsDirPath: '.agents/delivery/engineering-epic-07/reviews',
      handoffsDirPath: '.agents/delivery/engineering-epic-07/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'EE7.01',
          title: 'Boundary policy plumbing and visibility',
          slug: 'boundary-policy-plumbing-and-visibility',
          ticketFile:
            'docs/product/delivery/engineering-epic-07/ticket-01-boundary-policy-plumbing-and-visibility.md',
          status: 'reviewed',
          branch: 'agents/ee7-01-boundary-policy-plumbing-and-visibility',
          baseBranch: 'main',
          worktreePath: '/tmp/ee7_01',
          reviewOutcome: 'patched',
        },
        {
          id: 'EE7.02',
          title: 'Gated boundary semantics and resume prompt',
          slug: 'gated-boundary-semantics-and-resume-prompt',
          ticketFile:
            'docs/product/delivery/engineering-epic-07/ticket-02-gated-boundary-semantics-and-resume-prompt.md',
          status: 'pending',
          branch: 'agents/ee7-02-gated-boundary-semantics-and-resume-prompt',
          baseBranch: 'agents/ee7-01-boundary-policy-plumbing-and-visibility',
          worktreePath: '/tmp/ee7_02',
        },
      ],
    };

    it('auto-starts the next ticket in cook mode', async () => {
      const context = testContext({
        ticketBoundaryMode: 'cook',
      });

      const advancedState: DeliveryState = {
        ...baseState,
        tickets: baseState.tickets.map((ticket) =>
          ticket.id === 'EE7.01'
            ? { ...ticket, status: 'done' as const }
            : ticket,
        ),
      };

      let startedTicketId: string | undefined;

      const nextState = await applyAdvanceBoundaryMode(
        baseState,
        advancedState,
        '/tmp',
        context,
        {
          startTicket: async (_state, _cwd, ticketId) => {
            startedTicketId = ticketId;

            return {
              ...advancedState,
              tickets: advancedState.tickets.map((ticket) =>
                ticket.id === 'EE7.02'
                  ? {
                      ...ticket,
                      status: 'in_progress' as const,
                      handoffPath:
                        '.agents/delivery/engineering-epic-07/handoffs/ee7-02-handoff.md',
                    }
                  : ticket,
              ),
            };
          },
        },
      );

      expect(startedTicketId).toBe('EE7.02');
      expect(
        nextState.tickets.find((ticket) => ticket.id === 'EE7.02')?.status,
      ).toBe('in_progress');
    });
  });
});
