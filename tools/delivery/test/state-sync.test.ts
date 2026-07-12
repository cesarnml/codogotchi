import { describe, expect, it } from 'bun:test';
import { existsSync } from 'node:fs';
import { mkdtemp, readFile, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import type { DeliveryState } from '../types';
import { syncStateToPrimaryIfNeeded } from '../cli-runner';

const baseState: DeliveryState = {
  planKey: 'phase-test',
  planPath: 'docs/product/delivery/phase-test/implementation-plan.md',
  statePath: '.agents/delivery/phase-test/state.json',
  reviewsDirPath: '.agents/delivery/phase-test/reviews',
  handoffsDirPath: '.agents/delivery/phase-test/handoffs',
  reviewPollIntervalMinutes: 6,
  reviewPollMaxWaitMinutes: 12,
  tickets: [
    {
      id: 'PT.01',
      title: 'Test ticket',
      slug: 'test-ticket',
      ticketFile: 'docs/product/delivery/phase-test/ticket-01-test-ticket.md',
      status: 'done',
      branch: 'agents/pt-01-test-ticket',
      baseBranch: 'main',
      worktreePath: '/tmp/phase-test-wt',
      reviewOutcome: 'clean',
    },
  ],
};

describe('syncStateToPrimaryIfNeeded (P1.01)', () => {
  it('writes state.json to primary checkout when cwd differs from primary', async () => {
    const ticketWt = await mkdtemp(join(tmpdir(), 'ticket-wt-'));
    const primaryWt = await mkdtemp(join(tmpdir(), 'primary-wt-'));

    try {
      await syncStateToPrimaryIfNeeded(ticketWt, baseState, () => primaryWt);

      const stateFile = join(primaryWt, baseState.statePath);
      expect(existsSync(stateFile)).toBe(true);

      const written = JSON.parse(await readFile(stateFile, 'utf8')) as Record<
        string,
        unknown
      >;
      expect(written['planKey']).toBe('phase-test');
    } finally {
      await rm(ticketWt, { recursive: true, force: true });
      await rm(primaryWt, { recursive: true, force: true });
    }
  });

  it('does not write to primary when cwd resolves to the same path as primary', async () => {
    const primaryWt = await mkdtemp(join(tmpdir(), 'primary-wt-'));

    try {
      await syncStateToPrimaryIfNeeded(primaryWt, baseState, () => primaryWt);

      const stateFile = join(primaryWt, baseState.statePath);
      expect(existsSync(stateFile)).toBe(false);
    } finally {
      await rm(primaryWt, { recursive: true, force: true });
    }
  });

  it('does not write to primary when cwd is a symlink alias to primary', async () => {
    const primaryWt = await mkdtemp(join(tmpdir(), 'primary-wt-'));
    const aliasWt = join(tmpdir(), `primary-wt-alias-${Date.now()}`);

    try {
      await symlink(primaryWt, aliasWt, 'dir');
      await syncStateToPrimaryIfNeeded(aliasWt, baseState, () => primaryWt);

      const stateFile = join(primaryWt, baseState.statePath);
      expect(existsSync(stateFile)).toBe(false);
    } finally {
      await rm(aliasWt, { recursive: true, force: true });
      await rm(primaryWt, { recursive: true, force: true });
    }
  });

  it('skips sync without error when no primary path is found', async () => {
    const cwd = await mkdtemp(join(tmpdir(), 'ticket-wt-'));

    try {
      await expect(
        syncStateToPrimaryIfNeeded(cwd, baseState, () => undefined),
      ).resolves.toBeUndefined();
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
