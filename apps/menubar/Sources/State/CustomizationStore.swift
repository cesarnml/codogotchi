import Foundation

/// Single writer of `~/.codogotchi/customization.json`.
///
/// Owns read-merge-write (via `ConfigFileWriter.merge`, decoded back through
/// `CustomizationJsonReader`) plus a closure-based change-publication API, so
/// every writer — `CustomizationTabViewModel`, `GeneralTabViewModel`, and the
/// floating panels' right-click mode-switch affordances in `MenubarApp` — goes
/// through one call site instead of each hand-rolling its own read-merge-write
/// and a shared `NotificationCenter` name to signal other writers.
///
/// Multiple `CustomizationStore` instances may point at the same file (e.g. a
/// throwaway instance vs. the app's shared instance, or two isolated instances
/// in a test) — each `merge`/domain setter always re-reads the file it just
/// wrote, so sequential writes from different instances never drop each
/// other's fields, exactly like the pre-refactor `ConfigFileWriter.merge`
/// contract. Publication is per-instance: only subscribers registered on the
/// SAME instance that performed the write are notified. Production code
/// shares one instance (see `MenubarApp`) so a right-click write reaches the
/// open Settings tab's subscription.
final class CustomizationStore {
	/// Opaque handle returned by `subscribe(_:)`; pass to `unsubscribe(_:)`.
	typealias Token = UUID

	/// Latest known snapshot — set at init and refreshed after every
	/// successful `merge`/`reload` on this instance.
	private(set) var snapshot: CustomizationSnapshot
	private let filePath: String
	private var subscribers: [Token: (CustomizationSnapshot) -> Void] = [:]

	init(filePath: String = CodogotchiFolders.customizationPath()) {
		self.filePath = filePath
		self.snapshot = CustomizationJsonReader.read(at: filePath)
	}

	/// Re-reads the file from disk — picking up bytes written by another
	/// process, or another `CustomizationStore` instance in the same process —
	/// and republishes the result to this instance's subscribers.
	@discardableResult
	func reload() -> CustomizationSnapshot {
		snapshot = CustomizationJsonReader.read(at: filePath)
		publish()
		return snapshot
	}

	/// Read-merge-write: merges `updates` into the on-disk payload (preserving
	/// every unmanaged/sibling key, per `ConfigFileWriter.merge`'s contract),
	/// re-reads to obtain the coerced/clamped result, and publishes it to this
	/// instance's subscribers. Returns `nil` — leaving `snapshot` unchanged —
	/// on write failure, so callers can no-op exactly like the pre-refactor
	/// per-setter `do/catch` blocks did.
	///
	/// `notify` defaults to `true`; pass `false` to persist without publishing
	/// — used for the Panel Size drag's intermediate ticks, which must write
	/// every frame but only re-sync an open Settings tab once, on the final
	/// tick (see `MenubarApp.onPanelSizeChanged`).
	@discardableResult
	func merge(_ updates: [String: Any], notify: Bool = true) -> CustomizationSnapshot? {
		do {
			try ConfigFileWriter.merge(updates, into: URL(fileURLWithPath: filePath))
		} catch {
			NSLog("CustomizationStore: merge write failed — \(error)")
			return nil
		}
		snapshot = CustomizationJsonReader.read(at: filePath)
		if notify {
			publish()
		}
		return snapshot
	}

	/// Persists the per-origin platform mode. `NSNull` removes the key when
	/// every mode is back to the default (`.own`), avoiding an empty
	/// `platform_modes` object in the file — mirrors the setter this replaces.
	@discardableResult
	func setMode(_ mode: PlatformMode, for origin: String, notify: Bool = true)
		-> CustomizationSnapshot?
	{
		var proposed = snapshot.platformModes
		if mode == .own {
			proposed.removeValue(forKey: origin)
		} else {
			proposed[origin] = mode
		}
		let modesValue: Any = proposed.isEmpty ? NSNull() : proposed.mapValues { $0.rawValue }
		return merge(["platform_modes": modesValue], notify: notify)
	}

	@discardableResult
	func setCombinedMinimalistEnabled(_ enabled: Bool, notify: Bool = true)
		-> CustomizationSnapshot?
	{
		merge(["combined_minimalist_enabled": enabled], notify: notify)
	}

	/// Clamps to the achievable range (mirrors `CustomizationJsonReader`'s own
	/// clamp on read) before persisting.
	@discardableResult
	func setMinimalistBadgeScale(_ scale: Double, notify: Bool = true) -> CustomizationSnapshot? {
		let clamped = max(
			Double(GateBadgeLayout.achievableMinScale),
			min(Double(GateBadgeLayout.achievableMaxScale), scale)
		)
		return merge(["minimalist_badge_scale": clamped], notify: notify)
	}

	/// Registers `handler` to be called with the latest snapshot after every
	/// successful `merge`/`reload`/domain-setter write on THIS store instance.
	/// Returns a token for `unsubscribe(_:)`; callers that don't outlive the
	/// store (e.g. a view model) should unsubscribe in `deinit`.
	@discardableResult
	func subscribe(_ handler: @escaping (CustomizationSnapshot) -> Void) -> Token {
		let token = Token()
		subscribers[token] = handler
		return token
	}

	func unsubscribe(_ token: Token) {
		subscribers.removeValue(forKey: token)
	}

	private func publish() {
		for handler in subscribers.values {
			handler(snapshot)
		}
	}
}
