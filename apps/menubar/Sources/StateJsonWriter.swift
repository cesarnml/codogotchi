import Foundation

/// Writes back to slice files in `state.d/`. Used when the app needs to clear
/// hook-owned state (e.g. dismissing an attention payload so a relaunch does
/// not re-show the bubble).
enum StateJsonWriter {
	/// Clears `attention` and sets `activity_state` to `"idle"` in every slice
	/// file inside the `state.d/` directory. Fails silently — the worst outcome
	/// is the bubble reappears on relaunch.
	static func dismissAttention(at dir: String) {
		let fm = FileManager.default
		guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
		for name in names {
			guard name.hasSuffix(".json"), !name.hasPrefix(".") else { continue }
			let path = (dir as NSString).appendingPathComponent(name)
			let url = URL(fileURLWithPath: path)
			guard let data = try? Data(contentsOf: url),
				var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
			else { continue }
			root["activity_state"] = "idle"
			root.removeValue(forKey: "attention")
			guard let written = try? JSONSerialization.data(
				withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
			else { continue }
			try? written.write(to: url, options: .atomic)
		}
	}
}
