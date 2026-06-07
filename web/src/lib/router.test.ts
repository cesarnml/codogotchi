import { describe, expect, it } from "bun:test";
import { hashToView, viewToHash } from "./router";

describe("hashToView", () => {
  it("empty hash → gallery view", () => {
    expect(hashToView("")).toEqual({ type: "gallery" });
  });

  it("bare # → gallery view", () => {
    expect(hashToView("#")).toEqual({ type: "gallery" });
  });

  it("#<petId> → detail view with petId", () => {
    expect(hashToView("#maew")).toEqual({ type: "detail", petId: "maew" });
  });

  it("petId without # prefix → detail view", () => {
    expect(hashToView("boba")).toEqual({ type: "detail", petId: "boba" });
  });
});

describe("viewToHash", () => {
  it("gallery view → empty string", () => {
    expect(viewToHash({ type: "gallery" })).toBe("");
  });

  it("detail view → #<petId>", () => {
    expect(viewToHash({ type: "detail", petId: "maew" })).toBe("#maew");
  });
});

describe("round-trip", () => {
  it("gallery round-trips", () => {
    const v = { type: "gallery" } as const;
    expect(hashToView(viewToHash(v))).toEqual(v);
  });

  it("detail round-trips", () => {
    const v = { type: "detail", petId: "byte" } as const;
    expect(hashToView(viewToHash(v))).toEqual(v);
  });
});
