import { DEFAULT_HEALTH_CONFIG } from "@codogotchi/engine";
import {
  type CodogotchiConfig,
  configExists,
  configPath,
  readConfig,
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
};

// ---------------------------------------------------------------------------
// Lite setup (codogotchi setup)
// ---------------------------------------------------------------------------

export type LiteSetupDeps = {
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

/**
 * Lite (non-interactive) setup. Writes a minimal config with rpg_enabled=false
 * and installs hooks. No prompts, no Convex registration.
 */
export async function runSetup(
  deps: LiteSetupDeps,
  opts: SetupOptions = {},
): Promise<SetupResult> {
  const filePath = configPath(deps.home);
  if ((await configExists(deps.home)) && !opts.force) {
    throw new ConfigExistsError(filePath);
  }

  const profile_id = deps.randomUUID();
  const config: CodogotchiConfig = {
    profile_id,
    pet: "maew",
    features: { rpg_enabled: false },
  };

  // Write config first so installHooks can verify it exists
  await writeConfig(deps.home, config);
  try {
    await deps.installHooks({ home: deps.home });
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(
      `config written but hooks installation failed — run \`codogotchi hooks install\` to complete setup\n${detail}`,
    );
  }

  return { config, configPath: filePath };
}

// ---------------------------------------------------------------------------
// RPG enrollment (codogotchi rpg)
// ---------------------------------------------------------------------------

export type RpgDeps = {
  prompter: Prompter;
  fetch: typeof fetch;
  home: string;
  randomUUID: () => string;
};

export type RpgOptions = {
  force?: boolean;
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
      `No ${label} provided. ${label}-derived XP will be unavailable until you re-run \`codogotchi rpg --force\`.`,
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
    "Merged-PR signals need both GitHub username and PAT together. Skipping either leaves github PR XP off until both are set (e.g. `codogotchi config set …` or `codogotchi rpg --force`).",
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

/**
 * Interactive Alive enrollment (codogotchi rpg). Prompts for handle, Convex
 * URL, optional GitHub/Wakatime, registers with Convex, and writes an RPG
 * config. Allows upgrading a Lite config to RPG; refuses to overwrite an
 * existing RPG config without --force.
 */
export async function runRpg(
  deps: RpgDeps,
  opts: RpgOptions = {},
): Promise<SetupResult> {
  const { prompter, fetch: doFetch, home, randomUUID } = deps;

  const filePath = configPath(home);

  // Allow Lite→RPG upgrade; only block RPG→RPG without force
  if (await configExists(home)) {
    const existing = await readConfig(home);
    if (existing?.features.rpg_enabled === true && !opts.force) {
      throw new ConfigExistsError(filePath);
    }
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
    pet: "maew",
    features: { rpg_enabled: true },
    handle,
    github_username,
    github_token,
    wakatime_key,
    convex_http_url,
    health,
  };

  // Register profile with Convex before persisting config so a failure
  // does not leave a config.json that blocks a retry.
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

  await writeConfig(home, config);

  prompter.notice(
    `Setup complete for ${handle}. Config written to ${filePath}. Secrets are stored in plain JSON on this machine only.`,
  );

  return { config, configPath: filePath };
}
