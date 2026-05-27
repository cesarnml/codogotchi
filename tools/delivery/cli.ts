import {
  VALID_REVIEW_POLICY_STAGE_VALUES,
  VALID_SUBAGENT_RUNNERS,
  VALID_TICKET_BOUNDARY_MODES,
  type OrchestratorConfig,
  type ReviewPolicyStageValue,
  type TicketBoundaryMode,
} from './config';
import type { OrchestratorOptions } from './types';

export type BaselineValue = 'orchestrator' | 'run-policy';
export const VALID_BASELINE_VALUES: BaselineValue[] = [
  'orchestrator',
  'run-policy',
];

export type ParsedCliArgs = {
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
  baseline?: BaselineValue;
  promptFile?: string;
  ackReconciliation?: 'patched' | 'deferred' | 'clean';
  commitSha?: string;
  reason?: string;
  dispositionsPath?: string;
};

export const STANDALONE_TRIAGE_COMMAND = 'triage-standalone';
export const TICKET_TRIAGE_COMMAND = 'triage-ticket';

export function normalizeDeliveryCommand(command: string): string {
  if (command === 'ai-review') {
    return STANDALONE_TRIAGE_COMMAND;
  }

  if (command === 'reconcile-late-review') {
    return TICKET_TRIAGE_COMMAND;
  }

  return command;
}

export function isStandaloneTriageCommand(command: string): boolean {
  return normalizeDeliveryCommand(command) === STANDALONE_TRIAGE_COMMAND;
}

/**
 * Resolve runtime policy overrides from parsed CLI args onto the raw config.
 * CLI flags take precedence over config file values; absent flags preserve config.
 * Does not mutate `rawConfig` or `orchestrator.config.json`.
 */
export function resolveRuntimePolicyOverrides(
  parsed: Pick<
    ParsedCliArgs,
    'boundaryMode' | 'subagentReviewPolicy' | 'prReviewPolicy'
  >,
  rawConfig: OrchestratorConfig,
): OrchestratorConfig {
  const mergedReviewPolicy = {
    ...rawConfig.reviewPolicy,
    ...(parsed.subagentReviewPolicy !== undefined
      ? { subagentReview: parsed.subagentReviewPolicy }
      : {}),
    ...(parsed.prReviewPolicy !== undefined
      ? { prReview: parsed.prReviewPolicy }
      : {}),
  };

  const effectivePrReview = mergedReviewPolicy.prReview;

  if (
    parsed.prReviewPolicy !== undefined &&
    effectivePrReview !== 'disabled' &&
    (rawConfig.prReviewAgents === undefined ||
      rawConfig.prReviewAgents.length === 0)
  ) {
    throw new Error(
      `--pr-review-policy ${parsed.prReviewPolicy} requires prReviewAgents in orchestrator.config.json. Add a prReviewAgents array or use --pr-review-policy disabled.`,
    );
  }

  return {
    ...rawConfig,
    ticketBoundaryMode: parsed.boundaryMode ?? rawConfig.ticketBoundaryMode,
    reviewPolicy: mergedReviewPolicy,
  };
}

function isValidBoundaryMode(mode: unknown): mode is TicketBoundaryMode {
  return VALID_TICKET_BOUNDARY_MODES.includes(mode as TicketBoundaryMode);
}

export function getUsage(runDeliverInvocation: string): string {
  return [
    `Usage: ${runDeliverInvocation} [--plan <plan-path>] <command>`,
    '',
    'Commands:',
    '  triage-standalone [--pr <number>]',
    '  sync',
    '  status',
    '  repair-state',
    '  triage-advisory-observations --dispositions <path>',
    '  start [ticket-id]',
    '  post-red [ticket-id]',
    '  post-verify [ticket-id] [clean|patched] [patch-commit-sha ...]',
    '  write-subagent-adversarial-review [ticket-id] [--prompt-file <path>]',
    '  subagent-review [ticket-id] [clean|patched <sha>] [--force] [--subagent <claude-cli|codex-cli|cursor-cli>] [--primary <name>]',
    '  subagent-review record-deferred --reason "<rationale>" [ticket-id]',
    '  reconcile-subagent-review [ticket-id]',
    '  open-pr [ticket-id] [--ack-reconciliation <patched|deferred|clean>] [--commit <sha>] [--reason "<text>"]',
    '  poll-review [ticket-id]',
    '  triage-ticket <ticket-id>',
    '  record-review <ticket-id> <clean|patched|operator_input_needed> [note]',
    '  advance',
    '  restack [ticket-id]',
    '',
    'Aliases:',
    '  ai-review -> triage-standalone',
    '  reconcile-late-review -> triage-ticket',
    '',
    'Options:',
    '  --boundary-mode <cook|gated>',
    '  --subagent-review-policy <required|skip_doc_only|disabled>',
    '  --pr-review-policy <required|skip_doc_only|disabled>',
    '  --subagent <claude-cli|codex-cli|cursor-cli>',
    '  --primary <free-form name>',
    '  --ack-reconciliation <patched|deferred|clean>',
    '  --commit <sha>',
    '  --reason "<text>"',
    '  --dispositions <path>',
    '  --baseline <orchestrator|run-policy>',
  ].join('\n');
}

export function parseCliArgs(argv: string[], usage: string): ParsedCliArgs {
  let planPath: string | undefined;
  let prNumber: number | undefined;
  let boundaryMode: ParsedCliArgs['boundaryMode'];
  let subagentReviewPolicy: ParsedCliArgs['subagentReviewPolicy'];
  let prReviewPolicy: ParsedCliArgs['prReviewPolicy'];
  let subagent: ParsedCliArgs['subagent'];
  let primary: ParsedCliArgs['primary'];
  let baseline: ParsedCliArgs['baseline'];
  let promptFile: ParsedCliArgs['promptFile'];
  let ackReconciliation: ParsedCliArgs['ackReconciliation'];
  let commitSha: ParsedCliArgs['commitSha'];
  let reason: ParsedCliArgs['reason'];
  let dispositionsPath: ParsedCliArgs['dispositionsPath'];
  const flags = new Set<string>();
  const positionals: string[] = [];

  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];

    if (value === '--plan') {
      planPath = argv[index + 1];
      index += 1;
      continue;
    }

    if (value === '--pr') {
      const rawNumber = argv[index + 1];

      if (!rawNumber || Number.isNaN(Number(rawNumber))) {
        throw new Error('Pass --pr <number>.');
      }

      prNumber = Number(rawNumber);
      index += 1;
      continue;
    }

    if (value === '--boundary-mode') {
      const rawMode = argv[index + 1];

      if (rawMode === undefined) {
        throw new Error(
          `Missing value for --boundary-mode; pass one of <${VALID_TICKET_BOUNDARY_MODES.join('|')}>.`,
        );
      }

      if (!isValidBoundaryMode(rawMode)) {
        throw new Error(
          `Pass --boundary-mode <${VALID_TICKET_BOUNDARY_MODES.join('|')}>.`,
        );
      }

      boundaryMode = rawMode;
      index += 1;
      continue;
    }

    if (value === '--subagent-review-policy') {
      const raw = argv[index + 1];

      if (
        raw === undefined ||
        !VALID_REVIEW_POLICY_STAGE_VALUES.includes(
          raw as ReviewPolicyStageValue,
        )
      ) {
        throw new Error(
          `Pass --subagent-review-policy <${VALID_REVIEW_POLICY_STAGE_VALUES.join('|')}>.`,
        );
      }

      subagentReviewPolicy = raw as ReviewPolicyStageValue;
      index += 1;
      continue;
    }

    if (value === '--pr-review-policy') {
      const raw = argv[index + 1];

      if (
        raw === undefined ||
        !VALID_REVIEW_POLICY_STAGE_VALUES.includes(
          raw as ReviewPolicyStageValue,
        )
      ) {
        throw new Error(
          `Pass --pr-review-policy <${VALID_REVIEW_POLICY_STAGE_VALUES.join('|')}>.`,
        );
      }

      prReviewPolicy = raw as ReviewPolicyStageValue;
      index += 1;
      continue;
    }

    if (value === '--subagent') {
      const raw = argv[index + 1];
      if (
        raw === undefined ||
        raw.startsWith('--') ||
        !(VALID_SUBAGENT_RUNNERS as readonly string[]).includes(raw)
      ) {
        throw new Error(
          `Pass --subagent <${VALID_SUBAGENT_RUNNERS.join('|')}>.`,
        );
      }

      subagent = raw as ParsedCliArgs['subagent'];
      index += 1;
      continue;
    }

    if (value === '--primary') {
      const raw = argv[index + 1];

      if (raw === undefined || raw.startsWith('--') || raw.trim() === '') {
        throw new Error(
          'Pass --primary <name> (free-form, e.g. claude, codex, cursor, composer).',
        );
      }

      primary = raw.trim();
      index += 1;
      continue;
    }

    if (value === '--preferred-runner') {
      throw new Error(
        '--preferred-runner has been removed. Pass --subagent <claude-cli|codex-cli|cursor-cli> or set `subagentRunner` in orchestrator.config.json.',
      );
    }

    if (value === '--red-commit-sha') {
      throw new Error(
        '--red-commit-sha has been removed. Either author a `[red]` commit before continuing, or declare `Red: skip` in the ticket metadata if the ticket has no testable behavior.',
      );
    }

    if (value === '--prompt-file') {
      const raw = argv[index + 1];

      if (raw === undefined || raw.startsWith('--') || raw.trim() === '') {
        throw new Error('Pass --prompt-file <path>.');
      }

      promptFile = raw;
      index += 1;
      continue;
    }

    if (value === '--baseline') {
      const raw = argv[index + 1];

      if (
        raw === undefined ||
        !VALID_BASELINE_VALUES.includes(raw as BaselineValue)
      ) {
        throw new Error(
          `Pass --baseline <${VALID_BASELINE_VALUES.join('|')}>.`,
        );
      }

      baseline = raw as BaselineValue;
      index += 1;
      continue;
    }

    if (value === '--ack-reconciliation') {
      const raw = argv[index + 1];
      const VALID = ['patched', 'deferred', 'clean'] as const;
      if (
        raw === undefined ||
        raw.startsWith('--') ||
        !(VALID as readonly string[]).includes(raw)
      ) {
        throw new Error(`Pass --ack-reconciliation <${VALID.join('|')}>.`);
      }
      ackReconciliation = raw as 'patched' | 'deferred' | 'clean';
      index += 1;
      continue;
    }

    if (value === '--commit') {
      const raw = argv[index + 1];
      if (raw === undefined || raw.startsWith('--') || raw.trim() === '') {
        throw new Error('Pass --commit <sha>.');
      }
      commitSha = raw.trim();
      index += 1;
      continue;
    }

    if (value === '--reason') {
      const raw = argv[index + 1];
      if (raw === undefined || raw.startsWith('--')) {
        throw new Error(
          'Pass --reason "<rationale>" (the rationale is captured on the ledger for audit).',
        );
      }
      reason = raw;
      index += 1;
      continue;
    }

    if (value === '--dispositions') {
      const raw = argv[index + 1];
      if (raw === undefined || raw.startsWith('--') || raw.trim() === '') {
        throw new Error('Pass --dispositions <path>.');
      }
      dispositionsPath = raw;
      index += 1;
      continue;
    }

    if (value === '--phase') {
      throw new Error(
        '--phase has been removed. Pass --plan <plan-path> instead.',
      );
    }

    if (value?.startsWith('--')) {
      flags.add(value.slice(2));
      continue;
    }

    positionals.push(value ?? '');
  }

  const [command, ...rest] = positionals;

  if (!command) {
    throw new Error(usage);
  }

  return {
    command: normalizeDeliveryCommand(command),
    positionals: rest,
    flags,
    planPath,
    prNumber,
    boundaryMode,
    subagentReviewPolicy,
    prReviewPolicy,
    subagent,
    primary,
    baseline,
    promptFile,
    ackReconciliation,
    commitSha,
    reason,
    dispositionsPath,
  };
}

export async function resolveOptionsForCommand(input: {
  cwd: string;
  command: string;
  planPath?: string;
  createOptions: (input: { planPath?: string }) => OrchestratorOptions;
  inferPlanPathFromBranch: (cwd: string, branch: string) => Promise<string>;
  readCurrentBranch: (cwd: string) => string;
}): Promise<OrchestratorOptions> {
  const {
    command,
    createOptions,
    cwd,
    inferPlanPathFromBranch,
    planPath,
    readCurrentBranch,
  } = input;

  if (planPath) {
    return createOptions({ planPath });
  }

  if (command !== 'restack') {
    throw new Error(
      'Pass --plan <plan-path>. Phase aliases are no longer supported.',
    );
  }

  const branch = readCurrentBranch(cwd);
  const inferredPlanPath = await inferPlanPathFromBranch(cwd, branch);
  return createOptions({ planPath: inferredPlanPath });
}
