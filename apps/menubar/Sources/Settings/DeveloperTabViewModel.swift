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
/// Reads the most-recent slice from state.d/, gate.json, delivery-context.json,
/// and the last 5 transition log entries at call time (no polling — call
/// `refresh()` to update). All properties are computed lazily from the injected paths.
final class DeveloperTabViewModel {
	/// Path to the `state.d/` directory written by the hook.
	let stateDirPath: String
	let gateJsonPath: String?
	let deliveryContextPath: String?
	let transitionLogPath: String
	let hooksSnapshot: HooksStatusSnapshot?

	init(
		stateDirPath: String,
		gateJsonPath: String?,
		deliveryContextPath: String? = nil,
		transitionLogPath: String,
		hooksSnapshot: HooksStatusSnapshot? = nil
	) {
		self.stateDirPath = stateDirPath
		self.gateJsonPath = gateJsonPath
		self.deliveryContextPath = deliveryContextPath
		self.transitionLogPath = transitionLogPath
		self.hooksSnapshot = hooksSnapshot
	}

	// MARK: - Transition log

	/// Last 5 non-heartbeat entries from the transition log, in file order (oldest first).
	var last5Transitions: [TransitionEntry] {
		Self.readLastNTransitions(5, from: transitionLogPath)
	}

	// MARK: - State (state.d/ latest slice)

	/// Path to the most-recently modified `.json` slice file in `stateDirPath`,
	/// or nil when the directory is absent or empty.
	private var latestSlicePath: String? {
		let fm = FileManager.default
		var isDir: ObjCBool = false
		guard fm.fileExists(atPath: stateDirPath, isDirectory: &isDir), isDir.boolValue else {
			return nil
		}
		guard let names = try? fm.contentsOfDirectory(atPath: stateDirPath) else { return nil }
		let jsonNames = names.filter { $0.hasSuffix(".json") && !$0.contains(".tmp-") }
		return jsonNames
			.compactMap { name -> (path: String, mtime: Date)? in
				let path = (stateDirPath as NSString).appendingPathComponent(name)
				guard let attrs = try? fm.attributesOfItem(atPath: path),
					let mtime = attrs[.modificationDate] as? Date
				else { return nil }
				return (path, mtime)
			}
			.max(by: { $0.mtime < $1.mtime })
			.map(\.path)
	}

	/// Pretty-printed content of the most-recent state.d/ slice, or a short absence message.
	var stateJsonPretty: String {
		guard let path = latestSlicePath,
			let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
			let obj = (try? JSONSerialization.jsonObject(with: data)),
			let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
			let str = String(data: pretty, encoding: .utf8)
		else {
			return "(state.d/ absent or empty)"
		}
		return str
	}

	/// Newest `*.<suffix>` file directly inside `stateDirPath` (state.d/), or nil
	/// when the directory is absent or has no matching file.
	private func newestStateDirFile(suffix: String) -> String? {
		let fm = FileManager.default
		guard let names = try? fm.contentsOfDirectory(atPath: stateDirPath) else { return nil }
		return names
			.filter { $0.hasSuffix(suffix) && !$0.contains(".tmp-") }
			.compactMap { name -> (path: String, mtime: Date)? in
				let path = (stateDirPath as NSString).appendingPathComponent(name)
				guard let attrs = try? fm.attributesOfItem(atPath: path),
					let mtime = attrs[.modificationDate] as? Date
				else { return nil }
				return (path, mtime)
			}
			.max(by: { $0.mtime < $1.mtime })
			.map(\.path)
	}

	/// Path backing `gateJsonPretty`: prefers the newest per-origin
	/// `<origin>:<session_id>.gate.json` slice in state.d/ over the legacy flat
	/// `gate.json`. son-of-anton (Phase 17) writes the per-origin file whenever
	/// it can resolve an active session; the flat file is the pre-Phase-17
	/// fallback, kept for installs the orchestrator hasn't attributed yet.
	private var resolvedGateJsonPath: String? {
		newestStateDirFile(suffix: ".gate.json") ?? gateJsonPath
	}

	/// Same preference order as `resolvedGateJsonPath`, for delivery-context.json.
	private var resolvedDeliveryContextPath: String? {
		newestStateDirFile(suffix: ".context.json") ?? deliveryContextPath
	}

	/// Section header label for the gate JSON block — the per-origin filename
	/// when that's the source, so the Developer tab makes clear *which*
	/// platform's gate is shown rather than always reading "gate.json".
	var gateJsonSourceLabel: String {
		guard let path = resolvedGateJsonPath else { return "gate.json" }
		return (path as NSString).lastPathComponent
	}

	/// Same labeling as `gateJsonSourceLabel`, for delivery-context.json.
	var deliveryContextSourceLabel: String {
		guard let path = resolvedDeliveryContextPath else { return "delivery-context.json" }
		return (path as NSString).lastPathComponent
	}

	/// Pretty-printed content of the resolved gate JSON, or nil when no path is configured.
	var gateJsonPretty: String? {
		guard let path = resolvedGateJsonPath else { return nil }
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
			let obj = (try? JSONSerialization.jsonObject(with: data)),
			let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
			let str = String(data: pretty, encoding: .utf8)
		else {
			return "(\(gateJsonSourceLabel) absent or unreadable)"
		}
		return str
	}

	/// Pretty-printed content of the resolved delivery-context JSON, or nil when no path is configured.
	var deliveryContextPretty: String? {
		guard let path = resolvedDeliveryContextPath else { return nil }
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
			let obj = (try? JSONSerialization.jsonObject(with: data)),
			let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
			let str = String(data: pretty, encoding: .utf8)
		else {
			return "(\(deliveryContextSourceLabel) absent or unreadable)"
		}
		return str
	}

	// MARK: - Schema version

	/// Schema version this renderer understands.
	var rendererSchemaVersion: Int { EXPECTED_STATE_SCHEMA_VERSION }

	/// Schema version reported by the most-recent slice in state.d/.
	/// Returns 0 when state.d/ is absent/empty, or -1 when the latest slice
	/// is present but `schema_version` is missing or not a valid integer.
	/// -1 triggers a mismatch warning so a bad payload doesn't silently pass.
	var stateSchemaVersion: Int {
		guard let path = latestSlicePath,
			let data = try? Data(contentsOf: URL(fileURLWithPath: path))
		else {
			return 0  // no slice on disk — not a mismatch
		}
		guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
			return -1  // present but unparseable JSON
		}
		guard let v = obj["schema_version"] as? Int else {
			return -1  // schema_version missing or non-integer
		}
		return v
	}

	/// True when a slice is present but its schema version differs from the renderer's.
	/// A missing state.d/ (sv == 0) does not trigger a mismatch.
	var schemaVersionMismatch: Bool {
		let sv = stateSchemaVersion
		guard sv != 0 else { return false }
		return sv != rendererSchemaVersion
	}

	// MARK: - Platform attribution

	/// Last-seen `source_origin` from the transition log.
	/// Scans the last 50 entries so that a source origin older than the 5 displayed
	/// transitions still surfaces in the platform-attribution line.
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
			// `present` folds in partial installs, so a real, firing integration
			// reads ✓ — not a misleading ✗ just because one newly-added event
			// isn't wired yet.
			let mark = platform.present ? "✓" : "✗"
			let firing = platform.firingRecently ? " (firing)" : ""
			let partial = platform.partiallyInstalled ? " (update available)" : ""
			return "\(name): \(mark)\(firing)\(partial)"
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
