import Foundation

/// One parsed entry from the `state-transitions.log` NDJSON file.
struct TransitionEntry: Equatable {
	let ts: String
	let state: String
	let prev: String?
	let sourceKind: String?
	let sourceName: String?
	let sourceOrigin: String?
	let isHeartbeat: Bool
}

/// Read-only observability aggregation for the Developer settings tab (P8.08).
///
/// Reads state.json, gate.json, and the last 5 transition log entries at call
/// time (no polling — call `refresh()` to update). All properties are computed
/// lazily from the injected paths.
final class DeveloperTabViewModel {
	let stateJsonPath: String
	let gateJsonPath: String?
	let transitionLogPath: String
	let hooksSnapshot: HooksStatusSnapshot?

	init(
		stateJsonPath: String,
		gateJsonPath: String?,
		transitionLogPath: String,
		hooksSnapshot: HooksStatusSnapshot? = nil
	) {
		self.stateJsonPath = stateJsonPath
		self.gateJsonPath = gateJsonPath
		self.transitionLogPath = transitionLogPath
		self.hooksSnapshot = hooksSnapshot
	}

	// MARK: - Transition log

	/// Last 5 non-heartbeat entries from the transition log, in file order (oldest first).
	var last5Transitions: [TransitionEntry] {
		Self.readLastNTransitions(5, from: transitionLogPath)
	}

	// MARK: - State JSON

	/// Pretty-printed content of state.json, or a short absence message.
	var stateJsonPretty: String {
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateJsonPath)),
			let obj = (try? JSONSerialization.jsonObject(with: data)),
			let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
			let str = String(data: pretty, encoding: .utf8)
		else {
			return "(state.json absent or unreadable)"
		}
		return str
	}

	/// Pretty-printed content of gate.json, or nil when no gate path is configured.
	var gateJsonPretty: String? {
		guard let path = gateJsonPath else { return nil }
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
			let obj = (try? JSONSerialization.jsonObject(with: data)),
			let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
			let str = String(data: pretty, encoding: .utf8)
		else {
			return "(gate.json absent or unreadable)"
		}
		return str
	}

	// MARK: - Schema version

	/// Schema version this renderer understands.
	var rendererSchemaVersion: Int { EXPECTED_STATE_SCHEMA_VERSION }

	/// Schema version reported by state.json.
	/// Returns 0 when the file is absent, or -1 when present but `schema_version` is
	/// missing or not a valid integer (e.g. a string value). -1 triggers a mismatch
	/// warning so an invalid schema does not silently pass the mismatch check.
	var stateSchemaVersion: Int {
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateJsonPath)) else {
			return 0  // absent file — not a mismatch
		}
		guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
			return -1  // present but unparseable JSON — flag as problematic
		}
		guard let v = obj["schema_version"] as? Int else {
			return -1  // present but schema_version is missing or non-integer
		}
		return v
	}

	/// True when state.json is present but its schema version differs from the renderer's.
	/// A file that is absent (sv == 0) does not trigger a mismatch.
	var schemaVersionMismatch: Bool {
		let sv = stateSchemaVersion
		guard sv != 0 else { return false }
		return sv != rendererSchemaVersion
	}

	// MARK: - Cursor-bridge explainer

	/// Last-seen `source_origin` from the transition log.
	/// Scans the last 50 entries so that a source origin older than the 5 displayed
	/// transitions still surfaces in the Cursor-bridge explainer.
	var lastSeenSourceOrigin: String? {
		Self.readLastNTransitions(50, from: transitionLogPath)
			.last { $0.sourceOrigin != nil }?.sourceOrigin
	}

	/// Last-seen `source_name` from the transition log (same 50-entry window).
	var lastSeenSourceName: String? {
		Self.readLastNTransitions(50, from: transitionLogPath)
			.last { $0.sourceName != nil }?.sourceName
	}

	// MARK: - Hooks-present summary

	/// Human-readable hooks-present summary, or nil when no snapshot is available.
	var hooksPresentSummary: String? {
		guard let snap = hooksSnapshot else { return nil }
		let platforms: [(String, HooksStatusSnapshot.Platform)] = [
			("codex", snap.codex),
			("claude_code", snap.claudeCode),
			("cursor", snap.cursor),
			("vscode", snap.vscode),
		]
		let lines = platforms.compactMap { (name, platform) -> String? in
			guard platform.installableInPhase else { return nil }
			let mark = platform.installed ? "✓" : "✗"
			let firing = platform.firingRecently ? " (firing)" : ""
			return "\(name): \(mark)\(firing)"
		}
		return lines.joined(separator: "\n")
	}

	// MARK: - Internal: transition log reader

	/// Read the last `n` non-heartbeat NDJSON entries from `path`.
	static func readLastNTransitions(_ n: Int, from path: String) -> [TransitionEntry] {
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
			let text = String(data: data, encoding: .utf8)
		else { return [] }

		let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

		var entries: [TransitionEntry] = []
		for line in lines {
			guard let lineData = line.data(using: .utf8),
				let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
			else { continue }

			let isHeartbeat = (obj["heartbeat"] as? Bool) == true
			let state = obj["state"] as? String ?? ""
			let prev = obj["prev"] as? String
			let sourceKind = obj["source_kind"] as? String
			let sourceName = obj["source_name"] as? String
			let sourceOrigin = obj["source_origin"] as? String
			let ts = obj["ts"] as? String ?? ""

			let entry = TransitionEntry(
				ts: ts, state: state, prev: prev,
				sourceKind: sourceKind, sourceName: sourceName, sourceOrigin: sourceOrigin,
				isHeartbeat: isHeartbeat
			)
			if !isHeartbeat {
				entries.append(entry)
			}
		}

		if entries.count <= n { return entries }
		return Array(entries.suffix(n))
	}
}
