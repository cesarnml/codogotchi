import { existsSync, readFileSync } from 'node:fs';
import { readFile, readdir } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';

import { parseRedPolicy, type RedPolicy } from './ticket-metadata';
import type { OrchestratorOptions, TicketDefinition } from './types';
import { DEFAULT_REVIEW_POLLING_PROFILE } from './review-polling-profile';

export function parsePlan(
  markdown: string,
  planPath: string,
  cwd?: string,
): TicketDefinition[] {
  const ticketOrderSection = markdown.match(
    /## Ticket Order\s+([\s\S]*?)\n## Ticket Files/,
  )?.[1];
  const ticketFilesSection = markdown.match(
    /## Ticket Files\s+([\s\S]*?)\n## Exit Condition/,
  )?.[1];

  if (!ticketOrderSection || !ticketFilesSection) {
    throw new Error(`Could not parse ticket order from ${planPath}.`);
  }

  const titles = [
    ...ticketOrderSection.matchAll(/`([A-Z0-9.]+)\s+([^`]+)`/g),
  ].map((match) => ({
    id: match[1] ?? '',
    title: match[2] ?? '',
  }));
  const files = [...ticketFilesSection.matchAll(/`([^`]+)`/g)].map(
    (match) => match[1] ?? '',
  );

  if (titles.length === 0 || titles.length !== files.length) {
    throw new Error(
      `Ticket order and ticket file sections are inconsistent in ${planPath}.`,
    );
  }

  const planDir = dirname(planPath);

  return titles.map((ticket, index) => {
    const ticketFile = join(planDir, files[index] ?? '');
    return {
      ...ticket,
      slug: slugify(ticket.title),
      type: parseTicketType(resolve(cwd ?? '', ticketFile)),
      scope: parseTicketScope(resolve(cwd ?? '', ticketFile)),
      redPolicy: parseTicketRedPolicy(resolve(cwd ?? '', ticketFile)),
      ticketFile,
    };
  });
}

export function derivePlanKey(planPath: string): string {
  const normalizedPlanPath = normalizeRepoPath(planPath);

  if (basename(normalizedPlanPath).toLowerCase() === 'implementation-plan.md') {
    return slugify(basename(dirname(normalizedPlanPath)));
  }

  return normalizedPlanPath
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-md$/, '');
}

export function createOptions(input: {
  planPath?: string;
}): OrchestratorOptions {
  if (!input.planPath) {
    throw new Error(
      'Pass --plan <plan-path>. Phase aliases are no longer supported.',
    );
  }

  const planPath = normalizeRepoPath(input.planPath);
  const planKey = derivePlanKey(planPath);

  return {
    planPath,
    planKey,
    statePath: `.agents/delivery/${planKey}/state.json`,
    reviewsDirPath: `docs/product/delivery/${planKey}/reviews`,
    handoffsDirPath: `.agents/delivery/${planKey}/handoffs`,
    reviewPollIntervalMinutes: DEFAULT_REVIEW_POLLING_PROFILE.intervalMinutes,
    reviewPollMaxWaitMinutes: DEFAULT_REVIEW_POLLING_PROFILE.maxWaitMinutes,
  };
}

export async function inferPlanPathFromBranch(
  cwd: string,
  branch: string,
  planRoot: string,
  findExistingBranch: (
    branches: string[],
    definition: TicketDefinition,
  ) => { branch: string; source: 'ticket-id' | 'derived' } | undefined,
): Promise<string> {
  const planPaths = await listImplementationPlans(cwd, planRoot);
  const planIndex: Array<{ planPath: string; tickets: TicketDefinition[] }> =
    [];

  for (const planPath of planPaths) {
    const markdown = await readFile(resolve(cwd, planPath), 'utf8');
    planIndex.push({
      planPath,
      tickets: parsePlan(markdown, planPath, cwd),
    });
  }

  return resolvePlanPathForBranch(planIndex, branch, findExistingBranch);
}

export function resolvePlanPathForBranch(
  planIndex: Array<{ planPath: string; tickets: TicketDefinition[] }>,
  branch: string,
  findExistingBranch: (
    branches: string[],
    definition: TicketDefinition,
  ) => { branch: string; source: 'ticket-id' | 'derived' } | undefined,
): string {
  const matches: string[] = [];

  for (const plan of planIndex) {
    if (
      plan.tickets.some(
        (ticket) => findExistingBranch([branch], ticket)?.branch === branch,
      )
    ) {
      matches.push(plan.planPath);
    }
  }

  if (matches.length === 1) {
    return matches[0]!;
  }

  if (matches.length === 0) {
    throw new Error(
      `Could not infer a delivery plan for ${branch}. Pass --plan <plan-path>.`,
    );
  }

  throw new Error(
    `Multiple delivery plans match ${branch}: ${matches.join(', ')}. Pass --plan <plan-path>.`,
  );
}

async function listImplementationPlans(
  cwd: string,
  planRoot: string,
): Promise<string[]> {
  const deliveryRoot = resolve(cwd, planRoot, 'product/delivery');
  const entries = await readdir(deliveryRoot, { withFileTypes: true });

  return entries
    .filter((entry) => entry.isDirectory())
    .map((entry) =>
      relativeToRepo(
        cwd,
        resolve(deliveryRoot, entry.name, 'implementation-plan.md'),
      ),
    )
    .filter((planPath) => existsSync(resolve(cwd, planPath)))
    .sort();
}

function parseTicketType(ticketFilePath: string): string | undefined {
  try {
    const content = readFileSync(ticketFilePath, 'utf8');
    const match = content.match(/^Type:\s*(.+)$/im);
    return match ? match[1]!.trim().toLowerCase() : undefined;
  } catch {
    return undefined;
  }
}

function parseTicketScope(ticketFilePath: string): string | undefined {
  try {
    const content = readFileSync(ticketFilePath, 'utf8');
    const match = content.match(/^Scope:\s*(.+)$/im);
    return match ? match[1]!.trim().toLowerCase() : undefined;
  } catch {
    return undefined;
  }
}

function parseTicketRedPolicy(ticketFilePath: string): RedPolicy {
  let content: string;
  try {
    content = readFileSync(ticketFilePath, 'utf8');
  } catch {
    return 'required';
  }
  return parseRedPolicy(content);
}

function normalizeRepoPath(value: string): string {
  return value.replace(/^\.?\//, '');
}

export function relativeToRepo(cwd: string, absolutePath: string): string {
  return resolve(absolutePath).replace(`${resolve(cwd)}/`, '');
}

function slugify(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

export type BranchMatch = {
  branch: string;
  source: 'ticket-id' | 'derived';
};

export function deriveBranchName(
  definition: Pick<TicketDefinition, 'id' | 'slug'>,
): string {
  return `agents/${definition.id.toLowerCase().replace('.', '-')}-${definition.slug}`;
}

export function deriveWorktreePath(cwd: string, ticketId: string): string {
  const parent = dirname(resolve(cwd));
  const repoBaseName = basename(resolve(cwd)).replace(
    /_(?:p\d+(?:_\d+)?|ee\d+_\d+)$/,
    '',
  );
  return join(
    parent,
    `${repoBaseName}_${ticketId.toLowerCase().replace('.', '_')}`,
  );
}

function preferDeliveryBranch(branches: string[]): string {
  return (
    branches.find((branch) => branch.startsWith('agents/')) ?? branches[0]!
  );
}

export function findExistingBranch(
  branches: string[],
  definition: Pick<TicketDefinition, 'id' | 'slug'>,
): BranchMatch | undefined {
  const ticketIdToken = definition.id.toLowerCase().replace('.', '-');
  const ticketIdMatches = branches.filter((branch) => {
    const normalized = branch.toLowerCase();
    return (
      normalized.includes(`/${ticketIdToken}`) ||
      normalized.includes(`-${ticketIdToken}`) ||
      normalized.endsWith(ticketIdToken)
    );
  });

  if (ticketIdMatches.length > 0) {
    return {
      branch: preferDeliveryBranch(ticketIdMatches),
      source: 'ticket-id',
    };
  }

  const derived = deriveBranchName(definition);

  if (branches.includes(derived)) {
    return {
      branch: derived,
      source: 'derived',
    };
  }

  return undefined;
}
