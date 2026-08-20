#!/usr/bin/env node
// Check a cross-run donor receipt's artifacts against what is on disk NOW,
// BEFORE any of them are copied into the borrowing run.
//
// WHY THIS EXISTS. receipt.mjs says, of within-run replay:
//
//   "On a replay, the artifact records are copied VERBATIM from the receipt
//    being replayed, not re-hashed from disk. Re-hashing would launder a file
//    that changed after the original receipt was written; copying keeps the
//    original sha256 so `go.sh verify` still compares it against what is on
//    disk now and reports CHANGED."
//
// The CROSS-RUN path cannot copy the records verbatim -- `--artifacts-from`
// resolves its hash inside the current journal, and a borrowed path would
// dangle once `gc` pruned the donor -- so it copies the FILES in and records
// them with `--artifact`, which re-hashes. That is precisely the laundering the
// comment forbids: a donor artifact tampered with after its receipt was written
// would report CHANGED under `verify` in its own run and `matches` in the
// borrowing one, because the borrowing receipt records the new hash as though
// it were the measured one.
//
// So the hash is checked HERE, against the donor's recorded value, and a
// mismatch refuses the replay rather than repairing it: if a donor artifact no
// longer matches its own receipt, that receipt is not evidence of anything and
// the stage should simply execute.
//
// Usage:  donor-check.mjs   (prior receipt JSON on stdin)
// Exit:   0 every artifact resolves and matches — safe to borrow
//         1 a finding, described on stderr — do not borrow, execute the stage
//         2 usage
import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { basename, resolve } from "node:path";

const sha256File = (p) =>
  "sha256:" + createHash("sha256").update(readFileSync(p)).digest("hex");

let raw = "";
process.stdin.on("data", (d) => (raw += d));
process.stdin.on("end", () => {
  let prior;
  try {
    prior = JSON.parse(raw);
  } catch {
    process.stderr.write("donor-check.mjs: stdin is not valid JSON\n");
    process.exit(2);
  }
  const fromDir = prior.from_dir || "";
  const artifacts = Array.isArray(prior.artifacts) ? prior.artifacts : [];
  const problems = [];

  // Basename collision. The copy path flattens every artifact to its basename
  // inside the borrowing run's artifacts/ directory, so two artifacts from
  // different subdirectories with the same basename would silently overwrite
  // each other and the receipt would name one file twice. p7-lts already writes
  // into a state-graphs/ subdirectory, so this is close to reachable rather
  // than theoretical.
  const byBase = new Map();
  for (const a of artifacts) {
    const b = basename(a.path ?? "");
    if (byBase.has(b))
      problems.push(
        `two artifacts share the basename '${b}' (${byBase.get(b)} and ${a.path}); the copy flattens to basename and one would overwrite the other`,
      );
    byBase.set(b, a.path);
  }

  for (const a of artifacts) {
    const declared = a.sha256;
    const base = basename(a.path ?? "");
    // Same resolution order the copy path uses: the donor run's artifacts
    // directory first, then the recorded path as an in-tree file.
    const candidates = [
      fromDir ? resolve(fromDir, "artifacts", base) : null,
      a.path,
    ].filter(Boolean);
    const found = candidates.find((c) => existsSync(c) && statSync(c).isFile());
    if (!found) {
      problems.push(
        `artifact '${a.path}' is gone: neither ${candidates.join(" nor ")} exists`,
      );
      continue;
    }
    if (!declared) {
      problems.push(`artifact '${a.path}' has no recorded sha256 to check`);
      continue;
    }
    const actual = sha256File(found);
    if (actual !== declared)
      problems.push(
        `artifact '${a.path}' has CHANGED since its receipt was written:\n` +
          `      receipt: ${declared}\n` +
          `      on disk: ${actual}  (${found})`,
      );
  }

  if (problems.length) {
    process.stderr.write(
      `donor-check: refusing to borrow this receipt — ${problems.length} problem(s):\n` +
        problems.map((p) => `    - ${p}\n`).join(""),
    );
    process.exit(1);
  }
  process.exit(0);
});
