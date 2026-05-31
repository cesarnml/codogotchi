import XCTest

@testable import Codogotchi

final class LockstepPolicyTests: XCTestCase {

	func testNeedsUpdateWhenInstalledAndVersionsDiffer() {
		XCTAssertTrue(
			LockstepPolicy.needsUpdate(
				hooksInstalled: true,
				bundledVersion: "1.2.0",
				installedVersion: "1.1.0"
			)
		)
	}

	func testNoUpdateNeededWhenVersionsMatch() {
		XCTAssertFalse(
			LockstepPolicy.needsUpdate(
				hooksInstalled: true,
				bundledVersion: "1.2.0",
				installedVersion: "1.2.0"
			)
		)
	}

	func testNoUpdateNeededWhenNotInstalled() {
		XCTAssertFalse(
			LockstepPolicy.needsUpdate(
				hooksInstalled: false,
				bundledVersion: "1.2.0",
				installedVersion: nil
			)
		)
	}

	func testNoUpdateNeededWhenNotInstalledEvenWithRecordedVersion() {
		XCTAssertFalse(
			LockstepPolicy.needsUpdate(
				hooksInstalled: false,
				bundledVersion: "1.2.0",
				installedVersion: "1.0.0"
			)
		)
	}

	func testNeedsUpdateWhenInstalledAndRecordedVersionIsNil() {
		XCTAssertTrue(
			LockstepPolicy.needsUpdate(
				hooksInstalled: true,
				bundledVersion: "1.2.0",
				installedVersion: nil
			)
		)
	}

	func testNeedsUpdateReturnsFalseWhenBundledVersionUnknown() {
		XCTAssertFalse(
			LockstepPolicy.needsUpdate(
				hooksInstalled: true,
				bundledVersion: "unknown",
				installedVersion: "1.2.0"
			)
		)
	}

	func testNeedsUpdateReturnsFalseWhenBothVersionsUnknown() {
		XCTAssertFalse(
			LockstepPolicy.needsUpdate(
				hooksInstalled: true,
				bundledVersion: "unknown",
				installedVersion: nil
			)
		)
	}
}
