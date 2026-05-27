import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

export const VALID_TICKET_BOUNDARY_MODES = ['cook', 'gated'] as const;

export type TicketBoundaryMode = (typeof VALID_TICKET_BOUNDARY_MODES)[number];

export const VALID_REVIEW_POLICY_STAGE_VALUES = [
  'required',
  'skip_doc_only',
  'disabled',
] as const;

export type ReviewPolicyStageValue =
  (typeof VALID_REVIEW_POLICY_STAGE_VALUES)[number];

export type ReviewPolicy = {
  subagentReview?: ReviewPolicyStageValue;
  prReview?: ReviewPolicyStageValue;
};

export type ResolvedReviewPolicy = {
  subagentReview: ReviewPolicyStageValue;
  prReview: ReviewPolicyStageValue;
};

export type PrReviewAgent = {
  name: string;
  login: string;
  resolveThreads: boolean;
};

export const VALID_SUBAGENT_RUNNERS = [
  'claude-cli',
  'codex-cli',
  'cursor-cli',
] as const;
export type SubagentRunnerSelection = (typeof VALID_SUBAGENT_RUNNERS)[number];

export type CodogotchiConfig = {
  enabled: boolean;
};

export type OrchestratorConfig = {
  defaultBranch?: string;
  planRoot?: string;
  runtime?: 'bun' | 'node';
  packageManager?: 'bun' | 'npm' | 'pnpm' | 'yarn';
  ticketBoundaryMode?: TicketBoundaryMode;
  reviewPolicy?: ReviewPolicy;
  prReviewAgents?: PrReviewAgent[];
  /** Default subagent for `subagent-review` when no `--subagent` flag is passed. */
  subagentRunner?: SubagentRunnerSelection;
  /** Default primary-agent identity recorded on every ledger row. Free-form. */
  primaryAgent?: string;
  codogotchi?: CodogotchiConfig;
};

export type ResolvedOrchestratorConfig = {
  defaultBranch: string;
  planRoot: string;
  runtime: 'bun' | 'node';
  packageManager: 'bun' | 'npm' | 'pnpm' | 'yarn';
  ticketBoundaryMode: TicketBoundaryMode;
  reviewPolicy: ResolvedReviewPolicy;
  prReviewAgents?: PrReviewAgent[];
  subagentRunner?: SubagentRunnerSelection;
  primaryAgent?: string;
  codogotchi?: CodogotchiConfig;
};

const VALID_RUNTIMES = ['bun', 'node'] as const;
const VALID_PACKAGE_MANAGERS = ['bun', 'npm', 'pnpm', 'yarn'] as const;

export async function loadOrchestratorConfig(
  cwd: string,
): Promise<OrchestratorConfig> {
  const configPath = resolve(cwd, 'orchestrator.config.json');

  if (!existsSync(configPath)) {
    return {};
  }

  const raw = requireConfigObject(
    JSON.parse(await readFile(configPath, 'utf8')),
    'orchestrator.config.json',
  );

  if (
    raw.runtime !== undefined &&
    !VALID_RUNTIMES.includes(raw.runtime as (typeof VALID_RUNTIMES)[number])
  ) {
    throw new Error(
      `Invalid runtime "${String(raw.runtime)}" in orchestrator.config.json. Expected: ${VALID_RUNTIMES.join(', ')}`,
    );
  }

  if (
    raw.packageManager !== undefined &&
    !VALID_PACKAGE_MANAGERS.includes(
      raw.packageManager as (typeof VALID_PACKAGE_MANAGERS)[number],
    )
  ) {
    throw new Error(
      `Invalid packageManager "${String(raw.packageManager)}" in orchestrator.config.json. Expected: ${VALID_PACKAGE_MANAGERS.join(', ')}`,
    );
  }

  if (
    raw.ticketBoundaryMode !== undefined &&
    !VALID_TICKET_BOUNDARY_MODES.includes(
      raw.ticketBoundaryMode as (typeof VALID_TICKET_BOUNDARY_MODES)[number],
    )
  ) {
    throw new Error(
      `Invalid ticketBoundaryMode "${String(raw.ticketBoundaryMode)}" in orchestrator.config.json. Expected: ${VALID_TICKET_BOUNDARY_MODES.join(', ')}`,
    );
  }

  const defaultBranch = optionalNonBlankString(
    raw.defaultBranch,
    'defaultBranch',
    'orchestrator.config.json',
  );
  const planRoot = optionalNonBlankString(
    raw.planRoot,
    'planRoot',
    'orchestrator.config.json',
  );

  for (const retired of [
    'reviewSubagentOverride',
    'subagentReviewRunner',
  ] as const) {
    if (retired in raw) {
      throw new Error(
        `orchestrator.config.json: "${retired}" has been removed. Delete it from your config.`,
      );
    }
  }

  const reviewPolicy =
    raw.reviewPolicy !== undefined
      ? parseReviewPolicy(raw.reviewPolicy)
      : undefined;

  const resolvedPrReview = reviewPolicy?.prReview ?? undefined;
  const prReviewAgents =
    raw.prReviewAgents !== undefined
      ? parsePrReviewAgents(raw.prReviewAgents)
      : undefined;

  if (
    resolvedPrReview !== undefined &&
    resolvedPrReview !== 'disabled' &&
    prReviewAgents === undefined
  ) {
    throw new Error(
      'orchestrator.config.json: prReviewAgents is required when reviewPolicy.prReview is not "disabled". Add a prReviewAgents array or set prReview to "disabled".',
    );
  }

  let subagentRunner: SubagentRunnerSelection | undefined;
  if (raw.subagentRunner !== undefined) {
    if (
      typeof raw.subagentRunner !== 'string' ||
      !VALID_SUBAGENT_RUNNERS.includes(
        raw.subagentRunner as SubagentRunnerSelection,
      )
    ) {
      throw new Error(
        `Invalid subagentRunner "${String(raw.subagentRunner)}" in orchestrator.config.json. Expected: ${VALID_SUBAGENT_RUNNERS.join(', ')}`,
      );
    }
    subagentRunner = raw.subagentRunner as SubagentRunnerSelection;
  }

  let primaryAgent: string | undefined;
  if (raw.primaryAgent !== undefined) {
    if (
      typeof raw.primaryAgent !== 'string' ||
      raw.primaryAgent.trim() === ''
    ) {
      throw new Error(
        'Invalid primaryAgent in orchestrator.config.json. Expected a non-blank string (e.g. "claude", "codex", "cursor").',
      );
    }
    primaryAgent = raw.primaryAgent.trim();
  }

  let codogotchi: CodogotchiConfig | undefined;
  if (raw.codogotchi !== undefined) {
    codogotchi = parseCodogotchiConfig(raw.codogotchi);
  }

  return {
    defaultBranch,
    planRoot,
    runtime: raw.runtime as OrchestratorConfig['runtime'],
    packageManager: raw.packageManager as OrchestratorConfig['packageManager'],
    ticketBoundaryMode:
      raw.ticketBoundaryMode as OrchestratorConfig['ticketBoundaryMode'],
    reviewPolicy,
    prReviewAgents,
    subagentRunner,
    primaryAgent,
    codogotchi,
  };
}

export function inferPackageManager(
  cwd: string,
): ResolvedOrchestratorConfig['packageManager'] {
  if (existsSync(resolve(cwd, 'bun.lock'))) return 'bun';
  if (existsSync(resolve(cwd, 'pnpm-lock.yaml'))) return 'pnpm';
  if (existsSync(resolve(cwd, 'yarn.lock'))) return 'yarn';
  if (existsSync(resolve(cwd, 'package-lock.json'))) return 'npm';
  return 'npm';
}

export function resolveOrchestratorConfig(
  raw: OrchestratorConfig,
  cwd: string,
): ResolvedOrchestratorConfig {
  return {
    defaultBranch: raw.defaultBranch?.trim() || 'main',
    planRoot: raw.planRoot?.trim() || 'docs',
    runtime: raw.runtime ?? 'bun',
    packageManager: raw.packageManager ?? inferPackageManager(cwd),
    ticketBoundaryMode: raw.ticketBoundaryMode ?? 'cook',
    reviewPolicy: {
      subagentReview: raw.reviewPolicy?.subagentReview ?? 'skip_doc_only',
      prReview: raw.reviewPolicy?.prReview ?? 'skip_doc_only',
    },
    prReviewAgents: raw.prReviewAgents,
    subagentRunner: raw.subagentRunner,
    primaryAgent: raw.primaryAgent,
    codogotchi: raw.codogotchi ?? { enabled: true },
  };
}

function requireConfigObject(
  raw: unknown,
  sourceLabel: string,
): Record<string, unknown> {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    throw new Error(`${sourceLabel} must contain a JSON object.`);
  }

  return raw as Record<string, unknown>;
}

function parseReviewPolicy(raw: unknown): ReviewPolicy {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    throw new Error(
      'Invalid reviewPolicy in orchestrator.config.json. Expected an object.',
    );
  }

  const obj = raw as Record<string, unknown>;
  const result: ReviewPolicy = {};

  // Hard error for retired keys — must be caught before the unknown-key guard.
  if ('selfAudit' in obj) {
    throw new Error(
      'orchestrator.config.json: reviewPolicy.selfAudit has been removed. Use reviewPolicy.subagentReview instead.',
    );
  }
  if ('codexPreflight' in obj) {
    throw new Error(
      'orchestrator.config.json: reviewPolicy.codexPreflight has been removed. Use reviewPolicy.subagentReview instead.',
    );
  }

  const KNOWN_KEYS = ['subagentReview', 'prReview'] as const;

  for (const unknownKey of Object.keys(obj)) {
    if (!KNOWN_KEYS.includes(unknownKey as (typeof KNOWN_KEYS)[number])) {
      throw new Error(
        `Unknown reviewPolicy key "${unknownKey}" in orchestrator.config.json. Expected keys: ${KNOWN_KEYS.join(', ')}`,
      );
    }
  }

  for (const key of KNOWN_KEYS) {
    const value = obj[key];

    if (value === undefined) {
      continue;
    }

    if (
      !VALID_REVIEW_POLICY_STAGE_VALUES.includes(
        value as ReviewPolicyStageValue,
      )
    ) {
      throw new Error(
        `Invalid reviewPolicy.${key} "${String(value)}" in orchestrator.config.json. Expected: ${VALID_REVIEW_POLICY_STAGE_VALUES.join(', ')}`,
      );
    }

    result[key] = value as ReviewPolicyStageValue;
  }

  return result;
}

function parsePrReviewAgents(raw: unknown): PrReviewAgent[] {
  if (!Array.isArray(raw)) {
    throw new Error(
      'orchestrator.config.json: prReviewAgents must be an array.',
    );
  }

  return raw.map((item: unknown, index: number) => {
    if (typeof item !== 'object' || item === null || Array.isArray(item)) {
      throw new Error(
        `orchestrator.config.json: prReviewAgents[${index}] must be an object.`,
      );
    }

    const obj = item as Record<string, unknown>;

    if (typeof obj['name'] !== 'string' || obj['name'].trim() === '') {
      throw new Error(
        `orchestrator.config.json: prReviewAgents[${index}].name must be a non-blank string.`,
      );
    }

    if (typeof obj['login'] !== 'string' || obj['login'].trim() === '') {
      throw new Error(
        `orchestrator.config.json: prReviewAgents[${index}].login must be a non-blank string.`,
      );
    }

    return {
      name: obj['name'].trim(),
      login: obj['login'].trim(),
      resolveThreads: obj['resolveThreads'] === true,
    };
  });
}

function parseCodogotchiConfig(raw: unknown): CodogotchiConfig {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    throw new Error(
      'Invalid codogotchi in orchestrator.config.json. Expected an object.',
    );
  }
  const obj = raw as Record<string, unknown>;
  if (obj['enabled'] !== undefined && typeof obj['enabled'] !== 'boolean') {
    throw new Error(
      'Invalid codogotchi.enabled in orchestrator.config.json. Expected a boolean.',
    );
  }
  return { enabled: obj['enabled'] !== false };
}

function optionalNonBlankString(
  value: unknown,
  fieldName: string,
  sourceLabel: string,
): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== 'string') {
    throw new Error(
      `Invalid ${fieldName} in ${sourceLabel}. Expected a string.`,
    );
  }

  const normalized = value.trim();
  if (normalized.length === 0) {
    throw new Error(
      `Invalid ${fieldName} in ${sourceLabel}. Expected a non-blank string.`,
    );
  }

  return normalized;
}
