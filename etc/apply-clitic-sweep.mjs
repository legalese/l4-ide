#!/usr/bin/env node
// apply-clitic-sweep — rename the fields `etc/check-clitic-verbs.mjs` finds.
//
// THE RULE IS THE DETECTOR'S. `'s` already reads as "is" and "has", so a field
// named `is bankrupt` says the verb twice; the name must start at the
// complement. This file does not restate that rule, does not carry its own idea
// of what an identifier looks like, and does not keep a second copy of the
// exemption list. It IMPORTS all of it:
//
//     CLITIC · DECL · EXEMPT · MARKER · EXTS · SKIP_DIRS · scanText · walk
//
// That import is the point of the file's shape. Two earlier appliers were
// written and thrown away (#386's, and this one's first draft), each with its
// own hand-rolled pattern, and a detector and applier that merely AGREE today
// are a pair that will disagree the first time either is tuned. There is one
// definition of a clitic-verb name in this repository and it lives next door.
//
// Usage:
//   node etc/apply-clitic-sweep.mjs --check    <dir>...   exit 1 if any pending
//   node etc/apply-clitic-sweep.mjs --dry-run  <dir>...   show them, exit 0
//   node etc/apply-clitic-sweep.mjs            <dir>...   apply them
//   node etc/apply-clitic-sweep.mjs --selftest
// Exit: 0 clean/applied · 1 pending (--check) or a hazard held one back · 2 usage
//
// --- WHAT IT REPLACES, AND WHAT IT REFUSES TO ------------------------------
//
// ONLY DELIMITED OCCURRENCES, in three forms:
//
//     `name`        backticked — how L4 spells an identifier
//     "name"        a whole JSON or JS string
//     \`name\`      an escaped backtick — L4 written inside a JS template literal
//
// The third is not hypothetical and was not obvious. MEASURED: sg-succession's
// `app/build-scenarios.mjs` generates L4 inside a template literal, so its
// identifiers are backslash-backtick, and the plain form does not match them.
// Without this case the applier silently skipped the file that generates the
// app's scenario fixtures — no error, just an app emitting the OLD field name
// against a swept encoding, disagreeing with the law it renders.
//
// NEVER BARE TEXT, and that is the load-bearing refusal. MEASURED in canon at
// `sg/child-support/registers/fork-register.json:341`, the phrase "is the
// natural father" occurs inside a QUOTATION OF THE STATUTE — "... if (a) the
// male employee is the natural father of the qualifying child". A bare-text
// sweep edits a legal quotation into something the Act does not say, silently.
// The same shape appears in a comment at `sg-csp.l4:332`. Delimiters are what
// separate an identifier from a sentence, which is why matching is defined by
// them and not by word boundaries.
//
// `tests/` is never entered: goldens are REGENERATED from swept sources by the
// l4 binary. Hand-editing a golden blesses output nothing produced.

import {
  readFileSync,
  writeFileSync,
  readdirSync,
  mkdtempSync,
  mkdirSync,
  rmSync,
  symlinkSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, extname, resolve, dirname, sep } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import {
  EXEMPT,
  EXTS,
  MARKER,
  SKIP_DIRS,
  scanText,
  walk,
} from "./check-clitic-verbs.mjs";

// The detector reads `.l4` and `.md`, because that is where the RULE applies.
// The rename has to reach further: a field name renamed in an encoding also
// appears in the deposit JSON that cites it and in the generators that emit it.
// Finding and rewriting are therefore scoped differently ON PURPOSE — names are
// discovered only where the detector looks, and rewritten wherever they are
// spelled with delimiters.
const WRITE_EXTS = new Set([
  ...EXTS,
  ".json",
  ".mjs",
  ".js",
  ".ts",
  ".py",
  ".html",
  ".txt",
]);

// The vendored mirror is a copy of `legalese/canon` at a pinned SHA. A sweep
// applied HERE makes the mirror disagree with its pin; `etc/sync-canon.mjs
// --check` then fails, and the edit has to be thrown away and redone upstream.
// Refusing is better than being caught: the fix is to sweep in canon and bump
// the pin. `--allow-mirror` exists for the caller doing exactly that.
//
// RESOLVED, NOT SPELLED, AND CHECKED PER FILE. The first version of this guard
// compared the ARGUMENT string against "jl4/examples/canon", and every one of
// these walked straight past it: "./jl4/examples/canon", an absolute path, and
// "jl4/examples/legal/../canon". Worse, and the reason it was a real bug rather
// than a tidiness point: a PARENT directory -- "jl4/examples", or "." -- contains
// the mirror without being it, so the most natural way to invoke the tool swept
// the mirror with no refusal at all. A guard on the input's spelling is not a
// guard on the operation. This resolves real paths, and the check runs at the
// moment of writing each file.
const REPO = dirname(dirname(fileURLToPath(import.meta.url)));
const MIRROR = resolve(REPO, "jl4", "examples", "canon");

// The mechanical rename: drop the leading clitic verb, keep the complement.
// Anything cleverer would be inventing a name in somebody else's corpus.
export function renameOf(name) {
  const m = /^(is|has)\s+(.+)$/s.exec(name);
  return m ? m[2].trim() : null;
}

// The delimited forms. Escaped-backtick is the most specific (the plain form is
// a substring of it), and `sweepText` sorts by length anyway so no form can
// claim a prefix of another.
//
// THE QUOTED FORM IS NOT OFFERED IN `.l4` OR `.md`, and that exclusion was
// missed on the first pass. In L4 a double-quoted run is a STRING LITERAL --
// data -- so `GIVETH \`label\` MEANS "is a Singapore citizen"` is a value that
// happens to read like a name, and rewriting it changes what the program says.
// In Markdown it is prose: `the employee "is a Singapore citizen" at the time`
// is a sentence with quotation marks, and rewriting it makes the page assert
// something nobody wrote. The form exists for deposit JSON and for generators,
// where a bare "name" really is a reference to a field.
//
// Backticks stay available everywhere, because a backtick is how L4 spells an
// identifier and nothing else uses it that way.
const QUOTED_UNSAFE = new Set([".l4", ".md"]);

export function formsFor(from, to, ext = null) {
  const forms = [
    ["\\`" + from + "\\`", "\\`" + to + "\\`"],
    ["`" + from + "`", "`" + to + "`"],
  ];
  if (!QUOTED_UNSAFE.has(ext)) forms.push(['"' + from + '"', '"' + to + '"']);
  return forms;
}

// ONE PASS over the text, never a sequence of passes. The first version applied
// each rename to the OUTPUT of the last, which is order-dependent and collapses
// two distinct fields into one whenever a rename's output is another's input:
//
//   [["has is bankrupt","is bankrupt"], ["is bankrupt","bankrupt"]]
//   "p's `has is bankrupt` AND p's `is bankrupt`"
//     -> "p's `bankrupt`   AND p's `bankrupt`"      two fields, one name
//
// Sorting the list differently only moves the failure. A single pass cannot see
// its own output, so the result does not depend on order at all.
//
// Pure, so the selftest can exercise it without a filesystem.
const RX_SPECIAL = /[.*+?^${}()|[\]\\]/g;

export function sweepText(text, renames, ext = null) {
  const pairs = [];
  for (const [from, to] of renames)
    for (const f of formsFor(from, to, ext)) pairs.push(f);
  if (!pairs.length) return { text, edits: 0 };
  // Longest first: a shorter form must never claim a prefix of a longer one.
  pairs.sort((a, b) => b[0].length - a[0].length);
  const map = new Map(pairs);
  const rx = new RegExp(
    pairs.map(([a]) => a.replace(RX_SPECIAL, "\\$&")).join("|"),
    "g",
  );
  let n = 0;
  const out = text.replace(rx, (m) => {
    n++;
    return map.get(m) ?? m;
  });
  return { text: out, edits: n };
}

// A rename is HELD BACK when its target name is already bound to something
// else. MEASURED: canon's `is the natural father` wanted to become `the natural
// father`, which already existed as a top-level MEANS fixture — a Person value
// used by #ASSERT — so the field would have collided with it and the fixture's
// own body would have read "`the natural father` IS TRUE" inside the definition
// of `the natural father`. Forcing it invents; the resolution was to rename the
// FIXTURE first, which is a judgement about that corpus and not a sweep's call.
export function hazards(renames, corpus) {
  const held = [];
  const safe = [];
  for (const [from, to] of renames) {
    const decl = new RegExp(
      "`" +
        to.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") +
        "`\\s+(MEANS|IS\\s+A|IS\\s+AN|IS\\s+THE)",
    );
    const site = corpus.find((c) => decl.test(c.text));
    if (site)
      held.push([
        from,
        to,
        `\`${to}\` is already bound at ${site.file} — rename that first`,
      ]);
    else safe.push([from, to]);
  }
  return { held, safe };
}

// Same discipline as the detector's own walk: lstat via withFileTypes, and
// symlinks are never followed. `.claude/skills/writing-l4-rules` is a git
// symlink to `skills/writing-l4-rules`, so a walk that follows it would rewrite
// the same file twice under two paths.
export function writeWalk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true }).sort((a, b) =>
    a.name < b.name ? -1 : 1,
  )) {
    if (SKIP_DIRS.has(e.name)) continue;
    if (e.isSymbolicLink()) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === "tests") continue; // goldens are regenerated, never swept
      writeWalk(p, out);
    } else if (WRITE_EXTS.has(extname(p))) out.push(p);
  }
  return out;
}

// Collect the names to rename, from the DETECTOR, over the detector's own file
// set. `sink` catches CLITIC-VERB-OK lines: a marked line is a deliberate
// negative example — the teaching material for this very rule — and sweeping it
// would delete the lesson. EXEMPT names never reach here at all; scanText drops
// them before returning.
export function collect(dirs) {
  const corpus = [];
  const names = new Map(); // name -> {sites:[], kinds:Set}
  for (const dir of dirs)
    for (const f of walk(dir)) {
      const text = readFileSync(f, "utf8");
      corpus.push({ file: f, text });
      const sink = [];
      for (const g of scanText(text, f, sink)) {
        if (!g.name) continue;
        if (!names.has(g.name))
          names.set(g.name, { sites: [], kinds: new Set() });
        const e = names.get(g.name);
        e.sites.push(`${g.file}:${g.line}`);
        e.kinds.add(g.kind);
      }
    }
  return { corpus, names };
}

// A NAME IS RENAMED ONLY WHERE IT IS DECLARED. This is the restriction the first
// version lacked, and it is the difference between a checker and a tool that
// edits.
//
// The checker is DESIGNED to over-report: a dereference-shaped match is cheap to
// produce and a human filters it, so its own header lists the benign classes it
// knowingly reports. Making its findings actionable turns every one of those
// into an edit. MEASURED, in `cleanroom-2026-08/guardianship-of-infants-act.l4`,
// a COMMENT mentioning another file -- "probate-administration-act.l4's `is an
// infant on` writes it `is before`" -- is a filename's genitive, not a field
// reference. The first version took it at face value and renamed `is an infant
// on` across 20+ sites, and that name is not a field at all: it is a top-level
// mixfix predicate, `p `is an infant on` `the date` MEANS`, applied infix.
//
// A DEREFERENCE tells you a name is used somewhere. Only a DECLARATION tells you
// it is a field, which is what the ruling is about -- how a field is NAMED --
// and the declaration is where the name is defined. So a rename needs at least
// one `decl` finding, and a name seen only through dereferences is reported and
// left alone.
//
// This also closes a second hole for free. `CLITIC` makes the closing backtick
// optional so that a name wrapped across lines still matches, which means a
// dereference can yield a TRUNCATED name -- measured in the corpus today,
// `has given such security as is lawfully required to be`, whose EXEMPT entry is
// spelled `... to be furnished` and therefore never matched. `DECL` requires the
// closing backtick, so a declaration-sourced name is always whole.
export function plan(dirs) {
  const { corpus, names } = collect(dirs);
  const renames = [];
  const unrenamable = [];
  const derefOnly = [];
  for (const name of [...names.keys()].sort()) {
    const { kinds, sites } = names.get(name);
    if (!kinds.has("decl")) {
      derefOnly.push([name, sites[0]]);
      continue;
    }
    const to = renameOf(name);
    if (!to) unrenamable.push(name);
    else renames.push([name, to]);
  }
  const { held, safe } = hazards(renames, corpus);
  return { corpus, names, safe, held, unrenamable, derefOnly };
}

// ---------------------------------------------------------------------------
// Selftest. Every case is a bug this file HAD — every one of the numbers below
// is a defect a refuter found in the first version of this file, not a
// hypothetical. Each has been SEEN TO FAIL, measured 2026-09-16 by mutating a
// scratch copy one rule at a time:
//
//   sweep BARE TEXT (undelimited)         5 cases redden
//   drop the plain-backtick form          4
//   drop the escaped-backtick form        2
//   drop the quoted form entirely         2
//   allow the quoted form in .l4/.md      2
//   apply renames in sequence, not once   2
//   drop the declaration requirement      2
//   drop the `tests/` exclusion           1
//   follow symlinks                       1
//
// A MEASUREMENT NOTE, because the harness lies if you skip it. The mutant must
// be run where `REPO` still resolves to this repository: `REPO` is derived from
// `import.meta.url`, so a copy executed out of /tmp reports 4 phantom isMirror
// failures that have nothing to do with the mutation. The numbers above are
// differences against an UNMUTATED copy run from the same place, not raw counts.
// An instrument that reports 6 where the answer is 2 is worse than no
// instrument, because it reads as thoroughness.
// ---------------------------------------------------------------------------
const R = [["is a Singapore citizen", "a Singapore citizen"]];

const SELFTEST = [
  {
    name: "plain backtick — the ordinary L4 identifier",
    src: "    IF p's `is a Singapore citizen`",
    want: "    IF p's `a Singapore citizen`",
    edits: 1,
  },
  {
    name: "JSON string — a whole-string deposit field",
    src: '  "field": "is a Singapore citizen",',
    want: '  "field": "a Singapore citizen",',
    edits: 1,
  },
  {
    name: "escaped backtick — L4 inside a JS template literal (the form that was missed)",
    src: "  const l4 = `GIVEN p YIELD p's \\`is a Singapore citizen\\``;",
    want: "  const l4 = `GIVEN p YIELD p's \\`a Singapore citizen\\``;",
    edits: 1,
  },
  {
    // The quotation case, from the real corpus. A bare-text sweep rewrites a
    // quotation of the statute into something the Act does not say.
    name: "would have edited a QUOTATION — bare text is never touched",
    src: '   "quote": "if (a) the male employee is a Singapore citizen of the child"',
    want: '   "quote": "if (a) the male employee is a Singapore citizen of the child"',
    edits: 0,
  },
  {
    name: "would have edited a COMMENT — bare text is never touched",
    src: "-- whether the applicant is a Singapore citizen is decided elsewhere",
    want: "-- whether the applicant is a Singapore citizen is decided elsewhere",
    edits: 0,
  },
  {
    // Escaped-backtick must be tried FIRST. Were the plain form tried first it
    // would consume the inner backticks and strand the backslashes.
    name: "escaped form is not shredded by the plain form",
    src: "\\`is a Singapore citizen\\`",
    want: "\\`a Singapore citizen\\`",
    edits: 1,
  },
  {
    name: "a name that merely CONTAINS the target is left alone",
    src: "    IF p's `is a Singapore citizen by descent`",
    want: "    IF p's `is a Singapore citizen by descent`",
    edits: 0,
  },
  {
    // A double-quoted run in L4 is a STRING LITERAL. Rewriting it changes what
    // the program says, not what a field is called.
    name: "quoted form is NOT applied in .l4 — a string literal is data",
    ext: ".l4",
    src: '    GIVETH `label` MEANS "is a Singapore citizen"',
    want: '    GIVETH `label` MEANS "is a Singapore citizen"',
    edits: 0,
  },
  {
    // In prose, quotation marks are quotation marks.
    name: "quoted form is NOT applied in .md — prose is not a reference",
    ext: ".md",
    src: 'The Act asks whether the employee "is a Singapore citizen" at the time.',
    want: 'The Act asks whether the employee "is a Singapore citizen" at the time.',
    edits: 0,
  },
  {
    name: "quoted form IS applied in .json — a deposit names the field",
    ext: ".json",
    src: '  "field": "is a Singapore citizen",',
    want: '  "field": "a Singapore citizen",',
    edits: 1,
  },
  {
    // Backticks are how L4 spells an identifier, so they stay live everywhere.
    name: "backticks still work in .l4 despite the quoted-form exclusion",
    ext: ".l4",
    src: "    IF p's `is a Singapore citizen`",
    want: "    IF p's `a Singapore citizen`",
    edits: 1,
  },
];

// Order independence (S2). Applied in sequence, the first rename's output is the
// second's input and two distinct fields collapse into one name.
const ORDER_CASES = [
  {
    name: "a rename whose output is another's input does not collapse them",
    renames: [
      ["has is bankrupt", "is bankrupt"],
      ["is bankrupt", "bankrupt"],
    ],
    src: "p's `has is bankrupt` AND p's `is bankrupt`",
    want: "p's `is bankrupt` AND p's `bankrupt`",
  },
  {
    name: "and the result does not depend on the order given",
    renames: [
      ["is bankrupt", "bankrupt"],
      ["has is bankrupt", "is bankrupt"],
    ],
    src: "p's `has is bankrupt` AND p's `is bankrupt`",
    want: "p's `is bankrupt` AND p's `bankrupt`",
  },
];

// Cases for the parts that are not textual.
function selftest() {
  let bad = 0;
  const fail = (n, msg) => {
    bad++;
    console.error(`FAIL ${n}\n  ${msg}`);
  };

  for (const c of SELFTEST) {
    const got = sweepText(c.src, R, c.ext ?? null);
    if (got.text !== c.want || got.edits !== c.edits)
      fail(
        c.name,
        `want ${c.edits} edit(s) -> ${JSON.stringify(c.want)}\n  got  ${got.edits} -> ${JSON.stringify(got.text)}`,
      );
  }

  for (const c of ORDER_CASES) {
    const got = sweepText(c.src, c.renames);
    if (got.text !== c.want)
      fail(
        c.name,
        `want ${JSON.stringify(c.want)}\n  got  ${JSON.stringify(got.text)}`,
      );
  }

  // renameOf drops the verb and nothing else.
  for (const [from, to] of [
    ["is a Singapore citizen", "a Singapore citizen"],
    ["has a Child Development Account", "a Child Development Account"],
    [
      "has renounced the right to such grant",
      "renounced the right to such grant",
    ],
  ])
    if (renameOf(from) !== to)
      fail("renameOf", `${from} -> ${renameOf(from)}, want ${to}`);

  // A name that is only the verb is not renamable; it is a different smell and
  // the detector already declines to report it.
  if (renameOf("is") !== null)
    fail("renameOf", "`is` alone must not be renamable");

  // The collision hazard: the target is already bound, so the rename is HELD
  // BACK rather than forced. This is the canon case that stopped the sweep.
  const corpus = [
    {
      file: "cases.l4",
      text: "GIVEN x\n`the natural father` MEANS Person WITH ...\n",
    },
  ];
  const h = hazards([["is the natural father", "the natural father"]], corpus);
  if (h.held.length !== 1 || h.safe.length !== 0)
    fail(
      "hazards",
      `want 1 held / 0 safe, got ${h.held.length} / ${h.safe.length}`,
    );
  const h2 = hazards(
    [["is a Singapore citizen", "a Singapore citizen"]],
    corpus,
  );
  if (h2.held.length !== 0 || h2.safe.length !== 1)
    fail(
      "hazards",
      `an uncontested rename must be safe, got ${h2.held.length} held`,
    );

  // The mirror refusal, in every spelling that once bypassed it. The
  // parent-directory rows are the ones that made this a bug and not a nicety:
  // `.` and `jl4/examples` contain the mirror without being it, and they are
  // how a person actually invokes the tool.
  for (const q of [
    join("jl4", "examples", "canon"),
    join(".", "jl4", "examples", "canon"),
    resolve(REPO, "jl4", "examples", "canon"),
    join("jl4", "examples", "legal", "..", "canon"),
    join("jl4", "examples", "canon", "sg", "succession", "sg-paa.l4"),
  ])
    if (!isMirror(q)) fail("isMirror", `must refuse ${q}`);
  for (const q of [
    join("jl4", "examples", "legal", "sg-succession"),
    join("jl4", "examples"),
    ".",
    join("jl4", "examples", "canon-ish"),
  ])
    if (isMirror(q))
      fail("isMirror", `must not refuse ${q} (it is not inside the mirror)`);

  // The detector's vocabulary is IMPORTED, not restated. If these ever stop
  // being the same objects, the two files have drifted and this test says so.
  if (!(EXEMPT instanceof Map) || !EXEMPT.size)
    fail("shared EXEMPT", "the exemption list must come from the detector");
  if (!EXTS.has(".l4") || !MARKER)
    fail("shared EXTS/MARKER", "must come from the detector");
  for (const e of EXTS)
    if (!WRITE_EXTS.has(e))
      fail("WRITE_EXTS", `must be a superset of the detector's EXTS (${e})`);

  // `tests/` must never be entered: a golden is REGENERATED from the swept
  // source by the l4 binary, and hand-editing one blesses output nothing
  // produced. Checked on a real tree, because it is a property of the walk
  // rather than of the text.
  const tmp = mkdtempSync(join(tmpdir(), "clitic-sweep-"));
  try {
    mkdirSync(join(tmp, "tests"));
    writeFileSync(join(tmp, "a.l4"), "x");
    writeFileSync(join(tmp, "tests", "a.golden"), "x");
    writeFileSync(join(tmp, "tests", "a.l4"), "x");
    writeFileSync(join(tmp, "b.json"), "{}");
    const seen = writeWalk(tmp).map((f) => f.slice(tmp.length + 1));
    if (seen.some((f) => f.startsWith("tests")))
      fail("writeWalk", `entered tests/: ${seen.join(", ")}`);
    if (!seen.includes("a.l4") || !seen.includes("b.json"))
      fail(
        "writeWalk",
        `must reach .l4 and .json siblings, saw ${seen.join(", ")}`,
      );

    // Symlinks are never followed, and the case that matters is a symlinked
    // FILE, not a symlinked directory. MEASURED: `readdirSync(withFileTypes)`
    // has lstat semantics, so a symlink to a directory answers false to
    // `isDirectory()` and is skipped whether or not the guard is there — the
    // guard reddens nothing on that case. A symlink to `x.l4` answers true to
    // the extension test, so without the guard the SAME FILE is rewritten twice,
    // once under each name. That is how a sweep half-applies: the second pass
    // finds the already-renamed text and edits nothing, so the count lies.
    // (`.claude/skills/writing-l4-rules` is the repo's real directory symlink;
    // it is the detector's reason for the rule, and not this one's.)
    mkdirSync(join(tmp, "real"));
    writeFileSync(join(tmp, "real", "c.l4"), "x");
    symlinkSync(join(tmp, "real"), join(tmp, "linkdir"), "dir");
    symlinkSync(join(tmp, "a.l4"), join(tmp, "linkfile.l4"), "file");
    const withLink = writeWalk(tmp).map((f) => f.slice(tmp.length + 1));
    if (withLink.includes("linkfile.l4"))
      fail("writeWalk", `followed a symlinked FILE: ${withLink.join(", ")}`);
    if (withLink.some((f) => f.startsWith("linkdir")))
      fail(
        "writeWalk",
        `followed a symlinked directory: ${withLink.join(", ")}`,
      );
    if (!withLink.includes(join("real", "c.l4")))
      fail("writeWalk", "must still reach the real directory");
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }

  // S1: a name seen ONLY through a dereference is reported, never renamed. The
  // witness is the real one: a comment naming another file, whose genitive the
  // detector reports by design and a human filters.
  const t2 = mkdtempSync(join(tmpdir(), "clitic-decl-"));
  try {
    writeFileSync(
      join(t2, "m.l4"),
      [
        "-- probate-administration-act.l4's `is an infant on` writes it `is before`.",
        "GIVEN p",
        "DECLARE Thing",
        "    HAS `is bankrupt` IS A BOOLEAN",
        "",
        "`x` MEANS p's `is bankrupt`",
        "",
      ].join("\n"),
    );
    const { safe, derefOnly } = plan([t2]);
    const safeNames = safe.map(([f]) => f);
    if (!safeNames.includes("is bankrupt"))
      fail(
        "plan",
        `a DECLARED field must be renamed, got ${JSON.stringify(safeNames)}`,
      );
    if (safeNames.includes("is an infant on"))
      fail("plan", "a deref-only name (here, a comment) must NOT be renamed");
    if (!derefOnly.some(([n]) => n === "is an infant on"))
      fail("plan", "a deref-only name must still be REPORTED");
  } finally {
    rmSync(t2, { recursive: true, force: true });
  }

  if (bad) {
    console.error(`\napply-clitic-sweep selftest: ${bad} check(s) failed`);
    return 1;
  }
  console.log(
    `apply-clitic-sweep selftest: ${SELFTEST.length} text + ${ORDER_CASES.length} order cases + 25 structural checks pass`,
  );
  return 0;
}

export function isMirror(p) {
  const a = resolve(p);
  return a === MIRROR || a.startsWith(MIRROR + sep);
}

// ---------------------------------------------------------------------------
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const argv = process.argv.slice(2);
  const mode = argv.includes("--check")
    ? "check"
    : argv.includes("--dry-run")
      ? "dry"
      : "apply";
  const allowMirror = argv.includes("--allow-mirror");
  const dirs = argv.filter((a) => !a.startsWith("--"));

  if (argv[0] === "--selftest") process.exit(selftest());
  if (!dirs.length) {
    console.error(
      "usage: apply-clitic-sweep.mjs [--check | --dry-run] [--allow-mirror] <dir>...\n" +
        "       apply-clitic-sweep.mjs --selftest",
    );
    process.exit(2);
  }

  const inMirror = dirs.filter(isMirror);
  if (inMirror.length && !allowMirror && mode === "apply") {
    console.error(
      `apply-clitic-sweep: refusing to write inside the vendored mirror:\n` +
        inMirror.map((d) => `  ${d}`).join("\n") +
        `\n\n${MIRROR} is a copy of legalese/canon at the SHA in etc/canon-pin.json.\n` +
        `Sweeping it here makes the mirror disagree with its pin, which \`node\n` +
        `etc/sync-canon.mjs --check\` then fails on. Sweep in canon and bump the pin.\n` +
        `Use --check or --dry-run to see what is outstanding; --allow-mirror to override.\n`,
    );
    process.exit(2);
  }

  const { safe, held, unrenamable, derefOnly } = plan(dirs);

  if (!safe.length && !held.length) {
    console.log(`apply-clitic-sweep: nothing to rename in ${dirs.join(", ")}`);
    process.exit(0);
  }

  let edits = 0;
  const touched = [];
  const refused = [];
  for (const dir of dirs)
    for (const f of writeWalk(dir)) {
      const before = readFileSync(f, "utf8");
      const { text, edits: n } = sweepText(before, safe, extname(f));
      if (!n) continue;
      // THE guard. Reading and reporting is always fine; writing is not.
      if (mode === "apply" && isMirror(f) && !allowMirror) {
        refused.push(f);
        continue;
      }
      edits += n;
      touched.push(`${mode === "apply" ? "edited" : "would edit"} ${f} (${n})`);
      if (mode === "apply") writeFileSync(f, text);
    }

  for (const t of touched) console.log(`  ${t}`);
  console.log(
    `\n${mode === "apply" ? "" : "PENDING — "}${edits} replacement(s) in ${touched.length} file(s)`,
  );
  for (const [from, to] of safe) console.log(`  \`${from}\` -> \`${to}\``);

  if (refused.length) {
    console.error(
      `\napply-clitic-sweep: REFUSED to write ${refused.length} file(s) inside the vendored mirror:`,
    );
    for (const f of refused) console.error(`  ${f}`);
    console.error(
      `\n${MIRROR} is a copy of legalese/canon at the SHA in etc/canon-pin.json.\n` +
        `Sweeping it here makes the mirror disagree with its pin, which\n` +
        `\`node etc/sync-canon.mjs --check\` then fails on. Sweep in canon and bump\n` +
        `the pin. --allow-mirror overrides, for the caller doing exactly that.`,
    );
  }

  if (held.length) {
    console.log(`\nHELD BACK (listed, never forced):`);
    for (const [from, to, why] of held)
      console.log(`  \`${from}\` -> \`${to}\` — ${why}`);
  }
  if (unrenamable.length) {
    console.log(`\nNOT RENAMABLE (the name is only the verb):`);
    for (const n of unrenamable) console.log(`  \`${n}\``);
  }
  if (derefOnly.length) {
    console.log(
      `\nREPORTED, NOT RENAMED (seen only through a dereference, never declared —\n` +
        `so it may be a mixfix predicate, a comment, or a name wrapped across lines):`,
    );
    for (const [n, where] of derefOnly)
      console.log(`  \`${n}\`  first seen ${where}`);
  }

  // --check is the CI-shaped question "is there anything to sweep?", so pending
  // work is a non-zero exit. A held-back rename is also non-zero: it needs a
  // human decision and must not read as clean.
  if (mode === "check" && (edits || held.length)) process.exit(1);
  if (held.length || refused.length) process.exit(1);
  process.exit(0);
}
