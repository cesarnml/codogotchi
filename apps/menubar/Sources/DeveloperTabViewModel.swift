import Foundation

/// One parsed entry from the `state-transitions.log` NDJSON file.
struct TransitionEntry {
	let ts: String
	let state: String
	let prev: String?
	let sourceKind: String?
	let sourceName: String?
	let sourceOrigin: String?
	let isHeartbeat: Bool
}

/// Read-only observability aggregation for the Developer settings tab.
/// Stubs until P8.08 green.
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

	/// Last 5 non-heartbeat transition log entries. Stub until green.
	var last5Transitions: [TransitionEntry] { [] }

	/// Pretty-printed state.json content. Stub until green.
	var stateJsonPretty: String { "" }

	/// Pretty-printed gate.json content, or nil when no path is configured. Stub until green.
	var gateJsonPretty: String? { nil }

	/// Schema version reported by state.json. Stub until green.
	var stateSchemaVersion: Int { 0 }

	/// Schema version this renderer understands.
	var rendererSchemaVersion: Int { EXPECTED_STATE_SCHEMA_VERSION }

	/// True when state.json schema version != renderer schema version. Stub until green.
	var schemaVersionMismatch: Bool { false }

	/// Last-seen source_origin from the transition log. Stub until green.
	var lastSeenSourceOrigin: String? { nil }

	/// Last-seen source_name from the transition log. Stub until green.
	var lastSeenSourceName: String? { nil }

	/// Human-readable hooks-present summary, or nil when no snapshot. Stub until green.
	var hooksPresentSummary: String? { nil }
}
