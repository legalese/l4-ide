#!/usr/bin/env node
// Every .l4 that jl4-test walks must ship its goldens in the same commit.
//
// Twice now a corpus has landed on `unstable` with its .l4 and without its
// `tests/` directory, turning the whole golden suite red for everyone: the BNA
// (repaired by PR #202) and the Jersey charities cleanroom (PR #212). Both times
// the offending PR's own CI was GREEN, because the paths filter that decides
// whether the Haskell job runs does not fire on a `.l4` under `examples/`. The
// failure therefore appears first on somebody else's branch, which is the worst
// possible place to discover it.
//
// This check needs no build, no GHC and no filter, so it runs on every event and
// fails the PR that introduces the gap rather than the next one to come along.
//
// The rule mirrors jl4/tests/Main.hs: every file handed to its `tests` helper is
// run through four goldens, each written to `<dir>/tests/<stem>.<suffix>`. That
// is the "ok files", "tc fails", "nlg fails" and "export placement" describes —
// the lsp/ globs use a different mechanism and are deliberately out of scope.

import { readdirSync, existsSync, statSync } from "node:fs";
import { join, dirname, basename, relative } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const examples = join(repoRoot, "jl4", "examples");

// Kept in step with jl4/tests/Main.hs's globDir1 calls, one entry per glob whose
// result reaches the `tests` helper. A root added there and not here is a silent
// hole, so every root is asserted to exist and to match at least one file —
// exactly the discipline Main.hs's own "corpus sanity" describe applies.
const ROOTS = [
  { label: "ok", dir: join(examples, "ok"), recursive: true },
  { label: "legal", dir: join(examples, "legal"), recursive: true },
  {
    label: "libraries",
    dir: join(repoRoot, "jl4-core", "libraries"),
    recursive: false,
  },
  { label: "tc-fails", dir: join(examples, "not-ok", "tc"), recursive: true },
  { label: "nlg-fails", dir: join(examples, "not-ok", "nlg"), recursive: true },
  {
    label: "export-placement",
    dir: join(examples, "not-ok"),
    recursive: false,
    only: (n) => n.startsWith("export-"),
  },
];
const SUFFIXES = ["golden", "ep.golden", "nlg.golden", "schema.golden"];

function walk(dir, recursive, only, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (recursive && entry.name !== "tests") walk(p, recursive, only, out);
    } else if (entry.name.endsWith(".l4") && (!only || only(entry.name))) {
      out.push(p);
    }
  }
  return out;
}

const missing = [];
let checked = 0;

for (const { label, dir, recursive, only } of ROOTS) {
  if (!existsSync(dir) || !statSync(dir).isDirectory()) {
    console.error(
      `check-corpus-goldens: ${relative(repoRoot, dir)} does not exist — either the tree moved or ` +
        `this script's ROOTS list has drifted from jl4/tests/Main.hs. Fix the list, do not delete the check.`,
    );
    process.exit(2);
  }
  const files = walk(dir, recursive, only);
  if (files.length === 0) {
    console.error(
      `check-corpus-goldens: the "${label}" root matched no .l4 files. A glob that matches nothing ` +
        `passes every check it makes, which is why Main.hs asserts the same thing.`,
    );
    process.exit(2);
  }
  for (const file of files) {
    checked++;
    const stem = basename(file, ".l4");
    const absent = SUFFIXES.map((s) =>
      join(dirname(file), "tests", `${stem}.${s}`),
    ).filter((g) => !existsSync(g));
    if (absent.length) missing.push({ file, absent });
  }
}

if (missing.length) {
  console.error(
    `check-corpus-goldens: ${missing.length} corpus file(s) have no goldens, so the golden suite is\n` +
      `red for everyone the moment this lands. jl4-test writes four goldens per .l4 into <dir>/tests/.\n`,
  );
  for (const { file, absent } of missing) {
    console.error(`  ${relative(repoRoot, file)}`);
    for (const g of absent)
      console.error(`      missing: ${relative(repoRoot, g)}`);
  }
  console.error(
    `\nTo generate them: run \`cabal test jl4-test\` once (it creates each golden and fails,\n` +
      `because failFirstTime is True), then run it again to prove the goldens hold, then commit\n` +
      `only the .golden files — .actual is gitignored. Read the new goldens before committing:\n` +
      `blessing output you have not looked at is how a wrong answer becomes the expected answer.`,
  );
  process.exit(1);
}

console.log(
  `check-corpus-goldens: ${checked} corpus file(s), each with all ${SUFFIXES.length} goldens present`,
);
