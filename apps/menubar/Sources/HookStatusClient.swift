import Foundation

/// Thin wrapper around `codogotchi hooks status --json`. The subprocess path is
/// pluggable via the `runner` closure so tests can drive it with canned output
/// without spawning a real CLI binary.
struct HookStatusClient {
	struct RunResult {
		let exitCode: Int32
		let stdout: String
		let stderr: String
	}

	enum Failure: Error, Equatable {
		case commandFailed(exitCode: Int32, stderr: String)
		case parseFailed(message: String)
	}

	typealias Runner = (_ argv: [String]) -> RunResult

	let runner: Runner

	init(runner: @escaping Runner = HookStatusClient.defaultRunner) {
		self.runner = runner
	}

	/// Synchronously run the CLI status command and parse its JSON output.
	/// Throws `Failure.commandFailed` on non-zero exit or `Failure.parseFailed`
	/// when stdout is not a decodable `HooksStatusSnapshot`.
	func fetch() throws -> HooksStatusSnapshot {
		let result = runner(["codogotchi", "hooks", "status", "--json"])
		guard result.exitCode == 0 else {
			throw Failure.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
		}

		guard let data = result.stdout.data(using: .utf8) else {
			throw Failure.parseFailed(message: "stdout not utf8")
		}

		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		do {
			return try decoder.decode(HooksStatusSnapshot.self, from: data)
		} catch {
			throw Failure.parseFailed(message: String(describing: error))
		}
	}

	/// Resolve the executable + arguments for an `argv` invocation, preferring
	/// the `codogotchi` binary embedded in the app bundle's `Resources/` over a
	/// PATH lookup. When the bundled binary exists it is launched directly (the
	/// `codogotchi` head is consumed by the launch path); otherwise we fall back
	/// to `/usr/bin/env <argv...>` so `bun` dev builds still resolve via PATH.
	/// `resourceURL` / `fileExists` are injectable for testing.
	static func resolveRunnerLaunch(
		argv: [String],
		resourceURL: URL? = Bundle.main.resourceURL,
		fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
	) -> (launchPath: String, arguments: [String]) {
		guard let head = argv.first else {
			return (launchPath: "/usr/bin/env", arguments: [])
		}
		let rest = Array(argv.dropFirst())
		if let resourceURL {
			let bundled = resourceURL.appendingPathComponent(head)
			if fileExists(bundled.path) {
				return (launchPath: bundled.path, arguments: rest)
			}
		}
		return (launchPath: "/usr/bin/env", arguments: argv)
	}

	/// Default runner used in app code: launches the bundled `codogotchi` binary
	/// when present (no PATH dependency for the shipped `.app`), else spawns
	/// `/usr/bin/env <argv...>` so dev builds resolve through PATH.
	static func defaultRunner(_ argv: [String]) -> RunResult {
		guard argv.first != nil else {
			return RunResult(exitCode: 127, stdout: "", stderr: "empty argv")
		}
		let launch = resolveRunnerLaunch(argv: argv)
		let process = Process()
		process.launchPath = launch.launchPath
		process.arguments = launch.arguments

		let stdoutPipe = Pipe()
		let stderrPipe = Pipe()
		process.standardOutput = stdoutPipe
		process.standardError = stderrPipe

		do {
			try process.run()
		} catch {
			return RunResult(exitCode: 127, stdout: "", stderr: String(describing: error))
		}
		process.waitUntilExit()

		let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
		let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
		return RunResult(
			exitCode: process.terminationStatus,
			stdout: String(data: outData, encoding: .utf8) ?? "",
			stderr: String(data: errData, encoding: .utf8) ?? ""
		)
	}
}
