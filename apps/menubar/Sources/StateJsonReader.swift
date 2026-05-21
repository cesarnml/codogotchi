import Foundation

/// Renderer-side schema version this build understands. P2.02's forward-compat
/// clause: any `state.json` with `schema_version > EXPECTED_STATE_SCHEMA_VERSION`
/// is refused; equal or lower versions parse best-effort and tolerate extra
/// fields. Bump deliberately when the renderer gains support for a newer
/// schema; do not silently widen.
let EXPECTED_STATE_SCHEMA_VERSION = 1

/// Error cases surfaced by `StateJsonReader.read(at:)`.
///
/// `schemaNewer` carries both observed and expected versions so the renderer's
/// tooltip code (P2.07) can format the canonical "schema_version is v{got};
/// this app supports v{expected}" string without re-parsing the payload.
enum StateReadError: Error, Equatable {
	case fileNotFound
	case malformed
	case schemaMissingOrInvalid
	case schemaNewer(got: Int, expected: Int)
}

/// Reads `state.json` payloads from disk and returns either a decoded
/// `StateSnapshot` or the precise failure reason.
///
/// The reader is namespace-style (enum with no cases) because there is no
/// instance state — every call resolves a single path. `Result` is preferred
/// over throws so callers can match exhaustively without `do/catch` ceremony.
enum StateJsonReader {
	static func read(at path: String) -> Result<StateSnapshot, StateReadError> {
		let url = URL(fileURLWithPath: path)

		let data: Data
		do {
			data = try Data(contentsOf: url)
		} catch {
			if (error as NSError).domain == NSCocoaErrorDomain
				&& (error as NSError).code == NSFileReadNoSuchFileError
			{
				return .failure(.fileNotFound)
			}
			if !FileManager.default.fileExists(atPath: path) {
				return .failure(.fileNotFound)
			}
			return .failure(.malformed)
		}

		// Inspect schema_version before full decode so we can map the precise
		// missing/non-integer and newer-than-expected cases.
		guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
			return .failure(.malformed)
		}
		// JSONSerialization bridges JSON booleans to NSNumber, and NSNumber
		// satisfies `as? Int`. Reject Bool explicitly so `"schema_version": true`
		// is correctly classified as `.schemaMissingOrInvalid` rather than
		// silently coerced to `1`. Only true integer NSNumbers are accepted.
		guard let rawNumber = root["schema_version"] as? NSNumber,
			CFGetTypeID(rawNumber) != CFBooleanGetTypeID(),
			CFNumberIsFloatType(rawNumber) == false
		else {
			return .failure(.schemaMissingOrInvalid)
		}
		let schemaVersion = rawNumber.intValue
		if schemaVersion > EXPECTED_STATE_SCHEMA_VERSION {
			return .failure(
				.schemaNewer(got: schemaVersion, expected: EXPECTED_STATE_SCHEMA_VERSION)
			)
		}

		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		do {
			let payload = try decoder.decode(StatePayload.self, from: data)
			return .success(
				StateSnapshot(
					schemaVersion: payload.schemaVersion,
					activityState: payload.activityState,
					updatedAt: payload.updatedAt,
					sourceEvent: payload.sourceEvent
				)
			)
		} catch {
			return .failure(.malformed)
		}
	}
}

/// Private wire shape: matches v1 schema keys after snake-case conversion.
/// Extra payload fields (`hp`, `hpOverlay`, etc.) are tolerated because
/// `Decodable` ignores unknown keys by default. `sourceEvent` is decoded
/// when present so the transition log (P2.08) can record its
/// `origin`/`kind`/`name` triplet; absence is normal and surfaces as nil.
private struct StatePayload: Decodable {
	let schemaVersion: Int
	let activityState: ActivityState
	let updatedAt: String
	let sourceEvent: SourceEvent?
}
