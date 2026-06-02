import Foundation
import XCTest

@testable import Codogotchi

final class AppBootstrapTests: XCTestCase {
	private func withTempHome(_ body: (URL) throws -> Void) rethrows {
		let tmp = FileManager.default.temporaryDirectory
			.appendingPathComponent("app-bootstrap-test-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }

		let prev = ProcessInfo.processInfo.environment["CODOGOTCHI_HOME"] as String?
		setenv("CODOGOTCHI_HOME", tmp.path, 1)
		defer {
			if let prev { setenv("CODOGOTCHI_HOME", prev, 1) } else { unsetenv("CODOGOTCHI_HOME") }
		}

		try body(tmp)
	}

	// MARK: - ConfigBootstrap

	func testEnsureLiteConfigWritesMinimalConfigWhenMissing() throws {
		try withTempHome { dir in
			let outcome = try ConfigBootstrap.ensureLiteConfig()
			XCTAssertEqual(outcome, .wrote)

			let configPath = dir.appendingPathComponent("config.json")
			XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))

			let data = try Data(contentsOf: configPath)
			let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

			XCTAssertEqual(obj["pet"] as? String, "maew")
			let profileId = try XCTUnwrap(obj["profile_id"] as? String)
			XCTAssertFalse(profileId.isEmpty)
			let features = try XCTUnwrap(obj["features"] as? [String: Any])
			XCTAssertEqual(features["rpg_enabled"] as? Bool, false)

			// Minimal Lite: no RPG fields outside features.rpg_enabled.
			XCTAssertNil(obj["handle"])
			XCTAssertNil(obj["convex_url"])
		}
	}

	func testEnsureLiteConfigDoesNotOverwriteExistingConfig() throws {
		try withTempHome { dir in
			let configPath = dir.appendingPathComponent("config.json")
			let original = #"{ "profile_id": "preexisting", "pet": "mali", "features": { "rpg_enabled": true } }"#
			try original.write(to: configPath, atomically: true, encoding: .utf8)

			let outcome = try ConfigBootstrap.ensureLiteConfig()
			XCTAssertEqual(outcome, .alreadyExists)

			let after = try String(contentsOf: configPath, encoding: .utf8)
			XCTAssertEqual(after, original)
		}
	}

	// MARK: - HookStatusClient

	func testHookStatusClientParsesValidJsonFromInjectedRunner() throws {
		let json = #"""
		{
		  "codex": { "present_on_disk": true, "installable_in_phase": true, "installed": true, "firing_recently": false, "last_event_at": null },
		  "claude_code": { "present_on_disk": true, "installable_in_phase": true, "installed": true, "firing_recently": true, "last_event_at": "2026-05-28T12:00:00Z" },
		  "cursor": { "present_on_disk": true, "installable_in_phase": true, "installed": false, "firing_recently": false, "last_event_at": null },
		  "vscode": { "present_on_disk": false, "installable_in_phase": false, "installed": false, "firing_recently": false, "last_event_at": null },
		  "antigravity": { "present_on_disk": false, "installable_in_phase": false, "installed": false, "firing_recently": false, "last_event_at": null }
		}
		"""#

		let client = HookStatusClient(runner: { _ in
			HookStatusClient.RunResult(exitCode: 0, stdout: json, stderr: "")
		})

		let snapshot = try client.fetch()
		XCTAssertTrue(snapshot.codex.installed)
		XCTAssertTrue(snapshot.claudeCode.firingRecently)
		XCTAssertEqual(snapshot.claudeCode.lastEventAt, "2026-05-28T12:00:00Z")
		XCTAssertTrue(snapshot.cursor.installableInPhase)
		XCTAssertFalse(snapshot.vscode.installableInPhase)
		XCTAssertFalse(snapshot.antigravity.installableInPhase)
	}

	func testHookStatusClientThrowsOnNonZeroExit() {
		let client = HookStatusClient(runner: { _ in
			HookStatusClient.RunResult(exitCode: 2, stdout: "", stderr: "boom")
		})

		XCTAssertThrowsError(try client.fetch()) { err in
			guard case HookStatusClient.Failure.commandFailed(let code, let stderr) = err else {
				return XCTFail("expected .commandFailed, got \(err)")
			}
			XCTAssertEqual(code, 2)
			XCTAssertEqual(stderr, "boom")
		}
	}

	func testHookStatusClientThrowsOnMalformedJson() {
		let client = HookStatusClient(runner: { _ in
			HookStatusClient.RunResult(exitCode: 0, stdout: "{ not json", stderr: "")
		})

		XCTAssertThrowsError(try client.fetch()) { err in
			guard case HookStatusClient.Failure.parseFailed = err else {
				return XCTFail("expected .parseFailed, got \(err)")
			}
		}
	}

	// MARK: - bundled runner resolution (P8.02)

	func testResolveRunnerLaunchPrefersBundledBinaryWhenPresent() {
		let resources = URL(fileURLWithPath: "/Apps/Codogotchi.app/Contents/Resources")
		let launch = HookStatusClient.resolveRunnerLaunch(
			argv: ["codogotchi", "hooks", "status", "--json"],
			resourceURL: resources,
			fileExists: { _ in true }
		)
		XCTAssertEqual(
			launch.launchPath,
			"/Apps/Codogotchi.app/Contents/Resources/codogotchi"
		)
		// The bundled binary is invoked directly, so the "codogotchi" head is dropped.
		XCTAssertEqual(launch.arguments, ["hooks", "status", "--json"])
	}

	func testResolveRunnerLaunchFallsBackToPathWhenBundledAbsent() {
		let resources = URL(fileURLWithPath: "/Apps/Codogotchi.app/Contents/Resources")
		let launch = HookStatusClient.resolveRunnerLaunch(
			argv: ["codogotchi", "hooks", "status", "--json"],
			resourceURL: resources,
			fileExists: { _ in false }
		)
		XCTAssertEqual(launch.launchPath, "/usr/bin/env")
		XCTAssertEqual(launch.arguments, ["codogotchi", "hooks", "status", "--json"])
	}

	func testResolveRunnerLaunchFallsBackToPathWhenNoResourceURL() {
		let launch = HookStatusClient.resolveRunnerLaunch(
			argv: ["codogotchi", "hooks", "status", "--json"],
			resourceURL: nil,
			fileExists: { _ in true }
		)
		XCTAssertEqual(launch.launchPath, "/usr/bin/env")
		XCTAssertEqual(launch.arguments, ["codogotchi", "hooks", "status", "--json"])
	}

	// MARK: - hooks-not-active predicate

	func testHooksNotActiveTrueWhenNeitherPlatformInstalled() {
		let snap = HooksStatusSnapshot.fixtureNotInstalled()
		XCTAssertTrue(snap.isHooksNotActive())
	}

	func testHooksNotActiveFalseWhenInstalledButNotFiringRecently() {
		// Installation alone is the health signal — a correctly-installed hook
		// that simply hasn't fired yet must NOT surface the "Retry install" CTA.
		var snap = HooksStatusSnapshot.fixtureNotInstalled()
		snap.codex.installableInPhase = true
		snap.codex.installed = true
		snap.codex.firingRecently = false
		XCTAssertFalse(snap.isHooksNotActive())
	}

	func testHooksNotActiveTrueWhenInstallableButNotInstalled() {
		var snap = HooksStatusSnapshot.fixtureNotInstalled()
		snap.codex.installableInPhase = true
		snap.codex.installed = false
		XCTAssertTrue(snap.isHooksNotActive())
	}

	func testHooksNotActiveFalseWhenInstalledAndFiringRecently() {
		var snap = HooksStatusSnapshot.fixtureNotInstalled()
		snap.claudeCode.installableInPhase = true
		snap.claudeCode.installed = true
		snap.claudeCode.firingRecently = true
		XCTAssertFalse(snap.isHooksNotActive())
	}

	func testHooksNotActiveIgnoresPhaseDeferred() {
		// A phase-deferred platform (installableInPhase: false) must not suppress
		// the onboarding CTA even when the CLI snapshot marks it installed+firing.
		var snap = HooksStatusSnapshot.fixtureNotInstalled()
		snap.cursor.installed = true
		snap.cursor.firingRecently = true
		XCTAssertTrue(snap.isHooksNotActive())
	}
}
