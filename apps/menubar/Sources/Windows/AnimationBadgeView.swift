import AppKit

/// Transparent container laying out an optional platform chip immediately left
/// of the activity-state label pill. When no platform is attributed the chip is
/// detached and the pill stands alone, preserving the prior single-pill look.
final class AnimationBadgeView: NSView {
	private let chipView = PlatformChipView(frame: .zero)
	private let pillView = AnimationLabelPillView(frame: .zero)
	private let promptTimerView = PromptTimerChipView(frame: .zero)
	private let stackView = NSStackView()
	private let sessionBadge = PlatformSessionBadge(frame: .zero)
	/// Fixed, non-renamable fold/platform-only identity chip (P19.04 / QC) —
	/// same frosted chrome as `sessionBadge`, but never wired to Rename.
	/// Lives to the LEFT of `sessionBadge` on the identity row.
	private let modeIndicatorBadge = PlatformSessionBadge(frame: .zero)
	private let identityStack = NSStackView()
	/// Test-observable rendered text, `nil` while hidden.
	private(set) var currentModeIndicatorText: String?
	private let outerStack = NSStackView()
	private var metrics = GateBadgeLayout.metrics(
		for: CGRect(x: 0, y: 0, width: GateBadgeLayout.baselinePetWidth, height: 160)
	)
	private var currentSessionNumber: Int?
	private var currentSessionLabel: String?
	private var currentSessionTooltip: String?
	/// `private(set)` (not `private`) so tests can observe the presentation
	/// that actually reached rendering, distinct from asserting on an
	/// internal override field a caller might set without it surviving to
	/// `applyPromptTimerView()` (see P18.04's promptTimerPresentationOverride fix).
	private(set) var currentPromptTimer: PromptTimerPresentation?

	/// Forwards a right-click anywhere on the chip/pill/session-badge stack up
	/// to `AnimationBadgePanel`, which converts it to a screen anchor. `nil`
	/// when this view is embedded directly in `MinimalistBadgeView` (no
	/// owning `AnimationBadgePanel`) — falls back to `super` there so the
	/// event keeps bubbling up to `MinimalistBadgeView`'s own handler, exactly
	/// as it did before this override existed.
	var onRightMouseDown: ((NSEvent) -> Void)?

	override func rightMouseDown(with event: NSEvent) {
		guard let onRightMouseDown else {
			super.rightMouseDown(with: event)
			return
		}
		onRightMouseDown(event)
	}

	/// Forwards a left-click-drag anywhere on the chip/pill/session-badge
	/// stack up to `AnimationBadgePanel`, which routes it into moving the pet
	/// panel. `nil` when embedded directly in `MinimalistBadgeView` — falls
	/// back to `super` there for the same reason `onRightMouseDown` does: the
	/// event keeps bubbling up to `MinimalistBadgeView`'s own drag handling,
	/// unchanged from before this override existed.
	var onDragBegan: (() -> Void)?
	var onDragChanged: (() -> Void)?
	var onDragEnded: (() -> Void)?

	/// Fired when the user double-clicks the platform chip specifically (not
	/// the pill/session badge) — mirrors the attention bubble's Focus button,
	/// giving the chip the same "jump to the driving app" gesture even when no
	/// bubble is on screen to click Focus on.
	var onPlatformChipDoubleClick: (() -> Void)?

	override func mouseDown(with event: NSEvent) {
		if event.clickCount == 2, chipView.superview != nil {
			let pointInChip = chipView.convert(event.locationInWindow, from: nil)
			if chipView.bounds.contains(pointInChip) {
				onPlatformChipDoubleClick?()
				return
			}
		}
		guard let onDragBegan else {
			super.mouseDown(with: event)
			return
		}
		onDragBegan()
	}

	override func mouseDragged(with event: NSEvent) {
		guard let onDragChanged else {
			super.mouseDragged(with: event)
			return
		}
		onDragChanged()
	}

	override func mouseUp(with event: NSEvent) {
		guard let onDragEnded else {
			super.mouseUp(with: event)
			return
		}
		onDragEnded()
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.masksToBounds = false

		stackView.orientation = .horizontal
		stackView.alignment = .centerY
		stackView.addArrangedSubview(pillView)

		sessionBadge.isHidden = true
		modeIndicatorBadge.isHidden = true
		promptTimerView.isHidden = true

		identityStack.orientation = .horizontal
		identityStack.alignment = .centerY
		identityStack.spacing = 6
		identityStack.addArrangedSubview(modeIndicatorBadge)
		identityStack.addArrangedSubview(sessionBadge)

		outerStack.orientation = .vertical
		// `.leading` (not `.centerX`) pins the identity row's leading edge to
		// the chip+pill row's leading edge (the platform chip, when present)
		// regardless of which row is wider. `.centerX` would let a wide session
		// label re-center the narrower chip+pill row within the view, shifting it
		// off the `pillCenterX` anchor the panel uses to keep the pill centered
		// on the pet — see `AnimationBadgeLayout.frame`.
		outerStack.alignment = .leading
		outerStack.spacing = 4
		outerStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(outerStack)
		outerStack.addArrangedSubview(stackView)
		outerStack.addArrangedSubview(identityStack)
		NSLayoutConstraint.activate([
			outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
			outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
			outerStack.topAnchor.constraint(equalTo: topAnchor),
			outerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func configure(
		text: String,
		platform: PlatformAttribution?,
		inFlight: Bool,
		promptTimer: PromptTimerPresentation? = nil,
		metrics: GateBadgeLayout.Metrics,
		platformChipAnimationEnabled: Bool = false
	) {
		self.metrics = metrics
		currentPromptTimer = promptTimer
		stackView.spacing = metrics.interBadgeSpacing
		identityStack.spacing = max(6, metrics.interBadgeSpacing)
		pillView.configure(text: text, inFlight: inFlight, metrics: metrics)
		if let platform {
			chipView.configure(
				platform: platform,
				metrics: metrics,
				inFlight: inFlight,
				animationEnabled: platformChipAnimationEnabled
			)
			if chipView.superview == nil {
				stackView.insertArrangedSubview(chipView, at: 0)
			}
		} else if chipView.superview != nil {
			stackView.removeArrangedSubview(chipView)
			chipView.removeFromSuperview()
		}
		applyPromptTimerView()
		sessionBadge.configure(
			number: currentSessionNumber, label: currentSessionLabel, tooltip: currentSessionTooltip,
			metrics: metrics)
		modeIndicatorBadge.configure(
			number: nil, label: currentModeIndicatorText, tooltip: nil, metrics: metrics)
		layoutSubtreeIfNeeded()
	}

	/// Forwarded to the platform chip when the badge panel is ordered out or back
	/// in. See `PlatformChipView.setAnimationSuspended`.
	func setChipAnimationSuspended(_ suspended: Bool) {
		chipView.setAnimationSuspended(suspended)
	}

	func configurePromptTimer(_ presentation: PromptTimerPresentation?) {
		currentPromptTimer = presentation
		applyPromptTimerView()
		layoutSubtreeIfNeeded()
	}

	/// Shows/hides and labels the mode-indicator chip to the left of the
	/// session-label badge. `nil` hides it entirely — this chip only ever
	/// appears for platform-only / Combined windows, never for session-keyed
	/// ones. Kept separate from `configure()` (like `configurePromptTimer`) so
	/// an unrelated same-tick `configure()` call never clobbers it.
	func configureModeIndicator(_ text: String?) {
		currentModeIndicatorText = text
		modeIndicatorBadge.configure(number: nil, label: text, tooltip: nil, metrics: metrics)
		layoutSubtreeIfNeeded()
	}

	/// Shows/hides and labels the session badge to the right of the mode chip
	/// when both are present. A session-keyed window (`number` non-`nil`) shows
	/// "Session N" unless renamed; a platform-only/Combined window shows the
	/// winning session's rename / LLM title / "Session N" via `label`. The row
	/// hides only when both number and label are `nil`.
	func configureSessionNumber(_ number: Int?, label: String? = nil, tooltip: String? = nil) {
		currentSessionNumber = number
		currentSessionLabel = label
		currentSessionTooltip = tooltip
		sessionBadge.configure(number: number, label: label, tooltip: tooltip, metrics: metrics)
		layoutSubtreeIfNeeded()
	}

	var preferredSize: CGSize {
		layoutSubtreeIfNeeded()
		var size = stackView.fittingSize
		let identityVisible = !modeIndicatorBadge.isHidden || !sessionBadge.isHidden
		if identityVisible {
			size.width = max(size.width, identityStack.fittingSize.width)
			size.height += 4 + max(
				modeIndicatorBadge.isHidden ? 0 : modeIndicatorBadge.intrinsicContentSize.height,
				sessionBadge.isHidden ? 0 : sessionBadge.intrinsicContentSize.height)
		}
		return size
	}

	/// X-coordinate (in badge-local space) of the label pill's horizontal center.
	/// The pill is the rightmost element, so its center sits `pillWidth / 2` in
	/// from the trailing edge. The panel anchors *this* point on the pet's midX so
	/// the pill owns the dead-center position and the chip hangs off to its left;
	/// with no chip it collapses to `width / 2` (centered, as before).
	var pillCenterX: CGFloat {
		layoutSubtreeIfNeeded()
		let leadingWidth =
			chipView.superview == nil
			? 0
			: chipView.intrinsicContentSize.width + stackView.spacing
		return leadingWidth + pillView.intrinsicContentSize.width / 2
	}

	private func applyPromptTimerView() {
		guard let currentPromptTimer else {
			if promptTimerView.superview != nil {
				stackView.removeArrangedSubview(promptTimerView)
				promptTimerView.removeFromSuperview()
			}
			promptTimerView.isHidden = true
			return
		}
		promptTimerView.configure(presentation: currentPromptTimer, metrics: metrics)
		promptTimerView.isHidden = false
		if promptTimerView.superview == nil {
			stackView.addArrangedSubview(promptTimerView)
		}
	}
}
