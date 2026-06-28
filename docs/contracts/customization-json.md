# customization.json Contract

`~/.codogotchi/customization.json` is an optional user-owned config file that controls per-platform floating pet display and idle-dismiss behavior. Introduced in Phase 13 (app v2.0.0).

## File location

`~/.codogotchi/customization.json`

The file is absent until the user first changes a customization setting via **Settings > Customization** (or **Settings > General** for the monochrome icon toggle). Absence means all defaults apply.

## Schema

```json
{
  "schema_version": 1,
  "platform_modes": {
    "claude_code": "own",
    "codex": "combined",
    "cursor": "off"
  },
  "idle_dismiss_ttl_seconds": 300,
  "menubar_icon_monochrome": false
}
```

### Fields

| Field | Type | Default (absent) | Description |
|---|---|---|---|
| `schema_version` | integer | 1 | Always `1`. Present when the file is written by the app. |
| `platform_modes` | object | `{}` | Per-platform display mode. Keys are `SourceEventOrigin` raw values. Absent origins default to `"own"`. |
| `idle_dismiss_ttl_seconds` | number | `300` | Seconds before an idle platform's floating window is auto-dismissed. `0` = Never. |
| `menubar_icon_monochrome` | boolean | `false` | When `true`, the status-item icon renders as a monochrome template (adapts to light/dark menu bar). When `false`, full-color. |

### Platform mode values

| Value | Meaning |
|---|---|
| `"own"` | Platform drives its own independent floating pet window (default). |
| `"combined"` | Platform's state folds into the shared combined-mode window via `globalAggregate`. |
| `"off"` | Platform is invisible — its slices are filtered before any reducer runs. |

### Valid `platform_modes` keys

The set of valid keys is the `SourceEventOrigin` closed enum: `claude_code`, `codex`, `cursor`, `vscode`, `antigravity`. Unknown keys are ignored by the Swift reader.

## Write contract

The file is written via **read-merge-write**: the writer reads the existing file (if present), merges in the changed key(s), and writes atomically. Individual key writes do not clobber unrelated keys. If the existing file is unreadable or invalid JSON, the write is aborted (the UI shows the previous value).

`schema_version` is seeded to `1` when the file does not yet exist and is never changed by the app.

## Reader contract

The Swift `CustomizationJsonReader` returns a `CustomizationSnapshot` with all defaults applied when:
- The file is absent, or
- Any field is missing from the JSON object.

The TypeScript `CustomizationJsonSchema` (Zod, in `packages/contracts`) is the canonical schema for CLI-side reads. Defaults are identical.

## Phase 14 forward note

Per-thread (per-`session_id`) window mode and `SessionIdPanel` UI are deferred to Phase 14. If Phase 14 requires new fields in `customization.json`, it will bump `schema_version` to `2` and document the migration here.
