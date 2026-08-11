// Standalone PURE unit test for scripts/parity-gate.mjs.
//
// Imports ONLY ./parity-gate.mjs (zero heavy deps) so it runs under bare
// `node` with no LLVM toolchain and no jl4-service. This file is the sole
// machine-verifiable anchor for the gate's contract:
//   - classifyOutcome reproduces the harness:339-350 ladder exactly,
//   - the moved helpers (canonical/extractValue/ulpEqual) are regression-locked,
//   - gateVerdict's hardened semantics + the zero-comparison guard hold, and
//   - every false-negative trap from the gate survey now actually gates.
//
//   node scripts/parity-gate.test.mjs
//
// Pattern mirrors runtime/jl4-runtime.test.mjs: hand-rolled eq/throws with
// pass/fail counters, console.log 'ok '/'FAIL', final tally, exit(fail?1:0).

import {
  canonical,
  extractValue,
  ulpEqual,
  classifyOutcome,
  gateVerdict,
} from "./parity-gate.mjs";

let pass = 0;
let fail = 0;
const eq = (name, got, want) => {
  const ok = got === want;
  console.log(
    `${ok ? "ok  " : "FAIL"} ${name}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`,
  );
  ok ? pass++ : fail++;
};

// Deep-ish equality for arrays of primitives (the `failures` arrays).
const eqArr = (name, got, want) => {
  const ok =
    Array.isArray(got) &&
    Array.isArray(want) &&
    got.length === want.length &&
    got.every((v, i) => v === want[i]);
  console.log(
    `${ok ? "ok  " : "FAIL"} ${name}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`,
  );
  ok ? pass++ : fail++;
};

// Assert a boolean predicate (with both values printed for triage).
const ok = (name, cond, detail = "") => {
  console.log(
    `${cond ? "ok  " : "FAIL"} ${name}${detail ? ": " + detail : ""}`,
  );
  cond ? pass++ : fail++;
};

// Build a mock response body matching the wrapEvaluationEnvelope wire shape
// (verified in jl4-runtime.mjs:4423 -> { contents: { result: { value } }, tag };
// extractValue reads JSON.parse(body)?.contents?.result?.value).
const body = (value, tag = "SimpleResponse") =>
  JSON.stringify({ contents: { result: { value } }, tag });

// ===========================================================================
// A) classifyOutcome — cover EVERY one of the 7 trace=none outcomes
// ===========================================================================

// 1. byte-identical: svcStatus=200, svcBody===wasmBody (identical string).
{
  const b = body(42);
  eq(
    "classify byte-identical",
    classifyOutcome({ svcStatus: 200, svcBody: b, wasmBody: b, wasmErr: null }),
    "byte-identical",
  );
}

// 2. value-equal: same value, DIFFERENT envelope bytes (tag differs / key order)
//    so the strings differ but canonical(extractValue) matches.
{
  const svcB = body(42, "TraceResponse"); // different tag => different bytes
  const wasmB = body(42, "SimpleResponse");
  ok(
    "value-equal precondition: bodies differ",
    svcB !== wasmB,
    `${svcB} vs ${wasmB}`,
  );
  eq(
    "classify value-equal (tag differs)",
    classifyOutcome({
      svcStatus: 200,
      svcBody: svcB,
      wasmBody: wasmB,
      wasmErr: null,
    }),
    "value-equal",
  );
  // reordered object keys: byte-different strings, canonically equal value
  const svcObj = JSON.stringify({
    contents: { result: { value: { b: 1, a: 2 } } },
    tag: "SimpleResponse",
  });
  const wasmObj = JSON.stringify({
    contents: { result: { value: { a: 2, b: 1 } } },
    tag: "SimpleResponse",
  });
  ok("value-equal precondition: reordered bytes differ", svcObj !== wasmObj);
  eq(
    "classify value-equal (reordered keys)",
    classifyOutcome({
      svcStatus: 200,
      svcBody: svcObj,
      wasmBody: wasmObj,
      wasmErr: null,
    }),
    "value-equal",
  );
}

// 3. ulp-differs: 0.30000000000000004 vs 0.3 (within 1e-9 band); and the
//    outside-band counter-case (0.3 vs 0.4) must NOT be ulp-differs.
{
  eq(
    "classify ulp-differs (within band)",
    classifyOutcome({
      svcStatus: 200,
      svcBody: body(0.30000000000000004),
      wasmBody: body(0.3),
      wasmErr: null,
    }),
    "ulp-differs",
  );
  eq(
    "classify NOT ulp-differs (0.3 vs 0.4 -> differs)",
    classifyOutcome({
      svcStatus: 200,
      svcBody: body(0.3),
      wasmBody: body(0.4),
      wasmErr: null,
    }),
    "differs",
  );
}

// 4. differs: value 1 vs 2; and string "yes" vs "no".
{
  eq(
    "classify differs (1 vs 2)",
    classifyOutcome({
      svcStatus: 200,
      svcBody: body(1),
      wasmBody: body(2),
      wasmErr: null,
    }),
    "differs",
  );
  eq(
    "classify differs (string yes vs no)",
    classifyOutcome({
      svcStatus: 200,
      svcBody: body("yes"),
      wasmBody: body("no"),
      wasmErr: null,
    }),
    "differs",
  );
}

// 5. wasm-error: wasmErr truthy, svcStatus=200.
eq(
  "classify wasm-error",
  classifyOutcome({
    svcStatus: 200,
    svcBody: body(1),
    wasmBody: null,
    wasmErr: "boom",
  }),
  "wasm-error",
);

// 6. service-error: wasmErr falsy, svcStatus 500/404/502; boundary 299/300.
eq(
  "classify service-error (500)",
  classifyOutcome({
    svcStatus: 500,
    svcBody: "ISE",
    wasmBody: body(1),
    wasmErr: null,
  }),
  "service-error",
);
eq(
  "classify service-error (404)",
  classifyOutcome({
    svcStatus: 404,
    svcBody: "nf",
    wasmBody: body(1),
    wasmErr: null,
  }),
  "service-error",
);
eq(
  "classify service-error (502)",
  classifyOutcome({
    svcStatus: 502,
    svcBody: "bg",
    wasmBody: body(1),
    wasmErr: null,
  }),
  "service-error",
);
// Boundary: 299 ok (byte-identical), 300 not ok (service-error), 200 ok.
{
  const b = body(7);
  eq(
    "classify boundary 299 svcOk",
    classifyOutcome({ svcStatus: 299, svcBody: b, wasmBody: b, wasmErr: null }),
    "byte-identical",
  );
  eq(
    "classify boundary 300 NOT svcOk",
    classifyOutcome({ svcStatus: 300, svcBody: b, wasmBody: b, wasmErr: null }),
    "service-error",
  );
  eq(
    "classify boundary 200 svcOk",
    classifyOutcome({ svcStatus: 200, svcBody: b, wasmBody: b, wasmErr: null }),
    "byte-identical",
  );
}

// 7. both-error: wasmErr truthy, svcStatus=500.
eq(
  "classify both-error",
  classifyOutcome({
    svcStatus: 500,
    svcBody: "ISE",
    wasmBody: null,
    wasmErr: "boom",
  }),
  "both-error",
);

// Edge: wasmErr precedence over body comparison (wasmErr + svcOk + matching
// bodies still -> 'wasm-error', proving ladder order).
{
  const b = body(1);
  eq(
    "classify ladder order: wasmErr wins over matching bodies",
    classifyOutcome({ svcStatus: 200, svcBody: b, wasmBody: b, wasmErr: "x" }),
    "wasm-error",
  );
}

// Edge: non-numeric / unparseable bodies. extractValue undefined on both =>
// canonical(undefined)===canonical(undefined) so non-identical strings that
// both fail to parse -> value-equal; identical strings -> byte-identical.
{
  eq(
    "classify garbage-but-identical -> byte-identical",
    classifyOutcome({
      svcStatus: 200,
      svcBody: "not json",
      wasmBody: "not json",
      wasmErr: null,
    }),
    "byte-identical",
  );
  eq(
    "classify both-unparseable-different -> value-equal (both extract undefined)",
    classifyOutcome({
      svcStatus: 200,
      svcBody: "not json A",
      wasmBody: "not json B",
      wasmErr: null,
    }),
    "value-equal",
  );
}

// ===========================================================================
// B) Pure helpers — regression-lock the moved code
// ===========================================================================

eq(
  "canonical sorted-key stability",
  canonical({ b: 1, a: 2 }),
  canonical({ a: 2, b: 1 }),
);
ok(
  "canonical preserves array order",
  canonical([1, 2]) !== canonical([2, 1]),
  `${canonical([1, 2])} vs ${canonical([2, 1])}`,
);

eq("extractValue happy", extractValue(body(42)), 42);
eq("extractValue not-json", extractValue("not json"), undefined);
eq("extractValue empty object", extractValue("{}"), undefined);

eq("ulpEqual 0.1+0.2 == 0.3", ulpEqual(0.1 + 0.2, 0.3), true);
eq("ulpEqual 1 vs 2", ulpEqual(1, 2), false);
eq("ulpEqual non-number", ulpEqual("x", "x"), false);
// NOTE: the verbatim harness ulpEqual short-circuits on `a === b` BEFORE the
// Number.isFinite guard, so ulpEqual(Infinity, Infinity) === true (identical
// references are "equal" first). This is the preserved harness behavior; the
// finite-guard only rejects DISTINCT non-finite operands. We assert the true
// preserved behavior here (the spec's "=== false" expectation conflicts with
// the explicit moved-verbatim mandate and is the looser of the two — preserving
// behavior wins). Infinity vs -Infinity (distinct) is the meaningful guard case.
eq(
  "ulpEqual Infinity,Infinity (a===b short-circuit, verbatim)",
  ulpEqual(Infinity, Infinity),
  true,
);
eq(
  "ulpEqual Infinity,-Infinity (finite guard rejects)",
  ulpEqual(Infinity, -Infinity),
  false,
);
eq("ulpEqual NaN", ulpEqual(NaN, NaN), false);
eq("ulpEqual exact 5,5", ulpEqual(5, 5), true);

// ===========================================================================
// C) gateVerdict — load-bearing gate semantics + every false-negative trap
// ===========================================================================

// PASS happy path.
{
  const v = gateVerdict(
    { "byte-identical": 10, "value-equal": 2 },
    { comparisonsRun: 12 },
  );
  eq("happy pass", v.pass, true);
  eqArr("happy failures empty", v.failures, []);
}

// M4 ULP-MUST-NOT-GATE INVARIANT (headline regression guard).
{
  const v = gateVerdict(
    { "byte-identical": 3, "ulp-differs": 5 },
    { comparisonsRun: 8 },
  );
  eq("ulp-must-not-gate pass", v.pass, true);
  eq("ulp counts as real comparison", v.realComparisons, 8);
}

// differs gates.
{
  const v = gateVerdict(
    { "value-equal": 1, differs: 1 },
    { comparisonsRun: 2 },
  );
  eq("differs gates: pass false", v.pass, false);
  ok("differs gates: code present", v.failures.includes("differs"));
}

// wasm-error gates.
{
  const v = gateVerdict(
    { "byte-identical": 1, "wasm-error": 1 },
    { comparisonsRun: 1 },
  );
  eq("wasm-error gates: pass false", v.pass, false);
  ok("wasm-error gates: code present", v.failures.includes("wasm-error"));
}

// TRAP service-error (today silently passes).
{
  const v = gateVerdict(
    { "byte-identical": 1, "service-error": 1 },
    { comparisonsRun: 1 },
  );
  eq("service-error gates: pass false", v.pass, false);
  ok("service-error gates: code present", v.failures.includes("service-error"));
}

// TRAP compile-fail (broken default corpus): BOTH compile-fail AND
// zero-comparisons because compile-fail contributes 0 comparisons.
{
  const v = gateVerdict({ "compile-fail": 1 }, { comparisonsRun: 0 });
  eq("compile-fail gates: pass false", v.pass, false);
  ok("compile-fail gates: code present", v.failures.includes("compile-fail"));
  ok(
    "compile-fail also trips zero-comparisons",
    v.failures.includes("zero-comparisons"),
  );
}

// Allow-list path: allowCompileFail=[] -> still fails compile-fail (allow-list
// is keyed on the per-file results array in the HARNESS, not the aggregate
// tally; any compile-fail count in the tally fails the gate).
{
  const v = gateVerdict(
    { "byte-identical": 1, "compile-fail": 1 },
    { comparisonsRun: 1, allowCompileFail: ["some-id"] },
  );
  eq("allow-list aggregate still gates: pass false", v.pass, false);
  ok(
    "allow-list aggregate still gates: compile-fail code present",
    v.failures.includes("compile-fail"),
  );
}

// TRAP deploy-fail.
{
  const v = gateVerdict({ "deploy-fail": 1 }, { comparisonsRun: 0 });
  eq("deploy-fail gates: pass false", v.pass, false);
  ok("deploy-fail gates: code present", v.failures.includes("deploy-fail"));
  ok(
    "deploy-fail also trips zero-comparisons",
    v.failures.includes("zero-comparisons"),
  );
}

// TRAP empty corpus / all dropped.
{
  const v = gateVerdict({}, { comparisonsRun: 0 });
  eq("empty corpus: pass false", v.pass, false);
  eqArr("empty corpus: only zero-comparisons", v.failures, [
    "zero-comparisons",
  ]);

  const v2 = gateVerdict(
    { "compile-fail": 2, "deploy-fail": 1 },
    { comparisonsRun: 0 },
  );
  eq("all dropped: pass false", v2.pass, false);
  ok(
    "all dropped: zero-comparisons present",
    v2.failures.includes("zero-comparisons"),
  );
}

// TRAP all refused-unsupported (does NOT count as comparison).
{
  const v = gateVerdict({ "refused-unsupported": 4 }, { comparisonsRun: 0 });
  eq("all refused: pass false", v.pass, false);
  ok(
    "all refused: zero-comparisons present",
    v.failures.includes("zero-comparisons"),
  );
}

// TRAP all skip-no-cases.
{
  const v = gateVerdict({ "skip-no-cases": 3 }, { comparisonsRun: 0 });
  eq("all skip: pass false", v.pass, false);
  ok(
    "all skip: zero-comparisons present",
    v.failures.includes("zero-comparisons"),
  );
}

// TRAP all both-error consistency illusion (non-gating BUT 0 comparisons).
{
  const v = gateVerdict({ "both-error": 7 }, { comparisonsRun: 0 });
  eq("all both-error: pass false", v.pass, false);
  ok(
    "all both-error: zero-comparisons present",
    v.failures.includes("zero-comparisons"),
  );
}

// MIXED: only service-error gates; the non-gating outcomes (value-equal,
// ulp-differs, both-error, refused-unsupported, skip-no-cases) stay non-gating.
{
  const v = gateVerdict(
    {
      "byte-identical": 5,
      "value-equal": 2,
      "ulp-differs": 3,
      differs: 0,
      "service-error": 9,
      "deploy-fail": 0,
      "compile-fail": 0,
      "refused-unsupported": 4,
      "skip-no-cases": 1,
      "both-error": 2,
    },
    { comparisonsRun: 10 },
  );
  eq("mixed: pass false", v.pass, false);
  eqArr("mixed: only service-error gates", v.failures, ["service-error"]);
  eq("mixed: realComparisons", v.realComparisons, 10);
}

// comparisonsRun vs realComparisons cross-check: realComparisons recomputed as
// 10 from tally but comparisonsRun=0 -> fail on the SMALLER (belt-and-suspenders).
{
  const v = gateVerdict({ "byte-identical": 10 }, { comparisonsRun: 0 });
  eq("cross-check: pass false", v.pass, false);
  ok(
    "cross-check: zero-comparisons present",
    v.failures.includes("zero-comparisons"),
  );
  eq("cross-check: realComparisons recomputed", v.realComparisons, 10);
  ok(
    "cross-check: reason notes the mismatch",
    /comparisonsRun=0 != realComparisons=10/.test(v.reason),
    v.reason,
  );
}

// parityFails back-compat field + realComparisons.
// NOTE: realComparisons = byte-identical+value-equal+ulp-differs+differs ONLY.
// wasm-error does NOT count toward realComparisons (per the module's own
// definition and the zero-comparison guard exclusions), so with {differs:3,
// wasm-error:2} realComparisons is 3, not 8. parityFails (differs+wasm-error)
// is the back-compat 5. (The spec's "===8" is an arithmetic slip; the module
// is the ground truth.)
{
  const v = gateVerdict({ differs: 3, "wasm-error": 2 }, { comparisonsRun: 3 });
  eq("parityFails back-compat", v.parityFails, 5);
  eq(
    "parityFails realComparisons (differs only, wasm-error excluded)",
    v.realComparisons,
    3,
  );
}

// Simultaneously vacuous AND divergent reports BOTH codes (guard is independent).
{
  const v = gateVerdict(
    { differs: 0, "compile-fail": 1 },
    { comparisonsRun: 0 },
  );
  ok(
    "vacuous+compile-fail reports both",
    v.failures.includes("zero-comparisons") &&
      v.failures.includes("compile-fail"),
    JSON.stringify(v.failures),
  );
}

// ===========================================================================
// D) HARDENING regression locks (gate-survey "looser, not stricter" holes)
//    These guard the two confirmed exploits the red-team found:
//    (1) a NaN comparisonsRun must NOT disable the zero-comparison guard, and
//    (2) minComparisons must NOT be disable-able by config (floor of 1).
//    Both violated "a harness bug can only make the gate STRICTER" before the
//    fix; each `pass:true` below was a vacuous run reporting PARITY OK.
// ===========================================================================

// (1) NaN comparisonsRun: typeof NaN === 'number' is true and Math.min(NaN,0)
//     is NaN, so `NaN < 1` was false and the guard never fired. Now a
//     non-finite comparisonsRun is IGNORED and we fall back to realComparisons.
{
  const v = gateVerdict({}, { comparisonsRun: NaN });
  eq("NaN comparisonsRun: empty tally FAILS", v.pass, false);
  ok(
    "NaN comparisonsRun: zero-comparisons present",
    v.failures.includes("zero-comparisons"),
    JSON.stringify(v.failures),
  );
  ok(
    "NaN comparisonsRun: reason flags non-finite",
    /comparisonsRun=NaN non-finite/.test(v.reason),
    v.reason,
  );
}
{
  // Vacuous-but-non-empty tallies (only non-comparison outcomes) + NaN counter.
  const a = gateVerdict({ "both-error": 7 }, { comparisonsRun: NaN });
  eq("NaN comparisonsRun: all both-error FAILS", a.pass, false);
  ok(
    "NaN both-error: zero-comparisons",
    a.failures.includes("zero-comparisons"),
  );
  const b = gateVerdict({ "refused-unsupported": 12 }, { comparisonsRun: NaN });
  eq("NaN comparisonsRun: all refused FAILS", b.pass, false);
  ok("NaN refused: zero-comparisons", b.failures.includes("zero-comparisons"));
  const c = gateVerdict({ "skip-no-cases": 9 }, { comparisonsRun: NaN });
  eq("NaN comparisonsRun: all skip FAILS", c.pass, false);
  ok("NaN skip: zero-comparisons", c.failures.includes("zero-comparisons"));
}
{
  // NaN counter but real comparisons DID happen: must PASS via the
  // realComparisons fallback (NaN ignored, larger-is-safer preserved).
  const v = gateVerdict({ "byte-identical": 5 }, { comparisonsRun: NaN });
  eq("NaN comparisonsRun: real comparisons present PASSES", v.pass, true);
  eq("NaN comparisonsRun: realComparisons from tally", v.realComparisons, 5);
}

// (1b) Infinity comparisonsRun is also non-finite -> ignored, fall back.
{
  const present = gateVerdict(
    { "byte-identical": 5 },
    { comparisonsRun: Infinity },
  );
  eq("Infinity comparisonsRun: real comparisons PASSES", present.pass, true);
  const empty = gateVerdict({}, { comparisonsRun: Infinity });
  eq("Infinity comparisonsRun: empty tally FAILS", empty.pass, false);
  ok(
    "Infinity comparisonsRun: zero-comparisons present",
    empty.failures.includes("zero-comparisons"),
  );
}

// (2) minComparisons floor: 0 / negative / non-finite must NOT disable the
//     zero-comparison guard. Clamped to a floor of 1.
{
  const z = gateVerdict({}, { comparisonsRun: 0, minComparisons: 0 });
  eq("minComparisons:0 cannot disable guard (empty FAILS)", z.pass, false);
  ok(
    "minComparisons:0: zero-comparisons present",
    z.failures.includes("zero-comparisons"),
  );

  const neg = gateVerdict({}, { minComparisons: -1 });
  eq("minComparisons:-1 cannot disable guard (empty FAILS)", neg.pass, false);
  ok(
    "minComparisons:-1: zero-comparisons present",
    neg.failures.includes("zero-comparisons"),
  );

  const nan = gateVerdict({}, { minComparisons: NaN });
  eq(
    "minComparisons:NaN falls back to default 1 (empty FAILS)",
    nan.pass,
    false,
  );
  ok(
    "minComparisons:NaN: zero-comparisons present",
    nan.failures.includes("zero-comparisons"),
  );
}

// (2b) minComparisons floor is a FLOOR, not a ceiling: stricter values are
//      still honored so a higher per-corpus floor can detect partial collapse.
{
  const v = gateVerdict(
    { "byte-identical": 3 },
    { comparisonsRun: 3, minComparisons: 5 },
  );
  eq("minComparisons:5 still honored (3 < 5 FAILS)", v.pass, false);
  ok(
    "minComparisons:5: zero-comparisons present",
    v.failures.includes("zero-comparisons"),
  );
  const ok2 = gateVerdict(
    { "byte-identical": 5 },
    { comparisonsRun: 5, minComparisons: 5 },
  );
  eq("minComparisons:5 satisfied (5 >= 5 PASSES)", ok2.pass, true);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
