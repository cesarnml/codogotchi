import { describe, expect, it } from "bun:test";
import {
  computeXp,
  STAGE_THRESHOLDS,
  stageForXp,
  XP_PER_CLAUDE_TOKEN,
  XP_PER_CODEX_TOKEN,
  XP_PER_GITHUB_PR,
  XP_PER_WAKATIME_HOUR,
  xpFromClaudeTokens,
  xpFromCodexTokens,
  xpFromGithubPRs,
  xpFromWakatimeHours,
} from "./xp";

describe("per-source helpers", () => {
  it("xpFromClaudeTokens scales linearly with token count", () => {
    expect(xpFromClaudeTokens(0)).toBe(0);
    expect(xpFromClaudeTokens(10_000)).toBe(10_000 * XP_PER_CLAUDE_TOKEN);
    expect(xpFromClaudeTokens(100_000)).toBe(100_000 * XP_PER_CLAUDE_TOKEN);
  });

  it("xpFromCodexTokens scales linearly with token count", () => {
    expect(xpFromCodexTokens(0)).toBe(0);
    expect(xpFromCodexTokens(50_000)).toBe(50_000 * XP_PER_CODEX_TOKEN);
  });

  it("xpFromGithubPRs scales linearly with merged PR count", () => {
    expect(xpFromGithubPRs(0)).toBe(0);
    expect(xpFromGithubPRs(1)).toBe(XP_PER_GITHUB_PR);
    expect(xpFromGithubPRs(7)).toBe(7 * XP_PER_GITHUB_PR);
  });

  it("xpFromWakatimeHours scales linearly with coding hours", () => {
    expect(xpFromWakatimeHours(0)).toBe(0);
    expect(xpFromWakatimeHours(1)).toBe(XP_PER_WAKATIME_HOUR);
    expect(xpFromWakatimeHours(8)).toBe(8 * XP_PER_WAKATIME_HOUR);
  });

  it("negative inputs floor to zero (each source independent)", () => {
    expect(xpFromClaudeTokens(-100)).toBe(0);
    expect(xpFromCodexTokens(-1)).toBe(0);
    expect(xpFromGithubPRs(-3)).toBe(0);
    expect(xpFromWakatimeHours(-1)).toBe(0);
  });
});

describe("computeXp", () => {
  it("zero signals → zero everywhere", () => {
    const result = computeXp({
      claudeTokens: 0,
      codexTokens: 0,
      githubPRs: 0,
      wakatimeHours: 0,
    });
    expect(result).toEqual({
      byClaude: 0,
      byCodex: 0,
      byGithub: 0,
      byWakatime: 0,
      total: 0,
    });
  });

  it("aggregates a known multi-source signal set", () => {
    const result = computeXp({
      claudeTokens: 100_000,
      codexTokens: 50_000,
      githubPRs: 3,
      wakatimeHours: 4,
    });
    expect(result.byClaude).toBe(100_000 * XP_PER_CLAUDE_TOKEN);
    expect(result.byCodex).toBe(50_000 * XP_PER_CODEX_TOKEN);
    expect(result.byGithub).toBe(3 * XP_PER_GITHUB_PR);
    expect(result.byWakatime).toBe(4 * XP_PER_WAKATIME_HOUR);
    expect(result.total).toBe(
      result.byClaude + result.byCodex + result.byGithub + result.byWakatime,
    );
  });

  it("per-source isolation: claude input does not affect github contribution", () => {
    const noClaude = computeXp({
      claudeTokens: 0,
      codexTokens: 0,
      githubPRs: 5,
      wakatimeHours: 0,
    });
    const withClaude = computeXp({
      claudeTokens: 1_000_000,
      codexTokens: 0,
      githubPRs: 5,
      wakatimeHours: 0,
    });
    expect(withClaude.byGithub).toBe(noClaude.byGithub);
  });

  it("monotonic: increasing any source increases total", () => {
    const baseline = computeXp({
      claudeTokens: 1000,
      codexTokens: 1000,
      githubPRs: 1,
      wakatimeHours: 1,
    });
    const moreClaude = computeXp({
      claudeTokens: 2000,
      codexTokens: 1000,
      githubPRs: 1,
      wakatimeHours: 1,
    });
    const morePRs = computeXp({
      claudeTokens: 1000,
      codexTokens: 1000,
      githubPRs: 2,
      wakatimeHours: 1,
    });
    expect(moreClaude.total).toBeGreaterThan(baseline.total);
    expect(morePRs.total).toBeGreaterThan(baseline.total);
  });
});

describe("stageForXp", () => {
  it("returns Stage 1 below the first threshold", () => {
    expect(stageForXp(0)).toBe(1);
    expect(stageForXp(STAGE_THRESHOLDS[1] - 1)).toBe(1);
  });

  it("returns Stage N at and just above threshold N-1", () => {
    expect(stageForXp(STAGE_THRESHOLDS[1])).toBe(2);
    expect(stageForXp(STAGE_THRESHOLDS[1] + 1)).toBe(2);
    expect(stageForXp(STAGE_THRESHOLDS[2])).toBe(3);
    expect(stageForXp(STAGE_THRESHOLDS[3])).toBe(4);
    expect(stageForXp(STAGE_THRESHOLDS[4])).toBe(5);
  });

  it("clamps to Stage 5 for very large XP totals", () => {
    expect(stageForXp(STAGE_THRESHOLDS[4] * 100)).toBe(5);
  });

  it("each boundary: just-below stays at previous stage", () => {
    for (let i = 1; i <= 4; i++) {
      const threshold = STAGE_THRESHOLDS[i];
      if (threshold === undefined) continue;
      expect(stageForXp(threshold - 1)).toBe(i);
      expect(stageForXp(threshold)).toBe(i + 1);
    }
  });
});
