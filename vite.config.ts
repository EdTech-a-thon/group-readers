import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [svelte()],
  build: { outDir: "pb_public", emptyOutDir: true },
  server: {
    allowedHosts: [".exe.xyz", ".edtechathon.com"],
  },
});
