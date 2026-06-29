import XCTest

@testable import Codogotchi

/// `PlatformAttribution` maps `source_event.origin` strings to the platform logo
/// the animation badge surfaces. Coding platforms get their tool chip, the
/// synthetic combined origin gets the Default chip, and orchestration/
/// bookkeeping origins plus unknown/absent values resolve to `nil` so no chip is drawn.
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

	func testCombinedOriginResolvesToDefaultPlatform() {
		XCTAssertEqual(PlatformAttribution(origin: "combined"), .default)
		XCTAssertEqual(PlatformAttribution(origin: "combined")?.assetName, "PlatformDefault")
		XCTAssertEqual(PlatformAttribution(origin: "combined")?.displayName, "Default")
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
		XCTAssertEqual(PlatformAttribution.default.assetName, "PlatformDefault")
		let defaultAsset = URL(fileURLWithPath: #file)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Assets.xcassets/PlatformDefault.imageset")
		XCTAssertTrue(FileManager.default.fileExists(atPath: defaultAsset.path))
	}

	func testDisplayName() {
		XCTAssertEqual(PlatformAttribution.claudeCode.displayName, "Claude Code")
		XCTAssertEqual(PlatformAttribution.codex.displayName, "Codex")
		XCTAssertEqual(PlatformAttribution.cursor.displayName, "Cursor")
	}
}
