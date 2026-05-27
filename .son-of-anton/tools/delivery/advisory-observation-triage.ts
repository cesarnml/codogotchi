import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

export const ADVISORY_OBSERVATION_DISPOSITIONS = [
  'patched',
  'rejected',
  'deferred',
  'already-covered',
  'converted-to-ticket',
] as const;

export type AdvisoryObservationDisposition =
  (typeof ADVISORY_OBSERVATION_DISPOSITIONS)[number];

export type AdvisoryObservationTriageEntry = {
  sourceReportPath: string;
  ticketId: string;
  observationText: string;
  disposition: AdvisoryObservationDisposition;
  rationale?: string;
  patchCommitSha?: string;
  followUpReference?: string;
};

export type AdvisoryObservationTriageArtifact = {
  schemaVersion: 1;
  recordedAt: string;
  observations: AdvisoryObservationTriageEntry[];
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function requireNonEmptyString(
  value: unknown,
  fieldName: string,
  index?: number,
): string {
  if (typeof value !== 'string' || value.trim() === '') {
    const prefix = index === undefined ? '' : `Observation ${index + 1}: `;
    throw new Error(`${prefix}${fieldName} must be a non-empty string.`);
  }

  return value;
}

function parseOptionalString(
  value: unknown,
  fieldName: string,
): string | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== 'string') {
    throw new Error(`${fieldName} must be a string when present.`);
  }

  return value;
}

function isAdvisoryObservationDisposition(
  value: string,
): value is AdvisoryObservationDisposition {
  return ADVISORY_OBSERVATION_DISPOSITIONS.includes(
    value as AdvisoryObservationDisposition,
  );
}

function normalizeEntry(
  value: unknown,
  index: number,
): AdvisoryObservationTriageEntry {
  if (!isRecord(value)) {
    throw new Error(`Observation ${index + 1} must be an object.`);
  }

  const disposition = requireNonEmptyString(
    value.disposition,
    'disposition',
    index,
  );
  if (!isAdvisoryObservationDisposition(disposition)) {
    throw new Error(
      `Invalid advisory observation disposition "${disposition}" for observation ${index + 1}.`,
    );
  }

  const rationale = parseOptionalString(value.rationale, 'rationale');
  const patchCommitSha = parseOptionalString(
    value.patchCommitSha,
    'patchCommitSha',
  );
  const followUpReference = parseOptionalString(
    value.followUpReference,
    'followUpReference',
  );
  if (disposition !== 'patched' && (rationale ?? '').trim() === '') {
    throw new Error(
      `Observation ${index + 1} with disposition "${disposition}" requires a non-empty rationale.`,
    );
  }

  return {
    sourceReportPath: requireNonEmptyString(
      value.sourceReportPath,
      'sourceReportPath',
      index,
    ),
    ticketId: requireNonEmptyString(value.ticketId, 'ticketId', index),
    observationText: requireNonEmptyString(
      value.observationText,
      'observationText',
      index,
    ),
    disposition,
    ...(rationale !== undefined ? { rationale } : {}),
    ...(patchCommitSha !== undefined ? { patchCommitSha } : {}),
    ...(followUpReference !== undefined ? { followUpReference } : {}),
  };
}

export function validateAdvisoryObservationTriageArtifact(
  value: unknown,
): AdvisoryObservationTriageArtifact {
  if (!isRecord(value)) {
    throw new Error('Advisory observation triage artifact must be an object.');
  }

  if (value.schemaVersion !== 1) {
    throw new Error(
      'Advisory observation triage artifact schemaVersion must be 1.',
    );
  }

  const recordedAt = requireNonEmptyString(value.recordedAt, 'recordedAt');
  if (!Array.isArray(value.observations)) {
    throw new Error(
      'Advisory observation triage artifact observations must be an array.',
    );
  }

  return {
    schemaVersion: 1,
    recordedAt,
    observations: value.observations.map((entry, index) =>
      normalizeEntry(entry, index),
    ),
  };
}

export async function readAdvisoryObservationTriageArtifact(
  artifactPath: string,
): Promise<AdvisoryObservationTriageArtifact> {
  const raw = await readFile(artifactPath, 'utf8');
  return validateAdvisoryObservationTriageArtifact(JSON.parse(raw));
}

export async function writeAdvisoryObservationTriageArtifact(
  artifactPath: string,
  artifact: AdvisoryObservationTriageArtifact,
): Promise<void> {
  const validated = validateAdvisoryObservationTriageArtifact(artifact);
  await mkdir(dirname(artifactPath), { recursive: true });
  await writeFile(
    artifactPath,
    `${JSON.stringify(sortAdvisoryObservationTriageArtifact(validated), null, 2)}\n`,
  );
}

export function mergeAdvisoryObservationTriageEntries(
  existing: AdvisoryObservationTriageEntry[],
  incoming: AdvisoryObservationTriageEntry[],
): AdvisoryObservationTriageEntry[] {
  const merged = new Map<string, AdvisoryObservationTriageEntry>();
  for (const entry of [...existing, ...incoming]) {
    const normalized = normalizeEntry(entry, merged.size);
    merged.set(advisoryObservationTriageEntryKey(normalized), normalized);
  }

  return [...merged.values()].sort(compareAdvisoryObservationTriageEntries);
}

export function sortAdvisoryObservationTriageArtifact(
  artifact: AdvisoryObservationTriageArtifact,
): AdvisoryObservationTriageArtifact {
  return {
    ...artifact,
    observations: [...artifact.observations].sort(
      compareAdvisoryObservationTriageEntries,
    ),
  };
}

function advisoryObservationTriageEntryKey(
  entry: AdvisoryObservationTriageEntry,
): string {
  return `${entry.sourceReportPath}\u0000${entry.ticketId}\u0000${entry.observationText}`;
}

function compareAdvisoryObservationTriageEntries(
  left: AdvisoryObservationTriageEntry,
  right: AdvisoryObservationTriageEntry,
): number {
  return advisoryObservationTriageEntryKey(left).localeCompare(
    advisoryObservationTriageEntryKey(right),
  );
}
