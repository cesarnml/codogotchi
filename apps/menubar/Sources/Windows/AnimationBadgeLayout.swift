import AppKit

enum AnimationBadgeLayout {
	/// Gap between the badge and the pet frame's bottom-left corner so the badge
	/// sits *just inside* the border rather than flush against it. Matches the
	/// gate badge's fixed `margin` so both chrome elements share one spacing feel.
	static let inset: CGFloat = GateBadgeLayout.margin

	/// Reuse the gate badge metrics verbatim so the animation badge scales with
	/// the pet frame identically (single source of scaling truth).
	static func metrics(for petFrame: CGRect) -> GateBadgeLayout.Metrics {
		GateBadgeLayout.metrics(for: petFrame)
	}

	/// Below the pet, with the badge's *top* edge sitting `inset` above the
	/// frame's bottom border so the sprite appears to stand on the badge (the
	/// badge body hangs below the feet rather than overlapping the character).
	/// `anchorX` is the badge-local x that lands on the pet's midX — the label
	/// pill's center, so the pill owns the dead-center position and the platform
	/// chip extends to its left. Then clamps to the visible display.
	static func frame(
		relativeTo petFrame: CGRect,
		badgeSize: CGSize,
		anchorX: CGFloat,
		visibleFrame: CGRect
	) -> CGRect {
		let rect = CGRect(
			x: petFrame.midX - anchorX,
			y: petFrame.minY + inset - badgeSize.height,
			width: badgeSize.width,
			height: badgeSize.height
		)
		let safe = visibleFrame.insetBy(dx: GateBadgeLayout.margin, dy: GateBadgeLayout.margin)
		let x = max(safe.minX, min(safe.maxX - rect.width, rect.minX))
		let y = max(safe.minY, min(safe.maxY - rect.height, rect.minY))
		return CGRect(x: x, y: y, width: rect.width, height: rect.height)
	}
}

