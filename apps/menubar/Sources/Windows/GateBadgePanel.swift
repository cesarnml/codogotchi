import AppKit

@MainActor
final class GateBadgePanel: NSPanel {
	private let badgeView = GateBadgeView(frame: .zero)

	/// Fired with the screen-space anchor when the user right-clicks the
	/// ticket/gate token stack. Wired by whichever controller owns this panel
	/// (Own or Minimalist mode) to present the same hide/rename/force-idle
	/// prompt a click on the pet/strip itself presents — this badge is its own
	/// floating window, so it never received that click otherwise.
	var onRightClickRequested: ((CGPoint) -> Void)?

	/// Fired when the user starts/continues/ends a left-click-drag on the
	/// ticket/gate token stack. Wired by whichever controller owns this panel
	/// to move the panel the badge is anchored to (the pet panel in Own/
	/// Combined mode, the badge strip in Minimalist mode) — mirrors
	/// `onRightClickRequested`'s reasoning: this badge is its own floating
	/// window, so a drag on it never reached the owning panel otherwise.
	var onDragBegan: (() -> Void)?
	var onDragChanged: (() -> Void)?
	var onDragEnded: (() -> Void)?

	init() {
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
		// Was click-through (true); now interactive so a right-click/drag on
		// the badge can surface the hide prompt / move the panel like the
		// rest of the chrome.
		ignoresMouseEvents = false
		contentView = badgeView
		badgeView.onRightMouseDown = { [weak self] event in
			guard let self else { return }
			self.onRightClickRequested?(self.convertPoint(toScreen: event.locationInWindow))
		}
		badgeView.onDragBegan = { [weak self] in self?.onDragBegan?() }
		badgeView.onDragChanged = { [weak self] in self?.onDragChanged?() }
		badgeView.onDragEnded = { [weak self] in self?.onDragEnded?() }
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }

	func update(content: GateBadgeContent, relativeTo petFrame: CGRect) {
		badgeView.configure(
			content: content, metrics: GateBadgeLayout.metrics(for: petFrame), tokenAlignment: .leading)
	}

	/// Own-mode entry point: metrics scale off the pet frame's own width, but
	/// the stack is positioned by `chipLeadingX` (screen space) — the platform
	/// chip's leading edge — not centered on the pet. This is its own
	/// implementation rather than delegating to the Minimalist-mode
	/// `reposition(content:metrics:relativeTo:visibleFrame:)` below: that one
	/// treats its `anchorFrame` as *both* the metrics source and the
	/// left-edge-plus-inset anchor, which is correct when the anchor is the
	/// Minimalist strip itself (chip leading edge = strip leading edge +
	/// `hPad`) but wrong here, where `petFrame` (for metrics) and the chip's
	/// screen position (a separate floating panel below-left of the pet,
	/// anchored off `pillCenterX`) are unrelated.
	func reposition(
		content: GateBadgeContent,
		relativeTo petFrame: CGRect,
		chipLeadingX: CGFloat,
		visibleFrame: CGRect
	) {
		let metrics = GateBadgeLayout.metrics(for: petFrame)
		badgeView.configure(content: content, metrics: metrics, tokenAlignment: .leading)
		let size = badgeView.preferredSize
		let frame = GateBadgeLayout.frame(
			aboveTopOf: petFrame,
			badgeSize: size,
			leadingX: chipLeadingX,
			visibleFrame: visibleFrame
		)
		setFrame(frame, display: true)
		badgeView.frame = NSRect(origin: .zero, size: frame.size)
	}

	/// Minimalist-mode entry point: the anchor frame is a chromeless badge strip,
	/// not a pet sprite, so its width cannot drive `GateBadgeLayout.metrics(for:)`
	/// (baselined against a ~220pt pet). Callers pass the user's chosen badge
	/// scale directly instead.
	func reposition(
		content: GateBadgeContent,
		metrics: GateBadgeLayout.Metrics,
		relativeTo anchorFrame: CGRect,
		visibleFrame: CGRect
	) {
		badgeView.configure(content: content, metrics: metrics, tokenAlignment: .leading)
		// Hug the stacked tokens (ticket over gate, both left-aligned).
		let size = badgeView.preferredSize
		let frame = GateBadgeLayout.frame(
			relativeTo: anchorFrame,
			badgeSize: size,
			leadingInset: MinimalistBadgeView.hPad,
			visibleFrame: visibleFrame
		)
		setFrame(frame, display: true)
		badgeView.frame = NSRect(origin: .zero, size: frame.size)
	}
}

