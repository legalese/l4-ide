#!/usr/bin/env node
// The LTS leg's oracle.
//
// `l4 state-graph FILE` emits GraphViz DOT to stdout with ONE `digraph` block
// per regulative rule, concatenated. On its own that is a presence oracle: the
// file exists and is non-empty, which under etc/go/lib/verdict.mjs caps at
// UNVERIFIED.
//
// The cross-check that makes it structural: the number of `digraph` blocks must
// equal the number of regulative rules the BPMN discovery call independently
// reports. Two different code paths in the compiler have to agree about how
// many regulative rules the module has. MEASURED 2026-08-02 on the inaugural
// subject's corpus (the Reg CF encoding): 3 and 3.
//
// Usage:  node etc/go/lib/split-digraphs.mjs GRAPH.dot --expect N [--out DIR]
// Exit:   0 count matches · 1 count differs · 2 usage

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export function splitDigraphs(text) {
  const blocks = [];
  let current = null;
  let depth = 0;
  for (const line of text.split("\n")) {
    if (current === null) {
      const m = line.match(/^\s*(?:strict\s+)?digraph\b/);
      if (!m) continue;
      current = {
        name: (line.match(/digraph\s+("?)([^"{]*)\1/) || [, , ""])[2].trim(),
        lines: [line],
      };
      depth = (line.match(/{/g) || []).length - (line.match(/}/g) || []).length;
      if (depth <= 0) {
        blocks.push(current);
        current = null;
      }
      continue;
    }
    current.lines.push(line);
    depth += (line.match(/{/g) || []).length - (line.match(/}/g) || []).length;
    if (depth <= 0) {
      blocks.push(current);
      current = null;
    }
  }
  return blocks;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const file = args.find((a) => !a.startsWith("--"));
  const expectIdx = args.indexOf("--expect");
  const outIdx = args.indexOf("--out");
  if (!file || expectIdx < 0) {
    process.stderr.write(
      "usage: split-digraphs.mjs GRAPH.dot --expect N [--out DIR]\n",
    );
    process.exit(2);
  }
  const expect = Number(args[expectIdx + 1]);
  const blocks = splitDigraphs(readFileSync(file, "utf8"));

  if (outIdx >= 0) {
    const dir = args[outIdx + 1];
    mkdirSync(dir, { recursive: true });
    blocks.forEach((b, i) => {
      const safe =
        (b.name || `rule-${i + 1}`)
          .replace(/[^A-Za-z0-9._-]+/g, "-")
          .replace(/^-|-$/g, "") || `rule-${i + 1}`;
      writeFileSync(
        join(dir, `${String(i + 1).padStart(2, "0")}-${safe}.dot`),
        b.lines.join("\n") + "\n",
      );
    });
  }

  process.stdout.write(
    `split-digraphs: ${blocks.length} digraph block(s) in ${file}: ${blocks.map((b) => b.name || "(unnamed)").join(", ")}\n`,
  );
  if (blocks.length !== expect) {
    process.stderr.write(
      `split-digraphs: VERDICT: MISMATCH — ${blocks.length} digraph block(s) but the BPMN discovery call reports ${expect} regulative rule(s). ` +
        `Two independent code paths disagree about how many regulative rules this module has.\n`,
    );
    process.exit(1);
  }
  process.stdout.write(
    `split-digraphs: VERDICT: ${blocks.length} digraph blocks == ${expect} regulative rules reported by the BPMN discovery call\n`,
  );
  process.exit(0);
}
