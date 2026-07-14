import AppKit

/// Layout for the in-frame “Hide pet” pill shown on right-click (Codex-style).
enum FloatingPetHidePrompt {
	static let title = "Hide pet"
	/// Title for the minimalist badge's right-click affordance, which hides the
	/// whole platform strip rather than an Own-mode pet sprite.
	static let panelTitle = "Hide panel"
	/// Title for the right-click "Force Idle" escape hatch. Surfaced only when the
	/// pet is stuck in a non-idle animation (see `offersForceIdle(for:)`); resets
	/// the pet to idle by rewriting its `state.d/` slice.
	static let forceIdleTitle = "Force Idle"
	/// Title for the right-click "Rename" affordance, offered only on a
	/// session-keyed window (P15.06).
	static let renameTitle = "Rename…"
	/// Title for the right-click "Prune Session" affordance, offered only on a
	/// session-keyed window (P15.07). Destroys the panel and its backing state
	/// (slice, free-list number, rename label) — the same end-state as
	/// automatic TTL expiry.
	static let pruneTitle = "Prune Session"
	/// Prune's menu item / confirmation-alert title: the bare `pruneTitle` for
	/// a genuinely solo window, or `pruneTitle` suffixed with the resolved
	/// session's `"(<platform> · <label>)"` identity for a fold window
	/// (`resolvedIdentity != key` — origin-folded with 2+ real sessions, or
	/// Combined) so the user knows what's about to be removed before
	/// confirming (P19.03).
	static func pruneMenuTitle(foldedSessionDisplay: String?) -> String {
		guard let foldedSessionDisplay else { return pruneTitle }
		return "\(pruneTitle) (\(foldedSessionDisplay))"
	}
	/// Title for the right-click "Sync Label" affordance, offered only on a
	/// session-keyed window (mirrors Prune Session's gating): re-fetches the
	/// platform's own current thread title — bypassing the pool's
	/// once-resolved-then-frozen cache — and adopts it as this session's
	/// label. Lets a user who renamed the thread in the source app (Claude
	/// Code, Codex, Cursor) after Codogotchi already froze an earlier title
	/// pull the rename in manually, since Codogotchi never re-polls a
	/// resolved title on its own.
	static let syncLabelTitle = "Sync Label"
	/// Title for the right-click "Hide All Other Pets" affordance, offered
	/// unconditionally on every panel (Own mode, Minimalist mode, and the
	/// combined window — all share this prompt). Hides every OTHER
	/// currently-rendered window, same-platform sibling sessions included,
	/// leaving only the panel that was clicked. A snapshot action, not a
	/// mode: a session or platform that spawns afterward is unaffected and
	/// renders normally.
	static let hideAllOtherPetsTitle = "Hide All Other Pets"
	/// Title for the right-click mode-switch affordance on an Own/Combined pet
	/// window: flips the platform to Minimalist mode (or, on the combined
	/// window, turns on combined-minimalist rendering). For a sessions-enabled
	/// platform this is a platform-level switch — every session panel of that
	/// origin flips together, since mode is keyed per-origin.
	static let minimalistModeTitle = "Minimalist Mode"
	/// Title for the right-click mode-switch affordance on a Minimalist strip:
	/// the inverse of `minimalistModeTitle` — back to the full pet renderer.
	static let petModeTitle = "Pet Mode"
	/// Title for the right-click "Panel Size" affordance on a Minimalist strip.
	/// Opens the slider pill (`MinimalistPanelSizePillPanel`) driving the
	/// same global `minimalist_badge_scale` the Customization tab's slider
	/// writes — ellipsis per the "opens follow-up UI" convention (`Rename…`).
	static let panelSizeTitle = "Panel Size…"
	static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
	static let horizontalPadding: CGFloat = 14
	static let verticalPadding: CGFloat = 7
	/// Vertical gap between stacked pill rows when the prompt shows more than one
	/// action (e.g. "Force Idle" above "Hide pet").
	static let rowSpacing: CGFloat = 6

	static func preferredSize(title: String = FloatingPetHidePrompt.title) -> CGSize {
		let textSize = (title as NSString).size(withAttributes: [.font: font])
		let height = ceil(textSize.height) + verticalPadding * 2
		let width = ceil(textSize.width) + horizontalPadding * 2
		return CGSize(width: width, height: height)
	}

	/// Size of a vertical stack of pill rows: width fits the widest title, height
	/// sums the equal-height rows plus `rowSpacing` between them. A single title
	/// reduces to `preferredSize(title:)`.
	static func stackSize(titles: [String]) -> CGSize {
		guard !titles.isEmpty else { return .zero }
		let rowSizes = titles.map { preferredSize(title: $0) }
		let width = rowSizes.map(\.width).max() ?? 0
		let rowHeight = rowSizes.first?.height ?? 0
		let height = rowHeight * CGFloat(titles.count)
			+ rowSpacing * CGFloat(titles.count - 1)
		return CGSize(width: width, height: height)
	}

	/// Whether the right-click prompt should offer the "Force Idle" escape hatch
	/// for `state`. Offered for every state except `idle` — the idle "set"
	/// (idle / impatient / frustrated) all share the `.idle` wire state, since
	/// escalation is renderer-internal, so this single check covers all three.
	static func offersForceIdle(for state: ActivityState) -> Bool {
		state != .idle
	}

	/// Frame for row `index` (0 = top) within a prompt panel of `panelSize` that
	/// holds `count` equal-height rows separated by `rowSpacing`. AppKit's origin
	/// is bottom-left, so index 0 is pinned to the top edge and the last row sits
	/// on the bottom edge. Shared by the panel's row layout and its tests so the
	/// stacking geometry has one source of truth.
	static func rowFrame(index: Int, count: Int, panelSize: CGSize) -> CGRect {
		let rowHeight = preferredSize().height
		let minY = panelSize.height
			- CGFloat(index + 1) * rowHeight
			- CGFloat(index) * rowSpacing
		return CGRect(x: 0, y: minY, width: panelSize.width, height: rowHeight)
	}

	/// Places the pill so the right-click point is its top-left corner (AppKit
	/// coordinates: `origin` is the rect’s bottom-left, so `maxY` is the top edge).
	/// Keeps `minX` / `maxY` pinned to the click when possible; only nudges the
	/// anchor when the pill would cross the left/bottom inset (never slides left
	/// just because it would extend past the right edge — that looked “top-middle”).
	static func frame(anchor: CGPoint, promptSize: CGSize, in bounds: CGRect) -> CGRect {
		let margin: CGFloat = 4
		let inset = bounds.insetBy(dx: margin, dy: margin)
		var minX = anchor.x
		var maxY = anchor.y
		if minX < inset.minX {
			minX = inset.minX
		}
		if maxY > inset.maxY {
			maxY = inset.maxY
		}
		var minY = maxY - promptSize.height
		if minY < inset.minY {
			minY = inset.minY
			maxY = minY + promptSize.height
		}
		return CGRect(
			x: minX,
			y: minY,
			width: promptSize.width,
			height: promptSize.height
		)
	}

	static func shouldPresent(
		at localPoint: CGPoint,
		in bounds: CGRect,
		hasActivePointerInteraction: Bool
	) -> Bool {
		bounds.contains(localPoint) && !hasActivePointerInteraction
	}
}

extension FloatingPetHidePrompt {
	/// Screen-space frame for the prompt window, anchored like `frame(...)` but
	/// clamped to the visible display bounds (not the floating pet window), so
	/// the pill can extend beyond the pet frame without clipping.
	static func screenFrame(anchor: CGPoint, promptSize: CGSize, visibleFrame: CGRect) -> CGRect {
		let margin: CGFloat = 6
		let inset = visibleFrame.insetBy(dx: margin, dy: margin)
		var minX = anchor.x
		var maxY = anchor.y
		if minX < inset.minX { minX = inset.minX }
		if maxY > inset.maxY { maxY = inset.maxY }
		var minY = maxY - promptSize.height
		if minY < inset.minY {
			minY = inset.minY
			maxY = minY + promptSize.height
		}
		if minX > inset.maxX - 12 {
			minX = inset.maxX - 12
		}
		return CGRect(x: minX, y: minY, width: promptSize.width, height: promptSize.height)
	}
}

