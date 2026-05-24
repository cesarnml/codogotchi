import AppKit
import QuartzCore

/// Menu-bar agent entry point.
///
/// Registers an `NSStatusItem` and, when the pet assets are present at
/// `~/.codex/pets/mali/`, hands the status item off to a `MenubarRenderer`
/// that animates the idle row on a 1-second-per-cycle continuous loop.
/// Later Phase 02 tickets (P2.06 demo driver, P2.07 live polling) call
/// `renderer.update(state:visualMode:)` to switch states.
///
/// The app is configured as a menu-bar agent via `LSUIElement = true` in
/// `Info.plist` so it has no Dock icon and no main window.
@main
final class MenubarApp: NSObject, NSApplicationDelegate {
	/// Held strongly so the status item is not deallocated.
	var statusItem: NSStatusItem?

	/// Held strongly so the renderer's timer survives past the lifecycle
	/// callback. Nil until pet assets are successfully loaded.
	var renderer: MenubarRenderer?

	/// Held strongly so the demo cycle's `Timer` is not deallocated. Nil
	/// outside demo mode or when the renderer failed to load.
	var demoDriver: DemoCycleDriver?

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
	/// `nil` while a `MaliPet` failure keeps the app on the placeholder
	/// icon — there is no driver to feed the log in that state.
	var transitionLog: TransitionLog?

	/// Held strongly because `NSMenuItem.target` is a weak reference; without
	/// this, the menu items would still appear but their actions would no-op
	/// once `applicationDidFinishLaunching` returned.
	var menuBuilder: MenubarMenu?

	/// Opaque observer token for `NSWorkspace.didWakeNotification`. Held
	/// strongly so the block-based observer is not deallocated while the app
	/// runs, and removed in `applicationWillTerminate` so the workspace
	/// notification center does not retain a dangling block past shutdown.
	var workspaceWakeObserver: NSObjectProtocol?

	/// Held strongly to keep `ProcessInfo.beginActivity(...)` alive — without
	/// it, macOS App Nap can throttle the renderer's 8 Hz animation timer
	/// (manifesting as the pet animating for one cycle, vanishing for a
	/// second or so, then animating again).
	var activity: NSObjectProtocol?

	static func main() {
		let app = NSApplication.shared
		let delegate = MenubarApp()
		app.delegate = delegate
		app.setActivationPolicy(.accessory)
		app.run()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		// Disable App Nap so the renderer's animation timer fires at a steady
		// 8 Hz. As an LSUIElement agent with no visible window we are a prime
		// App Nap target; without this opt-out the pet animates for ~1 second
		// then freezes/disappears for ~1 second in a repeating cycle.
		self.activity = ProcessInfo.processInfo.beginActivity(
			options: [.userInitiated, .latencyCritical],
			reason: "codogotchi menubar pet animation"
		)

		let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		if let button = item.button {
			button.image = NSImage(
				systemSymbolName: "pawprint",
				accessibilityDescription: "Codogotchi"
			)
		}
		let menuBuilder = MenubarMenu()
		item.menu = menuBuilder.build()
		self.menuBuilder = menuBuilder
		self.statusItem = item

		// Attempt to load Mali and wire the renderer. If pet assets are
		// missing (e.g. on a dev machine without `~/.codex/pets/mali/`
		// populated), keep the placeholder `pawprint` icon — the renderer
		// is optional Phase 02 scaffolding, not a hard launch requirement.
		do {
			let codexPet = try MaliPet()
			// Soft degrade: if the codogotchi pet directory is absent or its
			// spritesheet is missing, pass nil — the nine SoA-owned states fall
			// back to idle until the sheet is installed at the default path.
			let codogotchiPet = try? CodogotchiPet()
			if codogotchiPet == nil {
				NSLog(
					"MenubarApp: CodogotchiPet not available — codogotchi-owned states render as idle"
				)
			}
			let renderer = MenubarRenderer(codexPet: codexPet, codogotchiPet: codogotchiPet) {
				[weak item] image in
				let t = CACurrentMediaTime()
				let hasButton = item?.button != nil
				dbgLog(
					"DBG t=\(t) sink: hasItem=\(item != nil) hasButton=\(hasButton) in=\(image.size.width)x\(image.size.height)"
				)
				item?.button?.image = image
				let actual = item?.button?.image?.size
				let win = item?.button?.window
				dbgLog(
					"DBG t=\(t) sink: after-set actual=\(actual?.width ?? -1)x\(actual?.height ?? -1) windowVisible=\(win?.isVisible ?? false) buttonHidden=\(item?.button?.isHidden ?? true)"
				)
			}
			renderer.update(state: .idle, visualMode: .normal)
			self.renderer = renderer
		} catch {
			NSLog("MenubarApp: MaliPet load failed — keeping placeholder icon (\(error))")
		}

		// Demo mode: re-point the polling target to a sandboxed file and run
		// the fixture cycle driver. P2.07 will own live polling against the
		// non-demo `pollingTarget`.
		let config = DemoConfig.forLaunch()
		self.demoConfig = config
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
		dbgLog(
			"DBG MenubarApp: branching — isDemoMode=\(config.isDemoMode) rendererLoaded=\(self.renderer != nil)"
		)
		if config.isDemoMode, let renderer = self.renderer {
			let fixtures = Self.bundledDemoFixturesDirectory()
			dbgLog(
				"DBG MenubarApp.demo: bundleResourceURL=\(Bundle.main.resourceURL?.path ?? "<nil>") fixturesDir=\(fixtures?.path ?? "<nil>")"
			)
			if let fixturesDirectory = fixtures {
				let contents =
					(try? FileManager.default.contentsOfDirectory(atPath: fixturesDirectory.path))
					?? []
				dbgLog("DBG MenubarApp.demo: fixtures contents=\(contents)")
				let driver = DemoCycleDriver(
					sandboxedPath: config.pollingTarget,
					fixturesDirectory: fixturesDirectory,
					apply: { [weak renderer] state in
						dbgLog("DBG demoDriver.apply: state=\(state.rawValue)")
						renderer?.update(state: state, visualMode: .normal)
					},
					transitionLog: self.transitionLog
				)
				driver.start()
				self.demoDriver = driver
				dbgLog("DBG MenubarApp.demo: DemoCycleDriver started")
			} else {
				dbgLog(
					"DBG MenubarApp.demo: fixtures NOT FOUND — driver not started, renderer stays in initial idle"
				)
			}
		} else if let renderer = self.renderer {
			// Live polling — read the hook's `~/.codogotchi/state.json` at 1Hz
			// and route success/failure into renderer + status-item tooltip.
			// Mutually exclusive with demo mode by construction (the `else` arm).
			let driver = LivePollingDriver(
				pollingTargetPath: config.pollingTarget.path,
				apply: { [weak renderer] state, mode in
					renderer?.update(state: state, visualMode: mode)
				},
				setTooltip: { [weak item] tooltip in
					item?.button?.toolTip = tooltip
				},
				transitionLog: self.transitionLog
			)
			driver.start()
			self.livePollingDriver = driver
		}

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
}
