import XCTest

@testable import Codogotchi

final class GeneralTabViewModelTests: XCTestCase {

	// MARK: - Helpers

	private func makeSnapshot(
		codexInstalled: Bool = false,
		codexFiring: Bool = false,
		codexDetected: Bool = false,
		codexPartiallyInstalled: Bool = false,
		// Defaults to matching `installed`: a fresh install is registration-current
		// unless a test deliberately simulates drift.
		codexRegistrationCurrent: Bool? = nil
	) -> HooksStatusSnapshot {
		let codex = HooksStatusSnapshot.Platform(
			presentOnDisk: codexInstalled,
			installableInPhase: true,
			detected: codexDetected || codexInstalled,
			installed: codexInstalled,
			partiallyInstalled: codexPartiallyInstalled,
			registrationCurrent: codexRegistrationCurrent ?? codexInstalled,
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

	// MARK: - Detected-but-unhooked banner

	func testShouldShowBannerWhenToolDetectedButNotInstalled() {
		let vm = GeneralTabViewModel(hookVersion: "1.2.0")
		vm.applySnapshot(makeSnapshot(codexInstalled: false, codexDetected: true))
		vm.installedHookVersion = nil
		XCTAssertTrue(vm.hasUnhookedDetectedPlatform)
		XCTAssertTrue(vm.shouldShowUpdateBanner)
		XCTAssertEqual(
			vm.updateBannerMessage,
			"A new coding tool was detected — click Update to install its hooks."
		)
	}

	func testNoDetectedBannerWhenDetectedToolAlreadyInstalled() {
		let vm = GeneralTabViewModel(hookVersion: "1.2.0")
		vm.applySnapshot(makeSnapshot(codexInstalled: true))
		vm.installedHookVersion = "1.2.0"
		XCTAssertFalse(vm.hasUnhookedDetectedPlatform)
		XCTAssertFalse(vm.shouldShowUpdateBanner)
	}

	// MARK: - Registration-drift vs version-drift banner

	/// The core P8.05 fix: a pure binary-version bump (e.g. 1.0.0 -> 1.0.1) whose
	/// registration is byte-identical must NOT surface an Update banner, even
	/// though the version predicate still reports drift.
	func testNoBannerWhenVersionDiffersButRegistrationCurrent() {
		let vm = GeneralTabViewModel(hookVersion: "1.0.1")
		vm.applySnapshot(
			makeSnapshot(codexInstalled: true, codexRegistrationCurrent: true))
		vm.installedHookVersion = "1.0.0"
		XCTAssertTrue(vm.needsBannerUpdate, "version predicate still sees drift")
		XCTAssertFalse(vm.hasStaleRegistration)
		XCTAssertFalse(
			vm.shouldShowUpdateBanner,
			"a version-only bump with unchanged registration must not nag")
	}

	/// True registration drift on a fully-installed platform (e.g. a stale command
	/// path) is actionable regardless of the version string.
	func testBannerWhenRegistrationStaleEvenIfVersionsMatch() {
		let vm = GeneralTabViewModel(hookVersion: "1.0.1")
		vm.applySnapshot(
			makeSnapshot(codexInstalled: true, codexRegistrationCurrent: false))
		vm.installedHookVersion = "1.0.1"
		XCTAssertFalse(vm.needsBannerUpdate)
		XCTAssertTrue(vm.hasStaleRegistration)
		XCTAssertTrue(vm.shouldShowUpdateBanner)
		XCTAssertEqual(
			vm.updateBannerMessage,
			"Hooks are out of date — click Update to re-register them.")
	}

	/// A present-but-partial install (new event slot added since install) reports
	/// registration_current=false and is caught by hasStaleRegistration.
	func testStaleRegistrationCoversPartialInstall() {
		let vm = GeneralTabViewModel(hookVersion: "1.0.1")
		vm.applySnapshot(
			makeSnapshot(
				codexInstalled: false,
				codexPartiallyInstalled: true,
				codexRegistrationCurrent: false))
		vm.installedHookVersion = "1.0.1"
		XCTAssertTrue(vm.hasStaleRegistration)
		XCTAssertTrue(vm.shouldShowUpdateBanner)
	}

	// MARK: - Platform-chip animation toggle

	func testPlatformChipAnimationDefaultsOffAndPersistsThroughStore() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("general-chip-anim-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: tmp) }
		let store = CustomizationStore(filePath: tmp.path)
		let vm = GeneralTabViewModel(store: store)

		XCTAssertFalse(vm.platformChipAnimationEnabled, "toggle must start off on a fresh install")

		XCTAssertTrue(vm.setPlatformChipAnimationEnabled(true))
		XCTAssertTrue(vm.platformChipAnimationEnabled)
		XCTAssertTrue(
			CustomizationJsonReader.read(at: tmp.path).platformChipAnimationEnabled,
			"the on state must survive a relaunch, not just live in memory")

		XCTAssertTrue(vm.setPlatformChipAnimationEnabled(false))
		XCTAssertFalse(vm.platformChipAnimationEnabled)
		XCTAssertFalse(CustomizationJsonReader.read(at: tmp.path).platformChipAnimationEnabled)
	}

	func testPlatformChipAnimationWritePreservesSiblingKeys() throws {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("general-chip-anim-siblings-\(UUID().uuidString).json")
		try #"{"menubar_icon_monochrome": true}"#.write(to: tmp, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let vm = GeneralTabViewModel(store: CustomizationStore(filePath: tmp.path))
		XCTAssertTrue(vm.setPlatformChipAnimationEnabled(true))

		let reread = CustomizationJsonReader.read(at: tmp.path)
		XCTAssertTrue(reread.platformChipAnimationEnabled)
		XCTAssertTrue(reread.menubarIconMonochrome, "the animation write must not clobber sibling keys")
	}

	func testDiagnosticsJSONIsValidJSON() {
		let vm = GeneralTabViewModel(appVersion: "1.0.0", hookVersion: "0.1.0")
		vm.applySnapshot(makeSnapshot())
		let json = vm.diagnosticsJSON()
		let data = json.data(using: .utf8)!
		XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data), "diagnostics JSON must be valid JSON")
	}
}
