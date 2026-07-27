// Prove that check-bpmn-soundness.mjs can still fail.
//
// A checker whose only observed behaviour is "PASS" is indistinguishable from a
// checker that has been quietly broken, and this repo has already been bitten
// by a green suite over a wrong diagram. So the fixtures come in two piles and
// this asserts both directions:
//
//   jl4/examples/bpmn/expected/*.bpmn   MUST be reported SOUND   (exit 0)
//   jl4/examples/bpmn/unsound/*.bpmn    MUST be reported UNSOUND (exit 1), AND
//                                       must fail the SPECIFIC property it was
//                                       written to exercise, per EXERCISES below
//
// The second pile is the demonstration that this route catches the defects it
// was added for, all of which bpmn-moddle passes at zero warnings. See
// jl4/examples/bpmn/unsound/.
//
// Naming the property per fixture, rather than accepting any failure, is what
// stops a fixture from "passing" for an incidental reason — a typo'd id would
// make almost any file unsound and would otherwise look like proof. It also
// forces every unsound fixture to be declared here: an undeclared one is a
// failure, so the S-properties cannot silently drift out of coverage.
//
// Zero install, zero dependencies:
//
//   node etc/check-bpmn-soundness.selftest.mjs
//
// Exit 0 if every expectation held, 1 otherwise.

import { execFileSync } from "node:child_process";
import { readdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, "..");
const checker = join(here, "check-bpmn-soundness.mjs");
const piles = [
  { dir: join(repo, "jl4/examples/bpmn/expected"), verdict: "SOUND", code: 0 },
  { dir: join(repo, "jl4/examples/bpmn/unsound"), verdict: "UNSOUND", code: 1 },
];

// Which property each unsound fixture exists to make fail. Every .bpmn in the
// unsound pile must appear here; see the header for why.
const EXERCISES = {
  "deadlock-boundary-in-rand.bpmn": "S2 no deadlock",
  "deadlock-ror-in-rand.bpmn": "S2 no deadlock",
  "unsafe-xor-join-after-rand.bpmn": "S4 safe (1-bounded)",
};

let failures = 0;
let checked = 0;

for (const { dir, verdict, code } of piles) {
  if (!existsSync(dir)) {
    console.error(
      `MISSING  ${dir} — the self-test needs both piles to mean anything`,
    );
    failures++;
    continue;
  }
  const files = readdirSync(dir)
    .filter((f) => f.endsWith(".bpmn"))
    .sort();
  if (files.length === 0) {
    console.error(`EMPTY    ${dir} — refusing to pass on an empty pile`);
    failures++;
    continue;
  }
  for (const f of files) {
    const path = join(dir, f);
    let out, status;
    try {
      out = execFileSync(process.execPath, [checker, path], {
        encoding: "utf8",
      });
      status = 0;
    } catch (err) {
      out = `${err.stdout ?? ""}${err.stderr ?? ""}`;
      status = err.status ?? 1;
    }
    checked++;

    const problems = [];
    if (status !== code) problems.push(`exit ${status}, expected ${code}`);
    if (!out.includes(`: ${verdict}`))
      problems.push(`did not report ${verdict}`);
    // Each unsound fixture exists for one property; make sure it is that
    // property that fires, not some incidental complaint.
    if (verdict === "UNSOUND") {
      const want = EXERCISES[f];
      if (!want)
        problems.push(
          `not listed in EXERCISES — declare which property this fixture exists to fail`,
        );
      else if (!out.includes(`FAIL  ${want}`))
        problems.push(
          `${want} did not fail — that is what this fixture is for`,
        );
    }
    if (verdict === "SOUND" && /FAIL/.test(out))
      problems.push("a property failed on a fixture expected to be sound");

    if (problems.length) {
      failures++;
      console.error(`FAIL  ${f}`);
      for (const p of problems) console.error(`        ${p}`);
      console.error(out.replace(/^/gm, "      | "));
    } else {
      console.log(`ok    ${f} — ${verdict}`);
    }
  }
}

console.log(`\n${checked} fixture(s) checked, ${failures} failure(s)`);
process.exit(failures ? 1 : 0);
