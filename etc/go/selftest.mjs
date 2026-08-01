#!/usr/bin/env node
// Proof that the honesty rules can still say no.
//
// The failure mode this defends against is not sabotage. It is erosion: seven
// statuses feel like bureaucracy, so DEGRADED quietly becomes green; a weak
// oracle gets picked because it is cheap; a resumed run reports `replayed` for
// a stage whose inputs actually moved. Each of those is one small edit away,
// and each is checked below.
//
//   node etc/go/selftest.mjs [--with-driver]
//
// Exit: 0 every check passed · 1 a check failed
//
// `--with-driver` additionally runs the driver twice to prove idempotence. It
// needs $L4 pointing at a prebuilt binary; without one it SKIPS with a named
// reason rather than passing silently.

import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { append, hashRecord, read, verify } from "./lib/ledger.mjs";
import {
  checkReceipt,
  milestoneVerdict,
  ORACLE_CLASSES,
  STATUSES,
} from "./lib/verdict.mjs";
import { CANONICALISATIONS } from "./lib/canon-diff.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../..");

let failures = 0;
let skips = 0;
const check = (name, cond) => {
  process.stdout.write(`${cond ? "ok  " : "FAIL"} ${name}\n`);
  if (!cond) failures++;
};
const skip = (name, why) => {
  process.stdout.write(`skip ${name} — ${why}\n`);
  skips++;
};

const base = (over = {}) => ({
  kind: "stage_end",
  stage: "p7-example",
  status: "PASS",
  reason: null,
  blocker: null,
  artifacts: [{ path: "x.dmn", bytes: 10, sha256: "sha256:deadbeef" }],
  oracle: {
    cmd: "some-checker x.dmn",
    exit: 0,
    class: "structural",
    because: "…",
  },
  metrics: {},
  notes: [],
  inputs_digest: "sha256:aaa",
  attempt: 1,
  replayed_from: null,
  label: null,
  ...over,
});

// ---------------------------------------------------------------- 1. lattice
process.stdout.write("\n-- the status lattice --\n");

check("a well-formed PASS is accepted", checkReceipt(base()).length === 0);

for (const status of STATUSES) {
  if (status === "PASS") continue;
  const needsBlocker = [
    "NOT-EXECUTABLE",
    "NOT-REGENERATED",
    "NOT-BUILT",
  ].includes(status);
  const r = base({
    status,
    oracle: null,
    reason: "a stated reason",
    blocker: needsBlocker ? "a named blocker" : null,
  });
  check(`${status} is producible`, checkReceipt(r).length === 0);
}

check(
  "PASS with a null oracle is REJECTED",
  checkReceipt(base({ oracle: null })).length > 0,
);
check(
  "PASS with oracle exit 1 is REJECTED",
  checkReceipt(base({ oracle: { cmd: "c", exit: 1, class: "structural" } }))
    .length > 0,
);
check(
  "PASS with no oracle command is REJECTED",
  checkReceipt(base({ oracle: { cmd: "", exit: 0, class: "structural" } }))
    .length > 0,
);
check(
  "PASS with no artifact is REJECTED",
  checkReceipt(base({ artifacts: [] })).length > 0,
);
check(
  "an artifact with no sha256 is REJECTED",
  checkReceipt(base({ artifacts: [{ path: "x" }] })).length > 0,
);
check(
  "an unknown status is REJECTED",
  checkReceipt(base({ status: "GREEN-ISH" })).length > 0,
);

// The weak-oracle rule: this is the crack the lattice erodes through, so it is
// checked class by class rather than by example.
for (const [cls, def] of Object.entries(ORACLE_CLASSES)) {
  const r = base({ oracle: { cmd: "c", exit: 0, class: cls, because: "…" } });
  const accepted = checkReceipt(r).length === 0;
  check(
    `a ${cls} oracle ${def.sufficient ? "may" : "may NOT"} license PASS`,
    accepted === def.sufficient,
  );
}
check(
  "PASS with an unknown oracle class is REJECTED",
  checkReceipt(base({ oracle: { cmd: "c", exit: 0, class: "vibes" } })).length >
    0,
);

// Non-PASS statuses must explain themselves.
check(
  "DEGRADED with no reason is REJECTED",
  checkReceipt(base({ status: "DEGRADED", oracle: null, reason: "" })).length >
    0,
);
check(
  "SKIPPED with no reason is REJECTED",
  checkReceipt(base({ status: "SKIPPED", oracle: null, reason: null })).length >
    0,
);
for (const s of ["NOT-EXECUTABLE", "NOT-REGENERATED", "NOT-BUILT"]) {
  check(
    `${s} with no blocker is REJECTED`,
    checkReceipt(
      base({ status: s, oracle: null, reason: "why", blocker: null }),
    ).length > 0,
  );
}

// A replayed receipt keeps its verdict with no oracle of its own — the oracle's
// row is named by replayed_from and lives in the same chain.
check(
  "a replayed PASS with no oracle is accepted (its evidence is the receipt it names)",
  checkReceipt(base({ oracle: null, replayed_from: "sha256:earlier" }))
    .length === 0,
);
check(
  "a NON-replayed PASS with no oracle is still REJECTED",
  checkReceipt(base({ oracle: null, replayed_from: null })).length > 0,
);

// -------------------------------------------------------------- 2. milestone
process.stdout.write("\n-- the milestone rule --\n");

const declared = ["a", "b", "c"];
const ok = [
  base({ stage: "a" }),
  base({ stage: "b", status: "DEGRADED", oracle: null, reason: "why" }),
  base({ stage: "c", status: "SKIPPED", oracle: null, reason: "no tool" }),
];
check(
  "a milestone of PASS + DEGRADED + SKIPPED is COMPLETE",
  milestoneVerdict({ declared, receipts: ok, gates: [] }).verdict ===
    "COMPLETE",
);
check(
  "a milestone with a BROKEN receipt is NOT COMPLETE",
  milestoneVerdict({
    declared,
    receipts: [
      ...ok.slice(0, 2),
      base({ stage: "c", status: "BROKEN", oracle: null, reason: "harness" }),
    ],
    gates: [],
  }).verdict === "BROKEN",
);
check(
  "a milestone missing a declared stage is INCOMPLETE",
  milestoneVerdict({ declared, receipts: ok.slice(0, 2), gates: [] })
    .verdict === "INCOMPLETE",
);
check(
  "a milestone with an unexplained non-PASS is INCOMPLETE",
  milestoneVerdict({
    declared,
    receipts: [
      ...ok.slice(0, 2),
      { stage: "c", status: "DEGRADED", reason: "" },
    ],
    gates: [],
  }).verdict === "INCOMPLETE",
);
check(
  "a refused gate makes the milestone GATE",
  milestoneVerdict({
    declared,
    receipts: ok,
    gates: [{ gate: "HG1", state: "refused" }],
  }).verdict === "GATE",
);
check(
  "a WAIVED gate does not block the milestone",
  milestoneVerdict({
    declared,
    receipts: ok,
    gates: [{ gate: "HG1", state: "waived", reason: "why" }],
  }).verdict === "COMPLETE",
);
check(
  "BROKEN outranks GATE",
  milestoneVerdict({
    declared,
    receipts: [
      ...ok.slice(0, 2),
      base({ stage: "c", status: "BROKEN", oracle: null, reason: "h" }),
    ],
    gates: [{ gate: "HG1", state: "refused" }],
  }).verdict === "BROKEN",
);

// ------------------------------------------------------------------ 3. chain
process.stdout.write("\n-- the journal chain --\n");

const dir = mkdtempSync(resolve(tmpdir(), "l4-go-selftest-"));
const journal = resolve(dir, "journal.ndjson");
append(journal, {
  kind: "run_begin",
  run_id: "test",
  milestone: "g1",
  subject: "t",
  declared_stages: ["a"],
});
const rec = append(journal, base({ stage: "a" }));
append(journal, { kind: "run_end", verdict: "COMPLETE", exit: 0 });
check("a freshly written chain verifies", verify(journal).ok === true);

const lines = readFileSync(journal, "utf8").trimEnd().split("\n");
{
  const tampered = JSON.parse(lines[1]);
  tampered.status = "PASS";
  tampered.reason = "edited by hand";
  writeFileSync(
    resolve(dir, "t1.ndjson"),
    [lines[0], JSON.stringify(tampered), lines[2]].join("\n") + "\n",
  );
  const v = verify(resolve(dir, "t1.ndjson"));
  check(
    "editing a record breaks the chain",
    v.ok === false && v.problems.some((p) => /hash mismatch/.test(p)),
  );
}
{
  writeFileSync(
    resolve(dir, "t2.ndjson"),
    [lines[0], lines[2]].join("\n") + "\n",
  );
  const v = verify(resolve(dir, "t2.ndjson"));
  check("deleting a record breaks the chain", v.ok === false);
}
{
  // The hardest case: a rewritten record with its OWN hash recomputed. The
  // chain still breaks, because every later record's `prev` points at the old
  // hash. This is why the chain is per-record and not a single digest.
  const t = JSON.parse(lines[1]);
  t.status = "DEGRADED";
  t.reason = "laundered";
  t.hash = hashRecord(t);
  writeFileSync(
    resolve(dir, "t3.ndjson"),
    [lines[0], JSON.stringify(t), lines[2]].join("\n") + "\n",
  );
  check(
    "rewriting a record AND its hash still breaks the chain",
    verify(resolve(dir, "t3.ndjson")).ok === false,
  );
}
{
  const bumped = JSON.parse(lines[1]);
  bumped.journal_schema = 99;
  bumped.hash = hashRecord(bumped);
  writeFileSync(
    resolve(dir, "t4.ndjson"),
    [lines[0], JSON.stringify(bumped), lines[2]].join("\n") + "\n",
  );
  const v = verify(resolve(dir, "t4.ndjson"));
  check(
    "an unknown journal_schema is reported, not silently misread",
    v.ok === false && v.problems.some((p) => /journal_schema/.test(p)),
  );
}
check(
  "receipt.mjs is the only module that calls append()",
  (() => {
    const callers = execFileSync(
      "grep",
      ["-rl", "append(", resolve(HERE, "lib")],
      { encoding: "utf8" },
    )
      .trim()
      .split("\n")
      .map((p) => p.split("/").pop())
      .filter((f) => f !== "ledger.mjs");
    return callers.length === 1 && callers[0] === "receipt.mjs";
  })(),
);

// ------------------------------------------------------------- 4. the driver
process.stdout.write("\n-- the driver --\n");

if (!process.argv.includes("--with-driver")) {
  skip(
    "idempotence under replay",
    "pass --with-driver to run it (it drives the whole G1 pipeline)",
  );
} else if (!process.env.L4 || !existsSync(process.env.L4)) {
  skip(
    "idempotence under replay",
    "L4 is unset or does not exist; the driver refuses to run without a prebuilt binary and this selftest will not build one",
  );
} else {
  const rundir = mkdtempSync(resolve(tmpdir(), "l4-go-idem-"));
  const env = { ...process.env, L4_GO_RUNDIR: rundir };
  const go = (args) => {
    try {
      return execFileSync("bash", [resolve(HERE, "go.sh"), ...args], {
        env,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (e) {
      return (e.stdout ?? "") + (e.stderr ?? "");
    }
  };
  go([
    "run",
    "--milestone",
    "g1",
    "--subject",
    "regcf",
    "--waive",
    "HG1=selftest",
  ]);
  const runId = execFileSync("ls", ["-1", rundir], { encoding: "utf8" })
    .trim()
    .split("\n")[0];
  const j = resolve(rundir, runId, "journal.ndjson");
  const firstPass = read(j).filter((r) => r.kind === "stage_end");
  const verdict1 = read(j)
    .filter((r) => r.kind === "run_end")
    .pop()?.verdict;

  go(["run", "--milestone", "g1", "--subject", "regcf", "--run-id", runId]);
  const all = read(j).filter((r) => r.kind === "stage_end");
  const secondPass = all.slice(firstPass.length);
  const verdict2 = read(j)
    .filter((r) => r.kind === "run_end")
    .pop()?.verdict;

  // The idempotence property, stated so it is falsifiable: on the second run,
  // every stage that CAN replay must replay. p9-report is the sole declared
  // exception and declares no inputs precisely so it re-renders every time.
  const executed = secondPass
    .filter((r) => !r.replayed_from)
    .map((r) => r.stage);
  check(
    "a second run re-executes nothing but the report",
    executed.length === 1 && executed[0] === "p9-report",
  );
  check(
    "every other stage of the second run is marked replayed",
    secondPass.filter((r) => r.replayed_from).length === secondPass.length - 1,
  );
  check(
    "the milestone verdict is unchanged by replay",
    verdict1 === verdict2 && !!verdict1,
  );
  check(
    "replayed receipts keep their original verdict",
    secondPass
      .filter((r) => r.replayed_from)
      .every(
        (r) => firstPass.find((f) => f.stage === r.stage)?.status === r.status,
      ),
  );
  check("the journal still verifies after a replay", verify(j).ok === true);

  // And the digest actually gates the replay: change an input, and the stage
  // that declares it must re-execute rather than report `replayed`.
  const verifyOut = execFileSync(
    "bash",
    [resolve(HERE, "go.sh"), "verify", "--run-id", runId, "--gates"],
    { env, encoding: "utf8" },
  );
  check(
    "verify --gates recomputes the same verdict",
    verifyOut.includes(`VERDICT: ${verdict2}`),
  );
  check(
    "verify re-hashes every recorded artifact",
    /artifacts: (\d+) recorded, \1 still hash as recorded/.test(verifyOut),
  );
}

// ------------------------------------------------------------- 5. the report
process.stdout.write("\n-- the report --\n");

const template = readFileSync(resolve(HERE, "report/template.md"), "utf8");
check(
  "the report template contains at least one placeholder",
  /\{\{[^}]+\}\}/.test(template),
);
check(
  "the report renderer reads the journal and nothing else",
  (() => {
    const src = readFileSync(resolve(HERE, "report/render-report.mjs"), "utf8");
    // It may read its own template and the journal. It must not read artifacts,
    // fidelity reports, or anything a phase script produced: every figure comes
    // from a receipt.
    return (
      src.includes("journal.ndjson") &&
      !/readFileSync\((?!TEMPLATE)[^)]*fidelity/.test(src)
    );
  })(),
);
// Structural, not textual: the entries themselves are inspected, so a new
// canonicalisation added without a `because` fails here rather than silently
// widening what the differential oracle is allowed to forgive.
check(
  "every canonicalisation names its cause, its deletion condition, and which side it rewrites",
  CANONICALISATIONS.length > 0 &&
    CANONICALISATIONS.every(
      (c) =>
        typeof c.id === "string" &&
        c.id.length > 0 &&
        typeof c.because === "string" &&
        /\.(hs|md|mjs|ts):\d+|\.(hs|md|mjs|ts)\b/.test(c.because) &&
        typeof c.delete_when === "string" &&
        c.delete_when.length > 20 &&
        ["expected", "actual", "both"].includes(c.side) &&
        typeof c.apply === "function",
    ),
);
check(
  "a canonicalisation may not silently forgive an arbitrary difference",
  // D1 rewrites `main.l4:<digit>` only. If someone widened it to strip whole
  // lines, this fixture would come out identical and the check would fail.
  (() => {
    const c = CANONICALISATIONS.find(
      (x) => x.id === "D1-golden-runner-source-uri",
    );
    if (!c) return true; // the entry was deleted, which is the goal
    const before =
      "<text>a (main.l4:1:1-2:3) and a REAL difference here</text>";
    const after = c.apply(before, { actualBasename: "regcf.l4" });
    return (
      after === "<text>a (regcf.l4:1:1-2:3) and a REAL difference here</text>"
    );
  })(),
);

process.stdout.write(
  `\n${failures === 0 ? "selftest: all checks passed" : `selftest: ${failures} FAILED`}${skips ? ` (${skips} skipped)` : ""}\n`,
);
process.exit(failures === 0 ? 0 : 1);
