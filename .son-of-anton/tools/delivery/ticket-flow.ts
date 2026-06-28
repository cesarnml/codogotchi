import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import {
  copyFile,
  mkdir,
  readFile,
  readdir,
  unlink,
  writeFile,
} from 'node:fs/promises';
import { basename, dirname, resolve } from 'node:path';

import type { PullRequestSummary } from './platform';
import type { ReviewActionCommit } from './pr-metadata';
import { buildPrReviewArtifactStem } from './review-artifacts';
import { saveState as saveStateImpl } from './state';
import type { ReviewPolicyStageValue } from './config';
import type {
  DeliveryState,
  InternalReviewPatchCommit,
  ReviewOutcome,
  SubagentReviewOutcome,
  TicketState,
} from './types';

type WorkflowContractCode =
  | 'workflow.advance.requires_reviewed_ticket'
  | 'workflow.open_pr.invalid_state'
  | 'workflow.open_pr.requires_post_verify'
  | 'workflow.post_verify.requires_post_red'
  | 'workflow.open_pr.requires_subagent_review'
  | 'workflow.worktree_guard.wrong_worktree';

type WorkflowContractError = Error & { code: WorkflowContractCode };

export function createWorkflowContractError(
  code: WorkflowContractCode,
  message: string,
): WorkflowContractError {
  return Object.assign(new Error(message), { code });
}

export async function runOptionalDependencyHook<TArgs extends unknown[]>(
  hook: ((...args: TArgs) => Promise<void> | void) | undefined,
  ...args: TArgs
): Promise<void> {
  if (!hook) {
    return;
  }

  await hook(...args);
}

function runOptionalDependencyHookSync<TArgs extends unknown[]>(
  hook: ((...args: TArgs) => void) | undefined,
  ...args: TArgs
): void {
  hook?.(...args);
}

function validateInternalReviewPatchCommits(input: {
  outcome: ReviewOutcome | SubagentReviewOutcome;
  patchCommits: InternalReviewPatchCommit[] | undefined;
  stageLabel: string;
}): void {
  const patchCount = input.patchCommits?.length ?? 0;
  if (input.outcome === 'patched' && patchCount === 0) {
    throw new Error(
      `${input.stageLabel} recorded as patched requires at least one patch commit.`,
    );
  }

  if (input.outcome !== 'patched' && patchCount > 0) {
    throw new Error(
      `${input.stageLabel} patch commits are only allowed when outcome is \`patched\`.`,
    );
  }
}

export function findNextPendingTicket(
  state: DeliveryState,
): TicketState | undefined {
  return state.tickets.find((ticket) => ticket.status === 'pending');
}

export function findTicketByBranch(
  state: DeliveryState,
  branch: string,
): TicketState | undefined {
  return state.tickets.find((ticket) => ticket.branch === branch);
}

export function canAdvanceTicket(ticket: TicketState): boolean {
  return (
    ticket.status === 'reviewed' &&
    (ticket.reviewOutcome === 'clean' ||
      ticket.reviewOutcome === 'patched' ||
      ticket.reviewOutcome === 'skipped')
  );
}

export function buildTicketHandoff(
  state: DeliveryState,
  ticket: Pick<
    TicketState,
    'id' | 'title' | 'ticketFile' | 'branch' | 'baseBranch' | 'worktreePath'
  >,
  modifiedSectionsNote?: string,
  options?: { ticketBoundaryMode?: string; subagentReviewPolicy?: string },
): string {
  const ticketIndex = state.tickets.findIndex(
    (candidate) => candidate.id === ticket.id,
  );
  const previous = ticketIndex > 0 ? state.tickets[ticketIndex - 1] : undefined;
  const requiredReads = [
    'docs/template/overview/start-here.md',
    state.planPath,
    ticket.ticketFile,
    'docs/template/delivery/delivery-orchestrator.md',
  ];
  const lines = [
    '# Ticket Handoff',
    '',
    `Phase plan: ${state.planPath}`,
    `Ticket: ${ticket.id} ${ticket.title}`,
    `Branch: ${ticket.branch}`,
    `Base branch: ${ticket.baseBranch}`,
    `Worktree: ${ticket.worktreePath}`,
    '',
    '## Required Reads',
    '',
    ...requiredReads.map((path) => `- \`${path}\``),
    '',
    '## Context Reset Contract',
    '',
    '- Re-read the required docs before implementing.',
    '- Start from the current repository state and this handoff artifact, not from prior chat assumptions.',
    '- Carry forward only explicit review notes, review artifacts, and committed branch state.',
    '- Do not read ahead during the AI review wait window. The wait is free (LLM idle during subprocess sleep). Be sabaai sabaai.',
  ];

  if (modifiedSectionsNote) {
    lines.push('', '## Modified Sections', '');
    lines.push(
      'Read only the file sections listed here — do not re-read full files.',
    );
    lines.push('');
    lines.push(modifiedSectionsNote);
  }

  if (previous) {
    lines.push('', '## Carry Forward From Previous Ticket', '');
    lines.push(`- Previous ticket: \`${previous.id} ${previous.title}\``);
    lines.push(`- Previous branch: \`${previous.branch}\``);

    if (previous.prUrl) {
      lines.push(`- Previous PR: ${previous.prUrl}`);
    }

    if (previous.reviewOutcome) {
      lines.push(`- Review outcome: \`${previous.reviewOutcome}\``);
    }

    if (previous.reviewFetchArtifactPath ?? previous.reviewArtifactPath) {
      lines.push(
        `- Review fetch artifact: \`${previous.reviewFetchArtifactPath ?? previous.reviewArtifactPath}\``,
      );
    }

    if (previous.reviewTriageArtifactPath ?? previous.reviewArtifactJsonPath) {
      lines.push(
        `- Review triage artifact: \`${previous.reviewTriageArtifactPath ?? previous.reviewArtifactJsonPath}\``,
      );
    }
  }

  lines.push('', '## Stop Conditions', '');
  lines.push(
    '- Stop if the current ticket cannot be completed safely or prerequisite state is missing.',
  );
  lines.push(
    '- Stop if review triage is ambiguous enough to require user input.',
  );
  lines.push(
    '- Stop if the work requires a broader redesign beyond the ticket scope.',
  );

  if (options?.ticketBoundaryMode === 'gated') {
    const nextCommand =
      options.subagentReviewPolicy === 'disabled' ||
      options.subagentReviewPolicy === undefined
        ? 'open-pr'
        : 'subagent-review';
    lines.push('', '## RESUME COMMAND', '');
    lines.push(`\`bun run deliver --plan ${state.planPath} ${nextCommand}\``);
  }

  return lines.join('\n') + '\n';
}

export async function writeTicketHandoff(
  state: DeliveryState,
  cwd: string,
  ticketId: string,
  dependencies: {
    relativeToRepo: (cwd: string, absolutePath: string) => string;
    subagentReviewPolicy?: string;
    ticketBoundaryMode?: string;
  },
): Promise<{ relativePath: string; generatedAt: string }> {
  const ticket = state.tickets.find((candidate) => candidate.id === ticketId);

  if (!ticket) {
    throw new Error(`Unknown ticket ${ticketId}.`);
  }

  const absolutePath = resolve(
    cwd,
    state.handoffsDirPath,
    `${ticket.id.toLowerCase().replace('.', '-')}-handoff.md`,
  );
  const generatedAt = new Date().toISOString();

  const modifiedSectionsNote = await extractScopeSection(
    resolve(cwd, ticket.ticketFile),
  );

  await mkdir(dirname(absolutePath), { recursive: true });
  await writeFile(
    absolutePath,
    buildTicketHandoff(state, ticket, modifiedSectionsNote, {
      ticketBoundaryMode: dependencies.ticketBoundaryMode,
      subagentReviewPolicy: dependencies.subagentReviewPolicy,
    }),
    'utf8',
  );

  return {
    relativePath: dependencies.relativeToRepo(cwd, absolutePath),
    generatedAt,
  };
}

async function extractScopeSection(
  ticketFilePath: string,
): Promise<string | undefined> {
  try {
    const content = await readFile(ticketFilePath, 'utf8');
    const lines = content.split('\n');
    const startIdx = lines.findIndex((line) => /^##\s+Scope/.test(line));

    if (startIdx === -1) {
      return undefined;
    }

    const sectionLines: string[] = [];

    for (let i = startIdx + 1; i < lines.length; i++) {
      const line = lines[i]!;
      if (/^##\s/.test(line)) {
        break;
      }
      sectionLines.push(line);
    }

    const body = sectionLines.join('\n').trim();
    return body.length > 0 ? body : undefined;
  } catch {
    return undefined;
  }
}

export async function startTicket(
  state: DeliveryState,
  cwd: string,
  ticketId: string | undefined,
  dependencies: {
    addWorktree: (
      cwd: string,
      worktreePath: string,
      branch: string,
      baseBranch: string,
    ) => void;
    bootstrapWorktreeIfNeeded: (worktreePath: string) => Promise<void>;
    copyLocalBootstrapFilesIfPresent: (
      sourceWorktreePath: string,
      targetWorktreePath: string,
    ) => Promise<void>;
    materializeTicketContext?: (
      state: DeliveryState,
      sourceWorktreePath: string,
      ticketId: string,
    ) => Promise<void>;
    relativeToRepo: (cwd: string, absolutePath: string) => string;
    subagentReviewPolicy?: string;
    ticketBoundaryMode?: string;
  },
): Promise<DeliveryState> {
  const active = state.tickets.find(
    (ticket) => ticket.status === 'in_progress',
  );

  if (active && ticketId && active.id !== ticketId) {
    throw new Error(`Ticket ${active.id} is already in progress.`);
  }

  const target =
    (ticketId
      ? state.tickets.find((ticket) => ticket.id === ticketId)
      : (active ?? findNextPendingTicket(state))) ?? undefined;

  if (!target) {
    throw new Error('No pending ticket found.');
  }

  const targetIndex = state.tickets.findIndex(
    (ticket) => ticket.id === target.id,
  );
  const previous = targetIndex > 0 ? state.tickets[targetIndex - 1] : undefined;

  if (previous && previous.status !== 'done') {
    throw new Error(
      `Cannot start ${target.id} before ${previous.id} is marked done.`,
    );
  }

  if (target.status === 'in_progress') {
    await runOptionalDependencyHook(
      dependencies.materializeTicketContext,
      state,
      cwd,
      target.id,
    );
    return state;
  }

  if (!existsSync(target.worktreePath)) {
    dependencies.addWorktree(
      cwd,
      target.worktreePath,
      target.branch,
      target.baseBranch,
    );
  }

  await dependencies.copyLocalBootstrapFilesIfPresent(cwd, target.worktreePath);
  await dependencies.bootstrapWorktreeIfNeeded(target.worktreePath);

  const handoff = await writeTicketHandoff(state, cwd, target.id, {
    relativeToRepo: dependencies.relativeToRepo,
    subagentReviewPolicy: dependencies.subagentReviewPolicy,
    ticketBoundaryMode: dependencies.ticketBoundaryMode,
  });

  const nextState: DeliveryState = {
    ...state,
    tickets: state.tickets.map((ticket) =>
      ticket.id === target.id
        ? {
            ...ticket,
            status: 'in_progress' as const,
            handoffPath: handoff.relativePath,
            handoffGeneratedAt: handoff.generatedAt,
          }
        : ticket,
    ),
  };

  await runOptionalDependencyHook(
    dependencies.materializeTicketContext,
    nextState,
    cwd,
    target.id,
  );

  return nextState;
}

export function recordPostVerify(
  state: DeliveryState,
  ticketId?: string,
  outcome?: ReviewOutcome,
  patchCommits?: InternalReviewPatchCommit[],
  now: () => string = () => new Date().toISOString(),
): DeliveryState {
  const target =
    (ticketId
      ? state.tickets.find((ticket) => ticket.id === ticketId)
      : (state.tickets.find((ticket) => ticket.status === 'red_complete') ??
        state.tickets.find((ticket) => ticket.status === 'in_progress'))) ??
    undefined;

  if (!target) {
    throw new Error('No in-progress ticket found to mark verified.');
  }

  if (target.status === 'verified') {
    return state;
  }

  if (target.status !== 'in_progress' && target.status !== 'red_complete') {
    throw new Error(
      `Ticket ${target.id} must be in progress or red_complete before post-verify can be recorded.`,
    );
  }

  const completedAt = now();
  const resolvedOutcome: ReviewOutcome = outcome ?? 'clean';
  validateInternalReviewPatchCommits({
    outcome: resolvedOutcome,
    patchCommits,
    stageLabel: 'Post-verify',
  });

  return {
    ...state,
    tickets: state.tickets.map((ticket) =>
      ticket.id === target.id
        ? {
            ...ticket,
            status: 'verified' as const,
            verifiedAt: completedAt,
            verifyOutcome: resolvedOutcome,
            verifyPatchCommits: patchCommits,
          }
        : ticket,
    ),
  };
}

export function recordPostRed(
  state: DeliveryState,
  input: {
    headSha: string;
    latestCommitSubject: string;
    ticketId?: string;
    verifyExitCode: number;
  },
): DeliveryState {
  const target =
    (input.ticketId
      ? state.tickets.find((ticket) => ticket.id === input.ticketId)
      : state.tickets.find((ticket) => ticket.status === 'in_progress')) ??
    undefined;

  if (!target) {
    throw new Error('No in-progress ticket found to mark red_complete.');
  }

  if (target.status === 'red_complete') {
    return state;
  }

  if (target.status !== 'in_progress') {
    throw new Error(
      `Ticket ${target.id} must be in progress before post-red can be recorded.`,
    );
  }

  if (!input.latestCommitSubject.includes('[red]')) {
    throw new Error(
      `Ticket ${target.id} post-red requires a HEAD commit subject containing \`[red]\`. ` +
        `Either author a \`[red]\` commit before continuing, or declare \`Red: skip\` in the ticket metadata if the ticket has no testable behavior.`,
    );
  }

  if (input.verifyExitCode === 0) {
    throw new Error(
      `Ticket ${target.id} post-red requires a failing verification run before delivery can advance. ` +
        `Either author a \`[red]\` commit (with a test that genuinely fails) before continuing, or declare \`Red: skip\` in the ticket metadata if the ticket has no testable behavior.`,
    );
  }

  return {
    ...state,
    tickets: state.tickets.map((ticket) =>
      ticket.id === target.id
        ? {
            ...ticket,
            status: 'red_complete' as const,
            redCommitSha: input.headSha,
          }
        : ticket,
    ),
  };
}

export function recordSubagentReview(
  state: DeliveryState,
  outcome?: 'clean' | 'patched' | 'skipped',
  isDocOnly?: boolean,
  policy: ReviewPolicyStageValue = 'skip_doc_only',
  patchCommits?: InternalReviewPatchCommit[],
  agentName?: string,
  now: () => string = () => new Date().toISOString(),
  ticketId?: string,
  artifactPath?: string,
): DeliveryState {
  const target =
    (ticketId
      ? state.tickets.find((ticket) => ticket.id === ticketId)
      : state.tickets.find((ticket) => ticket.status === 'verified')) ??
    undefined;

  if (!target) {
    throw new Error(
      ticketId
        ? `Unknown ticket ${ticketId}.`
        : 'No ticket at verified status found to record subagent review.',
    );
  }

  if (target.status !== 'verified') {
    throw new Error(
      `Ticket ${target.id} must be at verified status before subagent review can be recorded.`,
    );
  }

  const docOnly = isDocOnly ?? !!target.docOnly;
  let resolvedOutcome: SubagentReviewOutcome;

  if (outcome === 'skipped' || (policy === 'skip_doc_only' && docOnly)) {
    if (outcome === 'skipped' && policy === 'required') {
      throw new Error(
        `Ticket ${target.id} subagentReview is set to "required" — cannot record skipped. Pass \`clean\` or \`patched\`.`,
      );
    }
    resolvedOutcome = 'skipped';
  } else if (outcome === 'clean' || outcome === 'patched') {
    resolvedOutcome = outcome;
  } else {
    throw new Error(
      `Ticket ${target.id} requires a subagent review outcome. Pass \`clean\`, \`patched\`, or \`skipped\`.`,
    );
  }
  validateInternalReviewPatchCommits({
    outcome: resolvedOutcome,
    patchCommits,
    stageLabel: 'Subagent review',
  });

  const completedAt = now();

  return {
    ...state,
    tickets: state.tickets.map((ticket) =>
      ticket.id === target.id
        ? {
            ...ticket,
            status: 'subagent_review_complete' as const,
            subagentReviewOutcome: resolvedOutcome,
            subagentReviewCompletedAt: completedAt,
            subagentReviewPatchCommits: patchCommits,
            subagentReviewAgent: agentName,
            subagentRunnerArtifactPath: artifactPath,
          }
        : ticket,
    ),
  };
}

export function openPullRequest(
  state: DeliveryState,
  cwd: string,
  ticketId: string | undefined,
  dependencies: {
    assertReviewerFacingMarkdown: (markdown: string) => void;
    buildPullRequestBody: (
      state: DeliveryState,
      ticket: TicketState,
      options?: {
        actionCommits?: ReviewActionCommit[];
        currentHeadSha?: string;
        githubRepo?: { defaultBranch: string; name: string; owner: string };
      },
    ) => string;
    buildPullRequestTitle: (
      ticket: Pick<
        TicketState,
        'id' | 'title' | 'ticketFile' | 'type' | 'scope'
      >,
    ) => string;
    subagentReviewPolicy?: ReviewPolicyStageValue;
    createPullRequest: (
      cwd: string,
      options: {
        base: string;
        body: string;
        head: string;
        title: string;
      },
    ) => { number: number; url: string };
    editPullRequest: (
      cwd: string,
      prNumber: number,
      options: {
        base?: string;
        body?: string;
        title?: string;
      },
    ) => void;
    ensureBranchPushed: (cwd: string, branch: string) => void;
    findOpenPullRequest: (
      cwd: string,
      branch: string,
    ) => PullRequestSummary | undefined;
    reportProgress?: (message: string) => void;
    resolveGitHubRepo?: (
      cwd: string,
    ) => { defaultBranch: string; name: string; owner: string } | undefined;
  },
): DeliveryState {
  const target =
    (ticketId
      ? state.tickets.find((ticket) => ticket.id === ticketId)
      : (state.tickets.find(
          (ticket) => ticket.status === 'subagent_review_complete',
        ) ??
        state.tickets.find((ticket) => ticket.status === 'red_complete') ??
        state.tickets.find((ticket) => ticket.status === 'verified') ??
        state.tickets.find((ticket) => ticket.status === 'in_review') ??
        state.tickets.find((ticket) => ticket.status === 'in_progress'))) ??
    undefined;

  if (!target) {
    throw createWorkflowContractError(
      'workflow.open_pr.invalid_state',
      'No ticket in a PR-openable state found to open as a PR.',
    );
  }

  if (target.status === 'in_progress' || target.status === 'red_complete') {
    throw createWorkflowContractError(
      'workflow.open_pr.requires_post_verify',
      `Ticket ${target.id} is at status ${target.status}. Complete post-verify before opening a PR.`,
    );
  }

  if (
    target.status === 'verified' &&
    dependencies.subagentReviewPolicy !== undefined &&
    dependencies.subagentReviewPolicy !== 'disabled'
  ) {
    throw createWorkflowContractError(
      'workflow.open_pr.requires_subagent_review',
      `Ticket ${target.id} is at status verified and requires subagent-review before opening a PR. Run \`bun run deliver --plan ${state.planPath} subagent-review <clean|patched|skipped>\` after completing the subagent review step. If the subagent is unavailable, set subagentReview to "disabled" in orchestrator.config.json to bypass.`,
    );
  }

  if (
    target.status !== 'verified' &&
    target.status !== 'subagent_review_complete' &&
    target.status !== 'in_review'
  ) {
    throw createWorkflowContractError(
      'workflow.open_pr.invalid_state',
      `Ticket ${target.id} is not in a PR-openable state. Current status: ${target.status}.`,
    );
  }

  runOptionalDependencyHookSync(
    dependencies.reportProgress,
    `open-pr: publishing branch ${target.branch} to origin (push hooks may take a bit)...`,
  );
  dependencies.ensureBranchPushed(target.worktreePath, target.branch);

  const title = dependencies.buildPullRequestTitle(target);
  const body = dependencies.buildPullRequestBody(state, target, {
    githubRepo: dependencies.resolveGitHubRepo?.(target.worktreePath),
  });
  dependencies.assertReviewerFacingMarkdown(body);
  const existingPullRequest = dependencies.findOpenPullRequest(
    target.worktreePath,
    target.branch,
  );
  let prUrl: string;
  let prNumber: number;

  if (existingPullRequest) {
    runOptionalDependencyHookSync(
      dependencies.reportProgress,
      `open-pr: updating PR #${existingPullRequest.number} on GitHub...`,
    );
    dependencies.editPullRequest(
      target.worktreePath,
      existingPullRequest.number,
      {
        base: target.baseBranch,
        body,
        title,
      },
    );
    prUrl = existingPullRequest.url;
    prNumber = existingPullRequest.number;
  } else {
    runOptionalDependencyHookSync(
      dependencies.reportProgress,
      'open-pr: creating PR on GitHub...',
    );
    const pullRequest = dependencies.createPullRequest(target.worktreePath, {
      base: target.baseBranch,
      body,
      head: target.branch,
      title,
    });
    prUrl = pullRequest.url;
    prNumber = pullRequest.number;
  }

  runOptionalDependencyHookSync(
    dependencies.reportProgress,
    `open-pr: PR ready ${prUrl}`,
  );

  const now = new Date().toISOString();

  return {
    ...state,
    tickets: state.tickets.map((ticket) =>
      ticket.id === target.id
        ? {
            ...ticket,
            status: 'in_review',
            prUrl,
            prNumber,
            prOpenedAt: ticket.prOpenedAt ?? now,
          }
        : ticket,
    ),
  };
}

export async function advanceToNextTicket(
  state: DeliveryState,
  cwd: string,
  dependencies: {
    ensureBranchPushed?: (cwd: string, branch: string) => void;
    updatePullRequestBody: (state: DeliveryState, ticket: TicketState) => void;
  },
): Promise<DeliveryState> {
  const current = state.tickets.find((ticket) => ticket.status === 'reviewed');

  if (!current) {
    const activeTicket =
      state.tickets.find((t) => t.status === 'in_progress') ??
      state.tickets.find((t) => t.status === 'verified') ??
      state.tickets.find((t) => t.status === 'subagent_review_complete') ??
      state.tickets.find((t) => t.status === 'in_review') ??
      state.tickets.find((t) => t.status === 'needs_patch') ??
      state.tickets.find((t) => t.status === 'operator_input_needed');
    if (activeTicket) {
      throw createWorkflowContractError(
        'workflow.advance.requires_reviewed_ticket',
        `No reviewed ticket is ready to advance. Active ticket ${activeTicket.id} is at status ${activeTicket.status}.`,
      );
    }
    throw createWorkflowContractError(
      'workflow.advance.requires_reviewed_ticket',
      'No reviewed ticket is ready to advance.',
    );
  }

  if (!canAdvanceTicket(current)) {
    throw new Error(
      `Ticket ${current.id} cannot advance until review is recorded as clean, patched, or skipped.`,
    );
  }

  dependencies.ensureBranchPushed?.(current.worktreePath, current.branch);
  dependencies.updatePullRequestBody(state, current);

  return {
    ...state,
    tickets: state.tickets.map((ticket) =>
      ticket.id === current.id ? { ...ticket, status: 'done' } : ticket,
    ),
  };
}

function ticketHandoffFileName(ticketId: string): string {
  return `${ticketId.toLowerCase().replace('.', '-')}-handoff.md`;
}

async function copyFileIntoWorktree(
  sourcePath: string,
  targetPath: string,
): Promise<void> {
  if (!existsSync(sourcePath) || resolve(sourcePath) === resolve(targetPath)) {
    return;
  }

  await mkdir(dirname(targetPath), { recursive: true });
  await copyFile(sourcePath, targetPath);
}

function listTrackedFileNamesInDir(
  worktreePath: string,
  relativeDirPath: string,
): Set<string> {
  const result = spawnSync('git', ['ls-files', '--', relativeDirPath], {
    cwd: worktreePath,
    encoding: 'utf8',
  });
  if (result.status !== 0 || result.stdout.trim().length === 0) {
    return new Set();
  }

  const tracked = new Set<string>();
  for (const line of result.stdout.split('\n')) {
    const trimmed = line.trim();
    if (trimmed.length === 0) {
      continue;
    }
    tracked.add(basename(trimmed));
  }
  return tracked;
}

async function copyTicketScopedArtifacts(input: {
  artifactDirPath: string;
  artifactNames: Set<string>;
  sourceWorktreePath: string;
  targetWorktreePath: string;
}): Promise<void> {
  const sourceDir = resolve(input.sourceWorktreePath, input.artifactDirPath);
  if (!existsSync(sourceDir) || input.artifactNames.size === 0) {
    return;
  }

  const targetDir = resolve(input.targetWorktreePath, input.artifactDirPath);
  const trackedInTarget = listTrackedFileNamesInDir(
    input.targetWorktreePath,
    input.artifactDirPath,
  );
  if (existsSync(targetDir)) {
    for (const fileName of await readdir(targetDir)) {
      if (
        !input.artifactNames.has(fileName) &&
        !trackedInTarget.has(fileName)
      ) {
        await unlink(resolve(targetDir, fileName));
      }
    }
  }

  for (const fileName of await readdir(sourceDir)) {
    if (!input.artifactNames.has(fileName)) {
      continue;
    }

    await copyFileIntoWorktree(
      resolve(sourceDir, fileName),
      resolve(input.targetWorktreePath, input.artifactDirPath, fileName),
    );
  }
}

export async function materializeTicketContext(
  state: DeliveryState,
  sourceWorktreePath: string,
  ticketId: string,
): Promise<void> {
  const targetIndex = state.tickets.findIndex(
    (ticket) => ticket.id === ticketId,
  );
  const target = targetIndex >= 0 ? state.tickets[targetIndex] : undefined;

  if (!target) {
    throw new Error(`Unknown ticket ${ticketId}.`);
  }

  const previous = targetIndex > 0 ? state.tickets[targetIndex - 1] : undefined;
  await saveStateImpl(target.worktreePath, state);

  const handoffNames = new Set<string>([
    ticketHandoffFileName(target.id),
    ...(previous ? [ticketHandoffFileName(previous.id)] : []),
  ]);
  const reviewNames = new Set<string>();
  const scopedTickets = [target, previous].filter(
    (ticket): ticket is TicketState => ticket !== undefined,
  );
  for (const ticket of scopedTickets) {
    const artifactStem = buildPrReviewArtifactStem(ticket.id);
    for (const fileName of [
      `${artifactStem}.fetch.json`,
      `${artifactStem}.triage.json`,
    ]) {
      reviewNames.add(fileName);
    }
  }

  await copyTicketScopedArtifacts({
    artifactDirPath: state.handoffsDirPath,
    artifactNames: handoffNames,
    sourceWorktreePath,
    targetWorktreePath: target.worktreePath,
  });
  await copyTicketScopedArtifacts({
    artifactDirPath: state.reviewsDirPath,
    artifactNames: reviewNames,
    sourceWorktreePath,
    targetWorktreePath: target.worktreePath,
  });
}

export function restackTicket(
  state: DeliveryState,
  cwd: string,
  ticketId: string | undefined,
  dependencies: {
    buildPullRequestBody: (
      state: DeliveryState,
      ticket: TicketState,
      options?: {
        actionCommits?: ReviewActionCommit[];
        currentHeadSha?: string;
        githubRepo?: { defaultBranch: string; name: string; owner: string };
      },
    ) => string;
    defaultBranch: string;
    deliveryBaseBranch: string;
    editPullRequest: (
      cwd: string,
      prNumber: number,
      options: {
        base?: string;
        body?: string;
        title?: string;
      },
    ) => void;
    ensureCleanWorktree: (cwd: string) => void;
    fetchOrigin: (cwd: string) => void;
    findOpenPullRequest: (
      cwd: string,
      branch: string,
    ) => PullRequestSummary | undefined;
    hasMergedPullRequestForBranch: (cwd: string, branch: string) => boolean;
    readCurrentBranch: (cwd: string) => string;
    readMergeBase: (
      cwd: string,
      branch: string,
      previousBranch: string,
    ) => string;
    rebaseOnto: (cwd: string, rebaseTarget: string, oldBase: string) => void;
    rebaseOntoDefaultBranch: (cwd: string, defaultBranch: string) => void;
    resolveGitHubRepo?: (
      cwd: string,
    ) => { defaultBranch: string; name: string; owner: string } | undefined;
  },
): DeliveryState {
  dependencies.ensureCleanWorktree(cwd);
  const currentBranch = dependencies.readCurrentBranch(cwd);
  const target =
    (ticketId
      ? state.tickets.find((ticket) => ticket.id === ticketId)
      : findTicketByBranch(state, currentBranch)) ?? undefined;

  if (!target) {
    throw new Error(
      ticketId
        ? `Unknown ticket ${ticketId}.`
        : `Current branch ${currentBranch} is not tracked by the delivery plan.`,
    );
  }

  if (target.branch !== currentBranch) {
    throw new Error(
      `Restack must run from ${target.branch}. Current branch is ${currentBranch}.`,
    );
  }

  dependencies.fetchOrigin(cwd);

  const targetIndex = state.tickets.findIndex(
    (ticket) => ticket.id === target.id,
  );
  const previous = targetIndex > 0 ? state.tickets[targetIndex - 1] : undefined;

  let nextBaseBranch = dependencies.deliveryBaseBranch;
  let rebaseTarget = `origin/${dependencies.deliveryBaseBranch}`;

  if (previous) {
    const oldBase = dependencies.readMergeBase(
      cwd,
      target.branch,
      previous.branch,
    );

    if (!oldBase) {
      throw new Error(
        `Could not determine the shared ancestor between ${target.branch} and ${previous.branch}.`,
      );
    }

    if (!dependencies.hasMergedPullRequestForBranch(cwd, previous.branch)) {
      nextBaseBranch = previous.branch;
      rebaseTarget = previous.branch;
    }

    dependencies.rebaseOnto(cwd, rebaseTarget, oldBase);
  } else {
    dependencies.rebaseOntoDefaultBranch(cwd, dependencies.deliveryBaseBranch);
  }

  const nextState: DeliveryState = {
    ...state,
    tickets: state.tickets.map((ticket) =>
      ticket.id === target.id
        ? {
            ...ticket,
            baseBranch: nextBaseBranch,
          }
        : ticket,
    ),
  };
  const updatedTarget = nextState.tickets.find(
    (ticket) => ticket.id === target.id,
  );

  if (!updatedTarget) {
    throw new Error(`Unknown ticket ${target.id}.`);
  }

  const pullRequest = dependencies.findOpenPullRequest(cwd, target.branch);

  if (pullRequest) {
    dependencies.editPullRequest(cwd, pullRequest.number, {
      base: nextBaseBranch,
      body: dependencies.buildPullRequestBody(nextState, updatedTarget, {
        githubRepo: dependencies.resolveGitHubRepo?.(cwd),
      }),
    });
  }

  return nextState;
}
