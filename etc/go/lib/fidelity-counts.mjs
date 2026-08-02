#!/usr/bin/env node
// Parse a `--fidelity-report` file into severity and code counts.
//
// The counts are PARSED, never typed. `jl4/examples/legal/regcf/PROJECTIONS.md`
// once carried "114 blocking, 46 lossy, 18 advisory" against an exporter that
// emitted different figures, because those numbers were transcribed once and
// never re-measured (repaired since — ORCHESTRATOR.md §1.1 D2 is the history).
// This module is why the go report cannot repeat that failure.
//
// Usage: node etc/go/lib/fidelity-counts.mjs FIDELITY.txt [--json]
// Output (default): "<blocking> <lossy> <advisory>" on one line, for `read`.

import { existsSync, readFileSync } from "node:fs";

const [, , file, ...rest] = process.argv;
if (!file) {
  process.stderr.write("usage: fidelity-counts.mjs FIDELITY.txt [--json]\n");
  process.exit(2);
}
if (!existsSync(file)) {
  process.stdout.write(
    rest.includes("--json")
      ? '{"blocking":0,"lossy":0,"advisory":0,"codes":{},"absent":true}\n'
      : "0 0 0\n",
  );
  process.exit(0);
}

const text = readFileSync(file, "utf8");
const severity = (name) =>
  (text.match(new RegExp(`\\]\\s+${name}\\b`, "g")) || []).length;
const codes = {};
for (const m of text.matchAll(/\[(D-[A-Z-]+)\]/g))
  codes[m[1]] = (codes[m[1]] ?? 0) + 1;

const out = {
  blocking: severity("blocking"),
  lossy: severity("lossy"),
  advisory: severity("advisory"),
  codes,
  absent: false,
};
process.stdout.write(
  rest.includes("--json")
    ? JSON.stringify(out) + "\n"
    : `${out.blocking} ${out.lossy} ${out.advisory}\n`,
);
