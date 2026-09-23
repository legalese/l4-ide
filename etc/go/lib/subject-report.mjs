#!/usr/bin/env node
// R13 — the subject-level fold.
//
//   subject-report.mjs <rundir-base> --subject ID [--param k=v]… [--json]
//
// `p9-report` renders ONE RUN's journal, and no single run exercises every
// phase, so no single report is the account of the subject: `sg-succession`'s
// g1 report marks §P1 and §P2 ABSENT while its g2 report marks the measurement
// stages SKIPPED, and both are correct about their own run.
//
// THE FOLD IS NOT A UNION. A receipt binds to the digest it ran over, so
// evidence from two runs is jointly meaningful only where both ran over the
// same inputs. Each phase resolves to exactly one of three states.
//
// STALE MEANS R4'S STALE, NOT "OVER AN OLDER DIGEST".
// §3.13 first spelled it the second way, and the two are not the same claim:
//   - a digest can differ with NO prerequisite newer (a param changed the
//     question rather than the answer);
//   - a prerequisite can be newer with the digest UNMOVED — that is the entire
//     §3.7a bug class, where the clock, the stdlib and the IMPORT closure were
//     real input changes that moved no digest;
//   - a digest says only THAT something moved; a read-set says WHICH member.
// One concept, one mechanism, and R4's is the principled one. So this reads
// read-sets, and names the member that moved.
//
// WHAT THIS CAN SEE IS ITSELF REPORTED. Journals live in run directories, which
// are measured to last two to five days; the store outlives them but records
// only stages that PRODUCED something, so a SKIPPED stage leaves no trace there
// and would read as NEVER RUN. A fold that quietly narrowed its evidence would
// turn "I cannot see it" into "it never happened" — which is exactly the
// misreading R12's failure turned on. So the horizon is printed.

import { existsSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { read, runSubject, verify } from "./ledger.mjs";
import { classOf, freshness, rolesFor } from "./readset.mjs";
import { indexRecords, storeRoot } from "./store.mjs";

const EXIT = { CLEAN: 0, FINDING: 1, USAGE: 2 };
const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../../..");

const argv = process.argv.slice(2);
const positional = argv.filter((a) => !a.startsWith("--"));
const base = positional[0];
const flag = (n) => {
  const i = argv.indexOf(`--${n}`);
  return i >= 0 ? argv[i + 1] : null;
};
const subject = flag("subject");
const wantJson = argv.includes("--json");
const nowParams = {};
for (let i = 0; i < argv.length; i++) {
  if (argv[i] !== "--param") continue;
  const kv = argv[i + 1] ?? "";
  const j = kv.indexOf("=");
  if (j > 0) nowParams[kv.slice(0, j)] = kv.slice(j + 1);
}

if (!base || !subject) {
  process.stderr.write(
    "usage: subject-report.mjs <rundir-base> --subject ID [--param k=v]… [--json]\n",
  );
  process.exit(EXIT.USAGE);
}

// --- what evidence survives --------------------------------------------------
const runs = [];
if (existsSync(base))
  for (const name of readdirSync(base)) {
    const dir = join(base, name);
    let journal;
    try {
      if (!statSync(dir).isDirectory()) continue;
      journal = join(dir, "journal.ndjson");
      if (!existsSync(journal)) continue;
      if (runSubject(journal) !== subject) continue;
    } catch {
      continue;
    }
    // A journal that does not verify is not evidence. Folding it in would let a
    // hand-edited row set a phase's state for the whole subject.
    const chain = verify(journal);
    runs.push({
      id: name,
      dir,
      journal,
      ok: chain.ok,
      rows: chain.ok ? read(journal) : [],
    });
  }
// ORDERED BY THE RUN'S OWN RECORDED START TIME, not by its id.
//
// A run id is `<date>-<corpus_sha8>-<counter>`, so a lexicographic sort orders
// by date, then by a CONTENT HASH, then by counter. Two runs on the same day
// over different corpora therefore sort by hash — an arbitrary order — and
// "the most recent receipt wins" picks whichever hash sorted higher. The id
// does not totally order runs and cannot be made to.
//
// This is not the clock creeping into freshness. Freshness compares CONTENT and
// never a timestamp; that stays true. But "which run is most recent" is an
// inherently temporal question, and the answer is a fact the journal already
// recorded at run_begin — read back, not sampled now.
const startedAt = (r) => r.rows.find((x) => x.kind === "run_begin")?.ts ?? r.id;
runs.sort((a, b) => {
  const ta = startedAt(a);
  const tb = startedAt(b);
  return ta < tb ? -1 : ta > tb ? 1 : a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
});

let index = [];
try {
  index = indexRecords(storeRoot(), { subject });
} catch {
  index = [];
}

// --- the universe of phases ---------------------------------------------------
// Three sources, widest first: what the driver says is DECLARABLE, what this
// subject has ever DECLARED, and what the store has ever recorded an artifact
// from. Widest-first is the point — a universe built only from what has been
// declared cannot contain a phase nobody ever declared, which is exactly the
// phase R13 exists to name.
const universe = new Set();
// The DECLARABLE set, handed in by the driver, which owns the stage lists. A
// phase that has never been declared for this subject is precisely the one
// R13 must still name — building the universe only from what HAS been declared
// makes such a phase vanish from the report, and a phase that is absent reads
// as "accounted for elsewhere" when nothing had accounted for it anywhere.
for (const s of (flag("declarable") ?? "").split(/\s+/).filter(Boolean))
  universe.add(s);
for (const r of runs)
  for (const row of r.rows)
    if (row.kind === "run_begin")
      for (const s of row.declared_stages ?? []) universe.add(s);
for (const rec of index)
  if (rec.stage && classOf(rec.stage) !== "unknown") universe.add(rec.stage);

// --- resolve each phase -------------------------------------------------------
const phases = [];
for (const stage of [...universe].sort()) {
  // Most recent receipt wins, and "most recent" is run-id order — run ids are
  // date-prefixed and monotone within a subject, so this needs no clock.
  let latest = null;
  for (const r of runs)
    for (const row of r.rows)
      if (row.kind === "stage_end" && row.stage === stage)
        latest = { run: r.id, row, rows: r.rows };

  if (!latest) {
    // The state that would have caught R12's failure. Today a report says a
    // phase is "not declared for this run" — true, and readable as
    // "accounted for elsewhere" when nothing had accounted for it anywhere.
    const admitted = index.some((rec) => rec.stage === stage);
    phases.push({
      stage,
      state: "NEVER RUN",
      note: admitted
        ? "NO SURVIVING RECEIPT, but the store holds artifacts from a run that produced them — it ran, and the evidence of HOW has expired"
        : "no receipt in any surviving run, and no artifact in the store",
    });
    continue;
  }

  const { row, rows, run } = latest;
  if (!Array.isArray(row.read_set)) {
    phases.push({
      stage,
      state: "NO READ-SET",
      run,
      status: row.status,
      note:
        row.journal_schema && row.journal_schema < 4
          ? "receipt predates journal schema 4"
          : "the stage declares no inputs, so it can never replay and has none by design",
    });
    continue;
  }
  const roled = rolesFor(row.read_set, rows, index, REPO);
  const f = freshness(roled, index, nowParams);
  phases.push({
    stage,
    state:
      f.state === "stale"
        ? "STALE"
        : f.state === "current"
          ? "CURRENT"
          : "UNKNOWN",
    run,
    status: row.status,
    moved: f.moved.map((m) => m.path),
    unevaluated: f.unknown,
    inputs_digest: row.inputs_digest,
  });
}

const horizon = {
  runs_visible: runs.length,
  runs_unverifiable: runs.filter((r) => !r.ok).length,
  oldest: runs[0]?.id ?? null,
  newest: runs[runs.length - 1]?.id ?? null,
  store_records: index.length,
};

if (wantJson) {
  process.stdout.write(
    JSON.stringify({ subject, horizon, phases }, null, 2) + "\n",
  );
  process.exit(
    phases.some((p) => p.state === "STALE") ? EXIT.FINDING : EXIT.CLEAN,
  );
}

const rel = (p) => (p.startsWith(REPO + "/") ? p.slice(REPO.length + 1) : p);
process.stdout.write(`the account of subject ${subject}\n\n`);
if (!runs.length)
  process.stdout.write(
    "  NO SURVIVING RUN JOURNAL. Run directories last about two to five days;\n" +
      "  what follows rests on the store alone, which records only stages that\n" +
      "  produced an artifact.\n\n",
  );
for (const p of phases) {
  const line = `  ${p.stage.padEnd(14)} ${p.state.padEnd(12)}`;
  if (p.state === "NEVER RUN") {
    process.stdout.write(`${line} ${p.note}\n`);
    continue;
  }
  if (p.state === "NO READ-SET") {
    process.stdout.write(`${line} ${p.status} in ${p.run} — ${p.note}\n`);
    continue;
  }
  process.stdout.write(
    `${line} ${p.status} in ${p.run}` +
      (p.unevaluated ? `  (${p.unevaluated} unevaluated)` : "") +
      "\n",
  );
  for (const m of p.moved ?? [])
    process.stdout.write(`${" ".repeat(31)}MOVED ${rel(m)}\n`);
}

const stale = phases.filter((p) => p.state === "STALE").length;
const never = phases.filter((p) => p.state === "NEVER RUN").length;
process.stdout.write(
  `\n${phases.length} phase(s): ${phases.filter((p) => p.state === "CURRENT").length} current, ` +
    `${stale} stale, ${never} never run.\n` +
    `Evidence horizon: ${horizon.runs_visible} surviving journal(s)` +
    (horizon.oldest ? ` (${horizon.oldest} … ${horizon.newest})` : "") +
    `, ${horizon.store_records} store record(s)` +
    (horizon.runs_unverifiable
      ? `, ${horizon.runs_unverifiable} journal(s) EXCLUDED because their chain does not verify`
      : "") +
    ".\n" +
    "STALE here is Make's: a newer version of some prerequisite exists, named above.\n" +
    "It is NOT 'the digest moved' — a digest cannot say which member, and can miss a\n" +
    "prerequisite that moved without moving it.\n",
);
process.exit(stale ? EXIT.FINDING : EXIT.CLEAN);
