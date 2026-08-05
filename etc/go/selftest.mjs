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
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  append,
  hashRecord,
  read,
  sha256File as hashOf,
  verify,
} from "./lib/ledger.mjs";
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
      "--milestone",
      "g1",
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
    "every declared g1 stage sequenced at or after p6-tests is gated",
    plan.status === 0 && from >= 0 && ungated.length === 0,
  );
  check(
    "the never-replaying stages are declared g1 members, and the plan names them",
    NEVER_REPLAY.every((s) => rows.some((r) => r.stage === s)),
  );
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
  // assertion about go.sh would pass over a `GO_CORPUS_FILES` array that was
  // built and then overwritten.
  {
    const digestOf = () => {
      const p = spawnSync(
        "bash",
        [
          resolve(HERE, "go.sh"),
          "plan",
          "--milestone",
          "g1",
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
      milestone: "g1",
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
        milestone: "g1",
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
        milestone: "g1",
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
      lintNarrative("the milestone is COMPLETE").some(
        (f) => f.code === "N-STATUS",
      ) &&
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
  const T = mkdtempSync(resolve(tmpdir(), "l4-go-denovo-"));
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

  // --- 1. the sidecar's `denovo` section ------------------------------------
  const sidecars = resolve(T, "subjects");
  const mkSidecar = (id, denovo, corpus = CORPUS) => {
    const d = resolve(sidecars, id);
    mkd(d, { recursive: true });
    wr(
      resolve(d, "subject.json"),
      JSON.stringify({
        id,
        display_name: "Selftest Subject",
        citation: "n/a",
        source_url: "https://example.invalid/",
        corpus: { main: corpus },
        checks: { min_dated_arms: 0, min_assertions: 0 },
        legs: {},
        ...(denovo ? { denovo } : {}),
      }),
    );
    wr(resolve(d, "pins.json"), "{}");
    wr(resolve(d, "known-defects.json"), "{}");
    wr(resolve(d, "NOTES.md"), "selftest fixture\n");
    return d;
  };
  const subjectRun = (id) =>
    spawnSync("node", [resolve(HERE, "lib/subject.mjs"), id], {
      encoding: "utf8",
      env: { ...process.env, L4_GO_SUBJECTS_DIR: sidecars },
    });

  mkSidecar("smoke", {
    bundle: BUNDLE,
    register: REGISTER,
    fork_register: FORKS,
    modules: [resolve(DEP, "smoke.l4")],
  });
  {
    const r = subjectRun("smoke");
    check(
      "a sidecar's denovo section resolves to GO_S_DENOVO_* paths whose existence is NOT required",
      r.status === 0 &&
        r.stdout.includes(`GO_S_DENOVO_BUNDLE='${BUNDLE}'`) &&
        r.stdout.includes(`GO_S_DENOVO_REGISTER='${REGISTER}'`) &&
        r.stdout.includes(`GO_S_DENOVO_FORKS='${FORKS}'`) &&
        r.stdout.includes(
          `GO_S_DENOVO_MODULES='${resolve(DEP, "smoke.l4")}'`,
        ) &&
        !ex(resolve(DEP, "smoke.l4")),
    );
  }
  {
    mkSidecar("badkey", { bundle: BUNDLE, surprise: "x" });
    const r = subjectRun("badkey");
    check(
      "an unknown key inside denovo is refused, naming the allowed set",
      r.status === 2 && /denovo: unknown key 'surprise'/.test(r.stderr),
    );
  }
  {
    mkSidecar("selfdiff", { modules: ["jl4/examples/legal/regcf/regcf.l4"] });
    const r = subjectRun("selfdiff");
    check(
      "a denovo module that IS the corpus is refused — SPEC.md §8's diff would be an identity",
      r.status === 2 && /also a corpus module/.test(r.stderr),
    );
  }
  {
    mkSidecar("nodenovo", null);
    const r = subjectRun("nodenovo");
    check(
      "omitting denovo entirely is legal, and every GO_S_DENOVO_* comes back empty",
      r.status === 0 &&
        r.stdout.includes("GO_S_DENOVO_BUNDLE=''") &&
        r.stdout.includes("GO_S_DENOVO_MODULES=''"),
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
        GO_S_CORPUS: CORPUS,
        GO_S_DENOVO_BUNDLE: "",
        GO_S_DENOVO_REGISTER: "",
        GO_S_DENOVO_FORKS: "",
        GO_S_DENOVO_MODULES: "",
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
    GO_S_DENOVO_BUNDLE: BUNDLE,
    GO_S_DENOVO_REGISTER: REGISTER,
    GO_S_DENOVO_FORKS: FORKS,
  };

  // --- 3. deposit present: the stage validates it and PASSes -----------------
  for (const [name, key] of [
    ["p1-ingest", "GO_S_DENOVO_BUNDLE"],
    ["p2-sweep", "GO_S_DENOVO_REGISTER"],
    ["p4-forks", "GO_S_DENOVO_FORKS"],
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
      GO_S_DENOVO_BUNDLE: resolve(DEP, "never-written.json"),
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
    const t = stage("p2-sweep", { ...ALL, GO_S_DENOVO_REGISTER: "" });
    check(
      "a subject that declares no denovo.register is SKIPPED naming the key and the file to add it to",
      t.exit === 0 &&
        t.row?.status === "SKIPPED" &&
        /declares no denovo\.register/.test(t.row.reason) &&
        /subject\.json/.test(t.row.reason),
    );
  }
  {
    const s = stage("p4-forks", {
      ...ALL,
      GO_S_DENOVO_FORKS: resolve(DEP, "never-written.json"),
      L4_GO_REQUIRED: "1",
    });
    check(
      "an absent deposit is FATAL under L4_GO_REQUIRED=1 — a G2 run that skipped every deposit is not a G2 run",
      s.exit === 5 && s.row?.status === "SKIPPED",
    );
  }

  // --- 5. deposit invalid: DEGRADED, naming the rule ------------------------
  {
    const s = stage("p4-forks", { ...ALL, GO_S_DENOVO_FORKS: BAD_FORKS });
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
    const s = stage("p1-ingest", { ...ALL, GO_S_DENOVO_FORKS: BAD_FORKS });
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
    const s = stage("p4-forks", { ...ALL, GO_S_DENOVO_FORKS: BNA_FORKS });
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
    const s = stage("p1-ingest", { ...ALL, GO_S_DENOVO_BUNDLE: notJson });
    check(
      "an unparseable deposit is a finding about the DEPOSIT (DEGRADED), never BROKEN about the harness",
      s.exit === 1 &&
        s.row?.status === "DEGRADED" &&
        /is not valid JSON/.test(s.row.reason),
    );
  }

  // --- 6. p5-gate: the joins, and the two halves it does not hold ------------
  {
    const s = stage("p5-gate", { ...ALL, GO_S_DENOVO_FORKS: "" });
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
    const s = stage("p3-encode");
    check(
      "p3-encode with no denovo.modules is SKIPPED naming the key",
      s.exit === 0 &&
        s.row?.status === "SKIPPED" &&
        /declares no denovo\.modules/.test(s.row.reason),
    );
  }
  {
    const s = stage("p3-encode", {
      GO_S_DENOVO_MODULES: resolve(DEP, "never-written.l4"),
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
      const s = stage("p3-encode", { GO_S_DENOVO_MODULES: good });
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
      const t = stage("p3-encode", { GO_S_DENOVO_MODULES: bad });
      check(
        "p3-encode is capable of red: a module that does not typecheck is DEGRADED",
        t.exit === 1 &&
          t.row?.status === "DEGRADED" &&
          Number(t.row.metrics.typecheck_failures) === 1,
      );
    }
  }

  // --- 8. the plan stops refusing -------------------------------------------
  {
    const r = spawnSync(
      "bash",
      [
        resolve(HERE, "go.sh"),
        "plan",
        "--milestone",
        "g2",
        "--subject",
        "smoke",
      ],
      {
        encoding: "utf8",
        env: { ...process.env, L4_GO_SUBJECTS_DIR: sidecars },
      },
    );
    check(
      "go.sh plan --milestone g2 no longer refuses, and prints SPEC.md §4's full de novo order",
      r.status === 0 &&
        [
          "p1-ingest",
          "p2-sweep",
          "p3-encode",
          "p3-check",
          "p4-forks",
          "p5-gate",
          "p9-report",
        ].every((s) => r.stdout.includes(s)),
    );
    check(
      "the plan states each deposit's presence, and marks the stages that are NOT wired at g2",
      /p1-ingest\s+-\s+present/.test(r.stdout) &&
        /p3-check\s+NOT WIRED/.test(r.stdout) &&
        /p6-tests\s+NOT WIRED/.test(r.stdout),
    );
    check(
      "and it refuses to let 'g2 COMPLETE' be read as 'a de novo run happened'",
      /does NOT mean a de novo run happened/.test(r.stdout) &&
        /§8 diff oracle/.test(r.stdout),
    );
    const t = spawnSync(
      "bash",
      [
        resolve(HERE, "go.sh"),
        "plan",
        "--milestone",
        "g2",
        "--subject",
        "nodenovo",
      ],
      {
        encoding: "utf8",
        env: { ...process.env, L4_GO_SUBJECTS_DIR: sidecars },
      },
    );
    check(
      "a subject with no denovo section plans cleanly, every deposit reading 'undeclared'",
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
    milestone: "g2",
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
      milestone: "g1",
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
    run_id: "g1-report-test",
    milestone: "g1",
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
    "a g1 report no longer claims the de novo stages refuse, or that their tooling is unbuilt",
    !/entry point that refuses/.test(gmd) &&
      !/de novo tooling is unbuilt/.test(gmd) &&
      /not declared at this milestone/.test(gmd),
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

process.stdout.write(
  `\n${failures === 0 ? "selftest: all checks passed" : `selftest: ${failures} FAILED`}${skips ? ` (${skips} skipped)` : ""}\n`,
);
process.exit(failures === 0 ? 0 : 1);
