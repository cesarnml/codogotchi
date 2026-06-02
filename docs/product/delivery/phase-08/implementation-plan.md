# Phase 08 — Settings Window and Observability

> Make the `.app` the self-contained, app-owned control plane: bundle a compiled `codogotchi` so there is no PATH prerequisite, expand the Settings window into a 4-tab control surface (install/update/remove hooks, pet selection, read-only observability), enforce hook/renderer lockstep, and ship Maew's real two-sheet 8-frame animations so Lite **and** SoA visualization work end to end.

## Epic

Standalone phase — the **Lite-and-SoA v1 release gate**. Source product plan: [`docs/product/plans/phase-08-settings-window-and-observability.md`](../../plans/phase-08-settings-window-and-observability.md). Hard prerequisite **delivered**: Phase 07 (schema v4, `gate.json` sidecar, renderer gate-consumer, pure hook classifier) is on `main`. Pre-delivery developer artifact: the two Maew spritesheets generated per [`notes/private/codogotchi-8frame-lite-soa-sheet-prompts.md`](../../../notes/private/codogotchi-8frame-lite-soa-sheet-prompts.md).

## Product contract

When this phase is complete:

- A fresh Mac with only `Codogotchi.app` in `/Applications` and **no `codogotchi` on PATH** onboards end to end from the app: install hooks, pick a pet, pet renders full-color at schema v4.
- Install / Update / Remove hooks are app-owned (Settings → General), executed against the **bundled** binary; the README no longer tells users to run `codogotchi hooks install`.
- A developer running son-of-anton sees Maew animate through the review lifecycle on the **real SoA sheet** with no enrollment and no Convex.
- The Developer tab shows live `state.json` + `gate.json`, the last 5 transitions, the schema-vs-renderer version, and answers the Cursor empty-`hooks.json` question in-app.
- `codogotchi --help` lists only read/diagnostic commands plus `rpg`/`enroll`; `setup`/`hooks install`/`hooks uninstall` are hidden (still callable by the app internally).

## Grill-Me decisions locked

| Decision | Rationale |
| --- | --- |
| `bun build --compile` standalone binaries, **arm64-only**, **two** binaries (`codogotchi` + `codogotchi-hook`) | No binary exists today (TS-via-Bun); arm64 matches the 2026 dev audience and avoids cross-compile/lipo under the deadline; two binaries match the two existing `bin` entries. Intel/universal is a documented fast-follow with a clean unsupported-arch message |
| Compiled binary **self-locates** its sibling `codogotchi-hook` via `process.execPath` and writes the **absolute bundled path** into platform JSON | Self-contained hooks with no PATH; the app owns the path. Dev build (no bundle) falls back to the bare `codogotchi-hook` name |
| `defaultRunner` resolves the bundled binary first, PATH fallback **dev-only** | Closes the two-channel split; users never depend on PATH |
| **`Update hooks` = idempotent re-install** (no new CLI verb) | `installHooks` already rewrites platform JSON idempotently; "update" just re-runs it against the current bundle's path |
| **CLI trim = hide-from-`--help`, not remove** | The app's install API still invokes `hooks install`/`uninstall` as subprocesses; removing them would break the app |
| Keep `rpg`/`enroll` on the public CLI | No in-app enroll replacement until Phase 10; removing them now strands alive users |
| Keep the existing **blocking welcome consent sheet** for first run (re-pointed at the bundled binary) | It works, forces the one required action, and is not the "big wizard" the plan warned against; Settings→General owns ongoing hook controls. The product plan's "auto-open Settings" wording is reconciled in P8.10 |
| Pet import keeps **overwrite-with-rollback-backup** (`PetImportHelper` already does this) | Safe; the canonical store is a copy, not an edit surface — no versioned-copy complexity |
| Lockstep compares a **build/generation version the binary reports**, recorded in `app-state.json` (`installedHookVersion`, schema 1→2) | A concrete token to compare on launch; a persistent banner (not silent rewrite) delivers lockstep with consent |
| **Sparkle auto-update deferred** (fast-follow stretch) | EdDSA keys + appcast + update-cycle testing aren't needed for a notarized-DMG-on-GitHub-Releases launch |

## Ticket Order

1. `P8.01 Compile standalone binaries + Xcode bundle-embed`
2. `P8.02 Bundle-first resolution + absolute hook path`
3. `P8.03 Settings shell → 4-tab window + About`
4. `P8.04 General tab — app-owned hooks façade (install/update/remove)`
5. `P8.05 Lockstep — installedHookVersion + launch detection + banner`
6. `P8.06 Maew two-sheet assets + 8-frame renderer loader`
7. `P8.07 Pet tab — enumerate/select/import + Maew default`
8. `P8.08 Developer tab — read-only observability`
9. `P8.09 Public CLI read-only trim`
10. `P8.10 Docs + retrospective`

## Ticket Files

- `ticket-01-compile-bundle-binaries.md`
- `ticket-02-bundle-first-resolution-absolute-hook-path.md`
- `ticket-03-settings-four-tab-shell.md`
- `ticket-04-general-tab-hooks-facade.md`
- `ticket-05-lockstep-version-banner.md`
- `ticket-06-two-sheet-renderer-loader.md`
- `ticket-07-pet-tab.md`
- `ticket-08-developer-tab.md`
- `ticket-09-cli-readonly-trim.md`
- `ticket-10-docs-retrospective.md`

## Exit Condition

Phase 08 is done when a fresh Mac with only `Codogotchi.app` in `/Applications` (no `codogotchi` on PATH) onboards via the welcome sheet, installs hooks against the bundled binary, and renders Maew full-color at schema v4; Settings → General can Install/Update/Remove hooks through the app-owned façade and shows a persistent banner when the bundled hook version is newer than the installed one; the renderer loads `codogotchi-lite-spritesheet.webp` and `codogotchi-soa-spritesheet.webp` (8 frames/row, 1.5s loop) with no Phase 07 placeholder rows; the Pet tab enumerates/imports/selects pets with Maew default; the Developer tab shows live `state.json`/`gate.json`, the last 5 transitions, the schema-vs-renderer version, and the Cursor-bridge explainer; `codogotchi --help` hides `setup`/`hooks install`/`hooks uninstall` (still callable) while keeping `status`/`hooks status`/`rpg`/`enroll`; and the docs say "install Codogotchi.app; use Settings to enable hooks."

## CI Baseline

> Baseline recorded: 2026-05-30 — `bun run ci:quiet` green on `main` (exit 0): biome clean, TS suite passes, Swift `mac:test` 247 tests / 0 failures. No pre-existing failures.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- CI includes Swift `mac:test` — Settings/renderer tickets must keep it green.
- The absolute-hook-path writer (P8.02) and its consumer (the platform JSON the agent runs) are two sides of one boundary — verify the path the binary writes is the path the agent actually spawns.

## Explicit Deferrals

- **Sparkle auto-update** — fast-follow stretch; manual Update hooks ships this phase.
- **Universal / Intel binaries** — arm64-only for v1; documented unsupported-arch message, universal is a follow-up.
- **RPG enroll wizard, Health tab, Loot gallery** — Phases 09 / 10 / 12 respectively; `rpg`/`enroll` stay on the CLI until 09.
- **24-frame animation pack** — premium (Phase 14); v1 ships 8-frame.
- **BYOP full validation** — Phase 13 (layout documented only).
- **Log-verbosity write toggle**, **XPC vs in-process transport** — out of scope.

## Stop Conditions

- **P8.06 is blocked until the two Maew sheets are committed** (developer pre-delivery artifact). Do not invent art or ship placeholder rows as final.
- `bun build --compile` cannot produce a runnable arm64 binary that boots inside the bundle — escalate (the whole self-contained story depends on P8.01).
- Hook cold-start regression: if the compiled `codogotchi-hook` adds material latency per agent event vs today's `bun bin/codogotchi-hook.ts`, flag before proceeding.
- Broken CI that cannot be resolved within the ticket scope (incl. Swift `mac:test`).

## Phase Closeout

Retrospective: required
Why: Phase 08 changes the operator workflow (Settings replaces Terminal/JSON onboarding), introduces a durable architectural boundary (app-owns-writes via a bundled binary + install façade), and is the Lite-and-SoA v1 release gate. The compile/bundle pipeline and lockstep mechanism will generate follow-up decisions (universal binaries, Sparkle, silent auto-upgrade).
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-08-settings-window-and-observability-retrospective.md`
