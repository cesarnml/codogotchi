// @ts-check
import react from "@astrojs/react";
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";
import { fileURLToPath, URL } from "node:url";

// https://astro.build/config
export default defineConfig({
  site: "https://codogotchi.app",
  integrations: [react()],
  vite: {
    plugins: [tailwindcss()],
    resolve: {
      alias: {
        "~convex": fileURLToPath(new URL("../convex", import.meta.url)),
      },
    },
  },
});
