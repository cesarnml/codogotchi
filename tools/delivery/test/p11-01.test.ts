import { describe, expect, it } from 'bun:test';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

import {
  appendInvocationToArtifact,
  buildRunnerInvocation,
  readSubagentRunnerArtifact,
  validateRunnerArtifact,
} from '../subagent-runner';
import type {
  SubagentRunnerArtifact,
  SubagentRunnerInvocation,
} from '../subagent-runner';

const FIXTURE_DIR = resolve(
  __dirname,
  '../../../tests/fixtures/legacy-subagent-runner',
);

describe('P11.01 — readSubagentRunnerArtifact legacy adapter', () => {
  it('lifts a legacy 4-field artifact into a single-entry invocations[]', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p11-01-legacy-'));
    try {
      const legacy = {
        runnerKind: 'codex-cli',
        reviewedHeadSha: 'abc123',
        outcome: 'clean',
        completedAt: '2026-05-18T15:29:44.213Z',
      };
      const path = join(tempDir, 'P9.99-subagent-review.ledger.json');
      await writeFile(path, JSON.stringify(legacy));

      const artifact = readSubagentRunnerArtifact(path, 'P9.99');

      expect(artifact.ticket).toBe('P9.99');
      expect(artifact.invocations.length).toBe(1);
      const inv = artifact.invocations[0]!;
      expect(inv.runnerKind).toBe('codex-cli');
      expect(inv.reviewedHeadSha).toBe('abc123');
      expect(inv.outcome).toBe('clean');
      expect(inv.completedAt).toBe('2026-05-18T15:29:44.213Z');
      expect(inv.terminatedReason).toBe('completed');
      expect(inv.findings).toEqual([]);
      expect(inv.probedSurfaces).toEqual([]);
      expect(inv.patches).toEqual([]);
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('round-trips every real codogotchi phase-01 legacy fixture', () => {
    const fixtures = [
      'codogotchi-p1-01.json',
      'codogotchi-p1-18.json',
      'codogotchi-p1-20.json',
    ];
    for (const name of fixtures) {
      const path = join(FIXTURE_DIR, name);
      const legacy = JSON.parse(readFileSync(path, 'utf-8')) as Record<
        string,
        unknown
      >;
      const artifact = readSubagentRunnerArtifact(path, 'P1.XX');
      expect(artifact.invocations.length).toBe(1);
      const inv = artifact.invocations[0]!;
      expect(inv.runnerKind).toBe(legacy['runnerKind']);
      expect(inv.reviewedHeadSha).toBe(legacy['reviewedHeadSha'] as string);
      expect(inv.outcome).toBe(legacy['outcome']);
      expect(inv.completedAt).toBe(legacy['completedAt'] as string);
      expect(inv.terminatedReason).toBe('completed');
    }
  });

  it('rejects malformed legacy artifacts (missing reviewedHeadSha)', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p11-01-malformed-'));
    try {
      const path = join(tempDir, 'bad.json');
      await writeFile(
        path,
        JSON.stringify({
          runnerKind: 'codex-cli',
          outcome: 'clean',
          completedAt: '2026-05-18T15:29:44.213Z',
        }),
      );
      expect(() => readSubagentRunnerArtifact(path, 'P9.99')).toThrow(
        /reviewedHeadSha/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('reports a clear legacy field error when runnerKind is the wrong type', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p11-01-wrong-kind-'));
    try {
      const path = join(tempDir, 'bad.json');
      await writeFile(
        path,
        JSON.stringify({
          runnerKind: 123,
          reviewedHeadSha: 'abc',
          outcome: 'clean',
          completedAt: '2026-05-18T15:29:44.213Z',
        }),
      );
      expect(() => readSubagentRunnerArtifact(path, 'P9.99')).toThrow(
        /runnerKind/,
      );
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });
});

describe('P11.01 — validateRunnerArtifact rejects coerced array entries', () => {
  it('rejects an invocation whose findings array contains non-string entries', () => {
    expect(
      validateRunnerArtifact({
        ticket: 'P11.99',
        invocations: [
          {
            runnerKind: 'claude-cli',
            reviewedHeadSha: 'sha',
            outcome: 'clean',
            completedAt: '2026-05-19T00:00:00.000Z',
            terminatedReason: 'completed',
            findings: [1],
            probedSurfaces: [],
            patches: [],
          },
        ],
      }),
    ).toBeNull();
  });

  it('rejects an invocation whose probedSurfaces array contains objects', () => {
    expect(
      validateRunnerArtifact({
        ticket: 'P11.99',
        invocations: [
          {
            runnerKind: 'claude-cli',
            reviewedHeadSha: 'sha',
            outcome: 'clean',
            completedAt: '2026-05-19T00:00:00.000Z',
            terminatedReason: 'completed',
            findings: [],
            probedSurfaces: [{ a: 1 }],
            patches: [],
          },
        ],
      }),
    ).toBeNull();
  });
});

describe('P11.01 — readSubagentRunnerArtifact structured round-trip', () => {
  it('round-trips a multi-invocation structured artifact', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p11-01-structured-'));
    try {
      const invocation1: SubagentRunnerInvocation = {
        runnerKind: 'claude-cli',
        reviewedHeadSha: 'sha1',
        outcome: 'patched',
        completedAt: '2026-05-19T00:00:00.000Z',
        terminatedReason: 'completed',
        findings: ['CR-class 1: output stability across schema-version drift'],
        probedSurfaces: ['cli-flag-symmetry [probed]'],
        patches: ['abcdef0'],
      };
      const invocation2: SubagentRunnerInvocation = {
        runnerKind: 'codex-cli',
        reviewedHeadSha: 'sha2',
        outcome: 'clean',
        completedAt: '2026-05-19T01:00:00.000Z',
        terminatedReason: 'completed',
        findings: [],
        probedSurfaces: ['error-class-breadth [N/A — no catch blocks touched]'],
        patches: [],
      };
      const artifact: SubagentRunnerArtifact = {
        ticket: 'P11.99',
        invocations: [invocation1, invocation2],
      };
      const path = join(tempDir, 'P11.99-subagent-review.ledger.json');
      await writeFile(path, JSON.stringify(artifact, null, 2));

      const round = readSubagentRunnerArtifact(path, 'P11.99');
      expect(round).toEqual(artifact);
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });
});

describe('P11.01 — buildRunnerInvocation skipped-outcome terminatedReason contract', () => {
  it('defaults terminatedReason to completed for ran invocations', () => {
    const inv = buildRunnerInvocation('claude-cli', 'sha', 'clean');
    expect(inv.terminatedReason).toBe('completed');
  });

  it('requires explicit runner_unavailable for honest skipped invocations', () => {
    const inv = buildRunnerInvocation('skipped', 'sha', 'skipped', {
      terminatedReason: 'runner_unavailable',
    });
    expect(inv.terminatedReason).toBe('runner_unavailable');
  });
});

describe('P11.01 — appendInvocationToArtifact', () => {
  it('creates a new structured artifact when the path does not exist', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p11-01-create-'));
    try {
      const path = join(tempDir, 'P11.99-subagent-review.ledger.json');
      const invocation = buildRunnerInvocation(
        'claude-cli',
        'sha-new',
        'clean',
      );
      appendInvocationToArtifact(path, 'P11.99', invocation);

      const persisted = JSON.parse(
        await readFile(path, 'utf-8'),
      ) as SubagentRunnerArtifact;
      expect(persisted.ticket).toBe('P11.99');
      expect(persisted.invocations.length).toBe(1);
      expect(persisted.invocations[0]!.runnerKind).toBe('claude-cli');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('appends to an existing structured artifact (append-only)', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p11-01-append-'));
    try {
      const path = join(tempDir, 'P11.99-subagent-review.ledger.json');
      const first = buildRunnerInvocation('claude-cli', 'sha-1', 'clean');
      const second = buildRunnerInvocation('codex-cli', 'sha-2', 'patched');
      appendInvocationToArtifact(path, 'P11.99', first);
      appendInvocationToArtifact(path, 'P11.99', second);

      const persisted = JSON.parse(
        await readFile(path, 'utf-8'),
      ) as SubagentRunnerArtifact;
      expect(persisted.invocations.length).toBe(2);
      expect(persisted.invocations[0]!.reviewedHeadSha).toBe('sha-1');
      expect(persisted.invocations[1]!.reviewedHeadSha).toBe('sha-2');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });

  it('appends to a legacy 4-field artifact by lifting it first', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'p11-01-legacy-append-'));
    try {
      const path = join(tempDir, 'P11.99-subagent-review.ledger.json');
      await writeFile(
        path,
        JSON.stringify({
          runnerKind: 'codex-cli',
          reviewedHeadSha: 'sha-legacy',
          outcome: 'clean',
          completedAt: '2026-05-18T15:29:44.213Z',
        }),
      );

      const newInvocation = buildRunnerInvocation(
        'claude-cli',
        'sha-new',
        'patched',
      );
      appendInvocationToArtifact(path, 'P11.99', newInvocation);

      const persisted = JSON.parse(
        await readFile(path, 'utf-8'),
      ) as SubagentRunnerArtifact;
      expect(persisted.invocations.length).toBe(2);
      expect(persisted.invocations[0]!.reviewedHeadSha).toBe('sha-legacy');
      expect(persisted.invocations[0]!.terminatedReason).toBe('completed');
      expect(persisted.invocations[1]!.reviewedHeadSha).toBe('sha-new');
    } finally {
      await rm(tempDir, { recursive: true });
    }
  });
});
