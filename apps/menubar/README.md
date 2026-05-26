# apps/menubar

macOS menu-bar app for Codogotchi. First native Swift surface in the repo (Phase 02 scaffolding).

> **Dev build only.** No code signing, no notarization, no distribution pipeline. The committed `.xcodeproj` is for local development. A signing/notarization story is deliberately deferred to a later distribution-focused phase.

## What this app is (Phase 04)

An `LSUIElement` menu bar agent named **Codogotchi** with two render surfaces:

1. **Menu bar micro-pet** — `NSStatusItem` + `MenubarRenderer`, polling
   `~/.codogotchi/state.json` (or demo fixtures).
2. **Floating desktop pet** — transparent float-on-top `NSPanel` with a
   SpriteKit scene (`FloatingPetScene`), toggled from **Show/Hide Floating Pet**.

Direct manipulation: click-hold the frame to drag; click-hold the bottom-right
resize affordance to scale between 96×96 and 512×512 pt. Placement persists in
`~/.codogotchi/app-state.json` and reclamps after display changes.

Validate locally with [`docs/runbooks/phase-04-validation.md`](../../runbooks/phase-04-validation.md).

## Open in Xcode

```bash
open apps/menubar/Codogotchi.xcodeproj
```

## Build & test from the terminal

```bash
# Build
xcodebuild -project apps/menubar/Codogotchi.xcodeproj -scheme Codogotchi build

# Run tests (smoke test for now)
xcodebuild -project apps/menubar/Codogotchi.xcodeproj -scheme Codogotchi test
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
open apps/menubar/Codogotchi.xcodeproj
```

Then ⌘R. The pawprint icon (or Mali sprite, once `~/.codex/pets/mali/` is populated) appears in the menu bar.

### Launch the built `.app` directly

After `bun run mac:build` (or an Xcode build), the product lives under Xcode's `DerivedData` build output. Launch it with `open` or by double-clicking it in Finder.

Because the build is unsigned and not notarized, Gatekeeper warns on first launch: _"Codogotchi cannot be opened because the developer cannot be verified."_ Right-click the `.app` → **Open** → confirm. macOS remembers the exception; subsequent double-clicks work normally.

### Launch-at-login (deferred)

There is intentionally no `SMAppService` / login-item registration in this build. Launch the app manually each day, or use macOS's standard **System Settings → General → Login Items → Open at Login** to add the built `.app`. A first-class launch-at-login story is deferred to a later distribution-focused phase.

### Confirming the app is alive

- The menu bar shows the pet (or idle fallback when assets are missing).
- The **Codogotchi** menu opens on click; **Show/Hide Floating Pet** toggles the
  desktop surface; **Quit Codogotchi** terminates the agent.
- When visible, the floating pet appears transparent around the sprite art.

### Confirming state is updating

```bash
tail -f ~/.codogotchi/state-transitions.log
```

Each new line is one observed `(prev → curr)` activity-state transition or a periodic heartbeat. If the file does not exist, the app has not yet written a transition (no live activity yet) — that is normal until the hook publishes a state change.

### Sleep / wake

Closing the lid (or otherwise sleeping the machine) is safe — the 1-second poller pauses naturally because `Timer` does not fire while the system is asleep. On wake, the app receives `NSWorkspace.didWakeNotification` and triggers an immediate out-of-band poll so the pet reflects current state without waiting for the next scheduled tick.

## Demo mode

Demo mode re-points the polling target to a sandboxed file under
`$TMPDIR/codogotchi-demo/state.json` and cycles activity fixtures on a timer.
Both the menu bar renderer and floating scene consume the same fanout, so demo
mode validates state sync without touching live `~/.codogotchi/state.json`.

Two equivalent activations:

```bash
# 1. Environment variable
CODOGOTCHI_DEMO=1 open apps/menubar/Codogotchi.xcodeproj   # then ⌘R from Xcode
# or after a build, launch the .app with the env var pre-set:
CODOGOTCHI_DEMO=1 open path/to/Codogotchi.app

# 2. Launch argument (useful for Xcode scheme "Arguments Passed On Launch")
path/to/Codogotchi.app/Contents/MacOS/Codogotchi --demo
```

Inside Xcode: edit the Codogotchi scheme → **Run** → **Arguments** → add `CODOGOTCHI_DEMO=1` under **Environment Variables**, or `--demo` under **Arguments Passed On Launch**.

Quit demo mode the same way as any menubar agent: the **Quit Codogotchi** menu item (or `⌘Q` once that wiring lands in P2.09).

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
  Codogotchi.xcodeproj/  # generated, committed
  Info.plist             # generated by xcodegen from project.yml; committed
  Sources/               # Swift sources
    MenubarApp.swift
  Tests/MenubarTests/    # XCTest unit tests
    MenubarTests.swift
  Resources/             # app resources (placeholder until P2.04)
  Fixtures/              # test/demo fixtures (populated in P2.03+)
  README.md              # this file
```
