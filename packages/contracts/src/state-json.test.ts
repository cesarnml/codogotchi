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
  it("is 2 after the Phase 03 v2 bump", () => {
    expect(STATE_JSON_SCHEMA_VERSION).toBe(2);
  });
});

describe("v2 state.json parses with the new activity states", () => {
  it("accepts schema_version 2 + activity_state requesting_input", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 2,
      activity_state: "requesting_input",
    };
    expect(() => parseStateJson(payload)).not.toThrow();
    expect(parseStateJson(payload).activity_state).toBe("requesting_input");
  });

  it("accepts schema_version 2 + activity_state errored", () => {
    const payload = {
      ...baseV1Payload,
      schema_version: 2,
      activity_state: "errored",
    };
    expect(() => parseStateJson(payload)).not.toThrow();
    expect(parseStateJson(payload).activity_state).toBe("errored");
  });
});

describe("backward compatibility for v1 payloads", () => {
  it("still parses a schema_version 1 payload as valid v1", () => {
    expect(() => stateJsonV1Schema.parse(baseV1Payload)).not.toThrow();
  });
});

describe("forward-compat refusal", () => {
  it("rejects schema_version 3 (one ahead of v2)", () => {
    const payload = { ...baseV1Payload, schema_version: 3 };
    expect(() => parseStateJson(payload)).toThrow();
  });
});
