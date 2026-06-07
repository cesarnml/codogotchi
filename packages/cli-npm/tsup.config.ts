import { defineConfig } from "tsup";

export default defineConfig({
  entry: { codogotchi: "src/main.ts" },
  // CJS is required so bundled deps that use dynamic require() (image-size)
  // work under plain `node` without a native ESM loader.
  format: ["cjs"],
  platform: "node",
  bundle: true,
  // Inline all workspace and npm dependencies into the single artifact so
  // the published package runs under plain `node` without installing deps.
  noExternal: [/.*/],
  outDir: "dist",
  banner: { js: "#!/usr/bin/env node" },
  outExtension: () => ({ js: ".js" }),
  clean: true,
  target: "node18",
});
