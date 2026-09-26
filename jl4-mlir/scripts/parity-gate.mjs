// parity-gate.mjs — PURE, side-effect-free gate semantics for the differential
// parity harness. Importing this module pulls in ZERO heavy deps: no
// jl4-runtime, no execFileSync, no spawn, no fetch, no fs. That keeps the unit
// test (parity-gate.test.mjs) runnable under bare `node` with no toolchain.
//
// Three groups of exports:
//   - canonical / extractValue / ulpEqual : moved verbatim from
//     parity-harness.mjs:99-128 (behaviour-identical).
//   - classifyOutcome : a faithful extraction of the trace=none if/else ladder
//     at parity-harness.mjs:337-350. No new behaviour.
//   - gateVerdict : the HARDENED replacement for the inline
//     `parityFails = differs + wasm-error` verdict at parity-harness.mjs:448.
//     This is the SINGLE source of truth for whether a run passes.

// ---- moved verbatim from parity-harness.mjs:99-128 (behaviour-identical) ----

// ---- canonical JSON (sorted keys) for value comparison --------------------
/** Canonical JSON string with sorted object keys (was harness:100-112). */
export function canonical(x) {
  if (Array.isArray(x)) return "[" + x.map(canonical).join(",") + "]";
  if (x && typeof x === "object")
    return (
      "{" +
      Object.keys(x)
        .sort()
        .map((k) => JSON.stringify(k) + ":" + canonical(x[k]))
        .join(",") +
      "}"
    );
  return JSON.stringify(x);
}

/** Pull contents.result.value out of a jl4-service / wasm response body string;
 *  undefined on parse failure (was harness:113-119). */
export const extractValue = (body) => {
  try {
    return JSON.parse(body)?.contents?.result?.value;
  } catch {
    return undefined;
  }
};

// Are two values numerically equal to within a few ULP? This isolates the
// known f64-vs-exact-rational drift (M4) from genuine logic divergence so the
// harness can gate on the latter without being permanently red on the former.
/** True iff a,b are finite numbers equal within ~1 ULP band (was harness:123-128).
 *  rel/abs tol: Math.abs(a-b) <= 1e-9 * Math.max(1, |a|, |b|). */
export function ulpEqual(a, b) {
  if (typeof a !== "number" || typeof b !== "number") return false;
  if (a === b) return true;
  if (!Number.isFinite(a) || !Number.isFinite(b)) return false;
  return Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(a), Math.abs(b));
}

// ---- classification (faithful extraction of harness:337-350) --------------

/**
 * classifyOutcome — the trace=none classifier, byte-for-byte the same if/else
 * ladder as harness:339-350. NO new behavior; all hardening lives in
 * gateVerdict.
 *
 * @param {Object}  p
 * @param {number}  p.svcStatus  jl4-service HTTP status (svcR.status).
 *        svcOk := 200 <= svcStatus < 300.
 * @param {?string} p.svcBody    jl4-service response body text (svcR.body).
 * @param {?string} p.wasmBody   wasm-rendered body text, or null if wasm threw.
 * @param {?string} p.wasmErr    truthy error string if the wasm path threw,
 *        else null/undefined.
 * @returns {('byte-identical'|'value-equal'|'ulp-differs'|'differs'|'wasm-error'|'service-error'|'both-error')}
 *
 * Exact ladder (unchanged from harness:338-350):
 *   svcOk = svcStatus >= 200 && svcStatus < 300
 *   if (wasmErr && !svcOk)                              -> 'both-error'
 *   else if (wasmErr)                                   -> 'wasm-error'
 *   else if (!svcOk)                                    -> 'service-error'
 *   else if (svcBody === wasmBody)                      -> 'byte-identical'
 *   else if (canonical(extractValue(svcBody)) ===
 *            canonical(extractValue(wasmBody)))         -> 'value-equal'
 *   else if (ulpEqual(extractValue(svcBody),
 *                     extractValue(wasmBody)))          -> 'ulp-differs'
 *   else                                                -> 'differs'
 */
export function classifyOutcome({ svcStatus, svcBody, wasmBody, wasmErr }) {
  const svcOk = svcStatus >= 200 && svcStatus < 300;
  if (wasmErr && !svcOk) return "both-error";
  else if (wasmErr) return "wasm-error";
  else if (!svcOk) return "service-error";
  else if (svcBody === wasmBody) return "byte-identical";
  else if (
    canonical(extractValue(svcBody)) === canonical(extractValue(wasmBody))
  )
    return "value-equal";
  else if (ulpEqual(extractValue(svcBody), extractValue(wasmBody)))
    return "ulp-differs";
  else return "differs";
}

// ---- gate verdict (the HARDENED replacement for harness:448) --------------

/**
 * gateVerdict — the SINGLE source of truth for whether the run passes.
 * Replaces the inline `parityFails = differs + wasm-error` at harness:448,
 * which only ever gated on those two outcomes and silently passed broken /
 * vacuous runs.
 *
 * @param {Object<string,number>} tally  outcome -> count (the harness's
 *        `tally`, including compile-fail / deploy-fail / refused-unsupported /
 *        skip-no-cases / both-error / service-error rows). Missing keys read
 *        as 0.
 * @param {Object}  [opts]
 * @param {number}  [opts.comparisonsRun]  number of cells where BOTH backends
 *        produced a comparable value (the harness's own running counter).
 *        gateVerdict ALSO recomputes the guard from the tally (realComparisons)
 *        as a cross-check; the gate fails on the SMALLER of the two
 *        (larger-is-safer / fail if EITHER < minComparisons) and the reason
 *        string appends a WARN if they disagree.
 * @param {string[]} [opts.allowCompileFail=[]]  reviewed file-ids explicitly
 *        permitted to compile-fail. NOTE: the aggregate `tally` is opaque to
 *        file-ids, so allow-listing is enforced by the HARNESS subtracting
 *        reviewed file-ids from the compile-fail count it puts into the tally.
 *        Inside gateVerdict, ANY remaining compile-fail in the tally fails the
 *        gate (allowCompileFail is recorded in the reason for traceability
 *        only). See openRisks "Allow-list granularity gap".
 * @param {string[]} [opts.allowDeployFail=[]]   same contract for deploy-fail.
 * @param {number}  [opts.minComparisons=1]  minimum real comparisons required.
 *
 * @returns {{ pass: boolean, failures: string[], reason: string,
 *             parityFails: number, realComparisons: number }}
 *   failures: machine-readable reason codes, any of:
 *     'zero-comparisons' | 'differs' | 'wasm-error' | 'service-error' |
 *     'compile-fail' | 'deploy-fail'
 *   reason: one-line human summary for parity.txt / step summary.
 *
 * realComparisons := byte-identical + value-equal + ulp-differs + differs
 *   — the ONLY four outcomes where each side produced a comparable value.
 *   both-error / service-error / refused-unsupported / skip-no-cases /
 *   compile-fail / deploy-fail and ALL trace-* outcomes contribute 0.
 *
 * pass === (failures.length === 0). The harness sets process.exit(pass ? 0 : 1).
 */
export function gateVerdict(tally, opts = {}) {
  const t = tally || {};
  const get = (k) => t[k] || 0;
  const {
    comparisonsRun,
    allowCompileFail = [],
    allowDeployFail = [],
    minComparisons: rawMinComparisons = 1,
  } = opts;

  // The zero-comparison guard is the unconditional vacuous-run backstop; it
  // must be impossible to DISABLE by configuration. A minComparisons of 0 (or
  // negative, or non-finite) would make `effectiveComparisons < minComparisons`
  // vacuously false and let an empty/all-error corpus report PARITY OK. Clamp
  // to a floor of 1 so the guard can only ever be made STRICTER, never weaker.
  const minComparisons = Number.isFinite(rawMinComparisons)
    ? Math.max(1, rawMinComparisons)
    : 1;

  // The four outcomes where BOTH sides produced a comparable value.
  const realComparisons =
    get("byte-identical") +
    get("value-equal") +
    get("ulp-differs") +
    get("differs");

  // Back-compat number the harness used to log at line 448.
  const parityFails = get("differs") + get("wasm-error");

  const failures = [];
  const notes = [];

  // ---- ZERO-COMPARISON GUARD (checked FIRST, independent of everything) ----
  // A vacuous run (empty/broken corpus, all-both-error, all-refused, all-skip,
  // every file dropped to compile/deploy-fail) must NEVER report PARITY OK.
  // Belt-and-suspenders: fail on the SMALLER of comparisonsRun (the harness's
  // own counter, if supplied) and realComparisons (recomputed from the tally).
  // This wiring means a harness accumulation bug can only make the gate
  // STRICTER, never looser.
  //
  // CRITICAL: only HONOR comparisonsRun when it is a finite number. A bare
  // `typeof comparisonsRun === "number"` is true for NaN (typeof NaN ===
  // "number"), and Math.min(NaN, x) === NaN while `NaN < minComparisons` is
  // always false — so a harness bug producing NaN would silently DISABLE the
  // guard and let a vacuous run pass, the exact "looser, not stricter"
  // violation this guard exists to prevent. realComparisons is recomputed from
  // the tally (each term is `t[k]||0`) so it is provably never NaN; falling
  // back to it when comparisonsRun is non-finite preserves larger-is-safer.
  const comparisonsRunIsFinite = Number.isFinite(comparisonsRun);
  const effectiveComparisons = comparisonsRunIsFinite
    ? Math.min(comparisonsRun, realComparisons)
    : realComparisons;
  if (typeof comparisonsRun === "number" && !comparisonsRunIsFinite) {
    // A non-finite (NaN/Infinity) comparisonsRun is itself a harness bug worth
    // surfacing; we ignore it for the verdict but flag it loudly.
    notes.push(
      `WARN: comparisonsRun=${comparisonsRun} non-finite, ignored (using realComparisons=${realComparisons})`,
    );
  } else if (comparisonsRunIsFinite && comparisonsRun !== realComparisons) {
    notes.push(
      `WARN: comparisonsRun=${comparisonsRun} != realComparisons=${realComparisons}`,
    );
  }
  if (effectiveComparisons < minComparisons) {
    failures.push("zero-comparisons");
  }

  // ---- genuine logic divergence (preserved from harness:448) ----
  if (get("differs") > 0) failures.push("differs");

  // ---- WASM trapped where the reference succeeded (preserved) ----
  if (get("wasm-error") > 0) failures.push("wasm-error");

  // ---- NEW: a success-vs-failure disagreement between backends gates ----
  if (get("service-error") > 0) failures.push("service-error");

  // ---- NEW: an input that cannot be compiled to WASM gates ----
  // Per the allow-list contract, the harness has already subtracted any
  // reviewed file-ids from the count in the tally, so ANY remaining count
  // fails the gate.
  if (get("compile-fail") > 0) failures.push("compile-fail");

  // ---- NEW: jl4-service rejected the same source gates ----
  if (get("deploy-fail") > 0) failures.push("deploy-fail");

  const pass = failures.length === 0;

  // ---- human-readable one-liner for parity.txt / step summary ----
  let reason;
  if (pass) {
    const ulp = get("ulp-differs");
    reason =
      `PARITY OK: ${realComparisons} real comparisons` +
      (ulp ? `, ${ulp} known ULP drift (M4)` : "");
  } else {
    const parts = [];
    if (failures.includes("zero-comparisons"))
      parts.push(
        "vacuous run: 0 real comparisons (corpus empty/broken or every cell errored/skipped)",
      );
    if (get("differs") > 0) parts.push(`${get("differs")} differs`);
    if (get("wasm-error") > 0) parts.push(`${get("wasm-error")} wasm-error`);
    if (get("service-error") > 0)
      parts.push(`${get("service-error")} service-error`);
    if (get("compile-fail") > 0)
      parts.push(`${get("compile-fail")} compile-fail`);
    if (get("deploy-fail") > 0) parts.push(`${get("deploy-fail")} deploy-fail`);
    reason = "PARITY FAIL: " + parts.join("; ");
  }
  // Record allow-list opts for traceability (the per-file subtraction happens
  // in the harness; this just documents what was reviewed).
  if (allowCompileFail.length)
    notes.push(`allowCompileFail=[${allowCompileFail.join(",")}]`);
  if (allowDeployFail.length)
    notes.push(`allowDeployFail=[${allowDeployFail.join(",")}]`);
  if (notes.length) reason += " (" + notes.join("; ") + ")";

  return { pass, failures, reason, parityFails, realComparisons };
}
