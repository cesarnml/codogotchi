import { describe, expect, it } from "bun:test";
import { ACTIVITY_STATES } from "./animation-state";
import {
  parseStateJson,
  STATE_JSON_SCHEMA_VERSION,
  sourceEventOriginSchema,
  stateJsonV1Schema,
} from "./state-json";

const baseV1Payload = {
  schema_version: 1 as number,
  activity_state: "idle",
  hp_overlay: "thriving",
  hp: 100,
  updated_at: "2026-05-24T00:00:00.000Z",
  source_event: {
    origin: "manual",
    kind: "cli",
    name: "manual-poke",
  },
};

describe("STATE_JSON_SCHEMA_VERSION", () => {
  it("is 5 after the Phase 10 v5 bump", () => {
    expect(STATE_JSON_SCHEMA_VERSION).toBe(5);
  });
});

describe("v3 state.json parses with the new activity states", () => {
  it("accepts schema_version 3 + activity_state standby", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 3,
      activity_state: "standby",
    };
    expect(() => parseStateJson(payload)).not.toThrow();
    expect(parseStateJson(payload).activity_state).toBe("standby");
  });

  it("rejects activity_state requesting_input (removed in v3)", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 3,
      activity_state: "requesting_input",
    };
    expect(() => parseStateJson(payload)).toThrow();
  });

  it("accepts schema_version 3 + activity_state errored", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 3,
      activity_state: "errored",
    };
    expect(() => parseStateJson(payload)).not.toThrow();
    expect(parseStateJson(payload).activity_state).toBe("errored");
  });
});

describe("attention field (P6.01)", () => {
  it("accepts a fully-populated attention object", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 3,
      activity_state: "standby",
      attention: {
        reason_kind: "input_requested",
        summary: "Waiting for user input",
        created_at: "2026-05-29T00:00:00.000Z",
        expires_at: "2026-05-29T00:05:00.000Z",
      },
    };
    expect(() => parseStateJson(payload)).not.toThrow();
    const parsed = parseStateJson(payload);
    expect(parsed.attention).toEqual({
      reason_kind: "input_requested",
      summary: "Waiting for user input",
      created_at: "2026-05-29T00:00:00.000Z",
      expires_at: "2026-05-29T00:05:00.000Z",
    });
  });

  it("accepts absence of attention field", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 3,
      activity_state: "standby",
    };
    expect(() => parseStateJson(payload)).not.toThrow();
    expect(parseStateJson(payload).attention).toBeUndefined();
  });

  it("rejects attention with invalid reason_kind", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 3,
      activity_state: "standby",
      attention: {
        reason_kind: "unknown_kind",
        summary: "test",
        created_at: "2026-05-29T00:00:00.000Z",
        expires_at: "2026-05-29T00:05:00.000Z",
      },
    };
    expect(() => parseStateJson(payload)).toThrow();
  });
});

describe("work_mode field — removed in v4", () => {
  it("work_mode is silently stripped (unknown key, not rejected)", () => {
    // Zod strips unknown keys by default; payloads that include work_mode remain parseable.
    const payload = {
      ...baseV1Payload,
      schema_version: 4,
      activity_state: "standby",
      work_mode: "thinking",
    };
    expect(() => parseStateJson(payload)).not.toThrow();
  });
});

describe("source_event repo identity", () => {
  it("accepts optional repo_root for workspace-aware badge clearing", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 4,
      source_event: {
        ...baseV1Payload.source_event,
        repo_root: "/repo/non-soa",
      },
    };
    const parsed = parseStateJson(payload);
    expect(parsed.source_event.repo_root).toBe("/repo/non-soa");
  });
});

describe("backward compatibility for v1 and v2 payloads", () => {
  it("still parses a schema_version 1 payload as valid", () => {
    expect(() => stateJsonV1Schema.parse(baseV1Payload)).not.toThrow();
  });

  it("still parses schema_version 2 + errored", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 2,
      activity_state: "errored",
    };
    expect(() => parseStateJson(payload)).not.toThrow();
  });
});

describe("schema v5 — RPG progression fields (P10.03)", () => {
  const baseV5Payload = {
    schema_version: 5 as number,
    activity_state: "idle",
    hp_overlay: "thriving",
    hp: 100,
    updated_at: "2026-06-03T00:00:00.000Z",
    source_event: {
      origin: "manual",
      kind: "cli",
      name: "manual-poke",
    },
    level: 1,
    level_fraction: 0,
    half_hearts: 6,
    last_activity_at: "2026-06-03T00:00:00.000Z",
  };

  it("STATE_JSON_SCHEMA_VERSION is 5", () => {
    expect(STATE_JSON_SCHEMA_VERSION).toBe(5);
  });

  it("parseStateJson accepts a v5 payload with all four new fields", () => {
    expect(() => parseStateJson(baseV5Payload)).not.toThrow();
  });

  it("parseStateJson accepts a v5 payload with last_activity_at: null", () => {
    expect(() =>
      parseStateJson({ ...baseV5Payload, last_activity_at: null }),
    ).not.toThrow();
  });

  it("parseStateJson rejects v5 payload missing level", () => {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { level: _level, ...rest } = baseV5Payload;
    expect(() => parseStateJson(rest)).toThrow();
  });

  it("parseStateJson rejects half_hearts = 7 (above max 6)", () => {
    expect(() =>
      parseStateJson({ ...baseV5Payload, half_hearts: 7 }),
    ).toThrow();
  });

  it("parseStateJson rejects half_hearts = -1 (below min 0)", () => {
    expect(() =>
      parseStateJson({ ...baseV5Payload, half_hearts: -1 }),
    ).toThrow();
  });

  it("parseStateJson rejects level = 0 (below min 1)", () => {
    expect(() => parseStateJson({ ...baseV5Payload, level: 0 })).toThrow();
  });

  it("parseStateJson rejects level = 101 (above max 100)", () => {
    expect(() => parseStateJson({ ...baseV5Payload, level: 101 })).toThrow();
  });

  it("parseStateJson accepts level_fraction = 0 (minimum)", () => {
    expect(() =>
      parseStateJson({ ...baseV5Payload, level_fraction: 0 }),
    ).not.toThrow();
  });

  it("parseStateJson accepts level_fraction = 1 (maximum)", () => {
    expect(() =>
      parseStateJson({ ...baseV5Payload, level_fraction: 1 }),
    ).not.toThrow();
  });

  it("parseStateJson still accepts a v4 payload (backward compat)", () => {
    const v4Payload = { ...baseV5Payload, schema_version: 4 as number };
    expect(() => parseStateJson(v4Payload)).not.toThrow();
  });
});

describe("sourceEventOriginSchema — P9.01 vscode/antigravity origins", () => {
  it("accepts vscode as a valid source_event origin", () => {
    expect(sourceEventOriginSchema.safeParse("vscode").success).toBe(true);
  });

  it("accepts antigravity as a valid source_event origin", () => {
    expect(sourceEventOriginSchema.safeParse("antigravity").success).toBe(true);
  });
});

describe("forward-compat refusal", () => {
  it("rejects schema_version 6 (one ahead of v5)", () => {
    const payload = { ...baseV1Payload, schema_version: 6 };
    expect(() => parseStateJson(payload)).toThrow();
  });
});

describe("schema v4 vocabulary", () => {
  it("STATE_JSON_SCHEMA_VERSION is 5 (v4 vocabulary still tested below)", () => {
    expect(STATE_JSON_SCHEMA_VERSION).toBe(5);
  });

  it("v4 hook states are members of ACTIVITY_STATES", () => {
    const states = ACTIVITY_STATES as readonly string[];
    expect(states).toContain("testing");
    expect(states).toContain("thinking");
    expect(states).toContain("reading");
    expect(states).toContain("cramming");
    expect(states).toContain("waiting_for_input");
  });

  it("v4 SoA gate states are members of ACTIVITY_STATES", () => {
    const states = ACTIVITY_STATES as readonly string[];
    expect(states).toContain("ticket_started");
    expect(states).toContain("ticket_completed");
    expect(states).toContain("review_clean");
    expect(states).toContain("red_tdd");
    expect(states).toContain("green_tdd");
    expect(states).toContain("adversarial_review");
    expect(states).toContain("open_pr");
    expect(states).toContain("poll_review");
    expect(states).toContain("record_review");
    expect(states).toContain("advance");
  });

  it("deleted states are not members of ACTIVITY_STATES", () => {
    const states = ACTIVITY_STATES as readonly string[];
    expect(states).not.toContain("hyped");
    expect(states).not.toContain("celebrating");
    expect(states).not.toContain("running-tests");
    expect(states).not.toContain("reviewing");
    expect(states).not.toContain("pushing");
    expect(states).not.toContain("focused");
    expect(states).not.toContain("nervous");
    expect(states).not.toContain("panicking");
    expect(states).not.toContain("ascended");
    expect(states).not.toContain("calling_for_backup");
    expect(states).not.toContain("waiting");
  });

  it("parseStateJson accepts schema_version 4", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 4,
      activity_state: "idle",
    };
    expect(() => parseStateJson(payload)).not.toThrow();
  });

  it("parseStateJson rejects schema_version 6 (one past max)", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 6,
      activity_state: "idle",
    };
    expect(() => parseStateJson(payload)).toThrow();
  });

  it("payload with removed state hyped fails to parse under v4", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 4,
      activity_state: "hyped",
    };
    expect(() => parseStateJson(payload)).toThrow();
  });
});
