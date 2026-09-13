#!/usr/bin/env node
// check-clitic-verbs — flag a genitive dereference onto a field whose name
// starts with the verb the clitic already supplied.
//
// THE RULE. `'s` reads as both "is" and "has", so `` person's `is bankrupt` ``
// says the verb twice. The field name must start at the complement:
// `` person's `bankrupt` ``. The ruling is recorded twice already --
// `doc/concepts/language-design/linguistic-syntax.md` under "The Saxon
// Genitive", and `skills/writing-l4-rules/references/drafting-patterns.md`
// under the same heading -- and both say WHY it is not tidiness: the field name
// is what a ladder diagram prints beside its node and what a generated wizard
// asks the user, so a doubled verb is a stutter in the picture and in the
// question.
//
// WHY A SECOND CHECKER, AND NOT A LINE IN check-retired-terms.mjs. That file
// blanks fenced blocks, inline code spans and link targets BEFORE it searches,
// because its terms are prose words and a page that documents an error message
// has to quote it. Its stripping is the load-bearing half of its design. This
// rule lives ONLY inside code -- exactly the text that file deletes. Adding an
// entry there would have produced a permanently green check over an empty
// string. Opposite polarity, separate file.
//
// WHAT IT SCANS, AND WHY THAT IS SIMPLER THAN IT LOOKS. Every line of every
// `.l4` and `.md`, prose and code alike, with no stripping. The pattern is
// specific enough to be self-limiting: `'s` followed by a backticked name
// starting `is `/`has ` occurs in L4 source, in markdown quoting L4 source, and
// essentially nowhere else. Prose is scanned deliberately rather than
// incidentally -- a comment that names a field is a reference to it, and a
// comment left behind by a rename is a stale claim about the tree, which is the
// failure this repo's CLAUDE.md spends its longest section on. Measured over
// `unstable` @ 75068010 before any repair: 143 findings on 142 lines in 51
// files, 83 distinct field names, and only 7 of the 143 sit on an `.l4` comment
// line -- so scanning prose costs almost nothing and catches the stale-comment
// case for free.
//
// WHAT IS NOT IN SCOPE. Meng's ruling (2026-09-13) names "an attribute or
// computed field". A standalone predicate is not one: `` `is misconduct` ``
// defined at top level and applied as `` `is misconduct` allegation `` reads
// correctly and stays. Such a name reached through a MODULE -- ``Part 1's
// `is misconduct` `` -- matches the pattern by accident, because module
// qualification borrows the same clitic. There were 4 of those at the time of
// writing and they take the marker below.
//
// THE MARKER. A line carrying CLITIC-VERB-OK is exempt, and is honoured ONLY
// where there was something to suppress, so it cannot quietly become
// decoration. Every use is printed, so they stay countable. Two things earn it:
// a module-qualified predicate as above, and a deliberate negative example --
// Meng's ruling exempts the wrong form shown AS the wrong form, which is how
// the rule gets taught at all.
//
// Usage:  node etc/check-clitic-verbs.mjs --dir doc/tutorials
//         node etc/check-clitic-verbs.mjs --dir <dir> [<dir> ...]
//         node etc/check-clitic-verbs.mjs <file> ...
//         node etc/check-clitic-verbs.mjs --selftest      (also what CI runs)
// Exit:   0 clean · 1 findings · 2 usage

import { readFileSync, readdirSync, lstatSync } from "node:fs";
import { join, extname } from "node:path";

const SKIP_DIRS = new Set([
  ".git",
  "node_modules",
  "dist-newstyle",
  "dist",
  ".stack-work",
  "target",
]);

const EXTS = new Set([".l4", ".md"]);
const MARKER = "CLITIC-VERB-OK";

// `'s` (straight or curly apostrophe), whitespace, then a backticked name whose
// first word is `is` or `has`. The name must continue past the verb -- a field
// actually called `` `is` `` is not this bug -- and the closing backtick is not
// required on the line, because a long name may wrap in a comment.
const CLITIC = /['’]s\s+`(is|has)(\s+[^`]*)?`?/g;

function scanText(text, label, sink) {
  const findings = [];
  text.split("\n").forEach((raw, i) => {
    CLITIC.lastIndex = 0;
    const hits = [];
    let m;
    while ((m = CLITIC.exec(raw)) !== null) {
      // `` X's `is` `` on its own is a field named for the verb alone, which is
      // a different (and rarer) smell; this check is about the doubled verb.
      if (!m[2] || !m[2].trim()) continue;
      hits.push({ file: label, line: i + 1, col: m.index + 1, verb: m[1], text: raw.trim() });
    }
    if (hits.length === 0) return;
    if (raw.includes(MARKER)) sink.push(`${label}:${i + 1}`);
    else findings.push(...hits);
  });
  return findings;
}

// lstat, not stat, and symlinks are never followed. `.claude/skills/writing-l4-rules`
// is a git symlink to `skills/writing-l4-rules`, so a walk that follows it reports
// the same 12 files under two paths -- which is how the first run of this checker
// claimed 57 files when the answer was 51. Counting a file twice is the harmless
// half; the dangerous half is that a repair applied under one path reads as
// outstanding under the other, forever.
function walk(dir) {
  const out = [];
  for (const e of readdirSync(dir)) {
    if (SKIP_DIRS.has(e)) continue;
    const p = join(dir, e);
    const st = lstatSync(p);
    if (st.isSymbolicLink()) continue;
    if (st.isDirectory()) out.push(...walk(p));
    else if (EXTS.has(extname(p))) out.push(p);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Selftest. Each case is a bug this file had or would have had. It has been
// seen to fail: measured by mutating a scratch copy one rule at a time --
// dropping the `m[2]` guard reddens 2 cases, dropping the curly-apostrophe
// alternative 1, the optional-trailing-backtick 1, and the MARKER branch 1.
//
// The `m[2]` guard is worth the sentence it costs. Without it the regex matches
// `` claim's `issue date` ``: it consumes the backtick and the letters `is`,
// group 2 fails on `sue date`, and the trailing backtick is optional -- so a
// perfectly good field name reads as a finding. The guard is not there to be
// strict about `` X's `is` ``; it is there to stop a false positive on every
// field whose name merely STARTS with those two letters.
// ---------------------------------------------------------------------------
const SELFTEST = [
  { name: "the plain wrong form is a finding", findings: 1, suppressed: 0,
    src: "    AND NOT person's `is bankrupt`" },
  { name: "has is caught as well as is", findings: 1, suppressed: 0,
    src: "    IF NOT filing's `has the required financial statements`" },
  { name: "two on one line are two findings", findings: 2, suppressed: 0,
    src: "applicant's `is existing customer` AND applicant's `has paid`" },
  { name: "the repaired form is clean", findings: 0, suppressed: 0,
    src: "    AND NOT person's `bankrupt`" },
  { name: "a field named for the verb alone is out of scope", findings: 0, suppressed: 0,
    src: "    x's `is`" },
  { name: "an ordinary field starting with a word that merely begins 'is' is clean",
    findings: 0, suppressed: 0, src: "    claim's `issue date`" },
  { name: "a name wrapping past the end of a comment line still counts",
    findings: 1, suppressed: 0,
    src: "-- because `Grant`'s `has given such security as is lawfully required" },
  { name: "a curly apostrophe is the same clitic", findings: 1, suppressed: 0,
    src: "the occupier’s `is a wedding`" },
  { name: "the marker exempts a module-qualified predicate", findings: 0, suppressed: 1,
    src: "-- decided by Part 1's `is misconduct`.   -- CLITIC-VERB-OK module member" },
  { name: "the marker does nothing on a clean line", findings: 0, suppressed: 0,
    src: "-- nothing to suppress here.   CLITIC-VERB-OK" },
  { name: "prose in markdown quoting the wrong form is a finding", findings: 1, suppressed: 0,
    src: "…quote it back — ``IF applicant's `is existing customer` THEN…``" },
];

function selftest() {
  let bad = 0;
  for (const c of SELFTEST) {
    const sink = [];
    const got = scanText(c.src, "<selftest>", sink);
    const ok = got.length === c.findings && sink.length === c.suppressed;
    if (!ok) {
      bad++;
      console.error(
        `FAIL ${c.name}\n  want ${c.findings} findings / ${c.suppressed} suppressed` +
          `, got ${got.length} / ${sink.length}\n  src: ${c.src}`,
      );
    }
  }
  if (bad) {
    console.error(`\ncheck-clitic-verbs selftest: ${bad} of ${SELFTEST.length} failed`);
    return 1;
  }
  console.log(`check-clitic-verbs selftest: ${SELFTEST.length} cases pass`);
  return 0;
}

// ---------------------------------------------------------------------------
const argv = process.argv.slice(2);
if (argv.length === 0) {
  console.error("usage: check-clitic-verbs.mjs [--selftest | --dir <dir>... | <file>...]");
  process.exit(2);
}
if (argv[0] === "--selftest") process.exit(selftest());

let files;
if (argv[0] === "--dir") {
  const dirs = argv.slice(1);
  if (dirs.length === 0) {
    console.error("--dir needs at least one directory");
    process.exit(2);
  }
  files = dirs.flatMap((d) => walk(d));
} else {
  files = argv;
}

const suppressed = [];
const findings = files.flatMap((f) => scanText(readFileSync(f, "utf8"), f, suppressed));

if (suppressed.length) {
  console.log(`${MARKER} honoured on ${suppressed.length} line(s):`);
  for (const s of suppressed) console.log(`  ${s}`);
  console.log("");
}

if (findings.length === 0) {
  console.log(`check-clitic-verbs: clean over ${files.length} file(s)`);
  process.exit(0);
}

const byFile = new Map();
for (const f of findings) byFile.set(f.file, (byFile.get(f.file) ?? 0) + 1);

console.error(
  `check-clitic-verbs: ${findings.length} finding(s) in ${byFile.size} file(s).\n` +
    `The clitic 's already supplies "is" and "has" -- start the field name at the\n` +
    `complement: person's \`bankrupt\`, not person's \`is bankrupt\`.\n` +
    `See doc/concepts/language-design/linguistic-syntax.md, "The Saxon Genitive".\n`,
);
for (const f of findings) console.error(`  ${f.file}:${f.line}:${f.col}  ${f.text}`);
process.exit(1);
