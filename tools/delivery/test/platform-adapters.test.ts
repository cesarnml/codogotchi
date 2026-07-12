import { describe, expect, it } from 'bun:test';

import {
  createPlatformAdapters,
  parsePullRequestNumber,
} from '../platform-adapters';
import { hasLocalBranchCommits } from '../platform';
import type { ResolvedOrchestratorConfig } from '../runtime-config';

const baseConfig: ResolvedOrchestratorConfig = {
  defaultBranch: 'main',
  planRoot: 'docs',
  runtime: 'bun',
  packageManager: 'bun',
  ticketBoundaryMode: 'cook',
  reviewPolicy: {
    subagentReview: 'skip_doc_only',
    prReview: 'disabled',
  },
};

describe('platform adapters', () => {
  it('creates a factory-backed adapter surface', () => {
    const adapters = createPlatformAdapters(baseConfig);

    expect(adapters.createPullRequest).toBeFunction();
    expect(adapters.runProcessResult).toBeFunction();
    expect(adapters.bootstrapWorktreeIfNeeded).toBeFunction();
  });

  it('exposes hasLocalBranchCommits on the adapter surface', () => {
    const adapters = createPlatformAdapters(baseConfig);
    expect(adapters.hasLocalBranchCommits).toBeFunction();
  });

  it('keeps PR number parsing inside the adapter boundary', () => {
    expect(
      parsePullRequestNumber('https://github.com/example/repo/pull/245'),
    ).toBe(245);
    expect(() =>
      parsePullRequestNumber('https://github.com/example/repo/issues/245'),
    ).toThrow(/Could not parse PR number/);
  });
});

describe('hasLocalBranchCommits (P3.01)', () => {
  it('is exported from platform', () => {
    expect(typeof hasLocalBranchCommits).toBe('function');
  });

  it('returns true when git diff returns non-empty output', () => {
    let seenCommand: string[] | undefined;
    const mockRunProcess = (_cwd: string, cmd: string[]) => {
      seenCommand = cmd;
      return '2\n';
    };
    expect(
      hasLocalBranchCommits('ignored', 'main', 'bun', mockRunProcess),
    ).toBe(true);
    expect(seenCommand).toEqual([
      'git',
      'rev-list',
      '--count',
      'origin/main..HEAD',
    ]);
  });

  it('returns false when git rev-list count is zero', () => {
    const mockRunProcess = (_cwd: string, _cmd: string[]) => '0\n';
    expect(
      hasLocalBranchCommits('ignored', 'main', 'bun', mockRunProcess),
    ).toBe(false);
  });

  it('returns false on git errors', () => {
    const mockRunProcess = (_cwd: string, _cmd: string[]): string => {
      throw new Error('git: not a git repository');
    };
    expect(
      hasLocalBranchCommits('ignored', 'main', 'bun', mockRunProcess),
    ).toBe(false);
  });
});
