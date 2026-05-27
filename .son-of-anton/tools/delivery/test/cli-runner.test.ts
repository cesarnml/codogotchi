import { describe, expect, it } from 'bun:test';

import { getUsage, parseCliArgs } from '../cli';

const USAGE = getUsage('bun run deliver');

describe('P14.02 — --subagent flag (strict enum)', () => {
  it('parses --subagent claude-cli', () => {
    const parsed = parseCliArgs(
      ['--plan', 'plan.md', 'subagent-review', '--subagent', 'claude-cli'],
      USAGE,
    );
    expect(parsed.subagent).toBe('claude-cli');
  });

  it('parses --subagent codex-cli', () => {
    const parsed = parseCliArgs(
      ['--plan', 'plan.md', 'subagent-review', '--subagent', 'codex-cli'],
      USAGE,
    );
    expect(parsed.subagent).toBe('codex-cli');
  });

  it('parses --subagent cursor-cli', () => {
    const parsed = parseCliArgs(
      ['--plan', 'plan.md', 'subagent-review', '--subagent', 'cursor-cli'],
      USAGE,
    );
    expect(parsed.subagent).toBe('cursor-cli');
  });

  it('rejects invalid --subagent value', () => {
    expect(() =>
      parseCliArgs(
        ['--plan', 'plan.md', 'subagent-review', '--subagent', 'gemini-cli'],
        USAGE,
      ),
    ).toThrow(/--subagent/);
  });

  it('rejects missing --subagent value', () => {
    expect(() =>
      parseCliArgs(
        ['--plan', 'plan.md', 'subagent-review', '--subagent'],
        USAGE,
      ),
    ).toThrow(/--subagent/);
  });

  it('leaves subagent undefined when flag is absent', () => {
    const parsed = parseCliArgs(
      ['--plan', 'plan.md', 'subagent-review'],
      USAGE,
    );
    expect(parsed.subagent).toBeUndefined();
  });
});

describe('P14.02 — --primary flag (free-form)', () => {
  it('parses --primary with a known value', () => {
    const parsed = parseCliArgs(
      ['--plan', 'plan.md', 'subagent-review', '--primary', 'claude'],
      USAGE,
    );
    expect(parsed.primary).toBe('claude');
  });

  it('accepts free-form values without enum validation', () => {
    for (const value of ['cursor', 'composer', 'copilot', 'aider']) {
      const parsed = parseCliArgs(
        ['--plan', 'plan.md', 'subagent-review', '--primary', value],
        USAGE,
      );
      expect(parsed.primary).toBe(value);
    }
  });

  it('rejects missing --primary value', () => {
    expect(() =>
      parseCliArgs(
        ['--plan', 'plan.md', 'subagent-review', '--primary'],
        USAGE,
      ),
    ).toThrow(/--primary/);
  });

  it('leaves primary undefined when flag is absent', () => {
    const parsed = parseCliArgs(
      ['--plan', 'plan.md', 'subagent-review'],
      USAGE,
    );
    expect(parsed.primary).toBeUndefined();
  });
});

describe('P14.02 — --preferred-runner is removed', () => {
  it('throws when --preferred-runner is passed', () => {
    expect(() =>
      parseCliArgs(
        [
          '--plan',
          'plan.md',
          'subagent-review',
          '--preferred-runner',
          'claude-cli',
        ],
        USAGE,
      ),
    ).toThrow(/preferred-runner|--subagent/);
  });

  it('USAGE text no longer documents --preferred-runner', () => {
    expect(USAGE).not.toContain('--preferred-runner');
  });

  it('USAGE text documents --subagent and --primary', () => {
    expect(USAGE).toContain('--subagent');
    expect(USAGE).toContain('--primary');
  });
});
