import { describe, expect, it } from 'bun:test';

import type { AiReviewFetcherResult } from '../types';
import { buildStandaloneReviewStartedEvent } from '../pr-metadata';
import {
  DEFAULT_REVIEW_POLLING_PROFILE,
  pollForAiReview,
  runAiReviewLifecycleWithAdapters,
  type ReviewPollingProfile,
} from '../review';
import type { TicketReviewDependencies } from '../review';

function emptyUndetected(): AiReviewFetcherResult {
  return {
    agents: [],
    comments: [],
    detected: false,
    vendors: [],
  };
}

function inFlight(): AiReviewFetcherResult {
  return {
    agents: [
      {
        agent: 'external',
        state: 'started',
        findingsCount: undefined,
        note: undefined,
      },
    ],
    comments: [],
    detected: true,
    vendors: [],
  };
}

function allTerminal(): AiReviewFetcherResult {
  return {
    agents: [
      {
        agent: 'external',
        state: 'completed',
        findingsCount: 0,
        note: undefined,
      },
    ],
    comments: [],
    detected: true,
    vendors: [],
  };
}

function baseDeps(
  overrides: Partial<TicketReviewDependencies> & {
    fetcher: TicketReviewDependencies['fetcher'];
  },
): TicketReviewDependencies {
  return {
    relativeToRepo: (cwd, p) => p,
    resolveReviewFetcher: () => 'fetcher',
    resolveReviewThread: () => '{"resolved":true}',
    resolveReviewTriager: () => 'triager',
    runProcess: () => '',
    ...overrides,
  };
}

describe('pollForAiReview', () => {
  it('extends the polling window to 12 minutes only when agents are still in flight at the 10-minute check', async () => {
    let virtualNow = 0;
    let pollCalls = 0;
    const profile: ReviewPollingProfile = {
      intervalMinutes: 2,
      maxWaitMinutes: 10,
      extendByOneInterval: true,
    };

    const result = await pollForAiReview(
      '/wt',
      1,
      profile,
      0,
      baseDeps({
        fetcher: () => {
          pollCalls += 1;
          if (pollCalls < 5) {
            return emptyUndetected();
          }
          if (pollCalls === 5) {
            return inFlight();
          }
          return inFlight();
        },
        now: () => virtualNow,
        sleep: async (ms: number) => {
          virtualNow += ms;
        },
      }),
    );

    expect(result.status).toBe('clean_timeout');
    if (result.status !== 'clean_timeout') {
      throw new Error('expected clean_timeout');
    }
    expect(result.effectiveMaxWaitMinutes).toBe(12);
    expect(result.incompleteAgents).toEqual(['external']);
    expect(pollCalls).toBe(6);
  });

  it('does not extend when triage becomes ready by the 10-minute check', async () => {
    let virtualNow = 0;
    let pollCalls = 0;
    const profile: ReviewPollingProfile = {
      intervalMinutes: 2,
      maxWaitMinutes: 10,
      extendByOneInterval: true,
    };

    const result = await pollForAiReview(
      '/wt',
      1,
      profile,
      0,
      baseDeps({
        fetcher: () => {
          pollCalls += 1;
          if (pollCalls < 5) {
            return emptyUndetected();
          }
          return allTerminal();
        },
        now: () => virtualNow,
        sleep: async (ms: number) => {
          virtualNow += ms;
        },
      }),
    );

    expect(result.status).toBe('triage_ready');
    if (result.status !== 'triage_ready') {
      throw new Error('expected triage_ready');
    }
    expect(result.effectiveMaxWaitMinutes).toBe(10);
    expect(pollCalls).toBe(5);
  });

  it('does not schedule a 12-minute check when extendByOneInterval is false', async () => {
    let virtualNow = 0;
    let pollCalls = 0;
    const profile: ReviewPollingProfile = {
      intervalMinutes: 2,
      maxWaitMinutes: 10,
      extendByOneInterval: false,
    };

    const result = await pollForAiReview(
      '/wt',
      1,
      profile,
      0,
      baseDeps({
        fetcher: () => {
          pollCalls += 1;
          if (pollCalls < 5) {
            return emptyUndetected();
          }
          return inFlight();
        },
        now: () => virtualNow,
        sleep: async (ms: number) => {
          virtualNow += ms;
        },
      }),
    );

    expect(result.status).toBe('clean_timeout');
    expect(result.effectiveMaxWaitMinutes).toBe(10);
    expect(pollCalls).toBe(5);
  });
});

describe('review polling profile wiring', () => {
  it('uses the default profile for standalone review started notifications', () => {
    const event = buildStandaloneReviewStartedEvent(
      42,
      'https://example.test/pull/42',
    );
    expect(event.kind).toBe('standalone_review_started');
    if (event.kind !== 'standalone_review_started') {
      throw new Error('expected standalone_review_started');
    }
    expect(event.reviewPollIntervalMinutes).toBe(
      DEFAULT_REVIEW_POLLING_PROFILE.intervalMinutes,
    );
    expect(event.reviewPollMaxWaitMinutes).toBe(
      DEFAULT_REVIEW_POLLING_PROFILE.maxWaitMinutes,
    );
  });
});

describe('runAiReviewLifecycleWithAdapters', () => {
  it('routes ticketed vs standalone handlers without mixing outcome semantics', async () => {
    type RouteTag = { kind: 'ticketed' | 'standalone'; triaged: boolean };
    let virtualNow = 0;
    let pollCalls = 0;
    const profile: ReviewPollingProfile = {
      intervalMinutes: 2,
      maxWaitMinutes: 10,
      extendByOneInterval: false,
    };

    const ticketed = await runAiReviewLifecycleWithAdapters<RouteTag>({
      profile,
      worktreePath: '/wt',
      prNumber: 1,
      pollWindowStartedAt: 0,
      dependencies: baseDeps({
        fetcher: () => {
          pollCalls += 1;
          if (pollCalls < 5) {
            return emptyUndetected();
          }
          return allTerminal();
        },
        now: () => virtualNow,
        sleep: async (ms: number) => {
          virtualNow += ms;
        },
      }),
      onTriageOrPartial: async () => ({ kind: 'ticketed', triaged: true }),
      onCleanTimeout: async () => ({ kind: 'ticketed', triaged: false }),
    });

    expect(ticketed).toEqual({ kind: 'ticketed', triaged: true });

    virtualNow = 0;
    pollCalls = 0;

    const standalone = await runAiReviewLifecycleWithAdapters<RouteTag>({
      profile,
      worktreePath: '/wt',
      prNumber: 1,
      pollWindowStartedAt: 0,
      dependencies: baseDeps({
        fetcher: () => {
          pollCalls += 1;
          if (pollCalls < 5) {
            return emptyUndetected();
          }
          return allTerminal();
        },
        now: () => virtualNow,
        sleep: async (ms: number) => {
          virtualNow += ms;
        },
      }),
      onTriageOrPartial: async () => ({ kind: 'standalone', triaged: true }),
      onCleanTimeout: async () => ({ kind: 'standalone', triaged: false }),
    });

    expect(standalone).toEqual({ kind: 'standalone', triaged: true });
  });
});
