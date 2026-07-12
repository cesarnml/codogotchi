import Foundation

/// Pure fold: `derive(input:memory:) -> (DesiredWindows, PoolMemory)`.
///
/// P18.01 wires exactly `FloatingPetWindowPool.update()` Steps 1–5b plus the
/// eligibility-bounding block that follows Step 3b:
///
/// - Step 1: off-mode render-key filtering
/// - Step 2: the idle-frozen TTL clock, first-seen seeding, last-updated
///   tracking
/// - Step 3: the last-active election, restricted to eligible keys
/// - Step 3b: the sticky HUD-bearer election
/// - eligibility bounding: pruning the three clock maps to the eligibility
///   window
/// - `isTTLExpired`: the TTL-expiry-with-last-active-immunity predicate
///   (Steps 5a/5b's guard), exposed as a pure static function
///
/// Selection (Step 6c), the collapse steps (6a/6a2/6b), and push-payload
/// construction (Steps 7/8) are NOT implemented here — those are P18.02 and
/// P18.03. `derive` therefore always returns an empty `DesiredWindows` this
/// ticket; see `DesiredWindow`'s doc comment for the placeholder contract.
///
/// No AppKit import anywhere in this file or elsewhere under `Pool/Derive/`
/// — enforced by `PoolDerivePurityGateTests`.
enum PoolDerive {
	static func derive(input: PoolTickInput, memory: PoolMemory) -> (DesiredWindows, PoolMemory) {
		var memory = memory
		let snapshot = input.snapshot
		let customization = input.customization
		let currentTime = input.currentTime
		let ttlSeconds: TimeInterval = customization.idleDismissTtlSeconds == 0
			? .infinity
			: TimeInterval(customization.idleDismissTtlSeconds)

		func mode(forWindowKey key: WindowKey) -> PlatformMode {
			customization.platformModes[key.origin] ?? .own
		}

		// Step 1: filter render keys whose owning origin's mode is off.
		let visibleEntries = snapshot.perPlatform.filter { mode(forWindowKey: $0.key) != .off }

		// Step 2: update tracking for each visible render key.
		for (renderKey, state) in visibleEntries {
			// TTL clock: advance only while the key is doing work. Seed on
			// first sight so a freshly-observed idle pet still gets a full
			// TTL grace window.
			if state.activityState != .idle || memory.lastSeenAt[renderKey] == nil {
				memory.lastSeenAt[renderKey] = currentTime
			}
			// First-seen clock: set once, never refreshed.
			if memory.firstSeenAt[renderKey] == nil {
				memory.firstSeenAt[renderKey] = currentTime
			}
			// Active-key election: track the snapshot's own updated_at.
			let stateDate = StateJsonReader.parseISO8601Date(state.updatedAt) ?? currentTime
			if memory.lastUpdatedAt[renderKey] == nil || stateDate > memory.lastUpdatedAt[renderKey]! {
				memory.lastUpdatedAt[renderKey] = stateDate
			}
		}

		// Step 3: elect lastActiveRenderKey only from keys that are currently
		// visible OR still within their TTL window — a clock-skewed key that
		// has left the snapshot must not hold last-active immunity forever.
		let eligibleKeys = Set(visibleEntries.keys).union(
			memory.lastSeenAt.keys.filter {
				currentTime.timeIntervalSince(memory.lastSeenAt[$0] ?? .distantPast) <= ttlSeconds
			}
		)
		let eligibleForElection = memory.lastUpdatedAt.filter { eligibleKeys.contains($0.key) }
		if !eligibleForElection.isEmpty {
			memory.lastActiveRenderKey = eligibleForElection.max(by: { $0.value < $1.value })?.key
		}

		// Step 3b: elect hudBearingRenderKey ("Show HUD on Most Recent Pet").
		// Re-elect only when the current holder is no longer in-flight or has
		// fallen out of eligibility; otherwise keep the same holder
		// regardless of what else updated this tick.
		let holderStillInFlight: Bool =
			if let key = memory.hudBearingRenderKey, eligibleKeys.contains(key) {
				visibleEntries[key]?.activityState.isInFlight ?? false
			} else {
				false
			}
		if !holderStillInFlight, !eligibleForElection.isEmpty {
			memory.hudBearingRenderKey = eligibleForElection.max(by: { $0.value < $1.value })?.key
		}

		// Bound the tracked clocks to the eligibility window computed above —
		// without this they grow one entry per render key ever seen for the
		// lifetime of the process.
		memory.firstSeenAt = memory.firstSeenAt.filter { eligibleKeys.contains($0.key) }
		memory.lastSeenAt = memory.lastSeenAt.filter { eligibleKeys.contains($0.key) }
		memory.lastUpdatedAt = memory.lastUpdatedAt.filter { eligibleKeys.contains($0.key) }

		// P18.02 wires selection/collapse and starts populating `windows`;
		// P18.01 has nothing yet to desire.
		return (DesiredWindows(), memory)
	}

	/// True when `windowKey` is not the last-active key and its last-seen
	/// clock is older than `ttlSeconds`. Mirrors
	/// `FloatingPetWindowPool.isTTLExpired(windowKey:)` exactly, keyed by
	/// render key rather than the post-collapse window key — combined-window
	/// folding (Step 6/8) is P18.02 scope.
	static func isTTLExpired(
		windowKey: WindowKey, memory: PoolMemory, ttlSeconds: TimeInterval, currentTime: Date
	) -> Bool {
		guard windowKey != memory.lastActiveRenderKey else { return false }
		guard let seen = memory.lastSeenAt[windowKey] else { return true }
		return currentTime.timeIntervalSince(seen) > ttlSeconds
	}
}
