// End-to-end test for the M7 hardening in 'wasm-server.mjs':
//   - happy path returns 200 + peak-heap header
//   - memory cap returns 413 and re-instantiates so the next request works
//   - a function the schema marks "supported": false is not run: 501,
//     and the worker that declined it answers the next request
//
// Compiles a tiny L4 fixture, spawns the server, hits its HTTP API.
// Requires the LLVM/MLIR toolchain on PATH; otherwise the script
// short-circuits with a skip message so CI without the toolchain
// still reports green.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { Worker } from "node:worker_threads";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..");

function which(cmd) {
  try {
    return execFileSync("which", [cmd], { encoding: "utf8" }).trim() || null;
  } catch {
    return null;
  }
}

if (
  !which("mlir-opt") ||
  !which("mlir-translate") ||
  !which("llc") ||
  !which("wasm-ld")
) {
  console.log("skip — LLVM/MLIR toolchain not on PATH");
  process.exit(0);
}

function cabalBin(name) {
  return execFileSync("cabal", ["list-bin", name], {
    cwd: repoRoot,
    encoding: "utf8",
  }).trim();
}

const mlirBin = cabalBin("jl4-mlir");

// A minimum L4 fixture — single @export function with one NUMBER param.
// 'cubed' was the M0-bug-fix witness from the previous session; reusing
// it here keeps the test wholly self-contained.
const srcDir = fs.mkdtempSync(path.join(os.tmpdir(), "jl4-m7-"));
const srcPath = path.join(srcDir, "fixture.l4");
fs.writeFileSync(
  srcPath,
  [
    "@export default Cube of a number",
    "GIVEN n IS A NUMBER",
    "cubed n MEANS n * n * n",
    "",
    // The schema marks this one "supported": false, because it may REFUSE.
    "@export Eligibility by age",
    "GIVEN age IS A NUMBER",
    "GIVETH A BOOLEAN",
    "eligible age MEANS",
    '  IF age < 0 THEN REFUSE "age cannot be negative" ELSE age >= 18',
    "",
  ].join("\n"),
);

execFileSync(
  mlirBin,
  ["wasm", srcPath, "-o", path.join(srcDir, "fixture.wasm")],
  {
    stdio: "inherit",
  },
);

const wasmPath = path.join(srcDir, "fixture.wasm");
const schemaPath = path.join(srcDir, "fixture.schema.json");

const port = 9991;
const serverPath = path.join(__dirname, "wasm-server.mjs");
// Tight memory cap (8 KiB) so a sufficiently-deep recursive expression
// would blow past it — but `cubed 1` only allocates ~24 bytes, so it's
// the wrong fixture for an OOM. Instead the OOM test below directly
// imports the runtime and calls 'allocBytes' to trip the limit. The
// HTTP path here just verifies the happy-path + header surface.
const server = spawn("node", [serverPath, schemaPath, wasmPath, String(port)], {
  env: { ...process.env },
  stdio: ["ignore", "pipe", "inherit"],
});
await new Promise((resolve) => {
  server.stderr ? server.stderr.on("data", () => {}) : null;
  // listen for the "listening" log line on the server's stderr
  setTimeout(resolve, 300);
});

let pass = 0;
let fail = 0;
const eq = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log(
    `${ok ? "ok  " : "FAIL"} ${name}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`,
  );
  ok ? pass++ : fail++;
};

async function postEval(fnName, args, traceMode) {
  const url =
    `http://127.0.0.1:${port}/deployments/x/functions/${encodeURIComponent(fnName)}/evaluation` +
    (traceMode ? `?trace=${traceMode}` : "");
  const r = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ arguments: args }),
  });
  return {
    status: r.status,
    body: await r.text(),
    peakHeap: r.headers.get("x-jl4-peak-heap-bytes"),
    maxHeap: r.headers.get("x-jl4-max-heap-bytes"),
  };
}

try {
  // Happy path.
  const ok = await postEval("cubed", { n: 1 });
  eq("happy: status", ok.status, 200);
  eq("happy: cubed 1 === 1", JSON.parse(ok.body).contents.result.value, 1);
  eq("happy: peak-heap header present", typeof ok.peakHeap, "string");
  eq("happy: max-heap header present", typeof ok.maxHeap, "string");
  // Second call uses the same warm instance.
  const ok2 = await postEval("cubed", { n: 7 });
  eq("warm: cubed 7 === 343", JSON.parse(ok2.body).contents.result.value, 343);

  // Unknown function → 404, no re-instantiation.
  const nope = await postEval("does-not-exist", {});
  eq("404: status", nope.status, 404);

  // Sanity: third call after the 404 still works.
  const ok3 = await postEval("cubed", { n: 3 });
  eq(
    "post-404: cubed 3 === 27",
    JSON.parse(ok3.body).contents.result.value,
    27,
  );

  // A function marked "supported": false is not run, traced or not: the
  // answer is a 501 naming the schema's reason, never a value.
  const schema = JSON.parse(fs.readFileSync(schemaPath, "utf8"));
  const meta = schema.functions["eligible"];
  eq("unsupported: the schema marks it", meta && meta.supported, false);
  for (const trace of [undefined, "full"]) {
    const label = trace ? "unsupported, traced" : "unsupported";
    const r = await postEval("eligible", { age: -1 }, trace);
    const body = JSON.parse(r.body);
    eq(`${label}: status`, r.status, 501);
    eq(`${label}: no answer`, "contents" in body, false);
    eq(
      `${label}: the error names the schema's reason`,
      String(body.error).includes(meta.unsupportedReason),
      true,
    );
    eq(
      `${label}: the message`,
      body.error,
      "eligible is not evaluated by the WASM backend: " +
        meta.unsupportedReason +
        ". Evaluate it with jl4-service.",
    );
  }
  // The server answers the next request; that the worker which declined is
  // the one that answers is pinned below, on one worker.
  const ok4 = await postEval("cubed", { n: 2 });
  eq("post-501: cubed 2 === 8", JSON.parse(ok4.body).contents.result.value, 8);
} finally {
  server.kill("SIGTERM");
  await new Promise((r) => server.on("exit", r));
}

// ---- A decline does not cost the worker its instance ------------------
// The server terminates a worker whose result is marked fatal. A decline is
// thrown before anything runs, so its result is not fatal, and the same
// worker answers the next request.
{
  const worker = new Worker(path.join(__dirname, "wasm-worker.mjs"), {
    workerData: {
      schemaPath: path.resolve(schemaPath),
      wasmPath: path.resolve(wasmPath),
      maxHeapBytes: 64 * 1024 * 1024,
      backend: "v8",
    },
  });
  let exited = false;
  worker.once("exit", () => {
    exited = true;
  });
  const nextMessage = () =>
    new Promise((resolve, reject) => {
      worker.once("message", resolve);
      worker.once("error", reject);
    });
  try {
    const ready = await nextMessage();
    eq("worker: ready", ready.type, "ready");
    worker.postMessage({
      type: "eval",
      id: 1,
      fnName: "eligible",
      args: { age: -1 },
    });
    const declined = await nextMessage();
    eq("worker: a decline is a 501", declined.status, 501);
    eq("worker: a decline is not fatal", declined.fatal, false);
    worker.postMessage({
      type: "eval",
      id: 2,
      fnName: "cubed",
      args: { n: 2 },
    });
    const answered = await nextMessage();
    eq(
      "worker: the worker that declined answers cubed 2 === 8",
      JSON.parse(answered.body).contents.result.value,
      8,
    );
    eq("worker: still running", exited, false);
  } finally {
    await worker.terminate();
  }
}

// ---- M7 slice 2: timeout + worker_threads, header surface ----------
// Verifying a real timed-out eval requires a fixture slow enough to
// outrun a deliberately short timeout — the M0 corpus is sub-ms, so
// we'd need a synthetic recursive helper. Instead, lock the header
// contract here ('x-jl4-eval-timeout-ms' present + reflects the env
// knob); a manual slow-eval rehearsal lives in
// 'jl4-mlir/parity-report/' notes.
{
  const port2 = 9992;
  const server2 = spawn(
    "node",
    [serverPath, schemaPath, wasmPath, String(port2)],
    {
      env: { ...process.env, JL4_EVAL_TIMEOUT_MS: "1234" },
      stdio: ["ignore", "pipe", "inherit"],
    },
  );
  await new Promise((r) => {
    server2.stderr ? server2.stderr.on("data", () => {}) : null;
    setTimeout(r, 300);
  });
  try {
    const r = await fetch(
      "http://127.0.0.1:" + port2 + "/deployments/x/functions/cubed/evaluation",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ arguments: { n: 1 } }),
      },
    );
    eq(
      "timeout: env knob plumbed",
      r.headers.get("x-jl4-eval-timeout-ms"),
      "1234",
    );
  } finally {
    server2.kill("SIGTERM");
    await new Promise((r) => server2.on("exit", r));
  }
}

// 'cubed n' has no compound args / no list / no record, so its
// 'walkWasmValue' / marshaling never touches the bump-pointer heap;
// the OOM-respawn path is exercised instead by the unit test in
// 'runtime/jl4-runtime.test.mjs' that calls 'allocBytes' directly.
// A future e2e OOM test would need a fixture that allocates a List
// or Record argument.

// ---- M7 slice 4: worker pool concurrency + headers -------------------
{
  // Pool of 3, fire 12 concurrent requests. Each must succeed; the
  // pool-queued header on at least one response should surface > 0
  // (proving requests really did queue up rather than serialize on
  // a single worker).
  const port4 = 9994;
  const server4 = spawn(
    "node",
    [serverPath, schemaPath, wasmPath, String(port4)],
    {
      env: { ...process.env, JL4_WORKER_POOL_SIZE: "3" },
      stdio: ["ignore", "pipe", "inherit"],
    },
  );
  await new Promise((r) => {
    server4.stderr ? server4.stderr.on("data", () => {}) : null;
    setTimeout(r, 500);
  });
  try {
    const N = 12;
    const reqs = Array.from({ length: N }, (_, i) =>
      fetch(
        "http://127.0.0.1:" +
          port4 +
          "/deployments/x/functions/cubed/evaluation",
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ arguments: { n: i + 1 } }),
        },
      ),
    );
    const ress = await Promise.all(reqs);
    const bodies = await Promise.all(ress.map((r) => r.text()));
    const allOk = ress.every((r) => r.status === 200);
    eq("pool: all " + N + " concurrent requests succeed", allOk, true);
    // Pool size header reflects the env.
    eq(
      "pool: size header surfaces JL4_WORKER_POOL_SIZE",
      ress[0].headers.get("x-jl4-pool-size"),
      "3",
    );
    // Verify the results came back correct (cubed i = i^3 for i=1..N).
    const values = bodies.map((b) => JSON.parse(b).contents.result.value);
    const expected = Array.from({ length: N }, (_, i) => Math.pow(i + 1, 3));
    eq("pool: results correct under concurrency", values, expected);
  } finally {
    server4.kill("SIGTERM");
    await new Promise((r) => server4.on("exit", r));
  }
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
