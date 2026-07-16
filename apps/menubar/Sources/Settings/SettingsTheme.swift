import AppKit

// MARK: - SettingsTheme

/// Fixed dark-navy palette for the Settings window, matching the approved
/// mockup. Applied window-wide (all six tabs) via the window's forced
/// `.darkAqua` appearance + these background layers; system semantic colors
/// (`labelColor` etc.) resolve against the dark appearance on top of it.
enum SettingsTheme {
	static let windowBackground = NSColor(srgbRed: 0.043, green: 0.063, blue: 0.102, alpha: 1)  // #0B101A
	static let cardBackground = NSColor(srgbRed: 0.071, green: 0.098, blue: 0.153, alpha: 1)  // #121927
	static let tableBackground = NSColor(srgbRed: 0.055, green: 0.078, blue: 0.125, alpha: 1)  // #0E1420
	static let buttonBackground = NSColor(srgbRed: 0.098, green: 0.133, blue: 0.204, alpha: 1)  // #192234
	static let cardBorder = NSColor.white.withAlphaComponent(0.08)
	static let rowDivider = NSColor.white.withAlphaComponent(0.06)
}
