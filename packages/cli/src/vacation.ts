import { type CodogotchiConfig, readConfig } from "./config";
import { ConfigCommandError, configSet } from "./config-command";

export type VacationDeps = {
	home: string;
	now: () => Date;
};

export type VacationOnOptions = {
	until?: string;
};

export const VACATION_DEFAULT_DAYS = 30;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function validateIsoDateOnly(raw: string): string {
	if (!ISO_DATE_RE.test(raw)) {
		throw new ConfigCommandError(
			`Expected YYYY-MM-DD, got ${JSON.stringify(raw)}.`,
		);
	}
	const t = Date.parse(`${raw}T00:00:00Z`);
	if (Number.isNaN(t)) {
		throw new ConfigCommandError(`Invalid date: ${raw}`);
	}
	const d = new Date(t);
	const formatted = `${d.getUTCFullYear()}-${String(
		d.getUTCMonth() + 1,
	).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
	if (formatted !== raw) {
		throw new ConfigCommandError(`Invalid calendar date: ${raw}`);
	}
	return d.toISOString();
}

function defaultUntil(now: Date, days: number): string {
	return new Date(now.getTime() + days * MS_PER_DAY).toISOString();
}

export async function vacationOn(
	deps: VacationDeps,
	opts: VacationOnOptions = {},
): Promise<string> {
	const iso =
		opts.until !== undefined
			? validateIsoDateOnly(opts.until)
			: defaultUntil(deps.now(), VACATION_DEFAULT_DAYS);
	await configSet({
		home: deps.home,
		path: "health.vacation_until",
		value: iso,
	});
	return `vacation on until ${iso}\n`;
}

export async function vacationOff(deps: VacationDeps): Promise<string> {
	await configSet({
		home: deps.home,
		path: "health.vacation_until",
		value: "null",
	});
	return "vacation off\n";
}

function daysRemaining(now: Date, untilIso: string): number {
	const t = Date.parse(untilIso);
	if (Number.isNaN(t)) return 0;
	return Math.max(0, Math.ceil((t - now.getTime()) / MS_PER_DAY));
}

export async function vacationStatus(deps: VacationDeps): Promise<string> {
	const config = (await readConfig(deps.home)) as CodogotchiConfig | null;
	if (!config) {
		throw new ConfigCommandError(
			"codogotchi: no config found. Run `codogotchi setup` first.",
			2,
		);
	}
	const until = config.health.vacation_until;
	if (until === null) return "vacation off\n";
	return `vacation on until ${until} (${daysRemaining(deps.now(), until)} days remaining)\n`;
}
