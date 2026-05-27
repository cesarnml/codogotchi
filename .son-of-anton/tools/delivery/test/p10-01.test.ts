import { describe, expect, it } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { parseCliArgs } from '../cli';
import {
  loadOrchestratorConfig,
  resolveOrchestratorConfig,
} from '../runtime-config';
import { formatRunPolicy } from '../format';
import { deriveRunPolicyFromConfig } from '../state';
import {
  buildRunnerArtifact,
  buildRunnerInvocation,
  findDeliveryDocPaths,
  isDeliveryDocPath,
  tryRunner,
  validateRunnerArtifact,
} from '../subagent-runner';
import type { SubagentRunnerInvocation } from '../subagent-runner';
import type { ResolvedOrchestratorConfig } from '../runtime-config';
import type { RunPolicy } from '../types';

const baseResolvedConfig: ResolvedOrchestratorConfig = {
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

// ─── Clean-break: retired config keys throw ─────────────────────────────────

describe('P10.01 — retired config keys throw on load', () => {
  it('throws when subagentReviewRunner is present in config', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p10-01-retired-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({ subagentReviewRunner: { kind: 'claude-cli' } }),
      );
      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /subagentReviewRunner.*has been removed/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('throws when reviewSubagentOverride is present in config', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p10-01-retired2-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({ reviewSubagentOverride: 'codex:codex-rescue' }),
      );
      await expect(loadOrchestratorConfig(tempDir)).rejects.toThrow(
        /reviewSubagentOverride.*has been removed/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('loads cleanly when neither retired key is present', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p10-01-clean-'));
    try {
      await writeFile(
        join(tempDir, 'orchestrator.config.json'),
        JSON.stringify({ ticketBoundaryMode: 'cook' }),
      );
      const config = await loadOrchestratorConfig(tempDir);
      expect(config.ticketBoundaryMode).toBe('cook');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });
});

// ─── resolveOrchestratorConfig ───────────────────────────────────────────────

describe('P10.01 — resolveOrchestratorConfig', () => {
  it('resolves with no subagentReviewRunner field', () => {
    const resolved = resolveOrchestratorConfig({}, '/tmp/test');
    expect(
      (resolved as Record<string, unknown>)['subagentReviewRunner'],
    ).toBeUndefined();
    expect(
      (resolved as Record<string, unknown>)['reviewSubagentOverride'],
    ).toBeUndefined();
  });
});

// ─── deriveRunPolicyFromConfig ───────────────────────────────────────────────

describe('P10.01 — deriveRunPolicyFromConfig', () => {
  it('produces a RunPolicy with three fields (no reviewSubagent)', () => {
    const policy = deriveRunPolicyFromConfig(baseResolvedConfig);
    expect(policy).toEqual({
      ticketBoundaryMode: 'cook',
      subagentReview: 'skip_doc_only',
      prReview: 'skip_doc_only',
    });
    expect(
      (policy as Record<string, unknown>)['reviewSubagent'],
    ).toBeUndefined();
  });
});

// ─── CLI --subagent flag ─────────────────────────────────────────────

describe('P10.01 — CLI --subagent flag', () => {
  const usage = 'Usage: bun run deliver --plan <plan> <cmd>';

  it('parses --subagent claude-cli', () => {
    const parsed = parseCliArgs(
      [
        '--plan',
        'docs/product/delivery/p/impl.md',
        '--subagent',
        'claude-cli',
        'subagent-review',
      ],
      usage,
    );
    expect(parsed.subagent).toBe('claude-cli');
  });

  it('parses --subagent codex-cli', () => {
    const parsed = parseCliArgs(
      [
        '--plan',
        'docs/product/delivery/p/impl.md',
        '--subagent',
        'codex-cli',
        'subagent-review',
      ],
      usage,
    );
    expect(parsed.subagent).toBe('codex-cli');
  });

  it('throws on invalid --subagent value', () => {
    expect(() =>
      parseCliArgs(
        [
          '--plan',
          'docs/product/delivery/p/impl.md',
          '--subagent',
          'gemini-cli',
          'subagent-review',
        ],
        usage,
      ),
    ).toThrow(/--subagent/);
  });

  it('throws when --subagent value is missing', () => {
    expect(() =>
      parseCliArgs(
        [
          '--plan',
          'docs/product/delivery/p/impl.md',
          '--subagent',
          'subagent-review',
        ],
        usage,
      ),
    ).toThrow(/--subagent/);
  });

  it('leaves subagent undefined when flag is absent', () => {
    const parsed = parseCliArgs(
      ['--plan', 'docs/product/delivery/p/impl.md', 'subagent-review'],
      usage,
    );
    expect(parsed.subagent).toBeUndefined();
  });
});

// ─── tryRunner unit tests ─────────────────────────────────────────────────────

describe('P10.01 — tryRunner', () => {
  it('returns ran+clean when spawn succeeds and no changes', () => {
    const result = tryRunner(
      () => ({ exitCode: 0, timedOut: false }),
      () => false,
    );
    expect(result).toEqual({
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'completed',
    });
  });

  it('returns ran+patched when spawn succeeds and changes detected', () => {
    const result = tryRunner(
      () => ({ exitCode: 0, timedOut: false }),
      () => true,
    );
    expect(result).toEqual({
      status: 'ran',
      outcome: 'patched',
      terminatedReason: 'completed',
    });
  });

  it('returns unavailable when spawn throws', () => {
    const result = tryRunner(
      () => {
        throw new Error('not found');
      },
      () => false,
    );
    expect(result).toEqual({ status: 'unavailable' });
  });

  it('returns timeout when spawn times out', () => {
    const result = tryRunner(
      () => ({ exitCode: null, timedOut: true }),
      () => false,
    );
    expect(result).toEqual({ status: 'timeout' });
  });

  it('does not call checkHasChanges when spawned process timed out', () => {
    let checked = false;
    tryRunner(
      () => ({ exitCode: null, timedOut: true }),
      () => {
        checked = true;
        return false;
      },
    );
    expect(checked).toBe(false);
  });
});

// ─── subagent review prompt boundary ─────────────────────────────────────────

describe('P10.01 — subagent review hard write boundary', () => {
  // The generic changed-files runner prompt builder was removed in P13.03.
  // Runner invocations now consume the primary-agent-authored prompt persisted
  // by `write-subagent-adversarial-review`, so the boundary language lives in
  // that prompt artifact and the adversarial-review template, not in a built-in
  // builder. The path-classification helpers below are still authoritative.

  it('detects delivery doc paths across exact and nested paths', () => {
    expect(isDeliveryDocPath('docs/product/delivery')).toBe(true);
    expect(
      isDeliveryDocPath('docs/product/delivery/phase-01/ticket-01.md'),
    ).toBe(true);
    expect(
      isDeliveryDocPath('./docs/product/delivery/phase-01/reviews/a.json'),
    ).toBe(true);
    expect(isDeliveryDocPath('docs/product/retrospectives/phase-01.md')).toBe(
      false,
    );
    expect(isDeliveryDocPath('tools/delivery/cli-runner.ts')).toBe(false);
  });

  it('filters delivery doc paths from runner-changed files', () => {
    expect(
      findDeliveryDocPaths([
        'tools/delivery/cli-runner.ts',
        'docs/product/delivery/phase-01/ticket-01.md',
        'docs/template/delivery/delivery-orchestrator.md',
      ]),
    ).toEqual(['docs/product/delivery/phase-01/ticket-01.md']);
  });
});

// ─── validateRunnerArtifact ───────────────────────────────────────────────────

describe('P10.01 — validateRunnerArtifact', () => {
  function makeArtifact(invocation: SubagentRunnerInvocation) {
    return buildRunnerArtifact('P10.01', [invocation]);
  }

  it('validates a valid claude-cli structured artifact', () => {
    const artifact = makeArtifact(
      buildRunnerInvocation('claude-cli', 'abc123', 'clean'),
    );
    expect(validateRunnerArtifact(artifact)).toEqual(artifact);
  });

  it('validates a valid codex-cli structured artifact', () => {
    const artifact = makeArtifact(
      buildRunnerInvocation('codex-cli', 'def456', 'patched'),
    );
    expect(validateRunnerArtifact(artifact)).toEqual(artifact);
  });

  it('validates a skipped invocation', () => {
    const artifact = makeArtifact(
      buildRunnerInvocation('skipped', 'ghi789', 'skipped', {
        terminatedReason: 'runner_unavailable',
      }),
    );
    expect(validateRunnerArtifact(artifact)).toEqual(artifact);
  });

  it('returns null for legacy 4-field shape', () => {
    expect(
      validateRunnerArtifact({
        runnerKind: 'claude-cli',
        reviewedHeadSha: 'abc',
        outcome: 'clean',
        completedAt: 'x',
      }),
    ).toBeNull();
  });

  it('returns null for an invocation with invalid outcome', () => {
    expect(
      validateRunnerArtifact({
        ticket: 'P10.01',
        invocations: [
          {
            runnerKind: 'claude-cli',
            reviewedHeadSha: 'abc',
            outcome: 'bad',
            completedAt: 'x',
            terminatedReason: 'completed',
            findings: [],
            probedSurfaces: [],
            patches: [],
          },
        ],
      }),
    ).toBeNull();
  });

  it('returns null for non-object input', () => {
    expect(validateRunnerArtifact(null)).toBeNull();
    expect(validateRunnerArtifact('string')).toBeNull();
    expect(validateRunnerArtifact(42)).toBeNull();
  });
});

// ─── formatRunPolicy (no reviewSubagent) ─────────────────────────────────────

describe('P10.01 — formatRunPolicy without reviewSubagent', () => {
  it('formats policy with three fields only', () => {
    const policy: RunPolicy = {
      ticketBoundaryMode: 'cook',
      subagentReview: 'skip_doc_only',
      prReview: 'skip_doc_only',
    };
    const formatted = formatRunPolicy(policy);
    expect(formatted).toContain('boundary_mode=cook');
    expect(formatted).toContain('subagentReview:skip_doc_only');
    expect(formatted).toContain('prReview:skip_doc_only');
    expect(formatted).not.toContain('reviewSubagent');
  });
});
