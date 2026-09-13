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

// EXEMPTIONS. Meng ruled on 2026-09-13 that rare exceptions may keep the verb
// "especially if they are terms of art from the upstream source". The marker
// above handles a one-off line; this list handles a NAME, because a name used in
// forty places should not need forty markers -- and because the reason belongs
// in one reviewable place rather than scattered through the corpus.
//
// The test that admits the first five is objective rather than a matter of
// taste: the name contains a SECOND `is`/`has` inside it. A name we coined does
// not do that. A limb quoted from a statute does, because the source sentence
// has its own clauses -- and in each of these the chapeau does NOT supply the
// verb (Reg CF's is bare: "if the issuer:"), so the limb carries it and matching
// the source means carrying it too. Fidelity to the source is the ruling's own
// stated rationale, so it is also the ruling's own limit.
const EXEMPT = new Map([
  ["has given such security as is lawfully required to be furnished",
   "Probate and Administration Act limb, quoted; contains its own `is`"],
  ["has no specific business plan, or has indicated that its business plan is to engage in a merger or acquisition with an unidentified company or companies",
   "17 CFR 227.100(b)(6), quoted; the chapeau does not supply the verb"],
  ["has sold securities in reliance on section 4(a)(6) and has not filed the ongoing annual reports required during the two years immediately preceding the filing of the offering statement",
   "17 CFR 227.100(b)(5), quoted; the chapeau does not supply the verb"],
  ["has that general control and management only on behalf of another person who has it in that other person's own right under the constitution of the entity",
   "Charities (Jersey) Law limb, quoted; contains its own `has`"],
  ["is calculated to facilitate, or is conducive or incidental to, the performance of any of the Commissioner's functions",
   "Charities (Jersey) Law limb, quoted; contains its own `is`"],
  ["has capacity",
   "term of art in succession and mental-capacity law; `capacity` alone reads as an amount"],
]);

// `'s` (straight or curly apostrophe), whitespace, then a backticked name whose
// first word is `is` or `has`. The name must continue past the verb -- a field
// actually called `` `is` `` is not this bug -- and the closing backtick is not
// required on the line, because a long name may wrap in a comment.
const CLITIC = /['’]s\s+`(is|has)(\s+[^`]*)?`?/g;

// RULE 2 -- the DECLARATION. Meng ruled on 2026-09-13 that a field named `is …`
// or `has …` is wrong wherever it is declared, whether or not anything
// dereferences it yet: "every l4 file is a training example ultimately", and a
// DECLARE block is what an example teaches naming from. Measured at the time of
// the ruling: 121 distinct is/has field names over 175 declaration sites, of
// which 74 were clitic-dereferenced and 47 were not. Rule 1 alone would have
// left those 47 in place, to be copied forward by the next encoder.
//
// The line must be INDENTED (a field sits under `DECLARE … HAS`), the name must
// be followed directly by its type, and the type must not be a FUNCTION. Each
// of those three exclusions is load-bearing and each was measured:
//
//   `is unreasonable` IS A FUNCTION FROM Conduct TO BOOLEAN   -- 44 of these
//        an ASSUMEd PREDICATE, not an attribute. It is applied prefix --
//        `` `is unreasonable` c `` -- where nothing else supplies the verb, so
//        the verb belongs in the name and the ruling does not reach it.
//   ASSUME `is unreasonable` c IS A BOOLEAN
//        the same thing spelled with an explicit parameter; the `c` between name
//        and type is what distinguishes it, which is why the regex allows no gap.
//   `is a registered charity`  IS TRUE
//        a record CONSTRUCTION, not a declaration. Renaming is driven by the
//        declaration; constructions follow the rename and are not separately
//        reported, or every fixture row would be a finding.
//   HAS `has tickets` IS A BOOLEAN
//        the FIRST field of a record shares the `HAS` line, so the optional
//        `HAS` below is not cosmetic -- without it the first field of every
//        DECLARE is invisible, which is the gap this file's own selftest caught.
const DECL = /^\s+(HAS\s+)?`(is|has)\s+[^`]+`\s+IS\s+(A|AN|THE)\s+(?!FUNCTION\b)/;

function scanText(text, label, sink) {
  const findings = [];
  text.split("\n").forEach((raw, i) => {
    const hits = [];

    CLITIC.lastIndex = 0;
    let m;
    while ((m = CLITIC.exec(raw)) !== null) {
      // `` X's `is` `` on its own is a field named for the verb alone, which is
      // a different (and rarer) smell; this check is about the doubled verb.
      if (!m[2] || !m[2].trim()) continue;
      if (EXEMPT.has((m[1] + m[2]).trim())) continue;
      hits.push({ kind: "deref", file: label, line: i + 1, col: m.index + 1, text: raw.trim() });
    }

    const d = DECL.exec(raw);
    const dn = d && /`([^`]+)`/.exec(d[0]);
    if (d && dn && EXEMPT.has(dn[1])) {
      // named exemption: recorded once in EXEMPT, not repeated at every site
    } else if (d) hits.push({ kind: "decl", file: label, line: i + 1, col: d[0].indexOf("`") + 1, text: raw.trim() });

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

  // -- rule 2, the declaration --
  { name: "an is-prefixed field declaration is a finding", findings: 1, suppressed: 0,
    src: "        `is bankrupt` IS A BOOLEAN" },
  { name: "a has-prefixed field declaration is a finding", findings: 1, suppressed: 0,
    src: "    HAS `has tickets`    IS A BOOLEAN" },
  { name: "a trailing TYPICALLY does not hide the declaration", findings: 1, suppressed: 0,
    src: "        `has spousal approval`   IS A BOOLEAN TYPICALLY FALSE" },
  { name: "a name on the EXEMPT list is not reported, at its declaration",
    findings: 0, suppressed: 0, src: "        `has capacity`   IS A BOOLEAN TYPICALLY TRUE" },
  { name: "a name on the EXEMPT list is not reported, at a dereference",
    findings: 0, suppressed: 0, src: "    IF testator's `has capacity`" },
  { name: "a non-boolean field counts too", findings: 1, suppressed: 0,
    src: "        `has a date of transfer`                 IS A DATE" },
  { name: "the repaired declaration is clean", findings: 0, suppressed: 0,
    src: "        `bankrupt` IS A BOOLEAN" },
  { name: "an ASSUMEd predicate typed as a FUNCTION is out of scope", findings: 0, suppressed: 0,
    src: "          `is a Singapore offence` IS A FUNCTION FROM Offence TO BOOLEAN" },
  { name: "an ASSUMEd predicate with an explicit parameter is out of scope",
    findings: 0, suppressed: 0, src: "ASSUME `is unreasonable` c IS A BOOLEAN" },
  { name: "a record construction is not a declaration", findings: 0, suppressed: 0,
    src: "        `is a registered charity`                       IS TRUE" },
  { name: "a construction assigning another name is not a declaration", findings: 0, suppressed: 0,
    src: "        `has been extracted` IS `has been taken out`" },
  { name: "a top-level rule name is not a field", findings: 0, suppressed: 0,
    src: "`is disqualified` MEANS issuer's `a disqualifying event`" },
  { name: "declaration and dereference on one line are two findings", findings: 2, suppressed: 0,
    src: "    `is odd` IS A BOOLEAN -- see x's `is even`" },
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

const nDecl = findings.filter((f) => f.kind === "decl").length;
const nDeref = findings.length - nDecl;
console.error(
  `check-clitic-verbs: ${findings.length} finding(s) in ${byFile.size} file(s) ` +
    `(${nDecl} declaration, ${nDeref} dereference).\n` +
    `The clitic 's already supplies "is" and "has" -- start the field name at the\n` +
    `complement: person's \`bankrupt\`, not person's \`is bankrupt\`. A field named\n` +
    `for the verb is wrong where it is DECLARED too, whether or not anything reads\n` +
    `it yet, because every L4 file is ultimately a training example.\n` +
    `See doc/concepts/language-design/linguistic-syntax.md, "The Saxon Genitive".\n`,
);
for (const f of findings)
  console.error(`  ${f.file}:${f.line}:${f.col}  [${f.kind}]  ${f.text}`);
process.exit(1);
