import AppKit

@MainActor
final class AnimationBadgePanel: NSPanel {
	private let badgeView = AnimationBadgeView(frame: .zero)

	/// Fired with the screen-space anchor when the user right-clicks the
	/// platform chip, activity pill, or session badge. Wired by
	/// `FloatingPetPanelController` to present the same hide/rename/force-idle
	/// prompt a click on the pet sprite itself presents — this badge is its
	/// own floating window, so it never received that click otherwise.
	var onRightClickRequested: ((CGPoint) -> Void)?

	/// Fired when the user starts/continues/ends a left-click-drag on the
	/// platform chip, activity pill, or session badge. Wired by
	/// `FloatingPetPanelController` to move the pet panel this badge is
	/// anchored to — mirrors `onRightClickRequested`'s reasoning: this badge
	/// is its own floating window, so a drag on it never reached the pet
	/// panel otherwise.
	var onDragBegan: (() -> Void)?
	var onDragChanged: (() -> Void)?
	var onDragEnded: (() -> Void)?

	/// Fired when the user double-clicks the platform chip — mirrors the
	/// attention bubble's Focus button. Wired by `FloatingPetPanelController`
	/// to the same `AttentionFocusTarget.focus(sourceEvent:)` call.
	var onPlatformChipDoubleClick: (() -> Void)?

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
		// Was click-through except while a tooltip was live (see `reposition`);
		// now always interactive so a right-click/drag reaches the badge
		// regardless of tooltip/session state.
		ignoresMouseEvents = false
		contentView = badgeView
		badgeView.onRightMouseDown = { [weak self] event in
			guard let self else { return }
			self.onRightClickRequested?(self.convertPoint(toScreen: event.locationInWindow))
		}
		badgeView.onDragBegan = { [weak self] in self?.onDragBegan?() }
		badgeView.onDragChanged = { [weak self] in self?.onDragChanged?() }
		badgeView.onDragEnded = { [weak self] in self?.onDragEnded?() }
		badgeView.onPlatformChipDoubleClick = { [weak self] in self?.onPlatformChipDoubleClick?() }
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }

	func reposition(
		label: String,
		platform: PlatformAttribution?,
		inFlight: Bool,
		promptTimer: PromptTimerPresentation? = nil,
		sessionNumber: Int? = nil,
		sessionLabel: String? = nil,
		sessionTooltip: String? = nil,
		modeIndicator: String? = nil,
		relativeTo petFrame: CGRect,
		visibleFrame: CGRect
	) {
		badgeView.configure(
			text: label,
			platform: platform,
			inFlight: inFlight,
			promptTimer: promptTimer,
			metrics: AnimationBadgeLayout.metrics(for: petFrame)
		)
		badgeView.configureSessionNumber(sessionNumber, label: sessionLabel, tooltip: sessionTooltip)
		badgeView.configureModeIndicator(modeIndicator)
		let size = badgeView.preferredSize
		let frame = AnimationBadgeLayout.frame(
			relativeTo: petFrame,
			badgeSize: size,
			anchorX: badgeView.pillCenterX,
			visibleFrame: visibleFrame
		)
		setFrame(frame, display: true)
		badgeView.frame = NSRect(origin: .zero, size: frame.size)
	}
}

