import XCTest

@testable import Codogotchi

/// Covers every reachable state of the update-detection machine:
/// (marker absent | marker without build | marker with build)
/// × (version same | differs) × (build same | differs).
///
/// The build-keyed marker exists because Sparkle compares CFBundleVersion, so a
/// rebuild that keeps the same marketing version is a real update that the
/// version-only marker used to miss entirely.
final class UpdateTelemetryReporterTests: XCTestCase {
	private var tempDir: URL!
	private var markerURL: URL!

	override func setUpWithError() throws {
		tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("update-telemetry-tests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: tempDir, withIntermediateDirectories: true
		)
		markerURL = tempDir.appendingPathComponent("update-telemetry.json")
	}

	override func tearDownWithError() throws {
		try? FileManager.default.removeItem(at: tempDir)
	}

	// MARK: - helpers

	/// Writes a marker by hand so tests can construct legacy (build-less) files
	/// that the current encoder would never produce.
	private func writeMarker(version: String, build: String?) throws {
		var fields = ["\"lastReportedVersion\":\"\(version)\""]
		if let build { fields.append("\"lastReportedBuild\":\"\(build)\"") }
		let json = "{\(fields.joined(separator: ","))}"
		try Data(json.utf8).write(to: markerURL)
	}

	private func readMarker() throws -> (version: String?, build: String?) {
		let data = try Data(contentsOf: markerURL)
		let obj =
			try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
		return (obj["lastReportedVersion"] as? String, obj["lastReportedBuild"] as? String)
	}

	@discardableResult
	private func run(version: String, build: String)
		-> [UpdateTelemetryReporter.Report]
	{
		var reports: [UpdateTelemetryReporter.Report] = []
		UpdateTelemetryReporter.reportIfUpdated(
			currentVersion: version,
			currentBuild: build,
			url: markerURL,
			emit: { reports.append($0) }
		)
		return reports
	}

	// MARK: - fresh install

	func testFreshInstallWritesMarkerAndReportsNothing() throws {
		let reports = run(version: "3.1.0", build: "17")

		XCTAssertTrue(reports.isEmpty, "a first-ever launch is not an update")
		let marker = try readMarker()
		XCTAssertEqual(marker.version, "3.1.0")
		XCTAssertEqual(marker.build, "17")
	}

	// MARK: - legacy marker migration (the phantom-event hazard)

	func testLegacyMarkerSameVersionBackfillsBuildWithoutReporting() throws {
		try writeMarker(version: "3.1.0", build: nil)

		let reports = run(version: "3.1.0", build: "17")

		XCTAssertTrue(
			reports.isEmpty,
			"shipping build tracking must not emit a phantom update for every existing install"
		)
		XCTAssertEqual(try readMarker().build, "17", "the build should be backfilled silently")
	}

	func testLegacyMarkerNewVersionReportsWithNilPreviousBuild() throws {
		try writeMarker(version: "3.0.3", build: nil)

		let reports = run(version: "3.1.0", build: "17")

		XCTAssertEqual(reports.count, 1)
		XCTAssertEqual(reports.first?.previousVersion, "3.0.3")
		XCTAssertNil(reports.first?.previousBuild, "the old marker recorded no build")
		XCTAssertEqual(reports.first?.appBuild, "17")
	}

	// MARK: - steady state

	func testSameVersionAndBuildIsANoOp() throws {
		try writeMarker(version: "3.1.0", build: "17")
		let before = try Data(contentsOf: markerURL)

		let reports = run(version: "3.1.0", build: "17")

		XCTAssertTrue(reports.isEmpty, "re-launching the same build is not an update")
		XCTAssertEqual(try Data(contentsOf: markerURL), before, "marker must not be rewritten")
	}

	func testBuildBumpWithUnchangedVersionReports() throws {
		try writeMarker(version: "3.1.0", build: "17")

		let reports = run(version: "3.1.0", build: "18")

		XCTAssertEqual(
			reports.count, 1,
			"a same-version rebuild is the case the version-only marker used to miss"
		)
		XCTAssertEqual(reports.first?.previousBuild, "17")
		XCTAssertEqual(reports.first?.appBuild, "18")
		XCTAssertEqual(reports.first?.appVersion, "3.1.0")
		XCTAssertEqual(try readMarker().build, "18")
	}

	func testVersionBumpReports() throws {
		try writeMarker(version: "3.1.0", build: "17")

		let reports = run(version: "3.2.0", build: "20")

		XCTAssertEqual(reports.count, 1)
		XCTAssertEqual(reports.first?.previousVersion, "3.1.0")
		XCTAssertEqual(reports.first?.previousBuild, "17")
		XCTAssertEqual(reports.first?.appVersion, "3.2.0")
	}

	func testReportFiresAtMostOncePerBuild() throws {
		try writeMarker(version: "3.1.0", build: "17")

		let first = run(version: "3.1.0", build: "18")
		let second = run(version: "3.1.0", build: "18")

		XCTAssertEqual(first.count, 1)
		XCTAssertTrue(second.isEmpty, "the marker must suppress a repeat on the next launch")
	}

	// MARK: - failure path

	func testUnwritableMarkerSuppressesTheReport() throws {
		try writeMarker(version: "3.1.0", build: "17")
		// A directory where the marker file belongs makes the atomic write fail.
		try FileManager.default.removeItem(at: markerURL)
		try FileManager.default.createDirectory(
			at: markerURL, withIntermediateDirectories: true
		)

		let reports = run(version: "3.2.0", build: "20")

		XCTAssertTrue(
			reports.isEmpty,
			"a failed marker write must suppress the send, or every launch resends"
		)
	}
}
