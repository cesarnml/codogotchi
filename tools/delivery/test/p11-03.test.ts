import { describe, expect, it } from 'bun:test';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  appendInvocationToArtifact,
  buildRunnerInvocation,
  decideSubagentReviewMode,
  parseSubagentReviewArgs,
  readSubagentRunnerArtifact,
} from '../subagent-runner';
import type {
  SubagentRunnerArtifact,
  SubagentRunnerInvocation,
} from '../subagent-runner';

describe('P11.03 — parseSubagentReviewArgs', () => {
  it('parses recorder positional args with explicit ticket id', () => {
    const parsed = parseSubagentReviewArgs(
      ['P11.03', 'clean', 'abc123'],
      new Set(),
    );
    expect(parsed.ticketId).toBe('P11.03');
    expect(parsed.outcome).toBe('clean');
    expect(parsed.reviewedHeadSha).toBe('abc123');
    expect(parsed.force).toBe(false);
  });

  it('parses recorder positional args without ticket id', () => {
    const parsed = parseSubagentReviewArgs(['patched', 'abc123'], new Set());
    expect(parsed.ticketId).toBeUndefined();
    expect(parsed.outcome).toBe('patched');
    expect(parsed.reviewedHeadSha).toBe('abc123');
  });

  it('throws when outcome is supplied without a SHA', () => {
    expect(() => parseSubagentReviewArgs(['clean'], new Set())).toThrow(/SHA/);
    expect(() =>
      parseSubagentReviewArgs(['P11.03', 'patched'], new Set()),
    ).toThrow(/SHA/);
  });

  it('honors --force flag', () => {
    const parsed = parseSubagentReviewArgs(['P11.03'], new Set(['force']));
    expect(parsed.force).toBe(true);
    expect(parsed.outcome).toBeUndefined();
  });

  it('keeps bare ticket id for auto-runner mode', () => {
    const parsed = parseSubagentReviewArgs(['P11.03'], new Set());
    expect(parsed.ticketId).toBe('P11.03');
    expect(parsed.outcome).toBeUndefined();
    expect(parsed.reviewedHeadSha).toBeUndefined();
  });

  it('rejects trailing positionals after ticket id when no outcome word is present', () => {
    // Guards against operator typos like `subagent-review P11.03 clear abc` —
    // without this, `clear` would be silently treated as a ticket id and `abc`
    // would be discarded, falling through to runner mode.
    expect(() => parseSubagentReviewArgs(['P11.03', 'abc'], new Set())).toThrow(
      /Unexpected positional/,
    );
  });

  it('rejects patch-commit trailing positionals when outcome is clean', () => {
    expect(() =>
      parseSubagentReviewArgs(
        ['P11.03', 'clean', 'abc123', 'patch1'],
        new Set(),
      ),
    ).toThrow(/only allowed when outcome is `patched`/);
  });

  it('accepts patch-commit trailing positionals when outcome is patched', () => {
    const parsed = parseSubagentReviewArgs(
      ['P11.03', 'patched', 'abc123', 'patch1', 'patch2'],
      new Set(),
    );
    expect(parsed.outcome).toBe('patched');
    expect(parsed.reviewedHeadSha).toBe('abc123');
    expect(parsed.patchCommitArgs).toEqual(['patch1', 'patch2']);
  });
});

describe('P11.03 — decideSubagentReviewMode dispatch (recorder, no-op, invoke-runner)', () => {
  function buildInv(
    overrides: Partial<SubagentRunnerInvocation> = {},
  ): SubagentRunnerInvocation {
    return {
      runnerKind: 'claude-cli',
      reviewedHeadSha: 'sha-head',
      outcome: 'clean',
      completedAt: '2026-05-19T00:00:00.000Z',
      terminatedReason: 'completed',
      findings: [],
      probedSurfaces: [],
      patches: [],
      ...overrides,
    };
  }

  it('chooses recorder mode when outcome + sha are supplied (no runner invocation)', () => {
    const decision = decideSubagentReviewMode(
      { outcome: 'clean', reviewedHeadSha: 'abc123', force: false },
      null,
      'unrelated-head',
    );
    expect(decision.kind).toBe('recorder');
    if (decision.kind === 'recorder') {
      expect(decision.reviewedHeadSha).toBe('abc123');
      expect(decision.outcome).toBe('clean');
    }
  });

  it('returns no-op when artifact already has a matching HEAD invocation and --force is absent', () => {
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P11.03',
      invocations: [buildInv({ reviewedHeadSha: 'sha-head' })],
    };
    const decision = decideSubagentReviewMode(
      { force: false },
      artifact,
      'sha-head',
    );
    expect(decision.kind).toBe('no-op');
  });

  it('returns invoke-runner when artifact has no invocation matching current HEAD', () => {
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P11.03',
      invocations: [buildInv({ reviewedHeadSha: 'old-head' })],
    };
    const decision = decideSubagentReviewMode(
      { force: false },
      artifact,
      'sha-head',
    );
    expect(decision.kind).toBe('invoke-runner');
  });

  it('--force always returns invoke-runner regardless of artifact match', () => {
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P11.03',
      invocations: [buildInv({ reviewedHeadSha: 'sha-head' })],
    };
    const decision = decideSubagentReviewMode(
      { force: true },
      artifact,
      'sha-head',
    );
    expect(decision.kind).toBe('invoke-runner');
  });

  it('skipped invocations do not count as matching HEAD invocations', () => {
    const artifact: SubagentRunnerArtifact = {
      ticket: 'P11.03',
      invocations: [
        buildInv({
          reviewedHeadSha: 'sha-head',
          outcome: 'skipped',
          runnerKind: 'skipped',
          terminatedReason: 'runner_unavailable',
        }),
      ],
    };
    const decision = decideSubagentReviewMode(
      { force: false },
      artifact,
      'sha-head',
    );
    expect(decision.kind).toBe('invoke-runner');
  });
});

describe('P11.03 — operator-recorder invocation writes through buildRunnerInvocation + appendInvocationToArtifact', () => {
  it('writes a single recorder-mode invocation with the supplied SHA and outcome', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p11-03-recorder-'));
    try {
      const path = join(tempDir, 'P11.03-subagent-review.ledger.json');
      const invocation = buildRunnerInvocation(
        'operator-recorder',
        'abc123',
        'clean',
      );
      appendInvocationToArtifact(path, 'P11.03', invocation);

      const persisted = JSON.parse(
        await readFile(path, 'utf-8'),
      ) as SubagentRunnerArtifact;
      expect(persisted.ticket).toBe('P11.03');
      expect(persisted.invocations.length).toBe(1);
      const inv = persisted.invocations[0]!;
      expect(inv.runnerKind).toBe('operator-recorder');
      expect(inv.reviewedHeadSha).toBe('abc123');
      expect(inv.outcome).toBe('clean');
      expect(inv.terminatedReason).toBe('completed');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('round-trips the operator-recorder runnerKind through readSubagentRunnerArtifact', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p11-03-recorder-rt-'));
    try {
      const path = join(tempDir, 'P11.03-subagent-review.ledger.json');
      await writeFile(
        path,
        JSON.stringify({
          ticket: 'P11.03',
          invocations: [
            {
              runnerKind: 'operator-recorder',
              reviewedHeadSha: 'abc123',
              outcome: 'patched',
              completedAt: '2026-05-19T00:00:00.000Z',
              terminatedReason: 'completed',
              findings: [],
              probedSurfaces: [],
              patches: ['cafef00'],
            },
          ],
        }),
      );
      const artifact = readSubagentRunnerArtifact(path, 'P11.03');
      expect(artifact.invocations[0]!.runnerKind).toBe('operator-recorder');
      expect(artifact.invocations[0]!.patches).toEqual(['cafef00']);
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });
});
