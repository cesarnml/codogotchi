import AppKit

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

	/// Held so `LivePollingDriver` can check sheet availability for gate elevation.
	var codogotchiPet: CodogotchiPet?

	/// Held strongly so the live polling driver's `Timer` is not deallocated.
	/// Nil in demo mode or when the renderer failed to load. Live polling and
	/// the demo cycle are mutually exclusive at launch — only one drives the
	/// renderer at a time.
	var livePollingDriver: LivePollingDriver?

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

	/// Held strongly so the floating panel and its persisted visibility state
	/// stay alive for the lifetime of the menu item target.
	var floatingPetController: FloatingPetController?

	/// Panel shell used for the floating pet; held so the hide prompt can call back.
	var floatingPetPanelController: FloatingPetPanelController?

	/// Held strongly so the first-run onboarding panel controller is not deallocated
	/// while the app runs. Nil after the sheet is dismissed on a non-first-launch.
	var onboardingWindowController: OnboardingWindowController?

	/// Held strongly so the Settings panel is not deallocated while the app runs.
	var settingsWindowController: SettingsWindowController?

	/// Opaque observer token for `NSWorkspace.didWakeNotification`. Held
	/// strongly so the block-based observer is not deallocated while the app
	/// runs, and removed in `applicationWillTerminate` so the workspace
	/// notification center does not retain a dangling block past shutdown.
	var workspaceWakeObserver: NSObjectProtocol?

	/// Held while the floating pet is visible so App Nap does not throttle the
	/// SpriteKit frame timer. Nil when the float is hidden (menubar-only).
	var activity: NSObjectProtocol?

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
			button.image = NSImage(
				systemSymbolName: "pawprint",
				accessibilityDescription: "Codogotchi"
			)
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

		// Seed Maew from the app bundle when the canonical store is absent or incomplete.
		// Runs before pet loading so a clean machine has assets available at first launch.
		if let bundledMaewDir = Self.bundledMaewDirectory() {
			let canonicalPath = CodexPet.defaultPetDirectoryPath()
			if !PetStoreSeeder.isCanonicalStoreComplete(at: canonicalPath) {
				do {
					try PetStoreSeeder.seed(from: bundledMaewDir, into: canonicalPath)
				} catch {
					NSLog("MenubarApp: bundle seed failed — \(error)")
				}
			}
		}

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
			renderer.update(state: .idle, visualMode: .normal)
			self.renderer = renderer

			let floatingPanel = FloatingPetPanelController(
				codexPet: codexPet,
				codogotchiPet: codogotchiPet,
				demoFrameInterval: demoInterval,
				idleEscalationConfig: IdleEscalationConfig.resolve()
			)
			self.floatingPetPanelController = floatingPanel
			let floatingPetController = FloatingPetController(
				panel: floatingPanel,
				visibleFrameProvider: Self.visibleFloatingFrame
			)
			floatingPetController.onVisibilityChanged = { [weak self] visible in
				self?.setFloatingPetAppNapOptOut(active: visible)
			}
			self.floatingPetController = floatingPetController
			setFloatingPetAppNapOptOut(active: floatingPetController.isFloatingPetVisible)
		} catch {
			NSLog(
				"MenubarApp: CodexPet load failed from '%@' — keeping placeholder icon (%@)",
				CodexPet.defaultPetDirectoryPath(),
				String(describing: error)
			)
		}

		let onboardingController = OnboardingWindowController()
		self.onboardingWindowController = onboardingController

		let settingsController = SettingsWindowController()
		settingsController.onPetActivated = { [weak self] _ in
			self?.reloadActivePet()
		}
		self.settingsWindowController = settingsController

		let menuBuilder = MenubarMenu(
			floatingPetController: self.floatingPetController,
			retryHooksInstall: { [weak onboardingController] in
				onboardingController?.showIfNeeded()
			},
			openSettings: { [weak settingsController] in
				settingsController?.show()
			}
		)
		item.menu = menuBuilder.build()
		self.menuBuilder = menuBuilder
		floatingPetPanelController?.onHideFloatingPet = { [weak self] in
			guard let self else { return }
			self.floatingPetController?.setFloatingPetVisible(false)
			self.menuBuilder?.refreshFloatingPetMenuItemTitle()
		}

		let stateFanout = PetStateFanout(
			applyToMenubar: { [weak renderer = self.renderer] state, mode in
				renderer?.update(state: state, visualMode: mode)
			},
			applyToFloatingPet: { [weak floatingPetController = self.floatingPetController] state, mode in
				floatingPetController?.apply(state: state, visualMode: mode)
			}
		)

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
					apply: { state in
						stateFanout.applyDemo(state: state)
					},
					transitionLog: self.transitionLog
				)
				driver.start()
				self.demoDriver = driver
			}
		} else if self.renderer != nil {
			// Live polling — read the hook's `~/.codogotchi/state.json` at 1Hz
			// and route success/failure into renderer + status-item tooltip.
			// Mutually exclusive with demo mode by construction (the `else` arm).
			let gateJsonPath = config.pollingTarget
				.deletingLastPathComponent()
				.appendingPathComponent("gate.json")
				.path
			let deliveryContextPath = config.pollingTarget
				.deletingLastPathComponent()
				.appendingPathComponent("delivery-context.json")
				.path
			let driver = LivePollingDriver(
				pollingTargetPath: config.pollingTarget.path,
				gatePath: gateJsonPath,
				deliveryContextPath: deliveryContextPath,
				apply: { state, mode in
					stateFanout.apply(state: state, visualMode: mode)
				},
				setTooltip: { [weak item] tooltip in
					item?.button?.toolTip = tooltip
				},
				transitionLog: self.transitionLog,
				codogotchiPet: self.codogotchiPet
			)
			driver.applyAttention = { [weak floatingPetController = self.floatingPetController] payload, sourceEvent in
				floatingPetController?.applyAttention(payload: payload, sourceEvent: sourceEvent)
			}
			driver.applyGateBadge = { [weak floatingPetController = self.floatingPetController] content in
				floatingPetController?.applyGateBadge(content: content)
			}
			driver.start()
			self.livePollingDriver = driver
		}

		// Best-effort hook status refresh: shell out to `codogotchi hooks status --json`
		// and cache the snapshot in app-state. Subprocess failure is logged and
		// non-fatal — P5.06 onboarding surfaces this to the user.
		refreshHookStatusCache()

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
	@MainActor
	func reloadActivePet() {
		guard let renderer else { return }
		do {
			let newCodexPet = try CodexPet()
			let newCodogotchiPet = try? CodogotchiPet()
			self.codogotchiPet = newCodogotchiPet
			renderer.replacePets(codexPet: newCodexPet, codogotchiPet: newCodogotchiPet)
			floatingPetPanelController?.replacePets(
				codexPet: newCodexPet, codogotchiPet: newCodogotchiPet)
			livePollingDriver?.replaceCodogotchiPet(newCodogotchiPet)
		} catch {
			NSLog("MenubarApp: reloadActivePet failed — %@", error.localizedDescription)
		}
	}

	/// Opt out of App Nap only while the floating pet is on screen.
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

	func applicationWillTerminate(_ notification: Notification) {
		if let observer = workspaceWakeObserver {
			NSWorkspace.shared.notificationCenter.removeObserver(observer)
			workspaceWakeObserver = nil
		}
		if let activity = activity {
			ProcessInfo.processInfo.endActivity(activity)
			self.activity = nil
		}
		demoDriver?.stop()
		livePollingDriver?.stop()
		transitionLog?.stop()
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

	private static func visibleFloatingFrame() -> CGRect {
		NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
	}
}
