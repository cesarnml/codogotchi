import Foundation

/// Maps `state.json` `source_event.origin` strings to the platform whose logo
/// the animation badge surfaces. Only the five coding platforms that can
/// *drive* the pet get an icon; orchestration/bookkeeping origins (`soa`,
/// `sync`, `manual`) and unknown/absent values resolve to `nil` so no chip is
/// shown.
///
/// The raw-value strings are the asset-catalog imageset names (template SVGs in
/// `Assets.xcassets`); the renderer tints them to match the badge text so a
/// single monochrome glyph reads on any backdrop behind the transparent frame.
enum PlatformAttribution: String {
	case claudeCode = "PlatformClaudeCode"
	case codex = "PlatformCodex"
	case cursor = "PlatformCursor"
	case vscode = "PlatformVSCode"
	case antigravity = "PlatformAntigravity"
	/// Shown persistently on the combined window while idle; feeds the ⭐ Default pill in Pet tab.
	case `default` = "PlatformDefault"

	/// Resolve a `source_event.origin` value to a platform, or `nil` when the
	/// origin is absent, non-platform (`soa`/`sync`/`manual`), or unrecognized.
	init?(origin: String?) {
		switch origin {
		case "combined": self = .default
		case "claude_code": self = .claudeCode
		case "codex": self = .codex
		case "cursor": self = .cursor
		case "vscode": self = .vscode
		case "antigravity": self = .antigravity
		default: return nil
		}
	}

	/// Asset-catalog imageset name for the platform's template logo.
	var assetName: String { rawValue }

	/// Human-readable name for tooltips and accessibility.
	var displayName: String {
		switch self {
		case .default: "Default"
		case .claudeCode: "Claude Code"
		case .codex: "Codex"
		case .cursor: "Cursor"
		case .vscode: "VS Code"
		case .antigravity: "Antigravity"
		}
	}
}
