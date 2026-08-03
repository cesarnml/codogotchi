"use node";

import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction } from "../_generated/server";

// GitHub reports a *cumulative* download_count per release asset and keeps no
// history. Sampling it on a schedule and differencing consecutive snapshots is
// the only way to chart installs over time.
//
// This is also the only counter that observes the download paths the website
// button cannot see: Homebrew (`brew install --cask codogotchi`), direct hits
// on `releases/latest/download/Codogotchi.dmg`, the GitHub releases page, and
// Sparkle auto-updates pulling the DMG from the appcast.
const DEFAULT_REPO = "cesarnml/codogotchi";

// Only `.dmg` assets are install signals. Sparkle's appcast XML, checksums, and
// source tarballs would otherwise pollute the series.
const TRACKED_EXTENSION = ".dmg";

// GitHub's maximum page size. See the truncation warning in the handler.
const PER_PAGE = 100;

type GitHubAsset = { name: unknown; download_count: unknown };
type GitHubRelease = { tag_name: unknown; assets: unknown };

/**
 * Fetches every release asset's cumulative download count and writes one
 * snapshot row per `.dmg` asset. Scheduled daily from `convex/crons.ts`.
 *
 * Unauthenticated GitHub API calls are rate-limited to 60/hour per IP, which a
 * daily cron sits far below. Setting a `GITHUB_TOKEN` deployment env var raises
 * that to 5000/hour and is honoured here if present, but is not required.
 */
export const pollReleaseDownloads = internalAction({
  args: {},
  returns: v.object({ snapshots: v.number() }),
  handler: async (ctx) => {
    const repo = process.env.GITHUB_RELEASES_REPO ?? DEFAULT_REPO;
    const headers: Record<string, string> = {
      accept: "application/vnd.github+json",
      "user-agent": "codogotchi-release-poller",
    };
    const token = process.env.GITHUB_TOKEN;
    if (token) headers.authorization = `Bearer ${token}`;

    const res = await fetch(
      `https://api.github.com/repos/${repo}/releases?per_page=${PER_PAGE}`,
      { headers },
    );
    if (!res.ok) {
      // Throwing surfaces the failure in the Convex logs and lets the next
      // scheduled run retry; a partial write would corrupt the diff series.
      throw new Error(
        `GitHub releases fetch failed: ${res.status} ${res.statusText}`,
      );
    }

    const body: unknown = await res.json();
    if (!Array.isArray(body)) {
      throw new Error("GitHub releases response was not an array");
    }
    // Single page, no Link-header following. A full page means older releases
    // were silently dropped from the sample — surface it rather than letting
    // their series flatline unnoticed.
    if (body.length >= PER_PAGE) {
      console.warn(
        `GitHub returned a full page of ${PER_PAGE} releases; older releases are not being sampled. Add pagination.`,
      );
    }

    const rows: {
      tagName: string;
      assetName: string;
      downloadCount: number;
    }[] = [];
    for (const release of body as GitHubRelease[]) {
      const tagName = release?.tag_name;
      if (typeof tagName !== "string" || !Array.isArray(release?.assets)) {
        continue;
      }
      for (const asset of release.assets as GitHubAsset[]) {
        const assetName = asset?.name;
        const downloadCount = asset?.download_count;
        if (
          typeof assetName !== "string" ||
          !assetName.endsWith(TRACKED_EXTENSION) ||
          typeof downloadCount !== "number" ||
          !Number.isFinite(downloadCount)
        ) {
          continue;
        }
        rows.push({ tagName, assetName, downloadCount });
      }
    }

    await ctx.runMutation(
      internal.mutations.recordReleaseDownloads.recordReleaseDownloads,
      { rows },
    );
    return { snapshots: rows.length };
  },
});
