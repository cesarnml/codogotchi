import XCTest

@testable import Codogotchi

/// CI-run purity gate (P18.01 outcome): nothing under `Pool/Derive/` may
/// import AppKit. `derive` must stay callable off the main thread / outside
/// a running app, and an AppKit import is the cheapest tripwire for a
/// contributor accidentally reaching for a UIKit-adjacent convenience type.
///
/// Verified by manually inserting `import AppKit` into a scratch file under
/// `Pool/Derive/` and confirming this test fails, then removing it — see the
/// ticket Rationale for the P18.01 red-phase note.
final class PoolDerivePurityGateTests: XCTestCase {
	private var deriveDirectory: URL {
		// This file lives at .../Tests/MenubarTests/Derive/PoolDerivePurityGateTests.swift.
		// Sources/Pool/Derive is a sibling of Tests three levels up.
		URL(fileURLWithPath: #file)
			.deletingLastPathComponent()  // Derive/
			.deletingLastPathComponent()  // MenubarTests/
			.deletingLastPathComponent()  // Tests/
			.deletingLastPathComponent()  // apps/menubar/
			.appendingPathComponent("Sources/Pool/Derive")
	}

	/// Matches every Swift import-declaration form that names the `AppKit`
	/// module: a plain `import AppKit`, an attributed form (`@_exported
	/// import AppKit`, `@testable import AppKit`), and a declaration-specific
	/// import (`import class AppKit.NSWindow`). Anchored so a substring like
	/// `AppKitAdjacentThing` never false-positives.
	private static let appKitImportPattern = try! NSRegularExpression(
		pattern:
			#"^\s*(?:@\w+\s+)*import\s+(?:(?:class|struct|enum|protocol|func|var|let|typealias)\s+)?AppKit(?:\.\w+)?\s*$"#
	)

	func testNoAppKitImportUnderPoolDerive() throws {
		let fm = FileManager.default
		let files = try fm.contentsOfDirectory(
			at: deriveDirectory, includingPropertiesForKeys: nil
		).filter { $0.pathExtension == "swift" }
		XCTAssertFalse(files.isEmpty, "expected at least one source file under \(deriveDirectory.path)")

		for file in files {
			let contents = try String(contentsOf: file, encoding: .utf8)
			for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
				let range = NSRange(line.startIndex..<line.endIndex, in: line)
				let hasAppKitImport =
					Self.appKitImportPattern.firstMatch(in: String(line), range: range) != nil
				XCTAssertFalse(
					hasAppKitImport,
					"\(file.lastPathComponent) must not import AppKit: \"\(line)\"")
			}
		}
	}
}
