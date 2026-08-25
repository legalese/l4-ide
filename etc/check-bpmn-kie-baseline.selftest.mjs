#!/usr/bin/env node
// Self-test for etc/check-bpmn-kie-baseline.mjs.
//
// A baseline comparator that has only ever been observed to say "OK" is
// indistinguishable from one that says "OK" unconditionally — which is exactly
// the failure it was written to fix, so shipping it without this file would
// have reproduced the bug one level up.
//
// Every case below mutates a REAL transcript (captured from
// `etc/check-bpmn-kie.sh jl4/examples/bpmn/expected/*.bpmn`) in one specific
// way, and asserts the comparator notices — or, for the last group,
// deliberately does not.
//
//   node etc/check-bpmn-kie-baseline.selftest.mjs
//
// Needs no JVM, no Maven and no network: the transcript is a fixture.

import {
  parseTranscript,
  parseBaseline,
  compare,
} from "./check-bpmn-kie-baseline.mjs";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";

const HERE = new URL(".", import.meta.url).pathname;
const CMP = HERE + "check-bpmn-kie-baseline.mjs";
const BASELINE_PATH = HERE + "bpmn-kie-baseline.txt";

// A faithful abridgement of the real harness output: the lines the comparator
// reads, in the order it reads them, with the prose tails intact so that the
// "prose churn is tolerated" cases below are testing the real shapes.
const TRANSCRIPT = `jBPM/KIE second opinion  (jbpm-bpmn2 7.74.1.Final)

=========================================================
FILE  consultation.bpmn
=========================================================
[PHASE 0 adapt] 2 adaptation(s) — see the header for which are flavor axes and which are gaps
[PHASE 1 compile] errors=0 warnings=0
[PHASE 2 execute] COMPLETED — reaches an end state on the path explored

=========================================================
FILE  handover.bpmn
=========================================================
[PHASE 0 adapt] 4 adaptation(s) — see the header for which are flavor axes and which are gaps
[PHASE 1 compile] errors=4 warnings=0
   ERROR   Unable to Analyse Expression
   ERROR   Unable to Analyse Expression
   ERROR   Unable to Analyse Expression
   ERROR   Unable to Analyse Expression
   -> jBPM REJECTS this file. NOT EXECUTED, so nothing below was checked.

=========================================================
FILE  offering.bpmn
=========================================================
[PHASE 0 adapt] 3 adaptation(s) — see the header for which are flavor axes and which are gaps
[PHASE 1 compile] errors=0 warnings=0
[PHASE 2 execute] ABORTED via error end event [Breach] — a modelled terminal state, not a liveness defect

=========================================================
FILE  regcf-advertising.bpmn
=========================================================
[PHASE 0 adapt] 3 adaptation(s) — see the header for which are flavor axes and which are gaps
[PHASE 1 compile] errors=4 warnings=0
   ERROR   mismatched input 'WITHIN'
   ERROR   Unable to Analyse Expression
   ERROR   Unable to Analyse Expression
   ERROR   Unable to Analyse Expression
   -> jBPM REJECTS this file. NOT EXECUTED, so nothing below was checked.

=========================================================
FILE  regcf-reporting.bpmn
=========================================================
[PHASE 0 adapt] 3 adaptation(s) — see the header for which are flavor axes and which are gaps
[PHASE 1 compile] errors=1 warnings=0
   ERROR   Unknown gateway direction: Mixed
   -> jBPM REJECTS this file. NOT EXECUTED, so nothing below was checked.

=========================================================
FILE  regcf-resale.bpmn
=========================================================
[PHASE 0 adapt] 3 adaptation(s) — see the header for which are flavor axes and which are gaps
[PHASE 1 compile] errors=6 warnings=0
   ERROR   Unable to Analyse Expression
   -> jBPM REJECTS this file. NOT EXECUTED, so nothing below was checked.

RESULT: 4 file(s) with findings.
`;

const BASELINE = parseBaseline(readFileSync(BASELINE_PATH, "utf8"));

let failures = 0;
const ok = (label, cond, detail) => {
  console.log(
    `${cond ? "ok   " : "FAIL "} ${label}${cond || !detail ? "" : ` — ${detail}`}`,
  );
  if (!cond) failures++;
};

// A mutation is caught iff `compare` reports at least one problem matching the
// expected class. Matching on the class, not the whole sentence, so rewording a
// diagnostic does not fail the self-test.
const caughtAs = (label, mutate, expectClass) => {
  const problems = compare(BASELINE, parseTranscript(mutate(TRANSCRIPT)));
  const hit = problems.some((p) => p.startsWith(expectClass));
  ok(
    label,
    hit,
    hit
      ? ""
      : `got ${problems.length ? problems.join(" | ") : "NO problems at all"}`,
  );
};

console.log("\n-- the fixture itself must match the committed baseline --\n");
{
  const problems = compare(BASELINE, parseTranscript(TRANSCRIPT));
  ok(
    "unmutated transcript is clean",
    problems.length === 0,
    problems.join(" | "),
  );
}

console.log("\n-- regressions the gate MUST catch --\n");

caughtAs(
  "a fifth golden starts being rejected",
  (t) =>
    t.replace(
      "RESULT: 4 file(s) with findings.",
      `=========================================================
FILE  brand-new.bpmn
=========================================================
[PHASE 1 compile] errors=2 warnings=0
   -> jBPM REJECTS this file. NOT EXECUTED, so nothing below was checked.

RESULT: 5 file(s) with findings.`,
    ),
  "UNBASELINED",
);

caughtAs(
  "a file silently stops being checked (narrowed glob)",
  (t) => t.replace(/=+\nFILE {2}regcf-resale\.bpmn\n[\s\S]*?(?=\nRESULT:)/, ""),
  "NOT CHECKED",
);

caughtAs(
  "a rejected file gains an extra compile error",
  (t) =>
    t.replace(
      "errors=4 warnings=0\n   ERROR   mismatched",
      "errors=5 warnings=0\n   ERROR   mismatched",
    ),
  "CHANGED",
);

caughtAs(
  "a clean file starts deadlocking",
  (t) =>
    t.replace(
      "[PHASE 2 execute] COMPLETED — reaches an end state on the path explored",
      "[PHASE 2 execute] DEADLOCK — left ACTIVE, cannot reach any end state",
    ),
  "CHANGED",
);

caughtAs(
  "a clean file starts duplicating work",
  (t) =>
    t.replace(
      "[PHASE 2 execute] COMPLETED — reaches an end state on the path explored",
      "[PHASE 2 execute] COMPLETED — reaches an end state on the path explored\n   DUPLICATION — the process is acyclic, so firing twice means a merge",
    ),
  "CHANGED",
);

caughtAs(
  "a compile warning appears where there was none",
  (t) =>
    t.replace(
      "errors=0 warnings=0\n[PHASE 2 execute] COMPLETED",
      "errors=0 warnings=3\n[PHASE 2 execute] COMPLETED",
    ),
  "CHANGED",
);

caughtAs(
  "the harness tally moves on its own",
  (t) => t.replace("RESULT: 4 file(s)", "RESULT: 3 file(s)"),
  "RESULT",
);

// Found the hard way: breaking a golden's XML on purpose produced a FILE block
// with no PHASE lines at all, which parsed to verdict=null and exited 2 with a
// message blaming KieBpmnCheck.java. Red either way, but for the wrong reason.
// A file jBPM cannot even read is a verdict about that file.
caughtAs(
  "a golden becomes unparseable (HARNESS ERROR, no PHASE lines)",
  (t) =>
    t.replace(
      "[PHASE 0 adapt] 2 adaptation(s) — see the header for which are flavor axes and which are gaps\n[PHASE 1 compile] errors=0 warnings=0\n[PHASE 2 execute] COMPLETED — reaches an end state on the path explored",
      '  HARNESS ERROR org.xml.sax.SAXParseException: The element type "bpmn:parallelGateway" must be terminated by the matching end-tag "</bpmn:parallelGateway>".',
    ),
  "CHANGED",
);

// The improvement direction is a change too. A golden that starts compiling is
// good news, and it still must not land silently: the baseline is the record of
// where we stand, and unrecorded good news is how the next regression hides.
caughtAs(
  "a rejected file starts compiling (an IMPROVEMENT is still a change)",
  (t) =>
    t.replace(
      "[PHASE 1 compile] errors=1 warnings=0\n   ERROR   Unknown gateway direction: Mixed\n   -> jBPM REJECTS this file. NOT EXECUTED, so nothing below was checked.",
      "[PHASE 1 compile] errors=0 warnings=0\n[PHASE 2 execute] COMPLETED — reaches an end state on the path explored",
    ),
  "CHANGED",
);

console.log("\n-- churn the gate must deliberately TOLERATE --\n");

// If this ever starts failing, someone has tightened the comparator onto error
// text. That feels stricter and is not: it makes the gate fire on every jBPM
// bump and every reworded L4 label, which is how a gate gets routinely
// --updated until it asserts nothing.
{
  const reworded = TRANSCRIPT.replace(
    /ERROR   [^\n]*/g,
    "ERROR   something else entirely, from a different jBPM build",
  );
  const problems = compare(BASELINE, parseTranscript(reworded));
  ok(
    "error TEXT may change freely while counts hold",
    problems.length === 0,
    problems.join(" | "),
  );
}
{
  const renumbered = TRANSCRIPT.replace(
    /\[PHASE 0 adapt\] \d+ adaptation/g,
    "[PHASE 0 adapt] 99 adaptation",
  );
  const problems = compare(BASELINE, parseTranscript(renumbered));
  ok(
    "PHASE 0 adaptation counts are not pinned",
    problems.length === 0,
    problems.join(" | "),
  );
}

console.log("\n-- transcripts that are not verdicts at all --\n");

const exitOf = (input, args = []) => {
  try {
    execFileSync(process.execPath, [CMP, ...args], {
      input,
      stdio: ["pipe", "pipe", "pipe"],
    });
    return 0;
  } catch (e) {
    return e.status;
  }
};

ok("empty input exits 2, not 0", exitOf("") === 2);
ok(
  "a transcript with FILE blocks but no RESULT exits 2",
  exitOf(TRANSCRIPT.replace(/RESULT:.*/, "")) === 2,
);
ok(
  "an unrelated log that happens to contain RESULT: exits 2",
  exitOf("RESULT: no findings.\n") === 2,
);
ok("the real fixture through the CLI exits 0", exitOf(TRANSCRIPT) === 0);

console.log(`\n${failures === 0 ? "PASS" : "FAIL"} — ${failures} failure(s)\n`);
process.exit(failures === 0 ? 0 : 1);
