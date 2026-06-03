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
		let width = AttentionBubbleLayoutMetrics.bubbleWidth(forPetWidth: petFrame.width)
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

private enum BubblePalette {
	static let focusBlue = NSColor(calibratedRed: 0.42, green: 0.72, blue: 1.0, alpha: 1.0)
	static let dismissFill = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.22, alpha: 1.0)
	static let dismissBorder = NSColor(calibratedRed: 0.34, green: 0.37, blue: 0.46, alpha: 1.0)
	/// Opaque chrome for hover controls so subtitle text does not show through.
	static let controlFill = NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.18, alpha: 1.0)
}

// MARK: - Panel

/// Resolves which app the Focus button should foreground for a given
/// `source_event`. Pure mapping, factored out of the (private) bubble view so it
/// can be unit-tested without constructing AppKit panels.
///
/// Priority:
/// 1. `terminalBundleId` — the terminal that launched the hook process,
///    populated by `detectTerminalBundleId` in hook-binary.ts.
/// 2. IDE-native origin map — for IDE agents (cursor, codex Desktop) that fire
///    hooks directly without a terminal parent.
/// 3. `nil` — no reliable Focus target; the bubble still dismisses, Focus no-ops.
enum AttentionFocusTarget {
	static func bundleId(for event: SourceEvent?) -> String? {
		if let terminalId = event?.terminalBundleId { return terminalId }
		let ideMap: [String: String] = [
			"cursor": "com.todesktop.230313mzl4w4u92",
			"codex": "com.openai.codex",
		]
		return ideMap[event?.origin ?? ""]
	}
}

/// Floating attention bubble shown below the pet panel when `state.json`
/// carries an unexpired `attention` object. On dismiss the caller writes
/// `activity_state: idle` and removes `attention` from `state.json` via
/// `FloatingPetPanelController.onAttentionDismissed`.
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
		// Pet drag/resize moves this panel under the cursor without a matching
		// mouseExited when the grab ends elsewhere — re-sync from screen location.
		bubbleView.syncPointerHover()
	}
}

// MARK: - View

private final class AttentionBubbleView: NSView {
	private enum HoverButtonShape {
		case circle
		case capsule
	}

	private final class HoverButton: NSButton {
		private let shape: HoverButtonShape
		private let normalBorderAlpha: CGFloat
		private let hoverBorderAlpha: CGFloat
		private let normalFillAlpha: CGFloat
		private let hoverFillAlpha: CGFloat
		private let borderBaseColor: NSColor
		private let fillBaseColor: NSColor
		private var trackingArea: NSTrackingArea?
		private var isDirectlyHovered = false

		init(
			frame: NSRect = .zero,
			shape: HoverButtonShape = .circle,
			normalBorderAlpha: CGFloat = 0.18,
			hoverBorderAlpha: CGFloat = 0.44,
			normalFillAlpha: CGFloat = 0.04,
			hoverFillAlpha: CGFloat = 0.16,
			borderBaseColor: NSColor = .white,
			fillBaseColor: NSColor = .white
		) {
			self.shape = shape
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
			isDirectlyHovered = true
			updateHoverStyle(isDirectlyHovered: true)
		}

		override func mouseExited(with event: NSEvent) {
			isDirectlyHovered = false
			updateHoverStyle(isDirectlyHovered: false)
		}

		override func layout() {
			super.layout()
			updateHoverStyle(isDirectlyHovered: isDirectlyHovered)
		}

		private func updateHoverStyle(isDirectlyHovered: Bool) {
			let borderAlpha = isDirectlyHovered ? hoverBorderAlpha : normalBorderAlpha
			let fillAlpha = isDirectlyHovered ? hoverFillAlpha : normalFillAlpha
			switch shape {
			case .circle:
				let side = min(bounds.width, bounds.height)
				layer?.cornerRadius = side / 2
			case .capsule:
				layer?.cornerRadius = bounds.height / 2
			}
			layer?.masksToBounds = true
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

	// Always visible when `source_event.origin` maps to a platform logo.
	private let platformChip = AttentionBubblePlatformChip(frame: .zero)
	private var platformChipWidthConstraint: NSLayoutConstraint?

	// Hover-revealed
	private let dismissButton = HoverButton(
		shape: .circle,
		normalBorderAlpha: 0.9,
		hoverBorderAlpha: 1.0,
		normalFillAlpha: 1.0,
		hoverFillAlpha: 1.0,
		borderBaseColor: BubblePalette.dismissBorder,
		fillBaseColor: BubblePalette.dismissFill
	)
	private let actionButton = HoverButton(
		shape: .capsule,
		normalBorderAlpha: 0.45,
		hoverBorderAlpha: 0.65,
		normalFillAlpha: 1.0,
		hoverFillAlpha: 1.0,
		borderBaseColor: BubblePalette.dismissBorder,
		fillBaseColor: BubblePalette.controlFill
	)

	var onDismiss: (() -> Void)?

	private var trackingArea: NSTrackingArea?
	private var isHovered = false
	private var sourceEvent: SourceEvent?
	private var reasonKind: String = ""
	/// Raw prompt excerpt from `attention.summary` (display adds `Re:` in layout).
	private var promptExcerpt: String = ""

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

		platformChip.translatesAutoresizingMaskIntoConstraints = false
		addSubview(platformChip)

		configureButton(
			dismissButton,
			symbol: "xmark",
			accessibility: "Dismiss",
			selector: #selector(dismissBubble)
		)
		dismissButton.contentTintColor = BubblePalette.focusBlue
		dismissButton.image = dismissButton.image?.withSymbolConfiguration(
			NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
		)
		dismissButton.imageScaling = .scaleNone
		dismissButton.alphaValue = 0
		dismissButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(dismissButton)

		actionButton.bezelStyle = .rounded
		actionButton.isBordered = false
		actionButton.font = NSFont.systemFont(ofSize: 10, weight: .medium)
		actionButton.contentTintColor = BubblePalette.focusBlue
		actionButton.target = self
		actionButton.action = #selector(performAction)
		actionButton.imagePosition = .noImage
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

			// platform chip — right edge, top row (same slot as the old info icon)
			platformChip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(hPad - 2)),
			platformChip.topAnchor.constraint(equalTo: topAnchor, constant: vPad),
			platformChip.heightAnchor.constraint(equalToConstant: icon),

			// summary — uses the full left side; hover controls float above it.
			summaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad + 2),
			summaryLabel.trailingAnchor.constraint(
				equalTo: platformChip.leadingAnchor, constant: -4),
			summaryLabel.topAnchor.constraint(equalTo: topAnchor, constant: vPad),

			// subtitle — full-width by default; Focus overlays on hover.
			subtitleLabel.leadingAnchor.constraint(equalTo: summaryLabel.leadingAnchor),
			subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad),
			subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vPad),

			// close button — hover-only circle, floating over the bubble chrome.
			dismissButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad - 1),
			dismissButton.centerYAnchor.constraint(equalTo: summaryLabel.centerYAnchor),
			dismissButton.widthAnchor.constraint(equalToConstant: BubbleLayout.closeButtonSize),
			dismissButton.heightAnchor.constraint(equalTo: dismissButton.widthAnchor),

			// action button — hover-only pill right-aligned with the platform chip.
			actionButton.trailingAnchor.constraint(equalTo: platformChip.trailingAnchor),
			actionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vPad),
			actionButton.widthAnchor.constraint(equalToConstant: BubbleLayout.actionButtonWidth),
			actionButton.heightAnchor.constraint(equalToConstant: BubbleLayout.actionButtonHeight),
		])
		let chipWidth = platformChip.widthAnchor.constraint(equalToConstant: icon)
		platformChipWidthConstraint = chipWidth
		chipWidth.isActive = true

		applyChromeStyle()
	}

	private func applyPromptSubtitle() {
		guard reasonKind == "input_requested" else { return }
		let contentWidth = AttentionBubbleLayoutMetrics.subtitleContentWidth(
			forBubbleWidth: bounds.width
		)
		subtitleLabel.stringValue = AttentionSubtitleFormatting.truncatedReplyLine(
			excerpt: promptExcerpt,
			fittingWidth: contentWidth
		)
	}

	private func configureButton(
		_ button: NSButton,
		symbol: String,
		accessibility: String,
		selector: Selector
	) {
		button.bezelStyle = .circular
		button.isBordered = false
		button.setButtonType(.momentaryChange)
		button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)
		button.contentTintColor = NSColor.white.withAlphaComponent(0.65)
		button.target = self
		button.action = selector
	}

	func configure(summary: String, reasonKind: String, sourceEvent: SourceEvent?) {
		self.sourceEvent = sourceEvent
		self.reasonKind = reasonKind

		switch reasonKind {
		case "input_requested":
			summaryLabel.stringValue = "Waiting for your input"
			promptExcerpt =
				summary == "Waiting for your input" || summary.isEmpty ? "" : summary
		case "error_blocked":
			promptExcerpt = ""
			summaryLabel.stringValue = "Something went wrong"
			subtitleLabel.stringValue = ""
		default:
			promptExcerpt = ""
			summaryLabel.stringValue = summary.isEmpty ? "Waiting for input" : summary
			subtitleLabel.stringValue = ""
		}

		applyPromptSubtitle()

		let platform = PlatformAttribution(origin: sourceEvent?.origin)
		platformChip.configure(platform: platform)
		if let platform {
			platformChip.toolTip = "Focus opens \(platform.displayName)"
			platformChipWidthConstraint?.constant = BubbleLayout.iconSize
			platformChip.isHidden = false
		} else {
			platformChip.toolTip = nil
			platformChipWidthConstraint?.constant = 0
			platformChip.isHidden = true
		}

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

	/// Align hover chrome with whether the pointer is actually over this panel.
	fileprivate func syncPointerHover() {
		guard let window else {
			setHovered(false)
			return
		}
		let mouse = NSEvent.mouseLocation
		setHovered(window.frame.contains(mouse))
	}

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
		applyPromptSubtitle()
	}

	private func applyChromeStyle() {
		effectView.layer?.cornerRadius = BubbleLayout.cornerRadius
		effectView.layer?.masksToBounds = true
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

	@objc private func dismissBubble() {
		onDismiss?()
		window?.orderOut(nil)
	}

	@objc private func performAction() {
		let bundleId = AttentionFocusTarget.bundleId(for: sourceEvent)
		defer {
			onDismiss?()
			window?.orderOut(nil)
		}
		guard let bundleId else { return }
		let running = NSWorkspace.shared.runningApplications.first {
			$0.bundleIdentifier == bundleId
		}
		// activate forces the OS to foreground the app (handles Electron apps that
		// ignore the reopen event).
		running?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
		// Resolve the bundle URL (running instance first, else a LaunchServices
		// lookup for a not-running target) and reopen it via `openApplication`.
		// This deliberately replaces the deprecated `NSWorkspace.open(bundleURL)`:
		// opening another app's bundle URL trips macOS App Management ("…prevented
		// from modifying apps"), which re-prompts on every unsigned rebuild.
		// `openApplication(at:configuration:)` is the sanctioned launch/reopen path
		// — it un-minimises from the Dock without touching the bundle.
		guard
			let url = running?.bundleURL
				?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
		else { return }
		let configuration = NSWorkspace.OpenConfiguration()
		configuration.activates = true
		NSWorkspace.shared.openApplication(at: url, configuration: configuration)
	}

}

// MARK: - Platform chip

/// Small frosted square showing which app Focus will foreground — mirrors the
/// animation badge's platform chip so the logo survives when the badge is hidden.
private final class AttentionBubblePlatformChip: NSView {
	private static let glyphColor = NSColor(calibratedWhite: 0.95, alpha: 1.0)

	private let effectView: NSVisualEffectView
	private let imageView = NSImageView()

	override init(frame frameRect: NSRect) {
		effectView = NSVisualEffectView(frame: .zero)
		effectView.material = .hudWindow
		effectView.blendingMode = .behindWindow
		effectView.state = .active
		effectView.appearance = NSAppearance(named: .darkAqua)
		effectView.wantsLayer = true
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		effectView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(effectView)

		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.contentTintColor = Self.glyphColor
		imageView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(imageView)

		let inset: CGFloat = 3
		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
			imageView.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(platform: PlatformAttribution?) {
		if let platform {
			let image = NSImage(named: platform.assetName)
			image?.isTemplate = true
			imageView.image = image
		} else {
			imageView.image = nil
		}
	}

	override func layout() {
		super.layout()
		let radius = min(bounds.width, bounds.height) * 0.22
		effectView.layer?.cornerRadius = radius
		effectView.layer?.masksToBounds = true
		layer?.cornerRadius = radius
		layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
		layer?.borderWidth = 1
		layer?.shadowColor = NSColor.black.cgColor
		layer?.shadowOpacity = 0.32
		layer?.shadowRadius = 8
		layer?.shadowOffset = CGSize(width: 0, height: -2)
	}
}
