import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { realpath } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import {
  getUsage,
  isStandaloneTriageCommand,
  parseCliArgs,
  resolveOptionsForCommand,
  resolveRuntimePolicyOverrides,
  TICKET_TRIAGE_COMMAND,
} from './cli';
import { ensureEnvReady as ensureEnvReadyImpl } from './env';
import {
  generateRunDeliverInvocation,
  loadOrchestratorConfig,
  resolveOrchestratorConfig,
} from './runtime-config';
import type {
  ResolvedOrchestratorConfig,
  ReviewPolicyStageValue,
  TicketBoundaryMode,
} from './config';
import type {
  DeliveryState,
  InternalReviewPatchCommit,
  OrchestratorOptions,
  ReviewOutcome,
  ReviewResult,
  StandaloneAiReviewResult,
  TicketDefinition,
  TicketState,
} from './types';
import {
  createDeliveryOrchestratorContext,
  type DeliveryOrchestratorContext,
} from './context';
import {
  copyLocalBootstrapFilesIfPresent as copyPlatformBootstrapFilesIfPresent,
  copyLocalEnvIfPresent as copyPlatformEnvIfPresent,
  findPrimaryWorktreePath as findPlatformPrimaryWorktreePath,
  isLocalBranchDocOnly as isPlatformLocalBranchDocOnly,
  type Runtime,
} from './platform';
import {
  createOptions as createOptionsImpl,
  deriveBranchName,
  derivePlanKey as derivePlanKeyImpl,
  deriveWorktreePath,
  findExistingBranch,
  inferPlanPathFromBranch as inferPlanPathFromBranchImpl,
  parsePlan as parsePlanImpl,
  relativeToRepo,
  resolvePlanPathForBranch as resolvePlanPathForBranchImpl,
} from './planning';
import {
  applyRunPolicyToConfig,
  deriveRunPolicyFromConfig,
  detectRunPolicyDivergence,
  formatRunPolicyDivergenceError,
  loadState as loadStateImpl,
  normalizeRunPolicy,
  patchRunPolicyWithFlags,
  repairState as repairStateImpl,
  saveState as saveStateImpl,
  summarizeStateDifferences as summarizeStateDifferencesImpl,
  syncStateFromExisting as syncStateFromExistingImpl,
  syncStateFromScratch as syncStateFromScratchImpl,
} from './state';
import {
  buildRunBlockedEvent,
  buildStandaloneReviewRecordedEvent,
  emitNotificationWarnings,
  eventsForAdvanceCommand,
  eventsForOpenPrCommand,
  eventsForPollReviewCommand,
  eventsForReconcileLateReviewCommand,
  eventsForRecordReviewCommand,
  eventsForStartCommand,
  formatReviewWindowMessage,
  resolveNotifier,
  type DeliveryNotifier,
} from './notifications';
import {
  assertReviewerFacingMarkdown,
  buildPullRequestBody,
  buildPullRequestTitle,
  buildStandaloneReviewStartedEvent,
} from './pr-metadata';
import {
  formatAdvanceBoundaryGuidance,
  formatCurrentTicketStatus,
  formatRepairSummary,
  formatStandaloneAiReviewResult,
  formatStatus,
  resolveNextCommand,
  type RepairStateResult,
} from './format';
import {
  recordTicketReview,
  runReconcileLateTicketReview,
  runStandaloneAiReviewLifecycle,
  runTicketReviewLifecycle,
  type StandaloneAiReviewDependencies,
  type TicketReviewDependencies,
} from './review';
import {
  readAdvisoryObservationDispositionInput,
  runAdvisoryObservationTriage,
} from './advisory-observation-command';
import {
  advanceToNextTicket,
  createWorkflowContractError,
  materializeTicketContext,
  openPullRequest as openPullRequestImpl,
  recordSubagentReview as recordSubagentReviewImpl,
  recordPostRed as recordPostRedImpl,
  recordPostVerify as recordPostVerifyImpl,
  restackTicket as restackTicketImpl,
  startTicket as startTicketImpl,
} from './ticket-flow';
import {
  ReconciliationBlockedError,
  reconcileReview,
  recordAcknowledgment,
  recordDeferred,
} from './reconciliation';
import {
  appendInvocationToArtifact,
  buildRunnerSpawnCommand,
  buildRunnerInvocation,
  coerceClaudeCliClassification,
  coerceCodexCliClassification,
  coerceCursorCliClassification,
  decideAdvisoryRunnerOutcome,
  decideSubagentReviewMode,
  findDeliveryDocPaths,
  parseSubagentReviewArgs,
  readSubagentRunnerArtifact,
  resolvePrimaryAgent,
  resolveSubagentSelection,
  runSubagentWithFallback,
  shouldFallbackToOtherRunner,
  SUBAGENT_LEDGER_SCHEMA_VERSION,
  tryReadSubagentRunnerArtifact,
  tryRunner,
  writeSubagentReviewOutcome,
  type SubagentRunnerTerminatedReason,
} from './subagent-runner';
import {
  assertSubagentAdversarialPromptPresent,
  requireSubagentAdversarialPromptForRunner,
  writeSubagentAdversarialPrompt,
} from './subagent-prompt';
import { readFileSync, writeFileSync } from 'node:fs';
import { GATE_NAMES, writeGateEvent } from './codogotchi-gate';

export const WORKTREE_EXEMPT = new Set(['status', 'sync', 'start']);

export function commitDeliveryArtifactAndPush(input: {
  absolutePath: string;
  /** Additional repo files to include in the same commit (e.g. review sidecars). */
  alsoCommitAbsolutePaths?: string[];
  branch: string;
  commitMessage: string;
  ensureBranchPushed: (cwd: string, branch: string) => void;
  relativeToRepo: (cwd: string, absolutePath: string) => string;
  repoRoot: string;
  runProcess: (cwd: string, cmd: string[]) => string;
}): boolean {
  try {
    input.runProcess(input.repoRoot, ['git', 'rev-parse', '--git-dir']);
  } catch {
    return false;
  }

  const pathsToStage = [
    input.absolutePath,
    ...(input.alsoCommitAbsolutePaths ?? []),
  ].filter((path) => existsSync(path));

  if (pathsToStage.length === 0) {
    return false;
  }

  const relativePaths = pathsToStage
    .map((path) => input.relativeToRepo(input.repoRoot, path))
    .filter((path) => path.length > 0);

  if (relativePaths.length === 0) {
    return false;
  }

  input.runProcess(input.repoRoot, ['git', 'add', '--', ...relativePaths]);
  const stagedNames = input.runProcess(input.repoRoot, [
    'git',
    'diff',
    '--cached',
    '--name-only',
  ]);

  if (!stagedNames.trim()) {
    return false;
  }

  input.runProcess(input.repoRoot, [
    'git',
    'commit',
    '-m',
    input.commitMessage,
  ]);
  input.ensureBranchPushed(input.repoRoot, input.branch);
  return true;
}

export function assertWorktreeGuard(
  cwd: string,
  command: string,
  positionals: string[],
  state: DeliveryState,
  config: ResolvedOrchestratorConfig,
): void {
  if (WORKTREE_EXEMPT.has(command)) return;

  const activeTicket =
    state.tickets.find((t) => t.status === 'in_progress') ??
    state.tickets.find((t) => t.status === 'red_complete') ??
    state.tickets.find((t) => t.status === 'verified') ??
    state.tickets.find((t) => t.status === 'subagent_review_complete') ??
    state.tickets.find((t) => t.status === 'in_review') ??
    state.tickets.find((t) => t.status === 'needs_patch') ??
    state.tickets.find((t) => t.status === 'operator_input_needed') ??
    state.tickets.find((t) => t.status === 'reviewed');

  if (!activeTicket) return;

  const resolvedCwd = cwd;
  const expectedPath = (() => {
    try {
      return realpathSync(activeTicket.worktreePath);
    } catch {
      return resolve(activeTicket.worktreePath);
    }
  })();

  if (resolvedCwd !== expectedPath) {
    const invoke = generateRunDeliverInvocation(config.packageManager);
    const recoveryArgs = [command, ...positionals].join(' ');
    const recovery = `cd ${expectedPath} && ${invoke} --plan ${state.planPath} ${recoveryArgs}`;
    const nextCommand = resolveNextCommand(
      activeTicket.status,
      config,
      state.planPath,
      activeTicket.id,
      activeTicket,
    );
    const nextCommandHint = nextCommand
      ? `\nNext command from worktree: ${nextCommand}`
      : '';
    throw createWorkflowContractError(
      'workflow.worktree_guard.wrong_worktree',
      `Command '${command}' for ticket ${activeTicket.id} must be run from its worktree.\n` +
        `Current directory: ${resolvedCwd}\n` +
        `Expected worktree: ${expectedPath}\n` +
        `Recovery: ${recovery}` +
        nextCommandHint,
    );
  }
}

export async function runDeliveryOrchestrator(
  argv: string[],
  cwd: string,
): Promise<number> {
  let parsed:
    | {
        command: string;
        positionals: string[];
        flags: Set<string>;
        planPath?: string;
        prNumber?: number;
        boundaryMode?: TicketBoundaryMode;
        subagentReviewPolicy?: ReviewPolicyStageValue;
        prReviewPolicy?: ReviewPolicyStageValue;
        subagent?: 'claude-cli' | 'codex-cli' | 'cursor-cli';
        primary?: string;
        baseline?: 'orchestrator' | 'run-policy';
        dispositionsPath?: string;
      }
    | undefined;

  try {
    const rawConfig = await loadOrchestratorConfig(cwd);
    const initialConfig = resolveOrchestratorConfig(rawConfig, cwd);
    await ensureEnvReadyImpl(cwd, (worktreePath) =>
      findPrimaryWorktreePath(worktreePath, initialConfig),
    );
    const usage = getUsage(
      generateRunDeliverInvocation(initialConfig.packageManager),
    );
    parsed = parseCliArgs(argv, usage);
    const resolvedConfig = resolveOrchestratorConfig(
      resolveRuntimePolicyOverrides(parsed, rawConfig),
      cwd,
    );
    let context = createDeliveryOrchestratorContext(resolvedConfig);
    const platform = context.platform;
    const notifier = resolveNotifier();
    // Always emit SoA events into the primary worktree's .soa/, regardless of
    // which worktree directory bun was invoked from.
    if (isStandaloneTriageCommand(parsed.command)) {
      const result = await runStandaloneAiReview(
        cwd,
        notifier,
        context,
        parsed.prNumber,
      );
      console.log(formatStandaloneAiReviewResult(result));
      await emitNotificationWarnings(notifier, cwd, [
        buildStandaloneReviewRecordedEvent(result),
      ]);
      return 0;
    }
    const options = await resolveOptionsForCommand({
      command: parsed.command,
      createOptions,
      cwd,
      inferPlanPathFromBranch: (worktreePath, branch) =>
        inferPlanPathFromBranch(worktreePath, branch, context.config),
      planPath: parsed.planPath,
      readCurrentBranch: platform.readCurrentBranch,
    });
    parsed = {
      ...parsed,
      planPath: options.planPath,
    };

    if (parsed.command === 'repair-state') {
      const repaired = await repairState(cwd, options, context.config);
      console.log(
        [
          formatStatus(repaired.state, context.config),
          formatRepairSummary(repaired),
        ]
          .filter(Boolean)
          .join('\n\n'),
      );
      return 0;
    }

    const { state: loadedState, hadPersistedRunPolicy }: LoadStateResult =
      await loadState(cwd, options, context.config);

    // Divergence check: when a run is in-progress (runPolicy was already
    // persisted) and the current config has drifted, refuse to continue
    // silently. Skip diagnostic/idempotent commands that do not consume policy.
    const DIVERGENCE_EXEMPT = new Set([
      // Diagnostic / idempotent commands that do not consume runPolicy.
      'status',
      'sync',
      'repair-state',
      'record-review',
      TICKET_TRIAGE_COMMAND,
      // start: re-stamps runPolicy from current config when explicit flags are
      // present, so blocking it on divergence is counter-productive — let
      // start-time stamping resolve the conflict.
      'start',
    ]);
    let state = loadedState;
    if (
      hadPersistedRunPolicy &&
      !DIVERGENCE_EXEMPT.has(parsed.command) &&
      loadedState.runPolicy != null
    ) {
      const currentRunPolicy = deriveRunPolicyFromConfig(resolvedConfig);
      const divergedFields = detectRunPolicyDivergence(
        loadedState.runPolicy,
        currentRunPolicy,
      );
      if (divergedFields.length > 0) {
        const runDeliverInvocation = generateRunDeliverInvocation(
          context.config.packageManager,
        );
        const commandArgs = [
          '--plan',
          state.planPath,
          parsed.command,
          ...parsed.positionals,
        ].join(' ');
        const recoveryInvocation = `${runDeliverInvocation} ${commandArgs}`;

        if (parsed.baseline === undefined) {
          throw new Error(
            formatRunPolicyDivergenceError(
              loadedState.runPolicy,
              currentRunPolicy,
              divergedFields,
              recoveryInvocation,
            ),
          );
        }

        // Operator provided --baseline: resolve and persist the new runPolicy.
        const resolvedRunPolicy =
          parsed.baseline === 'orchestrator'
            ? deriveRunPolicyFromConfig(resolvedConfig)
            : patchRunPolicyWithFlags(loadedState.runPolicy, parsed);

        state = { ...loadedState, runPolicy: resolvedRunPolicy };
        await saveState(cwd, state);
      }
    }

    // Apply persisted runPolicy so all downstream call sites use the governing
    // policy values from state, not the current config.
    if (hadPersistedRunPolicy && state.runPolicy != null) {
      context = {
        ...context,
        config: applyRunPolicyToConfig(context.config, state.runPolicy),
      };
    }

    const resolvedCwd = await realpath(cwd).catch(() => cwd);
    assertWorktreeGuard(
      resolvedCwd,
      parsed.command,
      parsed.positionals,
      state,
      context.config,
    );

    switch (parsed.command) {
      case 'sync': {
        await saveState(cwd, state);
        console.log(formatStatus(state, context.config));
        return 0;
      }
      case 'status': {
        console.log(formatStatus(state, context.config));
        return 0;
      }
      case 'triage-advisory-observations': {
        if (!parsed.dispositionsPath) {
          throw new Error(
            'triage-advisory-observations requires --dispositions <path>.',
          );
        }
        const dispositions = await readAdvisoryObservationDispositionInput(
          resolve(cwd, parsed.dispositionsPath),
        );
        const result = await runAdvisoryObservationTriage({
          repoRoot: cwd,
          state,
          dispositions,
        });
        console.log(
          [
            `Advisory observation triage artifact: ${result.artifactPath}`,
            `Observation groups: ${result.groups.length}`,
            `Observations recorded: ${result.observationsWritten}`,
          ].join('\n'),
        );
        return 0;
      }
      case 'start': {
        // When explicit policy flags are provided, re-stamp runPolicy from the
        // current resolved config so the persisted state reflects the operator's
        // explicit overrides. Without explicit flags, the existing runPolicy (or
        // normalizeRunPolicy-derived baseline) is preserved.
        const hasExplicitPolicyFlags =
          parsed.boundaryMode !== undefined ||
          parsed.subagentReviewPolicy !== undefined ||
          parsed.prReviewPolicy !== undefined;
        const stateForStart = hasExplicitPolicyFlags
          ? { ...state, runPolicy: deriveRunPolicyFromConfig(resolvedConfig) }
          : state;
        // When explicit flags are provided, stateForStart.runPolicy reflects the
        // new policy derived from CLI flags. Re-anchor context.config to the
        // flag-resolved config so startTicket and status output use the
        // operator's intended values, not the persisted policy stamped by the
        // merge block above.
        if (hasExplicitPolicyFlags) {
          context = { ...context, config: resolvedConfig };
        }
        // Determine target ticket before start so ticket_started is emitted at entry
        const startTargetId =
          parsed.positionals[0] ??
          (
            stateForStart.tickets.find((t) => t.status === 'in_progress') ??
            stateForStart.tickets.find((t) => t.status === 'pending')
          )?.id;
        if (startTargetId) {
          await writeGateEvent(context.config, {
            gate: GATE_NAMES.TICKET_STARTED,
            planKey: stateForStart.planKey,
            ticketId: startTargetId,
          });
        }
        const nextState = await startTicket(
          stateForStart,
          cwd,
          context,
          parsed.positionals[0],
        );
        await saveState(cwd, nextState);
        console.log(formatStatus(nextState, context.config));
        // Emit start exit gate: red_tdd for Red: required, green_tdd for Red: skip
        const startedTicket = startTargetId
          ? nextState.tickets.find((t) => t.id === startTargetId)
          : nextState.tickets.find((t) => t.status === 'in_progress');
        if (startedTicket) {
          await emitStartExitGate(
            startedTicket,
            context.config,
            nextState.planKey,
          );
        }
        await emitNotificationWarnings(
          notifier,
          cwd,
          eventsForStartCommand(nextState, parsed.positionals[0]),
        );
        return 0;
      }
      case 'post-verify': {
        const { auditOutcome, auditTicketId, auditPatchCommitArgs } =
          parsePostVerifyArgs(parsed.positionals);
        if (auditOutcome !== 'patched' && auditPatchCommitArgs.length > 0) {
          throw new Error(
            'Post-verify patch commits are only allowed when outcome is `patched`.',
          );
        }
        const auditPatchCommits =
          auditOutcome === 'patched'
            ? resolveInternalReviewPatchCommits(
                (
                  state.tickets.find((ticket) => ticket.id === auditTicketId) ??
                  state.tickets.find(
                    (ticket) => ticket.status === 'in_progress',
                  ) ??
                  state.tickets[0]
                )?.worktreePath ?? cwd,
                context,
                auditPatchCommitArgs,
                '[post-verify]',
                'Post-verify',
              )
            : undefined;
        const nextState = await recordPostVerify(
          state,
          auditTicketId,
          auditOutcome,
          context.config,
          {
            getWorkingTreeStatus: context.platform.getWorkingTreeStatus,
            hasLocalBranchCommits: context.platform.hasLocalBranchCommits,
            hasUncommittedChanges: context.platform.hasUncommittedChanges,
            warn: (message: string) => console.log(message),
          },
          auditPatchCommits,
        );
        await saveState(cwd, nextState);
        console.log(formatStatus(nextState, context.config));
        return 0;
      }
      case 'post-red': {
        const nextState = await recordPostRed(
          state,
          parsed.positionals[0],
          context,
        );
        await saveState(cwd, nextState);
        console.log(formatStatus(nextState, context.config));
        // Emit green_tdd: Red: required ticket has passed its failing test gate
        const postRedTicket =
          nextState.tickets.find(
            (t) =>
              t.status === 'red_complete' &&
              state.tickets.find((s) => s.id === t.id)?.status !==
                'red_complete',
          ) ?? nextState.tickets.find((t) => t.status === 'red_complete');
        if (postRedTicket) {
          await emitPostRedGate(
            postRedTicket,
            context.config,
            nextState.planKey,
          );
        }
        return 0;
      }
      case 'write-subagent-adversarial-review': {
        const writeTicketId = parsed.positionals[0];
        const writeTarget =
          (writeTicketId
            ? state.tickets.find((t) => t.id === writeTicketId)
            : state.tickets.find((t) => t.status === 'verified')) ?? undefined;

        if (!writeTarget) {
          throw new Error(
            writeTicketId
              ? `Unknown ticket ${writeTicketId}.`
              : 'No ticket at verified status found.',
          );
        }

        if (writeTarget.status !== 'verified') {
          throw new Error(
            `Ticket ${writeTarget.id} must be at status verified before write-subagent-adversarial-review. Current status: ${writeTarget.status}.`,
          );
        }

        const writePolicy = context.config.reviewPolicy.subagentReview;
        if (writePolicy === 'disabled') {
          throw new Error(
            `subagentReview is disabled — write-subagent-adversarial-review is not applicable. Run open-pr next.`,
          );
        }

        const writeIsDocOnly = isPlatformLocalBranchDocOnly(
          writeTarget.worktreePath,
          writeTarget.baseBranch,
          context.config.runtime,
        );
        if (writePolicy === 'skip_doc_only' && writeIsDocOnly) {
          throw new Error(
            `Ticket ${writeTarget.id} is doc-only under skip_doc_only — subagent review auto-skips and no adversarial prompt is required. Run subagent-review next.`,
          );
        }

        await emitAdversarialReviewGate(
          writeTarget,
          context.config,
          state.planKey,
        );

        const promptContent = resolveAdversarialPromptContent({
          repoRoot: cwd,
          ticket: writeTarget,
          promptFilePath: parsed.promptFile,
        });

        const written = writeSubagentAdversarialPrompt({
          repoRoot: cwd,
          reviewsDirPath: state.reviewsDirPath,
          ticketId: writeTarget.id,
          content: promptContent,
        });

        const nextState: DeliveryState = {
          ...state,
          tickets: state.tickets.map((t) =>
            t.id === writeTarget.id
              ? {
                  ...t,
                  subagentAdversarialPromptPath: written.relativePath,
                  subagentAdversarialPromptWrittenAt: written.writtenAt,
                }
              : t,
          ),
        };

        commitDeliveryArtifactAndPush({
          absolutePath: written.absolutePath,
          branch: writeTarget.branch,
          commitMessage: `chore(${writeTarget.id}): record subagent adversarial review prompt`,
          ensureBranchPushed: context.platform.ensureBranchPushed,
          relativeToRepo,
          repoRoot: cwd,
          runProcess: context.platform.runProcess,
        });

        console.log(
          `Recorded subagent adversarial review prompt for ${writeTarget.id} at ${written.relativePath}.`,
        );
        await saveState(cwd, nextState);
        console.log(formatStatus(nextState, context.config));
        return 0;
      }
      case 'subagent-review': {
        // P14.03: `subagent-review record-deferred --reason "<text>"` appends
        // a `deferred` ledger row alongside the existing runner/recorder rows.
        if (parsed.positionals[0] === 'record-deferred') {
          const deferTarget =
            (parsed.positionals[1]
              ? state.tickets.find((t) => t.id === parsed.positionals[1])
              : state.tickets.find(
                  (t) => t.status === 'subagent_review_complete',
                )) ?? undefined;
          if (!deferTarget) {
            throw new Error(
              'record-deferred requires a ticket at subagent_review_complete (or pass an explicit ticket id).',
            );
          }
          const artifactRel =
            deferTarget.subagentRunnerArtifactPath ??
            `${state.reviewsDirPath}/${deferTarget.id}-subagent-review.ledger.json`;
          const artifactAbs = resolve(cwd, artifactRel);
          // Use the latest invocation's reviewedHeadSha. A corrupt artifact
          // must surface as an error — silently writing `reviewedHeadSha:
          // "unknown"` would heal the corruption with a sentinel value that
          // never matches a real SHA, leaving the reconciliation gate
          // permanently unsatisfied.
          let reviewedHead = 'unknown';
          if (existsSync(artifactAbs)) {
            try {
              const a = JSON.parse(readFileSync(artifactAbs, 'utf-8')) as {
                invocations?: Array<{ reviewedHeadSha?: string }>;
              };
              const last = a.invocations?.[a.invocations.length - 1];
              if (last?.reviewedHeadSha) reviewedHead = last.reviewedHeadSha;
            } catch (parseError) {
              throw new Error(
                `record-deferred: failed to parse subagent runner artifact at ${artifactAbs}: ${String(parseError)}. Fix or remove the corrupt artifact before recording a deferred row.`,
                { cause: parseError },
              );
            }
          }
          const primaryAgentForDefer = resolvePrimaryAgent({
            flag: parsed.primary,
            configField: context.config.primaryAgent,
          });
          recordDeferred({
            artifactPath: artifactAbs,
            ticket: deferTarget.id,
            reviewedHeadSha: reviewedHead,
            reason: parsed.reason ?? '',
            primaryAgent: primaryAgentForDefer,
          });
          commitDeliveryArtifactAndPush({
            absolutePath: artifactAbs,
            branch: deferTarget.branch,
            commitMessage: `chore(${deferTarget.id}): record subagent-review deferred row`,
            ensureBranchPushed: context.platform.ensureBranchPushed,
            relativeToRepo,
            repoRoot: cwd,
            runProcess: context.platform.runProcess,
          });
          console.log(
            `Recorded deferred row for ${deferTarget.id} (reason captured).`,
          );
          return 0;
        }
        const subagentArgs = parseSubagentReviewArgs(
          parsed.positionals,
          parsed.flags,
        );
        const subagentTicketId = subagentArgs.ticketId;
        const subagentTarget =
          (subagentTicketId
            ? state.tickets.find((t) => t.id === subagentTicketId)
            : state.tickets.find((t) => t.status === 'verified')) ?? undefined;

        if (!subagentTarget) {
          throw new Error(
            subagentTicketId
              ? `Unknown ticket ${subagentTicketId}.`
              : 'No ticket at verified status found.',
          );
        }

        const isDocOnly = isPlatformLocalBranchDocOnly(
          subagentTarget.worktreePath,
          subagentTarget.baseBranch,
          context.config.runtime,
        );
        const policy = context.config.reviewPolicy.subagentReview;

        // Auto-skip doc-only tickets under skip_doc_only policy.
        if (policy === 'skip_doc_only' && isDocOnly) {
          const nextState = recordSubagentReview(
            state,
            'skipped',
            true,
            policy,
            undefined,
            undefined,
            subagentTarget.id,
          );
          console.log('Doc-only ticket — subagent review auto-skipped.');
          await saveState(cwd, nextState);
          console.log(formatStatus(nextState, context.config));
          return 0;
        }

        const artifactRelPath = `${state.reviewsDirPath}/${subagentTarget.id}-subagent-review.ledger.json`;
        const artifactAbsPath = resolve(cwd, artifactRelPath);

        // Resolve current HEAD for both recorder and idempotency dispatch.
        const readHeadShaForDispatch = () => {
          try {
            return spawnSync('git', ['rev-parse', 'HEAD'], {
              cwd: subagentTarget.worktreePath,
              encoding: 'utf-8',
            }).stdout.trim();
          } catch {
            return '';
          }
        };
        const existingArtifact = tryReadSubagentRunnerArtifact(
          artifactAbsPath,
          subagentTarget.id,
        );
        const dispatchHeadSha = readHeadShaForDispatch();
        const dispatch = decideSubagentReviewMode(
          {
            outcome: subagentArgs.outcome,
            reviewedHeadSha: subagentArgs.reviewedHeadSha,
            force: subagentArgs.force,
          },
          existingArtifact,
          dispatchHeadSha,
        );

        if (dispatch.kind === 'recorder') {
          const recorderPatchCommits =
            dispatch.outcome === 'patched'
              ? resolveInternalReviewPatchCommits(
                  subagentTarget.worktreePath,
                  context,
                  subagentArgs.patchCommitArgs.length > 0
                    ? subagentArgs.patchCommitArgs
                    : [dispatch.reviewedHeadSha],
                  '[subagent-review]',
                  'Subagent review',
                )
              : undefined;

          // Validate state transition before touching the artifact so a failed
          // record does not leave a dangling invocation on disk.
          const nextState = recordSubagentReview(
            state,
            dispatch.outcome,
            isDocOnly,
            policy,
            recorderPatchCommits,
            undefined,
            subagentTarget.id,
            artifactRelPath,
          );

          const recorderPrimaryAgent = resolvePrimaryAgent({
            flag: parsed.primary,
            configField: context.config.primaryAgent,
          });
          const recorderInvocation = buildRunnerInvocation(
            'operator-recorder',
            dispatch.reviewedHeadSha,
            dispatch.outcome,
            {
              terminatedReason: 'completed',
              patches: recorderPatchCommits?.map((c) => c.sha) ?? [],
              schemaVersion: SUBAGENT_LEDGER_SCHEMA_VERSION,
              primaryAgent: recorderPrimaryAgent,
              runnerSelfReport: null,
              fallbackFrom: null,
            },
          );
          appendInvocationToArtifact(
            artifactAbsPath,
            subagentTarget.id,
            recorderInvocation,
          );
          commitDeliveryArtifactAndPush({
            absolutePath: artifactAbsPath,
            branch: subagentTarget.branch,
            commitMessage: `chore(${subagentTarget.id}): record subagent-review runner artifact`,
            ensureBranchPushed: context.platform.ensureBranchPushed,
            relativeToRepo,
            repoRoot: cwd,
            runProcess: context.platform.runProcess,
          });

          console.log(
            `Recorded operator-recorder invocation (outcome=${dispatch.outcome}, sha=${dispatch.reviewedHeadSha}). No runner subprocess invoked.`,
          );
          await saveState(cwd, nextState);
          console.log(formatStatus(nextState, context.config));
          return 0;
        }

        if (dispatch.kind === 'no-op') {
          console.log(
            `No-op: artifact already contains a valid invocation for HEAD ${dispatch.reviewedHeadSha}. Pass --force to re-run the runner.`,
          );
          console.log(formatStatus(state, context.config));
          return 0;
        }

        // Gate runner invocation on a recorded primary-agent-authored
        // adversarial review prompt. Doc-only auto-skip already returned above;
        // `disabled` policy short-circuits inside the assertion helper.
        assertSubagentAdversarialPromptPresent({
          repoRoot: cwd,
          ticket: subagentTarget,
          isDocOnly,
          policy,
        });

        // P14.02: operator-explicit subagent selection. Flag > config > error.
        const subagentSelection = resolveSubagentSelection({
          flag: parsed.subagent,
          configField: context.config.subagentRunner,
        });
        const primaryAgent = resolvePrimaryAgent({
          flag: parsed.primary,
          configField: context.config.primaryAgent,
        });

        const worktreePath = subagentTarget.worktreePath;
        const readHeadSha = () => {
          try {
            return spawnSync('git', ['rev-parse', 'HEAD'], {
              cwd: worktreePath,
              encoding: 'utf-8',
            }).stdout.trim();
          } catch {
            return 'unknown';
          }
        };
        const listDiffPaths = (...revisions: string[]) => {
          const result = spawnSync(
            'git',
            ['diff', '--name-only', ...revisions],
            {
              cwd: worktreePath,
              encoding: 'utf-8',
            },
          );
          return (result.stdout ?? '')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        };
        const listDirtyPaths = () => {
          const status = spawnSync('git', ['status', '--porcelain'], {
            cwd: worktreePath,
            encoding: 'utf-8',
          });
          return (status.stdout ?? '')
            .split('\n')
            .map((line) => line.slice(3).trim())
            .map((path) => path.split(' -> ').pop() ?? path)
            .filter(Boolean);
        };
        const headSha = readHeadSha();
        // P13.03: the runner consumes the primary-agent-authored adversarial
        // review prompt persisted under reviews/. There is no generic
        // changed-files fallback; missing artifact → hard error from the
        // resolver above.
        const reviewPrompt = requireSubagentAdversarialPromptForRunner({
          repoRoot: cwd,
          ticket: subagentTarget,
        });

        const RUNNER_TIMEOUT_MS = 10 * 60 * 1000;

        let outcome: 'clean' | 'patched' | 'skipped' = 'skipped';
        let terminatedReason: SubagentRunnerTerminatedReason =
          'runner_unavailable';
        let runnerOutputText: string | undefined;
        let runnerStdout: string | undefined;
        let runnerStderr: string | undefined;
        let runnerSelfReport: string | null = null;

        const fallbackOutcome = runSubagentWithFallback(
          subagentSelection.kind,
          (runner) => {
            const runnerHeadBefore = readHeadSha();
            const preRunDirtyPaths = new Set(listDirtyPaths());
            const result = tryRunner(
              () => {
                const outputLastMessageDir =
                  runner === 'codex-cli'
                    ? mkdtempSync(join(tmpdir(), 'soa-codex-runner-'))
                    : undefined;
                const outputLastMessagePath = outputLastMessageDir
                  ? join(outputLastMessageDir, 'last-message.md')
                  : undefined;
                const { bin, args } = buildRunnerSpawnCommand(
                  runner,
                  reviewPrompt,
                  {
                    outputLastMessagePath,
                    workspacePath:
                      runner === 'cursor-cli' ? worktreePath : undefined,
                  },
                );
                try {
                  const spawned = spawnSync(bin, args, {
                    cwd: worktreePath,
                    timeout: RUNNER_TIMEOUT_MS,
                    encoding: 'utf-8',
                  });
                  const spawnError = spawned.error as
                    | (Error & { code?: string })
                    | undefined;
                  if (spawnError && spawnError.code === 'ENOENT') {
                    throw spawnError;
                  }
                  const stdoutFromFile =
                    outputLastMessagePath && existsSync(outputLastMessagePath)
                      ? readFileSync(outputLastMessagePath, 'utf-8')
                      : '';
                  const stdout = stdoutFromFile || spawned.stdout || '';
                  const stderr = [
                    spawned.stderr ?? '',
                    spawnError && spawnError.code !== 'ENOENT'
                      ? spawnError.message
                      : '',
                  ]
                    .filter(Boolean)
                    .join('\n');
                  // P14.02: per-runner classification trusts the model's
                  // self-reported runnerStatus trailer and only escalates to
                  // skipped/rate_limit on authentic structured signals (not
                  // stderr/stdout prose). Symmetric for codex-cli and claude-cli.
                  const classified =
                    runner === 'codex-cli'
                      ? coerceCodexCliClassification({
                          exitCode: spawned.status,
                          stdout,
                          stderr,
                        })
                      : runner === 'cursor-cli'
                        ? coerceCursorCliClassification({
                            exitCode: spawned.status,
                            stdout,
                            stderr,
                          })
                        : coerceClaudeCliClassification({
                            exitCode: spawned.status,
                            stdout,
                            stderr,
                          });
                  runnerSelfReport = classified.runnerSelfReport;
                  return {
                    exitCode: spawned.status,
                    timedOut:
                      spawned.signal === 'SIGTERM' ||
                      spawnError?.message?.includes('timed out') ||
                      false,
                    stdout,
                    stderr,
                    terminatedReason: classified.terminatedReason,
                  };
                } finally {
                  if (outputLastMessageDir) {
                    rmSync(outputLastMessageDir, {
                      recursive: true,
                      force: true,
                    });
                  }
                }
              },
              () => {
                return (
                  readHeadSha() !== runnerHeadBefore ||
                  listDirtyPaths().some((p) => !preRunDirtyPaths.has(p))
                );
              },
            );

            if (result.status === 'ran') {
              const runnerHeadAfter = readHeadSha();
              const runnerWroteFiles =
                runnerHeadBefore !== runnerHeadAfter ||
                listDirtyPaths().some((p) => !preRunDirtyPaths.has(p));

              const decided = decideAdvisoryRunnerOutcome(result, {
                runnerWroteFiles,
              });
              outcome = decided.outcome;
              terminatedReason = decided.terminatedReason;
              runnerOutputText = result.rawOutput;
              runnerStdout = result.stdout;
              runnerStderr = result.stderr;

              if (runnerWroteFiles) {
                const wroteHeadPaths =
                  runnerHeadBefore !== runnerHeadAfter
                    ? listDiffPaths(`${runnerHeadBefore}..${runnerHeadAfter}`)
                    : [];
                const writePaths = [...wroteHeadPaths, ...listDirtyPaths()];
                const deliveryDocChanges = findDeliveryDocPaths(writePaths);
                const detail =
                  deliveryDocChanges.length > 0
                    ? ` Delivery-doc paths affected: ${deliveryDocChanges.join(', ')}`
                    : ` Affected paths: ${writePaths.join(', ')}`;
                console.log(
                  `Runner ${runner} attempted file writes — recording as advisory_violation (advisory-only contract).${detail}`,
                );
              }
            } else if (shouldFallbackToOtherRunner(result)) {
              console.log(
                `Runner ${runner} unavailable${result.status === 'timeout' ? ' (timed out)' : ''}, trying fallback...`,
              );
            }
            return result;
          },
        );

        const usedRunner: 'claude-cli' | 'codex-cli' | 'skipped' =
          fallbackOutcome.ranKind;
        const fallbackLevel = fallbackOutcome.fallbackLevel;
        const fallbackFrom = fallbackOutcome.fallbackFrom;

        // Write runner artifact (append-only invocations[] per ticket).
        // Sidecar files hold prompt and outcome prose; JSON stores path refs only.
        const promptPath = subagentTarget.subagentAdversarialPromptPath;
        if (!promptPath) {
          throw new Error(
            `Ticket ${subagentTarget.id} is missing subagentAdversarialPromptPath after prompt gate.`,
          );
        }

        let outcomeSidecar:
          | { absolutePath: string; relativePath: string }
          | undefined;
        if (runnerOutputText !== undefined) {
          outcomeSidecar = writeSubagentReviewOutcome({
            repoRoot: cwd,
            reviewsDirPath: state.reviewsDirPath,
            ticketId: subagentTarget.id,
            stdout: runnerStdout ?? runnerOutputText,
            stderr: runnerStderr ?? '',
          });
        }

        const invocation = buildRunnerInvocation(usedRunner, headSha, outcome, {
          terminatedReason,
          rawOutput: outcomeSidecar?.relativePath,
          filledPrompt: promptPath,
          fallbackLevel,
          schemaVersion: SUBAGENT_LEDGER_SCHEMA_VERSION,
          primaryAgent,
          runnerSelfReport,
          fallbackFrom,
        });
        appendInvocationToArtifact(
          artifactAbsPath,
          subagentTarget.id,
          invocation,
        );

        const nextState = recordSubagentReview(
          state,
          outcome,
          isDocOnly,
          policy,
          undefined,
          undefined,
          subagentTarget.id,
          artifactRelPath,
        );
        commitDeliveryArtifactAndPush({
          absolutePath: artifactAbsPath,
          alsoCommitAbsolutePaths: outcomeSidecar
            ? [outcomeSidecar.absolutePath]
            : undefined,
          branch: subagentTarget.branch,
          commitMessage: `chore(${subagentTarget.id}): record subagent-review runner artifact`,
          ensureBranchPushed: context.platform.ensureBranchPushed,
          relativeToRepo,
          repoRoot: cwd,
          runProcess: context.platform.runProcess,
        });

        if (outcome === 'skipped') {
          if (usedRunner === 'skipped') {
            console.log(
              'All runners unavailable — subagent review honestly skipped.',
            );
          } else {
            console.log(
              `Runner ${usedRunner} completed with terminatedReason=${terminatedReason} — subagent review honestly skipped.`,
            );
          }
        }
        await saveState(cwd, nextState);
        console.log(formatStatus(nextState, context.config));
        return 0;
      }
      case 'reconcile-subagent-review': {
        await runReconcileSubagentReview(
          state,
          cwd,
          context,
          parsed.positionals[0],
        );
        return 0;
      }
      case 'open-pr': {
        // P14.03: --ack-reconciliation appends an operator-explicit row to
        // the runner artifact, then proceeds to the standard open-pr gate.
        if (parsed.ackReconciliation) {
          await runAckReconciliation(state, cwd, context, parsed);
        }
        // Hard-block silent-lie conditions before publish.
        runReconciliationGate(state, cwd, context, parsed.positionals[0]);
        // Emit open_pr gate before publishing the PR (emit-then-action).
        // Mirror openPullRequest's internal resolution: subagent_review_complete
        // first, then verified (subagentReview=disabled path).
        const openPrTarget =
          (parsed.positionals[0]
            ? state.tickets.find((t) => t.id === parsed.positionals[0])
            : (state.tickets.find(
                (t) => t.status === 'subagent_review_complete',
              ) ?? state.tickets.find((t) => t.status === 'verified'))) ??
          undefined;
        if (openPrTarget) {
          await emitOpenPrGate(openPrTarget, context.config, state.planKey);
        }
        const nextState = await openPullRequest(
          state,
          cwd,
          context,
          parsed.positionals[0],
        );
        await saveState(cwd, nextState);
        console.log(
          [
            formatStatus(nextState, context.config),
            formatReviewWindowMessage(nextState, parsed.positionals[0]),
          ]
            .filter(Boolean)
            .join('\n\n'),
        );
        await emitNotificationWarnings(
          notifier,
          cwd,
          eventsForOpenPrCommand(nextState, parsed.positionals[0]),
        );
        return 0;
      }
      case 'poll-review': {
        const pollTicketId = parsed.positionals[0];
        const pollTarget = pollTicketId
          ? state.tickets.find((t) => t.id === pollTicketId)
          : state.tickets.find((t) => t.status === 'in_review');

        // Emit poll_review gate before polling begins (emit-then-action)
        if (pollTarget) {
          await emitPollReviewGate(pollTarget, context.config, state.planKey);
        }

        if (
          pollTarget &&
          shouldAutoRecordReviewSkippedForPollReview(
            context.config.reviewPolicy.prReview,
            pollTarget,
          )
        ) {
          const skipNote =
            context.config.reviewPolicy.prReview === 'disabled'
              ? 'PR review disabled by policy'
              : 'doc-only PR; PR review skipped by policy';
          console.log(
            context.config.reviewPolicy.prReview === 'disabled'
              ? `prReview=disabled for ${pollTarget.id}: skipping AI review window, recording skipped`
              : `doc_only=true for ${pollTarget.id} under prReview=skip_doc_only: skipping AI review window, recording skipped`,
          );
          const docOnlyState = await recordReview(
            state,
            cwd,
            context,
            pollTarget.id,
            'skipped',
            skipNote,
          );
          await saveState(cwd, docOnlyState);
          console.log(
            formatCurrentTicketStatus(
              docOnlyState,
              context.config,
              pollTicketId,
            ),
          );
          const docOnlyEvents = eventsForPollReviewCommand(
            docOnlyState,
            pollTicketId,
          );
          await emitNotificationWarnings(notifier, cwd, docOnlyEvents);
          await emitReviewCleanGate(
            docOnlyEvents,
            context.config,
            state.planKey,
          );
          return 0;
        }

        const nextState = await pollReview(state, cwd, context, pollTicketId);
        await saveState(cwd, nextState);
        console.log(
          formatCurrentTicketStatus(nextState, context.config, pollTicketId),
        );
        const pollEvents = eventsForPollReviewCommand(nextState, pollTicketId);
        await emitNotificationWarnings(notifier, cwd, pollEvents);
        await emitReviewCleanGate(pollEvents, context.config, state.planKey);
        return 0;
      }
      case TICKET_TRIAGE_COMMAND: {
        const ticketId = parsed.positionals[0];

        if (!ticketId) {
          throw new Error(
            `Usage: ${context.invocation} --plan <plan-path> triage-ticket <ticket-id>`,
          );
        }

        const nextState = await reconcileLateReview(
          state,
          cwd,
          context,
          ticketId,
        );
        await saveState(cwd, nextState);
        console.log(formatStatus(nextState, context.config));
        const triageEvents = eventsForReconcileLateReviewCommand(
          nextState,
          ticketId,
        );
        await emitNotificationWarnings(notifier, cwd, triageEvents);
        await emitReviewCleanGate(triageEvents, context.config, state.planKey);
        return 0;
      }
      case 'record-review': {
        const [ticketId, outcome, ...noteParts] = parsed.positionals;

        if (
          !ticketId ||
          (outcome !== 'clean' &&
            outcome !== 'patched' &&
            outcome !== 'operator_input_needed')
        ) {
          throw new Error(
            `Usage: ${context.invocation} --plan <plan-path> record-review <ticket-id> <clean|patched|operator_input_needed> [note]`,
          );
        }

        // Emit record_review gate before recording outcome (emit-then-action)
        const recordTarget =
          state.tickets.find((t) => t.id === ticketId) ?? undefined;
        if (recordTarget) {
          await emitRecordReviewGate(
            recordTarget,
            context.config,
            state.planKey,
          );
        }

        const nextState = await recordReview(
          state,
          cwd,
          context,
          ticketId,
          outcome,
          noteParts.join(' ').trim() || undefined,
        );
        await saveState(cwd, nextState);
        console.log(formatStatus(nextState, context.config));
        const recordEvents = eventsForRecordReviewCommand(nextState, ticketId);
        await emitNotificationWarnings(notifier, cwd, recordEvents);
        await emitReviewCleanGate(recordEvents, context.config, state.planKey);
        return 0;
      }
      case 'advance': {
        const advancedState = await advanceToNextTicketImpl(
          state,
          cwd,
          context,
        );
        const nextState = await applyAdvanceBoundaryMode(
          state,
          advancedState,
          cwd,
          context,
        );
        await saveState(cwd, nextState);
        await syncStateToPrimaryIfNeeded(cwd, nextState, (wt) =>
          findPrimaryWorktreePath(wt, context.config),
        );
        console.log(formatStatus(nextState, context.config));
        await emitGateForTransitions(state, nextState, context.config);
        const boundaryGuidance = formatAdvanceBoundaryGuidance(
          state,
          advancedState,
          nextState,
          context.config,
        );

        if (boundaryGuidance) {
          console.log('');
          console.log(boundaryGuidance);
        }

        await emitNotificationWarnings(
          notifier,
          cwd,
          eventsForAdvanceCommand(state, nextState),
        );
        return 0;
      }
      case 'restack': {
        const nextState = await restackTicket(
          state,
          cwd,
          context,
          parsed.positionals[0],
        );
        await saveState(cwd, nextState);
        console.log(formatStatus(nextState, context.config));
        return 0;
      }
      default: {
        console.error(usage);
        return 1;
      }
    }
  } catch (error) {
    const notifier = resolveNotifier();
    await emitNotificationWarnings(notifier, cwd, [
      buildRunBlockedEvent(
        parsed?.planPath ? derivePlanKey(parsed.planPath) : undefined,
        parsed?.command,
        formatError(error),
      ),
    ]);
    console.error(formatError(error));
    return 1;
  }
}

export function findPrimaryWorktreePath(
  cwd: string,
  config: ResolvedOrchestratorConfig,
): string | undefined {
  return findPlatformPrimaryWorktreePath(
    cwd,
    config.defaultBranch,
    config.runtime,
  );
}

export function parsePlan(
  markdown: string,
  planPath: string,
  cwd?: string,
): TicketDefinition[] {
  return parsePlanImpl(markdown, planPath, cwd);
}

export function syncStateFromScratch(
  ticketDefinitions: TicketDefinition[],
  cwd: string,
  options: OrchestratorOptions,
  config: ResolvedOrchestratorConfig,
  inferred?: DeliveryState,
): DeliveryState {
  return syncStateFromScratchImpl(ticketDefinitions, options, inferred, {
    cwd,
    defaultBranch: config.defaultBranch,
    deriveBranchName,
    deriveWorktreePath,
  });
}

export function syncStateFromExisting(
  existing: DeliveryState,
  ticketDefinitions: TicketDefinition[],
  cwd: string,
  options: OrchestratorOptions,
  config: ResolvedOrchestratorConfig,
  inferred?: DeliveryState,
): DeliveryState {
  return syncStateFromExistingImpl(
    existing,
    ticketDefinitions,
    options,
    inferred,
    {
      cwd,
      defaultBranch: config.defaultBranch,
      deriveBranchName,
      deriveWorktreePath,
    },
  );
}

export function resolveReviewFetcher(): string {
  if (process.env.AI_CODE_REVIEW_FETCHER) {
    return process.env.AI_CODE_REVIEW_FETCHER;
  }

  return resolveSonOfAntonSkillScript(
    'pr-review/scripts/fetch_pr_review_comments.sh',
  );
}

export function resolveReviewTriager(): string {
  if (process.env.AI_CODE_REVIEW_TRIAGER) {
    return process.env.AI_CODE_REVIEW_TRIAGER;
  }

  return resolveSonOfAntonSkillScript('pr-review/scripts/triage_pr_review.sh');
}

function resolveSonOfAntonSkillScript(scriptPath: string): string {
  const subtreePath = `.son-of-anton/.agents/skills/${scriptPath}`;
  if (existsSync(resolve(process.cwd(), subtreePath))) {
    return subtreePath;
  }

  return `.agents/skills/${scriptPath}`;
}

export function createOptions(input: {
  planPath?: string;
}): OrchestratorOptions {
  return createOptionsImpl(input);
}

export type LoadStateResult = {
  state: DeliveryState;
  hadPersistedRunPolicy: boolean;
};

export async function loadState(
  cwd: string,
  options: OrchestratorOptions,
  config: ResolvedOrchestratorConfig,
): Promise<LoadStateResult> {
  const raw = await loadStateImpl(cwd, options, {
    cwd,
    defaultBranch: config.defaultBranch,
    runtime: config.runtime,
    deriveBranchName,
    deriveWorktreePath,
    findExistingBranch,
  });
  const hadPersistedRunPolicy = raw.runPolicy != null;
  return { state: normalizeRunPolicy(raw, config), hadPersistedRunPolicy };
}

async function repairState(
  cwd: string,
  options: OrchestratorOptions,
  config: ResolvedOrchestratorConfig,
): Promise<RepairStateResult> {
  const result = await repairStateImpl(cwd, options, {
    cwd,
    defaultBranch: config.defaultBranch,
    runtime: config.runtime,
    deriveBranchName,
    deriveWorktreePath,
    findExistingBranch,
  });
  const normalized = normalizeRunPolicy(result.state, config);

  if (normalized !== result.state) {
    await saveState(cwd, normalized);
  }

  return { ...result, state: normalized };
}

export async function inferPlanPathFromBranch(
  cwd: string,
  branch: string,
  config: ResolvedOrchestratorConfig,
): Promise<string> {
  return inferPlanPathFromBranchImpl(
    cwd,
    branch,
    config.planRoot,
    findExistingBranch,
  );
}

export function resolvePlanPathForBranch(
  planIndex: Array<{ planPath: string; tickets: TicketDefinition[] }>,
  branch: string,
): string {
  return resolvePlanPathForBranchImpl(planIndex, branch, findExistingBranch);
}

export async function saveState(
  cwd: string,
  state: DeliveryState,
): Promise<void> {
  await saveStateImpl(cwd, state);
}

export async function syncStateToPrimaryIfNeeded(
  cwd: string,
  state: DeliveryState,
  findPrimaryPath: (cwd: string) => string | undefined,
): Promise<void> {
  const primaryPath = findPrimaryPath(cwd);
  if (!primaryPath) {
    return;
  }

  const canonicalizePath = async (path: string): Promise<string> => {
    try {
      return await realpath(path);
    } catch {
      return resolve(path);
    }
  };

  const [primaryCanonicalPath, cwdCanonicalPath] = await Promise.all([
    canonicalizePath(primaryPath),
    canonicalizePath(cwd),
  ]);

  if (primaryCanonicalPath !== cwdCanonicalPath) {
    await saveState(primaryPath, state);
  }
}

export function summarizeStateDifferences(
  existing: DeliveryState,
  repaired: DeliveryState,
): string[] {
  return summarizeStateDifferencesImpl(existing, repaired);
}

async function startTicket(
  state: DeliveryState,
  cwd: string,
  context: DeliveryOrchestratorContext,
  ticketId?: string,
): Promise<DeliveryState> {
  const platform = context.platform;
  return startTicketImpl(state, cwd, ticketId, {
    addWorktree: platform.addWorktree,
    bootstrapWorktreeIfNeeded: platform.bootstrapWorktreeIfNeeded,
    copyLocalBootstrapFilesIfPresent,
    materializeTicketContext,
    relativeToRepo,
    subagentReviewPolicy: context.config.reviewPolicy.subagentReview,
    ticketBoundaryMode: context.config.ticketBoundaryMode,
  });
}

export async function copyLocalBootstrapFilesIfPresent(
  sourceWorktreePath: string,
  targetWorktreePath: string,
): Promise<void> {
  await copyPlatformBootstrapFilesIfPresent(
    sourceWorktreePath,
    targetWorktreePath,
  );
}

export async function copyLocalEnvIfPresent(
  sourceWorktreePath: string,
  targetWorktreePath: string,
): Promise<void> {
  await copyPlatformEnvIfPresent(sourceWorktreePath, targetWorktreePath);
}

export async function recordPostVerify(
  state: DeliveryState,
  ticketId?: string,
  outcome?: ReviewOutcome,
  config?: ResolvedOrchestratorConfig,
  dependencies: {
    isLocalBranchDocOnly?: (
      cwd: string,
      baseBranch: string,
      runtime: Runtime,
    ) => boolean;
    hasLocalBranchCommits?: (cwd: string, baseBranch: string) => boolean;
    hasUncommittedChanges?: (cwd: string) => boolean;
    getWorkingTreeStatus?: (cwd: string) => string;
    postVerifyPolicy?: ReviewPolicyStageValue;
    warn?: (message: string) => void;
  } = {},
  patchCommits?: InternalReviewPatchCommit[],
): Promise<DeliveryState> {
  if (!config) {
    throw new Error('recordPostVerify requires explicit config.');
  }

  const target =
    (ticketId
      ? state.tickets.find((ticket) => ticket.id === ticketId)
      : (state.tickets.find((ticket) => ticket.status === 'red_complete') ??
        state.tickets.find((ticket) => ticket.status === 'in_progress'))) ??
    undefined;
  const subagentReviewPolicy =
    dependencies.postVerifyPolicy ?? config.reviewPolicy.subagentReview;
  const isDocOnly =
    target &&
    subagentReviewPolicy !== 'disabled' &&
    (dependencies.isLocalBranchDocOnly ?? isPlatformLocalBranchDocOnly)(
      target.worktreePath,
      target.baseBranch,
      config.runtime,
    );

  if (target) {
    try {
      if (dependencies.hasUncommittedChanges?.(target.worktreePath) === true) {
        let statusOutput = '';

        try {
          statusOutput =
            dependencies.getWorkingTreeStatus?.(target.worktreePath) ?? '';
        } catch {
          // Keep post-verify non-blocking if status lookup fails.
        }

        const warningLines = [
          'Warning: working tree has uncommitted changes.',
          'Confirm these are intentional before recording post-verify clean.',
        ];

        if (statusOutput.trim().length > 0) {
          warningLines.push(
            'Uncommitted files:',
            ...statusOutput.split('\n').map((line) => `  ${line}`),
          );
        }

        dependencies.warn?.(warningLines.join('\n'));
      }
    } catch {
      // Keep post-verify non-blocking if dirty-worktree inspection fails.
    }
  }

  if (isDocOnly && target && dependencies.hasLocalBranchCommits !== undefined) {
    const hasCommits = dependencies.hasLocalBranchCommits(
      target.worktreePath,
      target.baseBranch,
    );
    if (!hasCommits) {
      throw new Error(
        `No commits on branch for doc-only ticket ${target.id}. Add or update documentation files before continuing.`,
      );
    }
  }

  if (subagentReviewPolicy === 'skip_doc_only' && isDocOnly) {
    return recordPostVerifyImpl(state, ticketId, 'skipped', undefined);
  }

  if (
    subagentReviewPolicy === 'required' &&
    isDocOnly &&
    outcome === undefined
  ) {
    throw new Error(
      `Ticket ${target.id} requires an explicit post-verify outcome. Pass \`clean\` or \`patched\`.`,
    );
  }

  if (
    outcome === 'skipped' &&
    (!isDocOnly || subagentReviewPolicy === 'required')
  ) {
    throw new Error(
      isDocOnly
        ? `Ticket ${target.id} requires an explicit post-verify outcome. Pass \`clean\` or \`patched\`.`
        : `Ticket ${target.id} cannot record \`skipped\` for post-verify on a code ticket. Pass \`clean\` or \`patched\`.`,
    );
  }

  if (target?.status === 'in_progress' && !isDocOnly) {
    throw createWorkflowContractError(
      'workflow.post_verify.requires_post_red',
      `Ticket ${target.id} is at status in_progress. Run \`bun run deliver --plan ${state.planPath} post-red ${target.id}\` before post-verify on a code ticket.`,
    );
  }

  return recordPostVerifyImpl(state, ticketId, outcome, patchCommits);
}

export async function recordPostRed(
  state: DeliveryState,
  ticketId: string | undefined,
  context: DeliveryOrchestratorContext,
  dependencies: {
    isLocalBranchDocOnly?: (
      cwd: string,
      baseBranch: string,
      runtime: Runtime,
    ) => boolean;
    readHeadSha?: (cwd: string) => string;
    readLatestCommitSubject?: (cwd: string) => string;
    runVerify?: (cwd: string) => {
      exitCode: number;
      stderr: string;
      stdout: string;
    };
  } = {},
): Promise<DeliveryState> {
  const target =
    (ticketId
      ? state.tickets.find((ticket) => ticket.id === ticketId)
      : state.tickets.find((ticket) => ticket.status === 'in_progress')) ??
    undefined;

  if (!target) {
    throw new Error('No in-progress ticket found to mark red_complete.');
  }

  if (target.status === 'red_complete') {
    console.log(`Ticket ${target.id} is already red_complete.`);
    return state;
  }

  const isDocOnly = (
    dependencies.isLocalBranchDocOnly ?? isPlatformLocalBranchDocOnly
  )(target.worktreePath, target.baseBranch, context.config.runtime);
  const isSkipPolicy = target.redPolicy === 'skip';

  if (isDocOnly || isSkipPolicy) {
    const reasons: string[] = [];
    if (isSkipPolicy) {
      reasons.push('Red: skip');
    }
    if (isDocOnly) {
      reasons.push('doc-only branch');
    }
    console.log(`post-red skipped (${reasons.join(', ')}).`);
    return {
      ...state,
      tickets: state.tickets.map((ticket) =>
        ticket.id === target.id
          ? { ...ticket, status: 'red_complete' as const }
          : ticket,
      ),
    };
  }

  const latestCommitSubject =
    dependencies.readLatestCommitSubject ??
    context.platform.readLatestCommitSubject;
  const readHeadSha = dependencies.readHeadSha ?? context.platform.readHeadSha;
  const runVerify =
    dependencies.runVerify ??
    ((cwd: string) =>
      context.platform.runProcessResult(cwd, [
        context.config.packageManager,
        'run',
        'ci',
      ]));

  const verifyResult = runVerify(target.worktreePath);

  if (verifyResult.exitCode === 0) {
    throw new Error(
      `Ticket ${target.id} post-red requires a failing verification run before delivery can advance.`,
    );
  }

  return recordPostRedImpl(state, {
    headSha: readHeadSha(target.worktreePath),
    latestCommitSubject: latestCommitSubject(target.worktreePath),
    ticketId,
    verifyExitCode: verifyResult.exitCode,
  });
}

export function recordSubagentReview(
  state: DeliveryState,
  outcome?: 'clean' | 'patched' | 'skipped',
  isDocOnly?: boolean,
  policy?: ReviewPolicyStageValue,
  patchCommits?: InternalReviewPatchCommit[],
  agentName?: string,
  ticketId?: string,
  artifactPath?: string,
): DeliveryState {
  if (!policy) {
    throw new Error('recordSubagentReview requires an explicit policy.');
  }

  return recordSubagentReviewImpl(
    state,
    outcome,
    isDocOnly,
    policy,
    patchCommits,
    agentName,
    undefined,
    ticketId,
    artifactPath,
  );
}

export function shouldAutoRecordReviewSkippedForPollReview(
  policy: ReviewPolicyStageValue,
  ticket?: Pick<TicketState, 'docOnly'>,
): boolean {
  return (
    policy === 'disabled' ||
    (policy === 'skip_doc_only' && ticket?.docOnly === true)
  );
}

function resolveAdversarialPromptContent(input: {
  repoRoot: string;
  ticket: TicketState;
  promptFilePath?: string;
}): string {
  if (input.promptFilePath) {
    try {
      return readFileSync(
        resolve(input.repoRoot, input.promptFilePath),
        'utf-8',
      );
    } catch (error) {
      throw new Error(
        `Failed to read --prompt-file at ${input.promptFilePath}: ${(error as Error).message}`,
        { cause: error },
      );
    }
  }

  const ticket = input.ticket;
  let ticketSpec = '';
  try {
    ticketSpec = readFileSync(
      resolve(input.repoRoot, ticket.ticketFile),
      'utf-8',
    );
  } catch {
    // Best-effort: an unreadable ticket file is surfaced through the content
    // validator, which rejects empty / stub prompts.
  }

  const changedFiles = (() => {
    try {
      const out = spawnSync(
        'git',
        ['diff', '--name-only', `${ticket.baseBranch}...HEAD`],
        { cwd: ticket.worktreePath, encoding: 'utf-8' },
      );
      return (out.stdout ?? '')
        .split('\n')
        .map((line) => line.trim())
        .filter(Boolean);
    } catch {
      return [];
    }
  })();

  const fileList = changedFiles.length
    ? changedFiles.map((f) => `- ${f}`).join('\n')
    : '- (no changed files detected)';

  return [
    `# Adversarial review for ${ticket.id} — ${ticket.title}`,
    '',
    `Base branch: ${ticket.baseBranch}`,
    `Branch: ${ticket.branch}`,
    '',
    '## Ticket scope',
    '',
    ticketSpec.trim() || '(ticket spec unavailable)',
    '',
    '## Files changed in this diff',
    '',
    fileList,
    '',
    '## Invariants to hold',
    '',
    'Derived from the ticket Outcome section. The subagent must treat each as a',
    'machine-verifiable assertion and report `[held | broken | untested]`.',
    '',
    '## Attack surfaces to probe',
    '',
    'The subagent must probe each of the seven diff-derived classes listed in',
    '`docs/template/delivery/adversarial-review-template.md` and add ticket-spec-derived',
    'surfaces from the changed files above. Report coverage per surface using',
    '`[probed]` / `[N/A — reason]` / `[blocked — missing-input]`.',
    '',
    '## Directives',
    '',
    '- Patch only demonstrable correctness gaps tied to ticket behavior.',
    '- Do not patch files under `docs/product/delivery/**`.',
    '- Surface doc-vs-code drift in `## Rationale` and contract docs under Findings.',
    '- Cross-model preferred when available; same-type review is acceptable.',
    '',
    'Output strictly per the `Required output format` section of the adversarial review template.',
  ].join('\n');
}

function normalizeUniquePatchCommitShas(rawShas: string[]): string[] {
  return [...new Set(rawShas.map((sha) => sha.trim()).filter(Boolean))];
}

function parsePostVerifyArgs(positionals: string[]): {
  auditOutcome?: ReviewOutcome;
  auditPatchCommitArgs: string[];
  auditTicketId?: string;
} {
  const positional0 = positionals[0];
  const positional1 = positionals[1];
  const isOutcome = (s: string | undefined): s is ReviewOutcome =>
    s === 'clean' || s === 'patched' || s === 'skipped';
  const auditOutcome: ReviewOutcome | undefined = isOutcome(positional0)
    ? positional0
    : isOutcome(positional1)
      ? positional1
      : undefined;
  const auditTicketId = !isOutcome(positional0) ? positional0 : undefined;
  const auditPatchCommitArgs = auditTicketId
    ? positionals.slice(2)
    : positionals.slice(1);
  return { auditOutcome, auditTicketId, auditPatchCommitArgs };
}

function resolveInternalReviewPatchCommits(
  cwd: string,
  context: DeliveryOrchestratorContext,
  rawShas: string[],
  suffix: '[post-verify]' | '[subagent-review]',
  stageLabel: string,
): InternalReviewPatchCommit[] {
  const platform = context.platform;
  return normalizeUniquePatchCommitShas(rawShas).map((sha) => {
    const subject = platform.readCommitSubject(cwd, sha);
    if (!subject.endsWith(` ${suffix}`)) {
      throw new Error(
        `${stageLabel} patch commit ${sha.slice(0, 12)} must end with " ${suffix}" (note the space).`,
      );
    }
    return { sha, subject };
  });
}

export async function openPullRequest(
  state: DeliveryState,
  cwd: string,
  context: DeliveryOrchestratorContext,
  ticketId?: string,
): Promise<DeliveryState> {
  const resolvedTicketId = ticketId;

  if (context.config.reviewPolicy.subagentReview !== 'disabled') {
    const targetTicket = resolvedTicketId
      ? state.tickets.find((t) => t.id === resolvedTicketId)
      : (state.tickets.find((t) => t.status === 'subagent_review_complete') ??
        state.tickets.find((t) => t.status === 'verified') ??
        state.tickets.find((t) => t.status === 'in_review'));

    if (
      targetTicket !== undefined &&
      targetTicket.subagentReviewOutcome != null &&
      targetTicket.subagentReviewOutcome !== 'skipped'
    ) {
      const rawArtifactPath = targetTicket.subagentRunnerArtifactPath;
      const artifactPath = rawArtifactPath
        ? resolve(cwd, rawArtifactPath)
        : undefined;
      const artifactExists =
        artifactPath !== undefined && existsSync(artifactPath);
      const artifact =
        artifactExists && artifactPath !== undefined
          ? (() => {
              try {
                return readSubagentRunnerArtifact(
                  artifactPath,
                  targetTicket.id,
                );
              } catch {
                return null;
              }
            })()
          : null;
      if (!artifact) {
        throw createWorkflowContractError(
          'workflow.open_pr.requires_runner_review',
          `Ticket ${targetTicket.id} requires a valid runner review artifact before opening a PR. subagentReviewOutcome="${targetTicket.subagentReviewOutcome}" but no artifact found at ${rawArtifactPath ?? '(path not set)'}. Re-run subagent-review to regenerate the artifact.`,
        );
      }
    }
  }

  const platform = context.platform;
  const nextState = openPullRequestImpl(state, cwd, resolvedTicketId, {
    assertReviewerFacingMarkdown,
    buildPullRequestBody,
    buildPullRequestTitle,
    subagentReviewPolicy: context.config.reviewPolicy.subagentReview,
    createPullRequest: platform.createPullRequest,
    editPullRequest: platform.editPullRequest,
    ensureBranchPushed: platform.ensureBranchPushed,
    findOpenPullRequest: platform.findOpenPullRequest,
    reportProgress: (message: string) => console.log(message),
    resolveGitHubRepo: platform.resolveGitHubRepoForOrchestrator,
  });

  // Detect doc-only PRs to skip the external AI review window.
  // Recompute on every open-pr call so that a PR that gains code changes
  // after an initial docs-only push has its docOnly flag cleared.
  const reviewTicket =
    (resolvedTicketId
      ? nextState.tickets.find((t) => t.id === resolvedTicketId)
      : nextState.tickets.find((t) => t.status === 'in_review')) ?? undefined;

  if (reviewTicket) {
    const docOnly = isPlatformLocalBranchDocOnly(
      reviewTicket.worktreePath,
      reviewTicket.baseBranch,
      context.config.runtime,
    );

    return {
      ...nextState,
      tickets: nextState.tickets.map((t) =>
        t.id === reviewTicket.id ? { ...t, docOnly: docOnly || undefined } : t,
      ),
    };
  }

  return nextState;
}

export async function pollReview(
  state: DeliveryState,
  cwd: string,
  context: DeliveryOrchestratorContext,
  ticketId?: string,
  maybeDependencies?: Partial<TicketReviewDependencies>,
  dependencies: Partial<TicketReviewDependencies> = {},
): Promise<DeliveryState> {
  const resolvedDependencies =
    typeof maybeDependencies === 'object' ? maybeDependencies : dependencies;
  const platform = context.platform;
  return runTicketReviewLifecycle(state, cwd, ticketId, {
    ...resolvedDependencies,
    relativeToRepo,
    replyToReviewThread:
      resolvedDependencies.replyToReviewThread ??
      platform.replyToReviewThreadForOrchestrator,
    resolveReviewFetcher,
    resolveReviewThread: platform.resolveReviewThread,
    resolveReviewTriager,
    ensureBranchPushed:
      resolvedDependencies.ensureBranchPushed ?? platform.ensureBranchPushed,
    runProcess: platform.runProcess,
    updatePullRequestBody:
      resolvedDependencies.updatePullRequestBody ??
      platform.updatePullRequestBody,
  });
}

export async function reconcileLateReview(
  state: DeliveryState,
  cwd: string,
  context: DeliveryOrchestratorContext,
  ticketId: string,
  maybeDependencies?: Partial<TicketReviewDependencies>,
  dependencies: Partial<TicketReviewDependencies> = {},
): Promise<DeliveryState> {
  const resolvedDependencies =
    typeof maybeDependencies === 'object' ? maybeDependencies : dependencies;
  if (!ticketId) {
    throw new Error('Missing ticket id for triage-ticket.');
  }
  const platform = context.platform;
  return runReconcileLateTicketReview(state, cwd, ticketId, {
    ...resolvedDependencies,
    relativeToRepo,
    replyToReviewThread:
      resolvedDependencies.replyToReviewThread ??
      platform.replyToReviewThreadForOrchestrator,
    resolveReviewFetcher,
    resolveReviewThread: platform.resolveReviewThread,
    resolveReviewTriager,
    ensureBranchPushed:
      resolvedDependencies.ensureBranchPushed ?? platform.ensureBranchPushed,
    runProcess: platform.runProcess,
    updatePullRequestBody:
      resolvedDependencies.updatePullRequestBody ??
      platform.updatePullRequestBody,
  });
}

export async function runStandaloneAiReview(
  cwd: string,
  notifier: DeliveryNotifier,
  context: DeliveryOrchestratorContext,
  prNumber?: number,
  maybeDependencies?: Partial<StandaloneAiReviewDependencies>,
  dependencies: Partial<StandaloneAiReviewDependencies> = {},
): Promise<StandaloneAiReviewResult> {
  const resolvedDependencies =
    typeof maybeDependencies === 'object' ? maybeDependencies : dependencies;
  const platform = context.platform;
  const pullRequest =
    resolvedDependencies.pullRequest ??
    platform.resolveStandalonePullRequest(cwd, prNumber);

  await emitNotificationWarnings(notifier, cwd, [
    buildStandaloneReviewStartedEvent(pullRequest.number, pullRequest.url),
  ]);

  return runStandaloneAiReviewLifecycle(cwd, prNumber, {
    ...resolvedDependencies,
    pullRequest,
    relativeToRepo,
    replyToReviewThread:
      resolvedDependencies.replyToReviewThread ??
      platform.replyToReviewThreadForOrchestrator,
    resolveReviewFetcher,
    resolveReviewThread: platform.resolveReviewThread,
    resolveReviewTriager,
    resolveStandalonePullRequest: platform.resolveStandalonePullRequest,
    runProcess: platform.runProcess,
    updatePullRequestBody:
      resolvedDependencies.updatePullRequestBody ??
      platform.updateStandalonePullRequestBody,
  });
}

export async function recordReview(
  state: DeliveryState,
  cwd: string,
  context: DeliveryOrchestratorContext,
  ticketId: string,
  outcome: ReviewResult,
  note?: string,
  maybeDependencies?: Partial<TicketReviewDependencies>,
  dependencies: Partial<TicketReviewDependencies> = {},
): Promise<DeliveryState> {
  const resolvedDependencies =
    typeof maybeDependencies === 'object' ? maybeDependencies : dependencies;
  const platform = context.platform;
  return recordTicketReview(state, cwd, ticketId, outcome, note, {
    ...(resolvedDependencies as Partial<TicketReviewDependencies>),
    relativeToRepo,
    replyToReviewThread:
      resolvedDependencies.replyToReviewThread ??
      platform.replyToReviewThreadForOrchestrator,
    resolveReviewFetcher,
    resolveReviewThread: platform.resolveReviewThread,
    resolveReviewTriager,
    ensureBranchPushed:
      resolvedDependencies.ensureBranchPushed ?? platform.ensureBranchPushed,
    runProcess: platform.runProcess,
    updatePullRequestBody:
      resolvedDependencies.updatePullRequestBody ??
      platform.updatePullRequestBody,
  });
}

async function advanceToNextTicketImpl(
  state: DeliveryState,
  cwd: string,
  context: DeliveryOrchestratorContext,
): Promise<DeliveryState> {
  const platform = context.platform;
  return advanceToNextTicket(state, cwd, {
    ensureBranchPushed: platform.ensureBranchPushed,
    updatePullRequestBody: platform.updatePullRequestBody,
  });
}

export async function applyAdvanceBoundaryMode(
  state: DeliveryState,
  advancedState: DeliveryState,
  cwd: string,
  context: DeliveryOrchestratorContext,
  dependencies: {
    startTicket: (
      state: DeliveryState,
      cwd: string,
      ticketId?: string,
    ) => Promise<DeliveryState>;
  } = {
    startTicket: (state, cwd, ticketId) =>
      startTicket(state, cwd, context, ticketId),
  },
): Promise<DeliveryState> {
  const nextPending = advancedState.tickets.find(
    (ticket) =>
      ticket.status === 'pending' &&
      state.tickets.find((previous) => previous.id === ticket.id)?.status ===
        'pending',
  );

  if (!nextPending) {
    return advancedState;
  }

  if (context.config.ticketBoundaryMode !== 'cook') {
    return advancedState;
  }

  return dependencies.startTicket(advancedState, cwd, nextPending.id);
}

async function restackTicket(
  state: DeliveryState,
  cwd: string,
  context: DeliveryOrchestratorContext,
  ticketId?: string,
): Promise<DeliveryState> {
  const platform = context.platform;
  return restackTicketImpl(state, cwd, ticketId, {
    buildPullRequestBody,
    defaultBranch: context.config.defaultBranch,
    editPullRequest: platform.editPullRequest,
    ensureCleanWorktree: platform.ensureCleanWorktree,
    fetchOrigin: platform.fetchOrigin,
    findOpenPullRequest: platform.findOpenPullRequest,
    hasMergedPullRequestForBranch: platform.hasMergedPullRequestForBranch,
    readCurrentBranch: platform.readCurrentBranch,
    readMergeBase: platform.readMergeBase,
    rebaseOnto: platform.rebaseOnto,
    rebaseOntoDefaultBranch: platform.rebaseOntoDefaultBranch,
    resolveGitHubRepo: platform.resolveGitHubRepoForOrchestrator,
  });
}

export function derivePlanKey(planPath: string): string {
  return derivePlanKeyImpl(planPath);
}

export async function emitSoaEventForOpenPr(
  _state: DeliveryState,
  _config: ResolvedOrchestratorConfig,
  _projectRoot: string,
  _ticketId?: string,
): Promise<void> {
  // pr_review_window_opened NDJSON emission retired in P17.03.
  // open_pr gate now emits to gate.json via emitOpenPrGate before openPullRequest.
  // This function is retained for backwards-compatible call sites and will be removed in P17.04.
}

export async function emitSoaEventsForTransitions(
  _previousState: DeliveryState,
  _nextState: DeliveryState,
  _config: ResolvedOrchestratorConfig,
  _projectRoot: string,
): Promise<void> {
  // ticket_started and ticket_completed now emit to gate.json via emitGateForTransitions.
  // This function is retained for backwards-compatible call sites and will be removed in P17.04.
}

export async function emitGateForTransitions(
  previousState: DeliveryState,
  nextState: DeliveryState,
  config: ResolvedOrchestratorConfig,
): Promise<void> {
  // Two-pass emission: completions first, starts second.
  // This makes ticket_started the resident last-write-wins value in cook mode
  // regardless of ticket array order.
  for (const previousTicket of previousState.tickets) {
    const nextTicket = nextState.tickets.find(
      (t) => t.id === previousTicket.id,
    );
    if (previousTicket.status !== 'done' && nextTicket?.status === 'done') {
      await writeGateEvent(config, {
        gate: GATE_NAMES.TICKET_COMPLETED,
        planKey: nextState.planKey,
        ticketId: nextTicket.id,
      });
    }
  }
  for (const previousTicket of previousState.tickets) {
    const nextTicket = nextState.tickets.find(
      (t) => t.id === previousTicket.id,
    );
    if (
      previousTicket.status !== 'in_progress' &&
      nextTicket?.status === 'in_progress'
    ) {
      await writeGateEvent(config, {
        gate: GATE_NAMES.TICKET_STARTED,
        planKey: nextState.planKey,
        ticketId: nextTicket.id,
      });
    }
  }
}

export async function emitStartExitGate(
  ticket: TicketState,
  config: ResolvedOrchestratorConfig,
  planKey: string,
): Promise<void> {
  // Conservative fallback: unknown/undefined redPolicy defaults to red_tdd
  // (stricter gate) rather than silently treating it as skipped.
  const gate =
    ticket.redPolicy === 'required'
      ? GATE_NAMES.RED_TDD
      : ticket.redPolicy === 'skip'
        ? GATE_NAMES.GREEN_TDD
        : GATE_NAMES.RED_TDD;
  await writeGateEvent(config, {
    gate,
    planKey,
    ticketId: ticket.id,
  });
}

export async function emitPostRedGate(
  ticket: TicketState,
  config: ResolvedOrchestratorConfig,
  planKey: string,
): Promise<void> {
  await writeGateEvent(config, {
    gate: GATE_NAMES.GREEN_TDD,
    planKey,
    ticketId: ticket.id,
  });
}

export async function emitAdversarialReviewGate(
  ticket: TicketState,
  config: ResolvedOrchestratorConfig,
  planKey: string,
): Promise<void> {
  await writeGateEvent(config, {
    gate: GATE_NAMES.ADVERSARIAL_REVIEW,
    planKey,
    ticketId: ticket.id,
  });
}

export async function emitOpenPrGate(
  ticket: TicketState,
  config: ResolvedOrchestratorConfig,
  planKey: string,
): Promise<void> {
  await writeGateEvent(config, {
    gate: GATE_NAMES.OPEN_PR,
    planKey,
    ticketId: ticket.id,
  });
}

export async function emitPollReviewGate(
  ticket: TicketState,
  config: ResolvedOrchestratorConfig,
  planKey: string,
): Promise<void> {
  await writeGateEvent(config, {
    gate: GATE_NAMES.POLL_REVIEW,
    planKey,
    ticketId: ticket.id,
  });
}

export async function emitRecordReviewGate(
  ticket: TicketState,
  config: ResolvedOrchestratorConfig,
  planKey: string,
): Promise<void> {
  await writeGateEvent(config, {
    gate: GATE_NAMES.RECORD_REVIEW,
    planKey,
    ticketId: ticket.id,
  });
}

export async function emitReviewCleanGate(
  events: DeliveryNotificationEvent[],
  config: ResolvedOrchestratorConfig,
  planKey: string,
): Promise<void> {
  const reviewEvent = events.find(
    (e): e is Extract<DeliveryNotificationEvent, { kind: 'review_recorded' }> =>
      e.kind === 'review_recorded' && e.outcome === 'clean',
  );
  if (reviewEvent) {
    await writeGateEvent(config, {
      gate: GATE_NAMES.REVIEW_CLEAN,
      planKey,
      ticketId: reviewEvent.ticketId,
    });
  }
}

function formatError(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  return String(error);
}

// ─── P14.03 reconciliation helpers ────────────────────────────────────────

function gitListChangedPaths(
  worktreePath: string,
  from: string,
  to: string,
): string[] {
  const r = spawnSync('git', ['diff', '--name-only', `${from}..${to}`], {
    cwd: worktreePath,
    encoding: 'utf-8',
  });
  return (r.stdout ?? '')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
}

function gitListCommitsInRange(
  worktreePath: string,
  from: string,
  to: string,
): { sha: string; subject: string }[] {
  const r = spawnSync('git', ['log', '--pretty=%H%x09%s', `${from}..${to}`], {
    cwd: worktreePath,
    encoding: 'utf-8',
  });
  return (r.stdout ?? '')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [sha, ...rest] = line.split('\t');
      return { sha: sha ?? '', subject: rest.join('\t') };
    });
}

function gitListCommitFiles(worktreePath: string, sha: string): string[] {
  const r = spawnSync('git', ['show', '--pretty=format:', '--name-only', sha], {
    cwd: worktreePath,
    encoding: 'utf-8',
  });
  return (r.stdout ?? '')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
}

function loadReconciliationContext(
  state: DeliveryState,
  cwd: string,
  ticketId?: string,
): {
  ticket: TicketState;
  artifactAbs: string;
  artifactRows: Array<{ outcome: string; reviewedHeadSha?: string }>;
  reviewedHeadSha: string;
  headSha: string;
  reviewedPaths: string[];
  reportMarkdown: string;
} {
  const ticket =
    (ticketId
      ? state.tickets.find((t) => t.id === ticketId)
      : (state.tickets.find((t) => t.status === 'subagent_review_complete') ??
        state.tickets.find((t) => t.status === 'verified') ??
        state.tickets.find((t) => t.status === 'in_review'))) ?? undefined;
  if (!ticket) {
    throw new Error(
      ticketId
        ? `Unknown ticket ${ticketId}.`
        : 'No ticket at subagent_review_complete / verified / in_review found.',
    );
  }
  const artifactRel =
    ticket.subagentRunnerArtifactPath ??
    `${state.reviewsDirPath}/${ticket.id}-subagent-review.ledger.json`;
  const artifactAbs = resolve(cwd, artifactRel);
  let rows: Array<{ outcome: string; reviewedHeadSha?: string }> = [];
  let reviewedHeadSha = '';
  if (existsSync(artifactAbs)) {
    try {
      const parsed = JSON.parse(readFileSync(artifactAbs, 'utf-8')) as {
        invocations?: Array<{ outcome: string; reviewedHeadSha?: string }>;
      };
      rows = parsed.invocations ?? [];
      const last = rows[rows.length - 1];
      if (last?.reviewedHeadSha) reviewedHeadSha = last.reviewedHeadSha;
    } catch {
      /* ignore */
    }
  }
  if (!reviewedHeadSha) {
    throw new Error(
      `No reviewedHeadSha recorded for ${ticket.id}. Run subagent-review first.`,
    );
  }
  const headSha = spawnSync('git', ['rev-parse', 'HEAD'], {
    cwd: ticket.worktreePath,
    encoding: 'utf-8',
  }).stdout.trim();

  // Reviewed paths = files modified between baseBranch and reviewedHeadSha.
  const reviewedPaths = gitListChangedPaths(
    ticket.worktreePath,
    ticket.baseBranch,
    reviewedHeadSha,
  );

  const outcomePath = `${state.reviewsDirPath}/${ticket.id}-subagent-review.report.md`;
  const outcomeAbs = resolve(cwd, outcomePath);
  const reportMarkdown = existsSync(outcomeAbs)
    ? readFileSync(outcomeAbs, 'utf-8')
    : '';

  return {
    ticket,
    artifactAbs,
    artifactRows: rows,
    reviewedHeadSha,
    headSha,
    reviewedPaths,
    reportMarkdown,
  };
}

function runReconciliationGate(
  state: DeliveryState,
  cwd: string,
  context: DeliveryOrchestratorContext,
  ticketId?: string,
): void {
  if (context.config.reviewPolicy.subagentReview === 'disabled') return;
  let ctx: ReturnType<typeof loadReconciliationContext>;
  try {
    ctx = loadReconciliationContext(state, cwd, ticketId);
  } catch {
    // No artifact / no reviewedHeadSha: existing open-pr gate handles
    // missing-artifact cases. Reconciliation only applies when a row exists.
    return;
  }
  // If the only recorded outcome is `skipped`, the runner gate didn't review
  // anything — reconciliation is N/A.
  const hasNonSkipped = ctx.artifactRows.some((r) => r.outcome !== 'skipped');
  if (!hasNonSkipped) return;

  const decision = reconcileReview({
    artifactRows: ctx.artifactRows,
    reportMarkdown: ctx.reportMarkdown,
    reviewedHeadSha: ctx.reviewedHeadSha,
    headSha: ctx.headSha,
    reviewedPaths: ctx.reviewedPaths,
    listCommitSubjects: (from, to) =>
      gitListCommitsInRange(ctx.ticket.worktreePath, from, to),
    listCommitFiles: (sha) => gitListCommitFiles(ctx.ticket.worktreePath, sha),
    listChangedPathsInRange: (from, to) =>
      gitListChangedPaths(ctx.ticket.worktreePath, from, to),
  });

  if (decision.kind === 'blocked') {
    throw new ReconciliationBlockedError(decision.condition, decision.message);
  }

  if (decision.kind === 'patched') {
    // Append a patched row referencing detected commit SHAs.
    const parsed = JSON.parse(readFileSync(ctx.artifactAbs, 'utf-8')) as {
      ticket: string;
      invocations: Array<Record<string, unknown>>;
    };
    // Dedup: if an existing patched row for this reviewedHeadSha already
    // records the same commit SHAs, skip the append. Prevents unbounded row
    // accumulation when commitDeliveryArtifactAndPush fails between writes
    // and re-runs of the gate.
    const alreadyRecorded = parsed.invocations.some((row) => {
      if (row['outcome'] !== 'patched') return false;
      if (row['reviewedHeadSha'] !== ctx.reviewedHeadSha) return false;
      const existing = row['patches'];
      if (!Array.isArray(existing)) return false;
      return decision.commitShas.every((sha) =>
        (existing as unknown[]).includes(sha),
      );
    });
    if (alreadyRecorded) {
      console.log(
        `reconcile-subagent-review: patched row for ${decision.commitShas.join(', ')} already recorded; skipping duplicate.`,
      );
      return;
    }
    parsed.invocations.push({
      runnerKind: 'operator-recorder',
      reviewedHeadSha: ctx.reviewedHeadSha,
      outcome: 'patched',
      completedAt: new Date().toISOString(),
      terminatedReason: 'completed',
      findings: [],
      probedSurfaces: [],
      patches: decision.commitShas,
      schemaVersion: SUBAGENT_LEDGER_SCHEMA_VERSION,
      primaryAgent: 'unknown',
      runnerSelfReport: null,
      fallbackFrom: null,
    });
    writeFileSync(
      ctx.artifactAbs,
      JSON.stringify(parsed, null, 2) + '\n',
      'utf-8',
    );
    commitDeliveryArtifactAndPush({
      absolutePath: ctx.artifactAbs,
      branch: ctx.ticket.branch,
      commitMessage: `chore(${ctx.ticket.id}): reconciliation appended patched row`,
      ensureBranchPushed: context.platform.ensureBranchPushed,
      relativeToRepo,
      repoRoot: cwd,
      runProcess: context.platform.runProcess,
    });
    console.log(
      `reconcile-subagent-review: appended patched row referencing ${decision.commitShas.join(', ')}`,
    );
  }
}

async function runReconcileSubagentReview(
  state: DeliveryState,
  cwd: string,
  context: DeliveryOrchestratorContext,
  ticketId?: string,
): Promise<void> {
  runReconciliationGate(state, cwd, context, ticketId);
  console.log(
    'reconcile-subagent-review: ledger is consistent with git state.',
  );
}

async function runAckReconciliation(
  state: DeliveryState,
  cwd: string,
  context: DeliveryOrchestratorContext,
  parsed: {
    ackReconciliation?: 'patched' | 'deferred' | 'clean';
    commitSha?: string;
    reason?: string;
    primary?: string;
    positionals: string[];
  },
): Promise<void> {
  if (!parsed.ackReconciliation) return;
  const ctx = loadReconciliationContext(state, cwd, parsed.positionals[0]);
  const primaryAgent = resolvePrimaryAgent({
    flag: parsed.primary,
    configField: context.config.primaryAgent,
  });
  recordAcknowledgment({
    artifactPath: ctx.artifactAbs,
    ticket: ctx.ticket.id,
    reviewedHeadSha: ctx.reviewedHeadSha,
    variant: parsed.ackReconciliation,
    commitSha: parsed.commitSha,
    reason: parsed.reason,
    primaryAgent,
  });
  commitDeliveryArtifactAndPush({
    absolutePath: ctx.artifactAbs,
    branch: ctx.ticket.branch,
    commitMessage: `chore(${ctx.ticket.id}): record subagent-review ack-reconciliation (${parsed.ackReconciliation})`,
    ensureBranchPushed: context.platform.ensureBranchPushed,
    relativeToRepo,
    repoRoot: cwd,
    runProcess: context.platform.runProcess,
  });
  console.log(
    `Recorded ${parsed.ackReconciliation} acknowledgment row for ${ctx.ticket.id}.`,
  );
}
