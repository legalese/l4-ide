#!/usr/bin/env node
// Bundle src/app.js (bpmn-js + bpmn-js-token-simulation + their CSS and fonts)
// into dist/ so index.html can be opened from file:// with no server.
import { build } from "esbuild";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));

await build({
  entryPoints: [join(here, "src/app.js")],
  bundle: true,
  format: "iife",
  outfile: join(here, "dist/app.js"),
  loader: {
    ".woff": "file",
    ".woff2": "file",
    ".ttf": "file",
    ".eot": "file",
    ".svg": "file",
    ".png": "file",
  },
  assetNames: "[name]",
  logLevel: "info",
  sourcemap: false,
  target: ["chrome120"],
});
