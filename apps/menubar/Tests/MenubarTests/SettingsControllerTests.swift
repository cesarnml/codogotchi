import XCTest

@testable import Codogotchi

final class SettingsControllerTests: XCTestCase {

	// MARK: - Hook install

	func testRunHooksInstallInvokesRunnerWithCorrectArgs() {
		var captured: [[String]] = []
		let controller = SettingsController(runner: { args in
			captured.append(args)
			return HookStatusClient.RunResult(exitCode: 0, stdout: "", stderr: "")
		})
		_ = controller.runHooksInstall()
		XCTAssertEqual(
			captured,
			[
				["codogotchi", "hooks", "install"],
				["codogotchi", "hooks", "install", "--platform", "cursor"],
			]
		)
	}

	func testRunHooksInstallReturnsNilOnSuccess() {
		let controller = SettingsController(runner: { _ in
			HookStatusClient.RunResult(exitCode: 0, stdout: "", stderr: "")
		})
		XCTAssertNil(controller.runHooksInstall())
	}

	func testRunHooksInstallReturnsErrorMessageOnFailure() {
		let controller = SettingsController(runner: { _ in
			HookStatusClient.RunResult(exitCode: 1, stdout: "", stderr: "permission denied")
		})
		XCTAssertEqual(controller.runHooksInstall(), "permission denied")
	}

	// MARK: - Hook uninstall

	func testRunHooksUninstallInvokesRunnerWithCorrectArgs() {
		var captured: [[String]] = []
		let controller = SettingsController(runner: { args in
			captured.append(args)
			return HookStatusClient.RunResult(exitCode: 0, stdout: "", stderr: "")
		})
		_ = controller.runHooksUninstall()
		XCTAssertEqual(
			captured,
			[
				["codogotchi", "hooks", "uninstall", "--platform", "cursor"],
				["codogotchi", "hooks", "uninstall"],
			]
		)
	}

	func testRunHooksUninstallReturnsNilOnSuccess() {
		let controller = SettingsController(runner: { _ in
			HookStatusClient.RunResult(exitCode: 0, stdout: "", stderr: "")
		})
		XCTAssertNil(controller.runHooksUninstall())
	}

	func testRunHooksUninstallReturnsErrorMessageOnFailure() {
		let controller = SettingsController(runner: { _ in
			HookStatusClient.RunResult(exitCode: 1, stdout: "", stderr: "no hook found")
		})
		XCTAssertEqual(controller.runHooksUninstall(), "no hook found")
	}

	// MARK: - Hook update

	func testRunHooksUpdateInvokesInstallArgs() {
		var captured: [[String]] = []
		let controller = SettingsController(runner: { args in
			captured.append(args)
			return HookStatusClient.RunResult(exitCode: 0, stdout: "", stderr: "")
		})
		_ = controller.runHooksUpdate()
		XCTAssertEqual(captured.count, 2)
		XCTAssertEqual(captured[0], ["codogotchi", "hooks", "install"])
	}

	func testRunHooksUpdateReturnsNilOnSuccess() {
		let controller = SettingsController(runner: { _ in
			HookStatusClient.RunResult(exitCode: 0, stdout: "", stderr: "")
		})
		XCTAssertNil(controller.runHooksUpdate())
	}

	func testRunHooksUpdateReturnsErrorMessageOnFailure() {
		let controller = SettingsController(runner: { _ in
			HookStatusClient.RunResult(exitCode: 1, stdout: "", stderr: "path mismatch")
		})
		XCTAssertEqual(controller.runHooksUpdate(), "path mismatch")
	}

	func testRunHooksUpdateReturnsFallbackErrorWhenStderrEmpty() {
		let controller = SettingsController(runner: { _ in
			HookStatusClient.RunResult(exitCode: 2, stdout: "", stderr: "")
		})
		XCTAssertNotNil(controller.runHooksUpdate())
	}

	// MARK: - RPG config independence

	func testSettingsControllerDoesNotRequireRPGConfig() {
		// Settings window must open without any RPG / Convex config present.
		// A SettingsController created with a no-op runner must not crash or throw.
		let controller = SettingsController(runner: { _ in
			HookStatusClient.RunResult(exitCode: 0, stdout: "", stderr: "")
		})
		// Calling any read-only method must succeed without touching RPG config.
		XCTAssertNil(controller.runHooksInstall())
	}
}
