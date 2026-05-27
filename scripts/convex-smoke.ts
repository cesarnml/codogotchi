#!/usr/bin/env bun
// Post-deploy smoke test for the Convex `/sync` HTTP action.
//
// Usage:
//   CODOGOTCHI_CONVEX_URL=https://<deployment>.convex.site bun scripts/convex-smoke.ts
//   bun scripts/convex-smoke.ts --url https://<deployment>.convex.site
//
// Exits 0 on success, non-zero on any assertion failure. POSTs synthetic
// payloads for two distinct profile UUIDs and asserts:
//   - both responses are 200 with the expected envelope shape
//   - per-source XP totals differ between the two profiles (no bleed)
//   - new_loot_events on each response carry the correct profile_id

type SmokeResponse = {
  profile: {
    profile_id: string;
    handle: string;
    total_xp: number;
    stage: number;
    hp: number;
    mood: string;
    xp_by_source: {
      claude_code: number;
      codex: number;
      github: number;
      wakatime: number;
    };
  };
  new_loot_events: { profile_id: string; tier: string; source: string }[];
};

function parseUrl(argv: string[]): string {
  const flagIdx = argv.indexOf("--url");
  if (flagIdx !== -1 && argv[flagIdx + 1]) {
    return argv[flagIdx + 1] as string;
  }
  const envUrl = process.env.CODOGOTCHI_CONVEX_URL;
  if (envUrl) return envUrl;
  console.error(
    "error: set CODOGOTCHI_CONVEX_URL or pass --url <https://...convex.site>",
  );
  process.exit(2);
}

function payload(profileId: string, handle: string, claudeTokens: number) {
  return {
    profile_id: profileId,
    handle,
    signals: {
      claude: { tokens: claudeTokens },
      codex: null,
      github: null,
      wakatime: null,
    },
    config: {
      weekend_decay: false,
      grace_days: 2,
      vacation_until: null,
      timezone: "UTC",
      decay_per_day: 5,
      revive_threshold: 100,
      revive_hp: 50,
    },
    now: new Date().toISOString(),
  };
}

async function postSync(
  siteUrl: string,
  body: ReturnType<typeof payload>,
): Promise<SmokeResponse> {
  const url = `${siteUrl.replace(/\/$/, "")}/sync`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  if (res.status !== 200) {
    const text = await res.text();
    throw new Error(
      `POST /sync for ${body.profile_id} → HTTP ${res.status}: ${text}`,
    );
  }
  return (await res.json()) as SmokeResponse;
}

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(`assertion failed: ${msg}`);
}

async function main() {
  const siteUrl = parseUrl(process.argv.slice(2));
  const uuidA = `smoke-a-${Math.floor(Date.now() / 1000)}`;
  const uuidB = `smoke-b-${Math.floor(Date.now() / 1000)}`;

  console.log(`[smoke] target: ${siteUrl}`);
  console.log(`[smoke] profile A: ${uuidA}`);
  console.log(`[smoke] profile B: ${uuidB}`);

  const a = await postSync(siteUrl, payload(uuidA, "smoke-alice", 12_345));
  const b = await postSync(siteUrl, payload(uuidB, "smoke-bob", 67_890));

  assert(a.profile.profile_id === uuidA, "profile A id round-trips");
  assert(b.profile.profile_id === uuidB, "profile B id round-trips");
  assert(
    a.profile.xp_by_source.claude_code === 12_345,
    `profile A claude_code XP === 12345 (got ${a.profile.xp_by_source.claude_code})`,
  );
  assert(
    b.profile.xp_by_source.claude_code === 67_890,
    `profile B claude_code XP === 67890 (got ${b.profile.xp_by_source.claude_code})`,
  );
  assert(
    a.profile.xp_by_source.claude_code !== b.profile.xp_by_source.claude_code,
    "two profiles report independent XP totals (no cross-bleed)",
  );
  for (const ev of a.new_loot_events) {
    assert(
      ev.profile_id === uuidA,
      `loot event on response A is tagged with profile A (got ${ev.profile_id})`,
    );
  }
  for (const ev of b.new_loot_events) {
    assert(
      ev.profile_id === uuidB,
      `loot event on response B is tagged with profile B (got ${ev.profile_id})`,
    );
  }

  console.log(
    `[smoke] OK — A total_xp=${a.profile.total_xp} (${a.new_loot_events.length} loot), B total_xp=${b.profile.total_xp} (${b.new_loot_events.length} loot)`,
  );
}

main().catch((err: unknown) => {
  console.error(`[smoke] FAILED: ${err instanceof Error ? err.message : err}`);
  process.exit(1);
});
