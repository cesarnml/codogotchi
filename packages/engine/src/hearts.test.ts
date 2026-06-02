import { describe, expect, it } from "bun:test";
import {
  ACTIVE_MINUTES_PER_HALF_HEART,
  HALF_HEART_DECAY_HOURS,
  MAX_HALF_HEARTS,
  resolveHalfHearts,
} from "./hearts";

const NOW = new Date("2026-06-03T12:00:00Z");

function hoursAgo(h: number): string {
  return new Date(NOW.getTime() - h * 3600_000).toISOString();
}

describe("constants", () => {
  it("exports MAX_HALF_HEARTS = 6", () => {
    expect(MAX_HALF_HEARTS).toBe(6);
  });
  it("exports HALF_HEART_DECAY_HOURS = 8", () => {
    expect(HALF_HEART_DECAY_HOURS).toBe(8);
  });
  it("exports ACTIVE_MINUTES_PER_HALF_HEART = 60", () => {
    expect(ACTIVE_MINUTES_PER_HALF_HEART).toBe(60);
  });
});

describe("fresh state (null lastActivityAt)", () => {
  it("returns MAX_HALF_HEARTS when lastActivityAt is null regardless of currentHalfHearts", () => {
    expect(
      resolveHalfHearts(
        { lastActivityAt: null, activeMinutes: 0, currentHalfHearts: 3 },
        NOW,
      ),
    ).toBe(6);
  });

  it("returns MAX_HALF_HEARTS even when currentHalfHearts is already 0", () => {
    expect(
      resolveHalfHearts(
        { lastActivityAt: null, activeMinutes: 0, currentHalfHearts: 0 },
        NOW,
      ),
    ).toBe(6);
  });

  it("does not add active minutes on top when lastActivityAt is null", () => {
    expect(
      resolveHalfHearts(
        { lastActivityAt: null, activeMinutes: 120, currentHalfHearts: 6 },
        NOW,
      ),
    ).toBe(6);
  });
});

describe("idle decay", () => {
  it("no decay when idle < 8h (partial block)", () => {
    expect(
      resolveHalfHearts(
        { lastActivityAt: hoursAgo(7), activeMinutes: 0, currentHalfHearts: 4 },
        NOW,
      ),
    ).toBe(4);
  });

  it("−1 half-heart after exactly 8h idle", () => {
    expect(
      resolveHalfHearts(
        { lastActivityAt: hoursAgo(8), activeMinutes: 0, currentHalfHearts: 6 },
        NOW,
      ),
    ).toBe(5);
  });

  it("−1 half-heart after 15h idle (only 1 full 8h block)", () => {
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: hoursAgo(15),
          activeMinutes: 0,
          currentHalfHearts: 6,
        },
        NOW,
      ),
    ).toBe(5);
  });

  it("floors at 0 after 48h idle (6 blocks of decay from 6 hearts)", () => {
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: hoursAgo(48),
          activeMinutes: 0,
          currentHalfHearts: 6,
        },
        NOW,
      ),
    ).toBe(0);
  });

  it("floors at 0 with surplus idle beyond what currentHalfHearts can absorb", () => {
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: hoursAgo(200),
          activeMinutes: 0,
          currentHalfHearts: 2,
        },
        NOW,
      ),
    ).toBe(0);
  });
});

describe("active healing", () => {
  it("ghost + 60 active minutes → 1 half-heart", () => {
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: hoursAgo(48),
          activeMinutes: 60,
          currentHalfHearts: 0,
        },
        NOW,
      ),
    ).toBe(1);
  });

  it("partial active minutes (< 60) produce no heal", () => {
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: hoursAgo(48),
          activeMinutes: 59,
          currentHalfHearts: 0,
        },
        NOW,
      ),
    ).toBe(0);
  });

  it("caps at 6 with surplus active minutes", () => {
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: hoursAgo(0),
          activeMinutes: 300,
          currentHalfHearts: 3,
        },
        NOW,
      ),
    ).toBe(6);
  });
});

describe("simultaneous idle + active", () => {
  it("heal outweighs decay: net positive", () => {
    // 8h idle (−1) + 120 active minutes (+2) = net +1
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: hoursAgo(8),
          activeMinutes: 120,
          currentHalfHearts: 3,
        },
        NOW,
      ),
    ).toBe(4);
  });

  it("decay outweighs heal: net negative", () => {
    // 24h idle (−3) + 60 active minutes (+1) = net −2
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: hoursAgo(24),
          activeMinutes: 60,
          currentHalfHearts: 4,
        },
        NOW,
      ),
    ).toBe(2);
  });
});

describe("edge cases", () => {
  it("lastActivityAt in the future (clock drift) → no decay, no negative elapsed", () => {
    const future = new Date(NOW.getTime() + 3 * 3600_000).toISOString();
    expect(
      resolveHalfHearts(
        { lastActivityAt: future, activeMinutes: 0, currentHalfHearts: 4 },
        NOW,
      ),
    ).toBe(4);
  });

  it("currentHalfHearts already 0, no activity, short idle → stays 0", () => {
    expect(
      resolveHalfHearts(
        { lastActivityAt: hoursAgo(1), activeMinutes: 0, currentHalfHearts: 0 },
        NOW,
      ),
    ).toBe(0);
  });

  it("malformed ISO string → no decay, result is still in [0,6]", () => {
    const result = resolveHalfHearts(
      { lastActivityAt: "not-a-date", activeMinutes: 0, currentHalfHearts: 4 },
      NOW,
    );
    expect(result).toBe(4);
    expect(Number.isFinite(result)).toBe(true);
  });

  it("NaN activeMinutes → treated as 0, no heal", () => {
    const result = resolveHalfHearts(
      { lastActivityAt: hoursAgo(0), activeMinutes: NaN, currentHalfHearts: 3 },
      NOW,
    );
    expect(result).toBe(3);
    expect(Number.isFinite(result)).toBe(true);
  });

  it("NaN currentHalfHearts → treated as 0, result still in [0,6]", () => {
    const result = resolveHalfHearts(
      { lastActivityAt: hoursAgo(0), activeMinutes: 0, currentHalfHearts: NaN },
      NOW,
    );
    expect(result).toBe(0);
    expect(Number.isFinite(result)).toBe(true);
  });
});
