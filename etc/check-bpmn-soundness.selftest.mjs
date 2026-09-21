// Prove that check-bpmn-soundness.mjs can still fail.
//
// A checker whose only observed behaviour is "PASS" is indistinguishable from a
// checker that has been quietly broken, and this repo has already been bitten
// by a green suite over a wrong diagram. So the fixtures come in two piles and
// this asserts both directions:
//
//   jl4/examples/bpmn/expected/*.bpmn   MUST be reported SOUND   (exit 0)
//   jl4/examples/bpmn/sound/*.bpmn      MUST be reported SOUND   (exit 0)
//   jl4/examples/bpmn/unsound/*.bpmn    MUST be reported UNSOUND (exit 1), AND
//                                       must produce the SPECIFIC complaint it
//                                       was written to provoke — a token-game
//                                       `FAIL  Sn …`, a `STRUCTURE  …`
//                                       well-formedness line, or a `FIDELITY  …`
//                                       undeclared-loss line, per EXERCISES below
//
// `expected/` is exporter output. `sound/` is hand-written, and exists because
// a gate is not only wrong when it misses a defect — it is also wrong when it
// invents one, and no golden covered that. Its first member pins the rule that
// an error end event TERMINATES the instance: model that end event as an
// ordinary one-token sink and the diagram is reported as deadlocking, which is a
// bug in the checker rather than in the diagram. Mutation-tested: disabling
// terminate semantics leaves every other fixture here green.
//
// The second pile is the demonstration that this route catches the defects it
// was added for, all of which bpmn-moddle passes at zero warnings. See
// jl4/examples/bpmn/unsound/.
//
// Naming the property per fixture, rather than accepting any failure, is what
// stops a fixture from "passing" for an incidental reason — a typo'd id would
// make almost any file unsound and would otherwise look like proof.
//
// Coverage drift is asserted in BOTH directions, because the first version only
// caught one of them. An UNDECLARED fixture is a failure (nobody said what it is
// for), and so is a DECLARED fixture that was never seen — deleting the only S4
// witness used to leave this self-test green, which is exactly how a property
// silently drops out of coverage.
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
  { dir: join(repo, "jl4/examples/bpmn/sound"), verdict: "SOUND", code: 0 },
  { dir: join(repo, "jl4/examples/bpmn/unsound"), verdict: "UNSOUND", code: 1 },
];

// The line each unsound fixture must produce. Every .bpmn in the unsound pile
// must appear here; see the header for why.
//
// Stored as the literal output line, marker and all, because there are THREE
// kinds of defect and they must not be confusable: `FAIL  Sn …` is a token-game
// property the diagram violates, `STRUCTURE  …` is a well-formedness rule it
// breaks while playing perfectly well, and `FIDELITY  …` is a loss the file
// really has and does not declare — every S passes and the diagram is still not
// one a reader should be handed. A bare property name would have made a
// STRUCTURE fixture look like it was exercising a token-game property.
//
// A FIDELITY entry is stored as the PREFIX up to the element list, for two
// reasons: the tail names the sidecar by the path it was given on the command
// line and this self-test passes absolute ones, and the element list is a
// measurement that a change to the net would legitimately move.
const EXERCISES = {
  "deadlock-boundary-in-rand.bpmn": "FAIL  S2 no deadlock",
  "deadlock-ror-in-rand.bpmn": "FAIL  S2 no deadlock",
  "unsafe-xor-join-after-rand.bpmn": "FAIL  S4 safe (1-bounded)",
  "historical-handover-edge-counted-join.bpmn": "FAIL  S2 no deadlock",
  // Caught at 2 instances and invisible at 0, which is the point: a
  // multi-instance scope is played once per instance count and the verdict is
  // read across them. Before the expansion this file was NOT CHECKED at all.
  "deadlock-inside-mi-subprocess.bpmn": "FAIL  S2 no deadlock",
  // Sound in every token-game sense and silent about the one thing it does:
  // byte-for-byte the tenancy fork as the exporter emitted it before
  // fcd7ecb2c, where a member's escalation met a top-level ERROR end and so
  // cancelled the members who had not breached. Its own fidelity report is
  // checked in beside it with all nine of the notes it really carried, which is
  // what makes this a test of the rule rather than of a missing file.
  "historical-fork-undeclared-sibling-loss.bpmn":
    'FIDELITY  End_3 "Breach" throws away up to 3 token(s) still in flight',
  // The same rule, from the other side: not a historical file but today's fork
  // golden with one `<errorEventDefinition>` put back, i.e. the defect
  // RE-INTRODUCED. It exists because the rule as first written did not catch
  // that — it also read the terminating end event's own `<documentation>`, and
  // the exporter puts a counterfactual about error ends on exactly that element.
  // The file keeps that documentation unedited; what changed is that nothing
  // reads it.
  "refork-counterfactual-documentation.bpmn":
    'FIDELITY  EndBreach_0 "Breach" throws away up to 3 token(s) still in flight',
  "mislabelled-gateway-direction.bpmn":
    'STRUCTURE  exclusiveGateway Split_0 declares gatewayDirection="Diverging" ' +
    "but has 2 incoming and 2 outgoing sequence flow(s)",
};

let failures = 0;
let checked = 0;
const seen = new Set();

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
      seen.add(f);
      const want = Object.hasOwn(EXERCISES, f) ? EXERCISES[f] : undefined;
      if (!want)
        problems.push(
          `not listed in EXERCISES — declare which property this fixture exists to fail`,
        );
      else if (!out.includes(want))
        problems.push(
          `${want} did not fire — that is what this fixture is for`,
        );
    }
    if (verdict === "SOUND" && /FAIL|STRUCTURE|FIDELITY/.test(out))
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

// The other direction: a declared fixture that never turned up. Deleting a
// witness must break this self-test, not quietly shrink its coverage.
for (const f of Object.keys(EXERCISES))
  if (!seen.has(f)) {
    failures++;
    console.error(
      `MISSING  ${f} — declared in EXERCISES for "${EXERCISES[f]}" but not found in the unsound pile.`,
    );
    console.error(
      `        Either restore it or delete its EXERCISES entry, deliberately.`,
    );
  }

console.log(`\n${checked} fixture(s) checked, ${failures} failure(s)`);
process.exit(failures ? 1 : 0);
