import { DEFAULT_HEALTH_CONFIG } from "@codogotchi/engine";
import {
  type CodogotchiConfig,
  configExists,
  configPath,
  writeConfig,
} from "./config";
import type { Prompter } from "./prompts";

export class ConfigExistsError extends Error {
  constructor(public readonly configFilePath: string) {
    super(
      `config already exists at ${configFilePath}; pass --force to overwrite`,
    );
    this.name = "ConfigExistsError";
  }
}

export type InstallHooksContext = {
  home: string;
  convex_http_url: string;
};

export type SetupDeps = {
  prompter: Prompter;
  fetch: typeof fetch;
  home: string;
  randomUUID: () => string;
  installHooks: (ctx: InstallHooksContext) => Promise<void>;
};

export type SetupOptions = {
  force?: boolean;
};

export type SetupResult = {
  config: CodogotchiConfig;
  configPath: string;
};

const HANDLE_PATTERN = /^[a-zA-Z0-9-]{1,40}$/;

async function promptHandle(prompter: Prompter): Promise<string> {
  for (;;) {
    const answer = (
      await prompter.ask("Handle (alphanumeric + dash): ")
    ).trim();
    if (HANDLE_PATTERN.test(answer)) return answer;
    prompter.notice(
      "Invalid handle. Use 1-40 characters: letters, numbers, or dashes.",
    );
  }
}

async function promptOptionalSecret(
  prompter: Prompter,
  label: string,
  question: string,
): Promise<string | null> {
  const raw = (await prompter.ask(question)).trim();
  if (raw.length === 0) {
    prompter.notice(
      `No ${label} provided. ${label}-derived XP will be unavailable until you re-run \`codogotchi setup --force\`.`,
    );
    return null;
  }
  return raw;
}

/** GitHub PR signals require both username and PAT. */
async function promptGithubPair(
  prompter: Prompter,
): Promise<{ github_username: string | null; github_token: string | null }> {
  const rawUser = (
    await prompter.ask("GitHub username (press Enter to skip): ")
  ).trim();
  const rawToken = (
    await prompter.ask("GitHub Personal Access Token (press Enter to skip): ")
  ).trim();

  const github_username = rawUser.length > 0 ? rawUser : null;
  const github_token = rawToken.length > 0 ? rawToken : null;

  if (github_username !== null && github_token !== null) {
    return { github_username, github_token };
  }

  prompter.notice(
    "Merged-PR signals need both GitHub username and PAT together. Skipping either leaves github PR XP off until both are set (e.g. `codogotchi config set …` or `codogotchi setup --force`).",
  );
  return { github_username, github_token };
}

async function promptConvexUrl(prompter: Prompter): Promise<string> {
  for (;;) {
    const raw = (
      await prompter.ask("Convex HTTP action URL (https://...convex.site): ")
    ).trim();
    try {
      const parsed = new URL(raw);
      if (parsed.protocol !== "https:") {
        prompter.notice("Convex URL must use https://.");
        continue;
      }
      return raw.replace(/\/+$/, "");
    } catch {
      prompter.notice("Invalid URL. Try again.");
    }
  }
}

export async function runSetup(
  deps: SetupDeps,
  opts: SetupOptions = {},
): Promise<SetupResult> {
  const { prompter, fetch: doFetch, home, randomUUID, installHooks } = deps;

  const filePath = configPath(home);
  if ((await configExists(home)) && !opts.force) {
    throw new ConfigExistsError(filePath);
  }

  const handle = await promptHandle(prompter);
  const profile_id = randomUUID();
  const { github_username, github_token } = await promptGithubPair(prompter);
  const wakatime_key = await promptOptionalSecret(
    prompter,
    "Wakatime",
    "Wakatime API key (press Enter to skip): ",
  );
  const convex_http_url = await promptConvexUrl(prompter);

  const health = { ...DEFAULT_HEALTH_CONFIG };

  const config: CodogotchiConfig = {
    profile_id,
    handle,
    github_username,
    github_token,
    wakatime_key,
    convex_http_url,
    health,
  };

  // Run registration and hook install BEFORE persisting config so a failure
  // in either step does not leave a `config.json` on disk that would block a
  // retry with `ConfigExistsError`. Config write is the last side effect.
  const syncBody = {
    profile_id,
    handle,
    signals: {
      claude: null,
      codex: null,
      github: null,
      wakatime: null,
    },
    config: health,
    now: new Date().toISOString(),
  };

  const response = await doFetch(`${convex_http_url}/sync`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(syncBody),
  });
  if (!response.ok) {
    throw new Error(
      `Convex /sync registration failed: ${response.status} ${response.statusText}`,
    );
  }

  await installHooks({ home, convex_http_url });

  await writeConfig(home, config);

  prompter.notice(
    `Setup complete for ${handle}. Config written to ${filePath}. Secrets are stored in plain JSON on this machine only.`,
  );

  return { config, configPath: filePath };
}
