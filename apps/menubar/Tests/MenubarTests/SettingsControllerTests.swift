import XCTest

@testable import Codogotchi

final class SettingsControllerTests: XCTestCase {

	// MARK: - Hook install

	func testRunHooksInstallInvokesRunnerWithCorrectArgs() {
		var capturedArgs: [String] = []
		let controller = SettingsController(runner: { args in
			capturedArgs = args
			return HookStatusClient.RunResult(exitCode: 0, stdout: "", stderr: "")
		})
		_ = controller.runHooksInstall()
		XCTAssertEqual(capturedArgs, ["codogotchi", "hooks", "install"])
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
		var capturedArgs: [String] = []
		let controller = SettingsController(runner: { args in
			capturedArgs = args
			return HookStatusClient.RunResult(exitCode: 0, stdout: "", stderr: "")
		})
		_ = controller.runHooksUninstall()
		XCTAssertEqual(capturedArgs, ["codogotchi", "hooks", "uninstall"])
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
