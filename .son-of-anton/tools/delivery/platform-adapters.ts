import {
  addWorktree as addPlatformWorktree,
  bootstrapWorktreeIfNeeded as bootstrapPlatformWorktreeIfNeeded,
  createPullRequest as createPlatformPullRequest,
  editPullRequest as editPlatformPullRequest,
  ensureBranchPushed as ensurePlatformBranchPushed,
  ensureCleanWorktree as ensurePlatformCleanWorktree,
  fetchOrigin as fetchPlatformOrigin,
  findOpenPullRequest as findPlatformOpenPullRequest,
  hasMergedPullRequestForBranch as hasPlatformMergedPullRequestForBranch,
  hasLocalBranchCommits as hasPlatformLocalBranchCommits,
  hasUncommittedChanges as hasPlatformUncommittedChanges,
  getWorkingTreeStatus as getPlatformWorkingTreeStatus,
  listCommitSubjectsBetween as listPlatformCommitSubjectsBetween,
  readCommitSubject as readPlatformCommitSubject,
  readCurrentBranch as readPlatformCurrentBranch,
  readHeadSha as readPlatformHeadSha,
  readLatestCommitSubject as readPlatformLatestCommitSubject,
  readMergeBase as readPlatformMergeBase,
  rebaseOnto as rebasePlatformOnto,
  rebaseOntoDefaultBranch as rebasePlatformOntoDefaultBranch,
  replyToReviewComment as replyPlatformToReviewComment,
  resolveGitHubRepo as resolvePlatformGitHubRepo,
  resolveReviewThread as resolvePlatformReviewThread,
  resolveStandalonePullRequest as resolvePlatformStandalonePullRequest,
  runProcess as runPlatformProcess,
  runProcessResult as runPlatformProcessResult,
  type PullRequestSummary,
} from './platform';
import {
  updatePullRequestBody as updatePrMetadataPullRequestBody,
  updateStandalonePullRequestBody as updateStandalonePrMetadataPullRequestBody,
} from './pr-metadata';
import type { ResolvedOrchestratorConfig } from './runtime-config';
import type {
  DeliveryState,
  StandaloneAiReviewResult,
  StandalonePullRequest,
  TicketState,
} from './types';

export type CreatePullRequestResult = {
  number: number;
  url: string;
};

export type PlatformAdapters = {
  addWorktree: (
    cwd: string,
    worktreePath: string,
    branch: string,
    baseBranch: string,
  ) => void;
  bootstrapWorktreeIfNeeded: (worktreePath: string) => Promise<void>;
  createPullRequest: (
    cwd: string,
    options: {
      base: string;
      body: string;
      head: string;
      title: string;
    },
  ) => CreatePullRequestResult;
  editPullRequest: (
    cwd: string,
    prNumber: number,
    options: {
      base?: string;
      body?: string;
      title?: string;
    },
  ) => void;
  ensureBranchPushed: (cwd: string, branch: string) => void;
  ensureCleanWorktree: (cwd: string) => void;
  fetchOrigin: (cwd: string) => void;
  findOpenPullRequest: (
    cwd: string,
    branch: string,
  ) => PullRequestSummary | undefined;
  hasMergedPullRequestForBranch: (cwd: string, branch: string) => boolean;
  hasLocalBranchCommits: (cwd: string, baseBranch: string) => boolean;
  hasUncommittedChanges: (cwd: string) => boolean;
  getWorkingTreeStatus: (cwd: string) => string;
  listCommitSubjectsBetween: (
    cwd: string,
    reviewedHeadSha: string,
    currentHeadSha: string,
    maxCount: number,
  ) => string[];
  readCommitSubject: (cwd: string, sha: string) => string;
  readCurrentBranch: (cwd: string) => string;
  readHeadSha: (cwd: string) => string;
  readLatestCommitSubject: (cwd: string) => string;
  readMergeBase: (
    cwd: string,
    branch: string,
    previousBranch: string,
  ) => string;
  rebaseOnto: (cwd: string, rebaseTarget: string, oldBase: string) => void;
  rebaseOntoDefaultBranch: (cwd: string, defaultBranch: string) => void;
  replyToReviewThreadForOrchestrator: (
    worktreePath: string,
    databaseId: number,
    body: string,
  ) => void;
  resolveGitHubRepoForOrchestrator: (
    cwd: string,
  ) => { defaultBranch: string; name: string; owner: string } | undefined;
  resolveReviewThread: (worktreePath: string, threadId: string) => string;
  resolveStandalonePullRequest: (
    cwd: string,
    prNumber?: number,
  ) => StandalonePullRequest;
  runProcess: (cwd: string, cmd: string[]) => string;
  runProcessResult: (
    cwd: string,
    cmd: string[],
  ) => {
    exitCode: number;
    stderr: string;
    stdout: string;
  };
  updatePullRequestBody: (state: DeliveryState, ticket: TicketState) => void;
  updateStandalonePullRequestBody: (
    cwd: string,
    pullRequest: StandalonePullRequest,
    result: StandaloneAiReviewResult,
  ) => void;
};

export function parsePullRequestNumber(prUrl: string): number {
  const match = prUrl.match(/\/pull\/(\d+)$/);

  if (!match?.[1]) {
    throw new Error(`Could not parse PR number from ${prUrl}.`);
  }

  return Number(match[1]);
}

export function createPlatformAdapters(
  config: ResolvedOrchestratorConfig,
): PlatformAdapters {
  const repoCacheByWorktree = new Map<
    string,
    ReturnType<typeof resolvePlatformGitHubRepo>
  >();

  const adapters: PlatformAdapters = {
    addWorktree(cwd, worktreePath, branch, baseBranch) {
      addPlatformWorktree(
        cwd,
        worktreePath,
        branch,
        baseBranch,
        config.runtime,
      );
    },
    async bootstrapWorktreeIfNeeded(worktreePath) {
      await bootstrapPlatformWorktreeIfNeeded(
        worktreePath,
        config.packageManager,
        config.runtime,
      );
    },
    createPullRequest(cwd, options) {
      const url = createPlatformPullRequest(cwd, options, config.runtime);
      return {
        number: parsePullRequestNumber(url),
        url,
      };
    },
    editPullRequest(cwd, prNumber, options) {
      editPlatformPullRequest(cwd, prNumber, options, config.runtime);
    },
    ensureBranchPushed(cwd, branch) {
      ensurePlatformBranchPushed(cwd, branch, config.runtime);
    },
    ensureCleanWorktree(cwd) {
      ensurePlatformCleanWorktree(cwd, config.runtime);
    },
    fetchOrigin(cwd) {
      fetchPlatformOrigin(cwd, config.runtime);
    },
    findOpenPullRequest(cwd, branch) {
      return findPlatformOpenPullRequest(cwd, branch, config.runtime);
    },
    hasMergedPullRequestForBranch(cwd, branch) {
      return hasPlatformMergedPullRequestForBranch(cwd, branch, config.runtime);
    },
    hasLocalBranchCommits(cwd, baseBranch) {
      return hasPlatformLocalBranchCommits(cwd, baseBranch, config.runtime);
    },
    hasUncommittedChanges(cwd) {
      return hasPlatformUncommittedChanges(cwd, config.runtime);
    },
    getWorkingTreeStatus(cwd) {
      return getPlatformWorkingTreeStatus(cwd, config.runtime);
    },
    listCommitSubjectsBetween(cwd, reviewedHeadSha, currentHeadSha, maxCount) {
      return listPlatformCommitSubjectsBetween(
        cwd,
        reviewedHeadSha,
        currentHeadSha,
        maxCount,
        config.runtime,
      );
    },
    readCommitSubject(cwd, sha) {
      return readPlatformCommitSubject(cwd, sha, config.runtime);
    },
    readCurrentBranch(cwd) {
      return readPlatformCurrentBranch(cwd, config.runtime);
    },
    readHeadSha(cwd) {
      return readPlatformHeadSha(cwd, config.runtime);
    },
    readLatestCommitSubject(cwd) {
      return readPlatformLatestCommitSubject(cwd, config.runtime);
    },
    readMergeBase(cwd, branch, previousBranch) {
      return readPlatformMergeBase(cwd, branch, previousBranch, config.runtime);
    },
    rebaseOnto(cwd, rebaseTarget, oldBase) {
      rebasePlatformOnto(cwd, rebaseTarget, oldBase, config.runtime);
    },
    rebaseOntoDefaultBranch(cwd, defaultBranch) {
      rebasePlatformOntoDefaultBranch(cwd, defaultBranch, config.runtime);
    },
    resolveGitHubRepoForOrchestrator(cwd) {
      return resolvePlatformGitHubRepo(cwd, config.runtime);
    },
    replyToReviewThreadForOrchestrator(worktreePath, databaseId, body) {
      const cached = repoCacheByWorktree.get(worktreePath);
      const repo =
        cached ?? resolvePlatformGitHubRepo(worktreePath, config.runtime);
      if (!repo) {
        return;
      }
      if (!cached) {
        repoCacheByWorktree.set(worktreePath, repo);
      }

      try {
        replyPlatformToReviewComment(
          worktreePath,
          repo.owner,
          repo.name,
          databaseId,
          body,
          config.runtime,
        );
      } catch {
        // Best-effort; thread resolution still proceeds.
      }
    },
    resolveReviewThread(worktreePath, threadId) {
      return resolvePlatformReviewThread(
        worktreePath,
        threadId,
        config.runtime,
      );
    },
    resolveStandalonePullRequest(cwd, prNumber) {
      return resolvePlatformStandalonePullRequest(
        cwd,
        config.runtime,
        prNumber,
      );
    },
    runProcess(cwd, cmd) {
      return runPlatformProcess(cwd, cmd, config.runtime);
    },
    runProcessResult(cwd, cmd) {
      return runPlatformProcessResult(cwd, cmd, config.runtime);
    },
    updatePullRequestBody(state, ticket) {
      return updatePrMetadataPullRequestBody(state, ticket, {
        editPullRequest: adapters.editPullRequest,
        listCommitSubjectsBetween: adapters.listCommitSubjectsBetween,
        readHeadSha: adapters.readHeadSha,
        resolveGitHubRepo: adapters.resolveGitHubRepoForOrchestrator,
      });
    },
    updateStandalonePullRequestBody(cwd, pullRequest, result) {
      return updateStandalonePrMetadataPullRequestBody(
        cwd,
        pullRequest,
        result,
        {
          editPullRequest: adapters.editPullRequest,
          listCommitSubjectsBetween: adapters.listCommitSubjectsBetween,
          resolveGitHubRepo: adapters.resolveGitHubRepoForOrchestrator,
        },
      );
    },
  };

  return adapters;
}
