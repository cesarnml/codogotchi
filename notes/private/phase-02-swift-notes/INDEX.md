# Phase 02 — Swift Notes (curated reading order)

TS-developer field notes from Phase 02's eight Swift-touching tickets.
Each entry is a companion to the Swift file(s) the ticket landed, scoped
to "what a TS reviewer needs to know to read this PR honestly" — not a
general Swift tutorial.

Recommended read order matches ticket order: each note builds on idioms
introduced in the previous one. Skip around by topic if you only need
the AppKit surface (P2.05, P2.09, P2.10) or only the IPC + polling
surface (P2.03, P2.06, P2.07, P2.08).

- [P2.03 — state-json-reader](P2.03-state-json-reader.md) — raw-value
  enums, `Codable` with an `init(from:)` fallback, and closed-enum
  decoding against an open JSON wire format.
- [P2.04 — mali-pet-loader](P2.04-mali-pet-loader.md) — `NSImage`
  vs. `CGImage`, WebP decode via AppKit, and reading a hardcoded
  `[ActivityState: RowSpec]` row table back into Swift.
- [P2.05 — menubar-renderer](P2.05-menubar-renderer.md) —
  `NSStatusItem` lifecycle (must hold a strong reference),
  `@MainActor` and AppKit threading, and the continuous-loop
  animation swap.
- [P2.06 — demo-mode](P2.06-demo-mode.md) — `ProcessInfo`
  environment + arguments, atomic file writes
  (`Data.write(.atomic)`), and a `$TMPDIR` sandboxed cycle driver
  that never touches real `~/.codogotchi/`.
- [P2.07 — live-polling](P2.07-live-polling.md) —
  `Timer.scheduledTimer` and the `[weak self]` retain-cycle dance,
  bridging the timer callback back onto `@MainActor`.
- [P2.08 — transition-log](P2.08-transition-log.md) — append-only
  NDJSON via `FileHandle`, why we reopen per write, and same-volume
  atomic rename for rotation.
- [P2.09 — menu-items](P2.09-menu-items.md) — `NSMenu` /
  `NSMenuItem` built in code, target/action with weak-target
  pitfalls, and `#selector` vs. trailing-closure init.
- [P2.10 — lifecycle-hardening](P2.10-lifecycle-hardening.md) —
  the two `NotificationCenter` instances (`default` vs.
  `NSWorkspace.shared.notificationCenter`), wake-from-sleep
  observers, and `applicationWillTerminate(_:)` cleanup.
