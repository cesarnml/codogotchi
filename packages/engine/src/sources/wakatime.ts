export interface WakatimeHttpResponse {
	ok: boolean;
	status: number;
	headers: Record<string, string>;
	json(): Promise<unknown>;
}

export type WakatimeHttpFetch = (
	url: string,
	init: { headers: Record<string, string> },
) => Promise<WakatimeHttpResponse>;

export interface WakatimeDay {
	date: string;
	hours: number;
}

export interface WakatimeSignalSet {
	days: WakatimeDay[];
	totalHours: number;
	fetchedAt: string;
	error: string | null;
}

export interface ReadWakatimeSignalsOpts {
	apiKey: string;
	since: Date;
	now?: Date;
	http?: WakatimeHttpFetch;
	batchDays?: number;
}

export interface DateRange {
	start: string;
	end: string;
}

const DEFAULT_BATCH_DAYS = 30;
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

function formatDate(d: Date): string {
	return d.toISOString().slice(0, 10);
}

function addDays(d: Date, days: number): Date {
	return new Date(d.getTime() + days * ONE_DAY_MS);
}

export function chunkDateRange(
	since: Date,
	until: Date,
	batchDays: number,
): DateRange[] {
	const ranges: DateRange[] = [];
	let cursor = since;
	while (cursor.getTime() <= until.getTime()) {
		const batchEnd = addDays(cursor, batchDays - 1);
		const end = batchEnd.getTime() > until.getTime() ? until : batchEnd;
		ranges.push({ start: formatDate(cursor), end: formatDate(end) });
		cursor = addDays(end, 1);
	}
	return ranges;
}

function defaultFetch(): WakatimeHttpFetch {
	return async (url, init) => {
		const res = await fetch(url, { headers: init.headers });
		const headers: Record<string, string> = {};
		res.headers.forEach((value, key) => {
			headers[key.toLowerCase()] = value;
		});
		return {
			ok: res.ok,
			status: res.status,
			headers,
			json: () => res.json(),
		};
	};
}

function basicAuthHeader(apiKey: string): string {
	// Wakatime accepts the raw API key in HTTP Basic auth; password is empty.
	const encoded = Buffer.from(apiKey, "utf8").toString("base64");
	return `Basic ${encoded}`;
}

function asObject(v: unknown): Record<string, unknown> | null {
	return typeof v === "object" && v !== null
		? (v as Record<string, unknown>)
		: null;
}

function asNumber(v: unknown): number {
	return typeof v === "number" && Number.isFinite(v) && v > 0 ? v : 0;
}

function asString(v: unknown): string {
	return typeof v === "string" ? v : "";
}

function parseSummaries(body: unknown): WakatimeDay[] {
	const obj = asObject(body);
	if (!obj) return [];
	const data = Array.isArray(obj.data) ? obj.data : [];
	const out: WakatimeDay[] = [];
	for (const entry of data) {
		const item = asObject(entry);
		if (!item) continue;
		const range = asObject(item.range);
		const date = asString(range?.date);
		if (!date) continue;
		const total = asObject(item.grand_total);
		const seconds = asNumber(total?.total_seconds);
		out.push({ date, hours: seconds / 3600 });
	}
	return out;
}

export async function readWakatimeSignals(
	opts: ReadWakatimeSignalsOpts,
): Promise<WakatimeSignalSet> {
	const http = opts.http ?? defaultFetch();
	const now = opts.now ?? new Date();
	const batchDays = opts.batchDays ?? DEFAULT_BATCH_DAYS;
	const fetchedAt = now.toISOString();
	const headers = {
		Authorization: basicAuthHeader(opts.apiKey),
		Accept: "application/json",
		"User-Agent": "codogotchi-source-wakatime",
	};

	const sinceIso = formatDate(opts.since);
	const ranges = chunkDateRange(opts.since, now, batchDays);
	const days: WakatimeDay[] = [];
	let error: string | null = null;

	for (const range of ranges) {
		const url = `https://wakatime.com/api/v1/users/current/summaries?start=${range.start}&end=${range.end}`;
		let res: WakatimeHttpResponse;
		try {
			res = await http(url, { headers });
		} catch (e) {
			error = `network error: ${(e as Error).message}`;
			break;
		}
		if (!res.ok) {
			error = `HTTP ${res.status}`;
			break;
		}
		let body: unknown;
		try {
			body = await res.json();
		} catch {
			error = "invalid JSON in Wakatime response";
			break;
		}
		for (const day of parseSummaries(body)) {
			if (day.date < sinceIso) continue;
			days.push(day);
		}
	}

	const totalHours = days.reduce((sum, d) => sum + d.hours, 0);
	return { days, totalHours, fetchedAt, error };
}
