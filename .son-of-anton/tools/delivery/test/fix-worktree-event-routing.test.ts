/**
 * Regression test: SoA events emitted during per-ticket worktree execution
 * must land in the primary repo's .soa/events.ndjson, not in the ephemeral
 * worktree's path (which is pruned on closeout).
 *
 * The bug: all appendSoaEvent call sites in runDeliverCli passed `cwd` as
 * projectRoot. When bun was invoked from inside a ticket worktree, events
 * wrote to <worktree>/.soa/events.ndjson instead of <primary>/.soa/events.ndjson.
 *
 * The fix: compute eventRoot = findPrimaryWorktreePath(cwd, config) ?? cwd
 * once after context setup, then use eventRoot for all emit calls.
 */
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  realpathSync,
  writeFileSync,
} from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { describe, expect, it } from 'bun:test';

import {
  findPrimaryWorktreePath,
  emitSoaEventsForTransitions,
} from '../cli-runner';
import type { ResolvedOrchestratorConfig } from '../config';
import type { DeliveryState, TicketState } from '../types';

function enabledConfig(): ResolvedOrchestratorConfig {
  return {
    defaultBranch: 'main',
    planRoot: 'docs',
    runtime: 'bun',
    packageManager: 'bun',
    ticketBoundaryMode: 'cook',
    reviewPolicy: { subagentReview: 'skip_doc_only', prReview: 'disabled' },
    codogotchi: { enabled: true },
  };
}

function makeTicket(id: string, status: TicketState['status']): TicketState {
  return {
    id,
    title: `Ticket ${id}`,
    slug: id.toLowerCase(),
    redPolicy: 'required',
    ticketFile: `docs/delivery/ticket-${id}.md`,
    status,
    branch: `agents/${id}`,
    baseBranch: 'main',
    worktreePath: '/tmp/fake',
  };
}

function makeState(planKey: string, tickets: TicketState[]): DeliveryState {
  return {
    planKey,
    planPath: `docs/product/delivery/${planKey}/implementation-plan.md`,
    statePath: `.agents/delivery/${planKey}/state.json`,
    reviewsDirPath: `docs/product/delivery/${planKey}/reviews`,
    handoffsDirPath: `.agents/delivery/${planKey}/handoffs`,
    reviewPollIntervalMinutes: 6,
    reviewPollMaxWaitMinutes: 12,
    tickets,
  };
}

/**
 * Create a minimal git repo with one commit on `main`, plus a linked worktree
 * at a sibling directory. Returns { primary, worktree } paths.
 */
function makeGitWorktreeFixture(): { primary: string; worktree: string } {
  const base = mkdtempSync(join(tmpdir(), 'soa-event-routing-'));
  const primaryRaw = join(base, 'primary');
  const worktreeRaw = join(base, 'worktree');

  mkdirSync(primaryRaw, { recursive: true });

  const git = (args: string[]) =>
    spawnSync('git', args, { cwd: primaryRaw, encoding: 'utf-8' });

  git(['init', '-b', 'main']);
  git(['config', 'user.email', 'test@test.com']);
  git(['config', 'user.name', 'Test']);
  writeFileSync(join(primaryRaw, 'README.md'), '# fixture');
  git(['add', '.']);
  git(['commit', '-m', 'initial']);
  git(['worktree', 'add', '--detach', worktreeRaw]);

  // Resolve symlinks so paths match what git worktree list --porcelain reports
  // (on macOS, /var/folders is a symlink to /private/var/folders).
  return {
    primary: realpathSync(primaryRaw),
    worktree: realpathSync(worktreeRaw),
  };
}

describe('findPrimaryWorktreePath — worktree routing', () => {
  it('returns primary path when called from a linked worktree', () => {
    const { primary, worktree } = makeGitWorktreeFixture();
    const config = enabledConfig();

    const resolved = findPrimaryWorktreePath(worktree, config);

    // Must resolve to primary, not the worktree itself.
    expect(resolved).not.toBeUndefined();
    expect(resolved).toBe(primary);
  });

  it('returns undefined when called from the primary repo (already home)', () => {
    const { primary } = makeGitWorktreeFixture();
    const config = enabledConfig();

    const resolved = findPrimaryWorktreePath(primary, config);

    // cwd is the primary repo itself — no separate primary to resolve to.
    // The ?? cwd fallback kicks in, so eventRoot === cwd, which is correct.
    expect(resolved).toBeUndefined();
  });
});

describe('emitSoaEventsForTransitions — events land in primary .soa/', () => {
  it('writes to primary .soa/ when projectRoot is resolved through findPrimaryWorktreePath', async () => {
    const { primary, worktree } = makeGitWorktreeFixture();
    const config = enabledConfig();

    // Simulate what runDeliverCli now does: resolve eventRoot from worktree CWD.
    const eventRoot = findPrimaryWorktreePath(worktree, config) ?? worktree;

    const previous = makeState('phase-04', [makeTicket('P4.01', 'pending')]);
    const next = makeState('phase-04', [makeTicket('P4.01', 'in_progress')]);

    await emitSoaEventsForTransitions(previous, next, config, eventRoot);

    // Event must appear in primary, not in the worktree.
    expect(existsSync(join(primary, '.soa', 'events.ndjson'))).toBe(true);
    expect(existsSync(join(worktree, '.soa', 'events.ndjson'))).toBe(false);

    const content = await readFile(
      join(primary, '.soa', 'events.ndjson'),
      'utf8',
    );
    const parsed = JSON.parse(content.trim().split('\n')[0]!);
    expect(parsed.name).toBe('ticket_started');
    expect(parsed.ticket_id).toBe('P4.01');
  });

  it('events land in primary when bun is invoked from a worktree (pre-fix behaviour regression)', async () => {
    const { primary, worktree } = makeGitWorktreeFixture();
    const config = enabledConfig();

    // Pre-fix: passing worktree directly as projectRoot would have written here.
    // Post-fix: eventRoot resolves to primary so worktree gets nothing.
    const eventRoot = findPrimaryWorktreePath(worktree, config) ?? worktree;

    const previous = makeState('phase-04', [
      makeTicket('P4.01', 'in_progress'),
    ]);
    const next = makeState('phase-04', [makeTicket('P4.01', 'done')]);

    await emitSoaEventsForTransitions(previous, next, config, eventRoot);

    expect(existsSync(join(worktree, '.soa'))).toBe(false);

    const content = await readFile(
      join(primary, '.soa', 'events.ndjson'),
      'utf8',
    );
    const parsed = JSON.parse(content.trim().split('\n')[0]!);
    expect(parsed.name).toBe('ticket_completed');
  });
});
