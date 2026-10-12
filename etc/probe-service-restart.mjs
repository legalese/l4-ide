#!/usr/bin/env node
// probe-service-restart.mjs — does jl4-service answer the same after a restart
// that loads its deployments back from the store?
//
// WHY
//   Everything jl4-service-test does runs in one process, and most of it
//   registers freshly compiled functions straight into memory. A restarted
//   service reads each deployment back from <store>/<id>/bundle.cbor instead,
//   and that encoding has twice lost something the first process had: the
//   types query-plan needs, and the multi-clause mark that words a no-match
//   error in the drafter's terms (review of legalese/l4-ide#545, round 2).
//   Both were silent: 200 or a plausible error, no diagnostic.
//
// WHAT
//   Starts the given jl4-service on a fresh store and a free port, deploys an
//   ordinary rule and a rule written as clauses, and calls both, including an
//   input no clause matches. Stops it, checks bundle.cbor was written, restarts
//   it on the same store, and makes the same calls. Any answer that differs is
//   a FAIL. The service is stopped by PID.
//
//   A build without multi-clause rules (main before #545) rejects the clause
//   module; that half is then reported as not probed, and the rest still runs.
//
// USAGE
//   node etc/probe-service-restart.mjs [--perturb] <jl4-service binary>
//
//     --perturb   positive control: after the restart, ask for `price` of
//                 Green instead of Red, so a working probe must FAIL.
//
//   Exit 0: same answers. 1: an answer differs. 2: the probe could not run.
//   Needs `zip` on PATH.

import { spawn, spawnSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  openSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PLAIN = `@export default Whether a number is large
GIVEN n IS A NUMBER
GIVETH A BOOLEAN
DECIDE \`is large\` IF n > 10
`;

const CLAUSES = `DECLARE Colour IS ONE OF Red, Green, Blue

@export default The price of a colour
GIVEN c IS A Colour
GIVETH A NUMBER
DECIDE price Red   IS 1
DECIDE price Green IS 2
`;

const args = process.argv.slice(2);
const perturb = args.includes("--perturb");
const bin = args.filter((a) => a !== "--perturb")[0];
if (!bin || args.filter((a) => a !== "--perturb").length !== 1) {
  console.error(
    "usage: node etc/probe-service-restart.mjs [--perturb] <jl4-service binary>",
  );
  process.exit(2);
}
let dir = null;
let child = null;
if (!existsSync(bin)) die(`no such binary: ${bin}`);
dir = mkdtempSync(join(tmpdir(), "probe-service-restart."));
const store = join(dir, "store");
const log = join(dir, "service.log");

function die(msg) {
  console.error(`probe-service-restart: ${msg}`);
  if (child) child.kill("SIGKILL");
  if (dir && existsSync(join(dir, "service.log"))) {
    console.error("  service log, last lines:");
    for (const l of readFileSync(join(dir, "service.log"), "utf8")
      .trimEnd()
      .split("\n")
      .slice(-10))
      console.error(`  | ${l}`);
  }
  if (dir) rmSync(dir, { recursive: true, force: true });
  process.exit(2);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Each wait polls every 200 ms; generous, since a loaded machine compiles slowly.
const WAIT_SECONDS = 120;

function freePort() {
  return new Promise((resolve, reject) => {
    const s = createServer();
    s.once("error", reject);
    s.listen(0, "127.0.0.1", () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });
}

function zipOf(name, text) {
  const src = join(dir, name);
  writeFileSync(src, text);
  const zip = join(dir, `${name}.zip`);
  const r = spawnSync("zip", ["-q", "-j", zip, src]);
  if (r.status !== 0)
    die(`zip failed (is it on PATH?): ${r.stderr ?? r.error}`);
  return readFileSync(zip);
}

async function start(port) {
  const fd = openSync(log, "a");
  child = spawn(bin, ["--port", String(port), "--store-path", store], {
    stdio: ["ignore", fd, fd],
  });
  const exited = new Promise((r) => child.once("exit", (code) => r(code)));
  for (let i = 0; i < WAIT_SECONDS * 5; i++) {
    const code = await Promise.race([exited, sleep(200).then(() => undefined)]);
    if (code !== undefined)
      die(`the service exited (${code}) before answering /health`);
    try {
      if ((await fetch(`http://127.0.0.1:${port}/health`)).ok) return;
    } catch {}
  }
  die(`the service did not answer /health within ${WAIT_SECONDS} s`);
}

async function stop() {
  const c = child;
  child = null;
  if (c.exitCode !== null) return;
  const exited = new Promise((r) => c.once("exit", r));
  c.kill("SIGTERM");
  if (
    (await Promise.race([exited, sleep(10000).then(() => "timeout")])) ===
    "timeout"
  ) {
    c.kill("SIGKILL");
    await exited;
  }
}

async function deploy(port, id, name, text) {
  const form = new FormData();
  form.append("id", id);
  form.append("sources", new Blob([zipOf(name, text)]), `${name}.zip`);
  const resp = await fetch(`http://127.0.0.1:${port}/deployments`, {
    method: "POST",
    body: form,
  });
  const body = await resp.json().catch(() => ({}));
  if (resp.status !== 202 || !body.updateId)
    die(`deploy ${id}: ${resp.status} ${JSON.stringify(body)}`);
  for (let i = 0; i < WAIT_SECONDS * 5; i++) {
    const job = await (
      await fetch(
        `http://127.0.0.1:${port}/deployments/${id}/updates/${body.updateId}`,
      )
    ).json();
    if (job.status === "applied") return null;
    if (job.status === "rejected") return job.error ?? JSON.stringify(job);
    await sleep(200);
  }
  die(`deploy ${id}: the job did not finish within ${WAIT_SECONDS} s`);
}

async function ready(port, id) {
  for (let i = 0; i < WAIT_SECONDS * 5; i++) {
    const r = await fetch(`http://127.0.0.1:${port}/deployments/${id}`);
    if (r.ok && (await r.json()).status === "ready") return;
    await sleep(200);
  }
  die(`deployment ${id} was not ready within ${WAIT_SECONDS} s of the restart`);
}

// Sorted keys, so two answers differ only when their content does.
const canon = (v) =>
  Array.isArray(v)
    ? v.map(canon)
    : v && typeof v === "object"
      ? Object.fromEntries(
          Object.keys(v)
            .sort()
            .map((k) => [k, canon(v[k])]),
        )
      : v;

function calls(withClauses, after) {
  const ev = (id, fn, args) => ({
    label: `${id} ${fn} ${JSON.stringify(args)}`,
    path: `/deployments/${id}/functions/${fn}/evaluation`,
    body: { arguments: args },
  });
  const list = [
    ev("probe-plain", "is-large", { n: 12 }),
    ev("probe-plain", "is-large", { n: 3 }),
    {
      label: "probe-plain is-large query-plan {}",
      path: "/deployments/probe-plain/functions/is-large/query-plan",
      body: { arguments: {} },
    },
  ];
  if (withClauses) {
    const red = ev("probe-clauses", "price", {
      c: perturb && after ? "Green" : "Red",
    });
    red.label = `probe-clauses price {"c":"Red"}`;
    list.push(red, ev("probe-clauses", "price", { c: "Blue" }));
  }
  return list;
}

async function ask(port, list) {
  const out = [];
  for (const c of list) {
    const r = await fetch(`http://127.0.0.1:${port}${c.path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(c.body),
    });
    const text = await r.text();
    let shown = text;
    try {
      shown = JSON.stringify(canon(JSON.parse(text)));
    } catch {}
    out.push(`${r.status} ${shown}`);
  }
  return out;
}

const port = await freePort();
await start(port);
await deploy(port, "probe-plain", "plain.l4", PLAIN).then(
  (err) => err && die(`the ordinary rule did not compile: ${err}`),
);
const clauseErr = await deploy(port, "probe-clauses", "clauses.l4", CLAUSES);
if (clauseErr)
  console.log(
    `NOTE: the clause module did not compile on this build, so that half is not probed: ${clauseErr}`,
  );
const list = calls(!clauseErr, false);
const before = await ask(port, list);
await stop();

const cached = ["probe-plain", ...(clauseErr ? [] : ["probe-clauses"])].filter(
  (id) => !existsSync(join(store, id, "bundle.cbor")),
);
if (cached.length)
  die(
    `no bundle.cbor for ${cached.join(", ")}: a restart would not read the cache, so it cannot be probed`,
  );

await start(port);
await ready(port, "probe-plain");
if (!clauseErr) await ready(port, "probe-clauses");
const after = await ask(port, calls(!clauseErr, true));
await stop();

let differs = 0;
const cut = (s) => (s.length > 300 ? `${s.slice(0, 300)}…` : s);
for (let i = 0; i < list.length; i++) {
  const same = before[i] === after[i];
  if (!same) differs++;
  console.log(`${same ? "same  " : "DIFFER"} ${list[i].label}`);
  console.log(`         before: ${cut(before[i])}`);
  if (!same) console.log(`         after:  ${cut(after[i])}`);
}
rmSync(dir, { recursive: true, force: true });
console.log(
  differs
    ? `FAIL: ${differs} of ${list.length} answers differ after a restart from bundle.cbor${perturb ? " (--perturb: expected)" : ""}`
    : `PASS: ${list.length} answers identical before and after a restart from bundle.cbor`,
);
process.exit(differs ? 1 : 0);
