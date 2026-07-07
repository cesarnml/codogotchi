import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { execSync } from 'node:child_process';

import type { ResolvedOrchestratorConfig } from './config';

/** Flat TTL for all gate events: 30 seconds. The persistent UI gate badges are
 *  now the durable signal for which gate is active, so the animation only needs
 *  to mark the transition briefly rather than hold for minutes. */
const GATE_TTL_MS = 30_000;
/** Lease long enough to survive an overnight pause + next-day resume. */
const DELIVERY_CONTEXT_LEASE_MS = 24 * 60 * 60 * 1000;

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
  repoRoot?: string;
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
const DELIVERY_CONTEXT_JSON_FILENAME = 'delivery-context.json';
const GATE_TRANSITIONS_LOG_ROTATION_BYTES = 10 * 1024 * 1024;

export type DeliveryContextJsonPayload = {
  owner: 'soa';
  status: 'active' | 'cleared';
  repo_root: string;
  plan_key: string;
  ticket_id: string;
  last_gate: string;
  updated_at: string;
  lease_expires_at: string;
};

export function resolveCodogotchiHome(): string {
  return process.env['CODOGOTCHI_HOME'] || join(homedir(), '.codogotchi');
}

/**
 * Returns the main-worktree root for any git checkout, including linked
 * worktrees. `git rev-parse --git-common-dir` always points at the shared
 * `.git` dir regardless of which worktree is active; its parent is the main
 * checkout root. This makes delivery-context.json use the same path the hook
 * binary writes into `source_event.repo_root` (which also resolves from the
 * main checkout), so the renderer's repo-mismatch guard never fires for
 * worktrees of the same repository.
 */
function resolveCanonicalGitRoot(cwd: string): string {
  try {
    const raw = execSync('git rev-parse --git-common-dir', {
      cwd,
      encoding: 'utf8',
    }).trim();
    const absoluteCommonDir = isAbsolute(raw) ? raw : join(cwd, raw);
    return dirname(absoluteCommonDir);
  } catch {
    return cwd;
  }
}

type ActiveSession = {
  origin: string | undefined;
  sessionId: string | undefined;
};

/**
 * `.soa/active-session.json` is a shared, mutable pointer that any origin's
 * hook (Claude Code, Codex, Cursor, ...) can overwrite at any time. A single
 * ticket's gate sequence fires many `writeGateEvent` calls in succession
 * (ticket_started, red_tdd, green_tdd, ...); re-reading the file fresh on
 * every call let a concurrent, unrelated writer steal the routing mid-ticket
 * and silently misdirect a gate event into the wrong origin/session's file.
 * Cache the first *resolved* session per repoRoot for this process's
 * lifetime so the whole sequence stays pinned to whichever session actually
 * started the ticket. Deliberately do not cache an unresolved read (file
 * missing/malformed) so we keep retrying until the session becomes known.
 */
const resolvedSessionCache = new Map<string, ActiveSession>();

function readActiveSession(repoRoot: string): ActiveSession {
  const cached = resolvedSessionCache.get(repoRoot);
  if (cached) return cached;

  try {
    const raw = readFileSync(
      join(repoRoot, '.soa', 'active-session.json'),
      'utf8',
    );
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object') {
      const session: ActiveSession = {
        origin: typeof parsed.origin === 'string' ? parsed.origin : undefined,
        sessionId:
          typeof parsed.session_id === 'string' ? parsed.session_id : undefined,
      };
      if (session.origin && session.sessionId) {
        resolvedSessionCache.set(repoRoot, session);
      }
      return session;
    }
  } catch {
    // File absent or malformed — fall back to legacy single-file mode
  }
  return { origin: undefined, sessionId: undefined };
}

function rotateGateTransitionsLogIfNeeded(path: string): void {
  if (!existsSync(path)) return;
  if (statSync(path).size <= GATE_TRANSITIONS_LOG_ROTATION_BYTES) return;

  const backupPath = `${path}.1`;
  if (existsSync(backupPath)) rmSync(backupPath);
  renameSync(path, backupPath);
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
    const repoRoot = resolveCanonicalGitRoot(
      resolve(event.repoRoot ?? process.cwd()),
    );

    const { origin, sessionId } = readActiveSession(repoRoot);

    const payload: GateJsonPayload = {
      gate: event.gate,
      since: since.toISOString(),
      expires_at: expiresAt.toISOString(),
      plan_key: event.planKey,
      ticket_id: event.ticketId,
    };

    const stateDir = join(home, 'state.d');
    const gateFile =
      origin && sessionId
        ? join(stateDir, `${origin}:${sessionId}.gate.json`)
        : join(home, GATE_JSON_FILENAME);
    const contextFile =
      origin && sessionId
        ? join(stateDir, `${origin}:${sessionId}.context.json`)
        : join(home, DELIVERY_CONTEXT_JSON_FILENAME);

    mkdirSync(home, { recursive: true });
    if (origin && sessionId) mkdirSync(stateDir, { recursive: true });
    const serialized = JSON.stringify(payload);
    writeFileSync(gateFile, serialized, 'utf8');

    const transitionsLogFile = join(home, GATE_TRANSITIONS_LOG_FILENAME);
    rotateGateTransitionsLogIfNeeded(transitionsLogFile);
    appendFileSync(transitionsLogFile, `${serialized}\n`, 'utf8');

    const contextPayload: DeliveryContextJsonPayload = {
      owner: 'soa',
      status: event.gate === GATE_NAMES.TICKET_COMPLETED ? 'cleared' : 'active',
      repo_root: repoRoot,
      plan_key: event.planKey,
      ticket_id: event.ticketId,
      last_gate: event.gate,
      updated_at: since.toISOString(),
      lease_expires_at: new Date(
        since.getTime() + DELIVERY_CONTEXT_LEASE_MS,
      ).toISOString(),
    };
    writeFileSync(contextFile, JSON.stringify(contextPayload), 'utf8');
  } catch {
    // best-effort: write failures never abort a delivery command
  }
}
