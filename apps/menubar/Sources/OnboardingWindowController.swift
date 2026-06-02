import AppKit

/// Shows a blocking first-run consent sheet when `onboardingCompletedAt` is absent.
///
/// The panel has no dismiss path before the user approves and the install subprocess
/// succeeds. On success it writes `onboardingCompletedAt` to `app-state.json`, then
/// offers an explicit dismiss path while waiting for hook activity. Subsequent launches
/// skip the sheet because the flag is present.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
	static let windowTitle = "Welcome to Codogotchi"
	static let ctaTitle = "Approve & install hooks"
	static let hooksNotActiveTitle = "Hooks installed — waiting for recent activity"
	static let hooksInstalledWaitingTitle = "Hooks installed — Codogotchi is ready to use"
	static let dismissTitle = "Dismiss"
	static let retryTitle = "Retry install"
	static let installingText = "Installing hooks…"

	private var panel: NSPanel?
	private var contentView: OnboardingContentView?
	private var installSucceeded = false

	private let onboardingController: OnboardingController
	private let appStateLoader: () -> FloatingAppState
	private let appStateSaver: (FloatingAppState) throws -> Void
	private let bundledHookVersionSource: () -> String

	init(
		onboardingController: OnboardingController = OnboardingController(),
		appStateLoader: @escaping () -> FloatingAppState = {
			AppStateStore.load(visibleFrame: NSScreen.main?.visibleFrame ?? .zero)
		},
		appStateSaver: @escaping (FloatingAppState) throws -> Void = AppStateStore.save,
		bundledHookVersionSource: @escaping () -> String = { AboutViewModel.bundledHookVersion() }
	) {
		self.onboardingController = onboardingController
		self.appStateLoader = appStateLoader
		self.appStateSaver = appStateSaver
		self.bundledHookVersionSource = bundledHookVersionSource
	}

	/// Shows the onboarding panel when `onboardingCompletedAt` is absent. No-ops otherwise.
	func showIfNeeded() {
		let appState = appStateLoader()
		guard onboardingController.needsOnboarding(appState: appState) else { return }
		guard panel == nil else { return }
		showPanel()
	}

	/// Refreshes the panel if it's showing to reflect updated hook status.
	/// When hooks become active after a successful install, closes the panel.
	func updateHookStatus(_ snapshot: HooksStatusSnapshot) {
		guard installSucceeded else { return }
		if onboardingController.isHooksActive(snapshot) {
			panel?.close()
		} else {
			contentView?.setHooksNotActive()
		}
	}

	// MARK: - NSWindowDelegate

	func windowShouldClose(_ sender: NSWindow) -> Bool {
		return installSucceeded
	}

	// MARK: - Private

	private func showPanel() {
		let frame = CGRect(x: 0, y: 0, width: 480, height: 340)
		let p = NSPanel(
			contentRect: frame,
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)
		p.title = Self.windowTitle
		p.isReleasedWhenClosed = false
		p.level = .floating
		p.hidesOnDeactivate = false
		p.delegate = self
		p.center()

		let content = OnboardingContentView(
			frame: CGRect(origin: .zero, size: frame.size),
			onApprove: { [weak self] in self?.runInstall() },
			onRetry: { [weak self] in self?.runInstall() },
			onDismiss: { [weak self] in self?.panel?.close() }
		)
		content.autoresizingMask = [.width, .height]
		p.contentView = content

		p.makeKeyAndOrderFront(nil)
		self.panel = p
		self.contentView = content
	}

	private func runInstall() {
		contentView?.setInstalling()
		let runner = onboardingController
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let error = runner.runHooksInstall()
			DispatchQueue.main.async {
				guard let self else { return }
				if let errorMsg = error {
					self.contentView?.setFailed(errorMsg)
				} else {
					self.handleInstallSuccess()
				}
			}
		}
	}

	private func handleInstallSuccess() {
		installSucceeded = true
		let current = appStateLoader()
		let iso = ISO8601DateFormatter().string(from: Date())
		let hookVersion = bundledHookVersionSource()
		let recordedVersion = hookVersion == "unknown" ? current.installedHookVersion : hookVersion
		let next = FloatingAppState(
			isFloatingPetVisible: current.isFloatingPetVisible,
			frame: current.frame,
			onboardingCompletedAt: iso,
			lastHookActivityAt: current.lastHookActivityAt,
			hooksStatus: current.hooksStatus,
			installedHookVersion: recordedVersion
		)
		try? appStateSaver(next)
		contentView?.setInstalledWaiting()
	}
}

// MARK: - OnboardingContentView

/// Programmatic AppKit view for the onboarding sheet content.
private final class OnboardingContentView: NSView {
	private let bodyLabel = NSTextField(wrappingLabelWithString: "")
	private let ctaButton = NSButton(title: "", target: nil, action: nil)
	private let statusLabel = NSTextField(wrappingLabelWithString: "")
	private let retryButton = NSButton(title: "", target: nil, action: nil)
	private let dismissButton = NSButton(title: "", target: nil, action: nil)

	private var dismissCenteredConstraint: NSLayoutConstraint!
	private var dismissPairedConstraint: NSLayoutConstraint!

	private let onApprove: () -> Void
	private let onRetry: () -> Void
	private let onDismiss: () -> Void

	init(
		frame: CGRect,
		onApprove: @escaping () -> Void,
		onRetry: @escaping () -> Void,
		onDismiss: @escaping () -> Void
	) {
		self.onApprove = onApprove
		self.onRetry = onRetry
		self.onDismiss = onDismiss
		super.init(frame: frame)
		setupViews()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	// MARK: - State transitions

	func setInstalling() {
		ctaButton.isEnabled = false
		ctaButton.title = OnboardingWindowController.installingText
		statusLabel.stringValue = ""
		retryButton.isHidden = true
		dismissButton.isHidden = true
	}

	func setFailed(_ message: String) {
		ctaButton.isEnabled = true
		ctaButton.title = OnboardingWindowController.ctaTitle
		statusLabel.stringValue = message
		statusLabel.textColor = .systemRed
		retryButton.isHidden = true
		dismissButton.isHidden = true
	}

	func setInstalledWaiting() {
		ctaButton.isHidden = true
		statusLabel.stringValue = OnboardingWindowController.hooksInstalledWaitingTitle
		statusLabel.textColor = .secondaryLabelColor
		retryButton.isHidden = true
		dismissButton.isHidden = false
		dismissPairedConstraint.isActive = false
		dismissCenteredConstraint.isActive = true
	}

	func setHooksNotActive() {
		ctaButton.isHidden = true
		statusLabel.stringValue = OnboardingWindowController.hooksNotActiveTitle
		statusLabel.textColor = .secondaryLabelColor
		retryButton.isHidden = false
		dismissButton.isHidden = false
		dismissCenteredConstraint.isActive = false
		dismissPairedConstraint.isActive = true
	}

	// MARK: - Layout

	private func setupViews() {
		wantsLayer = true

		let iconLabel = NSTextField(labelWithString: "🐱")
		iconLabel.font = .systemFont(ofSize: 48)
		iconLabel.alignment = .center
		iconLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(iconLabel)

		bodyLabel.stringValue =
			"Codogotchi animates when your AI coding tools are active. "
			+ "Installing hooks lets Codex, Claude Code, and Cursor notify the pet.\n\n"
			+ "Once hooks are installed, you can dismiss this window immediately. "
			+ "Tool activity will animate the pet whenever you use a supported platform."
		bodyLabel.isEditable = false
		bodyLabel.isBordered = false
		bodyLabel.backgroundColor = .clear
		bodyLabel.alignment = .center
		bodyLabel.font = .systemFont(ofSize: 13)
		bodyLabel.textColor = .labelColor
		bodyLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(bodyLabel)

		ctaButton.title = OnboardingWindowController.ctaTitle
		ctaButton.bezelStyle = .rounded
		ctaButton.keyEquivalent = "\r"
		ctaButton.target = self
		ctaButton.action = #selector(approveTapped)
		ctaButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(ctaButton)

		statusLabel.stringValue = ""
		statusLabel.isEditable = false
		statusLabel.isBordered = false
		statusLabel.backgroundColor = .clear
		statusLabel.alignment = .center
		statusLabel.font = .systemFont(ofSize: 12)
		statusLabel.textColor = .secondaryLabelColor
		statusLabel.maximumNumberOfLines = 4
		statusLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(statusLabel)

		retryButton.title = OnboardingWindowController.retryTitle
		retryButton.bezelStyle = .inline
		retryButton.isHidden = true
		retryButton.target = self
		retryButton.action = #selector(retryTapped)
		retryButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(retryButton)

		dismissButton.title = OnboardingWindowController.dismissTitle
		dismissButton.bezelStyle = .rounded
		dismissButton.isHidden = true
		dismissButton.target = self
		dismissButton.action = #selector(dismissTapped)
		dismissButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(dismissButton)

		NSLayoutConstraint.activate([
			iconLabel.topAnchor.constraint(equalTo: topAnchor, constant: 28),
			iconLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

			bodyLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 14),
			bodyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
			bodyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),

			ctaButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 24),
			ctaButton.centerXAnchor.constraint(equalTo: centerXAnchor),
			ctaButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),

			statusLabel.topAnchor.constraint(equalTo: ctaButton.bottomAnchor, constant: 12),
			statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
			statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),

			retryButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
			retryButton.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -56),

			dismissButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
		])

		dismissCenteredConstraint = dismissButton.centerXAnchor.constraint(equalTo: centerXAnchor)
		dismissPairedConstraint = dismissButton.centerXAnchor.constraint(
			equalTo: centerXAnchor, constant: 56)
		dismissCenteredConstraint.isActive = true
	}

	@objc private func approveTapped() {
		onApprove()
	}

	@objc private func retryTapped() {
		onRetry()
	}

	@objc private func dismissTapped() {
		onDismiss()
	}
}
