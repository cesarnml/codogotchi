import { describe, expect, it } from 'bun:test';

import {
  deriveBranchName,
  deriveWorktreePath,
  findExistingBranch,
  parseOriginIssueNumbers,
} from '../planning';

describe('planning', () => {
  it('parses a single origin issue number from the Epic section (back-compat)', () => {
    expect(
      parseOriginIssueNumbers(
        '## Epic\n\nOrigin issue: #76\n\n## Product contract\n',
      ),
    ).toEqual([76]);
  });

  it('returns an empty list when no origin issue line is present', () => {
    expect(
      parseOriginIssueNumbers('## Epic\n\nNo issue referenced here.\n'),
    ).toEqual([]);
  });

  it('returns an empty list when the markdown has no ## Epic section — stays Epic-scoped, no whole-document fallback', () => {
    expect(
      parseOriginIssueNumbers(
        '# Some Plan\n\nOrigin issue: #99\n\n## Product contract\n',
      ),
    ).toEqual([]);
  });

  it('parses five Origin issue lines in document order', () => {
    expect(
      parseOriginIssueNumbers(
        '## Epic\n\nOrigin issue: #78\nOrigin issue: #83\nOrigin issue: #84\nOrigin issue: #87\nOrigin issue: #105\n\n## Product contract\n',
      ),
    ).toEqual([78, 83, 84, 87, 105]);
  });

  it('dedupes duplicate issue numbers', () => {
    expect(
      parseOriginIssueNumbers(
        '## Epic\n\nOrigin issue: #78\nOrigin issue: #83\nOrigin issue: #78\n\n## Product contract\n',
      ),
    ).toEqual([78, 83]);
  });

  it('does not truncate the Epic section at a heading-like line inside a fenced code block', () => {
    expect(
      parseOriginIssueNumbers(
        '## Epic\n\nOrigin issue: #78\n\n```\n## fake heading inside a fence\n```\n\nOrigin issue: #83\n\n## Product contract\n',
      ),
    ).toEqual([78, 83]);
  });

  it('rejects near-miss formats — strictness is preserved', () => {
    expect(
      parseOriginIssueNumbers(
        '## Epic\n\nOrigin Issue #76\n\n## Product contract\n',
      ),
    ).toEqual([]);
    expect(
      parseOriginIssueNumbers(
        '## Epic\n\norigin issue: 76\n\n## Product contract\n',
      ),
    ).toEqual([]);
    expect(
      parseOriginIssueNumbers(
        '## Epic\n\nOrigin issue: #76. Design stance pre-agreed elsewhere.\n\n## Product contract\n',
      ),
    ).toEqual([]);
    expect(
      parseOriginIssueNumbers(
        '## Epic\n\nOrigin issue: #76,\n\n## Product contract\n',
      ),
    ).toEqual([]);
  });

  it('derives deterministic branch and worktree names', () => {
    expect(
      deriveBranchName({
        id: 'P2.03',
        slug: 'readme-and-real-world-config-example',
      }),
    ).toBe('agents/p2-03-readme-and-real-world-config-example');
    expect(deriveWorktreePath('/tmp/test_project', 'P2.03')).toBe(
      '/tmp/test_project_p2_03',
    );
    expect(deriveWorktreePath('/tmp/test_project_ee10_04', 'EE10.05')).toBe(
      '/tmp/test_project_ee10_05',
    );
    expect(deriveWorktreePath('/tmp/test_project_p2_03', 'P2.04')).toBe(
      '/tmp/test_project_p2_04',
    );
  });

  it('prefers existing ticket-id branch matches over title-derived names', () => {
    expect(
      findExistingBranch(
        [
          'agents/p2-02-movie-matcher-missing-codec',
          'agents/p2-03-readme-config-live-verification',
          'agents/p2-04-rename-cli-config',
        ],
        {
          id: 'P2.02',
          slug: 'movie-matcher-allows-missing-codec',
        },
      ),
    ).toEqual({
      branch: 'agents/p2-02-movie-matcher-missing-codec',
      source: 'ticket-id',
    });
  });
});
