import { describe, expect, it } from "bun:test";
import {
  ACTIVE_MINUTES_PER_HALF_HEART,
  HALF_HEART_DECAY_HOURS,
  MAX_HALF_HEARTS,
  resolveHalfHearts,
  weekendMsBetween,
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

describe("configurable decay/regen timings", () => {
  it("honors a custom decayHours block size", () => {
    // 24h idle at 24h/half-heart = exactly one block of decay.
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: hoursAgo(24),
          activeMinutes: 0,
          currentHalfHearts: 6,
          decayHours: 24,
        },
        NOW,
      ),
    ).toBe(5);
  });

  it("honors a custom regenMinutes block size", () => {
    // 45 active minutes at 15min/half-heart = 3 half-hearts of heal.
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: hoursAgo(0),
          activeMinutes: 45,
          currentHalfHearts: 2,
          regenMinutes: 15,
        },
        NOW,
      ),
    ).toBe(5);
  });

  it("non-positive or non-finite overrides fall back to the defaults", () => {
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: hoursAgo(8),
          activeMinutes: 60,
          currentHalfHearts: 3,
          decayHours: 0,
          regenMinutes: Number.NaN,
        },
        NOW,
      ),
    ).toBe(3); // −1 (8h block) +1 (60min block) with defaults
  });
});

describe("skip weekends", () => {
  const HOUR = 3600_000;
  // Local-time constructors so weekday math is deterministic in any TZ.
  // 2026-07-03 is a Friday; 07-04/05 are Sat/Sun; 07-06 is Monday.
  const friday = (h: number) => new Date(2026, 6, 3, h);
  const monday = (h: number) => new Date(2026, 6, 6, h);
  const wednesday = (h: number) => new Date(2026, 6, 8, h);

  it("weekendMsBetween covers a full enclosed weekend", () => {
    expect(weekendMsBetween(friday(12).getTime(), monday(12).getTime())).toBe(
      48 * HOUR,
    );
  });

  it("weekendMsBetween is 0 for a midweek window", () => {
    expect(weekendMsBetween(monday(9).getTime(), wednesday(9).getTime())).toBe(
      0,
    );
  });

  it("weekendMsBetween handles a window starting inside the weekend", () => {
    const satEvening = new Date(2026, 6, 4, 18).getTime();
    const sunMorning = new Date(2026, 6, 5, 6).getTime();
    expect(weekendMsBetween(satEvening, sunMorning)).toBe(12 * HOUR);
  });

  it("skipWeekends suppresses decay across a weekend-only idle stretch", () => {
    // Friday 22:00 → Sunday 22:00 = 48h; only Fri 22–24 (2h) counts.
    const input = {
      lastActivityAt: friday(22).toISOString(),
      activeMinutes: 0,
      currentHalfHearts: 6,
    };
    expect(resolveHalfHearts(input, new Date(2026, 6, 5, 22))).toBe(0);
    expect(
      resolveHalfHearts(
        { ...input, skipWeekends: true },
        new Date(2026, 6, 5, 22),
      ),
    ).toBe(6);
  });

  it("skipWeekends still charges weekday idle hours", () => {
    // Friday 00:00 → Monday 16:00 = 88h elapsed, 48h weekend → 40h ⇒ −5.
    expect(
      resolveHalfHearts(
        {
          lastActivityAt: friday(0).toISOString(),
          activeMinutes: 0,
          currentHalfHearts: 6,
          skipWeekends: true,
        },
        monday(16),
      ),
    ).toBe(1);
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
