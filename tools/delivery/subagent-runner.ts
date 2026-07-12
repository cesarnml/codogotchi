import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

export type SubagentRunnerOutcome =
  | 'clean'
  | 'patched'
  | 'deferred'
  | 'skipped';

export const SUBAGENT_LEDGER_SCHEMA_VERSION = 1;

export type SubagentRunnerKind =
  | 'claude-cli'
  | 'codex-cli'
  | 'cursor-cli'
  | 'skipped'
  | 'operator-recorder';

/** Headless runners invoked by `subagent-review` (excludes recorder-only kinds). */
export const PROGRAMMATIC_SUBAGENT_RUNNERS = [
  'claude-cli',
  'codex-cli',
  'cursor-cli',
] as const;

export type ProgrammaticSubagentRunner =
  (typeof PROGRAMMATIC_SUBAGENT_RUNNERS)[number];

export type SubagentRunnerTerminatedReason =
  | 'completed'
  | 'rate_limit'
  | 'sandbox_denied'
  | 'runner_unavailable'
  | 'runner_failed'
  | 'advisory_violation';

export type SubagentRunnerFallbackLevel =
  | 'preferred'
  | 'fallback'
  | 'failed_all'
  | 'not_applicable';

export type SubagentRunnerInvocation = {
  runnerKind: SubagentRunnerKind;
  reviewedHeadSha: string;
  outcome: SubagentRunnerOutcome;
  completedAt: string;
  terminatedReason: SubagentRunnerTerminatedReason;
  /**
   * Repo-relative path to `reviews/<ticket>-subagent-review.report.md` (runner
   * prose). Legacy artifacts may still store inline stdout/stderr text.
   */
  rawOutput?: string;
  /**
   * Repo-relative path to `reviews/<ticket>-subagent-review.prompt.md`.
   * Legacy artifacts may still store inline prompt text.
   */
  filledPrompt?: string;
  fallbackLevel?: SubagentRunnerFallbackLevel;
  /**
   * Ledger schema version for this row. Pre-Phase-14 rows omit this field;
   * the validator preserves that absence rather than back-filling it.
   */
  schemaVersion?: number;
  /**
   * Free-form identity of the primary agent that drove this ticket
   * (e.g. `"claude-code"`, `"codex-cli"`). Defaults to `"unknown"` when a
   * row is parsed without it.
   */
  primaryAgent?: string;
  /**
   * Self-reported `runnerStatus` value emitted by the model in its prose,
   * when parseable. `null` when the runner did not surface one.
   */
  runnerSelfReport?: string | null;
  /**
   * Originally-requested subagent kind when a fallback fired. `null` when no
   * fallback was needed.
   */
  fallbackFrom?: SubagentRunnerKind | null;
  findings: string[];
  probedSurfaces: string[];
  patches: string[];
};

export type SubagentRunnerArtifact = {
  ticket: string;
  invocations: SubagentRunnerInvocation[];
};

export type SpawnResult = {
  exitCode: number | null;
  timedOut: boolean;
  stdout?: string;
  stderr?: string;
  rawOutput?: string;
  /**
   * Optional honest termination reason flagged by the spawn closure (e.g. a
   * rate-limit signature detected in stdout despite exit code 0). When omitted,
   * tryRunner defaults to `'completed'`.
   */
  terminatedReason?: SubagentRunnerTerminatedReason;
};

export type RunnerAttemptResult =
  | {
      status: 'ran';
      outcome: 'clean' | 'patched';
      terminatedReason: SubagentRunnerTerminatedReason;
      rawOutput?: string;
      stdout?: string;
      stderr?: string;
    }
  | { status: 'unavailable' }
  | { status: 'timeout' };

export function buildRunnerSpawnCommand(
  runner: ProgrammaticSubagentRunner,
  reviewPrompt: string,
  options: {
    outputLastMessagePath?: string;
    /** Ticket worktree path; required for cursor-cli headless runs. */
    workspacePath?: string;
  } = {},
): { bin: string; args: string[] } {
  if (runner === 'claude-cli') {
    return { bin: 'claude', args: ['-p', reviewPrompt] };
  }
  if (runner === 'cursor-cli') {
    return {
      bin: 'agent',
      args: [
        '--print',
        '--trust',
        '--output-format',
        'text',
        ...(options.workspacePath
          ? ['--workspace', options.workspacePath]
          : []),
        reviewPrompt,
      ],
    };
  }
  return {
    bin: 'codex',
    args: [
      'exec',
      ...(options.outputLastMessagePath
        ? ['--output-last-message', options.outputLastMessagePath]
        : []),
      '--color',
      'never',
      reviewPrompt,
    ],
  };
}

export function buildSubagentFallbackOrder(
  requested: ProgrammaticSubagentRunner,
): ProgrammaticSubagentRunner[] {
  return [
    requested,
    ...PROGRAMMATIC_SUBAGENT_RUNNERS.filter((kind) => kind !== requested),
  ];
}

/**
 * Operator-explicit subagent selection. Flag > config > hard error.
 * P14.02: SoA ships no silent default; missing both surfaces the contract
 * up-front rather than letting a runner be picked silently.
 */
export function resolveSubagentSelection(input: {
  flag: ProgrammaticSubagentRunner | undefined;
  configField: ProgrammaticSubagentRunner | undefined;
}): { kind: ProgrammaticSubagentRunner; source: 'flag' | 'config' } {
  if (input.flag) {
    return { kind: input.flag, source: 'flag' };
  }
  if (input.configField) {
    return { kind: input.configField, source: 'config' };
  }
  throw new Error(
    `No subagent selected. Pass --subagent <${PROGRAMMATIC_SUBAGENT_RUNNERS.join('|')}> or set \`subagentRunner\` in orchestrator.config.json. See docs/template/delivery/delivery-orchestrator.md for cross-family best-practice guidance.`,
  );
}

/**
 * Free-form primary-agent identity. Flag > config > "unknown".
 * P14.02: values like `cursor`, `composer`, `copilot`, `aider` pass through
 * without enum validation so the field captures whichever execution agent
 * actually drove the ticket.
 */
export function resolvePrimaryAgent(input: {
  flag: string | undefined;
  configField: string | undefined;
}): string {
  if (input.flag !== undefined && input.flag.trim() !== '') {
    return input.flag.trim();
  }
  if (input.configField !== undefined && input.configField.trim() !== '') {
    return input.configField.trim();
  }
  return 'unknown';
}

/**
 * P14.02 — codex-cli classification fidelity.
 *
 * Trusts the model's self-reported `runnerStatus: <value>` trailer when
 * present. Only escalates to skipped/rate_limit on the runner's authentic
 * structured signal — not on stderr text that resembles rate-limit prose.
 * Prevents the "stderr noise → silent skipped" misclassification documented
 * in the codogotchi P2 subagent-review audit.
 */
export function coerceCodexCliClassification(input: {
  exitCode: number | null;
  stdout: string;
  stderr: string;
}): {
  outcome: 'clean' | 'skipped';
  terminatedReason: SubagentRunnerTerminatedReason;
  runnerSelfReport: string | null;
} {
  const runnerSelfReport = parseRunnerStatusTrailer(input.stdout);

  if (isCodexCliAuthenticRateLimit(input)) {
    return {
      outcome: 'skipped',
      terminatedReason: 'rate_limit',
      runnerSelfReport,
    };
  }

  if (runnerSelfReport === 'completed') {
    return {
      outcome: 'clean',
      terminatedReason: 'completed',
      runnerSelfReport,
    };
  }

  if (input.exitCode !== 0) {
    return {
      outcome: 'skipped',
      terminatedReason: 'runner_failed',
      runnerSelfReport,
    };
  }
  if (`${input.stdout}${input.stderr}`.trim() === '') {
    return {
      outcome: 'skipped',
      terminatedReason: 'runner_failed',
      runnerSelfReport,
    };
  }
  return {
    outcome: 'clean',
    terminatedReason: 'completed',
    runnerSelfReport,
  };
}

function parseRunnerStatusTrailer(stdout: string): string | null {
  const lines = stdout
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  const tail = lines.slice(-50);
  for (let i = tail.length - 1; i >= 0; i -= 1) {
    const match = /^runnerStatus\s*:\s*(.+)$/i.exec(tail[i]!);
    if (match) {
      return match[1]!.trim();
    }
  }
  return null;
}

// Authentic rate-limit signal for codex-cli — derived from structured tokens
// (exit code and quoted JSON-shaped values), not from free-text matching.
function isCodexCliAuthenticRateLimit(input: {
  exitCode: number | null;
  stdout: string;
  stderr: string;
}): boolean {
  if (input.exitCode === 7) return true;
  return hasStructuredRateLimitToken(`${input.stdout}\n${input.stderr}`, [
    'error',
    'status',
    'code',
    'type',
  ]);
}

// Authentic rate-limit signal for claude-cli — Anthropic API structured error
// shape. Prose like "you've hit your limit" alone is NOT authentic; only the
// quoted `{"type":"rate_limit_error"}` (or `"overloaded_error"`) token counts.
function isClaudeCliAuthenticRateLimit(input: {
  exitCode: number | null;
  stdout: string;
  stderr: string;
}): boolean {
  return hasStructuredRateLimitToken(`${input.stdout}\n${input.stderr}`, [
    'type',
  ]);
}

function hasStructuredRateLimitToken(blob: string, keys: string[]): boolean {
  const allowedKeys = new Set(keys);
  return blob
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.startsWith('{') && line.endsWith('}'))
    .some((line) => {
      try {
        return jsonContainsRateLimitToken(JSON.parse(line), allowedKeys);
      } catch {
        return false;
      }
    });
}

function jsonContainsRateLimitToken(
  value: unknown,
  allowedKeys: Set<string>,
): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => jsonContainsRateLimitToken(item, allowedKeys));
  }
  if (!value || typeof value !== 'object') {
    return false;
  }
  for (const [key, child] of Object.entries(value)) {
    if (
      allowedKeys.has(key) &&
      typeof child === 'string' &&
      /^(?:rate_limited|rate_limit_exceeded|RATE_LIMIT(?:_EXCEEDED)?|rate_limit_error|overloaded_error)$/.test(
        child,
      )
    ) {
      return true;
    }
    if (jsonContainsRateLimitToken(child, allowedKeys)) {
      return true;
    }
  }
  return false;
}

// Authentic usage/rate-limit signal for cursor-cli `agent --print` — billing
// failures surface as short stdout prose (e.g. "out of usage"), not JSON trailers.
function isCursorCliAuthenticRateLimit(input: {
  exitCode: number | null;
  stdout: string;
  stderr: string;
}): boolean {
  if (
    hasStructuredRateLimitToken(`${input.stdout}\n${input.stderr}`, ['type'])
  ) {
    return true;
  }
  if (input.exitCode === 0) {
    return false;
  }
  const blob = `${input.stdout}\n${input.stderr}`;
  return (
    /\byou(?:'re| are) out of usage\b/i.test(blob) ||
    /\bout of usage\b/i.test(blob) ||
    /\brun out of usage credits\b/i.test(blob)
  );
}

/**
 * cursor-cli classification fidelity, symmetric to claude/codex-cli.
 */
export function coerceCursorCliClassification(input: {
  exitCode: number | null;
  stdout: string;
  stderr: string;
}): {
  outcome: 'clean' | 'skipped';
  terminatedReason: SubagentRunnerTerminatedReason;
  runnerSelfReport: string | null;
} {
  const runnerSelfReport = parseRunnerStatusTrailer(input.stdout);

  if (isCursorCliAuthenticRateLimit(input)) {
    return {
      outcome: 'skipped',
      terminatedReason: 'rate_limit',
      runnerSelfReport,
    };
  }

  if (runnerSelfReport === 'completed') {
    return {
      outcome: 'clean',
      terminatedReason: 'completed',
      runnerSelfReport,
    };
  }

  if (input.exitCode !== 0) {
    return {
      outcome: 'skipped',
      terminatedReason: 'runner_failed',
      runnerSelfReport,
    };
  }
  if (`${input.stdout}${input.stderr}`.trim() === '') {
    return {
      outcome: 'skipped',
      terminatedReason: 'runner_failed',
      runnerSelfReport,
    };
  }
  return {
    outcome: 'clean',
    terminatedReason: 'completed',
    runnerSelfReport,
  };
}

/**
 * P14.02 — claude-cli classification fidelity, symmetric to codex-cli.
 *
 * Trusts the model's self-reported `runnerStatus: <value>` trailer when
 * present. Only escalates to skipped/rate_limit on the runner's authentic
 * structured signal (Anthropic API `"type":"rate_limit_error"`), not on
 * stderr text that resembles rate-limit prose. Prevents prose like
 * "you have hit your rate limit" from producing a silent `skipped`.
 */
export function coerceClaudeCliClassification(input: {
  exitCode: number | null;
  stdout: string;
  stderr: string;
}): {
  outcome: 'clean' | 'skipped';
  terminatedReason: SubagentRunnerTerminatedReason;
  runnerSelfReport: string | null;
} {
  const runnerSelfReport = parseRunnerStatusTrailer(input.stdout);

  if (isClaudeCliAuthenticRateLimit(input)) {
    return {
      outcome: 'skipped',
      terminatedReason: 'rate_limit',
      runnerSelfReport,
    };
  }

  if (runnerSelfReport === 'completed') {
    return {
      outcome: 'clean',
      terminatedReason: 'completed',
      runnerSelfReport,
    };
  }

  if (input.exitCode !== 0) {
    return {
      outcome: 'skipped',
      terminatedReason: 'runner_failed',
      runnerSelfReport,
    };
  }
  if (`${input.stdout}${input.stderr}`.trim() === '') {
    return {
      outcome: 'skipped',
      terminatedReason: 'runner_failed',
      runnerSelfReport,
    };
  }
  return {
    outcome: 'clean',
    terminatedReason: 'completed',
    runnerSelfReport,
  };
}

/**
 * P14.02 — Runner availability fallback.
 *
 * Attempts the operator-selected runner first. On `unavailable`/`timeout`,
 * falls back to the other configured runner. The return value records what
 * actually ran (`ranKind`), what was originally requested when fallback
 * fired (`fallbackFrom`), and the bucket (`preferred|fallback|failed_all`).
 * When both runners are unavailable, `fallbackFrom` preserves the originally
 * requested kind so the skipped row remains auditable.
 */
export function runSubagentWithFallback(
  requested: ProgrammaticSubagentRunner,
  attempt: (kind: ProgrammaticSubagentRunner) => RunnerAttemptResult,
): {
  ranKind: ProgrammaticSubagentRunner | 'skipped';
  fallbackFrom: ProgrammaticSubagentRunner | null;
  fallbackLevel: 'preferred' | 'fallback' | 'failed_all';
  result: RunnerAttemptResult;
  attemptedKinds: ProgrammaticSubagentRunner[];
} {
  const order = buildSubagentFallbackOrder(requested);
  const attemptedKinds: ProgrammaticSubagentRunner[] = [];
  let lastResult: RunnerAttemptResult = { status: 'unavailable' };

  for (const [index, kind] of order.entries()) {
    attemptedKinds.push(kind);
    const result = attempt(kind);
    lastResult = result;
    if (result.status === 'ran') {
      return {
        ranKind: kind,
        fallbackFrom: index === 0 ? null : requested,
        fallbackLevel: index === 0 ? 'preferred' : 'fallback',
        result,
        attemptedKinds,
      };
    }
    if (!shouldFallbackToOtherRunner(result)) {
      break;
    }
  }

  return {
    ranKind: 'skipped',
    fallbackFrom: requested,
    fallbackLevel: 'failed_all',
    result: lastResult,
    attemptedKinds,
  };
}

export const SUBAGENT_REVIEW_OUTCOME_SUFFIX = '-subagent-review.report.md';
export const SUBAGENT_REVIEW_TRACE_SUFFIX = '-subagent-review.trace.log';

export function deriveSubagentReviewOutcomePath(
  reviewsDirPath: string,
  ticketId: string,
): string {
  return `${reviewsDirPath}/${ticketId}${SUBAGENT_REVIEW_OUTCOME_SUFFIX}`;
}

export function deriveSubagentReviewTracePath(
  reviewsDirPath: string,
  ticketId: string,
): string {
  return `${reviewsDirPath}/${ticketId}${SUBAGENT_REVIEW_TRACE_SUFFIX}`;
}

export function formatRawRunnerOutput(stdout = '', stderr = ''): string {
  const sections: string[] = [];
  if (stdout.trim() !== '') sections.push(`stdout:\n${stdout.trimEnd()}`);
  if (stderr.trim() !== '') sections.push(`stderr:\n${stderr.trimEnd()}`);
  return sections.join('\n\n');
}

export type SubagentReviewOutcomeWriteResult = {
  absolutePath: string;
  relativePath: string;
  traceAbsolutePath: string;
  traceRelativePath: string;
};

/**
 * Persist the runner's model report and local stderr trace sidecar.
 * The runner artifact stores `relativePath` in `rawOutput`, not the prose body.
 */
export function writeSubagentReviewOutcome(input: {
  repoRoot: string;
  reviewsDirPath: string;
  ticketId: string;
  stdout?: string;
  stderr?: string;
  /** When set, written as-is as the report body. */
  content?: string;
}): SubagentReviewOutcomeWriteResult {
  const body = input.content ?? input.stdout ?? '';
  const relativePath = deriveSubagentReviewOutcomePath(
    input.reviewsDirPath,
    input.ticketId,
  );
  const traceRelativePath = deriveSubagentReviewTracePath(
    input.reviewsDirPath,
    input.ticketId,
  );
  const absolutePath = join(input.repoRoot, relativePath);
  const traceAbsolutePath = join(input.repoRoot, traceRelativePath);
  mkdirSync(dirname(absolutePath), { recursive: true });
  writeFileSync(
    absolutePath,
    body.endsWith('\n') ? body : `${body}\n`,
    'utf-8',
  );
  writeFileSync(traceAbsolutePath, input.stderr ?? '', 'utf-8');
  return { absolutePath, relativePath, traceAbsolutePath, traceRelativePath };
}

export function isSubagentReviewOutcomePath(value: string): boolean {
  return value.endsWith(SUBAGENT_REVIEW_OUTCOME_SUFFIX);
}

export function isSubagentAdversarialPromptReference(value: string): boolean {
  return value.endsWith('-subagent-review.prompt.md');
}

export function classifyRunnerTermination(
  exitCode: number | null,
  stdout = '',
  stderr = '',
): SubagentRunnerTerminatedReason {
  const blob = `${stdout}\n${stderr}`.toLowerCase();
  if (
    /\byou['’]?ve hit your limit\b|\brate[\s_-]?limited\b|\brate[\s_-]?limit\s+(?:exceeded|reached|hit)\b|\b429\s+(too\s+many|rate)|\bquota\s+exceeded\b/.test(
      blob,
    )
  ) {
    return 'rate_limit';
  }
  if (/\bsandbox[\s_-]?(denied|blocked|violation)\b/.test(blob)) {
    return 'sandbox_denied';
  }
  if (exitCode !== 0) return 'runner_failed';
  if (`${stdout}${stderr}`.trim() === '') return 'runner_failed';
  return 'completed';
}

export function isDeliveryDocPath(filePath: string): boolean {
  const normalized = filePath.replace(/\\/g, '/').replace(/^\.\//, '');
  return (
    normalized === 'docs/product/delivery' ||
    normalized.startsWith('docs/product/delivery/')
  );
}

export function findDeliveryDocPaths(paths: string[]): string[] {
  return paths.filter(isDeliveryDocPath);
}

export function tryRunner(
  spawnProcess: () => SpawnResult,
  checkHasChanges: () => boolean,
): RunnerAttemptResult {
  let result: SpawnResult;
  try {
    // Synchronous spawn — checkHasChanges below is guaranteed post-exit so the
    // porcelain sample never races a runner that finishes its writes at exit.
    result = spawnProcess();
  } catch {
    return { status: 'unavailable' };
  }

  if (result.timedOut) return { status: 'timeout' };

  const hasOutputFields =
    result.stdout !== undefined ||
    result.stderr !== undefined ||
    result.rawOutput !== undefined;
  const terminatedReason =
    result.terminatedReason ??
    (hasOutputFields
      ? classifyRunnerTermination(result.exitCode, result.stdout, result.stderr)
      : 'completed');
  const hasChanges = checkHasChanges();
  return {
    status: 'ran',
    outcome: hasChanges ? 'patched' : 'clean',
    terminatedReason,
    stdout: result.stdout,
    stderr: result.stderr,
    rawOutput:
      result.rawOutput ??
      (hasOutputFields
        ? formatRawRunnerOutput(result.stdout, result.stderr)
        : undefined),
  };
}

/**
 * The narrow set of runner-attempt outcomes that justify falling back to the
 * other runner. Binary-availability failures and timeouts only — never
 * ambiguous output (rate_limit, sandbox_denied, exit-code-0-with-no-work),
 * which should surface honestly through terminatedReason instead.
 */
export function shouldFallbackToOtherRunner(
  result: RunnerAttemptResult,
): boolean {
  return result.status === 'unavailable' || result.status === 'timeout';
}

/**
 * @deprecated Legacy outcome resolver from before the advisory-only contract.
 * Retained only for test compatibility; runner invocation now uses
 * {@link decideAdvisoryRunnerOutcome} which enforces no-write semantics.
 */
export function decideSubagentOutcomeFromRunner(
  result: Extract<RunnerAttemptResult, { status: 'ran' }>,
): {
  outcome: SubagentRunnerOutcome;
  terminatedReason: SubagentRunnerTerminatedReason;
} {
  if (result.terminatedReason !== 'completed' && result.outcome === 'clean') {
    return { outcome: 'skipped', terminatedReason: result.terminatedReason };
  }
  return { outcome: result.outcome, terminatedReason: result.terminatedReason };
}

/**
 * Advisory-only contract for programmatic subagent runners.
 *
 * The runner is allowed to read and reason about the diff, but any file write
 * it performs (tracked or untracked, committed or working-tree) is a contract
 * violation, not a valid review outcome. This is the core P13.03 inversion:
 * `patched` is reserved for primary-agent recorder mode. The runner reports
 * findings; the primary agent applies any patches and records them separately.
 *
 * - runner wrote files → `{ outcome: 'skipped', terminatedReason: 'advisory_violation' }`
 * - runner completed cleanly and made no writes → preserve `clean`
 * - runner reported a non-completed termination reason (rate_limit, etc.) →
 *   collapse to `skipped` with the original terminatedReason preserved
 */
export function decideAdvisoryRunnerOutcome(
  result: Extract<RunnerAttemptResult, { status: 'ran' }>,
  info: { runnerWroteFiles: boolean },
): {
  outcome: SubagentRunnerOutcome;
  terminatedReason: SubagentRunnerTerminatedReason;
} {
  if (info.runnerWroteFiles) {
    return { outcome: 'skipped', terminatedReason: 'advisory_violation' };
  }
  if (result.terminatedReason !== 'completed') {
    return { outcome: 'skipped', terminatedReason: result.terminatedReason };
  }
  return { outcome: 'clean', terminatedReason: 'completed' };
}

const VALID_RUNNER_KINDS: SubagentRunnerKind[] = [
  'claude-cli',
  'codex-cli',
  'cursor-cli',
  'skipped',
  'operator-recorder',
];
const VALID_OUTCOMES: SubagentRunnerOutcome[] = [
  'clean',
  'patched',
  'deferred',
  'skipped',
];
const VALID_TERMINATED_REASONS: SubagentRunnerTerminatedReason[] = [
  'completed',
  'rate_limit',
  'sandbox_denied',
  'runner_unavailable',
  'runner_failed',
  'advisory_violation',
];
const VALID_FALLBACK_LEVELS: SubagentRunnerFallbackLevel[] = [
  'preferred',
  'fallback',
  'failed_all',
  'not_applicable',
];

export type BuildRunnerInvocationOptions = {
  terminatedReason?: SubagentRunnerTerminatedReason;
  rawOutput?: string;
  filledPrompt?: string;
  fallbackLevel?: SubagentRunnerFallbackLevel;
  schemaVersion?: number;
  primaryAgent?: string;
  runnerSelfReport?: string | null;
  fallbackFrom?: SubagentRunnerKind | null;
  findings?: string[];
  probedSurfaces?: string[];
  patches?: string[];
  completedAt?: string;
};

export function buildRunnerInvocation(
  runnerKind: SubagentRunnerKind,
  reviewedHeadSha: string,
  outcome: SubagentRunnerOutcome,
  options: BuildRunnerInvocationOptions = {},
): SubagentRunnerInvocation {
  return {
    runnerKind,
    reviewedHeadSha,
    outcome,
    completedAt: options.completedAt ?? new Date().toISOString(),
    terminatedReason: options.terminatedReason ?? 'completed',
    ...(options.rawOutput !== undefined
      ? { rawOutput: options.rawOutput }
      : {}),
    ...(options.filledPrompt !== undefined
      ? { filledPrompt: options.filledPrompt }
      : {}),
    ...(options.fallbackLevel !== undefined
      ? { fallbackLevel: options.fallbackLevel }
      : {}),
    ...(options.schemaVersion !== undefined
      ? { schemaVersion: options.schemaVersion }
      : {}),
    ...(options.primaryAgent !== undefined
      ? { primaryAgent: options.primaryAgent }
      : {}),
    ...(options.runnerSelfReport !== undefined
      ? { runnerSelfReport: options.runnerSelfReport }
      : {}),
    ...(options.fallbackFrom !== undefined
      ? { fallbackFrom: options.fallbackFrom }
      : {}),
    findings: options.findings ?? [],
    probedSurfaces: options.probedSurfaces ?? [],
    patches: options.patches ?? [],
  };
}

export function buildRunnerArtifact(
  ticket: string,
  invocations: SubagentRunnerInvocation[],
): SubagentRunnerArtifact {
  return { ticket, invocations };
}

function validateInvocation(value: unknown): SubagentRunnerInvocation | null {
  if (typeof value !== 'object' || value === null) return null;
  const obj = value as Record<string, unknown>;

  if (
    typeof obj['runnerKind'] !== 'string' ||
    !(VALID_RUNNER_KINDS as string[]).includes(obj['runnerKind'])
  ) {
    return null;
  }
  if (
    typeof obj['reviewedHeadSha'] !== 'string' ||
    obj['reviewedHeadSha'] === ''
  ) {
    return null;
  }
  if (
    typeof obj['outcome'] !== 'string' ||
    !(VALID_OUTCOMES as string[]).includes(obj['outcome'])
  ) {
    return null;
  }
  if (typeof obj['completedAt'] !== 'string' || obj['completedAt'] === '') {
    return null;
  }
  if (
    typeof obj['terminatedReason'] !== 'string' ||
    !(VALID_TERMINATED_REASONS as string[]).includes(obj['terminatedReason'])
  ) {
    return null;
  }
  const findings = validateStringArray(obj['findings']);
  if (findings === null) return null;
  const probedSurfaces = validateStringArray(obj['probedSurfaces']);
  if (probedSurfaces === null) return null;
  const patches = validateStringArray(obj['patches']);
  if (patches === null) return null;
  if (obj['rawOutput'] !== undefined && typeof obj['rawOutput'] !== 'string') {
    return null;
  }
  if (
    obj['filledPrompt'] !== undefined &&
    typeof obj['filledPrompt'] !== 'string'
  ) {
    return null;
  }
  if (
    obj['fallbackLevel'] !== undefined &&
    (typeof obj['fallbackLevel'] !== 'string' ||
      !(VALID_FALLBACK_LEVELS as string[]).includes(obj['fallbackLevel']))
  ) {
    return null;
  }
  if (
    obj['schemaVersion'] !== undefined &&
    (typeof obj['schemaVersion'] !== 'number' ||
      !Number.isInteger(obj['schemaVersion']))
  ) {
    return null;
  }
  if (
    obj['primaryAgent'] !== undefined &&
    typeof obj['primaryAgent'] !== 'string'
  ) {
    return null;
  }
  if (
    obj['runnerSelfReport'] !== undefined &&
    obj['runnerSelfReport'] !== null &&
    typeof obj['runnerSelfReport'] !== 'string'
  ) {
    return null;
  }
  if (
    obj['fallbackFrom'] !== undefined &&
    obj['fallbackFrom'] !== null &&
    (typeof obj['fallbackFrom'] !== 'string' ||
      !(VALID_RUNNER_KINDS as string[]).includes(obj['fallbackFrom']))
  ) {
    return null;
  }

  // The validator preserves input shape: Phase-14 fields are emitted only when
  // present in the source row. Readers should apply `getPrimaryAgent` /
  // `getRunnerSelfReport` / `getFallbackFrom` to materialize the documented
  // defaults (`"unknown"`, `null`, `null`) for legacy rows. Forward-compat note:
  // an unknown future `schemaVersion` (e.g. `999`) parses without throwing — the
  // contract for unknown versions is "read what you can; don't enforce".
  return {
    runnerKind: obj['runnerKind'] as SubagentRunnerKind,
    reviewedHeadSha: obj['reviewedHeadSha'] as string,
    outcome: obj['outcome'] as SubagentRunnerOutcome,
    completedAt: obj['completedAt'] as string,
    terminatedReason: obj['terminatedReason'] as SubagentRunnerTerminatedReason,
    ...(obj['rawOutput'] !== undefined
      ? { rawOutput: obj['rawOutput'] as string }
      : {}),
    ...(obj['filledPrompt'] !== undefined
      ? { filledPrompt: obj['filledPrompt'] as string }
      : {}),
    ...(obj['fallbackLevel'] !== undefined
      ? { fallbackLevel: obj['fallbackLevel'] as SubagentRunnerFallbackLevel }
      : {}),
    ...(obj['schemaVersion'] !== undefined
      ? { schemaVersion: obj['schemaVersion'] as number }
      : {}),
    ...(obj['primaryAgent'] !== undefined
      ? { primaryAgent: obj['primaryAgent'] as string }
      : {}),
    ...(obj['runnerSelfReport'] !== undefined
      ? { runnerSelfReport: obj['runnerSelfReport'] as string | null }
      : {}),
    ...(obj['fallbackFrom'] !== undefined
      ? { fallbackFrom: obj['fallbackFrom'] as SubagentRunnerKind | null }
      : {}),
    findings,
    probedSurfaces,
    patches,
  };
}

/**
 * Materialize the documented default for a row missing `primaryAgent`. Pre-
 * Phase-14 rows render as `"unknown"`; Phase-14 rows preserve whatever the
 * writer recorded.
 */
export function getPrimaryAgent(row: SubagentRunnerInvocation): string {
  return row.primaryAgent ?? 'unknown';
}

/**
 * Materialize the documented default for a row missing `runnerSelfReport`.
 * Defaults to `null` (no parseable self-report).
 */
export function getRunnerSelfReport(
  row: SubagentRunnerInvocation,
): string | null {
  return row.runnerSelfReport ?? null;
}

/**
 * Materialize the documented default for a row missing `fallbackFrom`.
 * Defaults to `null` (no fallback fired).
 */
export function getFallbackFrom(
  row: SubagentRunnerInvocation,
): SubagentRunnerKind | null {
  return row.fallbackFrom ?? null;
}

function validateStringArray(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  for (const entry of value) {
    if (typeof entry !== 'string') return null;
  }
  return value as string[];
}

export function validateRunnerArtifact(
  value: unknown,
): SubagentRunnerArtifact | null {
  if (typeof value !== 'object' || value === null) return null;
  const obj = value as Record<string, unknown>;

  if (typeof obj['ticket'] !== 'string' || obj['ticket'] === '') return null;
  if (!Array.isArray(obj['invocations'])) return null;

  const invocations: SubagentRunnerInvocation[] = [];
  for (const raw of obj['invocations']) {
    const validated = validateInvocation(raw);
    if (!validated) return null;
    invocations.push(validated);
  }
  if (invocations.length === 0) return null;

  return { ticket: obj['ticket'] as string, invocations };
}

function isLegacyShape(value: unknown): value is Record<string, unknown> {
  if (typeof value !== 'object' || value === null) return false;
  const obj = value as Record<string, unknown>;
  return !('invocations' in obj) && !('ticket' in obj) && 'runnerKind' in obj;
}

function liftLegacyArtifact(
  raw: Record<string, unknown>,
  ticket: string,
  sourcePath: string,
): SubagentRunnerArtifact {
  if (
    typeof raw['reviewedHeadSha'] !== 'string' ||
    raw['reviewedHeadSha'] === ''
  ) {
    throw new Error(
      `Legacy subagent runner artifact at ${sourcePath} is missing required field: reviewedHeadSha.`,
    );
  }
  if (
    typeof raw['outcome'] !== 'string' ||
    !(VALID_OUTCOMES as string[]).includes(raw['outcome'] as string)
  ) {
    throw new Error(
      `Legacy subagent runner artifact at ${sourcePath} is missing required field: outcome.`,
    );
  }
  if (typeof raw['completedAt'] !== 'string' || raw['completedAt'] === '') {
    throw new Error(
      `Legacy subagent runner artifact at ${sourcePath} is missing required field: completedAt.`,
    );
  }
  if (!(VALID_RUNNER_KINDS as string[]).includes(raw['runnerKind'] as string)) {
    throw new Error(
      `Legacy subagent runner artifact at ${sourcePath} has invalid runnerKind: ${String(raw['runnerKind'])}.`,
    );
  }

  const invocation: SubagentRunnerInvocation = {
    runnerKind: raw['runnerKind'] as SubagentRunnerKind,
    reviewedHeadSha: raw['reviewedHeadSha'],
    outcome: raw['outcome'] as SubagentRunnerOutcome,
    completedAt: raw['completedAt'],
    terminatedReason: 'completed',
    findings: [],
    probedSurfaces: [],
    patches: [],
  };
  return { ticket, invocations: [invocation] };
}

export function readSubagentRunnerArtifact(
  path: string,
  ticket: string,
): SubagentRunnerArtifact {
  const raw = JSON.parse(readFileSync(path, 'utf-8')) as unknown;

  if (isLegacyShape(raw)) {
    return liftLegacyArtifact(raw as Record<string, unknown>, ticket, path);
  }

  const validated = validateRunnerArtifact(raw);
  if (!validated) {
    throw new Error(
      `Subagent runner artifact at ${path} is not a valid structured SubagentRunnerArtifact.`,
    );
  }
  return validated;
}

export type ParsedSubagentReviewArgs = {
  ticketId?: string;
  outcome?: 'clean' | 'patched';
  reviewedHeadSha?: string;
  patchCommitArgs: string[];
  force: boolean;
};

export function parseSubagentReviewArgs(
  positionals: string[],
  flags: Set<string>,
): ParsedSubagentReviewArgs {
  const isOutcome = (value: string | undefined): value is 'clean' | 'patched' =>
    value === 'clean' || value === 'patched';

  let cursor = 0;
  let ticketId: string | undefined;

  if (positionals[cursor] !== undefined && !isOutcome(positionals[cursor])) {
    ticketId = positionals[cursor];
    cursor += 1;
  }

  let outcome: 'clean' | 'patched' | undefined;
  if (isOutcome(positionals[cursor])) {
    outcome = positionals[cursor] as 'clean' | 'patched';
    cursor += 1;
  }

  let reviewedHeadSha: string | undefined;
  if (outcome) {
    const sha = positionals[cursor];
    if (sha === undefined || sha.trim() === '') {
      throw new Error(
        'subagent-review recorder mode requires a HEAD SHA after the outcome: `subagent-review [ticket-id] <clean|patched> <sha> [patch-commit-sha ...]`.',
      );
    }
    reviewedHeadSha = sha;
    cursor += 1;
  }

  const patchCommitArgs = positionals.slice(cursor);
  if (!outcome && patchCommitArgs.length > 0) {
    throw new Error(
      `Unexpected positional argument: \`${patchCommitArgs[0]}\`. Usage: \`subagent-review [ticket-id] [clean|patched <sha> [patch-commit-sha ...]] [--force]\`.`,
    );
  }
  if (outcome === 'clean' && patchCommitArgs.length > 0) {
    throw new Error(
      'subagent-review patch commits are only allowed when outcome is `patched`.',
    );
  }

  return {
    ticketId,
    outcome,
    reviewedHeadSha,
    patchCommitArgs,
    force: flags.has('force'),
  };
}

export type SubagentReviewModeDecision =
  | {
      kind: 'recorder';
      reviewedHeadSha: string;
      outcome: 'clean' | 'patched';
    }
  | {
      kind: 'no-op';
      reviewedHeadSha: string;
      existingInvocationIndex: number;
    }
  | { kind: 'invoke-runner' };

export function decideSubagentReviewMode(
  args: {
    outcome?: 'clean' | 'patched';
    reviewedHeadSha?: string;
    force: boolean;
  },
  artifact: SubagentRunnerArtifact | null,
  currentHeadSha: string,
): SubagentReviewModeDecision {
  if (args.outcome && args.reviewedHeadSha) {
    return {
      kind: 'recorder',
      reviewedHeadSha: args.reviewedHeadSha,
      outcome: args.outcome,
    };
  }

  if (!args.force && artifact && currentHeadSha) {
    const idx = artifact.invocations.findIndex(
      (invocation) =>
        invocation.reviewedHeadSha === currentHeadSha &&
        invocation.outcome !== 'skipped',
    );
    if (idx >= 0) {
      return {
        kind: 'no-op',
        reviewedHeadSha: currentHeadSha,
        existingInvocationIndex: idx,
      };
    }
  }

  return { kind: 'invoke-runner' };
}

export function tryReadSubagentRunnerArtifact(
  path: string,
  ticket: string,
): SubagentRunnerArtifact | null {
  if (!existsSync(path)) return null;
  return readSubagentRunnerArtifact(path, ticket);
}

export function appendInvocationToArtifact(
  path: string,
  ticket: string,
  invocation: SubagentRunnerInvocation,
): SubagentRunnerArtifact {
  let existing: SubagentRunnerArtifact | null = null;
  if (existsSync(path)) {
    existing = readSubagentRunnerArtifact(path, ticket);
  }
  const invocations = existing
    ? [...existing.invocations, invocation]
    : [invocation];
  const artifact: SubagentRunnerArtifact = { ticket, invocations };

  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(artifact, null, 2) + '\n', 'utf-8');
  return artifact;
}
