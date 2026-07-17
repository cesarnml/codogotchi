import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { describe, expect, it } from 'bun:test';

import {
  buildRunnerInvocation,
  buildRunnerSpawnCommand,
  getFallbackFrom,
  getPrimaryAgent,
  getRunnerSelfReport,
  resolveRunnerOptions,
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
const coerceCursorCliClassification = (
  sr as {
    coerceCursorCliClassification?: (input: {
      exitCode: number | null;
      stdout: string;
      stderr: string;
    }) => {
      outcome: 'clean' | 'skipped';
      terminatedReason: 'completed' | 'rate_limit' | 'runner_failed';
      runnerSelfReport: string | null;
    };
  }
).coerceCursorCliClassification;
const buildSubagentFallbackOrder = (
  sr as {
    buildSubagentFallbackOrder?: (
      requested: 'claude-cli' | 'codex-cli' | 'cursor-cli',
    ) => ('claude-cli' | 'codex-cli' | 'cursor-cli')[];
  }
).buildSubagentFallbackOrder;
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
  it('trusts runnerStatus: completed inside the <runner-termination> tag even when stderr resembles rate-limit prose', () => {
    expect(coerceCodexCliClassification).toBeDefined();
    const result = coerceCodexCliClassification!({
      exitCode: 0,
      stdout:
        'findings...\n\n<runner-termination>\nrunnerStatus: completed\n</runner-termination>\n',
      stderr: 'warning: you may have hit your rate limit on prior call\n',
    });
    expect(result.outcome).toBe('clean');
    expect(result.terminatedReason).toBe('completed');
    expect(result.runnerSelfReport).toBe('completed');
  });

  it('P21.01 — ignores a bare runnerStatus: line outside the <runner-termination> tag (no leak)', () => {
    expect(coerceCodexCliClassification).toBeDefined();
    const result = coerceCodexCliClassification!({
      exitCode: 0,
      stdout: 'findings...\n\nrunnerStatus: completed\n',
      stderr: '',
    });
    // The bare trailer is no longer trusted (no tag), so runnerSelfReport is
    // null — but the coercer still falls through to exitCode===0 + non-empty
    // stdout, so outcome/terminatedReason are unaffected.
    expect(result.runnerSelfReport).toBeNull();
    expect(result.outcome).toBe('clean');
    expect(result.terminatedReason).toBe('completed');
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

  it('P21.01 — trusts runnerStatus: completed inside the <runner-termination> tag', () => {
    expect(coerceClaudeCliClassification).toBeDefined();
    const result = coerceClaudeCliClassification!({
      exitCode: 0,
      stdout:
        'review report ...\n\n<runner-termination>\nrunnerStatus: completed\nterminatedReason: finished the review\n</runner-termination>\n',
      stderr: '',
    });
    expect(result.outcome).toBe('clean');
    expect(result.terminatedReason).toBe('completed');
    expect(result.runnerSelfReport).toBe('completed');
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

describe('cursor-cli — coerceCursorCliClassification', () => {
  it('trusts runnerStatus: completed inside the <runner-termination> tag when stdout is a full review', () => {
    expect(coerceCursorCliClassification).toBeDefined();
    const result = coerceCursorCliClassification!({
      exitCode: 0,
      stdout:
        '<actionable-findings>\nNone\n</actionable-findings>\n\n<runner-termination>\nrunnerStatus: completed\n</runner-termination>\n',
      stderr: '',
    });
    expect(result.outcome).toBe('clean');
    expect(result.terminatedReason).toBe('completed');
    expect(result.runnerSelfReport).toBe('completed');
  });

  it('classifies Cursor billing "out of usage" stdout as rate_limit', () => {
    expect(coerceCursorCliClassification).toBeDefined();
    const result = coerceCursorCliClassification!({
      exitCode: 1,
      stdout:
        "You're out of usage. Switch to Auto, or ask your admin to increase your limit to continue.",
      stderr: '',
    });
    expect(result.outcome).toBe('skipped');
    expect(result.terminatedReason).toBe('rate_limit');
  });

  it('does not treat review prose mentioning rate limits as rate_limit', () => {
    expect(coerceCursorCliClassification).toBeDefined();
    const result = coerceCursorCliClassification!({
      exitCode: 0,
      stdout:
        'Finding: preserves existing rate limit retry behavior.\n\n<runner-termination>\nrunnerStatus: completed\n</runner-termination>',
      stderr: '',
    });
    expect(result.outcome).toBe('clean');
    expect(result.terminatedReason).toBe('completed');
  });
});

describe('cursor-cli — buildSubagentFallbackOrder', () => {
  it('tries the requested runner first, then the other programmatic runners', () => {
    expect(buildSubagentFallbackOrder).toBeDefined();
    expect(buildSubagentFallbackOrder!('cursor-cli')).toEqual([
      'cursor-cli',
      'claude-cli',
      'codex-cli',
    ]);
  });
});

describe('P14.02 — resolveSubagentSelection', () => {
  it('returns the flag value (source=flag) when provided', () => {
    expect(resolveSubagentSelection).toBeDefined();
    expect(
      resolveSubagentSelection!({ flag: 'codex-cli', configField: undefined }),
    ).toEqual({ kind: 'codex-cli', source: 'flag' });
  });

  it('accepts cursor-cli as a strict enum value', () => {
    expect(resolveSubagentSelection).toBeDefined();
    expect(
      resolveSubagentSelection!({
        flag: 'cursor-cli',
        configField: undefined,
      }),
    ).toEqual({ kind: 'cursor-cli', source: 'flag' });
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

  it('records failed_all and preserves the originally-requested kind when all unavailable', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const calls: string[] = [];
    const result = runSubagentWithFallback!('codex-cli', (kind) => {
      calls.push(kind);
      return unavailable;
    });
    expect(result.fallbackLevel).toBe('failed_all');
    expect(result.fallbackFrom).toBe('codex-cli');
    expect(result.result.status).toBe('unavailable');
    expect(calls).toEqual(['codex-cli', 'claude-cli', 'cursor-cli']);
  });

  it('falls back through claude-cli to cursor-cli when codex-cli is unavailable', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const calls: string[] = [];
    const result = runSubagentWithFallback!('codex-cli', (kind) => {
      calls.push(kind);
      return kind === 'cursor-cli' ? ran() : unavailable;
    });
    expect(result.ranKind).toBe('cursor-cli');
    expect(result.fallbackFrom).toBe('codex-cli');
    expect(calls).toEqual(['codex-cli', 'claude-cli', 'cursor-cli']);
  });
});

describe('P21.03 — fallback advances on ran-but-failed runners', () => {
  const ranWith = (
    terminatedReason:
      | 'completed'
      | 'runner_failed'
      | 'rate_limit'
      | 'sandbox_denied'
      | 'advisory_violation',
  ) => ({
    status: 'ran' as const,
    outcome: 'clean' as const,
    terminatedReason,
  });

  it('advances to the next runner when codex-cli spawns but returns runner_failed (issue #105 repro)', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const calls: string[] = [];
    const result = runSubagentWithFallback!('codex-cli', (kind) => {
      calls.push(kind);
      return kind === 'codex-cli'
        ? ranWith('runner_failed')
        : ranWith('completed');
    });
    expect(result.ranKind).toBe('claude-cli');
    expect(result.fallbackFrom).toBe('codex-cli');
    expect(result.fallbackLevel).toBe('fallback');
    expect(calls).toEqual(['codex-cli', 'claude-cli']);
  });

  it('advances to the next runner when the requested runner returns ran + rate_limit', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const calls: string[] = [];
    const result = runSubagentWithFallback!('codex-cli', (kind) => {
      calls.push(kind);
      return kind === 'codex-cli'
        ? ranWith('rate_limit')
        : ranWith('completed');
    });
    expect(result.ranKind).toBe('claude-cli');
    expect(result.fallbackFrom).toBe('codex-cli');
    expect(calls).toEqual(['codex-cli', 'claude-cli']);
  });

  it('advances to the next runner when the requested runner returns ran + sandbox_denied', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const calls: string[] = [];
    const result = runSubagentWithFallback!('codex-cli', (kind) => {
      calls.push(kind);
      return kind === 'codex-cli'
        ? ranWith('sandbox_denied')
        : ranWith('completed');
    });
    expect(result.ranKind).toBe('claude-cli');
    expect(result.fallbackFrom).toBe('codex-cli');
    expect(calls).toEqual(['codex-cli', 'claude-cli']);
  });

  it('does not advance on ran + advisory_violation — preserves the violation row', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const calls: string[] = [];
    const result = runSubagentWithFallback!('codex-cli', (kind) => {
      calls.push(kind);
      return ranWith('advisory_violation');
    });
    expect(result.ranKind).toBe('codex-cli');
    expect(result.fallbackFrom).toBeNull();
    expect(result.fallbackLevel).toBe('preferred');
    expect(result.result).toEqual(ranWith('advisory_violation'));
    expect(calls).toEqual(['codex-cli']);
  });

  it('records failed_all with the full attempted chain when every runner fails with a ran-but-failed reason', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const calls: string[] = [];
    const result = runSubagentWithFallback!('codex-cli', (kind) => {
      calls.push(kind);
      return ranWith('runner_failed');
    });
    expect(result.ranKind).toBe('skipped');
    expect(result.fallbackLevel).toBe('failed_all');
    expect(result.fallbackFrom).toBe('codex-cli');
    expect(result.attemptedKinds).toEqual([
      'codex-cli',
      'claude-cli',
      'cursor-cli',
    ]);
    expect(calls).toEqual(['codex-cli', 'claude-cli', 'cursor-cli']);
  });

  it('does not advance when the first attempt wrote files even though it also classified as runner_failed — a write violation must not be masked by a later successful fallback', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const calls: string[] = [];
    const result = runSubagentWithFallback!('codex-cli', (kind) => {
      calls.push(kind);
      return kind === 'codex-cli'
        ? {
            status: 'ran' as const,
            outcome: 'patched' as const,
            terminatedReason: 'runner_failed' as const,
          }
        : ranWith('completed');
    });
    expect(result.ranKind).toBe('codex-cli');
    expect(result.fallbackFrom).toBeNull();
    expect(result.fallbackLevel).toBe('preferred');
    expect(calls).toEqual(['codex-cli']);
  });

  it('a genuinely completed ran result still returns immediately with no fallback', () => {
    expect(runSubagentWithFallback).toBeDefined();
    const calls: string[] = [];
    const result = runSubagentWithFallback!('codex-cli', (kind) => {
      calls.push(kind);
      return ranWith('completed');
    });
    expect(result.ranKind).toBe('codex-cli');
    expect(result.fallbackFrom).toBeNull();
    expect(result.fallbackLevel).toBe('preferred');
    expect(calls).toEqual(['codex-cli']);
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

describe('P21.04 — resolveRunnerOptions precedence', () => {
  it('flag beats config beats default for the requested runner', () => {
    const flagWins = resolveRunnerOptions({
      runner: 'codex-cli',
      requestedRunner: 'codex-cli',
      flagModel: 'flag-model',
      configOptions: { 'codex-cli': { model: 'config-model' } },
    });
    expect(flagWins).toEqual({ model: 'flag-model' });

    const configWins = resolveRunnerOptions({
      runner: 'codex-cli',
      requestedRunner: 'codex-cli',
      configOptions: { 'codex-cli': { model: 'config-model' } },
    });
    expect(configWins).toEqual({ model: 'config-model' });

    const defaultWins = resolveRunnerOptions({
      runner: 'codex-cli',
      requestedRunner: 'codex-cli',
    });
    expect(defaultWins).toEqual({});
  });

  it('does not apply the flag to a fallback runner — fallback resolves from config alone', () => {
    const fallbackAttempt = resolveRunnerOptions({
      runner: 'claude-cli',
      requestedRunner: 'codex-cli',
      flagModel: 'flag-model-for-codex',
      flagEffort: 'high',
      configOptions: { 'claude-cli': { model: 'claude-config-model' } },
    });
    expect(fallbackAttempt).toEqual({ model: 'claude-config-model' });
  });

  it('resolves model and effort independently for claude-cli', () => {
    const resolved = resolveRunnerOptions({
      runner: 'claude-cli',
      requestedRunner: 'claude-cli',
      flagModel: 'claude-opus-4-8',
      flagEffort: 'high',
    });
    expect(resolved).toEqual({ model: 'claude-opus-4-8', effort: 'high' });
  });

  it('throws fail-fast when an effort value is resolved for cursor-cli', () => {
    expect(() =>
      resolveRunnerOptions({
        runner: 'cursor-cli',
        requestedRunner: 'cursor-cli',
        flagEffort: 'high',
      }),
    ).toThrow(/cursor-cli has no effort flag/);
  });

  it('throws fail-fast when a config entry sets effort on cursor-cli via a fallback attempt', () => {
    expect(() =>
      resolveRunnerOptions({
        runner: 'cursor-cli',
        requestedRunner: 'codex-cli',
        configOptions: { 'cursor-cli': { effort: 'high' } },
      }),
    ).toThrow(/cursor-cli has no effort flag/);
  });
});

describe('P21.04 — buildRunnerSpawnCommand forwards model/effort per platform', () => {
  it('claude-cli: forwards --model and --effort', () => {
    const { bin, args } = buildRunnerSpawnCommand('claude-cli', 'prompt', {
      model: 'claude-opus-4-8',
      effort: 'high',
    });
    expect(bin).toBe('claude');
    expect(args).toContain('--model');
    expect(args[args.indexOf('--model') + 1]).toBe('claude-opus-4-8');
    expect(args).toContain('--effort');
    expect(args[args.indexOf('--effort') + 1]).toBe('high');
    expect(args).toContain('prompt');
  });

  it('claude-cli: omits flags entirely when model/effort are unresolved', () => {
    const { args } = buildRunnerSpawnCommand('claude-cli', 'prompt');
    expect(args).toEqual(['-p', 'prompt']);
  });

  it('codex-cli: forwards -m for model and -c model_reasoning_effort=<e> for effort', () => {
    const { bin, args } = buildRunnerSpawnCommand('codex-cli', 'prompt', {
      model: 'gpt-5-codex',
      effort: 'high',
    });
    expect(bin).toBe('codex');
    expect(args).toContain('-m');
    expect(args[args.indexOf('-m') + 1]).toBe('gpt-5-codex');
    expect(args).toContain('-c');
    expect(args[args.indexOf('-c') + 1]).toBe('model_reasoning_effort=high');
  });

  it('cursor-cli: forwards --model, has no effort flag to forward', () => {
    const { bin, args } = buildRunnerSpawnCommand('cursor-cli', 'prompt', {
      model: 'composer-1',
      workspacePath: '/tmp/worktree',
    });
    expect(bin).toBe('agent');
    expect(args).toContain('--model');
    expect(args[args.indexOf('--model') + 1]).toBe('composer-1');
    expect(args).not.toContain('--effort');
  });
});

describe('P21.04 — ledger fidelity for runnerModel/runnerEffort', () => {
  it('records runnerModel/runnerEffort for an overridden run', () => {
    const invocation = buildRunnerInvocation('claude-cli', 'sha', 'clean', {
      runnerModel: 'claude-opus-4-8',
      runnerEffort: 'high',
    });
    expect(invocation.runnerModel).toBe('claude-opus-4-8');
    expect(invocation.runnerEffort).toBe('high');

    const artifact: SubagentRunnerArtifact = {
      ticket: 'P21.04',
      invocations: [invocation],
    };
    const validated = validateRunnerArtifact(artifact);
    expect(validated?.invocations[0]?.runnerModel).toBe('claude-opus-4-8');
    expect(validated?.invocations[0]?.runnerEffort).toBe('high');
  });

  it('omits runnerModel/runnerEffort when buildRunnerInvocation options are omitted', () => {
    const invocation = buildRunnerInvocation('claude-cli', 'sha', 'clean');
    expect(invocation.runnerModel).toBeUndefined();
    expect(invocation.runnerEffort).toBeUndefined();
  });

  it('round-trips explicit null runnerModel/runnerEffort for a default run — the production ledger-row shape recorded by the subagent-review CLI (resolvedOptions.model/.effort ?? null)', () => {
    const invocation = buildRunnerInvocation('claude-cli', 'sha', 'clean', {
      runnerModel: null,
      runnerEffort: null,
    });
    expect(invocation.runnerModel).toBeNull();
    expect(invocation.runnerEffort).toBeNull();

    const artifact: SubagentRunnerArtifact = {
      ticket: 'P21.04',
      invocations: [invocation],
    };
    const validated = validateRunnerArtifact(artifact);
    expect(validated?.invocations[0]?.runnerModel).toBeNull();
    expect(validated?.invocations[0]?.runnerEffort).toBeNull();
  });
});
