import { describe, expect, it } from "bun:test";
import {
  normalizeUsername,
  USERNAME_MAX,
  USERNAME_MIN,
  usernameTakenMessage,
  validateUsername,
} from "./username";

describe("normalizeUsername", () => {
  it("trims surrounding whitespace", () => {
    expect(normalizeUsername("  maew  ")).toBe("maew");
  });

  it("lowercases so case variants collapse to one identity", () => {
    // uniqueness-shape: "Maew" and "maew" must normalize to the same value
    expect(normalizeUsername("Maew")).toBe(normalizeUsername("maew"));
    expect(normalizeUsername("MAEW")).toBe("maew");
  });
});

describe("validateUsername", () => {
  it("accepts a valid lowercase alphanumeric/underscore handle", () => {
    const result = validateUsername("boba_99");
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value).toBe("boba_99");
  });

  it("normalizes before validating (mixed case + padding is accepted)", () => {
    const result = validateUsername("  Byte_Sized  ");
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value).toBe("byte_sized");
  });

  it("rejects disallowed characters", () => {
    const result = validateUsername("bad name!");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toMatch(/letters|characters|invalid/i);
  });

  it("rejects too-short handles", () => {
    const tooShort = "a".repeat(USERNAME_MIN - 1);
    const result = validateUsername(tooShort);
    expect(result.ok).toBe(false);
  });

  it("rejects too-long handles", () => {
    const tooLong = "a".repeat(USERNAME_MAX + 1);
    const result = validateUsername(tooLong);
    expect(result.ok).toBe(false);
  });

  it("accepts boundary lengths", () => {
    expect(validateUsername("a".repeat(USERNAME_MIN)).ok).toBe(true);
    expect(validateUsername("a".repeat(USERNAME_MAX)).ok).toBe(true);
  });
});

describe("usernameTakenMessage", () => {
  it("names the colliding handle in the collision message", () => {
    expect(usernameTakenMessage("maew")).toBe(
      'Username "maew" is already taken',
    );
  });
});
