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

	/// Default runner used in app code: spawns `/usr/bin/env <argv...>` so the
	/// CLI is resolved through PATH (consistent with Phase 05 Q1 decision).
	static func defaultRunner(_ argv: [String]) -> RunResult {
		guard let head = argv.first else {
			return RunResult(exitCode: 127, stdout: "", stderr: "empty argv")
		}
		let process = Process()
		process.launchPath = "/usr/bin/env"
		process.arguments = [head] + Array(argv.dropFirst())

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
