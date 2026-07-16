import XCTest

@testable import Codogotchi

/// Pins the `WindowKey` raw-value serialization contract (P16.04): this is the
/// single parse/serialize path for window-key strings persisted to
/// `app-state.json`, encoded into slice filenames, and compared throughout the
/// pool/resolver. The raw-value format must byte-match the pre-existing string
/// convention exactly — a drift here silently corrupts persisted state on
/// upgrade.
final class WindowKeyTests: XCTestCase {

	// MARK: - Round-trip: .origin

	func testOriginRoundTripsThroughRawValue() {
		// [red] a bare origin string (no colon) round-trips as .origin(String)
		let key = WindowKey.origin("claude")
		XCTAssertEqual(key.rawValue, "claude")
		XCTAssertEqual(WindowKey(rawValue: "claude"), .origin("claude"))
	}

	// MARK: - Round-trip: .session

	func testSessionRoundTripsThroughRawValue() {
		// [red] "origin:session_id" round-trips as .session(origin:id:)
		let key = WindowKey.session(origin: "claude", id: "s1")
		XCTAssertEqual(key.rawValue, "claude:s1")
		XCTAssertEqual(WindowKey(rawValue: "claude:s1"), .session(origin: "claude", id: "s1"))
	}

	// MARK: - Round-trip: .combined

	func testCombinedRoundTripsThroughRawValue() {
		// [red] the literal "combined" round-trips as .combined
		XCTAssertEqual(WindowKey.combined.rawValue, "combined")
		XCTAssertEqual(WindowKey(rawValue: "combined"), .combined)
	}

	// MARK: - Exact persisted raw-string forms (byte-compat pin)

	func testExactPersistedRawStringForms() {
		// [red] these are the literal strings the pre-WindowKey code persisted
		// to app-state.json / session-labels.json / gate filenames — the
		// serialization contract this ticket must not drift.
		XCTAssertEqual(WindowKey(rawValue: "combined")?.rawValue, "combined")
		XCTAssertEqual(WindowKey(rawValue: "claude")?.rawValue, "claude")
		XCTAssertEqual(WindowKey(rawValue: "claude:s1")?.rawValue, "claude:s1")
	}

	// MARK: - Origin/session-id extraction sanity (used at policy call sites)

	func testSessionCaseCarriesOriginAndId() {
		guard case .session(let origin, let id) = WindowKey(rawValue: "codex:abc123") else {
			return XCTFail("expected .session case")
		}
		XCTAssertEqual(origin, "codex")
		XCTAssertEqual(id, "abc123")
	}

	// MARK: - Invalid-input rejection

	func testEmptyStringIsRejected() {
		// [red] empty string is not a valid window key
		XCTAssertNil(WindowKey(rawValue: ""))
	}

	func testColonWithEmptyOriginIsRejected() {
		// [red] a session key must have a non-empty origin before the colon
		XCTAssertNil(WindowKey(rawValue: ":s1"))
	}

	func testColonWithEmptySessionIdIsRejected() {
		// [red] a session key must have a non-empty id after the colon
		XCTAssertNil(WindowKey(rawValue: "claude:"))
	}

	func testBareColonIsRejected() {
		// [red] neither side present
		XCTAssertNil(WindowKey(rawValue: ":"))
	}

	// MARK: - Equatable / Hashable sanity (used as dictionary keys throughout the pool)

	func testDistinctCasesAreNotEqual() {
		XCTAssertNotEqual(WindowKey.origin("claude"), WindowKey.combined)
		XCTAssertNotEqual(
			WindowKey.origin("claude"), WindowKey.session(origin: "claude", id: "s1"))
	}

	func testUsableAsDictionaryKey() {
		var dict: [WindowKey: Int] = [:]
		dict[.combined] = 1
		dict[.origin("claude")] = 2
		dict[.session(origin: "claude", id: "s1")] = 3
		XCTAssertEqual(dict[.combined], 1)
		XCTAssertEqual(dict[.origin("claude")], 2)
		XCTAssertEqual(dict[.session(origin: "claude", id: "s1")], 3)
	}
}
