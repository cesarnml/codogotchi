# Phase 14 Draft — Extended Platform Hooks

_Drafted: 2026-05-27_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: [codogotchi-platform-extension-and-signal-pipeline-research.md](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md) §2.2–2.3, [multi-platform-hook-support.md](../../notes/public/multi-platform-hook-support.md)_

---

## Thesis

After **Cursor** (Phase 06), expand **lite** install to **VS Code GitHub Copilot Agent** and **Antigravity 2.0** with the same adapter pattern: truthful `source_origin`, tool alias tables, fixture-driven tests. Antigravity ships **only** with captured real stdin fixtures.

---

## The problem

- VS Code tool names differ from Claude (`create_file`, `replace_string_in_file`, …).
- Antigravity hook shape is research-only; Gemini CLI sunset June 2026 increases urgency to capture fixtures before betting schema.

---

## Committed scope

### 1. VS Code Copilot hooks (Preview)

- Installer for documented hook config paths
- `source_origin: vscode` (or `copilot`) in contracts
- Tool alias table: VS Code names → classify heuristics
- `workspace_roots` → SoA project root resolution

### 2. Antigravity 2.0

- `packages/engine/test/fixtures/hooks/antigravity/*.json` from real sessions
- Adapter + installer only after fixtures land
- Document IDE vs CLI vs SDK parity matrix

### 3. Installer UX

- `codogotchi hooks install --all` or per-platform flags
- Settings → Developer or Hooks section lists installed platforms (optional)

### 4. Parity matrix doc

- Table: platform × events × tool names × Codogotchi support level

---

## Defers

- Managed Agents API / cloud Antigravity policies (different hook shape)
- Tab hooks / non-agent Cursor events unless needed for animation

---

## Exit conditions

1. VS Code Copilot session produces `source_origin: vscode` and sensible `activity_state` on file edit + test run.
2. Antigravity fixture tests pass classification without network.
3. `hooks install` idempotent across four+ platforms.

---

## Dependencies

- **Phase 05** `hooks install`
- **Phase 06** adapter patterns + attention contract
- **Phase 07** optional for global gates (works per-platform once hooks fire)

---

## Next step

`/soa plan docs/product/drafts/phase-14-extended-platform-hooks.md`
