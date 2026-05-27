# P1.01 Repo skeleton — 3-package workspace + empty convex/

Size: 2 points
Type: chore
Scope: repo

## Outcome

- `packages/cli/`, `packages/engine/`, `packages/contracts/` exist as Bun workspaces with their own `package.json`, `tsconfig.json`, and a stub `src/index.ts`.
- Root `convex/` directory exists with `convex.json` and an empty `schema.ts` stub that typechecks.
- Root `package.json` declares the workspace (`"workspaces": ["packages/*"]`) and `convex` is installed as a root dev dependency.
- `bun install` succeeds; `bun run verify` (Biome) is green; `bun run spellcheck` is green; `bun run ci:quiet` is green.
- No product logic. No engine functions. No CLI commands. No Convex schema. Imports between packages are wired but resolve to stub exports only.
- `.gitignore` updated with `.soa/`, `node_modules/`, `.convex/`, `~/.codogotchi/` is irrelevant (user-home) but `.codogotchi-test-home/` (test tempdir convention) is ignored.

## Red

- **Skip Red.** This is a chore/scaffolding ticket — files are mostly configuration and empty stubs. Automated tests against scaffolding wording would couple CI to legitimate restructures without quality signal. Human review at the PR is the gate.

## Green

- Create three `packages/*/package.json` files: `@codogotchi/cli`, `@codogotchi/engine`, `@codogotchi/contracts`. Each `"type": "module"`, `"main": "src/index.ts"`, with workspace dependencies declared (`cli` depends on `engine` and `contracts`; `engine` depends on `contracts`).
- Create a `packages/*/tsconfig.json` extending the root `tsconfig.json`.
- Add stub `src/index.ts` files exporting nothing meaningful (e.g. `export {}`) so `tsc --noEmit` and Biome pass.
- Add `convex/convex.json`, `convex/schema.ts` containing only `import { defineSchema } from "convex/server"; export default defineSchema({});`.
- Update root `package.json` to declare workspaces; ensure `bun install` resolves the workspace graph.
- Update root `.gitignore` to cover `.soa/` and any test-home convention.
- Update `cspell.json` to whitelist project-specific terms that surface (`codogotchi`, `Wakatime`, `Convex`, `ndjson`, etc.) so spellcheck remains green.

## Refactor

- None expected — this ticket is the canonical starting point.
- Only refactor what this ticket touches (workspace + tsconfig wiring). No opportunistic cleanup of `.son-of-anton/` (read-only subtree).

## Review Focus

- Workspace graph: does `bun install` resolve `@codogotchi/engine` from `packages/cli` without falling back to npm registry?
- Convex root-vs-workspace: confirm `convex/` is at repo root (not inside `packages/`) so the Convex CLI defaults work.
- TS path resolution: `import { ... } from "@codogotchi/engine"` resolves to the source file (no build step required for Bun-driven dev).
- `.gitignore` does not over-ignore (e.g. accidentally hiding `packages/*/src/`).
- No stray references to `claude-pet` anywhere in the new files.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.
