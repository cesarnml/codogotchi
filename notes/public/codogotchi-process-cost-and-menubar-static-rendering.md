# Codogotchi process cost, Cursor helpers, and menubar static rendering

Date: 2026-05-27 (research); updated 2026-05-28 (shipped)  
Status: **Shipped** on `main` — `892bc69` (static menubar), `8a5b5e8` (pause float + gate App Nap)  
Related: [codogotchi-platform-extension-and-signal-pipeline-research.md](./codogotchi-platform-extension-and-signal-pipeline-research.md), [phase-04 validation runbook](../../docs/runbooks/phase-04-validation.md), [apps/menubar/README.md](../../apps/menubar/README.md)

---

## Executive summary (shipped behavior)

| Surface | Rendering | CPU (dev Mac, Activity Monitor, filter `codo`) |
| --- | --- | --- |
| **Menubar** | Static **hero frame** (`heroFrameIndex = 3`, clamped per row); repaints only when `activity_state` or `visual_mode` changes | Part of menubar-only baseline |
| **Floating pet (visible)** | Full SpriteKit frame loop + mouse interaction rows | **~5%** Codogotchi process (typical) |
| **Floating pet (hidden)** | Timer **paused**, `SKView.isPaused = true`, App Nap opt-out **ended** | **~0.5%** Codogotchi process (typical) |

The hook pipeline (`codogotchi-hook` → `~/.codogotchi/state.json`, polled at **1 Hz**) is cheap. Steady CPU was **hidden float still animating** and **global `beginActivity(.latencyCritical)`**, not the 1 Hz read.

**Product:** Menubar shows which state is active without jittery 22pt flipbook motion; float carries motion. Show/hide float remains snappy.

---

## 1. Cursor “extension-host codogotchi” vs Codogotchi.app

Activity Monitor may show:

- **Codogotchi** — native `Codogotchi.app` (menu bar + optional floating pet).
- **Cursor Helper (Plugin): extension-host codogotchi [1-N]** — Cursor’s extension host processes, named after the **workspace folder** (`codogotchi`), not a Codogotchi VS Code extension.

Integration path:

```
Cursor Agent → hooks → codogotchi-hook → ~/.codogotchi/state.json → Codogotchi.app
```

**Quitting Cursor** ends extension-host helpers. **Codogotchi.app** keeps running until quit separately.

---

## 2. What shipped (May 2026)

### 2.1 Static menubar (`892bc69`)

- `MenubarRenderer`: no frame `Timer`; paints hero frame once per `(state, mode)` change.
- `LivePollingDriver`: caches last rendered `(state, mode)` — no fanout when unchanged.
- `CODOGOTCHI_DEMO_FRAME_MS` affects **floating pet only** (debug).

### 2.2 Pause float when hidden (`8a5b5e8`)

- `FloatingPetScene.pauseAnimation()` / `resumeAnimation()` on hide/show.
- `FloatingPetInteractionView.setSpriteKitPaused(_:)` — `skView.isPaused` while hidden.
- `MenubarApp.setFloatingPetAppNapOptOut(active:)` — `beginActivity(.latencyCritical)` **only while float is visible**.

Key files: `MenubarRenderer.swift`, `LivePollingDriver.swift`, `FloatingPetScene.swift`, `FloatingPetPanel.swift`, `FloatingPetController.swift`, `MenubarApp.swift`.

---

## 3. Empirical findings (conversation + validation)

| Scenario | Codogotchi CPU (approx.) | Notes |
| --- | --- | --- |
| Pre-static menubar + float | ~7% idle; ~26% drag torture | Debug/Xcode build |
| Static menubar + float visible | ~5–6% | Menubar static saved **~1–2%**, not ~5% |
| Static menubar + float **hidden** (before pause fix) | ~4–5% | Hide only `orderOut` — timer kept running |
| Static menubar + float **hidden** (after pause fix) | **~0.5%** | Pause + App Nap gate |
| Float visible after pause fix | ~5% | Animation + opt-out restored on show |

**Misread corrected:** 1 Hz polling is **not** the main CPU hog. Unchanged state does not repaint after cache + static menubar. The cost was **off-screen animation** and **process-wide wake policy**.

---

## 4. Comparison to other 24/7 menubar tools

Qualitative — Codogotchi **menubar-only + float hidden** now behaves like Wakatime/CodexBar (low idle). **Float visible** is closer to a small always-on game loop (~5%).

---

## 5. Future optimizations (not shipped)

- **FSEvents** on `state.json` instead of 1 Hz timer (minor; wake policy was the issue).
- Focus-aware auto-hide float (phase deferral).
- Release build vs Debug for fair Codex comparison.

---

## 6. Open questions

- ~~Hero frame vs middle frame~~ → `heroFrameIndex = 3`.
- ~~Gate App Nap on float visibility~~ → shipped `8a5b5e8`.
- Release vs Debug CPU baseline for runbook?
