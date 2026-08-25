#!/usr/bin/env node
// Build the canonical payload for a gate, from the journal.
//
// Nothing here is typed by hand. The payload is a deterministic rendering of
// (a) what run this is, (b) what tree it ran against, (c) the sha256 of every
// corpus file, and (d) the receipt hash of every stage that EXECUTED before the
// gate. Signing it approves that exact content and nothing else.
//
// (d) says "executed" rather than "ran" on purpose: replayed receipts are
// excluded, so resuming a run leaves the payload — and therefore a signature
// over it — untouched. See the filter below.
//
// Usage: node etc/go/lib/gate-payload.mjs HG1|HG2 RUNDIR

import { resolve } from "node:path";
import { read } from "./ledger.mjs";

const [, , gate, rundir] = process.argv;
if (!gate || !rundir) {
  process.stderr.write("usage: gate-payload.mjs HG1|HG2 RUNDIR\n");
  process.exit(2);
}

const records = read(resolve(rundir, "journal.ndjson"));
const begin = records.find((r) => r.kind === "run_begin");
if (!begin) {
  process.stderr.write("gate-payload.mjs: journal has no run_begin record\n");
  process.exit(2);
}

// Replayed receipts are EXCLUDED. A replay carries no new evidence — it copies
// the verdict and the artifact records of the receipt it names, whose own row is
// already in this list — but it is a fresh record with a fresh hash. Including
// replays made the payload a function of how many times the run had been
// resumed, so a signature stopped verifying on the very first resume the tools
// themselves print, over a corpus nobody had touched. The payload must be a
// function of CONTENT, and a replay changes none.
const stageEnds = records.filter(
  (r) => r.kind === "stage_end" && !r.replayed_from,
);
// The corpus section is exactly p0-preflight's `corpus_sha_*` metrics — one per
// module of the encoding, keyed by repo-relative path, written by
// etc/go/lib/corpus-metrics.mjs. That is a CONTRACT, not an implementation
// detail: a module p0-preflight does not record is a module this document never
// mentions and the signature therefore does not cover. If you are adding a file
// to what HG1 blesses, add it there, not here.
//
// The LAST executed p0-preflight wins, rather than the union of all of them.
// The receipts list below is an audit trail and correctly names every execution;
// this section is a STATEMENT ABOUT THE CORPUS, and there is only one corpus.
// Taking the union rendered each module twice after any re-execution — once at
// its pre-edit digest and once at its post-edit digest, with nothing saying
// which was current — so the one document that has to be unambiguous became the
// one that was not. That was latent while p0-preflight re-executed only on an
// edit to the entry module, the wizard, the pin file or its own source; it
// became routine on 2026-08-18, when every module of the encoding joined the
// stage's declared inputs (which is what makes a non-entry module's edit
// re-open the gate at all).
//
// SELECTED FROM ALL stage_end ROWS, REPLAYS INCLUDED — deliberately not from
// `stageEnds` above. The replay exclusion is right for the RECEIPTS list, which
// attests work: a replay is a fresh record of no new work, and including it made
// the payload a function of how many times the run had been resumed. It is
// WRONG here, because this section does not attest work — it states what the
// corpus IS, and a replayed p0-preflight row restates that faithfully, carrying
// the same `corpus_sha_*` metrics the executed row carried.
//
// MEASURED, before the fix: run 2026-08-19-951d08d8-004 replayed p0-preflight
// from run -003. Its p0 row carries all seven corpus_sha_ metrics, and the
// payload nonetheless rendered "(none recorded — p0-preflight has not run)". A
// human signing that document would have been signing a text that names no
// corpus file at all, while the journal's corpus_digest carried the real
// seven-module binding the reviewer never saw. That is the precise failure a
// human gate exists to prevent, produced by the gate's own tooling.
const allStageEnds = records.filter((r) => r.kind === "stage_end");
const p0 = allStageEnds.filter((r) => r.stage === "p0-preflight").at(-1);
const corpus = Object.entries(p0?.metrics ?? {})
  .filter(([k]) => k.startsWith("corpus_sha_"))
  .map(([k, v]) => [k.replace(/^corpus_sha_/, ""), v]);

// A PAYLOAD THAT NAMES NOTHING REFUSES TO RENDER.
//
// This used to degrade to a parenthetical, which is the one thing a signable
// document may not do: the whole point of the text is to tell the signer what
// they are blessing, and "(none recorded)" tells them nothing while still
// producing a file they can sign. The refusal already exists one layer down —
// corpus-metrics.mjs exits 2 on an empty module set rather than emitting an
// empty section, and p0-preflight.sh calls that out by name — and it simply did
// not fire one layer up.
//
// This is reachable on the g2 path in EVERY run state, not just after a replay:
// p0-preflight is not a declared g2 stage, so nothing records per-file corpus
// hashes there at all, and the g2 gate binds to the de novo deposit set instead.
// Every g2 HG1 payload was therefore corpus-blind. Refusing is the honest
// outcome until a g2 stage records those digests.
//
// Only the SIGNATURE route is affected: gate-payload.mjs is called from
// gate-request.sh and gate-verify.sh alone, never from `--waive`. A waiver is
// recorded with a reason and printed in the report, which is a different and
// deliberately weaker claim than a signature — so this refusal closes the route
// where a human is asked to bless something, and leaves the route where a human
// says on the record that they did not.
if (corpus.length === 0) {
  const why =
    begin.milestone === "g2"
      ? `p0-preflight is not a declared g2 stage (go.sh's G2_STAGES), so nothing in a g2 run records per-file corpus hashes.
` +
        `  The g2 gate binds to the DE NOVO deposit set, and no stage records its per-file digests yet, so this
` +
        `  payload cannot say what it would bless. Waive HG1 with a recorded reason instead, or add a g2 stage
` +
        `  that emits corpus_sha_* metrics over the deposit set.`
      : `no p0-preflight receipt in this journal carries corpus_sha_* metrics.
` +
        `  Run p0-preflight in this run before requesting a gate: it is the stage that states what the corpus is.`;
  process.stderr.write(
    `gate-payload.mjs: refusing to render a ${gate} payload that names no corpus file.
` +
      `  ${why}
` +
      `  A signable document whose corpus section is empty asks a human to bless something the document
` +
      `  does not describe, while the journal's corpus_digest carries the real binding they never saw.
`,
  );
  process.exit(2);
}

const lines = [];
lines.push(`l4-go gate payload`);
lines.push(`gate: ${gate}`);
lines.push(`run_id: ${begin.run_id}`);
lines.push(`milestone: ${begin.milestone}`);
lines.push(`subject: ${begin.subject}`);
lines.push(`repo_head: ${begin.repo_head}`);
lines.push(`tree_state: ${begin.tree_state}`);
lines.push(`fixed_now: ${begin.fixed_now}`);
lines.push("");
lines.push("corpus (sha256 of every file this gate blesses):");
for (const [name, sha] of corpus.sort()) lines.push(`  ${name} ${sha}`);
// THE TOOLCHAIN THE ANSWER DEPENDS ON.
//
// The corpus section above names what the gate BLESSES. This names what the
// blessing is CONDITIONAL ON, and it exists because those are different sets
// and the difference was invisible: the `l4` binary and the L4 standard library
// are inputs to every stage, and until 2026-08-20 the standard library was in
// no digest at all. Measured then: substituting one word in `daydate.l4`'s DATE
// comparison left all 79 sg-paa assertions passing and byte-identical while a
// boundary EVAL went TRUE -> FALSE. A signer who is shown seven corpus hashes
// and nothing else is being asked to bless an answer whose other half they
// cannot see.
//
// Recorded from p0-preflight's metrics, on the same contract as the corpus
// section: if a value is not on the receipt it is not in this document. A run
// whose p0-preflight predates these metrics renders "(not recorded)" for that
// line rather than omitting it, so an old journal reads as a gap and not as an
// absence of dependency.
const toolchainKeys = [
  ["l4 binary     ", "l4_binary_sha"],
  ["l4 stdlib     ", "l4_stdlib_sha"],
  ["l4 stdlib path", "l4_stdlib"],
];
lines.push("");
lines.push(
  "toolchain this answer depends on (not blessed by this signature, but fixed by it):",
);
for (const [label, key] of toolchainKeys)
  lines.push(`  ${label} ${p0?.metrics?.[key] ?? "(not recorded)"}`);

lines.push("");
lines.push("receipts that EXECUTED before this gate (replays excluded):");
for (const r of stageEnds) lines.push(`  ${r.stage} ${r.status} ${r.hash}`);
lines.push("");
lines.push(
  "Signing this payload approves exactly this content. Any later change",
);
lines.push(
  "to a corpus file or an earlier receipt changes this payload's digest,",
);
lines.push("the signature stops verifying, and the gate closes again.");
lines.push("Resuming a run does NOT change it: a replayed receipt re-states a");
lines.push("verdict this payload already covers, so it is not listed above.");
process.stdout.write(lines.join("\n") + "\n");
