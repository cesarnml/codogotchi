# Post–Phase 04 floating pet fixes

Reference for agents and maintainers: what shipped **after** the Phase 04 ticket stack closed (`7b9c5fe` — advisory triage), as a series of `fix(phase-04):` commits on `main`. These are polish and parity fixes for the menubar floating pet, not new tickets.

**Commits:** `b414e48` … `01c1960` (newest first below).

**Primary surfaces:** `apps/menubar/Sources/FloatingPetPanel.swift`, `FloatingPetScene.swift`, `MaliPet.swift`, `FloatingInteractionPolicy` / `FloatingInteraction`, hide-prompt types in `FloatingPetPanel.swift`, `MenubarMenu.swift`.

---

## Fix index (newest → oldest)

| # | Commit | Summary |
|---|--------|---------|
| 14 | `01c1960` | Cache interaction rows — translate stutter |
| 13 | `be107a9` | Keyboard dismiss for hide pill |
| 12 | `e94e4f4` | Codex-style hide pill polish |
| 11 | `4475c0c` | Right-click hide pill |
| 10 | `19850c7` | Remove temp debug logging / frame outline |
| 9 | `d202a91` | Codex 1.5 s / Codogotchi ~4 s cycle speeds |
| 8 | `4046234` | Smooth translate drag + grab offset |
| 7 | `6c96eab` | Responsive running during drag |
| 6 | `043f32f` | Hover jumping + horizontal running |
| 5 | `f2d7598` | 256×256 cap; horizontal-only resize |
| 4 | `57e36a3` | Resize affordance overlay + hit testing |
| 3 | `4e7126f` | Affordance on hover + scale icon |
| 2 | `bdbc3f2` | Floating pet animates with menubar |
| 1 | `b414e48` | Native-resolution floating sprites |

---

## Fix 14 — Translate stutter on interaction row change (`01c1960`)

**Problem:** Dragging the floating panel was smooth while `runningLeft` / `runningRight` stayed stable, but **hitched** whenever the interaction row changed (L↔R, `jumping`→running, first drag after hover). Perf investigation showed `setInteraction` cost ~200 ms per swap while `setFrameOrigin` stayed &lt;1 ms — almost all time in `MaliPet.floatingFrames(forInteraction:)` re-slicing and rasterizing the full Codex row on the main thread in the same run-loop turn as the window move.

**Solution:**

- Pre-warm and cache floating interaction frame arrays in `MaliPet` at pet load (`floatingInteractionFrameCache` + `prewarmFloatingInteractionFrameCache()`).
- `setInteraction` returns early when `currentInteraction == interaction` (before frame lookup).
- Unit test: `testFloatingInteractionFramesReuseCachedBackingImages`.

**Do not reintroduce:** per-call sheet slicing for interaction rows on the drag hot path.

---

## Fix 13 — Hide pill keyboard dismiss (`be107a9`)

**Problem:** The “Hide pet” tooltip could stay visible over other apps after Cmd+Tab / Alt+Tab.

**Solution:** Global keyboard monitor (`keyDown` / `keyUp` / `flagsChanged`) dismisses the active hide prompt panel.

---

## Fix 12 — Hide pill Codex parity (`e94e4f4`)

**Problem:** Initial pill (Fix 11) did not match Codex placement, styling, or clipping behavior.

**Solution:**

- Label **“Hide pet”** (`FloatingPetHidePrompt.title`).
- Top-left anchor at click (no horizontal recenter past frame edge).
- Separate borderless `FloatingPetHidePromptPanel` in screen space (not clipped by pet bounds); `behindWindow` vibrancy; charcoal/blue gradients; hover state.
- Dismiss on outside click, deactivation, or hide action; refresh menubar toggle title.

---

## Fix 11 — Right-click hide pill (`4475c0c`)

**Problem:** No in-context way to hide the floating pet (Codex shows a hide affordance on right-click).

**Solution:** Right-click inside the frame shows a hide prompt; activates same path as menubar “Hide Floating Pet”; dismiss rules; block during active drag.

---

## Fix 10 — Remove investigation debug (`19850c7`)

**Problem:** Temporary `DebugLog` / `dbgLog` and a white debug frame outline were left from earlier tuning.

**Solution:** Delete `DebugLog.swift`, strip `dbgLog` calls, remove overlay outline. Animation cadence lives in Fix 9.

---

## Fix 9 — Animation cycle speeds (`d202a91`)

**Problem:** Codex-sheet cycles felt too fast (~1 s); Codogotchi sheet should stay ~4 s.

**Solution:**

- `MaliPet.animationCycleDuration` = 1.5 s full row; used in menubar and floating (including interaction rows).
- Codogotchi sheet keeps 167 ms/frame (~4 s for 24-frame rows).
- Restart interaction timer when jumping ↔ running changes frame count so per-row 1.5 s cadence holds.

---

## Fix 8 — Translate drag smoothness (`4046234`)

**Problem:** Panel jumped under cursor; vertical-only drag steps flashed wrong row; animation phase reset on interaction swaps.

**Solution:**

- Screen-space **grab offset** via `convertPoint(toScreen:)` + `setFrameOrigin` (not broken `frame.origin` deltas).
- `display: false` during translate; `displayIfNeeded` on mouseUp.
- Skip layout/tracking churn while translating.
- Hold `jumping` on vertical-only steps; preserve frame index for jumping→running and running↔running; stable `MaliPet.frameInterval` for codex interaction overlays.

---

## Fix 7 — Running row responsiveness (`6c96eab`)

**Problem:** Running direction followed cumulative drag instead of per-tick movement; vertical steps flipped row incorrectly.

**Solution:** `FloatingInteractionPolicy` uses **per-event** screen delta for L/R; hold current running row on vertical-only steps; preserve timer/frame index when flipping running rows.

---

## Fix 6 — Hover + horizontal drag interactions (`043f32f`)

**Problem:** No hover affordance animation; body drag did not map to reserved Codex rows.

**Solution:** `jumping` while pointer over frame (no drag); body drag maps to `runningLeft` / `runningRight` from horizontal delta only; centralized `emitInteraction`.

---

## Fix 5 — Size cap and resize behavior (`f2d7598`)

**Problem:** Panel could grow to 512×512; vertical resize stretched frame awkwardly.

**Solution:** `FloatingFramePolicy.maximumSize` = 256×256 pt; resize uses **horizontal delta only** for affordance drags; preserve aspect ratio (Codex-style).

---

## Fix 4 — Resize affordance restoration (`57e36a3`)

**Problem:** Affordance/hit testing misaligned after SpriteKit layering.

**Solution:** Dedicated `FloatingPetOverlayView` above SK; dual tracking areas + local mouse monitor; content view sized to panel; debug outline (removed in Fix 10).

---

## Fix 3 — Hover-only affordance (`4e7126f`)

**Problem:** Resize chrome always visible; L-bracket instead of scale cursor idiom.

**Solution:** Show bottom-right affordance only on hover or active resize; diagonal resize icon; uniform scale on horizontal/diagonal drags per policy.

---

## Fix 2 — Floating animation sync (`bdbc3f2`)

**Problem:** `FloatingPetScene` had no frame timer — sprite stuck on frame 0 while menubar cycled.

**Solution:** Timer-driven `tick()` loop aligned with `MenubarRenderer` cadence.

---

## Fix 1 — Sprite resolution (`b414e48`)

**Problem:** Floating pet used menubar-scaled frames (22 pt), so sprites looked soft/wrong in the larger panel.

**Solution:** `floatingFrames(for:)` / `floatingFrames(forInteraction:)` at **source-cell** resolution (`.sourceCell` output in `MaliPet` / `CodogotchiPet`); menubar keeps `.menubar` scaling.

---

## Agent notes

- **Prefix:** All commits use `fix(phase-04):` (not `phase-14`).
- **Reserved Codex rows:** Rows 1, 2, 4 — only floating `FloatingInteraction`; never `ActivityState` / menubar `rowMap`. See `docs/contracts/animation-state-vocabulary.md` and ticket P4.07.
- **Regression checks:** Drag translate with rapid L↔R (Fix 14), right-click hide pill + keyboard dismiss (Fix 11–13), hover jumping + resize affordance (Fix 3–6), menubar/floating animation sync (Fix 2, 9).
- **Investigation artifact:** Fix 14 perf logging was removed after verification; behavior is documented above under Fix 14.
