import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { describe, expect, it } from 'bun:test';

import {
  buildRunnerInvocation,
  getFallbackFrom,
  getPrimaryAgent,
  getRunnerSelfReport,
  validateRunnerArtifact,
  writeSubagentReviewOutcome,
} from '../subagent-runner';
import type {
  SubagentRunnerArtifact,
  SubagentRunnerInvocation,
} from '../subagent-runner';

describe('P14.01 — outcome vocabulary expands to include deferred', () => {
  it('round-trips a deferred outcome through the validator', () => {
    const invocation = buildRunnerInvocation(
      'claude-cli',
      'abc123',
      'deferred',
      {
        primaryAgent: 'claude-code',
        schemaVersion: 1,
        runnerSelfReport: 'clean',
        fallbackFrom: null,
      },
    );
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P14.01',
      invocations: [invocation],
    };

    expect(validateRunnerArtifact(artifact)).toEqual(artifact);
    expect(artifact.invocations[0]?.outcome).toBe('deferred');
  });

  it('round-trips all four outcome values', () => {
    const outcomes = ['clean', 'patched', 'deferred', 'skipped'] as const;
    for (const outcome of outcomes) {
      const invocation = buildRunnerInvocation('claude-cli', 'sha', outcome, {
        primaryAgent: 'claude-code',
        schemaVersion: 1,
        runnerSelfReport: null,
        fallbackFrom: null,
      });
      const artifact: SubagentRunnerArtifact = {
        ticket: 'P14.01',
        invocations: [invocation],
      };
      expect(validateRunnerArtifact(artifact)?.invocations[0]?.outcome).toBe(
        outcome,
      );
    }
  });
});

describe('P14.01 — identity and provenance fields round-trip', () => {
  it('preserves schemaVersion, primaryAgent, runnerSelfReport, fallbackFrom', () => {
    const invocation = buildRunnerInvocation('codex-cli', 'sha', 'clean', {
      schemaVersion: 1,
      primaryAgent: 'codex-cli',
      runnerSelfReport: 'completed',
      fallbackFrom: 'claude-cli',
    });
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P14.01',
      invocations: [invocation],
    };

    const validated = validateRunnerArtifact(artifact);
    expect(validated).not.toBeNull();
    const row = validated!.invocations[0]!;
    expect(row.schemaVersion).toBe(1);
    expect(row.primaryAgent).toBe('codex-cli');
    expect(row.runnerSelfReport).toBe('completed');
    expect(row.fallbackFrom).toBe('claude-cli');
    expect(row.runnerKind).toBe('codex-cli');
  });

  it('accepts runnerSelfReport: null and fallbackFrom: null explicitly', () => {
    const invocation = buildRunnerInvocation('claude-cli', 'sha', 'clean', {
      schemaVersion: 1,
      primaryAgent: 'claude-code',
      runnerSelfReport: null,
      fallbackFrom: null,
    });
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P14.01',
      invocations: [invocation],
    };
    const validated = validateRunnerArtifact(artifact);
    expect(validated).not.toBeNull();
    expect(validated!.invocations[0]?.runnerSelfReport).toBeNull();
    expect(validated!.invocations[0]?.fallbackFrom).toBeNull();
  });
});

describe('P14.01 — permissive parse for legacy rows', () => {
  it('parses a Phase 13-shaped row (no schemaVersion, no primaryAgent) with sensible defaults', () => {
    const legacyRow: Record<string, unknown> = {
      runnerKind: 'claude-cli',
      reviewedHeadSha: 'sha',
      outcome: 'clean',
      completedAt: '2026-05-22T00:00:00.000Z',
      terminatedReason: 'completed',
      findings: [],
      probedSurfaces: [],
      patches: [],
    };
    const artifact = { ticket: 'P14.01', invocations: [legacyRow] };
    const validated = validateRunnerArtifact(artifact);
    expect(validated).not.toBeNull();
    const row = validated!.invocations[0] as SubagentRunnerInvocation;
    // Phase-14 fields are absent on legacy rows; reader getters materialize
    // the documented defaults (`"unknown"`, `null`, `null`) without mutating
    // the stored row shape.
    expect(row.primaryAgent).toBeUndefined();
    expect(row.runnerSelfReport).toBeUndefined();
    expect(row.fallbackFrom).toBeUndefined();
    expect(getPrimaryAgent(row)).toBe('unknown');
    expect(getRunnerSelfReport(row)).toBeNull();
    expect(getFallbackFrom(row)).toBeNull();
    // schemaVersion may be 0 or absent — both signal "pre-Phase-14".
    expect(row.schemaVersion === undefined || row.schemaVersion === 0).toBe(
      true,
    );
  });

  it('tolerates an unknown future schemaVersion rather than throwing', () => {
    const futureRow: Record<string, unknown> = {
      runnerKind: 'claude-cli',
      reviewedHeadSha: 'sha',
      outcome: 'clean',
      completedAt: '2026-05-22T00:00:00.000Z',
      terminatedReason: 'completed',
      findings: [],
      probedSurfaces: [],
      patches: [],
      schemaVersion: 999,
      primaryAgent: 'mystery-agent',
      runnerSelfReport: null,
      fallbackFrom: null,
    };
    const artifact = { ticket: 'P14.01', invocations: [futureRow] };
    const validated = validateRunnerArtifact(artifact);
    expect(validated).not.toBeNull();
    expect(validated!.invocations[0]?.schemaVersion).toBe(999);
  });
});

// P14.02 helpers imported via dynamic require so the file still parses
// while they don't yet exist (red state). Once `subagent-runner.ts` exports
// them, the live functions take over and the assertions become meaningful.
const sr = await import('../subagent-runner');
const coerceCodexCliClassification = (
  sr as {
    coerceCodexCliClassification?: (input: {
      exitCode: number | null;
      stdout: string;
      stderr: string;
    }) => {
      outcome: 'clean' | 'skipped';
      terminatedReason: 'completed' | 'rate_limit';
      runnerSelfReport: string | null;
    };
  }
).coerceCodexCliClassification;
const coerceClaudeCliClassification = (
  sr as {
    coerceClaudeCliClassification?: (input: {
      exitCode: number | null;
      stdout: string;
      stderr: string;
    }) => {
      outcome: 'clean' | 'skipped';
      terminatedReason: 'completed' | 'rate_limit';
      runnerSelfReport: string | null;
    };
  }
).coerceClaudeCliClassification;
const resolveSubagentSelection = (
  sr as {
    resolveSubagentSelection?: (input: {
      flag: 'claude-cli' | 'codex-cli' | undefined;
      configField: 'claude-cli' | 'codex-cli' | undefined;
    }) => { kind: 'claude-cli' | 'codex-cli'; source: 'flag' | 'config' };
  }
).resolveSubagentSelection;
const resolvePrimaryAgent = (
  sr as {
    resolvePrimaryAgent?: (input: {
      flag: string | undefined;
      configField: string | undefined;
    }) => string;
  }
).resolvePrimaryAgent;
const runSubagentWithFallback = (
  sr as {
    runSubagentWithFallback?: (
      requested: 'claude-cli' | 'codex-cli',
      attempt: (kind: 'claude-cli' | 'codex-cli') => {
        status: 'ran' | 'unavailable' | 'timeout';
        outcome?: 'clean' | 'patched';
        terminatedReason?: string;
      },
    ) => {
      ranKind: 'claude-cli' | 'codex-cli' | 'skipped';
      fallbackFrom: 'claude-cli' | 'codex-cli' | null;
      fallbackLevel: 'preferred' | 'fallback' | 'failed_all';
      result: { status: 'ran' | 'unavailable' | 'timeout' };
      attemptedKinds: ('claude-cli' | 'codex-cli')[];
    };
  }
).runSubagentWithFallback;

describe('P14.02 — coerceCodexCliClassification', () => {
  it('trusts runnerStatus: completed even when stderr resembles rate-limit prose', () => {
    expect(coerceCodexCliClassification).toBeDefined();
    const result = coerceCodexCliClassification!({
      exitCode: 0,
      stdout: 'findings...\n\nrunnerStatus: completed\n',
      stderr: 'warning: you may have hit your rate limit on prior call\n',
    });
    expect(result.outcome).toBe('clean');
    expect(result.terminatedReason).toBe('completed');
    expect(result.runnerSelfReport).toBe('completed');
  });

  it('classifies authentic rate-limit signal (structured) as skipped/rate_limit', () => {
    expect(coerceCodexCliClassification).toBeDefined();
    const result = coerceCodexCliClassification!({
      exitCode: 7,
      stdout: '',
      stderr: '{"error":"rate_limited","retryAfter":60}\n',
    });
    expect(result.outcome).toBe('skipped');
    expect(result.terminatedReason).toBe('rate_limit');
  });

  it('ignores rate-limit tokens echoed from prompts or source code in stderr', () => {
    expect(coerceCodexCliClassification).toBeDefined();
    const result = coerceCodexCliClassification!({
      exitCode: 0,
      stdout: 'review findings\n\nrunnerStatus: completed',
      stderr:
        'prompt text: return /"(?:error|status|code|type)"\\s*:\\s*"(?:rate_limited|rate_limit_exceeded|RATE_LIMIT(?:_EXCEEDED)?)"/.test(blob);',
    });
    expect(result.outcome).toBe('clean');
    expect(result.terminatedReason).toBe('completed');
  });

  it('classifies authentic rate-limit JSON lines as skipped/rate_limit', () => {
    expect(coerceCodexCliClassification).toBeDefined();
    const result = coerceCodexCliClassification!({
      exitCode: 0,
      stdout: '',
      stderr: '{"error":"rate_limited","retryAfter":60}\n',
    });
    expect(result.outcome).toBe('skipped');
    expect(result.terminatedReason).toBe('rate_limit');
  });

  it('records runnerSelfReport: null when the trailer is absent', () => {
    expect(coerceCodexCliClassification).toBeDefined();
    const result = coerceCodexCliClassification!({
      exitCode: 0,
      stdout: 'findings without any trailer',
      stderr: '',
    });
    expect(result.runnerSelfReport).toBeNull();
  });
});

describe('P14.02 — coerceClaudeCliClassification (symmetric to codex-cli)', () => {
  it('treats stderr/stdout prose like "you have hit your rate limit" as completed/clean', () => {
    expect(coerceClaudeCliClassification).toBeDefined();
    const result = coerceClaudeCliClassification!({
      exitCode: 0,
      stdout: 'review report ...',
      stderr: 'warning: you have hit your rate limit on prior call',
    });
    expect(result.outcome).toBe('clean');
    expect(result.terminatedReason).toBe('completed');
  });

  it('classifies authentic Anthropic rate_limit_error JSON token as skipped/rate_limit', () => {
    expect(coerceClaudeCliClassification).toBeDefined();
    const result = coerceClaudeCliClassification!({
      exitCode: 0,
      stdout: '',
      stderr:
        '{"type":"error","error":{"type":"rate_limit_error","message":"Number of request tokens has exceeded your per-minute rate limit"}}',
    });
    expect(result.outcome).toBe('skipped');
    expect(result.terminatedReason).toBe('rate_limit');
  });

  it('also accepts the overloaded_error structured token', () => {
    expect(coerceClaudeCliClassification).toBeDefined();
    const result = coerceClaudeCliClassification!({
      exitCode: 0,
      stdout: '',
      stderr: '{"type":"overloaded_error"}',
    });
    expect(result.outcome).toBe('skipped');
    expect(result.terminatedReason).toBe('rate_limit');
  });
});

describe('P14.02 — resolveSubagentSelection', () => {
  it('returns the flag value (source=flag) when provided', () => {
    expect(resolveSubagentSelection).toBeDefined();
    expect(
      resolveSubagentSelection!({ flag: 'codex-cli', configField: undefined }),
    ).toEqual({ kind: 'codex-cli', source: 'flag' });
  });

  it('falls back to the config field (source=config) when flag missing', () => {
    expect(resolveSubagentSelection).toBeDefined();
    expect(
      resolveSubagentSelection!({ flag: undefined, configField: 'claude-cli' }),
    ).toEqual({ kind: 'claude-cli', source: 'config' });
  });

  it('throws when both flag and config field are absent, naming both resolutions', () => {
    expect(resolveSubagentSelection).toBeDefined();
    let caught: Error | null = null;
    try {
      resolveSubagentSelection!({ flag: undefined, configField: undefined });
    } catch (err) {
      caught = err as Error;
    }
    expect(caught).not.toBeNull();
    expect(caught!.message).toMatch(/--subagent/);
    expect(caught!.message).toMatch(/subagentRunner/);
  });

  it('flag wins over config when both are set', () => {
    expect(resolveSubagentSelection).toBeDefined();
    expect(
      resolveSubagentSelection!({
        flag: 'codex-cli',
        configField: 'claude-cli',
      }),
    ).toEqual({ kind: 'codex-cli', source: 'flag' });
  });
});

describe('P14.02 — resolvePrimaryAgent', () => {
  it('returns the flag value (free-form passthrough)', () => {
    expect(resolvePrimaryAgent).toBeDefined();
    expect(
      resolvePrimaryAgent!({ flag: 'cursor', configField: undefined }),
    ).toBe('cursor');
  });

  it('falls back to the config field', () => {
    expect(resolvePrimaryAgent).toBeDefined();
    expect(
      resolvePrimaryAgent!({ flag: undefined, configField: 'composer' }),
    ).toBe('composer');
  });

  it('returns "unknown" when neither flag nor config is set', () => {
    expect(resolvePrimaryAgent).toBeDefined();
    expect(
      resolvePrimaryAgent!({ flag: undefined, configField: undefined }),
    ).toBe('unknown');
  });

  it('accepts arbitrary free-form values without validation', () => {
    expect(resolvePrimaryAgent).toBeDefined();
    for (const v of ['aider', 'copilot', 'composer', 'mystery-agent']) {
      expect(resolvePrimaryAgent!({ flag: v, configField: undefined })).toBe(v);
    }
  });
});

describe('P14.02 — runSubagentWithFallback', () => {
  const ran = (outcome: 'clean' | 'patched' = 'clean') => ({
    status: 'ran' as const,
    outcome,
    terminatedReason: 'completed' as const,
  });
  const unavailable = { status: 'unavailable' as const };

  it('uses the requested runner with no fallbackFrom when it succeeds', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const calls: string[] = [];
    const result = runSubagentWithFallback!('codex-cli', (kind) => {
      calls.push(kind);
      return ran();
    });
    expect(result.ranKind).toBe('codex-cli');
    expect(result.fallbackFrom).toBeNull();
    expect(result.fallbackLevel).toBe('preferred');
    expect(calls).toEqual(['codex-cli']);
  });

  it('falls back to the other runner and records fallbackFrom', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const calls: string[] = [];
    const result = runSubagentWithFallback!('codex-cli', (kind) => {
      calls.push(kind);
      return kind === 'codex-cli' ? unavailable : ran();
    });
    expect(result.ranKind).toBe('claude-cli');
    expect(result.fallbackFrom).toBe('codex-cli');
    expect(result.fallbackLevel).toBe('fallback');
    expect(calls).toEqual(['codex-cli', 'claude-cli']);
  });

  it('records failed_all and preserves the originally-requested kind when both unavailable', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const result = runSubagentWithFallback!('codex-cli', () => unavailable);
    expect(result.fallbackLevel).toBe('failed_all');
    expect(result.fallbackFrom).toBe('codex-cli');
    expect(result.result.status).toBe('unavailable');
  });
});

describe('P14.05 — stderr trace discipline', () => {
  it('writes the model report without stderr admixture', () => {
    const repoRoot = mkdtempSync(join(tmpdir(), 'soa-p14-05-report-'));
    try {
      const stdout = 'Final report\n\nrunnerStatus: completed';
      const stderr = Array.from(
        { length: 1001 },
        (_, index) => `stderr noise ${index + 1}`,
      ).join('\n');

      const written = writeSubagentReviewOutcome({
        repoRoot,
        reviewsDirPath: 'docs/product/delivery/phase-14/reviews',
        ticketId: 'P14.05',
        stdout,
        stderr,
      });

      expect(readFileSync(written.absolutePath, 'utf-8')).toBe(`${stdout}\n`);
    } finally {
      rmSync(repoRoot, { recursive: true, force: true });
    }
  });

  it('writes stderr to a sibling trace log', () => {
    const repoRoot = mkdtempSync(join(tmpdir(), 'soa-p14-05-trace-'));
    try {
      const stdout = 'Final report\n\nrunnerStatus: completed';
      const stderr = 'hook output\nconfig dump\n';

      writeSubagentReviewOutcome({
        repoRoot,
        reviewsDirPath: 'docs/product/delivery/phase-14/reviews',
        ticketId: 'P14.05',
        stdout,
        stderr,
      });

      const tracePath = join(
        repoRoot,
        'docs/product/delivery/phase-14/reviews/P14.05-subagent-review.trace.log',
      );
      expect(readFileSync(tracePath, 'utf-8')).toBe(stderr);
    } finally {
      rmSync(repoRoot, { recursive: true, force: true });
    }
  });

  it('keeps subagent trace logs out of git by default', () => {
    const gitignore = readFileSync(
      join(import.meta.dir, '../../../.gitignore'),
      {
        encoding: 'utf-8',
      },
    );

    expect(gitignore).toContain('*-subagent-review.trace.log');
  });
});
