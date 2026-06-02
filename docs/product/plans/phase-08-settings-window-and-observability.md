# Phase 08: Settings Window and Observability

**Delivery status:** Shipped — Phase 08 complete. All 10 tickets delivered. Stack awaiting closeout.

## TL;DR

**Goal:** Replace JSON-and-Terminal onboarding with a **Settings window** that is the *only* user-facing control plane for mutating Codogotchi on disk, and **bundle the CLI inside the `.app`** so it is a self-contained drag-and-drop artifact — leaving the product with **Lite *and* SoA visualization fully supported** end to end.

**Ships:**

- Settings window shell (menubar → **Settings…**, standard macOS window) with the tabs that are functional this phase: **General**, **Pet**, **Developer**, **About**.
- **General tab** — hooks status summary + **Install / Update / Remove hooks** as the *sole* user-facing hook controls, executed through an **app-owned install API** (the app owns all writes).
- **Pet tab** — enumerate and select Codex built-in, custom, and bundled pets; **import-on-select** copies pet assets into `~/.codogotchi/pets/<id>/`. v1 ships **one fully-animated bundled pet, Maew** (the default when no Codex pet is imported).
- **First-run onboarding** — Settings → General auto-opens with an Install-hooks CTA (no wizard, no silent writes).
- **Developer tab (read-only)** — pretty-print `state.json` + the `gate.json` sidecar, schema-vs-renderer version line, per-platform hooks-present summary, a **last-5** `state-transitions.log` tail, and the Cursor-bridge explainer.
- **About tab** — app version, bundled hook-binary version, links.
- **Bundled `codogotchi` binary inside the `.app`** — self-contained, no PATH prerequisite; resolves from the bundle first, PATH only in dev builds.
- **Public CLI trimmed to read-only diagnostics** — `status`, `hooks status [--json]` remain; `setup`, `hooks install`, `hooks uninstall` removed/hidden (because the app now owns those writes).
- **Renderer loads the two real spritesheets** (`codogotchi-lite-spritesheet.webp` + `codogotchi-soa-spritesheet.webp`), replacing the single placeholder — making "SoA supported" real rather than a gray pet.
- **8-frame continuous-loop animation contract** (8 frames/row, `1.5s` loop, frame 1 ≈ frame 8); the 24-frame sheets move to a premium pack.

**Defers:**

- **RPG enroll wizard** + "Enable alive pet" CTA → **Phase 10** (first alive-only phase; enroll is its gateway). Carries the corrected enroll design: single shared Convex backend baked into the build; **no user-provided `convex_url`** — users supply a handle only.
- **Health tab** (`weekend_decay`, `grace_days`, death count, vacation status) → **Phase 11**.
- **Loot gallery tab** (read-only cards) → **Phase 13**.
- **Sparkle auto-update** → fast-follow stretch (ships only if the week has slack; otherwise a small standalone PR post-launch). Manual **Update hooks** button still ships this phase.
- **24-frame-per-row animation sheets** → premium pack (Phase 14); v1 ships the 8-frame contract.
- **`rpg` / `enroll` removal from the public CLI** → **Phase 10** (cannot trim until the in-app enroll replacement exists).
- BYOP full validation → Phase 13 (layout documented only). XPC-vs-in-process install-API transport → implementation detail. Log-verbosity write toggle → later (config-write surface).

---

Phases 05–07 still treat the `codogotchi` CLI as a shared *write* surface (`setup`, `hooks install`, config mutation) while the `.app` installs separately — a two-channel split that lets the hook binary and the menubar renderer drift, producing schema-mismatch gray failures. Phase 08 is the **Lite-and-SoA v1 release gate**: it closes that split for the product by making the app own all writes through an install API, bundling the CLI so the `.app` needs nothing on PATH, and shipping the two real spritesheets so the SoA visualization that Phase 07 wired up is actually visible. Hard prerequisite: **Phase 07** (schema v4 + `gate.json` sidecar + renderer merge) must land first.

## Phase Goal

This phase should leave the product in a state where:

- A **fresh machine with only `Codogotchi.app` in `/Applications`** — no `codogotchi` on PATH — completes onboarding and hook install entirely through Settings, and the pet renders full color with a matching schema (no `schemaNewer` desaturated failure).
- A **Lite user** installs / updates / removes hooks and selects a pet **from Settings only** — no JSON editing, no Terminal install steps in the README.
- A user running **son-of-anton** sees Maew react to review gates (the SoA spritesheet) **without enrolling and without Convex** — SoA visualization works for free because gate *rendering* is decoupled from RPG *enrollment*.
- The **Developer tab** answers "why does my pet react in Cursor when `~/.cursor/hooks.json` is empty?" without requiring external docs, and shows live `state.json` + `gate.json` read-only.
- The **public CLI `--help`** lists only read/diagnostic commands for the trimmed set (`setup` / `hooks install` / `hooks uninstall` gone); `rpg` / `enroll` remain until Phase 10 ships the in-app replacement.

## Committed Scope

### Settings window shell

- Menubar → **Settings…** opens a standard macOS window (not a tiny panel).
- Tabs shipped this phase: **General**, **Pet**, **Developer**, **About**. Alive-tier tabs (Health, Loot) and the enroll wizard are **not** present — no disabled/dead-end tabs.

### First-run onboarding

**Delivered decision (P8.10 reconcile):** The app keeps the existing **blocking welcome consent
sheet** from Phase 05 (re-pointed at the bundled binary). On first launch the sheet presents
**Approve & install hooks** — there is no skip. Settings → General is the *ongoing* control plane for
hook management after onboarding; it does not auto-open on first launch. This matches what shipped
and avoids the confusion of auto-opening a multi-tab settings window as the first user experience.
The "auto-open Settings" wording in earlier drafts of this plan was aspirational; the blocking
consent sheet was confirmed as the right call during implementation review.

- **Maew is the default pet**: if the user does not import one of their existing Codex pets, the bundled Maew is active out of the box, so the pet renders immediately after hook install.

### General tab — hooks write surface (app-owned)

- **Install hooks**, **Update hooks** (refresh hook binary + platform JSON to match this app build), and **Remove hooks** live **only** here (and the onboarding equivalents) — not in Terminal README flows.
- The UI calls the app's **install API**; it never tells the user to "run `codogotchi hooks install` yourself."
- Status display reuses the same JSON shape as `codogotchi hooks status --json`, populated by the app (read path). Optional **Copy diagnostics** for support.
- **Lockstep enforcement (launch detection + one-click).** On launch the app compares its **bundled hook version** to the **last-installed version** recorded in `app-state.json`; on mismatch *and* hooks-already-installed, it surfaces a **persistent, non-blocking banner** ("Hooks are out of date — Update") that runs the install-API upgrade. This is what makes "one lockstep upgrade path" *true* rather than aspirational — a bare manual button lets a freshly-updated app sit next to stale hooks (the exact drift this phase exists to kill). The app does **not** silently rewrite agent config dirs without consent; silent auto-upgrade is a post-v1 escalation.
- On schema mismatch (hook wrote a newer `schema_version` than this build understands — should not happen after the lockstep release), surface an in-app **Update Codogotchi** message rather than relying on the menubar tooltip alone.

### Pet tab

- Enumerate **Codex built-in** pets when `~/.codex/pets` is present, **custom** pets under `~/.codogotchi/pets`, and the **bundled** pet.
- **v1 ships exactly one bundled pet — Maew — fully animated** (88-frame lite + 80-frame SoA sheets). The tab architecture supports N pets; more are added post-launch. Maew is the default when no Codex pet is imported.
- On select: **copy** pet assets (`pet.json`, the lite + SoA spritesheets) into `~/.codogotchi/pets/<id>/`. Overwrite-vs-versioned-copy semantics resolved at decompose.

### Developer tab (read-only)

- Pretty-print `state.json` (refresh) and the **`gate.json` sidecar** (current gate, `since`, `expires_at`, live-vs-expired).
- **Last-5** `state-transitions.log` tail — a light realtime view of recent animations (source kind/name/origin/state), not full pagination.
- Show **renderer schema version** vs `state.json` `schema_version` when they differ (explains a gray pet without opening Finder); baseline after Phase 07 is **schema v4**.
- Per-platform **hooks-present** summary (derived from the same logic as `hooks status --json`).
- **Cursor-bridge explainer** — last-seen `source_origin` / tool name; native-vs-Claude-bridge guidance — satisfying the "empty `~/.cursor/hooks.json`" question in-app.

### About tab

- App version, **bundled hook-binary version** (pinned per release), product blurb, links.

### CLI bundling + install-API boundary

- Embed the `codogotchi` binary inside the app bundle so the `.app` is a fully self-contained drag-and-drop artifact with no PATH prerequisite. This closes the notarized-DMG distribution story.
- The app owns **all** writes through an install-API façade (Settings and onboarding call only this façade); the bundled binary is invoked by the app, not advertised as a user write surface. Resolution: bundle first, PATH fallback only in dev builds.
- Same TypeScript codebase as today's CLI; the release train ships **one** consumer artifact: `Codogotchi.app`.

### Public CLI read-only trim

- Retain `status` and `hooks status [--json]` (and future `logs tail` / `state dump`) as scriptable, support-friendly read commands.
- Remove or hide `setup`, `hooks install`, `hooks uninstall` — these now have in-app replacements.
- **Keep `rpg` / `enroll` on the public surface** until Phase 10 ships the in-app enroll wizard; removing them now would strand alive users with no enrollment path.

### Renderer two-sheet load + Lite/SoA support

- The renderer loads `codogotchi-lite-spritesheet.webp` (9 hook/lite states, with renderer-driven idle escalation) and `codogotchi-soa-spritesheet.webp` (10 SoA gate states), replacing the single placeholder. This is the load-bearing piece that makes "SoA supported" real.
- **Pre-delivery dependency (developer-owned):** the contact-sheet note `notes/public/codogotchi-lite-and-soa-spritesheet-contact-sheets.md` defining both sheets, validated 1:1 against the schema-v4 closed enum, must exist before delivery. ActivityState → row mapping updates accordingly.

### Animation contract (8-frame continuous loop)

- **v1 frame budget: 8 frames per animation row** (down from 24), `1.5s` per loop, **continuous playback for as long as the state is active** — this looping liveness (vs Codex's decay-to-idle after ~3 cycles) is the differentiator, not frame count.
- **Loop seam:** frame 1 ≈ frame 8 so the single animation loops cleanly.
- Roughly **88 frames per lite pet** (11 rows incl. idle escalation × 8) + **80 SoA frames** (10 rows × 8), stitched into the two sheets — sized to the GPT-image gen-art rate limit on the Codex plan.
- The **24-frame-per-row sheets become a premium offering** (Phase 14 premium animation pack); v1 free tier ships 8-frame.
- Renderer animation duration is set to `1.5s` to match this contract (and the Codex spritesheet cadence).

## Explicit Deferrals

- **RPG enroll wizard + "Enable alive pet" CTA → Phase 10.** Enroll is the gateway to alive mode and Phase 10 is the first alive-only phase. **Binding enroll-design note:** the Convex deployment is a single shared backend owned by the developer, baked into the app build as a compile-time constant — enroll collects a **handle (+ optional GitHub / WakaTime identifiers)** only and **never prompts for `convex_url`**.
- **Health tab → Phase 11.** Its knobs (`weekend_decay`, `grace_days`, death count, vacation) are health-tier and Phase 11 owns health visuals/decay; the tab is built there, not as a Phase 08 dependency.
- **Loot gallery tab → Phase 13.** Read-only gallery folds into the loot phase that also adds equip; building it in 08 would ship an alive-tier tab no Lite user touches.
- **Sparkle auto-update → fast-follow stretch.** Real setup cost is EdDSA key management, appcast hosting, and full update-cycle testing (~1–1.5 days), none of which a notarized-DMG-on-GitHub-Releases launch requires. Ships only with slack; manual **Update hooks** ships regardless.
- **`rpg` / `enroll` CLI removal → Phase 10**, gated on the in-app replacement existing.
- **BYOP full validation → Phase 13** (folder layout documented this phase). **Install-API transport (XPC vs in-process)** and **log-verbosity write toggle** are out of scope as added write surface / implementation detail.

## Exit Condition

A fresh Mac with only `Codogotchi.app` in `/Applications` and **no `codogotchi` on PATH** can be onboarded end to end from the Settings window: the user installs hooks, selects a pet, and the menubar/floating pet renders in full color at schema v4. The same Settings window can **Update** and **Remove** hooks. A developer running son-of-anton sees Maew animate through the review lifecycle on the SoA spritesheet with no enrollment and no Convex configured, and the Developer tab shows the live `state.json`/`gate.json` and explains the Cursor third-party-bridge attribution without external docs. The public CLI `--help` shows only read/diagnostic commands for the trimmed set (`setup` / `hooks install` / `hooks uninstall` absent); `rpg` / `enroll` remain pending Phase 10. The README and runbook say "Install Codogotchi.app; use Settings to enable hooks" — not "run `codogotchi hooks install`."

## Retrospective

`required` — Phase 08 changes the operator workflow (Settings replaces Terminal/JSON onboarding), introduces a durable architectural boundary (app-owns-writes via the install API; self-contained bundled artifact), and is the Lite-and-SoA v1 release gate. All three triggers (product-impact, architecture/process impact, durable-learning risk) apply. Add the retrospective to the final docs/exit ticket at decompose.
