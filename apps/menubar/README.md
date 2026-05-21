# apps/menubar

macOS menu-bar app for Codogotchi. First native Swift surface in the repo (Phase 02 scaffolding).

> **Dev build only.** No code signing, no notarization, no distribution pipeline. The committed `.xcodeproj` is for local development. A signing/notarization story is deliberately deferred to a later distribution-focused phase.

## What this app is right now (P2.01)

A minimal `NSStatusItem` with a placeholder `pawprint` system-symbol icon and a single **Quit Menubar** menu item. `LSUIElement = true` in `Info.plist` makes it a true menu-bar agent: no Dock icon, no main window.

Later Phase 02 tickets replace the placeholder icon with the Mali sprite, wire `~/.codogotchi/state.json` polling, and add state-driven animation on top of this scaffold.

## Open in Xcode

```bash
open apps/menubar/Menubar.xcodeproj
```

## Build & test from the terminal

```bash
# Build
xcodebuild -project apps/menubar/Menubar.xcodeproj -scheme Menubar build

# Run tests (smoke test for now)
xcodebuild -project apps/menubar/Menubar.xcodeproj -scheme Menubar test
```

Or via the root `package.json` script aliases:

```bash
bun run mac:build
bun run mac:test
```

`bun run ci` stays TS-only — Swift verification is a manual local step you run and paste into ticket PR bodies. See `docs/product/delivery/phase-02/implementation-plan.md` (Review Rules).

## Running this app daily

This is a **dev build** — unsigned, not notarized, no launch-at-login automation. Day-to-day use is manual.

### Launch from Xcode

```bash
open apps/menubar/Menubar.xcodeproj
```

Then ⌘R. The pawprint icon (or Mali sprite, once `~/.codex/pets/mali/` is populated) appears in the menu bar.

### Launch the built `.app` directly

After `bun run mac:build` (or an Xcode build), the product lives under Xcode's `DerivedData` build output. Launch it with `open` or by double-clicking it in Finder.

Because the build is unsigned and not notarized, Gatekeeper warns on first launch: _"Menubar cannot be opened because the developer cannot be verified."_ Right-click the `.app` → **Open** → confirm. macOS remembers the exception; subsequent double-clicks work normally.

### Launch-at-login (deferred)

There is intentionally no `SMAppService` / login-item registration in this build. Launch the app manually each day, or use macOS's standard **System Settings → General → Login Items → Open at Login** to add the built `.app`. A first-class launch-at-login story is deferred to a later distribution-focused phase.

### Confirming the app is alive

- The menu bar shows the pet (or the pawprint placeholder when Mali assets are missing).
- The **Codogotchi** menu opens on click; **Quit Codogotchi** terminates the agent.

### Confirming state is updating

```bash
tail -f ~/.codogotchi/state-transitions.log
```

Each new line is one observed `(prev → curr)` activity-state transition or a periodic heartbeat. If the file does not exist, the app has not yet written a transition (no live activity yet) — that is normal until the hook publishes a state change.

### Sleep / wake

Closing the lid (or otherwise sleeping the machine) is safe — the 1-second poller pauses naturally because `Timer` does not fire while the system is asleep. On wake, the app receives `NSWorkspace.didWakeNotification` and triggers an immediate out-of-band poll so the pet reflects current state without waiting for the next scheduled tick.

## Demo mode

Demo mode (P2.06) re-points the polling target to a sandboxed file under `$TMPDIR/codogotchi-demo/state.json` and runs a fixture cycle driver that copies the four floor-state fixtures (`idle` → `implementing` → `running-tests` → `celebrating` → loop) on a 3-second timer. The real `~/.codogotchi/state.json` is never touched.

Two equivalent activations:

```bash
# 1. Environment variable
CODOGOTCHI_DEMO=1 open apps/menubar/Menubar.xcodeproj   # then ⌘R from Xcode
# or after a build, launch the .app with the env var pre-set:
CODOGOTCHI_DEMO=1 open path/to/Menubar.app

# 2. Launch argument (useful for Xcode scheme "Arguments Passed On Launch")
path/to/Menubar.app/Contents/MacOS/Menubar --demo
```

Inside Xcode: edit the Menubar scheme → **Run** → **Arguments** → add `CODOGOTCHI_DEMO=1` under **Environment Variables**, or `--demo` under **Arguments Passed On Launch**.

Quit demo mode the same way as any menubar agent: the **Quit Menubar** menu item (or `⌘Q` once that wiring lands in P2.09).

## Regenerating the Xcode project

The `.xcodeproj` is generated from `project.yml` via [xcodegen](https://github.com/yonaskolb/XcodeGen). Both the YAML source and the generated `.xcodeproj` are committed; the YAML is the source of truth.

```bash
brew install xcodegen   # one-time
cd apps/menubar && xcodegen generate
```

Regenerate after editing `project.yml`; commit both the YAML change and the regenerated `.xcodeproj`.

## Directory layout

```
apps/menubar/
  project.yml            # xcodegen source of truth
  Menubar.xcodeproj/     # generated, committed
  Info.plist             # generated by xcodegen from project.yml; committed
  Sources/               # Swift sources
    MenubarApp.swift
  Tests/MenubarTests/    # XCTest unit tests
    MenubarTests.swift
  Resources/             # app resources (placeholder until P2.04)
  Fixtures/              # test/demo fixtures (populated in P2.03+)
  README.md              # this file
```
