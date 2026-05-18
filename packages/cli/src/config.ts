import { homedir } from "node:os";
import { join } from "node:path";
import type { HealthConfigPayload } from "@codogotchi/contracts";

export type CodogotchiConfig = {
	profile_id: string;
	handle: string;
	github_token: string | null;
	wakatime_key: string | null;
	convex_http_url: string;
	health: HealthConfigPayload;
};

export function getCodogotchiHome(
	env: NodeJS.ProcessEnv = process.env,
): string {
	const override = env.CODOGOTCHI_HOME;
	if (override && override.length > 0) return override;
	return join(homedir(), ".codogotchi");
}

export function configPath(home: string): string {
	return join(home, "config.json");
}

export async function configExists(home: string): Promise<boolean> {
	throw new Error("not implemented");
}

export async function readConfig(
	home: string,
): Promise<CodogotchiConfig | null> {
	throw new Error("not implemented");
}

export async function writeConfig(
	home: string,
	config: CodogotchiConfig,
): Promise<void> {
	throw new Error("not implemented");
}
