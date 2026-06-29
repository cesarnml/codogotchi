import Foundation

/// Writes back to slice files in `state.d/`. Used when the app needs to clear
/// hook-owned state (e.g. dismissing an attention payload so a relaunch does
/// not re-show the bubble).
enum StateJsonWriter {
	/// Clears `attention` and sets `activity_state` to `"idle"` in slice files
	/// inside the `state.d/` directory. Fails silently — the worst outcome
	/// is the bubble reappears on relaunch.
	///
	/// When `origin` is non-nil, only slices whose `source_event.origin` matches
	/// are cleared. Multi-pet mode renders one window per origin, so dismissing
	/// one pet's bubble must not silence pending attention on the others. When
	/// `origin` is nil (the combined-window and legacy single-state paths) every
	/// slice is cleared.
	static func dismissAttention(at dir: String, origin: String? = nil) {
		let fm = FileManager.default
		guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
		for name in names {
			guard name.hasSuffix(".json"), !name.hasPrefix(".") else { continue }
			let path = (dir as NSString).appendingPathComponent(name)
			let url = URL(fileURLWithPath: path)
			guard let data = try? Data(contentsOf: url),
				var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
			else { continue }
			if let origin {
				let sliceOrigin = (root["source_event"] as? [String: Any])?["origin"] as? String
				guard sliceOrigin?.trimmingCharacters(in: .whitespaces) == origin else { continue }
			}
			root["activity_state"] = "idle"
			root.removeValue(forKey: "attention")
			guard let written = try? JSONSerialization.data(
				withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
			else { continue }
			try? written.write(to: url, options: .atomic)
		}
	}
}
