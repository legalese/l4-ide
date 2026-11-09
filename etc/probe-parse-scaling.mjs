#!/usr/bin/env node
// probe-parse-scaling.mjs — does `l4 check` take linear time in the length of a file?
//
// WHY
//   The corpus files a parser change is tested on are a few hundred lines, and
//   at that size a quadratic parser looks only twice as slow. A file of 4,000
//   lines `f x MEANS i` took 0.7 s to check on main and 284 s with a parser that
//   re-parsed a run of same-named definitions from every suffix (review of
//   legalese/l4-ide#545, round 2). The blind pre-review had timed the same
//   change on distinct names and seen a doubling.
//
// WHAT
//   Times `<l4> check` on N and 4N lines of two shapes: ordinary definitions,
//   each with its own name (`f1 x MEANS 1`), and one name repeated (`f x MEANS 1`,
//   `f x MEANS 2`, ...), the reviewer's file. They are separate shapes because
//   they take different paths through the parser: at the #545 head he reviewed,
//   4,000 distinct names checked in about 1 s and 1,000 repeated names took
//   24 to 33 s. Linear is a ratio of 4, and above 8 is a FAIL; a quadratic
//   parser gives 16.
//
//   The time is CPU time, user plus system, from /usr/bin/time -p, best of up
//   to three runs at each size. Wall-clock time is not used for the ratio
//   because load moves it: on a Mac at load 15 to 30, one wall-clock run of the
//   quadratic build took 285 s for the N file and 1,426 s for the 4N file, a
//   ratio of 5. A 4N run is stopped only past 32 times the N run's wall-clock
//   time, which is then a FAIL.
//
//   The distinct-name file must check clean, or the timing would measure an
//   early exit. The repeated-name file may fail to check, on a build that reads
//   the lines as duplicate definitions, say; the probe then says so.
//
// USAGE
//   node etc/probe-parse-scaling.mjs <l4 binary> [N]      N defaults to 1000
//   node etc/probe-parse-scaling.mjs --selftest
//
//   --selftest runs the probe on two stand-ins for `l4`, shell scripts whose
//   CPU time grows with the file's line count and with its square, and passes
//   only if the probe scores the first PASS and the second FAIL.
//
//   Exit 0: linear. 1: superlinear. 2: the probe could not run.

import { spawn } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const LIMIT = 8;
const GIVE_UP = 32;
const TIME = "/usr/bin/time";

const SHAPES = [
  {
    name: "distinct names",
    line: (i) => `f${i} x MEANS ${i}\n`,
    mustCheck: true,
  },
  { name: "one name", line: (i) => `f x MEANS ${i}\n`, mustCheck: false },
];

// What to stop and remove if the probe is interrupted: a child in its own
// process group does not get the terminal's Ctrl-C.
const live = { pid: null, dirs: new Set() };
for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => {
    try {
      if (live.pid) process.kill(-live.pid, "SIGKILL");
    } catch {}
    for (const d of live.dirs) rmSync(d, { recursive: true, force: true });
    process.exit(2);
  });
}

// One `check`, in its own process group so that stopping it stops the l4 under
// /usr/bin/time too. Resolves to { cpu, wall, stopped, status, firstError }.
function run(bin, file, capSeconds) {
  return new Promise((resolve, reject) => {
    const t0 = process.hrtime.bigint();
    const child = spawn(TIME, ["-p", bin, "check", file], {
      stdio: ["ignore", "ignore", "pipe"],
      detached: true,
    });
    live.pid = child.pid;
    let head = "";
    let tail = "";
    child.stderr.on("data", (d) => {
      if (head.length < 4096) head += d;
      tail = (tail + d).slice(-4096);
    });
    let stopped = false;
    const timer =
      capSeconds &&
      setTimeout(() => {
        stopped = true;
        try {
          process.kill(-child.pid, "SIGKILL");
        } catch {}
      }, capSeconds * 1000);
    child.on("error", (e) =>
      reject(new Error(`could not run ${TIME}: ${e.message}`)),
    );
    child.on("close", (status) => {
      live.pid = null;
      if (timer) clearTimeout(timer);
      const wall = Number(process.hrtime.bigint() - t0) / 1e9;
      if (stopped) return resolve({ wall, stopped: true });
      const user = /^user\s+([\d.]+)/m.exec(tail);
      const sys = /^sys\s+([\d.]+)/m.exec(tail);
      if (!user || !sys)
        return reject(
          new Error(`no timing from ${TIME} -p: ${tail.slice(-200)}`),
        );
      if (status !== 0 && status !== 1)
        return reject(new Error(`${bin} check ${file} ended with ${status}`));
      const firstError = head.split("\n").find((l) => l.trim());
      resolve({
        cpu: Number(user[1]) + Number(sys[1]),
        wall,
        stopped: false,
        status,
        firstError,
      });
    });
  });
}

// Best of up to three runs, by CPU time; a run over 5 s is not repeated, since
// noise no longer matters there and a repeat of a slow run is expensive.
async function measure(bin, file, capSeconds) {
  let best = null;
  for (let i = 0; i < 3; i++) {
    const r = await run(bin, file, capSeconds);
    if (r.stopped) return r;
    if (!best || r.cpu < best.cpu) best = r;
    if (r.cpu > 5) break;
  }
  return best;
}

async function shape(bin, dir, s, n, say) {
  const file = (k) => {
    const p = join(dir, `${s.name.replace(" ", "-")}-${k}.l4`);
    writeFileSync(
      p,
      Array.from({ length: k }, (_, i) => s.line(i + 1)).join(""),
    );
    return p;
  };
  const small = file(n);
  const large = file(4 * n);
  const best = await measure(bin, small);
  if (best.status !== 0) {
    if (s.mustCheck)
      throw new Error(
        `${n} lines of ${s.name} did not check clean: ${best.firstError}`,
      );
    say(
      `  NOTE: ${s.name} does not check clean on this build (${best.firstError}); timed anyway`,
    );
  }
  const cap = Math.max(GIVE_UP * best.wall, 30);
  const big = await measure(bin, large, cap);
  const ratio = big.stopped ? Infinity : big.cpu / Math.max(best.cpu, 0.01);
  say(
    `  ${s.name}: ${n} lines ${best.cpu.toFixed(2)} s CPU, ${4 * n} lines ` +
      (big.stopped
        ? `stopped after ${cap.toFixed(0)} s wall-clock: FAIL`
        : `${big.cpu.toFixed(2)} s CPU: ratio ${ratio.toFixed(1)}${ratio > LIMIT ? "  FAIL" : ""}`),
  );
  return ratio > LIMIT;
}

async function probe(bin, n, say = console.log, shapes = SHAPES) {
  if (!existsSync(TIME))
    throw new Error(`${TIME} is needed for CPU time, and is missing`);
  const dir = mkdtempSync(join(tmpdir(), "probe-parse-scaling."));
  live.dirs.add(dir);
  try {
    const fails = [];
    for (const s of shapes)
      if (await shape(bin, dir, s, n, say)) fails.push(s.name);
    say(
      fails.length
        ? `FAIL: superlinear on ${fails.join(", ")} (linear is 4, FAIL above ${LIMIT})`
        : `PASS: linear (FAIL above ${LIMIT})`,
    );
    return fails.length ? 1 : 0;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

async function selftest() {
  const dir = mkdtempSync(join(tmpdir(), "probe-parse-scaling-selftest."));
  live.dirs.add(dir);
  try {
    // Called as `<stand-in> check <file>`, so the file is $2. awk burns CPU,
    // because the probe reads CPU time and a sleep uses none.
    const standIn = (name, iterations) => {
      const p = join(dir, name);
      writeFileSync(
        p,
        `#!/bin/sh\nn=$(wc -l < "$2")\nawk -v n="$n" 'BEGIN { for (i = 0; i < ${iterations}; i++) x++ }'\n`,
      );
      chmodSync(p, 0o755);
      return p;
    };
    const quiet = () => {};
    // The stand-ins ignore the file's text, so one shape is enough.
    const one = SHAPES.slice(0, 1);
    const lin = await probe(standIn("linear", "n * 1000"), 1000, quiet, one);
    const quad = await probe(standIn("quadratic", "n * n"), 1000, quiet, one);
    console.log(
      `  linear stand-in, a million steps per 1,000 lines: ${lin ? "FAIL" : "PASS"} (expected PASS)`,
    );
    console.log(
      `  quadratic stand-in, a million steps at 1,000 lines: ${quad ? "FAIL" : "PASS"} (expected FAIL)`,
    );
    const ok = lin === 0 && quad === 1;
    console.log(
      ok
        ? "selftest PASS"
        : "selftest FAIL: the probe cannot tell linear from quadratic",
    );
    return ok ? 0 : 1;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const args = process.argv.slice(2);
try {
  if (args[0] === "--selftest") process.exit(await selftest());
  if (args.length < 1 || args.length > 2 || !existsSync(args[0])) {
    console.error(
      "usage: node etc/probe-parse-scaling.mjs <l4 binary> [N]  |  --selftest",
    );
    process.exit(2);
  }
  process.exit(await probe(args[0], args[1] ? Number(args[1]) : 1000));
} catch (e) {
  console.error(`probe-parse-scaling: ${e.message}`);
  process.exit(2);
}
