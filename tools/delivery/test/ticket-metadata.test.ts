import { describe, expect, it } from 'bun:test';

import { parseRedPolicy } from '../ticket-metadata';

const baseMetadata = (redLine: string | undefined): string => {
  const lines = [
    '# P12.XX Example ticket',
    '',
    'Size: 1 points',
    'Type: feat',
    'Scope: delivery',
  ];

  if (redLine !== undefined) {
    lines.push(redLine);
  }

  lines.push('', '## Outcome', '', '- example', '');
  return lines.join('\n');
};

describe('parseRedPolicy', () => {
  it('returns "skip" for a ticket declaring Red: skip', () => {
    expect(parseRedPolicy(baseMetadata('Red: skip'))).toBe('skip');
  });

  it('returns "required" for a ticket declaring Red: required', () => {
    expect(parseRedPolicy(baseMetadata('Red: required'))).toBe('required');
  });

  it('defaults to "required" when the Red field is missing entirely', () => {
    expect(parseRedPolicy(baseMetadata(undefined))).toBe('required');
  });

  it('rejects case variants of the valid values', () => {
    expect(() => parseRedPolicy(baseMetadata('Red: Required'))).toThrow(
      /expected literal `required` or `skip`/,
    );
    expect(() => parseRedPolicy(baseMetadata('Red: SKIP'))).toThrow(
      /expected literal `required` or `skip`/,
    );
  });

  it('rejects unrecognized values', () => {
    expect(() => parseRedPolicy(baseMetadata('Red: maybe'))).toThrow(
      /expected literal `required` or `skip`/,
    );
    expect(() => parseRedPolicy(baseMetadata('Red: 1'))).toThrow(
      /expected literal `required` or `skip`/,
    );
  });

  it('rejects an empty value', () => {
    expect(() => parseRedPolicy(baseMetadata('Red:'))).toThrow(
      /expected literal `required` or `skip`/,
    );
    expect(() => parseRedPolicy(baseMetadata('Red:   '))).toThrow(
      /expected literal `required` or `skip`/,
    );
  });

  it('rejects values followed by extra tokens on the same line', () => {
    expect(() =>
      parseRedPolicy(baseMetadata('Red: skip and also required')),
    ).toThrow(/expected literal `required` or `skip`/);
  });

  it('error message echoes the offending value so the operator knows what to fix', () => {
    expect(() => parseRedPolicy(baseMetadata('Red: Required'))).toThrow(
      /Red: Required/,
    );
  });
});
