import XCTest

@testable import Codogotchi

// [red] CustomizationStore does not yet exist — this file fails to compile
// until the GREEN implementation (P16.06) lands.
final class CustomizationStoreTests: XCTestCase {
	private func makeTmpPath() -> String {
		FileManager.default.temporaryDirectory
			.appendingPathComponent("customization-store-\(UUID().uuidString).json").path
	}

	private func readPayload(at path: String) throws -> [String: Any] {
		let data = try Data(contentsOf: URL(fileURLWithPath: path))
		return try JSONSerialization.jsonObject(with: data) as! [String: Any]
	}

	// MARK: - No-clobber contract

	func testMergePreservesASiblingFieldWrittenMomentsBefore() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let store = CustomizationStore(filePath: path)

		store.merge(["menubar_icon_monochrome": true])
		store.merge(["idle_dismiss_ttl_seconds": 900])

		let payload = try readPayload(at: path)
		XCTAssertEqual(
			payload["menubar_icon_monochrome"] as? Bool, true,
			"a sibling field written moments before must survive a later unrelated write")
		XCTAssertEqual(payload["idle_dismiss_ttl_seconds"] as? Int, 900)
	}

	func testMergePreservesAFieldUnmanagedByAnyCurrentSetter() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		// Simulates a field present in the file that no current store method
		// manages — the no-clobber contract must still preserve it verbatim.
		try """
			{ "schema_version": 1, "some_future_field": "keep-me" }
			""".write(toFile: path, atomically: true, encoding: .utf8)
		let store = CustomizationStore(filePath: path)

		store.merge(["idle_dismiss_ttl_seconds": 60])

		let payload = try readPayload(at: path)
		XCTAssertEqual(payload["some_future_field"] as? String, "keep-me")
	}

	// MARK: - Sequential writes from two different adapters

	func testSequentialWritesFromTwoAdaptersDoNotDropFields() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		// Two different adapters (e.g. CustomizationTabViewModel and a
		// right-click handler) each hold their own store instance pointed at
		// the same file — mirroring two call sites writing through the store.
		let adapterA = CustomizationStore(filePath: path)
		let adapterB = CustomizationStore(filePath: path)

		adapterA.setMode(.minimalist, for: "claude_code")
		adapterB.setCombinedMinimalistEnabled(true)
		adapterA.merge(["idle_dismiss_ttl_seconds": 1800])

		let payload = try readPayload(at: path)
		let modes = payload["platform_modes"] as? [String: String]
		XCTAssertEqual(
			modes?["claude_code"], "minimalist",
			"adapter A's mode write must survive adapter B's subsequent write")
		XCTAssertEqual(
			payload["combined_minimalist_enabled"] as? Bool, true,
			"adapter B's write must survive adapter A's later write")
		XCTAssertEqual(payload["idle_dismiss_ttl_seconds"] as? Int, 1800)
	}

	func testTwoAdaptersSettingDifferentOriginsInPlatformModesDoNotDropEachOther() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		// Regression for a data-loss bug found in subagent review: `setMode`
		// must base its proposed `platform_modes` map on a fresh disk read,
		// not this instance's cached `snapshot`, or a sibling instance's
		// concurrent entry in the SAME aggregate object is silently dropped.
		let adapterA = CustomizationStore(filePath: path)
		let adapterB = CustomizationStore(filePath: path)

		adapterA.setMode(.minimalist, for: "claude_code")
		adapterB.setMode(.combined, for: "cursor")

		let payload = try readPayload(at: path)
		let modes = payload["platform_modes"] as? [String: String]
		XCTAssertEqual(
			modes?["claude_code"], "minimalist",
			"adapter A's platform_modes entry must survive adapter B's later write to the same aggregate object"
		)
		XCTAssertEqual(modes?["cursor"], "combined")
	}

	// MARK: - Change publication

	func testPublicationFiresOnWriteAndDeliversTheMergedSnapshot() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let store = CustomizationStore(filePath: path)
		var received: CustomizationSnapshot?
		var callCount = 0
		_ = store.subscribe { snapshot in
			received = snapshot
			callCount += 1
		}

		store.merge(["idle_dismiss_ttl_seconds": 900])

		XCTAssertEqual(callCount, 1)
		XCTAssertEqual(received?.idleDismissTtlSeconds, 900)
	}

	func testPublicationDeliversTheDomainSetterResult() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let store = CustomizationStore(filePath: path)
		var received: CustomizationSnapshot?
		_ = store.subscribe { snapshot in received = snapshot }

		store.setMode(.minimalist, for: "cursor")

		XCTAssertEqual(received?.platformModes["cursor"], .minimalist)
	}

	func testUnsubscribeStopsFurtherPublication() {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let store = CustomizationStore(filePath: path)
		var callCount = 0
		let token = store.subscribe { _ in callCount += 1 }
		store.unsubscribe(token)

		store.merge(["idle_dismiss_ttl_seconds": 900])

		XCTAssertEqual(callCount, 0)
	}

	func testNotifyFalseSuppressesPublicationButStillPersists() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let store = CustomizationStore(filePath: path)
		var callCount = 0
		_ = store.subscribe { _ in callCount += 1 }

		store.merge(["idle_dismiss_ttl_seconds": 900], notify: false)

		XCTAssertEqual(callCount, 0, "a suppressed-notify write (e.g. mid-drag) must not publish")
		XCTAssertEqual(
			store.snapshot.idleDismissTtlSeconds, 900,
			"the in-memory snapshot must still update even when publication is suppressed")
		let payload = try readPayload(at: path)
		XCTAssertEqual(
			payload["idle_dismiss_ttl_seconds"] as? Int, 900, "but must still persist to disk")
	}

	// MARK: - Reads reflect external file edits

	func testReadsReflectExternalFileEditsAfterReload() throws {
		let path = makeTmpPath()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let store = CustomizationStore(filePath: path)
		XCTAssertEqual(store.snapshot.idleDismissTtlSeconds, 0, "default before any file exists")

		// Simulate bytes written by another process/instance, bypassing this
		// store entirely.
		try """
			{ "idle_dismiss_ttl_seconds": 1800 }
			""".write(toFile: path, atomically: true, encoding: .utf8)

		let reloaded = store.reload()

		XCTAssertEqual(reloaded.idleDismissTtlSeconds, 1800)
		XCTAssertEqual(store.snapshot.idleDismissTtlSeconds, 1800)
	}
}
