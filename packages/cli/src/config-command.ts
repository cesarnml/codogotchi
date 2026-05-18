import type { CodogotchiConfigShape } from "@codogotchi/contracts";

export class ConfigCommandError extends Error {
	constructor(
		message: string,
		public readonly exitCode = 1,
	) {
		super(message);
		this.name = "ConfigCommandError";
	}
}

export type ConfigGetOptions = { home: string; path: string };
export type ConfigSetOptions = { home: string; path: string; value: string };
export type ConfigListOptions = { home: string };

export async function configGet(_opts: ConfigGetOptions): Promise<string> {
	throw new Error("not implemented");
}

export async function configSet(_opts: ConfigSetOptions): Promise<string> {
	throw new Error("not implemented");
}

export async function configList(_opts: ConfigListOptions): Promise<string> {
	throw new Error("not implemented");
}

// Re-export for tests that need the schema type.
export type { CodogotchiConfigShape };
