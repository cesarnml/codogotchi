import { runAdd } from "./add-command";
import { getCodogotchiHome } from "./config";
import { runStatus } from "./status";
import { CLI_VERSION } from "./version";

// The production Convex HTTP URL.  Override with CODOGOTCHI_API_URL for testing
// or self-hosting.
const DEFAULT_API_URL = "https://careful-bat-587.convex.site";

export type DispatchResult = { exitCode: number };

const NPM_USAGE = `codogotchi — install pets from the Codogotchi marketplace

Usage:
  codogotchi add <pet-id> [--force]
  codogotchi status
  codogotchi version

Commands:
  add <pet-id>   Download and install a pet from the marketplace.
                 Existing files are left intact unless --force is passed.
  status         Print the cached pet profile and HP.
  version, --version, -v
                 Print the version.

Environment:
  CODOGOTCHI_HOME      Override the install root (defaults to ~/.codogotchi).
  CODOGOTCHI_API_URL   Override the marketplace API URL.
`;

export async function dispatchNpm(argv: string[]): Promise<DispatchResult> {
  const [command, ...rest] = argv;

  if (
    !command ||
    command === "help" ||
    command === "--help" ||
    command === "-h"
  ) {
    process.stdout.write(NPM_USAGE);
    return { exitCode: command ? 0 : 1 };
  }

  if (command === "--version" || command === "-v" || command === "version") {
    process.stdout.write(`${CLI_VERSION}\n`);
    return { exitCode: 0 };
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

  if (command === "add") {
    const petId = rest.find((a) => !a.startsWith("-"));
    const force = rest.includes("--force");
    if (!petId) {
      process.stderr.write("Usage: codogotchi add <pet-id> [--force]\n");
      return { exitCode: 2 };
    }
    const apiUrl = process.env.CODOGOTCHI_API_URL?.trim() || DEFAULT_API_URL;
    const result = await runAdd(
      { home: getCodogotchiHome(), fetch, apiUrl },
      { petId, force },
    );
    if (!result.ok) {
      process.stderr.write(`${result.message}\n`);
      return { exitCode: result.code === "not_found" ? 2 : 1 };
    }
    process.stdout.write(
      `Pet '${petId}' installed.\nOpen Codogotchi.app → Settings → Pet to switch to this pet.\n`,
    );
    return { exitCode: 0 };
  }

  process.stderr.write(`Unknown command: ${command}\n${NPM_USAGE}`);
  return { exitCode: 1 };
}
