import { type HpOverlay, hpToOverlay } from "@codogotchi/contracts";
import type { RawSignals } from "./xp";

export type ProfileHealth = {
	hp: number;
	last_signal_at: string | null;
	died_at: string | null;
	death_count: number;
	cause?: "decay";
};

export type HealthConfig = {
	weekend_decay: boolean;
	grace_days: number;
	vacation_until: string | null;
	timezone: string;
	decay_per_day: number;
	revive_threshold: number;
	revive_hp: number;
};

export const DEFAULT_HEALTH_CONFIG: HealthConfig = {
	weekend_decay: false,
	grace_days: 2,
	vacation_until: null,
	timezone: "UTC",
	decay_per_day: 5,
	revive_threshold: 100,
	revive_hp: 50,
};

const MS_PER_DAY = 24 * 60 * 60 * 1000;

export function hpBucket(hp: number): HpOverlay {
	return hpToOverlay(hp);
}

export function isWeekendInTimezone(now: Date, timezone: string): boolean {
	const weekday = new Intl.DateTimeFormat("en-US", {
		timeZone: timezone,
		weekday: "short",
	}).format(now);
	return weekday === "Sat" || weekday === "Sun";
}

function signalVolume(signals: RawSignals): number {
	return (
		Math.max(0, signals.claudeTokens) +
		Math.max(0, signals.codexTokens) +
		Math.max(0, signals.githubPRs) * 1000 +
		Math.max(0, signals.wakatimeHours) * 1000
	);
}

function daysSince(nowMs: number, lastIso: string | null): number {
	if (lastIso === null) return Number.POSITIVE_INFINITY;
	const last = Date.parse(lastIso);
	if (Number.isNaN(last)) return Number.POSITIVE_INFINITY;
	return (nowMs - last) / MS_PER_DAY;
}

export function tickHealth(
	now: Date,
	profile: ProfileHealth,
	signals: RawSignals,
	config: HealthConfig,
): ProfileHealth {
	const next: ProfileHealth = { ...profile };
	const nowMs = now.getTime();
	const volume = signalVolume(signals);
	const hasActivity = volume > 0;

	if (hasActivity) {
		next.last_signal_at = now.toISOString();
	}

	if (next.died_at !== null) {
		if (volume >= config.revive_threshold) {
			next.died_at = null;
			next.cause = undefined;
			next.hp = config.revive_hp;
		}
		return next;
	}

	if (!config.weekend_decay && isWeekendInTimezone(now, config.timezone)) {
		return next;
	}

	if (config.vacation_until !== null) {
		const until = Date.parse(config.vacation_until);
		if (!Number.isNaN(until) && until >= nowMs) {
			return next;
		}
	}

	const idleDays = daysSince(nowMs, profile.last_signal_at);
	if (idleDays < config.grace_days) {
		return next;
	}

	next.hp = Math.max(0, next.hp - config.decay_per_day);
	if (next.hp === 0) {
		next.died_at = now.toISOString();
		next.cause = "decay";
		next.death_count = profile.death_count + 1;
	}
	return next;
}
