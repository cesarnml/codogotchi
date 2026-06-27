import { describe, expect, it } from "bun:test";
import type { SliceEntry } from "./slice-entry";
import { globalAggregate, perPlatform, sliceEntrySchema } from "./slice-entry";

const makeSlice = (overrides: Partial<SliceEntry> = {}): SliceEntry => ({
  origin: "claude_code",
  session_id: "test-session-1",
  activity_state: "idle",
  hp_overlay: "thriving",
  hp: 100,
  updated_at: "2026-06-28T00:00:00.000Z",
  source_event: { origin: "claude_code", kind: "cli", name: "test" },
  ...overrides,
});

describe("sliceEntrySchema — validator", () => {
  it("accepts a well-formed slice entry", () => {
    expect(() => sliceEntrySchema.parse(makeSlice())).not.toThrow();
  });

  it("rejects a slice entry missing origin", () => {
    const { origin: _o, ...noOrigin } = makeSlice();
    expect(() => sliceEntrySchema.parse(noOrigin)).toThrow();
  });

  it("rejects a slice entry missing session_id", () => {
    const { session_id: _s, ...noSession } = makeSlice();
    expect(() => sliceEntrySchema.parse(noSession)).toThrow();
  });

  it("rejects a slice entry missing activity_state", () => {
    const { activity_state: _a, ...noState } = makeSlice();
    expect(() => sliceEntrySchema.parse(noState)).toThrow();
  });

  it("accepts a slice with all optional v5 RPG fields", () => {
    expect(() =>
      sliceEntrySchema.parse(
        makeSlice({
          level: 5,
          level_fraction: 0.5,
          half_hearts: 4,
          active_minutes: 12,
          last_activity_at: "2026-06-28T00:00:00.000Z",
        }),
      ),
    ).not.toThrow();
  });

  it("accepts a slice with attention field", () => {
    expect(() =>
      sliceEntrySchema.parse(
        makeSlice({
          attention: {
            reason_kind: "input_requested",
            summary: "Waiting for input",
            created_at: "2026-06-28T00:00:00.000Z",
            expires_at: "2026-06-28T00:05:00.000Z",
          },
        }),
      ),
    ).not.toThrow();
  });
});

describe("globalAggregate — empty set", () => {
  it("returns idle activity_state for an empty slice set", () => {
    const result = globalAggregate([]);
    expect(result.activity_state).toBe("idle");
  });

  it("returns thriving hp_overlay for an empty slice set", () => {
    const result = globalAggregate([]);
    expect(result.hp_overlay).toBe("thriving");
  });
});

describe("globalAggregate — single slice", () => {
  it("returns the slice state for a one-element input", () => {
    const slice = makeSlice({ activity_state: "implementing" });
    expect(globalAggregate([slice]).activity_state).toBe("implementing");
  });

  it("returns the slice hp for a one-element input", () => {
    const slice = makeSlice({ hp: 42 });
    expect(globalAggregate([slice]).hp).toBe(42);
  });
});

describe("globalAggregate — tiebreak (most-recent updated_at wins)", () => {
  it("picks the slice with the later updated_at when given two slices", () => {
    const older = makeSlice({
      activity_state: "idle",
      updated_at: "2026-01-01T00:00:00.000Z",
    });
    const newer = makeSlice({
      activity_state: "implementing",
      updated_at: "2026-06-28T00:00:00.000Z",
    });
    expect(globalAggregate([older, newer]).activity_state).toBe("implementing");
  });

  it("picks the winner regardless of input order (older first)", () => {
    const older = makeSlice({
      activity_state: "idle",
      updated_at: "2026-01-01T00:00:00.000Z",
    });
    const newer = makeSlice({
      activity_state: "thinking",
      updated_at: "2026-06-28T12:00:00.000Z",
    });
    expect(globalAggregate([older, newer]).activity_state).toBe("thinking");
    expect(globalAggregate([newer, older]).activity_state).toBe("thinking");
  });

  it("handles three slices — last updated wins", () => {
    const oldest = makeSlice({
      activity_state: "idle",
      session_id: "s1",
      updated_at: "2026-01-01T00:00:00.000Z",
    });
    const middle = makeSlice({
      activity_state: "searching",
      session_id: "s2",
      updated_at: "2026-03-01T00:00:00.000Z",
    });
    const latest = makeSlice({
      activity_state: "implementing",
      session_id: "s3",
      updated_at: "2026-06-28T00:00:00.000Z",
    });
    expect(globalAggregate([oldest, middle, latest]).activity_state).toBe(
      "implementing",
    );
  });
});

describe("perPlatform — distinct origins", () => {
  it("returns one entry per distinct origin", () => {
    const claude = makeSlice({ origin: "claude_code", session_id: "s1" });
    const cursor = makeSlice({
      origin: "cursor",
      session_id: "s2",
      activity_state: "thinking",
    });
    const result = perPlatform([claude, cursor]);
    expect(Object.keys(result)).toHaveLength(2);
    expect(result["claude_code"].activity_state).toBe("idle");
    expect(result["cursor"].activity_state).toBe("thinking");
  });

  it("collapses multiple sessions of the same origin via most-recent updated_at", () => {
    const older = makeSlice({
      origin: "claude_code",
      session_id: "s1",
      activity_state: "idle",
      updated_at: "2026-01-01T00:00:00.000Z",
    });
    const newer = makeSlice({
      origin: "claude_code",
      session_id: "s2",
      activity_state: "implementing",
      updated_at: "2026-06-28T00:00:00.000Z",
    });
    const result = perPlatform([older, newer]);
    expect(Object.keys(result)).toHaveLength(1);
    expect(result["claude_code"].activity_state).toBe("implementing");
  });

  it("returns empty record for empty slice set", () => {
    const result = perPlatform([]);
    expect(Object.keys(result)).toHaveLength(0);
  });

  it("handles slices from three different origins", () => {
    const slices = [
      makeSlice({ origin: "claude_code", session_id: "s1" }),
      makeSlice({ origin: "cursor", session_id: "s2" }),
      makeSlice({ origin: "codex", session_id: "s3" }),
    ];
    const result = perPlatform(slices);
    expect(Object.keys(result)).toHaveLength(3);
  });
});
