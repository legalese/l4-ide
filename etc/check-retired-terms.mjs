#!/usr/bin/env node
// check-retired-terms — flag words we coined, then retired, still standing in
// user-facing prose.
//
// WHY THIS EXISTS. L4's user-facing text is written for a non-technical
// first-time critical thinker. A few words fail that test not because they are
// hard but because they are OURS: we invented them, wrote them into pages, then
// ruled them out. Those are different from merely-discouraged jargon, and they
// are what this file is for -- for a retired term, ANY occurrence in prose is
// suspect, so a plain search is a sound check. For a merely discouraged word it
// is not, and that difference is the whole design. Measured over `doc/` with
// the stripping below, on this branch's base (`props/discharge` @ 3625b533,
// before the repairs that ship with this file): `binder` 9 lines,
// `parameter` 140 across 49 files. A list that admitted the second word could
// only ever be advisory; this one can gate CI.
//
// It is not hypothetical, and note the order of events. The ruling is from
// 2026-09-04. The DAY AFTER, `doc/reference/syntax/section-given.md` had the word
// removed by one pull request and put back five times by another, while everyone
// involved believed the ruling was being followed. So the thing this file guards
// against is not an unclear rule -- it is a clear one silently not being held,
// which is the one failure a better-worded rule cannot fix. Nothing caught it:
// `doc/test-docs.sh` checks links and type-checks `.l4` files and has no opinion
// about words.
//
// WHAT IT DOES NOT FLAG, AND WHY THAT IS THE LOAD-BEARING PART. A page that
// documents an error message has to QUOTE it, and a page that teaches a
// construct has to SHOW it. So fenced blocks, inline code spans and link
// targets are blanked before the search. On the same base, this scan reported
// 17 lines under `doc/` naive and 9 after stripping. The 8 it drops are quoted
// compiler output and code -- every one a false positive, and together enough
// to have made the check unrunnable on its first day.
//
// ADDING A TERM. Every entry cites the ruling that retired it, by date and by
// document. That citation is the anti-rot mechanism, and it is strict on
// purpose: an entry added because someone dislikes a word, with no ruling
// behind it, fails review. A term belongs here only if we coined it AND
// retired it. `discharge` and `assumed term` are current, in-use terms, not
// retired ones. `read-set`, `elaboration` and `section binder` have no
// retiring ruling to cite. So the list has one element, and one element earns
// its keep: it has a five-instance regression against it from inside a day.
//
// Usage:  node etc/check-retired-terms.mjs --dir doc [<dir> ...]
//         node etc/check-retired-terms.mjs <file.md> ...
//         node etc/check-retired-terms.mjs --selftest      (also what CI runs)
// Exit:   0 clean · 1 findings · 2 usage

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, extname } from "node:path";

// Each entry: the word, when and where it was retired, and what to say instead.
// `re` is per-entry so a term controls its own matching; the default shape
// anchors the word start and lets any suffix through, which is what catches
// "binders" and "binder's" without a second entry.
const RETIRED = [
  {
    term: "binder",
    re: /\bbinder/gi,
    retired: "2026-09-04",
    ruling: "Meng's vocabulary ruling, recorded at CLAUDE.md §7",
    instead:
      'say "section GIVEN" or "rule GIVEN" for the construct, and "input" for what it supplies',
  },
];

const SKIP_DIRS = new Set([
  ".git",
  "node_modules",
  "dist-newstyle",
  "dist",
  ".stack-work",
  "target",
]);

const MARKER = "RETIRED-TERM-OK";

// Blank out inline code spans, link targets and autolinks, so that a word we
// are QUOTING cannot be mistaken for a word we are USING. Length is preserved
// throughout so reported columns stay true.
//
// The code-span case is not theoretical, and neither is the link case: a page
// that documents this very error writes `` `the rate` `` in prose and links to
// `../syntax/section-given.md`. A scan that cannot see either reads them as
// ordinary words. Double-backtick spans are blanked before single ones so a
// span containing a backtick is not cut in half.
function stripNoise(line) {
  const blank = (m) => " ".repeat(m.length);
  let out = line.replace(/``[^`]*``/g, blank);
  out = out.replace(/`[^`]*`/g, blank);
  // markdown link and image targets: the visible text stays, the URL goes
  out = out.replace(/\]\([^)]*\)/g, blank);
  // autolinks and raw html attributes
  out = out.replace(/<[^>\s]*>/g, blank);
  return out;
}

// A fence opens on ``` or ~~~ and closes on a run of the same character at
// least as long. Everything between is quoted, not written.
function fenceToken(raw) {
  const m = /^\s*(`{3,}|~{3,})/.exec(raw);
  return m ? m[1] : null;
}

function scanText(text, label, sink) {
  const findings = [];
  const lines = text.split("\n");
  let fence = null;
  lines.forEach((raw, i) => {
    const tok = fenceToken(raw);
    if (fence === null) {
      if (tok) {
        fence = tok;
        return;
      }
    } else {
      // inside a fence: only a closing run of the same char, at least as long,
      // ends it. The fence line itself is never scanned.
      if (tok && tok[0] === fence[0] && tok.length >= fence.length)
        fence = null;
      return;
    }

    const line = stripNoise(raw);
    const lineFindings = [];
    for (const entry of RETIRED) {
      entry.re.lastIndex = 0;
      let m;
      while ((m = entry.re.exec(line)) !== null) {
        lineFindings.push({
          file: label,
          line: i + 1,
          col: m.index + 1,
          entry,
          text: raw.trim(),
        });
      }
    }

    // A page that must name a retired word -- because it is glossing what the
    // compiler still prints -- says so on the line. The marker is honoured
    // ONLY where there was something to suppress, so it cannot quietly become
    // decoration; and every use is printed, so they stay countable and the
    // count falls as the underlying reason goes away.
    if (lineFindings.length === 0) return;
    if (raw.includes(MARKER)) sink.push(`${label}:${i + 1}`);
    else findings.push(...lineFindings);
  });
  return findings;
}

function mdfiles(dir) {
  const out = [];
  for (const e of readdirSync(dir)) {
    if (SKIP_DIRS.has(e)) continue;
    const p = join(dir, e);
    if (statSync(p).isDirectory()) out.push(...mdfiles(p));
    else if (extname(p) === ".md") out.push(p);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Selftest
//
// The negative control lives here rather than in a committed fixture file: a
// page full of deliberately-retired words would fail the very sweep it exists
// to validate. Each case below is a bug this file either had or would have had
// -- in particular every stripping rule has a case, because a selftest that has
// never been seen to fail is worth nothing.
//
// It has been seen to fail. Measured, by deleting one rule at a time from a
// scratch copy: the single-backtick line in `stripNoise` reddens 2 cases, the
// link-target line 1, and the fence block in `scanText` 4. The first of those
// numbers was 1 until the code-span case was rewritten -- its original text
// (`SuspiciousBinderPattern`) has no word boundary before the term, so it
// passed with the stripping removed and was testing nothing.
// ---------------------------------------------------------------------------
const SELFTEST = [
  {
    name: "a retired word in plain prose is a finding",
    findings: 1,
    suppressed: 0,
    src: "the section binder reaches every rule beneath it",
  },
  {
    name: "plural and possessive are the same word",
    findings: 2,
    suppressed: 0,
    src: "two binders, and the binder's own type",
  },
  {
    name: "capitalised at the start of a sentence still counts",
    findings: 1,
    suppressed: 0,
    src: "Binder is its name for a section GIVEN.",
  },
  {
    name: "inside a fenced block it is quoted, not written",
    findings: 0,
    suppressed: 0,
    src: "```\nIf `the rate` was meant as a binder for the whole of\n```",
  },
  {
    name: "a longer closing run still closes the fence",
    findings: 0,
    suppressed: 0,
    src: "```l4\n-- the NUMBER binder\n````",
  },
  {
    name: "a fence reopens, so prose after it is scanned again",
    findings: 1,
    suppressed: 0,
    src: "```\na binder in a fence\n```\na binder in prose",
  },
  {
    name: "a tilde fence is a fence",
    findings: 0,
    suppressed: 0,
    src: "~~~\nan unsupplied binder\n~~~",
  },
  {
    name: "an inline code span is quoted, not written",
    findings: 0,
    suppressed: 0,
    src: "the compiler's own word for it is `binder`, which we no longer use",
  },
  {
    name: "a term embedded in a longer identifier needs no stripping at all",
    findings: 0,
    suppressed: 0,
    src: "the constructor is spelled SuspiciousBinderPattern in the source",
  },
  {
    name: "a double-backtick span containing a backtick is blanked whole",
    findings: 0,
    suppressed: 0,
    src: "write `` `binder` `` when quoting it",
  },
  {
    name: "a link target is not prose",
    findings: 0,
    suppressed: 0,
    src: "see [the page](../syntax/binder-notes.md) for more",
  },
  {
    name: "but a retired word in the link TEXT is prose",
    findings: 1,
    suppressed: 0,
    src: "see [the binder page](../syntax/section-given.md) for more",
  },
  {
    name: "a word merely containing the term is not the term",
    findings: 0,
    suppressed: 0,
    src: "the bookbinder analogy does not apply here",
  },
  // the suppression, and its guard against becoming decoration
  {
    name: "the marker suppresses a real finding",
    findings: 0,
    suppressed: 1,
    src: 'the message says "binder". <!-- RETIRED-TERM-OK: glossing compiler output -->',
  },
  {
    name: "the marker on a clean line suppresses nothing and counts nothing",
    findings: 0,
    suppressed: 0,
    src: "an ordinary sentence <!-- RETIRED-TERM-OK: nothing to suppress here -->",
  },
];

function selftest() {
  let failed = 0;
  for (const c of SELFTEST) {
    const sink = [];
    const got = scanText(c.src, c.name, sink);
    if (got.length === c.findings && sink.length === c.suppressed) {
      console.log(`  ok   ${c.name}`);
    } else {
      failed++;
      console.log(
        `  FAIL ${c.name}: expected ${c.findings} finding(s) and ${c.suppressed} suppression(s), got ${got.length} and ${sink.length}`,
      );
    }
  }
  console.log(
    failed === 0
      ? `check-retired-terms --selftest: ${SELFTEST.length} case(s) passed`
      : `check-retired-terms --selftest: ${failed} of ${SELFTEST.length} case(s) FAILED`,
  );
  process.exit(failed ? 1 : 0);
}

const argv = process.argv.slice(2);
if (argv[0] === "--selftest") selftest();
if (argv.length === 0) {
  console.error(
    "usage: check-retired-terms.mjs <file.md>... | --dir <dir> [<dir>...] | --selftest",
  );
  process.exit(2);
}

const files = argv[0] === "--dir" ? argv.slice(1).flatMap(mdfiles) : argv;
const suppressed = [];
const findings = files.flatMap((f) =>
  scanText(readFileSync(f, "utf8"), f, suppressed),
);

for (const f of findings) {
  console.log(
    `${f.file}:${f.line}:${f.col}: "${f.entry.term}" was retired on ${f.entry.retired} — ${f.entry.ruling}`,
  );
  console.log(`    ${f.text}`);
  console.log(`    Instead: ${f.entry.instead}.`);
  console.log(
    `    If this line is quoting what the compiler prints, put <!-- ${MARKER}: reason --> on it.`,
  );
}
if (suppressed.length) {
  console.log(
    `check-retired-terms: ${suppressed.length} line(s) suppressed with ${MARKER}: ${suppressed.join(", ")}`,
  );
}
console.log(
  findings.length === 0
    ? `check-retired-terms: ${files.length} file(s) clean, ${RETIRED.length} retired term(s) checked`
    : `check-retired-terms: ${findings.length} finding(s) across ${new Set(findings.map((f) => f.file)).size} file(s)`,
);
process.exit(findings.length ? 1 : 0);
