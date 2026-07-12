import XCTest

final class SurfaceConvergenceInvariantTests: XCTestCase {
	private var repoRoot: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent() // MenubarTests
			.deletingLastPathComponent() // Tests
			.deletingLastPathComponent() // menubar
			.deletingLastPathComponent() // apps
			.deletingLastPathComponent() // repository root
	}

	private func source(_ relativePath: String) throws -> String {
		try String(
			contentsOf: repoRoot.appendingPathComponent(relativePath),
			encoding: .utf8)
	}

	func testSharedPanelHandlersAreAssignedOnlyInsideWirePanelActions() throws {
		let menubarApp = try source("apps/menubar/Sources/App/MenubarApp.swift")
		let handlerNames = [
			"onAttentionDismissed", "onForceIdle", "onRenameRequested",
			"onSyncLabelRequested", "onPruneRequested", "onHideAllOtherPetsRequested",
			"onModeSwitchRequested", "onOpenSettingsRequested", "onHideWindowRequested",
		]

		guard let methodStart = menubarApp.range(of: "private func wirePanelActions(") else {
			return XCTFail("wirePanelActions must remain the shared panel-action wiring path")
		}
		let methodTail = menubarApp[methodStart.lowerBound...]
		guard let methodEnd = methodTail.range(of: "\n\t}\n\n", range: methodStart.lowerBound..<menubarApp.endIndex) else {
			return XCTFail("could not locate the end of wirePanelActions")
		}
		let method = menubarApp[methodStart.lowerBound..<methodEnd.upperBound]

		for handler in handlerNames {
			let assignment = ".\(handler) ="
			XCTAssertEqual(
				menubarApp.components(separatedBy: assignment).count - 1, 1,
				"\(handler) must have exactly one production assignment")
			XCTAssertTrue(
				method.contains(assignment),
				"\(handler) must be assigned inside wirePanelActions")
		}
	}

	func testRetiredRendererProtocolNamesHaveNoAppOrContractHits() throws {
		let retiredNames = ["FloatingPetPanelManaging", "MinimalistPanelManaging"]
		let roots = [
			repoRoot.appendingPathComponent("apps/menubar/Sources"),
			repoRoot.appendingPathComponent("docs/contracts"),
		]
		let enumerator = FileManager.default.enumerator(
			at: roots[0], includingPropertiesForKeys: nil)
		let appFiles = (enumerator?.allObjects as? [URL] ?? []).filter {
			$0.pathExtension == "swift"
		}
		let contractFiles = try FileManager.default.contentsOfDirectory(
			at: roots[1], includingPropertiesForKeys: nil
		).filter { $0.pathExtension == "md" }

		for file in appFiles + contractFiles {
			let contents = try String(contentsOf: file, encoding: .utf8)
			for retiredName in retiredNames {
				XCTAssertFalse(
					contents.contains(retiredName),
					"retired renderer protocol \(retiredName) found in \(file.path)")
			}
		}
	}
}
