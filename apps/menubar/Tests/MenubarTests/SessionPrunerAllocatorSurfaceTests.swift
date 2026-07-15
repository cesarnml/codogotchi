import XCTest

/// P21.04 — SessionPruner is disk-only; no throwaway class allocator on the prune path.
final class SessionPrunerAllocatorSurfaceTests: XCTestCase {
	private var repoRoot: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}

	func testSessionPrunerSourceHasNoAllocatorParameter() throws {
		let source = try String(
			contentsOf: repoRoot.appendingPathComponent(
				"apps/menubar/Sources/State/SessionPruner.swift"),
			encoding: .utf8)
		XCTAssertFalse(
			source.contains("allocator"),
			"SessionPruner must be disk-only — no allocator parameter or release (P21.04)")
	}

	func testPoolPrunePathDoesNotConstructSessionNumberAllocator() throws {
		let source = try String(
			contentsOf: repoRoot.appendingPathComponent(
				"apps/menubar/Sources/Pool/FloatingPetWindowPool.swift"),
			encoding: .utf8)
		XCTAssertFalse(
			source.contains("SessionNumberAllocator()"),
			"FloatingPetWindowPool.pruneSession must not construct a throwaway SessionNumberAllocator (P21.04)")
	}

	func testSourcesDoNotContainClassSessionNumberAllocator() throws {
		let sources = repoRoot.appendingPathComponent("apps/menubar/Sources")
		let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
		let files = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
		for file in files {
			let contents = try String(contentsOf: file, encoding: .utf8)
			XCTAssertFalse(
				contents.contains("final class SessionNumberAllocator"),
				"class SessionNumberAllocator must be deleted from Sources (\(file.lastPathComponent))")
			// Allow SessionNumberAllocatorState and docstring mentions of the deleted class name
			// only outside a class definition — construction of the class type must be gone.
			if file.lastPathComponent != "SessionNumberAllocatorState.swift" {
				XCTAssertFalse(
					contents.contains("SessionNumberAllocator("),
					"no SessionNumberAllocator construction in \(file.path)")
			}
		}
	}
}
