import Foundation
import XCTest

@testable import Codogotchi

final class StateJsonWriterTests: XCTestCase {
	private var tmp: URL!

	override func setUp() {
		super.setUp()
		tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("StateJsonWriterTests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
	}

	override func tearDown() {
		try? FileManager.default.removeItem(at: tmp)
		super.tearDown()
	}

	// MARK: - Helpers

	private func makeStateDir() -> URL {
		let dir = tmp.appendingPathComponent("state.d")
		try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private func writeSlice(_ filename: String, in dir: URL, json: [String: Any]) {
		let url = dir.appendingPathComponent(filename)
		let data = try! JSONSerialization.data(withJSONObject: json)
		try! data.write(to: url)
	}

	private func readSlice(_ filename: String, in dir: URL) -> [String: Any]? {
		let url = dir.appendingPathComponent(filename)
		guard let data = try? Data(contentsOf: url),
			let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else { return nil }
		return obj
	}

	// MARK: - Single slice with attention

	func testDismissAttentionClearsAttentionAndSetsIdle() {
		let dir = makeStateDir()
		writeSlice(
			"claude_code:session1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "implementing",
				"attention": ["message": "look at me"],
			])

		StateJsonWriter.dismissAttention(at: dir.path)

		let result = readSlice("claude_code:session1.json", in: dir)!
		XCTAssertEqual(result["activity_state"] as? String, "idle")
		XCTAssertNil(result["attention"], "attention must be removed after dismissAttention")
	}

	// MARK: - Multiple slices

	func testDismissAttentionPatchesAllSlices() {
		let dir = makeStateDir()
		for i in 1...3 {
			writeSlice(
				"claude_code:session\(i).json", in: dir,
				json: [
					"schema_version": 6,
					"activity_state": "red_tdd",
					"attention": ["message": "notice \(i)"],
				])
		}

		StateJsonWriter.dismissAttention(at: dir.path)

		for i in 1...3 {
			let result = readSlice("claude_code:session\(i).json", in: dir)!
			XCTAssertEqual(
				result["activity_state"] as? String, "idle",
				"slice \(i) must have activity_state=idle")
			XCTAssertNil(result["attention"], "slice \(i) must have attention removed")
		}
	}

	// MARK: - Missing directory

	func testDismissAttentionNoOpsWhenDirectoryAbsent() {
		let missing = tmp.appendingPathComponent("state.d").path
		// Must not crash
		StateJsonWriter.dismissAttention(at: missing)
	}

	// MARK: - Non-.json files are skipped

	func testDismissAttentionSkipsNonJsonFiles() {
		let dir = makeStateDir()
		// A .tmp partial file that should be ignored
		let tmpFile = dir.appendingPathComponent(".tmp-partial")
		try! Data("{\"activity_state\":\"implementing\",\"attention\":{}}".utf8).write(to: tmpFile)
		// A subdirectory that should be skipped
		let subdir = dir.appendingPathComponent("subdir.json")
		try! FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

		// Must not crash and must not touch the .tmp file
		StateJsonWriter.dismissAttention(at: dir.path)

		// The .tmp file should be unchanged (still has attention key)
		let raw = try! String(contentsOf: tmpFile, encoding: .utf8)
		XCTAssertTrue(raw.contains("attention"), ".tmp file must not be modified by dismissAttention")
	}

	// MARK: - Slice without attention field

	func testDismissAttentionSetsIdleEvenWhenAttentionAbsent() {
		let dir = makeStateDir()
		writeSlice(
			"cursor:session1.json", in: dir,
			json: [
				"schema_version": 6,
				"activity_state": "implementing",
			])

		StateJsonWriter.dismissAttention(at: dir.path)

		let result = readSlice("cursor:session1.json", in: dir)!
		XCTAssertEqual(result["activity_state"] as? String, "idle",
			"activity_state must be set to idle even when attention key was absent")
		XCTAssertNil(result["attention"])
	}
}
