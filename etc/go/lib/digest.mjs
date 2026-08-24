#!/usr/bin/env node
// One sha256 over a named set of files. Missing files are recorded ABSENT
// rather than skipped, so an input that disappears changes the digest and its
// stage re-runs instead of reporting `replayed`.
//
// Usage: node etc/go/lib/digest.mjs FILE…            (paths on argv)
//        node etc/go/lib/digest.mjs --stdin          (paths on stdin, one per line)
//        node etc/go/lib/digest.mjs --stdin --members-out FILE
//
// `--members-out` writes R4's read-set — the same set, ITEMISED — to FILE as
// JSON while still printing the digest to stdout, so the caller's
// `digest=$(digest.mjs …)` is unchanged. It is one flag and not a second
// invocation on purpose: the members and the digest must come from ONE pass
// over the files, or a file edited between two passes would produce a read-set
// that does not re-fold to its own digest and the integrity check in
// `readset.refold` would fire on a race rather than on a defect.

import { readFileSync, writeFileSync } from "node:fs";
import { digestMembers, digestSet, refold } from "./ledger.mjs";

const args = process.argv.slice(2);
const membersIdx = args.indexOf("--members-out");
const membersOut = membersIdx >= 0 ? args[membersIdx + 1] : null;
if (membersIdx >= 0 && !membersOut) {
  process.stderr.write("digest.mjs: --members-out needs a path\n");
  process.exit(2);
}

let paths;
if (args.includes("--stdin")) {
  paths = readFileSync(0, "utf8")
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);
} else {
  // Guarded on membersIdx >= 0: with no flag present membersIdx is -1, and an
  // unguarded `i !== membersIdx + 1` drops argv[0] — the first real path.
  paths =
    membersIdx >= 0
      ? args.filter((_, i) => i !== membersIdx && i !== membersIdx + 1)
      : args;
}
if (paths.length === 0) {
  process.stderr.write("usage: digest.mjs FILE… | --stdin [--members-out FILE]\n");
  process.exit(2);
}

// `digestSet` REMAINS THE AUTHORITY. It is the path that named every run
// directory and every gate binding already committed to `legalese/canon`, and
// deriving the printed digest from the members instead would put a second
// implementation in front of a frozen format — a change that would be invisible
// until every historical run id stopped corresponding to anything.
//
// So the members are checked AGAINST it rather than trusted in place of it.
// digestMembers and digestSet each walk the files, so a file rewritten between
// the two walks yields a read-set that does not prove its own digest. That is a
// race, not a defect, and the right response is to fail loudly at the point it
// happened rather than to record an unprovable read-set that would later look
// like tampering.
const digest = digestSet(paths);
if (membersOut) {
  const members = digestMembers(paths);
  const proof = refold(members);
  if (proof !== digest) {
    process.stderr.write(
      "digest.mjs: the itemised read-set does not re-fold to the digest —\n" +
        `  digest ${digest}\n  refold ${proof}\n` +
        "An input changed while it was being read. Nothing was written; re-run.\n",
    );
    process.exit(2);
  }
  writeFileSync(membersOut, JSON.stringify(members));
}
process.stdout.write(digest + "\n");
