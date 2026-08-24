#!/usr/bin/env node
// R4's query surface: what did this run READ, and is any of it out of date?
//
//   readset-cli.mjs <rundir> [--stage S] [--param k=v]… [--json]
//
// A COMPARISON YOU ASK A QUESTION WITH IS A QUERY, NOT A PHASE (§4.2). This
// consumes no declared input set, earns no receipt and sits in no graph; it
// reads a journal that already exists and answers a question about it. Nothing
// downstream depends on its output, which is precisely what distinguishes it
// from `p8-diff`.
//
// FRESHNESS IS DERIVED HERE AND STORED NOWHERE. The read-set on a receipt says
// what was read; whether a newer version of any of it exists is a fact about
// the world *now*, and recording it would freeze an answer whose whole value is
// that it is recomputed. That is Make's discipline and §3.4's ruling.
//
// `--param k=v` supplies the value a `text:` member WOULD have now. The driver
// owns those facts (the `l4` binary's sha, the stdlib digest, the pinned
// clock), so the driver passes them; a param nobody supplies is reported
// UNEVALUATED rather than guessed at, because a param silently assumed
// unchanged is exactly the §3.7a bug class this ruling exists to close.

import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { read, verify } from "./ledger.mjs";
import { freshness, independence, rolesFor } from "./readset.mjs";
import { indexRecords, storeRoot } from "./store.mjs";

const EXIT = { CLEAN: 0, FINDING: 1, USAGE: 2 };
const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../../..");

const argv = process.argv.slice(2);
const positional = argv.filter((a) => !a.startsWith("--"));
const runDir = positional[0];
const flag = (name) => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : null;
};
const wantJson = argv.includes("--json");
const onlyStage = flag("stage");

const nowParams = {};
for (let i = 0; i < argv.length; i++) {
  if (argv[i] !== "--param") continue;
  const kv = argv[i + 1] ?? "";
  const j = kv.indexOf("=");
  if (j > 0) nowParams[kv.slice(0, j)] = kv.slice(j + 1);
}

if (!runDir) {
  process.stderr.write(
    "usage: readset-cli.mjs <rundir> [--stage S] [--param k=v]… [--json]\n",
  );
  process.exit(EXIT.USAGE);
}
const journal = resolve(runDir, "journal.ndjson");
if (!existsSync(journal)) {
  process.stderr.write(`readset: no journal at ${journal}\n`);
  process.exit(EXIT.USAGE);
}

// REFUSE TO REPORT OVER A JOURNAL THAT DOES NOT VERIFY. A read-set's whole
// claim is that it proves its digest; reading it out of a chain that has been
// edited would present a laundered claim as an attested one.
const chain = verify(journal);
if (!chain.ok) {
  process.stderr.write(
    `readset: ${journal} does not verify — ${chain.problems.length} problem(s):\n` +
      chain.problems.map((p) => `  - ${p}\n`).join(""),
  );
  process.exit(EXIT.FINDING);
}

const rows = read(journal);
const runBegin = rows.find((r) => r.kind === "run_begin") ?? {};
const subject = runBegin.subject ?? null;

let index = [];
try {
  index = indexRecords(storeRoot());
} catch {
  index = [];
}

const out = [];
for (const r of rows) {
  if (r.kind !== "stage_end") continue;
  if (onlyStage && r.stage !== onlyStage) continue;
  if (!Array.isArray(r.read_set)) {
    out.push({ stage: r.stage, declared: false });
    continue;
  }
  const roled = rolesFor(r.read_set, rows, index, REPO);
  out.push({
    stage: r.stage,
    declared: true,
    replayed: Boolean(r.replayed_from),
    inputs_digest: r.inputs_digest,
    members: roled,
    freshness: freshness(roled, index, nowParams),
    independence: independence(roled, subject),
  });
}

if (wantJson) {
  process.stdout.write(
    JSON.stringify({ run: runBegin.run_id ?? null, subject, stages: out }, null, 2) +
      "\n",
  );
  process.exit(EXIT.CLEAN);
}

const rel = (p) => (p.startsWith(REPO + "/") ? p.slice(REPO.length + 1) : p);
process.stdout.write(
  `read-sets for run ${runBegin.run_id ?? "?"} (subject ${subject ?? "?"})\n\n`,
);
let stale = 0;
for (const s of out) {
  if (!s.declared) {
    // NOT A GAP. p9-report and p9-explain declare an empty input set on
    // purpose — a report is a function of the journal it is writing into, so a
    // stage cannot digest its own future. Saying so here stops the next reader
    // filing a bug against a deliberate design.
    process.stdout.write(
      `  ${s.stage.padEnd(14)} declares no inputs — cannot replay, and has no read-set by design\n`,
    );
    continue;
  }
  const f = s.freshness;
  if (f.state === "stale") stale++;
  const tag =
    f.state === "stale"
      ? `STALE (${f.moved.length} moved)`
      : f.state === "unknown"
        ? `unknown (${f.unknown} unevaluated)`
        : "current";
  process.stdout.write(
    `  ${s.stage.padEnd(14)} ${String(s.members.length).padStart(2)} members  ` +
      `${s.replayed ? "replayed" : "executed"}  ${tag}` +
      `${s.independence.independent ? "" : `  reads ${s.independence.priors.length} prior encoding(s)`}\n`,
  );
  const byRole = {};
  for (const m of s.members) byRole[m.role] = (byRole[m.role] ?? 0) + 1;
  process.stdout.write(
    `                 roles: ${Object.entries(byRole)
      .map(([k, v]) => `${k}=${v}`)
      .join(" ")}\n`,
  );
  for (const m of f.moved)
    process.stdout.write(`                 MOVED ${rel(m.path)}\n`);
}
process.stdout.write(
  `\n${out.filter((s) => s.declared).length} stage(s) with a read-set, ${stale} stale.\n` +
    "Freshness is derived, never stored: a member is stale when a newer version of that\n" +
    "prerequisite exists, which is Make's meaning and not 'the digest moved'.\n",
);
process.exit(stale ? EXIT.FINDING : EXIT.CLEAN);
