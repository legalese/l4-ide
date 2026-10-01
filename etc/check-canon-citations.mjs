#!/usr/bin/env node
// Do this repository's prose citations INTO legalese/canon still resolve?
//
// We cite canon from `skills/`, `specs/` and `doc/`: a section of a subject's
// NOTES.md, a file:line inside an encoding, a count of its assertions. Each is a
// claim about ANOTHER REPOSITORY, and a section number always LOOKS right, so
// nothing notices when canon renumbers, reflows or grows. That is the drift the
// user-level CLAUDE.md's rule 3 is about, and this is the check for it.
//
// It matters more than an ordinary stale link because `skills/writing-l4-rules/`
// is DUPLICATED into legalese/l4-plugin and shipped as a marketplace bundle, so a
// citation that rots here rots in two repositories at once.
//
// THREE CLASSES, AND ONLY ONE OF THEM NEEDS CANON ON DISK:
//
//   l4-line   `ofek-pay.l4:64` — resolved against the VENDORED MIRROR under
//             jl4/examples/canon/, so it runs anywhere this repo is checked out,
//             including CI, with no canon and no network.
//   count     "263 `#ASSERT`s across its nine modules" — RECOUNTED from the same
//             mirror. This is the claim likeliest to rot, because a number that
//             was measured once reads exactly like a number that is still true.
//   notes     "`NOTES.md` §9" — NOT mirrored: the pin's allowlist carries *.l4,
//             tests/*.golden, encoding.json, SOURCE-LICENSE.md and
//             registers/*.json, and no prose.
//             Needs a canon checkout, so it SKIPS with a PRINTED note by default
//             (a silent skip would read as a pass) and is fatal under --require.
//
// Usage:  node etc/check-canon-citations.mjs [--require] [--canon DIR]
//         node etc/check-canon-citations.mjs --selftest
// Exit:   0 every resolvable citation resolved · 1 a citation is stale
//         2 --require was given and canon could not be found · 3 selftest failed

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ROOTS = ["skills", "specs", "doc"];

const NUM = {
  nine: 9,
  eight: 8,
  seven: 7,
  six: 6,
  five: 5,
  four: 4,
  three: 3,
  two: 2,
};

// ---------------------------------------------------------------------------
// The scan, with every filesystem touch behind `fsx` so --selftest can drive it
// over fixtures. A checker whose detection logic can only be exercised against
// the real tree is a checker whose green is unfalsifiable.
// ---------------------------------------------------------------------------
export function scanText(text, rel, fsx) {
  const findings = [];
  const skipped = [];
  let checked = 0;
  const lineOf = (i) => text.slice(0, i).split("\n").length;

  const subjects = [...text.matchAll(/subjects\/([a-z]{2}\/[a-z0-9-]+)/g)];
  const subjectAt = (i) => {
    let best = null;
    for (const s of subjects) if (s.index < i && i - s.index < 400) best = s[1];
    return best;
  };

  // --- l4-line --------------------------------------------------------------
  for (const m of text.matchAll(/`([a-z0-9][a-z0-9-]*\.l4):(\d+(?:,\d+)*)`/g)) {
    const to = fsx.mirrorOf(subjectAt(m.index));
    if (!to) continue; // not a blessed subject: nothing local to check against
    const path = `${to}/${m[1]}`;
    checked++;
    if (!fsx.exists(path)) {
      findings.push(
        `${rel}:${lineOf(m.index)} cites ${m[1]}, which is not in the mirror at ${to}/`,
      );
      continue;
    }
    // Strip ONE trailing newline before counting. A well-formed text file ends
    // with one, and splitting on "\n" then yields a phantom final element -- so
    // a citation to exactly one line past the end would have resolved. Found by
    // --selftest, not by reading the code.
    const n = fsx.read(path).replace(/\n$/, "").split("\n").length;
    for (const l of m[2].split(",").map(Number))
      if (l > n)
        findings.push(
          `${rel}:${lineOf(m.index)} cites ${m[1]}:${l} but that file has ${n} lines`,
        );
  }

  // --- count ----------------------------------------------------------------
  for (const m of text.matchAll(
    /(\d+)\s+`?#ASSERT`?s?\s+across\s+its\s+(\w+)\s+modules/gi,
  )) {
    const subject = subjectAt(m.index);
    const to = fsx.mirrorOf(subject);
    if (!to || !fsx.exists(to)) continue;
    const mods = fsx.readdir(to).filter((f) => f.endsWith(".l4"));
    const total = mods.reduce(
      (a, f) =>
        a + (fsx.read(`${to}/${f}`).match(/^\s*#ASSERT\b/gm) ?? []).length,
      0,
    );
    const claimedMods = NUM[m[2].toLowerCase()] ?? Number(m[2]);
    checked++;
    if (Number(m[1]) !== total || claimedMods !== mods.length)
      findings.push(
        `${rel}:${lineOf(m.index)} claims ${m[1]} #ASSERTs across ${m[2]} modules for ${subject}; the mirror has ${total} across ${mods.length}`,
      );
  }

  // --- notes ----------------------------------------------------------------
  for (const m of text.matchAll(/`NOTES\.md`\s*§+\s*(\d+(?:\.\d+)?)/g)) {
    const subject = subjectAt(m.index);
    if (!subject) continue;
    const where = `${rel}:${lineOf(m.index)}`;
    const candidates = fsx.notesFor(subject);
    if (candidates === null) {
      skipped.push(`${where} NOTES.md §${m[1]} in ${subject}`);
      continue;
    }
    if (!candidates.length) {
      findings.push(
        `${where} cites ${subject}'s NOTES.md; canon has no NOTES.md for that subject`,
      );
      continue;
    }
    const heads = candidates.map((c) => fsx.read(c));
    const sectionRe = (n) =>
      new RegExp(`^#{2,4}\\s*${n.replace(".", "\\.")}[.\\s]`, "m");

    checked++;
    const re = sectionRe(m[1]);
    const hit = heads.find((h) => re.test(h));
    if (!hit) {
      findings.push(
        `${where} cites NOTES.md §${m[1]} in ${subject}, but no such section exists`,
      );
      continue;
    }

    const after = text.slice(m.index, m.index + 320);
    const tail = after.slice(m[0].length);

    // A quoted title belongs to THIS section only when no other § intervenes.
    // SKILL.md:200 reads "`NOTES.md` §9 ... and §9.2 — \"Ditto fails loudly …\"";
    // a checker that grabs the nearest quote after §9 reports a defect in prose
    // that is correct. Measured on that line, which is why this guard exists.
    const quoted = tail.match(/[—-]\s*"([^"]{12,})"/);
    const nextSection = tail.search(/§/);
    if (quoted && (nextSection < 0 || quoted.index < nextSection)) {
      const heading = hit.split("\n").find((l) => re.test(l));
      const norm = (s) =>
        s.replace(/[`*]/g, "").replace(/\s+/g, " ").trim().toLowerCase();
      if (heading && !norm(heading).includes(norm(quoted[1])))
        findings.push(
          `${where} quotes §${m[1]} as "${quoted[1]}" but the heading reads "${heading.replace(/^#+\s*/, "")}"`,
        );
    }

    // Follow-on references to the same file — "§9 … and §9.2". The subsection is
    // the likelier one to move, so it is the one most worth checking.
    for (const f of tail.matchAll(/§+\s*(\d+\.\d+)/g)) {
      checked++;
      if (!heads.some((h) => sectionRe(f[1]).test(h)))
        findings.push(
          `${where} also cites §${f[1]} in ${subject}'s NOTES.md, and no such section exists`,
        );
    }
  }

  return { findings, skipped, checked };
}

// ---------------------------------------------------------------------------
function walk(dir, pred, out = []) {
  for (const e of readdirSync(dir)) {
    if (e === "node_modules" || e === ".git") continue;
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, pred, out);
    else if (pred(e)) out.push(p);
  }
  return out;
}

function selftest() {
  // A synthetic subject, so the fixtures cannot be made to pass by the real tree
  // happening to agree with them.
  const MIRROR = "/mirror/xx/fixture-1999";
  const files = {
    [`${MIRROR}/a.l4`]: "line1\n#ASSERT one\nline3\n",
    [`${MIRROR}/b.l4`]: "#ASSERT two\n#ASSERT three\n",
    "/canon/NOTES.md": "## 1. First\n### 1.2 Second thing\n## 2. Other\n",
  };
  const fsx = {
    mirrorOf: (s) => (s === "xx/fixture-1999" ? MIRROR : null),
    exists: (p) => p === MIRROR || p in files,
    read: (p) => files[p] ?? "",
    readdir: () => ["a.l4", "b.l4"],
    notesFor: (s) => (s === "xx/fixture-1999" ? ["/canon/NOTES.md"] : []),
  };

  const cases = [
    [
      "l4-line beyond EOF",
      "`subjects/xx/fixture-1999` cites `a.l4:99`.",
      /has 3 lines/,
    ],
    [
      "l4-line to a missing file",
      "`subjects/xx/fixture-1999` cites `zzz.l4:1`.",
      /not in the mirror/,
    ],
    [
      "wrong assertion count",
      "`subjects/xx/fixture-1999` has 77 `#ASSERT`s across its two modules.",
      /the mirror has 3 across 2/,
    ],
    [
      "wrong module count",
      "`subjects/xx/fixture-1999` has 3 `#ASSERT`s across its nine modules.",
      /across 2/,
    ],
    [
      "missing section",
      "`subjects/xx/fixture-1999`, `NOTES.md` §7.",
      /no such section/,
    ],
    [
      "missing subsection",
      "`subjects/xx/fixture-1999`, `NOTES.md` §1 and §1.9.",
      /also cites §1\.9/,
    ],
    [
      "misquoted heading",
      '`subjects/xx/fixture-1999`, `NOTES.md` §1 — "a title it does not have".',
      /but the heading reads/,
    ],
  ];

  const good = [
    ["correct line", "`subjects/xx/fixture-1999` cites `a.l4:2`."],
    [
      "correct count",
      "`subjects/xx/fixture-1999` has 3 `#ASSERT`s across its two modules.",
    ],
    [
      "correct section + subsection",
      "`subjects/xx/fixture-1999`, `NOTES.md` §1 and §1.2.",
    ],
    ["correct quote", '`subjects/xx/fixture-1999`, `NOTES.md` §1 — "First".'],
    [
      "unblessed subject is not our business",
      "`subjects/zz/not-blessed` cites `a.l4:99999`.",
    ],
  ];

  let bad = 0;
  for (const [name, text, want] of cases) {
    const { findings } = scanText(text, "fixture.md", fsx);
    const ok = findings.some((f) => want.test(f));
    if (!ok) {
      bad++;
      console.error(`  MISSED  ${name}: got ${JSON.stringify(findings)}`);
    } else console.log(`  caught  ${name}`);
  }
  for (const [name, text] of good) {
    const { findings } = scanText(text, "fixture.md", fsx);
    if (findings.length) {
      bad++;
      console.error(`  FALSE+  ${name}: ${JSON.stringify(findings)}`);
    } else console.log(`  clean   ${name}`);
  }

  // The skip path must SAY it skipped. A silent skip is indistinguishable from a pass.
  const blind = { ...fsx, notesFor: () => null };
  const { skipped } = scanText(
    "`subjects/xx/fixture-1999`, `NOTES.md` §1.",
    "fixture.md",
    blind,
  );
  if (skipped.length !== 1) {
    bad++;
    console.error("  MISSED  absent canon must report a skip");
  } else console.log("  caught  absent canon reports a skip");

  console.log(
    bad
      ? `check-canon-citations: SELFTEST FAILED, ${bad} case(s)`
      : "check-canon-citations: selftest passed, 8 detections and 5 non-detections.",
  );
  return bad ? 3 : 0;
}

// ---------------------------------------------------------------------------
const argv = process.argv.slice(2);
if (argv.includes("--selftest")) process.exit(selftest());

const REQUIRE = argv.includes("--require");
const flag = argv.indexOf("--canon");
// An EXPLICIT --canon is validated exactly as a discovered one is. Taking the flag
// on trust turns "you pointed me at the wrong directory" into "all your citations
// are stale" — a confident wrong answer, which is the worst kind.
const CANON = validCanon(flag >= 0 ? argv[flag + 1] : findCanon());

function validCanon(dir) {
  if (dir && existsSync(join(dir, "subjects"))) return dir;
  if (dir)
    console.log(
      `check-canon-citations: ${dir} has no subjects/ — treating canon as absent.`,
    );
  return null;
}
function findCanon() {
  for (const c of [
    process.env.CANON_DIR,
    resolve(REPO, "../canon"),
    resolve(REPO, "../../canon"),
    join(process.env.HOME ?? "", "src/legalese/canon"),
  ])
    if (c && existsSync(join(c, "subjects"))) return c;
  return null;
}

const pin = JSON.parse(readFileSync(join(REPO, "etc/canon-pin.json"), "utf8"));
const mirrorMap = new Map(
  pin.blessed.map((b) => [
    b.from.replace(/^subjects\//, "").replace(/\/encodings\/.*$/, ""),
    join(REPO, "jl4/examples/canon", b.to),
  ]),
);

const fsx = {
  mirrorOf: (s) => (s ? (mirrorMap.get(s) ?? null) : null),
  exists: existsSync,
  read: (p) => readFileSync(p, "utf8"),
  readdir: readdirSync,
  notesFor: (s) => {
    if (!CANON) return null;
    const base = join(CANON, "subjects", s);
    return existsSync(base) ? walk(base, (e) => e === "NOTES.md") : [];
  },
};

// `--dir A B ...` sweeps other trees instead of this repo's own. It exists for
// legalese/l4-plugin, which carries a HAND-SYNCED copy of skills/writing-l4-rules/
// and therefore its own copies of these citations. l4-ide must not DEPEND on
// l4-plugin (CLAUDE.md section 1.2's rule, applied to a sibling), so this is opt-in
// and never discovered: a maintainer points it there, CI does not.
const dirFlag = argv.indexOf("--dir");
const SWEEP =
  dirFlag >= 0
    ? argv.slice(dirFlag + 1).filter((a) => !a.startsWith("--"))
    : ROOTS;

const findings = [];
const skipped = [];
let checked = 0;
for (const root of SWEEP) {
  const dir = root.startsWith("/") ? root : join(REPO, root);
  if (!existsSync(dir)) continue;
  for (const file of walk(dir, (e) => e.endsWith(".md"))) {
    const r = scanText(
      readFileSync(file, "utf8"),
      file.slice(REPO.length + 1),
      fsx,
    );
    findings.push(...r.findings);
    skipped.push(...r.skipped);
    checked += r.checked;
  }
}

if (skipped.length) {
  console.log(
    `check-canon-citations: NOTE — ${skipped.length} NOTES.md citation(s) NOT checked; no canon checkout found.`,
  );
  for (const s of skipped) console.log(`  unchecked: ${s}`);
  console.log(
    "  set CANON_DIR=/path/to/legalese/canon (or pass --canon DIR) to check these.",
  );
  if (REQUIRE) {
    console.error(
      "check-canon-citations: --require given and canon is absent.",
    );
    process.exit(2);
  }
}
if (findings.length) {
  console.error(`check-canon-citations: ${findings.length} stale citation(s):`);
  for (const f of findings) console.error(`  ${f}`);
  console.error(
    "\nFix the citation here. If canon moved the thing being cited, cite its new place;\ndo not delete the citation to silence this. NOTE: skills/writing-l4-rules/ is\nduplicated into legalese/l4-plugin, so re-run etc/build-plugin-bundle.mjs after.",
  );
  process.exit(1);
}
console.log(
  `check-canon-citations: ${checked} citation(s) into legalese/canon all resolve${skipped.length ? ` (${skipped.length} unchecked, see note above)` : ""}.`,
);
