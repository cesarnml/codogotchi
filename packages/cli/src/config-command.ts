import {
	type CodogotchiConfigShape,
	resolveConfigPath,
	SETTABLE_HEALTH_KEYS,
	SETTABLE_TOP_LEVEL,
} from "@codogotchi/contracts";
import { readConfig, writeConfig } from "./config";

export class ConfigCommandError extends Error {
	constructor(
		message: string,
		public readonly exitCode = 1,
	) {
		super(message);
		this.name = "ConfigCommandError";
	}
}

export type ConfigGetOptions = {
	home: string;
	path: string;
};

export type ConfigSetOptions = {
	home: string;
	path: string;
	value: string;
};

export type ConfigListOptions = {
	home: string;
};

const HEALTH_BOOL_KEYS = new Set(["weekend_decay"]);
const HEALTH_NUMBER_KEYS = new Set([
	"grace_days",
	"decay_per_day",
	"revive_threshold",
	"revive_hp",
]);
const HEALTH_NULLABLE_DATE_KEYS = new Set(["vacation_until"]);
const HEALTH_STRING_KEYS = new Set(["timezone"]);
const TOP_NULLABLE_STRING_KEYS = new Set([
	"github_token",
	"github_username",
	"wakatime_key",
]);
const TOP_REQUIRED_STRING_KEYS = new Set(["handle", "convex_http_url"]);

function parseBool(raw: string): boolean {
	if (raw === "true") return true;
	if (raw === "false") return false;
	throw new ConfigCommandError(
		`Expected boolean (true/false), got ${JSON.stringify(raw)}.`,
	);
}

function parseNumber(raw: string): number {
	const n = Number(raw);
	if (!Number.isFinite(n) || n < 0) {
		throw new ConfigCommandError(
			`Expected non-negative number, got ${JSON.stringify(raw)}.`,
		);
	}
	return n;
}

function parseNullableDate(raw: string): string | null {
	if (raw === "null" || raw === "") return null;
	const t = Date.parse(raw);
	if (Number.isNaN(t)) {
		throw new ConfigCommandError(
			`Expected ISO date string or "null", got ${JSON.stringify(raw)}.`,
		);
	}
	return new Date(t).toISOString();
}

function parseNullableString(raw: string): string | null {
	if (raw === "null") return null;
	if (raw.length === 0) {
		throw new ConfigCommandError(
			"Empty string is not allowed; use 'null' to clear.",
		);
	}
	return raw;
}

function parseUrl(raw: string): string {
	try {
		const u = new URL(raw);
		if (u.protocol !== "https:") {
			throw new ConfigCommandError("convex_http_url must use https://.");
		}
		return raw.replace(/\/+$/, "");
	} catch (err) {
		if (err instanceof ConfigCommandError) throw err;
		throw new ConfigCommandError(`Invalid URL: ${raw}`);
	}
}

async function loadOrFail(home: string): Promise<CodogotchiConfigShape> {
	const config = await readConfig(home);
	if (!config) {
		throw new ConfigCommandError(
			"codogotchi: no config found. Run `codogotchi setup` first.",
			2,
		);
	}
	return config as CodogotchiConfigShape;
}

function getDottedValue(config: CodogotchiConfigShape, path: string): unknown {
	if (path.startsWith("health.")) {
		const rest = path.slice("health.".length);
		if (!(SETTABLE_HEALTH_KEYS as readonly string[]).includes(rest)) {
			throw new ConfigCommandError(`Unknown config key: ${path}`);
		}
		return (config.health as Record<string, unknown>)[rest];
	}
	if (path === "profile_id" || path === "handle") {
		return (config as Record<string, unknown>)[path];
	}
	if ((SETTABLE_TOP_LEVEL as readonly string[]).includes(path)) {
		return (config as Record<string, unknown>)[path];
	}
	throw new ConfigCommandError(`Unknown config key: ${path}`);
}

function applyTopLevelValue(
	config: CodogotchiConfigShape,
	key: string,
	raw: string,
): CodogotchiConfigShape {
	const next: CodogotchiConfigShape = { ...config };
	if (TOP_NULLABLE_STRING_KEYS.has(key)) {
		(next as Record<string, unknown>)[key] = parseNullableString(raw);
		return next;
	}
	if (key === "convex_http_url") {
		next.convex_http_url = parseUrl(raw);
		return next;
	}
	if (TOP_REQUIRED_STRING_KEYS.has(key)) {
		if (raw.length === 0) {
			throw new ConfigCommandError(`${key} cannot be empty.`);
		}
		(next as Record<string, unknown>)[key] = raw;
		return next;
	}
	throw new ConfigCommandError(`Unknown config key: ${key}`);
}

function applyHealthValue(
	config: CodogotchiConfigShape,
	key: string,
	raw: string,
): CodogotchiConfigShape {
	const nextHealth = { ...config.health };
	if (HEALTH_BOOL_KEYS.has(key)) {
		(nextHealth as Record<string, unknown>)[key] = parseBool(raw);
	} else if (HEALTH_NUMBER_KEYS.has(key)) {
		(nextHealth as Record<string, unknown>)[key] = parseNumber(raw);
	} else if (HEALTH_NULLABLE_DATE_KEYS.has(key)) {
		(nextHealth as Record<string, unknown>)[key] = parseNullableDate(raw);
	} else if (HEALTH_STRING_KEYS.has(key)) {
		if (raw.length === 0) {
			throw new ConfigCommandError(`${key} cannot be empty.`);
		}
		(nextHealth as Record<string, unknown>)[key] = raw;
	} else {
		throw new ConfigCommandError(`Unknown health key: ${key}`);
	}
	return { ...config, health: nextHealth };
}

export async function configGet(opts: ConfigGetOptions): Promise<string> {
	const config = await loadOrFail(opts.home);
	const raw = getDottedValue(config, opts.path);
	// Normalize `undefined` to `null` so optional fields absent from older
	// configs (e.g. `github_username`) never render as the literal string
	// "undefined" — that would be both confusing and lossy.
	const value = raw === undefined ? null : raw;
	return typeof value === "string"
		? `${value}\n`
		: `${JSON.stringify(value)}\n`;
}

export async function configSet(opts: ConfigSetOptions): Promise<string> {
	const config = await loadOrFail(opts.home);
	const resolved = resolveConfigPath(opts.path);
	if (resolved === null) {
		throw new ConfigCommandError(
			`Unknown or read-only config key: ${opts.path}`,
		);
	}
	const next =
		resolved.kind === "top"
			? applyTopLevelValue(config, resolved.key, opts.value)
			: applyHealthValue(config, resolved.key, opts.value);
	await writeConfig(opts.home, next);
	return `${opts.path}=${
		typeof getDottedValue(next, opts.path) === "string"
			? getDottedValue(next, opts.path)
			: JSON.stringify(getDottedValue(next, opts.path))
	}\n`;
}

export async function configList(opts: ConfigListOptions): Promise<string> {
	const config = await loadOrFail(opts.home);
	const redacted: CodogotchiConfigShape & Record<string, unknown> = {
		...config,
		github_token:
			config.github_token === null ? null : ("<set>" as unknown as null),
		wakatime_key:
			config.wakatime_key === null ? null : ("<set>" as unknown as null),
	};
	return `${JSON.stringify(redacted, null, 2)}\n`;
}
