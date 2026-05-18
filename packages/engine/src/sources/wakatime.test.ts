import { describe, expect, it } from "bun:test";
import {
	chunkDateRange,
	readWakatimeSignals,
	type WakatimeHttpFetch,
	type WakatimeHttpResponse,
} from "./wakatime";

function summariesBody(days: { date: string; seconds: number }[]) {
	return {
		data: days.map((d) => ({
			range: { date: d.date, start: d.date, end: d.date },
			grand_total: {
				total_seconds: d.seconds,
				hours: Math.floor(d.seconds / 3600),
				minutes: Math.floor((d.seconds % 3600) / 60),
			},
		})),
	};
}

function ok(body: unknown): WakatimeHttpResponse {
	return {
		ok: true,
		status: 200,
		headers: {},
		json: async () => body,
	};
}

function err(status: number): WakatimeHttpResponse {
	return {
		ok: false,
		status,
		headers: {},
		json: async () => ({ error: "bad" }),
	};
}

describe("chunkDateRange", () => {
	it("returns a single range when the window fits in one batch", () => {
		const ranges = chunkDateRange(
			new Date("2026-05-10T00:00:00.000Z"),
			new Date("2026-05-15T00:00:00.000Z"),
			30,
		);
		expect(ranges).toEqual([{ start: "2026-05-10", end: "2026-05-15" }]);
	});

	it("splits a larger window into batchDays-sized ranges", () => {
		const ranges = chunkDateRange(
			new Date("2026-01-01T00:00:00.000Z"),
			new Date("2026-04-01T00:00:00.000Z"),
			30,
		);
		// 91 days → ranges of 30 days each, end-inclusive.
		expect(ranges.length).toBe(4);
		expect(ranges[0]?.start).toBe("2026-01-01");
		expect(ranges[ranges.length - 1]?.end).toBe("2026-04-01");
		// Adjacent ranges do not overlap (next start = prev end + 1d).
		for (let i = 1; i < ranges.length; i++) {
			expect(ranges[i]?.start > (ranges[i - 1]?.end ?? "")).toBe(true);
		}
	});
});

describe("readWakatimeSignals", () => {
	const since = new Date("2026-05-11T00:00:00.000Z");
	const now = new Date("2026-05-18T00:00:00.000Z");

	it("aggregates total_seconds into hours per day for a single-batch window", async () => {
		const calls: string[] = [];
		const http: WakatimeHttpFetch = async (url) => {
			calls.push(url);
			return ok(
				summariesBody([
					{ date: "2026-05-15", seconds: 7200 }, // 2h
					{ date: "2026-05-16", seconds: 5400 }, // 1.5h
					{ date: "2026-05-17", seconds: 0 },
				]),
			);
		};
		const result = await readWakatimeSignals({
			apiKey: "wak_test",
			since,
			now,
			http,
		});
		expect(result.error).toBeNull();
		expect(result.days.length).toBe(3);
		expect(result.days.find((d) => d.date === "2026-05-15")?.hours).toBe(2);
		expect(result.days.find((d) => d.date === "2026-05-16")?.hours).toBe(1.5);
		expect(result.totalHours).toBe(3.5);
		// Single call within batch size; URL includes start + end.
		expect(calls.length).toBe(1);
		expect(calls[0]).toContain("start=2026-05-11");
		expect(calls[0]).toContain("end=2026-05-18");
	});

	it("returns an empty result with error=null on an empty window", async () => {
		const http: WakatimeHttpFetch = async () => ok(summariesBody([]));
		const result = await readWakatimeSignals({
			apiKey: "k",
			since,
			now,
			http,
		});
		expect(result.error).toBeNull();
		expect(result.days).toEqual([]);
		expect(result.totalHours).toBe(0);
	});

	it("splits multi-month ranges into batched calls", async () => {
		const calls: string[] = [];
		const http: WakatimeHttpFetch = async (url) => {
			calls.push(url);
			return ok(summariesBody([{ date: "2026-04-01", seconds: 3600 }]));
		};
		await readWakatimeSignals({
			apiKey: "k",
			since: new Date("2026-01-01T00:00:00.000Z"),
			now: new Date("2026-04-01T00:00:00.000Z"),
			http,
			batchDays: 30,
		});
		expect(calls.length).toBe(4);
	});

	it("returns the partial result with error set when one batch fails", async () => {
		let batch = 0;
		const http: WakatimeHttpFetch = async () => {
			batch++;
			if (batch === 2) return err(502);
			return ok(summariesBody([{ date: "2026-01-15", seconds: 3600 }]));
		};
		const result = await readWakatimeSignals({
			apiKey: "k",
			since: new Date("2026-01-01T00:00:00.000Z"),
			now: new Date("2026-04-01T00:00:00.000Z"),
			http,
			batchDays: 30,
		});
		// One successful batch in, second 502s, remaining batches are skipped.
		expect(result.error).not.toBeNull();
		expect(result.error).toContain("502");
		expect(result.days.length).toBe(1);
		expect(result.totalHours).toBe(1);
	});

	it("uses Basic auth with the apiKey, never throws on thrown fetch", async () => {
		const http: WakatimeHttpFetch = async () => {
			throw new Error("network down");
		};
		const result = await readWakatimeSignals({
			apiKey: "k",
			since,
			now,
			http,
		});
		expect(result.error).not.toBeNull();
		expect(result.days).toEqual([]);
		expect(result.totalHours).toBe(0);
	});

	it("attaches the Basic auth header with the apiKey", async () => {
		let seenAuth: string | undefined;
		const http: WakatimeHttpFetch = async (_url, init) => {
			seenAuth = init.headers.Authorization;
			return ok(summariesBody([]));
		};
		await readWakatimeSignals({
			apiKey: "secret_abc",
			since,
			now,
			http,
		});
		expect(seenAuth).toBeDefined();
		expect(seenAuth?.startsWith("Basic ")).toBe(true);
		const decoded = Buffer.from(
			(seenAuth ?? "").slice("Basic ".length),
			"base64",
		).toString("utf8");
		expect(decoded).toBe("secret_abc");
	});

	it("filters out days that fall before `since`", async () => {
		const http: WakatimeHttpFetch = async () =>
			ok(
				summariesBody([
					{ date: "2026-05-10", seconds: 9999 }, // before since
					{ date: "2026-05-15", seconds: 3600 },
				]),
			);
		const result = await readWakatimeSignals({
			apiKey: "k",
			since: new Date("2026-05-11T00:00:00.000Z"),
			now: new Date("2026-05-18T00:00:00.000Z"),
			http,
		});
		expect(result.days.length).toBe(1);
		expect(result.days[0]?.date).toBe("2026-05-15");
	});
});
