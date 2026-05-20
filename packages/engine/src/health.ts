import { type HpOverlay, hpToOverlay } from "@codogotchi/contracts";
import type { RawSignals } from "./xp";

export type ProfileHealth = {
	hp: number;
	last_signal_at: string | null;
	died_at: string | null;
	death_count: number;
	cause?: "decay";
	// UTC day key (YYYY-MM-DD) of the last decay/regen evaluation. Used to
	// rate-limit each tick to once per UTC day — without these, every sync
	// fires the tick. Optional for backward compat: missing/null means
	// "never evaluated" and the next tick will evaluate.
	last_decay_day?: string | null;
	last_regen_day?: string | null;
};

export type HealthConfig = {
	weekend_decay: boolean;
	grace_days: number;
	vacation_until: string | null;
	timezone: string;
	decay_per_day: number;
	revive_threshold: number;
	revive_hp: number;
	regen_per_day: number;
	regen_per_day_bonus: number;
	hp_cap: number;
};

export const DEFAULT_HEALTH_CONFIG: HealthConfig = {
	weekend_decay: false,
	grace_days: 2,
	vacation_until: null,
	timezone: "UTC",
	decay_per_day: 5,
	revive_threshold: 100,
	revive_hp: 50,
	regen_per_day: 1,
	regen_per_day_bonus: 2,
	hp_cap: 100,
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

export function utcDayKey(now: Date): string {
	return now.toISOString().slice(0, 10);
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

function isOnVacation(nowMs: number, vacationUntil: string | null): boolean {
	if (vacationUntil === null) return false;
	const until = Date.parse(vacationUntil);
	if (Number.isNaN(until)) return false;
	return until >= nowMs;
}

function shouldDecayToday(
	now: Date,
	nowMs: number,
	priorLastSignalAt: string | null,
	config: HealthConfig,
): boolean {
	if (!config.weekend_decay && isWeekendInTimezone(now, config.timezone)) {
		return false;
	}
	if (isOnVacation(nowMs, config.vacation_until)) {
		return false;
	}
	if (priorLastSignalAt === null) {
		return false;
	}
	return daysSince(nowMs, priorLastSignalAt) >= config.grace_days;
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
	const todayKey = utcDayKey(now);

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

	// Decay tick — at most once per UTC day. Marking the day key on every
	// evaluation (not just when decay actually fires) ensures that subsequent
	// syncs on the same day stay no-op, even when the eval skipped via
	// weekend/vacation/grace/fresh-profile rules.
	if (profile.last_decay_day !== todayKey) {
		next.last_decay_day = todayKey;
		if (shouldDecayToday(now, nowMs, profile.last_signal_at, config)) {
			next.hp = Math.max(0, next.hp - config.decay_per_day);
			if (next.hp === 0) {
				next.died_at = now.toISOString();
				next.cause = "decay";
				next.death_count = profile.death_count + 1;
			}
		}
	}

	// Regen tick — at most once per UTC day. Active days (any signal volume)
	// earn +regen_per_day, or +regen_per_day_bonus on weekends/vacation as a
	// "thank you for showing up on a day you didn't have to" reward. HP cap
	// at hp_cap. Skipped when the pet just died this tick — death first.
	if (next.died_at === null && profile.last_regen_day !== todayKey) {
		next.last_regen_day = todayKey;
		if (hasActivity) {
			const bonusDay =
				(!config.weekend_decay && isWeekendInTimezone(now, config.timezone)) ||
				isOnVacation(nowMs, config.vacation_until);
			const amount = bonusDay
				? config.regen_per_day_bonus
				: config.regen_per_day;
			// Regen must never lower HP: a custom hp_cap below current HP simply
			// prevents further upward movement, it doesn't shave existing HP.
			const target = Math.min(config.hp_cap, next.hp + amount);
			if (target > next.hp) next.hp = target;
		}
	}

	return next;
}
