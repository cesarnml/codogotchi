# P5.08 Operator scripts (upgrade + greenfield)

Size: 2 points
Type: chore
Scope: operator
Red: skip

## Outcome

- `scripts/operator/backup-rpg-home.sh` — copies `~/.codogotchi` → `~/.codogotchi.rpg-backup-<timestamp>`; documents optional hook JSON backup.
- `scripts/operator/enter-lite-greenfield.sh` — runs backup if user confirms; removes `~/.codogotchi`; does **not** auto-uninstall hooks (document optional `codogotchi hooks uninstall`).
- `scripts/operator/restore-rpg-home.sh` — restores from chosen backup directory.
- `scripts/operator/upgrade-phase-05-config.ts` (or `.sh`) — reads developer config, writes schema with `features.rpg_enabled: true`, preserves handle/Convex/tokens/health/pet; dry-run flag.
- Short comment header in each script: **operator-only, not user-facing**.
- `docs/runbooks/phase-05-operator.md` (or section in validation runbook) describes backup → Lite → restore workflow.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value.**

Optional: smoke test upgrade script against fixture config in `packages/cli` test dir if low cost — not required for ticket close.

## Green

- Add scripts with `set -euo pipefail` and confirmation prompts where destructive.
- Document Convex: Lite greenfield does not call `sync`; RPG restore + `sync` refreshes cache.

## Refactor

- Do not register scripts in public `package.json` user commands.

## Review Focus

- Scripts never commit real `config.json` or secrets.
- Restore path is obvious if multiple backups exist.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
