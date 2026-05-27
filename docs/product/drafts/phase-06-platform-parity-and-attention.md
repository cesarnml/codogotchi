# Phase 06 Draft — Platform Parity and Attention UX

_Drafted: 2026-05-27_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: [codogotchi-native-codex-pet-feature-parity-roadmap.md](../../notes/public/codogotchi-native-codex-pet-feature-parity-roadmap.md), [codogotchi-platform-extension-and-signal-pipeline-research.md](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md)_

---

## Thesis

**Lite mode** users should get **native Codex pet parity** on attention and platform coverage: why the pet wants you, TTL decay so poses do not stick, dismiss → badge, focus agent app, plus **Cursor** hook support (highest immediate audience). This phase does **not** require RPG enrollment.

Codogotchi already exceeds native on state vocabulary and SoA gates; the largest gap is **attention UX** and **honest platform attribution**. Cursor may already animate the pet today via the **Claude third-party hook bridge** (empty `~/.cursor/hooks.json` is not proof hooks are off); logs still mislabel that traffic as `claude_code`.

---

## The problem

- `requesting_input` / Codex `waving` can persist indefinitely — no `attention` payload or renderer TTL ([parity roadmap](../../notes/public/codogotchi-native-codex-pet-feature-parity-roadmap.md)).
- **Cursor already drives the pet for many users without any `~/.cursor/hooks.json` entry.** Cursor loads **Claude Code–compatible** hooks from `~/.claude/settings.json` when **Third-party skills** is enabled ([Cursor third-party hooks](https://cursor.com/docs/reference/third-party-hooks)). `codogotchi-hook` runs on Cursor Agent lifecycle events, but logs **`source_origin: claude_code`** because `rawHookOrigin()` treats camelCase (`preToolUse`) as non-Codex and defaults to Claude ([platform research](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md)). Tool names like **`Shell`** / **`Grep`** in `state-transitions.log` are the reliable Cursor fingerprint.
- Hook uses `command` for heuristics but does not persist it to `state.json` or transition log.
- Installers today only write **Claude Code** + **Codex** config; there is no first-class **`~/.cursor/hooks.json`** path yet.

---

## Committed scope

### 1. Attention contract (schema v2 extension or sibling)

Optional `attention` on `state.json` (or documented sibling file):

- `reason_kind`, `summary`, `created_at`, `expires_at` (or `ttl_ms`)
- Hook emits on `requesting_input`-class states; kinds for review ready, verification failed, etc. (starter set)

**Renderer policy:** if `expires_at < now` → show `idle` animation even when `activity_state` still says `requesting_input`.

### 2. Attention UI (Codex-like)

- Chat **bubble** near floating pet (and/or menubar) with short summary
- **Dismiss** → notification **badge** with count on menubar icon
- **Click** bubble/badge → focus best-effort target from `source_origin` (Codex, Cursor, VS Code when known)
- Works in **lite** and **alive** modes

### 3. Hook semantics + TTL

- Stable `reason_kind` + TTL heuristics per state (waiting on user: hours; errors: shorter; review: longer)
- `sessionEnd` / `stop` clears attention where platform sends it (Cursor)
- Fold **alignment-draft** hook hardening where still open: path resolution tests, tail/inode, five Phase 15 gate mappings, precedence matrix

### 4. Cursor platform adapter (v1)

**Two tracks — do not conflate:**

| Track | Status today | Phase 06 deliverable |
| --- | --- | --- |
| **A. Claude third-party bridge** | Works when Cursor **Third-party skills** is on and `~/.claude/settings.json` lists `codogotchi-hook` | Document in README/runbook; optional `hooks install` check for bridge vs native |
| **B. Native Cursor hooks** | `~/.cursor/hooks.json` often empty; not written by installer | Installer writes `~/.cursor/hooks.json` (or project `.cursor/hooks.json`) calling `codogotchi-hook --platform cursor` |

- `source_origin: "cursor"` in contracts + transition log (fix mis-label from bridge traffic)
- Normalize `Shell` / `afterFileEdit` / `workspace_roots[]` for classification and SoA root resolution (`CURSOR_PROJECT_DIR` / first workspace root)
- Document IDE vs Cursor CLI hook parity matrix; note bridge precedence in [Cursor hook priority](https://cursor.com/docs/reference/third-party-hooks) (native project/user hooks vs Claude user settings)

### 5. Signal logging (lite-visible)

- Persist `tool.command` on `state.json` and `state-transitions.log` for Bash/Shell
- Optional stub `work_mode` field in contract (populate later in Phase 07)

### 6. Bash idle gap (recommended)

- Unknown Bash/Shell → **`implementing`** fallback instead of `idle` when agent is clearly working (per platform research)

---

## Defers

- VS Code Copilot hook installer + tool alias table → **Phase 14**
- Antigravity without captured fixtures → **Phase 14**
- SoA direct write to `~/.codogotchi/` → **Phase 07** (upstream + reader)
- Full `work_mode: thinking | implementing | testing` taxonomy → **Phase 07**
- HUD hearts / XP → **Phase 08+** (RPG-gated)

---

## Exit conditions

1. “Stuck waving” resolved in manual test: attention expires to idle without new agent event.
2. Cursor-only session (native hooks **or** documented third-party bridge) logs `source_origin: cursor` and correct tool names in transition log — not `claude_code` for `Shell`/`Grep` traffic.
3. Bubble + dismiss + badge + focus flow demonstrated on macOS (runbook attestation).
4. Hook integration tests cover tail semantics and five SoA gate events through file-read pipeline.
5. Runbook explains empty `~/.cursor/hooks.json` vs working pet (bridge path) and when to prefer native install.

---

## Dependencies

- **Phase 05** lite install (hooks without Convex) should land first so parity testing does not require enroll.

---

## Cross-repo

- Son-of-Anton: optional; repo `.soa/events.ndjson` still consumed on hook fire. Global gate file is Phase 07.

---

## Open questions

1. Bubble on floating only vs menubar + floating?
2. Default TTL for `requesting_input` (2h vs 8h)?
3. Focus target when multiple IDEs open?
4. Ship native `~/.cursor/hooks.json` only, or also detect/advertise third-party bridge when Third-party skills is on?
5. If both bridge and native hooks fire, dedupe or define merge precedence in `codogotchi-hook`?

---

## Next step

`/soa plan docs/product/drafts/phase-06-platform-parity-and-attention.md`
