import XCTest

@testable import Codogotchi

/// Focus-target resolution for the attention bubble's Focus button. The terminal
/// bundle id (when the hook ran under a terminal) wins; otherwise IDE-native
/// origins map to their app bundle; everything else is a no-op target.
@MainActor
final class AttentionFocusTargetTests: XCTestCase {
	func testTerminalBundleIdTakesPriorityOverOrigin() {
		let event = SourceEvent(
			origin: "cursor",
			kind: "tool_use",
			name: "Edit",
			terminalBundleId: "com.mitchellh.ghostty"
		)
		XCTAssertEqual(AttentionFocusTarget.bundleId(for: event), "com.mitchellh.ghostty")
	}

	func testIdeNativeOriginsResolveToTheirBundle() {
		let cursor = SourceEvent(origin: "cursor", kind: nil, name: nil)
		let codex = SourceEvent(origin: "codex", kind: nil, name: nil)
		XCTAssertEqual(AttentionFocusTarget.bundleId(for: cursor), "com.todesktop.230313mzl4w4u92")
		XCTAssertEqual(AttentionFocusTarget.bundleId(for: codex), "com.openai.codex")
	}

	func testNonIdeOrAbsentOriginsHaveNoTarget() {
		// claude_code fires under a terminal, so without a terminal id there is no
		// reliable IDE target.
		XCTAssertNil(AttentionFocusTarget.bundleId(for: SourceEvent(origin: "claude_code", kind: nil, name: nil)))
		XCTAssertNil(AttentionFocusTarget.bundleId(for: SourceEvent(origin: "soa", kind: nil, name: nil)))
		XCTAssertNil(AttentionFocusTarget.bundleId(for: nil))
	}
}
