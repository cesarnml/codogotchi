import { describe, expect, it } from "bun:test";
import {
  LEVEL_COUNT,
  LEVEL_EXPONENT,
  LEVEL_T,
  LEVEL_THRESHOLDS,
  levelForXp,
  levelProgress,
} from "./level";

const T = LEVEL_T;

describe("LEVEL_THRESHOLDS", () => {
  it("has exactly 100 entries", () => {
    expect(LEVEL_THRESHOLDS.length).toBe(LEVEL_COUNT);
  });

  it("first entry is 0 (level 1 starts at 0 XP)", () => {
    expect(LEVEL_THRESHOLDS[0]).toBe(0);
  });

  it("last entry is T (level 100 requires T total XP)", () => {
    expect(LEVEL_THRESHOLDS[99]).toBe(T);
  });

  it("is monotonically increasing", () => {
    for (let i = 1; i < LEVEL_THRESHOLDS.length; i++) {
      expect(LEVEL_THRESHOLDS[i]).toBeGreaterThan(LEVEL_THRESHOLDS[i - 1] ?? 0);
    }
  });

  it("constants have correct values", () => {
    expect(T).toBe(68_000_000_000);
    expect(LEVEL_EXPONENT).toBe(2.5);
    expect(LEVEL_COUNT).toBe(100);
  });
});

describe("levelForXp", () => {
  it("returns 1 at 0 XP", () => {
    expect(levelForXp(0)).toBe(1);
  });

  it("returns 100 at exactly T XP", () => {
    expect(levelForXp(T)).toBe(100);
  });

  it("caps at 100 for XP beyond T", () => {
    expect(levelForXp(T * 2)).toBe(100);
    expect(levelForXp(Number.MAX_SAFE_INTEGER)).toBe(100);
  });

  it("returns 1 for negative XP (clamped)", () => {
    expect(levelForXp(-1)).toBe(1);
    expect(levelForXp(-1_000_000)).toBe(1);
  });

  it("returns 1 for NaN input (clamped)", () => {
    expect(levelForXp(NaN)).toBe(1);
  });

  it("boundary at LEVEL_THRESHOLDS[50]: just below → level 50, at → level 51", () => {
    const threshold = LEVEL_THRESHOLDS[50] ?? 0;
    expect(levelForXp(threshold - 1)).toBe(50);
    expect(levelForXp(threshold)).toBe(51);
  });

  it("is monotonically non-decreasing over a sampled sweep", () => {
    const samples = 500;
    const step = T / samples;
    let prev = levelForXp(0);
    for (let i = 1; i <= samples; i++) {
      const curr = levelForXp(Math.round(i * step));
      expect(curr).toBeGreaterThanOrEqual(prev);
      prev = curr;
    }
  });
});

describe("levelProgress", () => {
  it("at 0 XP: level 1, fraction near 0", () => {
    const p = levelProgress(0);
    expect(p.level).toBe(1);
    expect(p.fraction).toBe(0);
    expect(p.into).toBe(0);
  });

  it("at T XP: level 100, fraction is 1, into is 0, span is positive", () => {
    const p = levelProgress(T);
    expect(p.level).toBe(100);
    expect(p.fraction).toBe(1);
    expect(p.into).toBe(0);
    expect(p.span).toBeGreaterThan(0);
  });

  it("beyond T: level 100, fraction clamped to 1", () => {
    const p = levelProgress(T * 2);
    expect(p.level).toBe(100);
    expect(p.fraction).toBe(1);
  });

  it("fraction near 0 at bottom of a level", () => {
    const threshold = LEVEL_THRESHOLDS[10] ?? 0;
    const p = levelProgress(threshold);
    expect(p.level).toBe(11);
    expect(p.fraction).toBeCloseTo(0, 5);
    expect(p.into).toBe(0);
  });

  it("fraction near 1 just below the next level threshold", () => {
    const lo = LEVEL_THRESHOLDS[10] ?? 0;
    const hi = LEVEL_THRESHOLDS[11] ?? 0;
    const p = levelProgress(hi - 1);
    expect(p.level).toBe(11);
    expect(p.fraction).toBeGreaterThan(0.99);
    expect(p.span).toBe(hi - lo);
    expect(p.into).toBe(hi - 1 - lo);
  });

  it("span = distance between adjacent thresholds for interior levels", () => {
    for (let i = 0; i < 99; i++) {
      const lo = LEVEL_THRESHOLDS[i] ?? 0;
      const hi = LEVEL_THRESHOLDS[i + 1] ?? 0;
      const p = levelProgress(lo);
      expect(p.span).toBe(hi - lo);
    }
  });
});
