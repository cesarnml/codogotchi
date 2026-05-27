import { describe, expect, it } from "bun:test";
import {
  type HttpFetch,
  type HttpResponse,
  readGithubSignals,
  resolveGithubMergedSince,
} from "./github";

interface PRFixture {
  number: number;
  title: string;
  additions: number;
  deletions: number;
  reviewComments: number;
  mergedAt: string;
  repoFullName: string;
}

function searchItem(pr: PRFixture) {
  const [owner, repo] = pr.repoFullName.split("/");
  return {
    number: pr.number,
    title: pr.title,
    pull_request: {
      url: `https://api.github.com/repos/${owner}/${repo}/pulls/${pr.number}`,
      html_url: `https://github.com/${owner}/${repo}/pull/${pr.number}`,
    },
    repository_url: `https://api.github.com/repos/${owner}/${repo}`,
    closed_at: pr.mergedAt,
  };
}

function prDetail(pr: PRFixture) {
  return {
    number: pr.number,
    title: pr.title,
    additions: pr.additions,
    deletions: pr.deletions,
    review_comments: pr.reviewComments,
    merged_at: pr.mergedAt,
    html_url: `https://github.com/${pr.repoFullName}/pull/${pr.number}`,
    base: { repo: { full_name: pr.repoFullName } },
  };
}

interface CannedRouting {
  searchItems: PRFixture[];
  prs: PRFixture[];
  rateLimitOnPR?: number;
}

function mockHttp(canned: CannedRouting): {
  fetch: HttpFetch;
  calls: string[];
} {
  const calls: string[] = [];
  const respond = (body: unknown, status = 200): HttpResponse => ({
    ok: status >= 200 && status < 300,
    status,
    headers: {},
    json: async () => body,
  });
  const fetch: HttpFetch = async (url) => {
    calls.push(url);
    if (url.includes("/search/issues")) {
      return respond({
        total_count: canned.searchItems.length,
        items: canned.searchItems.map(searchItem),
      });
    }
    const m = url.match(/\/repos\/([^/]+)\/([^/]+)\/pulls\/(\d+)/);
    if (m) {
      const num = Number(m[3]);
      if (canned.rateLimitOnPR === num) {
        return {
          ok: false,
          status: 403,
          headers: { "x-ratelimit-remaining": "0" },
          json: async () => ({ message: "API rate limit exceeded" }),
        };
      }
      const pr = canned.prs.find((p) => p.number === num);
      if (!pr) return respond({ message: "Not Found" }, 404);
      return respond(prDetail(pr));
    }
    return respond({}, 404);
  };
  return { fetch, calls };
}

describe("resolveGithubMergedSince", () => {
  const now = new Date("2026-05-18T12:00:00.000Z");

  it("uses now when since is null (forward-only, no backfill)", () => {
    expect(resolveGithubMergedSince(null, now).toISOString()).toBe(
      now.toISOString(),
    );
  });

  it("uses the provided since on subsequent syncs", () => {
    const since = new Date("2026-05-17T00:00:00.000Z");
    expect(resolveGithubMergedSince(since, now).toISOString()).toBe(
      since.toISOString(),
    );
  });
});

describe("readGithubSignals — forward-only first sync", () => {
  const now = new Date("2026-05-18T00:00:00.000Z");

  it("does not ingest PRs merged before the sync instant", async () => {
    const prs: PRFixture[] = [
      {
        number: 1,
        title: "feat: old",
        additions: 10,
        deletions: 5,
        reviewComments: 0,
        mergedAt: "2026-05-10T00:00:00.000Z",
        repoFullName: "owner/repo",
      },
    ];
    const { fetch, calls } = mockHttp({ searchItems: [], prs });
    const result = await readGithubSignals({
      token: "t",
      username: "alice",
      since: null,
      now,
      http: fetch,
    });
    expect(result.prs.length).toBe(0);
    expect(decodeURIComponent(calls[0] ?? "")).toContain("merged:>=2026-05-18");
  });

  it("ingests PRs merged on or after the first-sync calendar day", async () => {
    const prs: PRFixture[] = [
      {
        number: 1,
        title: "feat: today",
        additions: 30,
        deletions: 5,
        reviewComments: 0,
        mergedAt: "2026-05-18T10:00:00.000Z",
        repoFullName: "o/r",
      },
    ];
    const { fetch } = mockHttp({ searchItems: prs, prs });
    const result = await readGithubSignals({
      token: "t",
      username: "alice",
      since: null,
      now,
      http: fetch,
    });
    expect(result.prs.length).toBe(1);
    expect(result.prs[0]?.number).toBe(1);
  });
});

describe("readGithubSignals — subsequent sync", () => {
  it("uses since cutoff for merged search", async () => {
    const prs: PRFixture[] = [
      {
        number: 7,
        title: "fix: regression",
        additions: 5,
        deletions: 3,
        reviewComments: 1,
        mergedAt: "2026-05-17T12:00:00.000Z",
        repoFullName: "o/r",
      },
    ];
    const { fetch, calls } = mockHttp({ searchItems: prs, prs });
    const result = await readGithubSignals({
      token: "t",
      username: "alice",
      since: new Date("2026-05-17T00:00:00.000Z"),
      now: new Date("2026-05-18T00:00:00.000Z"),
      http: fetch,
    });
    expect(result.prs.length).toBe(1);
    expect(decodeURIComponent(calls[0] ?? "")).toContain("merged:>=2026-05-17");
  });
});

describe("readGithubSignals — enrichment + scoring", () => {
  const now = new Date("2026-05-18T00:00:00.000Z");

  it("applies scorePR (revert collapses the score)", async () => {
    const prs: PRFixture[] = [
      {
        number: 42,
        title: 'Revert "feat: oops"',
        additions: 60,
        deletions: 60,
        reviewComments: 2,
        mergedAt: "2026-05-18T12:00:00.000Z",
        repoFullName: "o/r",
      },
    ];
    const { fetch } = mockHttp({ searchItems: prs, prs });
    const result = await readGithubSignals({
      token: "t",
      username: "alice",
      since: null,
      now,
      http: fetch,
    });
    expect(result.prs[0]?.score).toBeLessThanOrEqual(0.2);
    expect(result.prs[0]?.scoreExplanation.toLowerCase()).toContain("revert");
  });

  it("heavy review traffic lowers score relative to a clean PR", async () => {
    const prs: PRFixture[] = [
      {
        number: 1,
        title: "feat: clean",
        additions: 50,
        deletions: 10,
        reviewComments: 0,
        mergedAt: "2026-05-18T12:00:00.000Z",
        repoFullName: "o/r",
      },
      {
        number: 2,
        title: "feat: noisy",
        additions: 50,
        deletions: 10,
        reviewComments: 30,
        mergedAt: "2026-05-18T13:00:00.000Z",
        repoFullName: "o/r",
      },
    ];
    const { fetch } = mockHttp({ searchItems: prs, prs });
    const result = await readGithubSignals({
      token: "t",
      username: "alice",
      since: null,
      now,
      http: fetch,
    });
    const clean = result.prs.find((p) => p.number === 1);
    const noisy = result.prs.find((p) => p.number === 2);
    expect(noisy?.score).toBeLessThan(clean?.score ?? 0);
    expect(noisy?.scoreExplanation).toContain("30 review comments");
  });
});

describe("readGithubSignals — rate limit", () => {
  it("returns partial result with rateLimitHit=true on 403 during enrichment", async () => {
    const prs: PRFixture[] = [
      {
        number: 1,
        title: "feat: one",
        additions: 10,
        deletions: 1,
        reviewComments: 0,
        mergedAt: "2026-05-18T12:00:00.000Z",
        repoFullName: "o/r",
      },
      {
        number: 2,
        title: "feat: two",
        additions: 10,
        deletions: 1,
        reviewComments: 0,
        mergedAt: "2026-05-18T13:00:00.000Z",
        repoFullName: "o/r",
      },
    ];
    const { fetch } = mockHttp({
      searchItems: prs,
      prs,
      rateLimitOnPR: 2,
    });
    const result = await readGithubSignals({
      token: "t",
      username: "alice",
      since: null,
      now: new Date("2026-05-18T00:00:00.000Z"),
      http: fetch,
      concurrency: 1,
    });
    expect(result.rateLimitHit).toBe(true);
    expect(result.prs.length).toBe(1);
    expect(result.prs[0]?.number).toBe(1);
  });

  it("returns rateLimitHit=true on 403 during search itself", async () => {
    const fetch: HttpFetch = async () => ({
      ok: false,
      status: 403,
      headers: { "x-ratelimit-remaining": "0" },
      json: async () => ({ message: "API rate limit exceeded" }),
    });
    const result = await readGithubSignals({
      token: "t",
      username: "alice",
      since: null,
      now: new Date("2026-05-18T00:00:00.000Z"),
      http: fetch,
    });
    expect(result.rateLimitHit).toBe(true);
    expect(result.prs.length).toBe(0);
  });
});
