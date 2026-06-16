# Post-Phase 11 mainline sweep

Reference for agents and maintainers: what shipped directly on `main` after the Phase 11 ticket stack closed at `56dc386` (`v0.1.0`) through `7d649c9`.

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

## Follow-up recommendations

1. Treat this file as the closeout ledger for direct-to-main work after Phase 11.
2. Start a new phase plan before the next feature that spans app + web + Convex, or Hatch plugin + runtime contracts.
3. Keep direct-to-main for narrow fixes that can be understood from one commit title and one test command.
4. If marketplace/gallery work continues, make "production gallery operations" the next explicit planning boundary instead of letting operator scripts, upload schema, and CDN behavior drift independently.

## Suggested commit subject

`docs: capture post-phase-11 mainline sweep`
