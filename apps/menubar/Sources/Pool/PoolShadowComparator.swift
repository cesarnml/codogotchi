import Foundation

/// The full, named/enumerated set of accepted shadow-compare divergences.
/// Exactly one today (Grill-Me decision 3's title-seam delay) — a new
/// exemption must be added here explicitly, never pattern-matched loosely
/// against arbitrary field names (see the ticket's Review Focus).
enum ShadowCompareExemption: CaseIterable, Hashable {
	/// A freshly-resolved session title lags ~1 tick behind the old
	/// (synchronous) pipeline, since `derive` only signals "resolution in
	/// flight" via `DesiredWindows.titleResolutionRequests` and `apply`
	/// resolves it out-of-band; the result lands next tick's `PoolMemory`.
	/// Scoped to exactly the `sessionLabel` field on a key with an in-flight
	/// request this tick — never a loose "any sessionLabel mismatch is fine."
	case titleResolutionDelay

	/// P18.05's pre-cutover "old" side is reconstructed from
	/// `RecordingFloatingPetWindowControllingProxy`'s recorded pushes, which
	/// only ever record a spawn's *resolved* `CGRect` (via `adoptFrame`),
	/// never the structural donor `WindowKey` `PoolDerive` emits as
	/// `inheritedFrameFrom` — there is no old-pipeline call that expresses
	/// "which window this one inherited its frame from" as data. Scoped to
	/// exactly the `inheritedFrameFrom` field, and only when the
	/// reconstructed old side is `nil` (the only value it can ever take) —
	/// never a loose "any inheritedFrameFrom mismatch is fine."
	case frameProvenanceUnavailableFromRecordedPushes
}

/// One field-level shadow-compare mismatch: what changed, on which window,
/// on which tick — replayable via `tickFingerprint`. Log-only in the
/// dogfood build (never fatal); asserted in tests/debug.
struct DivergenceRecord: Equatable {
	let tickFingerprint: String
	let windowKey: WindowKey
	let fieldPath: String
	let oldValue: String
	let newValue: String
}

/// Field-level and membership comparator between the old pipeline's recorded
/// per-window push behavior (captured via
/// `RecordingFloatingPetWindowControllingProxy`, represented here as a
/// `[WindowKey: DesiredWindow]` — see this file's test-file scope note) and
/// the new engine's `DesiredWindows` output. A key present on only one side
/// (a missing or spurious window) is reported as a `"membership"`
/// `DivergenceRecord`, distinct from the field-level comparisons below.
///
/// Frame-inheritance directives are compared structurally (which `WindowKey`
/// a spawn inherits from), never as resolved `CGRect` values — there is no
/// `CGRect` on `DesiredWindow` to compare in the first place; `inheritedFrameFrom`
/// IS the structural comparison.
enum PoolShadowComparator {
	static func compare(
		old: [WindowKey: DesiredWindow],
		new: DesiredWindows,
		tickFingerprint: String
	) -> [DivergenceRecord] {
		var divergences: [DivergenceRecord] = []

		let keys = Set(old.keys).union(new.windows.keys)
		for key in keys.sorted(by: { $0.rawValue < $1.rawValue }) {
			guard let oldWindow = old[key], let newWindow = new.windows[key] else {
				// P18.05: a key present on only one side IS a divergence — a
				// missing or spurious window is exactly the class of bug
				// shadow-compare exists to catch, so it must produce a
				// record rather than being silently skipped. `fieldPath`
				// "membership" distinguishes this from the field-level
				// divergences below.
				let oldPresent = old[key] != nil
				let newPresent = new.windows[key] != nil
				divergences.append(
					DivergenceRecord(
						tickFingerprint: tickFingerprint,
						windowKey: key,
						fieldPath: "membership",
						oldValue: oldPresent ? "present" : "absent",
						newValue: newPresent ? "present" : "absent"
					))
				continue
			}

			divergences.append(
				contentsOf: fieldDivergences(
					old: oldWindow, new: newWindow, newDesired: new, key: key, tickFingerprint: tickFingerprint))
		}

		return divergences
	}

	private static func fieldDivergences(
		old: DesiredWindow,
		new: DesiredWindow,
		newDesired: DesiredWindows,
		key: WindowKey,
		tickFingerprint: String
	) -> [DivergenceRecord] {
		var divergences: [DivergenceRecord] = []

		func record(_ fieldPath: String, _ oldValue: Any, _ newValue: Any) {
			divergences.append(
				DivergenceRecord(
					tickFingerprint: tickFingerprint, windowKey: key, fieldPath: fieldPath,
					oldValue: String(describing: oldValue), newValue: String(describing: newValue)))
		}

		if old.isMinimalist != new.isMinimalist {
			record("isMinimalist", old.isMinimalist, new.isMinimalist)
		}
		if old.petId != new.petId {
			record("petId", old.petId, new.petId)
		}
		if old.sessionNumber != new.sessionNumber {
			record("sessionNumber", describeOptional(old.sessionNumber), describeOptional(new.sessionNumber))
		}
		if old.sessionLabel != new.sessionLabel, !isTitleSeamExempt(key: key, newDesired: newDesired) {
			record("sessionLabel", describeOptional(old.sessionLabel), describeOptional(new.sessionLabel))
		}
		if old.sessionTooltip != new.sessionTooltip {
			record("sessionTooltip", describeOptional(old.sessionTooltip), describeOptional(new.sessionTooltip))
		}
		if old.activityState != new.activityState {
			record("activityState", old.activityState, new.activityState)
		}
		if old.promptTimerStatus != new.promptTimerStatus {
			record(
				"promptTimerStatus", describeOptional(old.promptTimerStatus), describeOptional(new.promptTimerStatus))
		}
		if old.attention != new.attention {
			// P18.05: `AttentionPayload.summary` is user-facing free text (a
			// submitted prompt's summary), unlike the other structural
			// fields compared here — redact it at the source, before it
			// ever reaches a `DivergenceRecord`, rather than relying on the
			// disk/NSLog sink to redact a raw struct dump downstream.
			record("attention", describeAttention(old.attention), describeAttention(new.attention))
		}
		if old.attentionSourceEvent != new.attentionSourceEvent {
			record(
				"attentionSourceEvent", describeOptional(old.attentionSourceEvent),
				describeOptional(new.attentionSourceEvent))
		}
		if old.gateBadge != new.gateBadge {
			record("gateBadge", describeOptional(old.gateBadge), describeOptional(new.gateBadge))
		}
		if old.platformChip != new.platformChip {
			record("platformChip", describeOptional(old.platformChip), describeOptional(new.platformChip))
		}
		if old.rpgSnapshot != new.rpgSnapshot {
			record("rpgSnapshot", old.rpgSnapshot, new.rpgSnapshot)
		}
		if old.hudEnabled != new.hudEnabled {
			record("hudEnabled", old.hudEnabled, new.hudEnabled)
		}
		if old.conflictBubble != new.conflictBubble {
			record("conflictBubble", describeOptional(old.conflictBubble), describeOptional(new.conflictBubble))
		}
		if old.inheritedFrameFrom != new.inheritedFrameFrom, old.inheritedFrameFrom != nil {
			// `old.inheritedFrameFrom == nil` is exempt
			// (`.frameProvenanceUnavailableFromRecordedPushes`) — the
			// reconstructed old side can never carry a non-nil value, so
			// comparing it against a genuine `new` donor key would be a
			// permanent false divergence, not a real one.
			record(
				"inheritedFrameFrom", describeWindowKey(old.inheritedFrameFrom),
				describeWindowKey(new.inheritedFrameFrom))
		}

		return divergences
	}

	/// The one named exemption (`ShadowCompareExemption.titleResolutionDelay`):
	/// `key` has an in-flight title-resolution request THIS tick per
	/// `DesiredWindows.titleResolutionRequests` — scoped to exactly that key,
	/// never a blanket "any sessionLabel mismatch is fine."
	private static func isTitleSeamExempt(key: WindowKey, newDesired: DesiredWindows) -> Bool {
		newDesired.titleResolutionRequests.contains { identity in
			WindowKey.session(origin: identity.origin, id: identity.sessionId) == key
		}
	}

	private static func describeOptional(_ value: Any?) -> String {
		guard let value else { return "nil" }
		return String(describing: value)
	}

	/// Structural description of an `AttentionPayload` divergence value with
	/// `summary` (user-facing free text) redacted to a length indicator —
	/// every other field is safe bounded metadata (timestamps, a reason
	/// enum-ish string) and is retained verbatim so the divergence record
	/// stays useful for debugging.
	private static func describeAttention(_ payload: AttentionPayload?) -> String {
		guard let payload else { return "nil" }
		let summary = payload.summary.map { "<redacted:\($0.count)ch>" } ?? "nil"
		return "AttentionPayload(createdAt: \(describeOptional(payload.createdAt)), "
			+ "expiresAt: \(describeOptional(payload.expiresAt)), summary: \(summary), "
			+ "reasonKind: \(describeOptional(payload.reasonKind)))"
	}

	private static func describeWindowKey(_ key: WindowKey?) -> String {
		guard let key else { return "nil" }
		return key.rawValue
	}
}
