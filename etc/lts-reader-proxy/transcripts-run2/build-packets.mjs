// Builds the twelve reader packets of RUN 2 (2026-09-21) from `manifest.json` and the
// per-contract `truth.json` question lists. One packet is the whole of what one reader saw.
//
// Run from the repo root:
//     node etc/lts-reader-proxy/transcripts-run2/build-packets.mjs
//
// It overwrites `packets/` in place, so a rerun against an unchanged `manifest.json` is a
// no-op and `git diff` is the check that the committed packets are the ones this script
// produces. It does NOT re-cut the artifacts — `prepare.sh` does that, and `manifest.json`
// must already be current for the packets to describe the tree.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const proxy = join(here, "..");
const out = join(here, "packets");

const INSTR =
  "Answer each question from this document alone. If it does not say, answer 'cannot tell from this' rather than guess.";

const manifest = JSON.parse(readFileSync(join(proxy, "manifest.json"), "utf8"));
mkdirSync(out, { recursive: true });

let n = 0;
for (const e of manifest) {
  const qs = JSON.parse(
    readFileSync(join(proxy, e.contract, "truth.json"), "utf8"),
  ).questions;
  if (qs.length !== 5) throw new Error(`${e.contract}: ${qs.length} questions`);

  const parts = ["Document", ""];
  if (e.artifact !== "A") {
    const h = readFileSync(
      join(proxy, e.contract, "history.txt"),
      "utf8",
    ).trimEnd();
    if (!h) throw new Error(`${e.contract}: empty history`);
    parts.push(h, "");
  } else if (e.history !== null) {
    throw new Error(`${e.contract} A: history is not null`);
  }
  parts.push(e.text.replace(/\n+$/, ""), "");
  parts.push(...qs, "");
  parts.push(INSTR, "");

  writeFileSync(join(out, `${e.contract}-${e.artifact}.txt`), parts.join("\n"));
  n++;
}
console.log(`packets written: ${n}`);
