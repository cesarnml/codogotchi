# P8.01 Compile standalone binaries + Xcode bundle-embed

Size: 3 points
Type: chore
Scope: build
Red: skip

## Outcome

- `bun build --compile` produces standalone arm64 executables for **both** `codogotchi` and `codogotchi-hook` from `packages/cli/bin/*.ts`, with no PATH or workspace-runtime prerequisite.
- A repo build script (e.g. `bun run build:binaries`) writes the two executables to a known artifacts dir.
- The Xcode build (`apps/menubar/project.yml`) embeds both executables into `Codogotchi.app/Contents/Resources/` as a build phase, alongside the existing `Fixtures/maew` resources.
- Smoke check: from the built app, `Codogotchi.app/Contents/Resources/codogotchi-hook --version` and `…/codogotchi --version` run successfully with `PATH=` empty.
- The compiled `codogotchi-hook` cold-start is no worse than today's `bun bin/codogotchi-hook.ts` (sanity-timed, recorded in Rationale).

## Red

- `Red: skip` — this is a build/packaging ticket with no unit-testable behavior. Verification is the smoke check above (a CI/manual step that runs the embedded binary with an empty PATH), not an automated assertion.

## Green

- Add `bun build --compile --target=bun-darwin-arm64` invocations for `packages/cli/bin/codogotchi.ts` and `packages/cli/bin/codogotchi-hook.ts`; resolve workspace deps (`@codogotchi/contracts`, `@codogotchi/engine`) into the bundle.
- Add the build script to `package.json`; output both binaries to a stable artifacts path.
- Add an Xcode copy-files/resources build phase in `project.yml` that places both binaries under `Contents/Resources/` (executable bit preserved).
- Keep the binaries out of source control / lint scope as appropriate (artifacts).

## Refactor

- Only touch the build wiring. Do not change CLI command behavior here — resolution and absolute-path writing are P8.02.

## Review Focus

- That **both** binaries actually run standalone with an empty PATH (no Bun/Node on the machine) — the entire self-contained story rests on this.
- Bundle size impact (each `--compile` binary embeds the Bun runtime ~tens of MB) and that the executable bit survives the Xcode copy.
- Whether one multi-call binary would be simpler than two — intentionally chose two to match the existing `bin` entries; note if that proves wrong.
- Codesign/notarization implications of embedding executables in `Resources/` (flag for the eventual DMG ticket; not signed here).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a (build packaging — smoke-verified).
Why this path: no compiled binary exists today; `bun build --compile` is the lightest path to a self-contained artifact.
Alternative considered: ship the Bun runtime + JS in the bundle — heavier and messier invocation, rejected.
Deferred: universal/Intel binary (arm64-only for v1); codesign/notarization of embedded binaries.

Contract note (implementation, 2026-05-31):

- **Build script.** `scripts/build-binaries.sh` runs `bun build --compile --target=bun-darwin-arm64` for both `packages/cli/bin/codogotchi.ts` and `…/codogotchi-hook.ts`. Workspace deps (`@codogotchi/contracts`, `@codogotchi/engine`) resolve into the bundle automatically. `bun run build:binaries` writes both to `apps/menubar/Generated/binaries/` (gitignored); the script also accepts an output-dir arg, used by Xcode to write straight into the app's `Resources/`. The script discovers `bun` explicitly (login PATH is not inherited by Xcode run-script phases).
- **Embed mechanism.** A `postBuildScripts` run-script phase on the `Codogotchi` target (xcodegen `project.yml`, regenerated into the committed `.xcodeproj`) invokes `build-binaries.sh "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"`, compiling + copying both binaries into `Codogotchi.app/Contents/Resources/` on every build. Chose a build-and-copy run-script over a Copy Files phase because the binaries are gitignored build artifacts that must not need a pre-build step for `mac:test` to be self-contained. `basedOnDependencyAnalysis: false` makes it run every build (and silences the no-outputs warning); `ENABLE_USER_SCRIPT_SANDBOXING: NO` is required so the phase can shell out to bun and read the workspace.
- **Smoke check.** Verified from the built `Codogotchi.app`: both binaries are arm64 Mach-O with the executable bit preserved, and `env -i PATH= …/codogotchi help` and `env -i PATH= …/codogotchi-hook </dev/null` each exit 0 (boots standalone, no Bun/Node on PATH). **`--version` is not a CLI verb today** (the router prints help + exit 1), so the smoke uses `help` / empty-stdin to prove standalone boot rather than adding a new CLI verb — the Refactor section forbids changing CLI command behavior in this ticket. A real `--version` verb is a candidate for the P8.09 CLI-trim ticket or a fast-follow.
- **Cold-start (sanity-timed).** Compiled `codogotchi-hook` steady-state ~0.05–0.06s vs today's `bun packages/cli/bin/codogotchi-hook.ts` ~0.07–0.09s (5 runs each, empty stdin; first run ~0.29s is FS-cache warmup). **No regression** — the compiled binary is marginally faster (no workspace module resolution at startup).
- **Signing/notarization (for the DMG ticket).** Despite the xcodegen `postBuildScripts` name, the embed phase runs **before** the target's CodeSign step (verified against the `xcodebuild` log: `PhaseScriptExecution Embed codogotchi binaries` precedes `CodeSign …Codogotchi.app`). So the embedded binaries are inside the bundle when it is signed: each binary is ad-hoc signed (`Signature=adhoc`) and `codesign --verify --deep --strict Codogotchi.app` passes. No phase reordering is needed for the seal to stay valid. What the DMG ticket still owns: Developer ID signing + notarization (not ad-hoc), and giving the nested binaries a stable code-signing identifier — the current ad-hoc identifier is `a.out`, which notarization will reject.
- **Bundle size.** Each `--compile` binary is ~61–64 MB (embedded Bun runtime); the app gains ~128 MB of embedded executables. Acceptable for a GitHub-Releases DMG; noted for the size-conscious if Intel/universal doubles it later.
