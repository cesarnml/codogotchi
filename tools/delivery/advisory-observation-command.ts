import { existsSync } from 'node:fs';
import { mkdir, readdir, readFile } from 'node:fs/promises';
import { dirname, isAbsolute, join } from 'node:path';

import {
  mergeAdvisoryObservationTriageEntries,
  readAdvisoryObservationTriageArtifact,
  writeAdvisoryObservationTriageArtifact,
  type AdvisoryObservationTriageEntry,
} from './advisory-observation-triage';
import { parseAdvisoryObservations } from './reconciliation';
import type { DeliveryState } from './types';

export type AdvisoryObservationDispositionInput =
  AdvisoryObservationTriageEntry;

export type AdvisoryObservationGroup = {
  ticketId: string;
  sourceReportPath: string;
  observations: string[];
};

export type AdvisoryObservationTriageResult = {
  artifactPath: string;
  groups: AdvisoryObservationGroup[];
  observationsWritten: number;
};

type SubagentLedgerInvocation = {
  outcome?: string;
  rawOutput?: string;
  terminatedReason?: string;
};

type SubagentLedger = {
  invocations?: SubagentLedgerInvocation[];
  ticket?: string;
};

function normalizeRepoPath(value: string): string {
  return value.replace(/^\.?\//, '');
}

function toAbsolute(repoRoot: string, repoPath: string): string {
  return isAbsolute(repoPath) ? repoPath : join(repoRoot, repoPath);
}

export function deriveAdvisoryObservationTriageArtifactPath(
  state: Pick<DeliveryState, 'reviewsDirPath'>,
): string {
  return `${dirname(normalizeRepoPath(state.reviewsDirPath))}/advisory-observation-triage.json`;
}

function dispositionKey(input: {
  observationText: string;
  sourceReportPath: string;
  ticketId: string;
}): string {
  return `${input.sourceReportPath}\u0000${input.ticketId}\u0000${input.observationText}`;
}

function normalizeDispositions(
  dispositions: AdvisoryObservationDispositionInput[],
): Map<string, AdvisoryObservationDispositionInput> {
  const byKey = new Map<string, AdvisoryObservationDispositionInput>();
  for (const disposition of dispositions) {
    byKey.set(dispositionKey(disposition), disposition);
  }
  return byKey;
}

async function readJson(path: string): Promise<unknown> {
  return JSON.parse(await readFile(path, 'utf8'));
}

async function listLedgerPaths(input: {
  repoRoot: string;
  state: DeliveryState;
}): Promise<string[]> {
  const paths = new Set<string>();
  for (const ticket of input.state.tickets) {
    if (ticket.subagentRunnerArtifactPath) {
      paths.add(normalizeRepoPath(ticket.subagentRunnerArtifactPath));
    }
  }

  const reviewsDir = toAbsolute(input.repoRoot, input.state.reviewsDirPath);
  if (existsSync(reviewsDir)) {
    for (const entry of await readdir(reviewsDir)) {
      if (entry.endsWith('-subagent-review.ledger.json')) {
        paths.add(`${normalizeRepoPath(input.state.reviewsDirPath)}/${entry}`);
      }
    }
  }

  return [...paths].sort();
}

function latestReportPath(ledger: SubagentLedger): string | undefined {
  const invocations = [...(ledger.invocations ?? [])].reverse();
  return invocations.find(
    (invocation) =>
      invocation.terminatedReason === 'completed' &&
      typeof invocation.rawOutput === 'string' &&
      invocation.rawOutput.trim() !== '',
  )?.rawOutput;
}

function ticketIdForLedger(
  ledger: SubagentLedger,
  fallbackPath: string,
): string {
  if (typeof ledger.ticket === 'string' && ledger.ticket.trim() !== '') {
    return ledger.ticket;
  }
  return (
    fallbackPath
      .split('/')
      .pop()
      ?.replace(/-subagent-review\.ledger\.json$/, '') ?? ''
  );
}

async function scanAdvisoryObservationGroups(input: {
  repoRoot: string;
  state: DeliveryState;
}): Promise<AdvisoryObservationGroup[]> {
  const groups: AdvisoryObservationGroup[] = [];
  for (const ledgerPath of await listLedgerPaths(input)) {
    const absoluteLedgerPath = toAbsolute(input.repoRoot, ledgerPath);
    if (!existsSync(absoluteLedgerPath)) {
      continue;
    }

    const ledger = (await readJson(absoluteLedgerPath)) as SubagentLedger;
    const sourceReportPath = latestReportPath(ledger);
    if (!sourceReportPath) {
      continue;
    }

    const absoluteReportPath = toAbsolute(input.repoRoot, sourceReportPath);
    if (!existsSync(absoluteReportPath)) {
      continue;
    }

    const observations = parseAdvisoryObservations(
      await readFile(absoluteReportPath, 'utf8'),
    );
    if (observations.length === 0) {
      continue;
    }

    groups.push({
      ticketId: ticketIdForLedger(ledger, ledgerPath),
      sourceReportPath: normalizeRepoPath(sourceReportPath),
      observations,
    });
  }

  return groups.sort((left, right) =>
    `${left.ticketId}\u0000${left.sourceReportPath}`.localeCompare(
      `${right.ticketId}\u0000${right.sourceReportPath}`,
    ),
  );
}

export async function readAdvisoryObservationDispositionInput(
  inputPath: string,
): Promise<AdvisoryObservationDispositionInput[]> {
  const raw = await readJson(inputPath);
  const observations = Array.isArray(raw)
    ? raw
    : Array.isArray((raw as { observations?: unknown }).observations)
      ? (raw as { observations: unknown[] }).observations
      : undefined;

  if (!observations) {
    throw new Error(
      'Advisory observation disposition input must be an array or an object with observations[].',
    );
  }

  return observations as AdvisoryObservationDispositionInput[];
}

export async function runAdvisoryObservationTriage(input: {
  repoRoot: string;
  state: DeliveryState;
  dispositions: AdvisoryObservationDispositionInput[];
}): Promise<AdvisoryObservationTriageResult> {
  const groups = await scanAdvisoryObservationGroups(input);
  const dispositionsByKey = normalizeDispositions(input.dispositions);
  const incoming: AdvisoryObservationTriageEntry[] = [];

  for (const group of groups) {
    for (const observationText of group.observations) {
      const key = dispositionKey({
        sourceReportPath: group.sourceReportPath,
        ticketId: group.ticketId,
        observationText,
      });
      const disposition = dispositionsByKey.get(key);
      if (!disposition) {
        throw new Error(
          `Missing advisory observation disposition data for ${group.ticketId} in ${group.sourceReportPath}: ${observationText}`,
        );
      }
      incoming.push(disposition);
    }
  }

  const artifactPath = deriveAdvisoryObservationTriageArtifactPath(input.state);
  const absoluteArtifactPath = toAbsolute(input.repoRoot, artifactPath);
  const existing = existsSync(absoluteArtifactPath)
    ? await readAdvisoryObservationTriageArtifact(absoluteArtifactPath)
    : {
        schemaVersion: 1 as const,
        recordedAt: new Date().toISOString(),
        observations: [],
      };

  await mkdir(dirname(absoluteArtifactPath), { recursive: true });
  const merged = mergeAdvisoryObservationTriageEntries(
    existing.observations,
    incoming,
  );
  await writeAdvisoryObservationTriageArtifact(absoluteArtifactPath, {
    ...existing,
    recordedAt: new Date().toISOString(),
    observations: merged,
  });

  return {
    artifactPath,
    groups,
    observationsWritten: incoming.length,
  };
}
