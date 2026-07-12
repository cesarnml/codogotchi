import { existsSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

import type {
  AiReviewAgentResult,
  AiReviewAgentState,
  AiReviewComment,
  AiReviewFetcherResult,
  AiReviewThreadResolution,
  AiReviewTriagerResult,
  DeliveryState,
  ReviewOutcome,
  ReviewResult,
  StandaloneAiReviewResult,
  StandalonePullRequest,
  TicketState,
} from './types';

import {
  buildPrReviewArtifactStem,
  buildReviewArtifactPaths,
  readFetchArtifact,
  readTriageArtifact,
  updateTriageArtifact,
  writeFetchArtifact,
  writeTriageArtifact,
  type AiReviewFetchArtifact,
  type AiReviewTriageArtifact,
} from './review-artifacts';

import {
  type ReviewPollingProfile,
  DEFAULT_REVIEW_POLLING_PROFILE,
  RECONCILE_REVIEW_POLLING_PROFILE,
  computeExtendedReviewPollMaxWaitMinutes,
  resolveDeliveryReviewPollingProfile,
} from './review-polling-profile';

export {
  type ReviewPollingProfile,
  DEFAULT_REVIEW_POLLING_PROFILE,
  RECONCILE_REVIEW_POLLING_PROFILE,
  computeExtendedReviewPollMaxWaitMinutes,
  resolveDeliveryReviewPollingProfile,
} from './review-polling-profile';

const STANDALONE_TRIAGE_ARTIFACT_DIR = '.agents/triage-standalone';

function formatError(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  return String(error);
}

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

export function buildReviewPollCheckMinutes(
  intervalMinutes: number,
  maxWaitMinutes: number,
): number[] {
  if (intervalMinutes <= 0 || maxWaitMinutes <= 0) {
    throw new Error('Review polling interval and max wait must be positive.');
  }

  const checks: number[] = [];

  for (
    let minute = intervalMinutes;
    minute <= maxWaitMinutes;
    minute += intervalMinutes
  ) {
    checks.push(minute);
  }

  return checks;
}

export function resolveReviewPollWindowStart(
  startedAt: string | undefined,
  now: () => number = Date.now,
): { pollWindowStartedAt: number; pollWindowStartedAtIso: string } {
  const parsed = Date.parse(startedAt ?? '');

  if (!Number.isNaN(parsed)) {
    return {
      pollWindowStartedAt: parsed,
      pollWindowStartedAtIso: new Date(parsed).toISOString(),
    };
  }

  const fallback = now();
  return {
    pollWindowStartedAt: fallback,
    pollWindowStartedAtIso: new Date(fallback).toISOString(),
  };
}

export function parseAiReviewFetcherOutput(
  output: string,
): AiReviewFetcherResult {
  let parsed: unknown;

  try {
    parsed = JSON.parse(output);
  } catch (error) {
    throw new Error(
      `AI review fetcher must emit JSON. ${formatError(error)}\n${output.trim()}`.trim(),
      {
        cause: error,
      },
    );
  }

  if (!isRecord(parsed)) {
    throw new Error(
      'AI review fetcher output must be a JSON object with `agents`, `detected`, `vendors`, and `comments` fields.',
    );
  }

  if (
    !Array.isArray(parsed.agents) ||
    !parsed.agents.every(
      (entry) =>
        isRecord(entry) &&
        typeof entry.agent === 'string' &&
        (entry.state === 'started' ||
          entry.state === 'completed' ||
          entry.state === 'findings_detected') &&
        (typeof entry.findingsCount === 'undefined' ||
          parseOptionalNumber(entry.findingsCount) !== undefined) &&
        (typeof entry.note === 'undefined' ||
          parseOptionalString(entry.note) !== undefined),
    ) ||
    typeof parsed.detected !== 'boolean' ||
    !Array.isArray(parsed.vendors) ||
    !parsed.vendors.every((value) => typeof value === 'string') ||
    !Array.isArray(parsed.comments)
  ) {
    throw new Error(
      'AI review fetcher output must be JSON with `agents`, boolean `detected`, string[] `vendors`, and array `comments` fields.',
    );
  }

  const comments = parsed.comments.map((entry) => {
    if (!isRecord(entry)) {
      throw new Error('AI review fetcher comments must be JSON objects.');
    }

    if (
      typeof entry.vendor !== 'string' ||
      typeof entry.channel !== 'string' ||
      typeof entry.author_login !== 'string' ||
      typeof entry.author_type !== 'string' ||
      typeof entry.body !== 'string' ||
      typeof entry.kind !== 'string'
    ) {
      throw new Error(
        'AI review fetcher comments must include string `vendor`, `channel`, `author_login`, `author_type`, `body`, and `kind` fields.',
      );
    }

    if (
      entry.channel !== 'issue_comment' &&
      entry.channel !== 'review_summary' &&
      entry.channel !== 'inline_review'
    ) {
      throw new Error(`Unknown AI review comment channel: ${entry.channel}`);
    }

    if (
      entry.kind !== 'summary' &&
      entry.kind !== 'finding' &&
      entry.kind !== 'unknown'
    ) {
      throw new Error(`Unknown AI review comment kind: ${entry.kind}`);
    }

    return {
      authorLogin: entry.author_login,
      authorType: entry.author_type,
      body: entry.body,
      channel: entry.channel,
      databaseId: parseOptionalNumber(entry.database_id),
      isOutdated: parseOptionalBoolean(entry.is_outdated),
      isResolved: parseOptionalBoolean(entry.is_resolved),
      kind: entry.kind,
      line: parseOptionalNumber(entry.line),
      path: parseOptionalString(entry.path),
      threadId: parseOptionalString(entry.thread_id),
      threadViewerCanResolve: parseOptionalBoolean(
        entry.thread_viewer_can_resolve,
      ),
      updatedAt: parseOptionalString(entry.updated_at),
      url: parseOptionalString(entry.url),
      vendor: entry.vendor,
    } satisfies AiReviewComment;
  });

  return {
    agents: parsed.agents.map((entry) => ({
      agent: entry.agent as string,
      state: entry.state as AiReviewAgentState,
      findingsCount: parseOptionalNumber(entry.findingsCount),
      note: parseOptionalString(entry.note),
    })) satisfies AiReviewAgentResult[],
    comments,
    detected: parsed.detected,
    reviewedHeadSha: parseOptionalString(parsed.reviewed_head_sha),
    vendors: parsed.vendors,
  };
}

export function parseAiReviewTriagerOutput(
  output: string,
): AiReviewTriagerResult {
  let parsed: unknown;

  try {
    parsed = JSON.parse(output);
  } catch (error) {
    throw new Error(
      `AI review triager must emit JSON. ${formatError(error)}\n${output.trim()}`.trim(),
      {
        cause: error,
      },
    );
  }

  if (!isRecord(parsed)) {
    throw new Error(
      'AI review triager output must be a JSON object with `outcome`, `note`, and `vendors` fields.',
    );
  }

  if (
    (parsed.outcome !== 'clean' &&
      parsed.outcome !== 'needs_patch' &&
      parsed.outcome !== 'patched') ||
    typeof parsed.note !== 'string' ||
    !Array.isArray(parsed.vendors) ||
    !parsed.vendors.every((value) => typeof value === 'string')
  ) {
    throw new Error(
      'AI review triager output must be JSON with `outcome`, string `note`, and string[] `vendors` fields.',
    );
  }

  return {
    actionSummary: parseOptionalString(parsed.action_summary),
    note: parsed.note,
    nonActionSummary: parseOptionalString(parsed.non_action_summary),
    outcome: parsed.outcome,
    vendors: parsed.vendors,
  };
}

function summarizeReviewMessage(message: string): string {
  const normalized = message.replace(/\s+/g, ' ').trim();
  return normalized.length > 180
    ? `${normalized.slice(0, 177).trimEnd()}...`
    : normalized;
}

export function parseResolveReviewThreadOutput(output: string): {
  message?: string;
  resolved: boolean;
} {
  let parsed: unknown;

  try {
    parsed = JSON.parse(output);
  } catch (error) {
    throw new Error(
      `GitHub review-thread resolution must emit JSON. ${formatError(error)}`.trim(),
      {
        cause: error,
      },
    );
  }

  if (!isRecord(parsed)) {
    throw new Error(
      'GitHub review-thread resolution output must be a JSON object.',
    );
  }

  if (Array.isArray(parsed.errors) && parsed.errors.length > 0) {
    const firstError = parsed.errors.find(isRecord);
    return {
      resolved: false,
      message: summarizeReviewMessage(
        typeof firstError?.message === 'string'
          ? firstError.message
          : 'GitHub reported a review-thread resolution error.',
      ),
    };
  }

  const thread =
    isRecord(parsed.data) &&
    isRecord(parsed.data.resolveReviewThread) &&
    isRecord(parsed.data.resolveReviewThread.thread)
      ? parsed.data.resolveReviewThread.thread
      : undefined;

  if (thread?.isResolved === true) {
    return { resolved: true };
  }

  return {
    resolved: false,
    message: 'GitHub did not confirm that the review thread was resolved.',
  };
}

const THREAD_REPLY_BEFORE_RESOLVE =
  'Addressed during patch phase — see PR body for full finding disposition.';

function sanitizeThreadReplyBody(body: string): string {
  return body.replace(/\s+/g, ' ').trim();
}

type ReviewCoreDependencies = {
  relativeToRepo: (cwd: string, absolutePath: string) => string;
  replyToReviewThread?: (
    worktreePath: string,
    databaseId: number,
    body: string,
  ) => void;
  resolveReviewFetcher: () => string;
  resolveReviewThread: (worktreePath: string, threadId: string) => string;
  resolveReviewTriager: () => string;
  runProcess: (cwd: string, cmd: string[]) => string;
};

export type TicketReviewDependencies = {
  ensureBranchPushed?: (cwd: string, branch: string) => void;
  fetcher?: (worktreePath: string, prNumber: number) => AiReviewFetcherResult;
  now?: () => number;
  replyToReviewThread?: ReviewCoreDependencies['replyToReviewThread'];
  resolveThreads?: (
    worktreePath: string,
    comments: AiReviewComment[],
  ) => AiReviewThreadResolution[];
  sleep?: (milliseconds: number) => Promise<void>;
  triager?: (
    worktreePath: string,
    artifactJsonPath: string,
  ) => AiReviewTriagerResult;
  updatePullRequestBody?: (
    state: DeliveryState,
    ticket: TicketState,
  ) => void | Promise<void>;
} & ReviewCoreDependencies;

export type StandaloneAiReviewDependencies = Pick<
  TicketReviewDependencies,
  | 'fetcher'
  | 'now'
  | 'replyToReviewThread'
  | 'resolveThreads'
  | 'sleep'
  | 'triager'
> &
  ReviewCoreDependencies & {
    previousOutcome?: ReviewOutcome;
    pullRequest?: StandalonePullRequest;
    resolveStandalonePullRequest: (
      cwd: string,
      prNumber?: number,
    ) => StandalonePullRequest;
    updatePullRequestBody?: (
      cwd: string,
      pullRequest: StandalonePullRequest,
      result: StandaloneAiReviewResult,
    ) => void | Promise<void>;
    writeNote?: (
      cwd: string,
      prNumber: number,
      result: StandaloneAiReviewResult,
    ) => Promise<void>;
  };

export type PollForAiReviewResult =
  | {
      status: 'triage_ready';
      result: AiReviewFetcherResult;
      effectiveMaxWaitMinutes: number;
    }
  | {
      status: 'partial_timeout';
      result: AiReviewFetcherResult;
      incompleteAgents: string[];
      effectiveMaxWaitMinutes: number;
    }
  | {
      status: 'clean_timeout';
      incompleteAgents?: string[];
      effectiveMaxWaitMinutes: number;
    };

type DetectedReviewProcessingResult = {
  fetchArtifactPath: string;
  incompleteAgents?: string[];
  note: string;
  outcome: ReviewResult;
  reviewedHeadSha?: string;
  recordedAt: string;
  triageArtifactPath: string;
};

type CleanReviewProcessingResult = {
  incompleteAgents?: string[];
  note: string;
  outcome: ReviewResult;
  recordedAt: string;
};

function runAiReviewFetcher(
  worktreePath: string,
  prNumber: number,
  dependencies: ReviewCoreDependencies,
): AiReviewFetcherResult {
  const fetcher = dependencies.resolveReviewFetcher();
  const output = dependencies.runProcess(worktreePath, [
    fetcher,
    String(prNumber),
  ]);
  return parseAiReviewFetcherOutput(output);
}

function runAiReviewTriager(
  worktreePath: string,
  artifactJsonPath: string,
  dependencies: ReviewCoreDependencies,
): AiReviewTriagerResult {
  const triager = dependencies.resolveReviewTriager();
  const output = dependencies.runProcess(worktreePath, [
    triager,
    artifactJsonPath,
  ]);
  return parseAiReviewTriagerOutput(output);
}

function isTerminalReviewAgent(
  agent: Pick<AiReviewAgentResult, 'state'>,
): boolean {
  return agent.state === 'completed' || agent.state === 'findings_detected';
}

function hasActionableReviewFindings(result: AiReviewFetcherResult): boolean {
  return result.agents.some((agent) => agent.state === 'findings_detected');
}

function hasInFlightReviewAgents(result: AiReviewFetcherResult): boolean {
  return result.agents.some((agent) => agent.state === 'started');
}

function allDetectedAgentsReadyForTriage(
  result: AiReviewFetcherResult,
): boolean {
  return (
    result.agents.length > 0 &&
    result.agents.every((agent) => isTerminalReviewAgent(agent))
  );
}

function listIncompleteReviewAgents(result: AiReviewFetcherResult): string[] {
  return result.agents
    .filter((agent) => agent.state === 'started')
    .map((agent) => agent.agent);
}

function formatReviewAgentList(agents: string[]): string {
  return agents.join(', ');
}

function formatPartialAiReviewTimeoutNote(
  maxWaitMinutes: number,
  agents: string[],
): string {
  return `AI review reached the ${maxWaitMinutes}-minute limit while waiting on: ${formatReviewAgentList(agents)}. Triage the captured findings and rerun manually if needed.`;
}

function formatIncompleteAiReviewWithoutFindingsNote(
  maxWaitMinutes: number,
  agents: string[],
): string {
  return `AI review reached the ${maxWaitMinutes}-minute limit while waiting on: ${formatReviewAgentList(agents)}. No actionable findings were captured. Rerun manually if needed.`;
}

function formatNoAiReviewFeedbackNote(maxWaitMinutes: number): string {
  return `No AI review feedback was detected within the ${maxWaitMinutes}-minute polling window.`;
}

function mergeReviewOutcome(
  previous: ReviewResult | undefined,
  next: ReviewResult | undefined,
): ReviewOutcome | undefined {
  if (previous === 'patched' || next === 'patched') {
    return 'patched';
  }

  if (previous === 'clean' || next === 'clean') {
    return 'clean';
  }

  return undefined;
}

function accumulateReviewOutcome(
  previous: ReviewResult | undefined,
  next: ReviewResult,
): ReviewResult | undefined {
  if (next === 'clean' || next === 'patched') {
    return mergeReviewOutcome(previous, next) ?? next;
  }

  return next;
}

function accumulateTicketReviewOutcome(
  previous: ReviewResult | undefined,
  next: ReviewResult,
): ReviewResult | undefined {
  return accumulateReviewOutcome(previous, next);
}

function mapStandaloneReviewOutcome(outcome: ReviewResult): ReviewResult {
  return outcome === 'needs_patch' ? 'operator_input_needed' : outcome;
}

function formatCumulativePatchedReviewNote(note: string | undefined): string {
  if (note === undefined || note.length === 0) {
    return 'Earlier review cycles led to prudent follow-up patches; the latest review pass found no additional prudent changes.';
  }

  if (note.includes('no additional prudent follow-up changes')) {
    return note;
  }

  return `${note} Earlier review cycles led to prudent follow-up patches, and the latest review pass found no additional prudent follow-up changes.`;
}

function formatAccumulatedReviewNote(
  previous: ReviewResult | undefined,
  next: ReviewResult,
  note: string | undefined,
): string | undefined {
  if (previous === 'patched' && next === 'clean') {
    return formatCumulativePatchedReviewNote(note);
  }

  return note;
}

function defaultFinalReviewNote(
  outcome: ReviewResult,
  note: string | undefined,
  previousNote: string | undefined,
): string | undefined {
  if (note !== undefined) {
    return note;
  }

  if (outcome === 'clean') {
    return 'External AI review completed without prudent follow-up changes.';
  }

  return previousNote;
}

function formatNoFeedbackReviewNote(
  previous: ReviewResult | undefined,
  maxWaitMinutes: number,
): string {
  return (
    formatAccumulatedReviewNote(
      previous,
      'clean',
      formatNoAiReviewFeedbackNote(maxWaitMinutes),
    ) ?? formatNoAiReviewFeedbackNote(maxWaitMinutes)
  );
}

async function readStandaloneAiReviewOutcome(
  cwd: string,
  prNumber: number,
): Promise<ReviewOutcome | undefined> {
  const triageArtifactPath = resolve(
    cwd,
    STANDALONE_TRIAGE_ARTIFACT_DIR,
    `pr-${prNumber}`,
    'review.triage.json',
  );

  if (!existsSync(triageArtifactPath)) {
    return undefined;
  }

  const triageArtifact = readTriageArtifact(triageArtifactPath);
  if (
    triageArtifact?.outcome === 'clean' ||
    triageArtifact?.outcome === 'patched'
  ) {
    return triageArtifact.outcome;
  }

  return undefined;
}

function shouldResolveDetectedReviewThreads(
  mode: 'standalone' | 'ticketed',
  outcome: ReviewResult,
): boolean {
  if (mode === 'ticketed') {
    return outcome === 'patched';
  }

  return outcome === 'patched';
}

function defaultSleep(milliseconds: number): Promise<void> {
  return new Promise((resolveSleep) => {
    setTimeout(resolveSleep, milliseconds);
  });
}

export function resolveNativeReviewThreads(
  worktreePath: string,
  comments: AiReviewComment[],
  dependencies: ReviewCoreDependencies,
): AiReviewThreadResolution[] {
  const resolutions: AiReviewThreadResolution[] = [];
  const seen = new Set<string>();

  for (const comment of comments) {
    if (
      comment.channel !== 'inline_review' ||
      (comment.kind !== 'finding' && comment.isOutdated !== true) ||
      comment.isResolved === true ||
      !comment.threadId ||
      seen.has(comment.threadId)
    ) {
      continue;
    }

    seen.add(comment.threadId);

    if (comment.threadViewerCanResolve === false) {
      resolutions.push({
        status: 'unresolvable',
        threadId: comment.threadId,
        url: comment.url,
        vendor: comment.vendor,
        message: 'GitHub did not expose this review thread as resolvable.',
      });
      continue;
    }

    if (dependencies.replyToReviewThread && comment.databaseId !== undefined) {
      try {
        dependencies.replyToReviewThread(
          worktreePath,
          comment.databaseId,
          sanitizeThreadReplyBody(THREAD_REPLY_BEFORE_RESOLVE),
        );
      } catch {
        // Reply is best-effort; resolution still proceeds.
      }
    }

    try {
      const response = dependencies.resolveReviewThread(
        worktreePath,
        comment.threadId,
      );
      const parsed = parseResolveReviewThreadOutput(response);

      if (!parsed.resolved) {
        resolutions.push({
          status: 'failed',
          threadId: comment.threadId,
          url: comment.url,
          vendor: comment.vendor,
          message: parsed.message,
        });
        continue;
      }

      resolutions.push({
        status: 'resolved',
        threadId: comment.threadId,
        url: comment.url,
        vendor: comment.vendor,
      });
    } catch (error) {
      const message = summarizeReviewMessage(formatError(error));
      resolutions.push({
        status: message.includes('already resolved')
          ? 'already_resolved'
          : 'failed',
        threadId: comment.threadId,
        url: comment.url,
        vendor: comment.vendor,
        message,
      });
    }
  }

  return resolutions;
}

export async function pollForAiReview(
  worktreePath: string,
  prNumber: number,
  profile: ReviewPollingProfile,
  pollWindowStartedAt: number,
  dependencies: Pick<TicketReviewDependencies, 'fetcher' | 'now' | 'sleep'> &
    ReviewCoreDependencies,
): Promise<PollForAiReviewResult> {
  const now = dependencies.now ?? Date.now;
  const sleepFn = dependencies.sleep ?? defaultSleep;
  const fetcher =
    dependencies.fetcher ??
    ((nextWorktreePath: string, nextPrNumber: number) =>
      runAiReviewFetcher(nextWorktreePath, nextPrNumber, dependencies));
  const intervalMinutes = profile.intervalMinutes;
  const maxWaitMinutes = profile.maxWaitMinutes;
  const checks = buildReviewPollCheckMinutes(intervalMinutes, maxWaitMinutes);
  const extendedMaxWaitMinutes = computeExtendedReviewPollMaxWaitMinutes(
    intervalMinutes,
    maxWaitMinutes,
  );
  let extended = false;

  for (let index = 0; index < checks.length; index += 1) {
    const checkMinute = checks[index]!;
    const dueAt = pollWindowStartedAt + checkMinute * 60_000;
    const remaining = dueAt - now();

    if (remaining > 0) {
      await sleepFn(remaining);
    }

    const result = fetcher(worktreePath, prNumber);

    if (!result.detected) {
      continue;
    }

    if (allDetectedAgentsReadyForTriage(result)) {
      return {
        status: 'triage_ready',
        result,
        effectiveMaxWaitMinutes: extended
          ? extendedMaxWaitMinutes
          : maxWaitMinutes,
      };
    }

    if (
      profile.extendByOneInterval &&
      !extended &&
      checkMinute === maxWaitMinutes &&
      hasInFlightReviewAgents(result)
    ) {
      checks.push(extendedMaxWaitMinutes);
      extended = true;
      continue;
    }

    // At the final wait boundary (extended when extendByOneInterval is true,
    // or maxWaitMinutes when not extending), surface partial/clean timeout.
    const isAtFinalBoundary =
      checkMinute === extendedMaxWaitMinutes ||
      (!profile.extendByOneInterval && checkMinute === maxWaitMinutes);

    if (isAtFinalBoundary && hasInFlightReviewAgents(result)) {
      const incompleteAgents = listIncompleteReviewAgents(result);
      const effectiveMax = profile.extendByOneInterval
        ? extendedMaxWaitMinutes
        : maxWaitMinutes;

      if (hasActionableReviewFindings(result)) {
        return {
          status: 'partial_timeout',
          result,
          incompleteAgents,
          effectiveMaxWaitMinutes: effectiveMax,
        };
      }

      return {
        status: 'clean_timeout',
        incompleteAgents,
        effectiveMaxWaitMinutes: effectiveMax,
      };
    }
  }

  return {
    status: 'clean_timeout',
    effectiveMaxWaitMinutes: maxWaitMinutes,
  };
}

async function writeAiReviewArtifacts(
  artifactStemPath: string,
  result: AiReviewFetcherResult,
  fetchedAt: string,
): Promise<{ fetchArtifactPath: string; triageArtifactPath: string }> {
  const { fetchArtifactPath, triageArtifactPath } =
    buildReviewArtifactPaths(artifactStemPath);

  const fetchArtifact: AiReviewFetchArtifact = {
    schemaVersion: 1,
    fetchedAt,
    reviewedHeadSha: result.reviewedHeadSha,
    detected: result.detected,
    vendors: result.vendors,
    agents: result.agents,
    comments: result.comments,
  };

  await writeFetchArtifact(fetchArtifactPath, fetchArtifact);

  return {
    fetchArtifactPath,
    triageArtifactPath,
  };
}

async function processDetectedAiReview(options: {
  artifactStemPath: string;
  detectedReview: AiReviewFetcherResult;
  effectiveMaxWaitMinutes: number;
  incompleteAgents?: string[];
  mapOutcome?: (outcome: ReviewResult) => ReviewResult;
  mode: 'standalone' | 'ticketed';
  previousOutcome: ReviewResult | undefined;
  resolveThreads: (
    worktreePath: string,
    comments: AiReviewComment[],
  ) => AiReviewThreadResolution[];
  triager: (
    worktreePath: string,
    artifactJsonPath: string,
  ) => AiReviewTriagerResult;
  worktreePath: string;
}): Promise<DetectedReviewProcessingResult> {
  const fetchedAt = new Date().toISOString();
  const artifacts = await writeAiReviewArtifacts(
    options.artifactStemPath,
    options.detectedReview,
    fetchedAt,
  );
  const triageResult = options.triager(
    options.worktreePath,
    artifacts.fetchArtifactPath,
  );
  const latestOutcome =
    options.mapOutcome?.(triageResult.outcome) ?? triageResult.outcome;
  const threadResolutions = shouldResolveDetectedReviewThreads(
    options.mode,
    latestOutcome,
  )
    ? options.resolveThreads(
        options.worktreePath,
        options.detectedReview.comments,
      )
    : [];
  const recordedAt = new Date().toISOString();
  const triageArtifact: AiReviewTriageArtifact = {
    schemaVersion: 1,
    recordedAt,
    reviewedHeadSha: options.detectedReview.reviewedHeadSha,
    outcome:
      accumulateReviewOutcome(options.previousOutcome, latestOutcome) ??
      latestOutcome,
    note: options.incompleteAgents?.length
      ? formatPartialAiReviewTimeoutNote(
          options.effectiveMaxWaitMinutes,
          options.incompleteAgents,
        )
      : (formatAccumulatedReviewNote(
          options.previousOutcome,
          latestOutcome,
          triageResult.note,
        ) ?? triageResult.note),
    actionSummary: triageResult.actionSummary,
    nonActionSummary: triageResult.nonActionSummary,
    incompleteAgents: options.incompleteAgents,
    threadResolutions:
      threadResolutions.length > 0 ? threadResolutions : undefined,
  };
  await writeTriageArtifact(artifacts.triageArtifactPath, triageArtifact);

  return {
    fetchArtifactPath: artifacts.fetchArtifactPath,
    incompleteAgents: options.incompleteAgents,
    note: triageArtifact.note,
    outcome: triageArtifact.outcome,
    reviewedHeadSha: options.detectedReview.reviewedHeadSha,
    recordedAt,
    triageArtifactPath: artifacts.triageArtifactPath,
  };
}

function processCleanAiReview(options: {
  effectiveMaxWaitMinutes: number;
  incompleteAgents?: string[];
  maxWaitMinutes: number;
  previousOutcome: ReviewResult | undefined;
}): CleanReviewProcessingResult {
  const recordedAt = new Date().toISOString();
  return {
    incompleteAgents: options.incompleteAgents,
    note: options.incompleteAgents?.length
      ? formatIncompleteAiReviewWithoutFindingsNote(
          options.effectiveMaxWaitMinutes,
          options.incompleteAgents,
        )
      : formatNoFeedbackReviewNote(
          options.previousOutcome,
          options.maxWaitMinutes,
        ),
    outcome:
      accumulateReviewOutcome(options.previousOutcome, 'clean') ?? 'clean',
    recordedAt,
  };
}

async function writeCleanTriageArtifact(
  artifactStemPath: string,
  input: {
    incompleteAgents?: string[];
    note: string;
    outcome: ReviewResult;
    recordedAt: string;
    reviewedHeadSha?: string;
  },
): Promise<string> {
  const { triageArtifactPath } = buildReviewArtifactPaths(artifactStemPath);
  await writeTriageArtifact(triageArtifactPath, {
    schemaVersion: 1,
    recordedAt: input.recordedAt,
    reviewedHeadSha: input.reviewedHeadSha,
    outcome: input.outcome,
    note: input.note,
    incompleteAgents: input.incompleteAgents,
  });
  return triageArtifactPath;
}

async function commitPrReviewArtifactsAfterRecordReview(
  repoRoot: string,
  ticketId: string,
  absolutePaths: string[],
  relativeToRepo: (cwd: string, absolutePath: string) => string,
  runProcess: (cwd: string, cmd: string[]) => string,
): Promise<boolean> {
  try {
    runProcess(repoRoot, ['git', 'rev-parse', '--git-dir']);
  } catch {
    return false;
  }

  const relPaths: string[] = [];
  for (const abs of absolutePaths) {
    if (!existsSync(abs)) {
      continue;
    }

    const rel = relativeToRepo(repoRoot, abs);
    if (rel.length > 0) {
      relPaths.push(rel);
    }
  }

  const unique = [...new Set(relPaths)];
  if (unique.length === 0) {
    return false;
  }

  for (const rel of unique) {
    try {
      runProcess(repoRoot, ['git', 'add', '--', rel]);
    } catch (error) {
      console.warn(
        `Could not stage review artifact ${rel} for commit: ${formatError(error)}`,
      );
    }
  }

  const stagedNames = (() => {
    try {
      return runProcess(repoRoot, ['git', 'diff', '--cached', '--name-only']);
    } catch {
      return '';
    }
  })();

  if (!stagedNames.trim()) {
    return false;
  }

  try {
    runProcess(repoRoot, [
      'git',
      'commit',
      '-m',
      `chore(delivery): commit PR review artifacts after record-review ${ticketId}`,
    ]);
    return true;
  } catch (error) {
    console.warn(
      `Could not commit staged review artifacts for ${ticketId}: ${formatError(error)}`,
    );
    return false;
  }
}

async function applyTicketReviewUpdate(
  cwd: string,
  state: DeliveryState,
  ticketId: string,
  updateTicket: (ticket: TicketState) => TicketState,
  dependencies: Pick<
    TicketReviewDependencies,
    | 'updatePullRequestBody'
    | 'relativeToRepo'
    | 'runProcess'
    | 'ensureBranchPushed'
  >,
): Promise<DeliveryState> {
  const updatedTickets = state.tickets.map((ticket) =>
    ticket.id === ticketId ? updateTicket(ticket) : ticket,
  );
  const updatedIndex = updatedTickets.findIndex(
    (ticket) => ticket.id === ticketId,
  );

  if (updatedIndex === -1) {
    throw new Error(`Unknown ticket ${ticketId}.`);
  }

  const updatedTarget = updatedTickets[updatedIndex]!;
  const isLastTicket = updatedIndex === updatedTickets.length - 1;
  const finalizedTickets: TicketState[] =
    isLastTicket &&
    updatedTarget.status === 'reviewed' &&
    (updatedTarget.reviewOutcome === 'clean' ||
      updatedTarget.reviewOutcome === 'patched')
      ? updatedTickets.map((ticket, index) =>
          index === updatedIndex ? { ...ticket, status: 'done' } : ticket,
        )
      : updatedTickets;

  const nextState: DeliveryState = {
    ...state,
    tickets: finalizedTickets,
  };
  const persistedTarget = nextState.tickets[updatedIndex]!;
  const triageArtifactPath = persistedTarget.reviewTriageArtifactPath
    ? resolve(cwd, persistedTarget.reviewTriageArtifactPath)
    : undefined;

  try {
    await dependencies.updatePullRequestBody?.(nextState, persistedTarget);
    if (triageArtifactPath) {
      await updateTriageArtifact(triageArtifactPath, (current) => ({
        ...current,
        schemaVersion: 1,
        recordedAt:
          current?.recordedAt ??
          persistedTarget.reviewRecordedAt ??
          new Date().toISOString(),
        outcome: current?.outcome ?? persistedTarget.reviewOutcome ?? 'clean',
        note:
          current?.note ??
          'External AI review completed without prudent follow-up changes.',
        reviewedHeadSha:
          current?.reviewedHeadSha ?? persistedTarget.reviewHeadSha,
        prBodyRefresh: {
          attemptedAt: new Date().toISOString(),
          status: 'updated',
        },
      }));
    }
  } catch (error) {
    console.warn(
      `Review was recorded locally for ${persistedTarget.id}, but PR body update failed: ${formatError(error)}`,
    );
    if (triageArtifactPath) {
      await updateTriageArtifact(triageArtifactPath, (current) => ({
        ...current,
        schemaVersion: 1,
        recordedAt:
          current?.recordedAt ??
          persistedTarget.reviewRecordedAt ??
          new Date().toISOString(),
        outcome: current?.outcome ?? persistedTarget.reviewOutcome ?? 'clean',
        note:
          current?.note ??
          'External AI review completed without prudent follow-up changes.',
        reviewedHeadSha:
          current?.reviewedHeadSha ?? persistedTarget.reviewHeadSha,
        prBodyRefresh: {
          attemptedAt: new Date().toISOString(),
          status: 'failed',
          message: formatError(error),
        },
      }));
    }
  }

  const fetchPath = persistedTarget.reviewFetchArtifactPath
    ? resolve(cwd, persistedTarget.reviewFetchArtifactPath)
    : undefined;
  const triagePath = persistedTarget.reviewTriageArtifactPath
    ? resolve(cwd, persistedTarget.reviewTriageArtifactPath)
    : undefined;
  const artifactPaths = [triagePath, fetchPath].filter(
    (p): p is string => p !== undefined,
  );
  if (artifactPaths.length > 0) {
    const committed = await commitPrReviewArtifactsAfterRecordReview(
      cwd,
      ticketId,
      artifactPaths,
      dependencies.relativeToRepo,
      dependencies.runProcess,
    );
    if (committed) {
      dependencies.ensureBranchPushed?.(
        persistedTarget.worktreePath,
        persistedTarget.branch,
      );
    }
  }

  return nextState;
}

async function persistStandaloneAiReviewResult(
  cwd: string,
  pullRequest: StandalonePullRequest,
  result: StandaloneAiReviewResult,
  dependencies: Pick<
    StandaloneAiReviewDependencies,
    'updatePullRequestBody' | 'writeNote'
  >,
): Promise<StandaloneAiReviewResult> {
  const writeNote = dependencies.writeNote ?? writeStandaloneAiReviewNote;

  await writeNote(cwd, pullRequest.number, result);
  const triageArtifactPath = result.triageArtifactPath
    ? resolve(cwd, result.triageArtifactPath)
    : undefined;
  try {
    await dependencies.updatePullRequestBody?.(cwd, pullRequest, result);
    if (triageArtifactPath) {
      await updateTriageArtifact(triageArtifactPath, (current) => ({
        ...current,
        schemaVersion: 1,
        recordedAt:
          current?.recordedAt ?? result.recordedAt ?? new Date().toISOString(),
        outcome: current?.outcome ?? result.outcome,
        note: current?.note ?? result.note,
        reviewedHeadSha: current?.reviewedHeadSha ?? result.reviewedHeadSha,
        prBodyRefresh: {
          attemptedAt: new Date().toISOString(),
          status: 'updated',
        },
      }));
    }
  } catch (error) {
    console.warn(
      `Standalone AI review was recorded locally for PR #${pullRequest.number}, but PR body update failed: ${formatError(error)}`,
    );
    if (triageArtifactPath) {
      await updateTriageArtifact(triageArtifactPath, (current) => ({
        ...current,
        schemaVersion: 1,
        recordedAt:
          current?.recordedAt ?? result.recordedAt ?? new Date().toISOString(),
        outcome: current?.outcome ?? result.outcome,
        note: current?.note ?? result.note,
        reviewedHeadSha: current?.reviewedHeadSha ?? result.reviewedHeadSha,
        prBodyRefresh: {
          attemptedAt: new Date().toISOString(),
          status: 'failed',
          message: formatError(error),
        },
      }));
    }
  }

  return result;
}

export type AiReviewLifecycleHooks<T> = {
  onTriageOrPartial: (
    reviewPollResult: Extract<
      PollForAiReviewResult,
      { status: 'triage_ready' | 'partial_timeout' }
    >,
  ) => Promise<T>;
  onCleanTimeout: (reviewPollResult: PollForAiReviewResult) => Promise<T>;
};

export async function runAiReviewLifecycleWithAdapters<T>(input: {
  profile: ReviewPollingProfile;
  worktreePath: string;
  prNumber: number;
  pollWindowStartedAt: number;
  dependencies: Pick<TicketReviewDependencies, 'fetcher' | 'now' | 'sleep'> &
    ReviewCoreDependencies;
  onTriageOrPartial: AiReviewLifecycleHooks<T>['onTriageOrPartial'];
  onCleanTimeout: AiReviewLifecycleHooks<T>['onCleanTimeout'];
}): Promise<T> {
  const reviewPollResult = await pollForAiReview(
    input.worktreePath,
    input.prNumber,
    input.profile,
    input.pollWindowStartedAt,
    input.dependencies,
  );

  if (
    reviewPollResult.status === 'triage_ready' ||
    reviewPollResult.status === 'partial_timeout'
  ) {
    return input.onTriageOrPartial(reviewPollResult);
  }

  return input.onCleanTimeout(reviewPollResult);
}

export async function runTicketReviewLifecycle(
  state: DeliveryState,
  cwd: string,
  ticketId: string | undefined,
  dependencies: TicketReviewDependencies,
): Promise<DeliveryState> {
  const target = state.tickets.find((ticket) =>
    ticketId ? ticket.id === ticketId : ticket.status === 'in_review',
  );

  if (!target || target.status !== 'in_review' || !target.prNumber) {
    throw new Error('No in-review ticket with an open PR was found.');
  }

  const now = dependencies.now ?? Date.now;
  const triager =
    dependencies.triager ??
    ((worktreePath: string, artifactJsonPath: string) =>
      runAiReviewTriager(worktreePath, artifactJsonPath, dependencies));
  const resolveThreads =
    dependencies.resolveThreads ??
    ((worktreePath: string, comments: AiReviewComment[]) =>
      resolveNativeReviewThreads(worktreePath, comments, dependencies));
  const { pollWindowStartedAt, pollWindowStartedAtIso } =
    resolveReviewPollWindowStart(target.prOpenedAt, now);
  const profile = resolveDeliveryReviewPollingProfile(state);

  return runAiReviewLifecycleWithAdapters({
    profile,
    worktreePath: target.worktreePath,
    prNumber: target.prNumber,
    pollWindowStartedAt,
    dependencies,
    async onTriageOrPartial(reviewPollResult) {
      const processedReview = await processDetectedAiReview({
        artifactStemPath: resolve(
          cwd,
          state.reviewsDirPath,
          buildPrReviewArtifactStem(target.id),
        ),
        detectedReview: reviewPollResult.result,
        effectiveMaxWaitMinutes: reviewPollResult.effectiveMaxWaitMinutes,
        incompleteAgents:
          reviewPollResult.status === 'partial_timeout'
            ? reviewPollResult.incompleteAgents
            : undefined,
        mode: 'ticketed',
        previousOutcome: target.reviewOutcome,
        resolveThreads,
        triager,
        worktreePath: target.worktreePath,
      });
      const nextStatus =
        processedReview.outcome === 'needs_patch' ? 'needs_patch' : 'reviewed';
      return applyTicketReviewUpdate(
        cwd,
        state,
        target.id,
        (ticket) => ({
          ...ticket,
          prOpenedAt: ticket.prOpenedAt ?? pollWindowStartedAtIso,
          status: nextStatus,
          reviewFetchArtifactPath: dependencies.relativeToRepo(
            cwd,
            processedReview.fetchArtifactPath,
          ),
          reviewTriageArtifactPath: dependencies.relativeToRepo(
            cwd,
            processedReview.triageArtifactPath,
          ),
          reviewHeadSha: processedReview.reviewedHeadSha,
          reviewRecordedAt: processedReview.recordedAt,
          reviewOutcome: accumulateTicketReviewOutcome(
            ticket.reviewOutcome,
            processedReview.outcome,
          ),
        }),
        dependencies,
      );
    },
    async onCleanTimeout(reviewPollResult) {
      const processedReview = processCleanAiReview({
        effectiveMaxWaitMinutes: reviewPollResult.effectiveMaxWaitMinutes,
        incompleteAgents:
          reviewPollResult.status === 'clean_timeout'
            ? reviewPollResult.incompleteAgents
            : undefined,
        maxWaitMinutes: profile.maxWaitMinutes,
        previousOutcome: target.reviewOutcome,
      });
      const triageArtifactPath = await writeCleanTriageArtifact(
        resolve(
          cwd,
          state.reviewsDirPath,
          buildPrReviewArtifactStem(target.id),
        ),
        {
          incompleteAgents: processedReview.incompleteAgents,
          note: processedReview.note,
          outcome: processedReview.outcome,
          recordedAt: processedReview.recordedAt,
          reviewedHeadSha: target.reviewHeadSha,
        },
      );
      return applyTicketReviewUpdate(
        cwd,
        state,
        target.id,
        (ticket) => ({
          ...ticket,
          prOpenedAt: ticket.prOpenedAt ?? pollWindowStartedAtIso,
          status: 'reviewed',
          reviewFetchArtifactPath: ticket.reviewFetchArtifactPath,
          reviewTriageArtifactPath: dependencies.relativeToRepo(
            cwd,
            triageArtifactPath,
          ),
          reviewHeadSha: ticket.reviewHeadSha,
          reviewRecordedAt: processedReview.recordedAt,
          reviewOutcome: accumulateTicketReviewOutcome(
            ticket.reviewOutcome,
            processedReview.outcome,
          ),
        }),
        dependencies,
      );
    },
  });
}

export async function runReconcileLateTicketReview(
  state: DeliveryState,
  cwd: string,
  ticketId: string,
  dependencies: TicketReviewDependencies,
): Promise<DeliveryState> {
  const target = state.tickets.find((ticket) => ticket.id === ticketId);

  if (!target) {
    throw new Error(`Unknown ticket ${ticketId}.`);
  }

  if (target.status !== 'done') {
    throw new Error(
      `Ticket ${ticketId} must be done before ticket PR triage (use poll-review while the ticket is in review).`,
    );
  }

  if (!target.prNumber) {
    throw new Error(
      `Ticket ${ticketId} has no PR number; cannot reconcile review.`,
    );
  }

  const now = dependencies.now ?? Date.now;
  const triager =
    dependencies.triager ??
    ((worktreePath: string, artifactJsonPath: string) =>
      runAiReviewTriager(worktreePath, artifactJsonPath, dependencies));
  const resolveThreads =
    dependencies.resolveThreads ??
    ((worktreePath: string, comments: AiReviewComment[]) =>
      resolveNativeReviewThreads(worktreePath, comments, dependencies));
  const profile = RECONCILE_REVIEW_POLLING_PROFILE;
  const { pollWindowStartedAt: resolvedStart, pollWindowStartedAtIso } =
    resolveReviewPollWindowStart(target.prOpenedAt, now);
  const pollWindowStartedAt = Math.min(
    resolvedStart,
    now() - (profile.intervalMinutes + 1) * 60_000,
  );

  return runAiReviewLifecycleWithAdapters({
    profile,
    worktreePath: target.worktreePath,
    prNumber: target.prNumber,
    pollWindowStartedAt,
    dependencies,
    async onTriageOrPartial(reviewPollResult) {
      const processedReview = await processDetectedAiReview({
        artifactStemPath: resolve(
          cwd,
          state.reviewsDirPath,
          buildPrReviewArtifactStem(target.id),
        ),
        detectedReview: reviewPollResult.result,
        effectiveMaxWaitMinutes: reviewPollResult.effectiveMaxWaitMinutes,
        incompleteAgents:
          reviewPollResult.status === 'partial_timeout'
            ? reviewPollResult.incompleteAgents
            : undefined,
        mode: 'ticketed',
        previousOutcome: target.reviewOutcome,
        resolveThreads,
        triager,
        worktreePath: target.worktreePath,
      });
      return applyTicketReviewUpdate(
        cwd,
        state,
        target.id,
        (ticket) => ({
          ...ticket,
          prOpenedAt: ticket.prOpenedAt ?? pollWindowStartedAtIso,
          status: 'done',
          reviewFetchArtifactPath: dependencies.relativeToRepo(
            cwd,
            processedReview.fetchArtifactPath,
          ),
          reviewTriageArtifactPath: dependencies.relativeToRepo(
            cwd,
            processedReview.triageArtifactPath,
          ),
          reviewHeadSha: processedReview.reviewedHeadSha,
          reviewRecordedAt: processedReview.recordedAt,
          reviewOutcome: accumulateTicketReviewOutcome(
            ticket.reviewOutcome,
            processedReview.outcome,
          ),
        }),
        dependencies,
      );
    },
    async onCleanTimeout(reviewPollResult) {
      const processedReview = processCleanAiReview({
        effectiveMaxWaitMinutes: reviewPollResult.effectiveMaxWaitMinutes,
        incompleteAgents:
          reviewPollResult.status === 'clean_timeout'
            ? reviewPollResult.incompleteAgents
            : undefined,
        maxWaitMinutes: profile.maxWaitMinutes,
        previousOutcome: target.reviewOutcome,
      });
      const triageArtifactPath = await writeCleanTriageArtifact(
        resolve(
          cwd,
          state.reviewsDirPath,
          buildPrReviewArtifactStem(target.id),
        ),
        {
          incompleteAgents: processedReview.incompleteAgents,
          note: processedReview.note,
          outcome: processedReview.outcome,
          recordedAt: processedReview.recordedAt,
          reviewedHeadSha: target.reviewHeadSha,
        },
      );
      return applyTicketReviewUpdate(
        cwd,
        state,
        target.id,
        (ticket) => ({
          ...ticket,
          prOpenedAt: ticket.prOpenedAt ?? pollWindowStartedAtIso,
          status: 'done',
          reviewFetchArtifactPath: ticket.reviewFetchArtifactPath,
          reviewTriageArtifactPath: dependencies.relativeToRepo(
            cwd,
            triageArtifactPath,
          ),
          reviewOutcome: accumulateTicketReviewOutcome(
            ticket.reviewOutcome,
            processedReview.outcome,
          ),
          reviewRecordedAt: processedReview.recordedAt,
        }),
        dependencies,
      );
    },
  });
}

export async function runStandaloneAiReviewLifecycle(
  cwd: string,
  prNumber: number | undefined,
  dependencies: StandaloneAiReviewDependencies,
): Promise<StandaloneAiReviewResult> {
  const pullRequest =
    dependencies.pullRequest ??
    dependencies.resolveStandalonePullRequest(cwd, prNumber);
  const previousOutcome =
    dependencies.previousOutcome ??
    (await readStandaloneAiReviewOutcome(cwd, pullRequest.number));
  const triager =
    dependencies.triager ??
    ((worktreePath: string, artifactJsonPath: string) =>
      runAiReviewTriager(worktreePath, artifactJsonPath, dependencies));
  const resolveThreads =
    dependencies.resolveThreads ??
    ((worktreePath: string, comments: AiReviewComment[]) =>
      resolveNativeReviewThreads(worktreePath, comments, dependencies));
  const now = dependencies.now ?? Date.now;
  const { pollWindowStartedAt } = resolveReviewPollWindowStart(
    pullRequest.createdAt,
    now,
  );
  const profile = DEFAULT_REVIEW_POLLING_PROFILE;

  return runAiReviewLifecycleWithAdapters({
    profile,
    worktreePath: cwd,
    prNumber: pullRequest.number,
    pollWindowStartedAt,
    dependencies,
    async onTriageOrPartial(reviewPollResult) {
      const processedReview = await processDetectedAiReview({
        artifactStemPath: resolve(
          cwd,
          STANDALONE_TRIAGE_ARTIFACT_DIR,
          `pr-${pullRequest.number}`,
          'review',
        ),
        detectedReview: reviewPollResult.result,
        effectiveMaxWaitMinutes: reviewPollResult.effectiveMaxWaitMinutes,
        incompleteAgents:
          reviewPollResult.status === 'partial_timeout'
            ? reviewPollResult.incompleteAgents
            : undefined,
        mapOutcome: mapStandaloneReviewOutcome,
        mode: 'standalone',
        previousOutcome,
        resolveThreads,
        triager,
        worktreePath: cwd,
      });
      const triageArtifact = readTriageArtifact(
        processedReview.triageArtifactPath,
      );
      const standaloneResult: StandaloneAiReviewResult = {
        actionSummary: triageArtifact?.actionSummary,
        comments: reviewPollResult.result.comments,
        fetchArtifactPath: dependencies.relativeToRepo(
          cwd,
          processedReview.fetchArtifactPath,
        ),
        incompleteAgents: processedReview.incompleteAgents,
        nonActionSummary: triageArtifact?.nonActionSummary,
        triageArtifactPath: dependencies.relativeToRepo(
          cwd,
          processedReview.triageArtifactPath,
        ),
        note: processedReview.note,
        outcome: processedReview.outcome,
        prNumber: pullRequest.number,
        prUrl: pullRequest.url,
        reviewedHeadSha: processedReview.reviewedHeadSha,
        recordedAt: processedReview.recordedAt,
        threadResolutions: triageArtifact?.threadResolutions,
        vendors: reviewPollResult.result.vendors,
      };
      return persistStandaloneAiReviewResult(
        cwd,
        pullRequest,
        standaloneResult,
        dependencies,
      );
    },
    async onCleanTimeout(reviewPollResult) {
      const processedReview = processCleanAiReview({
        effectiveMaxWaitMinutes: reviewPollResult.effectiveMaxWaitMinutes,
        incompleteAgents:
          reviewPollResult.status === 'clean_timeout'
            ? reviewPollResult.incompleteAgents
            : undefined,
        maxWaitMinutes: profile.maxWaitMinutes,
        previousOutcome,
      });
      const triageArtifactPath = await writeCleanTriageArtifact(
        resolve(
          cwd,
          STANDALONE_TRIAGE_ARTIFACT_DIR,
          `pr-${pullRequest.number}`,
          'review',
        ),
        {
          incompleteAgents: processedReview.incompleteAgents,
          note: processedReview.note,
          outcome: processedReview.outcome,
          recordedAt: processedReview.recordedAt,
        },
      );
      const existingFetchArtifactPath = buildReviewArtifactPaths(
        resolve(
          cwd,
          STANDALONE_TRIAGE_ARTIFACT_DIR,
          `pr-${pullRequest.number}`,
          'review',
        ),
      ).fetchArtifactPath;
      const standaloneResult: StandaloneAiReviewResult = {
        fetchArtifactPath: existsSync(existingFetchArtifactPath)
          ? dependencies.relativeToRepo(cwd, existingFetchArtifactPath)
          : undefined,
        incompleteAgents: processedReview.incompleteAgents,
        note: processedReview.note,
        outcome: processedReview.outcome,
        prNumber: pullRequest.number,
        prUrl: pullRequest.url,
        recordedAt: processedReview.recordedAt,
        triageArtifactPath: dependencies.relativeToRepo(
          cwd,
          triageArtifactPath,
        ),
        vendors: [],
      };
      return persistStandaloneAiReviewResult(
        cwd,
        pullRequest,
        standaloneResult,
        dependencies,
      );
    },
  });
}

export async function writeStandaloneAiReviewNote(
  cwd: string,
  prNumber: number,
  result: StandaloneAiReviewResult,
): Promise<void> {
  const notePath = resolve(
    cwd,
    STANDALONE_TRIAGE_ARTIFACT_DIR,
    `pr-${prNumber}`,
    'note.md',
  );
  await mkdir(dirname(notePath), { recursive: true });
  await writeFile(
    notePath,
    [
      '# AI Review Note',
      '',
      `- PR: ${result.prUrl}`,
      `- Outcome: \`${result.outcome}\``,
      result.recordedAt ? `- Recorded at: ${result.recordedAt}` : undefined,
      `- Note: ${result.note}`,
      result.fetchArtifactPath
        ? `- Fetch artifact: \`${result.fetchArtifactPath}\``
        : undefined,
      result.triageArtifactPath
        ? `- Triage artifact: \`${result.triageArtifactPath}\``
        : undefined,
    ]
      .filter((line): line is string => line !== undefined)
      .join('\n') + '\n',
    'utf8',
  );
}

export async function recordTicketReview(
  state: DeliveryState,
  cwd: string,
  ticketId: string,
  outcome: ReviewResult,
  note: string | undefined,
  dependencies: Pick<
    TicketReviewDependencies,
    | 'resolveThreads'
    | 'updatePullRequestBody'
    | 'replyToReviewThread'
    | 'resolveReviewThread'
    | 'relativeToRepo'
    | 'resolveReviewFetcher'
    | 'resolveReviewTriager'
    | 'runProcess'
  >,
): Promise<DeliveryState> {
  const target = state.tickets.find((ticket) => ticket.id === ticketId);

  if (!target) {
    throw new Error(`Unknown ticket ${ticketId}.`);
  }

  if (
    target.status !== 'needs_patch' &&
    target.status !== 'in_review' &&
    target.status !== 'operator_input_needed'
  ) {
    throw new Error(
      `Ticket ${ticketId} must be in review before recording an outcome.`,
    );
  }

  const resolveThreads =
    dependencies.resolveThreads ??
    ((worktreePath: string, comments: AiReviewComment[]) =>
      resolveNativeReviewThreads(worktreePath, comments, dependencies));
  const artifactStemPath = resolve(
    cwd,
    state.reviewsDirPath,
    buildPrReviewArtifactStem(ticketId),
  );
  let fetchArtifactPath = target.reviewFetchArtifactPath
    ? resolve(cwd, target.reviewFetchArtifactPath)
    : undefined;
  let triageArtifactPath = target.reviewTriageArtifactPath
    ? resolve(cwd, target.reviewTriageArtifactPath)
    : undefined;
  let fetchArtifact = fetchArtifactPath
    ? readFetchArtifact(fetchArtifactPath)
    : undefined;
  let existingTriageArtifact = triageArtifactPath
    ? readTriageArtifact(triageArtifactPath)
    : undefined;

  if (
    !fetchArtifact &&
    target.reviewComments &&
    target.reviewComments.length > 0
  ) {
    const paths = buildReviewArtifactPaths(artifactStemPath);
    fetchArtifactPath = paths.fetchArtifactPath;
    await writeFetchArtifact(fetchArtifactPath, {
      schemaVersion: 1,
      fetchedAt: new Date().toISOString(),
      reviewedHeadSha: target.reviewHeadSha,
      detected: true,
      vendors:
        target.reviewVendors && target.reviewVendors.length > 0
          ? target.reviewVendors
          : [
              ...new Set(
                target.reviewComments.map((comment) => comment.vendor),
              ),
            ],
      agents: [],
      comments: target.reviewComments,
    });
    fetchArtifact = readFetchArtifact(fetchArtifactPath);
  }

  if (!existingTriageArtifact) {
    const paths = buildReviewArtifactPaths(artifactStemPath);
    triageArtifactPath = paths.triageArtifactPath;
    await writeTriageArtifact(triageArtifactPath, {
      schemaVersion: 1,
      recordedAt: new Date().toISOString(),
      reviewedHeadSha: target.reviewHeadSha,
      outcome:
        target.reviewOutcome ??
        (target.status === 'needs_patch'
          ? 'needs_patch'
          : target.status === 'operator_input_needed'
            ? 'operator_input_needed'
            : 'clean'),
      note:
        target.reviewNote ??
        'External AI review completed without prudent follow-up changes.',
      actionSummary: target.reviewActionSummary,
      nonActionSummary: target.reviewNonActionSummary,
      incompleteAgents: target.reviewIncompleteAgents,
      threadResolutions: target.reviewThreadResolutions,
    });
    existingTriageArtifact = readTriageArtifact(triageArtifactPath);
  }

  if (!triageArtifactPath || !existingTriageArtifact) {
    throw new Error(
      `Ticket ${ticketId} has incomplete review state: triage artifact is missing.`,
    );
  }
  if (
    outcome === 'patched' &&
    (!fetchArtifact || fetchArtifact.comments.length === 0) &&
    (!existingTriageArtifact.threadResolutions ||
      existingTriageArtifact.threadResolutions.length === 0)
  ) {
    throw new Error(
      `Ticket ${ticketId} has incomplete review state: fetch artifact is missing or empty, so patched review threads cannot be reconciled safely.`,
    );
  }
  const reviewThreadResolutions =
    outcome === 'patched' &&
    existingTriageArtifact?.threadResolutions &&
    existingTriageArtifact.threadResolutions.length > 0
      ? existingTriageArtifact.threadResolutions
      : outcome === 'patched' && fetchArtifact?.comments
        ? resolveThreads(target.worktreePath, fetchArtifact.comments)
        : existingTriageArtifact?.threadResolutions;
  if (
    outcome === 'patched' &&
    reviewThreadResolutions &&
    reviewThreadResolutions.length > 0 &&
    triageArtifactPath
  ) {
    await updateTriageArtifact(triageArtifactPath, (current) => ({
      schemaVersion: 1,
      recordedAt: new Date().toISOString(),
      reviewedHeadSha:
        current?.reviewedHeadSha ??
        existingTriageArtifact?.reviewedHeadSha ??
        target.reviewHeadSha,
      outcome,
      note:
        formatAccumulatedReviewNote(
          target.reviewOutcome,
          outcome,
          defaultFinalReviewNote(
            outcome,
            note,
            current?.note ?? existingTriageArtifact?.note,
          ),
        ) ??
        defaultFinalReviewNote(
          outcome,
          note,
          current?.note ?? existingTriageArtifact?.note,
        ) ??
        'External AI review completed without prudent follow-up changes.',
      actionSummary:
        current?.actionSummary ?? existingTriageArtifact?.actionSummary,
      nonActionSummary:
        current?.nonActionSummary ?? existingTriageArtifact?.nonActionSummary,
      incompleteAgents:
        current?.incompleteAgents ?? existingTriageArtifact?.incompleteAgents,
      patchCommitShas:
        current?.patchCommitShas ?? existingTriageArtifact?.patchCommitShas,
      threadResolutions: reviewThreadResolutions,
      prBodyRefresh:
        current?.prBodyRefresh ?? existingTriageArtifact?.prBodyRefresh,
    }));
  } else if (triageArtifactPath) {
    await updateTriageArtifact(triageArtifactPath, (current) => ({
      schemaVersion: 1,
      recordedAt: new Date().toISOString(),
      reviewedHeadSha:
        current?.reviewedHeadSha ??
        existingTriageArtifact?.reviewedHeadSha ??
        target.reviewHeadSha,
      outcome,
      note:
        formatAccumulatedReviewNote(
          target.reviewOutcome,
          outcome,
          defaultFinalReviewNote(
            outcome,
            note,
            current?.note ?? existingTriageArtifact?.note,
          ),
        ) ??
        defaultFinalReviewNote(
          outcome,
          note,
          current?.note ?? existingTriageArtifact?.note,
        ) ??
        'External AI review completed without prudent follow-up changes.',
      actionSummary:
        current?.actionSummary ?? existingTriageArtifact?.actionSummary,
      nonActionSummary:
        current?.nonActionSummary ?? existingTriageArtifact?.nonActionSummary,
      incompleteAgents:
        current?.incompleteAgents ?? existingTriageArtifact?.incompleteAgents,
      patchCommitShas:
        current?.patchCommitShas ?? existingTriageArtifact?.patchCommitShas,
      threadResolutions:
        outcome === 'patched'
          ? reviewThreadResolutions
          : current?.threadResolutions,
      prBodyRefresh:
        current?.prBodyRefresh ?? existingTriageArtifact?.prBodyRefresh,
    }));
  }

  const nextState = await applyTicketReviewUpdate(
    cwd,
    state,
    ticketId,
    (ticket) => ({
      ...ticket,
      status:
        outcome === 'operator_input_needed'
          ? 'operator_input_needed'
          : 'reviewed',
      reviewFetchArtifactPath: fetchArtifactPath
        ? dependencies.relativeToRepo(cwd, fetchArtifactPath)
        : ticket.reviewFetchArtifactPath,
      reviewTriageArtifactPath: dependencies.relativeToRepo(
        cwd,
        triageArtifactPath,
      ),
      reviewOutcome: accumulateTicketReviewOutcome(
        ticket.reviewOutcome,
        outcome,
      ),
      reviewRecordedAt: new Date().toISOString(),
    }),
    dependencies,
  );

  return nextState;
}
