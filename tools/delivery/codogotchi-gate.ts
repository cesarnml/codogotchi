import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

import type { ResolvedOrchestratorConfig } from './config';

/** Flat TTL for all gate events: 3 minutes */
const GATE_TTL_MS = 180_000;

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
  gate: string;
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
    writeFileSync(join(home, 'gate.json'), JSON.stringify(payload), 'utf8');
  } catch {
    // best-effort: write failures never abort a delivery command
  }
}
