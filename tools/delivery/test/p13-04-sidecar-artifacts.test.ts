import { describe, expect, it } from 'bun:test';
import { mkdtempSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import {
  SUBAGENT_REVIEW_OUTCOME_SUFFIX,
  buildRunnerInvocation,
  deriveSubagentReviewOutcomePath,
  isSubagentAdversarialPromptReference,
  isSubagentReviewOutcomePath,
  validateRunnerArtifact,
  writeSubagentReviewOutcome,
} from '../subagent-runner';

describe('P13.04 — subagent review sidecar artifacts', () => {
  it('writeSubagentReviewOutcome persists runner stdout as report prose', () => {
    const repoRoot = mkdtempSync(join(tmpdir(), 'p13-04-outcome-'));
    const reviewsDirPath = 'docs/product/delivery/phase-13/reviews';
    const ticketId = 'P13.04';

    const written = writeSubagentReviewOutcome({
      repoRoot,
      reviewsDirPath,
      ticketId,
      stdout: 'Invariant results\nAll held.',
      stderr: '',
    });

    expect(written.relativePath).toBe(
      deriveSubagentReviewOutcomePath(reviewsDirPath, ticketId),
    );
    expect(written.relativePath.endsWith(SUBAGENT_REVIEW_OUTCOME_SUFFIX)).toBe(
      true,
    );

    const onDisk = readFileSync(written.absolutePath, 'utf-8');
    expect(onDisk).toBe('Invariant results\nAll held.\n');
  });

  it('runner artifact stores path references, not embedded prose', () => {
    const promptPath =
      'docs/product/delivery/phase-13/reviews/P13.04-subagent-review.prompt.md';
    const outcomePath =
      'docs/product/delivery/phase-13/reviews/P13.04-subagent-review.report.md';

    expect(isSubagentAdversarialPromptReference(promptPath)).toBe(true);
    expect(isSubagentReviewOutcomePath(outcomePath)).toBe(true);

    const artifact = {
      ticket: 'P13.04',
      invocations: [
        buildRunnerInvocation('claude-cli', 'abc1234', 'clean', {
          terminatedReason: 'completed',
          filledPrompt: promptPath,
          rawOutput: outcomePath,
        }),
      ],
    };

    expect(validateRunnerArtifact(artifact)).toEqual(artifact);
    expect(artifact.invocations[0]?.filledPrompt).toBe(promptPath);
    expect(artifact.invocations[0]?.rawOutput).toBe(outcomePath);
  });

  it('still accepts legacy inline filledPrompt and rawOutput strings', () => {
    const artifact = {
      ticket: 'P13.legacy',
      invocations: [
        buildRunnerInvocation('codex-cli', 'abc1234', 'clean', {
          terminatedReason: 'completed',
          filledPrompt: 'inline prompt body with enough text',
          rawOutput: 'inline runner prose',
        }),
      ],
    };
    expect(validateRunnerArtifact(artifact)).toEqual(artifact);
  });
});
