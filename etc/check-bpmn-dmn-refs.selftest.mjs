#!/usr/bin/env node
// Self-test for etc/check-bpmn-dmn-refs.mjs.
//
// The resolver's whole job is to catch a reference that dangles, and today no
// emitted golden has one — so its only observed behaviour in CI is "OK", which
// is indistinguishable from a resolver that says OK unconditionally. Every case
// below takes the REAL emitted pair, breaks the linkage in one specific way,
// and asserts the resolver objects; the last group breaks nothing and asserts
// it does not.
//
//   node etc/check-bpmn-dmn-refs.selftest.mjs
//
// Needs no JVM, no network and nothing installed: it mutates the goldens in a
// temporary directory and never touches the tree.

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const HERE = new URL(".", import.meta.url).pathname;
const CHECKER = join(HERE, "check-bpmn-dmn-refs.mjs");
const ROOT = join(HERE, "..");
const BPMN = join(ROOT, "jl4/examples/bpmn/expected/regcf-reporting.bpmn");
const DMN = join(ROOT, "jl4/examples/dmn/expected/regcf-corpus.dmn");

let failures = 0;
function ok(what, cond, detail = "") {
  if (cond) console.log(`  ok    ${what}`);
  else {
    failures++;
    console.log(`  FAIL  ${what}${detail ? ` — ${detail}` : ""}`);
  }
}

const bpmnSrc = readFileSync(BPMN, "utf8");
const dmnSrc = readFileSync(DMN, "utf8");

// The whole point of the fixture: if the golden ever stops carrying a
// businessRuleTask, every "it objects" case below would pass vacuously.
if (!/businessRuleTask/.test(bpmnSrc)) {
  console.error(
    `${BPMN} contains no <businessRuleTask>; this self-test would be vacuous. ` +
      "Either the wiring regressed or the fixture moved.",
  );
  process.exit(2);
}

const dir = mkdtempSync(join(tmpdir(), "bpmn-dmn-refs-"));
try {
  // Run the checker over one mutated BPMN and one mutated DMN, returning its
  // exit code. Either mutation may be the identity.
  const run = (mutateBpmn = (s) => s, mutateDmn = (s) => s) => {
    const b = join(dir, "case.bpmn");
    const d = join(dir, "case.dmn");
    writeFileSync(b, mutateBpmn(bpmnSrc));
    writeFileSync(d, mutateDmn(dmnSrc));
    try {
      execFileSync(process.execPath, [CHECKER, b, d], { stdio: "pipe" });
      return 0;
    } catch (e) {
      return e.status;
    }
  };

  console.log("\n-- the gate must FAIL on a broken linkage --\n");

  ok(
    "a decision name the DMN does not declare",
    run((s) =>
      s.replace(
        />ongoing_reporting_obligation</,
        ">ongoing_reporting_obligation_TYPO<",
      ),
    ) === 1,
  );

  ok(
    "the decision was renamed on the DMN side only",
    run(undefined, (s) =>
      s.replace(
        /<decision id="decision_ongoing_reporting_obligation" name="ongoing_reporting_obligation"/,
        '<decision id="decision_ongoing_reporting_obligation" name="renamed_by_the_dmn_backend"',
      ),
    ) === 1,
  );

  ok(
    "a namespace no supplied DMN serves",
    run((s) =>
      s.replace(
        />https:\/\/legalese\.com\/l4\/dmn\/[a-z0-9_]+</,
        ">https://example.invalid/nowhere<",
      ),
    ) === 1,
  );

  ok(
    "a model name no supplied DMN declares",
    run((s) =>
      s.replace(
        />SEC Regulation Crowdfunding — 17 CFR Part 227</,
        ">Some Other Model<",
      ),
    ) === 1,
  );

  ok(
    "the rule language is not the DMN one",
    run((s) =>
      s.replace(
        /implementation="http:\/\/www\.jboss\.org\/drools\/dmn"/,
        'implementation="##unspecified"',
      ),
    ) === 1,
  );

  ok(
    "the decision dataInput carries no assignment at all",
    run((s) =>
      s.replace(
        /<bpmn:dataInputAssociation id="DIA_Decide_0_decision">[\s\S]*?<\/bpmn:dataInputAssociation>\n/,
        "",
      ),
    ) === 1,
  );

  console.log("\n-- and it must PASS what is actually fine --\n");

  ok("the real emitted pair resolves", run() === 0);

  ok(
    "a BPMN with no businessRuleTask is not a failure",
    run((s) => s.replace(/businessRuleTask/g, "task")) === 0,
  );

  console.log(
    "\n-- and refuse to answer when it was given nothing to resolve against --\n",
  );

  const exitOf = (args) => {
    try {
      execFileSync(process.execPath, [CHECKER, ...args], { stdio: "pipe" });
      return 0;
    } catch (e) {
      return e.status;
    }
  };
  ok("no arguments exits 2", exitOf([]) === 2);
  ok("BPMN files but no DMN exits 2, not 0", exitOf([BPMN]) === 2);
  ok("DMN files but no BPMN exits 2", exitOf([DMN]) === 2);
} finally {
  rmSync(dir, { recursive: true, force: true });
}

console.log(`\n${failures === 0 ? "PASS" : "FAIL"} — ${failures} failure(s)\n`);
process.exit(failures === 0 ? 0 : 1);
