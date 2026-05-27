import { describe, expect, it } from 'bun:test';

import {
  buildRunnerInvocation,
  buildRunnerSpawnCommand,
  classifyRunnerTermination,
  decideSubagentOutcomeFromRunner,
  validateRunnerArtifact,
} from '../subagent-runner';
import type {
  RunnerAttemptResult,
  SubagentRunnerArtifact,
} from '../subagent-runner';

describe('P13.01 — runner spawn command shapes', () => {
  it('uses codex exec for codex-cli runner invocations', () => {
    expect(buildRunnerSpawnCommand('codex-cli', 'review prompt')).toEqual({
      bin: 'codex',
      args: ['exec', '--color', 'never', 'review prompt'],
    });
  });

  it('uses codex --output-last-message when a report path is supplied', () => {
    expect(
      buildRunnerSpawnCommand('codex-cli', 'review prompt', {
        outputLastMessagePath: '/tmp/report.md',
      }),
    ).toEqual({
      bin: 'codex',
      args: [
        'exec',
        '--output-last-message',
        '/tmp/report.md',
        '--color',
        'never',
        'review prompt',
      ],
    });
  });

  it('uses claude -p for claude-cli runner invocations', () => {
    expect(buildRunnerSpawnCommand('claude-cli', 'review prompt')).toEqual({
      bin: 'claude',
      args: ['-p', 'review prompt'],
    });
  });
});

describe('P13.01 — raw runner response artifact evidence', () => {
  it('persists rawOutput path ref and fallback metadata on invocations', () => {
    const outcomePath =
      'docs/product/delivery/phase-13/reviews/P13.01-subagent-review.report.md';
    const invocation = buildRunnerInvocation('codex-cli', 'abc123', 'clean', {
      fallbackLevel: 'preferred',
      rawOutput: outcomePath,
    });
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P13.01',
      invocations: [invocation],
    };

    expect(validateRunnerArtifact(artifact)).toEqual(artifact);
    expect(artifact.invocations[0]?.rawOutput).toBe(outcomePath);
    expect(artifact.invocations[0]?.fallbackLevel).toBe('preferred');
  });
});

describe('P13.01 — non-clean runner termination classification', () => {
  it('classifies empty exit-zero output as runner_failed', () => {
    expect(classifyRunnerTermination(0, '', '')).toBe('runner_failed');
  });

  it('classifies non-zero output as runner_failed when no narrower reason matches', () => {
    expect(classifyRunnerTermination(1, 'unexpected failure', '')).toBe(
      'runner_failed',
    );
  });

  it('classifies Claude hit-your-limit stdout as rate_limit', () => {
    expect(
      classifyRunnerTermination(
        1,
        "You've hit your limit · resets 10:30am (Asia/Bangkok)",
        '',
      ),
    ).toBe('rate_limit');
  });

  it('does not classify successful review prose mentioning rate limit as rate_limit', () => {
    expect(
      classifyRunnerTermination(
        0,
        'Finding: the implementation preserves rate limit retry behavior.',
        '',
      ),
    ).toBe('completed');
  });

  it('does not allow runner_failed to record clean', () => {
    const result: RunnerAttemptResult = {
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'runner_failed',
      rawOutput: 'unexpected failure',
    };

    expect(decideSubagentOutcomeFromRunner(result)).toEqual({
      outcome: 'skipped',
      terminatedReason: 'runner_failed',
    });
  });
});
