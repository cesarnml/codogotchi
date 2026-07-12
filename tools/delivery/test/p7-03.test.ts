import { describe, expect, it } from 'bun:test';

import { parseCliArgs } from '../cli';
import {
  detectRunPolicyDivergence,
  formatRunPolicyDivergenceError,
  patchRunPolicyWithFlags,
} from '../state';
import type { RunPolicy } from '../types';

const DUMMY_USAGE = 'Usage: bun run deliver --plan <plan> <command>';

const basePolicy: RunPolicy = {
  ticketBoundaryMode: 'cook',
  subagentReview: 'skip_doc_only',
  prReview: 'skip_doc_only',
};

// ─── detectRunPolicyDivergence ───────────────────────────────────────────────

describe('P7.03 resume divergence guardrails', () => {
  describe('detectRunPolicyDivergence', () => {
    it('returns empty array when policies are identical', () => {
      expect(detectRunPolicyDivergence(basePolicy, basePolicy)).toEqual([]);
    });

    it('detects ticketBoundaryMode divergence', () => {
      const current: RunPolicy = { ...basePolicy, ticketBoundaryMode: 'gated' };
      expect(detectRunPolicyDivergence(basePolicy, current)).toContain(
        'ticketBoundaryMode',
      );
    });

    it('detects subagentReview divergence', () => {
      const current: RunPolicy = { ...basePolicy, subagentReview: 'required' };
      expect(detectRunPolicyDivergence(basePolicy, current)).toContain(
        'subagentReview',
      );
    });

    it('detects prReview divergence', () => {
      const current: RunPolicy = { ...basePolicy, prReview: 'disabled' };
      expect(detectRunPolicyDivergence(basePolicy, current)).toContain(
        'prReview',
      );
    });

    it('returns multiple fields when multiple diverge', () => {
      const current: RunPolicy = {
        ...basePolicy,
        ticketBoundaryMode: 'gated',
        subagentReview: 'required',
      };
      const fields = detectRunPolicyDivergence(basePolicy, current);
      expect(fields).toContain('ticketBoundaryMode');
      expect(fields).toContain('subagentReview');
      expect(fields).not.toContain('prReview');
    });
  });

  // ─── formatRunPolicyDivergenceError ─────────────────────────────────────────

  describe('formatRunPolicyDivergenceError', () => {
    it('includes diverged field names in the error message', () => {
      const msg = formatRunPolicyDivergenceError(
        basePolicy,
        { ...basePolicy, ticketBoundaryMode: 'gated' },
        ['ticketBoundaryMode'],
        'bun run deliver --plan x.md',
      );
      expect(msg).toContain('ticketBoundaryMode');
    });

    it('includes recovery command with --baseline orchestrator (space-separated, parseable)', () => {
      const msg = formatRunPolicyDivergenceError(
        basePolicy,
        { ...basePolicy, subagentReview: 'required' },
        ['subagentReview'],
        'bun run deliver --plan x.md',
      );
      expect(msg).toContain('--baseline orchestrator');
    });

    it('includes recovery command with --baseline run-policy (space-separated, parseable)', () => {
      const msg = formatRunPolicyDivergenceError(
        basePolicy,
        { ...basePolicy, prReview: 'disabled' },
        ['prReview'],
        'bun run deliver --plan x.md',
      );
      expect(msg).toContain('--baseline run-policy');
    });

    it('includes persisted and current policy values for each diverged field', () => {
      const msg = formatRunPolicyDivergenceError(
        basePolicy,
        { ...basePolicy, ticketBoundaryMode: 'gated' },
        ['ticketBoundaryMode'],
        'bun run deliver --plan x.md',
      );
      // Should show both the old and new values
      expect(msg).toContain('cook');
      expect(msg).toContain('gated');
    });
  });

  // ─── parseCliArgs — --baseline flag ─────────────────────────────────────────

  describe('parseCliArgs — --baseline flag', () => {
    it('parses --baseline orchestrator', () => {
      const result = parseCliArgs(
        ['--plan', 'x.md', 'start', '--baseline', 'orchestrator'],
        DUMMY_USAGE,
      );
      expect(result.baseline).toBe('orchestrator');
    });

    it('parses --baseline run-policy', () => {
      const result = parseCliArgs(
        ['--plan', 'x.md', 'start', '--baseline', 'run-policy'],
        DUMMY_USAGE,
      );
      expect(result.baseline).toBe('run-policy');
    });

    it('throws on invalid --baseline value', () => {
      expect(() =>
        parseCliArgs(
          ['--plan', 'x.md', 'start', '--baseline', 'bogus'],
          DUMMY_USAGE,
        ),
      ).toThrow('--baseline');
    });

    it('leaves baseline undefined when flag is absent', () => {
      const result = parseCliArgs(['--plan', 'x.md', 'status'], DUMMY_USAGE);
      expect(result.baseline).toBeUndefined();
    });
  });

  // ─── parseCliArgs — --red-commit-sha removed in phase-12 ─────────────────────

  describe('parseCliArgs — --red-commit-sha removed', () => {
    it('throws with an explicit error pointing to the two honest paths', () => {
      expect(() =>
        parseCliArgs(
          ['--plan', 'x.md', 'post-red', '--red-commit-sha', 'abc1234def'],
          DUMMY_USAGE,
        ),
      ).toThrow(/--red-commit-sha has been removed/);
    });

    it('error names the two honest paths so the operator knows what to do next', () => {
      try {
        parseCliArgs(
          ['--plan', 'x.md', 'post-red', '--red-commit-sha', 'abc'],
          DUMMY_USAGE,
        );
        throw new Error('expected throw');
      } catch (error) {
        const message = (error as Error).message;
        expect(message).toContain('[red]');
        expect(message).toContain('Red: skip');
      }
    });
  });

  // ─── patchRunPolicyWithFlags ─────────────────────────────────────────────────

  describe('patchRunPolicyWithFlags', () => {
    it('returns base policy unchanged when no flags provided', () => {
      const patched = patchRunPolicyWithFlags(basePolicy, {});
      expect(patched).toEqual(basePolicy);
    });

    it('patches ticketBoundaryMode from --boundary-mode', () => {
      const patched = patchRunPolicyWithFlags(basePolicy, {
        boundaryMode: 'gated',
      });
      expect(patched.ticketBoundaryMode).toBe('gated');
    });

    it('patches subagentReview from --subagent-review-policy', () => {
      const patched = patchRunPolicyWithFlags(basePolicy, {
        subagentReviewPolicy: 'required',
      });
      expect(patched.subagentReview).toBe('required');
    });

    it('patches prReview from --pr-review-policy', () => {
      const patched = patchRunPolicyWithFlags(basePolicy, {
        prReviewPolicy: 'disabled',
      });
      expect(patched.prReview).toBe('disabled');
    });
  });

  // ─── formatRunPolicyDivergenceError — edge cases ─────────────────────────────

  describe('formatRunPolicyDivergenceError — edge cases', () => {
    it('produces header and recovery lines even when divergedFields is empty', () => {
      const msg = formatRunPolicyDivergenceError(
        basePolicy,
        basePolicy,
        [],
        'bun run deliver --plan x.md post-verify',
      );
      expect(msg).toContain('--baseline orchestrator');
      expect(msg).toContain('--baseline run-policy');
    });

    it('recovery guidance includes the run-deliver invocation', () => {
      const msg = formatRunPolicyDivergenceError(
        basePolicy,
        { ...basePolicy, prReview: 'required' },
        ['prReview'],
        'bun run deliver --plan docs/x.md post-verify',
      );
      expect(msg).toContain('bun run deliver --plan docs/x.md post-verify');
    });
  });
});
