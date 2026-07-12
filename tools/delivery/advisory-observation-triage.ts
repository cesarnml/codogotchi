import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

/**
 * Disposition vocabulary for the post-phase advisory-observation triage lane.
 *
 * The triage lane runs **after** the phase has landed on `main`. Unlike the
 * subagent-review reconciliation gate (which uses `deferred` to mean "the
 * primary agent consciously decided not to patch before opening the PR"),
 * post-phase triage has no in-flight PR window — every advisory observation
 * must reach a terminal decision.
 *
 * - `patched`               — primary agent applied a prudent fix. Requires a
 *                             `patch.commitSha` so the audit trail names the
 *                             actual change.
 * - `rejected`              — observation is not actionable (markdown artifact
 *                             parsed as observation, false positive, out of
 *                             scope, or covered by an existing follow-up
 *                             ticket recorded in `followUpReference`).
 * - `already-covered`       — observation is already addressed by behavior
 *                             that landed in a sibling ticket or earlier
 *                             phase. The rationale should name where.
 * - `requires-human-review` — the only escape hatch. Use when the decision is
 *                             genuinely ambiguous and the developer must
 *                             make the call. Not a synonym for "skip"; not a
 *                             holding state. Surface honestly.
 */
export const ADVISORY_OBSERVATION_DISPOSITIONS = [
  'patched',
  'rejected',
  'already-covered',
  'requires-human-review',
] as const;

export type AdvisoryObservationDisposition =
  (typeof ADVISORY_OBSERVATION_DISPOSITIONS)[number];

export type AdvisoryObservationPatchEvidence = {
  commitSha: string;
  files?: string[];
};

export type AdvisoryObservationTriageEntry = {
  /** Action taken — the disposition leads. */
  disposition: AdvisoryObservationDisposition;
  /** Why this disposition was chosen. Required for every disposition, including `patched`. */
  rationale: string;
  /** Structured patch evidence — required when `disposition` is `patched`. */
  patch?: AdvisoryObservationPatchEvidence;
  /** Optional pointer to a follow-up ticket, issue, or PR. */
  followUpReference?: string;
  /** Origin of the observation. */
  source: {
    reportPath: string;
    ticketId: string;
  };
  /** Verbatim observation text — primary matching key for idempotent re-triage. */
  observation: string;
};

export type AdvisoryObservationTriageSummary = {
  total: number;
  patched: number;
  rejected: number;
  'already-covered': number;
  'requires-human-review': number;
};

export type AdvisoryObservationTriageArtifact = {
  schemaVersion: 2;
  recordedAt: string;
  summary: AdvisoryObservationTriageSummary;
  dispositions: AdvisoryObservationTriageEntry[];
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
    const prefix = index === undefined ? '' : `Disposition ${index + 1}: `;
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

function parseOptionalStringArray(
  value: unknown,
  fieldName: string,
): string[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value)) {
    throw new Error(`${fieldName} must be an array of strings when present.`);
  }
  return value.map((entry, index) => {
    if (typeof entry !== 'string' || entry.trim() === '') {
      throw new Error(
        `${fieldName}[${index}] must be a non-empty string when present.`,
      );
    }
    return entry;
  });
}

function isAdvisoryObservationDisposition(
  value: string,
): value is AdvisoryObservationDisposition {
  return ADVISORY_OBSERVATION_DISPOSITIONS.includes(
    value as AdvisoryObservationDisposition,
  );
}

/**
 * Translate retired v1 disposition vocabulary onto v2. v1 had `deferred` and
 * `converted-to-ticket`; v2 has neither — `deferred` becomes
 * `requires-human-review` (no in-flight gate, so the operator must decide),
 * and `converted-to-ticket` becomes `rejected` with the ticket pointer
 * preserved via `followUpReference`.
 */
function migrateLegacyDisposition(
  value: string,
): AdvisoryObservationDisposition {
  if (value === 'deferred') return 'requires-human-review';
  if (value === 'converted-to-ticket') return 'rejected';
  if (isAdvisoryObservationDisposition(value)) return value;
  throw new Error(`Invalid advisory observation disposition "${value}".`);
}

function parsePatchEvidence(
  value: unknown,
  index: number,
  disposition: AdvisoryObservationDisposition,
): AdvisoryObservationPatchEvidence | undefined {
  if (value === undefined) {
    if (disposition === 'patched') {
      throw new Error(
        `Disposition ${index + 1}: \`patched\` requires \`patch.commitSha\` so the audit trail names the actual change.`,
      );
    }
    return undefined;
  }
  if (!isRecord(value)) {
    throw new Error(`Disposition ${index + 1}: \`patch\` must be an object.`);
  }
  const commitSha = requireNonEmptyString(
    value.commitSha,
    'patch.commitSha',
    index,
  );
  const files = parseOptionalStringArray(value.files, 'patch.files');
  return files !== undefined ? { commitSha, files } : { commitSha };
}

function parseSource(
  value: unknown,
  index: number,
): { reportPath: string; ticketId: string } {
  if (!isRecord(value)) {
    throw new Error(`Disposition ${index + 1}: \`source\` must be an object.`);
  }
  return {
    reportPath: requireNonEmptyString(
      value.reportPath,
      'source.reportPath',
      index,
    ),
    ticketId: requireNonEmptyString(value.ticketId, 'source.ticketId', index),
  };
}

function normalizeEntry(
  value: unknown,
  index: number,
): AdvisoryObservationTriageEntry {
  if (!isRecord(value)) {
    throw new Error(`Disposition ${index + 1} must be an object.`);
  }

  // Accept either the v2 nested shape (`source: { reportPath, ticketId }`,
  // `observation`, `patch: { commitSha, files? }`) or the legacy v1 flat
  // shape (`sourceReportPath`, `ticketId`, `observationText`,
  // `patchCommitSha`). v1 input is silently upgraded on read so existing
  // dispositions files continue to load.
  const legacyDisposition = value.disposition;
  if (
    typeof legacyDisposition !== 'string' ||
    legacyDisposition.trim() === ''
  ) {
    throw new Error(
      `Disposition ${index + 1}: \`disposition\` must be a non-empty string.`,
    );
  }
  const disposition = migrateLegacyDisposition(legacyDisposition);

  const rationale = parseOptionalString(value.rationale, 'rationale');
  if (rationale === undefined || rationale.trim() === '') {
    throw new Error(
      `Disposition ${index + 1}: \`rationale\` is required for every disposition (including \`patched\`).`,
    );
  }

  const followUpReference = parseOptionalString(
    value.followUpReference,
    'followUpReference',
  );

  // Patch evidence: v2 nested `patch: { commitSha, files? }` or v1 flat `patchCommitSha`.
  const patch =
    value.patch !== undefined
      ? parsePatchEvidence(value.patch, index, disposition)
      : value.patchCommitSha !== undefined
        ? parsePatchEvidence(
            { commitSha: value.patchCommitSha },
            index,
            disposition,
          )
        : parsePatchEvidence(undefined, index, disposition);

  // Source identity: v2 nested or v1 flat.
  const source =
    value.source !== undefined
      ? parseSource(value.source, index)
      : {
          reportPath: requireNonEmptyString(
            value.sourceReportPath,
            'source.reportPath',
            index,
          ),
          ticketId: requireNonEmptyString(
            value.ticketId,
            'source.ticketId',
            index,
          ),
        };

  const observationRaw = value.observation ?? value.observationText;
  const observation = requireNonEmptyString(
    observationRaw,
    'observation',
    index,
  );

  return {
    disposition,
    rationale,
    ...(patch !== undefined ? { patch } : {}),
    ...(followUpReference !== undefined ? { followUpReference } : {}),
    source,
    observation,
  };
}

function summarizeDispositions(
  entries: AdvisoryObservationTriageEntry[],
): AdvisoryObservationTriageSummary {
  const summary: AdvisoryObservationTriageSummary = {
    total: entries.length,
    patched: 0,
    rejected: 0,
    'already-covered': 0,
    'requires-human-review': 0,
  };
  for (const entry of entries) {
    summary[entry.disposition] += 1;
  }
  return summary;
}

export function validateAdvisoryObservationTriageArtifact(
  value: unknown,
): AdvisoryObservationTriageArtifact {
  if (!isRecord(value)) {
    throw new Error('Advisory observation triage artifact must be an object.');
  }

  // Accept schemaVersion 1 (legacy) and silently upgrade to 2 on read.
  if (value.schemaVersion !== 1 && value.schemaVersion !== 2) {
    throw new Error(
      'Advisory observation triage artifact schemaVersion must be 1 (legacy) or 2.',
    );
  }

  const recordedAt = requireNonEmptyString(value.recordedAt, 'recordedAt');

  // v1 stored entries under `observations`; v2 stores them under `dispositions`.
  const entriesRaw = value.dispositions ?? value.observations;
  if (!Array.isArray(entriesRaw)) {
    throw new Error(
      'Advisory observation triage artifact must include a `dispositions` array (or legacy `observations` array).',
    );
  }

  const dispositions = entriesRaw.map((entry, index) =>
    normalizeEntry(entry, index),
  );

  return {
    schemaVersion: 2,
    recordedAt,
    summary: summarizeDispositions(dispositions),
    dispositions,
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
  const dispositions = [...artifact.dispositions].sort(
    compareAdvisoryObservationTriageEntries,
  );
  return {
    ...artifact,
    summary: summarizeDispositions(dispositions),
    dispositions,
  };
}

function advisoryObservationTriageEntryKey(
  entry: AdvisoryObservationTriageEntry,
): string {
  return `${entry.source.reportPath}\u0000${entry.source.ticketId}\u0000${entry.observation}`;
}

function compareAdvisoryObservationTriageEntries(
  left: AdvisoryObservationTriageEntry,
  right: AdvisoryObservationTriageEntry,
): number {
  return advisoryObservationTriageEntryKey(left).localeCompare(
    advisoryObservationTriageEntryKey(right),
  );
}
