import Foundation

/// Performs safe read-merge-write on a JSON object file.
///
/// Loads the existing file (if any), aborts when the file exists but cannot
/// be parsed as a JSON object (preventing silent clobbers of unmanaged keys),
/// merges the caller's updates, seeds `schema_version = 1` when absent, and
/// writes atomically. `NSNull` values in `updates` remove their key from the
/// payload so callers can delete keys without a separate API.
///
/// Callers must follow the "persist first, propagate second" contract:
/// update in-memory state only after this function returns without throwing.
enum ConfigFileWriter {
  static func merge(_ updates: [String: Any], into url: URL) throws {
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

    var payload: [String: Any] = [:]
    if FileManager.default.fileExists(atPath: url.path) {
      guard let data = try? Data(contentsOf: url),
        let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        throw ConfigFileWriterError.existingFileUnreadable(url.path)
      }
      payload = existing
    }
    if payload["schema_version"] == nil {
      payload["schema_version"] = 1
    }
    for (key, value) in updates {
      if value is NSNull {
        payload.removeValue(forKey: key)
      } else {
        payload[key] = value
      }
    }
    let data = try JSONSerialization.data(
      withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
  }
}

enum ConfigFileWriterError: LocalizedError {
  case existingFileUnreadable(String)

  var errorDescription: String? {
    switch self {
    case .existingFileUnreadable(let path):
      return "file exists but cannot be read as a JSON object: \(path)"
    }
  }
}
