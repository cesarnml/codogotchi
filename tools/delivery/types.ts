import type { ReviewPolicyStageValue, TicketBoundaryMode } from './config';

export type RunPolicy = {
  ticketBoundaryMode: TicketBoundaryMode;
  subagentReview: ReviewPolicyStageValue;
  prReview: ReviewPolicyStageValue;
};

export type TicketStatus =
  | 'pending'
  | 'in_progress'
  | 'red_complete'
  | 'verified'
  | 'subagent_review_complete'
  | 'in_review'
  | 'needs_patch'
  | 'operator_input_needed'
  | 'reviewed'
  | 'done';

export type ReviewOutcome = 'clean' | 'patched' | 'skipped';
export type ReviewResult =
  | ReviewOutcome
  | 'needs_patch'
  | 'operator_input_needed';

export type SubagentReviewOutcome = 'clean' | 'patched' | 'skipped';

export type InternalReviewPatchCommit = {
  sha: string;
  subject: string;
};

import type { RedPolicy } from './ticket-metadata';

export type TicketDefinition = {
  id: string;
  title: string;
  slug: string;
  type?: string;
  scope?: string;
  redPolicy: RedPolicy;
  ticketFile: string;
};

export type AiReviewCommentChannel =
  | 'issue_comment'
  | 'review_summary'
  | 'inline_review';

export type AiReviewCommentKind = 'summary' | 'finding' | 'unknown';

export type AiReviewComment = {
  authorLogin: string;
  authorType: string;
  body: string;
  channel: AiReviewCommentChannel;
  databaseId?: number;
  isOutdated?: boolean;
  isResolved?: boolean;
  kind: AiReviewCommentKind;
  line?: number;
  path?: string;
  threadId?: string;
  threadViewerCanResolve?: boolean;
  updatedAt?: string;
  url?: string;
  vendor: string;
};

export type AiReviewThreadResolutionStatus =
  | 'resolved'
  | 'already_resolved'
  | 'failed'
  | 'unresolvable';

export type AiReviewThreadResolution = {
  message?: string;
  status: AiReviewThreadResolutionStatus;
  threadId: string;
  url?: string;
  vendor: string;
};

export type AiReviewAgentState = 'started' | 'completed' | 'findings_detected';

export type AiReviewAgentResult = {
  agent: string;
  state: AiReviewAgentState;
  findingsCount?: number;
  note?: string;
};

export type TicketState = TicketDefinition & {
  status: TicketStatus;
  branch: string;
  baseBranch: string;
  worktreePath: string;
  handoffPath?: string;
  handoffGeneratedAt?: string;
  redCommitSha?: string;
  verifiedAt?: string;
  verifyOutcome?: ReviewOutcome;
  verifyPatchCommits?: InternalReviewPatchCommit[];
  subagentReviewOutcome?: SubagentReviewOutcome;
  subagentReviewCompletedAt?: string;
  subagentReviewPatchCommits?: InternalReviewPatchCommit[];
  subagentReviewAgent?: string;
  subagentRunnerArtifactPath?: string;
  subagentAdversarialPromptPath?: string;
  subagentAdversarialPromptWrittenAt?: string;
  docOnly?: boolean;
  prNumber?: number;
  prUrl?: string;
  prOpenedAt?: string;
  reviewFetchArtifactPath?: string;
  reviewTriageArtifactPath?: string;
  reviewHeadSha?: string;
  reviewRecordedAt?: string;
  reviewOutcome?: ReviewResult;
  // Legacy compatibility fields: current write paths do not persist these.
  reviewArtifactJsonPath?: string;
  reviewArtifactPath?: string;
  reviewActionSummary?: string;
  reviewComments?: AiReviewComment[];
  reviewIncompleteAgents?: string[];
  reviewNonActionSummary?: string;
  reviewNote?: string;
  reviewThreadResolutions?: AiReviewThreadResolution[];
  reviewVendors?: string[];
};

export type DeliveryState = {
  planKey: string;
  planPath: string;
  statePath: string;
  reviewsDirPath: string;
  handoffsDirPath: string;
  reviewPollIntervalMinutes: number;
  reviewPollMaxWaitMinutes: number;
  runPolicy?: RunPolicy;
  tickets: TicketState[];
};

export type OrchestratorOptions = {
  planPath: string;
  planKey: string;
  statePath: string;
  reviewsDirPath: string;
  handoffsDirPath: string;
  reviewPollIntervalMinutes: number;
  reviewPollMaxWaitMinutes: number;
};

export type DeliveryNotificationEvent =
  | {
      kind: 'ticket_started';
      planKey: string;
      ticketId: string;
      ticketTitle: string;
      branch: string;
    }
  | {
      kind: 'pr_opened';
      planKey: string;
      ticketId: string;
      ticketTitle: string;
      branch: string;
      prUrl: string;
    }
  | {
      kind: 'review_window_ready';
      planKey: string;
      ticketId: string;
      ticketTitle: string;
      branch: string;
      prUrl: string;
      reviewPollIntervalMinutes: number;
      reviewPollMaxWaitMinutes: number;
      firstCheckAt: string;
      finalCheckAt: string;
    }
  | {
      kind: 'review_recorded';
      planKey: string;
      ticketId: string;
      ticketTitle: string;
      branch: string;
      outcome: ReviewResult;
      note?: string;
      prUrl?: string;
    }
  | {
      kind: 'ticket_completed';
      planKey: string;
      ticketId: string;
      ticketTitle: string;
      branch: string;
      prUrl?: string;
    }
  | {
      kind: 'standalone_review_started';
      prNumber: number;
      prUrl: string;
      reviewPollIntervalMinutes: number;
      reviewPollMaxWaitMinutes: number;
    }
  | {
      kind: 'standalone_review_recorded';
      prNumber: number;
      prUrl: string;
      outcome: ReviewResult;
      note?: string;
    }
  | {
      kind: 'run_blocked';
      planKey?: string;
      command?: string;
      reason: string;
    };

export type AiReviewFetcherResult = {
  agents: AiReviewAgentResult[];
  // Legacy compatibility field: not populated by the current fetcher contract.
  artifactText?: string;
  comments: AiReviewComment[];
  detected: boolean;
  reviewedHeadSha?: string;
  vendors: string[];
};

export type AiReviewTriagerResult = {
  actionSummary?: string;
  note: string;
  nonActionSummary?: string;
  outcome: ReviewResult;
  vendors: string[];
};

export type StandaloneAiReviewResult = {
  fetchArtifactPath?: string;
  note: string;
  outcome: ReviewResult;
  prNumber: number;
  prUrl: string;
  reviewedHeadSha?: string;
  recordedAt?: string;
  triageArtifactPath?: string;
  // Legacy compatibility fields: current write paths do not persist these.
  actionSummary?: string;
  artifactJsonPath?: string;
  artifactTextPath?: string;
  comments?: AiReviewComment[];
  incompleteAgents?: string[];
  nonActionSummary?: string;
  threadResolutions?: AiReviewThreadResolution[];
  vendors?: string[];
};

export type StandalonePullRequest = {
  body: string;
  createdAt: string;
  headRefName: string;
  headRefOid: string;
  number: number;
  title: string;
  url: string;
};
