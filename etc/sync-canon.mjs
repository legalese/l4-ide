#!/usr/bin/env node
// The vendored canon mirror: pull it, check it, bump it.
//
// Usage:
//   node etc/sync-canon.mjs --check          diff mirror against canon@pin (CI)
//   node etc/sync-canon.mjs --pull           rewrite the mirror from canon@pin
//   node etc/sync-canon.mjs --bump <sha>     repoint the pin, then pull
//   node etc/sync-canon.mjs --selftest       (also what CI runs)
//
// Exit: 0 clean · 1 findings · 2 usage · 3 canon unreachable at the pin
//
// --- what this is for --------------------------------------------------------
//
// `jl4/examples/legal/` is the language's regression corpus. Ruled 2026-09-15,
// a handful of directories in `legalese/canon` join it. They are VENDORED —
// copied into this tree at a pinned canon SHA — rather than checked out across
// a repo boundary in CI, because the cross-repo shape makes every
// output-changing compiler PR re-bless goldens in a second repo before it can
// merge (SPEC §5).
//
// A checked-in copy of somebody else's files is duplication. The pin plus this
// script's `--check` is what makes it DETECTED duplication rather than the
// silent kind: CI fails the moment the mirror and canon disagree.
//
// --- the one place the mirror is not verbatim, and why ------------------------
//
// jl4/tests/Main.hs derives a golden's path as
// `takeDirectory inputFile </> "tests"`. Two blessed directories keep a cases
// file at `cases/x.l4` while its goldens sit in the directory-level `tests/` —
// so the harness would look in `cases/tests/`, and canon has no `cases/tests/`
// anywhere (measured at the pin). The mirror therefore HOISTS `cases/*.l4` to
// the directory root. That is the only layout in which canon's own goldens are
// the ones the harness reads.
//
// The hoist is applied by `pathInMirror` alone, so `--check` maps canon paths
// through the same function and is not fooled by it. A collision — two source
// files landing on one mirror path — is REFUSED rather than resolved, because
// silently keeping one of them would drop a corpus file and still look green.
//
// MEASURED, not assumed: both layouts pass `l4 check` (imports resolve either
// way at this pin), so the hoist is about goldens only. Recorded because the
// obvious guess — that a nested file cannot find its sibling imports — is wrong
// and would have justified the same change for the wrong reason.
//
// --- goldens: whose are they? ------------------------------------------------
//
// SPEC §6 leaves ownership open. This implementation reads canon's goldens and
// does not write them back (no `--push-goldens`; see the Not built list in the
// spec). `--check` therefore reports a golden difference SEPARATELY from a
// source difference, and the rule is:
//
//     a differing SOURCE file (.l4, encoding.json, SOURCE-LICENSE.md) is FATAL
//     a differing GOLDEN is reported and is NOT fatal
//
// because a golden that differs means the compiler's output moved since canon
// last blessed — which is ordinary, is the reason the pin exists, and must not
// block an l4-ide PR on a second repository's blessing cadence. A differing
// source means somebody hand-edited the mirror, which is the thing the mirror
// is not for.

import { execFileSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "..");
const PIN_PATH = resolve(HERE, "canon-pin.json");
const MIRROR = resolve(REPO, "jl4", "examples", "canon");

const EXIT = { CLEAN: 0, FINDING: 1, USAGE: 2, UNREACHABLE: 3 };

export function readPin(path = PIN_PATH) {
  const p = JSON.parse(readFileSync(path, "utf8"));
  if (!/^[0-9a-f]{40}$/.test(p.sha ?? ""))
    throw new Error(`canon-pin.json: 'sha' must be 40 hex characters`);
  if (!Array.isArray(p.blessed) || !p.blessed.length)
    throw new Error("canon-pin.json: 'blessed' must be a non-empty array");
  for (const b of p.blessed)
    if (!b?.from || !b?.to)
      throw new Error("canon-pin.json: every blessed entry needs from and to");
  return p;
}

/** A file's classification. Goldens are reported apart from sources. */
export function classify(rel) {
  if (rel.endsWith(".golden")) return "golden";
  return "source";
}

/**
 * Which files of a blessed directory the mirror carries.
 *
 * An ALLOWLIST, not a denylist. The spec names what is in (.l4, tests/ goldens,
 * encoding.json, SOURCE-LICENSE.md) and what is out (source/raw, report/, app/)
 * — but canon directories also carry registers/, projections/, NOTES.md and
 * README.md, which the spec's out-list does not mention. A denylist would have
 * vendored those by silent default and grown the mirror every time canon grew a
 * new sibling directory. The cost is that a genuinely new kind of file needs an
 * edit here; that is the intended cost.
 */
export function included(rel) {
  // `.l4` IS SCOPED BY DIRECTORY, not admitted at any depth.
  //
  // An unscoped `endsWith(".l4")` looks harmless and is not. Live at this pin:
  // `subjects/il/ofek-hadash-2008/encodings/legalese/source/_salary-table-tail.l4`
  // is a BUILD FRAGMENT, not a module — it opens with a bare `§§`, has no
  // `IMPORT prelude`, and is concatenated by a python script in the same
  // directory. Vendoring it would promote it to a top-level corpus file and
  // demand four goldens for something that cannot stand alone. `ofek` is
  // unblessed today, so this is latent rather than live — and the pin's header
  // says it is unblessed only "until they have goldens", which is precisely the
  // day this would fire.
  //
  // So: a module at the directory root, or under `cases/`. Those are the two
  // layouts canon actually uses for modules at this pin.
  if (rel.endsWith(".l4"))
    return !rel.includes("/") || rel.startsWith("cases/");
  if (rel.startsWith("tests/") && rel.endsWith(".golden")) return true;
  return rel === "encoding.json" || rel === "SOURCE-LICENSE.md";
}

/**
 * Where a file of a blessed directory lands in the mirror, relative to <to>.
 *
 * THE HOIST LIVES HERE AND NOWHERE ELSE, so pull and check cannot disagree
 * about it.
 */
export function pathInMirror(rel) {
  if (rel.endsWith(".l4")) return rel.slice(rel.lastIndexOf("/") + 1);
  return rel;
}

function walk(root, base = "", out = []) {
  for (const e of readdirSync(join(root, base), { withFileTypes: true }).sort(
    (a, b) => (a.name < b.name ? -1 : 1),
  )) {
    const rel = base ? `${base}/${e.name}` : e.name;
    if (e.isDirectory()) walk(root, rel, out);
    else out.push(rel);
  }
  return out;
}

/** The mirror as canon-at-the-pin says it should be: mirrorRel -> absolute source. */
export function plan(canonRoot, pin) {
  const want = new Map();
  const collisions = [];
  for (const b of pin.blessed) {
    const src = join(canonRoot, b.from);
    if (!existsSync(src))
      throw new Error(
        `blessed directory is not present at the pin: ${b.from}\n` +
          `  The pin is ${pin.sha} on ${pin.repo}${pin.ref ? ` (${pin.ref})` : ""}.\n` +
          `  A SHA on a person's shelf can be rebased away; re-pin with --bump <sha>.`,
      );
    for (const rel of walk(src)) {
      if (!included(rel)) continue;
      const to = `${b.to}/${pathInMirror(rel)}`;
      if (want.has(to))
        collisions.push(
          `${to} <- both ${b.from}/${rel} and ${relative(canonRoot, want.get(to))}`,
        );
      want.set(to, join(src, rel));
    }
  }
  if (collisions.length)
    throw new Error(
      `the hoist collides — two source files would land on one mirror path:\n` +
        collisions.map((c) => `  ${c}`).join("\n") +
        `\nRefusing rather than picking one: keeping either would drop a corpus file and still look green.`,
    );
  return want;
}

/** Fetch canon at the pin into a temp dir. Public repo, so no token. */
export function fetchCanon(pin, { quiet = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "canon-pin-"));
  const url = `https://github.com/${pin.repo}.git`;
  const run = (args, cwd) =>
    execFileSync("git", args, {
      cwd,
      encoding: "utf8",
      stdio: quiet ? ["ignore", "pipe", "pipe"] : "inherit",
    });
  try {
    run(["init", "--quiet", dir], undefined);
    run(["remote", "add", "origin", url], dir);
    // One commit, no blobs we do not need. `fetch <sha>` works on GitHub
    // because uploadpack.allowReachableSHA1InWant is on for public repos; if it
    // ever is not, this is where it fails and it fails loudly.
    run(["fetch", "--quiet", "--depth", "1", "origin", pin.sha], dir);
    run(["checkout", "--quiet", "FETCH_HEAD"], dir);
  } catch (e) {
    rmSync(dir, { recursive: true, force: true });
    const err = new Error(
      `could not fetch ${pin.repo} at ${pin.sha}:\n  ${String(e.stderr || e.message).trim()}`,
    );
    err.exitCode = EXIT.UNREACHABLE;
    throw err;
  }
  return dir;
}

function readIf(p) {
  try {
    return readFileSync(p);
  } catch {
    return null;
  }
}

/**
 * Files under the mirror that git ignores, and which are therefore not part of
 * the mirror at all.
 *
 * `jl4-test` writes a `<stem>.actual` beside every golden it compares, and
 * `.gitignore` has ignored `*.actual` since long before this mirror existed. A
 * raw directory walk counts all sixty of them as EXTRA and fails — MEASURED,
 * the first time the suite was run in this worktree before `--check` was.
 *
 * That failure is the worst kind: it fires only for someone who has just run the
 * tests, never in CI (a fresh checkout has no build output), so the person who
 * sees it is the person least able to believe it, and the fix they would reach
 * for is to stop trusting the check.
 *
 * One `git check-ignore` call for the whole set, not one per file. A repository
 * where git is unavailable degrades to the raw walk rather than throwing,
 * because a mirror check is not the place to fail over a missing tool.
 */
function gitIgnored(paths) {
  if (!paths.length) return new Set();
  try {
    const out = execFileSync("git", ["check-ignore", "--stdin"], {
      cwd: REPO,
      input: paths.map((p) => join(MIRROR, p)).join("\n"),
      encoding: "utf8",
      stdio: ["pipe", "pipe", "ignore"],
    });
    return new Set(
      out
        .split("\n")
        .filter(Boolean)
        .map((abs) => relative(MIRROR, abs)),
    );
  } catch (e) {
    // exit 1 means "none of them are ignored", which is not an error.
    if (e.status === 1) return new Set();
    return new Set();
  }
}

/** Compare the mirror on disk against a plan. */
export function diffMirror(want) {
  const walked = existsSync(MIRROR) ? walk(MIRROR) : [];
  const ignored = gitIgnored(walked);
  const have = walked.filter((rel) => !ignored.has(rel));
  const haveSet = new Set(have);
  const findings = { missing: [], extra: [], differing: [] };
  for (const [rel, srcAbs] of want) {
    if (!haveSet.has(rel)) {
      findings.missing.push(rel);
      continue;
    }
    const a = readIf(join(MIRROR, rel));
    const b = readIf(srcAbs);
    if (!a || !b || !a.equals(b)) findings.differing.push(rel);
  }
  for (const rel of have) {
    // README.md is this repo's own, not canon's: it explains the mirror to a
    // reader who finds it. It is the one file here with no canon counterpart,
    // and exempting it by name keeps `--check` from demanding its deletion.
    if (rel === "README.md") continue;
    if (!want.has(rel)) findings.extra.push(rel);
  }
  return findings;
}

function report(findings) {
  const sources = [...findings.missing, ...findings.extra].concat(
    findings.differing.filter((f) => classify(f) === "source"),
  );
  const goldens = findings.differing.filter((f) => classify(f) === "golden");
  const out = [];
  if (findings.missing.length)
    out.push(
      `MISSING from the mirror (${findings.missing.length}):`,
      ...findings.missing.map((f) => `  ${f}`),
    );
  if (findings.extra.length)
    out.push(
      `EXTRA in the mirror, not in canon at the pin (${findings.extra.length}):`,
      ...findings.extra.map((f) => `  ${f}`),
    );
  const diffSrc = findings.differing.filter((f) => classify(f) === "source");
  if (diffSrc.length)
    out.push(
      `DIFFERING sources (${diffSrc.length}) — the mirror was hand-edited, or the pin moved without a pull:`,
      ...diffSrc.map((f) => `  ${f}`),
    );
  if (goldens.length)
    out.push(
      `DIFFERING goldens (${goldens.length}) — NOT fatal:`,
      ...goldens.map((f) => `  ${f}`),
      `  THIS SCRIPT CANNOT TELL WHY. Two causes produce the identical diff: the`,
      `  compiler's output moved since canon last blessed (ordinary, and the reason the`,
      `  pin exists), or somebody hand-edited the mirror to make a red suite green`,
      `  (which is the thing the mirror is not for). It is non-fatal because treating`,
      `  the first as fatal would block every l4-ide PR on canon's blessing cadence —`,
      `  not because the second has been ruled out. Check the diff before believing it.`,
      `  The legitimate route is: re-bless in canon, then --bump the pin.`,
    );
  return { text: out.join("\n"), fatal: sources.length > 0, goldens };
}

function doPull(pin, canonRoot) {
  const want = plan(canonRoot, pin);
  // The mirror is rewritten, not merged: a file canon dropped must disappear
  // here too, and a merge would leave it behind looking blessed.
  const keptReadme = readIf(join(MIRROR, "README.md"));
  rmSync(MIRROR, { recursive: true, force: true });
  for (const [rel, srcAbs] of want) {
    const dest = join(MIRROR, rel);
    mkdirSync(dirname(dest), { recursive: true });
    cpSync(srcAbs, dest);
  }
  if (keptReadme) writeFileSync(join(MIRROR, "README.md"), keptReadme);
  return want.size;
}

// ---------------------------------------------------------------- selftest ---
//
// Each case mutates a fake mirror and asserts the finding. The three GM named
// are the three that matter: a hand-edited mirror, a pin moved without a pull,
// and a stale-in-canon golden — and the third must NOT be fatal, which is the
// only one of the three where the interesting assertion is a negative.
function selftest() {
  let bad = 0;
  const ok = (name, cond) => {
    process.stdout.write(`${cond ? "ok  " : "FAIL"} ${name}\n`);
    if (!cond) bad++;
  };

  const root = mkdtempSync(join(tmpdir(), "sync-canon-st-"));
  const canon = join(root, "canon");
  const mk = (p, body) => {
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, body);
  };
  const from = "subjects/x/encodings/legalese";
  mk(join(canon, from, "a.l4"), "A\n");
  mk(join(canon, from, "cases", "c.l4"), "C\n");
  mk(join(canon, from, "tests", "a.golden"), "GA\n");
  mk(join(canon, from, "tests", "c.golden"), "GC\n");
  mk(join(canon, from, "encoding.json"), "{}\n");
  // `.l4`, NOT `.md`: a fixture that plants an extension the allowlist would
  // reject anyway tests nothing. This one fails against the unscoped rule.
  mk(join(canon, from, "report", "big.l4"), "ignored\n");
  mk(join(canon, from, "source", "_fragment.l4"), "ignored\n");
  mk(join(canon, from, "registers", "r.json"), "ignored\n");
  const pin = { repo: "r", sha: "0".repeat(40), blessed: [{ from, to: "x" }] };

  const want = plan(canon, pin);
  ok(
    "the allowlist keeps report/ and registers/ out of the mirror",
    ![...want.keys()].some((k) => /report|registers/.test(k)),
  );
  ok(
    "...including a .l4 inside them — the extension alone does not admit a file",
    !want.has("x/big.l4") && !want.has("x/_fragment.l4"),
  );
  ok(
    "a cases/ file is HOISTED to the directory root, where its golden is",
    want.has("x/c.l4") && !want.has("x/cases/c.l4"),
  );
  ok(
    "and its golden keeps the path canon gave it",
    want.has("x/tests/c.golden"),
  );

  // "mirror hand-edited" — a source difference, fatal.
  {
    const f = { missing: [], extra: [], differing: ["x/a.l4"] };
    const r = report(f);
    ok("a hand-edited SOURCE file is fatal", r.fatal === true);
    ok("and is named in the output", /x\/a\.l4/.test(r.text));
  }
  // "pin moved without pull" — presents as missing/extra, fatal.
  {
    const r = report({
      missing: ["x/new.l4"],
      extra: ["x/gone.l4"],
      differing: [],
    });
    ok("a pin moved without a pull is fatal", r.fatal === true);
    ok(
      "and distinguishes what is missing from what is left over",
      /MISSING/.test(r.text) && /EXTRA/.test(r.text),
    );
  }
  // "canon golden stale" — reported, NOT fatal. The negative is the point.
  {
    const r = report({
      missing: [],
      extra: [],
      differing: ["x/tests/a.golden"],
    });
    ok("a differing GOLDEN is reported", /DIFFERING goldens/.test(r.text));
    ok("...and is NOT fatal", r.fatal === false);
    ok(
      "...and the output says why it is not fatal",
      /would block every l4-ide PR on canon's blessing cadence/.test(r.text),
    );
    ok(
      "...and refuses to claim it knows WHY the golden differs",
      /CANNOT TELL WHY/.test(r.text),
    );
  }
  // A golden and a source differing together: still fatal, both reported.
  {
    const r = report({
      missing: [],
      extra: [],
      differing: ["x/a.l4", "x/tests/a.golden"],
    });
    ok(
      "a golden difference does not mask a source difference",
      r.fatal === true && /DIFFERING goldens/.test(r.text),
    );
  }
  // The hoist must refuse a collision rather than silently drop a file.
  {
    mk(join(canon, from, "cases", "a.l4"), "COLLIDE\n");
    let threw = null;
    try {
      plan(canon, pin);
    } catch (e) {
      threw = e.message;
    }
    ok(
      "a hoist collision is REFUSED",
      threw !== null && /collides/.test(threw),
    );
    ok(
      "and names both sources so the fix is obvious",
      threw !== null && /cases\/a\.l4/.test(threw),
    );
    rmSync(join(canon, from, "cases", "a.l4"));
  }
  // A blessed dir absent at the pin is a loud failure, not an empty mirror.
  {
    let threw = null;
    try {
      plan(canon, { ...pin, blessed: [{ from: "subjects/nope", to: "n" }] });
    } catch (e) {
      threw = e.message;
    }
    ok(
      "a blessed directory missing at the pin fails loudly",
      threw !== null && /not present at the pin/.test(threw),
    );
    ok(
      "and says a shelf SHA can be rebased away",
      threw !== null && /rebased away/.test(threw),
    );
  }
  // The pin file itself is validated.
  {
    const p = join(root, "bad.json");
    writeFileSync(p, JSON.stringify({ sha: "nope", blessed: [{}] }));
    let threw = null;
    try {
      readPin(p);
    } catch (e) {
      threw = e.message;
    }
    ok("a malformed sha is refused", threw !== null && /40 hex/.test(threw));
  }

  // BUILD OUTPUT IN THE MIRROR MUST NOT READ AS A DIFFERENCE. This one runs
  // against the REAL mirror, because what it pins is the interaction between
  // this script and the repository's own .gitignore, and a fake tree would not
  // have one. It writes a single ignored file and removes it in `finally`.
  if (existsSync(MIRROR)) {
    const probe = join(MIRROR, "__selftest_probe.actual");
    try {
      writeFileSync(probe, "build output\n");
      ok(
        "a gitignored .actual beside a golden is NOT an EXTRA file",
        gitIgnored([relative(MIRROR, probe)]).size === 1,
      );
    } finally {
      rmSync(probe, { force: true });
    }
  } else {
    process.stdout.write("skip .actual probe — no mirror on disk\n");
  }

  rmSync(root, { recursive: true, force: true });
  process.stdout.write(
    bad
      ? `\nsync-canon selftest: ${bad} FAILED\n`
      : `\nsync-canon selftest: all checks passed\n`,
  );
  return bad ? EXIT.FINDING : EXIT.CLEAN;
}

// -------------------------------------------------------------------- CLI ---
if (import.meta.url === `file://${process.argv[1]}`) {
  const argv = process.argv.slice(2);
  const mode = argv[0];
  if (mode === "--selftest") process.exit(selftest());

  if (!["--check", "--pull", "--bump"].includes(mode)) {
    process.stderr.write(
      "usage: sync-canon.mjs --check | --pull | --bump <sha> | --selftest\n",
    );
    process.exit(EXIT.USAGE);
  }

  let pin;
  try {
    pin = readPin();
  } catch (e) {
    process.stderr.write(`sync-canon: ${e.message}\n`);
    process.exit(EXIT.USAGE);
  }

  if (mode === "--bump") {
    const sha = argv[1];
    if (!/^[0-9a-f]{40}$/.test(sha ?? "")) {
      process.stderr.write("sync-canon: --bump needs a 40-hex sha\n");
      process.exit(EXIT.USAGE);
    }
    const raw = readFileSync(PIN_PATH, "utf8");
    writeFileSync(
      PIN_PATH,
      raw.replace(/("sha":\s*")[0-9a-f]{40}(")/, `$1${sha}$2`),
    );
    process.stderr.write(`sync-canon: pin -> ${sha}\n`);
    pin = readPin();
  }

  let canonRoot;
  try {
    canonRoot = fetchCanon(pin);
  } catch (e) {
    process.stderr.write(`sync-canon: ${e.message}\n`);
    process.exit(e.exitCode ?? EXIT.FINDING);
  }

  try {
    if (mode === "--check") {
      const findings = diffMirror(plan(canonRoot, pin));
      const r = report(findings);
      if (r.text) process.stderr.write(r.text + "\n");
      if (r.fatal) {
        process.stderr.write(
          `\nsync-canon: the mirror does not match ${pin.repo}@${pin.sha.slice(0, 12)}.\n` +
            `  Do not fix this by editing jl4/examples/canon/ — it is a copy.\n` +
            `  Edit in canon and \`node etc/sync-canon.mjs --bump <sha>\`, or \`--pull\` if the pin is right.\n`,
        );
        process.exit(EXIT.FINDING);
      }
      process.stderr.write(
        r.goldens.length
          ? `sync-canon: sources match ${pin.repo}@${pin.sha.slice(0, 12)}; ` +
              `${r.goldens.length} golden(s) DIFFER (listed above, not fatal)\n`
          : `sync-canon: mirror matches ${pin.repo}@${pin.sha.slice(0, 12)}\n`,
      );
      process.exit(EXIT.CLEAN);
    }
    const n = doPull(pin, canonRoot);
    process.stderr.write(
      `sync-canon: mirror rewritten from ${pin.repo}@${pin.sha.slice(0, 12)} — ${n} file(s)\n`,
    );
    process.exit(EXIT.CLEAN);
  } catch (e) {
    process.stderr.write(`sync-canon: ${e.message}\n`);
    process.exit(EXIT.FINDING);
  } finally {
    rmSync(canonRoot, { recursive: true, force: true });
  }
}
