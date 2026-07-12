import { describe, expect, it } from 'bun:test';

import {
  deriveBranchName,
  deriveWorktreePath,
  findExistingBranch,
} from '../planning';

describe('planning', () => {
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
