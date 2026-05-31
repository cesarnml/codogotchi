import XCTest

@testable import Codogotchi

final class AboutViewModelTests: XCTestCase {

	func testReturnsInjectedAppVersion() {
		let vm = AboutViewModel(
			appVersionSource: { "1.4.2" },
			hookVersionSource: { "9.9.9" }
		)
		XCTAssertEqual(vm.appVersion, "1.4.2")
	}

	func testReturnsInjectedHookVersion() {
		let vm = AboutViewModel(
			appVersionSource: { "1.4.2" },
			hookVersionSource: { "0.3.0" }
		)
		XCTAssertEqual(vm.hookVersion, "0.3.0")
	}

	func testBundledHookVersionParsesRunnerStdout() {
		var capturedArgs: [String] = []
		let version = AboutViewModel.bundledHookVersion(runner: { argv in
			capturedArgs = argv
			return HookStatusClient.RunResult(exitCode: 0, stdout: "0.3.0\n", stderr: "")
		})
		XCTAssertEqual(capturedArgs, ["codogotchi", "--version"])
		XCTAssertEqual(version, "0.3.0")
	}

	func testBundledHookVersionReturnsUnknownOnFailure() {
		let version = AboutViewModel.bundledHookVersion(runner: { _ in
			HookStatusClient.RunResult(exitCode: 1, stdout: "", stderr: "boom")
		})
		XCTAssertEqual(version, "unknown")
	}

	func testBundledHookVersionReturnsUnknownOnEmptyOutput() {
		let version = AboutViewModel.bundledHookVersion(runner: { _ in
			HookStatusClient.RunResult(exitCode: 0, stdout: "   \n", stderr: "")
		})
		XCTAssertEqual(version, "unknown")
	}
}
