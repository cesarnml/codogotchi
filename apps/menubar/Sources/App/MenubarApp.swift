import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Menu-bar agent entry point.
///
/// Registers an `NSStatusItem` and seeds the canonical pet store from the app
/// bundle before loading. Once pet assets are available at
/// `~/.codogotchi/pets/<pet>/`, hands the status item off to a `MenubarRenderer`
/// that animates the idle row on a continuous loop.
///
/// The app is configured as a menu-bar agent via `LSUIElement = true` in
/// `Info.plist` so it has no Dock icon and no main window.
@main
final class MenubarApp: NSObject, NSApplicationDelegate {
	/// Held strongly so the status item is not deallocated.
	var statusItem: NSStatusItem?

	/// Held strongly so the renderer outlives the launch callback and stays
	/// reachable from the polling driver's update sink. Nil until pet assets
	/// are successfully loaded.
	var renderer: MenubarRenderer?

	/// Held strongly so the demo cycle's `Timer` is not deallocated. Nil
	/// outside demo mode or when the renderer failed to load.
	var demoDriver: DemoCycleDriver?

	/// Held strongly so the HUD demo's `Timer` survives. Non-nil only under
	/// `CODOGOTCHI_HUD_DEMO=1`.
	var hudDemoDriver: HUDDemoDriver?

	/// True while the HUD demo is sweeping RPG values; suppresses the live
	/// poller's RPG updates so they do not fight the demo animation.
	private var hudDemoActive = false

	/// Held strongly so the runtime `hud-pin` sentinel watcher's `Timer` survives.
	private var hudPinWatchTimer: Timer?
	/// Last observed `hud-pin` sentinel state, so the HUD is toggled only on change.
	private var hudPinnedLast = false

	/// Held so `LivePollingDriver` can check sheet availability for gate elevation.
	var codogotchiPet: CodogotchiPet?

	/// Held strongly so the live polling driver's `Timer` is not deallocated.
	/// Nil in demo mode or when the renderer failed to load. Live polling and
	/// the demo cycle are mutually exclusive at launch — only one drives the
	/// renderer at a time.
	var livePollingDriver: LivePollingDriver?

	/// Owns the session/combined/plain-origin targeting policy for
	/// `onAttentionDismissed` / `onForceIdle`, shared by the own-window and
	/// minimalist-window factories so that policy is expressed exactly once
	/// (P17.05). Constructed once pool assets are available.
	var windowActionRouter: WindowActionRouter?

	/// Held strongly so the periodic `state.d/` prune `Timer` survives. Nil in
	/// demo mode (the sandboxed fixture dir is not pruned).
	var slicePruneScheduler: SlicePruneScheduler?

	/// Resolved at launch: tells the app whether to run the demo cycle and
	/// which polling target to read. Exposed for diagnostics; live polling
	/// (P2.07) will also consume `pollingTarget`.
	var demoConfig: DemoConfig?

	/// Holds the NDJSON transition log writer so its heartbeat `Timer` and
	/// lazily-opened file handle survive past `applicationDidFinishLaunching`.
	/// `nil` while a `CodexPet` failure keeps the app on the placeholder
	/// icon — there is no driver to feed the log in that state.
	var transitionLog: TransitionLog?

	/// Held strongly because `NSMenuItem.target` is a weak reference; without
	/// this, the menu items would still appear but their actions would no-op
	/// once `applicationDidFinishLaunching` returned.
	var menuBuilder: MenubarMenu?

	/// Holds the CodexPet loaded at launch so the pool factory can use it
	/// when spawning new per-origin windows (and after `reloadActivePet`).
	var codexPet: CodexPet?

	/// Resolves petId → (CodexPet, CodogotchiPet?) with a shared cache so origins
	/// assigned the same pet share one loaded CodexPet.
	var petAssetResolver: PetAssetResolver?

	/// Manages one floating pet window per active AI-platform origin.
	/// Nil while pet assets are unavailable or in demo mode.
	var floatingPetWindowPool: FloatingPetWindowPool?

	/// Held strongly so the first-run onboarding panel controller is not deallocated
	/// while the app runs. Nil after the sheet is dismissed on a non-first-launch.
	var onboardingWindowController: OnboardingWindowController?

	/// Held strongly so the Settings panel is not deallocated while the app runs.
	var settingsWindowController: SettingsWindowController?

	/// The app's single `customization.json` writer, shared with
	/// `SettingsWindowController`'s `CustomizationTabViewModel`/`GeneralTabViewModel`
	/// so a right-click write below reaches an open Settings tab's subscription —
	/// the replacement for the old throwaway-view-model-plus-NotificationCenter-post
	/// pattern. A stored-property default initializer (no DI params needed here)
	/// so it exists before any closure below captures `self`, regardless of
	/// definition order.
	private let customizationStore = CustomizationStore()

	/// Same `state.d/`-scan tier engine backing Settings → Sessions, also
	/// wired into `MenubarMenu` so the menu bar's Active/Live/Capped tiering
	/// reads the identical rows the Sessions tab shows. Held strongly here
	/// (not just inside `settingsWindowController`) so `menuBuilder`'s weak
	/// reference to it stays valid for the app's lifetime.
	var sessionsTabViewModel: SessionsTabViewModel?

	/// Opaque observer token for `NSWorkspace.didWakeNotification`. Held
	/// strongly so the block-based observer is not deallocated while the app
	/// runs, and removed in `applicationWillTerminate` so the workspace
	/// notification center does not retain a dangling block past shutdown.
	var workspaceWakeObserver: NSObjectProtocol?

	/// Held while the floating pet is visible so App Nap does not throttle the
	/// SpriteKit frame timer. Nil when the float is hidden (menubar-only).
	var activity: NSObjectProtocol?

	/// Low-frequency timer that re-runs `refreshHookStatusCache()` so the menu
	/// item, onboarding panel, and Settings tabs reflect the current install
	/// state instead of freezing at the single launch-time snapshot. Without it
	/// a fresh install never propagated to the UI until the next app launch.
	var hookStatusRefreshTimer: Timer?

	static func main() {
		let app = NSApplication.shared
		let delegate = MenubarApp()
		app.delegate = delegate
		app.setActivationPolicy(.accessory)
		app.run()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		if let button = item.button {
			let initialMonochrome = CustomizationJsonReader.read(
				at: CodogotchiFolders.customizationPath()
			).menubarIconMonochrome
			Self.applyMenubarIcon(to: button, monochrome: initialMonochrome)
		}
		self.statusItem = item

		// Load the pet and wire the renderer. On a clean machine the bundle seed
		// above populates the canonical store; if it fails or the seeder is not
		// available, keep the placeholder `pawprint` icon.
		// Resolve demo config before creating the renderer so we can pass the
		// demo frame interval at construction time — the renderer's timer logic
		// uses it from the first tick.
		let config = DemoConfig.forLaunch()
		self.demoConfig = config

		// First-launch Lite config: write minimal {profile_id, pet, features.rpg_enabled}
		// when missing. Coordinated with bundle seed below so first frame shows Maew
		// without `codogotchi setup`. Soft failure — log and continue.
		do {
			try ConfigBootstrap.ensureLiteConfig()
		} catch {
			NSLog("MenubarApp: ConfigBootstrap.ensureLiteConfig failed — \(error)")
		}

		// Clean up pre-state.d/ legacy artifacts (gate.json, delivery-context.json,
		// and state.json once its RPG data has migrated to rpg-state.json). See
		// LegacyStateFileCleanup for the phase-15 advisory-observation rationale.
		LegacyStateFileCleanup.run()

		// Seed Maew from the app bundle when Maew's canonical store is absent or
		// incomplete. Runs before pet loading so a clean machine has assets
		// available at first launch.
		//
		// Always target Maew's own directory — never `CodexPet.defaultPetDirectoryPath()`,
		// which resolves to the *active* pet. Seeding into the active pet's directory
		// pollutes Codex-tier custom pets (e.g. an imported `mali` that ships only
		// `spritesheet.webp`) with Maew's lite/SoA sheets, making them falsely render
		// codogotchi-tier animations.
		if let bundledMaewDir = Self.bundledMaewDirectory() {
			let maewPath = Self.canonicalMaewDirectoryPath()
			if !PetStoreSeeder.isCanonicalStoreComplete(at: maewPath) {
				do {
					try PetStoreSeeder.seed(from: bundledMaewDir, into: maewPath)
				} catch {
					NSLog("MenubarApp: bundle seed failed — \(error)")
				}
			}
		}

		// Seed assignments.json from config.pet on first launch. Must run before
		// pool creation so the pool's first tick reads a valid assignments file.
		// Use CodogotchiFolders so CODOGOTCHI_HOME overrides are respected for both URLs.
		AssignmentsMigration.seedIfAbsent(
			assignmentsURL: URL(fileURLWithPath: CodogotchiFolders.assignmentsPath()),
			configURL: CodogotchiFolders.dataFolderURL().appendingPathComponent("config.json")
		)

		do {
			let codexPet = try CodexPet()
			// Soft degrade: if the codogotchi pet directory is absent or its
			// sheets are missing, pass nil — states fall back to Codex or idle
			// until the sheets are installed at the default path.
			let codogotchiPet = try? CodogotchiPet()
			self.codogotchiPet = codogotchiPet
			if codogotchiPet == nil {
				NSLog(
					"MenubarApp: CodogotchiPet not available — codogotchi-owned states render as idle"
				)
			}
			let demoInterval: TimeInterval? = config.isDemoMode
				? Double(DemoConfig.demoFrameMs(from: ProcessInfo.processInfo.environment)) / 1000.0
				: nil
			let renderer = MenubarRenderer(
				codexPet: codexPet, codogotchiPet: codogotchiPet,
				sink: { [weak item] image in
					item?.button?.image = image
				}
			)
			renderer.setStaticMode()
			self.renderer = renderer

			self.codexPet = codexPet
			let resolver = PetAssetResolver()
			self.petAssetResolver = resolver
			// Closures capture `self` weakly and read `floatingPetWindowPool`
			// lazily — safe even though the pool below is constructed after
			// the router, because these bodies only run once the pool (and
			// the window factories that use the router) exist.
			let router = WindowActionRouter(
				stateDir: { config.pollingTarget.path },
				resetPromptTimer: { [weak self] key in
					self?.floatingPetWindowPool?.resetPromptTimer(forWindowKey: key)
				},
				combinedModeOrigins: { [weak self] in
					self?.floatingPetWindowPool?.combinedModeOrigins() ?? []
				},
				clearAttentionBubbles: { [weak self] key in
					self?.floatingPetWindowPool?.clearAttentionBubbles(sharingOriginWith: key)
				}
			)
			self.windowActionRouter = router
			let pool = FloatingPetWindowPool(
				windowFactory: { [weak self] origin, petId in
					guard let self else {
						fatalError("FloatingPetWindowPool factory called after app teardown")
					}
					let (resolvedCodexPet, resolvedCodogotchiPet): (CodexPet, CodogotchiPet?)
					if let pair = try? self.petAssetResolver?.resolve(petId: petId) {
						resolvedCodexPet = pair.0
						resolvedCodogotchiPet = pair.1
					} else if let fallback = self.codexPet {
						resolvedCodexPet = fallback
						resolvedCodogotchiPet = self.codogotchiPet
					} else {
						fatalError("FloatingPetWindowPool factory: no pet assets available")
					}
					// Reuses the config the pool already resolved this same tick
					// (Step 7 spawns happen after the pool's own resolve, well
					// before this factory could ever run) instead of
					// independently re-reading and re-decoding
					// customization.json from disk — avoiding both the
					// redundant I/O and the risk of disagreeing with the value
					// just pushed to every other open window.
					let panel = FloatingPetPanelController(
						codexPet: resolvedCodexPet,
						codogotchiPet: resolvedCodogotchiPet,
						demoFrameInterval: nil,
						idleEscalationConfig: self.floatingPetWindowPool?.resolvedIdleEscalationConfig ?? .production,
						initialIdleAge: IdleEscalationConfig.backdateSeconds()
					)
					let savedFrame = AppStateStore.loadFrame(
						for: origin, visibleFrame: Self.visibleFloatingFrame())
					let controller = FloatingPetController(
						panel: panel,
						visibleFrameProvider: Self.visibleFloatingFrame,
						saveState: { state in
							try AppStateStore.saveFrame(state.frame, for: origin)
						},
						initialState: FloatingAppState(
							isFloatingPetVisible: false, frame: savedFrame)
					)
					controller.onVisibilityChanged = { [weak self] _ in
						self?.updateAppNapOptOut()
					}
					self.wirePanelActions(
						panel,
						for: origin,
						stateDirectory: config.pollingTarget.path,
						modeSwitch: { app in
							if let platformOrigin = FloatingPetWindowPool.modeSwitchOrigin(forWindowKey: origin) {
								app.customizationStore.setMode(.minimalist, for: platformOrigin)
							} else {
								app.customizationStore.setCombinedMinimalistEnabled(true)
							}
						},
						hideWindow: { app in
							app.floatingPetWindowPool?.setVisible(false, for: origin)
						}
					)
					return controller
				},
				minimalistWindowFactory: { [weak self] origin in
					let panel = MinimalistPanelController(visibleFrameProvider: Self.visibleFloatingFrame)
					// Right-click "Panel Size…" slider pill: persists the same
					// global minimalist_badge_scale the Customization tab's slider
					// writes, so every Minimalist strip resizes, not just this one
					// (the clicked strip live-applies in the panel; siblings follow
					// on their next poll tick). The Settings re-sync notification
					// is deferred to the gesture's final tick — per-tick posts
					// would make an open Customization tab re-read the file for
					// every pixel of the drag.
					panel.onPanelSizeChanged = { [weak self] scale, isFinal in
						// Persists every tick (so the on-disk value tracks the drag even
						// if the app quits mid-gesture) but only publishes on the final
						// tick — per-tick publication would make an open Customization
						// tab re-read the file for every pixel of the drag.
						self?.customizationStore.setMinimalistBadgeScale(scale, notify: isFinal)
					}
					let savedFrame = AppStateStore.loadFrame(
						for: origin, visibleFrame: Self.visibleFloatingFrame())
					let controller = MinimalistWindowController(
						origin: origin,
						panel: panel,
						visibleFrameProvider: Self.visibleFloatingFrame,
						saveState: { state in
							try AppStateStore.saveFrame(state.frame, for: origin)
						},
						initialState: FloatingAppState(
							isFloatingPetVisible: false, frame: savedFrame)
					)
					controller.onVisibilityChanged = { [weak self] _ in
						self?.updateAppNapOptOut()
					}
					self?.wirePanelActions(
						panel,
						for: origin,
						stateDirectory: config.pollingTarget.path,
						modeSwitch: { app in
							if let platformOrigin = FloatingPetWindowPool.modeSwitchOrigin(forWindowKey: origin) {
								app.customizationStore.setMode(.own, for: platformOrigin)
							} else {
								app.customizationStore.setCombinedMinimalistEnabled(false)
							}
						},
						hideWindow: { app in
							app.floatingPetWindowPool?.setVisible(false, for: origin)
						}
					)
					return controller
				},
				retrievedSessionTitleReader: { RetrievedSessionTitleStore.title(for: $0.rawValue) },
				retrievedSessionTitleWriter: { key, title in
					RetrievedSessionTitleStore.setTitle(title, for: key.rawValue)
				},
				hiddenKeysLoader: { AppStateStore.loadHiddenWindowKeys() },
				hiddenKeysSaver: { try? AppStateStore.saveHiddenWindowKeys($0) }
			)
			pool.onMonochromeChanged = { [weak item] isMonochrome in
				if let button = item?.button { Self.applyMenubarIcon(to: button, monochrome: isMonochrome) }
			}
			self.floatingPetWindowPool = pool
		} catch {
			NSLog(
				"MenubarApp: CodexPet load failed from '%@' — keeping placeholder icon (%@)",
				CodexPet.defaultPetDirectoryPath(),
				String(describing: error)
			)
		}

		let onboardingController = OnboardingWindowController()
		self.onboardingWindowController = onboardingController

		// Explicit "Show" restarts the dismiss-TTL clock on the window's
		// backing slice(s) so a pet that expired while hidden actually
		// re-spawns; same window-key targeting as Force Idle (session-keyed
		// → exactly that slice, combined/plain → that window's origin set).
		// Shared by the menubar's "Show … Pet" items and the Settings →
		// Sessions tab's per-row/bulk "Show" actions.
		let refreshTtlForShow: (WindowKey) -> Void = { [weak self] windowKey in
			let stateDir = config.pollingTarget.path
			if let identity = windowKey.sessionIdentity {
				StateJsonWriter.refreshForShow(
					at: stateDir, origin: identity.origin, sessionId: identity.sessionId)
			} else {
				StateJsonWriter.refreshForShow(
					at: stateDir,
					origins: self?.resolveWindowOrigins(windowKey: windowKey) ?? [windowKey.origin]
				)
			}
		}

		let sessionsTabViewModel = SessionsTabViewModel(
			stateDirectoryPath: config.pollingTarget.path,
			pool: self.floatingPetWindowPool,
			refreshTtlForShow: refreshTtlForShow
		)
		self.sessionsTabViewModel = sessionsTabViewModel

		let settingsController = SettingsWindowController(
			customizationStore: customizationStore,
			sessionsTabViewModel: sessionsTabViewModel
		)
		settingsController.onPetActivated = { [weak self] _ in
			self?.reloadActivePet()
		}
		settingsController.onRPGHUDModeChanged = { _ in
			// Pool reads PetConfig.resolvedRPGHUDMode() on each tick; no direct wire needed.
		}
		settingsController.onMonochromeChanged = { [weak item] isMonochrome in
			if let button = item?.button { Self.applyMenubarIcon(to: button, monochrome: isMonochrome) }
		}
		self.settingsWindowController = settingsController

		let menuBuilder = MenubarMenu(
			floatingPetPool: self.floatingPetWindowPool,
			sessionsTabViewModel: sessionsTabViewModel,
			retryHooksInstall: { [weak onboardingController] in
				onboardingController?.showIfNeeded()
			},
			openSettings: { [weak settingsController] tab in
				settingsController?.show(tab: tab)
			},
			refreshTtlForShow: refreshTtlForShow,
			// On menu open, drop hidden keys whose slice SlicePruner already
			// deleted — past the 24h horizon there is nothing left for Show
			// (or refreshForShow) to act on, so the entry would be a lie.
			pruneOrphanHiddenKeys: { [weak self] in
				self?.floatingPetWindowPool?.pruneHiddenKeysWithoutBackingSlice(
					stateDirectory: config.pollingTarget.path)
			}
		)
		item.menu = menuBuilder.build()
		self.menuBuilder = menuBuilder

		// Demo mode: re-point the polling target to a sandboxed file and run
		// the fixture cycle driver. P2.07 will own live polling against the
		// non-demo `pollingTarget`.
		if self.renderer != nil {
			// Demo mode writes its log under a sandboxed sibling of its
			// `pollingTarget` so a live run is never trampled by a demo
			// session.
			let logPath: URL = {
				if config.isDemoMode {
					return config.pollingTarget
						.deletingLastPathComponent()
						.appendingPathComponent("state-transitions.log")
				}
				return TransitionLog.defaultPath()
			}()
			let log = TransitionLog(path: logPath)
			log.start()
			self.transitionLog = log
		}
		if config.isDemoMode, self.renderer != nil {
			let fixtures = Self.bundledDemoFixturesDirectory()
			if let fixturesDirectory = fixtures {
				let contents =
					(try? FileManager.default.contentsOfDirectory(atPath: fixturesDirectory.path))
					?? []
				let driver = DemoCycleDriver(
					sandboxedPath: config.pollingTarget,
					fixturesDirectory: fixturesDirectory,
					apply: { [weak renderer = self.renderer] state in
						renderer?.update(state: state, visualMode: .normal)
					},
					tickInterval: DemoConfig.demoTickSeconds(
						from: ProcessInfo.processInfo.environment
					),
					transitionLog: self.transitionLog
				)
				driver.start()
				self.demoDriver = driver
			}
		} else if self.renderer != nil {
			// Live polling — read the hook's `~/.codogotchi/state.json` at 1Hz
			// and route success/failure into renderer + status-item tooltip.
			// Mutually exclusive with demo mode by construction (the `else` arm).
			// Gate and context files are discovered by the driver from state.d/
			// (per-platform+session `origin:session_id.{gate,context}.json`), with
			// legacy flat-file fallback for installs without the new SoA hook.
			let legacyGatePath = config.pollingTarget
				.deletingLastPathComponent()
				.appendingPathComponent("gate.json")
				.path
			let legacyContextPath = config.pollingTarget
				.deletingLastPathComponent()
				.appendingPathComponent("delivery-context.json")
				.path
			let driver = LivePollingDriver(
				pollingTargetPath: config.pollingTarget.path,
				gatePath: legacyGatePath,
				deliveryContextPath: legacyContextPath,
				apply: { [weak renderer = self.renderer] state, mode in
					renderer?.update(state: state, visualMode: mode)
				},
				setTooltip: { [weak item] tooltip in
					item?.button?.toolTip = tooltip
				},
				transitionLog: self.transitionLog,
				codogotchiPet: self.codogotchiPet
			)
			driver.applyPerPlatform = { [weak self] snapshot in
				guard self?.hudDemoActive != true else { return }
				self?.floatingPetWindowPool?.update(snapshot: snapshot)
				self?.menuBuilder?.refreshFloatingPetMenuItemTitle()
			}
			driver.start()
			self.livePollingDriver = driver

			// Session slices in state.d/ are never removed by the hooks, so they
			// accumulate one-per-session forever. Prune the ones the reader already
			// ignores (mtime past its staleTTL) on launch and periodically, keeping
			// the per-tick scan and the winner-only writers cheap.
			let pruneScheduler = SlicePruneScheduler(
				dir: config.pollingTarget.path,
				maxAgeProvider: {
					TimeInterval(
						CustomizationJsonReader.read(at: CodogotchiFolders.customizationPath())
							.pruneArchivedSessionsAfterSeconds)
				}
			)
			pruneScheduler.start()
			self.slicePruneScheduler = pruneScheduler
		}

		// HUD demo (developer convenience): pin the floating pet + HUD and sweep
		// RPG values for 120s. Independent of `CODOGOTCHI_DEMO`.
		if ProcessInfo.processInfo.environment["CODOGOTCHI_HUD_DEMO"] == "1" {
			startHUDDemo()
		}

		// Float-on-launch (developer convenience): no-op in P13.04 multi-pet mode;
		// pool spawns windows when applyPerPlatform fires on first poll tick.

		// Runtime HUD pin: while `~/.codogotchi/hud-pin` exists, force the floating
		// pet + HUD visible regardless of hover — without suppressing live RPG
		// updates (so a scripted demo like `tcha` keeps driving hearts/level).
		// Checked on a light 0.5s cadence and toggled only on change.
		let hudPinPath = config.pollingTarget
			.deletingLastPathComponent()
			.appendingPathComponent("hud-pin")
			.path
		let applyHUDPin: (Bool) -> Void = { [weak self] pinned in
			guard let self, pinned != self.hudPinnedLast else { return }
			self.hudPinnedLast = pinned
			// HUD pin in multi-pet mode: no-op (pool manages window lifecycle)
		}
		applyHUDPin(FileManager.default.fileExists(atPath: hudPinPath))
		hudPinWatchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
			Task { @MainActor in
				applyHUDPin(FileManager.default.fileExists(atPath: hudPinPath))
			}
		}

		// Best-effort hook status refresh: shell out to `codogotchi hooks status --json`
		// and cache the snapshot in app-state. Subprocess failure is logged and
		// non-fatal — P5.06 onboarding surfaces this to the user.
		refreshHookStatusCache()

		// Re-run the status refresh on a low-frequency cadence so the cached
		// snapshot doesn't freeze at launch. The status subprocess is cheap but
		// not free, so this runs every 30s — far below the live-poll 1Hz cadence
		// — which is plenty for install-state changes to reach the UI.
		hookStatusRefreshTimer = Timer.scheduledTimer(
			withTimeInterval: 30.0,
			repeats: true
		) { [weak self] _ in
			Task { @MainActor in self?.refreshHookStatusCache() }
		}

		// Show first-run onboarding sheet when onboardingCompletedAt is absent.
		// Must run after hook status refresh so the sheet has fresh snapshot context.
		onboardingController.showIfNeeded()

		// Wake-from-sleep: trigger an immediate out-of-band poll so the
		// menu bar pet reflects current state without waiting up to one
		// second after wake for the next scheduled tick. Sleep itself
		// needs no handler — `Timer` pauses naturally while the system is
		// asleep, so polling resumes on wake regardless.
		self.workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
			forName: NSWorkspace.didWakeNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.livePollingDriver?.pollNow()
		}
	}

	/// Reload the active pet from the canonical store and repaint all renderers.
	/// Called when the user selects a different pet in Settings.
	///
	/// Loading a pet decodes its spritesheet(s) and slices every animation row
	/// up front (~hundreds of ms each, per `CodexPet.prewarmFloatingInteractionFrameCache`).
	/// Doing that synchronously on the main thread — once for the default pet
	/// and once per active floating-pet origin, since assignment used to evict
	/// the whole resolver cache — froze the whole app (spinning beach ball) for
	/// several seconds on every single assignment. The actual decode/slice work
	/// now runs off the main thread; only the cheap pointer-swap/UI steps below
	/// stay on the main actor.
	@MainActor
	func reloadActivePet() {
		guard let renderer, let petAssetResolver else { return }
		let assignments = AssignmentsJsonReader.read(at: CodogotchiFolders.assignmentsPath())
		// Active window keys may be per-session (`origin:session_id`); pet identity
		// is per-origin, so fold the keys down to their owning origins before
		// resolving — `replacePet(origin:)` then fans back out to every session
		// window of that origin.
		let origins = Set(
			(floatingPetWindowPool?.activeOrigins ?? [])
				.map { $0.origin }
		)
		let originPetIds = Dictionary(uniqueKeysWithValues: origins.map { ($0, assignments.resolve(origin: $0)) })
		let petIdsToReload = Set(originPetIds.values)

		Task.detached(priority: .userInitiated) {
			let newCodexPet = try? CodexPet()
			let newCodogotchiPet = try? CodogotchiPet()
			var freshPairs: [String: (CodexPet, CodogotchiPet?)] = [:]
			for petId in petIdsToReload {
				freshPairs[petId] = try? petAssetResolver.loadFresh(petId: petId)
			}

			await MainActor.run { [weak self] in
				guard let self, let newCodexPet else {
					NSLog("MenubarApp: reloadActivePet failed to load the default pet")
					return
				}
				self.codexPet = newCodexPet
				self.codogotchiPet = newCodogotchiPet
				renderer.replacePets(codexPet: newCodexPet, codogotchiPet: newCodogotchiPet)
				self.livePollingDriver?.replaceCodogotchiPet(newCodogotchiPet)
				// Evict, then reinsert only the pets we just reloaded — leaves
				// any other still-cached, unaffected pet alone.
				petAssetResolver.evictAll()
				for (petId, pair) in freshPairs {
					petAssetResolver.insert(petId: petId, pair: pair)
				}
				for (origin, petId) in originPetIds {
					if let pair = freshPairs[petId] {
						self.floatingPetWindowPool?.replacePet(
							origin: origin, codexPet: pair.0, codogotchiPet: pair.1)
					}
				}
				self.menuBuilder?.refreshFloatingPetMenuItemTitle()
			}
		}
	}

	/// Opt out of App Nap when any pool window is visible; opt back in when all are hidden.
	///
	/// `onVisibilityChanged` (which calls this) fires synchronously from inside
	/// `PoolApply.apply`, while that call still holds an exclusive `inout`
	/// access on `FloatingPetWindowPool.windows` — the same storage
	/// `activeOrigins` reads. Reading it in the same call frame is a Swift
	/// exclusivity violation (fatal at runtime). Deferring to the next run
	/// loop turn lets `apply` return and release the access first.
	@MainActor
	private func updateAppNapOptOut() {
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			let anyVisible = !(self.floatingPetWindowPool?.activeOrigins.isEmpty ?? true)
			setFloatingPetAppNapOptOut(active: anyVisible)
		}
	}

	/// Wires the action surface shared by Own and Minimalist renderers. Shape
	/// differences are passed as the two closures; all identity targeting and
	/// side-effect wiring otherwise lives here exactly once.
	@MainActor
	private func wirePanelActions(
		_ panel: PanelActionHandling,
		for origin: WindowKey,
		stateDirectory: String,
		modeSwitch: @escaping (MenubarApp) -> Void,
		hideWindow: @escaping (MenubarApp) -> Void
	) {
		panel.onAttentionDismissed = { [weak self] in
			self?.windowActionRouter?.handleAttentionDismissed(for: origin)
		}
		panel.onForceIdle = { [weak self, weak panel] in
			self?.windowActionRouter?.handleForceIdle(for: origin)
			panel?.applyGateBadge(content: nil)
			panel?.applyConflictBubble(nil)
		}
		panel.onRenameRequested = { newLabel in
			SessionLabelStore.setLabel(newLabel, for: origin.rawValue)
		}
		panel.onSyncLabelRequested = {
			guard let identity = origin.sessionIdentity,
				let title = SessionTitleResolver.title(
					forOrigin: identity.origin, sessionId: identity.sessionId)
			else { return }
			SessionLabelStore.setLabelExemptFromCap(title, for: origin.rawValue)
		}
		panel.onPruneRequested = { [weak self] in
			self?.floatingPetWindowPool?.pruneSession(
				windowKey: origin, stateDirectory: stateDirectory)
		}
		panel.onHideAllOtherPetsRequested = { [weak self] in
			self?.floatingPetWindowPool?.hideAllOtherWindows(keepVisible: origin)
		}
		panel.onModeSwitchRequested = { [weak self] in
			guard let self else { return }
			modeSwitch(self)
		}
		panel.onOpenSettingsRequested = { [weak self] in
			self?.settingsWindowController?.show(tab: .customization)
		}
		panel.onHideWindowRequested = { [weak self] in
			guard let self else { return }
			hideWindow(self)
			self.menuBuilder?.refreshFloatingPetMenuItemTitle()
		}
	}

	/// Resolves a window's `state.d/` origins for the winner-only writers
	/// (`forceIdle` / `dismissAttention`). The shared combined window folds every
	/// combined-mode origin into one pet, so it expands to that live set; any other
	/// window key (plain origin or per-session `origin:session_id`) resolves to its
	/// owning origin, whose winner slice the writers target.
	@MainActor
	private func resolveWindowOrigins(windowKey: WindowKey) -> Set<String> {
		if windowKey == .combined {
			return Set(floatingPetWindowPool?.combinedModeOrigins() ?? [])
		}
		return [windowKey.origin]
	}

	private func setFloatingPetAppNapOptOut(active: Bool) {
		if active {
			guard activity == nil else { return }
			activity = ProcessInfo.processInfo.beginActivity(
				options: [.userInitiated, .latencyCritical],
				reason: "codogotchi floating pet animation"
			)
		} else if let activity {
			ProcessInfo.processInfo.endActivity(activity)
			self.activity = nil
		}
	}

	/// Pin the floating pet + HUD and run the RPG-HUD animation for developer
	/// inspection. In multi-pet mode targets the first active pool window.
	@MainActor
	private func startHUDDemo() {
		guard let pool = floatingPetWindowPool,
			let origin = pool.activeOrigins.first,
			let controller = pool.controller(for: origin) as? FloatingPetController
		else {
			NSLog("MenubarApp: HUD demo requested but no pool window is active")
			return
		}
		hudDemoActive = true
		controller.setHUDDemoActive(true)
		let levelSeconds = DemoConfig.hudDemoLevelSeconds(
			from: ProcessInfo.processInfo.environment
		)
		let heartsFull = DemoConfig.hudDemoHeartsFull(
			from: ProcessInfo.processInfo.environment
		)
		let driver = HUDDemoDriver(
			apply: { [weak controller] halfHearts, levelFraction, level, activeMinutes in
				controller?.applyRPGState(
					halfHearts: halfHearts,
					levelFraction: levelFraction,
					level: level,
					activeMinutes: activeMinutes,
					hudEnabled: true
				)
			},
			onComplete: { [weak self, weak controller] in
				controller?.setHUDDemoActive(false)
				self?.hudDemoActive = false
				self?.hudDemoDriver = nil
			},
			secondsPerLevel: levelSeconds,
			heartsFull: heartsFull
		)
		driver.start()
		self.hudDemoDriver = driver
	}

	func applicationWillTerminate(_ notification: Notification) {
		if let observer = workspaceWakeObserver {
			NSWorkspace.shared.notificationCenter.removeObserver(observer)
			workspaceWakeObserver = nil
		}
		if let activity = activity {
			ProcessInfo.processInfo.endActivity(activity)
			self.activity = nil
		}
		hookStatusRefreshTimer?.invalidate()
		hookStatusRefreshTimer = nil
		demoDriver?.stop()
		livePollingDriver?.stop()
		transitionLog?.stop()
	}

	/// Canonical on-disk directory for the bundled Maew pet
	/// (`$CODOGOTCHI_HOME/pets/maew/` or `~/.codogotchi/pets/maew/`). Mirrors
	/// `CodexPet.defaultPetDirectoryPath()` but pins the pet name to `maew`
	/// instead of the active pet so seeding never touches another pet's store.
	private static func canonicalMaewDirectoryPath() -> String {
		let base: URL
		if let cStr = getenv("CODOGOTCHI_HOME"), let home = String(validatingUTF8: cStr) {
			base = URL(fileURLWithPath: home)
		} else {
			base = FileManager.default.homeDirectoryForCurrentUser
				.appendingPathComponent(".codogotchi")
		}
		return base
			.appendingPathComponent("pets")
			.appendingPathComponent(DEFAULT_PET_NAME)
			.path
	}

	/// Locate the bundled Maew pet directory at `Resources/maew/`.
	/// Returns nil when the resource directory is absent (partial build or test context).
	private static func bundledMaewDirectory() -> URL? {
		guard let resources = Bundle.main.resourceURL else { return nil }
		let candidate = resources.appendingPathComponent("maew", isDirectory: true)
		var isDir: ObjCBool = false
		guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
			isDir.boolValue
		else { return nil }
		return candidate
	}

	/// Locate the demo fixture directory bundled into `Resources/state-json/`.
	/// Returns nil when the app is run from a context without the resource
	/// directory (e.g. a partial build), so the caller can degrade cleanly.
	private static func bundledDemoFixturesDirectory() -> URL? {
		guard let resources = Bundle.main.resourceURL else { return nil }
		let candidate = resources.appendingPathComponent("state-json", isDirectory: true)
		var isDir: ObjCBool = false
		guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
			isDir.boolValue
		else {
			return nil
		}
		return candidate
	}

	@MainActor
	private func refreshHookStatusCache() {
		let client = HookStatusClient()
		let snapshot: HooksStatusSnapshot
		do {
			snapshot = try client.fetch()
		} catch {
			NSLog("MenubarApp: hooks status refresh failed — \(error)")
			return
		}

		let current = AppStateStore.load(visibleFrame: Self.visibleFloatingFrame())
		let observed = [
			snapshot.codex, snapshot.claudeCode, snapshot.cursor,
			snapshot.vscode, snapshot.antigravity,
		]
		.compactMap(\.lastEventAt)
		.max()
		let lastActivity = observed ?? current.lastHookActivityAt
		let next = FloatingAppState(
			isFloatingPetVisible: current.isFloatingPetVisible,
			frame: current.frame,
			onboardingCompletedAt: current.onboardingCompletedAt,
			lastHookActivityAt: lastActivity,
			hooksStatus: snapshot,
			installedHookVersion: current.installedHookVersion
		)
		do {
			try AppStateStore.save(next)
		} catch {
			NSLog("MenubarApp: app-state save after hook refresh failed — \(error)")
		}

		// Update "Hooks not active" menu item: only visible after onboarding completes
		// and hooks aren't yet firing, so the user knows to retry.
		if next.onboardingCompletedAt != nil {
			menuBuilder?.refreshHooksNotActive(isActive: !snapshot.isHooksNotActive())
		}
		onboardingWindowController?.updateHookStatus(snapshot)
		settingsWindowController?.updateHookStatus(snapshot)
	}

	/// Union of every attached display's visible frame, so drag-clamping (see
	/// `FloatingPetPanel.clampedFrame`) confines a panel to the combined
	/// desktop area rather than a single screen. `NSScreen.main` names the
	/// screen with current keyboard focus, not the display a floating panel
	/// happens to sit on or is being dragged toward — anchoring the clamp to
	/// it made panels appear locked to whichever screen had focus at launch,
	/// since the clamped frame could never cross into a neighboring display.
	private static func visibleFloatingFrame() -> CGRect {
		guard !NSScreen.screens.isEmpty else {
			return CGRect(x: 0, y: 0, width: 800, height: 600)
		}
		return NSScreen.screens
			.map(\.visibleFrame)
			.reduce(CGRect.null) { $0.union($1) }
	}

	/// Sets the status-item button image to the Codogotchi app icon, sized to
	/// the menu-bar thickness so the mark reads at a comparable weight to system
	/// menu-bar icons. The app icon carries its own internal padding, so sizing
	/// to the full bar thickness (rather than a hard-coded 18pt, which floated
	/// small and undersized next to neighbors like the calendar) lets that
	/// intrinsic margin supply the breathing room.
	///
	/// When `monochrome` is true the same icon is rendered in grayscale
	/// (saturation collapsed via Core Image) — shape and shading are preserved,
	/// only the color is removed, so the icon does not change form when the
	/// setting is toggled. It is intentionally NOT a template image: a template
	/// flattens the icon to a single-color silhouette (the full app icon's alpha
	/// is a solid rounded square, which renders as a filled block) and cannot
	/// carry grayscale shading. The grayscale image is fixed, so it does not
	/// invert on selection.
	static func applyMenubarIcon(to button: NSStatusBarButton, monochrome: Bool) {
		let side = NSStatusBar.system.thickness
		let base = NSApp.applicationIconImage.copy() as? NSImage ?? NSImage()
		let icon = monochrome ? (Self.desaturated(base) ?? base) : base
		icon.size = NSSize(width: side, height: side)
		icon.isTemplate = false
		button.image = icon
	}

	/// Returns a grayscale copy of `image` by collapsing saturation to zero via
	/// Core Image, mirroring `MenubarRenderer.desaturate`. Returns nil when the
	/// image cannot be bridged to a `CGImage` or the filter produces no output,
	/// so callers can fall back to the original color image.
	private static func desaturated(_ image: NSImage) -> NSImage? {
		guard
			let cgImage = image.cgImage(
				forProposedRect: nil,
				context: nil,
				hints: nil
			)
		else {
			return nil
		}
		let filter = CIFilter.colorControls()
		filter.inputImage = CIImage(cgImage: cgImage)
		filter.saturation = 0
		let context = CIContext(options: nil)
		guard
			let output = filter.outputImage,
			let outputCG = context.createCGImage(output, from: output.extent)
		else {
			return nil
		}
		return NSImage(cgImage: outputCG, size: image.size)
	}
}
