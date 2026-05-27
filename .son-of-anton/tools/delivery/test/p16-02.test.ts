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
} from '../advisory-observation-triage';

const DISPOSITIONS: AdvisoryObservationDisposition[] = [
  'patched',
  'rejected',
  'deferred',
  'already-covered',
  'converted-to-ticket',
];

function makeArtifact(): AdvisoryObservationTriageArtifact {
  return {
    schemaVersion: 1,
    recordedAt: '2026-05-24T04:00:00.000Z',
    observations: DISPOSITIONS.map((disposition, index) => ({
      sourceReportPath: `docs/product/delivery/phase-16/reviews/P16.0${index + 1}-subagent-review.report.md`,
      ticketId: `P16.0${index + 1}`,
      observationText: `Observation ${index + 1}`,
      disposition,
      rationale:
        disposition === 'patched' ? undefined : `Rationale for ${disposition}`,
      patchCommitSha:
        disposition === 'patched'
          ? '0123456789abcdef0123456789abcdef01234567'
          : undefined,
      followUpReference:
        disposition === 'converted-to-ticket'
          ? 'docs/product/delivery/phase-17/ticket-01-follow-up.md'
          : undefined,
    })),
  };
}

describe('P16.02 advisory observation triage artifact', () => {
  it('round-trips a valid artifact with all five dispositions', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'p16-02-'));
    const path = join(dir, 'advisory-observation-triage.json');

    try {
      const artifact = makeArtifact();
      await writeAdvisoryObservationTriageArtifact(path, artifact);

      const raw = await readFile(path, 'utf8');
      expect(raw.endsWith('\n')).toBe(true);

      const parsed = await readAdvisoryObservationTriageArtifact(path);
      expect(parsed).toEqual(artifact);
      expect(parsed.observations.map((entry) => entry.disposition)).toEqual(
        DISPOSITIONS,
      );
    } finally {
      await rm(dir, { force: true, recursive: true });
    }
  });

  it('rejects an unknown disposition', () => {
    const artifact = makeArtifact();
    const malformed = {
      ...artifact,
      observations: [
        {
          ...artifact.observations[0]!,
          disposition: 'accepted',
        },
      ],
    };

    expect(() => validateAdvisoryObservationTriageArtifact(malformed)).toThrow(
      /Invalid advisory observation disposition/,
    );
  });

  it('rejects non-patched dispositions without rationale', () => {
    const artifact = makeArtifact();
    const malformed = {
      ...artifact,
      observations: [
        {
          ...artifact.observations[1]!,
          rationale: '',
        },
      ],
    };

    expect(() => validateAdvisoryObservationTriageArtifact(malformed)).toThrow(
      /requires a non-empty rationale/,
    );
  });

  it('accepts a patched disposition with a commit SHA', () => {
    const artifact = makeArtifact();
    const patched = validateAdvisoryObservationTriageArtifact({
      ...artifact,
      observations: [artifact.observations[0]],
    });

    expect(patched.observations[0]?.disposition).toBe('patched');
    expect(patched.observations[0]?.patchCommitSha).toBe(
      '0123456789abcdef0123456789abcdef01234567',
    );
  });

  it('preserves source report path and ticket identity', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'p16-02-'));
    const path = join(dir, 'advisory-observation-triage.json');

    try {
      await writeAdvisoryObservationTriageArtifact(path, makeArtifact());
      const parsed = await readAdvisoryObservationTriageArtifact(path);

      expect(parsed.observations[0]?.sourceReportPath).toBe(
        'docs/product/delivery/phase-16/reviews/P16.01-subagent-review.report.md',
      );
      expect(parsed.observations[0]?.ticketId).toBe('P16.01');
    } finally {
      await rm(dir, { force: true, recursive: true });
    }
  });

  it('updates matching observations without duplicating decisions', () => {
    const artifact = makeArtifact();
    const updated = {
      ...artifact.observations[1]!,
      disposition: 'deferred' as const,
      rationale: 'Needs a product decision after closeout.',
    };

    const merged = mergeAdvisoryObservationTriageEntries(
      artifact.observations,
      [updated],
    );

    expect(merged).toHaveLength(5);
    expect(
      merged.find(
        (entry) =>
          entry.sourceReportPath === updated.sourceReportPath &&
          entry.ticketId === updated.ticketId &&
          entry.observationText === updated.observationText,
      ),
    ).toEqual(updated);
  });
});
