#!/usr/bin/env node
// Negative control for assert-report.mjs.
//
// House convention (etc/check-bpmn-kie-baseline.selftest.mjs): every positive
// control ships a negative sibling. A checker that only ever sees green input
// has not been shown to be capable of red.
//
// The two envelopes below are REAL captures from the prebuilt `l4` binary on
// 2026-08-02, then mutated (the source basenames are generalised to
// `corpus.l4`; the capture came from the inaugural subject's corpus). The
// green one is the shape `l4 run <module> --json` actually emits; the red one
// is the shape a failing `#ASSERT` actually emits — note `"ok": true` and
// process exit 0 in BOTH.
//
//   node etc/go/lib/assert-report.selftest.mjs
// Exit: 0 the checker objects when it should and does not when it should not.

import { analyse } from "./assert-report.mjs";

let failures = 0;
const check = (name, cond) => {
  process.stdout.write(`${cond ? "ok  " : "FAIL"} ${name}\n`);
  if (!cond) failures++;
};

// --- captured green: three passing assertions and a value ---------------------
const green = {
  diagnostics: [],
  file: "/…/corpus.l4",
  ok: true,
  results: [
    { kind: "assertion", range: "corpus.l4:890:1-50", value: true },
    { kind: "assertion", range: "corpus.l4:891:1-52", value: true },
    { kind: "assertion", range: "corpus.l4:892:1-52", value: true },
    { kind: "value", range: "corpus.l4:900:1-20", value: 12 },
  ],
};

// --- captured red: ONE failing assertion, and `ok` STILL true ------------------
const red = {
  diagnostics: ["Info | updateFileDiagnostics … Message:  assertion failed"],
  file: "/tmp/failing.l4",
  ok: true,
  results: [{ kind: "assertion", range: "failing.l4:5:1-30", value: false }],
};

const g = analyse(green);
check("the green capture is accepted", g.ok === true);
check("the green capture counts 3 assertions", g.assertions_total === 3);
check("the green capture counts 1 value", g.values_total === 1);

const r = analyse(red);
check("the red capture is REJECTED", r.ok === false);
check(
  "the red capture is rejected despite ok:true",
  r.typecheck_ok === true && r.ok === false,
);
check(
  "the red capture names the failing range",
  r.failures[0].range === "failing.l4:5:1-30",
);

// --- eight mutations of the green capture; every one must be caught ------------
const mutations = [
  ["one assertion flipped false", (e) => (e.results[1].value = false)],
  ["one assertion set null", (e) => (e.results[1].value = null)],
  [
    "one assertion set to the string 'true'",
    (e) => (e.results[1].value = "true"),
  ],
  [
    "an error result appended",
    (e) =>
      e.results.push({
        kind: "error",
        range: "corpus.l4:1:1-1",
        value: "Division by zero",
      }),
  ],
  [
    "a Stuck error result appended",
    (e) =>
      e.results.push({
        kind: "error",
        range: "corpus.l4:2:1-1",
        value: "Stuck",
      }),
  ],
  [
    "every assertion flipped false",
    (e) =>
      e.results
        .filter((x) => x.kind === "assertion")
        .forEach((x) => (x.value = false)),
  ],
  ["ok flipped false but results still green", (e) => (e.ok = false)],
  ["results emptied", (e) => (e.results = [])],
];
for (const [name, mutate] of mutations) {
  const e = JSON.parse(JSON.stringify(green));
  mutate(e);
  const a = analyse(e);
  // The last two are the interesting ones: `ok:false` with green results is NOT
  // a finding for this checker (typechecking is `l4 check`'s job and has its own
  // stage), and an empty results array is vacuously clean — which is exactly why
  // p6-tests.sh separately asserts a MINIMUM assertion count.
  const expectedObjection = ![
    "ok flipped false but results still green",
    "results emptied",
  ].includes(name);
  check(`mutation caught: ${name}`, a.ok === !expectedObjection);
}

// --- and the checker must not object to a file it has no opinion about --------
check("an envelope with no results is not a crash", analyse({}).ok === true);
check("a null envelope is not a crash", analyse(null).ok === true);

process.stdout.write(
  failures === 0
    ? "assert-report.selftest: all checks passed\n"
    : `assert-report.selftest: ${failures} FAILED\n`,
);
process.exit(failures === 0 ? 0 : 1);
