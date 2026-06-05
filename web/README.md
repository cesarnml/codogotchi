# codogotchi.app — marketing + docs site

The public website for [Codogotchi](https://github.com/cesarnml/codogotchi) — a cute
desktop pet for AI coding agents that lives in the macOS menubar.

- **Stack:** [Astro](https://astro.build) 6.4.4 + [Tailwind CSS](https://tailwindcss.com) 4.3.0 (via `@tailwindcss/vite`).
- **Design system:** "Cute Thai Cartoon" (warm cream + terracotta/saffron, charcoal-ink
  sticker outlines). Color tokens live in [`src/styles/global.css`](src/styles/global.css)
  as **OKLCH** values converted from the original sRGB DESIGN.md palette (the source hex
  is kept in a trailing comment per token).

## Pages

| Route | Page |
|-------|------|
| `/` | Landing — hero with a live menubar-inset demo, four ways to get a pet, features, install |
| `/hatch` | Hatch a pet with the `hatch-codogotchi` skill (seed image or text description) |
| `/pets` | Community pet gallery (adopt by dropping a folder into `~/.codogotchi/pets/`) |
| `/docs/spritesheet` | The three-tier spritesheet reference (Codex 8×9 / Lite 8×11 / SoA 8×10) |
| `/rpg` | RPG teaser — local levels/half-hearts today, social layer coming soon |

Copy reflects the **actual Codogotchi v1 product**: macOS menubar app + optional floating
pet, 19-state activity vocabulary, the three-tier sheet model, five hooked platforms
(Claude Code · Codex · Cursor · Copilot/VS Code · Antigravity), and the half-hearts HUD.

## Hero demo

[`src/components/HeroDemo.astro`](src/components/HeroDemo.astro) is the web counterpart of
`scripts/test-codogotchi-hero-animation.sh` (the `tcha` demo). It replays the same beat
arc — the pet animates per activity/gate state while the half-hearts HUD drains 6 → 0, a
level-up flashes on the ticket gate, the pet faints on `errored`, and a +½ heal flashes on
ticket completion — and the platform-attribution chip cycles through all five agents. It's
a self-contained CSS/JS proxy; real sprite frames can be dropped in later.

## Develop

```bash
bun install
bun run dev      # http://localhost:4321
bun run build    # static output → dist/
bun run preview
```
