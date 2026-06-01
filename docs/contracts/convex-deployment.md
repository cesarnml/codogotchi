# Convex deployment contract

> **Operator setup.** Deployment URLs and dashboard links are **not** committed to this repo. Copy the live values from your local operator notes or Convex dashboard.

## What belongs where

| Item | Location |
| --- | --- |
| Deployment ID, `CONVEX_URL`, `CONVEX_SITE_URL`, `/sync` URL, dashboard | Local: `notes/private/convex-deployment.md` (gitignored) |
| `CONVEX_DEPLOY_KEY` | Gitignored `.env` / CI secrets only — never commit |
| Per-machine enroll URL | `~/.codogotchi/config.json` → `convex_http_url` (written by `codogotchi rpg` today) |

## Config shape

`~/.codogotchi/config.json` (Alive / RPG) includes:

```json
{
  "convex_http_url": "https://<your-deployment>.convex.site"
}
```

Lite installs do not require this field. Sync uses `POST {convex_http_url}/sync` with the payload defined in `@codogotchi/contracts` (`syncProfileRequestSchema`).

## Smoke test

```bash
CODOGOTCHI_CONVEX_URL=https://<your-deployment>.convex.site bun scripts/convex-smoke.ts
# or
bun scripts/convex-smoke.ts --url https://<your-deployment>.convex.site
```

Asserts two-profile isolation and `{ profile, new_loot_events }` envelope shape. Exit non-zero on failure.

## Before open-sourcing

1. Add authentication on the `/sync` HTTP action (see `convex/http.ts`).
2. Keep real deployment identifiers out of git; rotate deployment if URLs were ever published.
3. See local `notes/private/secrets-and-public-repo-hygiene.md` for the full checklist.
