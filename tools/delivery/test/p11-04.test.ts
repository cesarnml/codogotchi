import { describe, expect, it } from 'bun:test';

import {
  decideSubagentOutcomeFromRunner,
  shouldFallbackToOtherRunner,
  tryRunner,
  type RunnerAttemptResult,
  type SpawnResult,
} from '../subagent-runner';

// P11.04 — termination honesty for subagent-review.
//
// Four ticket-Red invariants:
//   1. Outcome detection (porcelain sample) is strictly post-exit.
//   2. A runner result with terminatedReason !== 'completed' cannot be recorded as 'clean'.
//   3. Ambiguous runner output (e.g., rate-limit signature in stdout, exit 0)
//      does NOT trigger auto-fallback to the other runner.
//   4. A binary-availability failure (spawn ENOENT) DOES trigger auto-fallback.

describe('P11.04 — porcelain sample is strictly post-exit', () => {
  it('invokes checkHasChanges only after spawnProcess returns', () => {
    let exited = false;
    let sampledAfterExit: boolean | null = null;

    const spawnProcess = (): SpawnResult => {
      exited = true;
      return { exitCode: 0, timedOut: false };
    };
    const checkHasChanges = () => {
      sampledAfterExit = exited;
      return true;
    };

    const result = tryRunner(spawnProcess, checkHasChanges);
    expect(sampledAfterExit).toBe(true);
    expect(result.status).toBe('ran');
    if (result.status === 'ran') {
      expect(result.outcome).toBe('patched');
    }
  });

  it('reflects post-exit porcelain state when runner writes files after the old sample point', () => {
    // Simulates a runner that finishes its writes only at exit. The "old" buggy
    // sample point read porcelain before exit and saw clean. The fix requires
    // sampling after exit, so the recorded outcome is 'patched'.
    let runnerFinishedWriting = false;
    const spawnProcess = (): SpawnResult => {
      runnerFinishedWriting = true;
      return { exitCode: 0, timedOut: false };
    };
    const checkHasChanges = () => runnerFinishedWriting;

    const result = tryRunner(spawnProcess, checkHasChanges);
    expect(result).toEqual({
      status: 'ran',
      outcome: 'patched',
      terminatedReason: 'completed',
    });
  });
});

describe('P11.04 — honesty guard: terminatedReason !== completed cannot record clean', () => {
  it('refuses outcome=clean when terminatedReason is rate_limit', () => {
    const result: RunnerAttemptResult = {
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'rate_limit',
    };
    const decided = decideSubagentOutcomeFromRunner(result);
    expect(decided.outcome).not.toBe('clean');
    expect(decided.terminatedReason).toBe('rate_limit');
  });

  it('refuses outcome=clean when terminatedReason is sandbox_denied', () => {
    const result: RunnerAttemptResult = {
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'sandbox_denied',
    };
    const decided = decideSubagentOutcomeFromRunner(result);
    expect(decided.outcome).not.toBe('clean');
    expect(decided.terminatedReason).toBe('sandbox_denied');
  });

  it('keeps outcome=clean when terminatedReason is completed', () => {
    const result: RunnerAttemptResult = {
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'completed',
    };
    expect(decideSubagentOutcomeFromRunner(result)).toEqual({
      outcome: 'clean',
      terminatedReason: 'completed',
    });
  });

  it('keeps outcome=patched even when terminatedReason is not completed', () => {
    // patched implies the runner actually wrote real fixes; we keep the outcome
    // but still surface the non-completed termination reason honestly.
    const result: RunnerAttemptResult = {
      status: 'ran',
      outcome: 'patched',
      terminatedReason: 'rate_limit',
    };
    const decided = decideSubagentOutcomeFromRunner(result);
    expect(decided.outcome).toBe('patched');
    expect(decided.terminatedReason).toBe('rate_limit');
  });
});

describe('P11.04 — auto-fallback predicate is narrowed to binary-availability failures', () => {
  it('does NOT fall back on ambiguous ran-with-rate-limit output', () => {
    const result: RunnerAttemptResult = {
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'rate_limit',
    };
    expect(shouldFallbackToOtherRunner(result)).toBe(false);
  });

  it('does NOT fall back on ambiguous ran-with-sandbox-denied output', () => {
    const result: RunnerAttemptResult = {
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'sandbox_denied',
    };
    expect(shouldFallbackToOtherRunner(result)).toBe(false);
  });

  it('does NOT fall back on a clean completed run', () => {
    const result: RunnerAttemptResult = {
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'completed',
    };
    expect(shouldFallbackToOtherRunner(result)).toBe(false);
  });

  it('falls back when the preferred runner binary is unavailable', () => {
    expect(shouldFallbackToOtherRunner({ status: 'unavailable' })).toBe(true);
  });

  it('falls back when the preferred runner times out', () => {
    expect(shouldFallbackToOtherRunner({ status: 'timeout' })).toBe(true);
  });
});

describe('P11.04 — tryRunner propagates terminatedReason from SpawnResult', () => {
  it('returns ran with terminatedReason=rate_limit when spawn flags it', () => {
    const spawnProcess = (): SpawnResult => ({
      exitCode: 0,
      timedOut: false,
      terminatedReason: 'rate_limit',
    });
    const result = tryRunner(spawnProcess, () => false);
    expect(result).toEqual({
      status: 'ran',
      outcome: 'clean',
      terminatedReason: 'rate_limit',
    });
  });

  it('defaults terminatedReason to completed when spawnProcess does not specify one', () => {
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

  it('returns unavailable when the binary is missing from PATH', () => {
    const result = tryRunner(
      () => {
        throw new Error('spawn claude ENOENT');
      },
      () => false,
    );
    expect(result).toEqual({ status: 'unavailable' });
  });
});
