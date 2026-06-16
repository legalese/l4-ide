// Standalone tests for the JS side of the WASM runtime
// (runtime/jl4-runtime.mjs). The Haskell test suite covers lowering and
// schema; this covers the runtime imports the compiled .wasm calls into.
//
// No WASM toolchain required — we drive the import functions directly
// against a real WebAssembly.Memory, exactly as a compiled module would.
//
//   node runtime/jl4-runtime.test.mjs

import {
  createRuntime,
  makeTracePool,
  MemoryLimitError,
  DEFAULT_MAX_HEAP_BYTES,
  DeonticInputError,
  runDeontic,
} from "./jl4-runtime.mjs";

const rt = createRuntime();
rt.attachMemory(new WebAssembly.Memory({ initial: 4 }));
const { env } = rt.makeImports();

// Box a JS string into the f64-bit-pattern-of-a-pointer the ABI uses;
// unbox the reverse.
const box = (s) => rt.u64ToF64(rt.writeString(s));
const unbox = (f) => rt.readCString(Number(rt.f64ToU64(f)));

let pass = 0;
let fail = 0;
const eq = (name, got, want) => {
  const ok = got === want;
  console.log(
    `${ok ? "ok  " : "FAIL"} ${name}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`,
  );
  ok ? pass++ : fail++;
};

// Assert that 'fn' throws, optionally matching a predicate on the error.
// Prints ok/FAIL like 'eq' so it slots into the same pass/fail tally.
const throws = (name, fn, pred) => {
  let threw = false;
  let err = null;
  try {
    fn();
  } catch (e) {
    threw = true;
    err = e;
  }
  const ok = threw && (pred ? pred(err) : true);
  console.log(
    `${ok ? "ok  " : "FAIL"} ${name}: ${
      threw ? `threw ${err && err.name}: ${err && err.message}` : "did NOT throw"
    }`,
  );
  ok ? pass++ : fail++;
};

// Expected-to-fail (TDD): encodes a behavior we intend to implement but
// haven't yet, documenting the target without breaking the suite. `fn`
// returns true iff the DESIRED behavior already holds.
//   throws / returns false → xfail (pending): logged, suite stays green
//   returns true           → XPASS: the feature landed; promote to a real `eq`
let xfailPending = 0;
let xpass = 0;
const xfail = (name, fn) => {
  let ok = false;
  let info = "";
  try {
    ok = fn() === true;
  } catch (e) {
    info = ` (throws ${e && e.name})`;
  }
  if (ok) {
    console.log(`XPASS ${name}: now passes — promote to a real test`);
    xpass++;
  } else {
    console.log(`xfail ${name}: pending${info}`);
    xfailPending++;
  }
};

// --- __l4_str_concat (M1b: was an identity stub) ---
eq("concat", unbox(env.__l4_str_concat(box("foo"), box("bar"))), "foobar");
eq("concat empty lhs", unbox(env.__l4_str_concat(box(""), box("x"))), "x");
eq("concat empty rhs", unbox(env.__l4_str_concat(box("x"), box(""))), "x");
eq(
  "concat unicode",
  unbox(env.__l4_str_concat(box("café "), box("☕"))),
  "café ☕",
);

// --- __l4_str_len (M1b: was a `() => 0` stub) ---
eq("len ascii", env.__l4_str_len(box("hello")), 5);
eq("len empty", env.__l4_str_len(box("")), 0);

// --- __l4_str_eq (M1b: was comparing pointers, not contents) ---
eq(
  "eq same content, different pointers",
  env.__l4_str_eq(box("abc"), box("abc")),
  1,
);
eq("eq different", env.__l4_str_eq(box("abc"), box("abd")), 0);

// --- __l4_to_string (M4 slice 2b: NUMBER args are rational handles) ---
const num = (decimalText) => env.__l4_rat_parse(box(decimalText));
eq("to_string int", unbox(env.__l4_to_string(num("5"))), "5");
eq("to_string negative int", unbox(env.__l4_to_string(num("-3"))), "-3");
eq("to_string fractional", unbox(env.__l4_to_string(num("3.5"))), "3.5");
eq("to_string zero", unbox(env.__l4_to_string(num("0"))), "0");
// 0.1 + 0.2 = 0.3 exactly (was 0.30000000000000004 under f64)
const r = env.__l4_rat_add(num("0.1"), num("0.2"));
eq("0.1 + 0.2 == 0.3 (rat-exact)", env.__l4_rat_cmp(r, num("0.3")), 0);

// --- composition: a concat result must be a valid string downstream ---
const c = env.__l4_str_concat(box("a"), box("b"));
eq("concat then len", env.__l4_str_len(c), 2);
eq("concat then eq", env.__l4_str_eq(c, box("ab")), 1);

// --- M5 slice 2B: makeTracePool stack semantics ---
// enter/exit pairs build a tree; exit on an empty stack saves the popped
// frame as `root`. Mirrors what `<fn>$trace` codegen produces around the
// body root (a single enter/exit pair => one-node root).
{
  const pool = makeTracePool();
  pool.enter(0);
  pool.exit(42, 0); // NUMBER kind
  const r = pool.root;
  eq("trace pool: root.nodeId after single enter/exit", r.nodeId, 0);
  eq("trace pool: root.result.raw", r.result.raw, 42);
  eq("trace pool: root.result.kind", r.result.kind, 0);
  eq("trace pool: root.children empty", r.children.length, 0);
  eq("trace pool: stackDepth after exit", pool.stackDepth, 0);
}
// Nested enter/exit (parent + child): the child must attach to parent
// before parent exits, and root is the parent.
{
  const pool = makeTracePool();
  pool.enter(0); // parent
  pool.enter(1); // child
  pool.exit(7, 1); // child exits → attaches to parent
  pool.exit(99, 0); // parent exits → root
  const r = pool.root;
  eq("trace pool: nested root.nodeId", r.nodeId, 0);
  eq("trace pool: nested children.length", r.children.length, 1);
  eq("trace pool: nested child.nodeId", r.children[0].nodeId, 1);
}
// reset clears both the stack and the saved root.
{
  const pool = makeTracePool();
  pool.enter(0);
  pool.exit(0, 0);
  pool.reset();
  eq("trace pool: reset clears root", pool.root, null);
  eq("trace pool: reset clears stack", pool.stackDepth, 0);
}

// --- M5 slice 2B end-to-end via the createRuntime imports ---
// The `__l4_trace_enter` / `__l4_trace_exit` env imports must route
// through to the per-instance trace pool. Smoke-test that the pool
// receives the calls correctly.
{
  const rt2 = createRuntime();
  rt2.attachMemory(new WebAssembly.Memory({ initial: 2 }));
  const { env: env2 } = rt2.makeImports();
  env2.__l4_trace_enter(0);
  env2.__l4_trace_exit(123, 0);
  // tracePool is internal to the runtime; we verify indirectly by
  // running invokeFunctionWithReasoning on a stub instance below.
  eq("trace ABI: env imports exist", typeof env2.__l4_trace_enter, "function");
  eq(
    "trace ABI: env imports exist (exit)",
    typeof env2.__l4_trace_exit,
    "function",
  );
}

// --- M7 slice 1: per-eval memory cap ----------------------------------
// 'allocBytes' must throw 'MemoryLimitError' once the cumulative
// allocation since 'resetHeap' would push past 'maxHeapBytes'. Catching
// gives the HTTP wrapper a chance to surface a 413 and re-instantiate
// the wasm module on the next request.
{
  // 4 KiB cap leaves room for the bump-pointer's leading 1 KiB
  // reserved region; the test allocates 8 KiB in 1 KiB chunks.
  const tiny = createRuntime({ maxHeapBytes: 4 * 1024 });
  tiny.attachMemory(new WebAssembly.Memory({ initial: 1 }));
  let threw = false;
  let underCapAllocs = 0;
  try {
    for (let i = 0; i < 16; i++) {
      tiny.allocBytes(1024);
      underCapAllocs++;
    }
  } catch (e) {
    threw = e instanceof MemoryLimitError;
  }
  eq("memory cap: throws MemoryLimitError", threw, true);
  eq(
    "memory cap: stopped before exhausting cap",
    underCapAllocs <= 3, // 3 × 1024 = 3072 ≤ 4096-1024 reserved
    true,
  );
  eq(
    "memory cap: peak tracked",
    tiny.getPeakHeapBytes() >= underCapAllocs * 1024,
    true,
  );
  // After resetHeap, the next allocation should succeed again.
  tiny.resetHeap();
  let postReset = -1;
  try {
    postReset = tiny.allocBytes(512);
  } catch {
    postReset = -1;
  }
  eq("memory cap: resetHeap clears state", postReset > 0, true);
  eq("memory cap: resetHeap clears peak", tiny.getPeakHeapBytes(), 512);
}

// Default cap is 64 MiB — published as a public constant so the HTTP
// wrapper and tests stay in sync without hard-coding the number.
eq("memory cap: default constant", DEFAULT_MAX_HEAP_BYTES, 64 * 1024 * 1024);

// --- Deontic: null/absent contract must FAIL LOUD, never FULFILLED ----
// Regression for the silent-wrong-answer bug: a deontic function whose
// 'deonticContract' is null/undefined was returning FULFILLED on the
// trace path (runDeonticInternal walked a null tree). It must throw on
// BOTH the value path (invokeFunction → invokeDeontic) and the trace
// path (invokeFunctionWithReasoning), plus via the exported runDeontic.
{
  const rt3 = createRuntime();
  rt3.attachMemory(new WebAssembly.Memory({ initial: 1 }));
  // Deontic dispatch skips the wasm body, so a stub instance is fine.
  const stubInstance = { exports: {} };
  // A well-formed deontic request (startTime + events present) so the
  // ONLY thing that can go wrong is the missing contract — proving the
  // null-contract guard fires rather than the startTime/events guards.
  const goodArgs = { startTime: 0, events: [] };
  const isDeonticErr = (e) => e instanceof DeonticInputError;

  // null contract
  const metaNull = {
    isDeontic: true,
    deonticContract: null,
    parameters: { properties: {} },
    paramOrder: [],
  };
  throws(
    "deontic: null contract throws on VALUE path",
    () => rt3.invokeFunction(stubInstance, metaNull, goodArgs),
    isDeonticErr,
  );
  throws(
    "deontic: null contract throws on TRACE path",
    () => rt3.invokeFunctionWithReasoning(stubInstance, metaNull, goodArgs),
    isDeonticErr,
  );

  // absent contract (key entirely missing — undefined)
  const metaAbsent = {
    isDeontic: true,
    parameters: { properties: {} },
    paramOrder: [],
  };
  throws(
    "deontic: absent contract throws on VALUE path",
    () => rt3.invokeFunction(stubInstance, metaAbsent, goodArgs),
    isDeonticErr,
  );
  throws(
    "deontic: absent contract throws on TRACE path",
    () => rt3.invokeFunctionWithReasoning(stubInstance, metaAbsent, goodArgs),
    isDeonticErr,
  );

  // Exported runDeontic in isolation also refuses a null contract.
  throws(
    "deontic: runDeontic(null, …) throws (no silent FULFILLED)",
    () => runDeontic(null, 0, [], {}, null),
    isDeonticErr,
  );

  // Sanity: a well-formed MUST contract with no events still produces a
  // residual OBLIGATION (proving the guards above didn't over-fire and
  // that the normal MUST path is unaffected).
  const mustContract = {
    kind: "OBLIGATION",
    modal: "MUST",
    party: "buyer",
    action: "pay",
    deadline: 14,
  };
  const mustResult = runDeontic(mustContract, 0, [], {}, null);
  eq(
    "deontic: MUST contract with no events is a residual OBLIGATION",
    !!(mustResult && mustResult.OBLIGATION),
    true,
  );

  // Task 2: a reached MUSTNOT (prohibition) node must be REFUSED loudly
  // rather than computing the inverted FULFILLED. MUST/MAY fixtures
  // never carry this modal, so they remain unaffected.
  const mustNotContract = {
    kind: "OBLIGATION",
    modal: "MUSTNOT",
    party: "driver",
    action: "speed",
    deadline: 14,
  };
  throws(
    "deontic: MUSTNOT (prohibition) is refused, not inverted",
    () =>
      runDeontic(
        mustNotContract,
        0,
        [{ party: "driver", action: "speed", at: 1 }],
        {},
        null,
      ),
    (e) => e instanceof DeonticInputError && /MUSTNOT/.test(e.message),
  );
}

// ---------------------------------------------------------------------------
// TDD (expected-fail): bold deontic claims from the docs, not yet realized.
// These encode jl4-core's prohibition semantics (EvaluateLazy/Machine.hs) and
// go RED today because QW2 refuses MUSTNOT loudly. When correct prohibition
// support lands they XPASS — at which point promote them to `eq` and delete
// the "MUSTNOT refused" guard test above. Tracked in
// specs/todo/mlir-parity-fixes.md (deontic semantics, full fix).
// ---------------------------------------------------------------------------
{
  const prohibition = {
    kind: "OBLIGATION",
    modal: "MUSTNOT",
    party: "driver",
    action: "speed",
    deadline: 14,
  };
  // Machine.hs:1038-1042 — the prohibited action performed before the deadline
  // is a VIOLATION → LEST, or immediate BREACH when there is no LEST clause;
  // never FULFILLED (the inversion QW2 currently guards against by refusing).
  xfail(
    "deontic: MUSTNOT + prohibited act before deadline → BREACH (not FULFILLED)",
    () => {
      const r = runDeontic(
        prohibition,
        0,
        [{ party: "driver", action: "speed", at: 1 }],
        {},
        null,
      );
      return r !== "FULFILLED" && !(r && r.OBLIGATION);
    },
  );
  // Machine.hs:983-986 — deadline passes with the prohibited action never taken:
  // the prohibition was RESPECTED → HENCE, defaulting to FULFILLED.
  xfail(
    "deontic: MUSTNOT respected (no prohibited act by deadline) → FULFILLED",
    () => runDeontic(prohibition, 0, [], {}, null) === "FULFILLED",
  );
}

console.log(
  `\n${pass} passed, ${fail} failed, ${xfailPending} xfail (pending), ${xpass} XPASS`,
);
process.exit(fail ? 1 : 0);
