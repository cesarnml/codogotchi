import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// Daily snapshot of GitHub release asset download counts. Daily (rather than
// hourly) keeps the table small and sits far inside GitHub's unauthenticated
// 60-requests/hour limit; download counts are an adoption trend, not a metric
// that needs minute resolution.
crons.daily(
  "poll release download counts",
  { hourUTC: 3, minuteUTC: 0 },
  internal.actions.pollReleaseDownloads.pollReleaseDownloads,
  {},
);

export default crons;
