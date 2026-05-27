import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

import { copyLocalEnvIfPresent } from './platform';

export function parseDotEnv(content: string): Record<string, string> {
  const values: Record<string, string> = {};

  for (const rawLine of content.split('\n')) {
    const line = rawLine.trim();

    if (line.length === 0 || line.startsWith('#')) {
      continue;
    }

    const separatorIndex = line.indexOf('=');

    if (separatorIndex === -1) {
      continue;
    }

    const key = line.slice(0, separatorIndex).trim();
    let value = line.slice(separatorIndex + 1).trim();

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (key.length > 0) {
      values[key] = value;
    }
  }

  return values;
}

export async function ensureEnvReady(
  cwd: string,
  findPrimaryWorktreePath: (cwd: string) => string | undefined,
): Promise<void> {
  await ensureLocalEnvFile(cwd, findPrimaryWorktreePath);
  await loadDotEnvIntoProcess(cwd);
}

async function ensureLocalEnvFile(
  cwd: string,
  findPrimaryWorktreePath: (cwd: string) => string | undefined,
): Promise<void> {
  const localEnvPath = resolve(cwd, '.env');

  if (existsSync(localEnvPath)) {
    return;
  }

  const primaryWorktreePath = findPrimaryWorktreePath(cwd);

  if (!primaryWorktreePath) {
    return;
  }

  await copyLocalEnvIfPresent(primaryWorktreePath, cwd);
}

async function loadDotEnvIntoProcess(cwd: string): Promise<void> {
  const envPath = resolve(cwd, '.env');

  if (!existsSync(envPath)) {
    return;
  }

  const values = parseDotEnv(await readFile(envPath, 'utf8'));

  for (const [key, value] of Object.entries(values)) {
    if (typeof process.env[key] === 'undefined') {
      process.env[key] = value;
    }
  }
}
