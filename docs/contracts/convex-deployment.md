# Convex Deployment Contract

> **Private — do not link from public docs.** Limited circulation: project owner + buddy. The dashboard link is fine to share informally; the HTTP action URL gates writes to the production data, so treat it like a publish endpoint.

## Active deployment

| Field | Value |
| --- | --- |
| Deployment ID | `dev:careful-bat-587` |
| Client URL (`CONVEX_URL`) | `https://careful-bat-587.convex.cloud` |
| HTTP action base (`CONVEX_SITE_URL`) | `https://careful-bat-587.convex.site` |
| `/sync` endpoint | `https://careful-bat-587.convex.site/sync` |
| Dashboard | <https://dashboard.convex.dev/d/careful-bat-587> |
| Owner / admin | `cmejia` |

> The deployment was provisioned with a `dev:`-prefixed deploy key during P1.08. A `prod:` deployment will be cut from the same Convex project before public launch (Phase 04). Until then this dev deployment carries the Phase 01 validation data.

## Phase 01 reservation

`~/.codogotchi/config.json` (introduced in P1.12) reserves the field `convex_http_url`. For Phase 01, the owner and buddy populate it manually:

```json
{
  "convex_http_url": "https://careful-bat-587.convex.site"
}
```

P1.12's `codogotchi setup` command reads this value at sync time.

## Smoke test

`scripts/convex-smoke.ts` is the durable post-deploy assertion artifact. Re-run it any time deploy health is in question — not just during P1.08.

```bash
CODOGOTCHI_CONVEX_URL=https://careful-bat-587.convex.site bun scripts/convex-smoke.ts
# or
bun scripts/convex-smoke.ts --url https://careful-bat-587.convex.site
```

The script POSTs two synthetic payloads with distinct profile UUIDs and asserts:

- both responses are HTTP 200 with the `{ profile, new_loot_events }` envelope
- per-source XP totals come back independently for each profile (no bleed)
- every `new_loot_events` entry carries the correct `profile_id`

Exit code is `0` on success and non-zero on any assertion failure.

### Two-profile validation log

| Date | Operator | Profile A | Profile B | Result |
| --- | --- | --- | --- | --- |
| 2026-05-18 | cmejia (owner) | `smoke-a-<ts>` | `smoke-b-<ts>` | pass — see PR description for output |
| _pending_ | buddy | _tbd_ | _tbd_ | run after merge |

## Secret hygiene

- The `CONVEX_DEPLOY_KEY` lives only in operator `.env` files (gitignored) and the GitHub Actions secret store. Never paste it into a PR, commit, or chat transcript.
- The HTTP action URL is not technically a secret (Convex routes it on a guessable domain) but is treated as need-to-know to keep ad-hoc test traffic off the prod data while Phase 01 validation runs.
