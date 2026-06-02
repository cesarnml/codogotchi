import XCTest

@testable import Codogotchi

/// `PlatformAttribution` maps `source_event.origin` strings to the platform logo
/// the animation badge surfaces. Only the five coding platforms that drive the
/// pet get a chip; orchestration/bookkeeping origins and unknown/absent values
/// resolve to `nil` so no chip is drawn.
final class PlatformAttributionTests: XCTestCase {
	func testCodingPlatformsResolveToTheirLogo() {
		XCTAssertEqual(PlatformAttribution(origin: "claude_code"), .claudeCode)
		XCTAssertEqual(PlatformAttribution(origin: "codex"), .codex)
		XCTAssertEqual(PlatformAttribution(origin: "cursor"), .cursor)
	}

	func testNonPlatformOriginsResolveToNil() {
		XCTAssertNil(PlatformAttribution(origin: "soa"))
		XCTAssertNil(PlatformAttribution(origin: "sync"))
		XCTAssertNil(PlatformAttribution(origin: "manual"))
	}

	func testAbsentOrUnknownOriginResolvesToNil() {
		XCTAssertNil(PlatformAttribution(origin: nil))
		XCTAssertNil(PlatformAttribution(origin: ""))
	}

	// P9.01 — vscode / antigravity platform origins
	func testVSCodeOriginResolvesToVSCodePlatform() {
		XCTAssertEqual(PlatformAttribution(origin: "vscode")?.assetName, "PlatformVSCode")
	}

	func testAntigravityOriginResolvesToAntigravityPlatform() {
		XCTAssertEqual(PlatformAttribution(origin: "antigravity")?.assetName, "PlatformAntigravity")
	}

	func testVSCodeDisplayName() {
		XCTAssertEqual(PlatformAttribution(origin: "vscode")?.displayName, "VS Code")
	}

	func testAntigravityDisplayName() {
		XCTAssertEqual(PlatformAttribution(origin: "antigravity")?.displayName, "Antigravity")
	}

	func testNonPlatformOriginsStillResolveToNilAfterP9() {
		XCTAssertNil(PlatformAttribution(origin: "soa"))
		XCTAssertNil(PlatformAttribution(origin: nil))
	}

	func testAssetNameMatchesImagesetName() {
		XCTAssertEqual(PlatformAttribution.claudeCode.assetName, "PlatformClaudeCode")
		XCTAssertEqual(PlatformAttribution.codex.assetName, "PlatformCodex")
		XCTAssertEqual(PlatformAttribution.cursor.assetName, "PlatformCursor")
	}

	func testDisplayName() {
		XCTAssertEqual(PlatformAttribution.claudeCode.displayName, "Claude Code")
		XCTAssertEqual(PlatformAttribution.codex.displayName, "Codex")
		XCTAssertEqual(PlatformAttribution.cursor.displayName, "Cursor")
	}
}
