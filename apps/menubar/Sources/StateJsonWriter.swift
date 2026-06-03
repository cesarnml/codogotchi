import Foundation

/// Writes back to `state.json` in-place. Used when the app needs to mutate
/// hook-owned state (e.g. dismissing an attention payload so a relaunch does
/// not re-show the bubble).
enum StateJsonWriter {
	/// Sets `activity_state` to `"idle"` and removes `attention` from the
	/// on-disk state.json. All other fields are preserved unchanged.
	/// Fails silently — the worst outcome is the bubble reappears on relaunch.
	static func dismissAttention(at path: String) {
		let url = URL(fileURLWithPath: path)
		guard let data = try? Data(contentsOf: url),
			var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		else { return }
		root["activity_state"] = "idle"
		root.removeValue(forKey: "attention")
		guard let written = try? JSONSerialization.data(
			withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
		else { return }
		try? written.write(to: url, options: .atomic)
	}
}
