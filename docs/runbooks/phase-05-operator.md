# Phase 05 Operator Runbook

Operator-only procedures for managing the RPG ↔ Lite transition introduced in Phase 05. These scripts are not user-facing and are not exposed in the public CLI.

---

## Upgrade developer config (add `features.rpg_enabled`)

The Phase 05 config schema requires an explicit `features.rpg_enabled` key. If your `~/.codogotchi/config.json` predates this schema, run the upgrade script:

```bash
# Preview what will change (no write):
bun scripts/operator/upgrade-phase-05-config.ts --dry-run

# Apply:
bun scripts/operator/upgrade-phase-05-config.ts
```

Preserved fields: `profile_id`, `pet`, `handle`, `github_token`, `github_username`, `wakatime_key`, `convex_http_url`, `health`.

---

## Backup → Lite greenfield → Restore workflow

Use this workflow to test Lite mode on a developer machine that already has an RPG config.

### 1. Back up RPG home

```bash
bash scripts/operator/backup-rpg-home.sh
```

Creates `~/.codogotchi.rpg-backup-<timestamp>`. The backup includes all files in `~/.codogotchi`, including any hooks JSON files stored there.

> **Note on hooks:** The backup includes hooks JSON, but the installed hook binaries/symlinks in your shell profile are not removed. Run `codogotchi hooks uninstall` before step 2 if you want a fully clean slate.

### 2. Enter Lite greenfield

```bash
bash scripts/operator/enter-lite-greenfield.sh
```

This script:
1. Creates a backup (same as step 1) before deleting
2. Asks for confirmation
3. Removes `~/.codogotchi`
4. Does **not** touch installed hooks

Then set up a fresh Lite config:

```bash
codogotchi setup
```

### 3. Restore RPG home

When done testing, restore from a backup:

```bash
bash scripts/operator/restore-rpg-home.sh
```

Lists all available backups (newest first), prompts for a choice, saves the current `~/.codogotchi` as a safety backup, then restores the selected backup.

After restoring, refresh the server cache:

```bash
codogotchi sync
```

> **Convex note:** Lite mode does not call `sync`; it runs locally only. Restoring an RPG config and running `sync` re-establishes the server-side cache.

---

## Scripts reference

| Script | Purpose |
|---|---|
| `scripts/operator/backup-rpg-home.sh` | Non-destructive backup of `~/.codogotchi` |
| `scripts/operator/enter-lite-greenfield.sh` | Backup + delete `~/.codogotchi` to start fresh |
| `scripts/operator/restore-rpg-home.sh` | Restore from an existing backup |
| `scripts/operator/upgrade-phase-05-config.ts` | Add `features.rpg_enabled: true` to existing config |
