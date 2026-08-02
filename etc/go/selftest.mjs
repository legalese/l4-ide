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
  writeFileSync,
} from "node:fs";
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
    milestone: "g1",
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
    milestone: "g1",
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
    "--milestone",
    "g1",
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
        "--milestone",
        "g1",
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
    const mk = (pair, id, kind, mutation, l, r) => ({
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
      const out = mkdtempSync(resolve(tmpdir(), "go-denovo-diff-"));
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
}
// ===== END denovo-diff-oracle checks ========================================

process.stdout.write(
  `\n${failures === 0 ? "selftest: all checks passed" : `selftest: ${failures} FAILED`}${skips ? ` (${skips} skipped)` : ""}\n`,
);
process.exit(failures === 0 ? 0 : 1);
