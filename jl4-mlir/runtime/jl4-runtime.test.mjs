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

// --- __l4_str_cmp (ledger #7: ordered STRING comparison) ---
// Returns -1/0/1, lexicographic by Unicode CODE POINT (Data.Text Ord),
// NOT UTF-16 code units. clears britishcitizen5's date-string ordering.
eq("cmp equal", env.__l4_str_cmp(box("abc"), box("abc")), 0);
eq("cmp less (last char)", env.__l4_str_cmp(box("abc"), box("abd")), -1);
eq("cmp greater (last char)", env.__l4_str_cmp(box("abd"), box("abc")), 1);
// Prefix: shorter sorts first.
eq("cmp prefix a<ab", env.__l4_str_cmp(box("ab"), box("abc")), -1);
eq("cmp prefix ab>a", env.__l4_str_cmp(box("abc"), box("ab")), 1);
// Empty string is the least element.
eq("cmp empty < nonempty", env.__l4_str_cmp(box(""), box("a")), -1);
eq("cmp nonempty > empty", env.__l4_str_cmp(box("a"), box("")), 1);
eq("cmp empty == empty", env.__l4_str_cmp(box(""), box("")), 0);
// Date-string ordering (britishcitizen5's actual use): YYYY-MM-DD sorts
// lexicographically == chronologically.
eq(
  "cmp date before commencement",
  env.__l4_str_cmp(box("1980-01-01"), box("1983-01-01")),
  -1,
);
eq(
  "cmp date equal commencement",
  env.__l4_str_cmp(box("1983-01-01"), box("1983-01-01")),
  0,
);
eq(
  "cmp date after commencement",
  env.__l4_str_cmp(box("1990-06-15"), box("1983-01-01")),
  1,
);
// UNICODE TRAP: astral-plane char vs high-BMP char. "😀" is U+1F600
// (code point 128512), "" is U+E000 (57344). By CODE POINT, 😀 > .
// JS-native `<` on the strings would say 😀 <  (UTF-16 high surrogate
// 0xD83D < 0xE000) — the WRONG answer. str_cmp must return +1.
eq(
  "cmp astral > high-BMP (code point, not code unit)",
  env.__l4_str_cmp(box("😀"), box("")),
  1,
);
eq(
  "cmp high-BMP < astral (symmetric)",
  env.__l4_str_cmp(box(""), box("😀")),
  -1,
);
// Sanity: JS native `<` really does disagree here (documents the trap).
eq("native < disagrees on the trap", "😀" < "", true);
// Two astral chars compare by code point too.
eq(
  "cmp astral vs astral",
  env.__l4_str_cmp(box("😀"), box("😁")), // U+1F600 < U+1F601
  -1,
);

// --- embedded NUL (U+0000) round-trip: str-ordering lane blocker fix ---
// A STRING may legitimately CONTAIN a 0x00 byte. The wire ABI stores
// strings NUL-terminated, so a naive C-string reader truncates at the
// first embedded NUL and would compare truncated prefixes — a silent
// wrong answer vs jl4-service's Data.Text (which keeps the whole string).
// writeString records the exact byte length; readCString recovers it.
const NUL = String.fromCharCode(0); // U+0000, one 0x00 byte in UTF-8
eq("NUL round-trip len", env.__l4_str_len(box("a" + NUL + "b")), 3);
eq("NUL round-trip readback", unbox(box("a" + NUL + "b")), "a" + NUL + "b");
// "a\0" != "a": broken reader truncates both to "a" and reports EQUAL.
eq("cmp a\\0 vs a not-equal", env.__l4_str_cmp(box("a" + NUL), box("a")), 1);
eq("eq a\\0 vs a is false", env.__l4_str_eq(box("a" + NUL), box("a")), 0);
// "a" is a proper prefix of "a\0b": ordered comparison must see it.
eq("cmp a < a\\0b", env.__l4_str_cmp(box("a"), box("a" + NUL + "b")), -1);
// differ only AFTER an embedded NUL: truncating reader would call these
// equal; the length-aware reader compares the full strings.
eq(
  "cmp a\\0b < a\\0c",
  env.__l4_str_cmp(box("a" + NUL + "b"), box("a" + NUL + "c")),
  -1,
);
eq(
  "eq a\\0b vs a\\0c is false",
  env.__l4_str_eq(box("a" + NUL + "b"), box("a" + NUL + "c")),
  0,
);
// bare NUL vs empty must not both read as "".
eq("cmp \\0 > empty", env.__l4_str_cmp(box(NUL), box("")), 1);

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

// --- index-carrying string builtins are code-POINT, not code-unit ---
// jl4-service is Data.Text (counts/indexes by Unicode code point); naive
// JS .length/.indexOf/.charAt/.substring count UTF-16 code units. "😀"
// (U+1F600) is one code point but two units, so every astral case below
// is branch-crossing between the two semantics.
const ratEq = (name, gotHandle, wantDecimal) =>
  eq(name, env.__l4_rat_cmp(gotHandle, num(wantDecimal)), 0);
// STRINGLENGTH — Text.length.
ratEq("strlen astral is 1", env.__l4_string_length(box("😀")), "1");
ratEq("strlen mixed", env.__l4_string_length(box("a😀b")), "3");
ratEq("strlen ascii control", env.__l4_string_length(box("hello")), "5");
ratEq("strlen empty", env.__l4_string_length(box("")), "0");
// INDEXOF — prefix length in code points; not-found → -1; empty → 0.
ratEq("indexof after astral", env.__l4_index_of(box("😀x"), box("x")), "1");
ratEq(
  "indexof after two astrals",
  env.__l4_index_of(box("a😀b😀c"), box("c")),
  "4",
);
ratEq(
  "indexof ascii control",
  env.__l4_index_of(box("hello world"), box("world")),
  "6",
);
ratEq("indexof not found", env.__l4_index_of(box("abc"), box("z")), "-1");
ratEq("indexof empty needle", env.__l4_index_of(box("abc"), box("")), "0");
// CHARAT — Text.index by code point; out of bounds (either side) → "".
eq("charat after astral", unbox(env.__l4_char_at(box("😀x"), num("1"))), "x");
eq(
  "charat astral itself (no surrogate split)",
  unbox(env.__l4_char_at(box("a😀b"), num("1"))),
  "😀",
);
eq("charat oob", unbox(env.__l4_char_at(box("hello"), num("5"))), "");
eq("charat negative", unbox(env.__l4_char_at(box("hello"), num("-1"))), "");
// SUBSTRING(s, start, len) — Text.take len (Text.drop start s): the
// third arg is a LENGTH, not an end index (JS .substring("hello",1,3)
// gives "el" — wrong), and both counts are code points.
eq(
  "substring third arg is a length",
  unbox(env.__l4_substring(box("hello"), num("1"), num("3"))),
  "ell",
);
eq(
  "substring astral (code-point slicing)",
  unbox(env.__l4_substring(box("😀😀x"), num("1"), num("2"))),
  "😀x",
);
eq(
  "substring negative start clamps to 0",
  unbox(env.__l4_substring(box("hello"), num("-2"), num("3"))),
  "hel",
);
eq(
  "substring zero len",
  unbox(env.__l4_substring(box("hello"), num("0"), num("0"))),
  "",
);
eq(
  "substring negative len",
  unbox(env.__l4_substring(box("hello"), num("2"), num("-1"))),
  "",
);
eq(
  "substring len overrun clamps",
  unbox(env.__l4_substring(box("hello"), num("3"), num("99"))),
  "lo",
);

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
// Regression: the three adversarially-found blockers on supported:true deontic
// fixtures. jl4-service is the reference; these lock the runtime to it.
//   1. events are replayed in SUBMISSION order (no sort) — an out-of-order
//      stream must not invert FULFILLED/BREACH.
//   2. every breach serializes as a STRUCTURED object (never bare "BREACH"):
//      explicit LEST BREACH → {reason:"explicit",…}; a MUST lapse with no LEST
//      → {reason:"deadline_missed",…}.
//   3. an unexercised MAY surfaces a residual OBLIGATION, not FULFILLED.
// ---------------------------------------------------------------------------
{
  const jeq = (name, got, want) =>
    eq(name, JSON.stringify(got), JSON.stringify(want));

  // Sale cascade: seller MUST deliver WITHIN 14 (LEST BREACH), then buyer MUST
  // pay WITHIN 30 (LEST BREACH).
  const sale = {
    kind: "OBLIGATION",
    modal: "MUST",
    party: "`the seller`",
    action: "`deliver the goods`",
    deadline: 14,
    hence: {
      kind: "OBLIGATION",
      modal: "MUST",
      party: "`the buyer`",
      action: "`pay the invoice`",
      deadline: 30,
      hence: { kind: "FULFILLED" },
      lest: { kind: "BREACH", by: null, because: null },
    },
    lest: { kind: "BREACH", by: null, because: null },
  };

  // Blocker 1 — out-of-order events must NOT be sorted. deliver@20 precedes
  // deliver@5; the first event (20) is already past the WITHIN-14 deadline, so
  // the seller obligation lapses to its explicit LEST BREACH.
  jeq(
    "deontic: out-of-order events replay in submission order → BREACH",
    runDeontic(sale, 0, [
      { party: "the seller", action: "deliver the goods", at: 20 },
      { party: "the seller", action: "deliver the goods", at: 5 },
    ], {}, null),
    { BREACH: { detail: null, party: null, reason: "explicit" } },
  );
  // Control: the same multiset in ascending order fulfils the first leg and
  // leaves a residual buyer obligation — proving order is the sole driver.
  eq(
    "deontic: ascending order does NOT breach the seller leg",
    !!runDeontic(sale, 0, [
      { party: "the seller", action: "deliver the goods", at: 5 },
      { party: "the seller", action: "deliver the goods", at: 20 },
    ], {}, null).OBLIGATION,
    true,
  );

  // Blocker 2a — clause-less explicit LEST BREACH serializes as a structured
  // object, never the bare string "BREACH".
  jeq(
    "deontic: clause-less LEST BREACH → structured explicit object",
    runDeontic(sale, 0, [
      { party: "the seller", action: "deliver the goods", at: 15 },
    ], {}, null),
    { BREACH: { detail: null, party: null, reason: "explicit" } },
  );

  // Blocker 2a — explicit LEST BREACH BY p BECAUSE r carries party/detail.
  const repay = {
    kind: "OBLIGATION",
    modal: "MUST",
    party: "`the borrower`",
    action: "`repay loan`",
    deadline: 30,
    hence: { kind: "FULFILLED" },
    lest: { kind: "BREACH", by: "`the borrower`", because: '"loan not repaid"' },
  };
  jeq(
    "deontic: explicit BREACH BY/BECAUSE → party + detail",
    runDeontic(repay, 0, [
      { party: "the borrower", action: "repay loan", at: 100 },
    ], {}, null),
    { BREACH: { detail: "loan not repaid", party: "`the borrower`", reason: "explicit" } },
  );

  // Blocker 2b — a MUST with NO LEST that lapses → deadline_missed breach that
  // names the lapsing event's party/action/time and the obligation's deadline.
  const seatbeltMust = {
    kind: "OBLIGATION",
    modal: "MUST",
    party: { param: "driver" },
    action: "`wear seatbelt`",
    deadline: 1,
    hence: {
      kind: "OBLIGATION",
      modal: "MAY",
      party: { param: "driver" },
      action: "drive",
      deadline: null,
    },
  };
  const driverMeta = {
    parameters: { properties: { driver: { "x-l4-type": "Driver" } } },
  };
  jeq(
    "deontic: MUST lapse without LEST → deadline_missed structured breach",
    runDeontic(
      seatbeltMust,
      0,
      [{ party: { name: "Alice" }, action: "wear seatbelt", at: 2 }],
      { driver: { name: "Alice" } },
      driverMeta,
    ),
    {
      BREACH: {
        deadline: 1,
        // eventAction is the event's own action name, which the reference
        // renders PLAIN (a9caf2f6 replaced prettyLayout with constructorText
        // in Backend.Jl4). obligationAction on the very same object keeps its
        // backticks, because that one is still prettyLayout of an unevaluated
        // Name in ValueLazyJSON. The asymmetry is the reference's, not ours,
        // and the live differential run agrees: deontic-seatbelt is
        // byte-identical against jl4-service with exactly these two spellings.
        eventAction: "wear seatbelt",
        eventParty: { Driver: { name: "Alice" } },
        obligationAction: "`wear seatbelt`",
        reason: "deadline_missed",
        timestamp: 2,
      },
    },
  );

  // Blocker 3 — an unexercised MAY (no matching event, no lapse) surfaces the
  // residual OBLIGATION, NOT FULFILLED. Here the MUST is met at t=1 and the
  // HENCE MAY is never exercised; the residual party is the lazy parameter
  // name ("driver"), not the resolved record (matches jl4-service).
  jeq(
    "deontic: unexercised MAY → residual OBLIGATION (not FULFILLED)",
    runDeontic(
      seatbeltMust,
      0,
      [{ party: { name: "Alice" }, action: "wear seatbelt", at: 1 }],
      { driver: { name: "Alice" } },
      driverMeta,
    ),
    { OBLIGATION: { action: "drive", deadline: null, modal: "MAY", party: "driver" } },
  );

  // Minor — a residual MUST with ZERO observed events renders the lazy party
  // name and the original WITHIN literal as a string.
  jeq(
    "deontic: residual MUST at zero events → lazy party + string deadline",
    runDeontic(
      seatbeltMust,
      0,
      [],
      { driver: { name: "Alice" } },
      driverMeta,
    ),
    { OBLIGATION: { action: "`wear seatbelt`", deadline: "1", modal: "MUST", party: "driver" } },
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
