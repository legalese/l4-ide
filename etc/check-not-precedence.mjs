#!/usr/bin/env node
// check-not-precedence — flag `NOT` that swallows more than it looks like it does.
//
// WHY THIS EXISTS. L4's grammar parses `NOT` followed by a whole indented
// expression (jl4-core/src/L4/Parser.hs, `negation`), so `NOT` binds LOOSER
// than `AND`/`OR`:
//
//     A AND NOT B AND NOT C     parses as     A AND NOT (B AND NOT C)
//
// That is the opposite of every other logic notation, and it is silent: the
// module typechecks and returns a wrong BOOLEAN. It is not hypothetical. In
// the sg-succession corpus it fired twice:
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
// not help, because `NOT` still swallows what follows the parenthesis:
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
// It is a LINTER over source text, not a parser: it cannot see through a line
// continuation into an operator on the next line, so it errs toward silence.
// A clean run is not proof of correctness -- parenthesise anyway.
//
// Usage:  node etc/check-not-precedence.mjs <file.l4> [more.l4 ...]
//         node etc/check-not-precedence.mjs --dir jl4/examples/legal/sg-succession
// Exit:   0 clean · 1 findings · 2 usage

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, extname } from "node:path";

const CONNECTIVE = /\b(AND|OR|IMPLIES)\b/;

function stripNoise(line) {
  // blank out string literals and trailing comments so their words cannot
  // masquerade as operators
  let out = line.replace(/"(?:[^"\\]|\\.)*"/g, (m) => " ".repeat(m.length));
  const c = out.indexOf("--");
  if (c >= 0) out = out.slice(0, c) + " ".repeat(out.length - c);
  return out;
}

function scan(file) {
  const findings = [];
  const lines = readFileSync(file, "utf8").split("\n");
  lines.forEach((raw, i) => {
    const line = stripNoise(raw);
    // a line that is entirely a comment carries no code
    if (/^\s*--/.test(raw)) return;
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
      findings.push({
        file,
        line: i + 1,
        col: m.index + 1,
        text: raw.trim(),
        connective: verdict,
      });
    }
  });
  return findings;
}

function l4files(dir) {
  const out = [];
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) out.push(...l4files(p));
    else if (extname(p) === ".l4") out.push(p);
  }
  return out;
}

const argv = process.argv.slice(2);
if (argv.length === 0) {
  console.error("usage: check-not-precedence.mjs <file.l4>... | --dir <dir>");
  process.exit(2);
}
const files = argv[0] === "--dir" ? l4files(argv[1]) : argv;
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
    `    Write NOT (x) ${f.connective} ... if that is what you meant.`,
  );
}
console.log(
  findings.length === 0
    ? `check-not-precedence: ${files.length} file(s) clean`
    : `check-not-precedence: ${findings.length} finding(s) across ${new Set(findings.map((f) => f.file)).size} file(s)`,
);
process.exit(findings.length ? 1 : 0);
