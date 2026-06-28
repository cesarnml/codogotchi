import {
  createOptions,
  createPlatformAdapters,
  type DeliveryPlatformAdapters,
  formatStatus,
  loadOrchestratorConfig,
  loadState,
  resolveOrchestratorConfig,
  saveState,
} from './orchestrator';
import type { ResolvedOrchestratorConfig } from './runtime-config';
import type { DeliveryState, TicketState } from './types';
import {
  computeAdvisoryObservationWarnings,
  formatAdvisoryObservationWarnings,
  type AdvisoryObservationWarning,
} from './advisory-observation-warnings';

type CloseoutStackArgs = {
  planPath: string;
};

type PullRequestSnapshot = {
  baseRefName?: string;
  headRefName?: string;
  mergedAt?: string | null;
  number: number;
  state: 'OPEN' | 'CLOSED' | 'MERGED';
  title: string;
  url: string;
};

type CloseoutSummary = {
  merged: Array<{
    prNumber: number;
    ticketId: string;
    url: string;
    landedVia: 'squash' | 'cherry-pick';
  }>;
  skippedMerged: Array<{ prNumber: number; ticketId: string; url: string }>;
};

export type PullRequestCommitRef = {
  oid: string;
  authoredDate?: string;
};

export function orderCommitsForCherryPick(
  commits: PullRequestCommitRef[],
): string[] {
  const sorted = [...commits].sort((left, right) => {
    const leftDate = left.authoredDate ?? '';
    const rightDate = right.authoredDate ?? '';

    if (leftDate !== rightDate) {
      return leftDate.localeCompare(rightDate);
    }

    return left.oid.localeCompare(right.oid);
  });

  return sorted.map((commit) => commit.oid);
}

export function parseCloseoutStackArgs(argv: string[]): CloseoutStackArgs {
  let planPath: string | undefined;

  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === '--plan') {
      planPath = argv[index + 1];
      index += 1;
      continue;
    }

    if (value?.startsWith('--')) {
      throw new Error(getUsage());
    }
  }

  if (!planPath?.trim()) {
    throw new Error(getUsage());
  }

  return {
    planPath: planPath.trim(),
  };
}

export function getCloseoutTicketChain(state: DeliveryState): TicketState[] {
  const incomplete = state.tickets.filter((ticket) => ticket.status !== 'done');

  if (incomplete.length > 0) {
    throw new Error(
      `closeout-stack requires the full phase to be done first. Incomplete tickets: ${incomplete.map((ticket) => `${ticket.id}=${ticket.status}`).join(', ')}`,
    );
  }

  const missingPr = state.tickets.filter(
    (ticket) => !ticket.prNumber || !ticket.prUrl,
  );

  if (missingPr.length > 0) {
    throw new Error(
      `closeout-stack requires tracked PR metadata for every ticket. Missing PRs: ${missingPr.map((ticket) => ticket.id).join(', ')}`,
    );
  }

  return state.tickets;
}

function getUsage(): string {
  return 'Usage: bun run closeout-stack --plan <plan-path>';
}

let closeoutPlatform: DeliveryPlatformAdapters | undefined;

function runProcessResult(
  cwd: string,
  cmd: string[],
): ReturnType<DeliveryPlatformAdapters['runProcessResult']> {
  if (!closeoutPlatform) {
    throw new Error('closeout-stack platform adapters are not initialized.');
  }

  return closeoutPlatform.runProcessResult(cwd, cmd);
}

function runProcess(cwd: string, cmd: string[]): string {
  const result = runProcessResult(cwd, cmd);
  if (result.exitCode !== 0) {
    const stderr = result.stderr || result.stdout || 'unknown command failure';
    throw new Error(`${cmd.join(' ')} failed: ${stderr}`);
  }

  return result.stdout.trim();
}

function ensureCleanWorktree(cwd: string): void {
  const status = runProcess(cwd, ['git', 'status', '--short']).trim();
  if (status.length > 0) {
    throw new Error(
      `Worktree ${cwd} is not clean. Commit or stash changes before closeout-stack.`,
    );
  }
}

function readJson<T>(cwd: string, cmd: string[]): T {
  return JSON.parse(runProcess(cwd, cmd)) as T;
}

function listPullRequestCommitOidsAscending(
  cwd: string,
  prNumber: number,
): string[] {
  const raw = readJson<{ commits?: PullRequestCommitRef[] }>(cwd, [
    'gh',
    'pr',
    'view',
    String(prNumber),
    '--json',
    'commits',
  ]);

  return orderCommitsForCherryPick(raw.commits ?? []);
}

/** True when `git cherry-pick` stopped because the patch is already on HEAD (empty commit). */
export function isEmptyCherryPickFailure(output: string): boolean {
  return /cherry-pick is now empty/i.test(output);
}

function cherryPickCommitOntoHead(cwd: string, oid: string): void {
  const parents = runProcess(cwd, ['git', 'show', '-s', '--format=%P', oid])
    .trim()
    .split(/\s+/)
    .filter((token) => token.length > 0);

  const pickCmd =
    parents.length > 1
      ? ['git', 'cherry-pick', '-m', '1', oid]
      : ['git', 'cherry-pick', oid];

  const result = runProcessResult(cwd, pickCmd);
  if (result.exitCode === 0) {
    return;
  }

  const detail = `${result.stderr}\n${result.stdout}`;
  if (isEmptyCherryPickFailure(detail)) {
    runProcess(cwd, ['git', 'cherry-pick', '--skip']);
    return;
  }

  throw new Error(`${pickCmd.join(' ')} failed: ${detail.trim()}`);
}

function resolveRepoSlug(cwd: string): string {
  return runProcess(cwd, [
    'gh',
    'repo',
    'view',
    '--json',
    'nameWithOwner',
    '--jq',
    '.nameWithOwner',
  ]);
}

function findPullRequestsForBranch(
  cwd: string,
  branch: string,
): PullRequestSnapshot[] {
  return readJson<PullRequestSnapshot[]>(cwd, [
    'gh',
    'pr',
    'list',
    '--state',
    'all',
    '--head',
    branch,
    '--json',
    'number,title,state,baseRefName,headRefName,url,mergedAt',
  ]).sort((left, right) => right.number - left.number);
}

function resolvePullRequestForTicket(
  cwd: string,
  ticket: TicketState,
): PullRequestSnapshot {
  const byBranch = findPullRequestsForBranch(cwd, ticket.branch);
  const tracked = byBranch.find((pr) => pr.number === ticket.prNumber);
  const matched =
    tracked?.state === 'OPEN'
      ? tracked
      : (byBranch.find((pr) => pr.state === 'OPEN') ?? tracked ?? byBranch[0]);

  if (!matched) {
    throw new Error(
      `Could not find a pull request for ${ticket.id} on branch ${ticket.branch}.`,
    );
  }

  return matched;
}

function deleteRemoteBranch(cwd: string, repo: string, branch: string): void {
  const result = runProcessResult(cwd, [
    'gh',
    'api',
    '-X',
    'DELETE',
    `repos/${repo}/git/refs/heads/${branch}`,
  ]);

  if (result.exitCode === 0) {
    return;
  }

  const message = `${result.stderr}\n${result.stdout}`;
  if (message.includes('Reference does not exist')) {
    return;
  }

  throw new Error(
    `Failed to delete remote branch ${branch}: ${message.trim()}`,
  );
}

export function buildCloseoutBranchSyncCommands(closeoutBranch: string): {
  fetch: string[];
  push: string[];
  resetHard: string[];
} {
  return {
    fetch: ['git', 'fetch', 'origin', closeoutBranch],
    resetHard: ['git', 'reset', '--hard', `origin/${closeoutBranch}`],
    push: ['git', 'push', 'origin', closeoutBranch],
  };
}

export function formatCloseoutBranchGuardError(
  closeoutBranch: string,
  currentBranch: string,
): string {
  return `closeout-stack must run from the ${closeoutBranch} branch, but HEAD is on ${currentBranch}.`;
}

export function buildCloseoutPrCloseComment(
  ticketId: string,
  closeoutBranch: string,
  landedVia: 'squash' | 'cherry-pick',
): string {
  return landedVia === 'cherry-pick'
    ? `Merged to ${closeoutBranch} via closeout-stack (${ticketId}). merge --squash conflicted with the stacked branch; landed this PR using sequential git cherry-pick instead.`
    : `Squash-merged to ${closeoutBranch} via closeout-stack (${ticketId}).`;
}

function fetchOriginCloseoutBranch(cwd: string, closeoutBranch: string): void {
  runProcess(cwd, buildCloseoutBranchSyncCommands(closeoutBranch).fetch);
}

function ensureOnCloseoutBranch(cwd: string, closeoutBranch: string): void {
  const current = runProcess(cwd, ['git', 'rev-parse', '--abbrev-ref', 'HEAD']);
  if (current !== closeoutBranch) {
    throw new Error(formatCloseoutBranchGuardError(closeoutBranch, current));
  }
}

function closePullRequest(
  cwd: string,
  prNumber: number,
  ticketId: string,
  closeoutBranch: string,
  landedVia: 'squash' | 'cherry-pick',
): void {
  const result = runProcessResult(cwd, [
    'gh',
    'pr',
    'close',
    String(prNumber),
    '--comment',
    buildCloseoutPrCloseComment(ticketId, closeoutBranch, landedVia),
  ]);

  if (result.exitCode !== 0) {
    const message = `${result.stderr}\n${result.stdout}`;
    if (
      !message.includes('already closed') &&
      !message.includes('already merged')
    ) {
      throw new Error(`Failed to close PR #${prNumber}: ${message.trim()}`);
    }
  }
}

export function formatCloseoutSummary(
  summary: CloseoutSummary,
  state: DeliveryState,
  config: ResolvedOrchestratorConfig,
  advisoryObservationWarnings: AdvisoryObservationWarning[] = [],
): string {
  const lines = [formatStatus(state, config), '', 'Stacked Closeout Summary'];

  lines.push(`closeout_target=${config.closeoutBranch}`);

  for (const merged of summary.merged) {
    const via =
      merged.landedVia === 'cherry-pick' ? ' [cherry-pick fallback]' : '';
    lines.push(
      `- merged ${merged.ticketId}: PR #${merged.prNumber} (${merged.url})${via}`,
    );
  }

  for (const skipped of summary.skippedMerged) {
    lines.push(
      `- already merged ${skipped.ticketId}: PR #${skipped.prNumber} (${skipped.url})`,
    );
  }

  const warningText = formatAdvisoryObservationWarnings(
    advisoryObservationWarnings,
  );
  if (warningText) {
    lines.push('', warningText);
  }

  return lines.join('\n');
}

export async function runCloseoutStack(
  argv: string[],
  cwd: string,
): Promise<number> {
  try {
    const parsed = parseCloseoutStackArgs(argv);
    const rawConfig = await loadOrchestratorConfig(cwd);
    const config = resolveOrchestratorConfig(rawConfig, cwd);
    closeoutPlatform = createPlatformAdapters(config);
    const options = createOptions({ planPath: parsed.planPath });
    const { state } = await loadState(cwd, options, config);
    const tickets = getCloseoutTicketChain(state);
    const repo = resolveRepoSlug(cwd);
    const summary: CloseoutSummary = {
      merged: [],
      skippedMerged: [],
    };

    ensureCleanWorktree(cwd);
    ensureOnCloseoutBranch(cwd, config.closeoutBranch);

    // Prefetch PR snapshots before any branch mutations so child PRs
    // are still discoverable even after parent branches are deleted.
    const prSnapshots = tickets.map((ticket) =>
      resolvePullRequestForTicket(cwd, ticket),
    );

    for (let index = 0; index < tickets.length; index += 1) {
      const ticket = tickets[index]!;
      const pr = prSnapshots[index]!;

      if (pr.state === 'MERGED') {
        summary.skippedMerged.push({
          prNumber: pr.number,
          ticketId: ticket.id,
          url: pr.url,
        });
        const closeoutCommands = buildCloseoutBranchSyncCommands(
          config.closeoutBranch,
        );
        fetchOriginCloseoutBranch(cwd, config.closeoutBranch);
        runProcess(cwd, closeoutCommands.resetHard);
        continue;
      }

      // Sync local closeout branch with its remote before landing each PR.
      const closeoutCommands = buildCloseoutBranchSyncCommands(
        config.closeoutBranch,
      );
      fetchOriginCloseoutBranch(cwd, config.closeoutBranch);
      runProcess(cwd, closeoutCommands.resetHard);

      // Fetch ticket branch and squash-merge locally (3-way merge, no rebase)
      runProcess(cwd, ['git', 'fetch', 'origin', ticket.branch]);
      const squashResult = runProcessResult(cwd, [
        'git',
        'merge',
        '--squash',
        `origin/${ticket.branch}`,
      ]);

      let landedVia: 'squash' | 'cherry-pick' = 'squash';

      if (squashResult.exitCode !== 0) {
        runProcess(cwd, [
          'git',
          'reset',
          '--hard',
          `origin/${config.closeoutBranch}`,
        ]);

        const oids = listPullRequestCommitOidsAscending(cwd, pr.number);

        if (oids.length === 0) {
          const detail =
            squashResult.stderr || squashResult.stdout || 'no stderr/stdout';
          throw new Error(
            `git merge --squash origin/${ticket.branch} failed and gh pr view #${pr.number} returned no commits to cherry-pick. Squash output:\n${detail.trim()}`,
          );
        }

        for (const oid of oids) {
          cherryPickCommitOntoHead(cwd, oid);
        }

        landedVia = 'cherry-pick';
      } else {
        runProcess(cwd, ['git', 'commit', '-m', pr.title]);
      }

      runProcess(
        cwd,
        buildCloseoutBranchSyncCommands(config.closeoutBranch).push,
      );

      // Close the PR and clean up the remote branch
      closePullRequest(
        cwd,
        pr.number,
        ticket.id,
        config.closeoutBranch,
        landedVia,
      );
      deleteRemoteBranch(cwd, repo, ticket.branch);

      summary.merged.push({
        prNumber: pr.number,
        ticketId: ticket.id,
        url: pr.url,
        landedVia,
      });
    }

    await saveState(cwd, state);
    const advisoryObservationWarnings = await (async () => {
      try {
        return await computeAdvisoryObservationWarnings({
          repoRoot: cwd,
          state,
        });
      } catch (warningError) {
        return [
          {
            kind: 'warning_error' as const,
            message:
              warningError instanceof Error
                ? warningError.message
                : String(warningError),
          },
        ];
      }
    })();
    console.log(
      formatCloseoutSummary(
        summary,
        state,
        config,
        advisoryObservationWarnings,
      ),
    );
    return 0;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return 1;
  }
}
