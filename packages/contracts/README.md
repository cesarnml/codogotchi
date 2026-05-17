# @codogotchi/contracts

Shared TypeScript types and zod schemas for the codogotchi IPC surface.

The canonical narrative lives at
[`docs/contracts/animation-state-vocabulary.md`](../../docs/contracts/animation-state-vocabulary.md).
This package is the machine-checkable mirror of that doc — closed-enum
activity states, HP overlay buckets, and the `state.json` v1 schema with
`schema_version`.

Consumers:

- **P1.06** Convex schema's `mood` field
- **P1.18** Hook binary that writes `~/.codogotchi/state.json`
- **P1.19** SoA gate signal mapping
