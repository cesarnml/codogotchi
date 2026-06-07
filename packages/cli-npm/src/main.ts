import { dispatchNpm } from "@codogotchi/cli/npm-router";

// Top-level await is unavailable in CJS bundles; wrap in IIFE.
void dispatchNpm(process.argv.slice(2)).then(({ exitCode }) => {
  process.exit(exitCode);
});
