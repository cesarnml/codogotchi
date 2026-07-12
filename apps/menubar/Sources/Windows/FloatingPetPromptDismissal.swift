import AppKit

/// Owns the "any click away, keyboard input, or app-resign dismisses this
/// floating popup" observer stack shared by every prompt-like floating panel:
/// the hide-prompt pill stack (Own and Minimalist) and the Minimalist
/// panel-size slider pill. Installed independently on all three surfaces
/// before convergence — "the bug fixed three times" — this is the single
/// implementation; no prompt-presenting surface installs its own monitors.
///
/// Deliberately does not listen for `NSWindow.didResignKeyNotification`: both
/// prompt/pill panels are `.nonactivatingPanel` borderless panels that can
/// never become key, so that observer never fires (R1.11 in
/// `docs/contracts/window-capability-matrix.md`, dispositioned dead code, not
/// carried into the converged component).
final class FloatingPetPromptDismissal {
	private weak var owner: AnyObject?
	private weak var panel: NSPanel?
	private var dismissAction: (() -> Void)?

	private var didResignActiveObserver: NSObjectProtocol?
	private var globalMouseMonitor: Any?
	private var localMouseMonitor: Any?
	private var globalKeyboardMonitor: Any?

	init() {}

	/// Registers `owner` with `FloatingPetPromptCoordinator.shared` (so a
	/// right-click on a different panel dismisses this one) and installs the
	/// dismiss-on-click-away/keyboard/resign-active monitors. `panel` is the
	/// floating window that a same-app click must NOT dismiss when the click
	/// lands on it.
	func install(owner: AnyObject, panel: NSPanel, dismiss: @escaping () -> Void) {
		self.owner = owner
		self.panel = panel
		dismissAction = dismiss

		FloatingPetPromptCoordinator.shared.willPresent(owner: owner, dismiss: dismiss)

		didResignActiveObserver = NotificationCenter.default.addObserver(
			forName: NSApplication.didResignActiveNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor in self?.dismissAction?() }
		}

		globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
			matching: [.leftMouseDown, .rightMouseDown]
		) { [weak self] _ in
			Task { @MainActor in self?.dismissAction?() }
		}

		// In-app half of "any click away dismisses": global monitors only
		// report other applications' events, so a click on a sibling panel
		// would strand this popup without a local monitor. Dismissal is
		// synchronous (not Task-deferred) — the monitor fires before the
		// event dispatches, and a deferred dismissal would land after a
		// re-present and tear down the new popup instead of the old one.
		localMouseMonitor = NSEvent.addLocalMonitorForEvents(
			matching: [.leftMouseDown, .rightMouseDown]
		) { [weak self] event in
			if let self, event.window !== self.panel {
				self.dismissAction?()
			}
			return event
		}

		// Dismiss on any keyboard input (including Cmd+Tab / Alt+Tab system
		// switchers) so the popup never lingers over the UI while the user is
		// changing apps/windows.
		globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(
			matching: [.keyDown, .keyUp, .flagsChanged]
		) { [weak self] _ in
			Task { @MainActor in self?.dismissAction?() }
		}
	}

	/// Tears down monitors and clears the coordinator's active-owner
	/// registration. Safe to call when nothing is installed.
	func uninstall() {
		guard let owner else { return }
		FloatingPetPromptCoordinator.shared.didDismiss(owner: owner)

		if let didResignActiveObserver {
			NotificationCenter.default.removeObserver(didResignActiveObserver)
		}
		if let globalMouseMonitor {
			NSEvent.removeMonitor(globalMouseMonitor)
		}
		if let localMouseMonitor {
			NSEvent.removeMonitor(localMouseMonitor)
		}
		if let globalKeyboardMonitor {
			NSEvent.removeMonitor(globalKeyboardMonitor)
		}

		didResignActiveObserver = nil
		globalMouseMonitor = nil
		localMouseMonitor = nil
		globalKeyboardMonitor = nil
		self.owner = nil
		self.panel = nil
		dismissAction = nil
	}
}
