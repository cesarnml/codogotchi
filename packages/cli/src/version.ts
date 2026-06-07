// Single source of truth for the version the `codogotchi` binary reports via
// `codogotchi --version`. Kept as a compiled-in constant (not a runtime
// package.json read) so the standalone `bun build --compile` binary is fully
// self-contained. Mirrors packages/cli/package.json `version`.
//
// P8.05 (lockstep) builds the installed-vs-bundled comparison on top of this
// reported value; this ticket only establishes the command surface.
export const CLI_VERSION = "1.0.0";
