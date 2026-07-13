import Foundation

/// Log-only sink for shadow-compare divergences (Grill-Me decision 4):
/// `NSLog` plus a bounded on-disk log at
/// `~/.codogotchi/logs/shadow-divergence.log`. Never throws, never fatal — a
/// divergence here is diagnostic signal for the pre-cutover soak, not a
/// crash; `FloatingPetWindowPoolTests`/soak assertions on `assert()`
/// (compiled out in Release, active in Debug/test builds) are the loud
/// signal, this is the quiet one.
///
/// Each line carries `DivergenceRecord.tickFingerprint` — a replayable
/// tick-input fingerprint (see `ShadowTickFingerprint`) — plus the exact
/// field-level mismatch, so a real divergence found during the soak can be
/// turned into a regression test straight from the log line (Review Focus:
/// "are they actually replayable?").
///
/// Log hygiene (Review Focus): bounded file growth via a hard size-based
/// rotation, and no sensitive content — `sessionLabel`/`sessionTooltip`
/// divergence values can carry a renamed session title or a submitted
/// prompt's summary text, so their logged value is redacted to a
/// presence/length indicator rather than the raw string. The in-memory
/// `DivergenceRecord` itself (consumed by tests and any future regression
/// fixtures) is untouched — only this disk/NSLog sink redacts.
enum ShadowDivergenceLogger {
	/// Rotate the log once it exceeds this size, so a persistently-diverging
	/// tick cannot grow the file unbounded over a long dogfood session.
	static let maxBytes = 1_000_000

	/// Field paths whose `oldValue`/`newValue` may carry user-authored or
	/// platform-derived free text (a rename, a resolved thread title, a
	/// submitted-prompt summary) rather than a bounded enum/identifier —
	/// redacted before writing to disk or NSLog.
	private static let sensitiveFieldPaths: Set<String> = ["sessionLabel", "sessionTooltip"]

	static func log(_ divergences: [DivergenceRecord], fileManager: FileManager = .default) {
		guard !divergences.isEmpty else { return }
		for divergence in divergences {
			NSLog(
				"[ShadowDivergence] tick=%@ key=%@ field=%@ old=%@ new=%@",
				divergence.tickFingerprint, divergence.windowKey.rawValue, divergence.fieldPath,
				redacted(divergence.fieldPath, divergence.oldValue),
				redacted(divergence.fieldPath, divergence.newValue))
		}
		appendToDisk(divergences, fileManager: fileManager)
	}

	private static func redacted(_ fieldPath: String, _ value: String) -> String {
		guard sensitiveFieldPaths.contains(fieldPath) else { return value }
		return value == "nil" ? "nil" : "<redacted:\(value.count)ch>"
	}

	private static func appendToDisk(_ divergences: [DivergenceRecord], fileManager: FileManager) {
		let url = CodogotchiFolders.dataFolderURL()
			.appendingPathComponent("logs", isDirectory: true)
			.appendingPathComponent("shadow-divergence.log")
		let directory = url.deletingLastPathComponent()
		try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

		if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
			let size = attributes[.size] as? Int,
			size > maxBytes
		{
			try? fileManager.removeItem(at: url)
		}

		let timestamp = ISO8601DateFormatter().string(from: Date())
		let lines =
			divergences.map { record in
				"\(timestamp) tick=\(record.tickFingerprint) key=\(record.windowKey.rawValue) "
					+ "field=\(record.fieldPath) old=\(redacted(record.fieldPath, record.oldValue)) "
					+ "new=\(redacted(record.fieldPath, record.newValue))\n"
			}
			.joined()
		guard let data = lines.data(using: .utf8) else { return }

		if fileManager.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
			defer { try? handle.close() }
			handle.seekToEndOfFile()
			handle.write(data)
		} else {
			try? data.write(to: url)
		}
	}
}
