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

import { execFileSync, spawnSync } from "node:child_process";
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
  "a milestone that declares NOTHING is INCOMPLETE, not vacuously COMPLETE",
  milestoneVerdict({ declared: [], receipts: [], gates: [] }).verdict ===
    "INCOMPLETE",
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
// ------------------------------------------------------- 3b. the gate payload
process.stdout.write("\n-- the gate payload --\n");

// The payload must be a function of CONTENT, not of how many times the run has
// been resumed. It used to render one line per stage_end INCLUDING replays, so
// the first resume — the one gate-request.sh itself prints — appended fresh
// rows, changed the payload, and made a valid signature stop verifying over a
// corpus nobody had touched. gate-verify.sh's `cmp -s` then refused before ever
// reaching `ssh-keygen -Y verify`.
{
  const d = mkdtempSync(resolve(tmpdir(), "l4-go-payload-"));
  const j = resolve(d, "journal.ndjson");
  append(j, {
    kind: "run_begin",
    run_id: "payload-test",
    milestone: "g1",
    subject: "regcf",
    repo_head: "abc",
    tree_state: "clean",
    fixed_now: "2025-01-31T00:00:00Z",
    declared_stages: ["p0-preflight", "p6-tests"],
  });
  const real = append(
    j,
    base({
      stage: "p0-preflight",
      metrics: { "corpus_sha_regcf.l4": "sha256:aaa" },
    }),
  );
  const payload = () =>
    execFileSync("node", [resolve(HERE, "lib/gate-payload.mjs"), "HG1", d], {
      encoding: "utf8",
    });
  const before = payload();
  append(
    j,
    base({
      stage: "p0-preflight",
      oracle: null,
      replayed_from: real.hash,
      metrics: { "corpus_sha_regcf.l4": "sha256:aaa" },
    }),
  );
  const after = payload();
  check(
    "a replayed receipt does not change the gate payload",
    before === after,
  );
  check(
    "the payload still lists the receipt that actually executed",
    before.includes(`p0-preflight PASS ${real.hash}`),
  );
  // And the control: a receipt that really executed DOES change it, so the
  // exclusion above is not just "ignore everything".
  append(j, base({ stage: "p6-tests" }));
  check(
    "a receipt that executed DOES change the gate payload",
    payload() !== before,
  );
}

// ------------------------------------------------- 3c. the gate-ordering check
process.stdout.write("\n-- gate ordering --\n");

// `go.sh verify --gates` is described in four places as the one check the
// acting agent cannot pre-satisfy. It inspected `stage_begin` only — a record
// go.sh writes strictly AFTER deciding the gate, so on a driver journal the
// check could never fire, and a phase script invoked directly (which the skill
// tells the reader to do) writes only a `stage_end` and was invisible to it.
{
  const d = mkdtempSync(resolve(tmpdir(), "l4-go-gateorder-"));
  const j = resolve(d, "journal.ndjson");
  append(j, {
    kind: "run_begin",
    run_id: "order-test",
    milestone: "g1",
    subject: "regcf",
    declared_stages: ["p6-tests"],
    gated_stages: JSON.stringify({ HG1: ["p6-tests"], HG2: ["p10-publish"] }),
  });
  // gated work performed OUTSIDE the driver: a stage_end and no stage_begin
  append(j, base({ stage: "p6-tests" }));
  append(j, {
    kind: "gate",
    gate: "HG1",
    state: "waived",
    corpus_digest: "sha256:aaa",
    reason: "after the fact",
  });
  const r = spawnSync(
    "node",
    [resolve(HERE, "lib/verify-run.mjs"), d, "--gates", "--json"],
    { encoding: "utf8" },
  );
  const out = JSON.parse(r.stdout);
  check(
    "a gated stage_end BEFORE its gate is a finding",
    out.findings.some((f) => f.kind === "gate-order"),
  );
  check("that finding makes verify exit non-zero", r.status === 1);
}
{
  // The negative control: the ordinary driver ordering must stay clean.
  const d = mkdtempSync(resolve(tmpdir(), "l4-go-gateorder-ok-"));
  const j = resolve(d, "journal.ndjson");
  append(j, {
    kind: "run_begin",
    run_id: "order-ok",
    milestone: "g1",
    subject: "regcf",
    declared_stages: ["p6-tests"],
    gated_stages: JSON.stringify({ HG1: ["p6-tests"] }),
  });
  append(j, {
    kind: "gate",
    gate: "HG1",
    state: "waived",
    corpus_digest: "sha256:aaa",
    reason: "first",
  });
  append(j, { kind: "stage_begin", stage: "p6-tests", attempt: 1 });
  append(j, base({ stage: "p6-tests" }));
  // A SECOND waiver row for the same gate, as a resume would write: it must not
  // retro-report the stages the first grant legitimately authorised.
  append(j, {
    kind: "gate",
    gate: "HG1",
    state: "waived",
    corpus_digest: "sha256:aaa",
    reason: "resumed",
  });
  const r = spawnSync(
    "node",
    [resolve(HERE, "lib/verify-run.mjs"), d, "--gates", "--json"],
    { encoding: "utf8" },
  );
  check(
    "a correctly ordered gate, and a duplicate grant, produce no ordering finding",
    !JSON.parse(r.stdout).findings.some((f) => f.kind === "gate-order"),
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

  // …and everything else the receipt carried. A replay is the LATEST row for
  // its stage, so render-report.mjs reads it: dropping these silently rewrote
  // the report on the first resume — every measured number gone, `PASS
  // (INTERIM)` promoted to a bare `PASS`, and the "claimed, not verified"
  // caveats deleted.
  const carried = (field) =>
    secondPass
      .filter((r) => r.replayed_from)
      .every((r) => {
        const f = firstPass.find((x) => x.stage === r.stage);
        return JSON.stringify(f?.[field] ?? null) === JSON.stringify(r[field]);
      });
  check("replayed receipts keep their metrics", carried("metrics"));
  check("replayed receipts keep their label", carried("label"));
  check("replayed receipts keep their notes", carried("notes"));

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

  // The negative control this file has promised since it was written, and did
  // not have: the digest must actually GATE the replay. The `l4` binary is an
  // input to every stage and is declared by none, so it is the input that went
  // unnoticed — a run resumed against a rebuilt or substituted binary replayed
  // every leg without invoking it once, skipping p0's CLI-surface pin and its
  // upgrade tripwire while the report still named the original binary.
  {
    const stub = resolve(rundir, "fake-l4");
    writeFileSync(stub, "#!/bin/sh\nexit 1\n", { mode: 0o755 });
    const before = read(j).filter((r) => r.kind === "stage_end").length;
    // p0-preflight will report BROKEN against a stub, and go.sh will exit 4;
    // that IS the point — the stage ran. The assertion is on the receipt.
    const r = spawnSync(
      "bash",
      [
        resolve(HERE, "go.sh"),
        "run",
        "--milestone",
        "g1",
        "--subject",
        "regcf",
        "--run-id",
        runId,
      ],
      { env: { ...env, L4: stub }, encoding: "utf8" },
    );
    const after = read(j)
      .filter((r2) => r2.kind === "stage_end")
      .slice(before);
    check(
      "a substituted l4 binary re-executes p0-preflight instead of replaying it",
      after.some((r2) => r2.stage === "p0-preflight" && !r2.replayed_from),
    );
    check(
      "…and the run does not report COMPLETE over it",
      r.status !== 0 && /VERDICT: (g1 )?BROKEN/.test(r.stdout + r.stderr),
    );
  }

  // HG2 is not waivable, and the rule lives in the driver rather than only in
  // prose. It guards anything outward-facing, and no agent decides that alone.
  {
    const r = spawnSync(
      "bash",
      [
        resolve(HERE, "go.sh"),
        "run",
        "--milestone",
        "g1",
        "--subject",
        "regcf",
        "--through",
        "p0-preflight",
        "--waive",
        "HG2=an agent decided on its own",
      ],
      { env, encoding: "utf8" },
    );
    check(
      "--waive HG2 is refused by the driver, not only by the skill",
      r.status === 2 && /--waive HG2 is REFUSED/.test(r.stderr),
    );
  }
}

// ------------------------------------------------------------- 5. the report
process.stdout.write("\n-- the report --\n");

const template = readFileSync(resolve(HERE, "report/template.md"), "utf8");
check(
  "the report refuses a journal with no run_begin",
  (() => {
    const d = mkdtempSync(resolve(tmpdir(), "l4-go-emptyjournal-"));
    writeFileSync(resolve(d, "journal.ndjson"), "");
    const r = spawnSync(
      "node",
      [resolve(HERE, "report/render-report.mjs"), d],
      { encoding: "utf8" },
    );
    return r.status === 4 && /no run_begin/.test(r.stderr);
  })(),
);
check(
  "the report template contains at least one placeholder",
  /\{\{[^}]+\}\}/.test(template),
);
check(
  "every figure in the report comes from the journal",
  (() => {
    const src = readFileSync(resolve(HERE, "report/render-report.mjs"), "utf8");
    // It may read its own template and the journal. It must not read artifacts,
    // fidelity reports, or anything a phase script produced: every figure comes
    // from a receipt. It DOES ask the filesystem whether the artifacts a
    // receipt names are still there — see artifactState — but takes no number
    // from them; the bytes and sha256 columns stay the recorded ones.
    return (
      src.includes("journal.ndjson") &&
      !/readFileSync\((?!TEMPLATE)[^)]*fidelity/.test(src)
    );
  })(),
);
check(
  "the artifacts table contradicts the journal when a recorded artifact is gone",
  (() => {
    const d = mkdtempSync(resolve(tmpdir(), "l4-go-gonereport-"));
    const j = resolve(d, "journal.ndjson");
    const missing = resolve(d, "never-written.dmn");
    append(j, {
      kind: "run_begin",
      run_id: "gone-test",
      milestone: "g1",
      subject: "regcf",
      declared_stages: ["p7-dmn"],
    });
    append(
      j,
      base({
        stage: "p7-dmn",
        artifacts: [
          { path: missing, bytes: 225141, sha256: "sha256:deadbeefdeadbeef" },
        ],
      }),
    );
    append(j, { kind: "run_end", verdict: "COMPLETE", exit: 0 });
    const r = spawnSync(
      "node",
      [resolve(HERE, "report/render-report.mjs"), d],
      { encoding: "utf8" },
    );
    if (r.status !== 0) return false;
    const md = readFileSync(resolve(d, "report.md"), "utf8");
    // The recorded figures still print — they are what the receipt said — but
    // the row must say the file is not there. Printing 225141 bytes and a
    // sha256 under "Every artifact this run put on disk", with nothing else, is
    // the defect this replaces.
    return /\*\*GONE\*\*/.test(md) && /no longer hash as recorded/.test(md);
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
