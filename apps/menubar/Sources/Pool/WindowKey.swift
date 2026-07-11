import Foundation

/// Identifies one floating-pet window / render slot: a plain platform origin
/// (session-pets off), a specific session on a platform (session-pets on), or
/// the shared "combined" window that folds several combined-mode origins into
/// one pet.
///
/// This is the **single parse/serialize path** for the window-key string
/// convention the pool, resolver, and menu previously spoke in raw `String`
/// form. `rawValue` byte-matches that pre-existing convention exactly — this
/// is a serialization contract, not a design surface — so persisted state
/// (`app-state.json`, `session-labels.json`, slice/gate filenames) keeps
/// reading and writing the identical strings across the introduction of this
/// type:
/// - `.origin(x)` → `x`
/// - `.session(origin: o, id: s)` → `"\(o):\(s)"`
/// - `.combined` → `"combined"`
///
/// Every other call site should match on the enum (`switch`/`if case`)
/// instead of round-tripping through `rawValue` — see P16.04.
enum WindowKey: Hashable {
	case origin(String)
	case session(origin: String, id: String)
	case combined

	private static let combinedRawValue = "combined"

	/// Parses a persisted/raw window-key string back into its typed form.
	/// Returns `nil` for input that cannot possibly have been produced by
	/// `rawValue`: an empty string, or a colon-bearing string missing its
	/// origin or id half (`":x"`, `"x:"`, `":"`).
	init?(rawValue: String) {
		guard !rawValue.isEmpty else { return nil }
		if rawValue == Self.combinedRawValue {
			self = .combined
			return
		}
		if let colon = rawValue.firstIndex(of: ":") {
			let origin = String(rawValue[rawValue.startIndex..<colon])
			let id = String(rawValue[rawValue.index(after: colon)...])
			guard !origin.isEmpty, !id.isEmpty else { return nil }
			self = .session(origin: origin, id: id)
			return
		}
		self = .origin(rawValue)
	}

	/// The persisted/raw string form — see the type doc for the exact contract.
	var rawValue: String {
		switch self {
		case .origin(let origin):
			return origin
		case .session(let origin, let id):
			return "\(origin):\(id)"
		case .combined:
			return Self.combinedRawValue
		}
	}

	/// The owning platform origin: the key itself for `.origin`, the origin
	/// half for `.session`, and the literal `"combined"` for `.combined` —
	/// matching the pre-existing `origin(forWindowKey:)` contract (the
	/// literal "combined" key mapped to itself, since it never contains a
	/// colon).
	var origin: String {
		switch self {
		case .origin(let origin):
			return origin
		case .session(let origin, _):
			return origin
		case .combined:
			return Self.combinedRawValue
		}
	}

	/// The `(origin, sessionId)` pair for a session-keyed window, or `nil`
	/// for `.origin`/`.combined` — matching the pre-existing
	/// `sessionIdentity(forWindowKey:)` contract.
	var sessionIdentity: (origin: String, sessionId: String)? {
		guard case .session(let origin, let id) = self else { return nil }
		return (origin, id)
	}

	/// True for `.session` keys — matching the pre-existing
	/// `isSessionKeyed(_:)` contract (session numbering, cap partitioning,
	/// etc. only ever apply to these keys).
	var isSessionKeyed: Bool {
		if case .session = self { return true }
		return false
	}
}

/// String-literal ergonomics for test fixtures (P16.04's sanctioned
/// "test fixtures" raw-string boundary) — `let key: WindowKey = "claude:s1"`
/// instead of every test spelling `WindowKey(rawValue: "claude:s1")!`.
/// Delegates to `init?(rawValue:)`, the single parse path, so this adds no
/// second way to interpret a raw string — a malformed literal (which should
/// never appear in a test fixture) degrades to `.origin(value)` rather than
/// crashing the test run.
extension WindowKey: ExpressibleByStringLiteral {
	init(stringLiteral value: String) {
		self = WindowKey(rawValue: value) ?? .origin(value)
	}
}
