// Validate the emitted Catala goldens against the real Catala toolchain.
//
// This is R9 of specs/todo/CATALA-EXPORT-SPEC.md: **optional when present,
// never a build dependency**. Catala is an OCaml toolchain that has to be built
// from source on macOS arm64 (upstream ships Linux amd64 .deb only), so it is
// not on CI runners and must not be made a merge-queue requirement — the same
// posture etc/validate-dmn.mjs takes toward dmnmd. When the binaries are absent
// this script prints one clear SKIP line and exits 0. It exits non-zero only
// for a real failure: a golden the toolchain rejects.
//
// TWO LAYERS, and they are not the same claim:
//
//   1. `catala typecheck` -- the emitted module is well-formed Catala and its
//      types agree. This catches syntax and arity, and nothing semantic.
//   2. `clerk test` -- every ```catala-test-cli block in the golden is re-run
//      and its output compared. Those blocks hold values computed by *L4's*
//      evaluator (R7), and the Mode A/B equivalence grids emitted under R4, so
//      a green `clerk test` is the claim that matters: the two languages agree
//      on these points, and the exception ladders agree with the reference
//      rendering they were rewritten from.
//
// Layer 2 is why this harness exists at all. §10.3 records the ladder-direction
// bug that `catala typecheck` was green on and `clerk test` caught.
//
// USAGE
//
//   node etc/validate-catala.mjs                  # every golden under
//                                                 # jl4/examples/catala/expected/
//   node etc/validate-catala.mjs FILE...          # just these
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
// equal the capitalised basename of the file it is in, but our goldens are
// named after their L4 sources (`flat-tax.catala_en` declares `Module
// FlatTax`). So each golden is COPIED into a scratch directory under the name
// Catala wants before it is checked; the repo copy is never renamed and never
// written to. The scratch directory also needs a one-time `clerk start`, which
// writes clerk.toml and _build -- another reason not to do this in-tree.

import { readdir, mkdtemp, copyFile, rm } from "node:fs/promises";
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

const catala = discover("catala", "CATALA_EXE");
const clerk = discover("clerk", "CLERK_EXE");

if (!catala || !clerk) {
  const missing = [!catala && "catala", !clerk && "clerk"]
    .filter(Boolean)
    .join(" and ");
  console.log(
    `skipped: no catala toolchain (${missing} not found on PATH, in ` +
      `CATALA_EXE/CLERK_EXE, or in an opam switch). This validation is ` +
      `optional by design — see R9 in specs/todo/CATALA-EXPORT-SPEC.md.`,
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
  console.log(`skipped: no *.catala_en goldens under ${defaultDir}`);
  process.exit(0);
}

// `flat-tax.catala_en` -> `FlatTax.catala_en`, matching `> Module FlatTax`.
// This mirrors L4.Catala.IR.catUpper; a mismatch is a real failure, and the
// toolchain reports it as one rather than being silently papered over here.
function catalaFileName(golden) {
  const stem = basename(golden).replace(/\.catala_en$/, "");
  const camel = stem
    .split(/[-_ ]+/)
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join("");
  return `${camel}.catala_en`;
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
    const name = catalaFileName(golden);
    await copyFile(golden, join(work, name));
    staged.push({ golden, name });
  }

  // Layer 1: typecheck, per file, so a failure names the file.
  for (const { golden, name } of staged) {
    const tc = run(catala, ["typecheck", name], { cwd: work });
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
    console.log(`OK    ${golden}\n       catala typecheck: successful`);
  }

  if (failed > 0) {
    console.error(
      `\n${failed} file(s) failed typechecking; clerk test not run.`,
    );
    process.exit(1);
  }

  // Layer 2: one `clerk test` over the whole directory.
  const test = run(clerk, ["test"], { cwd: work });
  const out = `${test.stdout ?? ""}${test.stderr ?? ""}`;
  const tail = out.trim().split("\n").slice(-12).join("\n");
  if (test.status !== 0 || !/ALL TESTS PASSED/.test(out)) {
    console.error(`FAIL  clerk test\n${tail}`);
    process.exit(1);
  }
  console.log(`\nOK    clerk test over ${staged.length} file(s)\n${tail}`);
} finally {
  await rm(work, { recursive: true, force: true });
}

process.exit(0);
