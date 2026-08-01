#!/usr/bin/env node
// Re-derive a run's verdict from committed artifacts. No build, no model, no
// network — SPEC.md §7.2's "verification agents read committed artifacts and
// never build", implemented.
//
// This is also the after-the-fact backstop the gate design needs. The acting
// agent can edit gate-verify.sh; it cannot pre-satisfy a recomputation run by a
// DIFFERENT party at a later time against the journal it already wrote.
//
// Usage: node etc/go/lib/verify-run.mjs RUNDIR [--gates] [--json]
// Exit:  0 the run verifies · 1 a finding · 2 usage · 4 the journal itself is
//        unreadable or its chain is broken

import { existsSync, statSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import { sha256File, verify } from "./ledger.mjs";
import { milestoneVerdict } from "./verdict.mjs";

const args = process.argv.slice(2);
const rundir = args.find((a) => !a.startsWith("--"));
const wantGates = args.includes("--gates");
const asJson = args.includes("--json");
if (!rundir) {
  process.stderr.write("usage: verify-run.mjs RUNDIR [--gates] [--json]\n");
  process.exit(2);
}

const journal = resolve(rundir, "journal.ndjson");
if (!existsSync(journal)) {
  process.stderr.write(`verify-run.mjs: no journal at ${journal}\n`);
  process.exit(2);
}

const chain = verify(journal);
const findings = [];

if (!chain.ok) {
  for (const p of chain.problems) findings.push({ kind: "chain", detail: p });
}

const records = chain.records;
const begin = records.find((r) => r.kind === "run_begin");
const allStageEnds = records.filter((r) => r.kind === "stage_end");
// The journal is append-only, so a resumed run holds several rows per stage.
// The LATEST row is the stage's current verdict; the earlier ones are history
// and stay on the record. `attempts` is reported so a stage that was re-run
// many times is visible rather than smoothed over.
const stageEnds = [...new Map(allStageEnds.map((r) => [r.stage, r])).values()];
const attempts = new Map();
for (const r of allStageEnds)
  attempts.set(r.stage, (attempts.get(r.stage) ?? 0) + 1);
const gates = records.filter((r) => r.kind === "gate");

// --- 1. every artifact a receipt names must still hash to what it recorded ----
const artifactChecks = [];
for (const r of stageEnds) {
  for (const a of r.artifacts || []) {
    const p = isAbsolute(a.path) ? a.path : resolve(rundir, a.path);
    if (a.absent) {
      artifactChecks.push({
        stage: r.stage,
        path: a.path,
        state: "recorded-absent",
      });
      continue;
    }
    if (!existsSync(p)) {
      artifactChecks.push({ stage: r.stage, path: a.path, state: "GONE" });
      findings.push({
        kind: "artifact",
        detail: `${r.stage}: ${a.path} was recorded with a sha256 and is no longer on disk`,
      });
      continue;
    }
    const now = sha256File(p);
    if (now !== a.sha256) {
      artifactChecks.push({
        stage: r.stage,
        path: a.path,
        state: "CHANGED",
        recorded: a.sha256,
        now,
      });
      findings.push({
        kind: "artifact",
        detail: `${r.stage}: ${a.path} changed after its receipt was written`,
      });
    } else {
      artifactChecks.push({
        stage: r.stage,
        path: a.path,
        state: "matches",
        bytes: statSync(p).size,
      });
    }
  }
}

// --- 2. the milestone verdict, recomputed --------------------------------------
const declared = begin?.declared_stages ?? [];
const gateStates = [...new Map(gates.map((g) => [g.gate, g])).values()].map(
  (g) => ({ gate: g.gate, state: g.state, reason: g.reason }),
);
const verdict = milestoneVerdict({
  declared,
  receipts: stageEnds,
  gates: gateStates,
});

// --- 3. gate ordering ----------------------------------------------------------
// A granted gate must be recorded BEFORE the first stage it gates began. If a
// gated stage started first, the gate did not gate anything.
const gateOrder = [];
if (wantGates) {
  const GATED_BY = begin?.gated_stages ? JSON.parse(begin.gated_stages) : {};
  for (const g of gates) {
    const gatedStages = GATED_BY[g.gate] ?? [];
    const early = records.filter(
      (r) =>
        r.kind === "stage_begin" &&
        gatedStages.includes(r.stage) &&
        r.seq < g.seq,
    );
    gateOrder.push({
      gate: g.gate,
      state: g.state,
      seq: g.seq,
      gated_stages: gatedStages,
      began_before_gate: early.map((e) => e.stage),
    });
    if (early.length)
      findings.push({
        kind: "gate-order",
        detail: `${g.gate} was recorded at seq ${g.seq} but ${early.map((e) => e.stage).join(", ")} began before it — the gate did not gate anything`,
      });
    if (g.state === "satisfied" && !g.signature_file)
      findings.push({
        kind: "gate",
        detail: `${g.gate} is recorded satisfied with no signature file named`,
      });
  }
  // A gate needs a record only if this milestone actually declares one of the
  // stages it gates. HG2 gates p10-publish, which is not a G1 stage, so its
  // absence from a G1 journal is correct and must not be reported as a finding.
  for (const [gname, gatedStages] of Object.entries(GATED_BY)) {
    const relevant = (gatedStages ?? []).some((s) => declared.includes(s));
    if (relevant && !gates.some((g) => g.gate === gname))
      findings.push({
        kind: "gate",
        detail: `${gname} gates ${gatedStages.filter((s) => declared.includes(s)).join(", ")} and has no record at all`,
      });
  }
}

const out = {
  rundir,
  run_id: begin?.run_id ?? null,
  milestone: begin?.milestone ?? null,
  subject: begin?.subject ?? null,
  chain_ok: chain.ok,
  chain_problems: chain.problems,
  records: records.length,
  stages: stageEnds.map((r) => ({
    stage: r.stage,
    status: r.status,
    replayed: !!r.replayed_from,
    receipts: attempts.get(r.stage) ?? 1,
  })),
  artifacts: artifactChecks,
  gates: gateStates,
  gate_order: gateOrder,
  verdict: verdict.verdict,
  missing_stages: verdict.missing,
  findings,
};

if (asJson) {
  process.stdout.write(JSON.stringify(out, null, 2) + "\n");
} else {
  process.stdout.write(
    `run ${out.run_id ?? "(no run_begin)"} — ${out.milestone ?? "?"}/${out.subject ?? "?"}\n`,
  );
  process.stdout.write(
    `  journal chain: ${chain.ok ? "verifies" : "BROKEN"} (${records.length} records)\n`,
  );
  for (const s of out.stages)
    process.stdout.write(
      `  ${s.stage.padEnd(16)} ${s.status}${s.replayed ? " (replayed)" : ""}${s.receipts > 1 ? `  [${s.receipts} receipts]` : ""}\n`,
    );
  for (const g of out.gates)
    process.stdout.write(
      `  gate ${g.gate}: ${g.state}${g.reason ? ` — ${g.reason}` : ""}\n`,
    );
  const changed = artifactChecks.filter((a) => a.state !== "matches");
  process.stdout.write(
    `  artifacts: ${artifactChecks.length} recorded, ${artifactChecks.length - changed.length} still hash as recorded\n`,
  );
  for (const c of changed)
    process.stdout.write(`    ${c.state} ${c.stage} ${c.path}\n`);
  process.stdout.write(`  VERDICT: ${out.verdict}\n`);
  for (const f of findings)
    process.stdout.write(`  finding [${f.kind}] ${f.detail}\n`);
}

if (!chain.ok) process.exit(4);
process.exit(findings.length ? 1 : 0);
