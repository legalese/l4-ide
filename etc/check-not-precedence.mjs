#!/usr/bin/env node
// check-not-precedence — flag `NOT` that swallows more than it looks like it does.
//
// WHY THIS EXISTS. `NOT` in L4 does not have a precedence at all. Its operand
// is delimited by LAYOUT: the parser records the column `NOT` sits in, and then
// keeps absorbing operators for as long as they are indented STRICTLY DEEPER
// than that column (jl4-core/src/L4/Parser.hs, `negation` -> `indentedExpr` ->
// `expressionCont` -> `cont`, each threading the same `withIndent GT`).
//
// Measured on this tree, with `a = FALSE`, `b = FALSE`:
//
//   NOT a AND b            (one line)          ==> TRUE   -- NOT (a AND b)
//       NOT a
//           AND b          (AND deeper)        ==> TRUE   -- NOT (a AND b)
//       NOT a
//       AND b              (AND level)         ==> FALSE  -- (NOT a) AND b
//         NOT a
//     AND b                (AND shallower)     ==> FALSE  -- (NOT a) AND b
//
// So: a connective at a column <= the `NOT`'s ENDS the operand; strictly deeper
// is swallowed; and a single line ALWAYS swallows, because everything after the
// `NOT` on its own line is necessarily further right.
//
// It is silent: the module typechecks and returns a wrong BOOLEAN. It is not
// hypothetical. In the sg-succession corpus it fired twice:
//
//   * ISA s 7 rule 1 ("a surviving spouse, no issue and no parent"),
//     transcribed the obvious way, gave a widow the WHOLE estate where rule 4
//     gives her one-half -- for every intestate leaving a spouse and a parent.
//   * `what happens next in` told a family with a spouse and two children that
//     they had "no will and no close family".
//
// Both read exactly like the statute. Neither was caught by the typechecker,
// by `l4 check`, or by any assertion that happened to be written.
//
// WHAT IT FLAGS, AND THE TRAP INSIDE THE TRAP. Parenthesising the OPERAND does
// not help, because the closing parenthesis does not end the operand -- `NOT`
// goes on absorbing whatever follows it:
//
//     #EVAL NOT (FALSE) AND (FALSE)      ==> TRUE    -- i.e. NOT (FALSE AND FALSE)
//     #EVAL (NOT (FALSE)) AND (FALSE)    ==> FALSE   -- what a reader expects
//
// Measured on this tree. So `NOT (x) AND y` -- the form that looks maximally
// careful to any programmer -- is exactly as wrong as `NOT x AND y`. The ONLY
// safe form is to wrap the negation itself: `(NOT x) AND y`.
//
// This linter therefore flags a `NOT` that is NOT enclosed in a parenthesis
// group closing before the next connective at its own nesting level. A `NOT`
// with no following connective is left alone.
//
// It is a LINTER over source text, not a parser, and it deliberately reads ONE
// LINE AT A TIME. That is not laziness, it is the point: the multi-line cases
// are the ones where the layout is doing visible work, and a reader who
// indented a continuation deeper than the `NOT` usually MEANT the wide reading.
// The same-line cases are the ones nobody can see. So a clean run is not proof
// of correctness -- parenthesise anyway.
//
// WHY THIS SCANS ONLY `AND`/`OR`/`IMPLIES`, AND MUST KEEP DOING SO. This looks
// like an oversight, because `NOT`'s reach is over EVERY binary operator, not
// just the connectives -- `NOT n EQUALS 0` means `NOT (n EQUALS 0)`, measured.
// Widening the scan to all of them was measured on this tree (2026-09-05) and
// is WRONG. It finds 33 further sites and not one of them is a defect:
//
//   * For a CONNECTIVE, BOTH readings are well-typed and both are plausible.
//     That is exactly what makes the wrong one silently wrong, and it is the
//     whole reason this file exists.
//   * For a COMPARISON, the tight reading is either ILL-TYPED -- `(NOT s)
//     EQUALS ""` for a STRING `s` does not typecheck, which covers 24 of the
//     33 -- or a NO-OP: `NOT b EQUALS TRUE` and `(NOT b) EQUALS TRUE` agree at
//     both values of `b`. So a comparison site has exactly ONE well-typed
//     parse, the one everybody means.
//
// It follows that no golden can hide in that population either: there is no
// second reading for one to move to. Widening this scan would add 33 correct
// lines and 2 false positives to a check that runs on every PR, which is how a
// linter teaches people to ignore it.
//
// THE TWO FALSE POSITIVES, named so the next person does not rediscover them as
// bugs: `x AND NOT y <<SG-c-2025-sghcf-12>>` in `ok/ref.l4` and
// `lsp/semantic-tokens/annotations.l4`, where the `<` opens a `<<citation>>`
// annotation and is not a comparison at all.
//
// Both of those, and the backtick-identifier repair in `stripNoise` below, are
// the same lesson in different clothes: STRIP EVERY CONSTRUCT THAT CAN CONTAIN
// OPERATOR-LOOKING TEXT BEFORE YOU COUNT OPERATORS. A text scan over this
// corpus will otherwise count things the language does not.
//
// SUPPRESSION. A line whose comment contains `NOT-REACH-OK` is skipped. That is
// for documentation and tests that deliberately EXHIBIT the wide reading -- the
// NOT reference page has to be able to print the broken form beside the fixed
// one. Every suppression is listed in the run's output, so they stay countable.
//
// Usage:  node etc/check-not-precedence.mjs <file.l4> [more.l4 ...]
//         node etc/check-not-precedence.mjs --dir jl4/examples/legal/sg-succession
//         node etc/check-not-precedence.mjs --dir .        (what CI runs)
//         node etc/check-not-precedence.mjs --selftest      (also what CI runs)
// Exit:   0 clean · 1 findings · 2 usage

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, extname } from "node:path";

const CONNECTIVE = /\b(AND|OR|IMPLIES)\b/;

const suppressed = [];

function stripNoise(line) {
  // Blank out string literals, backtick-quoted identifiers and trailing
  // comments, so that words and brackets inside them cannot masquerade as
  // operators or nesting. The backtick case is not theoretical: L4 names are
  // ordinary prose, and
  //     #ASSERT NOT `the governor knew AND concealed it` `some other name`
  // has no operator in it at all -- but a scan that cannot see the quoting
  // reads that `AND` as a connective and the `(4)(d)` in a citation as nesting.
  // Length is preserved throughout so reported columns stay true.
  let out = line.replace(/"(?:[^"\\]|\\.)*"/g, (m) => " ".repeat(m.length));
  out = out.replace(/`[^`]*`/g, (m) => " ".repeat(m.length));
  const c = out.indexOf("--");
  if (c >= 0) out = out.slice(0, c) + " ".repeat(out.length - c);
  return out;
}

function scanText(text, label, sink) {
  const findings = [];
  const lines = text.split("\n");
  lines.forEach((raw, i) => {
    const line = stripNoise(raw);
    // a line that is entirely a comment carries no code
    if (/^\s*--/.test(raw)) return;
    const lineFindings = [];
    const re = /\bNOT\b/g;
    let m;
    while ((m = re.exec(line)) !== null) {
      // `MUST NOT` / `SHANT` are deontic modals, a different construct
      if (/\bMUST\s*$/.test(line.slice(0, m.index))) continue;
      // Walk forward from the NOT tracking depth RELATIVE to it. Whichever we
      // meet first decides:
      //   depth < 0  -> a paren closed around the NOT, so it is enclosed: safe
      //   a connective at depth 0 -> the NOT will swallow it: a finding
      const after = line.slice(m.index + 3);
      let depth = 0,
        verdict = null;
      for (let k = 0; k < after.length && verdict === null; k++) {
        const ch = after[k];
        if (ch === "(") depth++;
        else if (ch === ")") {
          if (--depth < 0) verdict = "enclosed";
        } else if (depth === 0) {
          const rest = after.slice(k);
          const c = /^\s*\b(AND|OR|IMPLIES)\b/.exec(rest);
          if (c && (k === 0 || /[\s)`]/.test(after[k - 1]))) verdict = c[1];
        }
      }
      if (verdict === null || verdict === "enclosed") continue;
      lineFindings.push({
        file: label,
        line: i + 1,
        col: m.index + 1,
        text: raw.trim(),
        connective: verdict,
      });
    }
    // A page that TEACHES this trap has to be able to show it. `NOT-REACH-OK`
    // in a comment on the line says "the wide reading is the point here". The
    // marker is only honoured where there was something to suppress, so it
    // cannot quietly become decoration -- and every use is printed, so they
    // stay countable.
    if (lineFindings.length === 0) return;
    if (raw.includes("NOT-REACH-OK")) sink.push(`${label}:${i + 1}`);
    else findings.push(...lineFindings);
  });
  return findings;
}

function scan(file) {
  return scanText(readFileSync(file, "utf8"), file, suppressed);
}

// Directories that never hold source we are responsible for. Without these the
// repo-root sweep that CI runs would wander into build output and vendored
// packages, which is both slow and noisy.
const SKIP_DIRS = new Set([
  ".git",
  "node_modules",
  "dist-newstyle",
  "dist",
  ".stack-work",
  "target",
]);

function l4files(dir) {
  const out = [];
  for (const e of readdirSync(dir)) {
    if (SKIP_DIRS.has(e)) continue;
    const p = join(dir, e);
    if (statSync(p).isDirectory()) out.push(...l4files(p));
    else if (extname(p) === ".l4") out.push(p);
  }
  return out;
}

// SELFTEST. A checker that ships in the same PR as the tree it checks has no
// independent test: "it passes" and "it cannot see anything" look identical
// from the outside. This file has ALREADY been wrong in both directions --
// it flagged two `AND`s that were inside a backticked legal name, and its
// advice line recommended the one spelling its own header calls broken -- so
// the cases below are regressions, not hypotheticals. Run by CI.
const SELFTEST = [
  // the two shapes that are actually wrong
  {
    name: "same-line NOT swallows AND",
    findings: 1,
    suppressed: 0,
    src: "bad a b MEANS NOT a AND b",
  },
  {
    name: "bracketing the OPERAND does not narrow it",
    findings: 1,
    suppressed: 0,
    src: "alsoBad a b MEANS NOT (a) AND b",
  },
  // the two shapes that are safe
  {
    name: "bracketing the NOT itself is safe",
    findings: 0,
    suppressed: 0,
    src: "fine a b MEANS (NOT a) AND b",
  },
  {
    name: "NOT last on the line is safe",
    findings: 0,
    suppressed: 0,
    src: "fineToo a b MEANS a AND NOT b",
  },
  // things that only LOOK like operators -- each one a bug this file had
  {
    name: "AND inside a backticked identifier is not an operator",
    findings: 0,
    suppressed: 0,
    src: "#ASSERT NOT `the governor knew (or should have) AND concealed it` `other name`",
  },
  {
    name: "< opening a <<citation>> is not a comparison",
    findings: 0,
    suppressed: 0,
    src: "     x AND NOT y <<SG-c-2025-sghcf-12>>",
  },
  {
    name: "AND inside a string literal is not an operator",
    findings: 0,
    suppressed: 0,
    src: 'msg a MEANS IF NOT a THEN "one AND two" ELSE "three"',
  },
  {
    name: "AND in a trailing comment is not an operator",
    findings: 0,
    suppressed: 0,
    src: "q a b MEANS NOT a  -- AND b",
  },
  {
    name: "MUST NOT is a deontic modal, not this construct",
    findings: 0,
    suppressed: 0,
    src: "  PARTY MUST NOT pay AND notify",
  },
  // the suppression, and its guard against becoming decoration
  {
    name: "NOT-REACH-OK suppresses a real finding",
    findings: 0,
    suppressed: 1,
    src: "teach a b MEANS NOT a AND b -- NOT-REACH-OK",
  },
  {
    name: "NOT-REACH-OK on a clean line counts as nothing",
    findings: 0,
    suppressed: 0,
    src: "safe a b MEANS (NOT a) AND b -- NOT-REACH-OK",
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
      ? `check-not-precedence --selftest: ${SELFTEST.length} case(s) passed`
      : `check-not-precedence --selftest: ${failed} of ${SELFTEST.length} case(s) FAILED`,
  );
  process.exit(failed ? 1 : 0);
}

const argv = process.argv.slice(2);
if (argv[0] === "--selftest") selftest();
if (argv.length === 0) {
  console.error(
    "usage: check-not-precedence.mjs <file.l4>... | --dir <dir> [<dir>...]",
  );
  process.exit(2);
}
const files =
  argv[0] === "--dir" ? argv.slice(1).flatMap((d) => l4files(d)) : argv;
if (argv[0] === "--dir" && argv.length === 1) {
  console.error("usage: --dir needs at least one directory");
  process.exit(2);
}
const findings = files.flatMap(scan);

for (const f of findings) {
  console.log(
    `${f.file}:${f.line}:${f.col}: NOT is followed by ${f.connective} at the same level and is not itself parenthesised`,
  );
  console.log(`    ${f.text}`);
  console.log(
    `    NOT takes the WHOLE following expression, so this reads as NOT ( ... ${f.connective} ... ).`,
  );
  console.log(
    `    Write (NOT x) ${f.connective} ... if that is what you meant. Parenthesising`,
  );
  console.log(
    `    the OPERAND -- NOT (x) ${f.connective} ... -- does NOT help; the bracket must`,
  );
  console.log(`    close around the NOT itself.`);
}
if (suppressed.length) {
  console.log(
    `check-not-precedence: ${suppressed.length} line(s) suppressed with NOT-REACH-OK: ${suppressed.join(", ")}`,
  );
}
console.log(
  findings.length === 0
    ? `check-not-precedence: ${files.length} file(s) clean`
    : `check-not-precedence: ${findings.length} finding(s) across ${new Set(findings.map((f) => f.file)).size} file(s)`,
);
process.exit(findings.length ? 1 : 0);
