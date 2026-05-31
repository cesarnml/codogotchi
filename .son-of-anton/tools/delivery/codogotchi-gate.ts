import { appendFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

import type { ResolvedOrchestratorConfig } from './config';

/** Flat TTL for all gate events: 30 seconds. The persistent UI gate badges are
 *  now the durable signal for which gate is active, so the animation only needs
 *  to mark the transition briefly rather than hold for minutes. */
const GATE_TTL_MS = 30_000;

/** Canonical gate-name strings matching the codogotchi schema-v4 ActivityState contract */
export const GATE_NAMES = {
  TICKET_STARTED: 'ticket_started',
  TICKET_COMPLETED: 'ticket_completed',
  RED_TDD: 'red_tdd',
  GREEN_TDD: 'green_tdd',
  ADVERSARIAL_REVIEW: 'adversarial_review',
  OPEN_PR: 'open_pr',
  POLL_REVIEW: 'poll_review',
  RECORD_REVIEW: 'record_review',
  REVIEW_CLEAN: 'review_clean',
} as const;

export type GateEvent = {
  gate: (typeof GATE_NAMES)[keyof typeof GATE_NAMES];
  planKey: string;
  ticketId: string;
};

export type GateJsonPayload = {
  gate: string;
  since: string;
  expires_at: string;
  plan_key: string;
  ticket_id: string;
};

const GATE_JSON_FILENAME = 'gate.json';
const GATE_TRANSITIONS_LOG_FILENAME = 'gate-transitions.log';

export function resolveCodogotchiHome(): string {
  return process.env['CODOGOTCHI_HOME'] || join(homedir(), '.codogotchi');
}

export async function writeGateEvent(
  config: ResolvedOrchestratorConfig,
  event: GateEvent,
): Promise<void> {
  try {
    if (config.codogotchi?.enabled === false) return;
    const home = resolveCodogotchiHome();
    const since = new Date();
    const expiresAt = new Date(since.getTime() + GATE_TTL_MS);
    const payload: GateJsonPayload = {
      gate: event.gate,
      since: since.toISOString(),
      expires_at: expiresAt.toISOString(),
      plan_key: event.planKey,
      ticket_id: event.ticketId,
    };
    mkdirSync(home, { recursive: true });
    const serialized = JSON.stringify(payload);
    writeFileSync(join(home, GATE_JSON_FILENAME), serialized, 'utf8');
    appendFileSync(join(home, GATE_TRANSITIONS_LOG_FILENAME), `${serialized}\n`, 'utf8');
  } catch {
    // best-effort: write failures never abort a delivery command
  }
}
