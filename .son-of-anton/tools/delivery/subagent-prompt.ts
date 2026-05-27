import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

import type { ReviewPolicyStageValue } from './config';
import type { TicketState } from './types';

export const SUBAGENT_ADVERSARIAL_PROMPT_SUFFIX = '-subagent-review.prompt.md';

export type SubagentAdversarialPromptResult = {
  absolutePath: string;
  relativePath: string;
  writtenAt: string;
};

export function deriveSubagentAdversarialPromptPath(
  reviewsDirPath: string,
  ticketId: string,
): string {
  return `${reviewsDirPath}/${ticketId}${SUBAGENT_ADVERSARIAL_PROMPT_SUFFIX}`;
}

/**
 * The prompt content must be a substantive primary-agent-authored brief, not
 * a stub or placeholder. We reject prompts that look like raw template
 * scaffolding to avoid silently moving a "primary-agent has thought about
 * this" gate forward without real thought.
 */
export function isValidSubagentAdversarialPromptContent(
  content: string,
): boolean {
  if (typeof content !== 'string') {
    return false;
  }

  const trimmed = content.trim();
  if (trimmed.length === 0) {
    return false;
  }

  // Minimum content length so a one-line stub does not pass.
  if (trimmed.length < 80) {
    return false;
  }

  // Reject angle-bracket TODO placeholders left from the template skeleton.
  if (
    /<TODO\b|<paste\b|<list each|<invariant>|<function\/path/i.test(content)
  ) {
    return false;
  }

  return true;
}

export function writeSubagentAdversarialPrompt(input: {
  repoRoot: string;
  reviewsDirPath: string;
  ticketId: string;
  content: string;
  now?: () => string;
}): SubagentAdversarialPromptResult {
  if (!isValidSubagentAdversarialPromptContent(input.content)) {
    throw new Error(
      `Refusing to write empty or placeholder-like subagent adversarial prompt for ticket ${input.ticketId}. ` +
        `Fill in invariants, attack surfaces, and diff context before recording.`,
    );
  }

  const relativePath = deriveSubagentAdversarialPromptPath(
    input.reviewsDirPath,
    input.ticketId,
  );
  const absolutePath = join(input.repoRoot, relativePath);
  mkdirSync(dirname(absolutePath), { recursive: true });
  writeFileSync(absolutePath, ensureTrailingNewline(input.content), 'utf-8');
  const writtenAt = (input.now ?? (() => new Date().toISOString()))();
  return { absolutePath, relativePath, writtenAt };
}

export function readSubagentAdversarialPrompt(
  repoRoot: string,
  relativePath: string,
): string {
  return readFileSync(resolve(repoRoot, relativePath), 'utf-8');
}

/**
 * Resolve the exact prompt bytes that must be sent to the subagent runner.
 *
 * P13.03 contract: programmatic runner invocations must consume the
 * primary-agent-authored prompt persisted by `write-subagent-adversarial-review`.
 * There is no generic changed-files fallback. Missing state path or missing
 * file on disk → hard error pointing the operator back to the prompt step.
 */
export function requireSubagentAdversarialPromptForRunner(input: {
  repoRoot: string;
  ticket: Pick<TicketState, 'id' | 'subagentAdversarialPromptPath'>;
}): string {
  const promptPath = input.ticket.subagentAdversarialPromptPath;
  if (!promptPath) {
    throw new Error(
      `Ticket ${input.ticket.id} requires a subagent adversarial review prompt before invoking the runner. ` +
        `Run \`write-subagent-adversarial-review ${input.ticket.id}\` first.`,
    );
  }
  const absolutePath = resolve(input.repoRoot, promptPath);
  if (!existsSync(absolutePath)) {
    throw new Error(
      `Recorded subagent adversarial review prompt for ticket ${input.ticket.id} is missing on disk at ${promptPath}. ` +
        `Re-run \`write-subagent-adversarial-review ${input.ticket.id}\` before invoking the runner.`,
    );
  }
  return readFileSync(absolutePath, 'utf-8');
}

export function subagentAdversarialPromptExists(absolutePath: string): boolean {
  return existsSync(absolutePath);
}

/**
 * Guard that the runner-invocation path can call before spawning the subagent
 * runner. It is a no-op when the policy is `disabled`, when the ticket is a
 * doc-only auto-skip under `skip_doc_only`, or when a valid prompt artifact is
 * persisted both in state and on disk. Otherwise it throws with a message that
 * points the operator to `write-subagent-adversarial-review`.
 */
export function assertSubagentAdversarialPromptPresent(input: {
  repoRoot: string;
  ticket: Pick<
    TicketState,
    'id' | 'subagentAdversarialPromptPath' | 'verifyOutcome'
  >;
  isDocOnly: boolean;
  policy: ReviewPolicyStageValue;
}): void {
  if (input.policy === 'disabled') {
    return;
  }

  if (input.policy === 'skip_doc_only' && input.isDocOnly) {
    return;
  }

  const promptPath = input.ticket.subagentAdversarialPromptPath;
  if (!promptPath) {
    throw new Error(
      `Ticket ${input.ticket.id} requires a subagent adversarial review prompt before invoking the runner. ` +
        `Run \`write-subagent-adversarial-review ${input.ticket.id}\` first.`,
    );
  }

  const absolutePath = resolve(input.repoRoot, promptPath);
  if (!subagentAdversarialPromptExists(absolutePath)) {
    throw new Error(
      `Recorded subagent adversarial review prompt for ticket ${input.ticket.id} is missing on disk at ${promptPath}. ` +
        `Re-run \`write-subagent-adversarial-review ${input.ticket.id}\` before invoking the runner.`,
    );
  }
}

function ensureTrailingNewline(content: string): string {
  return content.endsWith('\n') ? content : `${content}\n`;
}
