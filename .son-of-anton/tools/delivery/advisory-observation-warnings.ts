import { existsSync } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';

import {
  deriveAdvisoryObservationTriageArtifactPath,
  type AdvisoryObservationGroup,
} from './advisory-observation-command';
import {
  readAdvisoryObservationTriageArtifact,
  type AdvisoryObservationTriageEntry,
} from './advisory-observation-triage';
import {
  inspectSubagentReviewEvidence,
  parseAdvisoryObservations,
} from './reconciliation';
import type { DeliveryState } from './types';

export type AdvisoryObservationWarning =
  | {
      kind: 'untriaged_observation';
      observationText: string;
      sourceReportPath: string;
      ticketId: string;
    }
  | {
      evidenceKind: 'missing_report' | 'empty_report';
      kind: 'suspicious_evidence';
      rawOutput?: string;
      ticketId: string;
    }
  | {
      kind: 'warning_error';
      message: string;
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

function observationKey(input: {
  observationText: string;
  sourceReportPath: string;
  ticketId: string;
}): string {
  return `${input.sourceReportPath}\u0000${input.ticketId}\u0000${input.observationText}`;
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

function latestCompletedRawOutput(ledger: SubagentLedger): string | undefined {
  return [...(ledger.invocations ?? [])]
    .reverse()
    .find(
      (invocation) =>
        invocation.terminatedReason === 'completed' &&
        typeof invocation.rawOutput === 'string' &&
        invocation.rawOutput.trim() !== '',
    )?.rawOutput;
}

async function collectAdvisoryObservationGroups(input: {
  repoRoot: string;
  state: DeliveryState;
}): Promise<{
  groups: AdvisoryObservationGroup[];
  suspicious: AdvisoryObservationWarning[];
}> {
  const groups: AdvisoryObservationGroup[] = [];
  const suspicious: AdvisoryObservationWarning[] = [];

  for (const ledgerPath of await listLedgerPaths(input)) {
    const absoluteLedgerPath = toAbsolute(input.repoRoot, ledgerPath);
    if (!existsSync(absoluteLedgerPath)) {
      continue;
    }

    const ledger = (await readJson(absoluteLedgerPath)) as SubagentLedger;
    const ticketId = ticketIdForLedger(ledger, ledgerPath);
    for (const warning of inspectSubagentReviewEvidence({
      repoRoot: input.repoRoot,
      rows: ledger.invocations ?? [],
    })) {
      suspicious.push({
        kind: 'suspicious_evidence',
        ticketId,
        evidenceKind: warning.kind,
        ...(warning.rawOutput !== undefined
          ? { rawOutput: normalizeRepoPath(warning.rawOutput) }
          : {}),
      });
    }

    const sourceReportPath = latestCompletedRawOutput(ledger);
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
      ticketId,
      sourceReportPath: normalizeRepoPath(sourceReportPath),
      observations,
    });
  }

  return {
    groups: groups.sort((left, right) =>
      `${left.ticketId}\u0000${left.sourceReportPath}`.localeCompare(
        `${right.ticketId}\u0000${right.sourceReportPath}`,
      ),
    ),
    suspicious,
  };
}

async function readTriagedObservationKeys(input: {
  repoRoot: string;
  state: DeliveryState;
}): Promise<Set<string>> {
  const artifactPath = toAbsolute(
    input.repoRoot,
    deriveAdvisoryObservationTriageArtifactPath(input.state),
  );
  if (!existsSync(artifactPath)) {
    return new Set();
  }

  const artifact = await readAdvisoryObservationTriageArtifact(artifactPath);
  return new Set(
    artifact.observations.map((entry: AdvisoryObservationTriageEntry) =>
      observationKey(entry),
    ),
  );
}

export async function computeAdvisoryObservationWarnings(input: {
  repoRoot: string;
  state: DeliveryState;
}): Promise<AdvisoryObservationWarning[]> {
  const { groups, suspicious } = await collectAdvisoryObservationGroups(input);
  const triagedKeys = await readTriagedObservationKeys(input);
  const untriaged: AdvisoryObservationWarning[] = [];

  for (const group of groups) {
    for (const observationText of group.observations) {
      const key = observationKey({
        ticketId: group.ticketId,
        sourceReportPath: group.sourceReportPath,
        observationText,
      });
      if (!triagedKeys.has(key)) {
        untriaged.push({
          kind: 'untriaged_observation',
          ticketId: group.ticketId,
          sourceReportPath: group.sourceReportPath,
          observationText,
        });
      }
    }
  }

  return [...untriaged, ...suspicious].sort((left, right) =>
    formatWarningSortKey(left).localeCompare(formatWarningSortKey(right)),
  );
}

export function formatAdvisoryObservationWarnings(
  warnings: AdvisoryObservationWarning[],
): string {
  if (warnings.length === 0) {
    return '';
  }

  const lines = ['Advisory Observation Warnings'];
  for (const warning of warnings) {
    if (warning.kind === 'untriaged_observation') {
      lines.push(
        `- untriaged ${warning.ticketId}: ${warning.observationText} (${warning.sourceReportPath})`,
      );
      continue;
    }

    if (warning.kind === 'warning_error') {
      lines.push(`- warning computation failed: ${warning.message}`);
      continue;
    }

    lines.push(
      `- suspicious evidence ${warning.ticketId}: ${warning.evidenceKind}${warning.rawOutput ? ` (${warning.rawOutput})` : ''}`,
    );
  }

  return lines.join('\n');
}

function formatWarningSortKey(warning: AdvisoryObservationWarning): string {
  if (warning.kind === 'untriaged_observation') {
    return `${warning.ticketId}\u0000${warning.sourceReportPath}\u0000${warning.observationText}`;
  }

  if (warning.kind === 'warning_error') {
    return `zzzz\u0000${warning.message}`;
  }

  return `${warning.ticketId}\u0000${warning.evidenceKind}\u0000${warning.rawOutput ?? ''}`;
}
