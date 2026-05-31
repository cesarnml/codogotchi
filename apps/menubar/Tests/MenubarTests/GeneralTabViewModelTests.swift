import XCTest

@testable import Codogotchi

final class GeneralTabViewModelTests: XCTestCase {

	// MARK: - Helpers

	private func makeSnapshot(
		codexInstalled: Bool = false,
		codexFiring: Bool = false
	) -> HooksStatusSnapshot {
		let codex = HooksStatusSnapshot.Platform(
			presentOnDisk: codexInstalled,
			installableInPhase: true,
			installed: codexInstalled,
			firingRecently: codexFiring,
			lastEventAt: codexFiring ? "2026-05-31T12:00:00Z" : nil,
			sourceOrigin: nil
		)
		let off = HooksStatusSnapshot.Platform(
			presentOnDisk: false,
			installableInPhase: false,
			installed: false,
			firingRecently: false,
			lastEventAt: nil,
			sourceOrigin: nil
		)
		return HooksStatusSnapshot(
			codex: codex,
			claudeCode: off,
			cursor: off,
			vscode: off,
			antigravity: off
		)
	}

	// MARK: - Row mapping

	func testApplySnapshotProducesFivePlatformRows() {
		let vm = GeneralTabViewModel()
		vm.applySnapshot(makeSnapshot())
		XCTAssertEqual(vm.rows.count, 5)
	}

	func testFirstRowIsCodex() {
		let vm = GeneralTabViewModel()
		vm.applySnapshot(makeSnapshot())
		XCTAssertEqual(vm.rows.first?.name, "Codex")
	}

	func testInstalledFlagReflectsSnapshot() {
		let vm = GeneralTabViewModel()
		vm.applySnapshot(makeSnapshot(codexInstalled: true))
		XCTAssertTrue(vm.rows.first!.installed)
	}

	func testNotInstalledFlagReflectsSnapshot() {
		let vm = GeneralTabViewModel()
		vm.applySnapshot(makeSnapshot(codexInstalled: false))
		XCTAssertFalse(vm.rows.first!.installed)
	}

	// MARK: - Refresh after action

	func testRefreshCallsStatusClient() {
		let snapshot = makeSnapshot(codexInstalled: true, codexFiring: true)
		var callCount = 0
		let client = HookStatusClient(runner: { _ in
			callCount += 1
			let encoder = JSONEncoder()
			encoder.keyEncodingStrategy = .convertToSnakeCase
			let data = try! encoder.encode(snapshot)
			return HookStatusClient.RunResult(
				exitCode: 0,
				stdout: String(data: data, encoding: .utf8)!,
				stderr: ""
			)
		})
		let vm = GeneralTabViewModel(statusClient: client)
		vm.refresh()
		XCTAssertGreaterThan(callCount, 0)
	}

	func testRefreshUpdatesRowsFromFetchedSnapshot() {
		let snapshot = makeSnapshot(codexInstalled: true, codexFiring: true)
		let client = HookStatusClient(runner: { _ in
			let encoder = JSONEncoder()
			encoder.keyEncodingStrategy = .convertToSnakeCase
			let data = try! encoder.encode(snapshot)
			return HookStatusClient.RunResult(
				exitCode: 0,
				stdout: String(data: data, encoding: .utf8)!,
				stderr: ""
			)
		})
		let vm = GeneralTabViewModel(statusClient: client)
		vm.refresh()
		XCTAssertEqual(vm.rows.first?.installed, true)
	}

	// MARK: - Diagnostics JSON

	func testDiagnosticsJSONContainsAppVersion() {
		let vm = GeneralTabViewModel(appVersion: "2.0.0", hookVersion: "0.5.0")
		vm.applySnapshot(makeSnapshot())
		let json = vm.diagnosticsJSON()
		XCTAssertTrue(json.contains("2.0.0"), "diagnostics JSON must contain app version")
	}

	func testDiagnosticsJSONContainsHookVersion() {
		let vm = GeneralTabViewModel(appVersion: "2.0.0", hookVersion: "0.5.0")
		vm.applySnapshot(makeSnapshot())
		let json = vm.diagnosticsJSON()
		XCTAssertTrue(json.contains("0.5.0"), "diagnostics JSON must contain hook version")
	}

	func testDiagnosticsJSONContainsStatusKeys() {
		let vm = GeneralTabViewModel()
		vm.applySnapshot(makeSnapshot(codexInstalled: true))
		let json = vm.diagnosticsJSON()
		XCTAssertTrue(json.contains("codex"), "diagnostics JSON must contain platform key 'codex'")
		XCTAssertTrue(json.contains("installed"), "diagnostics JSON must contain 'installed' field")
	}

	// MARK: - needsBannerUpdate

	func testNeedsBannerUpdateWhenInstalledVersionDiffers() {
		let vm = GeneralTabViewModel(hookVersion: "1.2.0")
		vm.applySnapshot(makeSnapshot(codexInstalled: true))
		vm.installedHookVersion = "1.1.0"
		XCTAssertTrue(vm.needsBannerUpdate)
	}

	func testNoBannerUpdateWhenVersionsMatch() {
		let vm = GeneralTabViewModel(hookVersion: "1.2.0")
		vm.applySnapshot(makeSnapshot(codexInstalled: true))
		vm.installedHookVersion = "1.2.0"
		XCTAssertFalse(vm.needsBannerUpdate)
	}

	func testNoBannerUpdateWhenNoHooksInstalled() {
		let vm = GeneralTabViewModel(hookVersion: "1.2.0")
		vm.applySnapshot(makeSnapshot(codexInstalled: false))
		vm.installedHookVersion = nil
		XCTAssertFalse(vm.needsBannerUpdate)
	}

	func testNeedsBannerUpdateWhenInstalledAndNoRecordedVersion() {
		let vm = GeneralTabViewModel(hookVersion: "1.2.0")
		vm.applySnapshot(makeSnapshot(codexInstalled: true))
		vm.installedHookVersion = nil
		XCTAssertTrue(vm.needsBannerUpdate)
	}

	func testNeedsBannerUpdateReturnsFalseWhenBundledVersionUnknown() {
		let vm = GeneralTabViewModel(hookVersion: "unknown")
		vm.applySnapshot(makeSnapshot(codexInstalled: true))
		vm.installedHookVersion = nil
		XCTAssertFalse(vm.needsBannerUpdate)
	}

	func testDiagnosticsJSONIsValidJSON() {
		let vm = GeneralTabViewModel(appVersion: "1.0.0", hookVersion: "0.1.0")
		vm.applySnapshot(makeSnapshot())
		let json = vm.diagnosticsJSON()
		let data = json.data(using: .utf8)!
		XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data), "diagnostics JSON must be valid JSON")
	}
}
