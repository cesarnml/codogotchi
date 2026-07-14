import AppKit

final class BadgeRowView: NSView {
	private var isDisabled: Bool
	var onTap: (() -> Void)?
	var checkmark: NSImageView?

	init(isDisabled: Bool) {
		self.isDisabled = isDisabled
		super.init(frame: .zero)
		wantsLayer = true
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { nil }

	func update(isChecked: Bool, isDisabled: Bool) {
		self.isDisabled = isDisabled
		checkmark?.isHidden = !isChecked
		updateTrackingAreas()
	}

	override func mouseUp(with event: NSEvent) {
		guard !isDisabled else { return }
		onTap?()
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		trackingAreas.forEach { removeTrackingArea($0) }
		guard !isDisabled else { return }
		addTrackingArea(NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .activeInActiveApp],
			owner: self,
			userInfo: nil
		))
	}

	override func mouseEntered(with event: NSEvent) {
		layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.1).cgColor
	}

	override func mouseExited(with event: NSEvent) {
		layer?.backgroundColor = .clear
	}
}

func badgeDisplayName(_ key: String) -> String {
	switch key {
	case "default": return "Default"
	case "claude_code": return "Claude Code"
	case "vscode": return "VS Code"
	case "codex": return "Codex"
	case "cursor": return "Cursor"
	case "antigravity": return "Antigravity"
	default: return key
	}
}

func platformAttribution(forBadgeKey key: String) -> PlatformAttribution? {
	switch key {
	case "default": return .default
	case "claude_code": return .claudeCode
	case "vscode": return .vscode
	case "codex": return .codex
	case "cursor": return .cursor
	case "antigravity": return .antigravity
	default: return nil
	}
}

/// Shared brand palette for platform logos across General and Pet settings.
/// Keep these colors centralized so cards, popovers, and hook rows do not drift.
func platformIconTint(forBadgeKey key: String) -> NSColor {
	switch key {
	case "default":
		return NSColor(srgbRed: 0.90, green: 0.13, blue: 0.63, alpha: 1)  // AI fuchsia
	case "claude_code":
		return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)  // Anthropic clay
	case "codex":
		return NSColor(srgbRed: 0.06, green: 0.64, blue: 0.50, alpha: 1)  // OpenAI green
	case "vscode":
		return NSColor(srgbRed: 0.00, green: 0.48, blue: 0.80, alpha: 1)  // VS Code blue
	case "cursor":
		return .systemRed
	case "antigravity":
		return NSColor(srgbRed: 0.545, green: 0.361, blue: 0.965, alpha: 1)  // AI violet
	default:
		return .labelColor
	}
}

var assignBtnKey: UInt8 = 0
var importBtnKey: UInt8 = 2

/// Top-left origin so a short pet grid anchors to the top of its scroll view
/// instead of sinking to the bottom (the default non-flipped behavior).
