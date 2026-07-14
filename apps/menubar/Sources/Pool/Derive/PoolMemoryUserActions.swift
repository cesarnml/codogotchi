import Foundation

/// Pure transition functions mirroring `FloatingPetWindowPool`'s out-of-band
/// user-action methods (Hide/Show, Prune, Hide All Others, Force-Idle timer
/// reset). Per the phase's Grill-Me decision 2: these are unwired this
/// ticket (P18.06 wires the shell's stored `PoolMemory` through them) but
/// each has a documented two-limb contract for that future wiring —
/// (1) this pure transition updates `PoolMemory` immediately, and (2) the
/// shell must pair it with the identical immediate window effect
/// (`setFloatingPetVisible(false)`, etc.) the legacy method performs
/// synchronously today. Neither limb waits for the next `derive` tick.
extension PoolMemory {
	/// Mirrors `FloatingPetWindowPool.setVisible(false, for:)`. Two-limb
	/// contract: (1) this call — insert into `userHiddenWindowKeys`, drop the
	/// key from `previousDesiredWindowKeys` (its window is gone), clear its
	/// spawned-mode bookkeeping, and release any session number using the
	/// identity captured at assign time (never the latest snapshot — see
	/// `windowSessionIdentities`); (2) the shell's paired immediate
	/// `setFloatingPetVisible(false)` call on the real window. Deliberately
	/// never touches `slotOccupants` (P15.07-QC): hide is concealment, not
	/// cap release, so a hidden incumbent keeps its slot reserved and
	/// un-hiding it respawns on the very next tick without competing for a
	/// new one.
	func hiding(_ key: WindowKey) -> PoolMemory {
		var memory = self
		memory.previousDesiredWindowKeys.remove(key)
		memory.windowSpawnedModes.removeValue(forKey: key)
		// Immediate, not "correct by next tick": `derive`'s own torndownKeys
		// pass also clears this, but that only runs on the NEXT tick — a
		// caller reading `sessionNumber(forWindowKey:)` between this call and
		// the next `update()` must not see a number that was just released
		// (subagent-review finding).
		memory.sessionNumbers.removeValue(forKey: key)
		if let identity = memory.windowSessionIdentities.removeValue(forKey: key) {
			memory.sessionNumberAllocator.release(origin: identity.origin, sessionId: identity.sessionId)
		}
		memory.userHiddenWindowKeys.insert(key)
		return memory
	}

	/// Mirrors `FloatingPetWindowPool.setVisible(true, for:)`. Two-limb
	/// contract: (1) this call — clear the hidden flag AND drop `lastSeenAt`
	/// so the next `derive` tick re-seeds a full TTL grace window (the exact
	/// fix for the "Show is a silent no-op" bug: without dropping this clock,
	/// respawn hinges on the refreshed slice winning the last-active
	/// election, which a concurrently-working sibling session's newer
	/// `updated_at` wins instead); (2) the shell has no immediate window
	/// effect to pair here — re-spawn is left to the next `derive` tick, same
	/// as the legacy method's own comment ("Re-spawn is handled by the next
	/// update() tick").
	func showing(_ key: WindowKey) -> PoolMemory {
		var memory = self
		memory.userHiddenWindowKeys.remove(key)
		memory.lastSeenAt.removeValue(forKey: key)
		return memory
	}

	/// Mirrors `FloatingPetWindowPool.pruneSession`'s in-memory bookkeeping
	/// (the on-disk slice/sidecar deletion itself stays an impure effect for
	/// a later ticket to wire). Two-limb contract: (1) this call — arm the
	/// origin permanently for the process lifetime (so a future promotion
	/// into the freed slot requires the promoted session to be in-flight,
	/// never a merely-held idle sibling) and clear every per-key bookkeeping
	/// map a fresh session at that key should not inherit stale state from:
	/// `previousDesiredWindowKeys`, `windowSpawnedModes`, `promptTimers`. Also
	/// releases the session number directly here, exactly like `hiding(_:)`
	/// does — unlike a hide, a prune removes the key's membership evidence
	/// from `previousDesiredWindowKeys` immediately, out-of-band from
	/// `derive`'s own diff. If the release were left for `derive`'s next
	/// teardown-diff pass instead, a key already absent from
	/// `previousDesiredWindowKeys` (removed by this very call) would compute
	/// `torndownKeys = previousKeys.subtracting(visibleFinalKeys)` as empty
	/// for it — the key is invisible to both sides of that diff — so the
	/// release-on-teardown path would never fire and the session number
	/// would leak forever. Releasing here, using the identity captured at
	/// assign time (never the latest snapshot — see
	/// `windowSessionIdentities`), closes that gap. (2) the shell's paired
	/// `SessionPruner.pruneSession` call performs the actual disk/allocator
	/// side effects.
	func pruning(_ key: WindowKey, resolvedOrigin: String? = nil) -> PoolMemory {
		var memory = self
		memory.previousDesiredWindowKeys.remove(key)
		memory.windowSpawnedModes.removeValue(forKey: key)
		memory.promptTimers.removeValue(forKey: key)
		memory.prunedOrigins.insert(resolvedOrigin ?? key.origin)
		// Immediate, not "correct by next tick" — see `hiding(_:)`'s identical
		// note (subagent-review finding).
		memory.sessionNumbers.removeValue(forKey: key)
		if let identity = memory.windowSessionIdentities.removeValue(forKey: key) {
			memory.sessionNumberAllocator.release(origin: identity.origin, sessionId: identity.sessionId)
		}
		return memory
	}

	/// Mirrors `FloatingPetWindowPool.hideAllOtherWindows(keepVisible:)`.
	/// Two-limb contract: (1) this call — apply the exact same transition
	/// `hiding(_:)` performs to every key in `desiredKeys` except `keeping`,
	/// batched; (2) the shell's paired immediate
	/// `setFloatingPetVisible(false)` call on each of those real windows.
	/// `desiredKeys` is the caller's current desired-window membership (the
	/// pure analogue of iterating `windows.keys`), since `PoolMemory` itself
	/// does not store which windows are currently open beyond
	/// `previousDesiredWindowKeys`.
	func hidingAllOthers(keeping: WindowKey, among desiredKeys: Set<WindowKey>) -> PoolMemory {
		var memory = self
		for key in desiredKeys where key != keeping {
			memory = memory.hiding(key)
		}
		return memory
	}

	/// Mirrors `FloatingPetWindowPool.resetPromptTimer(forWindowKey:)`. A
	/// live user action (Force Idle, attention-bubble dismiss) that stamps
	/// the pool-owned prompt timer with the real current time so a
	/// subsequent stale-slice poll cannot restart it. Two-limb contract: (1)
	/// this call — reset the tracker if one exists for `key`; (2) the
	/// shell's paired panel-side "clear displayed status immediately" effect
	/// (`WindowActionRouter`'s callers already do this before the on-disk
	/// rewrite settles).
	func resettingPromptTimer(for key: WindowKey) -> PoolMemory {
		var memory = self
		memory.promptTimers[key]?.reset()
		return memory
	}
}
