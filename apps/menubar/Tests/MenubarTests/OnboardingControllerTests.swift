import CoreGraphics
import XCTest

@testable import Codogotchi

final class OnboardingControllerTests: XCTestCase {

	// MARK: - needsOnboarding

	func testNeedsOnboardingWhenOnboardingCompletedAtIsNil() {
		let state = FloatingAppState(isFloatingPetVisible: true, frame: .zero)
		let controller = OnboardingController()
		XCTAssertTrue(controller.needsOnboarding(appState: state))
	}

	func testDoesNotNeedOnboardingWhenAlreadyCompleted() {
		let state = FloatingAppState(
			isFloatingPetVisible: true,
			frame: .zero,
			onboardingCompletedAt: "2026-05-28T10:00:00Z"
		)
		let controller = OnboardingController()
		XCTAssertFalse(controller.needsOnboarding(appState: state))
	}

	func testNeedsOnboardingIgnoresLastHookActivityAt() {
		// lastHookActivityAt alone does not satisfy onboarding completion
		let state = FloatingAppState(
			isFloatingPetVisible: true,
			frame: .zero,
			onboardingCompletedAt: nil,
			lastHookActivityAt: "2026-05-28T11:00:00Z"
		)
		let controller = OnboardingController()
		XCTAssertTrue(controller.needsOnboarding(appState: state))
	}

	// MARK: - runHooksInstall

	func testRunHooksInstallInvokesRunnerWithCorrectArgs() {
		var capturedArgs: [String] = []
		let controller = OnboardingController(installRunner: { args in
			capturedArgs = args
			return HookStatusClient.RunResult(exitCode: 0, stdout: "", stderr: "")
		})
		_ = controller.runHooksInstall()
		XCTAssertEqual(capturedArgs, ["codogotchi", "hooks", "install"])
	}

	func testRunHooksInstallReturnsNilOnSuccess() {
		let controller = OnboardingController(installRunner: { _ in
			HookStatusClient.RunResult(exitCode: 0, stdout: "", stderr: "")
		})
		XCTAssertNil(controller.runHooksInstall())
	}

	func testRunHooksInstallReturnsStderrOnFailure() {
		let controller = OnboardingController(installRunner: { _ in
			HookStatusClient.RunResult(exitCode: 1, stdout: "", stderr: "hook write failed: permission denied")
		})
		XCTAssertEqual(controller.runHooksInstall(), "hook write failed: permission denied")
	}

	func testRunHooksInstallReturnsFallbackMessageWhenStderrEmptyOnFailure() {
		let controller = OnboardingController(installRunner: { _ in
			HookStatusClient.RunResult(exitCode: 1, stdout: "", stderr: "")
		})
		let err = controller.runHooksInstall()
		XCTAssertNotNil(err)
		XCTAssertFalse(err!.isEmpty)
	}

	func testRunHooksInstallReturnsFallbackMessageWhenStderrEmptyOnNonZeroExit() {
		let controller = OnboardingController(installRunner: { _ in
			HookStatusClient.RunResult(exitCode: 127, stdout: "", stderr: "")
		})
		let err = controller.runHooksInstall()
		XCTAssertNotNil(err)
		// Fallback must mention the exit code
		XCTAssertTrue(err!.contains("127"))
	}

	// MARK: - isHooksActive

	func testIsHooksActiveReturnsFalseWhenNoHooksFiring() {
		let controller = OnboardingController()
		XCTAssertFalse(controller.isHooksActive(HooksStatusSnapshot.fixtureNotInstalled()))
	}

	func testIsHooksActiveReturnsFalseWhenInstalledButNotFiringRecently() {
		var snap = HooksStatusSnapshot.fixtureNotInstalled()
		snap.codex.installed = true
		snap.codex.firingRecently = false
		let controller = OnboardingController()
		XCTAssertFalse(controller.isHooksActive(snap))
	}

	func testIsHooksActiveReturnsTrueWhenAtLeastOnePlatformFiring() {
		var snap = HooksStatusSnapshot.fixtureNotInstalled()
		snap.claudeCode.installableInPhase = true
		snap.claudeCode.installed = true
		snap.claudeCode.firingRecently = true
		let controller = OnboardingController()
		XCTAssertTrue(controller.isHooksActive(snap))
	}

	func testIsHooksActiveReturnsFalseForPhaseDeferredPlatform() {
		// Cursor is phase-deferred (installableInPhase: false); even if the snapshot
		// marks it installed+firing it must not flip the onboarding CTA to active.
		var snap = HooksStatusSnapshot.fixtureNotInstalled()
		snap.cursor.installed = true
		snap.cursor.firingRecently = true
		let controller = OnboardingController()
		XCTAssertFalse(controller.isHooksActive(snap))
	}

	func testIsHooksActiveReturnsTrueWhenCursorIsPhaseEnabledAndFiring() {
		var snap = HooksStatusSnapshot.fixtureNotInstalled()
		snap.cursor.installableInPhase = true
		snap.cursor.installed = true
		snap.cursor.firingRecently = true
		let controller = OnboardingController()
		XCTAssertTrue(controller.isHooksActive(snap))
	}
}
