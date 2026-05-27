import { describe, expect, it } from 'bun:test';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { relativeToRepo } from '../planning';
import { runProcess } from '../platform';
import { recordTicketReview } from '../review';
import type { DeliveryState } from '../types';

const runtime = 'bun' as const;

function git(repo: string, args: string[]) {
  execFileSync('git', args, { cwd: repo, stdio: 'pipe' });
}

describe('record-review artifact commit', () => {
  it('commits and pushes updated PR review JSON after record-review when in a git checkout', async () => {
    const repoRoot = await mkdtemp(join(tmpdir(), 'record-review-commit-'));
    const reviewsDir = join(
      repoRoot,
      'docs/product/delivery/phase-99-commit-test/reviews',
    );
    const fetchPath = join(reviewsDir, 'P99.01-pr-review.fetch.json');
    const triagePath = join(reviewsDir, 'P99.01-pr-review.triage.json');

    try {
      await mkdir(reviewsDir, { recursive: true });
      await writeFile(join(repoRoot, 'README.md'), '# fixture\n', 'utf8');

      const fetchBody = {
        schemaVersion: 1,
        fetchedAt: '2026-05-14T00:00:00.000Z',
        reviewedHeadSha: 'abc123',
        detected: true,
        vendors: ['coderabbit'],
        agents: [],
        comments: [
          {
            vendor: 'coderabbit',
            channel: 'inline_review',
            authorLogin: 'coderabbitai',
            authorType: 'Bot',
            body: 'Fix the bug.',
            kind: 'finding',
            threadId: 'thread_1',
            url: 'https://example.test/comment/1',
          },
        ],
      };
      const triageBody = {
        schemaVersion: 1,
        recordedAt: '2026-05-14T00:00:00.000Z',
        reviewedHeadSha: 'abc123',
        outcome: 'needs_patch',
        note: 'Findings pending.',
      };

      await writeFile(fetchPath, `${JSON.stringify(fetchBody)}\n`, 'utf8');
      await writeFile(triagePath, `${JSON.stringify(triageBody)}\n`, 'utf8');

      git(repoRoot, ['init', '-b', 'main']);
      git(repoRoot, ['config', 'user.email', 'delivery-test@example.test']);
      git(repoRoot, ['config', 'user.name', 'delivery-test']);
      git(repoRoot, ['add', 'README.md', fetchPath, triagePath]);
      git(repoRoot, ['commit', '-m', 'init']);

      const state: DeliveryState = {
        planKey: 'phase-99-commit-test',
        planPath:
          'docs/product/delivery/phase-99-commit-test/implementation-plan.md',
        statePath: '.agents/delivery/phase-99-commit-test/state.json',
        reviewsDirPath: 'docs/product/delivery/phase-99-commit-test/reviews',
        handoffsDirPath: '.agents/delivery/phase-99-commit-test/handoffs',
        reviewPollIntervalMinutes: 6,
        reviewPollMaxWaitMinutes: 12,
        tickets: [
          {
            id: 'P99.01',
            title: 'Record review commit fixture',
            slug: 'record-review-commit-fixture',
            ticketFile:
              'docs/product/delivery/phase-99-commit-test/ticket-01-fixture.md',
            status: 'needs_patch',
            branch: 'agents/p99-01-record-review-commit-fixture',
            baseBranch: 'main',
            worktreePath: repoRoot,
            reviewFetchArtifactPath:
              'docs/product/delivery/phase-99-commit-test/reviews/P99.01-pr-review.fetch.json',
            reviewTriageArtifactPath:
              'docs/product/delivery/phase-99-commit-test/reviews/P99.01-pr-review.triage.json',
            reviewHeadSha: 'abc123',
            reviewNote: 'Findings pending.',
          },
        ],
      };
      const pushedBranches: Array<{ branch: string; cwd: string }> = [];

      await recordTicketReview(
        state,
        repoRoot,
        'P99.01',
        'patched',
        undefined,
        {
          relativeToRepo,
          runProcess: (cwd, cmd) => runProcess(cwd, cmd, runtime),
          resolveReviewFetcher: () => 'fetcher',
          resolveReviewThread: () => '{"resolved":true}',
          resolveReviewTriager: () => 'triager',
          resolveThreads: () => [
            {
              status: 'resolved',
              threadId: 'thread_1',
              url: 'https://example.test/comment/1',
              vendor: 'coderabbit',
            },
          ],
          ensureBranchPushed: (cwd, branch) => {
            pushedBranches.push({ branch, cwd });
          },
          updatePullRequestBody: async () => {},
        },
      );

      const status = runProcess(repoRoot, ['git', 'status', '--porcelain']);
      expect(status.trim()).toBe('');

      const lastSubject = runProcess(repoRoot, [
        'git',
        'log',
        '-1',
        '--pretty=%s',
      ]);
      expect(lastSubject.trim()).toContain('record-review P99.01');
      expect(lastSubject.trim()).toContain('PR review artifacts');
      expect(pushedBranches).toEqual([
        {
          branch: 'agents/p99-01-record-review-commit-fixture',
          cwd: repoRoot,
        },
      ]);

      const triage = JSON.parse(await readFile(triagePath, 'utf8')) as {
        outcome: string;
      };
      expect(triage.outcome).toBe('patched');
    } finally {
      await rm(repoRoot, { recursive: true, force: true });
    }
  });
});
