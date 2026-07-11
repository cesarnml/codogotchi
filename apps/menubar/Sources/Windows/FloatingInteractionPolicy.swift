import AppKit

enum FloatingInteractionHitTarget: Equatable {
	case dragRegion
	case resizeAffordance
}

enum FloatingInteractionPolicy {
	static let resizeAffordanceSize = CGSize(width: 28, height: 28)
	/// Enlarged hover/reveal zone (frame bottom-right anchored). Grab hit-testing
	/// stays on `resizeAffordanceRect` so accidental resizes near the corner are
	/// unlikely.
	static let resizeAffordanceRevealMultiplier: CGFloat = 2

	static func hitTest(point: CGPoint, in bounds: CGRect) -> FloatingInteractionHitTarget {
		if resizeAffordanceRect(in: bounds).contains(point) {
			return .resizeAffordance
		}
		return .dragRegion
	}

	static func resizeAffordanceRect(in bounds: CGRect) -> CGRect {
		CGRect(
			x: bounds.maxX - resizeAffordanceSize.width,
			y: bounds.minY,
			width: resizeAffordanceSize.width,
			height: resizeAffordanceSize.height
		)
	}

	/// Bottom-right anchored zone used for hover/reveal and affordance tracking.
	/// Larger than `resizeAffordanceRect` so the handle lights up when the cursor
	/// is nearby; does not widen the grab target.
	static func resizeAffordanceRevealRect(in bounds: CGRect) -> CGRect {
		let revealWidth = resizeAffordanceSize.width * resizeAffordanceRevealMultiplier
		let revealHeight = resizeAffordanceSize.height * resizeAffordanceRevealMultiplier
		return CGRect(
			x: bounds.maxX - revealWidth,
			y: bounds.minY,
			width: revealWidth,
			height: revealHeight
		)
	}

	/// Positions the panel so the `mouseDown` grab point stays under the cursor.
	/// `grabOffsetInScreen` is the vector from the window origin to the click in
	/// screen space (bottom-left origin, same as `NSWindow.frame`).
	static func draggedFrame(
		mouseLocationInScreen: CGPoint,
		grabOffsetInScreen: CGPoint,
		windowSize: CGSize,
		visibleFrame: CGRect
	) -> CGRect {
		FloatingFramePolicy.clamp(
			CGRect(
				x: mouseLocationInScreen.x - grabOffsetInScreen.x,
				y: mouseLocationInScreen.y - grabOffsetInScreen.y,
				width: windowSize.width,
				height: windowSize.height
			),
			to: visibleFrame
		)
	}

	/// Cumulative screen delta from a fixed start (resize drags).
	static func draggedFrame(
		from frame: CGRect,
		dragDelta: CGSize,
		visibleFrame: CGRect
	) -> CGRect {
		FloatingFramePolicy.clamp(
			CGRect(
				x: frame.origin.x + dragDelta.width,
				y: frame.origin.y + dragDelta.height,
				width: frame.width,
				height: frame.height
			),
			to: visibleFrame
		)
	}

	/// Horizontal screen delta that drives resize. Pure vertical drags return 0
	/// (Codex-style: only left/right motion changes scale).
	static func resizeHorizontalDelta(from rawDelta: CGSize) -> CGFloat {
		rawDelta.width
	}

	/// Uniform width/height growth applied to interaction feedback from the
	/// horizontal resize delta (zero when the drag has no horizontal component).
	static func resizeDragDelta(from rawDelta: CGSize) -> CGSize {
		let horizontal = resizeHorizontalDelta(from: rawDelta)
		guard horizontal != 0 else { return .zero }
		return CGSize(width: horizontal, height: horizontal)
	}

	static func resizedFrame(
		from frame: CGRect,
		dragDelta: CGSize,
		visibleFrame: CGRect
	) -> CGRect {
		let horizontalDelta = resizeHorizontalDelta(from: dragDelta)
		guard horizontalDelta != 0, frame.width > 0, frame.height > 0 else {
			return FloatingFramePolicy.clamp(frame, to: visibleFrame)
		}

		let aspect = frame.width / frame.height
		let newWidth = frame.width + horizontalDelta
		let newHeight = newWidth / aspect
		return FloatingFramePolicy.clamp(
			CGRect(
				x: frame.origin.x,
				y: frame.origin.y,
				width: newWidth,
				height: newHeight
			),
			to: visibleFrame
		)
	}

	/// Whether the resize affordance icon should paint for the current pointer
	/// and interaction state.
	static func shouldShowResizeAffordance(
		pointerInAffordance: Bool,
		isResizing: Bool
	) -> Bool {
		pointerInAffordance || isResizing
	}

	/// Avoid tearing down `NSTrackingArea` on every layout pass — only when the
	/// content bounds actually change (resize drags call `layout` every frame).
	static func shouldRefreshTrackingAreas(previousBounds: CGRect, newBounds: CGRect) -> Bool {
		previousBounds.size != newBounds.size
	}

	/// AppKit default (non-flipped) view coordinates: origin at bottom-left.
	static func pointerInBounds(_ point: CGPoint, bounds: CGRect) -> Bool {
		bounds.contains(point)
	}

	/// Reserved-row interaction for a primary (left) click on the pet body.
	/// Resize drags use `interaction(forStepDelta:…)` instead.
	static func clickInteraction(hitTarget: FloatingInteractionHitTarget) -> FloatingInteraction? {
		switch hitTarget {
		case .dragRegion:
			return .jumping
		case .resizeAffordance:
			return nil
		}
	}

	/// Maps a single drag event's screen-space step (not cumulative delta from
	/// `mouseDown`) to the reserved-row interaction. Vertical-only steps keep
	/// the previous running direction so frame translation stays smooth.
	static func interaction(
		forStepDelta delta: CGSize,
		hitTarget: FloatingInteractionHitTarget,
		previous: FloatingInteraction? = nil
	) -> FloatingInteraction? {
		switch hitTarget {
		case .resizeAffordance:
			// Resizing must not animate the pet: clear any interaction so the
			// activity-state animation that was already playing stays put.
			return nil
		case .dragRegion:
			if delta.width > 0 { return .runningRight }
			if delta.width < 0 { return .runningLeft }
			// Vertical-only steps must not drop back to activity frames mid-drag
			// (common on the first `mouseDragged` tick while a click set `.jumping`).
			if previous == .runningLeft || previous == .runningRight || previous == .jumping {
				return previous
			}
			return nil
		}
	}
}

