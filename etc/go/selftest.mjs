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
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  CROSS_RUN_INELIGIBLE,
  append,
  digestMembers,
  digestSet,
  findReplayableAcrossRuns,
  hashRecord,
  manifestText,
  read,
  refold,
  runSubject,
  sha256File as hashOf,
  sha256Text as hashText,
  verify,
} from "./lib/ledger.mjs";
import {
  classOf,
  comparability,
  freshness,
  independence,
  rolesFor,
} from "./lib/readset.mjs";
import * as Store from "./lib/store.mjs";
import {
  driftFor,
  lintNarrative,
  loadManifest,
  resolveCitations,
} from "./lib/narrative.mjs";
import {
  escapeAttr,
  lintMarkdown,
  mdToHtml,
  rawToken,
} from "./report/md-lite.mjs";
import {
  checkReceipt,
  runVerdict,
  ORACLE_CLASSES,
  STATUSES,
} from "./lib/verdict.mjs";
import { CANONICALISATIONS } from "./lib/canon-diff.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../..");

let failures = 0;
let skips = 0;
// `cond` is a value, but a thunk is accepted and CALLED. Most checks here are
// written `check(name, (() => { … })())` — an IIFE — and dropping the trailing
// `()` produces a function object, which is truthy, which is a check that can
// never fail. That happened: "surface-map.schema.json uses no keyword the
// validator ignores" shipped as `check(name, () => { … })` and passed
// vacuously. Resolving the thunk here closes the class rather than the one
// instance, because the next author will make the same typo.
const check = (name, cond) => {
  const value = typeof cond === "function" ? cond() : cond;
  process.stdout.write(`${value ? "ok  " : "FAIL"} ${name}\n`);
  if (!value) failures++;
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

// ------------------------------------------------------------- 0. the harness
// A selftest whose assertion helper cannot be red is decoration. Prove the
// thunk-resolving repair above before trusting anything below it.
process.stdout.write("\n-- the harness --\n");
{
  let called = false;
  const savedFailures = failures;
  const savedWrite = process.stdout.write.bind(process.stdout);
  process.stdout.write = () => true; // silence the deliberate FAIL line
  check("«harness probe»", () => {
    called = true;
    return false;
  });
  process.stdout.write = savedWrite;
  const wentRed = failures === savedFailures + 1;
  failures = savedFailures;
  check("check() calls a thunk rather than reading it as truthy", called);
  check("…and a thunk returning false makes it red", wentRed);
}

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

// ------------------------------------------------------------- 2. run verdict

process.stdout.write("\n-- cross-run replay --\n");

// Change 1: a receipt earned in an EARLIER run of the SAME subject satisfies a
// later run when the declared inputs digest is byte-identical. The digest folds
// in each stage's own script, the checkers it calls, and the `l4` binary's
// sha256, so this is what makes "tweak one exporter, re-run, and only that leg
// re-executes" true ACROSS sessions rather than only within one run.
{
  const root = mkdtempSync(resolve(tmpdir(), "l4-go-xrun-"));
  const mkRun = (id, subject, rows) => {
    const d = resolve(root, id);
    mkdirSync(d, { recursive: true });
    const j = resolve(d, "journal.ndjson");
    append(j, {
      kind: "run_begin",
      run_id: id,
      encoding: "primary",
      subject,
      repo_head: "abc",
      tree_state: "clean",
      fixed_now: "2025-01-31T00:00:00Z",
      declared_stages: ["p6-tests"],
    });
    for (const r of rows) append(j, r);
    return d;
  };
  const DIG = "sha256:" + "a".repeat(64);
  const OTHER = "sha256:" + "b".repeat(64);
  const row = (o) => ({
    kind: "stage_end",
    stage: "p6-tests",
    status: "PASS",
    reason: null,
    blocker: null,
    oracle: { class: "structural", because: "counted" },
    artifacts: [],
    metrics: {},
    notes: [],
    inputs_digest: DIG,
    attempt: 1,
    replayed_from: null,
    replayed_from_run: null,
    label: null,
    ...o,
  });

  const older = mkRun("2026-01-01-aaaaaaaa-001", "subj", [row({})]);
  const current = resolve(root, "2026-01-02-aaaaaaaa-001");
  mkdirSync(current, { recursive: true });

  const hit = findReplayableAcrossRuns(root, current, "subj", "p6-tests", DIG);
  check(
    "a receipt from an earlier run of the same subject is found, and names its run",
    !!hit &&
      hit.runId === "2026-01-01-aaaaaaaa-001" &&
      hit.record.status === "PASS",
  );

  check(
    "a DIFFERENT subject's receipt is never borrowed, however the digests fall",
    findReplayableAcrossRuns(
      root,
      current,
      "other-subject",
      "p6-tests",
      DIG,
    ) === null,
  );

  check(
    "a different inputs digest is not a hit — the digest is the whole authority",
    findReplayableAcrossRuns(root, current, "subj", "p6-tests", OTHER) === null,
  );

  check(
    "the CURRENT run is excluded; within-run replay is findReplayable's job",
    findReplayableAcrossRuns(root, older, "subj", "p6-tests", DIG) === null,
  );

  // A harness defect is not evidence, in any run.
  const brokenRoot = mkdtempSync(resolve(tmpdir(), "l4-go-xrun-broken-"));
  {
    const d = resolve(brokenRoot, "2026-01-01-bbbbbbbb-001");
    mkdirSync(d, { recursive: true });
    const j = resolve(d, "journal.ndjson");
    append(j, {
      kind: "run_begin",
      run_id: "2026-01-01-bbbbbbbb-001",
      encoding: "primary",
      subject: "subj",
      repo_head: "abc",
      tree_state: "clean",
      fixed_now: "2025-01-31T00:00:00Z",
      declared_stages: ["p6-tests"],
    });
    append(j, row({ status: "BROKEN", reason: "harness", oracle: null }));
    check(
      "a BROKEN receipt is never borrowed across runs",
      findReplayableAcrossRuns(
        brokenRoot,
        resolve(brokenRoot, "2026-01-02-bbbbbbbb-001"),
        "subj",
        "p6-tests",
        DIG,
      ) === null,
    );
  }

  check(
    "runSubject reads the subject off run_begin",
    runSubject(resolve(older, "journal.ndjson")) === "subj",
  );
  check(
    "runSubject returns null for a directory that is not a run",
    runSubject(resolve(root, "nope", "journal.ndjson")) === null,
  );
}

// The closed list of stages whose result is NOT a function of their declared
// inputs, and which therefore may never cross a run boundary.
{
  check(
    "p7-mcp is cross-run ineligible — its oracle talks to a live service",
    CROSS_RUN_INELIGIBLE.has("p7-mcp"),
  );
  check(
    "p2-sweep is cross-run ineligible — its whole subject is that time has passed",
    CROSS_RUN_INELIGIBLE.has("p2-sweep"),
  );
  const root = mkdtempSync(resolve(tmpdir(), "l4-go-xrun-inel-"));
  const d = resolve(root, "2026-01-01-cccccccc-001");
  mkdirSync(d, { recursive: true });
  const j = resolve(d, "journal.ndjson");
  const DIG = "sha256:" + "c".repeat(64);
  append(j, {
    kind: "run_begin",
    run_id: "2026-01-01-cccccccc-001",
    encoding: "primary",
    subject: "subj",
    repo_head: "abc",
    tree_state: "clean",
    fixed_now: "2025-01-31T00:00:00Z",
    declared_stages: ["p7-mcp"],
  });
  append(j, {
    kind: "stage_end",
    stage: "p7-mcp",
    status: "PASS",
    reason: null,
    blocker: null,
    oracle: { class: "execution", because: "deployed" },
    artifacts: [],
    metrics: {},
    notes: [],
    inputs_digest: DIG,
    attempt: 1,
    replayed_from: null,
    replayed_from_run: null,
    label: null,
  });
  check(
    "an ineligible stage is NOT borrowed even with a byte-identical digest",
    findReplayableAcrossRuns(
      root,
      resolve(root, "2026-01-02-cccccccc-001"),
      "subj",
      "p7-mcp",
      DIG,
    ) === null,
  );
}

process.stdout.write("\n-- the run rule --\n");

const declared = ["a", "b", "c"];
const ok = [
  base({ stage: "a" }),
  base({ stage: "b", status: "DEGRADED", oracle: null, reason: "why" }),
  base({ stage: "c", status: "SKIPPED", oracle: null, reason: "no tool" }),
];
check(
  "a run of PASS + DEGRADED + SKIPPED is COMPLETE",
  runVerdict({ declared, receipts: ok, gates: [] }).verdict === "COMPLETE",
);
check(
  "a run with a BROKEN receipt is NOT COMPLETE",
  runVerdict({
    declared,
    receipts: [
      ...ok.slice(0, 2),
      base({ stage: "c", status: "BROKEN", oracle: null, reason: "harness" }),
    ],
    gates: [],
  }).verdict === "BROKEN",
);
check(
  "a run missing a declared stage is INCOMPLETE",
  runVerdict({ declared, receipts: ok.slice(0, 2), gates: [] }).verdict ===
    "INCOMPLETE",
);
check(
  "a run with an unexplained non-PASS is INCOMPLETE",
  runVerdict({
    declared,
    receipts: [
      ...ok.slice(0, 2),
      { stage: "c", status: "DEGRADED", reason: "" },
    ],
    gates: [],
  }).verdict === "INCOMPLETE",
);
check(
  "a refused gate makes the run GATE",
  runVerdict({
    declared,
    receipts: ok,
    gates: [{ gate: "HG1", state: "refused" }],
  }).verdict === "GATE",
);
check(
  "a WAIVED gate does not block the run",
  runVerdict({
    declared,
    receipts: ok,
    gates: [{ gate: "HG1", state: "waived", reason: "why" }],
  }).verdict === "COMPLETE",
);
check(
  "a run that declares NOTHING is INCOMPLETE, not vacuously COMPLETE",
  runVerdict({ declared: [], receipts: [], gates: [] }).verdict ===
    "INCOMPLETE",
);
check(
  "BROKEN outranks GATE",
  runVerdict({
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
  encoding: "primary",
  subject: "t",
  declared_stages: ["a"],
});
append(journal, base({ stage: "a" }));
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
    encoding: "primary",
    subject: "fixture-subject",
    repo_head: "abc",
    tree_state: "clean",
    fixed_now: "2025-01-31T00:00:00Z",
    declared_stages: ["p0-preflight", "p6-tests"],
  });
  const real = append(
    j,
    base({
      stage: "p0-preflight",
      metrics: { "corpus_sha_fixture.l4": "sha256:aaa" },
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
      metrics: { "corpus_sha_fixture.l4": "sha256:aaa" },
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

  // A RE-EXECUTED p0-preflight restates the corpus; it does not add a second
  // corpus. The receipts list below is an audit trail and names every
  // execution, but the corpus section is a statement about the corpus and there
  // is only one. Taking the union rendered a module twice — pre-edit digest and
  // post-edit digest, nothing saying which was current — in the one document
  // that has to be unambiguous. Rare while p0-preflight re-executed only on an
  // edit to the entry module; routine since every module became one of its
  // declared inputs.
  append(
    j,
    base({
      stage: "p0-preflight",
      metrics: { "corpus_sha_fixture.l4": "sha256:bbb" },
    }),
  );
  const reexecuted = payload();
  const corpusOf = (p) =>
    p
      .split("corpus (sha256 of every file this gate blesses):\n")[1]
      .split("\n\n")[0]
      .split("\n")
      .filter(Boolean);
  check(
    "a re-executed p0-preflight RESTATES the corpus rather than appending a second one",
    corpusOf(reexecuted).length === 1,
  );
  check(
    "…and what it states is the CURRENT digest, not the one it superseded",
    corpusOf(reexecuted)[0].includes("sha256:bbb"),
  );
  check(
    "…while the payload still changes, so a signature over the superseded corpus stops verifying",
    reexecuted !== before,
  );
  check(
    "…and the receipts list keeps naming every execution, both rows",
    reexecuted.split("p0-preflight PASS ").length - 1 === 2,
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
    encoding: "primary",
    subject: "fixture-subject",
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
    encoding: "primary",
    subject: "fixture-subject",
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

// ------------------------------------------------- 3d. the subject resolver
process.stdout.write("\n-- the subject resolver --\n");

// The fixture subject is whatever sidecars actually exist — read through the
// resolver's own --list, never a hardcoded id, so this file stays green when a
// second subject lands.
const SUBJECTS = execFileSync(
  "node",
  [resolve(HERE, "lib/subject.mjs"), "--list"],
  { encoding: "utf8" },
)
  .trim()
  .split("\n")
  .filter(Boolean);
check("at least one subject sidecar exists", SUBJECTS.length >= 1);
const FIXTURE_SUBJECT = SUBJECTS[0];
// The additional encoding this subject declares, if any. DERIVED, never
// hardcoded: R9 replaced "the second pass" with a NAMED id, and a test that
// spelled the name out would go quietly wrong the day a sidecar renames it —
// which is the whole failure mode an id exists to prevent. `undeclared` is the
// third case, and is what a subject that has declared none resolves to.
const FIXTURE_ENCODING =
  execFileSync(
    "node",
    [resolve(HERE, "lib/subject.mjs"), FIXTURE_SUBJECT, "--encodings"],
    { encoding: "utf8" },
  )
    .trim()
    .split("\n")
    .filter(Boolean)[0] ?? "undeclared";

{
  // Every declared sidecar must resolve cleanly.
  for (const s of SUBJECTS) {
    const r = spawnSync("node", [resolve(HERE, "lib/subject.mjs"), s], {
      encoding: "utf8",
    });
    check(
      `sidecar '${s}' resolves and exports GO_S_* lines`,
      r.status === 0 && /^GO_S_ID='/m.test(r.stdout),
    );
  }
}
{
  // An unknown subject is refused with the available list and the recipe.
  const r = spawnSync(
    "node",
    [resolve(HERE, "lib/subject.mjs"), "no-such-subject"],
    { encoding: "utf8" },
  );
  check(
    "an unknown subject exits 2 and lists the available sidecars",
    r.status === 2 &&
      /Available subject\(s\)/.test(r.stderr) &&
      SUBJECTS.every((s) => r.stderr.includes(s)) &&
      /To add one/.test(r.stderr),
  );
}
{
  // A descriptor naming a nonexistent golden is refused, naming the path.
  const d = mkdtempSync(resolve(tmpdir(), "l4-go-badsubject-"));
  const bad = resolve(d, "bad");
  mkdirSync(bad);
  const desc = JSON.parse(
    readFileSync(
      resolve(HERE, "subjects", FIXTURE_SUBJECT, "subject.json"),
      "utf8",
    ),
  );
  desc.id = "bad";
  desc.legs["p7-dmn"].golden = "jl4/does/not/exist.dmn";
  writeFileSync(resolve(bad, "subject.json"), JSON.stringify(desc));
  const r = spawnSync("node", [resolve(HERE, "lib/subject.mjs"), "bad"], {
    encoding: "utf8",
    env: { ...process.env, L4_GO_SUBJECTS_DIR: d },
  });
  check(
    "a descriptor naming a nonexistent golden is refused (exit 2, path named)",
    r.status === 2 && r.stderr.includes("jl4/does/not/exist.dmn"),
  );
  // And the control: an unknown KEY is refused too, so validation is
  // refuse-by-default rather than existence-only.
  const desc2 = JSON.parse(
    readFileSync(
      resolve(HERE, "subjects", FIXTURE_SUBJECT, "subject.json"),
      "utf8",
    ),
  );
  desc2.id = "bad";
  desc2.surprise_key = true;
  writeFileSync(resolve(bad, "subject.json"), JSON.stringify(desc2));
  const r2 = spawnSync("node", [resolve(HERE, "lib/subject.mjs"), "bad"], {
    encoding: "utf8",
    env: { ...process.env, L4_GO_SUBJECTS_DIR: d },
  });
  check(
    "a descriptor with an unknown key is refused",
    r2.status === 2 && /unknown key 'surprise_key'/.test(r2.stderr),
  );
}
{
  // ---- corpus.modules: an encoding of MORE THAN TWO modules (2026-08-18) ----
  //
  // A subject's encoding is not always one file plus a wizard: Singapore
  // succession law is a shared ontology module, three statute modules and a
  // wizard. `corpus.modules` declares the whole set; omitting it still means
  // exactly what it always meant.
  //
  // Every refusal below has a positive sibling, because the schema's value is
  // that it is CLOSED — and because two of them guard silent failures rather
  // than loud ones. A set that omitted `corpus.main`, or a de novo module
  // colliding with a module that is neither main nor the wizard, would produce
  // no error at all under the pre-2026-08-18 checks: the first would drop the
  // entry module out of the gate digest, and the second would make SPEC.md §8's
  // acceptance diff a partial identity.
  const REPO_ROOT = resolve(HERE, "../..");
  const d = mkdtempSync(resolve(tmpdir(), "l4-go-corpusmodules-"));
  const M = resolve(d, "modules");
  mkdirSync(M, { recursive: true });
  const mod = (n) => {
    const p = resolve(M, n);
    writeFileSync(p, `-- selftest stand-in module ${n}\n`);
    return p;
  };
  const ONTOLOGY = mod("ontology.l4");
  const WILLS = mod("wills.l4");
  const INTESTATE = mod("intestate.l4");

  // Each case is the FIXTURE subject's own descriptor with `corpus` mutated, so
  // what is exercised is the corpus schema and nothing else; pins.json and
  // known-defects.json are required by the resolver and copied verbatim.
  const cm = resolve(d, "cm");
  mkdirSync(cm, { recursive: true });
  for (const f of ["pins.json", "known-defects.json"])
    writeFileSync(
      resolve(cm, f),
      readFileSync(resolve(HERE, "subjects", FIXTURE_SUBJECT, f)),
    );
  const withCorpus = (mutate) => {
    const desc = JSON.parse(
      readFileSync(
        resolve(HERE, "subjects", FIXTURE_SUBJECT, "subject.json"),
        "utf8",
      ),
    );
    desc.id = "cm";
    mutate(desc);
    writeFileSync(resolve(cm, "subject.json"), JSON.stringify(desc));
    return spawnSync("node", [resolve(HERE, "lib/subject.mjs"), "cm"], {
      encoding: "utf8",
      env: { ...process.env, L4_GO_SUBJECTS_DIR: d },
    });
  };
  const fixtureDesc = JSON.parse(
    readFileSync(
      resolve(HERE, "subjects", FIXTURE_SUBJECT, "subject.json"),
      "utf8",
    ),
  );
  const MAIN = resolve(REPO_ROOT, fixtureDesc.encoding.main);
  const WIZARD = fixtureDesc.encoding.wizard
    ? resolve(REPO_ROOT, fixtureDesc.encoding.wizard)
    : "";
  const FIVE = (desc) => {
    desc.encoding.modules = [
      ONTOLOGY,
      desc.encoding.main,
      WILLS,
      INTESTATE,
      desc.encoding.wizard,
    ];
  };

  {
    const r = withCorpus(FIVE);
    check(
      "corpus.modules resolves EVERY declared module into GO_S_ENCODING_MODULES, in declared (dependency) order",
      r.status === 0 &&
        r.stdout.includes(
          `GO_S_ENCODING_MODULES='${ONTOLOGY} ${MAIN} ${WILLS} ${INTESTATE} ${WIZARD}'`,
        ),
    );
    // The two old names are ROLE POINTERS into the set, not a second encoding
    // of it: every single-module leg still reads them, so widening the schema
    // must not have moved them.
    check(
      "GO_S_ENCODING and GO_S_WIZARD still name the entry module and the wizard, unchanged",
      r.status === 0 &&
        r.stdout.includes(`GO_S_ENCODING='${MAIN}'`) &&
        r.stdout.includes(`GO_S_WIZARD='${WIZARD}'`),
    );
  }
  {
    const r = withCorpus((desc) => {
      desc.encoding.modules = [
        ONTOLOGY,
        WILLS,
        INTESTATE,
        desc.encoding.wizard,
      ];
    });
    check(
      "a corpus.modules set that omits corpus.main is refused, naming the entry module",
      r.status === 2 &&
        /does not contain corpus\.main/.test(r.stderr) &&
        r.stderr.includes(MAIN),
    );
  }
  {
    const r = withCorpus((desc) => {
      desc.encoding.modules = [desc.encoding.main, ONTOLOGY];
    });
    check(
      "a declared corpus.wizard that is not a member of corpus.modules is refused — it would fall outside the gate digest",
      r.status === 2 &&
        /does not contain corpus\.wizard/.test(r.stderr) &&
        r.stderr.includes(WIZARD),
    );
  }
  {
    const r = withCorpus((desc) => {
      desc.encoding.modules = [
        desc.encoding.main,
        desc.encoding.wizard,
        "jl4/examples/legal/no-such-statute.l4",
      ];
    });
    check(
      "a corpus module that does not exist is refused, naming the path (unlike a denovo module, a corpus module is committed)",
      r.status === 2 &&
        r.stderr.includes("jl4/examples/legal/no-such-statute.l4"),
    );
  }
  {
    const r = withCorpus((desc) => {
      desc.encoding.modules = [
        ONTOLOGY,
        desc.encoding.main,
        desc.encoding.wizard,
        ONTOLOGY,
      ];
    });
    check(
      "a duplicated corpus module is refused — the set is also the digest's file list and the list the measurement stages iterate",
      r.status === 2 &&
        /duplicates/.test(r.stderr) &&
        r.stderr.includes(ONTOLOGY),
    );
  }
  {
    const r = withCorpus((desc) => {
      desc.encoding.modules = [
        desc.encoding.main,
        desc.encoding.wizard,
        "jl4/examples/legal/two words.l4",
      ];
    });
    check(
      "a corpus module path containing whitespace is refused — GO_S_ENCODING_MODULES is space-separated",
      r.status === 2 && /may not contain whitespace/.test(r.stderr),
    );
  }
  {
    const r = withCorpus((desc) => {
      desc.encoding.modules = [];
    });
    check(
      "an empty corpus.modules array is refused rather than read as 'no modules'",
      r.status === 2 && /must be a non-empty array/.test(r.stderr),
    );
  }
  {
    const r = withCorpus(() => {});
    check(
      "a descriptor with NO corpus.modules resolves to exactly main + wizard, as before the key existed",
      r.status === 0 &&
        r.stdout.includes(`GO_S_ENCODING_MODULES='${MAIN} ${WIZARD}'`),
    );
  }
  {
    // SPEC.md §8's identity guard, at the new arity. This is the regression the
    // widened schema could have introduced in silence: the old check named
    // encodingMain and encodingWizard, so a de novo module colliding with the third
    // or fourth corpus module would have been waved through and the acceptance
    // diff would have been a partial identity with no error anywhere.
    const r = withCorpus((desc) => {
      FIVE(desc);
      desc.encodings = { "cleanroom-a": { modules: [WILLS] } };
    });
    check(
      "an additional encoding's module colliding with a committed module that is NEITHER main NOR the wizard is refused",
      r.status === 2 && /also a committed encoding module/.test(r.stderr),
    );
  }
  {
    // BEHAVIOURAL, for the same reason the narrative-deposit check above is:
    // a source-text assertion about go.sh would pass over a GO_ENCODING_FILES
    // array that was built and then overwritten. So the driver is ASKED, via
    // `plan`, for the digest it would bind a gate to.
    withCorpus(FIVE);
    const planOf = () =>
      spawnSync(
        "bash",
        [
          resolve(HERE, "go.sh"),
          "plan",
          "--encoding",
          "primary",
          "--subject",
          "cm",
        ],
        { encoding: "utf8", env: { ...process.env, L4_GO_SUBJECTS_DIR: d } },
      );
    const before = planOf();
    check(
      "the primary gate digest covers every declared corpus module, not just the entry module",
      before.status === 0 &&
        [ONTOLOGY, MAIN, WILLS, INTESTATE, WIZARD].every((m) =>
          before.stdout.includes(m.replace(`${REPO_ROOT}/`, "")),
        ),
    );
    check(
      "the digest a gate binds to moves when a NON-entry corpus module is edited",
      (() => {
        const sha = (p) => /sha256:[0-9a-f]{64}/.exec(p.stdout)?.[0] ?? null;
        const b = sha(before);
        if (!b) return false;
        writeFileSync(INTESTATE, "-- edited by the selftest\n");
        const after = sha(planOf());
        return !!after && after !== b;
      })(),
    );
  }
}
{
  // ---- the HG1 payload's corpus section covers EVERY module (2026-08-18) ----
  //
  // The gate digest moving (checked just above) is only half of a gate. The
  // other half is the document a human READS AND SIGNS, and it is built from a
  // different source: gate-payload.mjs renders p0-preflight's `corpus_sha_*`
  // metrics and nothing else. So a module set can be digested correctly and
  // still be signed blind — which is what happened. p0-preflight recorded two
  // metrics (main, wizard) because for a one-module-plus-wizard encoding that
  // WAS the set; under `corpus.modules` it left modules 3..N out of the signed
  // document in every run state, so no honest re-run could produce a payload
  // that committed to them and the reviewer was never shown them at all.
  //
  // Measured here at the seam, end to end — corpus-metrics -> receipt ->
  // payload — because each of the three steps can drop a module on its own.
  const d = mkdtempSync(resolve(tmpdir(), "l4-go-corpusmetrics-"));
  const CM = resolve(HERE, "lib/corpus-metrics.mjs");
  const mods = resolve(d, "mods");
  // Two modules that SHARE A BASENAME in different directories: the shape
  // `corpus.modules` makes ordinary, and the shape the old basename key
  // collapsed. receipt.mjs's metricsFrom is last-wins, so a shared key does not
  // fail — it silently keeps one of the two.
  for (const sub of ["wills", "intestate"])
    mkdirSync(resolve(mods, sub), { recursive: true });
  const A = resolve(mods, "wills/rules.l4");
  const B = resolve(mods, "intestate/rules.l4");
  const C = resolve(mods, "ontology.l4");
  writeFileSync(A, "-- wills\n");
  writeFileSync(B, "-- intestate\n");
  writeFileSync(C, "-- ontology\n");

  const r = spawnSync("node", [CM, C, A, B], { encoding: "utf8" });
  const lines = r.stdout.trim().split("\n").filter(Boolean);
  check(
    "corpus-metrics.mjs emits one corpus_sha metric per module, in the order given",
    r.status === 0 &&
      lines.length === 3 &&
      lines.every((l) => /^corpus_sha_\S+=sha256:[0-9a-f]{64}$/.test(l)),
  );
  check(
    "two modules sharing a basename in different directories get DISTINCT keys",
    new Set(lines.map((l) => l.slice(0, l.indexOf("=")))).size === 3,
  );
  {
    const r2 = spawnSync("node", [CM, resolve(d, "no-such-module.l4")], {
      encoding: "utf8",
    });
    check(
      "a corpus module that is not on disk is refused, naming the path — a missing one is a misconfiguration, not a status",
      r2.status === 2 && r2.stderr.includes("no-such-module.l4"),
    );
  }
  {
    const r3 = spawnSync("node", [CM], { encoding: "utf8" });
    check(
      "corpus-metrics.mjs with NO modules is refused rather than emitting an empty corpus section",
      r3.status === 2 && /empty set|no module paths/.test(r3.stderr),
    );
  }
  {
    // The round trip. This is the check that would have caught the defect: it
    // asks the payload itself, through the only writer of the journal.
    const run = resolve(d, "run");
    mkdirSync(run, { recursive: true });
    const receipt = resolve(HERE, "lib/receipt.mjs");
    execFileSync("node", [
      receipt,
      "run-begin",
      "--run",
      run,
      "--run-id",
      "corpus-metrics-test",
      "--encoding",
      "primary",
      "--subject",
      "cm",
      "--declared",
      "p0-preflight",
    ]);
    execFileSync("node", [
      receipt,
      "stage-end",
      "--run",
      run,
      "--stage",
      "p0-preflight",
      "--status",
      "PASS",
      "--oracle-cmd",
      "(selftest stand-in for the CLI-surface check)",
      "--oracle-exit",
      "0",
      "--oracle-class",
      "structural",
      "--artifact",
      C,
      ...lines.flatMap((l) => ["--metric", l]),
    ]);
    const payload = execFileSync(
      "node",
      [resolve(HERE, "lib/gate-payload.mjs"), "HG1", run],
      { encoding: "utf8" },
    );
    const corpusLines = payload
      .split("corpus (sha256 of every file this gate blesses):\n")[1]
      .split("\n\n")[0]
      .split("\n")
      .filter(Boolean);
    check(
      "every module survives receipt.mjs into the payload's corpus section — none collapses",
      corpusLines.length === 3,
    );
    check(
      "the payload names each module by a path the reviewer can open, not by a bare basename",
      [A, B, C].every((m) =>
        corpusLines.some((l) => l.trim().startsWith(`${m} `)),
      ),
    );
    check(
      "editing a module the reviewer signed for changes the metric, and so the payload",
      (() => {
        writeFileSync(B, "-- intestate, edited\n");
        const after = spawnSync("node", [CM, C, A, B], { encoding: "utf8" });
        return after.status === 0 && after.stdout !== r.stdout;
      })(),
    );
  }
}

// ---- the signable document must NAME what it blesses (2026-08-20) ---------
//
// The block above proves every module reaches the payload WHEN p0-preflight
// executed. It has no control for the two states in which p0-preflight did not,
// and both were live in this tree:
//
//   * cross-run replay. The corpus section was selected out of the
//     replay-FILTERED receipts list, so a run that borrowed p0-preflight from an
//     earlier run rendered "(none recorded — p0-preflight has not run)" while
//     its own p0 row carried all seven corpus_sha_ metrics. MEASURED on run
//     2026-08-19-951d08d8-004, the run that validated cross-run replay itself.
//
//   * every g2 run, in every state, because p0-preflight is not a declared g2
//     stage at all.
//
// In both, a human would have signed a document naming no corpus file while the
// journal's corpus_digest carried the real binding they were never shown. The
// replay exclusion is right for the receipts list, which attests WORK, and wrong
// for the corpus section, which states what the corpus IS — a replayed row
// restates that faithfully.
process.stdout.write("\n-- the signable document --\n");
{
  const root = mkdtempSync(resolve(tmpdir(), "l4-go-payload-"));
  const GP = resolve(HERE, "lib/gate-payload.mjs");

  const mkRun = (id, encoding, p0Row) => {
    const d = resolve(root, id);
    mkdirSync(d, { recursive: true });
    const j = resolve(d, "journal.ndjson");
    append(j, {
      kind: "run_begin",
      run_id: id,
      encoding,
      subject: "subj",
      repo_head: "abc",
      tree_state: "clean",
      fixed_now: "2025-01-31T00:00:00Z",
      declared_stages: p0Row ? ["p0-preflight"] : ["p3-check"],
    });
    if (p0Row) append(j, p0Row);
    return d;
  };
  const p0 = (extra) => ({
    kind: "stage_end",
    stage: "p0-preflight",
    status: "PASS",
    reason: null,
    blocker: null,
    oracle: { class: "structural", because: "counted" },
    artifacts: [],
    metrics: {
      "corpus_sha_a.l4": "sha256:" + "a".repeat(64),
      "corpus_sha_b.l4": "sha256:" + "b".repeat(64),
    },
    notes: [],
    ...extra,
  });
  const render = (dir) =>
    spawnSync("node", [GP, "HG1", dir], { encoding: "utf8" });
  const corpusOf = (out) =>
    (out.split("corpus (sha256 of every file this gate blesses):\n")[1] ?? "")
      .split("\n\n")[0]
      .split("\n")
      .filter(Boolean);

  const executed = render(mkRun("2026-01-01-aaaaaaaa-001", "primary", p0({})));
  check(
    "a payload over an EXECUTED p0-preflight renders",
    executed.status === 0,
  );
  check("it names both modules", corpusOf(executed.stdout).length === 2);

  // The regression proper.
  const replayed = render(
    mkRun(
      "2026-01-02-aaaaaaaa-001",
      "g1",
      p0({
        replayed_from: "sha256:" + "c".repeat(64),
        replayed_from_run: "2026-01-01-aaaaaaaa-001",
      }),
    ),
  );
  check(
    "a payload over a REPLAYED p0-preflight still renders",
    replayed.status === 0,
  );
  check(
    "a replayed p0-preflight states the corpus just as an executed one does",
    corpusOf(replayed.stdout).length === 2,
  );
  check(
    "the two payloads agree on the corpus section — same corpus, same statement",
    corpusOf(replayed.stdout).join("\n") ===
      corpusOf(executed.stdout).join("\n"),
  );

  // And the refusals: a document that names nothing must not be signable.
  const blindG1 = render(mkRun("2026-01-03-aaaaaaaa-001", "primary", null));
  check(
    "a primary payload with no p0-preflight at all REFUSES",
    blindG1.status === 2,
  );
  check(
    "the primary refusal names p0-preflight as the stage to run",
    /p0-preflight/.test(blindG1.stderr),
  );
  check(
    "the refusal never emits a signable document",
    !/l4-go gate payload/.test(blindG1.stdout),
  );

  const blindG2 = render(mkRun("2026-01-04-aaaaaaaa-001", "cleanroom-a", null));
  check(
    "a deposit payload REFUSES — p0-preflight is not a deposit stage",
    blindG2.status === 2,
  );

  // The REALISTIC g2 case, and the one the check above is too weak to pin: a
  // fully populated journal with every declared stage green. An empty journal
  // would refuse under a much weaker rule ("no stages, no payload"); a g2 run
  // that did everything asked of it and still cannot describe what it blesses
  // is the actual property, because p0-preflight is not in DEPOSIT_STAGES at all.
  {
    const d = resolve(root, "2026-01-05-aaaaaaaa-001");
    mkdirSync(d, { recursive: true });
    const j = resolve(d, "journal.ndjson");
    const g2Stages = [
      "p1-ingest",
      "p2-sweep",
      "p3-encode",
      "p3-check",
      "p4-forks",
      "p5-gate",
      "p6-tests",
      "p7-dmn",
      "p8-verify",
      "p8-diff",
      "p9-report",
    ];
    append(j, {
      kind: "run_begin",
      run_id: "2026-01-05-aaaaaaaa-001",
      encoding: "cleanroom-a",
      subject: "subj",
      repo_head: "abc",
      tree_state: "clean",
      fixed_now: "2025-01-31T00:00:00Z",
      declared_stages: g2Stages,
    });
    for (const stage of g2Stages)
      append(j, {
        kind: "stage_end",
        stage,
        status: "PASS",
        reason: null,
        blocker: null,
        oracle: { class: "structural", because: "counted" },
        artifacts: [],
        metrics: { some_number: 1 },
        notes: [],
      });
    const fullG2 = render(d);
    check(
      "a FULLY GREEN deposit run still refuses — every stage passed and none states the corpus",
      fullG2.status === 2,
    );
    check(
      "and it says so without claiming the run failed",
      /not among this run's declared stages/.test(fullG2.stderr),
    );
  }

  // WHERE the corpus section comes from is itself a property. It is built from
  // p0-preflight's `corpus_sha_*` METRICS — a measurement a stage recorded
  // after reading the files — and gate-payload.mjs calls that "a CONTRACT, not
  // an implementation detail". The tempting future edit is to source it from a
  // driver-written record instead, which is cheaper, always available, and
  // silently downgrades the signed document's evidence from "a stage measured
  // this" to "the driver asserted this" — and would delete the g2 refusal as a
  // side effect, because a driver record exists at g2 and the section is then
  // never empty.
  check(
    "the corpus section is derived from a stage receipt's metrics, not a driver record",
    /corpus_sha_/.test(readFileSync(GP, "utf8")) &&
      /stage_end/.test(readFileSync(GP, "utf8")),
  );
  check(
    "the deposit refusal explains why the deposit path differs, and names the waiver as the honest alternative",
    /not among this run's declared stages/.test(blindG2.stderr) &&
      /[Ww]aive/.test(blindG2.stderr),
  );

  // R9 REGRESSION, PINNED. The arm used to be chosen by `begin.milestone ===
  // "g2"`, and journal schema 5 stopped writing that field — so a deposit run
  // fell through to the OTHER arm, which still refused (the same exit code, the
  // same absence of a payload) while telling the reader to "run p0-preflight in
  // this run". p0-preflight is not in DEPOSIT_STAGES and `--only p0-preflight`
  // intersects to nothing, so the advice could not be followed: a silent
  // downgrade from a correct refusal to an impossible instruction. The arm is
  // now chosen by the DECLARED STAGE LIST, which every schema from 2 onward
  // records, so both spellings resolve to the same, correct advice.
  {
    const armFor = (beginExtra, stages) => {
      const d = mkdtempSync(resolve(tmpdir(), "l4-go-gatearm-"));
      append(resolve(d, "journal.ndjson"), {
        kind: "run_begin",
        run_id: "2026-01-05-aaaaaaaa-001",
        subject: "subj",
        repo_head: "abc",
        tree_state: "clean",
        fixed_now: "2025-01-31T00:00:00Z",
        declared_stages: stages,
        ...beginExtra,
      });
      return render(d).stderr;
    };
    const DEPOSIT = ["p1-ingest", "p6-tests", "p8-diff", "p9-report"];
    const PRIMARY = ["p0-preflight", "p3-check", "p6-tests", "p9-report"];
    const deposit = /not among this run's declared stages/;
    const primary = /Run p0-preflight in this run/;
    check(
      "the refusal arm is chosen by the declared stages, so a schema-5 deposit run gets deposit advice",
      deposit.test(armFor({ encoding: "cleanroom-a" }, DEPOSIT)),
    );
    check(
      "…and a legacy row carrying `milestone` instead of `encoding` resolves to the SAME arm",
      deposit.test(armFor({ milestone: "g2" }, DEPOSIT)),
    );
    check(
      "…while a run that DOES declare p0-preflight is told to run it, which it can",
      primary.test(armFor({ encoding: "primary" }, PRIMARY)),
    );
  }

  // The old behaviour, pinned so it cannot come back: the parenthetical must
  // never be PUSHED into the document again. (The string still appears in
  // gate-payload.mjs's prose, explaining what was removed and why, so the check
  // has to look for the emission rather than the mention.)
  check(
    "no payload path pushes the '(none recorded)' parenthetical into the document",
    !/lines\.push\([^)]*none recorded/.test(readFileSync(GP, "utf8")),
  );
}

// ------------------------------------------- 3e. the deposit-contract schemas
process.stdout.write("\n-- the register schemas --\n");

// The three registers P1/P2/P4 write into carry no oracle of their own: nothing
// runs them, so nothing else would notice a schema that had quietly stopped
// refusing. These checks prove the validator can still be red — every valid
// fixture passes, every invalid one is refused NAMING the rule, cross-file
// joins actually fire, and the enforcement contract (a schema this validator
// cannot fully enforce is a hard error, not a partial pass) holds in both
// directions.
{
  const RV = resolve(HERE, "lib/register-validate.mjs");
  const SCHEMAS = resolve(
    HERE,
    "../../specs/todo/single-instruction-demo/schemas",
  );
  const fx = (n) => resolve(SCHEMAS, "fixtures", n);
  const rv = (args, env = {}) =>
    spawnSync("node", [RV, ...args], {
      encoding: "utf8",
      env: { ...process.env, ...env },
    });
  const NAMES = ["fork-register", "external-modifications", "source-bundle"];

  // 1. The trio validates clean, each seeing the other two.
  const trio = [
    fx("fork-register.valid.json"),
    fx("external-modifications.valid.json"),
    fx("source-bundle.valid.json"),
  ];
  for (const name of NAMES) {
    const primary = trio.find((p) => p.endsWith(`${name}.valid.json`));
    const r = rv([name, primary, ...trio.filter((p) => p !== primary)]);
    check(
      `the valid ${name} fixture passes with both peers`,
      r.status === 0 && /register-validate: ok/.test(r.stdout),
    );
  }

  // 2. Each invalid fixture is refused, and the message names the rule and the
  //    path. A validator that exited 1 without saying which key is at fault
  //    would send a reader back to the schema to guess.
  const expected = {
    "fork-register": [
      "entry-ids-unique",
      "taken-names-a-live-reading",
      "at-least-one-live-reading",
      "materialisation-implies-field",
      "materialisation-implies-mechanism",
      "interpretation-fields-unique",
      "non-live-readings-explain",
      "live-readings-cite-their-licence",
      "arguable-readings-cite-and-foreclose",
      "settled-or-demoted-requires-authority",
      "demoted-requires-a-demoted-reading",
      "quote-or-absent-reason",
      "materialised-forks-declare-divergence",
      "observable-divergence-requires-witnesses",
      "witnesses-only-when-observable",
    ],
    "external-modifications": [
      "entry-ids-unique",
      "search-ids-unique",
      "search-outcome-matches-findings",
      "search-findings-resolve",
      "findings-attributed-to-a-search",
      "binding-effect-declared",
      "suppressive-effects-need-a-rule-version-arm",
      "binding-routes-into-the-encoding",
      "interpretive-routes-to-a-fork",
      "url-or-absent-reason",
      "effective-from-exclusive",
      "disposition-entry-resolves",
      "markers-disposed-once",
    ],
    "source-bundle": [
      "document-ids-unique",
      "archive-method-requires-archive-url",
      "integrity-digest-or-immutable-capture",
      "assembled-digest-matches",
      "covers-or-absent-reason",
      "covers-range-ordered",
      "in-force-or-absent-reason",
      "annotation-markers-unique-within-document",
      "incomplete-inventory-explains",
    ],
  };
  for (const name of NAMES) {
    const r = rv([name, fx(`${name}.invalid.json`)]);
    const missed = expected[name].filter(
      (rule) => !r.stdout.includes(`[${rule}]`),
    );
    check(
      `the invalid ${name} fixture is refused, naming every expected rule${missed.length ? ` (missed: ${missed.join(", ")})` : ""}`,
      r.status === 1 && missed.length === 0 && /FAIL \S+: /.test(r.stdout),
    );
  }

  // 3. Cross-file rules fire when the peer is given — and are reported as
  //    skipped, never silently passed, when it is not. Both halves matter: a
  //    join that quietly no-ops when its peer is absent reads as coverage.
  {
    const alone = rv(["fork-register", fx("fork-register.invalid.json")]);
    const withPeer = rv([
      "fork-register",
      fx("fork-register.invalid.json"),
      fx("external-modifications.valid.json"),
    ]);
    check(
      "a dangling fork cross-ref is caught when the external-modifications peer is given",
      withPeer.status === 1 &&
        /EM-DOES-NOT-EXIST' is not an external-modifications entry id \[cross-refs-resolve\]/.test(
          withPeer.stdout,
        ),
    );
    check(
      "the same rule is reported skipped, not passed, when the peer is absent",
      /skip cross-refs-resolve — no external-modifications file was given/.test(
        alone.stdout,
      ) && !/\[cross-refs-resolve\]/.test(alone.stdout),
    );
  }
  {
    // The BNA C2 defect (SMOKE-REPORT.md §3.5) as an exit code: an annotation
    // the bundle declares part of a complete inventory, with no disposition.
    const r = rv([
      "external-modifications",
      fx("external-modifications.invalid.json"),
      fx("fork-register.valid.json"),
      fx("source-bundle.valid.json"),
    ]);
    check(
      "an undisposed annotation from a complete inventory is caught across files",
      r.status === 1 &&
        /annotation 'C2' \(modification\) has no disposition, and the inventory declares itself complete \[annotation-inventory-disposed\]/.test(
          r.stdout,
        ) &&
        /is not a fork-register entry id \[fork-refs-resolve\]/.test(r.stdout),
    );
  }

  // 4. A structural violation stops before the x-rules, and says so: running
  //    joins over a shape that is not the shape produces cascades that bury the
  //    one message worth reading.
  {
    const d = mkdtempSync(resolve(tmpdir(), "l4-go-regshape-"));
    const j = JSON.parse(readFileSync(fx("fork-register.valid.json"), "utf8"));
    j.entries[0].surprise_key = true;
    const p = resolve(d, "s.json");
    writeFileSync(p, JSON.stringify(j));
    const r = rv(["fork-register", p]);
    check(
      "an unknown key in a register is refused, and the x-rules do not run",
      r.status === 1 &&
        /unknown key \(allowed: /.test(r.stdout) &&
        /structural check failed; x-rules not run/.test(r.stdout),
    );
  }

  // 5. The enforcement contract, both directions. These are the checks that
  //    keep the schemas from growing a constraint nobody runs.
  {
    const d = mkdtempSync(resolve(tmpdir(), "l4-go-regschema-"));
    const load = (n) =>
      JSON.parse(readFileSync(resolve(SCHEMAS, `${n}.schema.json`), "utf8"));
    const put = (n, s) =>
      writeFileSync(resolve(d, `${n}.schema.json`), JSON.stringify(s));

    const s1 = load("source-bundle");
    s1.properties.bundle_version.multipleOf = 1;
    put("source-bundle", s1);
    const r1 = rv(["source-bundle", fx("source-bundle.valid.json")], {
      L4_GO_SCHEMA_DIR: d,
    });
    check(
      "a schema keyword the validator does not implement is a hard refusal, not a partial pass",
      r1.status === 2 && /does not implement/.test(r1.stderr),
    );

    const s2 = load("source-bundle");
    s2["x-rules"].push({
      id: "a-rule-nobody-implemented",
      description: "declared in the schema and implemented nowhere at all",
    });
    put("source-bundle", s2);
    const r2 = rv(["source-bundle", fx("source-bundle.valid.json")], {
      L4_GO_SCHEMA_DIR: d,
    });
    check(
      "an x-rule declared with no implementation is refused",
      r2.status === 2 &&
        /a-rule-nobody-implemented.*no implementation/s.test(r2.stderr),
    );

    const s3 = load("source-bundle");
    s3["x-rules"] = s3["x-rules"].filter(
      (x) => x.id !== "covers-range-ordered",
    );
    put("source-bundle", s3);
    const r3 = rv(["source-bundle", fx("source-bundle.valid.json")], {
      L4_GO_SCHEMA_DIR: d,
    });
    check(
      "a rule implemented but not declared is refused too",
      r3.status === 2 &&
        /covers-range-ordered.*x-rules does not declare/s.test(r3.stderr),
    );
  }

  // 6. Usage: an unknown schema name, and a file whose own `kind` disagrees
  //    with the schema it was asked to be.
  {
    const r = rv(["no-such-register", fx("source-bundle.valid.json")]);
    check(
      "an unknown schema name exits 2 listing the three",
      r.status === 2 && NAMES.every((n) => r.stderr.includes(n)),
    );
    const r2 = rv(["fork-register", fx("source-bundle.valid.json")]);
    check(
      "a file whose kind disagrees with the named schema exits 2",
      r2.status === 2 &&
        /kind is "source-bundle", expected "fork-register"/.test(r2.stderr),
    );
  }
}

// ------------------------------------------------------------- 4. the driver
process.stdout.write("\n-- the driver --\n");

// The stages that declare no inputs and therefore never replay. Each is a pure
// function of the journal, which grows while it runs. Keep this list and
// go.sh's two `--inputs` no-op blocks in step; the idempotence checks below
// compare against it as a SET, not as a count.
const NEVER_REPLAY = ["p9-report", "p9-explain"];

// THE ASSERTION THAT DID NOT EXIST, and whose absence is total when it bites.
//
// go.sh's gate test is `[[ " $gated_by_HG1 " == *" $s "* ]]` with an EMPTY
// default: an unlisted stage runs ungated, gate-verify.sh is never consulted,
// run_begin's gated_stages does not name it so verify-run.mjs's ordering check
// cannot fire for it, and the report's Gates table prints gate ROWS rather than
// gate COVERAGE, so it says nothing either. A stage omitted from gated_by_HG1
// therefore publishes HG1-unreviewed work while every downstream honesty check
// reports clean.
//
// SPEC.md §7.3's rule is "HG1 blocks P6 onward". This asks the DRIVER, not the
// source text: `plan` derives its gate column from the same two shell strings
// the dispatch loop tests, and the p7 legs enter both through a conditional
// loop that no static reader of go.sh can evaluate.
{
  const plan = spawnSync(
    "bash",
    [
      resolve(HERE, "go.sh"),
      "plan",
      "--encoding",
      "primary",
      "--subject",
      FIXTURE_SUBJECT,
    ],
    { encoding: "utf8" },
  );
  const rows = [...plan.stdout.matchAll(/^ {2}(\S+)\s+gate=(\S+)/gm)].map(
    (m) => ({ stage: m[1], gate: m[2] }),
  );
  const from = rows.findIndex((r) => r.stage === "p6-tests");
  const ungated = rows
    .slice(from < 0 ? rows.length : from)
    .filter((r) => r.gate === "-")
    .map((r) => r.stage);
  if (ungated.length)
    process.stdout.write(
      `     ungated at or after p6-tests: ${ungated.join(", ")}\n`,
    );
  check(
    "every declared primary stage sequenced at or after p6-tests is gated",
    plan.status === 0 && from >= 0 && ungated.length === 0,
  );
  check(
    "the never-replaying stages are declared primary members, and the plan names them",
    NEVER_REPLAY.every((s) => rows.some((r) => r.stage === s)),
  );

  // ---- R9: the gate set is DERIVED, and the flag that used to pick it is gone
  //
  // `gated_by_HG1` was two hand-kept lists, one per stage set, and nothing
  // stopped them drifting from SPEC.md §7.3's actual sentence ("HG1 blocks P6
  // onward"). An ungated stage in either list would publish HG1-unreviewed work
  // and every downstream honesty check would AGREE with the omission, because
  // verify-run.mjs reads the gated set out of run_begin rather than deriving it.
  // The rule is now written once and applied; these ask the driver, through
  // `plan`, what it would actually gate.
  {
    const planRows = (subject, encoding) => {
      const r = spawnSync(
        "bash",
        [
          resolve(HERE, "go.sh"),
          "plan",
          "--subject",
          subject,
          "--encoding",
          encoding,
        ],
        { encoding: "utf8" },
      );
      // Both plans print a per-stage gate column; the primary plan spells it
      // `gate=HG1` and the deposit plan uses a column. One regex over the
      // stage-bearing lines covers both.
      const out = [];
      for (const line of r.stdout.split("\n")) {
        const m = /^\s{2}(p\d+[a-z-]*)\s+(?:gate=)?(HG1|HG2|NOT WIRED|-)/.exec(
          line,
        );
        if (m) out.push({ stage: m[1], gate: m[2] });
      }
      return { status: r.status, rows: out };
    };
    const phase = (st) => Number(/^p(\d+)/.exec(st)[1]);

    for (const [subject, encoding, label] of [
      [FIXTURE_SUBJECT, "primary", "primary"],
      [FIXTURE_SUBJECT, FIXTURE_ENCODING, "deposit"],
    ]) {
      const { status, rows: pr } = planRows(subject, encoding);
      check(
        `the ${label} plan enumerates its stages with a gate each`,
        status === 0 && pr.length > 0,
      );
      // A row the sidecar declares no leg for prints NOT WIRED and is not a
      // declared stage, so it is outside the rule either way.
      const declared = pr.filter((r) => r.gate !== "NOT WIRED");
      check(
        `every declared ${label} stage from P6 onward is HG1-gated, and none before P6 is`,
        declared.every((r) =>
          phase(r.stage) >= 6 && r.gate !== "HG2"
            ? r.gate === "HG1"
            : r.gate !== "HG1",
        ),
      );
    }
  }

  // ---- R9: --milestone refuses, and says what replaced it --------------------
  //
  // Refusing beats accepting-and-translating: a shim that still works keeps the
  // ORDINAL executable, and "the additional encoding" stops naming anything the
  // day a subject declares two. It also beats a silent "unknown option": the
  // reader has a mental model to correct, and this message is the only thing
  // left in the system that can correct it.
  {
    const refused = spawnSync(
      "bash",
      [
        resolve(HERE, "go.sh"),
        "plan",
        "--subject",
        FIXTURE_SUBJECT,
        "--milestone",
        "g1",
      ],
      { encoding: "utf8" },
    );
    check(
      "--milestone is REFUSED, not translated and not silently unknown",
      refused.status === 2 && /--milestone was retired/.test(refused.stderr),
    );
    check(
      "…and the refusal names the replacement for BOTH of its old values",
      /--encoding primary/.test(refused.stderr) &&
        /--encoding <id>/.test(refused.stderr) &&
        /--encoding undeclared/.test(refused.stderr),
    );
    // The refusal must NOT be spelled as a `case` arm: check-skill-drift.mjs
    // decides a flag exists by looking for its arm in go.sh, so an arm would
    // make the drift guard green over any stale `--milestone` command line
    // left in SKILL.md — the one sweep this ruling depends on being complete.
    //
    // The pattern is LINE-ANCHORED, mirroring check-skill-drift's `flagExists`,
    // and that is not incidental: the checker used a bare substring, and the
    // comment above — which exists to explain why there is no arm — contains
    // the text that substring looks for. It reported the retired flag as still
    // accepted. A declaration and a mention of one are different things, and
    // only the anchor tells them apart.
    check(
      "the refusal is not a `case` arm, so check-skill-drift still treats --milestone as nonexistent",
      !/^\s*(?:[^\n)]*\|)?--milestone\)/m.test(
        readFileSync(resolve(HERE, "go.sh"), "utf8"),
      ),
    );
    check(
      "…and check-skill-drift's own flag test is line-anchored, not a substring",
      !/goSrc\.includes\(`\$\{flag\}\)`\)/.test(
        readFileSync(resolve(HERE, "check-skill-drift.mjs"), "utf8"),
      ),
    );
  }

  // ---- R9: `undeclared` is a CLAIM about the subject, and is checked ---------
  {
    const wrong = spawnSync(
      "bash",
      [
        resolve(HERE, "go.sh"),
        "plan",
        "--subject",
        FIXTURE_SUBJECT,
        "--encoding",
        "undeclared",
      ],
      { encoding: "utf8" },
    );
    // Only meaningful for a subject that DOES declare one; skip otherwise.
    if (FIXTURE_ENCODING !== "undeclared")
      check(
        "--encoding undeclared is refused when the subject does declare one, and lists them",
        wrong.status === 2 && wrong.stderr.includes(FIXTURE_ENCODING),
      );
  }

  // ---- ARGUMENT-PARSER HYGIENE ----------------------------------------------
  //
  // Two defects the R9 review found, both of which `bash -n` is structurally
  // unable to see.
  {
    const goSrc = readFileSync(resolve(HERE, "go.sh"), "utf8");

    // 1. NO DUPLICATE `case` LABEL. A repeated label is legal shell — the first
    //    arm wins and the second is dead — so the symptom is a documented flag
    //    that parses, sets a variable nobody reads, and exits 0. That is what
    //    happened when R2/R3 gave `--encoding` a second, unrelated meaning:
    //    `new-subject … --encoding path/x.l4` silently wrote the default path
    //    instead. Measured before the repair; `new-subject` and a control run
    //    with no flag at all produced byte-identical sidecars.
    const labels = [
      ...goSrc.matchAll(/^\s*(-[-a-z][a-z-]*(?:\s*\|\s*-[-a-z][a-z-]*)*)\)/gm),
    ].flatMap((m) => m[1].split("|").map((x) => x.trim()));
    const dupes = labels.filter((f, i) => labels.indexOf(f) !== i);
    check(
      "no flag is declared twice in go.sh's argument parser",
      dupes.length === 0 ||
        (process.stdout.write(`     duplicated: ${dupes.join(", ")}\n`), false),
    );

    // 2. EVERY VALUE-TAKING FLAG REFUSES A MISSING VALUE, with exit 2 and its
    //    own name. Without the guard, `$2` is unbound under `set -u` and bash
    //    aborts with a line number and exit 1 — an interpreter stack trace
    //    where a usage error belongs, and the wrong code: 2 is this driver's
    //    usage exit, 1 means a real finding about the corpus.
    //
    //    Derived from the parser, not listed here: a flag added without the
    //    guard must fail this, which a hand-kept list cannot make happen.
    const valueTaking = [
      ...goSrc.matchAll(
        /^\s*(--[a-z][a-z-]*)\)\n(?:\s*#[^\n]*\n)*\s*([^\n]*)/gm,
      ),
    ]
      .filter(([, , body]) => /"\$2"/.test(body) || /need_val/.test(body))
      .map(([, flag]) => flag);
    const unguarded = [];
    for (const flag of [...new Set(valueTaking)]) {
      const r = spawnSync("bash", [resolve(HERE, "go.sh"), "plan", flag], {
        encoding: "utf8",
      });
      if (r.status !== 2 || !r.stderr.includes(`${flag} needs a value`))
        unguarded.push(`${flag} (exit ${r.status})`);
    }
    check(
      `all ${new Set(valueTaking).size} value-taking flags refuse a missing value with exit 2`,
      valueTaking.length > 0 &&
        (unguarded.length === 0 ||
          (process.stdout.write(`     unguarded: ${unguarded.join(", ")}\n`),
          false)),
    );
  }
  // HG1 MUST RE-OPEN WHEN THE NARRATIVE MOVES.
  //
  // `p9-explain` is HG1-gated because it publishes narrative prose, but the
  // gate binds to `corpus_digest`, and that digest covered the L4 modules
  // alone. MEASURED against a scratch copy of the tree: waive HG1, edit
  // `explainer/orientation.md`, re-run `--only p9-explain` with no new grant —
  // the gate stayed open, the stage re-ran, and the replaced prose went into
  // the rendered document. `--bless` then cleared the drift banner too.
  //
  // This asks the driver, via `plan`, for the digest it would bind a gate to,
  // and checks that touching a narrative file moves it. A source-text
  // assertion about go.sh would pass over a `GO_ENCODING_FILES` array that was
  // built and then overwritten.
  {
    const digestOf = () => {
      const p = spawnSync(
        "bash",
        [
          resolve(HERE, "go.sh"),
          "plan",
          "--encoding",
          "primary",
          "--subject",
          FIXTURE_SUBJECT,
        ],
        { encoding: "utf8" },
      );
      return /sha256:[0-9a-f]{64}/.exec(p.stdout)?.[0] ?? null;
    };
    const subj = spawnSync(
      "node",
      [resolve(HERE, "lib/subject.mjs"), FIXTURE_SUBJECT],
      { encoding: "utf8" },
    ).stdout;
    const dir = /GO_S_EXPLAINER_DIR='([^']+)'/.exec(subj)?.[1] ?? null;
    const file = dir
      ? readdirSync(dir)
          .filter((f) => f.endsWith(".md"))
          .sort()[0]
      : null;
    check(
      "the digest a gate binds to moves when a narrative file is edited",
      (() => {
        if (!dir || !file) return false; // no deposit: nothing to bind, nothing to check
        const p = resolve(dir, file);
        const before = digestOf();
        if (!before) return false;
        const original = readFileSync(p, "utf8");
        try {
          writeFileSync(p, original + "\n<!-- selftest probe -->\n");
          const after = digestOf();
          return !!after && after !== before;
        } finally {
          writeFileSync(p, original);
        }
      })(),
    );
  }

  check(
    "every never-replaying stage declares an EMPTY --inputs block",
    NEVER_REPLAY.every((s) => {
      const p = resolve(HERE, "phases", `${s}.sh`);
      if (!existsSync(p)) return false;
      const t = readFileSync(p, "utf8");
      const m =
        /if \[\[ "\$\{1:-\}" == "--inputs" \]\]; then([\s\S]*?)\nfi/.exec(t);
      // The block must reach `exit 0` without printing a path: a stage that
      // digests its own future would report `replayed` over a journal that has
      // since grown.
      return !!m && /exit 0/.test(m[1]) && !/printf|echo/.test(m[1]);
    }),
  );
}

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
    "--encoding",
    "primary",
    "--subject",
    FIXTURE_SUBJECT,
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

  go([
    "run",
    "--encoding",
    "primary",
    "--subject",
    FIXTURE_SUBJECT,
    "--run-id",
    runId,
  ]);
  const all = read(j).filter((r) => r.kind === "stage_end");
  const secondPass = all.slice(firstPass.length);
  const verdict2 = read(j)
    .filter((r) => r.kind === "run_end")
    .pop()?.verdict;

  // The idempotence property, stated so it is falsifiable: on the second run,
  // every stage that CAN replay must replay. The exceptions are the stages that
  // declare NO inputs, deliberately, because they are functions of the journal
  // and the journal grows while they run — a stage cannot digest its own
  // future. They are named as a SET rather than counted: this assertion used to
  // read `executed.length === 1 && executed[0] === "p9-report"`, and adding the
  // second such stage broke it in a way that invited bumping the constant to 2,
  // which is how the next one breaks it again.
  const executed = secondPass
    .filter((r) => !r.replayed_from)
    .map((r) => r.stage)
    .sort();
  const sameSet = (a, b) =>
    a.length === b.length && a.every((x, i) => x === b[i]);
  check(
    `a second run re-executes nothing but the never-replaying stages (${NEVER_REPLAY.join(", ")})`,
    sameSet(
      executed,
      NEVER_REPLAY.filter((s) => secondPass.some((r) => r.stage === s)).sort(),
    ),
  );
  check(
    "every other stage of the second run is marked replayed",
    secondPass.filter((r) => r.replayed_from).length ===
      secondPass.length - executed.length,
  );
  check(
    "the run verdict is unchanged by replay",
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
        "--encoding",
        "primary",
        "--subject",
        FIXTURE_SUBJECT,
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
        "--encoding",
        "primary",
        "--subject",
        FIXTURE_SUBJECT,
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

  // --- g2 replay correctness (D9, 2026-08-09) -------------------------------
  // The same idempotence properties as the g1 block above, over the de novo
  // declared set — the re-pointed stages answer --inputs with the RESOLVED
  // module set, so a byte-identical deposit replays and an edited one re-runs.
  // Also asserted: the measurement stages ran at denovo origin, i.e. what a g2
  // run measured is the deposit and not the corpus.
  {
    const rundir2 = mkdtempSync(resolve(tmpdir(), "l4-go-idem-g2-"));
    const env2 = { ...process.env, L4_GO_RUNDIR: rundir2 };
    const go2 = (args) => {
      try {
        return execFileSync("bash", [resolve(HERE, "go.sh"), ...args], {
          env: env2,
          encoding: "utf8",
          stdio: ["ignore", "pipe", "pipe"],
        });
      } catch (e) {
        return (e.stdout ?? "") + (e.stderr ?? "");
      }
    };
    go2([
      "run",
      "--encoding",
      FIXTURE_ENCODING,
      "--subject",
      FIXTURE_SUBJECT,
      "--waive",
      "HG1=selftest deposit replay-correctness",
    ]);
    const runId2 = execFileSync("ls", ["-1", rundir2], { encoding: "utf8" })
      .trim()
      .split("\n")[0];
    const j2 = resolve(rundir2, runId2, "journal.ndjson");
    const first2 = read(j2).filter((r) => r.kind === "stage_end");
    const verdictA = read(j2)
      .filter((r) => r.kind === "run_end")
      .pop()?.verdict;
    go2([
      "run",
      "--encoding",
      FIXTURE_ENCODING,
      "--subject",
      FIXTURE_SUBJECT,
      "--run-id",
      runId2,
    ]);
    const all2 = read(j2).filter((r) => r.kind === "stage_end");
    const second2 = all2.slice(first2.length);
    const verdictB = read(j2)
      .filter((r) => r.kind === "run_end")
      .pop()?.verdict;
    const executed2 = second2
      .filter((r) => !r.replayed_from)
      .map((r) => r.stage)
      .sort();
    const sameSet2 = (a, b) =>
      a.length === b.length && a.every((x, i) => x === b[i]);
    check(
      "a second deposit run re-executes nothing but the never-replaying stages",
      sameSet2(
        executed2,
        NEVER_REPLAY.filter((s) => second2.some((r) => r.stage === s)).sort(),
      ),
    );
    check(
      "the deposit run verdict is unchanged by replay",
      verdictA === verdictB && !!verdictA,
    );
    check(
      "replayed deposit receipts keep their original verdict",
      second2
        .filter((r) => r.replayed_from)
        .every(
          (r) => first2.find((f) => f.stage === r.stage)?.status === r.status,
        ),
    );
    check(
      "the deposit journal still verifies after a replay",
      verify(j2).ok === true,
    );
    check(
      "the deposit-run measurement stages record WHICH ENCODING they measured",
      ["p3-check", "p6-tests", "p8-verify"].every((s) => {
        const id = first2.find((r) => r.stage === s)?.metrics?.encoding_id;
        // The metric names the thing measured, not the pass it belonged to.
        // `module_origin=denovo` said "this was the second pass"; `encoding_id`
        // says which encoding, which is the fact a later reader needs.
        return typeof id === "string" && id !== "" && id !== "primary";
      }),
    );
    // The after-verdict explainer render is DECLARED-STAGES-ONLY (2026-08-09).
    // RED, measured before the guard: a g2 run dir held explainer.md
    // (126,982 B of g1 narrative about the COMMITTED corpus) and
    // explainer.html, announced by the driver, with zero p9-explain journal
    // rows — narrative prose outside the g2 HG1 digest, reported to nobody.
    check(
      "a deposit run renders NO explainer — the stage is undeclared there and the render respects the declared list",
      !existsSync(resolve(rundir2, runId2, "explainer.md")) &&
        !existsSync(resolve(rundir2, runId2, "explainer.html")),
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
      encoding: "primary",
      subject: "fixture-subject",
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
    const after = c.apply(before, { actualBasename: "subject.l4" });
    return (
      after === "<text>a (subject.l4:1:1-2:3) and a REAL difference here</text>"
    );
  })(),
);

// ---------------------------------------------------------- 5b. the explainer
//
// The explainer is the reader-facing sibling of the report, and it is a bigger
// honesty surface than the report is: it carries prose, figures and numbers
// about a body of law. Everything below attacks the mechanisms that stop it
// becoming a second place where numbers are typed by hand.
process.stdout.write("\n-- the explainer --\n");
{
  const RENDER = resolve(HERE, "report/render-explainer.mjs");
  const runRender = (dir, extra = []) =>
    spawnSync("node", [RENDER, dir, ...extra], { encoding: "utf8" });

  // A journal that describes a real-enough run, so the renderer gets past its
  // preconditions and reaches the narrative.
  const fixtureRun = () => {
    const d = mkdtempSync(resolve(tmpdir(), "l4-go-explain-"));
    const j = resolve(d, "journal.ndjson");
    append(j, {
      kind: "run_begin",
      run_id: "explainer-selftest",
      encoding: "primary",
      subject: FIXTURE_SUBJECT,
      repo_head: "0000000",
      tree_state: "clean",
      fixed_now: "2025-01-31T00:00:00Z",
      l4_binary: "/nonexistent",
      declared_stages: ["p6-tests", "p9-report", "p9-explain"],
      gated_stages: JSON.stringify({ HG1: ["p9-explain"], HG2: [] }),
    });
    append(j, base({ stage: "p6-tests", artifacts: [] }));
    append(j, { kind: "run_end", verdict: "COMPLETE", exit: 0 });
    return d;
  };

  const d0 = fixtureRun();
  const r0 = runRender(d0);
  const rendered = r0.status === 0;
  check(
    "the explainer renders from a journal alone, with no build and no network",
    rendered || (process.stdout.write(`     ${r0.stderr}\n`), false),
  );

  if (rendered) {
    const md = readFileSync(resolve(d0, "explainer.md"), "utf8");
    const summary = JSON.parse(
      readFileSync(resolve(d0, "explainer.summary.json"), "utf8"),
    );
    check(
      "an unreviewed narrative section renders a draft banner, and the header count matches the number of banners",
      (() => {
        const banners = (md.match(/\*\*DRAFT — claimed, not verified/g) ?? [])
          .length;
        return (
          summary.draft_sections === banners &&
          banners > 0 &&
          md.includes(
            `**${summary.draft_sections} of ${summary.sections} narrative sections in this document are AGENT-DRAFTED AND NOT REVIEWED.**`,
          )
        );
      })(),
    );
    check(
      "a projection with no receipt renders ABSENT with a stated reason, never omitted",
      /\*\*ABSENT\.\*\*/.test(md) && md.includes("## Pictures"),
    );
    check(
      "the never-searched section quotes the audit report's refusal rather than softening it",
      md.includes(
        "Nothing was searched, so nothing may be reported as searched",
      ) && md.includes("no-action letters"),
    );
    check(
      "the explainer never claims a hosted deployment",
      !/jl4\.legalese\.com|dev\.jl4\.legalese\.com/.test(md),
    );
    check(
      "every citation in the shipped narrative resolves against its source",
      summary.citations_total > 0 && summary.citations_unresolved === 0,
    );
    // The renderer's summary counts UNRESOLVED citations; it does not count
    // narrative LINT, and an uncited figure is a lint, not an unresolved
    // citation. pr-checks.yml's "Every citation in the shipped narrative
    // resolves" step fails on either, and swept every subject where the render
    // above reads one. MEASURED 2026-08-09: two N-DIGIT lints (raw ladder
    // widths written into s2-07) passed this file and failed that job, so the
    // only way to see them was to push. A check CI runs that the selftest does
    // not is a check you discover after pushing, which is the wrong end.
    check(
      "no shipped narrative, in any subject, carries an uncited figure",
      (() => {
        const SUBJECTS = resolve(HERE, "subjects");
        const bad = [];
        for (const sub of readdirSync(SUBJECTS)) {
          const dir = resolve(SUBJECTS, sub, "explainer");
          if (!existsSync(dir)) continue;
          for (const f of readdirSync(dir).filter((n) => n.endsWith(".md")))
            for (const p of lintNarrative(
              readFileSync(resolve(dir, f), "utf8"),
            ))
              bad.push(`${sub}/${f}:${p.line} [${p.code}]`);
        }
        return (
          bad.length === 0 ||
          (process.stdout.write(`     ${bad.join("\n     ")}\n`), false)
        );
      })(),
    );
    // The gate is the fact that most changes what a verdict means, and the
    // explainer printed the verdict without it: MEASURED on run
    // 2026-08-03-3f45e62b-004, `run verdict COMPLETE` over a journal whose
    // HG1 row reads `waived`, with the string "HG1" nowhere in the document.
    check(
      "a waived gate reaches the explainer's header, not only the audit report's",
      (() => {
        const d = fixtureRun();
        const j = resolve(d, "journal.ndjson");
        append(j, {
          kind: "gate",
          gate: "HG1",
          state: "waived",
          reason: "«WAIVER-REASON»",
        });
        const r = runRender(d);
        if (r.status !== 0) return false;
        const t = readFileSync(resolve(d, "explainer.md"), "utf8");
        return /HG1 WAIVED/.test(t) && t.includes("«WAIVER-REASON»");
      })(),
    );
    // A markdown carrier that emits `![x](repo/relative/path.svg)` from a
    // document living under TMPDIR ships six broken links and calls them
    // figures. MEASURED on the same run: 6 of 6 targets did not exist.
    check(
      "the markdown carrier links to no image it cannot resolve",
      (() => {
        const links = [...md.matchAll(/!\[[^\]]*\]\(([^)]+)\)/g)].map(
          (m) => m[1],
        );
        return links.every((l) => existsSync(resolve(d0, l)));
      })(),
    );
    check(
      "the coverage summary counts the uncited sections rather than claiming there are none",
      /citation\(s\), \d+ of them exempted/.test(md) &&
        (summary.sections ===
          (md.match(/\| `[a-z0-9._-]+` \| `[^`]+\.md` \|/g) ?? []).length ||
          /carry no citation at all|Every narrative section carries at least one citation/.test(
            md,
          )),
    );
  }

  // A render taken BEFORE `run_end` may not print a verdict, because there is
  // none yet. It used to fall back to a recomputation, which saw the declared
  // stages that had not run and printed `**INCOMPLETE**` — into the copy that
  // carries a hash, over a run that ended COMPLETE. MEASURED on run
  // 2026-08-03-3f45e62b-004: the attested copy said INCOMPLETE, the derived one
  // said COMPLETE, and the wrong one was the one a verifier re-hashes.
  check(
    "a render with no run_end declines to state a verdict rather than recomputing one",
    (() => {
      const d = mkdtempSync(resolve(tmpdir(), "l4-go-noend-"));
      const j = resolve(d, "journal.ndjson");
      append(j, {
        kind: "run_begin",
        run_id: "no-run-end",
        encoding: "primary",
        subject: FIXTURE_SUBJECT,
        repo_head: "0000000",
        tree_state: "clean",
        fixed_now: "2025-01-31T00:00:00Z",
        l4_binary: "/nonexistent",
        declared_stages: ["p6-tests", "p9-report", "p9-explain"],
        gated_stages: JSON.stringify({ HG1: ["p9-explain"], HG2: [] }),
      });
      append(j, base({ stage: "p6-tests", artifacts: [] }));
      const r = runRender(d);
      if (r.status !== 0) return false;
      const t = readFileSync(resolve(d, "explainer.md"), "utf8");
      return (
        /run verdict\s*\|\s*not yet recorded/.test(t) &&
        !/\*\*INCOMPLETE\*\*/.test(t) &&
        !/\*\*COMPLETE\*\*/.test(t)
      );
    })(),
  );

  // THE EQUALITY ORACLE for the duplicated journal fold (EXPLAINER-REPORT-SPEC
  // §3.5). The duplication is defended by this test, not by care: if the two
  // renderers ever disagree about one journal, two documents about the same run
  // disagree, which is the exact failure the explainer exists to avoid.
  //
  // The fixture is chosen for the four cases the fold has to get right: a
  // resumed stage (two rows, latest wins), a replayed receipt, a BROKEN row,
  // and a stage_end written AFTER run_end.
  // Distinctive sentinels. A bare word like "first" occurs in both documents'
  // ordinary prose, which made this check pass for the wrong reason.
  const SUPERSEDED = "SUPERSEDED-ROW-MUST-NOT-APPEAR";
  const LATEST = "LATEST-ROW-IS-WHAT-BOTH-READ";
  check(
    "both renderers fold one journal the same way — verdict and per-stage status",
    (() => {
      const d = mkdtempSync(resolve(tmpdir(), "l4-go-fold-"));
      const j = resolve(d, "journal.ndjson");
      append(j, {
        kind: "run_begin",
        run_id: "fold-equality",
        encoding: "primary",
        subject: FIXTURE_SUBJECT,
        repo_head: "0000000",
        tree_state: "clean",
        fixed_now: "2025-01-31T00:00:00Z",
        l4_binary: "/nonexistent",
        declared_stages: ["p6-tests", "p7-dmn", "p9-report", "p9-explain"],
        gated_stages: JSON.stringify({ HG1: ["p9-explain"], HG2: [] }),
      });
      append(
        j,
        base({ stage: "p7-dmn", status: "DEGRADED", reason: SUPERSEDED }),
      );
      const replayed = append(
        j,
        base({ stage: "p7-dmn", status: "DEGRADED", reason: LATEST }),
      );
      append(
        j,
        base({
          stage: "p7-dmn",
          status: "DEGRADED",
          reason: LATEST,
          oracle: null,
          replayed_from: replayed.hash,
        }),
      );
      append(j, base({ stage: "p6-tests" }));
      append(j, { kind: "run_end", verdict: "INCOMPLETE", exit: 1 });
      // A stage_end AFTER run_end: a directly-invoked phase script writes one,
      // and both folds must see it.
      append(
        j,
        base({ stage: "p9-report", status: "BROKEN", reason: "after run_end" }),
      );

      const rep = spawnSync(
        "node",
        [resolve(HERE, "report/render-report.mjs"), d],
        {
          encoding: "utf8",
        },
      );
      const exp = runRender(d);
      if (rep.status !== 0 || exp.status !== 0) return false;
      const repMd = readFileSync(resolve(d, "report.md"), "utf8");
      const expMd = readFileSync(resolve(d, "explainer.md"), "utf8");
      // The RECORDED verdict wins in both, over any recomputation.
      const bothVerdict =
        /verdict\s*\|\s*\*\*INCOMPLETE\*\*/.test(repMd) &&
        /run verdict\s*\|\s*\*\*INCOMPLETE\*\*/.test(expMd);
      // Latest row per stage: the earlier `first` reason must appear in
      // NEITHER document, and the replayed row is what both read.
      const bothLatest =
        !repMd.includes(SUPERSEDED) &&
        !expMd.includes(SUPERSEDED) &&
        repMd.includes(LATEST) &&
        expMd.includes(LATEST);
      // The record count and chain state agree.
      const bothChain =
        repMd.includes("chain verifies") && expMd.includes("chain verifies");
      return bothVerdict && bothLatest && bothChain;
    })(),
  );

  // The template gets the SAME digit check the audit report's template gets,
  // and it needs its own: the CI leg that exercises the report's check names
  // render-report.mjs by path, so a sibling template gets no coverage from it.
  check(
    "the explainer template carries no transcribed measurement",
    (() => {
      const t = readFileSync(
        resolve(HERE, "report/explainer-template.md"),
        "utf8",
      );
      const scrubbed = t
        .replace(/<!--[\s\S]*?-->/g, "")
        .replace(/```[\s\S]*?```/g, "")
        .replace(/\{\{[^}]*\}\}/g, "")
        .replace(/\b17 CFR Part 227\b/g, "")
        .replace(/§ ?\d+(\.\d+)*/g, "");
      return !/\d{2,}/.test(scrubbed);
    })(),
  );
  check(
    "the explainer refuses a journal with no run_begin",
    (() => {
      const d = mkdtempSync(resolve(tmpdir(), "l4-go-noexpbegin-"));
      writeFileSync(resolve(d, "journal.ndjson"), "");
      const r = runRender(d);
      return r.status === 4 && /no run_begin/.test(r.stderr);
    })(),
  );
  check(
    "the explainer prints a chain failure rather than refusing to render",
    (() => {
      const d = fixtureRun();
      const j = resolve(d, "journal.ndjson");
      const lines = readFileSync(j, "utf8").trim().split("\n");
      const rec = JSON.parse(lines[1]);
      // A hand edit, exactly what the chain exists to expose. It must CHANGE
      // something: base() already writes PASS with a null reason, and setting a
      // field to the value it already has leaves the canonical hash intact,
      // which made this check pass over a journal that still verified.
      rec.status = "DEGRADED";
      rec.reason = "laundered by hand";
      lines[1] = JSON.stringify(rec);
      writeFileSync(j, lines.join("\n") + "\n");
      const r = runRender(d);
      if (r.status !== 0) return false;
      const md = readFileSync(resolve(d, "explainer.md"), "utf8");
      return /\*\*DOES NOT VERIFY\*\*/.test(md);
    })(),
  );

  // --- the narrative lint and the citation checker, attacked directly -------
  check(
    "a bare digit-run in narrative prose is a lint finding",
    lintNarrative("The ceiling is 5000000 dollars.").some(
      (f) => f.code === "N-DIGIT",
    ) &&
      lintNarrative(
        "The ceiling is [$5,000,000](src:x/y.l4#L1) dollars, under Rule 100(a)(1).",
      ).length === 0,
  );
  check(
    "a reserved run-status word in narrative prose is a lint finding",
    lintNarrative("Every assertion is a PASS.").some(
      (f) => f.code === "N-STATUS",
    ) &&
      lintNarrative("the run is COMPLETE").some((f) => f.code === "N-STATUS") &&
      lintNarrative("the run passed and the corpus is complete").length === 0,
  );
  // The SLOT owns `##`. MEASURED 2026-08-05: S10's deposit used `##` for its
  // five sub-sections, and the rendered page carried five headings at the same
  // level as `## The rules` — so the printed outline stopped matching the spine
  // the document is organised around. Found by reading the output, which is
  // exactly the kind of catch that should not depend on someone reading it.
  check(
    "a narrative file's own heading may not sit at the spine slot's level",
    (() => {
      const codes = (t) => lintNarrative(t).map((f) => f.code);
      return (
        codes("## Nope\n").includes("N-HEADING") &&
        codes("# Nope\n").includes("N-HEADING") &&
        !codes("### Fine\n").includes("N-HEADING") &&
        // a `##` inside a fence is a code comment, not a heading
        !codes("```\n## not a heading\n```\n").includes("N-HEADING")
      );
    })(),
  );
  check(
    "a markdown construct outside the subset is a lint finding at its line",
    (() => {
      const codes = (t) => lintMarkdown(t).map((f) => f.code);
      return (
        codes("[ref]: https://example.com").includes("MD-REFLINK") &&
        codes("text\n<!-- hidden -->").includes("MD-COMMENT") &&
        codes("![a](b.png)").includes("MD-IMAGE") &&
        codes("<script>x</script>").includes("MD-HTML") &&
        codes("> a\n> > b").includes("MD-NESTEDQUOTE") &&
        codes("##### too deep").includes("MD-HEADING-DEPTH") &&
        // The construct that was MEASURED being mangled rather than refused: a
        // code span containing another code span. inline() closes at the first
        // inner backtick and leaves the trailing pair to draw as literal text.
        codes("a \`x \`inner\`\` b").includes("MD-BACKTICK") &&
        // A code span WRAPPED ACROSS TWO LINES is legal and must not fire it:
        // mdToHtml joins a paragraph's lines before rendering, so the span
        // closes correctly, and two of the regcf narrative files rely on that.
        !codes("a \`long name\nspanning lines\` b").includes("MD-BACKTICK") &&
        lintMarkdown("# fine\n\n- a\n- b\n\n| x |\n| - |\n| 1 |\n").length === 0
      );
    })(),
  );
  check(
    "a citation whose figure is not at the cited line does not resolve",
    (() => {
      const d = mkdtempSync(resolve(tmpdir(), "l4-go-cite-"));
      writeFileSync(resolve(d, "src.txt"), "line one\nthe answer is 42\n");
      const ctx = {
        resolveSrc: (p) => (existsSync(resolve(d, p)) ? resolve(d, p) : null),
        resolveArt: () => null,
      };
      const good = resolveCitations("[42](src:src.txt#L2)", ctx);
      const bad = resolveCitations("[43](src:src.txt#L2)", ctx);
      const gone = resolveCitations("[42](src:nope.txt#L2)", ctx);
      const art = resolveCitations("[42](art:nothing.dmn#L1)", ctx);
      return (
        good.findings.length === 0 &&
        !/CITATION DOES NOT RESOLVE/.test(good.text) &&
        bad.findings.length === 1 &&
        /CITATION DOES NOT RESOLVE/.test(bad.text) &&
        gone.findings[0]?.code === "C-MISSING" &&
        art.findings[0]?.code === "C-ARTIFACT-UNKNOWN"
      );
    })(),
  );
  check(
    "an unchecked citation is counted, and its reason is rendered",
    (() => {
      const d = mkdtempSync(resolve(tmpdir(), "l4-go-unchecked-"));
      writeFileSync(resolve(d, "src.txt"), "nothing numeric here\n");
      const out = resolveCitations(
        '[1340 cases](src:src.txt#L1 "unchecked: reported by the leg, not by this line")',
        {
          resolveSrc: (p) => resolve(d, p),
          resolveArt: () => null,
        },
      );
      return (
        out.unchecked === 1 &&
        out.findings.length === 0 &&
        /reported by the leg/.test(out.text)
      );
    })(),
  );
  check(
    "the HTML carrier escapes quotes in attribute contexts",
    // render-report.mjs's escapeHtml deliberately does NOT escape quotes, which
    // is safe there because it only ever writes text nodes. Copying it into an
    // attribute context is an injection bug; this is the guard.
    escapeAttr(`a" onload="x`) === "a&quot; onload=&quot;x" &&
      mdToHtml('[t](https://e.com "plain")').includes('title="plain"'),
  );
  check(
    "a link whose text is a code span renders the code, not a leftover sentinel",
    // The nesting bug this exists for: inline() lifts code spans out first, then
    // lifts links out — so the anchor it builds still carries the code span's
    // sentinel inside it, and a single-pass restore left two NUL bytes around a
    // stray digit in the output. It was MEASURED in a rendered explainer, where
    // the pointer to the audit report — written [\`report.md\`](report.md) — drew
    // as the bare character 0 and made the whole file read as binary to grep.
    (() => {
      const html = mdToHtml("see [\`report.md\`](report.md) for the audit\n");
      return (
        html.includes('<a href="report.md"><code>report.md</code></a>') &&
        !/\u0000/.test(html)
      );
    })(),
  );
  check(
    "a raw block reaches the HTML verbatim and its markdown twin does not leak a sentinel",
    (() => {
      const html = mdToHtml(`para\n\n${rawToken("k")}\n`, {
        raw: { k: "<figure>X</figure>" },
      });
      const missing = mdToHtml(`${rawToken("absent")}\n`, { raw: {} });
      return (
        html.includes("<figure>X</figure>") &&
        missing.includes("MISSING RAW BLOCK")
      );
    })(),
  );
  check(
    "a narrative deposit whose manifest names a missing file is refused, not rendered",
    (() => {
      const d = mkdtempSync(resolve(tmpdir(), "l4-go-badman-"));
      writeFileSync(
        resolve(d, "manifest.json"),
        JSON.stringify({
          explainer_schema: 1,
          title: "t",
          spine: {
            orientation: { file: "nope.md" },
            body: [],
            pictures: { declined: "no figures" },
            time: { declined: "no dates" },
            limits: { declined: "none" },
            sweep: { declined: "none" },
            call_to_action: { declined: "none" },
          },
        }),
      );
      const { problems } = loadManifest(d);
      return problems.some((p) => p.includes("nope.md"));
    })(),
  );
  check(
    "a spine slot declined without a reason is a schema error, not a silent decline",
    (() => {
      const d = mkdtempSync(resolve(tmpdir(), "l4-go-nodecline-"));
      writeFileSync(
        resolve(d, "manifest.json"),
        JSON.stringify({
          explainer_schema: 1,
          title: "t",
          spine: {
            orientation: { declined: null },
            body: [],
            pictures: { declined: "x" },
            time: { declined: "x" },
            limits: { declined: "x" },
            sweep: { declined: "x" },
            call_to_action: { declined: "x" },
          },
        }),
      );
      return loadManifest(d).problems.some((p) =>
        p.includes("declined must be a non-empty reason"),
      );
    })(),
  );
  check(
    "narrative drift, source drift and review drift are each detected",
    (() => {
      const d = mkdtempSync(resolve(tmpdir(), "l4-go-drift-"));
      writeFileSync(resolve(d, "a.md"), "hello\n");
      writeFileSync(resolve(d, "srcfile"), "source\n");
      const fileSha = hashOf(resolve(d, "a.md"));
      const srcSha = hashOf(resolve(d, "srcfile"));
      const rec = (over = {}) => ({
        file: "a.md",
        sha256: fileSha,
        drafted_from: [{ path: "srcfile", sha256: srcSha }],
        review: { state: "unreviewed" },
        ...over,
      });
      const clean = driftFor(rec(), { repoRoot: d, dir: d });
      const narrativeMoved = driftFor(rec({ sha256: "sha256:different" }), {
        repoRoot: d,
        dir: d,
      });
      const sourceMoved = driftFor(
        rec({
          drafted_from: [{ path: "srcfile", sha256: "sha256:different" }],
        }),
        { repoRoot: d, dir: d },
      );
      const reviewStale = driftFor(
        rec({
          review: {
            state: "reviewed",
            reviewed_sha256: "sha256:different",
            reviewed_sources: [],
          },
        }),
        { repoRoot: d, dir: d },
      );
      return (
        !clean.narrative &&
        clean.sources.length === 0 &&
        clean.state === "unreviewed" &&
        narrativeMoved.narrative?.kind === "changed" &&
        sourceMoved.sources.length === 1 &&
        reviewStale.state === "stale"
      );
    })(),
  );
}

// ===== BEGIN denovo-diff-oracle checks (owner: denovo-diff agent) ===========
//
// The §8 diff oracle has no CI leg of its own — G2 is unbuilt, so nothing runs
// it on a schedule. These checks are the only thing standing between it and
// silent rot, and they are chosen for the three ways it would rot into
// uselessness: a schema that stopped refusing, a battery whose "minimised"
// witnesses stopped being minimal, and a rule-date wrapper that stopped
// applying (which produces confident, well-typed, wrong answers — see the
// comment at generateProbe).
import {
  assertSupported as ddAssertSupported,
  validateAgainstSchema as ddValidate,
  sanitiseFieldName as ddSanitise,
  candidatesFor as ddCandidates,
  expandBattery as ddExpand,
  jobsFor as ddJobsFor,
  generateProbe as ddGenerateProbe,
  canonAnswer as ddCanon,
  compare as ddCompare,
  minimise as ddMinimise,
  sensitivity as ddSensitivity,
} from "./lib/denovo-diff.mjs";

process.stdout.write("\n-- the de novo diff oracle --\n");
{
  const DD = resolve(HERE, "../../specs/todo/single-instruction-demo/schemas");
  const schemaPath = resolve(DD, "surface-map.schema.json");
  const fixturePath = resolve(DD, "fixtures/regcf-identity.surface-map.json");
  const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
  const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));

  // 1. The enforcement contract: the validator implements the whole schema, or
  //    says so. A keyword that is parsed and not enforced is a constraint that
  //    silently does not exist. (Same stance as register-validate.mjs's, over a
  //    larger keyword subset — surface-map needs oneOf, minProperties and
  //    schema-valued additionalProperties, which that validator does not have.)
  check("surface-map.schema.json uses no keyword the validator ignores", () => {
    try {
      ddAssertSupported(schema);
      return true;
    } catch {
      return false;
    }
  });

  // 2. The shipped fixture validates, and the validator can be RED. Four
  //    mutations, one per structural rule the schema leans on.
  check(
    "the identity fixture satisfies surface-map.schema.json",
    ddValidate(schema, fixture).length === 0,
  );
  const mutate = (f) => {
    const d = JSON.parse(JSON.stringify(fixture));
    f(d);
    return ddValidate(schema, d);
  };
  check(
    "an unknown key is refused (additionalProperties: false)",
    mutate((d) => {
      d.pairs[0].oops = 1;
    }).some((e) => /unknown key 'oops'/.test(e)),
  );
  check(
    "a missing required key is refused",
    mutate((d) => {
      delete d.pairs[0].left;
    }).some((e) => /missing required key 'left'/.test(e)),
  );
  check(
    "a wrong schema tag is refused",
    mutate((d) => {
      d.schema = "l4-go/surface-map@2";
    }).some((e) => /must be "l4-go\/surface-map@1"/.test(e)),
  );
  check(
    "a pair id that is not kebab-case is refused",
    mutate((d) => {
      d.pairs[0].id = "Not Kebab";
    }).some((e) => /must match/.test(e)),
  );
  check(
    "a slot kind outside the enum is refused",
    mutate((d) => {
      d.slots.issuer.kind = "blob";
    }).some((e) => /must be one of/.test(e)),
  );

  // 3. The DMN name sanitiser, pinned against the exact strings the committed
  //    cases file uses. The oracle un-sanitises forward (sanitise the declared
  //    label, match the case key); if this mapping moved, every record slot
  //    would fail to feed and the oracle would report BROKEN rather than
  //    quietly drop fields — but pin it anyway, because a silent widening here
  //    would let two labels collide onto one key.
  check(
    "the DMN field-name sanitiser still matches the committed cases file",
    ddSanitise(
      "subject to a disqualification as specified in section 227.503(a)",
    ) === "subject_to_a_disqualification_as_specified_in_section_227_503_a" &&
      ddSanitise(
        "aggregate amount sold in reliance on section 4(a)(6) during the preceding 12 months",
      ) ===
        "aggregate_amount_sold_in_reliance_on_section_4_a_6_during_the_preceding_12_months",
  );

  // 4. Perturbation is boundary-biased and never a no-op.
  const cfg = {
    enabled: true,
    max_per_seed: 0,
    numeric_deltas: [-1, 1],
    numeric_multipliers: [0, 2],
    cross_pollinate: true,
  };
  const numCands = ddCandidates({ path: ["n"], value: 100 }, [5000], cfg, [42]);
  check(
    "a numeric leaf is perturbed by ±1, by the multipliers, by the pool and by declared thresholds",
    [99, 101, 0, 200, 5000, 4999, 5001, 42, 41, 43].every((x) =>
      numCands.includes(x),
    ),
  );
  check(
    "a perturbation never re-proposes the value it started from",
    !numCands.includes(100) &&
      !ddCandidates({ path: ["b"], value: true }, [], cfg, null).includes(true),
  );
  check(
    "a boolean leaf is flipped",
    ddCandidates({ path: ["b"], value: true }, [], cfg, null).includes(false),
  );

  // 5. THE MINIMALITY PROPERTY, checked structurally rather than asserted in
  //    prose: every generated row differs from its seed in exactly one leaf.
  //    The whole claim that a divergence witness is "minimised" rests on it.
  {
    const map = {
      slots: {
        r: { kind: "record", left: { type: "R" }, right: { type: "R" } },
        q: { kind: "record", left: { type: "Q" }, right: { type: "Q" } },
      },
      pairs: [
        {
          id: "p",
          left: { call: "f", args: ["r"] },
          right: { call: "f", args: ["r"] },
        },
        {
          id: "z",
          left: { call: "g", args: ["q"] },
          right: { call: "g", args: ["q"] },
        },
      ],
    };
    const seeds = [
      {
        name: "s0",
        origin: "x",
        slots: { r: { a: 1, b: true }, q: { c: 7 } },
        rule_date: null,
      },
      {
        name: "s1",
        origin: "x",
        slots: { r: { a: 9, b: false }, q: { c: 8 } },
        rule_date: null,
      },
    ];
    const { rows } = ddExpand(map, seeds);
    const seedById = new Map(
      rows.filter((r) => r.kind === "seed").map((r) => [r.id, r]),
    );
    const diffCount = (a, b) => {
      let n = 0;
      for (const s of Object.keys(a))
        for (const k of Object.keys(a[s])) if (a[s][k] !== b[s][k]) n++;
      return n;
    };
    const perts = rows.filter((r) => r.kind === "perturbation");
    check(
      "every perturbation row differs from its seed in exactly one leaf",
      perts.length > 0 &&
        perts.every(
          (r) => diffCount(r.slots, seedById.get(r.derived_from).slots) === 1,
        ),
    );
    check(
      "a perturbation's recorded mutation is the leaf that actually moved",
      perts.every((r) => {
        const [slot, ...rest] = r.mutation.path.split(".");
        return r.slots[slot][rest.join(".")] === r.mutation.to;
      }),
    );
    // 6. Relevance pruning is sound and does not prune the baseline.
    const jobs = ddJobsFor(map, rows);
    check(
      "every seed row is evaluated against every pair",
      rows
        .filter((r) => r.kind === "seed")
        .every(
          (r) =>
            jobs.filter((j) => j.row.id === r.id).length === map.pairs.length,
        ),
    );
    check(
      "a perturbation is evaluated only against pairs that take the mutated slot",
      jobs
        .filter((j) => j.row.kind === "perturbation")
        .every((j) => {
          const slot = j.row.mutation.path.split(".")[0];
          const pair = map.pairs.find((p) => p.id === j.pair);
          return (
            pair.left.args.includes(slot) || pair.right.args.includes(slot)
          );
        }),
    );
  }

  // 7. THE RULE-DATE TRIPWIRE. `EVAL UNDER RULES EFFECTIVE AT` is dynamically
  //    scoped over evaluation, and a value built lazily inside that scope
  //    carries its payload out of it: wrapping the whole CONSIDER produces the
  //    UNDATED answer, silently and with no diagnostic. So the wrapper must sit
  //    inside the WHEN RIGHT arm, around the application. Nothing else in the
  //    tree would notice if that moved.
  {
    const map = {
      slots: {
        r: { kind: "record", left: { type: "R" }, right: { type: "R" } },
      },
      pairs: [
        {
          id: "p",
          rule_date: "case",
          left: { call: "f", args: ["r"] },
          right: { call: "f", args: ["r"] },
        },
      ],
    };
    const row = {
      id: "s0",
      kind: "seed",
      name: "s0",
      slots: { r: { a: 1 } },
      rule_date: "2016-09-01",
      derived_from: null,
      mutation: null,
    };
    const { source } = ddGenerateProbe(
      { label: "L", module: "m.l4", timezone: "UTC" },
      "left",
      [{ pair: "p", row }],
      map,
      "m",
    );
    const arm = source.split("\n").find((l) => l.includes("WHEN RIGHT"));
    check(
      "a dated pair puts EVAL UNDER RULES EFFECTIVE AT inside the WHEN RIGHT arm, not around the CONSIDER",
      /WHEN RIGHT args THEN JUST \(`EVAL UNDER RULES EFFECTIVE AT` \(Date 1 9 2016\)/.test(
        arm || "",
      ) && !/EVAL UNDER RULES EFFECTIVE AT[\s\S]*CONSIDER/.test(source),
    );
    check(
      "an undated pair emits no rule-date wrapper at all",
      !ddGenerateProbe(
        { label: "L", module: "m.l4", timezone: "UTC" },
        "left",
        [{ pair: "p", row: { ...row, rule_date: null } }],
        { ...map, pairs: [{ ...map.pairs[0], rule_date: null }] },
        "m",
      ).source.includes("EVAL UNDER RULES EFFECTIVE AT"),
    );
  }

  // 8. Answer canonicalisation must not launder a non-answer into an answer.
  check(
    "a JUST wrapper is stripped, an error stays an error, and a bare NOTHING is not an answer",
    ddCanon({ kind: "value", value: "JUST OF TRUE" }).text === "TRUE" &&
      ddCanon({ kind: "value", value: "NOTHING" }).kind === "decode-failed" &&
      ddCanon({ kind: "error", value: "boom\nmore" }).kind === "error" &&
      ddCanon(undefined).kind === "missing",
  );

  // 9. The script measures and never triages. SPEC.md §8's three dispositions
  //    are judgements; if one of them ever appears as a value this file writes,
  //    the skill/script boundary (ORCHESTRATOR.md §2.1) has been crossed.
  {
    const mk = (pair, id, kind, mutation, l) => ({
      job: {
        pair,
        rule_date: null,
        row: {
          id,
          kind,
          name: id,
          derived_from: kind === "perturbation" ? "s0" : null,
          mutation,
        },
      },
      answer: { kind: "value", value: l, text: l },
    });
    const L = [
      mk("p", "s0", "seed", null, "TRUE"),
      mk("p", "s0m0", "perturbation", { path: "r.a", from: 1, to: 2 }, "TRUE"),
      mk("p", "s0m1", "perturbation", { path: "r.a", from: 1, to: 3 }, "TRUE"),
    ];
    const R = JSON.parse(JSON.stringify(L));
    R[1].answer = { kind: "value", value: "FALSE", text: "FALSE" };
    R[2].answer = { kind: "value", value: "FALSE", text: "FALSE" };
    const rows = ddCompare(L, R);
    const ws = ddMinimise(rows);
    check(
      "two divergences on one leaf collapse to one witness, and it is the smaller move",
      ws.length === 1 && ws[0].mutation.to === 2 && ws[0].also_seen_on === 1,
    );
    check(
      "every witness leaves this script UNTRIAGED",
      ws.every((w) => w.disposition === "UNTRIAGED"),
    );
    check(
      "the comparator never writes a SPEC §8 disposition itself",
      !/["']?(ENCODING-ERROR|GENUINE-AMBIGUITY|IMPROVEMENT-OVER-CORPUS)["']?\s*[,;)]/.test(
        readFileSync(resolve(HERE, "lib/denovo-diff.mjs"), "utf8").replace(
          /^\s*\/\/.*$/gm,
          "",
        ),
      ),
    );
  }

  // 9b. Sensitivity accounting. Added after an adversarial re-measure found a
  //     false green: `total assets threshold` moved 10M → 20M in a scratch
  //     corpus changed a live path of `reporting-may-terminate` and produced
  //     6800 agreed · 0 diverged · exit 0, because every value the battery
  //     reaches for `status.total assets` sits below both thresholds. An
  //     agreement over an input no decision responded to is silence, not
  //     evidence, and the report has to say which is which.
  {
    const seed = (pair, l, r = l) => ({
      pair,
      row_id: "s0",
      row_kind: "seed",
      row_name: "s0",
      derived_from: null,
      mutation: null,
      left: { kind: "value", value: l, text: l },
      right: { kind: "value", value: r, text: r },
      agree: l === r,
    });
    const pert = (pair, id, path, l, r = l) => ({
      pair,
      row_id: id,
      row_kind: "perturbation",
      row_name: id,
      derived_from: "s0",
      mutation: { path, from: 1, to: 2 },
      left: { kind: "value", value: l, text: l },
      right: { kind: "value", value: r, text: r },
      agree: l === r,
    });
    const s = ddSensitivity([
      seed("p", "TRUE"),
      pert("p", "a1", "r.inert", "TRUE"), // never moves
      pert("p", "a2", "r.inert", "TRUE"),
      pert("p", "a3", "r.live", "FALSE"), // moves on both sides
      pert("p", "a4", "r.live", "TRUE"),
      pert("p", "a5", "r.rightonly", "TRUE", "FALSE"), // moves on one side only
    ]);
    const byLeaf = Object.fromEntries(s.map((x) => [x.leaf, x]));
    check(
      "a leaf perturbed without ever moving an answer is reported inert",
      byLeaf["r.inert"].perturbed === 2 && byLeaf["r.inert"].moved === 0,
    );
    check(
      "a leaf that moves an answer is not inert",
      byLeaf["r.live"].perturbed === 2 && byLeaf["r.live"].moved === 1,
    );
    check(
      "a move on either side alone counts — inertness is the conservative claim",
      byLeaf["r.rightonly"].moved === 1,
    );
    check(
      "a perturbation whose seed was never evaluated against the pair is not scored",
      ddSensitivity([pert("q", "b1", "r.x", "TRUE")]).length === 0,
    );
    // The whole point is that this is honest about the *measured* false green.
    // Reproduce it in miniature: total agreement over an inert leaf must not be
    // reportable as an unqualified reproduction of the corpus.
    check(
      "an all-inert comparison still agrees, and the sensitivity table says so",
      (() => {
        const rows = [seed("p", "TRUE"), pert("p", "a1", "r.inert", "TRUE")];
        const sens = ddSensitivity(rows);
        return (
          rows.every((r) => r.agree) && sens.length === 1 && sens[0].moved === 0
        );
      })(),
    );
  }

  // 10. End to end, when a binary and the corpus are both here: the identity
  //     map must agree with itself totally. This is self-test A of the design
  //     note, run small (--max-rows) so it stays a selftest rather than a job.
  {
    const l4 = process.env.L4;
    const corpus = resolve(HERE, "../../jl4/examples/legal/regcf/regcf.l4");
    if (!l4 || !existsSync(l4)) {
      skip("the identity run agrees with itself", "$L4 is unset or missing");
    } else if (!existsSync(corpus)) {
      skip(
        "the identity run agrees with itself",
        "the Reg CF corpus is not in this tree",
      );
    } else {
      const out = mkdtempSync(resolve(tmpdir(), "go-encode-diff-"));
      const r = spawnSync(
        "node",
        [
          resolve(HERE, "lib/denovo-diff.mjs"),
          "run",
          "--map",
          fixturePath,
          "--out",
          out,
          "--max-rows",
          "3",
        ],
        { encoding: "utf8" },
      );
      check(
        "the identity map agrees with itself on every evaluation, and exits 0",
        r.status === 0 && /0 diverged/.test(r.stdout || ""),
      );
      const rep = JSON.parse(
        readFileSync(resolve(out, "denovo-diff.json"), "utf8"),
      );
      check(
        "the identity run actually evaluated something (a vacuous agreement is not a pass)",
        rep.totals.evaluated >= fixture.pairs.length &&
          rep.totals.agreed === rep.totals.evaluated,
      );
      check(
        "the report states what the comparison cannot see",
        Array.isArray(rep.limits) &&
          rep.limits.some((l) => /deontic/i.test(l)) &&
          rep.limits.some((l) => /declare/i.test(l)) &&
          rep.limits.some((l) => /respond/i.test(l)),
      );
      check(
        "the report carries the sensitivity accounting, per pair and in total",
        Array.isArray(rep.sensitivity) &&
          typeof rep.totals.leaves_inert === "number" &&
          rep.per_pair.every(
            (p) =>
              typeof p.leaves_perturbed === "number" &&
              typeof p.leaves_inert === "number" &&
              p.leaves_inert <= p.leaves_perturbed,
          ) &&
          /Sensitivity/.test(
            readFileSync(resolve(out, "denovo-diff.md"), "utf8"),
          ),
      );
    }
  }

  // 11. THE SHIPPED MAP, not just the fixture.
  //
  //     Every leg above runs `fixtures/regcf-identity.surface-map.json`, so the
  //     map this repo actually ships was gated by nothing. It went stale twice
  //     without anyone noticing — once when the corpus grew a second DATE
  //     (4fec076e) and again when Rule 501(a)(4) became six booleans
  //     (3f06cdc6) — and by 2026-08-09 both `transfer`-slot pairs were raising
  //     `Missing required field` on the left for all twenty rows.
  //
  //     `validate` is the right depth for a selftest: it reads both modules'
  //     record declarations through `l4 render` and checks that every row
  //     supplies every declared field on both sides, which is the invariant
  //     that broke, without paying for eighty evaluations. A full `run` belongs
  //     in the pipeline, not here.
  {
    const l4 = process.env.L4;
    const shipped = resolve(
      HERE,
      "../../jl4/examples/legal/regcf/denovo/surface-map.json",
    );
    if (!l4 || !existsSync(l4)) {
      skip(
        "the shipped Reg CF surface map validates",
        "$L4 is unset or missing",
      );
    } else if (!existsSync(shipped)) {
      skip(
        "the shipped Reg CF surface map validates",
        "the Reg CF de novo map is not in this tree",
      );
    } else {
      const r = spawnSync(
        "node",
        [resolve(HERE, "lib/denovo-diff.mjs"), "validate", "--map", shipped],
        { encoding: "utf8" },
      );
      if (r.status !== 0)
        process.stdout.write(
          `     ${((r.stdout || "") + (r.stderr || "")).split("\n").slice(0, 4).join("\n     ")}\n`,
        );
      check(
        "the shipped Reg CF surface map validates — every row supplies every declared field, both sides",
        r.status === 0 && /is valid/.test(r.stdout || ""),
      );
    }
  }
}
// ===== END denovo-diff-oracle checks ========================================

// ===== BEGIN de-novo deposit-stage checks (owner: denovo-harnesses agent) ====
//
// The G2 stages p1-ingest, p2-sweep, p3-encode, p4-forks and p5-gate stopped
// refusing: each is now a real stage that VALIDATES a deposit an agent produced,
// because fetching, searching, encoding and fork-finding all need the network or
// a model and this orchestrator takes neither. That gives every one of them
// three outcomes, and all three are checked here — a stage whose only exercised
// path is "deposit absent, SKIPPED" is indistinguishable from the refusal it
// replaced.
//
// The stages are driven DIRECTLY rather than through go.sh, because CI's Go
// Orchestrator job builds no `l4` and go.sh refuses to run without one. p1, p2,
// p4 and p5 need no binary at all; only p3-encode does, and its binary-dependent
// path skips with a named reason.
{
  const {
    mkdirSync: mkd,
    writeFileSync: wr,
    readFileSync: rd,
    existsSync: ex,
    rmSync,
  } = await import("node:fs");
  const REPO = resolve(HERE, "../..");
  const T = mkdtempSync(resolve(tmpdir(), "l4-go-deposit-"));
  const DEP = resolve(T, "deposits");
  mkd(DEP, { recursive: true });

  const FX = resolve(
    REPO,
    "specs/todo/single-instruction-demo/schemas/fixtures",
  );
  // The shipped fixtures are about the BNA. A deposit carries its own `subject`
  // and the stages refuse one that is about a different body of law, so the
  // copies are re-subjected here — which is also what makes check 9 meaningful.
  const deposit = (fixture, name, subject = "smoke") => {
    const j = JSON.parse(rd(resolve(FX, fixture), "utf8"));
    j.subject = subject;
    const p = resolve(DEP, name);
    wr(p, JSON.stringify(j, null, 2) + "\n");
    return p;
  };
  const BUNDLE = deposit("source-bundle.valid.json", "bundle.json");
  const REGISTER = deposit(
    "external-modifications.valid.json",
    "register.json",
  );
  const FORKS = deposit("fork-register.valid.json", "forks.json");
  const BAD_FORKS = deposit("fork-register.invalid.json", "forks.bad.json");
  const BNA_FORKS = deposit(
    "fork-register.valid.json",
    "forks.bna.json",
    "bna",
  );

  const CORPUS = resolve(REPO, "jl4/examples/legal/regcf/regcf.l4");

  // --- 1. the sidecar's split sections (R2/R3) ------------------------------
  //
  // `denovo` used to be ONE object bundling six keys across four kinds of
  // thing. It is now three: `natlang_sources` (the fetched text and the sweep),
  // `comparison` (the declarations that only relate two encodings), and
  // `encodings` (additional encodings, keyed by an author-chosen id). The
  // schema's whole value is that it is CLOSED, so every positive resolution
  // below has a refusing sibling.
  const sidecars = resolve(T, "subjects");
  const mkSidecar = (id, extra, corpus = CORPUS) => {
    const d = resolve(sidecars, id);
    mkd(d, { recursive: true });
    wr(
      resolve(d, "subject.json"),
      JSON.stringify({
        id,
        display_name: "Selftest Subject",
        citation: "n/a",
        source_url: "https://example.invalid/",
        encoding: { main: corpus },
        checks: { min_dated_arms: 0, min_assertions: 0 },
        legs: {},
        ...(extra ?? {}),
      }),
    );
    wr(resolve(d, "pins.json"), "{}");
    wr(resolve(d, "known-defects.json"), "{}");
    wr(resolve(d, "NOTES.md"), "selftest fixture\n");
    return d;
  };
  const subjectRun = (id, ...args) =>
    spawnSync("node", [resolve(HERE, "lib/subject.mjs"), id, ...args], {
      encoding: "utf8",
      env: { ...process.env, L4_GO_SUBJECTS_DIR: sidecars },
    });

  mkSidecar("smoke", {
    natlang_sources: { bundle: BUNDLE, register: REGISTER },
    comparison: { fork_register: FORKS },
    encodings: { "cleanroom-a": { modules: [resolve(DEP, "smoke.l4")] } },
  });
  {
    const r = subjectRun("smoke");
    check(
      "natlang_sources and comparison resolve to absolute paths under their own keys",
      r.status === 0 &&
        r.stdout.includes(`GO_S_NATLANG_BUNDLE='${BUNDLE}'`) &&
        r.stdout.includes(`GO_S_NATLANG_REGISTER='${REGISTER}'`) &&
        r.stdout.includes(`GO_S_COMPARISON_FORKS='${FORKS}'`),
    );
    // THE SELECTION IS A RUN PARAMETER, NOT A SCHEMA KEY. Unselected, the answer
    // is about the committed encoding; that is the whole of R3 in one flag.
    check(
      "unselected, the committed encoding's modules are the module set",
      r.status === 0 &&
        r.stdout.includes(`GO_S_ENCODING_MODULES='${CORPUS}'`) &&
        r.stdout.includes("GO_S_ENCODING_ID='primary'"),
    );
    const sel = subjectRun("smoke", "--encoding", "cleanroom-a");
    check(
      "selecting an encoding swaps the module set under the ORDINARY name",
      sel.status === 0 &&
        sel.stdout.includes(
          `GO_S_ENCODING_MODULES='${resolve(DEP, "smoke.l4")}'`,
        ) &&
        sel.stdout.includes("GO_S_ENCODING_ID='cleanroom-a'") &&
        !ex(resolve(DEP, "smoke.l4")),
    );
    check(
      "an undeclared encoding id is refused, and the message names what IS declared",
      (() => {
        const bad = subjectRun("smoke", "--encoding", "nope");
        return (
          bad.status === 2 &&
          /declares no such encoding/.test(bad.stderr) &&
          /cleanroom-a/.test(bad.stderr)
        );
      })(),
    );
    check(
      "--encodings lists the additional encodings, which is what --encoding names and what a bad id is refused against",
      subjectRun("smoke", "--encodings").stdout.trim() === "cleanroom-a",
    );
  }
  {
    mkSidecar("badkey", { natlang_sources: { bundle: BUNDLE, surprise: "x" } });
    const r = subjectRun("badkey");
    check(
      "an unknown key inside natlang_sources is refused, naming the allowed set",
      r.status === 2 &&
        /natlang_sources: unknown key 'surprise'/.test(r.stderr),
    );
  }
  {
    mkSidecar("badcmp", { comparison: { surprise: "x" } });
    const r = subjectRun("badcmp");
    check(
      "an unknown key inside comparison is refused",
      r.status === 2 && /comparison: unknown key 'surprise'/.test(r.stderr),
    );
  }
  // FLOORS TRAVEL WITH THEIR ENCODING, and that is now STRUCTURAL rather than a
  // convention: `encodings.<id>.checks` sits inside the encoding it measures, so
  // a committed floor cannot be applied to a deposit and vice versa.
  {
    mkSidecar("floors", {
      comparison: { surface_map: resolve(DEP, "never-written-map.json") },
      encodings: {
        "cleanroom-a": {
          modules: [resolve(DEP, "smoke.l4")],
          checks: { min_dated_arms: 0, min_assertions: 39 },
          legs: {
            "p7-dmn": { cases: resolve(DEP, "never-written.cases.json") },
          },
        },
      },
    });
    const r = subjectRun("floors");
    check(
      "unselected, the floors are the committed encoding's",
      r.status === 0 &&
        r.stdout.includes("GO_S_MIN_DATED_ARMS='0'") &&
        r.stdout.includes("GO_S_MIN_ASSERTIONS='0'"),
    );
    const sel = subjectRun("floors", "--encoding", "cleanroom-a");
    check(
      "selecting an encoding swaps the FLOORS too, under the ordinary names",
      sel.status === 0 && sel.stdout.includes("GO_S_MIN_ASSERTIONS='39'"),
    );
    check(
      "comparison.surface_map and the encoding's own p7-dmn cases resolve, existence not required",
      sel.status === 0 &&
        sel.stdout.includes(
          `GO_S_COMPARISON_SURFACE_MAP='${resolve(DEP, "never-written-map.json")}'`,
        ) &&
        sel.stdout.includes(
          `GO_S_ENCODING_DMN_CASES='${resolve(DEP, "never-written.cases.json")}'`,
        ) &&
        !ex(resolve(DEP, "never-written-map.json")),
    );
  }
  {
    mkSidecar("badfloor", {
      encodings: {
        "cleanroom-a": {
          modules: [resolve(DEP, "smoke.l4")],
          checks: { min_assertions: 39, surprise: 1 },
        },
      },
    });
    const r = subjectRun("badfloor");
    check(
      "an unknown key inside an encoding's checks is refused, naming the two floors",
      r.status === 2 &&
        /encodings\['cleanroom-a'\]\.checks: unknown key 'surprise'/.test(
          r.stderr,
        ),
    );
  }
  {
    mkSidecar("badleg", {
      encodings: {
        "cleanroom-a": {
          modules: [resolve(DEP, "smoke.l4")],
          legs: { "p7-dmn": { golden: "x.dmn" } },
        },
      },
    });
    const r = subjectRun("badleg");
    check(
      "an additional encoding's legs do NOT reuse LEG_KEYS: a golden is refused, because it has none",
      r.status === 2 &&
        /encodings\['cleanroom-a'\]\.legs\['p7-dmn'\]: unknown key 'golden'/.test(
          r.stderr,
        ),
    );
  }
  {
    mkSidecar("badleg2", {
      encodings: {
        "cleanroom-a": {
          modules: [resolve(DEP, "smoke.l4")],
          legs: { "p7-akn": { cases: "x.json" } },
        },
      },
    });
    const r = subjectRun("badleg2");
    check(
      "a leg with no additional-encoding schema refuses every key",
      r.status === 2 &&
        /encodings\['cleanroom-a'\]\.legs\['p7-akn'\]: unknown key 'cases'/.test(
          r.stderr,
        ),
    );
  }
  // AN ID NAMES AN OCCASION, NOT A SENTENCE — and 'primary' is reserved, because
  // that is what the selector calls the committed encoding.
  {
    mkSidecar("badid", {
      encodings: { "Cleanroom Two": { modules: [resolve(DEP, "smoke.l4")] } },
    });
    check(
      "an encoding id that is not a slug is refused",
      subjectRun("badid").status === 2,
    );
    mkSidecar("reservedid", {
      encodings: { primary: { modules: [resolve(DEP, "smoke.l4")] } },
    });
    const r = subjectRun("reservedid");
    check(
      "'primary' may not be redeclared as an encoding id",
      r.status === 2 && /may not be redeclared/.test(r.stderr),
    );
  }
  {
    mkSidecar("nomodules", { encodings: { "cleanroom-a": { checks: {} } } });
    const r = subjectRun("nomodules");
    check(
      "an encoding with no modules is refused — an encoding IS its modules",
      r.status === 2 && /modules is required/.test(r.stderr),
    );
  }
  {
    mkSidecar("selfdiff", {
      encodings: {
        "cleanroom-a": { modules: ["jl4/examples/legal/regcf/regcf.l4"] },
      },
    });
    const r = subjectRun("selfdiff");
    check(
      "an additional module that IS the committed one is refused — the diff would be an identity",
      r.status === 2 && /also a committed encoding module/.test(r.stderr),
    );
  }
  {
    mkSidecar("bare", null);
    const r = subjectRun("bare");
    check(
      "omitting all three sections is legal, and every new GO_S_* comes back empty",
      r.status === 0 &&
        r.stdout.includes("GO_S_NATLANG_BUNDLE=''") &&
        r.stdout.includes("GO_S_NATLANG_REGISTER=''") &&
        r.stdout.includes("GO_S_COMPARISON_FORKS=''") &&
        r.stdout.includes("GO_S_COMPARISON_SURFACE_MAP=''"),
    );
    check(
      "and a subject with no additional encoding lists none",
      subjectRun("bare", "--encodings").stdout.trim() === "",
    );
  }

  // --- 2. driving one stage, and reading the row it wrote --------------------
  let runSeq = 0;
  const stage = (name, over = {}) => {
    const run = resolve(T, `run${++runSeq}`);
    mkd(resolve(run, "artifacts"), { recursive: true });
    const r = spawnSync("bash", [resolve(HERE, `phases/${name}.sh`)], {
      encoding: "utf8",
      env: {
        ...process.env,
        GO_ROOT: REPO,
        GO_RUN: run,
        GO_STAGE: name,
        GO_INPUTS_DIGEST: "sha256:selftest",
        GO_FIXED_NOW: "2025-01-31T00:00:00Z",
        GO_S_ID: "smoke",
        GO_S_DIR: resolve(sidecars, "smoke"),
        GO_S_CITATION: "n/a",
        GO_S_ENCODING: CORPUS,
        GO_S_NATLANG_BUNDLE: "",
        GO_S_NATLANG_REGISTER: "",
        GO_S_COMPARISON_FORKS: "",
        GO_S_ENCODING_MODULES: "",
        L4_GO_REQUIRED: "0",
        ...over,
      },
    });
    const jp = resolve(run, "journal.ndjson");
    const rows = ex(jp)
      ? rd(jp, "utf8")
          .trim()
          .split("\n")
          .filter(Boolean)
          .map((l) => JSON.parse(l))
      : [];
    const row = rows.filter((x) => x.kind === "stage_end").pop() ?? null;
    return { exit: r.status, stdout: r.stdout, stderr: r.stderr, row, rows };
  };
  const ALL = {
    GO_S_NATLANG_BUNDLE: BUNDLE,
    GO_S_NATLANG_REGISTER: REGISTER,
    GO_S_COMPARISON_FORKS: FORKS,
  };

  // --- 3. deposit present: the stage validates it and PASSes -----------------
  for (const [name, key] of [
    ["p1-ingest", "GO_S_NATLANG_BUNDLE"],
    ["p2-sweep", "GO_S_NATLANG_REGISTER"],
    ["p4-forks", "GO_S_COMPARISON_FORKS"],
  ]) {
    const s = stage(name, ALL);
    check(
      `${name} over a valid deposit PASSes with a structural oracle over a hashed artifact`,
      s.exit === 0 &&
        s.row?.status === "PASS" &&
        s.row?.oracle?.class === "structural" &&
        s.row?.oracle?.exit === 0 &&
        (s.row?.artifacts ?? []).length === 1 &&
        !!s.row.artifacts[0].sha256,
    );
    check(
      `${name} records how many peers its joins could see, and how many joins were skipped`,
      s.row?.metrics?.peers_present === "2" &&
        s.row?.metrics?.joins_skipped === "0" &&
        Number(s.row?.metrics?.rules_checked) > 0,
    );
    void key;
  }
  check(
    "p2-sweep records the sweep's own non-vacuity figures, so 'searched nothing' is readable from the journal",
    (() => {
      const m = stage("p2-sweep", ALL).row?.metrics ?? {};
      return m.searches !== undefined && m.entries !== undefined;
    })(),
  );
  check(
    "p4-forks records the fork counts per materialisation class, not just a total",
    (() => {
      const m = stage("p4-forks", ALL).row?.metrics ?? {};
      return (
        Number(m.forks) === 12 &&
        m.materialised !== undefined &&
        m.settled_by_authority !== undefined
      );
    })(),
  );

  // --- 4. deposit absent, and undeclared: SKIPPED with a NAMED reason --------
  {
    const s = stage("p1-ingest", {
      ...ALL,
      GO_S_NATLANG_BUNDLE: resolve(DEP, "never-written.json"),
    });
    check(
      "a declared-but-undeposited bundle is SKIPPED as a missing prerequisite, not refused as a defect",
      s.exit === 0 &&
        s.row?.status === "SKIPPED" &&
        /has not been produced yet/.test(s.row.reason) &&
        /agent work/.test(s.row.reason),
    );
  }
  {
    const s = stage("p2-sweep", ALL, {});
    void s;
    const t = stage("p2-sweep", { ...ALL, GO_S_NATLANG_REGISTER: "" });
    check(
      "a subject that declares no register is SKIPPED naming a LIVE key and the file to add it to",
      t.exit === 0 &&
        t.row?.status === "SKIPPED" &&
        // The key must be one the schema still accepts. Asserting the OLD
        // spelling is how a diagnostic survives a rename and starts pointing at
        // nothing: `denovo.*` ceased to exist at R2/R3, and these two tests were
        // pinning it in place for two rulings afterwards.
        !/denovo\./.test(t.row.reason) &&
        /declares no natlang_sources\.register/.test(t.row.reason) &&
        /subject\.json/.test(t.row.reason),
    );
  }
  {
    const s = stage("p4-forks", {
      ...ALL,
      GO_S_COMPARISON_FORKS: resolve(DEP, "never-written.json"),
      L4_GO_REQUIRED: "1",
    });
    check(
      "an absent deposit is FATAL under L4_GO_REQUIRED=1 — a G2 run that skipped every deposit is not a G2 run",
      s.exit === 5 && s.row?.status === "SKIPPED",
    );
  }

  // --- 5. deposit invalid: DEGRADED, naming the rule ------------------------
  {
    const s = stage("p4-forks", { ...ALL, GO_S_COMPARISON_FORKS: BAD_FORKS });
    check(
      "an invalid fork register is DEGRADED, and the reason NAMES the rules that fired against it",
      s.exit === 1 &&
        s.row?.status === "DEGRADED" &&
        /taken-names-a-live-reading/.test(s.row.reason) &&
        /interpretation-fields-unique/.test(s.row.reason),
    );
    // The errexit regression, pinned. `set -e` restored inside the shared helper
    // is shell-global, so it re-enabled errexit in the CALLER, whose next act
    // was to read the helper's non-zero return — and the stage died before
    // writing anything. Measured: exit 1, empty journal, no row at all.
    check(
      "a DEGRADED de novo stage still WRITES its receipt (the errexit leak that produced an empty journal)",
      s.rows.length > 0 && s.row !== null,
    );
  }
  {
    // Peer attribution. The validator's exit code is a total over every file on
    // its command line, so a clean bundle beside a broken fork register exits 1
    // — and reading that as a fact about the bundle produced a measured
    // falsehood: p1-ingest naming fifteen fork-register rules as the bundle's.
    const s = stage("p1-ingest", { ...ALL, GO_S_COMPARISON_FORKS: BAD_FORKS });
    check(
      "a clean bundle beside a broken peer is DEGRADED, but its reason does not blame the bundle",
      s.exit === 1 &&
        s.row?.status === "DEGRADED" &&
        /internally well formed/.test(s.row.reason) &&
        /no rule fired against it/.test(s.row.reason),
    );
    check(
      "and the peer's rules are attributed to the peer, by path",
      s.row.reason.includes(BAD_FORKS) &&
        /taken-names-a-live-reading/.test(s.row.reason),
    );
  }
  {
    const s = stage("p4-forks", { ...ALL, GO_S_COMPARISON_FORKS: BNA_FORKS });
    check(
      "a deposit about a different body of law is refused — nothing in the three schemas ties a register to a subject",
      s.exit === 1 &&
        s.row?.status === "DEGRADED" &&
        /is about subject "bna", but this run is about "smoke"/.test(
          s.row.reason,
        ),
    );
  }
  {
    const notJson = resolve(DEP, "not.json");
    wr(notJson, "{ this is not json\n");
    const s = stage("p1-ingest", { ...ALL, GO_S_NATLANG_BUNDLE: notJson });
    check(
      "an unparseable deposit is a finding about the DEPOSIT (DEGRADED), never BROKEN about the harness",
      s.exit === 1 &&
        s.row?.status === "DEGRADED" &&
        /is not valid JSON/.test(s.row.reason),
    );
  }

  // --- 6. p5-gate: the joins, and the two halves it does not hold ------------
  {
    const s = stage("p5-gate", { ...ALL, GO_S_COMPARISON_FORKS: "" });
    const notes = (s.row?.notes ?? []).map((n) => n.text).join("\n");
    check(
      "p5-gate SKIPs when a deposit is missing rather than passing over joins that could not run",
      s.exit === 0 &&
        s.row?.status === "SKIPPED" &&
        /a PASS for a gate that checked nothing/.test(s.row.reason),
    );
    check(
      "and it states its two HG1-carried halves even on the SKIP",
      /fork-register completeness/.test(notes) &&
        /isomorphism spot-checks/.test(notes),
    );
  }
  {
    const s = stage("p5-gate", ALL);
    const notes = (s.row?.notes ?? []).map((n) => n.text).join("\n");
    check(
      "p5-gate over all three deposits PASSes the mechanisable joins with every peer present",
      s.exit === 0 &&
        s.row?.status === "PASS" &&
        s.row?.oracle?.class === "structural" &&
        s.row?.metrics?.joins_skipped === "0",
    );
    check(
      "and its PASS says, on the receipt, that it is NOT the P5 gate",
      /CARRIED BY HG1 — fork-register completeness/.test(notes) &&
        /CARRIED BY HG1 — isomorphism spot-checks/.test(notes) &&
        /this PASS is NOT the P5 gate/.test(notes),
    );
  }

  // --- 7. p3-encode ---------------------------------------------------------
  {
    // GO_MODULES="" IS THE DRIVER-PRODUCED STATE, and the fixture must use it.
    //
    // It used to hand the stage `GO_S_ENCODING_MODULES=""` — a state go.sh
    // cannot produce, because subject.mjs guarantees at least the entry module —
    // and the stage read that sidecar name directly. So the test passed while
    // the DRIVER-produced state (`--encoding undeclared`: GO_MODULES empty,
    // GO_S_ENCODING_MODULES still holding the COMMITTED encoding) sent all seven
    // of sg-succession's committed modules through `l4 check` and earned a PASS
    // whose oracle read "the deposit is L4 the toolchain accepts". Measured on
    // 4cce130b before the repair; the stage's own plan row said `undeclared` at
    // the same moment.
    const s = stage("p3-encode", { GO_MODULES: "" });
    check(
      "p3-encode with no module set is SKIPPED, naming a key the schema accepts",
      s.exit === 0 &&
        s.row?.status === "SKIPPED" &&
        !/denovo\./.test(s.row.reason) &&
        /declares no encodings\.<id>\.modules|declares no encoding\.modules/.test(
          s.row.reason,
        ),
    );
    // The half the old fixture could not see: with the DRIVER's empty set the
    // stage must reach no module at all, whatever the sidecar still declares.
    check(
      "…and it names no module in its inputs, even though the sidecar declares the committed encoding",
      !/\.l4/.test(
        spawnSync(
          "bash",
          [resolve(HERE, "phases", "p3-encode.sh"), "--inputs"],
          {
            encoding: "utf8",
            env: {
              ...process.env,
              GO_MODULES: "",
              GO_S_ENCODING_MODULES: CORPUS,
            },
          },
        ).stdout ?? "",
      ),
    );
  }
  {
    const s = stage("p3-encode", {
      GO_S_ENCODING_MODULES: resolve(DEP, "never-written.l4"),
    });
    check(
      "p3-encode with a declared-but-undeposited module is SKIPPED, naming which module",
      s.exit === 0 &&
        s.row?.status === "SKIPPED" &&
        /has not been deposited yet/.test(s.row.reason) &&
        s.row.reason.includes("never-written.l4"),
    );
  }
  {
    const l4 = process.env.L4;
    if (!l4 || !ex(l4)) {
      skip(
        "p3-encode typechecks a deposited module",
        "$L4 is unset or missing (CI's Go Orchestrator job builds no binary)",
      );
    } else {
      const good = resolve(DEP, "good.l4");
      wr(
        good,
        "GIVEN x IS A NUMBER\nGIVETH A BOOLEAN\n`is positive` x MEANS x > 0\n",
      );
      const s = stage("p3-encode", { GO_S_ENCODING_MODULES: good });
      check(
        "p3-encode over a deposited module that typechecks PASSes, and says on the row what it did not check",
        s.exit === 0 &&
          s.row?.status === "PASS" &&
          s.row?.oracle?.class === "structural" &&
          (s.row.notes ?? []).some((n) => /isomorphic/.test(n.text)) &&
          (s.row.notes ?? []).some((n) => /BRANCH over ELSE IF/.test(n.text)),
      );
      const bad = resolve(DEP, "bad.l4");
      wr(
        bad,
        "GIVEN x IS A NUMBER\nGIVETH A BOOLEAN\n`is broken` x MEANS x > \n",
      );
      const t = stage("p3-encode", { GO_S_ENCODING_MODULES: bad });
      check(
        "p3-encode is capable of red: a module that does not typecheck is DEGRADED",
        t.exit === 1 &&
          t.row?.status === "DEGRADED" &&
          Number(t.row.metrics.typecheck_failures) === 1,
      );
    }
  }

  // --- 7a. the re-pointed measurement stages (D1/D2/D4, 2026-08-09) ---------
  //
  // p3-check, p6-tests, p8-verify and p8-diff run over the module set the
  // driver resolved (GO_MODULES + GO_MODULES_ORIGIN), with the deposit
  // contract and PER-ORIGIN floors. Three properties are load-bearing and each
  // is checked with its red sibling: (1) an undeclared/absent module set is
  // SKIPPED naming the key, and fatal under L4_GO_REQUIRED=1; (2) at denovo
  // origin the stages read the denovo floors and NEVER the corpus floors —
  // proven by poisoning the corpus floors to absurd values and watching the
  // stage stay green, then breaking the denovo floor and watching it go red;
  // (3) a zero dated-arm floor over a zero matched count reports NOT CHECKED
  // rather than the vacuous green it used to print.
  {
    const skp = stage("p3-check", {
      GO_MODULES: "",
      GO_S_ENCODING_ID: "cleanroom-a",
    });
    check(
      "p3-check with no module set for its encoding is SKIPPED, naming the key that EXISTS",
      skp.exit === 0 &&
        skp.row?.status === "SKIPPED" &&
        // NAMES A KEY THAT EXISTS. The old message said `denovo.modules`, which
        // the schema now refuses — a diagnostic pointing at a nonexistent key
        // sends the reader to edit something that cannot be edited.
        /encodings?[.[]/.test(skp.row.reason) &&
        !/denovo/.test(skp.row.reason),
    );
    const abs = stage("p3-check", {
      GO_MODULES: resolve(DEP, "never-written.l4"),
      GO_S_ENCODING_ID: "cleanroom-a",
      L4_GO_REQUIRED: "1",
    });
    check(
      "p3-check with a declared-but-undeposited module is SKIPPED, and exit 5 under L4_GO_REQUIRED=1",
      abs.exit === 5 &&
        abs.row?.status === "SKIPPED" &&
        abs.row.reason.includes("never-written.l4"),
    );
    const p6u = stage("p6-tests", {
      GO_MODULES: "",
      GO_S_ENCODING_ID: "cleanroom-a",
    });
    check(
      "p6-tests with no module set for its encoding is SKIPPED, naming the key that EXISTS",
      p6u.exit === 0 &&
        p6u.row?.status === "SKIPPED" &&
        /encodings?[.[]/.test(p6u.row.reason) &&
        !/denovo/.test(p6u.row.reason),
    );
    const p8u = stage("p8-verify", {
      GO_MODULES: "",
      GO_S_ENCODING_ID: "cleanroom-a",
    });
    check(
      "p8-verify with no module set for its encoding is SKIPPED, naming the key that EXISTS",
      p8u.exit === 0 &&
        p8u.row?.status === "SKIPPED" &&
        /encodings?[.[]/.test(p8u.row.reason) &&
        !/denovo/.test(p8u.row.reason),
    );
  }
  {
    // p8-diff's deposit contract is over the MAP, not the module set.
    const und = stage("p8-diff", { GO_S_COMPARISON_SURFACE_MAP: "" });
    check(
      "p8-diff with no declared surface map is SKIPPED naming comparison.surface_map",
      und.exit === 0 &&
        und.row?.status === "SKIPPED" &&
        !/denovo\./.test(und.row.reason) &&
        /comparison\.surface_map/.test(und.row.reason),
    );
    const abs = stage("p8-diff", {
      GO_S_COMPARISON_SURFACE_MAP: resolve(DEP, "never-written-map.json"),
      L4_GO_REQUIRED: "1",
    });
    check(
      "p8-diff with a declared-but-undeposited map is SKIPPED, and exit 5 under L4_GO_REQUIRED=1",
      abs.exit === 5 && abs.row?.status === "SKIPPED",
    );
    // A harness error is DEGRADED (D4's recorded deviation from go_broken),
    // carrying the comparator exit as a metric and the deviation as a note —
    // and it must NOT be a vacuous pass: an unparseable map exercises the
    // comparator's exit-2 class, which also covers unresolvable pair rules
    // and short battery rows.
    const badMap = resolve(DEP, "bad-map.json");
    wr(badMap, "{ this is not a surface map\n");
    const deg = stage("p8-diff", { GO_S_COMPARISON_SURFACE_MAP: badMap });
    check(
      "p8-diff over an unparseable map is DEGRADED naming the harness error, never PASS and never BROKEN",
      deg.exit === 1 &&
        deg.row?.status === "DEGRADED" &&
        deg.row?.metrics?.comparator_exit === "2" &&
        (deg.row.notes ?? []).some((n) => /deviation/.test(n.text)),
    );
  }
  {
    const l4 = process.env.L4;
    if (!l4 || !ex(l4)) {
      skip(
        "per-origin floor selection over a deposited module",
        "$L4 is unset or missing (CI's Go Orchestrator job builds no binary)",
      );
    } else {
      const tiny = resolve(DEP, "tiny.l4");
      wr(
        tiny,
        "GIVEN x IS A NUMBER\nGIVETH A BOOLEAN\nDECIDE `is positive` x IF x GREATER THAN 0\n\n#ASSERT `is positive` 1\n",
      );
      const FLOORS = {
        GO_MODULES: tiny,
        GO_S_ENCODING_ID: "cleanroom-a",
        // the poison: if a stage reads a corpus floor at denovo origin, these
        // make it red, so a green run PROVES per-origin selection
        GO_S_MIN_DATED_ARMS: "999",
        GO_S_MIN_ASSERTIONS: "99999",
      };
      const p3 = stage("p3-check", {
        ...FLOORS,
        GO_S_MIN_DATED_ARMS: "0",
      });
      check(
        "p3-check over an additional encoding reads THAT encoding's floor, not the poisoned committed one",
        p3.exit === 0 &&
          p3.row?.status === "PASS" &&
          p3.row?.metrics?.min_dated_arms === "0" &&
          p3.row?.metrics?.encoding_id === "cleanroom-a",
      );
      check(
        "…and a zero floor over zero matched arms is NOT CHECKED on the receipt, not a vacuous green",
        (p3.row?.notes ?? []).some((n) =>
          /temporal closure NOT CHECKED/.test(n.text),
        ) && /NOT CHECKED/.test(p3.row?.oracle?.cmd ?? ""),
      );
      const p6 = stage("p6-tests", {
        ...FLOORS,
        GO_S_MIN_ASSERTIONS: "1",
      });
      check(
        "p6-tests at denovo origin reads the denovo assertion floor, not the poisoned corpus floor",
        p6.exit === 0 &&
          p6.row?.status === "PASS" &&
          p6.row?.metrics?.assertions_total === "1",
      );
      const p6red = stage("p6-tests", {
        ...FLOORS,
        GO_S_MIN_ASSERTIONS: "2",
      });
      check(
        "…and the denovo floor is capable of red: floor 2 over 1 assertion is DEGRADED",
        p6red.exit === 1 &&
          p6red.row?.status === "DEGRADED" &&
          /floor is 2/.test(p6red.row.reason),
      );
      const p6undecl = stage("p6-tests", {
        GO_MODULES: tiny,
        GO_S_ENCODING_ID: "cleanroom-a",
      });
      check(
        "an UNDECLARED denovo assertion floor defaults to 0 with a toothless-guard note on the receipt",
        p6undecl.exit === 0 &&
          p6undecl.row?.status === "PASS" &&
          (p6undecl.row.notes ?? []).some((n) =>
            /declares no denovo\.checks\.min_assertions/.test(n.text),
          ),
      );
      // The vacuous-pass hole under that default (RED, measured 2026-08-09):
      // a module with NO #ASSERT at all, floor defaulted 0, earned
      // PASS/execution over assertions_total=0 — "ran on cases and agreed"
      // with nothing run. Now DEGRADED: the assertions are this stage's whole
      // oracle, so an empty set demotes the status (unlike p3-check's
      // NOT CHECKED, which demotes one sub-check among several).
      const empty = resolve(DEP, "zeroassert.l4");
      wr(
        empty,
        "GIVEN x IS A NUMBER\nGIVETH A BOOLEAN\nDECIDE `is positive` x IF x GREATER THAN 0\n",
      );
      const p6zero = stage("p6-tests", {
        GO_MODULES: empty,
        GO_S_ENCODING_ID: "cleanroom-a",
      });
      check(
        "a zero-assertion module set is DEGRADED, never a vacuous PASS/execution",
        p6zero.exit === 1 &&
          p6zero.row?.status === "DEGRADED" &&
          /0 assertions ran/.test(p6zero.row?.reason ?? "") &&
          p6zero.row?.metrics?.assertions_total === "0",
      );
    }
  }

  // --- 7b. the floors are DIGEST CONTRIBUTORS (2026-08-09) -------------------
  // A floor is a verdict input the stage reads out of the sidecar (via GO_S_*
  // env), so an edit to it must re-run the oracle, never replay the old
  // verdict. RED, measured before the fix: both stages' --inputs listed only
  // modules + script (+ assert-report.mjs), so denovo.checks.min_assertions
  // 39 → 1000 followed by a --run-id resume printed "p6-tests: PASS
  // (replayed)" — a verdict the edited configuration would refuse. No $L4
  // needed: --inputs executes nothing.
  {
    const inputsOf = (name, over = {}) =>
      spawnSync("bash", [resolve(HERE, `phases/${name}.sh`), "--inputs"], {
        encoding: "utf8",
        env: {
          ...process.env,
          GO_ROOT: REPO,
          GO_MODULES: "probe.l4",
          GO_S_ENCODING_ID: "cleanroom-a",
          GO_S_MIN_ASSERTIONS: "",
          GO_S_MIN_DATED_ARMS: "",
          ...over,
        },
      }).stdout;
    const a6 = inputsOf("p6-tests", { GO_S_MIN_ASSERTIONS: "1" });
    const b6 = inputsOf("p6-tests", { GO_S_MIN_ASSERTIONS: "2" });
    check(
      "p6-tests' --inputs carries the resolved assertion floor, so a floor edit moves the digest",
      a6.includes("text:min_assertions=1") &&
        b6.includes("text:min_assertions=2") &&
        a6 !== b6,
    );
    check(
      "…and an undeclared assertion floor is its own contributor (it changes the receipt too)",
      inputsOf("p6-tests").includes("text:min_assertions=undeclared"),
    );
    const a3 = inputsOf("p3-check", { GO_S_MIN_DATED_ARMS: "0" });
    const b3 = inputsOf("p3-check", { GO_S_MIN_DATED_ARMS: "2" });
    check(
      "p3-check's --inputs carries the resolved dated-arm floor, so a floor edit moves the digest",
      a3.includes("text:min_dated_arms=0") &&
        b3.includes("text:min_dated_arms=2") &&
        a3 !== b3,
    );
  }

  // --- 8. the plan stops refusing -------------------------------------------
  {
    const r = spawnSync(
      "bash",
      [
        resolve(HERE, "go.sh"),
        "plan",
        "--encoding",
        "cleanroom-a",
        "--subject",
        "smoke",
      ],
      {
        encoding: "utf8",
        env: { ...process.env, L4_GO_SUBJECTS_DIR: sidecars },
      },
    );
    check(
      "go.sh plan --encoding <id> no longer refuses, and prints SPEC.md §4's full de novo order",
      r.status === 0 &&
        [
          "p1-ingest",
          "p2-sweep",
          "p3-encode",
          "p3-check",
          "p4-forks",
          "p5-gate",
          "p6-tests",
          "p8-verify",
          "p8-diff",
          "p9-report",
        ].every((s) => r.stdout.includes(s)),
    );
    // Until 2026-08-09 this asserted p3-check and p6-tests printed NOT WIRED.
    // The g2 wiring (D1/D5) falsified that — measured: the old assertion went
    // red against the new plan before this rewrite — and the claim is now the
    // opposite: the measurement stages are wired rows, p6-tests onward behind
    // HG1, with the deposit state in the DEPOSIT column. The smoke sidecar
    // declares a module that is never written, so its state reads `absent`.
    check(
      "the plan states each deposit's presence, and the re-pointed stages are wired rows, not NOT WIRED",
      /p1-ingest\s+-\s+present/.test(r.stdout) &&
        /p3-check\s+-\s+absent/.test(r.stdout) &&
        /p6-tests\s+HG1\s+absent/.test(r.stdout) &&
        /p8-verify\s+HG1\s+absent/.test(r.stdout) &&
        /p8-diff\s+HG1\s+undeclared/.test(r.stdout) &&
        !/p3-check\s+NOT WIRED/.test(r.stdout) &&
        !/p6-tests\s+NOT WIRED/.test(r.stdout),
    );
    // The legs that remain unwired must still say WHY, per leg — the plan's
    // whole value is naming what is missing. The smoke sidecar declares no
    // legs, so this is asked of the repo's real subject via the default
    // subjects dir (FIXTURE_SUBJECT declares the full leg set).
    {
      const rp = spawnSync(
        "bash",
        [
          resolve(HERE, "go.sh"),
          "plan",
          "--encoding",
          FIXTURE_ENCODING,
          "--subject",
          FIXTURE_SUBJECT,
        ],
        { encoding: "utf8" },
      );
      check(
        "each still-unwired p7 leg carries its own precise reason, and p7-dmn is a wired emit-only row",
        rp.status === 0 &&
          /p7-dmn\s+HG1\s+present\s+emit-only/.test(rp.stdout) &&
          // The reasons must name keys and things that EXIST in the new schema.
          // They used to say `denovo.legs[...]` and "a de novo demo entry",
          // both of which are now vocabulary the sidecar refuses.
          /p7-tnr\s+NOT WIRED\s+-\s+the sidecar declares no legs\['p7-tnr'\]\.golden for this encoding/.test(
            rp.stdout,
          ) &&
          /p7-ladder\s+NOT WIRED\s+-\s+needs its own demo entry/.test(
            rp.stdout,
          ) &&
          // Scoped to schema KEY references, not the bare word: the corpus
          // directory is still literally named `denovo/`, and renaming it means
          // moving a .l4 whose four goldens must be regenerated — a change that
          // needs a build, and a separate one. R2/R3 is about keys.
          !/denovo\.(legs|checks|modules|bundle|register|fork_register|surface_map)/.test(
            rp.stdout,
          ) &&
          !/compares against this subject's committed goldens, which are the replay artifacts/.test(
            rp.stdout,
          ),
      );
    }
    check(
      "and it refuses to let COMPLETE be read as 'a de novo run happened'",
      /does NOT mean a de novo run happened/.test(r.stdout) &&
        /§8 diff oracle/.test(r.stdout),
    );
    const t = spawnSync(
      "bash",
      [
        resolve(HERE, "go.sh"),
        "plan",
        "--encoding",
        "undeclared",
        "--subject",
        "bare",
      ],
      {
        encoding: "utf8",
        env: { ...process.env, L4_GO_SUBJECTS_DIR: sidecars },
      },
    );
    check(
      "a subject with no additional encoding still PLANS on the deposit path, every deposit reading 'undeclared'",
      t.status === 0 && (t.stdout.match(/undeclared/g) ?? []).length >= 4,
    );
  }

  rmSync(T, { recursive: true, force: true });
}

// --- the de novo receipts must reach the REPORT, not only the journal -------
//
// ORCHESTRATOR.md §5.2 asserts that a g2 run's five SKIPPED receipts each carry
// "a reason that appears in the report". Measured on a real run, three did:
// `render-report.mjs` rendered p1/p2/p3-encode and named p4-forks only inside a
// stale ABSENT string, while p5-gate had no site at all. Two further silences
// rode along — the de novo sections printed `status — reason` and nothing else,
// so a PASS (whose `reason` is null by design) rendered as the literal
// `**PASS** — null`, and every oracle `because`, metric and note was dropped.
//
// Those notes are the load-bearing part. A de novo PASS is a narrow structural
// claim and everything it does NOT establish lives in the notes: p1-ingest's
// "whether the bundle is the RIGHT text is unverified", p5-gate's two
// `CARRIED BY HG1` halves. Rendering the status without them converts a hedged
// claim into a bare green in the one artifact a human actually reads.
process.stdout.write("\n-- de novo receipts in the report --\n");
{
  const { rmSync } = await import("node:fs");
  const d = mkdtempSync(resolve(tmpdir(), "l4-go-denovoreport-"));
  const j = resolve(d, "journal.ndjson");
  append(j, {
    kind: "run_begin",
    run_id: "denovo-report-test",
    encoding: "cleanroom-a",
    subject: "fixture-subject",
    declared_stages: [
      "p1-ingest",
      "p2-sweep",
      "p3-encode",
      "p4-forks",
      "p5-gate",
    ],
  });
  append(
    j,
    base({
      stage: "p1-ingest",
      status: "PASS",
      reason: null,
      oracle: {
        cmd: "register-validate source-bundle …",
        exit: 0,
        class: "structural",
        because: "«P1-BECAUSE»",
      },
      notes: [{ text: "«P1-NOTE»", author: "phase-script", verified: false }],
    }),
  );
  append(
    j,
    base({
      stage: "p2-sweep",
      status: "SKIPPED",
      reason: "«P2-REASON»",
      artifacts: [],
      oracle: null,
    }),
  );
  append(
    j,
    base({
      stage: "p3-encode",
      status: "SKIPPED",
      reason: "«P3-REASON»",
      artifacts: [],
      oracle: null,
    }),
  );
  append(
    j,
    base({
      stage: "p4-forks",
      status: "SKIPPED",
      reason: "«P4-REASON»",
      artifacts: [],
      oracle: null,
    }),
  );
  append(
    j,
    base({
      stage: "p5-gate",
      status: "PASS",
      reason: null,
      oracle: {
        cmd: "register-validate … ×3",
        exit: 0,
        class: "structural",
        because: "«P5-BECAUSE»",
      },
      notes: [
        {
          text: "«P5-HG1-COMPLETENESS»",
          author: "phase-script",
          verified: false,
        },
        {
          text: "«P5-HG1-ISOMORPHISM»",
          author: "phase-script",
          verified: false,
        },
      ],
    }),
  );
  append(j, { kind: "run_end", verdict: "COMPLETE", exit: 0 });
  const r = spawnSync("node", [resolve(HERE, "report/render-report.mjs"), d], {
    encoding: "utf8",
  });
  const md =
    r.status === 0 ? readFileSync(resolve(d, "report.md"), "utf8") : "";
  check(
    "every de novo receipt's reason reaches the report — all five, not three",
    ["«P2-REASON»", "«P3-REASON»", "«P4-REASON»"].every((s) => md.includes(s)),
  );
  // THE GENERAL FORM OF THE CHECK ABOVE, which is the one that would have
  // caught the defect the check above did not.
  //
  // The five-stage list is hard-coded, so it can only ever confirm the five
  // stages somebody already thought of. `render-report.mjs` narrates `p7-*` by
  // filter and every other stage by name, and the verdict gloss it prints
  // claims that on a COMPLETE run "every non-PASS receipt carries a reason that
  // appears below". `p9-report` never falsified that only because it can emit
  // nothing but PASS or a hard failure; `p9-explain` is DEGRADED whenever a
  // narrative section is unreviewed, which is its normal state, so its reason
  // reached the journal and no reader — MEASURED on run
  // 2026-08-03-3f45e62b-004, five of six non-PASS reasons in the report.
  //
  // This fixture puts a non-PASS receipt on a stage with NO narrated site, and
  // asserts what the gloss promises. It fails for any future stage added
  // without a home, which is the property the hard-coded list cannot have.
  {
    const o = mkdtempSync(resolve(tmpdir(), "l4-go-orphanreason-"));
    const oj = resolve(o, "journal.ndjson");
    append(oj, {
      kind: "run_begin",
      run_id: "orphan-reason-test",
      encoding: "primary",
      subject: FIXTURE_SUBJECT,
      declared_stages: ["p6-tests", "p9-report", "p9-explain", "pZ-invented"],
    });
    append(oj, base({ stage: "p6-tests", status: "PASS", reason: null }));
    append(
      oj,
      base({ stage: "p9-report", status: "DEGRADED", reason: "«P9REPORT»" }),
    );
    append(
      oj,
      base({ stage: "p9-explain", status: "DEGRADED", reason: "«P9EXPLAIN»" }),
    );
    append(
      oj,
      base({ stage: "pZ-invented", status: "UNVERIFIED", reason: "«PZ»" }),
    );
    append(oj, { kind: "run_end", verdict: "COMPLETE", exit: 0 });
    const orr = spawnSync(
      "node",
      [resolve(HERE, "report/render-report.mjs"), o],
      { encoding: "utf8" },
    );
    const omd =
      orr.status === 0 ? readFileSync(resolve(o, "report.md"), "utf8") : "";
    check(
      "EVERY non-PASS receipt's reason reaches the report, including a stage no section narrates",
      ["«P9REPORT»", "«P9EXPLAIN»", "«PZ»"].every((s) => omd.includes(s)),
    );
    rmSync(o, { recursive: true, force: true });
  }
  check(
    "p4-forks and p5-gate have their own rendered blocks, not just a mention in ABSENT prose",
    /\*\*Ambiguity forks:\*\*/.test(md) &&
      /\*\*Adversarial gate \(mechanisable half\):\*\* PASS/.test(md),
  );
  check(
    "a PASS receipt renders without the literal 'null' its absent reason used to print",
    /\*\*PASS\*\*/.test(md) && !/\bnull\b/.test(md),
  );
  check(
    "a de novo PASS carries its oracle's `because` into the report, not just its status",
    md.includes("«P1-BECAUSE»") && md.includes("«P5-BECAUSE»"),
  );
  check(
    "and its notes — everything the PASS does NOT establish — reach the reader too",
    md.includes("«P1-NOTE»") &&
      md.includes("«P5-HG1-COMPLETENESS»") &&
      md.includes("«P5-HG1-ISOMORPHISM»"),
  );
  // The retensing that commit e10a64f2 did to the docs and missed in the one
  // place a reader sees: the renderer's own ABSENT prose still said these
  // stages "refuse" and that the de novo tooling "is unbuilt", printed on
  // EVERY g1 run.
  const g1 = mkdtempSync(resolve(tmpdir(), "l4-go-g1report-"));
  const gj = resolve(g1, "journal.ndjson");
  append(gj, {
    kind: "run_begin",
    run_id: "primary-report-test",
    encoding: "primary",
    subject: "fixture-subject",
    declared_stages: ["p6-tests"],
  });
  append(gj, base({ stage: "p6-tests", status: "PASS", reason: null }));
  append(gj, { kind: "run_end", verdict: "COMPLETE", exit: 0 });
  const gr = spawnSync(
    "node",
    [resolve(HERE, "report/render-report.mjs"), g1],
    {
      encoding: "utf8",
    },
  );
  const gmd =
    gr.status === 0
      ? readFileSync(resolve(g1, "report.md"), "utf8")
      : "«unrendered»";
  check(
    "a primary-encoding report no longer claims the de novo stages refuse, or that their tooling is unbuilt",
    !/entry point that refuses/.test(gmd) &&
      !/de novo tooling is unbuilt/.test(gmd) &&
      /not declared for this run/.test(gmd),
  );
  rmSync(d, { recursive: true, force: true });
  rmSync(g1, { recursive: true, force: true });
}
// ===== END de-novo deposit-stage checks =====================================

// ===== BEGIN label-order checks (owner: p3-check label lint) ================
//
// p3-check.sh's label-order lint is WARNING level and never moves a status.
// That is exactly the shape that rots unnoticed: nothing goes red when it stops
// firing, and nothing goes red when it starts firing on faithful text either.
// So both directions are pinned here — a disordered run must warn, and a GAPPED
// run must NOT, because Meng's ruling is that "real legislation goes wobbly" and
// a repealed limb is a legitimate gap. The third check pins the invariant that
// makes the lint safe to leave on: neither outcome touches status.
{
  const { scanText, scoreRun, parseLabel } = await import(
    "./lib/label-order.mjs"
  );

  // The shape the ruling produces: a label-only inert string joined to its node
  // by `...`, inside a `..` disjunction. Built as a template so the two fixtures
  // differ ONLY in their labels.
  const rule = (labels) =>
    [
      "",
      "GIVEN x IS A BOOLEAN",
      "GIVETH A BOOLEAN",
      "`r` x MEANS",
      ...labels.map((l) => `    ..  "${l}" ... x`),
      "",
    ].join("\n");

  check(
    "an out-of-order label run warns",
    (() => {
      const r = scanText(rule(["(1)", "(3)", "(2)"]), "fixture.l4");
      return (
        r.warnings.length === 1 &&
        /out of order/.test(r.warnings[0]) &&
        /\(1\)/.test(r.warnings[0])
      );
    })(),
  );

  check(
    "a GAPPED label run does not warn — a repealed limb is a legitimate gap",
    (() => {
      const r = scanText(rule(["(a)", "(c)", "(d)"]), "fixture.l4");
      return r.warnings.length === 0 && r.gaps === 1;
    })(),
  );

  // The status invariant, stated where a future editor of p3-check.sh will trip
  // over it: the lint contributes to FINDINGS nowhere. Read the phase source
  // rather than assert it about a mock, because the mock is not what ships.
  check(
    "neither the warning nor the gap count can move p3-check's status",
    (() => {
      const src = readFileSync(resolve(HERE, "phases/p3-check.sh"), "utf8");
      const block = src.slice(src.indexOf("--- 4. label order"));
      const upToStatus = block.slice(0, block.indexOf("--- 5."));
      return (
        /LABEL_WARNINGS/.test(upToStatus) &&
        /LABEL_GAPS/.test(upToStatus) &&
        !/FINDINGS=/.test(upToStatus)
      );
    })(),
  );

  // The scheme reader is the part most likely to be "improved" into crying
  // wolf. `(i)` is both the ninth letter and roman one; an inserted `(1A)` is
  // not a gap; and a run is disordered only when NO scheme orders it.
  check(
    "roman (i)(ii)(iv) reads as roman, one gap, in order",
    (() => {
      const s = scoreRun(["i", "ii", "iv"]);
      return s.scheme === "roman" && s.ordered && s.gaps === 1;
    })(),
  );
  check(
    "an inserted (1A) sits between (1) and (2) and is not a gap",
    (() => {
      const s = scoreRun(["1", "1A", "2"]);
      return s.ordered && s.gaps === 0;
    })(),
  );
  check(
    "a string carrying a rubric is not a label, so it is never ordered",
    parseLabel("(b) Educational materials. (1)") === null &&
      parseLabel("(1) To the issuer of the securities;") === null &&
      parseLabel("(2)(b)(ii)") !== null,
  );
}
// ===== END label-order checks ===============================================

// ===== toolchain discovery + the doctor =====================================
// lib/toolchain.sh fills L4/JL4_LSP_CMD from dist-newstyle; lib/doctor.mjs
// turns the probes into a front-door forecast. The properties that must hold:
// explicit env is never overridden, the own worktree beats a newer sibling,
// discovery falls back to the newest sibling, and the doctor's three exit
// codes each fire when they should. Every case controls its environment
// explicitly — none depends on what this machine happens to have built.
{
  const tc = resolve(HERE, "lib/toolchain.sh");
  const bashDiscover = (root) =>
    spawnSync(
      "bash",
      ["-c", `source '${tc}'; go_discover_tool '${root}' 'jl4-*' l4`],
      { encoding: "utf8" },
    ).stdout.trim();

  const froot = mkdtempSync(resolve(tmpdir(), "l4-go-toolchain-"));
  const mkBin = (wt, mtimeSec) => {
    const d = resolve(
      froot,
      wt,
      "dist-newstyle/build/aarch64-osx/ghc-9.10.3/jl4-0.1/x/l4/build/l4",
    );
    mkdirSync(d, { recursive: true });
    const p = resolve(d, "l4");
    writeFileSync(p, "#!/bin/sh\nexit 0\n", { mode: 0o755 });
    utimesSync(p, mtimeSec, mtimeSec);
    return p;
  };
  const older = mkBin("wt-own", 1_000_000);
  const newer = mkBin("wt-sib", 2_000_000);
  mkdirSync(resolve(froot, "wt-bare"), { recursive: true });

  check(
    "discovery prefers the worktree's OWN binary over a newer sibling",
    bashDiscover(resolve(froot, "wt-own")) === older,
  );
  check(
    "a worktree with no dist-newstyle borrows the newest sibling",
    bashDiscover(resolve(froot, "wt-bare")) === newer,
  );
  check(
    "discovery prints nothing when no candidate exists anywhere",
    (() => {
      // The root is NESTED inside its own fresh parent, so the sibling scan
      // sees only that parent's (empty) contents. Rooting the check directly
      // in the shared $TMPDIR made it flaky: any concurrent process leaving
      // a dist-newstyle one level down would satisfy "empty" discovery.
      const parent = mkdtempSync(resolve(tmpdir(), "l4-go-empty-"));
      const root = resolve(parent, "wt");
      mkdirSync(root);
      return bashDiscover(root) === "";
    })(),
  );
  check(
    "explicit L4 is never overridden by discovery",
    (() => {
      const r = spawnSync(
        "bash",
        [
          "-c",
          `source '${tc}'; go_provision_toolchain '${resolve(froot, "wt-bare")}'; printf '%s|%s' "$L4" "$GO_L4_PROVENANCE"`,
        ],
        { encoding: "utf8", env: { ...process.env, L4: "/bin/echo" } },
      );
      return r.stdout === "/bin/echo|explicit";
    })(),
  );

  const doctor = (extraEnv, stages) => {
    const env = { ...process.env, ...extraEnv };
    // A test must not inherit this shell's provisioning: unset means ABSENT.
    for (const [k, v] of Object.entries(extraEnv))
      if (v === null) delete env[k];
    return spawnSync(
      "node",
      [
        resolve(HERE, "lib/doctor.mjs"),
        "--encoding",
        "primary",
        "--stages",
        stages,
      ],
      { encoding: "utf8", env },
    );
  };
  const CLEAN = {
    L4: "/bin/ls",
    JL4_LSP_CMD: null,
    JL4_GO_SERVICE_URL: null,
    GO_L4_PROVENANCE: null,
    GO_LSP_PROVENANCE: null,
  };
  check(
    "doctor exits 2, naming discovery, when no l4 is usable",
    (() => {
      const r = doctor(
        { ...CLEAN, L4: null, GO_L4_PROVENANCE: "none" },
        "p0-preflight p3-check",
      );
      return r.status === 2 && /CANNOT RUN/.test(r.stdout);
    })(),
  );
  check(
    "doctor exits 1 and names p7-ladder + the remedy when the LSP is missing",
    (() => {
      const r = doctor(CLEAN, "p0-preflight p7-ladder");
      return (
        r.status === 1 &&
        /p7-ladder will SKIP/.test(r.stdout) &&
        /JL4_LSP_CMD/.test(r.stdout)
      );
    })(),
  );
  check(
    "doctor exits 0 over stages with no environmental wants",
    doctor(CLEAN, "p0-preflight p3-check p6-tests p9-report").status === 0,
  );
  check(
    "doctor counts the MCP deploy half as not-whole (exit 1), zip half stated",
    (() => {
      const r = doctor(CLEAN, "p0-preflight p7-mcp");
      return r.status === 1 && /zip is still built/.test(r.stdout);
    })(),
  );
  check(
    "doctor forecasts the GATE abort for a non-loopback service URL",
    (() => {
      const r = doctor(
        { ...CLEAN, JL4_GO_SERVICE_URL: "http://192.168.1.10:8080" },
        "p0-preflight p7-mcp",
      );
      return r.status === 1 && /VERDICT: GATE/.test(r.stdout);
    })(),
  );
  check(
    "a loopback service URL is not a finding",
    (() => {
      const r = doctor(
        { ...CLEAN, JL4_GO_SERVICE_URL: "http://127.0.0.1:8080" },
        "p0-preflight p7-mcp",
      );
      return r.status === 0;
    })(),
  );
  check(
    "a set-but-stale JL4_LSP_CMD is a finding, same scrutiny as L4",
    (() => {
      const r = doctor(
        { ...CLEAN, JL4_LSP_CMD: "/nonexistent/jl4-lsp" },
        "p0-preflight p7-ladder",
      );
      return r.status === 1 && /not executable/.test(r.stdout);
    })(),
  );
}
// ===== END toolchain discovery + the doctor =================================

// ===== gc retention is per subject ==========================================
//
// `gc` is the only destructive command in the driver, and it had no test at
// all. What it deletes is not scratch: cross-run replay (SPEC §R7) satisfies a
// stage from a receipt in an EARLIER run, so the run store is the input to
// "tweak one exporter and re-measure cheaply". Collecting it wrongly does not
// fail loudly — it just makes the next run do all the work again, which reads
// as slowness rather than as data loss.
//
// The specific bug these checks pin: retention claimed "the latest run per
// subject" in a comment and implemented `sort | tail -$KEEP` over the whole
// store. One subject, no difference. Two subjects and a burst of runs on the
// newer one, and every run of the older subject is inside the window that gets
// deleted. The fixture below is that exact shape.
process.stdout.write("\n-- gc retention --\n");
{
  const root = mkdtempSync(resolve(tmpdir(), "l4-go-gc-"));
  const mkRun = (id, subject, gated = false) => {
    const d = resolve(root, id);
    mkdirSync(d, { recursive: true });
    const j = resolve(d, "journal.ndjson");
    // `subject: undefined` is dropped by JSON.stringify, which is exactly the
    // shape of a pre-subject-field run_begin — so this fixture reproduces the
    // real unattributed runs rather than simulating them.
    append(j, {
      kind: "run_begin",
      run_id: id,
      encoding: "primary",
      subject: subject ?? undefined,
      repo_head: "abc",
      tree_state: "clean",
      fixed_now: "2025-01-31T00:00:00Z",
      declared_stages: ["p6-tests"],
    });
    if (gated)
      append(j, { kind: "gate", gate: "HG1", state: "satisfied", by: "test" });
    return d;
  };

  // Newer subject dominating the sort order, older subject buried beneath it.
  mkRun("2026-01-01-aaaaaaaa-001", "old-subject", true); // gated, oldest
  mkRun("2026-01-02-aaaaaaaa-001", "old-subject");
  mkRun("2026-01-03-aaaaaaaa-001", "old-subject");
  mkRun("2026-01-04-nnnnnnnn-001", null); // unattributed
  for (let i = 1; i <= 8; i++)
    mkRun(`2026-02-${String(i).padStart(2, "0")}-bbbbbbbb-001`, "new-subject");

  const before = readdirSync(root).sort();
  check("gc fixture has 12 runs before collection", before.length === 12);

  const r = spawnSync("bash", [resolve(HERE, "go.sh"), "gc", "--keep", "2"], {
    env: { ...process.env, L4_GO_RUNDIR: root },
    encoding: "utf8",
  });
  check("gc exits 0", r.status === 0);

  const kept = new Set(readdirSync(root));
  check(
    "gc keeps the newest --keep runs of the DOMINANT subject",
    kept.has("2026-02-08-bbbbbbbb-001") && kept.has("2026-02-07-bbbbbbbb-001"),
  );
  check(
    "gc collects the dominant subject's runs beyond the window",
    !kept.has("2026-02-01-bbbbbbbb-001"),
  );
  // The regression proper. Under global `tail -$KEEP` every one of these sorts
  // below eight newer runs and is deleted, taking the older subject's entire
  // replay corpus with it.
  check(
    "gc keeps the newest --keep runs of the BURIED subject",
    kept.has("2026-01-03-aaaaaaaa-001") && kept.has("2026-01-02-aaaaaaaa-001"),
  );
  check(
    "a granted gate is retained even outside its subject's window",
    kept.has("2026-01-01-aaaaaaaa-001"),
  );
  check(
    "an unattributed run gets its own window, not a discard",
    kept.has("2026-01-04-nnnnnnnn-001"),
  );
  check(
    "gc says per subject, so the line cannot drift from the rule again",
    /latest 2 per subject/.test(r.stdout),
  );
}
// ===== END gc retention =====================================================

// ===== run resolution is subject-aware ======================================
//
// `status` and `verify` read a journal and check it, so they need no subject --
// but they ACCEPT --subject, and a flag that is accepted and unread is a silent
// wrong answer: `go.sh status --subject regcf` answering with sg-succession's
// newest run produces a completely normal-looking report about a different body
// of law. These pin the three outcomes.
process.stdout.write("\n-- run resolution --\n");
{
  const root = mkdtempSync(resolve(tmpdir(), "l4-go-resolve-"));
  const mk = (id, subject) => {
    const d = resolve(root, id);
    mkdirSync(d, { recursive: true });
    writeFileSync(
      resolve(d, "journal.ndjson"),
      JSON.stringify({ kind: "run_begin", run_id: id, subject }) + "\n",
    );
  };
  // regcf is OLDER, so a subject-blind resolver returns sg-succession for both.
  mk("2026-01-01-aaaaaaaa-001", "regcf");
  mk("2026-02-01-bbbbbbbb-001", "sg-succession");

  const go = (args) =>
    spawnSync("bash", [resolve(HERE, "go.sh"), ...args], {
      env: { ...process.env, L4_GO_RUNDIR: root },
      encoding: "utf8",
    });

  check(
    "status with no --subject resolves the newest run of any subject",
    /2026-02-01-bbbbbbbb-001/.test(go(["status"]).stdout),
  );
  check(
    "status --subject resolves the newest run OF THAT SUBJECT",
    /2026-01-01-aaaaaaaa-001/.test(go(["status", "--subject", "regcf"]).stdout),
  );

  // The refusal has to survive a command substitution. resolve_run refuses with
  // `exit 2`, which inside `$(...)` exits only the subshell -- so the driver
  // used to print the right diagnosis and then hand verify-run.mjs an empty
  // argument, producing a `usage:` line about another script under the wrong
  // exit code.
  const empty = mkdtempSync(resolve(tmpdir(), "l4-go-empty-"));
  const r = spawnSync("bash", [resolve(HERE, "go.sh"), "status"], {
    env: { ...process.env, L4_GO_RUNDIR: empty },
    encoding: "utf8",
  });
  check("an empty run store refuses with exit 2", r.status === 2);
  check(
    "the refusal is not followed by verify-run.mjs's usage line",
    !/usage: verify-run\.mjs/.test(r.stdout + r.stderr),
  );
}
// ===== END run resolution ===================================================

// ===== new-subject and the unwritten encoding ===============================
//
// R12: until encoding.state existed, registering a body of law required having
// already encoded it -- `main` was mandatory AND had to exist -- so the FIRST
// encoding had no home and `new-subject` could not exist.
//
// The risk in fixing that is turning a mistyped path into a silent skip, which
// is the exact failure subject.mjs's own "EXPLICIT DECLARATION, not directory
// discovery" comment refuses. So the declaration is checked in BOTH directions,
// and these tests pin both, plus the property that makes registering-before-
// encoding safe rather than merely possible: the gate digest is taken over the
// absent path, so depositing the first module MOVES it and re-opens HG1.
process.stdout.write("\n-- new-subject / unwritten encoding --\n");
{
  const subjectsDir = resolve(HERE, "subjects");
  const id = "selftest-unwritten";
  const dir = resolve(subjectsDir, id);
  const encRel = `jl4/examples/legal/${id}/${id}.l4`;
  const encAbs = resolve(REPO, encRel);

  const rmAll = () => {
    rmSync(dir, { recursive: true, force: true });
    rmSync(dirname(encAbs), { recursive: true, force: true });
  };
  rmAll();

  const go = (args) =>
    spawnSync("bash", [resolve(HERE, "go.sh"), ...args], { encoding: "utf8" });

  const made = go([
    "new-subject",
    id,
    "--citation",
    "Selftest Act 1867",
    "--source-url",
    "https://example.invalid/selftest",
  ]);
  check("new-subject exits 0", made.status === 0);
  check(
    "new-subject writes all four sidecar files",
    ["subject.json", "pins.json", "known-defects.json", "NOTES.md"].every((f) =>
      existsSync(resolve(dir, f)),
    ),
  );
  check(
    "new-subject does NOT create the encoding -- that would falsify the state it just declared",
    !existsSync(encAbs),
  );

  // The measurement files must claim nothing. A scaffolded pins.json carrying
  // enumerations copied from another subject would be a measurement nobody
  // took, and it would be believed, because a file that looks measured is not
  // distinguishable from one that is.
  const pins = JSON.parse(readFileSync(resolve(dir, "pins.json"), "utf8"));
  check(
    "scaffolded pins.json asserts no measured value",
    Object.keys(pins).every((k) => k.startsWith("_")),
  );
  check(
    "scaffolded pins.json says it is not measured",
    /NOT MEASURED/.test(JSON.stringify(pins)),
  );
  const defects = JSON.parse(
    readFileSync(resolve(dir, "known-defects.json"), "utf8"),
  );
  check(
    "scaffolded known-defects.json declares no group",
    Object.keys(defects).every((k) => k.startsWith("_")),
  );

  // It is a real subject immediately: that is the whole point of R12.
  const planned = go(["plan", "--subject", id, "--encoding", "primary"]);
  check("the scaffolded subject plans at once", planned.status === 0);
  check(
    "the plan says the encoding is unwritten rather than leaving it to be inferred",
    /encoding\.state "unwritten"/.test(planned.stdout),
  );
  const digestAbsent = (planned.stdout.match(/sha256:[0-9a-f]{64}/) || [])[0];
  check("the plan still shows a gate digest", Boolean(digestAbsent));

  // Direction two: once the file exists, the declaration is false, and a false
  // declaration must not survive. This is what stops the state key from rotting.
  mkdirSync(dirname(encAbs), { recursive: true });
  writeFileSync(encAbs, "§ `Selftest`\n");
  const stale = go(["plan", "--subject", id, "--encoding", "primary"]);
  check(
    "a written encoding under an 'unwritten' sidecar is refused",
    stale.status !== 0,
  );
  check(
    "the refusal names the one-line edit that repairs it",
    /Set encoding\.state to "written"/.test(stale.stderr),
  );

  // Flip it, and the digest MOVES -- so an HG1 granted while the encoding did
  // not exist cannot survive the encoding arriving.
  const descPath = resolve(dir, "subject.json");
  const desc = JSON.parse(readFileSync(descPath, "utf8"));
  desc.encoding.state = "written";
  writeFileSync(descPath, JSON.stringify(desc, null, 2) + "\n");
  const written = go(["plan", "--subject", id, "--encoding", "primary"]);
  check(
    "flipping the state to written resolves the sidecar",
    written.status === 0,
  );
  const digestPresent = (written.stdout.match(/sha256:[0-9a-f]{64}/) || [])[0];
  check(
    "depositing the first encoding MOVES the gate digest, re-opening HG1",
    Boolean(digestPresent) && digestPresent !== digestAbsent,
  );
  check(
    "the written plan no longer claims the encoding is unwritten",
    !/encoding\.state "unwritten"/.test(written.stdout),
  );

  // Refusals around the scaffolder itself.
  const again = go([
    "new-subject",
    id,
    "--citation",
    "x",
    "--source-url",
    "https://example.invalid/y",
  ]);
  check(
    "new-subject refuses to overwrite an existing sidecar",
    again.status === 2,
  );
  check(
    "the overwrite refusal names the measurement files it would destroy",
    /measurement records/.test(again.stderr),
  );

  rmAll();
  check("selftest cleaned up its scaffolded subject", !existsSync(dir));
}
// ===== END new-subject ======================================================

// ===== a negative control that did not run is not a pass ====================
//
// known-defects.mjs used to dereference `g.defects.length` with no schema
// check. sg-succession's catalogue was written with `entries`/`why_empty`
// instead of `defects`/`note`, so the checker threw a TypeError and exited 1 --
// and p7-wizard's `case` handled only 4 (a control stopped reproducing) and 2
// (usage). Exit 1 matched neither, fell through, and the stage emitted its
// receipt with the negative controls SILENTLY NOT RUN.
//
// That is the exact shape of erosion this file exists to catch: not a check
// that says the wrong thing, but a check that says nothing while looking like
// it said yes. Both halves are pinned -- the checker must refuse a malformed
// group under a code the caller handles, and the caller must treat any
// undefined exit as broken.
process.stdout.write("\n-- known-defects schema --\n");
{
  const dir = mkdtempSync(resolve(tmpdir(), "l4-go-defects-"));
  const artifact = resolve(dir, "artifact.json");
  writeFileSync(artifact, JSON.stringify({ units: [] }));
  const run = (catalogue) => {
    const c = resolve(dir, "catalogue.json");
    writeFileSync(c, JSON.stringify(catalogue));
    return spawnSync(
      "node",
      [resolve(HERE, "lib/known-defects.mjs"), "wizard", artifact],
      { env: { ...process.env, GO_S_KNOWN_DEFECTS: c }, encoding: "utf8" },
    );
  };

  const wrong = run({
    wizard: { measured_on: null, entries: [], why_empty: "because" },
  });
  check(
    "a group with no 'defects' array exits 2 (usage), not 1 (crash)",
    wrong.status === 2,
  );
  check(
    "the refusal names the key that is missing",
    /no 'defects' array/.test(wrong.stderr),
  );
  check(
    "the refusal lists the keys that ARE there, so the fix is obvious",
    /entries/.test(wrong.stderr) && /why_empty/.test(wrong.stderr),
  );

  const right = run({
    wizard: { measured_on: null, note: "nothing measured", defects: [] },
  });
  check("a well-formed empty group still exits 0", right.status === 0);
  check(
    "an empty group states its reason rather than passing silently",
    /nothing measured/.test(right.stdout),
  );

  // The caller half: p7-wizard must not let an undefined exit code through.
  const wizardSrc = readFileSync(resolve(HERE, "phases/p7-wizard.sh"), "utf8");
  const caseBlock = wizardSrc.slice(
    wizardSrc.indexOf("case $DEFECT_RC in"),
    wizardSrc.indexOf("esac", wizardSrc.indexOf("case $DEFECT_RC in")),
  );
  check(
    "p7-wizard's defect case has a catch-all arm",
    /^\s*\*\)/m.test(caseBlock),
  );
  check(
    "the catch-all arm is BROKEN, not a shrug",
    /\*\)[\s\S]*go_broken/.test(caseBlock),
  );
}
// ===== END known-defects schema =============================================

// ===== a borrowed artifact may not be laundered =============================
//
// receipt.mjs states the rule for WITHIN-run replay: artifact records are
// copied verbatim, never re-hashed, because "Re-hashing would launder a file
// that changed after the original receipt was written". The CROSS-run path
// cannot copy the records -- `--artifacts-from` resolves inside the current
// journal, and a borrowed path would dangle once gc pruned the donor -- so it
// copies the FILES and records them with `--artifact`, which re-hashes. Without
// a check that is exactly the laundering the rule forbids: a donor artifact
// tampered with after its receipt reports CHANGED under `verify` in its own run
// and `matches` in the borrowing one.
//
// donor-check.mjs closes it BEFORE any file is copied, and a finding refuses the
// borrow rather than repairing it -- a donor artifact that no longer matches its
// own receipt means the receipt is not evidence, so the stage should execute.
process.stdout.write("\n-- borrowed artifacts --\n");
{
  const DC = resolve(HERE, "lib/donor-check.mjs");
  const root = mkdtempSync(resolve(tmpdir(), "l4-go-donor-"));
  const donor = resolve(root, "donor");
  mkdirSync(resolve(donor, "artifacts"), { recursive: true });

  const put = (name, content) => {
    const p = resolve(donor, "artifacts", name);
    writeFileSync(p, content);
    return { path: p, bytes: content.length, sha256: hashOf(p) };
  };
  const run = (prior) => {
    const r = spawnSync("node", [DC], {
      input: JSON.stringify(prior),
      encoding: "utf8",
    });
    return r;
  };

  const a = put("a.json", "measured\n");
  const b = put("b.txt", "also measured\n");
  const intact = { from_dir: donor, artifacts: [a, b] };
  check("an intact donor is borrowable", run(intact).status === 0);

  // The laundering case.
  writeFileSync(resolve(donor, "artifacts", "a.json"), "tampered\n");
  const tampered = run(intact);
  check(
    "a donor artifact that CHANGED refuses the borrow",
    tampered.status === 1,
  );
  check(
    "the refusal shows both hashes, so the reader can see what moved",
    /receipt: sha256:/.test(tampered.stderr) &&
      /on disk: sha256:/.test(tampered.stderr),
  );
  check("the refusal names the artifact", /a\.json/.test(tampered.stderr));

  // A donor whose file is gone is also not borrowable: the copy would silently
  // skip it and the receipt would claim an artifact it does not have.
  writeFileSync(resolve(donor, "artifacts", "a.json"), "measured\n");
  rmSync(resolve(donor, "artifacts", "b.txt"));
  const gone = run(intact);
  check("a donor artifact that is GONE refuses the borrow", gone.status === 1);
  check(
    "the refusal says the bytes cannot be produced, and from where it looked",
    /cannot be produced/.test(gone.stderr) &&
      /not in the store/.test(gone.stderr),
  );

  // The store is now a source, so a donor whose file is gone is STILL
  // borrowable when the bytes were admitted — which is the point of the store:
  // $TMPDIR reaps a run directory in two to five days and the evidence should
  // not go with it.
  {
    const store = mkdtempSync(resolve(tmpdir(), "l4-go-donorstore-"));
    const src = resolve(donor, "artifacts", "a.json");
    writeFileSync(src, "measured\n");
    const sha = hashOf(src);
    Store.put(store, src, sha, {
      subject: "s",
      stage: "p7-lts",
      rel: "a.json",
    });
    rmSync(src);
    const r = spawnSync("node", [DC], {
      input: JSON.stringify({
        from_dir: donor,
        artifacts: [
          { path: src, bytes: 9, sha256: sha, rel: "a.json", cas: sha },
        ],
      }),
      env: { ...process.env, L4_GO_STORE: store },
      encoding: "utf8",
    });
    check(
      "a donor whose run directory was reaped is still borrowable from the store",
      r.status === 0,
    );
    rmSync(store, { recursive: true, force: true });
  }

  // Basename collision: the copy flattens to basename, so two artifacts from
  // different subdirectories with the same name would overwrite each other.
  // p7-lts already writes into a state-graphs/ subdirectory.
  mkdirSync(resolve(donor, "artifacts", "sub"), { recursive: true });
  const c1 = put("g.svg", "one\n");
  const p2 = resolve(donor, "artifacts", "sub", "g.svg");
  writeFileSync(p2, "two\n");
  const collide = run({
    from_dir: donor,
    artifacts: [c1, { path: p2, bytes: 4, sha256: hashOf(p2) }],
  });
  check(
    "two artifacts sharing a basename refuse the borrow",
    collide.status === 1,
  );
  check(
    "the collision refusal explains that the copy flattens to basename",
    /flattens to basename/.test(collide.stderr),
  );

  // And the driver must actually consult it.
  const goSrc = readFileSync(resolve(HERE, "go.sh"), "utf8");
  check(
    "go.sh runs donor-check.mjs on the cross-run path",
    /donor-check\.mjs/.test(goSrc),
  );
  check(
    "a donor-check finding clears \$prior, so the stage executes instead",
    /donor-check\.mjs[\s\S]{0,400}?prior=""/.test(goSrc),
  );
}
// ===== END borrowed artifacts ===============================================

// ===== the cross-run lookup picks the LATEST execution ======================
//
// findReplayableAcrossRuns ordered candidates with readdirSync().sort()
// .reverse(). A run id is `YYYY-MM-DD-<corpus_sha8>-NNN`, so that orders by
// date, then by the CORPUS HASH, then by sequence — and a content hash's order
// carries no meaning. Within one day the greater sha8 outranked the temporally
// later run, so a stage could borrow an older receipt while a newer execution
// over byte-identical inputs sat in the store.
//
// The fixture below is that exact shape and the old code fails it: the earlier
// run's sha8 sorts ABOVE the later run's, so a lexicographic reverse picks the
// earlier one.
process.stdout.write("\n-- cross-run ordering --\n");
{
  const root = mkdtempSync(resolve(tmpdir(), "l4-go-order-"));
  const DIG = "sha256:" + "d".repeat(64);
  const mk = (id, ts, status) => {
    const d = resolve(root, id);
    mkdirSync(d, { recursive: true });
    const j = resolve(d, "journal.ndjson");
    append(j, {
      kind: "run_begin",
      run_id: id,
      ts,
      encoding: "primary",
      subject: "subj",
      repo_head: "abc",
      tree_state: "clean",
      fixed_now: "2025-01-31T00:00:00Z",
      declared_stages: ["p7-wizard"],
    });
    append(j, {
      kind: "stage_end",
      stage: "p7-wizard",
      status,
      reason: null,
      blocker: null,
      oracle: { class: "structural", because: "counted" },
      artifacts: [],
      metrics: {},
      notes: [],
      inputs_digest: DIG,
    });
    return d;
  };

  // Same day. The EARLIER run's corpus sha8 sorts lexicographically ABOVE the
  // LATER run's, which is precisely the case the old ordering got wrong.
  mk("2026-03-01-ffffffff-001", "2026-03-01T09:00:00.000Z", "DEGRADED");
  mk("2026-03-01-00000000-001", "2026-03-01T17:00:00.000Z", "PASS");

  const hit = findReplayableAcrossRuns(
    root,
    resolve(root, "current"),
    "subj",
    "p7-wizard",
    DIG,
  );
  check("the cross-run lookup finds a candidate", Boolean(hit));
  check(
    "it picks the run that began LATER, not the one whose id sorts higher",
    hit?.runId === "2026-03-01-00000000-001",
  );

  // And the rule is "most recent execution", never "best status" — so make the
  // later run the WORSE one and assert it is still chosen. A lookup that
  // preferred the PASS here would be status shopping.
  const root2 = mkdtempSync(resolve(tmpdir(), "l4-go-order2-"));
  const mk2 = (id, ts, status) => {
    const d = resolve(root2, id);
    mkdirSync(d, { recursive: true });
    const j = resolve(d, "journal.ndjson");
    append(j, {
      kind: "run_begin",
      run_id: id,
      ts,
      encoding: "primary",
      subject: "subj",
      repo_head: "abc",
      tree_state: "clean",
      fixed_now: "2025-01-31T00:00:00Z",
      declared_stages: ["p7-wizard"],
    });
    append(j, {
      kind: "stage_end",
      stage: "p7-wizard",
      status,
      reason: null,
      blocker: null,
      oracle: { class: "structural", because: "counted" },
      artifacts: [],
      metrics: {},
      notes: [],
      inputs_digest: DIG,
    });
  };
  mk2("2026-03-01-aaaaaaaa-001", "2026-03-01T09:00:00.000Z", "PASS");
  mk2("2026-03-01-bbbbbbbb-001", "2026-03-01T17:00:00.000Z", "DEGRADED");
  const hit2 = findReplayableAcrossRuns(
    root2,
    resolve(root2, "current"),
    "subj",
    "p7-wizard",
    DIG,
  );
  check(
    "the rule is most-recent-execution, NOT best-status — no status shopping",
    hit2?.record?.status === "DEGRADED",
  );

  // A journal with no readable ts must sort LAST, so a malformed run can never
  // outrank a well-formed one by accident. Written RAW, not through append():
  // append() stamps `ts: new Date().toISOString()` itself, so a fixture built
  // with it is never actually ts-less — and would in fact carry TODAY's clock,
  // outranking every dated fixture and passing this check for the wrong reason.
  const root3 = mkdtempSync(resolve(tmpdir(), "l4-go-order3-"));
  const rawRun = (id, rows) => {
    const d = resolve(root3, id);
    mkdirSync(d, { recursive: true });
    writeFileSync(
      resolve(d, "journal.ndjson"),
      rows.map((r) => JSON.stringify(r)).join("\n") + "\n",
    );
  };
  // No `ts` anywhere, and an id that sorts ABOVE the well-formed run.
  rawRun("2026-03-09-zzzzzzzz-001", [
    {
      journal_schema: 2,
      seq: 0,
      kind: "run_begin",
      run_id: "2026-03-09-zzzzzzzz-001",
      subject: "subj",
      encoding: "primary",
      declared_stages: ["p7-wizard"],
    },
    {
      journal_schema: 2,
      seq: 1,
      kind: "stage_end",
      stage: "p7-wizard",
      status: "PASS",
      reason: null,
      blocker: null,
      oracle: { class: "structural", because: "counted" },
      artifacts: [],
      metrics: {},
      notes: [],
      inputs_digest: DIG,
    },
  ]);
  rawRun("2026-03-01-aaaaaaaa-001", [
    {
      journal_schema: 2,
      seq: 0,
      ts: "2026-03-01T09:00:00.000Z",
      kind: "run_begin",
      run_id: "2026-03-01-aaaaaaaa-001",
      subject: "subj",
      encoding: "primary",
      declared_stages: ["p7-wizard"],
    },
    {
      journal_schema: 2,
      seq: 1,
      ts: "2026-03-01T09:00:01.000Z",
      kind: "stage_end",
      stage: "p7-wizard",
      status: "DEGRADED",
      reason: null,
      blocker: null,
      oracle: { class: "structural", because: "counted" },
      artifacts: [],
      metrics: {},
      notes: [],
      inputs_digest: DIG,
    },
  ]);
  const hit3 = findReplayableAcrossRuns(
    root3,
    resolve(root3, "current"),
    "subj",
    "p7-wizard",
    DIG,
  );
  check(
    "a run with no readable ts sorts last, so it cannot outrank a well-formed one",
    hit3?.runId === "2026-03-01-aaaaaaaa-001",
  );
}
// ===== END cross-run ordering ===============================================

// ===== the standard library is an input to every stage ======================
//
// THE ATTACK THIS CLOSES, measured on this tree before the fix. Every module of
// every subject opens with IMPORT prelude and IMPORT daydate (7 of 7 for
// sg-succession), so the library files are inputs to every `l4 check`, `l4 run`,
// `l4 export` and `l4 verify` the pipeline performs. They were in NO digest --
// not the gate's GO_ENCODING_FILES, not any stage's --inputs -- and the path is
// an environment variable whose caller-supplied value wins.
//
// So: copy jl4-core/libraries, change `__GEQ__` on DATE from `AT LEAST` to
// `GREATER THAN` (one word), point JL4_LIBRARY_PATH at the copy. sg-paa.l4 still
// reported 79 assertions and 0 failures, byte-identical to the baseline, while a
// date-boundary EVAL went TRUE -> FALSE. Every oracle stayed green and the
// answer moved, under a signature a human gave for something else.
//
// The driver already folded the `l4` binary's sha for exactly this reason, in a
// comment that says "the `l4` binary is an input to every stage and is declared
// by none". The reasoning was written and not applied to the second case.
process.stdout.write("\n-- the standard library --\n");
{
  const SD = resolve(HERE, "lib/stdlib-digest.mjs");
  const dig = (dir) =>
    spawnSync("node", [SD, dir], { encoding: "utf8" }).stdout.trim();

  const real = mkdtempSync(resolve(tmpdir(), "l4-go-lib-"));
  writeFileSync(
    resolve(real, "daydate.l4"),
    "`__GEQ__` MEANS Day a AT LEAST Day b\n",
  );
  writeFileSync(resolve(real, "prelude.l4"), "-- prelude\n");
  const a = dig(real);
  check(
    "a populated library directory digests",
    /^sha256:[0-9a-f]{64}$/.test(a),
  );

  // The one-word mutation.
  const mut = mkdtempSync(resolve(tmpdir(), "l4-go-libmut-"));
  writeFileSync(
    resolve(mut, "daydate.l4"),
    "`__GEQ__` MEANS Day a GREATER THAN Day b\n",
  );
  writeFileSync(resolve(mut, "prelude.l4"), "-- prelude\n");
  check("one word changed in a library moves the digest", dig(mut) !== a);

  // Content, not path: relocating an identical library must NOT invalidate a
  // replay, or every worktree would re-run everything for no reason.
  const copy = mkdtempSync(resolve(tmpdir(), "l4-go-libcopy-"));
  writeFileSync(
    resolve(copy, "daydate.l4"),
    "`__GEQ__` MEANS Day a AT LEAST Day b\n",
  );
  writeFileSync(resolve(copy, "prelude.l4"), "-- prelude\n");
  check(
    "an identical library at a different path digests the same — content, not path",
    dig(copy) === a,
  );

  // Three distinct absence states, all distinct from each other and from a
  // populated directory. "No library directory" is not the same claim as "an
  // empty one", and neither may collide with a real digest.
  const empty = mkdtempSync(resolve(tmpdir(), "l4-go-libempty-"));
  const states = [
    dig(empty),
    dig(resolve(tmpdir(), "definitely-not-here")),
    dig(""),
  ];
  check(
    "empty, absent and unset are three distinct digests",
    new Set(states).size === 3,
  );
  check("none of them collides with a populated library", !states.includes(a));

  // A file that is not a library must not move it: resolution is by basename
  // and flat, so a stray README or a subdirectory is not reachable as a library.
  writeFileSync(resolve(real, "NOTES.md"), "not a library\n");
  mkdirSync(resolve(real, "sub"), { recursive: true });
  writeFileSync(resolve(real, "sub", "other.l4"), "-- unreachable\n");
  check(
    "a non-.l4 file and a subdirectory do not move the digest",
    dig(real) === a,
  );

  // And the driver must actually fold it, into EVERY stage, beside the binary.
  const goSrc = readFileSync(resolve(HERE, "go.sh"), "utf8");
  check(
    "go.sh folds text:l4-stdlib into the per-stage digest",
    /text:l4-stdlib=/.test(goSrc),
  );
  check(
    "it is folded in the same printf as the binary, so no stage can miss one and get the other",
    /text:l4-binary=[\s\S]{0,80}text:l4-stdlib=/.test(goSrc),
  );

  // p0-preflight records it, because the gate payload's toolchain section reads
  // this receipt's metrics and what is not on the receipt is not in the document
  // a human signs.
  const p0Src = readFileSync(resolve(HERE, "phases/p0-preflight.sh"), "utf8");
  check(
    "p0-preflight records l4_stdlib_sha as a metric",
    /--metric "l4_stdlib_sha=/.test(p0Src),
  );
  const gpSrc = readFileSync(resolve(HERE, "lib/gate-payload.mjs"), "utf8");
  check(
    "the gate payload names the stdlib the answer depends on",
    /l4_stdlib_sha/.test(gpSrc),
  );
}
// ===== END the standard library =============================================

// ===== the artifact store and the blessing edge (R6 + R11) ==================
//
// Two rulings, one structure, because both need the same thing: a fact about a
// content hash that outlives the run that produced it. Measured 2026-08-20: of
// 92 run directories, 16 still hold a journal and files last two to five days.
// A blessing recorded only in a run journal has that half-life — a human
// signature expiring in under a week for reasons nobody chose.
process.stdout.write("\n-- the store and the blessing edge --\n");
{
  const mkStore = () => mkdtempSync(resolve(tmpdir(), "l4-go-store-"));
  const mkFile = (dir, name, content) => {
    const p = resolve(dir, name);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, content);
    return p;
  };

  // T-1 · the lifted manifest still IS digestSet's body.
  //
  // digestSet's serialisation names run directories (every run id carries a
  // corpus_sha8) and sits inside gate rows committed to legalese/canon. Lifting
  // it out so a digest becomes a readable document is worth doing exactly once
  // and never worth drifting: a tab moved here silently stops every existing
  // run id and gate binding from corresponding to anything.
  {
    const d = mkStore();
    const present = mkFile(d, "a.l4", "-- a\n");
    const paths = [present, resolve(d, "gone.l4"), "text:floor=3"];
    check(
      "digestSet(paths) === sha256Text(manifestText(paths)) — the lift did not drift",
      digestSet(paths) === hashText(manifestText(paths)),
    );
    const members = digestMembers(paths);
    check("digestMembers itemises every member", members.length === 3);
    check(
      "an absent member is marked absent rather than dropped",
      members.some((m) => m.absent === true && m.sha256 === null),
    );
    check(
      "a text: literal carries no hash and is still a member",
      members.some((m) => m.path === "text:floor=3" && m.sha256 === null),
    );
    check(
      "members are in manifestText's order, so covers[] and the digest agree",
      members.map((m) => m.path).join("\n") === [...paths].sort().join("\n"),
    );
    rmSync(d, { recursive: true, force: true });
  }

  // T-2 · a schema-2 journal still verifies under the schema-3 binary.
  //
  // The check this replaces compared every record against the CURRENT constant,
  // so bumping it made every journal ever written unverifiable — including the
  // ones committed to legalese/canon, silently, because nobody re-verifies an
  // old run until they need it.
  {
    const d = mkStore();
    const j = resolve(d, "journal.ndjson");
    // Written RAW at schema 2: append() stamps the current schema, so a
    // fixture built with it could never be an OLD journal.
    const rows = [
      {
        journal_schema: 2,
        seq: 0,
        kind: "run_begin",
        run_id: "r",
        subject: "s",
      },
      {
        journal_schema: 2,
        seq: 1,
        kind: "stage_end",
        stage: "p3-check",
        status: "PASS",
      },
    ];
    let prev = "sha256:" + "0".repeat(64);
    const lines = rows.map((r) => {
      const rec = { ...r, prev };
      rec.hash = hashRecord(rec);
      prev = rec.hash;
      return JSON.stringify(rec);
    });
    writeFileSync(j, lines.join("\n") + "\n");
    check(
      "a schema-2 journal verifies under the schema-3 binary",
      verify(j).ok,
    );

    // The control: one chain, two binaries, is a genuine problem.
    const mixed = resolve(d, "mixed.ndjson");
    let prev2 = "sha256:" + "0".repeat(64);
    const mrows = [
      {
        journal_schema: 2,
        seq: 0,
        kind: "run_begin",
        run_id: "r",
        subject: "s",
      },
      {
        journal_schema: 3,
        seq: 1,
        kind: "stage_end",
        stage: "p3-check",
        status: "PASS",
      },
    ];
    writeFileSync(
      mixed,
      mrows
        .map((r) => {
          const rec = { ...r, prev: prev2 };
          rec.hash = hashRecord(rec);
          prev2 = rec.hash;
          return JSON.stringify(rec);
        })
        .join("\n") + "\n",
    );
    const mv = verify(mixed);
    check("a journal mixing two schemas is REFUSED", !mv.ok);
    check(
      "and the refusal says one chain, two binaries",
      mv.problems.some((p) => /one chain, two binaries/.test(p)),
    );
    check(
      "an unknown schema in record 0 is refused too",
      (() => {
        const u = resolve(d, "u.ndjson");
        const rec = {
          journal_schema: 99,
          seq: 0,
          kind: "run_begin",
          prev: "sha256:" + "0".repeat(64),
        };
        rec.hash = hashRecord(rec);
        writeFileSync(u, JSON.stringify(rec) + "\n");
        return !verify(u).ok;
      })(),
    );
    rmSync(d, { recursive: true, force: true });
  }

  // The store proper: admit, fetch, and the subdirectory case that basename
  // flattening would have collided.
  {
    const root = mkStore();
    const work = mkStore();
    const a = mkFile(work, "state-graphs/g.dot", "digraph A {}\n");
    const b = mkFile(work, "p8-diff/g.dot", "digraph B {}\n");
    const shaA = hashOf(a);
    const shaB = hashOf(b);
    check(
      "two artifacts sharing a basename have different hashes",
      shaA !== shaB,
    );
    Store.put(root, a, shaA, {
      subject: "s",
      stage: "p7-lts",
      rel: "state-graphs/g.dot",
    });
    Store.put(root, b, shaB, {
      subject: "s",
      stage: "p8-diff",
      rel: "p8-diff/g.dot",
    });
    const outA = resolve(work, "out/state-graphs/g.dot");
    const outB = resolve(work, "out/p8-diff/g.dot");
    check(
      "both materialise",
      Store.materialise(root, shaA, outA) &&
        Store.materialise(root, shaB, outB),
    );
    check(
      "to DISTINCT destinations at their own bytes — rel, not basename",
      readFileSync(outA, "utf8") !== readFileSync(outB, "utf8"),
    );
    check(
      "materialising an object the store does not have is false, not a throw",
      Store.materialise(
        root,
        "sha256:" + "f".repeat(64),
        resolve(work, "no.dot"),
      ) === false,
    );

    // put() must never throw: a broken home directory may not turn a good legal
    // encoding run red. The refusal belongs on the serving side.
    //
    // The unwritable root is a REGULAR FILE used as a directory, which gives
    // ENOTDIR instantly on every platform. It was `/proc/nonexistent-store`,
    // which is unwritable on Linux and simply absent on macOS — and that cost
    // 48 minutes of CI: `mkdirSync("/proc/<anything>/objects", {recursive:true})`
    // does not fail on Linux, it HANGS, forever. Reproduced in a
    // node:24-bookworm container, where the probe prints "before" and never
    // returns. So the check that put() cannot throw was itself the thing that
    // wedged the suite, on a platform the author was not running.
    //
    // Pick unwritable paths that are unwritable for a PORTABLE reason.
    const notADir = mkFile(work, "not-a-dir", "i am a file\n");
    check(
      "put() over an unwritable root returns null rather than throwing",
      Store.put(notADir, a, shaA, {}) === null,
    );
    rmSync(root, { recursive: true, force: true });
    rmSync(work, { recursive: true, force: true });
  }

  // T-6 · an object produced by an ungated stage is not servable. R11's
  // operative sentence: without it, default-deny becomes default-allow the
  // first time a caller finds it inconvenient.
  {
    const root = mkStore();
    const work = mkStore();
    const f = mkFile(work, "x.json", "{}\n");
    const sha = hashOf(f);

    Store.put(root, f, sha, {
      subject: "s",
      stage: "p3-check",
      produced_under: null,
    });
    check(
      "an object admitted under no gate is NOT servable",
      Store.servability(root, sha).servable === false,
    );
    check(
      "and it says why — the producing stage was ungated",
      /ungated/.test(Store.servability(root, sha).reason ?? ""),
    );

    const waived = Store.writeBlessing(root, {
      kind: "blessing",
      subject: "s",
      gate: "HG1",
      state: "waived",
      reason: "no domain expert has read this",
      covers: [],
      signer: null,
      signature: null,
      namespace: null,
      payload_digest: null,
    });
    Store.put(root, f, sha, {
      subject: "s",
      stage: "p6-tests",
      produced_under: {
        blessing: waived.hash,
        gate: "HG1",
        state: "waived",
        reason: waived.reason,
      },
    });
    const w = Store.servability(root, sha);
    check(
      "a WAIVED grant is an edge, not an absence — it resolves",
      w.state === "waived",
    );
    check("but waived is still not servable on its own", w.servable === false);
    check(
      "and the waiver's reason travels with it",
      /no domain expert/.test(w.reason ?? ""),
    );

    const sat = Store.writeBlessing(root, {
      kind: "blessing",
      subject: "s",
      gate: "HG1",
      state: "satisfied",
      reason: null,
      covers: [{ path: "x.l4", sha256: sha, bytes: 3 }],
      signer: "someone SHA256:abc",
      signature: "c2ln",
      namespace: "l4-go-gate",
      payload_digest: "sha256:" + "1".repeat(64),
    });
    Store.put(root, f, sha, {
      subject: "s",
      stage: "p6-tests",
      produced_under: { blessing: sat.hash, gate: "HG1", state: "satisfied" },
    });
    check(
      "one satisfied admission makes the BYTES servable, whichever run produced them",
      Store.servability(root, sha).servable === true,
    );
    check(
      "an object the store never saw is unknown, not servable",
      Store.servability(root, "sha256:" + "e".repeat(64)).servable === false,
    );
    rmSync(root, { recursive: true, force: true });
    rmSync(work, { recursive: true, force: true });
  }

  // T-8 · a blessing survives the deletion of the run that granted it.
  // INVARIANT I8. Today the only record of a grant lives in $TMPDIR, and gc
  // keeps only `satisfied` runs while every run in the store is `waived`.
  {
    const root = mkStore();
    const runDir = mkStore();
    writeFileSync(resolve(runDir, "journal.ndjson"), "{}\n");
    const rec = Store.writeBlessing(root, {
      kind: "blessing",
      subject: "sg-succession",
      gate: "HG1",
      state: "satisfied",
      reason: null,
      covers: [
        {
          path: "jl4/examples/legal/x/a.l4",
          sha256: "sha256:" + "a".repeat(64),
          bytes: 10,
        },
        {
          path: "jl4/examples/legal/x/b.l4",
          sha256: "sha256:" + "b".repeat(64),
          bytes: 20,
        },
      ],
      signer: "expert@example.invalid SHA256:Zz",
      signature: "c2lnbmF0dXJl",
      namespace: "l4-go-gate",
      payload_digest: "sha256:" + "2".repeat(64),
      granted_in_run: "2026-08-20-aaaaaaaa-001",
    });
    rmSync(runDir, { recursive: true, force: true });
    const back = Store.readBlessings(root).find((b) => b.hash === rec.hash);
    check(
      "a blessing outlives the run directory that granted it",
      Boolean(back),
    );
    check(
      "it still names the signer",
      /expert@example/.test(back?.signer ?? ""),
    );
    check(
      "it still carries the signature bytes, not a path into the run dir",
      back?.signature === "c2lnbmF0dXJl",
    );
    check(
      "it still itemises every covers[] member",
      back?.covers?.length === 2,
    );
    check("the ledger verifies", Store.verifyBlessings(root).ok);
    rmSync(root, { recursive: true, force: true });
  }

  // A ledger record that claims more than it carries. Gate rows bypass
  // checkReceipt today, so a `satisfied` with a null signature is written
  // without complaint — disposable in a run directory, permanent in a ledger.
  {
    const ok = Store.checkClaim({
      gate: "HG1",
      state: "satisfied",
      signature: "x",
      signer: "y",
      namespace: "l4-go-gate",
      payload_digest: "sha256:z",
      covers: [],
    });
    check("a well-formed satisfied claim passes checkClaim", ok.ok);
    check(
      "a satisfied claim with no signature is refused",
      !Store.checkClaim({ gate: "HG1", state: "satisfied", covers: [] }).ok,
    );
    check(
      "a waived claim with no reason is refused",
      !Store.checkClaim({ gate: "HG1", state: "waived", covers: [] }).ok,
    );
    const hg2 = Store.checkClaim({
      gate: "HG2",
      state: "waived",
      reason: "r",
      covers: [],
    });
    check(
      "a WAIVED HG2 is refused — unwaivability moves into the writer",
      !hg2.ok,
    );
    check(
      "and the refusal says a durable one could never be withdrawn",
      hg2.problems.some((p) => /never be withdrawn/.test(p)),
    );
    check(
      "a claim with no covers[] is refused",
      !Store.checkClaim({ gate: "HG1", state: "waived", reason: "r" }).ok,
    );
  }

  // The two structural rules the design rests on, asserted over the source so
  // they cannot be undone by a well-meaning edit.
  {
    const src = readFileSync(resolve(HERE, "lib/store.mjs"), "utf8");
    check(
      "writeBlessing has no CLI verb — receipt.mjs stays the only writer of a claim",
      !/process\.argv/.test(src),
    );
    check(
      "the serving predicate is written ONCE and exported",
      (src.match(/export function servability/g) || []).length === 1,
    );
  }
}
// ===== END the store and the blessing edge ==================================

// ===== artifacts flow THROUGH the store (R6, step 2) ========================
process.stdout.write("\n-- artifacts through the store --\n");
{
  const RECEIPT = resolve(HERE, "lib/receipt.mjs");
  const DIG = "sha256:" + "a".repeat(64);
  const PRIOR = "sha256:" + "b".repeat(64);

  const mkRun = (store, id) => {
    const d = mkdtempSync(resolve(tmpdir(), "l4-go-run-"));
    mkdirSync(resolve(d, "artifacts"), { recursive: true });
    spawnSync(
      "node",
      [
        RECEIPT,
        "run-begin",
        "--run",
        d,
        "--run-id",
        id,
        "--encoding",
        "primary",
        "--subject",
        "s",
        "--repo-head",
        "abc",
        "--tree-state",
        "clean",
        "--fixed-now",
        "2025-01-31T00:00:00Z",
        "--declared-stages",
        "p7-lts",
      ],
      { env: { ...process.env, L4_GO_STORE: store }, encoding: "utf8" },
    );
    return d;
  };
  const lastStageEnd = (runDir) =>
    read(resolve(runDir, "journal.ndjson"))
      .filter((r) => r.kind === "stage_end")
      .at(-1);

  const store = mkdtempSync(resolve(tmpdir(), "l4-go-s2-"));
  const donor = mkRun(store, "r1");

  // Produce, in a SUBDIRECTORY — the shape the old basename flattening broke.
  const art = resolve(donor, "artifacts", "state-graphs", "g.dot");
  mkdirSync(dirname(art), { recursive: true });
  writeFileSync(art, "digraph {}\n");
  const produce = spawnSync(
    "node",
    [
      RECEIPT,
      "stage-end",
      "--run",
      donor,
      "--stage",
      "p7-lts",
      "--status",
      "PASS",
      "--oracle-cmd",
      "dot",
      "--oracle-exit",
      "0",
      "--oracle-class",
      "structural",
      "--oracle-because",
      "counted",
      "--artifact",
      art,
      "--inputs-digest",
      DIG,
    ],
    { env: { ...process.env, L4_GO_STORE: store }, encoding: "utf8" },
  );
  check("producing a receipt with an artifact succeeds", produce.status === 0);
  const donorRec = lastStageEnd(donor);
  check(
    "the record carries `rel`, subdirectory included",
    donorRec?.artifacts?.[0]?.rel === "state-graphs/g.dot",
  );
  check(
    "and `cas`, the place the bytes can be re-fetched",
    donorRec?.artifacts?.[0]?.cas === donorRec?.artifacts?.[0]?.sha256,
  );
  check(
    "the bytes were admitted to the store",
    Store.has(store, donorRec.artifacts[0].cas),
  );

  // Borrow into a fresh run WITH THE DONOR DIRECTORY DELETED. This is R6's
  // payoff: $TMPDIR reaps a run in two to five days and the evidence stays.
  const borrower = mkRun(store, "r2");
  const donorsJson = resolve(borrower, "donors.json");
  writeFileSync(donorsJson, JSON.stringify(donorRec.artifacts));
  rmSync(donor, { recursive: true, force: true });
  const borrow = spawnSync(
    "node",
    [
      RECEIPT,
      "stage-end",
      "--run",
      borrower,
      "--stage",
      "p7-lts",
      "--status",
      "PASS",
      "--inputs-digest",
      DIG,
      "--replayed-from",
      PRIOR,
      "--replayed-from-run",
      "r1",
      "--artifacts-json",
      donorsJson,
    ],
    { env: { ...process.env, L4_GO_STORE: store }, encoding: "utf8" },
  );
  check(
    "a borrow succeeds after the donor run was deleted",
    borrow.status === 0,
  );
  const borrowed = lastStageEnd(borrower);
  check(
    "the artifact materialised into the borrower's own subdirectory",
    existsSync(resolve(borrower, "artifacts", "state-graphs", "g.dot")),
  );
  check(
    "the recorded sha256 is the DONOR'S, verbatim — never re-derived from the copy",
    borrowed?.artifacts?.[0]?.sha256 === donorRec.artifacts[0].sha256,
  );

  // T-4 · the laundering assertion. A donor record whose hash does not match
  // what lands is refused, not repaired.
  {
    const b2 = mkRun(store, "r3");
    const bad = resolve(b2, "bad.json");
    writeFileSync(
      bad,
      JSON.stringify([
        {
          path: resolve(b2, "artifacts", "z.dot"),
          bytes: 3,
          sha256: "sha256:" + "9".repeat(64),
          rel: "z.dot",
          cas: null,
        },
      ]),
    );
    writeFileSync(resolve(b2, "artifacts", "z.dot"), "tampered\n");
    const r = spawnSync(
      "node",
      [
        RECEIPT,
        "stage-end",
        "--run",
        b2,
        "--stage",
        "p7-lts",
        "--status",
        "PASS",
        "--inputs-digest",
        DIG,
        "--replayed-from",
        PRIOR,
        "--artifacts-json",
        bad,
      ],
      { env: { ...process.env, L4_GO_STORE: store }, encoding: "utf8" },
    );
    check(
      "a materialised file that does not match the donor is REFUSED",
      r.status === 4,
    );
    check(
      "the refusal shows both hashes",
      /receipt: sha256:/.test(r.stderr) && /on disk: sha256:/.test(r.stderr),
    );
    rmSync(b2, { recursive: true, force: true });
  }

  // T-5 · a replayed PASS naming no artifact. The guard it restores was
  // vacuous — `!r.replayed_from` inside a branch where `replayed` is true is
  // always false — so this receipt was accepted and `verify` called the
  // the run COMPLETE.
  {
    const b3 = mkRun(store, "r4");
    const empty = resolve(b3, "none.json");
    writeFileSync(empty, "[]");
    const r = spawnSync(
      "node",
      [
        RECEIPT,
        "stage-end",
        "--run",
        b3,
        "--stage",
        "p7-lts",
        "--status",
        "PASS",
        "--inputs-digest",
        DIG,
        "--replayed-from",
        PRIOR,
        "--artifacts-json",
        empty,
      ],
      { env: { ...process.env, L4_GO_STORE: store }, encoding: "utf8" },
    );
    check("a replayed PASS naming NO artifact is refused", r.status === 4);
    check(
      "and the refusal explains that the receipt it replays named one",
      /naming no artifact/.test(r.stdout + r.stderr),
    );
    rmSync(b3, { recursive: true, force: true });
  }

  // A pre-store donor — no `rel`, no `cas` — must still be borrowable, and the
  // bytes get back-filled so the NEXT borrow comes from the store.
  {
    const legacyDonor = mkdtempSync(resolve(tmpdir(), "l4-go-legacy-"));
    mkdirSync(resolve(legacyDonor, "artifacts"), { recursive: true });
    const lf = resolve(legacyDonor, "artifacts", "old.json");
    writeFileSync(lf, "legacy\n");
    const lsha = hashOf(lf);
    const b4 = mkRun(store, "r5");
    const lj = resolve(b4, "legacy.json");
    writeFileSync(lj, JSON.stringify([{ path: lf, bytes: 7, sha256: lsha }]));
    const r = spawnSync(
      "node",
      [
        RECEIPT,
        "stage-end",
        "--run",
        b4,
        "--stage",
        "p7-lts",
        "--status",
        "PASS",
        "--inputs-digest",
        DIG,
        "--replayed-from",
        PRIOR,
        "--replayed-from-run",
        "r0",
        "--donor-dir",
        legacyDonor,
        "--artifacts-json",
        lj,
      ],
      { env: { ...process.env, L4_GO_STORE: store }, encoding: "utf8" },
    );
    check(
      "a PRE-STORE donor (no rel, no cas) is still borrowable",
      r.status === 0,
    );
    check(
      "and its bytes are back-filled, so the store heals itself from old runs",
      Store.has(store, lsha),
    );
    rmSync(legacyDonor, { recursive: true, force: true });
    rmSync(b4, { recursive: true, force: true });
  }

  rmSync(borrower, { recursive: true, force: true });
  rmSync(store, { recursive: true, force: true });
}
// ===== END artifacts through the store ======================================

// ===== the blessing edge (R11, step 3) ======================================
process.stdout.write("\n-- the blessing edge --\n");
{
  const RECEIPT = resolve(HERE, "lib/receipt.mjs");
  const DIG = "sha256:" + "a".repeat(64);
  const CORPUS = "sha256:" + "9".repeat(64);

  const mkRun = (store, gated) => {
    const d = mkdtempSync(resolve(tmpdir(), "l4-go-bless-"));
    mkdirSync(resolve(d, "artifacts"), { recursive: true });
    writeFileSync(resolve(d, "artifacts", "a.txt"), "measured\n");
    writeFileSync(
      resolve(d, ".corpus-members.json"),
      JSON.stringify([
        {
          path: resolve(HERE, "go.sh"),
          sha256: hashOf(resolve(HERE, "go.sh")),
          bytes: 1,
        },
      ]),
    );
    spawnSync(
      "node",
      [
        RECEIPT,
        "run-begin",
        "--run",
        d,
        "--run-id",
        "r",
        "--encoding",
        "primary",
        "--subject",
        "sg",
        "--repo-head",
        "abc",
        "--tree-state",
        "clean",
        "--fixed-now",
        "2025-01-31T00:00:00Z",
        "--declared-stages",
        "p6-tests",
        "--gated-stages",
        JSON.stringify(gated),
      ],
      { env: { ...process.env, L4_GO_STORE: store }, encoding: "utf8" },
    );
    return d;
  };
  const grant = (store, runDir, state, extra = []) =>
    spawnSync(
      "node",
      [
        RECEIPT,
        "gate",
        "--run",
        runDir,
        "--gate",
        "HG1",
        "--state",
        state,
        "--subject",
        "sg",
        "--run-id",
        "r",
        "--covers-from",
        resolve(runDir, ".corpus-members.json"),
        "--corpus-digest",
        CORPUS,
        ...extra,
      ],
      { env: { ...process.env, L4_GO_STORE: store }, encoding: "utf8" },
    );
  const stage = (store, runDir, status, extra = []) =>
    spawnSync(
      "node",
      [
        RECEIPT,
        "stage-end",
        "--run",
        runDir,
        "--stage",
        "p6-tests",
        "--status",
        status,
        "--inputs-digest",
        DIG,
        ...extra,
      ],
      { env: { ...process.env, L4_GO_STORE: store }, encoding: "utf8" },
    );
  const lastEnd = (runDir) =>
    read(resolve(runDir, "journal.ndjson"))
      .filter((r) => r.kind === "stage_end")
      .at(-1);
  const GATED = { HG1: ["p6-tests"], HG2: ["p10-publish"] };
  const OK = [
    "--oracle-cmd",
    "t",
    "--oracle-exit",
    "0",
    "--oracle-class",
    "execution",
    "--oracle-because",
    "m",
  ];

  // A waiver reaches the ledger, and OUTLIVES the run it was granted in.
  {
    const store = mkdtempSync(resolve(tmpdir(), "l4-go-l1-"));
    const run = mkRun(store, GATED);
    const g = grant(store, run, "waived", [
      "--reason",
      "no domain expert has read this",
    ]);
    check("a waiver is recorded", g.status === 0);
    const row = read(resolve(run, "journal.ndjson")).find(
      (r) => r.kind === "gate",
    );
    check("the gate row names its ledger record", Boolean(row?.blessing));
    rmSync(run, { recursive: true, force: true });
    const led = Store.readBlessings(store);
    check("the blessing outlives the run directory", led.length === 1);
    check(
      "it carries the waiver's reason",
      /no domain expert/.test(led[0].reason ?? ""),
    );
    check("it itemises the corpus it covers", led[0].covers.length === 1);
    check(
      "the reviewed bytes are fetchable from the store, not merely named",
      Store.has(store, led[0].covers[0].sha256),
    );
    check("the ledger verifies", Store.verifyBlessings(store).ok);
    rmSync(store, { recursive: true, force: true });
  }

  // RULE 7, three directions.
  {
    const store = mkdtempSync(resolve(tmpdir(), "l4-go-l2-"));

    const noGrant = mkRun(store, GATED);
    const r1 = stage(store, noGrant, "PASS", [
      ...OK,
      "--artifact",
      resolve(noGrant, "artifacts", "a.txt"),
    ]);
    check("a GATED stage with no grant may not write PASS", r1.status === 4);
    check(
      "and the refusal says BROKEN is the only status left to it",
      /no status but BROKEN/.test(r1.stdout + r1.stderr),
    );

    const broken = mkRun(store, GATED);
    const r2 = stage(store, broken, "BROKEN", [
      "--reason",
      "the compiler is missing",
    ]);
    check(
      "but it may still report BROKEN — a stage must be able to say it could not run",
      r2.status === 0,
    );

    const ungated = mkRun(store, { HG1: [], HG2: [] });
    const r3 = stage(store, ungated, "PASS", [
      ...OK,
      "--artifact",
      resolve(ungated, "artifacts", "a.txt"),
    ]);
    check("an UNGATED stage is unaffected by Rule 7", r3.status === 0);
    check(
      "and carries no blessing, because there is no gate to carry",
      lastEnd(ungated)?.produced_under === null,
    );

    const waived = mkRun(store, GATED);
    grant(store, waived, "waived", ["--reason", "not reviewed"]);
    const r4 = stage(store, waived, "PASS", [
      ...OK,
      "--artifact",
      resolve(waived, "artifacts", "a.txt"),
    ]);
    check(
      "with a waiver on the record the stage may write PASS",
      r4.status === 0,
    );
    const pu = lastEnd(waived)?.produced_under;
    check(
      "and the receipt is STAMPED with what it ran under",
      pu?.state === "waived",
    );
    check(
      "naming the gate, the ledger record and the corpus",
      Boolean(pu?.gate && pu?.blessing && pu?.corpus_digest),
    );

    // THE DERIVATION IS NOT A FLAG. receipt.mjs is the only writer of a status
    // precisely so no caller can assert one it did not earn; a --blessing flag
    // would re-open that for any phase script.
    const src = readFileSync(RECEIPT, "utf8");
    check(
      "produced_under is DERIVED from the journal, never accepted as a CLI flag",
      !/args\.blessing/.test(src) && /gated_stages/.test(src),
    );
    rmSync(store, { recursive: true, force: true });
  }

  // checkClaim guards the ledger the way checkReceipt guards a receipt.
  {
    const store = mkdtempSync(resolve(tmpdir(), "l4-go-l3-"));
    const run = mkRun(store, GATED);
    const r = grant(store, run, "waived"); // no --reason
    check("a waiver with no reason is refused at the writer", r.status === 4);
    check("and says a ledger record is permanent", /permanent/.test(r.stderr));
    const hg2 = spawnSync(
      "node",
      [
        RECEIPT,
        "gate",
        "--run",
        run,
        "--gate",
        "HG2",
        "--state",
        "waived",
        "--subject",
        "sg",
        "--run-id",
        "r",
        "--reason",
        "shipping anyway",
        "--covers-from",
        resolve(run, ".corpus-members.json"),
        "--corpus-digest",
        CORPUS,
      ],
      { env: { ...process.env, L4_GO_STORE: store }, encoding: "utf8" },
    );
    check(
      "a WAIVED HG2 is refused by the writer, not merely by go.sh's prose",
      hg2.status === 4,
    );
    check(
      "no blessing was written for the refused claim",
      Store.readBlessings(store).length === 0,
    );
    rmSync(store, { recursive: true, force: true });
  }

  // go_require_blessing — the gate over the ACT, which happens before any
  // receipt exists and which a receipt-level rule therefore cannot see.
  {
    const store = mkdtempSync(resolve(tmpdir(), "l4-go-l4-"));
    const callPrelude = (runDir) =>
      spawnSync(
        "bash",
        [
          "-c",
          'source etc/go/lib/phase-prelude.sh; go_require_blessing "deploying" && echo ALLOWED',
        ],
        {
          cwd: REPO,
          env: {
            ...process.env,
            L4_GO_STORE: store,
            GO_ROOT: REPO,
            GO_RUN: runDir,
            GO_STAGE: "p6-tests",
            GO_OUT: resolve(runDir, "artifacts"),
          },
          encoding: "utf8",
        },
      );

    const noGrant = mkRun(store, GATED);
    const a = callPrelude(noGrant);
    check(
      "an outward-facing act with no grant is REFUSED",
      !/ALLOWED/.test(a.stdout),
    );
    check(
      "and the refusal says the act may not precede the gate",
      /may not precede the human gate/.test(a.stdout + a.stderr),
    );

    const waived = mkRun(store, GATED);
    grant(store, waived, "waived", ["--reason", "not reviewed"]);
    const b = callPrelude(waived);
    check("a waiver lets the act proceed", /ALLOWED/.test(b.stdout));
    check(
      "but the waiver's reason is PRINTED, so nobody deploys under one unseen",
      /WAIVED HG1 — not reviewed/.test(b.stdout + b.stderr),
    );

    const ungated = mkRun(store, { HG1: [], HG2: [] });
    const c = callPrelude(ungated);
    check(
      "a stage that performs an outward-facing act and is NOT gated is itself a defect",
      !/ALLOWED/.test(c.stdout) &&
        /must sit behind a gate/.test(c.stdout + c.stderr),
    );
    rmSync(store, { recursive: true, force: true });
  }

  // The wiring: the one live serving act calls it, before the first POST.
  {
    const mcp = readFileSync(resolve(HERE, "phases/p7-mcp.sh"), "utf8");
    check("p7-mcp requires a blessing", /go_require_blessing/.test(mcp));
    check(
      // BEFORE the first mutating request, not merely somewhere in the file:
      // the deployment exists the moment the POST returns, so a check after it
      // is a check about something that has already happened.
      "and does so BEFORE the first -X POST",
      mcp.indexOf("go_require_blessing") > 0 &&
        mcp.indexOf("go_require_blessing") < mcp.indexOf("-X POST"),
    );
  }
}
// ===== END the blessing edge ================================================

// ===== the store's command surface (R6's deliverable) =======================
//
// `diff` is what R6 actually asked for: "the difference between two runs of the
// same phase is cheap to compute and is itself the product". `cat` is R11's
// operative sentence, as an exit code.
process.stdout.write("\n-- store verbs --\n");
{
  const CLI = resolve(HERE, "lib/store-cli.mjs");
  const store = mkdtempSync(resolve(tmpdir(), "l4-go-cli-"));
  const work = mkdtempSync(resolve(tmpdir(), "l4-go-cliw-"));
  const DIG = "sha256:" + "a".repeat(64);
  const mk = (n, c) => {
    const f = resolve(work, n);
    writeFileSync(f, c);
    return f;
  };
  const run = (...args) =>
    spawnSync("node", [CLI, ...args], {
      env: { ...process.env, L4_GO_STORE: store },
      encoding: "utf8",
    });

  // Same witness key, two different outputs — a producer that did not converge.
  const a = mk("a.json", '{"tools":3}\n');
  const b = mk("b.json", '{"tools":4}\n');
  Store.put(store, a, hashOf(a), {
    subject: "sg",
    stage: "p7-mcp",
    rel: "tools.json",
    inputs_digest: DIG,
    run_id: "run-A",
  });
  Store.put(store, b, hashOf(b), {
    subject: "sg",
    stage: "p7-mcp",
    rel: "tools.json",
    inputs_digest: DIG,
    run_id: "run-B",
  });
  // Same key, same output — converged, and must stay silent.
  const c = mk("c.txt", "stable\n");
  Store.put(store, c, hashOf(c), {
    subject: "sg",
    stage: "p3-check",
    rel: "log.txt",
    inputs_digest: DIG,
    run_id: "run-A",
  });
  Store.put(store, c, hashOf(c), {
    subject: "sg",
    stage: "p3-check",
    rel: "log.txt",
    inputs_digest: DIG,
    run_id: "run-B",
  });

  const d1 = run("diff");
  check("store diff exits 1 when a witness key diverges", d1.status === 1);
  check("it names the divergent stage", /DIVERGENT {2}p7-mcp/.test(d1.stdout));
  check(
    "a key whose runs agreed is NOT reported — convergence is silence",
    !/p3-check/.test(d1.stdout),
  );
  check(
    "and it names the runs that disagreed",
    /run-A/.test(d1.stdout) && /run-B/.test(d1.stdout),
  );

  // Self-referential: an artifact that embeds its own run id can never dedupe.
  const s1 = mk("t1.json", '{"path":"/tmp/run-A/x"}\n');
  const s2 = mk("t2.json", '{"path":"/tmp/run-B/x"}\n');
  Store.put(store, s1, hashOf(s1), {
    subject: "sg",
    stage: "p0-preflight",
    rel: "tripwire.json",
    inputs_digest: DIG,
    run_id: "run-A",
  });
  Store.put(store, s2, hashOf(s2), {
    subject: "sg",
    stage: "p0-preflight",
    rel: "tripwire.json",
    inputs_digest: DIG,
    run_id: "run-B",
  });
  const d2 = run("diff");
  check(
    "a self-referential pair is LABELLED",
    /SELF-REFERENTIAL/.test(d2.stdout),
  );
  check(
    "and names the substring that triggered the label, so a reader can overrule it",
    /contains "run-A"/.test(d2.stdout),
  );
  check(
    "it is labelled, never filtered — the real finding is still there",
    /DIVERGENT {2}p7-mcp/.test(d2.stdout),
  );

  // cat — default deny.
  const ung = mk("u.txt", "ungated\n");
  Store.put(store, ung, hashOf(ung), {
    subject: "sg",
    stage: "p3-check",
    rel: "u.txt",
    produced_under: null,
  });
  const catUng = run("cat", hashOf(ung));
  check(
    "store cat REFUSES an object produced under no gate",
    catUng.status === 3,
  );
  check("and says which state it is in", /unblessed/.test(catUng.stderr));

  const bless = Store.writeBlessing(store, {
    kind: "blessing",
    subject: "sg",
    gate: "HG1",
    state: "waived",
    reason: "no domain expert has read this",
    covers: [{ path: c, sha256: hashOf(c), bytes: 7 }],
    signer: null,
    signature: null,
    namespace: null,
    payload_digest: null,
  });
  const wv = mk("w.txt", "waived output\n");
  Store.put(store, wv, hashOf(wv), {
    subject: "sg",
    stage: "p6-tests",
    rel: "w.txt",
    produced_under: {
      blessing: bless.hash,
      gate: "HG1",
      state: "waived",
      reason: bless.reason,
    },
  });
  const catW = run("cat", hashOf(wv));
  check("a WAIVED object is refused without the flag", catW.status === 3);
  const catWok = run("cat", hashOf(wv), "--allow-waived");
  check(
    "--allow-waived serves it",
    catWok.status === 0 && /waived output/.test(catWok.stdout),
  );
  check(
    "and PRINTS the waiver's reason, so it cannot be served unseen",
    /no domain expert/.test(catWok.stderr),
  );

  // gc — reachability before age.
  const g = run("gc", "--keep-days", "0");
  check("store gc exits 0", g.status === 0);
  check(
    "a covers[] member survives --keep-days 0 — no age policy reaches the reviewed bytes",
    Store.has(store, hashOf(c)),
  );
  check("an unblessed object is swept", !Store.has(store, hashOf(ung)));
  check(
    "and the output states the rule rather than only the counts",
    /unreachable by any age policy/.test(g.stdout),
  );

  const v = run("verify");
  check("store verify passes over a well-formed store", v.status === 0);
  rmSync(store, { recursive: true, force: true });
  rmSync(work, { recursive: true, force: true });
}
// ===== END store verbs ======================================================

// ===== the read-set (R4) ====================================================
//
// R4's claim is that recording the MEMBERS of an input set, rather than only
// the digest they fold into, makes four questions answerable that a digest
// cannot answer at all. These checks pin the identity that makes the members
// trustworthy, and then each of the four.
{
  process.stdout.write("\n-- the read-set (R4) --\n");
  const work = mkdtempSync(resolve(tmpdir(), "go-readset-"));
  const a = resolve(work, "a.txt");
  const b = resolve(work, "b.txt");
  writeFileSync(a, "alpha");
  writeFileSync(b, "beta");
  const paths = [a, b, resolve(work, "gone.txt"), "text:k=v"];

  // THE CORNERSTONE. Everything else in R4 rests on the members being a proof
  // of the digest rather than a second opinion about it.
  check(
    "refold(digestMembers(paths)) === digestSet(paths)",
    refold(digestMembers(paths)) === digestSet(paths),
  );
  check(
    "and the identity holds through manifestText, which is the frozen format",
    refold(digestMembers(paths)) === hashText(manifestText(paths)),
  );
  check(
    "a REORDERED read-set still re-folds — serialisation order is not evidence",
    (() => {
      const m = digestMembers(paths);
      return refold([m[3], m[0], m[2], m[1]]) === digestSet(paths);
    })(),
  );
  check(
    "a DOCTORED member does NOT re-fold — which is the asymmetry that matters",
    (() => {
      const m = digestMembers(paths).map((x) =>
        x.path === a ? { ...x, sha256: `sha256:${"0".repeat(64)}` } : x,
      );
      return refold(m) !== digestSet(paths);
    })(),
  );
  check(
    "an ABSENT member is part of the proof, not skipped from it",
    (() => {
      const m = digestMembers(paths);
      return m.some((x) => x.absent) && refold(m) === digestSet(paths);
    })(),
  );

  // digest.mjs --members-out: one pass, and the argv path must not regress.
  const DIGEST = resolve(HERE, "lib/digest.mjs");
  const out = resolve(work, "members.json");
  const withFlag = spawnSync(
    process.execPath,
    [DIGEST, a, b, "--members-out", out],
    { encoding: "utf8" },
  );
  const bare = spawnSync(process.execPath, [DIGEST, a, b], {
    encoding: "utf8",
  });
  check(
    "digest.mjs --members-out prints the SAME digest it always did",
    withFlag.stdout.trim() === bare.stdout.trim() && bare.status === 0,
  );
  check(
    "and the file it wrote re-folds to that digest",
    refold(JSON.parse(readFileSync(out, "utf8"))) === withFlag.stdout.trim(),
  );
  // REGRESSION: the flag-stripping filter was `i !== membersIdx + 1`, and with
  // no flag present membersIdx is -1, so it dropped argv[0] — the first real
  // path. The bare invocation above would have digested only `b`.
  check(
    "digest.mjs with NO --members-out still digests every argv path",
    bare.stdout.trim() === digestSet([a, b]),
  );

  // rolesFor — resolution order.
  const rows = [
    {
      kind: "stage_end",
      stage: "p1-ingest",
      artifacts: [{ sha256: "sha256:aaa", rel: "src/act.txt" }],
    },
  ];
  const index = [
    { sha256: "sha256:bbb", stage: "p3-encode", rel: "enc.l4", subject: "s" },
    // The blessing path re-admits every covers[] member under the pseudo-stage
    // `covers`, whose rel is `tree:<abs>`. It must NOT outrank the tree check.
    { sha256: "sha256:ccc", stage: "covers", rel: `tree:${a}`, subject: "s" },
  ];
  const roled = rolesFor(
    [
      { path: "text:l4-binary=x", sha256: null, bytes: null },
      { path: "/w/src/act.txt", sha256: "sha256:aaa", bytes: 1 },
      { path: "/w/enc.l4", sha256: "sha256:bbb", bytes: 1 },
      { path: a, sha256: "sha256:ccc", bytes: 5 },
      { path: "/elsewhere/x", sha256: "sha256:zzz", bytes: 1 },
    ],
    rows,
    index,
    work,
  );
  const roleOf = (p) => roled.find((m) => m.path === p)?.role;
  check("a text: member is a param", roleOf("text:l4-binary=x") === "param");
  check(
    "a member produced by an earlier stage of THIS run takes that stage's class",
    roleOf("/w/src/act.txt") === "natlang_sources",
  );
  check(
    "a member found only in the store takes its record's class",
    roleOf("/w/enc.l4") === "encode",
  );
  // REGRESSION: `covers` has no phase class, and letting the store hit win
  // returned `unknown` for every corpus module of a BLESSED run — a worse
  // answer than the filesystem was about to give for free.
  check(
    "a store record whose stage has no class does NOT outrank the tree check",
    roleOf(a) === "tree",
  );
  check(
    "a member resolvable nowhere is `unknown`, never guessed",
    roleOf("/elsewhere/x") === "unknown",
  );
  check(
    "classOf is total over the stages the driver declares",
    classOf("p1-ingest") === "natlang_sources" && classOf("nope") === "unknown",
  );

  // freshness — Make's meaning, per member, derived.
  const treeMember = digestMembers([a])[0];
  check(
    "an unchanged tree member is current",
    freshness([{ ...treeMember, role: "tree", origin: "tree" }], [], {})
      .state === "current",
  );
  writeFileSync(a, "alpha CHANGED");
  const stale = freshness(
    [{ ...treeMember, role: "tree", origin: "tree" }],
    [],
    {},
  );
  check("a moved tree member is STALE", stale.state === "stale");
  check(
    "and freshness NAMES the member that moved — the whole point over a digest",
    stale.moved.length === 1 && stale.moved[0].path === a,
  );
  // A param nobody supplied must never be reported current. Assuming it
  // unchanged is exactly the §3.7a bug: the binary and the stdlib moved and no
  // digest noticed.
  const unevaluated = freshness(
    [{ path: "text:l4-binary=old", role: "param", origin: "declared" }],
    [],
    {},
  );
  check(
    "an UNSUPPLIED param is `unknown`, never `current`",
    unevaluated.state === "unknown" && unevaluated.unknown === 1,
  );
  // A member outside the checkout is still a prerequisite. Gating freshness on
  // repo membership reported `unknown` for every one of them — an unevaluated
  // prerequisite wearing the same word as an evaluated one.
  check(
    "a member OUTSIDE the repo is still freshness-checked, not `unknown`",
    (() => {
      const outside = digestMembers([b])[0];
      return (
        freshness(
          [{ ...outside, role: "unknown", origin: "unresolved" }],
          [],
          {},
        ).state === "current"
      );
    })(),
  );
  check(
    "a DELETED prerequisite is stale, and is reported with no current value",
    (() => {
      const ghost = {
        path: resolve(work, "never-existed"),
        sha256: `sha256:${"3".repeat(64)}`,
        bytes: 1,
        role: "tree",
        origin: "tree",
      };
      const f = freshness([ghost], [], {});
      return f.state === "stale" && f.moved[0].now === null;
    })(),
  );
  check(
    "a member recorded ABSENT and still absent has NOT moved",
    (() => {
      const gone = {
        path: resolve(work, "never-existed"),
        sha256: null,
        bytes: null,
        absent: true,
        role: "tree",
        origin: "tree",
      };
      return freshness([gone], [], {}).state === "current";
    })(),
  );
  check(
    "a supplied param that moved is stale",
    freshness(
      [{ path: "text:l4-binary=old", role: "param", origin: "declared" }],
      [],
      { "l4-binary": "new" },
    ).state === "stale",
  );

  // independence — the one sense in which `blind` was ever meaningful.
  check(
    "a read-set with no prior encoding is independent",
    independence([{ path: "x", role: "natlang_sources" }]).independent,
  );
  check(
    "a read-set containing a prior encoding is NOT independent, and names it",
    (() => {
      const r = independence([{ path: "prior.l4", role: "encode" }]);
      return !r.independent && r.priors.length === 1;
    })(),
  );

  // comparability — R5's precondition, and the predicate a boolean cannot express.
  const src = (sha) => [{ path: "s", role: "natlang_sources", sha256: sha }];
  check(
    "two read-sets over identical natlang_sources are comparable",
    comparability(src("sha256:1"), src("sha256:1")).comparable,
  );
  check(
    "two read-sets over DIFFERENT sources are not — their diff is not a fork",
    (() => {
      const r = comparability(src("sha256:1"), src("sha256:2"));
      return !r.comparable && r.reason === "upstream sources differ";
    })(),
  );
  // ABSENCE OF EVIDENCE IS NOT COMPARABILITY. Returning true here would license
  // exactly the spurious fork claim R5 exists to prevent — and it is the case
  // that holds today for every subject in the tree.
  check(
    "two read-sets with NO natlang_sources at all are not comparable either",
    !comparability([], []).comparable,
  );

  // THE REFUSALS. A read-set is only worth recording if a false one cannot be.
  {
    const RECEIPT = resolve(HERE, "lib/receipt.mjs");
    const run = mkdtempSync(resolve(tmpdir(), "go-rs-run-"));
    const good = digestMembers([b]);
    const goodF = resolve(run, "good.json");
    writeFileSync(goodF, JSON.stringify(good));
    const badF = resolve(run, "bad.json");
    writeFileSync(
      badF,
      JSON.stringify(
        good.map((m) => ({ ...m, sha256: `sha256:${"1".repeat(64)}` })),
      ),
    );
    // SKIPPED-with-a-reason, deliberately: a bare PASS is REFUSED by the
    // verdict lattice ("a status may not be asserted, only measured"), and
    // borrowing an oracle here would test that rule rather than this one.
    const call = (f, digest) =>
      spawnSync(
        process.execPath,
        [
          RECEIPT,
          "stage-end",
          "--run",
          run,
          "--stage",
          "p3-check",
          "--status",
          "SKIPPED",
          "--reason",
          "read-set fixture",
          "--inputs-digest",
          digest,
          "--read-set",
          f,
        ],
        { encoding: "utf8" },
      );
    const okCall = call(goodF, digestSet([b]));
    check("receipt.mjs ACCEPTS a read-set that re-folds", okCall.status === 0);
    check(
      "and the row it wrote carries the members",
      (() => {
        const rows = read(resolve(run, "journal.ndjson"));
        const r = rows.find((x) => x.kind === "stage_end");
        return Array.isArray(r?.read_set) && r.read_set.length === good.length;
      })(),
    );
    const badCall = call(badF, digestSet([b]));
    check(
      "receipt.mjs REFUSES a read-set that does not re-fold to its own digest",
      badCall.status !== 0,
    );
    check(
      "and says so, rather than recording an unprovable claim",
      /does not re-fold/.test(badCall.stderr),
    );
    check(
      "the refused read-set was NOT appended to the journal",
      read(resolve(run, "journal.ndjson")).filter((x) => x.kind === "stage_end")
        .length === 1,
    );
    check(
      "a --read-set naming a file that is not there is BROKEN, not an empty read-set",
      spawnSync(
        process.execPath,
        [
          RECEIPT,
          "stage-end",
          "--run",
          run,
          "--stage",
          "p3-check",
          "--status",
          "SKIPPED",
          "--reason",
          "fixture",
          "--inputs-digest",
          "sha256:x",
          "--read-set",
          resolve(run, "nope.json"),
        ],
        { encoding: "utf8" },
      ).status !== 0,
    );
    rmSync(run, { recursive: true, force: true });
  }

  // verify() must catch a read-set doctored AFTER the fact — the chain proves
  // nobody edited a record, and this proves the record was worth writing.
  {
    const run = mkdtempSync(resolve(tmpdir(), "go-rs-ver-"));
    const j = resolve(run, "journal.ndjson");
    append(j, { kind: "run_begin", run_id: "r", subject: "s" });
    append(j, {
      kind: "stage_end",
      stage: "p3-check",
      status: "PASS",
      inputs_digest: digestSet([b]),
      read_set: digestMembers([b]),
    });
    check("a journal with a re-folding read-set verifies", verify(j).ok);
    // Rewrite the row AND re-chain it, so the hash check cannot be what fires.
    const rows = read(j);
    rows[1].read_set = rows[1].read_set.map((m) => ({
      ...m,
      sha256: `sha256:${"2".repeat(64)}`,
    }));
    rows[1].hash = hashRecord(rows[1]);
    writeFileSync(j, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
    const v = verify(j);
    check(
      "a read-set doctored and RE-CHAINED is still caught by the refold check",
      !v.ok && v.problems.some((p) => /read_set re-folds to/.test(p)),
    );
    rmSync(run, { recursive: true, force: true });
  }

  // Backward compatibility: schema 2 and 3 carry no read-set and must verify
  // exactly as they did. The journals in `legalese/canon` are schema 2 and 3.
  {
    const run = mkdtempSync(resolve(tmpdir(), "go-rs-old-"));
    const j = resolve(run, "journal.ndjson");
    writeFileSync(
      j,
      [
        {
          journal_schema: 3,
          seq: 0,
          kind: "run_begin",
          run_id: "r",
          subject: "s",
        },
        {
          journal_schema: 3,
          seq: 1,
          kind: "stage_end",
          stage: "p3-check",
          status: "PASS",
          inputs_digest: "sha256:whatever",
        },
      ]
        .map((r, i, all) => {
          r.prev = i === 0 ? "sha256:" + "0".repeat(64) : all[i - 1].hash;
          r.hash = hashRecord(r);
          return JSON.stringify(r);
        })
        .join("\n") + "\n",
    );
    check(
      "a schema-3 journal with no read_set verifies unchanged",
      verify(j).ok,
    );
    rmSync(run, { recursive: true, force: true });
  }

  rmSync(work, { recursive: true, force: true });
}
// ===== END the read-set =====================================================

// ===== a diff means something different per phase (R5) ======================
//
// A uniform "diff the artifacts" layer would mislabel three different events.
// These pin the labels, and the one constraint the whole comparison layer rests
// on: an encoding diff is an interpretive fork ONLY IF the upstream read-sets
// matched.
{
  process.stdout.write("\n-- per-phase diff meaning (R5) --\n");
  const store = mkdtempSync(resolve(tmpdir(), "go-r5-store-"));
  const work = mkdtempSync(resolve(tmpdir(), "go-r5-work-"));
  const CLI = resolve(HERE, "lib/store-cli.mjs");
  const runCli = (...a) =>
    spawnSync(process.execPath, [CLI, ...a], {
      encoding: "utf8",
      env: { ...process.env, L4_GO_STORE: store },
    });

  // Two witnesses per key, differing, so every key is divergent.
  const admit = (stage, rel, text, sources) => {
    const f = resolve(work, `${stage}-${text.length}-${rel}`);
    writeFileSync(f, text);
    Store.put(store, f, hashOf(f), {
      subject: "s",
      stage,
      rel,
      inputs_digest: "sha256:same",
      run_id: `r${text.length}`,
      sources_digest: sources,
    });
  };
  admit("p1-ingest", "act.txt", "one", null);
  admit("p1-ingest", "act.txt", "two", null);
  admit("p2-sweep", "reg.json", "one", null);
  admit("p2-sweep", "reg.json", "twoo", null);
  const d1 = runCli("diff");
  check(
    "a natlang_sources divergence is a CURRENCY EVENT, explicitly not a fork",
    /CURRENCY EVENT/.test(d1.stdout) && /NOT a fork/.test(d1.stdout),
  );
  check(
    "a research divergence is a SWEEP FINDING routed to the modification register",
    /SWEEP FINDING/.test(d1.stdout) &&
      /external-modification\s*\n?\s*register/.test(d1.stdout),
  );

  // encode, with the sources recorded and IDENTICAL -> a real fork.
  admit("p3-encode", "enc.l4", "aaa", "sha256:src1");
  admit("p3-encode", "enc.l4", "bbb", "sha256:src1");
  check(
    "an encode divergence over IDENTICAL sources is an INTERPRETIVE FORK",
    /INTERPRETIVE FORK/.test(runCli("diff").stdout),
  );

  // encode, sources DIFFER -> not a fork at all.
  const store2 = mkdtempSync(resolve(tmpdir(), "go-r5-store2-"));
  const admit2 = (text, sources) => {
    const f = resolve(work, `enc2-${text}`);
    writeFileSync(f, text);
    Store.put(store2, f, hashOf(f), {
      subject: "s",
      stage: "p3-encode",
      rel: "enc.l4",
      inputs_digest: "sha256:same",
      run_id: `r-${text}`,
      sources_digest: sources,
    });
  };
  admit2("aaa", "sha256:src1");
  admit2("bbb", "sha256:src2");
  const d3 = spawnSync(process.execPath, [CLI, "diff"], {
    encoding: "utf8",
    env: { ...process.env, L4_GO_STORE: store2 },
  });
  check(
    "an encode divergence over DIFFERENT sources is NOT A FORK — it is a currency event",
    /NOT A FORK/.test(d3.stdout),
  );

  // encode, sources UNRECORDED -> refuse to call it either way.
  const store3 = mkdtempSync(resolve(tmpdir(), "go-r5-store3-"));
  for (const t of ["aaa", "bbb"]) {
    const f = resolve(work, `enc3-${t}`);
    writeFileSync(f, t);
    Store.put(store3, f, hashOf(f), {
      subject: "s",
      stage: "p3-encode",
      rel: "enc.l4",
      inputs_digest: "sha256:same",
      run_id: `r-${t}`,
    });
  }
  const d4 = spawnSync(process.execPath, [CLI, "diff"], {
    encoding: "utf8",
    env: { ...process.env, L4_GO_STORE: store3 },
  });
  // ABSENCE OF EVIDENCE IS NOT COMPARABILITY. This is the case that holds for
  // every subject in the tree today, because none has run p1-ingest for real.
  check(
    "an encode divergence with NO recorded sources is NOT ESTABLISHED as a fork",
    /NOT ESTABLISHED as a fork/.test(d4.stdout),
  );
  check(
    "and it says why, rather than defaulting to the interesting answer",
    /Absence of evidence is not comparability/.test(d4.stdout),
  );

  for (const d of [store, store2, store3, work])
    rmSync(d, { recursive: true, force: true });
}
// ===== END per-phase diff meaning ===========================================

// ===== the subject-level fold (R13) =========================================
{
  process.stdout.write("\n-- the subject fold (R13) --\n");
  const SR = resolve(HERE, "lib/subject-report.mjs");
  const base = mkdtempSync(resolve(tmpdir(), "go-r13-"));
  const work = mkdtempSync(resolve(tmpdir(), "go-r13-w-"));
  const src = resolve(work, "law.l4");
  writeFileSync(src, "ORIGINAL");

  const mkRun = (id, stage, members, digest) => {
    const dir = resolve(base, id);
    mkdirSync(dir, { recursive: true });
    const j = resolve(dir, "journal.ndjson");
    append(j, {
      kind: "run_begin",
      run_id: id,
      subject: "subj",
      declared_stages: [stage],
    });
    append(j, {
      kind: "stage_end",
      stage,
      status: "PASS",
      inputs_digest: digest,
      read_set: members,
    });
    return dir;
  };
  mkRun(
    "2026-01-01-aaa-001",
    "p3-check",
    digestMembers([src]),
    digestSet([src]),
  );

  const run = (...a) =>
    spawnSync(process.execPath, [SR, base, "--subject", "subj", ...a], {
      encoding: "utf8",
      env: { ...process.env, L4_GO_STORE: resolve(work, "no-store") },
    });

  const clean = run();
  check(
    "a fold over an unchanged prerequisite is CURRENT",
    /CURRENT/.test(clean.stdout),
  );
  check("and exits 0", clean.status === 0);

  // A phase in the DECLARABLE set that no run ever declared must still appear.
  // This is R13's whole point: a phase that is absent from the report reads as
  // "accounted for elsewhere" when nothing accounted for it anywhere.
  const wide = run("--declarable", "p3-check p1-ingest");
  check(
    "a declarable phase with no receipt anywhere is NEVER RUN, not omitted",
    /p1-ingest\s+NEVER RUN/.test(wide.stdout),
  );

  writeFileSync(src, "CHANGED");
  const stale = run();
  check(
    "a moved prerequisite makes the phase STALE",
    /STALE/.test(stale.stdout),
  );
  check(
    "and NAMES the member that moved",
    /MOVED .*law\.l4/.test(stale.stdout),
  );
  check("and exits 1, so a caller can gate on it", stale.status === 1);
  check(
    "the footer states that STALE is Make's, not 'the digest moved'",
    /a newer version of some prerequisite exists/.test(stale.stdout),
  );

  // The evidence horizon must be reported, because a narrowed view must never
  // read as an empty world.
  check(
    "the evidence horizon is printed",
    /Evidence horizon: 1 surviving journal/.test(stale.stdout),
  );

  // A journal whose chain does not verify is not evidence, and its exclusion is
  // announced rather than silent.
  const j = resolve(base, "2026-01-01-aaa-001", "journal.ndjson");
  const rows = read(j);
  rows[1].status = "FORGED";
  writeFileSync(j, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
  const tampered = run();
  check(
    "a journal that does not verify is EXCLUDED from the fold",
    /1 journal\(s\) EXCLUDED/.test(tampered.stdout),
  );
  check(
    "and its phase then reads NEVER RUN rather than inheriting a forged status",
    !/FORGED/.test(tampered.stdout),
  );

  rmSync(base, { recursive: true, force: true });
  rmSync(work, { recursive: true, force: true });
}
// ===== END the subject fold =================================================

// ===== defects the adversarial review found (2026-08-24) ====================
//
// Five independent lenses converged on the first of these, which is the whole
// argument for reviewing by attack rather than by reading.
{
  process.stdout.write("\n-- review findings, pinned --\n");

  // THE SEPARATOR MISMATCH. The map was BUILT with NUL bytes and READ with
  // spaces, so every produced member missed and reported `unknown`. Invisible
  // in a diff, which is exactly why the separator is now an escape and this
  // test reads the file as BYTES.
  check(
    "readset.mjs contains no raw NUL byte — a separator must be visible in source",
    !readFileSync(resolve(HERE, "lib/readset.mjs")).includes(0),
  );
  check(
    "witnessKey is the ONE key builder, so the two ends cannot disagree",
    (() => {
      const src = readFileSync(resolve(HERE, "lib/readset.mjs"), "utf8");
      const uses = (src.match(/witnessKey\(/g) || []).length;
      return uses >= 3; // one definition, one build site, one lookup site
    })(),
  );
  check(
    "a produced member whose bytes are unchanged is CURRENT, not `unknown`",
    (() => {
      const rows = [
        { kind: "run_begin", subject: "subj" },
        {
          kind: "stage_end",
          stage: "p1-ingest",
          artifacts: [{ sha256: "sha256:aaa", rel: "act.txt" }],
        },
      ];
      const roled = rolesFor(
        [{ path: "/w/act.txt", sha256: "sha256:aaa", bytes: 1 }],
        rows,
        [],
      );
      const idx = [
        {
          subject: "subj",
          stage: "p1-ingest",
          rel: "act.txt",
          sha256: "sha256:aaa",
        },
      ];
      return freshness(roled, idx, {}).state === "current";
    })(),
  );
  check(
    "and when a NEWER admission exists for that slot it is STALE, naming it",
    (() => {
      const rows = [
        { kind: "run_begin", subject: "subj" },
        {
          kind: "stage_end",
          stage: "p1-ingest",
          artifacts: [{ sha256: "sha256:aaa", rel: "act.txt" }],
        },
      ];
      const roled = rolesFor(
        [{ path: "/w/act.txt", sha256: "sha256:aaa", bytes: 1 }],
        rows,
        [],
      );
      const idx = [
        {
          subject: "subj",
          stage: "p1-ingest",
          rel: "act.txt",
          sha256: "sha256:aaa",
        },
        {
          subject: "subj",
          stage: "p1-ingest",
          rel: "act.txt",
          sha256: "sha256:bbb",
        },
      ];
      const f = freshness(roled, idx, {});
      return f.state === "stale" && f.moved[0].now === "sha256:bbb";
    })(),
  );
  // rolesFor's run branch returned no subject, so the key carried an empty one
  // while every store record carries a real one — a guaranteed miss even after
  // the separator was fixed.
  check(
    "rolesFor stamps the run's own subject onto a run-origin member",
    (() => {
      const rows = [
        { kind: "run_begin", subject: "subj" },
        {
          kind: "stage_end",
          stage: "p1-ingest",
          artifacts: [{ sha256: "sha256:aaa", rel: "act.txt" }],
        },
      ];
      return (
        rolesFor([{ path: "/w/act.txt", sha256: "sha256:aaa" }], rows, [])[0]
          .subject === "subj"
      );
    })(),
  );

  // THE SHARPER HALF of the missing subject: an empty-subject key does not
  // merely MISS, it can FALSE-MATCH a `subject: null` record left by an
  // unrelated run — reporting STALE against another run's bytes, which is a
  // confident wrong answer rather than an absent one.
  check(
    "a run-origin member does not match a foreign subject-null store record",
    (() => {
      const rows = [
        { kind: "run_begin", subject: "subj" },
        {
          kind: "stage_end",
          stage: "p1-ingest",
          artifacts: [{ sha256: "sha256:aaa", rel: "p1-ingest-validate.txt" }],
        },
      ];
      const roled = rolesFor(
        [{ path: "/w/p1-ingest-validate.txt", sha256: "sha256:aaa", bytes: 1 }],
        rows,
        [],
      );
      // A record from somewhere else entirely, with no subject on it.
      const foreign = [
        {
          subject: null,
          stage: "p1-ingest",
          rel: "p1-ingest-validate.txt",
          sha256: "sha256:ffff",
        },
      ];
      const f = freshness(roled, foreign, {});
      // `unknown` is the honest answer: nothing in the index speaks for THIS
      // subject. Reporting `stale` here would be an accusation sourced from a
      // stranger's run.
      return f.state === "unknown" && f.moved.length === 0;
    })(),
  );

  // refold must REPORT a broken journal, not die on it. A verifier that throws
  // turns "this journal is wrong" into "the tool is wrong".
  check(
    "refold does not throw on a malformed read_set member",
    (() => {
      try {
        return typeof refold(["not-a-member", null, 42]) === "string";
      } catch {
        return false;
      }
    })(),
  );
  check(
    "and verify REPORTS such a journal rather than crashing",
    (() => {
      const run = mkdtempSync(resolve(tmpdir(), "go-malformed-"));
      const j = resolve(run, "journal.ndjson");
      const rows = [
        {
          journal_schema: 4,
          seq: 0,
          kind: "run_begin",
          run_id: "r",
          subject: "s",
        },
        {
          journal_schema: 4,
          seq: 1,
          kind: "stage_end",
          stage: "p3-check",
          status: "PASS",
          inputs_digest: "sha256:x",
          read_set: ["bogus"],
        },
      ];
      let prev = "sha256:" + "0".repeat(64);
      for (const r of rows) {
        r.prev = prev;
        r.hash = hashRecord(r);
        prev = r.hash;
      }
      writeFileSync(j, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
      let ok = false;
      try {
        ok = verify(j).problems.some((p) => /read_set re-folds/.test(p));
      } catch {
        ok = false;
      }
      rmSync(run, { recursive: true, force: true });
      return ok;
    })(),
  );

  // A journal's schema is fixed at creation. Resuming across a bump would put
  // two schemas in one chain and make the run permanently unverifiable.
  check(
    "append REFUSES to add a row to a journal created at another schema",
    (() => {
      const run = mkdtempSync(resolve(tmpdir(), "go-schema-"));
      const j = resolve(run, "journal.ndjson");
      const r0 = {
        journal_schema: 3,
        seq: 0,
        kind: "run_begin",
        run_id: "r",
        subject: "s",
        prev: "sha256:" + "0".repeat(64),
      };
      r0.hash = hashRecord(r0);
      writeFileSync(j, JSON.stringify(r0) + "\n");
      let threw = false;
      try {
        append(j, { kind: "stage_begin", stage: "p3-check" });
      } catch (e) {
        threw = /permanently unverifiable|two schemas/.test(e.message);
      }
      const stillVerifies = verify(j).ok;
      rmSync(run, { recursive: true, force: true });
      return threw && stillVerifies;
    })(),
  );

  // gc's keep-list compared PATH STRINGS. macOS TMPDIR ends in a slash, so the
  // base carries a double slash that `ls` preserves and node's resolver
  // collapses; nothing ever matched, and every run directory was deleted —
  // gate-holding ones included — while the summary printed "kept N".
  check(
    "gc matches its keep-list by run id, never by path string",
    (() => {
      const src = readFileSync(resolve(HERE, "go.sh"), "utf8");
      const body = src.slice(src.indexOf("cmd_gc()"));
      const gc = body.slice(0, body.indexOf("\n}\n"));
      return /basename "\$d"/.test(gc) && /"\$k" == "\$id"/.test(gc);
    })(),
  );
  check(
    "and a double-slashed base still keeps a gate-holding run",
    (() => {
      const base = mkdtempSync(resolve(tmpdir(), "go-gcpath-"));
      const dir = resolve(base, "l4-go", "2026-01-01-aaa-001");
      mkdirSync(dir, { recursive: true });
      writeFileSync(
        resolve(dir, "journal.ndjson"),
        JSON.stringify({ kind: "run_begin", subject: "regcf" }) +
          "\n" +
          JSON.stringify({ kind: "gate", state: "satisfied" }) +
          "\n",
      );
      const r = spawnSync(resolve(HERE, "go.sh"), ["gc", "--keep", "1"], {
        encoding: "utf8",
        env: { ...process.env, L4_GO_RUNDIR: `${base}//l4-go` },
      });
      const survived = existsSync(dir);
      rmSync(base, { recursive: true, force: true });
      return r.status === 0 && survived;
    })(),
  );

  // subject-report's declarable universe came from PRIMARY_STAGES, which was never
  // assembled for that command, so every g1-only phase reached the report only
  // via a surviving journal — and would vanish once those expired.
  check(
    "subject-report is in the set of commands that resolve a subject",
    /" run plan doctor subject-report "/.test(
      readFileSync(resolve(HERE, "go.sh"), "utf8"),
    ),
  );

  // Run ids sort date, then CONTENT HASH, then counter — so lexicographic order
  // is not chronological within a day.
  check(
    "subject-report orders runs by recorded start time, not by run id",
    /run_begin\"\)\?\.ts/.test(
      readFileSync(resolve(HERE, "lib/subject-report.mjs"), "utf8"),
    ),
  );

  // store diff read only the FIRST admission of each sha, hiding a real
  // disagreement between two runs that read different sources.
  check(
    "store diff folds EVERY admission's sources_digest, not just the first",
    (() => {
      const src = readFileSync(resolve(HERE, "lib/store-cli.mjs"), "utf8");
      return (
        /admissions\.map\(\(a\) => a\.sources_digest/.test(src) &&
        !/a\[0\]\.sources_digest/.test(src)
      );
    })(),
  );

  // receipt.mjs passed [] as the store index, which made the store branch of
  // rolesFor unreachable — so sources_digest was structurally null for exactly
  // the cross-run case it exists to serve.
  check(
    "receipt.mjs classifies a read-set against the REAL store index",
    /storeIndex = indexRecords\(store\)/.test(
      readFileSync(resolve(HERE, "lib/receipt.mjs"), "utf8"),
    ),
  );
}
// ===== END review findings ==================================================

process.stdout.write(
  `\n${failures === 0 ? "selftest: all checks passed" : `selftest: ${failures} FAILED`}${skips ? ` (${skips} skipped)` : ""}\n`,
);
process.exit(failures === 0 ? 0 : 1);
