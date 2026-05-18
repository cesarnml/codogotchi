import type {
	HealthConfigPayload,
	SignalClaude,
	SignalCodex,
	SignalGithub,
	SignalsPayload,
	SignalWakatime,
	SyncProfileResponse,
} from "@codogotchi/contracts";
import type { CodogotchiConfig } from "./config";

export type SourceReaders = {
	claude: (since: Date | null, now: Date) => Promise<SignalClaude | null>;
	codex: (since: Date | null, now: Date) => Promise<SignalCodex | null>;
	github: (since: Date | null, now: Date) => Promise<SignalGithub | null>;
	wakatime: (since: Date | null, now: Date) => Promise<SignalWakatime | null>;
};

export type SyncDeps = {
	home: string;
	config: CodogotchiConfig;
	readers: SourceReaders;
	fetch: typeof fetch;
	now: () => Date;
	logSizeLimit?: number;
};

export type SyncSourceError = {
	source: keyof SourceReaders;
	message: string;
};

export type SyncResult = {
	exitCode: 0 | 1;
	signals: SignalsPayload;
	errors: SyncSourceError[];
	postSucceeded: boolean;
	newLootCount: number;
	profile: SyncProfileResponse["profile"] | null;
};

export type SyncPayload = {
	profile_id: string;
	handle: string;
	signals: SignalsPayload;
	config: HealthConfigPayload;
	now: string;
	errors: SyncSourceError[];
};

export async function runSync(_deps: SyncDeps): Promise<SyncResult> {
	throw new Error("not implemented");
}
