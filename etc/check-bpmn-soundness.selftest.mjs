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
import {
  readdirSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  writeFileSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
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
  // THE ACCEPTANCE FIXTURE for the declaration rule, and the only one of the
  // three where the phrase list does no work at all. Today's
  // tenancy-fork-beside-party with one `<errorEventDefinition>` put back, i.e.
  // the same re-introduction as above — but inside an unjoined RAND, so its real
  // report carries a `lossy` `P-NOJOIN` that matches the phrase list and is filed
  // on a junction of this net. Two earlier versions of the rule read that as the
  // declaration and scored the file SOUND. It is not one: P-NOJOIN is about the
  // RAND's two branches, and this loss is one member of the cast cancelling
  // another, which the split cannot see. See CHANNELS below for the mutations
  // that pin the rest of the contract.
  "refork-beside-party-cross-instance.bpmn":
    'FIDELITY  EndBreach_1 "Breach" throws away up to 4 token(s) still in flight',
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

// CHANNELS: THE DECLARATION RULE MUST BE SATISFIABLE, AND MUST REFUSE TO GUESS.
//
// A red fixture on its own proves only that a rule can say no, and a rule that
// says no to everything is not a gate either — it is a `--fail` flag. Both of the
// following run on copies of the SAME red fixture in a temp directory, one line
// of its report apart, so what is being demonstrated is the rule and not a
// difference between two diagrams.
//
//   POSITIVE CONTROL  append one `lossy` note filed on the terminating end event
//                     and the identical XML is SOUND, exit 0. Without this leg,
//                     hard-coding `undeclared.push(...)` would pass this file.
//   CANNOT JUDGE      take the sidecar away and the verdict does NOT flip. The
//                     rule is not run, the output says so in those words, and the
//                     exit code is 0 — because `--fidelity-report` is opt-in and a
//                     verdict must be a property of the diagram plus whatever
//                     report came with it, never of whether someone passed a flag.
//   NEGATIVE CONTROL  append the SAME declaring note filed on the SUB-PROCESS
//                     instead, and the file stays UNSOUND. This is the one leg
//                     that pins the cross-instance narrowing, and it was added
//                     because nothing else did: mutation-tested 2026-09-21, and
//                     with this leg absent, accepting the scope's id for a
//                     cross-instance loss left the whole self-test green — the
//                     three red fixtures survived on the wording of the exporter's
//                     `P-FORK-JOIN` alone, which is exactly the fragility two
//                     rounds of review were about.
const unsoundDir = join(repo, "jl4/examples/bpmn/unsound");
// The acceptance fixture: a fork INSIDE an unjoined RAND, so the loss spans both
// the cast's own multiplicity and the RAND's branches.
const CHANNEL_SRC = join(unsoundDir, "refork-beside-party-cross-instance");
// A fork with NOTHING beside it, so the loss is purely cross-instance and the
// sub-process is the only junction in the file. That is what makes it the witness
// for the narrowing: on the fixture above, a note on the scope is rejected anyway
// for not covering the RAND half of the loss, so it proves nothing about it.
const FORK_SRC = join(unsoundDir, "refork-counterfactual-documentation");
const declaringNote = (element) =>
  `  [P-TERMINATE-CANCELS] lossy — ${element}\n` +
  "      Reaching this end ends every active thread in the process, so the runs of the members who did not breach are cancelled along with the one that did.\n" +
  "      lost: the duties of every member who had not breached when this end was reached\n";
const DECLARING_NOTE = declaringNote("EndBreach_1");

const run = (path) => {
  try {
    return {
      out: execFileSync(process.execPath, [checker, path], {
        encoding: "utf8",
      }),
      status: 0,
    };
  } catch (err) {
    return {
      out: `${err.stdout ?? ""}${err.stderr ?? ""}`,
      status: err.status ?? 1,
    };
  }
};

const tmp = mkdtempSync(join(tmpdir(), "bpmn-soundness-selftest-"));
const channels = [
  {
    name: "positive control: one lossy note on the terminating end event",
    stem: "declared",
    report:
      readFileSync(`${CHANNEL_SRC}.fidelity.txt`, "utf8") + DECLARING_NOTE,
    wantStatus: 0,
    wantIn: [": SOUND", "[P-TERMINATE-CANCELS] on EndBreach_1"],
    wantNotIn: ["FIDELITY"],
  },
  {
    name: "no sidecar: the rule is not run, and says so, without flipping the verdict",
    stem: "nosidecar",
    report: null,
    wantStatus: 0,
    wantIn: [
      ": SOUND",
      "CANNOT JUDGE: no fidelity report",
      "this is not a pass",
    ],
    wantNotIn: ["FIDELITY"],
  },
  {
    name: "negative control: on a pure fork, that note filed on the sub-process is not a declaration",
    src: FORK_SRC,
    stem: "onscope",
    report:
      readFileSync(`${FORK_SRC}.fidelity.txt`, "utf8") +
      declaringNote("Scope_0"),
    wantStatus: 1,
    wantIn: [
      ": UNSOUND",
      'FIDELITY  EndBreach_0 "Breach"',
      "no element in this file names one",
    ],
    wantNotIn: ["on Scope_0 by"],
  },
  {
    name: "positive control on the same pure fork: filed on its end event, it is",
    src: FORK_SRC,
    stem: "onend",
    report:
      readFileSync(`${FORK_SRC}.fidelity.txt`, "utf8") +
      declaringNote("EndBreach_0"),
    wantStatus: 0,
    wantIn: [": SOUND", "[P-TERMINATE-CANCELS] on EndBreach_0"],
    wantNotIn: ["FIDELITY"],
  },
];
for (const c of channels) {
  const bpmn = join(tmp, `${c.stem}.bpmn`);
  writeFileSync(bpmn, readFileSync(`${c.src ?? CHANNEL_SRC}.bpmn`, "utf8"));
  if (c.report !== null)
    writeFileSync(join(tmp, `${c.stem}.fidelity.txt`), c.report);
  const { out, status } = run(bpmn);
  checked++;
  const problems = [];
  if (status !== c.wantStatus)
    problems.push(`exit ${status}, expected ${c.wantStatus}`);
  for (const s of c.wantIn)
    if (!out.includes(s))
      problems.push(`output does not contain ${JSON.stringify(s)}`);
  for (const s of c.wantNotIn)
    if (out.includes(s))
      problems.push(`output contains ${JSON.stringify(s)} and must not`);
  if (problems.length) {
    failures++;
    console.error(`FAIL  channel — ${c.name}`);
    for (const p of problems) console.error(`        ${p}`);
    console.error(out.replace(/^/gm, "      | "));
  } else {
    console.log(`ok    channel — ${c.name}`);
  }
}
rmSync(tmp, { recursive: true, force: true });

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
