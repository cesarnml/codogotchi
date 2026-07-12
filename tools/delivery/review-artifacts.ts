import { existsSync, readFileSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

import type {
  AiReviewAgentResult,
  AiReviewComment,
  AiReviewThreadResolution,
  ReviewOutcome,
  ReviewResult,
} from './types';

export type AiReviewFetchArtifact = {
  schemaVersion: 1;
  fetchedAt: string;
  reviewedHeadSha?: string;
  detected: boolean;
  vendors: string[];
  agents: AiReviewAgentResult[];
  comments: AiReviewComment[];
};

export type PrBodyRefreshResult = {
  attemptedAt: string;
  status: 'updated' | 'failed';
  message?: string;
};

export type AiReviewTriageArtifact = {
  schemaVersion: 1;
  recordedAt: string;
  reviewedHeadSha?: string;
  outcome: ReviewResult;
  note: string;
  actionSummary?: string;
  nonActionSummary?: string;
  incompleteAgents?: string[];
  patchCommitShas?: string[];
  threadResolutions?: AiReviewThreadResolution[];
  prBodyRefresh?: PrBodyRefreshResult;
};

type StoredFetchArtifact = {
  schemaVersion?: unknown;
  fetchedAt?: unknown;
  reviewedHeadSha?: unknown;
  reviewed_head_sha?: unknown;
  detected?: unknown;
  vendors?: unknown;
  agents?: unknown;
  comments?: unknown;
};

type StoredTriageArtifact = {
  schemaVersion?: unknown;
  recordedAt?: unknown;
  reviewedHeadSha?: unknown;
  reviewed_head_sha?: unknown;
  outcome?: unknown;
  note?: unknown;
  actionSummary?: unknown;
  action_summary?: unknown;
  nonActionSummary?: unknown;
  non_action_summary?: unknown;
  incompleteAgents?: unknown;
  incomplete_agents?: unknown;
  patchCommitShas?: unknown;
  patch_commit_shas?: unknown;
  threadResolutions?: unknown;
  thread_resolutions?: unknown;
  prBodyRefresh?: unknown;
  pr_body_refresh?: unknown;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function parseOptionalString(value: unknown): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function parseOptionalNumber(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value)
    ? value
    : undefined;
}

function parseOptionalBoolean(value: unknown): boolean | undefined {
  return typeof value === 'boolean' ? value : undefined;
}

function parseCommentArray(value: unknown): AiReviewComment[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((entry) => {
    if (!isRecord(entry)) {
      return [];
    }

    const vendor = parseOptionalString(entry.vendor);
    const channel = parseOptionalString(entry.channel);
    const authorLogin = parseOptionalString(
      entry.authorLogin ?? entry.author_login,
    );
    const authorType = parseOptionalString(
      entry.authorType ?? entry.author_type,
    );
    const body = parseOptionalString(entry.body);
    const kind = parseOptionalString(entry.kind);

    if (
      !vendor ||
      !channel ||
      !authorLogin ||
      !authorType ||
      body === undefined ||
      !kind
    ) {
      return [];
    }

    return [
      {
        authorLogin,
        authorType,
        body,
        channel: channel as AiReviewComment['channel'],
        databaseId: parseOptionalNumber(entry.databaseId ?? entry.database_id),
        isOutdated: parseOptionalBoolean(entry.isOutdated ?? entry.is_outdated),
        isResolved: parseOptionalBoolean(entry.isResolved ?? entry.is_resolved),
        kind: kind as AiReviewComment['kind'],
        line: parseOptionalNumber(entry.line),
        path: parseOptionalString(entry.path),
        threadId: parseOptionalString(entry.threadId ?? entry.thread_id),
        threadViewerCanResolve: parseOptionalBoolean(
          entry.threadViewerCanResolve ?? entry.thread_viewer_can_resolve,
        ),
        updatedAt: parseOptionalString(entry.updatedAt ?? entry.updated_at),
        url: parseOptionalString(entry.url),
        vendor,
      },
    ];
  });
}

function parseAgentArray(value: unknown): AiReviewAgentResult[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((entry) => {
    if (!isRecord(entry)) {
      return [];
    }

    const agent = parseOptionalString(entry.agent);
    const state = parseOptionalString(entry.state);

    if (!agent || !state) {
      return [];
    }

    return [
      {
        agent,
        state: state as AiReviewAgentResult['state'],
        findingsCount: parseOptionalNumber(entry.findingsCount),
        note: parseOptionalString(entry.note),
      },
    ];
  });
}

function parseThreadResolutionArray(
  value: unknown,
): AiReviewThreadResolution[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }

  const parsed = value.flatMap((entry) => {
    if (!isRecord(entry)) {
      return [];
    }

    const status = parseOptionalString(entry.status);
    const threadId = parseOptionalString(entry.threadId ?? entry.thread_id);
    const vendor = parseOptionalString(entry.vendor);

    if (
      !status ||
      !isAiReviewThreadResolutionStatus(status) ||
      !threadId ||
      !vendor
    ) {
      return [];
    }

    return [
      {
        status,
        threadId,
        url: parseOptionalString(entry.url),
        vendor,
        message: parseOptionalString(entry.message),
      },
    ];
  });

  return parsed.length > 0 ? parsed : undefined;
}

function isAiReviewThreadResolutionStatus(
  value: string,
): value is AiReviewThreadResolution['status'] {
  return (
    value === 'resolved' ||
    value === 'already_resolved' ||
    value === 'unresolvable' ||
    value === 'failed'
  );
}

function parseOptionalStringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }

  const parsed = value.filter(
    (entry): entry is string => typeof entry === 'string' && entry.length > 0,
  );
  return parsed.length > 0 ? parsed : undefined;
}

function parsePrBodyRefresh(value: unknown): PrBodyRefreshResult | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const attemptedAt = parseOptionalString(
    value.attemptedAt ?? value.attempted_at,
  );
  const status = parseOptionalString(value.status);

  if (!attemptedAt || !status) {
    return undefined;
  }

  return {
    attemptedAt,
    status: status as PrBodyRefreshResult['status'],
    message: parseOptionalString(value.message),
  };
}

export function buildReviewArtifactPaths(artifactStemPath: string): {
  fetchArtifactPath: string;
  triageArtifactPath: string;
} {
  return {
    fetchArtifactPath: `${artifactStemPath}.fetch.json`,
    triageArtifactPath: `${artifactStemPath}.triage.json`,
  };
}

export function buildPrReviewArtifactStem(ticketId: string): string {
  return `${ticketId}-pr-review`;
}

export async function writeFetchArtifact(
  artifactPath: string,
  artifact: AiReviewFetchArtifact,
): Promise<void> {
  await mkdir(dirname(artifactPath), { recursive: true });
  await writeFile(
    artifactPath,
    JSON.stringify(artifact, null, 2) + '\n',
    'utf8',
  );
}

export async function writeTriageArtifact(
  artifactPath: string,
  artifact: AiReviewTriageArtifact,
): Promise<void> {
  await mkdir(dirname(artifactPath), { recursive: true });
  await writeFile(
    artifactPath,
    JSON.stringify(artifact, null, 2) + '\n',
    'utf8',
  );
}

export function readFetchArtifact(
  artifactPath: string | undefined,
): AiReviewFetchArtifact | undefined {
  if (!artifactPath || !existsSync(artifactPath)) {
    return undefined;
  }

  const parsed = JSON.parse(
    readFileSync(artifactPath, 'utf8'),
  ) as StoredFetchArtifact;
  const vendors = Array.isArray(parsed.vendors)
    ? parsed.vendors.filter(
        (value): value is string =>
          typeof value === 'string' && value.length > 0,
      )
    : [];

  return {
    schemaVersion: 1,
    fetchedAt:
      parseOptionalString(parsed.fetchedAt) ?? new Date(0).toISOString(),
    reviewedHeadSha: parseOptionalString(
      parsed.reviewedHeadSha ?? parsed.reviewed_head_sha,
    ),
    detected: parsed.detected === true,
    vendors,
    agents: parseAgentArray(parsed.agents),
    comments: parseCommentArray(parsed.comments),
  };
}

export function readTriageArtifact(
  artifactPath: string | undefined,
): AiReviewTriageArtifact | undefined {
  if (!artifactPath || !existsSync(artifactPath)) {
    return undefined;
  }

  const parsed = JSON.parse(
    readFileSync(artifactPath, 'utf8'),
  ) as StoredTriageArtifact;
  const outcome = parseOptionalString(parsed.outcome);
  const recordedAt = parseOptionalString(parsed.recordedAt);
  const note = parseOptionalString(parsed.note);

  if (!outcome || !recordedAt || note === undefined) {
    return undefined;
  }

  return {
    schemaVersion: 1,
    recordedAt,
    reviewedHeadSha: parseOptionalString(
      parsed.reviewedHeadSha ?? parsed.reviewed_head_sha,
    ),
    outcome: outcome as ReviewResult,
    note,
    actionSummary: parseOptionalString(
      parsed.actionSummary ?? parsed.action_summary,
    ),
    nonActionSummary: parseOptionalString(
      parsed.nonActionSummary ?? parsed.non_action_summary,
    ),
    incompleteAgents: parseOptionalStringArray(
      parsed.incompleteAgents ?? parsed.incomplete_agents,
    ),
    patchCommitShas: parseOptionalStringArray(
      parsed.patchCommitShas ?? parsed.patch_commit_shas,
    ),
    threadResolutions: parseThreadResolutionArray(
      parsed.threadResolutions ?? parsed.thread_resolutions,
    ),
    prBodyRefresh: parsePrBodyRefresh(
      parsed.prBodyRefresh ?? parsed.pr_body_refresh,
    ),
  };
}

export type LoadedReviewArtifacts = {
  fetch?: AiReviewFetchArtifact;
  triage?: AiReviewTriageArtifact;
};

export function readReviewArtifacts(paths: {
  fetchArtifactPath?: string;
  triageArtifactPath?: string;
}): LoadedReviewArtifacts {
  return {
    fetch: readFetchArtifact(paths.fetchArtifactPath),
    triage: readTriageArtifact(paths.triageArtifactPath),
  };
}

export async function updateTriageArtifact(
  artifactPath: string,
  update: (
    current: AiReviewTriageArtifact | undefined,
  ) => AiReviewTriageArtifact,
): Promise<AiReviewTriageArtifact> {
  const next = update(readTriageArtifact(artifactPath));
  await writeTriageArtifact(artifactPath, next);
  return next;
}

export function buildPatchedOutcome(
  previous: ReviewOutcome | undefined,
  next: ReviewResult,
): ReviewResult {
  if (previous === 'patched' && next === 'clean') {
    return 'patched';
  }

  return next;
}
