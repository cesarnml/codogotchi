import { existsSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

import type {
  ResolvedOrchestratorConfig,
  ReviewPolicyStageValue,
  TicketBoundaryMode,
} from './config';
import {
  listLocalBranches,
  listMergedPullRequests,
  listOpenPullRequests,
  listRemoteBranches,
  type PullRequestSummary,
  type Runtime,
} from './platform';
import { parsePlan } from './planning';
import type {
  DeliveryState,
  OrchestratorOptions,
  RunPolicy,
  TicketDefinition,
  TicketState,
  TicketStatus,
} from './types';

// ─── Run-policy divergence helpers ──────────────────────────────────────────

export function detectRunPolicyDivergence(
  persisted: RunPolicy,
  current: RunPolicy,
): string[] {
  const fields: string[] = [];
  if (persisted.ticketBoundaryMode !== current.ticketBoundaryMode) {
    fields.push('ticketBoundaryMode');
  }
  if (persisted.subagentReview !== current.subagentReview) {
    fields.push('subagentReview');
  }
  if (persisted.prReview !== current.prReview) {
    fields.push('prReview');
  }
  return fields;
}

export function formatRunPolicyDivergenceError(
  persisted: RunPolicy,
  current: RunPolicy,
  divergedFields: string[],
  runDeliverInvocation: string,
): string {
  const lines: string[] = [
    'Run-policy divergence detected. The persisted run policy in state.json',
    'differs from the current orchestrator.config.json on these fields:',
    '',
  ];

  for (const field of divergedFields) {
    let persistedValue: string;
    let currentValue: string;

    if (field === 'ticketBoundaryMode') {
      persistedValue = persisted.ticketBoundaryMode;
      currentValue = current.ticketBoundaryMode;
    } else if (field === 'subagentReview') {
      persistedValue = persisted.subagentReview;
      currentValue = current.subagentReview;
    } else {
      persistedValue = persisted.prReview;
      currentValue = current.prReview;
    }

    lines.push(
      `  ${field}: persisted=${persistedValue}  current=${currentValue}`,
    );
  }

  lines.push('');
  lines.push('Add --baseline to your command to resolve, e.g.:');
  lines.push(
    `  ${runDeliverInvocation} --baseline orchestrator   # adopt current repo config`,
  );
  lines.push(
    `  ${runDeliverInvocation} --baseline run-policy     # keep persisted run policy`,
  );

  return lines.join('\n');
}

export function patchRunPolicyWithFlags(
  base: RunPolicy,
  flags: {
    boundaryMode?: TicketBoundaryMode;
    subagentReviewPolicy?: ReviewPolicyStageValue;
    prReviewPolicy?: ReviewPolicyStageValue;
  },
): RunPolicy {
  return {
    ticketBoundaryMode: flags.boundaryMode ?? base.ticketBoundaryMode,
    subagentReview: flags.subagentReviewPolicy ?? base.subagentReview,
    prReview: flags.prReviewPolicy ?? base.prReview,
  };
}

export function deriveRunPolicyFromConfig(
  config: ResolvedOrchestratorConfig,
): RunPolicy {
  return {
    ticketBoundaryMode: config.ticketBoundaryMode,
    subagentReview: config.reviewPolicy.subagentReview,
    prReview: config.reviewPolicy.prReview,
  };
}

export function applyRunPolicyToConfig(
  config: ResolvedOrchestratorConfig,
  runPolicy: RunPolicy,
): ResolvedOrchestratorConfig {
  return {
    ...config,
    ticketBoundaryMode: runPolicy.ticketBoundaryMode,
    reviewPolicy: {
      ...config.reviewPolicy,
      subagentReview: runPolicy.subagentReview,
      prReview: runPolicy.prReview,
    },
  };
}

export function normalizeRunPolicy(
  state: DeliveryState,
  config: ResolvedOrchestratorConfig,
): DeliveryState {
  if (state.runPolicy != null) {
    return state;
  }

  return { ...state, runPolicy: deriveRunPolicyFromConfig(config) };
}

/** Persisted tickets may use legacy status and timestamp keys until re-saved. */
type PersistedTicketFields = Partial<TicketState> & {
  internalReviewCompletedAt?: string;
  postVerifySelfAuditCompletedAt?: string;
  status?: string;
};

function pickVerifiedAt(
  ticket: PersistedTicketFields | undefined,
): string | undefined {
  if (!ticket) {
    return undefined;
  }

  return (
    ticket.verifiedAt ??
    ticket.postVerifySelfAuditCompletedAt ??
    ticket.internalReviewCompletedAt
  );
}

function normalizeLegacyTicketStatus(status: string | undefined): TicketStatus {
  if (
    status === 'internally_reviewed' ||
    status === 'post_verify_self_audit_complete'
  ) {
    return 'verified';
  }

  if (status === 'codex_preflight_complete') {
    return 'subagent_review_complete';
  }

  if (status === undefined) {
    return 'pending';
  }

  return status as TicketStatus;
}

export function normalizeDeliveryStateFromPersisted(
  raw: unknown,
): DeliveryState {
  const root = raw as Record<string, unknown>;
  const rawTickets = root.tickets;

  if (!Array.isArray(rawTickets)) {
    return raw as DeliveryState;
  }

  const tickets = rawTickets.map((entry) => {
    const t = entry as PersistedTicketFields & Record<string, unknown>;
    const next: Record<string, unknown> = { ...t };
    delete next.internalReviewCompletedAt;
    next.status = normalizeLegacyTicketStatus(t.status);
    next.verifiedAt = pickVerifiedAt(t);
    delete next.postVerifySelfAuditCompletedAt;
    delete next.internalReviewCompletedAt;
    return next;
  });

  return { ...root, tickets } as DeliveryState;
}

type LoadPlanContextResult = {
  absoluteStatePath: string;
  inferred: DeliveryState;
  ticketDefinitions: TicketDefinition[];
};

type SyncStateDependencies = {
  cwd: string;
  defaultBranch: string;
  deriveBranchName: (
    definition: Pick<TicketDefinition, 'id' | 'slug'>,
  ) => string;
  deriveWorktreePath: (cwd: string, ticketId: string) => string;
};

type RepoInferenceDependencies = SyncStateDependencies & {
  runtime: Runtime;
  findExistingBranch: (
    branches: string[],
    definition: TicketDefinition,
  ) => { branch: string; source: 'ticket-id' | 'derived' } | undefined;
};

export async function loadState(
  cwd: string,
  options: OrchestratorOptions,
  dependencies: RepoInferenceDependencies,
): Promise<DeliveryState> {
  const { absoluteStatePath, inferred, ticketDefinitions } =
    await loadPlanContext(cwd, options, dependencies);

  if (!existsSync(absoluteStatePath)) {
    return syncStateFromScratch(
      ticketDefinitions,
      options,
      inferred,
      dependencies,
    );
  }

  const existing = normalizeDeliveryStateFromPersisted(
    JSON.parse(await readFile(absoluteStatePath, 'utf8')),
  );

  return syncStateFromExisting(
    existing,
    ticketDefinitions,
    options,
    inferred,
    dependencies,
  );
}

export async function repairState(
  cwd: string,
  options: OrchestratorOptions,
  dependencies: RepoInferenceDependencies,
): Promise<{
  state: DeliveryState;
  backupPath?: string;
  changes: string[];
  hadExistingState: boolean;
}> {
  const { absoluteStatePath, inferred, ticketDefinitions } =
    await loadPlanContext(cwd, options, dependencies);
  const hadExistingState = existsSync(absoluteStatePath);

  if (!hadExistingState) {
    const repairedState = syncStateFromScratch(
      ticketDefinitions,
      options,
      inferred,
      dependencies,
    );
    await saveState(cwd, repairedState);

    return {
      state: repairedState,
      changes: [
        'No prior state file existed; wrote clean state from repo reality.',
      ],
      hadExistingState: false,
    };
  }

  const existing = normalizeDeliveryStateFromPersisted(
    JSON.parse(await readFile(absoluteStatePath, 'utf8')),
  );
  const repairedState = syncStateFromExisting(
    existing,
    ticketDefinitions,
    options,
    inferred,
    dependencies,
  );
  const changes = summarizeStateDifferences(existing, repairedState);
  let backupPath: string | undefined;

  if (changes.length > 0) {
    backupPath = await backupStateFile(absoluteStatePath);
  }

  await saveState(cwd, repairedState);

  return {
    state: repairedState,
    backupPath: backupPath ? relativeToRepo(cwd, backupPath) : undefined,
    changes:
      changes.length > 0
        ? changes
        : [
            'Saved state already matched repo reality; rewrote normalized state.',
          ],
    hadExistingState: true,
  };
}

export async function saveState(
  cwd: string,
  state: DeliveryState,
): Promise<void> {
  const absoluteStatePath = resolve(cwd, state.statePath);
  await mkdir(dirname(absoluteStatePath), { recursive: true });
  await writeFile(
    absoluteStatePath,
    JSON.stringify(state, null, 2) + '\n',
    'utf8',
  );
}

export function syncStateFromScratch(
  ticketDefinitions: TicketDefinition[],
  options: OrchestratorOptions,
  inferred: DeliveryState | undefined,
  dependencies: SyncStateDependencies,
): DeliveryState {
  return syncStateWithPlan(
    undefined,
    ticketDefinitions,
    options,
    inferred,
    dependencies,
  );
}

export function syncStateFromExisting(
  existing: DeliveryState,
  ticketDefinitions: TicketDefinition[],
  options: OrchestratorOptions,
  inferred: DeliveryState | undefined,
  dependencies: SyncStateDependencies,
): DeliveryState {
  return syncStateWithPlan(
    existing,
    ticketDefinitions,
    options,
    inferred,
    dependencies,
  );
}

function syncStateWithPlan(
  existing: DeliveryState | undefined,
  ticketDefinitions: TicketDefinition[],
  options: OrchestratorOptions,
  inferred: DeliveryState | undefined,
  dependencies: SyncStateDependencies,
): DeliveryState {
  const existingById = new Map(
    existing?.tickets.map((ticket) => [ticket.id, ticket]),
  );
  const inferredById = new Map(
    inferred?.tickets.map((ticket) => [ticket.id, ticket]),
  );

  return {
    planKey: options.planKey,
    planPath: options.planPath,
    statePath: options.statePath,
    reviewsDirPath: options.reviewsDirPath,
    handoffsDirPath: options.handoffsDirPath,
    reviewPollIntervalMinutes: options.reviewPollIntervalMinutes,
    reviewPollMaxWaitMinutes: options.reviewPollMaxWaitMinutes,
    runPolicy: existing?.runPolicy,
    tickets: ticketDefinitions.map((definition, index) => {
      const previous = existingById.get(definition.id);
      const inferredTicket = inferredById.get(definition.id);
      const previousTicket = ticketDefinitions[index - 1];
      const resolvedBranch = selectBranchValue(
        previous?.branch,
        inferredTicket?.branch,
        dependencies.deriveBranchName(definition),
      );
      const inferredBaseBranch =
        index === 0
          ? dependencies.defaultBranch
          : selectBranchValue(
              existingById.get(previousTicket?.id ?? '')?.branch,
              inferredById.get(previousTicket?.id ?? '')?.branch,
              dependencies.deriveBranchName(previousTicket!),
            );

      return {
        id: definition.id,
        title: definition.title,
        slug: definition.slug,
        ticketFile: definition.ticketFile,
        type: definition.type,
        scope: definition.scope,
        redPolicy: previous?.redPolicy ?? definition.redPolicy,
        status: selectStatusValue(previous?.status, inferredTicket?.status),
        branch: resolvedBranch,
        baseBranch:
          index === 0
            ? dependencies.defaultBranch
            : selectBranchValue(
                previous?.baseBranch,
                inferredTicket?.baseBranch,
                inferredBaseBranch,
              ),
        worktreePath:
          previous?.worktreePath ??
          inferredTicket?.worktreePath ??
          dependencies.deriveWorktreePath(dependencies.cwd, definition.id),
        handoffPath: previous?.handoffPath ?? inferredTicket?.handoffPath,
        handoffGeneratedAt:
          previous?.handoffGeneratedAt ?? inferredTicket?.handoffGeneratedAt,
        redCommitSha: previous?.redCommitSha ?? inferredTicket?.redCommitSha,
        verifiedAt:
          pickVerifiedAt(previous) ??
          pickVerifiedAt(inferredTicket as PersistedTicketFields | undefined),
        verifyOutcome: previous?.verifyOutcome ?? inferredTicket?.verifyOutcome,
        verifyPatchCommits:
          previous?.verifyPatchCommits ?? inferredTicket?.verifyPatchCommits,
        docOnly: (previous?.docOnly ?? inferredTicket?.docOnly) || undefined,
        subagentReviewOutcome:
          previous?.subagentReviewOutcome ??
          inferredTicket?.subagentReviewOutcome,
        subagentReviewCompletedAt:
          previous?.subagentReviewCompletedAt ??
          inferredTicket?.subagentReviewCompletedAt,
        subagentReviewPatchCommits:
          previous?.subagentReviewPatchCommits ??
          inferredTicket?.subagentReviewPatchCommits,
        subagentReviewAgent:
          previous?.subagentReviewAgent ?? inferredTicket?.subagentReviewAgent,
        subagentRunnerArtifactPath:
          previous?.subagentRunnerArtifactPath ??
          inferredTicket?.subagentRunnerArtifactPath,
        subagentAdversarialPromptPath:
          previous?.subagentAdversarialPromptPath ??
          inferredTicket?.subagentAdversarialPromptPath,
        subagentAdversarialPromptWrittenAt:
          previous?.subagentAdversarialPromptWrittenAt ??
          inferredTicket?.subagentAdversarialPromptWrittenAt,
        prNumber: previous?.prNumber ?? inferredTicket?.prNumber,
        prUrl: previous?.prUrl ?? inferredTicket?.prUrl,
        prOpenedAt: previous?.prOpenedAt ?? inferredTicket?.prOpenedAt,
        reviewFetchArtifactPath:
          previous?.reviewFetchArtifactPath ??
          inferredTicket?.reviewFetchArtifactPath,
        reviewTriageArtifactPath:
          previous?.reviewTriageArtifactPath ??
          inferredTicket?.reviewTriageArtifactPath,
        reviewHeadSha: previous?.reviewHeadSha ?? inferredTicket?.reviewHeadSha,
        reviewRecordedAt:
          previous?.reviewRecordedAt ?? inferredTicket?.reviewRecordedAt,
        reviewOutcome: previous?.reviewOutcome ?? inferredTicket?.reviewOutcome,
      };
    }),
  };
}

export function summarizeStateDifferences(
  existing: DeliveryState,
  repaired: DeliveryState,
): string[] {
  const changes: string[] = [];

  if (existing.planKey !== repaired.planKey) {
    changes.push(`planKey ${existing.planKey} -> ${repaired.planKey}`);
  }

  if (existing.planPath !== repaired.planPath) {
    changes.push(`planPath ${existing.planPath} -> ${repaired.planPath}`);
  }

  const existingById = new Map(
    existing.tickets.map((ticket) => [ticket.id, ticket]),
  );

  for (const repairedTicket of repaired.tickets) {
    const existingTicket = existingById.get(repairedTicket.id);

    if (!existingTicket) {
      changes.push(`${repairedTicket.id}: missing from existing state`);
      continue;
    }

    if (existingTicket.status !== repairedTicket.status) {
      changes.push(
        `${repairedTicket.id}: status ${existingTicket.status} -> ${repairedTicket.status}`,
      );
    }

    if (existingTicket.branch !== repairedTicket.branch) {
      changes.push(
        `${repairedTicket.id}: branch ${existingTicket.branch} -> ${repairedTicket.branch}`,
      );
    }

    if (existingTicket.baseBranch !== repairedTicket.baseBranch) {
      changes.push(
        `${repairedTicket.id}: base ${existingTicket.baseBranch} -> ${repairedTicket.baseBranch}`,
      );
    }

    if (existingTicket.worktreePath !== repairedTicket.worktreePath) {
      changes.push(
        `${repairedTicket.id}: worktree ${existingTicket.worktreePath} -> ${repairedTicket.worktreePath}`,
      );
    }

    if (existingTicket.prUrl !== repairedTicket.prUrl) {
      changes.push(
        `${repairedTicket.id}: pr ${existingTicket.prUrl ?? 'none'} -> ${repairedTicket.prUrl ?? 'none'}`,
      );
    }
  }

  for (const existingTicket of existing.tickets) {
    if (
      !repaired.tickets.find((candidate) => candidate.id === existingTicket.id)
    ) {
      changes.push(
        `${existingTicket.id}: present in existing state but absent after repair`,
      );
    }
  }

  return changes;
}

function inferStateFromRepo(
  cwd: string,
  ticketDefinitions: TicketDefinition[],
  options: OrchestratorOptions,
  dependencies: RepoInferenceDependencies,
): DeliveryState {
  const remoteBranches = listRemoteBranches(cwd, dependencies.runtime);
  const localBranches = listLocalBranches(cwd, dependencies.runtime);
  const openPullRequests = listOpenPullRequests(cwd, dependencies.runtime);
  const mergedPullRequests = listMergedPullRequests(cwd, dependencies.runtime);
  const branchCatalog = [
    ...new Set([
      ...localBranches,
      ...remoteBranches,
      ...openPullRequests.keys(),
      ...mergedPullRequests.keys(),
    ]),
  ];

  const tickets = ticketDefinitions.map((definition, index) => {
    const branch =
      dependencies.findExistingBranch(branchCatalog, definition)?.branch ??
      dependencies.deriveBranchName(definition);
    const baseBranch =
      index === 0
        ? dependencies.defaultBranch
        : (dependencies.findExistingBranch(
            branchCatalog,
            ticketDefinitions[index - 1]!,
          )?.branch ??
          dependencies.deriveBranchName(ticketDefinitions[index - 1]!));
    const branchExists = branchCatalog.includes(branch);
    const openPr =
      openPullRequests.get(branch) ??
      findPullRequestForTicket(
        openPullRequests,
        definition,
        dependencies.findExistingBranch,
      );
    const mergedPr =
      mergedPullRequests.get(branch) ??
      findPullRequestForTicket(
        mergedPullRequests,
        definition,
        dependencies.findExistingBranch,
      );
    const pr = openPr ?? mergedPr;
    const nextBranch = ticketDefinitions[index + 1]
      ? (dependencies.findExistingBranch(
          branchCatalog,
          ticketDefinitions[index + 1]!,
        )?.branch ??
        dependencies.deriveBranchName(ticketDefinitions[index + 1]!))
      : undefined;
    const nextBranchExists =
      nextBranch !== undefined && branchCatalog.includes(nextBranch);

    let status: TicketStatus = 'pending';

    if (mergedPr || (branchExists && nextBranchExists)) {
      status = 'done';
    } else if (openPr) {
      status = 'in_review';
    } else if (branchExists) {
      status = 'in_progress';
    }

    return {
      ...definition,
      status,
      branch,
      baseBranch,
      worktreePath: dependencies.deriveWorktreePath(cwd, definition.id),
      handoffPath: undefined,
      handoffGeneratedAt: undefined,
      verifyOutcome: undefined,
      verifyPatchCommits: undefined,
      subagentReviewOutcome: undefined,
      subagentReviewCompletedAt: undefined,
      subagentReviewPatchCommits: undefined,
      prNumber: pr?.number,
      prUrl: pr?.url,
      prOpenedAt: undefined,
      reviewFetchArtifactPath: undefined,
      reviewTriageArtifactPath: undefined,
      reviewHeadSha: undefined,
      reviewRecordedAt: undefined,
      reviewOutcome: undefined,
    } satisfies TicketState;
  });

  return {
    planKey: options.planKey,
    planPath: options.planPath,
    statePath: options.statePath,
    reviewsDirPath: options.reviewsDirPath,
    handoffsDirPath: options.handoffsDirPath,
    reviewPollIntervalMinutes: options.reviewPollIntervalMinutes,
    reviewPollMaxWaitMinutes: options.reviewPollMaxWaitMinutes,
    tickets,
  };
}

async function loadPlanContext(
  cwd: string,
  options: OrchestratorOptions,
  dependencies: RepoInferenceDependencies,
): Promise<LoadPlanContextResult> {
  const planMarkdown = await readFile(resolve(cwd, options.planPath), 'utf8');
  const ticketDefinitions = parsePlan(planMarkdown, options.planPath, cwd);
  const absoluteStatePath = resolve(cwd, options.statePath);
  const inferred = inferStateFromRepo(
    cwd,
    ticketDefinitions,
    options,
    dependencies,
  );

  return {
    absoluteStatePath,
    inferred,
    ticketDefinitions,
  };
}

function findPullRequestForTicket(
  pullRequests: Map<string, PullRequestSummary>,
  definition: TicketDefinition,
  findExistingBranch: (
    branches: string[],
    definition: TicketDefinition,
  ) => { branch: string; source: 'ticket-id' | 'derived' } | undefined,
): PullRequestSummary | undefined {
  const match = findExistingBranch(Array.from(pullRequests.keys()), definition);
  return match ? pullRequests.get(match.branch) : undefined;
}

function selectStatusValue(
  currentStatus: TicketStatus | undefined,
  inferredStatus: TicketStatus | undefined,
): TicketStatus {
  if (!currentStatus) {
    return inferredStatus ?? 'pending';
  }

  if (!inferredStatus) {
    return currentStatus;
  }

  return statusRank(inferredStatus) > statusRank(currentStatus)
    ? inferredStatus
    : currentStatus;
}

function statusRank(status: TicketStatus): number {
  switch (status) {
    case 'pending':
      return 0;
    case 'in_progress':
      return 1;
    case 'red_complete':
      return 2;
    case 'verified':
      return 3;
    case 'subagent_review_complete':
      return 4;
    case 'in_review':
      return 5;
    case 'needs_patch':
      return 6;
    case 'operator_input_needed':
      return 7;
    case 'reviewed':
      return 8;
    case 'done':
      return 9;
  }
}

function selectBranchValue(
  currentBranch: string | undefined,
  inferredBranch: string | undefined,
  fallbackBranch: string,
): string {
  if (inferredBranch) {
    return inferredBranch;
  }

  return currentBranch ?? fallbackBranch;
}

async function backupStateFile(absoluteStatePath: string): Promise<string> {
  const backupPath = absoluteStatePath.replace(
    /\.json$/,
    `.stale-${new Date()
      .toISOString()
      .replace(/[-:]/g, '')
      .replace(/\.\d{3}Z$/, 'Z')}.json`,
  );

  await writeFile(
    backupPath,
    await readFile(absoluteStatePath, 'utf8'),
    'utf8',
  );
  return backupPath;
}

function relativeToRepo(cwd: string, absolutePath: string): string {
  return resolve(absolutePath).replace(`${resolve(cwd)}/`, '');
}
