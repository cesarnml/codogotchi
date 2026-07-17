import { describe, expect, it } from 'bun:test';

import {
  decideAdvisoryRunnerOutcome,
  decideSubagentOutcomeFromRunner,
  validateRunnerArtifact,
} from '../subagent-runner';
import type {
  RunnerAttemptResult,
  SubagentRunnerArtifact,
} from '../subagent-runner';
import { parseActionableFindings } from '../reconciliation';

function ranResult(
  overrides: Partial<Extract<RunnerAttemptResult, { status: 'ran' }>> = {},
): Extract<RunnerAttemptResult, { status: 'ran' }> {
  return {
    status: 'ran',
    outcome: 'clean',
    terminatedReason: 'completed',
    ...overrides,
  };
}

describe('P21.02 — completed_with_findings cross-check', () => {
  it('records completed_with_findings when the report lists actionable findings', () => {
    const report = [
      '<actionable-findings>',
      '- unchecked null deref in handler',
      '</actionable-findings>',
    ].join('\n');

    const decided = decideAdvisoryRunnerOutcome(ranResult(), {
      runnerWroteFiles: false,
      actionableFindings: parseActionableFindings(report),
    });

    expect(decided.outcome).toBe('completed_with_findings');
    expect(decided.terminatedReason).toBe('completed');
  });

  it('records clean when the report has literal None', () => {
    const report = [
      '<actionable-findings>',
      'None',
      '</actionable-findings>',
    ].join('\n');

    const decided = decideAdvisoryRunnerOutcome(ranResult(), {
      runnerWroteFiles: false,
      actionableFindings: parseActionableFindings(report),
    });

    expect(decided.outcome).toBe('clean');
  });

  it('records completed_with_findings for an unclosed tag that still yields bullets (parsed to EOF)', () => {
    // Found via subagent-review adversarial pass: a malformed report (missing
    // close tag) must never be misrecorded as `clean` just because `closed`
    // is false — the findings are still real and extractable.
    const report = [
      '<actionable-findings>',
      '- unchecked null deref in handler',
    ].join('\n');
    const parsed = parseActionableFindings(report);
    expect(parsed.closed).toBe(false);
    expect(parsed.findings.length).toBeGreaterThan(0);

    const decided = decideAdvisoryRunnerOutcome(ranResult(), {
      runnerWroteFiles: false,
      actionableFindings: parsed,
    });

    expect(decided.outcome).toBe('completed_with_findings');
  });

  it('collapses a non-completed termination to skipped regardless of findings', () => {
    const report = [
      '<actionable-findings>',
      '- something bad',
      '</actionable-findings>',
    ].join('\n');

    const decided = decideAdvisoryRunnerOutcome(
      ranResult({ terminatedReason: 'rate_limit' }),
      {
        runnerWroteFiles: false,
        actionableFindings: parseActionableFindings(report),
      },
    );

    expect(decided.outcome).toBe('skipped');
    expect(decided.terminatedReason).toBe('rate_limit');
  });

  it('collapses runner_failed to skipped with the original reason preserved', () => {
    const decided = decideAdvisoryRunnerOutcome(
      ranResult({ terminatedReason: 'runner_failed' }),
      { runnerWroteFiles: false },
    );

    expect(decided.outcome).toBe('skipped');
    expect(decided.terminatedReason).toBe('runner_failed');
  });

  it('still records clean when no actionableFindings info is supplied (refactor-review call site unaffected)', () => {
    const decided = decideAdvisoryRunnerOutcome(ranResult(), {
      runnerWroteFiles: false,
    });

    expect(decided.outcome).toBe('clean');
  });

  it('decideSubagentOutcomeFromRunner (deprecated recorder path) also cross-checks findings', () => {
    const report = [
      '<actionable-findings>',
      '- unchecked null deref in handler',
      '</actionable-findings>',
    ].join('\n');

    const decided = decideSubagentOutcomeFromRunner(ranResult(), {
      actionableFindings: parseActionableFindings(report),
    });

    expect(decided.outcome).toBe('completed_with_findings');
  });

  it('decideSubagentOutcomeFromRunner still records clean with no findings info supplied', () => {
    const decided = decideSubagentOutcomeFromRunner(ranResult());

    expect(decided.outcome).toBe('clean');
  });

  it('validates a v1 ledger row (no schemaVersion, pre-existing outcome) unchanged', () => {
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P21.02',
      invocations: [
        {
          runnerKind: 'codex-cli',
          reviewedHeadSha: 'abc123',
          outcome: 'clean',
          completedAt: '2026-01-01T00:00:00.000Z',
          terminatedReason: 'completed',
          findings: [],
          probedSurfaces: [],
          patches: [],
        },
      ],
    };

    const validated = validateRunnerArtifact(artifact);
    expect(validated).not.toBeNull();
    expect(validated!.invocations[0]?.outcome).toBe('clean');
    expect(validated!.invocations[0]?.schemaVersion).toBeUndefined();
  });

  it('validates a v2 ledger row with the new completed_with_findings outcome', () => {
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P21.02',
      invocations: [
        {
          runnerKind: 'codex-cli',
          reviewedHeadSha: 'def456',
          outcome: 'completed_with_findings',
          completedAt: '2026-01-01T00:00:00.000Z',
          terminatedReason: 'completed',
          schemaVersion: 2,
          findings: ['unchecked null deref in handler'],
          probedSurfaces: [],
          patches: [],
        },
      ],
    };

    const validated = validateRunnerArtifact(artifact);
    expect(validated).not.toBeNull();
    expect(validated!.invocations[0]?.outcome).toBe('completed_with_findings');
  });
});
