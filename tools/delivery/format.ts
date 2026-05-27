import { resolve } from 'node:path';

import { readReviewArtifacts } from './review-artifacts';
import { generateRunDeliverInvocation } from './runtime-config';
import type { ResolvedOrchestratorConfig } from './runtime-config';
import type {
  AiReviewComment,
  AiReviewThreadResolution,
  DeliveryState,
  RunPolicy,
  StandaloneAiReviewResult,
  TicketState,
  TicketStatus,
} from './types';

/**
 * Format the active run policy into a compact, operator-readable string
 * suitable for display in status output.
 *
 * Separator convention (intentional, mirrors existing status line format):
 * - Top-level key uses `=` (e.g. `boundary_mode=cook`)
 * - Sub-fields within the same line use `:` (e.g. `subagentReview:skip_doc_only`),
 *   matching the existing `review_policy=subagentReview:... prReview:...` pattern.
 *
 * Example output:
 *   boundary_mode=cook subagentReview:skip_doc_only prReview:skip_doc_only
 */
export function formatRunPolicy(policy: RunPolicy): string {
  return [
    `boundary_mode=${policy.ticketBoundaryMode}`,
    `subagentReview:${policy.subagentReview}`,
    `prReview:${policy.prReview}`,
  ].join(' ');
}

export type RepairStateResult = {
  state: DeliveryState;
  backupPath?: string;
  changes: string[];
  hadExistingState: boolean;
};

export function resolveNextCommand(
  status: TicketStatus,
  config: ResolvedOrchestratorConfig,
  planPath: string,
  ticketId?: string,
  ticket?: Pick<TicketState, 'subagentAdversarialPromptPath' | 'verifyOutcome'>,
): string | null {
  const invoke = generateRunDeliverInvocation(config.packageManager);
  const cmd = (subcommand: string) =>
    `${invoke} --plan ${planPath} ${subcommand}`;

  switch (status) {
    case 'in_progress':
      return cmd('post-red');
    case 'red_complete':
      return cmd('post-verify');
    case 'verified':
      return resolveVerifiedNextCommand(config, ticket, cmd);
    case 'subagent_review_complete':
      return cmd('open-pr');
    case 'in_review':
      return cmd('poll-review');
    case 'needs_patch':
      return cmd(`record-review ${ticketId ?? '<ticket-id>'} patched`);
    case 'operator_input_needed':
      return cmd(
        `record-review ${ticketId ?? '<ticket-id>'} operator_input_needed`,
      );
    case 'reviewed':
      return cmd('advance');
    case 'done':
    case 'pending':
      return null;
  }
}

function resolveVerifiedNextCommand(
  config: ResolvedOrchestratorConfig,
  ticket:
    | Pick<TicketState, 'subagentAdversarialPromptPath' | 'verifyOutcome'>
    | undefined,
  cmd: (subcommand: string) => string,
): string {
  if (config.reviewPolicy.subagentReview === 'disabled') {
    return cmd('open-pr');
  }

  // Doc-only tickets under skip_doc_only auto-record post-verify as skipped.
  // For those tickets `subagent-review` itself auto-skips without a runner —
  // so the adversarial prompt step is intentionally bypassed.
  if (ticket?.verifyOutcome === 'skipped') {
    return cmd('subagent-review');
  }

  if (!ticket?.subagentAdversarialPromptPath) {
    return cmd('write-subagent-adversarial-review');
  }

  return cmd('subagent-review');
}

function loadTicketReviewSnapshot(ticket: TicketState): {
  actionSummary?: string;
  comments?: AiReviewComment[];
  incompleteAgents?: string[];
  note?: string;
  nonActionSummary?: string;
  threadResolutions?: AiReviewThreadResolution[];
  vendors?: string[];
} {
  const artifacts = readReviewArtifacts({
    fetchArtifactPath:
      (ticket.reviewFetchArtifactPath ?? ticket.reviewArtifactJsonPath)
        ? resolve(
            ticket.reviewFetchArtifactPath ?? ticket.reviewArtifactJsonPath!,
          )
        : undefined,
    triageArtifactPath:
      (ticket.reviewTriageArtifactPath ?? ticket.reviewArtifactJsonPath)
        ? resolve(
            ticket.reviewTriageArtifactPath ?? ticket.reviewArtifactJsonPath!,
          )
        : undefined,
  });

  return {
    actionSummary:
      artifacts.triage?.actionSummary ?? ticket.reviewActionSummary,
    comments: artifacts.fetch?.comments ?? ticket.reviewComments,
    incompleteAgents:
      artifacts.triage?.incompleteAgents ?? ticket.reviewIncompleteAgents,
    note: artifacts.triage?.note ?? ticket.reviewNote,
    nonActionSummary:
      artifacts.triage?.nonActionSummary ?? ticket.reviewNonActionSummary,
    threadResolutions:
      artifacts.triage?.threadResolutions ?? ticket.reviewThreadResolutions,
    vendors: artifacts.fetch?.vendors ?? ticket.reviewVendors,
  };
}

export function formatStatus(
  state: DeliveryState,
  config: ResolvedOrchestratorConfig,
): string {
  const allDone =
    state.tickets.length > 0 && state.tickets.every((t) => t.status === 'done');

  const activeTicket =
    state.tickets.find((t) => t.status === 'in_progress') ??
    state.tickets.find((t) => t.status === 'red_complete') ??
    state.tickets.find((t) => t.status === 'verified') ??
    state.tickets.find((t) => t.status === 'subagent_review_complete') ??
    state.tickets.find((t) => t.status === 'in_review') ??
    state.tickets.find((t) => t.status === 'needs_patch') ??
    state.tickets.find((t) => t.status === 'operator_input_needed') ??
    state.tickets.find((t) => t.status === 'reviewed');

  const nextCommandLine = allDone
    ? 'Phase complete. Awaiting developer review.'
    : activeTicket
      ? (() => {
          const next = resolveNextCommand(
            activeTicket.status,
            config,
            state.planPath,
            activeTicket.id,
            activeTicket,
          );
          return next ? `Next command: ${next}` : undefined;
        })()
      : undefined;

  return [
    'Delivery Orchestrator',
    `plan_key=${state.planKey}`,
    `plan=${state.planPath}`,
    `state=${state.statePath}`,
    `handoffs=${state.handoffsDirPath}`,
    `review_poll_interval_minutes=${state.reviewPollIntervalMinutes}`,
    `review_poll_max_wait_minutes=${state.reviewPollMaxWaitMinutes}`,
    `boundary_mode=${config.ticketBoundaryMode}`,
    `review_policy=subagentReview:${config.reviewPolicy.subagentReview} prReview:${config.reviewPolicy.prReview}`,
    state.runPolicy != null
      ? `run_policy=${formatRunPolicy(state.runPolicy)} [persisted]`
      : undefined,
    '',
    ...state.tickets.map((ticket) =>
      [
        `${ticket.id} | status=${ticket.status} | branch=${ticket.branch} | base=${ticket.baseBranch}`,
        `title=${ticket.title}`,
        `worktree=${ticket.worktreePath}`,
        ticket.handoffPath ? `handoff=${ticket.handoffPath}` : undefined,
        ticket.redCommitSha
          ? `red_commit_sha=${ticket.redCommitSha}`
          : undefined,
        ticket.verifiedAt
          ? `post_verify=completed at ${ticket.verifiedAt}${ticket.verifyOutcome ? ` (${ticket.verifyOutcome})` : ''}`
          : undefined,
        ticket.subagentAdversarialPromptWrittenAt
          ? `subagent_adversarial_prompt=written at ${ticket.subagentAdversarialPromptWrittenAt}${ticket.subagentAdversarialPromptPath ? ` (${ticket.subagentAdversarialPromptPath})` : ''}`
          : undefined,
        ticket.subagentReviewCompletedAt
          ? `subagent_review=completed at ${ticket.subagentReviewCompletedAt} (${ticket.subagentReviewOutcome ?? 'unknown'})`
          : undefined,
        ticket.prUrl ? `pr=${ticket.prUrl}` : undefined,
        ticket.reviewFetchArtifactPath
          ? `review_fetch_artifact=${ticket.reviewFetchArtifactPath}`
          : undefined,
        ticket.reviewTriageArtifactPath
          ? `review_triage_artifact=${ticket.reviewTriageArtifactPath}`
          : undefined,
        ticket.reviewRecordedAt
          ? `review_recorded_at=${ticket.reviewRecordedAt}`
          : undefined,
        ticket.reviewOutcome
          ? `review_outcome=${ticket.reviewOutcome}`
          : undefined,
      ]
        .filter((value): value is string => value !== undefined)
        .join('\n'),
    ),
    nextCommandLine,
  ]
    .filter((value): value is string => value !== undefined)
    .join('\n');
}

export function formatAdvanceBoundaryGuidance(
  state: DeliveryState,
  advancedState: DeliveryState,
  nextState: DeliveryState,
  config: ResolvedOrchestratorConfig,
): string | undefined {
  const nextPending = advancedState.tickets.find(
    (t) =>
      t.status === 'pending' &&
      state.tickets.find((prev) => prev.id === t.id)?.status === 'pending',
  );
  const justDone = advancedState.tickets.find(
    (t) =>
      t.status === 'done' &&
      state.tickets.find((prev) => prev.id === t.id)?.status !== 'done',
  );

  if (!justDone || !nextPending) {
    return undefined;
  }

  const invocation = `${generateRunDeliverInvocation(config.packageManager)} --plan ${state.planPath} start`;
  const resumePrompt = `Immediately execute \`${invocation}\`, read the locally materialized handoff artifact in the started worktree as the source of truth for context, and implement ${nextPending.id}.`;

  if (config.ticketBoundaryMode === 'cook') {
    const startedTicket = nextState.tickets.find(
      (ticket) => ticket.id === nextPending.id,
    );
    const nextHandoffAbsolutePath =
      startedTicket?.handoffPath && startedTicket.worktreePath
        ? resolve(startedTicket.worktreePath, startedTicket.handoffPath)
        : undefined;

    return [
      'continuation_mode=cook',
      `COOK CONTINUATION started ${nextPending.id}.`,
      startedTicket?.worktreePath
        ? `next_worktree=${startedTicket.worktreePath}`
        : undefined,
      startedTicket?.handoffPath
        ? `next_handoff=${startedTicket.handoffPath}`
        : undefined,
      nextHandoffAbsolutePath
        ? `next_handoff_absolute=${nextHandoffAbsolutePath}`
        : undefined,
      'Read the locally materialized handoff artifact from `next_handoff_absolute` and continue implementation in the started ticket worktree.',
    ]
      .filter((line): line is string => line !== undefined)
      .join('\n');
  }

  return [
    'context_reset_required=true',
    `GATED BOUNDARY before starting ${nextPending.id}.`,
    'Reset context now. Prefer /clear for minimum token use; use /compact only if you intentionally want compressed carry-forward context.',
    `resume_prompt=${resumePrompt}`,
  ].join('\n');
}

export function formatCurrentTicketStatus(
  state: DeliveryState,
  config: ResolvedOrchestratorConfig,
  ticketId?: string,
): string {
  const ticket =
    (ticketId
      ? state.tickets.find((t) => t.id === ticketId)
      : (state.tickets.find((t) => t.status === 'in_review') ??
        state.tickets.find((t) => t.status === 'needs_patch') ??
        state.tickets.find((t) => t.status === 'operator_input_needed') ??
        state.tickets.find((t) => t.status === 'reviewed'))) ?? undefined;

  const header = [
    'Delivery Orchestrator',
    `plan_key=${state.planKey}`,
    `plan=${state.planPath}`,
    `boundary_mode=${config.ticketBoundaryMode}`,
  ].join('\n');

  if (!ticket) {
    return header;
  }

  const review = loadTicketReviewSnapshot(ticket);
  const actionableFindings = (review.comments ?? []).filter(
    (c) => c.kind !== 'summary' && !c.isOutdated && !c.isResolved,
  );

  const findingsBlock =
    actionableFindings.length > 0
      ? [
          `findings (${actionableFindings.length}):`,
          ...actionableFindings.map((c) => {
            const boldMatch = c.body.match(/\*\*([^*]+)\*\*/);
            const title = boldMatch
              ? boldMatch[1]!.trim()
              : c.body.slice(0, 120).replace(/\n/g, ' ').trim();
            const location = c.path
              ? c.line != null
                ? `${c.path}:${c.line}`
                : c.path
              : '(no file)';
            return `  [${c.vendor}] ${location} — ${title}`;
          }),
        ].join('\n')
      : undefined;

  const ticketLines = [
    `${ticket.id} | status=${ticket.status} | branch=${ticket.branch} | base=${ticket.baseBranch}`,
    `title=${ticket.title}`,
    ticket.prUrl ? `pr=${ticket.prUrl}` : undefined,
    ticket.docOnly ? `doc_only=true` : undefined,
    review.vendors && review.vendors.length > 0
      ? `review_vendors=${review.vendors.join(',')}`
      : undefined,
    ticket.reviewOutcome ? `review_outcome=${ticket.reviewOutcome}` : undefined,
    review.actionSummary
      ? `review_action_summary=${review.actionSummary}`
      : undefined,
    findingsBlock,
    review.note ? `review_note=${review.note}` : undefined,
    review.incompleteAgents?.length
      ? `review_incomplete_agents=${review.incompleteAgents.join(',')}`
      : undefined,
  ]
    .filter((value): value is string => value !== undefined)
    .join('\n');

  return [header, '', ticketLines].join('\n');
}

export function formatRepairSummary(result: RepairStateResult): string {
  return [
    'State Repair',
    result.hadExistingState
      ? 'Existing state file inspected and rebuilt from repo reality.'
      : 'Created fresh state from repo reality.',
    result.backupPath ? `- backup: ${result.backupPath}` : undefined,
    ...result.changes.map((change) => `- ${change}`),
  ]
    .filter((line): line is string => line !== undefined)
    .join('\n');
}

export function formatStandaloneAiReviewResult(
  result: StandaloneAiReviewResult,
): string {
  return [
    'Standalone PR Triage',
    `pr=${result.prUrl}`,
    `outcome=${result.outcome}`,
    result.recordedAt ? `recorded_at=${result.recordedAt}` : undefined,
    result.fetchArtifactPath
      ? `fetch_artifact=${result.fetchArtifactPath}`
      : undefined,
    result.triageArtifactPath
      ? `triage_artifact=${result.triageArtifactPath}`
      : undefined,
    `note=${result.note}`,
  ]
    .filter((line): line is string => line !== undefined)
    .join('\n');
}
