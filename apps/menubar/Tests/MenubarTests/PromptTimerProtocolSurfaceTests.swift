import XCTest

/// P21.03 — production pool-facing protocols expose presentation push only.
final class PromptTimerProtocolSurfaceTests: XCTestCase {
	private var repoRoot: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent() // MenubarTests
			.deletingLastPathComponent() // Tests
			.deletingLastPathComponent() // menubar
			.deletingLastPathComponent() // apps
			.deletingLastPathComponent() // repository root
	}

	func testPoolFacingProtocolsDoNotDeclareApplyPromptTimerStatus() throws {
		let path = repoRoot.appendingPathComponent(
			"apps/menubar/Sources/Windows/FloatingPetController.swift")
		let source = try String(contentsOf: path, encoding: .utf8)

		XCTAssertFalse(
			source.contains("func applyPromptTimerStatus("),
			"FloatingPetWindowControlling / PanelManaging must not declare applyPromptTimerStatus — presentation-only pool surface (P21.03)")
	}
}
