# P5.01 Lite/RPG config schema + CLI guards

Size: 2 points
Type: feat
Scope: cli-config
Red: required

## Outcome

- `CodogotchiConfig` includes `features: { rpg_enabled: boolean }` and optional `pet?: string` (default `"maew"` when writing Lite seed).
- Greenfield Lite config shape is valid: `{ profile_id, pet, features: { rpg_enabled: false } }` with **no** `handle`, `convex_http_url`, `github_*`, `wakatime_key`, or `health` keys required.
- When `rpg_enabled === true`, existing RPG field requirements apply (handle, convex URL, etc.).
- **No** product-code branch that treats missing `features` as RPG enabled (operator upgrade is P5.09 only).
- `sync`, `loot`, `vacation`, and other RPG commands exit non-zero with a clear message pointing to `codogotchi rpg` when `rpg_enabled === false`.
- `config set` refuses RPG-only keys when Lite (or documents allowed Lite keys only).

## Red

- Write failing tests: Lite config round-trip read/write; RPG command refusal when `rpg_enabled: false`; RPG command allowed when `true`.
- Write failing test: config without `features` is rejected or unreadable in product paths (no implicit RPG).
- Run `bun test` for `packages/cli` and confirm new tests fail.
- Commit: `test(P5.01): lite rpg config schema and guards [red]`.
- Do not implement until the `[red]` commit exists.

## Green

- Extend `packages/cli/src/config.ts` types and validation.
- Add guards at router entry points for RPG commands.
- Update `config set` / `config list` redaction behavior if needed for omitted keys.

## Refactor

- Keep Convex package types unchanged (no schema migration in this phase).
- Do not add a public `migrate` command.

## Review Focus

- Lite users never hit Convex via CLI by accident.
- Operator's pre-upgrade config is untouched until P5.09; P5.01 must not auto-migrate on read.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
