#!/usr/bin/env node
// One digest over the L4 standard library the run will actually resolve.
//
// WHY. Every module of every subject opens with `IMPORT prelude` and `IMPORT
// daydate` (measured: 7 of 7 for sg-succession), so those files are inputs to
// every `l4 check`, `l4 run`, `l4 export` and `l4 verify` the pipeline
// performs. They were in NO digest: not the gate's `GO_ENCODING_FILES`, not any
// stage's `--inputs`. And the path is an environment variable the driver
// exports with the caller's value winning:
//
//   export JL4_LIBRARY_PATH="${JL4_LIBRARY_PATH:-$GO_ROOT/jl4-core/libraries}"
//
// MEASURED. Copy the library directory, change `__GEQ__` on DATE from
// `AT LEAST` to `GREATER THAN` -- one word -- and point JL4_LIBRARY_PATH at the
// copy. `sg-paa.l4` still reports 79 assertions and 0 failures, byte-identical
// to the baseline, while a date-boundary EVAL goes TRUE -> FALSE. The whole
// evidence base is blind to a substitution that moves the answer.
//
// The driver already folds the `l4` binary's sha256 into every stage's digest,
// and its comment says exactly why: "the `l4` binary is an input to every stage
// and is declared by none: no phase script can see the path the driver was
// handed." JL4_LIBRARY_PATH is an input to every stage, declared by none, and
// invisible to every phase script, on identical terms. The reasoning was
// written and not applied to the second case. This applies it.
//
// Content and basename, not absolute path: two directories with identical bytes
// produce identical answers, so relocating the library -- or working in a
// second worktree -- must not invalidate a replay. The path is reported
// separately, for the reader.
//
// Usage:  stdlib-digest.mjs [DIR]      (default: $JL4_LIBRARY_PATH)
// Prints: one sha256 line. A missing or empty directory prints a NAMED
//         sentinel rather than a hash of nothing -- "no library directory" is a
//         distinct state from "an empty one", and both must move the digest
//         relative to a populated one.
import { existsSync, readdirSync, statSync } from "node:fs";
import { resolve } from "node:path";
import { sha256File, sha256Text } from "./ledger.mjs";

const dir = process.argv[2] || process.env.JL4_LIBRARY_PATH || "";

if (!dir) {
  process.stdout.write(sha256Text("jl4-library-path:unset") + "\n");
  process.exit(0);
}
if (!existsSync(dir) || !statSync(dir).isDirectory()) {
  process.stdout.write(sha256Text(`jl4-library-path:absent:${dir}`) + "\n");
  process.exit(0);
}

// Every `.l4` in the directory, sorted by digestSet. Not recursive: resolution
// is flat (a library is named by basename), so a subdirectory is not reachable
// as a library and hashing it would make an unrelated file move every digest.
const files = readdirSync(dir)
  .filter((f) => f.endsWith(".l4"))
  .sort()
  .map((f) => resolve(dir, f));

if (files.length === 0) {
  process.stdout.write(sha256Text(`jl4-library-path:empty:${dir}`) + "\n");
  process.exit(0);
}

// Keyed by BASENAME and not by absolute path -- deliberately NOT digestSet,
// whose serialisation is `${absolutePath}\t${size}\t${sha}`. A library is
// resolved by its basename (`IMPORT daydate` finds `daydate.l4` wherever the
// directory is), so basename plus content IS its identity, and two worktrees
// holding byte-identical libraries at different absolute paths must produce the
// same digest. Under digestSet they would not, and every stage in every
// worktree would re-execute for no reason -- which would make this fix look like
// a performance regression and get reverted.
const parts = files.map((p) => {
  const base = p.slice(p.lastIndexOf("/") + 1);
  return `${base}\t${statSync(p).size}\t${sha256File(p)}`;
});
process.stdout.write(sha256Text(parts.join("\n")) + "\n");
