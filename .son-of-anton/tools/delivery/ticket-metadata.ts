export type RedPolicy = 'required' | 'skip';

const VALID_RED_POLICIES = new Set<RedPolicy>(['required', 'skip']);

export function parseRedPolicy(content: string): RedPolicy {
  const match = content.match(/^Red:\s*(.+)$/im);

  if (!match) {
    return 'required';
  }

  const captured = match[1] ?? '';
  const trimmed = captured.trim();

  if ((VALID_RED_POLICIES as Set<string>).has(trimmed)) {
    return trimmed as RedPolicy;
  }

  throw new Error(
    `Ticket metadata declares \`Red: ${captured}\` — expected literal \`required\` or \`skip\` (lowercase).`,
  );
}
