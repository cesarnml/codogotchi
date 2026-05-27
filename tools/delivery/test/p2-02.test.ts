import { describe, expect, it } from 'bun:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';

import { buildTicketHandoff, writeTicketHandoff } from '../ticket-flow';
import type { DeliveryState } from '../types';

const REPO_ROOT = resolve(import.meta.dir, '../../..');

const gatedState: DeliveryState = {
  planKey: 'phase-02',
  planPath: 'docs/product/delivery/phase-02/implementation-plan.md',
  statePath: '.agents/delivery/phase-02/state.json',
  reviewsDirPath: '.agents/delivery/phase-02/reviews',
  handoffsDirPath: '.agents/delivery/phase-02/handoffs',
  reviewPollIntervalMinutes: 6,
  reviewPollMaxWaitMinutes: 12,
  tickets: [
    {
      id: 'P2.02',
      title: 'Docs, shell scripts, skill rename, example config',
      slug: 'docs-shell-scripts-skill-rename-example-config',
      ticketFile:
        'docs/product/delivery/phase-02/ticket-02-docs-scripts-skill-rename-example-config.md',
      status: 'in_progress',
      branch: 'agents/p2-02-docs-shell-scripts-skill-rename-example-config',
      baseBranch:
        'agents/p2-01-core-orchestrator-schema-cli-state-machine-tests',
      worktreePath: '/tmp/p2-02-worktree',
    },
  ],
};

describe('P2.02 — delivery-orchestrator.md cleanliness and gated handoff RESUME COMMAND', () => {
  it('delivery-orchestrator.md contains no occurrences of old command/config names', async () => {
    const content = await readFile(
      resolve(REPO_ROOT, 'docs/template/delivery/delivery-orchestrator.md'),
      'utf8',
    );
    const forbidden = [
      'selfAudit',
      'codexPreflight',
      'codex-preflight',
      'post-verify-self-audit',
    ];
    for (const term of forbidden) {
      expect(content).not.toContain(term);
    }
  });

  it('gated handoff with subagentReview disabled contains RESUME COMMAND pointing to open-pr', () => {
    const handoff = buildTicketHandoff(
      gatedState,
      gatedState.tickets[0]!,
      undefined,
      {
        ticketBoundaryMode: 'gated',
        subagentReviewPolicy: 'disabled',
      },
    );
    expect(handoff).toContain('## RESUME COMMAND');
    expect(handoff).toContain(
      'bun run deliver --plan docs/product/delivery/phase-02/implementation-plan.md open-pr',
    );
  });

  it('gated handoff with subagentReview required contains RESUME COMMAND pointing to subagent-review', () => {
    const handoff = buildTicketHandoff(
      gatedState,
      gatedState.tickets[0]!,
      undefined,
      {
        ticketBoundaryMode: 'gated',
        subagentReviewPolicy: 'required',
      },
    );
    expect(handoff).toContain('## RESUME COMMAND');
    expect(handoff).toContain(
      'bun run deliver --plan docs/product/delivery/phase-02/implementation-plan.md subagent-review',
    );
  });

  it('cook mode handoff does not contain ## RESUME COMMAND section', () => {
    const handoff = buildTicketHandoff(
      gatedState,
      gatedState.tickets[0]!,
      undefined,
      {
        ticketBoundaryMode: 'cook',
      },
    );
    expect(handoff).not.toContain('## RESUME COMMAND');
  });

  it('writeTicketHandoff persists the gated resume command in the artifact', async () => {
    const tempDir = await mkdtemp(resolve(tmpdir(), 'p2-02-handoff-'));

    try {
      const result = await writeTicketHandoff(gatedState, tempDir, 'P2.02', {
        relativeToRepo: (_cwd, absolutePath) => absolutePath,
        subagentReviewPolicy: 'required',
        ticketBoundaryMode: 'gated',
      });

      const content = await readFile(result.relativePath, 'utf8');
      expect(content).toContain('## RESUME COMMAND');
      expect(content).toContain(
        'bun run deliver --plan docs/product/delivery/phase-02/implementation-plan.md subagent-review',
      );
    } finally {
      await rm(tempDir, { recursive: true, force: true });
    }
  });
});
