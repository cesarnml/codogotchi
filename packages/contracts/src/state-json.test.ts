import { describe, expect, it } from "bun:test";
import {
  parseStateJson,
  STATE_JSON_SCHEMA_VERSION,
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
  it("is 3 after the Phase 06 v3 bump", () => {
    expect(STATE_JSON_SCHEMA_VERSION).toBe(3);
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
    const payload = { ...baseV1Payload, schema_version: 3, activity_state: "standby" };
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

describe("work_mode field (P6.01 stub)", () => {
  it("accepts work_mode: thinking", () => {
    const payload = { ...baseV1Payload, schema_version: 3, activity_state: "standby", work_mode: "thinking" };
    expect(() => parseStateJson(payload)).not.toThrow();
    expect(parseStateJson(payload).work_mode).toBe("thinking");
  });

  it("accepts work_mode: implementing", () => {
    const payload = { ...baseV1Payload, schema_version: 3, activity_state: "standby", work_mode: "implementing" };
    expect(() => parseStateJson(payload)).not.toThrow();
    expect(parseStateJson(payload).work_mode).toBe("implementing");
  });

  it("accepts work_mode: testing", () => {
    const payload = { ...baseV1Payload, schema_version: 3, activity_state: "standby", work_mode: "testing" };
    expect(() => parseStateJson(payload)).not.toThrow();
    expect(parseStateJson(payload).work_mode).toBe("testing");
  });

  it("accepts absence of work_mode", () => {
    const payload = { ...baseV1Payload, schema_version: 3, activity_state: "standby" };
    expect(() => parseStateJson(payload)).not.toThrow();
    expect(parseStateJson(payload).work_mode).toBeUndefined();
  });
});

describe("backward compatibility for v1 and v2 payloads", () => {
  it("still parses a schema_version 1 payload as valid", () => {
    expect(() => stateJsonV1Schema.parse(baseV1Payload)).not.toThrow();
  });

  it("still parses schema_version 2 + errored", () => {
    const payload = { ...baseV1Payload, schema_version: 2, activity_state: "errored" };
    expect(() => parseStateJson(payload)).not.toThrow();
  });
});

describe("forward-compat refusal", () => {
  it("rejects schema_version 4 (one ahead of v3)", () => {
    const payload = { ...baseV1Payload, schema_version: 4 };
    expect(() => parseStateJson(payload)).toThrow();
  });
});
