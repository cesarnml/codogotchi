export const XP_PER_CLAUDE_TOKEN = 1;
export const XP_PER_CODEX_TOKEN = 1;
export const XP_PER_GITHUB_PR = 10_000;
export const XP_PER_WAKATIME_HOUR = 5_000;

export const STAGE_THRESHOLDS = [
  0, 10_000, 150_000, 1_500_000, 15_000_000,
] as const;

export type Stage = 1 | 2 | 3 | 4 | 5;

export type RawSignals = {
  claudeTokens: number;
  codexTokens: number;
  githubPRs: number;
  wakatimeHours: number;
};

export type XpTotals = {
  byClaude: number;
  byCodex: number;
  byGithub: number;
  byWakatime: number;
  total: number;
};

function nonNegative(n: number): number {
  return n > 0 ? n : 0;
}

export function xpFromClaudeTokens(tokens: number): number {
  return Math.floor(nonNegative(tokens) * XP_PER_CLAUDE_TOKEN);
}

export function xpFromCodexTokens(tokens: number): number {
  return Math.floor(nonNegative(tokens) * XP_PER_CODEX_TOKEN);
}

export function xpFromGithubPRs(prs: number): number {
  return Math.floor(nonNegative(prs)) * XP_PER_GITHUB_PR;
}

export function xpFromWakatimeHours(hours: number): number {
  return Math.floor(nonNegative(hours) * XP_PER_WAKATIME_HOUR);
}

export function computeXp(signals: RawSignals): XpTotals {
  const byClaude = xpFromClaudeTokens(signals.claudeTokens);
  const byCodex = xpFromCodexTokens(signals.codexTokens);
  const byGithub = xpFromGithubPRs(signals.githubPRs);
  const byWakatime = xpFromWakatimeHours(signals.wakatimeHours);
  return {
    byClaude,
    byCodex,
    byGithub,
    byWakatime,
    total: byClaude + byCodex + byGithub + byWakatime,
  };
}

export function stageForXp(totalXp: number): Stage {
  let stage: Stage = 1;
  for (let i = 1; i < STAGE_THRESHOLDS.length; i++) {
    const threshold = STAGE_THRESHOLDS[i];
    if (threshold !== undefined && totalXp >= threshold) {
      stage = (i + 1) as Stage;
    }
  }
  return stage;
}
