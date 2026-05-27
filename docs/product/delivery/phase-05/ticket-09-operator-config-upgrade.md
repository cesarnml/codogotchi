# P5.09 [Operator config upgrade (developer machine)]

Size: 1 point
Type: chore
Scope: operator
Red: skip

## Outcome

- Developer runs P5.08 upgrade script against real `~/.codogotchi/config.json` with `features.rpg_enabled: true` and all RPG fields preserved.
- `codogotchi sync` succeeds after upgrade (manual verification recorded in ticket Rationale).
- No changes committed that include secrets, tokens, or full config contents.
- PR contains only confirmation in Rationale (or checklist comment) that operator machine is on RPG schema — optional empty commit message reference.

## Red

- **`Red: skip`** — chore executed on developer machine; gate is human verification.

## Green

- Run upgrade script; fix script bugs in follow-up commit on same ticket branch if needed.
- Note backup path used before upgrade in Rationale.

## Refactor

- None.

## Review Focus

- Daily dogfood remains RPG after Phase 05 lands on main.
- Greenfield scripts (P5.08) still work for Lite testing without touching committed files.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

**Operator machine upgrade verified (2026-05-28)**

- Backup path: `~/.codogotchi/config.json.bak-p5.09-upgrade`
- Ran `bun scripts/operator/upgrade-phase-05-config.ts` from the P5.09 worktree against the real `~/.codogotchi/config.json`
- Config successfully upgraded: `features.rpg_enabled: true` added; all prior fields (handle, profile_id, github_username, health, convex_http_url) preserved
- `bun /path/to/packages/cli/bin/codogotchi.ts sync` → `sync ok errors=0 new_loot=0`
- No secrets or full config contents committed
