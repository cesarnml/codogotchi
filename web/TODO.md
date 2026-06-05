# codogotchi.app — site TODO

**Status:** deployed scaffold at https://codogotchi.app (Vercel, Astro 6.4.4 +
Tailwind 4.3.0, DNS at Porkbun). Not ready for public attention — copy and some
product assumptions are wrong, and the pages are monolithic. The deploy pipeline,
domain, theme tokens (OKLCH), and design language are solid; the content layer
and component model are not.

---

## P0 — structural (do before any real copy work)

- [ ] **Extract shared UI primitives.** Pages currently inline all section markup.
      Pull out at least: `Section`, `StickerCard`, `CodeBlock` (with copy button),
      `Pill`/`Chip`, `FeatureGrid`, `MenubarInset`, `Squiggle`, `SectionHeading`.
- [ ] **Move copy + data out of markup.** Per-page `const` arrays (pets, tier rows,
      leaderboard, features, ways-to-get-a-pet, nav/footer links) should live in an
      Astro **content collection** or `src/data/*.ts` so copy is editable without
      touching layout. Prose should not be hard-coded inside `.astro` files.
- [ ] **De-duplicate.** Nav/footer link lists, the menubar-inset window chrome, and
      the copy-to-clipboard script are repeated. Single source each.

## P1 — correctness (the copy is not trustworthy yet)

- [ ] **Full copy pass against the ACTUAL v1 product.** Much was reverse-engineered
      from docs + the `tcha` script and is stale/guessed. Verify every claim against
      shipping behavior. Known soft spots:
  - [ ] Install flow — confirm the real path (Settings → General, source build, what
        actually ships in the private beta).
  - [ ] Activity-state list / tier model — re-check against current
        `docs/contracts/animation-state-vocabulary.md` and the pet contract (3-tier:
        Codex 8×9 / Lite 8×11 / SoA 8×10; resolution SoA→Lite→Codex→Codex idle).
  - [ ] Platform list (Claude Code · Codex · Cursor · Copilot/VS Code · Antigravity)
        — confirm phrasing and that all five are actually GA.
  - [ ] `/pets` adoption flow — today it's manual folder copy; the one-line registry
        is aspirational. Don't imply it exists.
  - [ ] `/rpg` — local levels/half-hearts vs. cloud social layer; keep the "coming
        soon / free / no pay-to-win" framing accurate.
  - [ ] `/hatch` — verify the `hatch-codogotchi` command, inputs, and outputs.
- [ ] **GitHub link** in footer points to `github.com/cesarnml/codogotchi` (private?).
      Decide what's public.
- [ ] Replace placeholder community pets (Boba/Mochi/Byte/…) and the mock leaderboard
      with real or clearly-labeled-sample data.

## P2 — assets & polish

- [ ] **Real sprite assets.** Hero is the draft Maew GIF (`public/assets/hero-maew.gif`,
      1.8 MB). Swap to `<video>` (MP4/WebM) or animated WebP — smaller, and lets us
      honor `prefers-reduced-motion` (a GIF can't). Consider a cleaner capture backdrop.
  - The earlier CSS/JS animated hero (state-machine replay of the `tcha` arc) is in
    git history if we want a no-asset fallback.
- [ ] Real pet thumbnails in `/pets` and `/rpg` (currently emoji in dark insets).
- [ ] OG/Twitter image + per-page meta; favicon is a placeholder paw SVG.
- [ ] Accessibility pass: focus states, color contrast on saffron/jade chips, the
      GIF/`<video>` reduced-motion path, real `<button>` semantics on the fake controls.

## P3 — infra niceties

- [ ] **www → apex 308 redirect** (canonical). Set in Vercel project domain settings;
      `www` currently *serves* the site instead of redirecting.
- [ ] **Git auto-deploys** — connect the repo to the Vercel project so pushes deploy
      (preview on branches, prod on main) instead of manual `vercel --prod`.
- [ ] Decide hosting of the site within the monorepo (it's `web/` linked as its own
      Vercel project with root dir `web`).

---

## Reference

- Deploy: `cd web && vercel --prod`
- Dev: `cd web && bun run dev`  (http://localhost:4321)
- Theme tokens (OKLCH, from DESIGN.md): `src/styles/global.css`
- Source design assets: `~/Downloads/codogotchi-site/` (Stitch HTML + screenshots,
  DESIGN.md). NOTE: Stitch drafts had wrong specs (4 tiers, 32px grids) — trust the
  repo contracts, not the Stitch HTML.
