import { scorePR } from "../loot";

export interface HttpResponse {
	ok: boolean;
	status: number;
	headers: Record<string, string>;
	json(): Promise<unknown>;
}

export type HttpFetch = (
	url: string,
	init: { headers: Record<string, string> },
) => Promise<HttpResponse>;

export interface GithubPRSignal {
	number: number;
	title: string;
	repoFullName: string;
	htmlUrl: string;
	mergedAt: string;
	additions: number;
	deletions: number;
	reviewCommentCount: number;
	score: number;
	scoreExplanation: string;
}

export type FirstSyncCap = "ninety-day" | "last-20";

export interface GithubSignalSet {
	prs: GithubPRSignal[];
	rateLimitHit: boolean;
	capApplied: FirstSyncCap | null;
	fetchedAt: string;
}

export interface ReadGithubSignalsOpts {
	token: string;
	username: string;
	since: Date | null;
	now?: Date;
	http?: HttpFetch;
	concurrency?: number;
	debugLog?: (event: GithubDebugEvent) => void;
}

export type GithubDebugEvent =
	| { kind: "rate_limit_hit"; phase: "search" | "enrichment"; url: string }
	| { kind: "first_sync_cap"; cap: FirstSyncCap; count: number };

const FIRST_SYNC_PER_PAGE = 20;
const SUBSEQUENT_SYNC_PER_PAGE = 100;
const NINETY_DAYS_MS = 90 * 24 * 60 * 60 * 1000;
const DEFAULT_CONCURRENCY = 4;

export function applyFirstSyncCap(input: {
	candidateCount: number;
	perPageLimit: number;
}): FirstSyncCap {
	return input.candidateCount >= input.perPageLimit ? "last-20" : "ninety-day";
}

function defaultFetch(): HttpFetch {
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

function isRateLimited(res: HttpResponse): boolean {
	if (res.status !== 403 && res.status !== 429) return false;
	if (res.headers["x-ratelimit-remaining"] === "0") return true;
	// Secondary rate limit responses use 403 without a 0 remaining counter.
	return true;
}

function formatDate(d: Date): string {
	return d.toISOString().slice(0, 10);
}

function buildSearchUrl(args: {
	username: string;
	mergedSince: string;
	perPage: number;
}): string {
	const q = `is:pr is:merged author:${args.username} merged:>=${args.mergedSince}`;
	const params = new URLSearchParams({
		q,
		sort: "updated",
		order: "desc",
		per_page: String(args.perPage),
	});
	return `https://api.github.com/search/issues?${params.toString()}`;
}

function ghHeaders(token: string): Record<string, string> {
	return {
		Accept: "application/vnd.github+json",
		Authorization: `Bearer ${token}`,
		"X-GitHub-Api-Version": "2022-11-28",
		"User-Agent": "codogotchi-source-github",
	};
}

interface SearchItem {
	number: number;
	title: string;
	pull_request?: { url?: string; html_url?: string };
}

function asObject(v: unknown): Record<string, unknown> | null {
	return typeof v === "object" && v !== null
		? (v as Record<string, unknown>)
		: null;
}

function asNumber(v: unknown): number {
	return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

function asString(v: unknown, fallback = ""): string {
	return typeof v === "string" ? v : fallback;
}

function parseSearchItems(body: unknown): SearchItem[] {
	const obj = asObject(body);
	if (!obj) return [];
	const items = Array.isArray(obj.items) ? obj.items : [];
	const out: SearchItem[] = [];
	for (const raw of items) {
		const item = asObject(raw);
		if (!item) continue;
		const pr = asObject(item.pull_request);
		if (!pr) continue;
		out.push({
			number: asNumber(item.number),
			title: asString(item.title),
			pull_request: {
				url: pr.url ? String(pr.url) : undefined,
				html_url: pr.html_url ? String(pr.html_url) : undefined,
			},
		});
	}
	return out;
}

interface EnrichedPR {
	number: number;
	title: string;
	repoFullName: string;
	htmlUrl: string;
	mergedAt: string;
	additions: number;
	deletions: number;
	reviewCommentCount: number;
}

function parsePRDetail(body: unknown): EnrichedPR | null {
	const obj = asObject(body);
	if (!obj) return null;
	const base = asObject(obj.base);
	const repo = base ? asObject(base.repo) : null;
	return {
		number: asNumber(obj.number),
		title: asString(obj.title),
		repoFullName: asString(repo?.full_name),
		htmlUrl: asString(obj.html_url),
		mergedAt: asString(obj.merged_at),
		additions: asNumber(obj.additions),
		deletions: asNumber(obj.deletions),
		reviewCommentCount: asNumber(obj.review_comments),
	};
}

async function runConcurrent<T, R>(
	items: T[],
	concurrency: number,
	worker: (item: T) => Promise<R | "rate_limited">,
): Promise<{ results: R[]; rateLimited: boolean }> {
	const results: R[] = [];
	let rateLimited = false;
	let cursor = 0;
	const lanes = Math.max(1, Math.min(concurrency, items.length));
	const drive = async () => {
		while (cursor < items.length && !rateLimited) {
			const idx = cursor++;
			const item = items[idx];
			if (item === undefined) continue;
			const r = await worker(item);
			if (r === "rate_limited") {
				rateLimited = true;
				return;
			}
			results.push(r);
		}
	};
	await Promise.all(Array.from({ length: lanes }, () => drive()));
	return { results, rateLimited };
}

export async function readGithubSignals(
	opts: ReadGithubSignalsOpts,
): Promise<GithubSignalSet> {
	const http = opts.http ?? defaultFetch();
	const now = opts.now ?? new Date();
	const debugLog = opts.debugLog ?? (() => {});
	const headers = ghHeaders(opts.token);

	const isFirstSync = opts.since === null;
	const cutoff = isFirstSync
		? new Date(now.getTime() - NINETY_DAYS_MS)
		: (opts.since as Date);
	const perPage = isFirstSync ? FIRST_SYNC_PER_PAGE : SUBSEQUENT_SYNC_PER_PAGE;
	const searchUrl = buildSearchUrl({
		username: opts.username,
		mergedSince: formatDate(cutoff),
		perPage,
	});

	const fetchedAt = now.toISOString();
	const empty: GithubSignalSet = {
		prs: [],
		rateLimitHit: false,
		capApplied: null,
		fetchedAt,
	};

	const searchRes = await http(searchUrl, { headers });
	if (isRateLimited(searchRes)) {
		debugLog({ kind: "rate_limit_hit", phase: "search", url: searchUrl });
		return { ...empty, rateLimitHit: true };
	}
	if (!searchRes.ok) {
		return empty;
	}

	const items = parseSearchItems(await searchRes.json());

	let capApplied: FirstSyncCap | null = null;
	if (isFirstSync) {
		capApplied = applyFirstSyncCap({
			candidateCount: items.length,
			perPageLimit: FIRST_SYNC_PER_PAGE,
		});
		debugLog({ kind: "first_sync_cap", cap: capApplied, count: items.length });
	}

	const concurrency = opts.concurrency ?? DEFAULT_CONCURRENCY;
	const detailUrls: { url: string; number: number }[] = [];
	for (const item of items) {
		const url = item.pull_request?.url;
		if (!url) continue;
		detailUrls.push({ url, number: item.number });
	}

	const { results, rateLimited } = await runConcurrent(
		detailUrls,
		concurrency,
		async ({ url }) => {
			const res = await http(url, { headers });
			if (isRateLimited(res)) {
				debugLog({ kind: "rate_limit_hit", phase: "enrichment", url });
				return "rate_limited" as const;
			}
			if (!res.ok) return null;
			return parsePRDetail(await res.json());
		},
	);

	const enriched = results.filter((r): r is EnrichedPR => r !== null);
	const prs: GithubPRSignal[] = enriched.map((pr) => {
		const scored = scorePR({
			number: pr.number,
			title: pr.title,
			additions: pr.additions,
			deletions: pr.deletions,
			reviewCommentCount: pr.reviewCommentCount,
		});
		return {
			number: pr.number,
			title: pr.title,
			repoFullName: pr.repoFullName,
			htmlUrl: pr.htmlUrl,
			mergedAt: pr.mergedAt,
			additions: pr.additions,
			deletions: pr.deletions,
			reviewCommentCount: pr.reviewCommentCount,
			score: scored.score,
			scoreExplanation: scored.explanation,
		};
	});

	return {
		prs,
		rateLimitHit: rateLimited,
		capApplied,
		fetchedAt,
	};
}
