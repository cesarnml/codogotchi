import { afterEach, beforeEach, describe, expect, it, mock } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { dispatch } from "./router";

describe("router Lite/RPG command guards", () => {
  let home: string;
  let prevHome: string | undefined;
  const stderrChunks: string[] = [];
  let stderrWrite: typeof process.stderr.write;
  let fetchMock: ReturnType<typeof mock>;

  beforeEach(async () => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-lite-rpg-"));
    prevHome = process.env.CODOGOTCHI_HOME;
    process.env.CODOGOTCHI_HOME = home;
    await writeFile(
      join(home, "config.json"),
      `${JSON.stringify(
        {
          profile_id: "11111111-2222-3333-4444-555555555555",
          pet: "maew",
          features: { rpg_enabled: false },
        },
        null,
        2,
      )}\n`,
      "utf8",
    );

    stderrChunks.length = 0;
    stderrWrite = process.stderr.write.bind(process.stderr);
    process.stderr.write = ((chunk: unknown) => {
      stderrChunks.push(String(chunk));
      return true;
    }) as typeof process.stderr.write;

    fetchMock = mock(async () =>
      new Response(
        JSON.stringify({
          profile: {
            profile_id: "11111111-2222-3333-4444-555555555555",
            handle: "ada",
            xp_by_source: {
              claude_code: 0,
              codex: 0,
              github: 0,
              wakatime: 0,
            },
            total_xp: 0,
            stage: 0,
            hp: 100,
            mood: "thriving",
            died_at: null,
            cause: null,
            death_count: 0,
            last_signal_at_by_source: {
              claude_code: null,
              codex: null,
              github: null,
              wakatime: null,
            },
            updated_at: Date.now(),
          },
          new_loot_events: [],
        }),
        { status: 200 },
      ),
    );
    globalThis.fetch = fetchMock as typeof fetch;
  });

  afterEach(() => {
    process.stderr.write = stderrWrite;
    if (prevHome === undefined) delete process.env.CODOGOTCHI_HOME;
    else process.env.CODOGOTCHI_HOME = prevHome;
    rmSync(home, { recursive: true, force: true });
    fetchMock.mockRestore();
  });

  it("refuses RPG commands in Lite mode with guidance to codogotchi rpg", async () => {
    const result = await dispatch(["sync"]);
    expect(result.exitCode).toBe(2);
    expect(stderrChunks.join("")).toContain("codogotchi rpg");
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
