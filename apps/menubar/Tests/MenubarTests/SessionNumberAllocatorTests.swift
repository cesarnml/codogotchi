import Foundation
import XCTest

@testable import Codogotchi

final class SessionNumberAllocatorTests: XCTestCase {

	// MARK: - Sequential assignment

	func testThreeSessionsGetSequentialNumbers() {
		let allocator = SessionNumberAllocator()

		let first = allocator.assign(origin: "claude_code", sessionId: "s1")
		let second = allocator.assign(origin: "claude_code", sessionId: "s2")
		let third = allocator.assign(origin: "claude_code", sessionId: "s3")

		XCTAssertEqual(first, 1)
		XCTAssertEqual(second, 2)
		XCTAssertEqual(third, 3)
	}

	// MARK: - Free-list reuse

	func testFreeingThenAddingReusesLowestFreeNumber() {
		let allocator = SessionNumberAllocator()

		_ = allocator.assign(origin: "claude_code", sessionId: "s1")
		_ = allocator.assign(origin: "claude_code", sessionId: "s2")
		_ = allocator.assign(origin: "claude_code", sessionId: "s3")

		allocator.release(origin: "claude_code", sessionId: "s2")

		let fourthSession = allocator.assign(origin: "claude_code", sessionId: "s4")

		XCTAssertEqual(fourthSession, 2, "the lowest free number (2) must be reused, not the next monotonic number (4)")
	}

	// MARK: - Never renumber a live session

	func testFreeingDoesNotRenumberOtherLiveSessions() {
		let allocator = SessionNumberAllocator()

		_ = allocator.assign(origin: "claude_code", sessionId: "s1")
		_ = allocator.assign(origin: "claude_code", sessionId: "s2")
		_ = allocator.assign(origin: "claude_code", sessionId: "s3")

		allocator.release(origin: "claude_code", sessionId: "s2")

		// Re-querying the still-live sessions must return their original numbers.
		XCTAssertEqual(allocator.assign(origin: "claude_code", sessionId: "s1"), 1)
		XCTAssertEqual(allocator.assign(origin: "claude_code", sessionId: "s3"), 3)
	}

	// MARK: - Unlimited never reuses

	func testUnlimitedCapNeverReusesFreedNumbers() {
		let allocator = SessionNumberAllocator()
		allocator.setUnlimited(true, origin: "claude_code")

		_ = allocator.assign(origin: "claude_code", sessionId: "s1")
		_ = allocator.assign(origin: "claude_code", sessionId: "s2")
		_ = allocator.assign(origin: "claude_code", sessionId: "s3")

		allocator.release(origin: "claude_code", sessionId: "s2")

		let fourthSession = allocator.assign(origin: "claude_code", sessionId: "s4")

		XCTAssertEqual(fourthSession, 4, "Unlimited numbering must stay monotonic — a freed number is never reclaimed")
	}

	// MARK: - Per-platform independence

	func testNumberingIsPerPlatform() {
		let allocator = SessionNumberAllocator()

		let claudeFirst = allocator.assign(origin: "claude_code", sessionId: "s1")
		let cursorFirst = allocator.assign(origin: "cursor", sessionId: "s1")

		XCTAssertEqual(claudeFirst, 1)
		XCTAssertEqual(cursorFirst, 1, "each origin's numbering starts at 1 independently")
	}
}
