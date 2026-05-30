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
Contract note:
