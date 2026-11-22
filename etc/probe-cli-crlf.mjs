#!/usr/bin/env node
// probe-cli-crlf.mjs — list new CLI-test assertions that compare a process's
// output without dropping carriage returns first.
//
// WHY
//   On Windows, a process's output or a fixture checked out there can end its
//   lines with "\r\n". An assertion that matches a needle spanning a line
//   break, compares whole lines, or compares the whole output then fails there
//   and nowhere else (review of legalese/l4-ide#545, round 2:
//   jl4/tests-cli/Main.hs:327). No PR check runs on Windows; the one Windows run
//   of l4-cli-test is the release workflow's (main-tag.yml, build-lsp-windows),
//   dispatched by hand after a merge to main. The house idiom drops "\r" from
//   both sides: `map (filter (/= '\r')) (lines sout)` (the CSV test in
//   jl4/tests-cli/Main.hs).
//
// WHAT
//   Reads the lines a branch adds under jl4/tests-cli/ (git diff BASE...HEAD)
//   and names each added Haskell line that does not mention '\r' and that
//     - compares against a string literal containing "\n";
//     - compares `lines <output>` with shouldBe or ==; or
//     - compares a whole stdout or stderr with shouldBe (other than with "").
//   It is a heuristic over text, so it WARNs and never FAILs: read each line it
//   names. It does not see an output passed through a helper first.
//
// USAGE
//   node etc/probe-cli-crlf.mjs [--base <ref>] <worktree>    base defaults to origin/unstable
//   node etc/probe-cli-crlf.mjs --selftest
//
//   Exit 0 whatever it finds; 2 if git could not produce the diff.

import { spawnSync } from "node:child_process";

const COMPARE =
  /`(shouldBe|shouldSatisfy|shouldContain|shouldStartWith|shouldEndWith|isInfixOf|isPrefixOf|isSuffixOf)`|==/;
const NEWLINE_LITERAL = /"(?:[^"\\]|\\.)*\\n(?:[^"\\]|\\.)*"/;
const LINES_COMPARED = /\blines\s+\w+\)?\s*`shouldBe`|\(==[^)]*\).*\blines\b/;
const WHOLE_OUTPUT =
  /^(\w*(out|err|Out|Err)|(outStdout|outStderr)\s+\w+)\s*`shouldBe`(?!\s*(""|mempty))/;
// A JSON string's "\n" is an escape inside the value, which no line ending touches.
const JSON_STRING = /\bString\s+"(?:[^"\\]|\\.)*"/g;

function reason(line) {
  const code = line.trim();
  if (code.startsWith("--") || code.includes("\\r")) return null;
  if (NEWLINE_LITERAL.test(code.replace(JSON_STRING, "")) && COMPARE.test(code))
    return 'needle spans a line break ("\\n")';
  if (LINES_COMPARED.test(code)) return "compares whole lines";
  if (WHOLE_OUTPUT.test(code)) return "compares the whole output";
  return null;
}

function scan(wt, base) {
  const r = spawnSync(
    "git",
    [
      "-C",
      wt,
      "diff",
      "-U0",
      "--no-color",
      `${base}...HEAD`,
      "--",
      "jl4/tests-cli/",
    ],
    {
      encoding: "utf8",
      maxBuffer: 1 << 26,
    },
  );
  if (r.status !== 0) {
    console.error(`probe-cli-crlf: git diff failed: ${r.stderr}`);
    process.exit(2);
  }
  const found = [];
  let file = null;
  let at = 0;
  for (const l of r.stdout.split("\n")) {
    if (l.startsWith("+++ ")) file = l.startsWith("+++ b/") ? l.slice(6) : null;
    else if (l.startsWith("@@")) at = Number(/\+(\d+)/.exec(l)[1]);
    else if (l.startsWith("+") && file) {
      const why = file.endsWith(".hs") ? reason(l.slice(1)) : null;
      if (why)
        found.push(
          `  ${file}:${at}  ${why}: ${l.slice(1).trim().slice(0, 110)}`,
        );
      at++;
    }
  }
  for (const f of found) console.log(f);
  console.log(
    found.length
      ? `WARN: ${found.length} added assertion(s) may compare output that still carries "\\r" on Windows; ` +
          `drop it on both sides, as in \`map (filter (/= '\\r')) (lines sout)\``
      : "PASS: no added assertion compares raw output across a line break",
  );
}

function selftest() {
  const flag = [
    'sout `shouldSatisfy` ("- if it is Green: 2\\n    - otherwise: 3" `isInfixOf`)',
    'lines sout `shouldBe` ["a", "b"]',
    "sout `shouldBe` expected",
    "outStderr o `shouldBe` golden",
    "unless (any ((== heading) . dropWhile (== ' ')) (lines sout)) $",
  ];
  const pass = [
    "filter (/= '\\r') sout `shouldBe` filter (/= '\\r') src",
    'sout `shouldSatisfy` ("xor" `isInfixOf`)',
    'serr `shouldBe` ""',
    "case map (filter (/= '\\r')) (lines sout) of",
    '-- sout `shouldBe` "a\\nb"',
    "code `shouldBe` ExitSuccess",
    "nonBlankLines sout `shouldBe` 2",
    'length (filter ("#EVAL" `isPrefixOf`) (lines sout)) `shouldBe` 0',
    '>>= (`shouldBe` map ok [String "a\\n      b", String "z"])',
  ];
  const wrong = [
    ...flag.filter((l) => !reason(l)),
    ...pass.filter((l) => reason(l)),
  ];
  for (const l of wrong) console.log(`  misread: ${l}`);
  console.log(
    wrong.length
      ? "selftest FAIL"
      : `selftest PASS (${flag.length} flagged, ${pass.length} left alone)`,
  );
  return wrong.length ? 1 : 0;
}

const args = process.argv.slice(2);
if (args[0] === "--selftest") process.exit(selftest());
let base = "origin/unstable";
const bi = args.indexOf("--base");
if (bi >= 0) {
  base = args[bi + 1];
  args.splice(bi, 2);
}
if (args.length !== 1 || !base) {
  console.error(
    "usage: node etc/probe-cli-crlf.mjs [--base <ref>] <worktree>  |  --selftest",
  );
  process.exit(2);
}
scan(args[0], base);
