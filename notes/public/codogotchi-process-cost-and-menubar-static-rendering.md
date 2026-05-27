# Codogotchi process cost, Cursor helpers, and menubar static rendering

Date: 2026-05-27  
Status: Research / product direction (conversation artifact, not shipped)  
Related: [codogotchi-platform-extension-and-signal-pipeline-research.md](./codogotchi-platform-extension-and-signal-pipeline-research.md), [codogotchi-native-codex-pet-feature-parity-roadmap.md](./codogotchi-native-codex-pet-feature-parity-roadmap.md), [phase-04 validation runbook](../../docs/runbooks/phase-04-validation.md)

---

## Executive summary

Codogotchi’s macOS app is **modest in absolute CPU** but **heavy for a menubar utility** because it **animates continuously** (menubar flipbook + optional floating `SKView`) and opts out of **App Nap** via `ProcessInfo.beginActivity(.userInitiated, .latencyCritical)`. The hook pipeline (`codogotchi-hook` → `~/.codogotchi/state.json`, polled at **1 Hz**) is cheap; the animation timers are not.

**Recommended long-term split:**

| Surface | Role | Rendering |
| --- | --- | --- |
| **Menubar** | Glanceable state glyph | **Static** — middle frame of the active row; repaint only when `activity_state` or `visual_mode` changes |
| **Floating pet** | Desktop companion | **Full animation loop** — keep current `FloatingPetScene` timer + mouse interactions |

**Demo mode** (`CODOGOTCHI_DEMO=1`, `--demo`) is a **developer debug affordance**, not a product feature. Production behavior should not be shaped around demo animation requirements.

---

## 1. Cursor “extension-host codogotchi” vs Codogotchi.app

Activity Monitor may show:

- **Codogotchi** — native `Codogotchi.app` (menu bar + optional floating pet).
- **Cursor Helper (Plugin): extension-host codogotchi [1-N]** — Cursor’s extension host processes, named after the **workspace folder** (`codogotchi`), not a Codogotchi VS Code extension.

This repo ships **Swift menubar app + CLI/hooks**, not a Cursor/VS Code extension manifest.

Integration path:

```
Cursor Agent
  → lifecycle hooks (or third-party Claude hook bridge)
  → codogotchi-hook
  → ~/.codogotchi/state.json
  → Codogotchi.app (poll + render)
```

**Quitting Cursor** (Cmd+Q) should end extension-host helpers. **Codogotchi.app** keeps running until quit separately.

---

## 2. Process cost analysis (CPU / GPU / energy)

### 2.1 What the app does today

| Work | Cadence | Cost character |
| --- | --- | --- |
| Read `state.json` | 1 Hz (`LivePollingDriver`) | Tiny |
| Menubar sprite updates | ~5–6 fps (`MenubarRenderer` `Timer`) | Sustained CPU |
| Floating pet | Same flip rate + transparent `SKView` / SpriteKit | Higher CPU + compositor/GPU |
| Transition log heartbeat | 1/hour | Negligible |
| App Nap opt-out | Always while app runs | Energy tax |

Key code:

- Polling: `apps/menubar/Sources/LivePollingDriver.swift` (`tickInterval` default 1.0s).
- Menubar animation: `apps/menubar/Sources/MenubarRenderer.swift` — restarts timer on state change and **keeps looping** in steady state.
- Floating animation: `apps/menubar/Sources/FloatingPetScene.swift` — `Timer` per frame interval (~167 ms codogotchi sheet, ~1.5s cycle / frame count for Codex rows).
- App Nap: `apps/menubar/Sources/MenubarApp.swift` — `beginActivity(options: [.userInitiated, .latencyCritical], reason: "codogotchi menubar pet animation")` so menubar timers are not throttled (LSUIElement agents are prime App Nap targets).

Frame intervals (production):

- Codex sheet: `CodexPet.animationCycleDuration` (1.5s) / frame count.
- Codogotchi sheet: `CodogotchiPet.frameInterval` (~167 ms/frame, 24-frame rows).

### 2.2 Stance (May 2026)

- **vs Cursor + LLM work:** Codogotchi CPU is noise.
- **vs other menubar utilities:** Noticeable — continuous animation + latency-critical activity.
- **vs the feature (mirror a JSON file):** Overbuilt at idle — information could be static between hook events.

Observed on one dev machine (Activity Monitor, filtered “codo”): **Codogotchi ~7% CPU**, Energy Impact ~3.5, with floating pet likely visible. Plausible for menubar + float + always-on animation; not profiled with Instruments.

---

## 3. Comparison to other 24/7 processes

Qualitative ranking for **steady CPU** on a typical dev Mac (not instrumented on a specific machine):

**Lower idle CPU (typical):**

- **Tailscale** — network daemon; near 0% until traffic/handshakes.
- **Wakatime (menubar)** — periodic API sync; static icon between syncs.
- **CodexBar** — provider quota polling on refresh presets (manual → 15m); bursts, not continuous flipbook.
- **Amphetamine (process only)** — menubar agent is tiny; **real cost is indirect** (sleep/display assertions).

**Mid / config-dependent:**

- **Codogotchi** (menubar + float, current build) — sustained low-fps animation + App Nap opt-out.
- **iStat Menus** — sensor/graph widgets on timers; fair peer for “live menubar,” cost scales with widgets.
- **Vivid** — low menubar CPU; cost is **display/HDR pipeline**, not file polling.

**Different shape (not CPU-comparable):**

- **OrbStack** — VM/hypervisor baseline; **RAM** and container spikes dominate.

**Dominates battery without high CPU%:**

- **Amphetamine** when it prevents system sleep.

Codogotchi is the outlier among menubar companions: peers **poll → update → sleep**; Codogotchi **polls → animates forever** even when `activity_state` is unchanged.

---

## 4. Recommended product / engineering direction

### 4.1 Menubar: static state glyph

On `activity_state` or `visual_mode` change only:

1. Resolve frames (`MenubarRenderer.resolveFrames`).
2. Set frame index to **middle of row**: `frameCount / 2` (integer division; works for 8-frame Codex rows and 24-frame Codogotchi rows).
3. `paintCurrent()` once.
4. **Do not** start or restart menubar `Timer` in production.

Repaint triggers:

- `activity_state` change (from 1 Hz poll or `pollNow` after wake).
- `visual_mode` change (e.g. desaturated failure glyph).
- Pet asset reload (future).

No repaint when poll sees unchanged state.

### 4.2 Floating: keep full loop

No change to `FloatingPetScene` timer behavior for production. Mouse-reactive Codex rows (`running-right`, `running-left`, `jumping`) remain float-only.

`PetStateFanout` already fans `(state, visualMode)` to menubar and float separately — menubar static mode is mostly `MenubarRenderer` + App Nap policy.

### 4.3 App Nap / `beginActivity`

Today justified for steady menubar timer cadence. After menubar static:

- **Remove** latency-critical activity for menubar-only use, **or**
- Gate `beginActivity` on **floating pet visible** (and/or float actively animating).

### 4.4 Demo mode (debug only)

Activation: `CODOGOTCHI_DEMO=1`, `--demo`, sandbox `$TMPDIR/codogotchi-demo/state.json`, `DemoCycleDriver` cycles all 15 states. Optional `CODOGOTCHI_DEMO_FRAME_MS` for fast frame inspection.

**Not** a shipped product surface. For static menubar implementation:

| Option | Behavior |
| --- | --- |
| **A (preferred)** | Demo uses same static menubar as production; validates state switching + fanout |
| **B (opt-in)** | Fast menubar flipbook only when `CODOGOTCHI_DEMO_FRAME_MS` set — sprite QA only |

Do not keep production menubar animated because demo exists.

### 4.5 Deferred / separate

- Focus-aware hide for floating pet (phase plan deferral) — largest UX win for “pet only when coding.”
- Pause `SKView` between float frames / `preferredFramesPerSecond` — second-pass GPU savings.
- Optional one-shot menubar crossfade on state change — polish, not required for v1.

---

## 5. Implementation sketch (when scheduled)

1. **`MenubarRenderer`** — remove steady-state timer; middle frame on `resolveFrames`; paint once per state/mode change.
2. **`MenubarApp`** — narrow or remove `beginActivity` per §4.3.
3. **Tests** — update `MenubarRenderer` tests that advance frames via timer; add “unchanged state does not repaint” if sink is instrumented.
4. **Contracts / docs** — menubar = static glyph, float = animated (animation-state vocabulary or runbook).

No change required to `LivePollingDriver`, hook binary, or `PetStateFanout` shape.

---

## 6. Validation ideas

1. Hide floating pet → CPU should drop sharply if SpriteKit/compositing was significant.
2. Quit Codogotchi vs quit Cursor — extension hosts vs app CPU separate.
3. Instruments: 10 minutes menubar-only vs float-on vs app quit (after static menubar ships).

---

## 7. Open questions

- Should menubar static use **exact** middle frame or “hero” frame per state (product art decision)?
- Gate App Nap only when float visible, or also when float animating (interaction overlay active)?
- Document in user-facing README or keep cost notes dev-only?
