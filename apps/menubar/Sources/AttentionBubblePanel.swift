import AppKit
import Foundation

// MARK: - Layout

private enum BubbleLayout {
	static let minWidth: CGFloat = 200
	static let maxWidth: CGFloat = 280
	static let height: CGFloat = 58
	static let gapBelowPet: CGFloat = 6
	static let hPad: CGFloat = 10
	static let vPad: CGFloat = 9
	static let cornerRadius: CGFloat = 10
	static let iconSize: CGFloat = 18
	static let closeButtonSize: CGFloat = 13
	static let actionButtonHeight: CGFloat = 18
	static let actionButtonWidth: CGFloat = 54

	static func frame(relativeTo petFrame: CGRect, visibleFrame: CGRect) -> CGRect {
		let width = max(minWidth, min(maxWidth, petFrame.width + 40))
		let x = petFrame.midX - width / 2
		let y = petFrame.minY - gapBelowPet - height
		let rect = CGRect(x: x, y: y, width: width, height: height)
		return clamped(rect, to: visibleFrame)
	}

	private static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
		let margin: CGFloat = 4
		let safe = bounds.insetBy(dx: margin, dy: margin)
		let x = max(safe.minX, min(safe.maxX - rect.width, rect.minX))
		let y = max(safe.minY, min(safe.maxY - rect.height, rect.minY))
		return CGRect(x: x, y: y, width: rect.width, height: rect.height)
	}
}

// MARK: - Panel

/// Floating attention bubble shown below the pet panel when `state.json`
/// carries an unexpired `attention` object. Session-local dismiss — never
/// writes back to `state.json`.
@MainActor
final class AttentionBubblePanel: NSPanel {
	private let bubbleView: AttentionBubbleView

	init() {
		self.bubbleView = AttentionBubbleView(frame: .zero)
		super.init(
			contentRect: .zero,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		backgroundColor = .clear
		isOpaque = false
		hasShadow = false
		level = .floating
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		hidesOnDeactivate = false
		isReleasedWhenClosed = false
		ignoresMouseEvents = false
		acceptsMouseMovedEvents = true
		contentView = bubbleView
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }

	var onDismiss: (() -> Void)? {
		get { bubbleView.onDismiss }
		set { bubbleView.onDismiss = newValue }
	}

	func update(payload: AttentionPayload, sourceEvent: SourceEvent?) {
		bubbleView.configure(
			summary: payload.summary ?? "",
			reasonKind: payload.reasonKind ?? "",
			sourceEvent: sourceEvent
		)
	}

	func reposition(relativeTo petFrame: CGRect, visibleFrame: CGRect) {
		let f = BubbleLayout.frame(relativeTo: petFrame, visibleFrame: visibleFrame)
		setFrame(f, display: true)
		bubbleView.frame = NSRect(origin: .zero, size: f.size)
	}
}

// MARK: - View

private final class AttentionBubbleView: NSView {
	private final class HoverButton: NSButton {
		private let normalBorderAlpha: CGFloat
		private let hoverBorderAlpha: CGFloat
		private let normalFillAlpha: CGFloat
		private let hoverFillAlpha: CGFloat
		private let borderBaseColor: NSColor
		private let fillBaseColor: NSColor
		private var trackingArea: NSTrackingArea?

		init(
			frame: NSRect = .zero,
			normalBorderAlpha: CGFloat = 0.18,
			hoverBorderAlpha: CGFloat = 0.44,
			normalFillAlpha: CGFloat = 0.04,
			hoverFillAlpha: CGFloat = 0.16,
			borderBaseColor: NSColor = .white,
			fillBaseColor: NSColor = .white
		) {
			self.normalBorderAlpha = normalBorderAlpha
			self.hoverBorderAlpha = hoverBorderAlpha
			self.normalFillAlpha = normalFillAlpha
			self.hoverFillAlpha = hoverFillAlpha
			self.borderBaseColor = borderBaseColor
			self.fillBaseColor = fillBaseColor
			super.init(frame: frame)
			wantsLayer = true
			layer?.masksToBounds = true
			bezelStyle = .regularSquare
			imagePosition = .imageOnly
			isBordered = false
			focusRingType = .none
			updateHoverStyle(isDirectlyHovered: false)
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) { nil }

		override func updateTrackingAreas() {
			super.updateTrackingAreas()
			if let old = trackingArea { removeTrackingArea(old) }
			let area = NSTrackingArea(
				rect: bounds,
				options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
				owner: self,
				userInfo: nil
			)
			addTrackingArea(area)
			trackingArea = area
		}

		override func mouseEntered(with event: NSEvent) {
			updateHoverStyle(isDirectlyHovered: true)
		}

		override func mouseExited(with event: NSEvent) {
			updateHoverStyle(isDirectlyHovered: false)
		}

		private func updateHoverStyle(isDirectlyHovered: Bool) {
			let borderAlpha = isDirectlyHovered ? hoverBorderAlpha : normalBorderAlpha
			let fillAlpha = isDirectlyHovered ? hoverFillAlpha : normalFillAlpha
			layer?.cornerRadius = min(bounds.width, bounds.height) / 2
			layer?.borderColor = borderBaseColor.withAlphaComponent(borderAlpha).cgColor
			layer?.borderWidth = 1
			layer?.backgroundColor = fillBaseColor.withAlphaComponent(fillAlpha).cgColor
		}
	}

	// Background
	private let effectView = NSVisualEffectView(frame: .zero)

	// Content
	private let summaryLabel = NSTextField(labelWithString: "")
	private let subtitleLabel = NSTextField(labelWithString: "")

	// Always visible
	private let infoButton = NSButton(frame: .zero)

	// Hover-revealed
	private let dismissButton = HoverButton(
		normalBorderAlpha: 0.9,
		hoverBorderAlpha: 1.0,
		normalFillAlpha: 0.62,
		hoverFillAlpha: 0.8,
		borderBaseColor: NSColor(calibratedRed: 0.33, green: 0.35, blue: 0.42, alpha: 1.0),
		fillBaseColor: NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.24, alpha: 1.0)
	)
	private let actionButton = HoverButton(
		normalBorderAlpha: 0.22,
		hoverBorderAlpha: 0.52,
		normalFillAlpha: 0.04,
		hoverFillAlpha: 0.14
	)

	var onDismiss: (() -> Void)?

	private var trackingArea: NSTrackingArea?
	private var isHovered = false
	private var sourceEvent: SourceEvent?
	private var reasonKind: String = ""

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		buildUI()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	private func buildUI() {
		wantsLayer = true

		effectView.material = .hudWindow
		effectView.blendingMode = .behindWindow
		effectView.state = .active
		effectView.appearance = NSAppearance(named: .darkAqua)
		effectView.wantsLayer = true
		effectView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(effectView)

		summaryLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
		summaryLabel.textColor = .white
		summaryLabel.lineBreakMode = .byTruncatingTail
		summaryLabel.maximumNumberOfLines = 1
		summaryLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(summaryLabel)

		subtitleLabel.font = NSFont.systemFont(ofSize: 10)
		subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.58)
		subtitleLabel.lineBreakMode = .byTruncatingTail
		subtitleLabel.maximumNumberOfLines = 1
		subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(subtitleLabel)

		configureButton(
			infoButton,
			symbol: "info.circle",
			accessibility: "More info",
			selector: #selector(showInfo)
		)
		infoButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(infoButton)

		configureButton(
			dismissButton,
			symbol: "xmark",
			accessibility: "Dismiss",
			selector: #selector(dismissBubble)
		)
		dismissButton.contentTintColor = NSColor(calibratedWhite: 0.86, alpha: 1.0)
		dismissButton.imageScaling = .scaleProportionallyDown
		dismissButton.alphaValue = 0
		dismissButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(dismissButton)

		actionButton.bezelStyle = .rounded
		actionButton.isBordered = false
		actionButton.font = NSFont.systemFont(ofSize: 10, weight: .medium)
		actionButton.contentTintColor = NSColor(calibratedRed: 0.42, green: 0.72, blue: 1.0, alpha: 1.0)
		actionButton.target = self
		actionButton.action = #selector(performAction)
		actionButton.layer?.cornerRadius = BubbleLayout.actionButtonHeight / 2
		actionButton.alphaValue = 0
		actionButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(actionButton)

		let hPad = BubbleLayout.hPad
		let vPad = BubbleLayout.vPad
		let icon = BubbleLayout.iconSize

		NSLayoutConstraint.activate([
			// background
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

			// info button — right edge, top row
			infoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(hPad - 2)),
			infoButton.topAnchor.constraint(equalTo: topAnchor, constant: vPad),
			infoButton.widthAnchor.constraint(equalToConstant: icon),
			infoButton.heightAnchor.constraint(equalToConstant: icon),

			// summary — uses the full left side; hover controls float above it.
			summaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad + 2),
			summaryLabel.trailingAnchor.constraint(
				equalTo: infoButton.leadingAnchor, constant: -4),
			summaryLabel.topAnchor.constraint(equalTo: topAnchor, constant: vPad),

			// subtitle — full-width by default; Focus overlays on hover.
			subtitleLabel.leadingAnchor.constraint(equalTo: summaryLabel.leadingAnchor),
			subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad),
			subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vPad),

			// close button — hover-only circle, floating over the bubble chrome.
			dismissButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad - 1),
			dismissButton.centerYAnchor.constraint(equalTo: summaryLabel.centerYAnchor),
			dismissButton.widthAnchor.constraint(equalToConstant: BubbleLayout.closeButtonSize),
			dismissButton.heightAnchor.constraint(equalToConstant: BubbleLayout.closeButtonSize),

			// action button — hover-only pill right-aligned with the info icon.
			actionButton.trailingAnchor.constraint(equalTo: infoButton.trailingAnchor),
			actionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vPad),
			actionButton.widthAnchor.constraint(equalToConstant: BubbleLayout.actionButtonWidth),
			actionButton.heightAnchor.constraint(equalToConstant: BubbleLayout.actionButtonHeight),
		])

		applyChromeStyle()
	}

	private func configureButton(
		_ button: NSButton,
		symbol: String,
		accessibility: String,
		selector: Selector
	) {
		button.bezelStyle = .circular
		button.isBordered = false
		button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)
		button.contentTintColor = NSColor.white.withAlphaComponent(0.65)
		button.target = self
		button.action = selector
	}

	func configure(summary: String, reasonKind: String, sourceEvent: SourceEvent?) {
		self.sourceEvent = sourceEvent
		self.reasonKind = reasonKind
		summaryLabel.stringValue = summary.isEmpty ? "Waiting for input" : summary
		subtitleLabel.stringValue = reasonKind
		infoButton.toolTip = reasonKind

		// Action button always does the same thing: focus the source app
		// (`performAction`). Both standby (input_requested) and error (error_blocked)
		// therefore use "Focus" — "Reply" was a false promise (no app layer can send
		// a prompt to the errored thread). "review_ready" is reserved — hide it.
		switch reasonKind {
		case "input_requested", "error_blocked":
			actionButton.title = "Focus"
			actionButton.isHidden = false
		default:
			actionButton.isHidden = true
			actionButton.alphaValue = 0  // clear any hover residue from a prior payload
		}

		// Reset hover state on new payload arrival so controls are not stuck visible.
		setHovered(false)
	}

	// MARK: - Hover

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let old = trackingArea { removeTrackingArea(old) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseEntered(with event: NSEvent) { setHovered(true) }
	override func mouseExited(with event: NSEvent) { setHovered(false) }

	private func setHovered(_ hovered: Bool) {
		guard isHovered != hovered else { return }
		isHovered = hovered
		let alpha: CGFloat = hovered ? 1 : 0
		dismissButton.alphaValue = alpha
		if !actionButton.isHidden {
			actionButton.alphaValue = alpha
		}
	}

	// MARK: - Appearance

	override func layout() {
		super.layout()
		applyChromeStyle()
	}

	private func applyChromeStyle() {
		effectView.layer?.cornerRadius = BubbleLayout.cornerRadius
		effectView.layer?.masksToBounds = true
		dismissButton.layer?.cornerRadius = min(
			dismissButton.bounds.width,
			dismissButton.bounds.height
		) / 2
		layer?.cornerRadius = BubbleLayout.cornerRadius
		layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
		layer?.borderWidth = 1
		layer?.shadowColor = NSColor.black.cgColor
		layer?.shadowOpacity = 0.32
		layer?.shadowRadius = 8
		layer?.shadowOffset = CGSize(width: 0, height: -2)
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		bounds.contains(point) ? super.hitTest(point) : nil
	}

	// MARK: - Actions

	@objc private func showInfo() {
		guard !reasonKind.isEmpty else { return }
		let popover = NSPopover()
		popover.behavior = .transient
		let vc = NSViewController()
		let view = NSView()
		view.translatesAutoresizingMaskIntoConstraints = false
		let label = NSTextField(labelWithString: reasonKind)
		label.font = NSFont.systemFont(ofSize: 12)
		label.textColor = .labelColor
		label.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(label)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
			label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
			label.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
			label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
		])
		vc.view = view
		popover.contentViewController = vc
		label.sizeToFit()
		popover.contentSize = CGSize(
			width: label.frame.width + 20,
			height: label.frame.height + 16
		)
		popover.show(relativeTo: infoButton.bounds, of: infoButton, preferredEdge: .minY)
	}

	@objc private func dismissBubble() {
		onDismiss?()
		window?.orderOut(nil)
	}

	@objc private func performAction() {
		let bundleId = focusBundleId(for: sourceEvent)
		defer {
			onDismiss?()
			window?.orderOut(nil)
		}
		guard let bundleId else { return }
		let match = NSWorkspace.shared.runningApplications.first {
			$0.bundleIdentifier == bundleId
		}
		// activate forces the OS to foreground the app (handles Electron apps that
		// ignore the reopen event); open(bundleURL) then handles un-minimise from dock.
		match?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
		if let url = match?.bundleURL {
			NSWorkspace.shared.open(url)
		}
	}

	/// Resolves the bundle ID to focus when the user taps Focus.
	///
	/// Priority:
	/// 1. `terminal_bundle_id` — the terminal that launched the hook process,
	///    populated by `detectTerminalBundleId` in hook-binary.ts.
	/// 2. IDE-native origin map — for IDE agents (cursor, codex Desktop) that fire
	///    hooks directly without a terminal parent.
	/// 3. nil — no reliable Focus target; bubble still dismisses, Focus is a no-op.
	private func focusBundleId(for event: SourceEvent?) -> String? {
		if let terminalId = event?.terminalBundleId { return terminalId }
		let ideMap: [String: String] = [
			"cursor": "com.todesktop.230313mzl4w4u92",
			"codex": "com.openai.codex",
		]
		return ideMap[event?.origin ?? ""]
	}
}
