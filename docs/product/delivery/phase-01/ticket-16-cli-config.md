# P1.16 CLI `codogotchi config`

Size: 2 points
Type: feat
Scope: cli

## Outcome

- `codogotchi config get <key>` prints the value at the dotted key path (e.g. `health.weekend_decay`).
- `codogotchi config set <key> <value>` writes the value at the dotted key path, validating type (bool / number / ISO date string) against the config schema. Refuses unknown keys.
- `codogotchi config list` prints the full config as formatted JSON (with credentials redacted: PAT and Wakatime key shown as `<set>` or `<unset>`).
- Writes are atomic (write-to-temp + rename).
- Config schema lives in `packages/contracts/src/config.ts` as a zod schema; `config set` validates against it.
- Tests cover: get/set/list happy paths, unknown key refusal, type validation refusal, credential redaction in `list`, atomic write under simulated interruption.

## Red

- Write failing tests for each subcommand.
- Commit: `test(P1.16): codogotchi config get/set/list [red]`.

## Green

- Implement subcommands. Reuse zod schema for validation.

## Refactor

- Extract dotted-path get/set helper if not already in the engine's pure utils.
- Only refactor what this ticket touches.

## Review Focus

- Credential redaction in `list` is genuine — reviewer confirms no PAT/Wakatime-key bytes appear in `list` output even when set.
- Unknown-key refusal works — `config set foo.bar baz` exits non-zero with a clear message.
- Type validation: `config set health.weekend_decay yes` refuses; `config set health.weekend_decay true` succeeds.
- Atomic write: confirm partial writes do not corrupt config on simulated interrupt (kill mid-write).
- Schema is authoritative; CLI does not allow keys the schema does not know about.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

- **Schema lives in `packages/contracts/src/config.ts`** as `codogotchiConfigSchema` (zod) plus `SETTABLE_TOP_LEVEL`/`SETTABLE_HEALTH_KEYS` allow-lists. `resolveConfigPath` is the authoritative dotted-path resolver — anything it returns `null` for is unknown or intentionally read-only.
- **`profile_id` is read-only.** `config get profile_id` works; `config set profile_id …` is refused. Rotating it would orphan the server-side profile.
- **Atomic writes.** Reuses `writeConfig` (tmp + rename). Kill mid-write leaves either previous or new content; never partial.
- **Type validation:** bool (exactly `true`/`false`), non-negative finite number, ISO date or `"null"`, non-empty string, https URL with trailing slash strip, nullable secrets via the `"null"` literal.
- **`list` redaction** renders `github_token` and `wakatime_key` as `"<set>"` when populated, `null` when not. No secret bytes appear in output.
- **`config get` output:** strings bare, non-strings as JSON.

- **Schema lives in `packages/contracts/src/config.ts`** as `codogotchiConfigSchema` (zod) plus an allow-list of `SETTABLE_TOP_LEVEL` and `SETTABLE_HEALTH_KEYS` keys. `resolveConfigPath` is the authoritative dotted-path resolver — anything it returns `null` for is unknown or intentionally read-only (e.g. `profile_id`).
- **`profile_id` is read-only.** `config get profile_id` works (so users can copy it for support); `config set profile_id …` is refused with `Unknown or read-only config key`. Rotating `profile_id` would orphan the server-side profile, so this is deliberate.
- **Atomic writes.** `configSet` uses the existing `writeConfig` from P1.12, which writes to `${target}.tmp-<pid>-<ts>` and `rename`s. A kill mid-write leaves either the previous good content or the new good content — never a partial JSON document.
- **Type validation per field.**
  - Booleans (`health.weekend_decay`): accepts exactly `"true"` / `"false"`; anything else rejected.
  - Numbers (`health.grace_days`, `health.decay_per_day`, `health.revive_threshold`, `health.revive_hp`): finite non-negative; rejects `nope` and `-5`.
  - Nullable date (`health.vacation_until`): accepts ISO date string or the literal `"null"`/`""` to clear; normalizes to `Date.toISOString()`.
  - Required string (`health.timezone`, `handle`): non-empty.
  - URL (`convex_http_url`): must be `https://`; trailing slashes stripped.
  - Nullable secrets (`github_token`, `github_username`, `wakatime_key`): the literal `"null"` clears the field; otherwise stored verbatim.
- **Credential redaction in `list`.** PAT and Wakatime key render as `"<set>"` when present and `null` when unset. No PAT/Wakatime bytes appear in output. Other config fields are passed through as-is.
- **`config get` output.** Strings print bare; non-string values print as JSON (so `health.grace_days` → `2`, `health.weekend_decay` → `false`, `health` (whole object) → JSON).
- **Subagent review.** Code ticket; subagent runs.
