import { randomUUID } from "node:crypto";
import { ConfigReadError, getCodogotchiHome, readConfig } from "./config";
import {
  ConfigCommandError,
  configGet,
  configList,
  configSet,
} from "./config-command";
import { defaultReaders } from "./default-readers";
import {
  hooksStatus,
  installCursorHooks,
  installHooks,
  installVscodeHooks,
  uninstallCursorHooks,
  uninstallHooks,
  uninstallVscodeHooks,
} from "./hooks";
import { type LootTier, runLoot, TIERS } from "./loot";
import { terminalPrompter } from "./prompts";
import { ConfigExistsError, runRpg, runSetup } from "./setup";
import { runStatus } from "./status";
import { runSync } from "./sync";
import { vacationOff, vacationOn, vacationStatus } from "./vacation";
import { CLI_VERSION } from "./version";

export type DispatchResult = {
  exitCode: number;
};

function ensureRpgEnabled(
  config: Awaited<ReturnType<typeof readConfig>>,
  commandName: string,
):
  | {
      ok: true;
      config: Exclude<Awaited<ReturnType<typeof readConfig>>, null> & {
        features: { rpg_enabled: true };
      };
    }
  | { ok: false; exitCode: 2; message: string } {
  if (!config) {
    return {
      ok: false,
      exitCode: 2,
      message: "codogotchi: no config found. Run `codogotchi setup` first.\n",
    };
  }
  if (config.features.rpg_enabled) return { ok: true, config };
  return {
    ok: false,
    exitCode: 2,
    message: `codogotchi: \`${commandName}\` is unavailable in Lite mode. Run \`codogotchi rpg\` first.\n`,
  };
}

export const USAGE = `codogotchi — your terminal tamagotchi

Usage:
  codogotchi <command> [flags]

Commands:
  rpg              Interactive Alive enrollment. Upgrades a Lite install to full
                   RPG mode: prompts for handle, Convex URL, optional GitHub/
                   Wakatime credentials, registers profile, and writes
                   features.rpg_enabled: true.
  sync             Run one sync cycle: poll each source, POST to Convex, update
                   the local profile cache and append a sync.log entry.
  status           Print the cached profile, HP, current activity, recent loot,
                   and last-sync staleness. Pure cache read; no network calls.
  loot             Print the full loot history from ~/.codogotchi/loot.log.
                   Supports --limit N and --tier <common|uncommon|rare|epic|legendary>.
  config get <key> Print the value at the dotted key (e.g. health.weekend_decay).
  config set <key> <value>
                   Write a typed value at the dotted key. Refuses unknown keys.
  config list      Print the full config as JSON (credentials redacted).
  vacation on [--until YYYY-MM-DD]
                   Pause HP decay until the given date (defaults to 30 days).
  vacation off     Clear vacation_until.
  vacation status  Show current vacation state.
  hooks status     Print hook installation status per platform.
  version, --version, -v
                   Print the codogotchi CLI version.
  help, --help     Show this message.

  Note: setup, hooks install, and hooks uninstall are app-managed commands.
  Use Codogotchi.app → Settings → General to install or remove hooks.
  These commands remain callable for internal use.

Flags (rpg):
  --force          Overwrite an existing ~/.codogotchi/config.json.

Flags (loot):
  --limit N        Keep only the last N events after filtering.
  --tier <tier>    Filter to a single tier.

Environment:
  CODOGOTCHI_HOME      Override the config root (defaults to ~/.codogotchi).
  CODOGOTCHI_USER_ROOT Override the home dir used for hook installation
                       (defaults to the OS home dir).
`;

function parseSetupFlags(
  args: string[],
  commandName = "setup",
): {
  force: boolean;
  help: boolean;
} {
  let force = false;
  let help = false;
  for (const arg of args) {
    if (arg === "--force") force = true;
    else if (arg === "--help" || arg === "-h") help = true;
    else throw new Error(`Unknown flag for ${commandName}: ${arg}`);
  }
  return { force, help };
}

function parseLootFlags(args: string[]): {
  limit?: number;
  tier?: LootTier;
  help: boolean;
} {
  let limit: number | undefined;
  let tier: LootTier | undefined;
  let help = false;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") {
      help = true;
    } else if (arg === "--limit") {
      const v = args[i + 1];
      i += 1;
      if (!v) throw new Error("Missing value for --limit");
      const n = Number(v);
      if (!Number.isInteger(n) || n < 0) {
        throw new Error(`Invalid --limit value: ${v}`);
      }
      limit = n;
    } else if (arg === "--tier") {
      const v = args[i + 1];
      i += 1;
      if (!v) throw new Error("Missing value for --tier");
      if (!(TIERS as readonly string[]).includes(v)) {
        throw new Error(
          `Invalid --tier ${v}; expected one of ${TIERS.join(", ")}`,
        );
      }
      tier = v as LootTier;
    } else {
      throw new Error(`Unknown flag for loot: ${arg}`);
    }
  }
  return { limit, tier, help };
}

type HooksPlatform = "claude_code" | "cursor" | "vscode";

function parseHooksPlatformFlag(args: string[]): {
  platform: HooksPlatform;
  rest: string[];
} {
  let platform: HooksPlatform = "claude_code";
  const rest: string[] = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--platform") {
      const v = args[i + 1];
      i += 1;
      if (v !== "claude_code" && v !== "cursor" && v !== "vscode") {
        throw new Error(
          `Invalid --platform value: ${v ?? "(missing)"}; expected claude_code, cursor, or vscode`,
        );
      }
      platform = v;
    } else {
      rest.push(args[i] as string);
    }
  }
  return { platform, rest };
}

export async function dispatch(argv: string[]): Promise<DispatchResult> {
  const [command, ...rest] = argv;

  if (
    !command ||
    command === "help" ||
    command === "--help" ||
    command === "-h"
  ) {
    process.stdout.write(USAGE);
    return { exitCode: command ? 0 : 1 };
  }

  if (command === "--version" || command === "-v" || command === "version") {
    process.stdout.write(`${CLI_VERSION}\n`);
    return { exitCode: 0 };
  }

  if (command === "setup") {
    const { force, help } = parseSetupFlags(rest);
    if (help) {
      process.stdout.write(USAGE);
      return { exitCode: 0 };
    }
    try {
      await runSetup(
        {
          home: getCodogotchiHome(),
          randomUUID: () => randomUUID(),
          installHooks,
          execPath: process.execPath,
        },
        { force },
      );
      return { exitCode: 0 };
    } catch (err) {
      if (err instanceof ConfigExistsError) {
        process.stderr.write(`${err.message}\n`);
        return { exitCode: 2 };
      }
      if (err instanceof ConfigReadError) {
        process.stderr.write(`${err.message}\n`);
        return { exitCode: err.exitCode };
      }
      throw err;
    }
  }

  if (command === "rpg") {
    const { force, help } = parseSetupFlags(rest, "rpg");
    if (help) {
      process.stdout.write(USAGE);
      return { exitCode: 0 };
    }
    try {
      await runRpg(
        {
          prompter: terminalPrompter(),
          fetch,
          home: getCodogotchiHome(),
          randomUUID: () => randomUUID(),
        },
        { force },
      );
      return { exitCode: 0 };
    } catch (err) {
      if (err instanceof ConfigExistsError) {
        process.stderr.write(`${err.message}\n`);
        return { exitCode: 2 };
      }
      if (err instanceof ConfigReadError) {
        process.stderr.write(`${err.message}\n`);
        return { exitCode: err.exitCode };
      }
      throw err;
    }
  }

  if (command === "sync") {
    const home = getCodogotchiHome();
    const config = await readConfig(home);
    const gate = ensureRpgEnabled(config, "sync");
    if (!gate.ok) {
      process.stderr.write(gate.message);
      return { exitCode: gate.exitCode };
    }
    const result = await runSync({
      home,
      config: gate.config,
      readers: defaultReaders(gate.config),
      fetch,
      now: () => new Date(),
    });
    const summary = [
      `sync ${result.exitCode === 0 ? "ok" : "failed"}`,
      `errors=${result.errors.length}`,
      `new_loot=${result.newLootCount}`,
    ].join(" ");
    process.stdout.write(`${summary}\n`);
    return { exitCode: result.exitCode };
  }

  if (command === "status") {
    const result = await runStatus({
      home: getCodogotchiHome(),
      now: () => new Date(),
    });
    if (result.missingProfile) {
      process.stderr.write(result.output);
      return { exitCode: 2 };
    }
    process.stdout.write(result.output);
    return { exitCode: 0 };
  }

  if (command === "config") {
    const [sub, ...subArgs] = rest;
    try {
      if (sub === "get") {
        if (subArgs.length !== 1) {
          throw new ConfigCommandError("Usage: codogotchi config get <key>");
        }
        const out = await configGet({
          home: getCodogotchiHome(),
          path: subArgs[0],
        });
        process.stdout.write(out);
        return { exitCode: 0 };
      }
      if (sub === "set") {
        if (subArgs.length !== 2) {
          throw new ConfigCommandError(
            "Usage: codogotchi config set <key> <value>",
          );
        }
        const out = await configSet({
          home: getCodogotchiHome(),
          path: subArgs[0],
          value: subArgs[1],
        });
        process.stdout.write(out);
        return { exitCode: 0 };
      }
      if (sub === "list") {
        if (subArgs.length !== 0) {
          throw new ConfigCommandError("Usage: codogotchi config list");
        }
        const out = await configList({ home: getCodogotchiHome() });
        process.stdout.write(out);
        return { exitCode: 0 };
      }
      throw new ConfigCommandError(
        "Usage: codogotchi config <get|set|list> [args]",
      );
    } catch (err) {
      if (err instanceof ConfigCommandError) {
        process.stderr.write(`${err.message}\n`);
        return { exitCode: err.exitCode };
      }
      if (err instanceof ConfigReadError) {
        process.stderr.write(`${err.message}\n`);
        return { exitCode: err.exitCode };
      }
      throw err;
    }
  }

  if (command === "loot") {
    const config = await readConfig(getCodogotchiHome());
    const gate = ensureRpgEnabled(config, "loot");
    if (!gate.ok) {
      process.stderr.write(gate.message);
      return { exitCode: gate.exitCode };
    }
    const parsed = parseLootFlags(rest);
    if (parsed.help) {
      process.stdout.write(USAGE);
      return { exitCode: 0 };
    }
    const result = await runLoot(
      { home: getCodogotchiHome() },
      { limit: parsed.limit, tier: parsed.tier },
    );
    process.stdout.write(result.output);
    return { exitCode: 0 };
  }

  if (command === "vacation") {
    const config = await readConfig(getCodogotchiHome());
    const gate = ensureRpgEnabled(config, "vacation");
    if (!gate.ok) {
      process.stderr.write(gate.message);
      return { exitCode: gate.exitCode };
    }
    const [sub, ...subArgs] = rest;
    try {
      const deps = {
        home: getCodogotchiHome(),
        now: () => new Date(),
      };
      if (sub === "on") {
        let until: string | undefined;
        for (let i = 0; i < subArgs.length; i++) {
          if (subArgs[i] === "--until") {
            until = subArgs[i + 1];
            i += 1;
            if (!until) {
              throw new ConfigCommandError("Missing value for --until");
            }
          } else {
            throw new ConfigCommandError(
              `Unknown arg for vacation on: ${subArgs[i]}`,
            );
          }
        }
        process.stdout.write(await vacationOn(deps, { until }));
        return { exitCode: 0 };
      }
      if (sub === "off") {
        if (subArgs.length !== 0) {
          throw new ConfigCommandError("Usage: codogotchi vacation off");
        }
        process.stdout.write(await vacationOff(deps));
        return { exitCode: 0 };
      }
      if (sub === "status") {
        if (subArgs.length !== 0) {
          throw new ConfigCommandError("Usage: codogotchi vacation status");
        }
        process.stdout.write(await vacationStatus(deps));
        return { exitCode: 0 };
      }
      throw new ConfigCommandError(
        "Usage: codogotchi vacation <on [--until YYYY-MM-DD]|off|status>",
      );
    } catch (err) {
      if (err instanceof ConfigCommandError) {
        process.stderr.write(`${err.message}\n`);
        return { exitCode: err.exitCode };
      }
      if (err instanceof ConfigReadError) {
        process.stderr.write(`${err.message}\n`);
        return { exitCode: err.exitCode };
      }
      throw err;
    }
  }

  if (command === "hooks") {
    const [sub, ...subArgs] = rest;
    if (sub === "install") {
      if (subArgs.includes("--help") || subArgs.includes("-h")) {
        process.stdout.write(
          "Usage: codogotchi hooks install [--platform <claude_code|cursor|vscode>]\n",
        );
        return { exitCode: 0 };
      }
      let platform: HooksPlatform;
      let rest: string[];
      try {
        ({ platform, rest } = parseHooksPlatformFlag(subArgs));
      } catch (err) {
        process.stderr.write(
          `${err instanceof Error ? err.message : String(err)}\n`,
        );
        return { exitCode: 2 };
      }
      if (rest.length > 0) {
        process.stderr.write(
          "Usage: codogotchi hooks install [--platform <claude_code|cursor|vscode>]\n",
        );
        return { exitCode: 2 };
      }
      let config: Awaited<ReturnType<typeof readConfig>>;
      try {
        config = await readConfig(getCodogotchiHome());
      } catch (err) {
        if (err instanceof ConfigReadError) {
          process.stderr.write(`${err.message}\n`);
          return { exitCode: err.exitCode };
        }
        throw err;
      }
      if (!config) {
        process.stderr.write(
          "codogotchi: missing ~/.codogotchi/config.json. Launch the app or run `codogotchi setup` first.\n",
        );
        return { exitCode: 2 };
      }
      if (platform === "cursor") {
        await installCursorHooks({ home: getCodogotchiHome() });
      } else if (platform === "vscode") {
        await installVscodeHooks({ home: getCodogotchiHome() });
      } else {
        await installHooks({
          home: getCodogotchiHome(),
          execPath: process.execPath,
        });
      }
      process.stdout.write("hooks install: ok\n");
      return { exitCode: 0 };
    }
    if (sub === "uninstall") {
      if (subArgs.includes("--help") || subArgs.includes("-h")) {
        process.stdout.write(
          "Usage: codogotchi hooks uninstall [--platform <claude_code|cursor|vscode>]\n",
        );
        return { exitCode: 0 };
      }
      let platform: HooksPlatform;
      let rest: string[];
      try {
        ({ platform, rest } = parseHooksPlatformFlag(subArgs));
      } catch (err) {
        process.stderr.write(
          `${err instanceof Error ? err.message : String(err)}\n`,
        );
        return { exitCode: 2 };
      }
      if (rest.length > 0) {
        process.stderr.write(
          "Usage: codogotchi hooks uninstall [--platform <claude_code|cursor|vscode>]\n",
        );
        return { exitCode: 2 };
      }
      if (platform === "cursor") {
        await uninstallCursorHooks();
      } else if (platform === "vscode") {
        await uninstallVscodeHooks();
      } else {
        await uninstallHooks();
      }
      process.stdout.write("hooks uninstall: ok\n");
      return { exitCode: 0 };
    }
    if (sub === "status") {
      if (subArgs.includes("--help") || subArgs.includes("-h")) {
        process.stdout.write("Usage: codogotchi hooks status [--json]\n");
        return { exitCode: 0 };
      }
      const asJson = subArgs.includes("--json");
      if (subArgs.length > (asJson ? 1 : 0)) {
        process.stderr.write("Usage: codogotchi hooks status [--json]\n");
        return { exitCode: 2 };
      }
      const status = await hooksStatus();
      if (asJson) {
        process.stdout.write(`${JSON.stringify(status, null, 2)}\n`);
      } else {
        const rows = Object.entries(status).map(([name, s]) => {
          const installable = s.installable_in_phase
            ? "installable"
            : "deferred";
          const installed = s.installed ? "installed" : "not-installed";
          const mode =
            s.source_origin !== undefined ? ` (${s.source_origin})` : "";
          return `${name}: ${installed}${mode}, ${installable}`;
        });
        process.stdout.write(`${rows.join("\n")}\n`);
      }
      return { exitCode: 0 };
    }
    process.stderr.write(
      "Usage: codogotchi hooks <install|uninstall|status> [--json]\n",
    );
    return { exitCode: 2 };
  }

  process.stderr.write(`Unknown command: ${command}\n${USAGE}`);
  return { exitCode: 1 };
}
