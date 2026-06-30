import Foundation

/// Manages one `FloatingPetWindowControlling` instance per active origin
/// (or one shared "combined" window for combined-mode origins).
///
/// Pool rules:
/// - Origins with mode "off" are filtered before any window is spawned.
/// - Origins with mode "combined" fold into a single shared window keyed "combined".
/// - Origins with mode "own" (the default) each get their own window.
/// - A window is dismissed when its origin's last-seen `updated_at` timestamp is
///   older than `ttlSeconds`, UNLESS that window is the last-active one.
/// - The last-active window (most-recently-updated origin across all active origins)
///   is never dismissed by TTL regardless of elapsed time.
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

	/// Active windows keyed by window key (origin for "own" mode, "combined" for combined mode).
	private var windows: [String: FloatingPetWindowControlling] = [:]
	/// Tracks the `now()` clock time when each origin was last present in a snapshot (TTL clock).
	private var lastSeenAt: [String: Date] = [:]
	/// Tracks the most-recent snapshot `updated_at` per origin (used to elect lastActiveOrigin).
	private var lastUpdatedAt: [String: Date] = [:]
	/// Origin whose snapshot `updated_at` is most recent across all tracked origins.
	private var lastActiveOrigin: String? = nil
	/// Most-recently read customization — updated at the start of each tick.
	private var currentCustomization: CustomizationSnapshot = .safeDefault
	/// Most-recently read assignments — updated at the start of each tick.
	private var currentAssignments: AssignmentsSnapshot = .safeDefault

	/// Window keys that currently have visible windows.
	var activeOrigins: [String] { Array(windows.keys).sorted() }

	/// Window keys explicitly hidden by the user via "Hide Pet". Excluded from spawning
	/// until the user explicitly shows them via "Show Pet".
	var hiddenWindowKeys: [String] { Array(userHiddenWindowKeys).sorted() }

	private var userHiddenWindowKeys: Set<String> = []

	/// Mode that was active when each window (keyed by origin) was spawned.
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

		// Step 1: filter off-mode origins
		let visibleEntries = snapshot.perPlatform.filter { mode(for: $0.key) != .off }

		// Step 2: update tracking for each visible origin
		for (origin, state) in visibleEntries {
			// TTL clock: advance only while the origin is doing work. The idle-dismiss
			// TTL measures how long a pet has been idle, so an idle slice must NOT
			// refresh this clock — otherwise a still-present idle pet (whose slice
			// lingers in state.d/ for hours) reads as "just seen" every tick and never
			// dismisses. Seed on first sight so a freshly-observed idle pet still gets a
			// full TTL grace window before it disappears.
			if state.activityState != .idle || lastSeenAt[origin] == nil {
				lastSeenAt[origin] = currentTime
			}
			// Active-origin election: track snapshot's own updated_at timestamp
			let stateDate = StateJsonReader.parseISO8601Date(state.updatedAt) ?? currentTime
			if lastUpdatedAt[origin] == nil || stateDate > lastUpdatedAt[origin]! {
				lastUpdatedAt[origin] = stateDate
			}
		}

		// Step 3: elect lastActiveOrigin only from origins that are currently visible
		// OR still within their TTL window. This prevents a clock-skewed origin that
		// has left state.d/ from holding last-active immunity indefinitely.
		let eligibleOrigins = Set(visibleEntries.keys).union(
			lastSeenAt.keys.filter {
				currentTime.timeIntervalSince(lastSeenAt[$0] ?? .distantPast) <= ttlSeconds
			}
		)
		let eligibleForElection = lastUpdatedAt.filter { eligibleOrigins.contains($0.key) }
		if !eligibleForElection.isEmpty {
			lastActiveOrigin = eligibleForElection.max(by: { $0.value < $1.value })?.key
		}

		// Step 4: compute the key of the window that must not be dismissed
		let lastActiveWindowKey: String? = lastActiveOrigin.map { windowKey(for: $0) }

		// Step 5a: force-dismiss off-mode origin windows — no last-active immunity.
		// An origin switching to .off must exit the render pipeline this tick regardless of
		// TTL or last-active status. Only own-keyed windows are affected here; the combined
		// window is handled in Step 8 when combinedOrigins is empty.
		for origin in snapshot.perPlatform.keys where mode(for: origin) == .off {
			if windows[origin] != nil {
				windows[origin]?.setFloatingPetVisible(false)
				windows.removeValue(forKey: origin)
				windowSpawnedModes.removeValue(forKey: origin)
			}
		}

		// A window key is TTL-expired when it is not the last-active window and its
		// (idle-frozen) last-seen clock is older than the dismiss TTL. Used both to
		// dismiss existing windows (Step 5b) and to suppress re-spawn of an idle origin
		// that has aged out (Steps 7–8): without the spawn guard, 5b would drop the
		// window and the spawn loop would immediately recreate it from the lingering
		// idle slice, so the pet would never actually disappear.
		func isTTLExpired(windowKey: String) -> Bool {
			guard windowKey != lastActiveWindowKey else { return false }
			guard let seen = lastSeenForWindow(key: windowKey) else { return true }
			return currentTime.timeIntervalSince(seen) > ttlSeconds
		}

		// Step 5b: dismiss stale own-mode windows (skip last-active)
		let staleKeys = windows.keys.filter { isTTLExpired(windowKey: $0) }
		for key in staleKeys {
			windows[key]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: key)
			windowSpawnedModes.removeValue(forKey: key)
		}

		// Step 6: separate combined vs own origins
		let ownOrigins = visibleEntries.keys.filter { mode(for: $0) != .combined }
		let combinedOrigins = visibleEntries.keys.filter { mode(for: $0) == .combined }

		// Step 6a: collapse own windows for origins that switched to combined mode.
		// An origin moving own→combined must lose its origin-keyed window immediately
		// so it doesn't render a second window alongside the shared combined one.
		for origin in combinedOrigins where windows[origin] != nil {
			windows[origin]?.setFloatingPetVisible(false)
			windows.removeValue(forKey: origin)
			windowSpawnedModes.removeValue(forKey: origin)
		}

		// Step 6b: collapse windows whose controller type no longer matches the current
		// mode. own→minimalist and minimalist→own transitions are not covered by Steps
		// 5a or 6a; if we skip teardown here the wrong-type window stays in `windows`
		// and the spawn gate below (windows[origin] == nil) is never entered.
		for origin in ownOrigins where windows[origin] != nil {
			if let spawnedMode = windowSpawnedModes[origin], spawnedMode != mode(for: origin) {
				windows[origin]?.setFloatingPetVisible(false)
				windows.removeValue(forKey: origin)
				windowSpawnedModes.removeValue(forKey: origin)
			}
		}

		// Step 7: spawn / update own-mode windows
		for origin in ownOrigins {
			guard let state = visibleEntries[origin] else { continue }
			// Idle past TTL: leave it dismissed and do not re-spawn from the lingering
			// idle slice (Step 5b already removed any window for it).
			if isTTLExpired(windowKey: origin) {
				if windows[origin] != nil {
					windows[origin]?.setFloatingPetVisible(false)
					windows.removeValue(forKey: origin)
					windowSpawnedModes.removeValue(forKey: origin)
				}
				continue
			}
			// User-hidden: do not re-spawn until the user explicitly shows the pet.
			if userHiddenWindowKeys.contains(origin) { continue }
			if windows[origin] == nil {
				let petId = currentAssignments.resolve(origin: origin)
				let controller: FloatingPetWindowControlling
				if mode(for: origin) == .minimalist {
					guard let minimalistWindowFactory else {
						NSLog("FloatingPetWindowPool: minimalist mode requires a minimalistWindowFactory for \(origin)")
						continue
					}
					controller = minimalistWindowFactory(origin)
				} else {
					controller = windowFactory(origin, petId)
				}
				controller.setFloatingPetVisible(true)
				windows[origin] = controller
				windowSpawnedModes[origin] = mode(for: origin)
			}
			windows[origin]?.apply(state: state.activityState, visualMode: .normal)
			windows[origin]?.applyAttention(
				payload: state.attention,
				sourceEvent: state.sourceEvent
			)
			if mode(for: origin) == .minimalist {
				windows[origin]?.applyPlatform(origin: origin)
			} else if let origin = state.sourceEvent?.origin {
				windows[origin]?.applyPlatform(origin: origin)
			}
		}

		// Step 8: spawn / update combined window
		if !combinedOrigins.isEmpty {
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
				// All combined-mode origins idle past TTL (and not last-active): dismiss
				// the shared window and do not re-spawn it this tick.
				if windows["combined"] != nil {
					windows["combined"]?.setFloatingPetVisible(false)
					windows.removeValue(forKey: "combined")
				}
			} else if !userHiddenWindowKeys.contains("combined") {
				let combinedStates = combinedOrigins.compactMap { visibleEntries[$0] }
				let winner = combinedStates.max(by: { a, b in
					(StateJsonReader.parseISO8601Date(a.updatedAt) ?? .distantPast)
						< (StateJsonReader.parseISO8601Date(b.updatedAt) ?? .distantPast)
				})
				if let winner {
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
			// No combined-mode origins → dismiss combined window if present,
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

	/// Live-swap the rendered pet for one origin's window. Called when the user
	/// reassigns a platform badge in Settings > Pet so only that platform's window
	/// updates; other windows are untouched. Newly spawned windows already pick up
	/// the current assignment via the factory's petId argument.
	func replacePet(origin: String, codexPet: CodexPet, codogotchiPet: CodogotchiPet?) {
		let key = windowKey(for: origin)
		windows[key]?.replacePets(codexPet: codexPet, codogotchiPet: codogotchiPet)
	}

	// MARK: - Private helpers

	private func mode(for origin: String) -> PlatformMode {
		currentCustomization.platformModes[origin] ?? .own
	}

	private func windowKey(for origin: String) -> String {
		mode(for: origin) == .combined ? "combined" : origin
	}

	/// Most-recent lastSeenAt across all origins that map to this window key.
	private func lastSeenForWindow(key: String) -> Date? {
		if key == "combined" {
			let combinedOrigins = currentCustomization.platformModes.keys
				.filter { currentCustomization.platformModes[$0] == .combined }
			return combinedOrigins.compactMap { lastSeenAt[$0] }.max()
		}
		return lastSeenAt[key]
	}
}
