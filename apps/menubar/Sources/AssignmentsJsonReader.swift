import Foundation

/// The 6 valid badge keys in `assignments.json`.
let ASSIGNMENT_BADGE_KEYS = ["default", "claude_code", "vscode", "codex", "cursor", "antigravity"]

/// Decoded form of `~/.codogotchi/assignments.json`. All fields have safe
/// defaults so the pool stays functional when the file is absent or malformed.
struct AssignmentsSnapshot {
	/// The pet ID assigned to the Default badge (mandatory, falls back to `DEFAULT_PET_NAME`).
	let `default`: String
	/// Optional per-platform pet ID overrides keyed by origin string.
	let platformOverrides: [String: String]

	static let safeDefault = AssignmentsSnapshot(
		default: DEFAULT_PET_NAME,
		platformOverrides: [:]
	)

	/// Returns the pet ID for the given origin.
	///
	/// `combined` and any origin without an explicit override fall through to `default`.
	func resolve(origin: String) -> String {
		guard origin != "combined" else { return self.default }
		return platformOverrides[origin] ?? self.default
	}
}

/// Reads `assignments.json` from disk and returns an `AssignmentsSnapshot`.
/// Any IO error or decode failure returns `AssignmentsSnapshot.safeDefault`.
enum AssignmentsJsonReader {
	static func read(at path: String) -> AssignmentsSnapshot {
		let url = URL(fileURLWithPath: path)
		guard let data = try? Data(contentsOf: url) else { return .safeDefault }

		let decoder = JSONDecoder()
		guard let payload = try? decoder.decode(AssignmentsPayload.self, from: data),
			let defaultPet = payload.defaultPet, !defaultPet.isEmpty
		else { return .safeDefault }

		var overrides: [String: String] = [:]
		if let v = payload.claudeCode, !v.isEmpty { overrides["claude_code"] = v }
		if let v = payload.vscode, !v.isEmpty { overrides["vscode"] = v }
		if let v = payload.codex, !v.isEmpty { overrides["codex"] = v }
		if let v = payload.cursor, !v.isEmpty { overrides["cursor"] = v }
		if let v = payload.antigravity, !v.isEmpty { overrides["antigravity"] = v }

		return AssignmentsSnapshot(default: defaultPet, platformOverrides: overrides)
	}
}

private struct AssignmentsPayload: Decodable {
	let defaultPet: String?
	let claudeCode: String?
	let vscode: String?
	let codex: String?
	let cursor: String?
	let antigravity: String?

	enum CodingKeys: String, CodingKey {
		case defaultPet = "default"
		case claudeCode = "claude_code"
		case vscode
		case codex
		case cursor
		case antigravity
	}
}

// MARK: - Writer

/// Persists a single badge assignment through the persist-first `ConfigFileWriter` pattern.
///
/// The badge-uniqueness invariant — each badge key holds exactly one pet ID — is
/// guaranteed structurally by the JSON key-value shape. The writer enforces it on
/// write by passing only the updated key-value pair to `ConfigFileWriter.merge`,
/// which preserves all other existing keys.
enum AssignmentsJsonWriter {
	/// Assigns `petId` to `badge` in the file at `url`.
	///
	/// - `badge` must be one of the 6 valid assignment badge keys.
	/// - On success the file reflects the new assignment; all other badges are unchanged.
	/// - When the file does not yet exist and `badge` is not `"default"`, seeds
	///   `default: DEFAULT_PET_NAME` so the reader always finds a valid `default` key.
	/// - Throws `ConfigFileWriterError` when the existing file is unreadable.
	static func write(badge: String, petId: String, to url: URL) throws {
		var update: [String: Any] = [badge: petId]
		if badge != "default", !FileManager.default.fileExists(atPath: url.path) {
			update["default"] = DEFAULT_PET_NAME
		}
		try ConfigFileWriter.merge(update, into: url)
	}
}

/// Pure helper: applies one badge assignment to an in-memory overrides dictionary.
///
/// Shared by `AssignmentsJsonWriter` callers and P14.07's `PetTabViewModel` so
/// the uniqueness invariant is computed once in both places.
func applyBadgeAssignment(badge: String, petId: String, in overrides: [String: String]) -> [String: String] {
	var result = overrides
	result[badge] = petId
	return result
}

// MARK: - Migration

/// Seeds `assignments.json` on first launch from `config.pet`, then never reads
/// `config.pet` again.
enum AssignmentsMigration {
	/// Seeds `assignments.json` when absent using O_EXCL exclusive-create semantics.
	///
	/// - If `assignmentsURL` already exists: no-op (idempotent).
	/// - Otherwise: raw-reads `config.json`'s `pet` key via `JSONSerialization`
	///   (schema-independent), falls back to `DEFAULT_PET_NAME`, and writes a
	///   minimal `assignments.json` with `default` set to that pet ID.
	/// - O_EXCL guarantees another process cannot silently overwrite `assignments.json`
	///   created in the window between our existence check and our write.
	///
	/// Failures are silently swallowed so a migration hiccup never crashes the pool.
	static func seedIfAbsent(assignmentsURL: URL, configURL: URL) {
		let petId: String
		if let data = try? Data(contentsOf: configURL),
			let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
			let pet = obj["pet"] as? String, !pet.isEmpty
		{
			petId = pet
		} else {
			petId = DEFAULT_PET_NAME
		}

		let payload: [String: Any] = ["schema_version": 1, "default": petId]
		guard let data = try? JSONSerialization.data(
			withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
		else { return }

		// O_CREAT | O_EXCL: fails with EEXIST when file already exists → race-safe no-op.
		let fd = Darwin.open(assignmentsURL.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
		guard fd >= 0 else { return }
		defer { Darwin.close(fd) }
		_ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
	}
}
