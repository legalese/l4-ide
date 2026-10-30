// Validate the emitted Catala goldens against the real Catala toolchain.
//
// This is R9 of specs/todo/CATALA-EXPORT-SPEC.md: **optional when present,
// never a build dependency**. Catala is an OCaml toolchain that has to be built
// from source on macOS arm64 (upstream ships Linux amd64 .deb only), so it is
// on no runner unless a job installs it (the catala-validate job in
// .github/workflows/pr-checks.yml does, when its `catala` paths filter matches)
// and must not be made a merge-queue requirement — the same posture
// etc/validate-dmn.mjs takes toward dmnmd. When the binaries are absent this
// script prints one clear SKIP line and exits 0. It exits non-zero only for a
// real failure: a golden the toolchain rejects.
//
// WHICH CATALA. The supported release is Catala 1.3.0 (2026-09-30), and the
// catala-validate job in .github/workflows/pr-checks.yml installs exactly that.
// The goldens were first checked with upstream commit fdf4ccd5 (master of
// 2026-07-30, which reports itself as "1.2.1"); 1.3.0 contains that commit.
// NOT the 1.2.1 release tarball: on it `catala typecheck` and `catala proof`
// pass on all 12 goldens and `clerk test` fails 41 of 83 tests (legalese/l4-ide
// run 41010257517), because the release's `catala interpret -F json`
// pretty-prints and renders rationals as floats, where the goldens'
// catala-test-cli blocks hold the compact exact-rational form, and it crashes
// on an enum value. clerk's diff, Reference on the left and Result on the right
// (the box clips long lines):
//
//     {"result":"1/4"}        ╳{ "result": 0.25 }
//     {"result":"500"}        ╳{ "result": 500.0 }
//     Unexpected error: Invalid_argument of non exhaustive Json_encoding.st
//     'Upper'                 (imports.catala_en:87, #return code 125#)
//
// Layer 3 below reads both clerk summaries: the `files`/`tests` banner of
// fdf4ccd5 and 1.2.1, and 1.3.0's `Interpreted` row, which has no `tests` row.
//
// THREE LAYERS, and they are not the same claim:
//
//   1. `catala typecheck` -- the emitted module is well-formed Catala and its
//      types agree. This catches syntax and arity, and nothing semantic.
//   2. `catala proof` -- §8.4(b)'s proof pass. What it buys us here is
//      NoOverlappingExceptions: the Mode B ladders are built as a LINEAR chain
//      precisely so that two rungs can never both win, and this is the only
//      thing in the pipeline that would notice if a future edit to
//      `armLadder`/`provisoLadder` made them siblings again (a `Conflict` at
//      run time, which the agreement grid cannot see because it exercises the
//      same builder). Verified to bite: a hand-written pair of sibling
//      exceptions is reported as "At least two exceptions overlap for this
//      variable", with a counterexample.
//
//      Two limits, recorded rather than papered over. `catala proof` reports
//      through WARNINGS and exits 0 even when it finds something, so this
//      script greps rather than trusting the exit code. And its NoEmptyError
//      half is NOT enforced: Z3 cannot encode our structures ("[Z3 encoding]
//      EStruct unsupported" on statute) and reports "might return an empty
//      error" for scopes that demonstrably cannot (tariff's test scopes), so
//      enforcing it would fail on correct output. Those are printed as notes.
//   3. `clerk test` -- every ```catala-test-cli block in the golden is re-run
//      and its output compared. Those blocks hold values computed by *L4's*
//      evaluator (R7), and the Mode A/B equivalence grids emitted under R4, so
//      a green `clerk test` is the claim that matters: the two languages agree
//      on these points, and the exception ladders agree with the reference
//      rendering they were rewritten from.
//
// Layer 3 is why this harness exists at all. §10.3 records the ladder-direction
// bug that `catala typecheck` was green on and `clerk test` caught. Note that
// `clerk test` prints its ALL TESTS PASSED banner over ZERO tests and exits 0,
// and over a run that left a file out, so the banner alone is not evidence.
// The run is checked against the goldens instead: every staged file must be
// listed as run, with exactly as many tests as its golden declares (its
// catala-test-cli blocks plus its #[test] scopes), and the summary banner's
// total must be their sum.
//
// USAGE
//
//   node etc/validate-catala.mjs                  # every golden under
//                                                 # jl4/examples/catala/expected/
//   node etc/validate-catala.mjs FILE...          # just these
//   node etc/validate-catala.mjs --selftest       # the clerk-output checks
//                                                 # against canned output; needs
//                                                 # no toolchain
//
// FINDING THE TOOLCHAIN, in order:
//
//   CATALA_EXE / CLERK_EXE   explicit paths, checked first
//   PATH                     a plain `catala` / `clerk`
//   opam                     `opam exec --switch=$CATALA_OPAM_SWITCH -- ...`,
//                            switch defaulting to `catala`
//
// On the reference machine the third route is the live one:
//
//   node etc/validate-catala.mjs
//
// finds the `catala` opam switch by itself. See R9 for the build recipe.
//
// A NOTE ON FILE NAMES. Catala requires a module's `> Module Name` header to
// equal the file's basename with its first letter capitalised, but our goldens
// are named after their L4 sources (`flat-tax.catala_en` declares `Module
// FlatTax`, and no file named `flat-tax` can host any module at all, since `-`
// is not an identifier character). So each golden is COPIED into a scratch
// directory under the name Catala wants before it is checked; the repo copy is
// never renamed and never written to. The scratch directory also needs a
// one-time `clerk start`, which writes clerk.toml and _build -- another reason
// not to do this in-tree.
//
// The staged name is READ OUT OF THE FILE (its `> Module X` line) rather than
// re-derived from the basename by a second implementation of the mangling.
// That is deliberate: the previous version re-implemented `catUpper` in JS and
// diverged from it (it split on `_`, which the Haskell does not), so a golden
// could have been staged under a name its own header did not claim. Reading
// the header cannot diverge. Every OK line below names the staged file, so the
// evidence describes a command a reader can actually run.

import {
  readdir,
  mkdtemp,
  mkdir,
  copyFile,
  readFile,
  rm,
} from "node:fs/promises";
import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, dirname, resolve, basename } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const defaultDir = join(repoRoot, "jl4", "examples", "catala", "expected");

// ---------------------------------------------------------------------------
// Toolchain discovery
// ---------------------------------------------------------------------------

// Returns [argv0, ...prefixArgs] to prepend to a catala/clerk invocation, or
// null when that tool cannot be found by any route.
function discover(tool, envVar) {
  const explicit = process.env[envVar];
  if (explicit) {
    if (!existsSync(explicit)) {
      console.error(`FAIL  ${envVar}=${explicit} does not exist`);
      process.exit(2);
    }
    return { argv: [explicit], how: `${envVar}=${explicit}` };
  }

  if (spawnSync(tool, ["--version"], { encoding: "utf8" }).status === 0) {
    return { argv: [tool], how: `${tool} on PATH` };
  }

  const sw = process.env.CATALA_OPAM_SWITCH ?? "catala";
  const viaOpam = ["opam", "exec", "--switch", sw, "--", tool];
  const probe = spawnSync(viaOpam[0], [...viaOpam.slice(1), "--version"], {
    encoding: "utf8",
  });
  if (probe.status === 0) {
    return { argv: viaOpam, how: `opam switch '${sw}'` };
  }

  return null;
}

// ---------------------------------------------------------------------------
// Reading `clerk test`
// ---------------------------------------------------------------------------
//
// Three facts about clerk's output decide what this can trust, and each was
// measured on 2026-10-30 against fdf4ccd5, 1.2.1 and 1.3.0:
//
//   * `clerk test -v` prints one line per file it ran (fdf4ccd5 and 1.3.0; the
//     1.2.1 release prints the same lines for a plain `clerk test`):
//       __ 02-bands/Bands.catala_en: 10 / 10 tests passed
//     A file that is not listed was not run.
//   * The summary banner differs. fdf4ccd5 and 1.2.1 print a `files` row and a
//     `tests` row. 1.3.0 prints one row per backend (`Interpreted 0 75 75`) and
//     no `tests` row, so a parser that looks only for `tests` reads 0 from a
//     run in which every test passed.
//   * `ALL TESTS PASSED` is printed over zero tests, and over a run that left a
//     file out. Neither is a pass, so the count is checked against the goldens,
//     not against what clerk says about itself.
//
// What a golden declares: each ```catala-test-cli block is one test, and so is
// each `#[test]` scope. The counts add up to what clerk runs on every golden
// in the tree (12 files, 83 tests on 2026-10-30), so a difference is a finding.

const stripAnsi = (s) => s.replace(/\u001b\[[0-9;]*m/g, "");

function expectedTests(text) {
  const blocks = (text.match(/^```catala-test-cli/gm) ?? []).length;
  const scopes = (text.match(/^#\[test\]/gm) ?? []).length;
  return { blocks, scopes, total: blocks + scopes };
}

function perFileResults(clean) {
  const seen = new Map();
  for (const m of clean.matchAll(
    /^__ (\S+): (\d+) \/ (\d+) tests passed\s*$/gm,
  )) {
    seen.set(m[1], { passed: Number(m[2]), total: Number(m[3]) });
  }
  return seen;
}

// `tests` row (fdf4ccd5, 1.2.1) or `Interpreted` row (1.3.0): FAILED PASSED TOTAL.
function bannerTotals(clean) {
  const m = /^[\s┃|]*(tests|Interpreted)\s+(\d+)\s+(\d+)\s+(\d+)/m.exec(clean);
  return m
    ? {
        row: m[1],
        failed: Number(m[2]),
        passed: Number(m[3]),
        total: Number(m[4]),
      }
    : null;
}

// `staged`: [{ golden, name, dir, blocks, scopes, expected }]. Returns every
// way the run disagrees with the goldens, so one failure names all of them.
function checkClerk(out, status, staged) {
  const clean = stripAnsi(out);
  const problems = [];
  if (status !== 0) problems.push(`clerk test exited ${status}`);
  if (!/ALL TESTS PASSED/.test(clean)) {
    problems.push("clerk test did not print ALL TESTS PASSED");
  }
  const seen = perFileResults(clean);
  let expectedSum = 0;
  for (const s of staged) {
    expectedSum += s.expected;
    if (s.expected === 0) {
      problems.push(
        `${s.golden}: no catala-test-cli block and no #[test] scope; an ` +
          `emitted module with no test proves nothing`,
      );
      continue;
    }
    const key = `${s.dir}/${s.name}`;
    const r = seen.get(key);
    if (!r) {
      problems.push(
        `${s.golden}: clerk did not run it (no \`__ ${key}\` line)`,
      );
      continue;
    }
    seen.delete(key);
    if (r.total !== s.expected) {
      problems.push(
        `${s.golden}: clerk ran ${r.total} test(s) but the golden declares ` +
          `${s.expected} (${s.blocks} catala-test-cli block(s) + ${s.scopes} ` +
          `#[test] scope(s))`,
      );
    }
    if (r.passed !== r.total) {
      problems.push(`${s.golden}: ${r.passed} of ${r.total} tests passed`);
    }
  }
  for (const key of seen.keys()) {
    problems.push(`clerk ran ${key}, which this run did not stage`);
  }
  const banner = bannerTotals(clean);
  if (!banner) {
    problems.push(
      "could not read the summary banner: looked for a `tests` row " +
        "(fdf4ccd5, 1.2.1) and an `Interpreted` row (1.3.0)",
    );
  } else {
    if (banner.failed !== 0) {
      problems.push(`the ${banner.row} row reports ${banner.failed} failed`);
    }
    if (banner.total !== expectedSum) {
      problems.push(
        `the ${banner.row} row totals ${banner.total} test(s) but the ` +
          `goldens declare ${expectedSum}`,
      );
    }
  }
  return { problems, ran: banner ? banner.total : null, expected: expectedSum };
}

if (process.argv.includes("--selftest")) {
  const row = (label, f, p) =>
    `┃   ${label.padEnd(14)}${String(f).padStart(5)}${String(p).padStart(11)}${String(f + p).padStart(11)}   ${f ? "  0" : "100"} %  ┃`;
  const oldBanner = (n) =>
    [
      "┏━  ALL TESTS PASSED  ━┓",
      row("files", 0, 2),
      row("tests", 0, n),
      "┗━━┛",
    ].join("\n");
  const newBanner = (n) =>
    ["┏━  ALL TESTS PASSED  ━┓", row("Interpreted", 0, n), "┗━━┛"].join("\n");
  const line = (key, p, t) => `__ ${key}: ${p} / ${t} tests passed`;
  const file = (n, name) => ({
    golden: `${name}.catala_en`,
    name: `${name}.catala_en`,
    dir: name,
    blocks: n / 2,
    scopes: n / 2,
    expected: n,
  });
  const a = file(4, "a");
  const b = file(2, "b");
  const both = [a, b];
  const ok = [line("a/a.catala_en", 4, 4), line("b/b.catala_en", 2, 2)];
  const cases = [
    // [label, output, status, staged, substrings every problem list must have, or [] for none]
    ["the old banner, every file run", [...ok, oldBanner(6)], 0, both, []],
    ["1.3.0's banner, every file run", [...ok, newBanner(6)], 0, both, []],
    [
      "1.3.0's banner, a file left out",
      [line("a/a.catala_en", 4, 4), newBanner(4)],
      0,
      both,
      [
        "b.catala_en: clerk did not run it",
        "totals 4 test(s) but the goldens declare 6",
      ],
    ],
    [
      "a count that differs from the golden",
      [line("a/a.catala_en", 3, 3), line("b/b.catala_en", 2, 2), newBanner(5)],
      0,
      both,
      ["clerk ran 3 test(s) but the golden declares 4"],
    ],
    [
      "a failing test",
      [
        line("a/a.catala_en", 3, 4),
        line("b/b.catala_en", 2, 2),
        oldBanner(6).replace("ALL TESTS PASSED", "TESTS FAILED"),
      ],
      1,
      both,
      [
        "clerk test exited 1",
        "did not print ALL TESTS PASSED",
        "3 of 4 tests passed",
      ],
    ],
    [
      "a banner in neither layout",
      [...ok, "┏━  ALL TESTS PASSED  ━┓"],
      0,
      both,
      ["could not read the summary banner"],
    ],
    [
      "ANSI colour around the lines",
      ok.map((l) => `\u001b[32m${l}\u001b[0m`).concat(newBanner(6)),
      0,
      both,
      [],
    ],
    [
      "a golden with no tests",
      [...ok, newBanner(6)],
      0,
      [...both, { ...file(2, "c"), blocks: 0, scopes: 0, expected: 0 }],
      ["c.catala_en: no catala-test-cli block"],
    ],
  ];
  let bad = 0;
  for (const [label, lines, status, staged, wanted] of cases) {
    const { problems } = checkClerk(lines.join("\n"), status, staged);
    const joined = problems.join("\n");
    const good =
      wanted.length === 0
        ? problems.length === 0
        : wanted.every((w) => joined.includes(w));
    console.log(`${good ? "ok  " : "FAIL"}  ${label}`);
    if (!good) {
      bad++;
      console.log(
        `      wanted ${wanted.length ? JSON.stringify(wanted) : "no problems"}`,
      );
      console.log(`      got    ${JSON.stringify(problems)}`);
    }
  }
  const et = expectedTests(
    "```catala-test-cli\nx\n```\n#[test] declaration scope T:\n```catala-test-cli\n",
  );
  const etGood = et.blocks === 2 && et.scopes === 1 && et.total === 3;
  console.log(
    `${etGood ? "ok  " : "FAIL"}  expectedTests counts blocks and #[test] scopes`,
  );
  if (!etGood) bad++;
  console.log(
    bad ? `\nselftest: ${bad} failed` : "\nselftest: all checks passed",
  );
  process.exit(bad ? 1 : 0);
}

const catala = discover("catala", "CATALA_EXE");
const clerk = discover("clerk", "CLERK_EXE");

// Skipping is right on a laptop that has no OCaml and wrong on a machine that
// is supposed to be checking this. CATALA_CHECK_REQUIRED=1 turns every skip
// path into exit 1, exactly as KIE_CHECK_REQUIRED does for the DMN engines --
// so a runner that is meant to have the toolchain fails loudly instead of
// printing SKIP and reporting green. Without the knob there is no way to tell a
// real pass from a harness that did nothing, and "did nothing" is the failure
// this file exists to prevent.
const required = process.env.CATALA_CHECK_REQUIRED === "1";

if (!catala || !clerk) {
  const missing = [!catala && "catala", !clerk && "clerk"]
    .filter(Boolean)
    .join(" and ");
  const where =
    `${missing} not found on PATH, in CATALA_EXE/CLERK_EXE, or in an ` +
    `opam switch (tried switch \`${process.env.CATALA_OPAM_SWITCH ?? "catala"}\`)`;
  if (required) {
    console.error(
      `FAIL  CATALA_CHECK_REQUIRED=1 but the toolchain is absent: ${where}. ` +
        `Install it (recipe in R9 of specs/todo/CATALA-EXPORT-SPEC.md) or unset ` +
        `CATALA_CHECK_REQUIRED.`,
    );
    process.exit(1);
  }
  console.log(
    `skipped: no catala toolchain (${where}). This validation is ` +
      `optional by design — see R9 in specs/todo/CATALA-EXPORT-SPEC.md. ` +
      `Set CATALA_CHECK_REQUIRED=1 to make this a failure instead.`,
  );
  process.exit(0);
}

function run({ argv }, args, opts = {}) {
  return spawnSync(argv[0], [...argv.slice(1), ...args], {
    encoding: "utf8",
    ...opts,
  });
}

const version = (run(catala, ["--version"]).stdout ?? "").trim();
console.log(`catala: ${catala.how}${version ? ` (${version})` : ""}`);
console.log(`clerk:  ${clerk.how}`);

// ---------------------------------------------------------------------------
// Targets
// ---------------------------------------------------------------------------

async function targets() {
  const args = process.argv.slice(2);
  if (args.length > 0) return args.map((f) => resolve(f));
  if (!existsSync(defaultDir)) return [];
  const entries = await readdir(defaultDir);
  return entries
    .filter((f) => f.endsWith(".catala_en"))
    .sort()
    .map((f) => join(defaultDir, f));
}

const files = await targets();
if (files.length === 0) {
  // Also a do-nothing run, and under CATALA_CHECK_REQUIRED it is a failure for
  // the same reason: a goldens directory that has gone missing or empty must
  // not read as "everything validated".
  if (required) {
    console.error(
      `FAIL  CATALA_CHECK_REQUIRED=1 but there are no *.catala_en goldens ` +
        `under ${defaultDir} to validate.`,
    );
    process.exit(1);
  }
  console.log(`skipped: no *.catala_en goldens under ${defaultDir}`);
  process.exit(0);
}

// `flat-tax.catala_en` declaring `> Module FlatTax` -> `FlatTax.catala_en`.
// The name comes out of the file, never out of a second copy of the mangling.
async function catalaFileName(golden) {
  const text = await readFile(golden, "utf8");
  const m = /^>\s*Module\s+([A-Za-z][A-Za-z0-9_]*)/m.exec(text);
  if (!m) return null;
  return `${m[1]}.catala_en`;
}

// ---------------------------------------------------------------------------
// Check
// ---------------------------------------------------------------------------

const work = await mkdtemp(join(tmpdir(), "validate-catala-"));
let failed = 0;

try {
  // One `clerk start` for the directory, then every golden lands in it. clerk
  // discovers its targets from the directory, so `clerk test` at the end
  // covers all of them in one run -- which is also how the goldens' own
  // provenance note describes them being checked.
  const started = run(clerk, ["start"], { cwd: work });
  if (started.status !== 0) {
    console.error(
      `FAIL  clerk start failed in ${work}\n` +
        (started.stderr || started.stdout || "").trim(),
    );
    process.exit(2);
  }

  const staged = [];
  for (const golden of files) {
    if (!existsSync(golden)) {
      console.error(`FAIL  ${golden}  (no such file)`);
      failed++;
      continue;
    }
    const name = await catalaFileName(golden);
    if (!name) {
      console.error(
        `FAIL  ${golden}  (no \`> Module <Name>\` header: catala cannot load it)`,
      );
      failed++;
      continue;
    }
    // One subdirectory per golden, so that two goldens whose staged names
    // collide cannot silently overwrite one another. `clerk test` walks the
    // tree from the directory it is started in, so a single `clerk start` at
    // the top still covers all of them.
    //
    // The directory is numbered, and that is not decoration. 1.3.0's clerk
    // silently skips a directory named like another staged directory plus a
    // dash and a suffix: staged as `bands` and `bands-boolean-only`, it lists
    // and runs only `bands`, and still prints ALL TESTS PASSED (measured
    // 2026-10-30; `bands2`, `bandsx`, `xbands` and `bands_boolean_only` beside
    // `bands` are all run, and so are `01-bands` and `02-bands-boolean-only`).
    // Layer 3 notices a file clerk did not run, and names it.
    //
    // Two goldens that declare the same `> Module` name are a different
    // failure and a loud one: clerk 1.3.0 stops with "Conflicting module name".
    // So each golden's module name must be its own.
    const dir = `${String(staged.length).padStart(2, "0")}-${basename(golden).replace(/\.catala_en$/, "")}`;
    await mkdir(join(work, dir), { recursive: true });
    await copyFile(golden, join(work, dir, name));
    const declared = expectedTests(await readFile(golden, "utf8"));
    staged.push({
      golden,
      name,
      dir,
      blocks: declared.blocks,
      scopes: declared.scopes,
      expected: declared.total,
    });
  }

  // Layer 1: typecheck, per file, so a failure names the file.
  for (const { golden, name, dir } of staged) {
    const tc = run(catala, ["typecheck", `${dir}/${name}`], { cwd: work });
    const out = `${tc.stdout ?? ""}${tc.stderr ?? ""}`;
    if (tc.status !== 0 || !out.includes("Typechecking successful")) {
      console.error(
        `FAIL  ${golden}  (catala typecheck)\n` +
          out
            .trim()
            .split("\n")
            .map((l) => `       ${l}`)
            .join("\n"),
      );
      failed++;
      continue;
    }
    console.log(
      `OK    ${golden}\n       staged as ${dir}/${name}; catala typecheck: successful`,
    );
  }

  if (failed > 0) {
    console.error(
      `\n${failed} file(s) failed typechecking; clerk test not run.`,
    );
    process.exit(1);
  }

  // Layer 2: `catala proof`. It reports through warnings and exits 0 whatever
  // it finds, so the output is what is inspected, and only the overlapping
  // exceptions half is fatal -- see the header for why NoEmptyError is not.
  for (const { golden, name, dir } of staged) {
    const pf = run(catala, ["proof", `${dir}/${name}`], { cwd: work });
    const out = `${pf.stdout ?? ""}${pf.stderr ?? ""}`;
    if (pf.status !== 0) {
      console.error(
        `FAIL  ${golden}  (catala proof exited ${pf.status})\n` +
          out
            .trim()
            .split("\n")
            .map((l) => `       ${l}`)
            .join("\n"),
      );
      failed++;
      continue;
    }
    if (/exceptions overlap/.test(out)) {
      console.error(
        `FAIL  ${golden}  (catala proof: overlapping exceptions -- a Mode B ` +
          `ladder has sibling rungs that can both fire, which is a Conflict at ` +
          `run time)\n` +
          out
            .trim()
            .split("\n")
            .map((l) => `       ${l}`)
            .join("\n"),
      );
      failed++;
      continue;
    }
    const soft = [
      /might return an empty error/.test(out) && "NoEmptyError (not enforced)",
      /translation to Z3 failed/.test(out) && "Z3 encoding incomplete",
    ].filter(Boolean);
    console.log(
      `OK    ${golden}\n       catala proof: no overlapping exceptions` +
        (soft.length ? `; notes: ${soft.join(", ")}` : ""),
    );
  }

  if (failed > 0) {
    console.error(
      `\n${failed} file(s) failed catala proof; clerk test not run.`,
    );
    process.exit(1);
  }

  // Layer 3: one `clerk test` over the whole directory. `-v` is what makes
  // clerk list every file it ran, which is how a file it left out is seen.
  const test = run(clerk, ["test", "-v"], { cwd: work });
  const out = `${test.stdout ?? ""}${test.stderr ?? ""}`;
  const tail = stripAnsi(out).trim().split("\n").slice(-12).join("\n");
  const verdict = checkClerk(out, test.status, staged);
  if (verdict.problems.length > 0) {
    console.error(
      `FAIL  clerk test\n` +
        verdict.problems.map((p) => `       ${p}`).join("\n") +
        `\n${tail}`,
    );
    process.exit(1);
  }
  console.log(
    `\nOK    clerk test over ${staged.length} file(s), ${verdict.ran} test(s): ` +
      `every file ran, and each ran as many tests as its golden declares\n${tail}`,
  );
} finally {
  await rm(work, { recursive: true, force: true });
}

process.exit(0);
