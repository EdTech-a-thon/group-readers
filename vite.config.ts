import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [svelte()],
  build: { outDir: "dist", emptyOutDir: true },
  server: {
    allowedHosts: [".exe.xyz", ".edtechathon.com", ".groupreaders.com", "groupreaders.com"],
  },
  preview: {
    host: "0.0.0.0",
    port: 8000,
    allowedHosts: [".exe.xyz", ".edtechathon.com", ".groupreaders.com", "groupreaders.com"],
  },
});
