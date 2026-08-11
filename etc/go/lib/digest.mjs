#!/usr/bin/env node
// One sha256 over a named set of files. Missing files are recorded ABSENT
// rather than skipped, so an input that disappears changes the digest and its
// stage re-runs instead of reporting `replayed`.
//
// Usage: node etc/go/lib/digest.mjs FILE…            (paths on argv)
//        node etc/go/lib/digest.mjs --stdin          (paths on stdin, one per line)

import { readFileSync } from "node:fs";
import { digestSet } from "./ledger.mjs";

const args = process.argv.slice(2);
let paths;
if (args.includes("--stdin")) {
  paths = readFileSync(0, "utf8")
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);
} else {
  paths = args;
}
if (paths.length === 0) {
  process.stderr.write("usage: digest.mjs FILE… | --stdin\n");
  process.exit(2);
}
process.stdout.write(digestSet(paths) + "\n");
