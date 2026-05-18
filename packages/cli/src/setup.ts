import type { CodogotchiConfig } from "./config";
import type { Prompter } from "./prompts";

export class ConfigExistsError extends Error {
	constructor(public readonly path: string) {
		super(`config already exists at ${path}; pass --force to overwrite`);
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

export async function runSetup(
	_deps: SetupDeps,
	_opts: SetupOptions = {},
): Promise<SetupResult> {
	throw new Error("not implemented");
}
