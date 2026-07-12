import { describe, expect, it } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { createOptions, syncStateFromScratch } from '../orchestrator';
import {
  inferPackageManager,
  loadOrchestratorConfig,
  resolveOrchestratorConfig,
  type ResolvedOrchestratorConfig,
} from '../runtime-config';

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
  },
};

describe('orchestrator config', () => {
  it('returns defaults when config file is absent', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      const config = await loadOrchestratorConfig(tempDir);
      expect(config).toEqual({});
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('loads a partial config and preserves specified fields', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({
          defaultBranch: 'develop',
          deliveryBaseBranch: 'integration',
          closeoutBranch: 'release',
          runtime: 'node',
        }),
      );

      const config = await loadOrchestratorConfig(tempDir);
      expect(config).toEqual({
        defaultBranch: 'develop',
        deliveryBaseBranch: 'integration',
        closeoutBranch: 'release',
        planRoot: undefined,
        runtime: 'node',
        packageManager: undefined,
        ticketBoundaryMode: undefined,
      });
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws on invalid runtime value', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({ runtime: 'deno' }),
      );

      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /Invalid runtime "deno"/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws on invalid packageManager value', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({ packageManager: 'cargo' }),
      );

      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /Invalid packageManager "cargo"/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws on invalid ticketBoundaryMode value', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({ ticketBoundaryMode: 'sprint' }),
      );

      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /Invalid ticketBoundaryMode "sprint"/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws on non-string defaultBranch', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({ defaultBranch: 42 }),
      );

      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /Invalid defaultBranch/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws when config json is not an object', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(join(tempDir, 'orchestrator.config.json'), '[]');

      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /must contain a JSON object/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws on blank defaultBranch', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({ defaultBranch: '   ' }),
      );

      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /Expected a non-blank string/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws when deliveryBaseBranch is missing', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({ defaultBranch: 'main', closeoutBranch: 'main' }),
      );

      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /deliveryBaseBranch/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws when closeoutBranch is missing', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({ defaultBranch: 'main', deliveryBaseBranch: 'main' }),
      );

      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /closeoutBranch/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws on blank deliveryBaseBranch', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({
          defaultBranch: 'main',
          deliveryBaseBranch: '   ',
          closeoutBranch: 'main',
        }),
      );

      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /deliveryBaseBranch/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws on blank closeoutBranch', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({
          defaultBranch: 'main',
          deliveryBaseBranch: 'main',
          closeoutBranch: '   ',
        }),
      );

      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /closeoutBranch/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws on blank planRoot', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({
          deliveryBaseBranch: 'main',
          closeoutBranch: 'main',
          planRoot: '   ',
        }),
      );

      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /Expected a non-blank string/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('resolves empty config to defaults', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-resolve-'));
    try {
      const resolved = resolveOrchestratorConfig({}, tempDir);
      expect(resolved).toMatchObject({
        defaultBranch: 'main',
        deliveryBaseBranch: 'main',
        closeoutBranch: 'main',
        planRoot: 'docs',
        runtime: 'bun',
        packageManager: 'npm',
        ticketBoundaryMode: 'cook',
        reviewPolicy: {
          subagentReview: 'skip_doc_only',
          prReview: 'skip_doc_only',
        },
        codogotchi: { enabled: true },
      });
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('merges partial config with defaults', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-resolve-'));
    try {
      const resolved = resolveOrchestratorConfig(
        {
          defaultBranch: 'develop',
          deliveryBaseBranch: 'integration',
          closeoutBranch: 'release',
          planRoot: 'specifications',
        } as never,
        tempDir,
      );
      expect(resolved.defaultBranch).toBe('develop');
      expect(resolved.deliveryBaseBranch).toBe('integration');
      expect(resolved.closeoutBranch).toBe('release');
      expect(resolved.planRoot).toBe('specifications');
      expect(resolved.runtime).toBe('bun');
      expect(resolved.packageManager).toBe('npm');
      expect(resolved.ticketBoundaryMode).toBe('cook');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('preserves configured ticketBoundaryMode when resolving config', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-cfg-resolve-'));
    try {
      const resolved = resolveOrchestratorConfig(
        { ticketBoundaryMode: 'gated' },
        tempDir,
      );
      expect(resolved.ticketBoundaryMode).toBe('gated');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('infers bun from bun.lock', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-pm-'));
    try {
      await writeFile(join(tempDir, 'bun.lock'), '');
      expect(inferPackageManager(tempDir)).toBe('bun');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('infers pnpm from pnpm-lock.yaml', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-pm-'));
    try {
      await writeFile(join(tempDir, 'pnpm-lock.yaml'), '');
      expect(inferPackageManager(tempDir)).toBe('pnpm');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('infers yarn from yarn.lock', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-pm-'));
    try {
      await writeFile(join(tempDir, 'yarn.lock'), '');
      expect(inferPackageManager(tempDir)).toBe('yarn');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('infers npm from package-lock.json', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-pm-'));
    try {
      await writeFile(join(tempDir, 'package-lock.json'), '{}');
      expect(inferPackageManager(tempDir)).toBe('npm');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('falls back to npm when no lockfile is present', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'orch-pm-'));
    try {
      expect(inferPackageManager(tempDir)).toBe('npm');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('syncStateFromScratch uses configured deliveryBaseBranch for first ticket baseBranch', () => {
    const config: ResolvedOrchestratorConfig = {
      ...baseConfig,
      defaultBranch: 'develop',
      deliveryBaseBranch: 'release-next',
    };
    const options = createOptions({
      planPath: 'docs/product/delivery/phase-03/implementation-plan.md',
    });

    const synced = syncStateFromScratch(
      [
        {
          id: 'P3.01',
          title: 'First Ticket',
          slug: 'first-ticket',
          ticketFile:
            'docs/product/delivery/phase-03/ticket-01-first-ticket.md',
        },
      ],
      '/workspace/test',
      options,
      config,
    );

    expect(synced.tickets[0]?.baseBranch).toBe('release-next');
  });
});

describe('P2.01 — subagentReview schema, prReview, and prReviewAgents validation', () => {
  it('throws when selfAudit key is present in reviewPolicy', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p2-cfg-selfaudit-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({
          deliveryBaseBranch: 'main',
          closeoutBranch: 'main',
          reviewPolicy: { selfAudit: 'disabled' },
        }),
      );
      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /selfAudit/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws when codexPreflight key is present in reviewPolicy', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p2-cfg-codexpreflight-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({
          deliveryBaseBranch: 'main',
          closeoutBranch: 'main',
          reviewPolicy: { codexPreflight: 'disabled' },
        }),
      );
      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /codexPreflight/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws when prReview is required but prReviewAgents is missing', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p2-cfg-prreviewagents-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({
          deliveryBaseBranch: 'main',
          closeoutBranch: 'main',
          reviewPolicy: { prReview: 'required' },
        }),
      );
      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /prReviewAgents/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('succeeds when prReview is disabled without prReviewAgents', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p2-cfg-prreview-disabled-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({
          deliveryBaseBranch: 'main',
          closeoutBranch: 'main',
          reviewPolicy: { prReview: 'disabled' },
        }),
      );
      const config = await loadOrchestratorConfig(tempDir);
      expect(config.reviewPolicy?.prReview).toBe('disabled');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });
});
