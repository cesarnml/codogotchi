import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import {
  mergeAdvisoryObservationTriageEntries,
  readAdvisoryObservationTriageArtifact,
  validateAdvisoryObservationTriageArtifact,
  writeAdvisoryObservationTriageArtifact,
  type AdvisoryObservationDisposition,
  type AdvisoryObservationTriageArtifact,
  type AdvisoryObservationTriageEntry,
} from '../advisory-observation-triage';

const DISPOSITIONS: AdvisoryObservationDisposition[] = [
  'patched',
  'rejected',
  'already-covered',
  'requires-human-review',
];

function entryFor(
  disposition: AdvisoryObservationDisposition,
  index: number,
): AdvisoryObservationTriageEntry {
  const base: AdvisoryObservationTriageEntry = {
    disposition,
    rationale: `Rationale for ${disposition}`,
    source: {
      reportPath: `docs/product/delivery/phase-16/reviews/P16.0${index + 1}-subagent-review.report.md`,
      ticketId: `P16.0${index + 1}`,
    },
    observation: `Observation ${index + 1}`,
  };
  if (disposition === 'patched') {
    return {
      ...base,
      patch: { commitSha: '0123456789abcdef0123456789abcdef01234567' },
    };
  }
  return base;
}

function makeArtifact(): AdvisoryObservationTriageArtifact {
  const dispositions = DISPOSITIONS.map((disposition, index) =>
    entryFor(disposition, index),
  );
  return {
    schemaVersion: 2,
    recordedAt: '2026-05-24T04:00:00.000Z',
    summary: {
      total: dispositions.length,
      patched: 1,
      rejected: 1,
      'already-covered': 1,
      'requires-human-review': 1,
    },
    dispositions,
  };
}

describe('P16.02 advisory observation triage artifact', () => {
  it('round-trips a valid artifact with all four v2 dispositions', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'p16-02-'));
    const path = join(dir, 'advisory-observation-triage.json');

    try {
      const artifact = makeArtifact();
      await writeAdvisoryObservationTriageArtifact(path, artifact);

      const raw = await readFile(path, 'utf8');
      expect(raw.endsWith('\n')).toBe(true);

      const parsed = await readAdvisoryObservationTriageArtifact(path);
      expect(parsed.schemaVersion).toBe(2);
      expect(
        parsed.dispositions.map((entry) => entry.disposition).sort(),
      ).toEqual([...DISPOSITIONS].sort());
      expect(parsed.summary.total).toBe(4);
      expect(parsed.summary.patched).toBe(1);
      expect(parsed.summary.rejected).toBe(1);
      expect(parsed.summary['already-covered']).toBe(1);
      expect(parsed.summary['requires-human-review']).toBe(1);
    } finally {
      await rm(dir, { force: true, recursive: true });
    }
  });

  it('rejects an unknown disposition', () => {
    const artifact = makeArtifact();
    const malformed = {
      ...artifact,
      dispositions: [
        {
          ...artifact.dispositions[0]!,
          disposition: 'accepted',
        },
      ],
    };

    expect(() => validateAdvisoryObservationTriageArtifact(malformed)).toThrow(
      /Invalid advisory observation disposition/,
    );
  });

  it('rejects every disposition that lacks a rationale (including patched)', () => {
    const artifact = makeArtifact();
    const malformed = {
      ...artifact,
      dispositions: [
        {
          ...artifact.dispositions[1]!,
          rationale: '',
        },
      ],
    };

    expect(() => validateAdvisoryObservationTriageArtifact(malformed)).toThrow(
      /rationale.* is required/,
    );
  });

  it('rejects patched dispositions without patch.commitSha', () => {
    const artifact = makeArtifact();
    const patchedEntry = artifact.dispositions.find(
      (entry) => entry.disposition === 'patched',
    )!;
    const { patch: _patch, ...missingPatch } = patchedEntry;
    const malformed = {
      ...artifact,
      dispositions: [missingPatch],
    };

    expect(() => validateAdvisoryObservationTriageArtifact(malformed)).toThrow(
      /patched.*requires.*patch\.commitSha/,
    );
  });

  it('accepts a patched disposition with structured patch evidence', () => {
    const artifact = makeArtifact();
    const patchedEntry = artifact.dispositions.find(
      (entry) => entry.disposition === 'patched',
    )!;
    const validated = validateAdvisoryObservationTriageArtifact({
      ...artifact,
      dispositions: [patchedEntry],
    });

    expect(validated.dispositions[0]?.disposition).toBe('patched');
    expect(validated.dispositions[0]?.patch?.commitSha).toBe(
      '0123456789abcdef0123456789abcdef01234567',
    );
  });

  it('preserves source report path and ticket identity', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'p16-02-'));
    const path = join(dir, 'advisory-observation-triage.json');

    try {
      await writeAdvisoryObservationTriageArtifact(path, makeArtifact());
      const parsed = await readAdvisoryObservationTriageArtifact(path);
      const sorted = [...parsed.dispositions].sort((a, b) =>
        a.source.ticketId.localeCompare(b.source.ticketId),
      );

      expect(sorted[0]?.source.reportPath).toBe(
        'docs/product/delivery/phase-16/reviews/P16.01-subagent-review.report.md',
      );
      expect(sorted[0]?.source.ticketId).toBe('P16.01');
    } finally {
      await rm(dir, { force: true, recursive: true });
    }
  });

  it('updates matching dispositions without duplicating decisions', () => {
    const artifact = makeArtifact();
    const target = artifact.dispositions[1]!;
    const updated: AdvisoryObservationTriageEntry = {
      ...target,
      disposition: 'requires-human-review',
      rationale: 'Needs a product decision after closeout.',
    };

    const merged = mergeAdvisoryObservationTriageEntries(
      artifact.dispositions,
      [updated],
    );

    expect(merged).toHaveLength(4);
    expect(
      merged.find(
        (entry) =>
          entry.source.reportPath === updated.source.reportPath &&
          entry.source.ticketId === updated.source.ticketId &&
          entry.observation === updated.observation,
      ),
    ).toEqual(updated);
  });

  it('upgrades legacy schemaVersion 1 artifacts on read', () => {
    const legacy = {
      schemaVersion: 1,
      recordedAt: '2026-05-24T04:00:00.000Z',
      observations: [
        {
          sourceReportPath: 'docs/.../P16.01-subagent-review.report.md',
          ticketId: 'P16.01',
          observationText: 'Legacy entry',
          disposition: 'deferred',
          rationale: 'Waiting on later phase decision',
        },
        {
          sourceReportPath: 'docs/.../P16.02-subagent-review.report.md',
          ticketId: 'P16.02',
          observationText: 'Converted entry',
          disposition: 'converted-to-ticket',
          rationale: 'Filed as follow-up ticket',
          followUpReference: 'docs/.../ticket-17-follow-up.md',
        },
      ],
    };

    const migrated = validateAdvisoryObservationTriageArtifact(legacy);
    expect(migrated.schemaVersion).toBe(2);
    const dispositions = migrated.dispositions.map((d) => d.disposition).sort();
    expect(dispositions).toEqual(['rejected', 'requires-human-review']);
    expect(migrated.summary['requires-human-review']).toBe(1);
    expect(migrated.summary.rejected).toBe(1);
  });
});
