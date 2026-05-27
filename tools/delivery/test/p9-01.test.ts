import { describe, expect, it } from 'bun:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const TRIAGER_PATH = resolve(
  import.meta.dir,
  '../../../.agents/skills/pr-review/scripts/triage_pr_review.sh',
);

function runTriager(artifactPath: string): ReturnType<typeof spawnSync> {
  return spawnSync('bash', [TRIAGER_PATH, artifactPath], { encoding: 'utf8' });
}

describe('P9.01 billing noise filter', () => {
  it('treats Qodo billing-limit comments as clean vendor noise', () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'p9-01-'));
    const artifactPath = join(tempDir, 'billing-noise.fetch.json');

    try {
      writeFileSync(
        artifactPath,
        JSON.stringify({
          vendors: ['qodo'],
          comments: [
            {
              kind: 'unknown',
              authorLogin: 'qodo-code-review',
              body: "You've reached your Qodo monthly free-tier limit",
            },
          ],
        }),
      );

      const result = runTriager(artifactPath);

      expect(result.status).toBe(0);
      expect(JSON.parse(result.stdout)).toMatchObject({
        outcome: 'clean',
        vendor_status_count: 1,
      });
    } finally {
      rmSync(tempDir, { force: true, recursive: true });
    }
  });

  it('keeps coderabbit comments with fenced code blocks actionable', () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'p9-01-codeblock-'));
    const artifactPath = join(tempDir, 'coderabbit-finding.fetch.json');

    try {
      writeFileSync(
        artifactPath,
        JSON.stringify({
          vendors: ['coderabbit'],
          comments: [
            {
              kind: 'unknown',
              authorLogin: 'coderabbitai',
              body: "You're out of credits.\n```diff\n- old\n+ new\n```",
            },
          ],
        }),
      );

      const result = runTriager(artifactPath);

      expect(result.status).toBe(0);
      expect(JSON.parse(result.stdout)).toMatchObject({
        outcome: 'needs_patch',
        vendor_status_count: 0,
      });
    } finally {
      rmSync(tempDir, { force: true, recursive: true });
    }
  });

  it('treats Greptile free-trial notices as clean vendor noise', () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'p9-01-greptile-'));
    const artifactPath = join(tempDir, 'greptile-noise.fetch.json');

    try {
      writeFileSync(
        artifactPath,
        JSON.stringify({
          vendors: ['greptile'],
          comments: [
            {
              kind: 'unknown',
              authorLogin: 'greptile-apps',
              body: 'Your free trial has ended. Add a payment method to continue reviews.',
            },
          ],
        }),
      );

      const result = runTriager(artifactPath);

      expect(result.status).toBe(0);
      expect(JSON.parse(result.stdout)).toMatchObject({
        outcome: 'clean',
        vendor_status_count: 1,
      });
    } finally {
      rmSync(tempDir, { force: true, recursive: true });
    }
  });
});
