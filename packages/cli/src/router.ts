import { randomUUID } from "node:crypto";
import { getCodogotchiHome } from "./config";
import { installHooks } from "./hooks";
import { terminalPrompter } from "./prompts";
import { ConfigExistsError, runSetup } from "./setup";

export type DispatchResult = {
	exitCode: number;
};

export const USAGE = `codogotchi — your terminal tamagotchi

Usage:
  codogotchi <command> [flags]

Commands:
  setup            Interactive first-time setup. Writes ~/.codogotchi/config.json
                   and installs Claude Code + Codex hook entries.
  help, --help     Show this message.

Flags (setup):
  --force          Overwrite an existing ~/.codogotchi/config.json.

Environment:
  CODOGOTCHI_HOME      Override the config root (defaults to ~/.codogotchi).
  CODOGOTCHI_USER_ROOT Override the home dir used for hook installation
                       (defaults to the OS home dir).
`;

function parseSetupFlags(args: string[]): { force: boolean } {
	let force = false;
	for (const arg of args) {
		if (arg === "--force") force = true;
		else if (arg === "--help" || arg === "-h") {
			// fall through; help is handled at top level
		} else {
			throw new Error(`Unknown flag for setup: ${arg}`);
		}
	}
	return { force };
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

	if (command === "setup") {
		const { force } = parseSetupFlags(rest);
		try {
			await runSetup(
				{
					prompter: terminalPrompter(),
					fetch,
					home: getCodogotchiHome(),
					randomUUID: () => randomUUID(),
					installHooks,
				},
				{ force },
			);
			return { exitCode: 0 };
		} catch (err) {
			if (err instanceof ConfigExistsError) {
				process.stderr.write(`${err.message}\n`);
				return { exitCode: 2 };
			}
			throw err;
		}
	}

	process.stderr.write(`Unknown command: ${command}\n${USAGE}`);
	return { exitCode: 1 };
}
