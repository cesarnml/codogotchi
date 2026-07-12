import { resolve } from 'node:path';

import type {
  AiReviewComment,
  AiReviewThreadResolution,
  DeliveryNotificationEvent,
  DeliveryState,
  InternalReviewPatchCommit,
  ReviewResult,
  StandaloneAiReviewResult,
  StandalonePullRequest,
  TicketState,
  TicketStatus,
} from './types';
import { DEFAULT_REVIEW_POLLING_PROFILE } from './review-polling-profile';
import { readReviewArtifacts } from './review-artifacts';

const MAX_ACTION_COMMITS = 20;
// Keep the historical marker values so refreshing old PR bodies replaces the
// managed block instead of appending a second triage section.
const STANDALONE_TRIAGE_SECTION_START = '<!-- ai-review:start -->';
const STANDALONE_TRIAGE_SECTION_END = '<!-- ai-review:end -->';

export type ReviewActionCommit = {
  sha: string;
  subject: string;
  vendors: string[];
};

type ReviewMetadataRefreshContext = {
  actionCommits?: ReviewActionCommit[];
  currentHeadSha?: string;
  githubRepo?: { defaultBranch: string; name: string; owner: string };
};

type TicketReviewMetadataRefreshTarget = Pick<
  TicketState,
  | 'id'
  | 'title'
  | 'ticketFile'
  | 'baseBranch'
  | 'verifiedAt'
  | 'verifyOutcome'
  | 'verifyPatchCommits'
  | 'subagentReviewOutcome'
  | 'subagentReviewCompletedAt'
  | 'subagentReviewPatchCommits'
  | 'reviewActionSummary'
  | 'reviewArtifactJsonPath'
  | 'reviewArtifactPath'
  | 'reviewComments'
  | 'reviewFetchArtifactPath'
  | 'reviewHeadSha'
  | 'reviewIncompleteAgents'
  | 'reviewNonActionSummary'
  | 'reviewNote'
  | 'reviewRecordedAt'
  | 'status'
  | 'reviewThreadResolutions'
  | 'reviewTriageArtifactPath'
  | 'reviewOutcome'
  | 'reviewVendors'
>;

type ReviewMetadataRefreshBodyOptions =
  | {
      cwd?: string;
      mode: 'standalone';
      body: string;
      result: StandaloneAiReviewResult;
    }
  | {
      mode: 'ticketed';
      state: DeliveryState;
      ticket: TicketReviewMetadataRefreshTarget;
    };

type PrMetadataDependencies = {
  editPullRequest: (
    cwd: string,
    prNumber: number,
    options: {
      base?: string;
      body?: string;
      title?: string;
    },
  ) => void;
  listCommitSubjectsBetween: (
    cwd: string,
    baseRef: string,
    headRef: string,
    limit: number,
  ) => string[];
  readHeadSha: (cwd: string) => string;
  resolveGitHubRepo?: (
    cwd: string,
  ) => { defaultBranch: string; name: string; owner: string } | undefined;
};

type PersistedReviewDetails = {
  actionSummary?: string;
  comments?: AiReviewComment[];
  incompleteAgents?: string[];
  nonActionSummary?: string;
  note?: string;
  outcome?: ReviewResult;
  recordedAt?: string;
  reviewedHeadSha?: string;
  threadResolutions?: AiReviewThreadResolution[];
  vendors?: string[];
};

function loadPersistedReviewDetails(
  cwd: string,
  paths: {
    fetchArtifactPath?: string;
    triageArtifactPath?: string;
  },
): PersistedReviewDetails {
  const artifacts = readReviewArtifacts({
    fetchArtifactPath: paths.fetchArtifactPath
      ? resolve(cwd, paths.fetchArtifactPath)
      : undefined,
    triageArtifactPath: paths.triageArtifactPath
      ? resolve(cwd, paths.triageArtifactPath)
      : undefined,
  });

  return {
    actionSummary: artifacts.triage?.actionSummary,
    comments: artifacts.fetch?.comments,
    incompleteAgents: artifacts.triage?.incompleteAgents,
    nonActionSummary: artifacts.triage?.nonActionSummary,
    note: artifacts.triage?.note,
    outcome: artifacts.triage?.outcome,
    recordedAt: artifacts.triage?.recordedAt,
    reviewedHeadSha:
      artifacts.triage?.reviewedHeadSha ?? artifacts.fetch?.reviewedHeadSha,
    threadResolutions: artifacts.triage?.threadResolutions,
    vendors: artifacts.fetch?.vendors,
  };
}

function parseFenceMarker(line: string): {
  char: '`' | '~';
  length: number;
  trailing: string;
} | null {
  const match = line.match(/^\s*([`~]{3,})(.*)$/);

  if (!match) {
    return null;
  }

  const marker = match[1]!;
  const char = marker[0];

  if (char !== '`' && char !== '~') {
    return null;
  }

  return {
    char,
    length: marker.length,
    trailing: match[2] ?? '',
  };
}

function parseMarkdownHeadingAt(
  lines: string[],
  index: number,
): { level: number; lineCount: number; title: string } | undefined {
  return (
    parseMarkdownHeading(lines[index]!) ?? parseUnderlineHeading(lines, index)
  );
}

function parseMarkdownHeading(
  line: string,
): { level: number; lineCount: number; title: string } | undefined {
  const match = line.trim().match(/^(#{1,6})\s+(.+?)(?:\s+#+\s*)?$/);
  if (!match) {
    return undefined;
  }

  return {
    level: match[1]!.length,
    lineCount: 1,
    title: match[2]!.trim(),
  };
}

function parseUnderlineHeading(
  lines: string[],
  index: number,
): { level: number; lineCount: number; title: string } | undefined {
  const titleLine = lines[index]?.trim();
  const underlineLine = lines[index + 1]?.trim();
  if (!titleLine || !underlineLine) {
    return undefined;
  }

  if (/^-{1,}\s*$/.test(underlineLine)) {
    return { level: 2, lineCount: 2, title: titleLine };
  }
  if (/^={1,}\s*$/.test(underlineLine)) {
    return { level: 1, lineCount: 2, title: titleLine };
  }
  return undefined;
}

function isBannedPrBodyHeadingTitle(title: string): boolean {
  const normalized = title
    .toLowerCase()
    .replace(/[#:]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return (
    /^validation\b/.test(normalized) ||
    /^verification\b/.test(normalized) ||
    /^summary by\b/.test(normalized)
  );
}

function stripMarkdownSections(
  body: string,
  shouldStripHeading: (heading: {
    level: number;
    lineCount: number;
    title: string;
  }) => boolean,
): string {
  const lines = body.split('\n');
  const kept: string[] = [];
  let index = 0;
  let activeFence: { char: '`' | '~'; length: number } | undefined;

  while (index < lines.length) {
    const line = lines[index]!;
    const fenceMarker = parseFenceMarker(line);
    if (fenceMarker) {
      if (!activeFence) {
        activeFence = { char: fenceMarker.char, length: fenceMarker.length };
      } else if (
        fenceMarker.char === activeFence.char &&
        fenceMarker.length >= activeFence.length &&
        fenceMarker.trailing.trim().length === 0
      ) {
        activeFence = undefined;
      }
      kept.push(line);
      index += 1;
      continue;
    }

    if (activeFence) {
      kept.push(line);
      index += 1;
      continue;
    }

    const heading = parseMarkdownHeadingAt(lines, index);
    if (!heading || !shouldStripHeading(heading)) {
      kept.push(lines[index]!);
      index += 1;
      continue;
    }

    index += heading.lineCount;
    while (index < lines.length) {
      const nextLine = lines[index]!;
      const nextFenceMarker = parseFenceMarker(nextLine);
      if (nextFenceMarker) {
        if (!activeFence) {
          activeFence = {
            char: nextFenceMarker.char,
            length: nextFenceMarker.length,
          };
        } else if (
          nextFenceMarker.char === activeFence.char &&
          nextFenceMarker.length >= activeFence.length &&
          nextFenceMarker.trailing.trim().length === 0
        ) {
          activeFence = undefined;
        }
        index += 1;
        continue;
      }
      if (activeFence) {
        index += 1;
        continue;
      }
      const nextHeading = parseMarkdownHeadingAt(lines, index);
      if (nextHeading && nextHeading.level <= heading.level) {
        break;
      }
      index += 1;
    }
  }

  return kept
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trimEnd();
}

function stripExternalAiReviewSections(body: string): string {
  return stripMarkdownSections(
    body,
    (heading) => heading.title.trim().toLowerCase() === 'external ai review',
  );
}

function stripBannedPrBodySections(body: string): string {
  return stripMarkdownSections(body, (heading) =>
    isBannedPrBodyHeadingTitle(heading.title),
  );
}

function normalizeReviewerFacingPullRequestBody(
  body: string,
  options: {
    stripExternalAiReviewSections?: boolean;
  } = {},
): string {
  const sanitized = stripBannedPrBodySections(body);
  const withoutExternalReview = options.stripExternalAiReviewSections
    ? stripExternalAiReviewSections(sanitized)
    : sanitized;

  return `${withoutExternalReview.trimEnd()}\n`;
}

function summarizeReviewMessage(message: string): string {
  const normalized = message.replace(/\s+/g, ' ').trim();
  return normalized.length > 180
    ? `${normalized.slice(0, 177).trimEnd()}...`
    : normalized;
}

function collectActionVendors(
  comments: AiReviewComment[] | undefined,
  vendors: string[] | undefined,
): string[] {
  const fromFindings = (comments ?? [])
    .filter((comment) => comment.kind === 'finding')
    .map((comment) => comment.vendor);
  const merged = fromFindings.length > 0 ? fromFindings : (vendors ?? []);
  return [...new Set(merged)];
}

function listReviewActionCommits(
  cwd: string,
  reviewedHeadSha: string | undefined,
  currentHeadSha: string | undefined,
  comments: AiReviewComment[] | undefined,
  vendors: string[] | undefined,
  dependencies: Pick<PrMetadataDependencies, 'listCommitSubjectsBetween'>,
): ReviewActionCommit[] {
  if (
    !reviewedHeadSha ||
    !currentHeadSha ||
    reviewedHeadSha === currentHeadSha
  ) {
    return [];
  }

  const actionVendors = collectActionVendors(comments, vendors);
  try {
    return dependencies
      .listCommitSubjectsBetween(
        cwd,
        reviewedHeadSha,
        currentHeadSha,
        MAX_ACTION_COMMITS,
      )
      .map((line) => {
        const [sha, subject] = line.split('\t', 2);
        if (!sha || !subject) {
          return undefined;
        }
        return {
          sha,
          subject: summarizeReviewMessage(subject),
          vendors: actionVendors,
        } satisfies ReviewActionCommit;
      })
      .filter((commit): commit is ReviewActionCommit => commit !== undefined);
  } catch {
    return [];
  }
}

function shortenSha(sha: string | undefined): string | undefined {
  return sha ? sha.slice(0, 12) : undefined;
}

function buildGitHubCommitLink(input: {
  githubRepo: { defaultBranch: string; name: string; owner: string };
  sha: string;
}): string {
  const short = input.sha.slice(0, 12);
  return `[\`${short}\`](https://github.com/${input.githubRepo.owner}/${input.githubRepo.name}/commit/${input.sha})`;
}

function formatHumanUtcTimestamp(iso: string): string {
  const parsed = Date.parse(iso);
  if (Number.isNaN(parsed)) {
    return iso;
  }
  const d = new Date(parsed);
  const y = d.getUTCFullYear();
  const month = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  const hours = String(d.getUTCHours()).padStart(2, '0');
  const minutes = String(d.getUTCMinutes()).padStart(2, '0');
  return `${y}-${month}-${day} ${hours}:${minutes} UTC`;
}

function summarizeReviewComment(body: string): string {
  const normalized = body.replace(/\s+/g, ' ').trim();
  return normalized.length > 140
    ? `${normalized.slice(0, 137).trimEnd()}...`
    : normalized;
}

function formatReviewCommentLocation(comment: AiReviewComment): string {
  if (!comment.path) {
    return '';
  }

  return comment.line
    ? ` \`${comment.path}:${comment.line}\``
    : ` \`${comment.path}\``;
}

function formatReviewThreadLink(url: string | undefined): string {
  return url ? ` [thread](${url})` : '';
}

function formatResolutionSuffix(
  resolution: AiReviewThreadResolution | undefined,
): string {
  if (!resolution) {
    return '';
  }

  switch (resolution.status) {
    case 'resolved':
      return '; native GitHub thread resolved';
    case 'already_resolved':
      return '; native GitHub thread was already resolved';
    case 'unresolvable':
      return '; native GitHub thread could not be resolved automatically';
    case 'failed':
      return resolution.message
        ? `; native GitHub thread resolution failed: ${summarizeReviewMessage(resolution.message)}`
        : '; native GitHub thread resolution failed';
  }
}

function extractHighlightedReviewText(body: string): string | undefined {
  const boldMatches = [...body.matchAll(/\*\*([^*]+)\*\*/g)];

  for (const match of boldMatches) {
    const candidate = match[1]?.trim();
    if (
      candidate &&
      !candidate.toLowerCase().startsWith('actionable comments posted')
    ) {
      return candidate;
    }
  }

  return undefined;
}

function summarizeReviewerFacingFinding(body: string): string {
  const highlighted = extractHighlightedReviewText(body);
  if (highlighted) {
    return highlighted;
  }

  const firstMeaningfulLine = body
    .split('\n')
    .map((line) => line.trim())
    .find(
      (line) =>
        line.length > 0 &&
        !line.startsWith('```') &&
        !line.startsWith('<') &&
        !line.startsWith('>') &&
        !line.startsWith('<!--'),
    );

  return summarizeReviewComment(firstMeaningfulLine ?? body);
}

function buildReviewCommentBullet(
  comment: AiReviewComment,
  detail?: string,
): string {
  const base = `- [${comment.vendor}] ${summarizeReviewerFacingFinding(comment.body)}`;
  const suffix = detail ? ` (${detail})` : '';
  return `${base}${suffix}${formatReviewCommentLocation(comment)}${formatReviewThreadLink(comment.url)}`;
}

function buildReviewCommentBullets(
  comments: AiReviewComment[] | undefined,
  detail?: string,
): string[] {
  if (!comments || comments.length === 0) {
    return [];
  }

  return comments.map((comment) => buildReviewCommentBullet(comment, detail));
}

type ReviewCommentGroups = {
  currentActionableComments: AiReviewComment[];
  currentSummaryNoiseComments: AiReviewComment[];
  resolvedFindingComments: AiReviewComment[];
  unresolvedFindingComments: AiReviewComment[];
};

function classifyReviewComments(input: {
  comments?: AiReviewComment[];
  currentHeadSha?: string;
  reviewedHeadSha?: string;
  reviewStatus: ReviewResult | TicketStatus;
}): ReviewCommentGroups {
  const appliesToCurrentHead =
    !!input.reviewedHeadSha &&
    !!input.currentHeadSha &&
    input.reviewedHeadSha === input.currentHeadSha;
  const effectiveContext =
    input.reviewedHeadSha && input.currentHeadSha && !appliesToCurrentHead
      ? 'history'
      : 'current';
  const currentComments =
    effectiveContext === 'current' ? (input.comments ?? []) : [];
  const currentActionableComments = currentComments.filter(
    (comment) =>
      !comment.isOutdated && !comment.isResolved && comment.kind !== 'summary',
  );
  const currentSummaryNoiseComments = currentComments.filter(
    (comment) =>
      !comment.isOutdated && !comment.isResolved && comment.kind === 'summary',
  );
  const staleOrResolvedComments =
    effectiveContext === 'history'
      ? (input.comments ?? [])
      : (input.comments ?? []).filter(
          (comment) => comment.isOutdated || comment.isResolved,
        );

  return {
    currentActionableComments,
    currentSummaryNoiseComments,
    resolvedFindingComments: [
      ...(input.reviewStatus === 'patched' ? currentActionableComments : []),
      ...staleOrResolvedComments,
    ],
    unresolvedFindingComments:
      input.reviewStatus === 'needs_patch' ||
      input.reviewStatus === 'operator_input_needed'
        ? currentActionableComments
        : [],
  };
}

function buildResolvedFindingBullets(input: {
  comments: AiReviewComment[];
  reviewStatus: ReviewResult | TicketStatus;
  threadResolutions?: AiReviewThreadResolution[];
}): string[] {
  const resolutionByThreadId = new Map(
    (input.threadResolutions ?? []).map((resolution) => [
      resolution.threadId,
      resolution,
    ]),
  );

  return input.comments.map((comment) => {
    const resolution = comment.threadId
      ? resolutionByThreadId.get(comment.threadId)
      : undefined;
    const detail = resolution
      ? formatResolutionSuffix(resolution).replace(/^;\s*/, '')
      : input.reviewStatus === 'patched'
        ? 'patched'
        : undefined;
    return buildReviewCommentBullet(comment, detail);
  });
}

function buildActionCommitBullets(
  actionCommits: ReviewActionCommit[] | undefined,
): string[] {
  return (actionCommits ?? []).map((commit) => {
    const vendorTag =
      commit.vendors.length > 0 ? ` [${commit.vendors.join(',')}]` : '';
    return `- \`${shortenSha(commit.sha)}\`${vendorTag} ${commit.subject}`;
  });
}

function buildRecordedPatchCommitBullets(
  patchCommits: InternalReviewPatchCommit[] | undefined,
  githubRepo:
    | { defaultBranch: string; name: string; owner: string }
    | undefined,
): string[] {
  return (patchCommits ?? []).map((commit) => {
    const shaLabel = githubRepo
      ? buildGitHubCommitLink({ githubRepo, sha: commit.sha })
      : `\`${shortenSha(commit.sha)}\``;
    return `- ${shaLabel} ${commit.subject}`;
  });
}

function buildInternalReviewStageLine(input: {
  completedAt?: string;
  outcome?: 'clean' | 'patched' | 'skipped';
  stageLabel: string;
}): string | undefined {
  if (!input.completedAt && !input.outcome) {
    return undefined;
  }

  const outcome = input.outcome ?? 'unknown';
  const completedSuffix = input.completedAt
    ? ` completed at ${formatHumanUtcTimestamp(input.completedAt)}`
    : '';
  return `- ${input.stageLabel}: outcome \`${outcome}\`${completedSuffix}`;
}

function assertPatchedStageHasCommitEvidence(input: {
  outcome?: 'clean' | 'patched' | 'skipped';
  patchCommits?: InternalReviewPatchCommit[];
  stageLabel: string;
}): void {
  if (
    input.outcome === 'patched' &&
    input.patchCommits !== undefined &&
    input.patchCommits.length === 0
  ) {
    throw new Error(
      `${input.stageLabel} PR metadata requires recorded patch commits for patched outcomes.`,
    );
  }
}

function hasPatchEvidence(input: {
  actionCommits?: ReviewActionCommit[];
  threadResolutions?: AiReviewThreadResolution[];
}): boolean {
  return (input.actionCommits?.length ?? 0) > 0;
}

export function assertReviewerFacingMarkdown(body: string): void {
  const lines = body.split('\n');
  let activeFence: { char: '`' | '~'; length: number } | undefined;
  const sanitizedLines: string[] = [];

  for (const line of lines) {
    const fenceMarker = parseFenceMarker(line);
    if (fenceMarker) {
      if (!activeFence) {
        activeFence = { char: fenceMarker.char, length: fenceMarker.length };
      } else if (
        fenceMarker.char === activeFence.char &&
        fenceMarker.length >= activeFence.length &&
        fenceMarker.trailing.trim().length === 0
      ) {
        activeFence = undefined;
      }
      sanitizedLines.push('');
      continue;
    }

    if (activeFence) {
      sanitizedLines.push('');
      continue;
    }

    sanitizedLines.push(line.replace(/`[^`]*`/g, ''));
  }

  if (activeFence) {
    throw new Error(
      'PR body guard failed: markdown contains an unmatched fenced code block.',
    );
  }

  const sanitizedBody = sanitizedLines.join('\n');
  if (/(^|[^`])\\n(#{1,6}\s|- |\* |\d+\.\s)/.test(sanitizedBody)) {
    throw new Error(
      'PR body guard failed: body contains likely-escaped newline formatting sequences.',
    );
  }

  const malformedHeading = sanitizedLines.find((line) =>
    /^(#{1,6})(?!#)\S/.test(line.trim()),
  );
  if (malformedHeading) {
    throw new Error(
      `PR body guard failed: malformed markdown heading "${malformedHeading.trim()}".`,
    );
  }

  const bannedHeading = sanitizedLines.find((line, index) => {
    const heading = parseMarkdownHeadingAt(sanitizedLines, index);
    return heading ? isBannedPrBodyHeadingTitle(heading.title) : false;
  });
  if (bannedHeading) {
    throw new Error(
      `PR body guard failed: banned section heading "${bannedHeading.trim()}".`,
    );
  }
}

function buildAiReviewDetailLines(input: {
  actionCommits?: ReviewActionCommit[];
  actionSummary?: string;
  comments?: AiReviewComment[];
  currentHeadSha?: string;
  githubRepo?: { defaultBranch: string; name: string; owner: string };
  maxWaitMinutes: number;
  nonActionSummary?: string;
  note?: string;
  outcome?: ReviewResult;
  reviewedHeadSha?: string;
  status?: TicketStatus;
  threadResolutions?: AiReviewThreadResolution[];
  vendors?: string[];
}): string[] {
  const lines: string[] = [];
  const reviewStatus = input.outcome ?? input.status;

  if (
    !reviewStatus ||
    (reviewStatus !== 'clean' &&
      reviewStatus !== 'patched' &&
      reviewStatus !== 'needs_patch' &&
      reviewStatus !== 'operator_input_needed')
  ) {
    return lines;
  }

  lines.push(`- outcome: \`${reviewStatus}\``);

  const appliesToCurrentHead =
    !!input.reviewedHeadSha &&
    !!input.currentHeadSha &&
    input.reviewedHeadSha === input.currentHeadSha;

  if (input.reviewedHeadSha) {
    if (input.githubRepo) {
      lines.push(
        `- reviewed commit: ${buildGitHubCommitLink({
          githubRepo: input.githubRepo,
          sha: input.reviewedHeadSha,
        })}`,
      );
    } else {
      lines.push(`- reviewed commit: \`${shortenSha(input.reviewedHeadSha)}\``);
    }
  }

  if (input.currentHeadSha) {
    if (input.githubRepo) {
      lines.push(
        `- current branch head: ${buildGitHubCommitLink({
          githubRepo: input.githubRepo,
          sha: input.currentHeadSha,
        })}`,
      );
    } else {
      lines.push(
        `- current branch head: \`${shortenSha(input.currentHeadSha)}\``,
      );
    }
  }

  if (input.reviewedHeadSha && input.currentHeadSha && !appliesToCurrentHead) {
    lines.push(
      '- the latest recorded external AI review applies to an older branch head; the prior review history is shown below for debugging.',
    );
    if (
      reviewStatus === 'patched' &&
      hasPatchEvidence({
        actionCommits: input.actionCommits,
        threadResolutions: input.threadResolutions,
      })
    ) {
      lines.push(
        `- patch commits after \`${shortenSha(input.reviewedHeadSha)}\` address all findings from that review.`,
      );
    }
  }

  if (input.vendors && input.vendors.length > 0) {
    lines.push(
      `- vendors: ${input.vendors.map((vendor) => `\`${vendor}\``).join(', ')}`,
    );
  }

  const {
    currentActionableComments,
    currentSummaryNoiseComments,
    resolvedFindingComments,
    unresolvedFindingComments,
  } = classifyReviewComments({
    comments: input.comments,
    currentHeadSha: input.currentHeadSha,
    reviewedHeadSha: input.reviewedHeadSha,
    reviewStatus,
  });

  if (
    reviewStatus === 'clean' &&
    currentActionableComments.length === 0 &&
    currentSummaryNoiseComments.length === 0 &&
    resolvedFindingComments.length === 0
  ) {
    lines.push('- no prudent follow-up changes were required.');
  }

  const resolvedFindingBullets = buildResolvedFindingBullets({
    comments: resolvedFindingComments,
    reviewStatus,
    threadResolutions: input.threadResolutions,
  }).filter((bullet, index) => {
    const source = resolvedFindingComments[index];
    return source?.kind !== 'summary';
  });
  const actionCommitBullets = buildActionCommitBullets(input.actionCommits);

  const hasStaleSha =
    !!input.reviewedHeadSha &&
    !!input.currentHeadSha &&
    input.reviewedHeadSha !== input.currentHeadSha;
  const showStalePatchedFindingsOnly =
    reviewStatus === 'patched' &&
    resolvedFindingBullets.length > 0 &&
    hasStaleSha;

  if (showStalePatchedFindingsOnly) {
    lines.push(
      '',
      '### Resolved Review Findings',
      '',
      ...resolvedFindingBullets,
    );
  } else if (actionCommitBullets.length > 0) {
    lines.push('', '### Actions Taken', '', ...actionCommitBullets);
  } else if (resolvedFindingBullets.length > 0) {
    lines.push(
      '',
      '### Resolved Review Findings',
      '',
      ...resolvedFindingBullets,
    );
  }

  const unresolvedFindingBullets = buildReviewCommentBullets(
    unresolvedFindingComments,
  );

  if (unresolvedFindingBullets.length > 0) {
    lines.push(
      '',
      '### Unresolved Review Findings',
      '',
      ...unresolvedFindingBullets,
    );
    if (input.note) {
      lines.push('', `- triage note: ${input.note}`);
    }
    if (input.actionSummary) {
      lines.push(`- triage summary: ${input.actionSummary}`);
    }
  }

  if (input.nonActionSummary) {
    lines.push(
      '',
      '### No-Action Rationale',
      '',
      `- ${input.nonActionSummary}`,
    );
  }

  return lines;
}

export function buildExternalAiReviewSection(
  result: {
    actionSummary?: string;
    comments?: AiReviewComment[];
    note?: string;
    nonActionSummary?: string;
    outcome?: ReviewResult;
    reviewedHeadSha?: string;
    status?: TicketStatus;
    threadResolutions?: AiReviewThreadResolution[];
    vendors?: string[];
  },
  options: {
    actionCommits?: ReviewActionCommit[];
    currentHeadSha?: string;
    githubRepo?: { defaultBranch: string; name: string; owner: string };
    incompleteAgents?: string[];
    maxWaitMinutes: number;
  },
): string {
  const lines = ['## External AI Review', ''];
  lines.push(
    ...buildAiReviewDetailLines({
      actionSummary: result.actionSummary,
      actionCommits: options.actionCommits,
      comments: result.comments,
      currentHeadSha: options.currentHeadSha,
      githubRepo: options.githubRepo,
      maxWaitMinutes: options.maxWaitMinutes,
      nonActionSummary: result.nonActionSummary,
      note: result.note,
      outcome: result.outcome,
      reviewedHeadSha: result.reviewedHeadSha,
      status: result.status,
      threadResolutions: result.threadResolutions,
      vendors: result.vendors,
    }),
  );

  if (options.incompleteAgents && options.incompleteAgents.length > 0) {
    lines.push(
      `- incomplete agents at timeout: \`${options.incompleteAgents.join(', ')}\``,
    );
  }

  return lines.join('\n');
}

export function buildPullRequestBody(
  state: DeliveryState,
  ticket: TicketReviewMetadataRefreshTarget,
  options: {
    actionCommits?: ReviewActionCommit[];
    currentHeadSha?: string;
    githubRepo?: { defaultBranch: string; name: string; owner: string };
  } = {},
  review: PersistedReviewDetails = loadPersistedReviewDetails(
    (ticket as TicketReviewMetadataRefreshTarget & { worktreePath?: string })
      .worktreePath ?? '',
    {
      fetchArtifactPath:
        ticket.reviewFetchArtifactPath ?? ticket.reviewArtifactPath,
      triageArtifactPath:
        ticket.reviewTriageArtifactPath ?? ticket.reviewArtifactJsonPath,
    },
  ),
): string {
  const effectiveReview: PersistedReviewDetails = {
    actionSummary: review.actionSummary ?? ticket.reviewActionSummary,
    comments: review.comments ?? ticket.reviewComments,
    incompleteAgents: review.incompleteAgents ?? ticket.reviewIncompleteAgents,
    nonActionSummary: review.nonActionSummary ?? ticket.reviewNonActionSummary,
    note: review.note ?? ticket.reviewNote,
    outcome: review.outcome ?? ticket.reviewOutcome,
    recordedAt: review.recordedAt ?? ticket.reviewRecordedAt,
    reviewedHeadSha: review.reviewedHeadSha ?? ticket.reviewHeadSha,
    threadResolutions:
      review.threadResolutions ?? ticket.reviewThreadResolutions,
    vendors: review.vendors ?? ticket.reviewVendors,
  };
  const shouldRenderExternalAiReviewSection =
    effectiveReview.outcome === 'clean' ||
    effectiveReview.outcome === 'patched' ||
    ticket.status === 'needs_patch' ||
    ticket.status === 'operator_input_needed';
  assertPatchedStageHasCommitEvidence({
    outcome: ticket.verifyOutcome,
    patchCommits: ticket.verifyPatchCommits,
    stageLabel: 'Post-verify',
  });
  assertPatchedStageHasCommitEvidence({
    outcome: ticket.subagentReviewOutcome,
    patchCommits: ticket.subagentReviewPatchCommits,
    stageLabel: 'Subagent review',
  });

  const lines = [
    '## Summary',
    '',
    `- delivery ticket: \`${ticket.id} ${ticket.title}\``,
  ];

  if (options.githubRepo) {
    const rel = ticket.ticketFile.replace(/\\/g, '/');
    lines.push(
      `- ticket file: [${rel}](https://github.com/${options.githubRepo.owner}/${options.githubRepo.name}/blob/${options.githubRepo.defaultBranch}/${rel})`,
    );
  } else {
    lines.push(`- ticket file: \`${ticket.ticketFile}\``);
  }

  lines.push(`- stacked base branch: \`${ticket.baseBranch}\``);

  const postVerifyLine = buildInternalReviewStageLine({
    completedAt: ticket.verifiedAt,
    outcome: ticket.verifyOutcome,
    stageLabel: 'post-verify',
  });
  if (postVerifyLine) {
    lines.push(postVerifyLine);
  }

  const subagentReviewLine = buildInternalReviewStageLine({
    completedAt: ticket.subagentReviewCompletedAt,
    outcome: ticket.subagentReviewOutcome,
    stageLabel: 'subagentReview',
  });
  if (subagentReviewLine) {
    lines.push(subagentReviewLine);
  }

  const postVerifyPatchCommitBullets = buildRecordedPatchCommitBullets(
    ticket.verifyPatchCommits,
    options.githubRepo,
  );
  if (postVerifyPatchCommitBullets.length > 0) {
    lines.push(
      '',
      '### Post-Verify Patch Commits',
      '',
      ...postVerifyPatchCommitBullets,
    );
  }

  const subagentPatchCommitBullets = buildRecordedPatchCommitBullets(
    ticket.subagentReviewPatchCommits,
    options.githubRepo,
  );
  if (subagentPatchCommitBullets.length > 0) {
    lines.push(
      '',
      '### Subagent Review Patch Commits',
      '',
      ...subagentPatchCommitBullets,
    );
  }

  if (shouldRenderExternalAiReviewSection) {
    lines.push(
      '',
      buildExternalAiReviewSection(
        {
          actionSummary: effectiveReview.actionSummary,
          comments: effectiveReview.comments,
          note: effectiveReview.note,
          nonActionSummary: effectiveReview.nonActionSummary,
          outcome: effectiveReview.outcome,
          reviewedHeadSha:
            effectiveReview.reviewedHeadSha ?? ticket.reviewHeadSha,
          status: ticket.status,
          threadResolutions: effectiveReview.threadResolutions,
          vendors: effectiveReview.vendors,
        },
        {
          actionCommits: options.actionCommits,
          currentHeadSha: options.currentHeadSha,
          githubRepo: options.githubRepo,
          incompleteAgents: effectiveReview.incompleteAgents,
          maxWaitMinutes: state.reviewPollMaxWaitMinutes,
        },
      ),
    );
  }

  return normalizeReviewerFacingPullRequestBody(lines.join('\n'));
}

export function buildStandaloneAiReviewSection(
  result: PersistedReviewDetails,
  options: {
    actionCommits?: ReviewActionCommit[];
    currentHeadSha?: string;
    githubRepo?: { defaultBranch: string; name: string; owner: string };
  } = {},
): string {
  const section = buildExternalAiReviewSection(result, {
    actionCommits: options.actionCommits,
    currentHeadSha: options.currentHeadSha,
    githubRepo: options.githubRepo,
    incompleteAgents: result.incompleteAgents,
    maxWaitMinutes: DEFAULT_REVIEW_POLLING_PROFILE.maxWaitMinutes,
  });

  return [
    STANDALONE_TRIAGE_SECTION_START,
    section,
    STANDALONE_TRIAGE_SECTION_END,
  ].join('\n');
}

export function mergeStandaloneAiReviewSection(
  body: string,
  section: string,
): string {
  const pattern = new RegExp(
    `${STANDALONE_TRIAGE_SECTION_START}[\\s\\S]*?${STANDALONE_TRIAGE_SECTION_END}`,
    'g',
  );
  const bodyWithoutAiReviewSections = body.replace(pattern, '').trimEnd();
  const normalizedBody = normalizeReviewerFacingPullRequestBody(
    bodyWithoutAiReviewSections,
    {
      stripExternalAiReviewSections: true,
    },
  ).trimEnd();
  const mergedBody =
    normalizedBody.length > 0
      ? `${normalizedBody}\n\n${section}\n`
      : `${section}\n`;

  return normalizeReviewerFacingPullRequestBody(mergedBody);
}

export function buildReviewMetadataRefreshBody(
  options: ReviewMetadataRefreshBodyOptions,
  context: ReviewMetadataRefreshContext = {},
): string {
  if (options.mode === 'ticketed') {
    const review = buildPullRequestBody(options.state, options.ticket, context);
    return review;
  }

  const review = loadPersistedReviewDetails(options.cwd ?? '', {
    fetchArtifactPath:
      options.result.fetchArtifactPath ?? options.result.artifactJsonPath,
    triageArtifactPath:
      options.result.triageArtifactPath ?? options.result.artifactJsonPath,
  });
  return mergeStandaloneAiReviewSection(
    options.body,
    buildStandaloneAiReviewSection(
      {
        actionSummary: review.actionSummary ?? options.result.actionSummary,
        comments: review.comments ?? options.result.comments,
        incompleteAgents:
          review.incompleteAgents ?? options.result.incompleteAgents,
        nonActionSummary:
          review.nonActionSummary ?? options.result.nonActionSummary,
        note: review.note ?? options.result.note,
        outcome: review.outcome ?? options.result.outcome,
        reviewedHeadSha:
          review.reviewedHeadSha ?? options.result.reviewedHeadSha,
        recordedAt: review.recordedAt ?? options.result.recordedAt,
        threadResolutions:
          review.threadResolutions ?? options.result.threadResolutions,
        vendors: review.vendors ?? options.result.vendors,
      },
      context,
    ),
  );
}

export function buildPullRequestTitle(
  ticket: Pick<TicketState, 'id' | 'title' | 'ticketFile' | 'type' | 'scope'>,
): string {
  const type = ticket.type ?? 'feat';
  const scopePart = ticket.scope ? `(${ticket.scope})` : '';
  const subject = ticket.title.toLowerCase();
  return `${type}${scopePart}: ${subject} [${ticket.id}]`;
}

export function updatePullRequestBody(
  state: DeliveryState,
  ticket: TicketState,
  dependencies: PrMetadataDependencies,
): void {
  if (!ticket.prNumber) {
    return;
  }

  const currentHeadSha = dependencies.readHeadSha(ticket.worktreePath);
  const githubRepo = dependencies.resolveGitHubRepo?.(ticket.worktreePath);
  const review = loadPersistedReviewDetails(ticket.worktreePath, {
    fetchArtifactPath: ticket.reviewFetchArtifactPath,
    triageArtifactPath: ticket.reviewTriageArtifactPath,
  });
  const body = buildReviewMetadataRefreshBody(
    {
      mode: 'ticketed',
      state,
      ticket,
    },
    {
      actionCommits: listReviewActionCommits(
        ticket.worktreePath,
        review.reviewedHeadSha ?? ticket.reviewHeadSha,
        currentHeadSha,
        review.comments,
        review.vendors,
        dependencies,
      ),
      currentHeadSha,
      githubRepo,
    },
  );
  assertReviewerFacingMarkdown(body);

  dependencies.editPullRequest(ticket.worktreePath, ticket.prNumber, { body });
}

export function updateStandalonePullRequestBody(
  cwd: string,
  pullRequest: StandalonePullRequest,
  result: StandaloneAiReviewResult,
  dependencies: Pick<
    PrMetadataDependencies,
    'editPullRequest' | 'listCommitSubjectsBetween' | 'resolveGitHubRepo'
  >,
): void {
  const githubRepo = dependencies.resolveGitHubRepo?.(cwd);
  const review = loadPersistedReviewDetails(cwd, {
    fetchArtifactPath: result.fetchArtifactPath,
    triageArtifactPath: result.triageArtifactPath,
  });
  const nextBody = buildReviewMetadataRefreshBody(
    {
      body: pullRequest.body,
      cwd,
      mode: 'standalone',
      result,
    },
    {
      actionCommits: listReviewActionCommits(
        cwd,
        review.reviewedHeadSha ?? result.reviewedHeadSha,
        pullRequest.headRefOid,
        review.comments,
        review.vendors,
        dependencies,
      ),
      currentHeadSha: pullRequest.headRefOid,
      githubRepo,
    },
  );
  assertReviewerFacingMarkdown(nextBody);

  dependencies.editPullRequest(cwd, pullRequest.number, { body: nextBody });
}

export function buildStandaloneReviewStartedEvent(
  prNumber: number,
  prUrl: string,
): DeliveryNotificationEvent {
  return {
    kind: 'standalone_review_started',
    prNumber,
    prUrl,
    reviewPollIntervalMinutes: DEFAULT_REVIEW_POLLING_PROFILE.intervalMinutes,
    reviewPollMaxWaitMinutes: DEFAULT_REVIEW_POLLING_PROFILE.maxWaitMinutes,
  };
}
