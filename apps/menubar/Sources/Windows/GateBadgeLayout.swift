import AppKit

enum GateBadgeLayout {
	static let margin: CGFloat = 4
	static let baselinePetWidth: CGFloat = 220

	struct Metrics: Equatable {
		let horizontalPadding: CGFloat
		let verticalPadding: CGFloat
		let interBadgeSpacing: CGFloat
		let cornerRadius: CGFloat
		let badgeHeight: CGFloat
		let fontSize: CGFloat
	}

	/// Hard floor/ceiling accepted by `metrics(scale:)`. Wider than the range
	/// Own mode can actually reach (see `achievableMinScale`/`achievableMaxScale`)
	/// so this stays a safety clamp, not a UI bound.
	static let minScale: CGFloat = 0.75
	static let maxScale: CGFloat = 1.5

	/// Smallest/largest scale Own mode can actually reach, derived from
	/// `FloatingFramePolicy`'s pet-panel size bounds. The Minimalist badge-size
	/// slider in Settings uses this narrower range — not `minScale`/`maxScale` —
	/// so "Large" never exceeds what an Own-mode badge ever renders at.
	static let achievableMinScale: CGFloat = max(
		minScale, FloatingFramePolicy.minimumSize.width / baselinePetWidth
	)
	static let achievableMaxScale: CGFloat = min(
		maxScale, FloatingFramePolicy.maximumSize.width / baselinePetWidth
	)

	static func metrics(for petFrame: CGRect) -> Metrics {
		metrics(scale: petFrame.width / baselinePetWidth)
	}

	static func metrics(scale rawScale: CGFloat) -> Metrics {
		let scale = max(minScale, min(maxScale, rawScale))
		// Base values net +14% over the original 8/4/5/7/20/8.7 set (+20% then
		// -5%) so the whole badge family (platform chip, animation/session
		// badges, ticket and gate tokens — all single-sourced from this
		// function) reads larger across the entire scale range, not just at
		// one end.
		return Metrics(
			horizontalPadding: round(9.12 * scale),
			verticalPadding: round(4.56 * scale),
			interBadgeSpacing: round(5.7 * scale),
			cornerRadius: round(7.98 * scale),
			badgeHeight: round(22.8 * scale),
			fontSize: round(9.918 * scale * 10) / 10
		)
	}

	static func frame(relativeTo petFrame: CGRect, badgeSize: CGSize, visibleFrame: CGRect) -> CGRect {
		// Centered on the pet's horizontal midpoint, just above the top border —
		// vertically symmetric with the bottom-centered animation badge.
		let rect = CGRect(
			x: petFrame.midX - badgeSize.width / 2,
			y: petFrame.maxY,
			width: badgeSize.width,
			height: badgeSize.height
		)
		let safe = visibleFrame.insetBy(dx: margin, dy: margin)
		let x = max(safe.minX, min(safe.maxX - rect.width, rect.minX))
		let y = max(safe.minY, min(safe.maxY - rect.height, rect.minY))
		return CGRect(x: x, y: y, width: rect.width, height: rect.height)
	}

	/// Minimalist-mode variant: left-aligned to the strip's leading edge
	/// (`anchorFrame.minX + leadingInset`) instead of centered on
	/// `anchorFrame.midX`. Centering looked awkward stacked above a
	/// left-anchored chip+pill row that itself no longer centers (see the
	/// `SessionLabel`/`PlatformChip` leading-alignment fix); this mirrors that
	/// same left-aligned treatment for the ticket/gate stack.
	static func frame(
		relativeTo anchorFrame: CGRect,
		badgeSize: CGSize,
		leadingInset: CGFloat,
		visibleFrame: CGRect
	) -> CGRect {
		let rect = CGRect(
			x: anchorFrame.minX + leadingInset,
			y: anchorFrame.maxY,
			width: badgeSize.width,
			height: badgeSize.height
		)
		let safe = visibleFrame.insetBy(dx: margin, dy: margin)
		let x = max(safe.minX, min(safe.maxX - rect.width, rect.minX))
		let y = max(safe.minY, min(safe.maxY - rect.height, rect.minY))
		return CGRect(x: x, y: y, width: rect.width, height: rect.height)
	}

	/// Own-mode variant: left-aligned to `leadingX` — the platform chip's
	/// leading edge in screen space (the animation badge panel's own `minX`,
	/// *not* the pet sprite's `minX`; the chip sits well inside the pet frame,
	/// anchored off `pillCenterX`) — with the top sitting `petFrame.maxY`,
	/// same as the centered variant. Replaces centering on `petFrame.midX`,
	/// which put the ticket/gate stack over the pet's horizontal center while
	/// the chip below it sits off to the left, so the two never lined up.
	static func frame(
		aboveTopOf petFrame: CGRect,
		badgeSize: CGSize,
		leadingX: CGFloat,
		visibleFrame: CGRect
	) -> CGRect {
		let rect = CGRect(
			x: leadingX,
			y: petFrame.maxY,
			width: badgeSize.width,
			height: badgeSize.height
		)
		let safe = visibleFrame.insetBy(dx: margin, dy: margin)
		let x = max(safe.minX, min(safe.maxX - rect.width, rect.minX))
		let y = max(safe.minY, min(safe.maxY - rect.height, rect.minY))
		return CGRect(x: x, y: y, width: rect.width, height: rect.height)
	}
}

