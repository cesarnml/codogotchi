# P11.05 codogotchi add command + npm publish pipeline

Size: 3 points
Type: feat
Scope: cli
Red: required

## Outcome

- A new `codogotchi add <pet-id>` command fetches the P11.04 download endpoint and unpacks the canonical zip into `${CODOGOTCHI_HOME:-~/.codogotchi}/pets/<pet-id>/`.
- Install is **no-overwrite** by default (matching `PetStoreSeeder` semantics — existing files are never clobbered) with a `--force` flag to override; on success it prints a pointer to **Settings → Pet** to switch to the pet.
- After unzip, the package is **re-validated** against the contract (reusing the P11.01 shared constants/validator) as defense-in-depth; a malformed download fails cleanly without leaving a partial pet dir.
- A **node-runnable npm build** exists: a bundler (tsup/esbuild) emits a single JS artifact with a `#!/usr/bin/env node` shebang, workspace deps (`@codogotchi/engine`, `@codogotchi/contracts`) inlined, `bin`/`files`/`version` set, published over the claimed bare `codogotchi` package.
- The published surface is **minimal — `add` plus read-only `--version`/`status`**; app-owned write commands (`setup`, `hooks install`) are **not** exposed by the npm entry (preserving the Phase-08 boundary). The bun-compiled app binary is unchanged and keeps the full command set.

## Red

- Tests: `add <id>` writes the expected files under a temp `CODOGOTCHI_HOME`; no-overwrite leaves existing files intact; `--force` overwrites; a corrupt/invalid downloaded zip is rejected and leaves no partial dir; the npm entry does not expose `hooks install`/`setup`.
- Run the suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P11.05): codogotchi add install + minimal npm surface [red]`
- Do not write implementation until this commit exists on the branch.

## Green

- Implement `add` (fetch → unzip → re-validate → place), wired into `router.ts`; add the minimal node build config and the publish workflow.

## Refactor

- Reuse the P11.01 contract module for re-validation; do not reimplement checks in the CLI.
- Keep the npm entry thin — a dedicated entrypoint wiring only the public commands, distinct from the full router used by the app binary.

## Review Focus

- The minimal-surface boundary: confirm an `npx codogotchi`-installed package genuinely cannot run `hooks install`/`setup` (not merely hidden from `--help`).
- node-runnability: the published artifact must run under plain `node` (no bun, no TS loader); verify the shebang and bundled deps.
- No-overwrite + `--force` + partial-failure cleanup behavior.
- Cross-boundary: the URL `add` fetches must match P11.04's endpoint and the curl one-liner shown on the detail page.
- Deferred: full-CLI npm distribution; auto-update.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [any deviation from the ticket metadata contract]
