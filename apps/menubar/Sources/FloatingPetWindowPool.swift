import Foundation

/// Manages one `FloatingPetWindowControlling` instance per resolved render key
/// (or one shared "combined" window for combined-mode origins).
///
/// Since P15.03 the snapshot's `perPlatform` map is keyed by **resolved render
/// keys** from `resolveRenderKeys`: a plain `origin` (session-pets off), an
/// `origin:session_id` (session-pets on), or a pre-folded `"combined"`. The
/// pool keys windows by that resolved key uniformly — with session-pets on,
/// each active session gets its own window; collapsed keys are byte-identical
/// to the pre-Phase-15 origin keys, so all pre-existing behavior is unchanged.
///
/// Pool rules:
/// - Render keys whose owning origin's mode is "off" are filtered before any
///   window is spawned.
/// - Combined-mode origins fold into a single shared window keyed "combined"
///   (the driver pre-folds these; unfolded per-origin input folds here too).
/// - Every other render key gets its own window keyed by the resolved key.
/// - A window is dismissed when its render key's last-seen clock is older than
///   `ttlSeconds`, UNLESS that window is the last-active one.
/// - The last-active window (most-recently-updated render key across all
///   active keys) is never dismissed by TTL regardless of elapsed time.
@MainActor
final class FloatingPetWindowPool {
	typealias WindowFactory = (String, String) -> FloatingPetWindowControlling
	typealias MinimalistWindowFactory = (String) -> FloatingPetWindowControlling
	typealias CustomizationReader = () -> CustomizationSnapshot
	typealias AssignmentsReader = () -> AssignmentsSnapshot

	private let assignmentsReader: AssignmentsReader
	private let customizationReader: CustomizationReader
	private let windowFactory: WindowFactory
	private let minimalistWindowFactory: MinimalistWindowFactory?
	private let now: () -> Date

	/// Active windows keyed by window key (the resolved render key, or "combined").
	private var windows: [String: FloatingPetWindowControlling] = [:]
	/// Tracks the `now()` clock time when each render key was last present in a snapshot (TTL clock).
	private var lastSeenAt: [String: Date] = [:]
	/// Tracks the most-recent snapshot `updated_at` per render key (used to elect lastActiveRenderKey).
	private var lastUpdatedAt: [String: Date] = [:]
	/// Render key whose snapshot `updated_at` is most recent across all tracked keys.
	private var lastActiveRenderKey: String? = nil
	/// Most-recently read customization — updated at the start of each tick.
	private var currentCustomization: CustomizationSnapshot = .safeDefault
	/// Most-recently read assignments — updated at the start of each tick.
	private var currentAssignments: AssignmentsSnapshot = .safeDefault

	/// Window keys that currently have visible windows.
	var activeOrigins: [String] { Array(windows.keys).sorted() }

	/// Window keys explicitly hidden by the user via "Hide Pet". Excluded from spawning
	/// until the user explicitly shows them via "Show Pet".
	var hiddenWindowKeys: [String] { Array(userHiddenWindowKeys).sorted() }

	/// The pet ID currently assigned to the Default badge, read fresh from
	/// assignments.json on each `update()` tick.
	var defaultPetId: String { currentAssignments.default }

	/// Origins currently assigned to combined mode, read fresh from customization.
	/// The shared combined window folds all of these into one pet, so its right-click
	/// "Force Idle" must reset exactly this set — never every slice on disk, which
	/// would also idle independently-windowed pets.
	func combinedModeOrigins() -> [String] {
		let customization = customizationReader()
		return customization.platformModes
			.filter { $0.value == .combined }
			.map(\.key)
	}

	/// Owning origin of a window/render key: the prefix before the first colon
	/// for an `origin:session_id` key, the key itself otherwise (plain origins
	/// never contain a colon; the literal "combined" maps to itself).
	static func origin(forWindowKey key: String) -> String {
		guard let colon = key.firstIndex(of: ":") else { return key }
		return String(key[key.startIndex..<colon])
	}

	private var userHiddenWindowKeys: Set<String> = []

	/// Mode that was active when each window (keyed by window key) was spawned.
	/// Used to detect own↔minimalist transitions so the stale window is torn
	/// down and the correct factory runs on the next spawn gate.
	private var windowSpawnedModes: [String: PlatformMode] = [:]
	/// Renderer the current "combined" window was spawned with — nil when no
	/// combined window exists. Used to detect the combinedMinimalistEnabled
	/// setting toggling mid-flight so the window is torn down and respawned
	/// with the correct factory.
	private var combinedWindowIsMinimalist: Bool?

	/// Called when `menubarIconMonochrome` changes between ticks. The caller
	/// uses this to toggle `NSImage.isTemplate` on the status-item button.
	var onMonochromeChanged: ((Bool) -> Void)?

	init(
		assignmentsReader: @escaping AssignmentsReader = {
			AssignmentsJsonReader.read(at: CodogotchiFolders.assignmentsPath())
		},
		customizationReader: @escaping CustomizationReader = {
			CustomizationJsonReader.read(at: CodogotchiFolders.customizationPath())
		},
		windowFactory: @escaping WindowFactory,
		minimalistWindowFactory: MinimalistWindowFactory? = nil,
		now: @escaping () -> Date = { Date() }
	) {
		self.assignmentsReader = assignmentsReader
		self.customizationReader = customizationReader
		self.windowFactory = windowFactory
		self.minimalistWindowFactory = minimalistWindowFactory
		self.now = now
	}

	func update(snapshot: PerPlatformSnapshot) {
		// Read customization and assignments fresh on every tick so Settings writes take effect within one second.
		let prevMonochrome = currentCustomization.menubarIconMonochrome
		currentCustomization = customizationReader()
		currentAssignments = assignmentsReader()
		if currentCustomization.menubarIconMonochrome != prevMonochrome {
			onMonochromeChanged?(currentCustomization.menubarIconMonochrome)
		}
		let ttlSeconds: TimeInterval = currentCustomization.idleDismissTtlSeconds == 0
			? .infinity
			: TimeInterval(currentCustomization.idleDismissTtlSeconds)
		let currentTime = now()

		// Step 1: filter render keys whose owning origin's mode is off
		let visibleEntries = snapshot.perPlatform.filter { mode(forWindowKey: $0.key) != .off }

		// Step 2: update tracking for each visible render key
		for (renderKey, state) in visibleEntries {
			// TTL clock: advance only while the key is doing work. The idle-dismiss
			// TTL measures how long a pet has been idle, so an idle slice must NOT
			// refresh this clock — otherwise a still-present idle pet (whose slice
			// lingers in state.d/ for hours) reads as "just seen" every tick and never
			// dismisses. Seed on first sight so a freshly-observed idle pet still gets a
			// full TTL grace window before it disappears.
			if state.activityState != .idle || lastSeenAt[renderKey] == nil {
				lastSeenAt[renderKey] = currentTime
			}
			// Active-key election: track snapshot's own updated_at timestamp
			let stateDate = StateJsonReader.parseISO8601Date(state.updatedAt) ?? currentTime
			if lastUpdatedAt[renderKey] == nil || stateDate > lastUpdatedAt[renderKey]! {
				lastUpdatedAt[renderKey] = stateDate
			}
		}

		// Step 3: elect lastActiveRenderKey only from keys that are currently visible
		// OR still within their TTL window. This prevents a clock-skewed key that
		// has left state.d/ from holding last-active immunity indefinitely.
		let eligibleKeys = Set(visibleEntries.keys).union(
			lastSeenAt.keys.filter {
				currentTime.timeIntervalSince(lastSeenAt[$0] ?? .distantPast) <= ttlSeconds
			}
		)
		let eligibleForElection = lastUpdatedAt.filter { eligibleKeys.contains($0.key) }
		if !eligibleForElection.isEmpty {
			lastActiveRenderKey = eligibleForElection.max(by: { $0.value < $1.value })?.key
		}

		// Step 4: compute the key of the window that must not be dismissed
		let lastActiveWindowKey: String? = lastActiveRenderKey.map { windowKey(for: $0) }

		// Step 5a: force-dismiss off-mode windows — no last-active immunity.
		// An origin switching to .off must exit the render pipeline this tick regardless of
		// TTL or last-active status. Only directly-keyed windows are affected here; the
		// combined window is handled in Step 8 when combinedEntries is empty.
		for renderKey in snapshot.perPlatform.keys where mode(forWindowKey: renderKey) == .off {
			if windows[renderKey] != nil {
				windows[renderKey]?.setFloatingPetVisible(false)
				windows.removeValue(forKey: renderKey)
				windowSpawnedModes.removeValue(forKey: renderKey)
			}
		}

		// A window key is TTL-expired when it is not the last-active window and its
		// (idle-frozen) last-seen clock is older than the dismiss TTL. Used both to
		// dismiss existing windows (Step 5b) and to suppress re-spawn of an idle key
		// that has aged out (Steps 7–8): without the spawn guard, 5b would drop the
		// window and the spawn loop would immediately recreate it from the lingering
		// idle slice, so the pet would never actually disappear.
		func isTTLExpired(windowKey: String) -> Bool {
			guard windowKey != lastActiveWindowKey else { return false }
			guard let seen = lastSeenForWindow(key: windowKey) else { return true }
			return currentTime.timeIntervalSince(seen) > ttlSeconds
		}

		// Step 5b: dismiss stale windows (skip last-active)
		let staleKeys = windows.keys.filter { isTTLExpired(windowKey: $0) }
		for key in staleKeys {
			windows[key]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: key)
			windowSpawnedModes.removeValue(forKey: key)
		}

		// Step 6: separate combined vs directly-keyed entries. The driver pre-folds
		// combined origins to the literal "combined" key; unfolded per-origin input
		// (the pre-P15.03 shape the existing tests feed) folds here via windowKey.
		let directKeys = visibleEntries.keys.filter { windowKey(for: $0) != "combined" }
		let combinedKeys = visibleEntries.keys.filter { windowKey(for: $0) == "combined" }

		// Step 6a: collapse directly-keyed windows for keys that switched to combined
		// mode. A key moving own→combined must lose its own window immediately so it
		// doesn't render a second window alongside the shared combined one. The
		// literal "combined" key IS the shared window, so it is never torn down here.
		for renderKey in combinedKeys where renderKey != "combined" && windows[renderKey] != nil {
			windows[renderKey]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: renderKey)
			windowSpawnedModes.removeValue(forKey: renderKey)
		}

		// Step 6b: collapse windows whose controller type no longer matches the current
		// mode. own→minimalist and minimalist→own transitions are not covered by Steps
		// 5a or 6a; if we skip teardown here the wrong-type window stays in `windows`
		// and the spawn gate below (windows[renderKey] == nil) is never entered.
		for renderKey in directKeys where windows[renderKey] != nil {
			if let spawnedMode = windowSpawnedModes[renderKey],
				spawnedMode != mode(forWindowKey: renderKey)
			{
				windows[renderKey]?.setFloatingPetVisible(false)
				windows.removeValue(forKey: renderKey)
				windowSpawnedModes.removeValue(forKey: renderKey)
			}
		}

		// Step 7: spawn / update directly-keyed windows
		for renderKey in directKeys {
			guard let state = visibleEntries[renderKey] else { continue }
			// Idle past TTL: leave it dismissed and do not re-spawn from the lingering
			// idle slice (Step 5b already removed any window for it).
			if isTTLExpired(windowKey: renderKey) {
				if windows[renderKey] != nil {
					windows[renderKey]?.setFloatingPetVisible(false)
					windows.removeValue(forKey: renderKey)
					windowSpawnedModes.removeValue(forKey: renderKey)
				}
				continue
			}
			// User-hidden: do not re-spawn until the user explicitly shows the pet.
			if userHiddenWindowKeys.contains(renderKey) { continue }
			// Pet identity and mode are per-ORIGIN: every session window of a platform
			// renders that platform's assigned (or Default) pet and follows its mode.
			let origin = Self.origin(forWindowKey: renderKey)
			if windows[renderKey] == nil {
				let petId = currentAssignments.resolve(origin: origin)
				let controller: FloatingPetWindowControlling
				if mode(for: origin) == .minimalist {
					guard let minimalistWindowFactory else {
						NSLog("FloatingPetWindowPool: minimalist mode requires a minimalistWindowFactory for \(renderKey)")
						continue
					}
					controller = minimalistWindowFactory(renderKey)
				} else {
					controller = windowFactory(renderKey, petId)
				}
				controller.setFloatingPetVisible(true)
				windows[renderKey] = controller
				windowSpawnedModes[renderKey] = mode(for: origin)
			}
			windows[renderKey]?.apply(state: state.activityState, visualMode: .normal)
			windows[renderKey]?.applyAttention(
				payload: state.attention,
				sourceEvent: state.sourceEvent
			)
			windows[renderKey]?.applyGateBadge(content: snapshot.gateBadges[renderKey])
			if mode(for: origin) == .minimalist {
				windows[renderKey]?.applyPlatform(origin: origin)
			} else if let sourceOrigin = state.sourceEvent?.origin {
				windows[renderKey]?.applyPlatform(origin: sourceOrigin)
			}
		}

		// Step 8: spawn / update combined window
		if !combinedKeys.isEmpty {
			// Style toggle: if the existing combined window was spawned with the wrong
			// renderer for the current combinedMinimalistEnabled setting, tear it down so
			// the spawn gate below recreates it with the correct factory.
			if let combined = windows["combined"],
				combinedWindowIsMinimalist != currentCustomization.combinedMinimalistEnabled
			{
				combined.setFloatingPetVisible(false)
				windows.removeValue(forKey: "combined")
			}
			if isTTLExpired(windowKey: "combined") {
				// All combined-folded keys idle past TTL (and not last-active): dismiss
				// the shared window and do not re-spawn it this tick.
				if windows["combined"] != nil {
					windows["combined"]?.setFloatingPetVisible(false)
					windows.removeValue(forKey: "combined")
				}
			} else if !userHiddenWindowKeys.contains("combined") {
				let combinedEntries = combinedKeys.compactMap { key in
					visibleEntries[key].map { (key: key, state: $0) }
				}
				let winnerEntry = combinedEntries.max(by: { a, b in
					(StateJsonReader.parseISO8601Date(a.state.updatedAt) ?? .distantPast)
						< (StateJsonReader.parseISO8601Date(b.state.updatedAt) ?? .distantPast)
				})
				if let winnerEntry {
					let winner = winnerEntry.state
					if windows["combined"] == nil {
						let useMinimalist = currentCustomization.combinedMinimalistEnabled
						let controller: FloatingPetWindowControlling
						if useMinimalist {
							guard let minimalistWindowFactory else {
								NSLog("FloatingPetWindowPool: combined-minimalist mode requires a minimalistWindowFactory")
								return
							}
							controller = minimalistWindowFactory("combined")
						} else {
							let petId = currentAssignments.resolve(origin: "combined")
							controller = windowFactory("combined", petId)
						}
						controller.setFloatingPetVisible(true)
						windows["combined"] = controller
						combinedWindowIsMinimalist = useMinimalist
					}
					windows["combined"]?.apply(state: winner.activityState, visualMode: .normal)
					windows["combined"]?.applyAttention(
						payload: winner.attention,
						sourceEvent: winner.sourceEvent
					)
					// The combined window's gate badge follows whichever entry is
					// currently winning the shared pet, mirroring the platform-chip
					// precedent below. Badges are keyed by render key, so the winning
					// entry's key resolves for both pre-folded ("combined") and
					// unfolded (per-origin) input.
					windows["combined"]?.applyGateBadge(content: snapshot.gateBadges[winnerEntry.key])
					// While idle the combined window shows the persistent ⭐ Default badge;
					// when active it badges with whichever platform triggered the winning
					// state, matching the pre-phase-13 single-pet behavior.
					if winner.activityState == .idle {
						windows["combined"]?.applyPlatform(origin: "combined")
					} else if let sourceOrigin = winner.sourceEvent?.origin {
						windows["combined"]?.applyPlatform(origin: sourceOrigin)
					}
				}
			}
		} else {
			// No combined-folded keys → dismiss combined window if present,
			// but only when it is not the last-active window (same immunity as own-mode).
			if windows["combined"] != nil && "combined" != lastActiveWindowKey {
				windows["combined"]?.setFloatingPetVisible(false)
				windows.removeValue(forKey: "combined")
			}
		}

		// Step 9: broadcast RPG to all windows
		let rpg = snapshot.rpgSnapshot
		let hudEnabled = PetConfig.resolvedRPGHUDEnabled()
		for controller in windows.values {
			controller.applyRPGState(
				halfHearts: rpg.halfHearts,
				levelFraction: rpg.levelFraction,
				level: rpg.level,
				activeMinutes: rpg.activeMinutes,
				hudEnabled: hudEnabled
			)
		}
	}

	/// Returns true when the window for the given key is currently in `windows`.
	func isActive(for key: String) -> Bool { windows[key] != nil }

	/// Hides or shows the window for the given key.
	/// Hiding persists across update() ticks until setVisible(true) is called.
	func setVisible(_ visible: Bool, for key: String) {
		if visible {
			userHiddenWindowKeys.remove(key)
			// Re-spawn is handled by the next update() tick once the key is unblocked.
		} else {
			windows[key]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: key)
			windowSpawnedModes.removeValue(forKey: key)
			userHiddenWindowKeys.insert(key)
		}
	}

	/// Returns the controller for the given window key. Used by MenubarApp to wire
	/// per-window callbacks (attention dismiss, app-nap opt-out).
	func controller(for key: String) -> FloatingPetWindowControlling? { windows[key] }

	/// Live-swap the rendered pet for one origin's windows. Called when the user
	/// reassigns a platform badge in Settings > Pet so only that platform's windows
	/// update; other windows are untouched. Pet identity is per-origin, so ALL of
	/// the origin's session windows swap together (or its folded "combined"
	/// window when the origin is in combined mode). Newly spawned windows already
	/// pick up the current assignment via the factory's petId argument.
	func replacePet(origin: String, codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		let foldedKey = windowKey(for: origin)
		for key in windows.keys
		where key == foldedKey || Self.origin(forWindowKey: key) == origin {
			windows[key]?.replacePets(codexPet: codexPet, codogotchiPet: codogotchiPet)
		}
	}

	// MARK: - Private helpers

	private func mode(for origin: String) -> PlatformMode {
		currentCustomization.platformModes[origin] ?? .own
	}

	private func mode(forWindowKey key: String) -> PlatformMode {
		mode(for: Self.origin(forWindowKey: key))
	}

	/// THE single branch site mapping a render key to its window key: the
	/// literal "combined" and combined-mode origins fold to "combined"; every
	/// other resolved key (plain origin or origin:session_id) is its own window.
	private func windowKey(for renderKey: String) -> String {
		renderKey == "combined" || mode(forWindowKey: renderKey) == .combined
			? "combined" : renderKey
	}

	/// Most-recent lastSeenAt across all tracked render keys that map to this
	/// window key (several fold into "combined"; every other key maps to itself).
	private func lastSeenForWindow(key: String) -> Date? {
		if key == "combined" {
			return lastSeenAt
				.filter { windowKey(for: $0.key) == "combined" }
				.values.max()
		}
		return lastSeenAt[key]
	}
}
