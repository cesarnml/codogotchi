# Post-Phase 11 mainline sweep

> **Status (2026-06-20): direct-to-main window CLOSED.** This ledger covers two sweeps of unplanned `main` work after the Phase 11 stack. The accumulated surface — production marketplace operations, upload guardrails, an auth-verification fix, a Studio chroma-key page, and a full Hatch pipeline rewrite (v3 → v6) — confirms the project has outgrown direct-to-main. Work now returns to **structured SoA phase delivery starting with Phase 12 (refactor / architectural cleanup)** to pay down the drift catalogued here and prepare a clean foundation for the v2 roadmap. Treat new multi-surface work as phase/ticket scope, not mainline commits.

Reference for agents and maintainers: what shipped directly on `main` after the Phase 11 ticket stack closed at `56dc386` (`v0.1.0`). **Sweep 1** runs through `7d649c9`; **Sweep 2** (below) runs `6a07d298..ab7f6a6c` and is the final batch before the Phase 12 boundary.

**Sweep command:** `git log --reverse --date=short --pretty=format:'%h %ad %s' 56dc386..HEAD`

**Date range:** 2026-06-08 through 2026-06-16.

**Stance:** this range deserves a post-phase doc. Most commits were small UI/UX, docs, release, or asset fixes, but the accumulated surface is no longer "just polish": schema-v6 revive behavior, Lite-Basic/Lite-Enhanced ghost semantics, production gallery upload evolution, operator upload tooling, settings-window redesign, production Convex wiring, and Hatch plugin workflow changes all landed after Phase 11 without a new phase plan.

Direct-to-main remains reasonable for single-surface copy fixes, release unblocks, asset swaps, and tight bug fixes. Any next multi-surface product addition should go back through the documented SoA phase/ticket path so contracts, tests, rollout notes, and review artifacts are captured before the work spreads.

---

## Change buckets

| Bucket | Commits | What changed | Why it matters |
| --- | --- | --- | --- |
| Public site, gallery, and deploy | `676ccfb`, `08c941d`, `9c1da90`, `58744e3`, `a353987`, `01f43c9`, `806a4ac`, `3e5b113`, `f885aba`, `c1785fc`, `77bb9cd`, `ab059fd`, `75c5175`, `ad0ee0e`, `562777c`, `5ed93d2`, `81092bf`, `27089e6`, `9791cd7`, `24762cb`, `40abad0`, `eee46b5`, `9680ea3`, `46ca7ca`, `6aa8a0e`, `8b9e726`, `8c02a21`, `18b124d`, `5728057`, `288c28a`, `87fdd8d`, `c18c251`, `82d7303`, `bfcbfbe`, `7d649c9` | Reworked install/docs flow, fixed Vercel build shape for standalone `web/`, improved auth modal behavior, reopened and iterated the gallery, added analytics/speed insights, fixed CLS/font/icon regressions, added animation previews, shifted gallery downloads to per-tier CDN blobs, supported progressive uploads and update-existing-pet, and wired `codogotchi.app` to production Convex. | The Phase 11 marketplace moved from completed implementation to production-facing operation. This is product/runtime scope, not just presentation polish. |
| Menubar app, state contracts, and settings | `72463c9`, `01f8c2d`, `2b5366e`, `958e2e0`, `7aacad4`, `fc226d7`, `d57c892`, `8eb505b`, `e216ec6`, `99d8f2e`, `5818002`, `34b45d1`, `d3f3f57`, `0db87b2`, `4bc8ca4`, `191750e`, `febcc5e`, `e566575` | Added revive animation and schema-v6 `revive_until`, preserved revive windows across non-gain hook writes, moved the app to Lite-Basic and ghost semantics, adjusted floating resize affordances, wired Lite-Enhanced Maew, redesigned the Pet tab/card grid, fixed Settings-window crashes/layout, sorted pet cards, renamed the pet menu action, moved folder shortcuts into Settings, and added layout-invariant tests. | These are user-visible app behavior changes plus contract evolution. They should be discoverable by future agents debugging state rendering or settings behavior. |
| Maew and shipped assets | `a4c8773`, `2b656aa`, `c5f4e93`, `7d2339f`, `44d087a`, `d80352d`, `fcf54fb`, `698eea8`, `7a5e450` | Replaced the dead row with ghost art, bottom-aligned Lite-Basic rows, refreshed the Lite-Basic and Codex sheets, regenerated thinking/standby rows, tightened idle/run cycles, added hatch sparkle art, and polished Lite-Enhanced idle loops. | Maew's bundled visual contract changed alongside the renderer semantics. Asset-only commits still affect QA expectations and screenshots. |
| Hatch plugin and pet contract tooling | `0575e2c`, `bf77ff2`, `206ecb2`, `b47bcaf`, `ca58a7b`, `79d537b`, `3e135a2`, `84ad21e`, `3c1b9bf`, `894cf74` | Clarified frame-first generation, row-safe chroma keys, Lite-Basic QA, atlas alignment guard, stability-over-expressiveness doctrine, idle escalation thresholds, plugin version bumps, deprecated tier removal, canonical `displayName`, sheet-first generation, and locomotion doctrine. | Hatch is now part generator, part contract surface. These changes should be treated as source-of-truth updates for future pet creation and validation work. |
| Release, packaging, and CLI/runtime fixes | `f01514b`, `45a0e4e`, `6f44ffb` | Bumped to v1.0.0, fixed the 1.0.1 DMG by stripping dev-tool symlinks, and shipped v1.0.2 with quote-aware shell-pipe classification. | These explain the release history after the Phase 11 `v0.1.0` marker and why versions advanced outside a formal phase. |
| Open-source and governance docs | `01a9f8f`, `9e79696`, `c99cac8`, `a334d5b`, `b82ba21`, `e29488f`, `21d4628`, `f8440d2` | Rewrote README as a product page, moved developer material to `CONTRIBUTING.md`, added `LICENSE`, documented Tier 1/Codex row mapping, triaged Phase 11 advisory observations, switched to PolyForm Noncommercial 1.0.0, added `START-HERE.md` and code of conduct, and added GitHub issue templates/discussion links. | The repo's public posture changed materially after the marketplace phase. License and contributor docs are not incidental implementation details. |
| Operator and Convex maintenance | `eadc784`, `c18c251`, `82d7303`, `bfcbfbe`, `7d649c9` | Added `scripts/operator/push-pet.ts`, operator upload mutations, per-tier blob serving, progressive tier uploads, update-existing-pet without requiring `pet.json`, and production Convex environment resolution. | This is the strongest signal that the marketplace has entered operational-maintenance mode and needs durable documentation. |

---

## Commit index

| Date | Commit | Summary |
| --- | --- | --- |
| 2026-06-08 | `676ccfb` | Open-source README, DMG-first install flow, and four-tier spritesheet split. |
| 2026-06-08 | `f01514b` | Bump to v1.0.0. |
| 2026-06-08 | `08c941d` | Vercel build command/output fix for `web/`. |
| 2026-06-08 | `9c1da90` | Call Astro from root `node_modules/.bin` with `--root web`. |
| 2026-06-08 | `58744e3` | Install/build inside standalone `web/`. |
| 2026-06-08 | `a353987` | Install root deps too because `web` aliases root Convex code. |
| 2026-06-08 | `01f43c9` | Auth modal scroll/viewport clipping fix. |
| 2026-06-08 | `806a4ac` | Format `vercel.json`. |
| 2026-06-08 | `3e5b113` | Portal auth modals to `document.body`. |
| 2026-06-08 | `01a9f8f` | User-facing README, `CONTRIBUTING.md`, and `LICENSE`. |
| 2026-06-08 | `9e79696` | Tier 1 Codex row-table docs. |
| 2026-06-08 | `72463c9` | Menubar revive animation, schema v6, and darker animation badge tint. |
| 2026-06-08 | `01f8c2d` | Accept state schema v6 and render `revive_until`. |
| 2026-06-08 | `2b5366e` | Preserve `revive_until` across non-gain hook writes. |
| 2026-06-08 | `0575e2c` | Clarify Hatch frame-first image generation workflow. |
| 2026-06-08 | `bf77ff2` | Use row-safe chroma keys for Hatch output. |
| 2026-06-09 | `374ceb4` | Rename Lite dead row to ghost. |
| 2026-06-09 | `a4c8773` | Replace Maew dead row with ghost art. |
| 2026-06-09 | `958e2e0` | Menubar app uses Lite-Basic and ghost semantics. |
| 2026-06-09 | `7aacad4` | Replace dead state with ghost Lite-Basic flow. |
| 2026-06-09 | `206ecb2` | Add Hatch spritesheet alignment guard. |
| 2026-06-09 | `2b656aa` | Bottom-align Maew Lite-Basic rows. |
| 2026-06-09 | `c5f4e93` | Update Maew Lite-Basic spritesheet. |
| 2026-06-09 | `fc226d7` | Enlarge resize affordance reveal zone and classify user-aborted stops as idle. |
| 2026-06-09 | `d57c892` | Reduce resize affordance reveal zone from 3x to 2x. |
| 2026-06-09 | `7d2339f` | Regenerate Maew thinking row. |
| 2026-06-09 | `44d087a` | Regenerate Maew standby row. |
| 2026-06-09 | `8eb505b` | Wire Maew Lite-Enhanced spritesheet into the app. |
| 2026-06-09 | `d80352d` | Refresh shipped Maew Codex spritesheet. |
| 2026-06-09 | `fcf54fb` | Tighten Maew Codex idle and run cycles. |
| 2026-06-10 | `698eea8` | Replace hatch egg banner with Maew sparkle hatch art. |
| 2026-06-11 | `c99cac8` | Triage Phase 11 advisory observations. |
| 2026-06-11 | `a334d5b` | Record Phase 11 advisory-observation triage. |
| 2026-06-11 | `b82ba21` | Replace MIT with PolyForm Noncommercial License 1.0.0. |
| 2026-06-11 | `7a5e450` | Polish Maew Lite-Enhanced idle loops. |
| 2026-06-11 | `f885aba` | Temporarily replace gallery with under-construction Maew notice. |
| 2026-06-11 | `e29488f` | Open-source onboarding, code of conduct, START-HERE, camelCase `pet.json` contract. |
| 2026-06-11 | `c1785fc` | Fix intermittent blank auth widget and "Leave site?" nav warning. |
| 2026-06-11 | `77bb9cd` | Improve site SEO metadata. |
| 2026-06-11 | `ab059fd` | Replace icon-font logo with logo image and WebP favicon. |
| 2026-06-11 | `75c5175` | Optimize images. |
| 2026-06-11 | `ad0ee0e` | Footer update. |
| 2026-06-11 | `1ed8edc` | Merge `main`. |
| 2026-06-11 | `562777c` | Footer update. |
| 2026-06-11 | `5ed93d2` | Rework Hatch page around Codex plugin install and canonical skill prompts. |
| 2026-06-11 | `81092bf` | Reopen gallery and surface Upload pet in navbar. |
| 2026-06-11 | `27089e6` | DMG download tracking, Vercel Analytics, and account dropdown fix. |
| 2026-06-11 | `9791cd7` | Full animation-state previews on pet detail page. |
| 2026-06-12 | `24762cb` | Animated gallery-card idles, light animation tiles, count-safe previews. |
| 2026-06-12 | `45a0e4e` | Strip dev-tool symlinks from DMG and bump to v1.0.1. |
| 2026-06-12 | `40abad0` | Enable Vercel Speed Insights. |
| 2026-06-12 | `6f44ffb` | Quote-aware shell-pipe classifier and v1.0.2. |
| 2026-06-12 | `eee46b5` | Remove stale "No PATH prerequisite" callout from download page. |
| 2026-06-12 | `9680ea3` | Rename "Adopt a Pet" to "Gallery". |
| 2026-06-12 | `46ca7ca` | Cache auth state in `localStorage` to reduce nav pop-in. |
| 2026-06-12 | `21d4628` | Add bug-report and feature-request issue templates. |
| 2026-06-12 | `f8440d2` | Link Discussions threads from issue chooser. |
| 2026-06-12 | `6aa8a0e` | Fix PageSpeed regressions: video hero, self-hosted fonts, subset icons. |
| 2026-06-12 | `8b9e726` | Preload above-the-fold fonts and pin icon width to fix CLS. |
| 2026-06-12 | `8c02a21` | Preload remaining hero-viewport fonts to fix mobile font-swap CLS. |
| 2026-06-12 | `18b124d` | Reserve nav auth-widget height and add missed icons to subset. |
| 2026-06-13 | `5728057` | Serve standalone Codex sheet, add card shimmer, accept loose uploads. |
| 2026-06-13 | `288c28a` | Point "Meet Maew" at her gallery page. |
| 2026-06-13 | `87fdd8d` | Fingerprint material-symbols subset to bust stale icon caches. |
| 2026-06-13 | `b47bcaf` | Make Hatch animation stability paramount over expressiveness. |
| 2026-06-14 | `ca58a7b` | Correct idle escalation thresholds to 10 min / 30 min. |
| 2026-06-14 | `79d537b` | Bump Hatch plugin version to 1.0.0. |
| 2026-06-14 | `3e135a2` | Bump Hatch plugin to 1.0.1 and drop deprecated Lite tier. |
| 2026-06-14 | `84ad21e` | Write canonical `displayName` in pet manifests. |
| 2026-06-15 | `3c1b9bf` | Bump Hatch sheet-first generation. |
| 2026-06-16 | `eadc784` | Add `push-pet` script and `operatorUpload` Convex mutations. |
| 2026-06-16 | `894cf74` | Update Hatch locomotion doctrine. |
| 2026-06-16 | `c18c251` | Per-tier CDN blobs and shimmer on pet detail page. |
| 2026-06-16 | `82d7303` | Progressive pet uploads: add/replace tiers, `pet.json` as source of truth. |
| 2026-06-16 | `bfcbfbe` | Update-existing-pet path without requiring `pet.json` on updates. |
| 2026-06-16 | `e216ec6` | Redesign Pet tab as a single card grid. |
| 2026-06-16 | `99d8f2e` | Align `project.yml` version with `Info.plist` (`1.0.2/4`). |
| 2026-06-16 | `5818002` | Open Pet grid window without `NSGenericException`. |
| 2026-06-16 | `34b45d1` | Sort pet cards alphabetically and keep ordering stable. |
| 2026-06-16 | `d3f3f57` | Rename "Show/Hide Floating Pet" to "Show/Hide Pet". |
| 2026-06-16 | `0db87b2` | Top-anchor pet grid so search results fill from the top. |
| 2026-06-16 | `4bc8ca4` | Move folder shortcuts into Settings and relabel data folder. |
| 2026-06-16 | `191750e` | Redesign pet cards Codex-style with larger art and fuller text. |
| 2026-06-16 | `febcc5e` | Add layout-invariant guard for pet cards. |
| 2026-06-16 | `e566575` | Widen default Settings window to 1020 px for a 3-column pet grid. |
| 2026-06-16 | `7d649c9` | Wire `codogotchi.app` to production Convex deployment. |

---

## Sweep 2 (2026-06-16 → 2026-06-20)

The batch from the Sweep 1 closeout commit (`6a07d298`) to the Phase 12 boundary (`ab7f6a6c`). Sweep command: `git log --reverse --date=short --pretty=format:'%h %ad %s' 6a07d298..ab7f6a6c`. Dominated by two large efforts — a top-to-bottom Hatch pipeline rewrite and a round of production marketplace hardening — plus release packaging, web polish, and an SoA subtree pull. This is the cluster Phase 12 is meant to consolidate.

### Change buckets

| Bucket | Commits | What changed | Why it matters |
| --- | --- | --- | --- |
| Marketplace ops, uploads, and auth | `8ec9c511`, `f6873211`, `363905dd`, `9a275708`, `d64407b5`, `54a43178`, `eb61df99`, `9f1c9261`, `ab7f6a6c` | Seeded preview deployments with real (capped) gallery data, scoped Vercel deploys, referenced public pet queries via `api`, added a 10 MB upload size cap and a 5/hour per-user upload rate limit (admin-exempt), and fixed `createOrUpdateUser` to actually persist `emailVerificationTime` (the Resend OTP / OAuth signal was being dropped). | Production marketplace gained real abuse guardrails and an auth-correctness fix. This is exactly the operational-maintenance scope flagged in Sweep 1 — now substantial enough to deserve phase-level treatment. |
| Hatch pipeline rewrite (v3 → v6) | `e5edc76f`, `bf1692a1`, `6761bb94`, `91b56d52`, `e7323199`, `6be77b19`, `b7347914`, `b19dfaf5`, `ce94d787`, `48757b6a`, `a0479279`, `e6f158a3`, `3e87393c`, `6b7c3b21`, `bbe4543e`, `86f3fef3`, `932e8f52`, `8c8cbae8`, `53c5ad9f`, `ea73435f`, `43ef8185` | Required `spritesheetPath`, hardened QA gates, then rewrote the generation pipeline end-to-end: strip-first → grid-first → slot-first; collapsed to a 4×2-only layout; switched chroma keying from green to magenta default to deterministic per-pet auto-select; moved the matte stage to the canonical TS engine; formalized the run workspace; and fixed running/jumping animation cycles. Versions advanced 3.2.0 → 4.0.0 → 5.x → 6.0.0. | Hatch is the pet-authoring contract surface. A rewrite this large with breaking version bumps is the single strongest argument for the Phase 12 cleanup boundary; its doctrine churn should be reconciled before v2 tooling builds on it. |
| Studio, gallery, and web polish | `ccb7cb70`, `f5e84e80`, `647fad7a`, `559fa6a3`, `b8ffc2fb`, `79e5762e`, `7b3740cc`, `46ee0f63`, `24b16d75`, `61bc7df2`, `6758aa4a`, `f743095a`, `3a8b8a15`, `2379d112`, `1378354e`, `eefe4bd4` | Added the `/studio` chroma-key page and made `/hatch` Studio-aware, added a live perf-comparison infographic, killed the intermittent "Leave site?" dialog (adopted `ClientRouter`), fixed account-menu/dropdown/nav behavior, replaced gallery loading text with shimmer skeletons, routed Gallery straight to `/gallery` (dropped the `/pets` redirect), corrected gallery animation-state row names, removed a stray `package-lock.json`, configured Renovate, and optimized images. | The public surface kept evolving — notably a new in-browser tool (`/studio`) that pairs with the Hatch keying handoff. The "Leave site?" fix closes a long-standing nav bug. |
| Release, packaging, and macOS app | `6f75a234`, `e6e3ea71`, `ed1da96f`, `4f54e54c`, `4be8f945` | Shipped v1.1.0 (Settings > Pet rework), repackaged 1.1.1, verified bundle packaging, shipped v1.1.2 with a refreshed app icon + Steam-style DMG installer, and added a low-health sickness overlay to the floating pet. | Continues the out-of-phase release cadence; v1.1.2 is the current shipped macOS build. |
| README, Product Hunt, and SoA subtree | `098d7a42`, `a706601c`, `b2623b08`, `869d3669`, `09cbce61`, `19942875`, `dbd31a95`, `dd048c37` | README/Product Hunt launch updates, plus an SoA subtree pull bringing the gate badge system and the subtree-readonly guard. | Governance/tooling maintenance; the subtree pull keeps SoA delivery machinery current ahead of resuming phase work. |

### Commit index

| Date | Commit | Summary |
| --- | --- | --- |
| 2026-06-16 | `6a07d298` | Capture post-phase-11 mainline sweep (Sweep 1 closeout). |
| 2026-06-16 | `098d7a42` | Update README with Product Hunt. |
| 2026-06-16 | `8ec9c511` | Seed preview deployments with real gallery data. |
| 2026-06-16 | `f6873211` | Cap preview seed at newest 10 listed pets. |
| 2026-06-16 | `6f75a234` | Release v1.1.0 — Settings > Pet rework. |
| 2026-06-16 | `e5edc76f` | Document source layouts and require `spritesheetPath`. |
| 2026-06-16 | `e6e3ea71` | Repackage Codogotchi 1.1.1. |
| 2026-06-16 | `363905dd` | Keep Vercel deploys scoped. |
| 2026-06-16 | `ed1da96f` | Verify macOS app bundle packaging. |
| 2026-06-16 | `ccb7cb70` | Add live perf-comparison infographic to landing page. |
| 2026-06-16 | `bf1692a1` | Harden hatch-codogotchi QA gates. |
| 2026-06-16 | `6761bb94` | Green-default 3-key chroma rule + 4×2-only layout. |
| 2026-06-16 | `91b56d52` | Make 4×2 the only layout end-to-end (remove 3×3). |
| 2026-06-16 | `e7323199` | Drop dead `is_empty_slot` / ninth-cell code from slicer. |
| 2026-06-17 | `a706601c` | Update Product Hunt links in README. |
| 2026-06-17 | `6be77b19` | Formalize Hatch run workspace to `~/Documents/Codex/<timestamp>`. |
| 2026-06-17 | `869d3669` | Add subtree-readonly guard to `AGENTS.soa.md` and `claude.soa.md`. |
| 2026-06-17 | `09cbce61` | Squashed `.son-of-anton/` changes. |
| 2026-06-17 | `19942875` | Merge SoA subtree. |
| 2026-06-17 | `dbd31a95` | Pull SoA upstream — gate badge system + subtree guard. |
| 2026-06-18 | `dd048c37` | SoA update. |
| 2026-06-18 | `f743095a` | Drop stray `package-lock.json` (bun is canonical). |
| 2026-06-18 | `3a8b8a15` | Configure Renovate (#123). |
| 2026-06-18 | `4f54e54c` | Refreshed app icon + Steam-style DMG installer (v1.1.2). |
| 2026-06-18 | `2379d112` | Optimize images (ImgBot). |
| 2026-06-18 | `9a275708` | Reference public pet queries via `api`, not internal. |
| 2026-06-18 | `559fa6a3` | Kill intermittent "Leave site?" dialog + adopt `ClientRouter`. |
| 2026-06-18 | `b8ffc2fb` | Account menu closes on any outside click + nav top gap. |
| 2026-06-18 | `79e5762e` | Responsive RPG hero (stretch on mobile, `min-w-0` email input). |
| 2026-06-18 | `7b3740cc` | Anchor account dropdown below the trigger (`top-full`). |
| 2026-06-18 | `b7347914` | Enforce keyed-row review in hatch-codogotchi. |
| 2026-06-18 | `b19dfaf5` | Document scratch-to-run relocation for hatch-codogotchi. |
| 2026-06-18 | `ce94d787` | Switch hatch matte stage to canonical TS engine. |
| 2026-06-18 | `4be8f945` | Add low-health sickness overlay to floating pet. |
| 2026-06-18 | `48757b6a` | Update hatch-codogotchi prompt guidance. |
| 2026-06-18 | `46ee0f63` | Replace gallery "Loading pets" text with 3 shimmer skeleton cards. |
| 2026-06-18 | `a0479279` | Release hatch-codogotchi 3.2.0 with path-agnostic pipeline docs. |
| 2026-06-18 | `24b16d75` | Link Gallery nav straight to `/gallery`, skip `/pets` redirect flash. |
| 2026-06-18 | `61bc7df2` | Drop deleted `/pets` redirect, point doc refs to `/gallery`. |
| 2026-06-18 | `6758aa4a` | Use canonical Codex row names in gallery animation states. |
| 2026-06-18 | `e6f158a3` | Hatch v4.0.0 — strip-first pipeline, flat green, external keying. |
| 2026-06-19 | `3e87393c` | Commit fully to the strip paradigm; make ~7.38:1 ratio explicit. |
| 2026-06-19 | `b2623b08` | Update `README.md`. |
| 2026-06-19 | `6b7c3b21` | Hatch v4.0.1 — restore v4 README, keep canonical jumping. |
| 2026-06-19 | `bbe4543e` | Hatch v5.0.0 — grid-first pipeline, no prescribed paths, no model-side QA. |
| 2026-06-19 | `86f3fef3` | Hatch v5.5.0 — magenta default key, gutter-aware grid slice. |
| 2026-06-19 | `932e8f52` | Hatch v5.5.1 — purge stale green wording, fix description-mode prompt. |
| 2026-06-19 | `f5e84e80` | Add Codogotchi Studio chroma-key page at `/studio`. |
| 2026-06-19 | `1378354e` | Gitignore hatch-codogotchi generation output at repo root. |
| 2026-06-19 | `8c8cbae8` | Hatch v5.5.2 — point keying handoff to `codogotchi.app/studio`. |
| 2026-06-19 | `53c5ad9f` | Hatch v5.6.0 — fix running rows (in-place stride cycle), blue ghost. |
| 2026-06-19 | `647fad7a` | Make `/hatch` Studio-aware; fix colorize icon subset. |
| 2026-06-19 | `eefe4bd4` | Update `.gitignore`. |
| 2026-06-19 | `ea73435f` | Hatch v5.7.0 — fix jumping (single full bounce, real clearance). |
| 2026-06-19 | `43ef8185` | Hatch v6.0.0 — per-pet chroma auto-select, dynamic recolor, 4×2 guide. |
| 2026-06-19 | `d64407b5` | Cap pet upload package size at 10 MB. |
| 2026-06-20 | `54a43178` | Rate-limit pet uploads to 5/hour per user. |
| 2026-06-20 | `eb61df99` | Exempt `admin@codogotchi.app` from upload rate limit. |
| 2026-06-20 | `9f1c9261` | Persist email verification; harden admin rate-limit exemption. |
| 2026-06-20 | `ab7f6a6c` | Remove one-off email-verification backfill mutation. |

---

## Follow-up recommendations

1. **This file is the closeout ledger; the direct-to-main window is now closed.** Both sweeps are captured. New work resumes under SoA phase/ticket delivery.
2. **Phase 12 = refactor / architectural cleanup.** Scope it to consolidate the drift catalogued here before any v2 feature builds on it. Prime candidates: the marketplace/gallery operational surface (upload schema, size + rate-limit guards, operator scripts, per-tier CDN/blob render path, preview-seed behavior), the Hatch pipeline (reconcile the v3 → v6 doctrine churn into one canonical contract), and the auth/user model now that `emailVerificationTime` is persisted.
3. Hold the direct-to-main exception to genuinely narrow fixes (single-surface copy, release unblocks, asset swaps) understandable from one commit title and one test command. Anything spanning app + web + Convex, or Hatch + runtime contracts, goes through a phase plan.
4. Treat Phase 12 as the foundation pass for the **v2 roadmap** — land the cleanup and durable contracts first so v2 features (per-platform multi-pet and the other roadmap candidates) start from a consolidated base rather than accreting on mainline drift.

## Suggested commit subject

`docs: capture sweep 2 and close post-phase-11 mainline window`
