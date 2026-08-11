#!/usr/bin/env node
// Render the conversion report from journal.ndjson AND NOTHING ELSE.
//
// Four rules, all enforced here rather than by convention:
//
//   1. The template carries no measured numbers. Every figure is a placeholder
//      resolved from a journal row. A digit-run in the template that is not on
//      the small allowlist below is a template defect (exit 4).
//   2. An unresolved placeholder is a hard error (exit 4). A claim with no
//      journal row cannot be printed.
//   3. A required section with no rows renders as "ABSENT", never omitted, and
//      says which stage would have supplied it.
//   4. Every CLAIM comes from the journal — but the artifacts table also asks
//      the disk whether the files those claims name are still there, and prints
//      GONE or CHANGED when they are not. Rule 1 forbids typing a number;
//      it does not license printing a recorded byte count and sha256 under the
//      heading "Every artifact this run put on disk" for a file that is not on
//      disk. That is what this renderer used to do, on every resumed run whose
//      artifacts had been cleaned up: `go.sh verify` found them GONE while the
//      report tabulated their sizes as fact.
//
// And one property that makes the whole honesty stance self-defending: this
// renderer verifies the journal's hash chain, and prints the failure IN THE
// REPORT when it does not verify. Hand-editing the journal produces a report
// that says the journal was hand-edited.
//
// Usage: node etc/go/report/render-report.mjs RUNDIR [--format md,html]
// Exit:  0 rendered · 2 usage · 4 template defect or unresolved placeholder

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { sha256File, verify } from "../lib/ledger.mjs";
import { milestoneVerdict } from "../lib/verdict.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TEMPLATE = resolve(HERE, "template.md");

// Tokens that may legitimately carry digits in the template: spec coordinates
// and standard version numbers. Everything else with two or more digits is a
// transcribed measurement and is refused.
const ALLOWED_DIGIT_TOKENS = [
  /\b17 CFR Part 227\b/g,
  /\bG[0-4]\b/g,
  /\bP(?:10|[1-9])\b/g,
  /\bR[0-7]\b/g,
  /\bHG[12]\b/g,
  /\bDMN 1\.3\b/g,
  /\bAKN 3\.0\b/g,
  /\bBPMN 2\.0\b/g,
  /§ ?\d+(\.\d+)*/g,
  /\bv0\b/g,
];

const args = process.argv.slice(2);
const positional = args.filter((a, i) => {
  if (a.startsWith("--")) return false;
  const prev = args[i - 1];
  return !(prev === "--format" || prev === "--out");
});
const rundir = positional[0];
const fmtIdx = args.indexOf("--format");
const formats = (fmtIdx >= 0 ? args[fmtIdx + 1] : "md").split(",");
const outIdx = args.indexOf("--out");
if (!rundir) {
  process.stderr.write("usage: render-report.mjs RUNDIR [--format md,html]\n");
  process.exit(2);
}

const journalPath = resolve(rundir, "journal.ndjson");
if (!existsSync(journalPath)) {
  process.stderr.write(`render-report.mjs: no journal at ${journalPath}\n`);
  process.exit(2);
}

// --- template hygiene, checked before anything is rendered -------------------
const template = readFileSync(TEMPLATE, "utf8");
{
  let scrubbed = template
    .replace(/<!--[\s\S]*?-->/g, "") // the header comment explains the rule; it may cite it
    .replace(/```[\s\S]*?```/g, "") // fenced blocks are commands, not claims
    .replace(/\{\{[^}]*\}\}/g, ""); // placeholders resolve to measured values
  for (const re of ALLOWED_DIGIT_TOKENS) scrubbed = scrubbed.replace(re, "");
  const stray = scrubbed.match(/\d{2,}/g);
  if (stray) {
    process.stderr.write(
      `render-report.mjs: TEMPLATE DEFECT — literal numbers in ${TEMPLATE}: ${[...new Set(stray)].join(", ")}\n` +
        `Every measured figure must be a {{placeholder}} resolved from a journal row. A number typed\n` +
        `into the template is a claim with no evidence behind it, and it is how PROJECTIONS.md came to\n` +
        `state a fidelity heading, a per-code table and two line counts that its own artifacts\n` +
        `contradicted. (This sentence gives no COUNT on purpose: three sites once gave three\n` +
        `different ones, and the count changes every time the document is repaired.)\n`,
    );
    process.exit(4);
  }
}

// --- the journal -------------------------------------------------------------
const chain = verify(journalPath);
const records = chain.records;
const begin = records.find((r) => r.kind === "run_begin");
const end = records.filter((r) => r.kind === "run_end").pop();
const allStageEnds = records.filter((r) => r.kind === "stage_end");
// Latest row per stage wins; earlier rows remain on the journal as history. A
// Map built in journal order does exactly that.
const stageEnds = [...new Map(allStageEnds.map((r) => [r.stage, r])).values()];
const gateRecs = records.filter((r) => r.kind === "gate");
const byStage = new Map(stageEnds.map((r) => [r.stage, r]));

// A journal with no run_begin describes no run, and a report over it would be
// a page of "(none)" carrying a verdict nothing earned. Refuse rather than
// render: an empty report that looks complete is worse than no report.
if (!begin) {
  process.stderr.write(
    `render-report.mjs: ${journalPath} has no run_begin record, so there is no run to report on. ` +
      `Refusing to render a report whose every field would be a placeholder.\n`,
  );
  process.exit(4);
}

const declared = begin?.declared_stages ?? [];
const gateStates = [...new Map(gateRecs.map((g) => [g.gate, g])).values()].map(
  (g) => ({
    gate: g.gate,
    state: g.state,
    reason: g.reason,
    signature_file: g.signature_file,
    seq: g.seq,
  }),
);
const mv = milestoneVerdict({
  declared,
  receipts: stageEnds,
  gates: gateStates,
});

const esc = (s) =>
  String(s ?? "")
    .replace(/\|/g, "\\|")
    .replace(/\n/g, " ");
const absent = (what, who) =>
  `**ABSENT.** ${what} No stage in this run wrote it; ${who}`;

// --- section builders --------------------------------------------------------
function gatesTable() {
  if (!gateStates.length)
    return absent(
      "SPEC.md §7.3 defines two human gates, HG1 and HG2.",
      "no gate record exists, which means no gated stage was reached.",
    );
  const rows = gateStates.map((g) => {
    let how;
    if (g.state === "satisfied")
      how = `satisfied by \`${g.signature_file ?? "(no signature file recorded)"}\``;
    else if (g.state === "waived") how = `**waived**: ${esc(g.reason)}`;
    else how = `**refused**: ${esc(g.reason)}`;
    return `| ${g.gate} | ${g.state} | ${how} |`;
  });
  return ["| gate | state | how |", "| --- | --- | --- |", ...rows].join("\n");
}

function projectionsTable() {
  const legs = declared.filter((s) => s.startsWith("p7-"));
  if (!legs.length)
    return absent(
      "SPEC.md §P7 lists seven projection legs.",
      "no p7 stage is declared for this milestone.",
    );
  const rows = legs.map((s) => {
    const r = byStage.get(s);
    if (!r) return `| \`${s}\` | — | **no receipt** | the stage did not run |`;
    // A replayed receipt deliberately carries no oracle of its own: the oracle
    // ran, on inputs whose digest is byte-identical, and its row is in this
    // same journal. Say that, rather than printing a bare "none" against a
    // PASS — which reads as a PASS the lattice would have refused.
    const oracle = r.oracle
      ? `${r.oracle.class}`
      : r.replayed_from
        ? "replayed"
        : "none";
    const label = r.label ? ` (${r.label})` : "";
    // A PASS carries no `reason` — the lattice requires a reason only where the
    // status is not green. What it does carry is the oracle's `because`, which
    // is the equivalent sentence: why this evidence licenses this status.
    const says =
      r.reason ??
      r.oracle?.because ??
      (r.replayed_from
        ? `inputs unchanged; the verdict and its evidence are the receipt ${r.replayed_from.slice(0, 23)}… on this journal`
        : "");
    return `| \`${s}\` | ${r.status}${label} | ${oracle} | ${esc(says)} |`;
  });
  return [
    "| leg | status | oracle class | what it says |",
    "| --- | --- | --- | --- |",
    ...rows,
  ].join("\n");
}

function projectionsDetail() {
  const legs = declared.filter((s) => s.startsWith("p7-"));
  const out = [];
  for (const s of legs) {
    const r = byStage.get(s);
    if (!r) continue;
    out.push(`### \`${s}\` — ${r.status}${r.label ? ` (${r.label})` : ""}`);
    out.push("");
    if (r.reason) out.push(r.reason);
    if (r.blocker) {
      out.push("");
      out.push(`**Blocker.** ${r.blocker}`);
    }
    if (r.oracle) {
      out.push("");
      out.push(
        `**Oracle** (\`${r.oracle.class}\`, exit ${r.oracle.exit}): \`${r.oracle.cmd}\``,
      );
      if (r.oracle.because) out.push(`${r.oracle.because}`);
    } else if (r.replayed_from) {
      out.push("");
      out.push(
        "**Oracle:** none in this receipt — see the replay note below, which names the receipt whose oracle did run.",
      );
    } else {
      out.push("");
      out.push("**Oracle:** none ran.");
    }
    const m = Object.entries(r.metrics || {});
    if (m.length) {
      out.push("");
      out.push(m.map(([k, v]) => `\`${k}=${esc(v)}\``).join(" · "));
    }
    for (const n of r.notes || [])
      out.push(`\n> *claimed, not verified* (${n.author}): ${n.text}`);
    if (r.replayed_from)
      out.push(
        `\n*Replayed* from receipt \`${r.replayed_from}\` — the inputs were unchanged and the oracle did not run again.`,
      );
    out.push("");
  }
  return out.join("\n") || absent("Per-leg detail.", "no p7 receipt exists.");
}

/**
 * One receipt, rendered whole: status, reason, oracle, metrics, notes.
 *
 * `label` prefixes the status line when a section carries more than one
 * receipt, so a reader can tell which stage is speaking.
 *
 * A PASS receipt has `reason: null` BY DESIGN — the reason field exists to
 * explain a non-PASS, and verdict.mjs's rule 3 requires it only there. So the
 * status line drops the dash entirely rather than printing the JS literal
 * `null`, which is what the de novo sections did before this helper existed:
 * a measured `**PASS** — null` in a report whose whole job is to say why.
 *
 * The oracle's `because` and the notes are not decoration. A de novo stage's
 * PASS is a narrow structural claim, and everything it does NOT establish
 * rides on those two fields — p1-ingest's "whether the bundle is the RIGHT
 * text is unverified", p5-gate's two `CARRIED BY HG1` halves. Rendering the
 * status without them turns a hedged claim into a bare green.
 */
function receiptBlock(r, label) {
  const head = label ? `**${label}:** ${r.status}` : `**${r.status}**`;
  const lines = [r.reason ? `${head} — ${r.reason}` : head];
  if (r.oracle) {
    lines.push("");
    lines.push(`Oracle (\`${r.oracle.class}\`): \`${r.oracle.cmd}\``);
    lines.push("");
    lines.push(r.oracle.because ?? "");
  }
  const m = Object.entries(r.metrics || {});
  if (m.length)
    lines.push("", m.map(([k, v]) => `\`${k}=${esc(v)}\``).join(" · "));
  for (const n of r.notes || [])
    lines.push(`\n> *claimed, not verified* (${n.author}): ${n.text}`);
  return lines.join("\n");
}

function testsSection() {
  const r = byStage.get("p6-tests");
  if (!r)
    return absent(
      "SPEC.md §P6 requires the test results.",
      "`p6-tests` has no receipt in this run.",
    );
  return receiptBlock(r);
}

function sourceSection() {
  const r = byStage.get("p1-ingest");
  if (r) return receiptBlock(r);
  const p0 = byStage.get("p0-preflight");
  const shas = Object.entries(p0?.metrics ?? {})
    .filter(([k]) => k.startsWith("corpus_sha_"))
    .map(([k, v]) => `| \`${k.replace(/^corpus_sha_/, "")}\` | \`${v}\` |`);
  return [
    absent(
      "SPEC.md §P1 requires the source bundle with provenance — the SEC entry point, the eCFR retrieval, and the FR citations for the adoption and each amendment.",
      "`p1-ingest` is not declared at this milestone: the corpus is REPLAYED, not re-derived from source, so no ingest happened and none is claimed. (The stage itself no longer refuses — at `g2` it validates a deposited source bundle — but a bundle is not what this run read.)",
    ),
    "",
    "What this run did read, and its exact content:",
    "",
    "| file | sha256 |",
    "| --- | --- |",
    ...(shas.length ? shas : ["| (none recorded) | |"]),
  ].join("\n");
}

function sweepSection() {
  const r = byStage.get("p2-sweep");
  if (r) return receiptBlock(r);
  return absent(
    'SPEC.md §P2 requires the external-modification register, and requires this report to state what was SEARCHED, not only what was found — "no modification found" is a checked claim, not a default.',
    "`p2-sweep` is not declared at this milestone. Nothing was searched, so nothing may be reported as searched, and this report makes no claim that the encoding is current with respect to courts, C&DIs, no-action letters, or rules in flight. (At `g2` the stage validates a deposited register — but note that validating a register is not performing a sweep: no procedure enumerates the searches that should have run.)",
  );
}

/**
 * SPEC.md §P3/§P4 want "what the encoding decided, including every ambiguity
 * fork and every externally-settled resolution", and P5 is the gate over that
 * same material. Three receipts answer to this heading, so all three are
 * rendered — labelled, whole, and each with its own notes.
 *
 * This section used to render `p3-encode` alone and name `p4-forks` only in
 * the ABSENT prose, which was measurable as a silence: a `g2` run whose fork
 * register had been deposited and validated produced a `p4-forks` receipt that
 * appeared NOWHERE in the report, and a `p5-gate` receipt whose two
 * `CARRIED BY HG1` notes — the halves of the gate no script holds — likewise
 * reached no reader. ORCHESTRATOR.md §5.2 asserted that every de novo receipt's
 * reason "appears in the report"; measured, three of the five did.
 */
function encodingSection() {
  const r = byStage.get("p3-check");
  const enc = byStage.get("p3-encode");
  const forks = byStage.get("p4-forks");
  const gate = byStage.get("p5-gate");
  const out = [];
  const denovo = [
    [enc, "Encoding (de novo)"],
    [forks, "Ambiguity forks"],
    [gate, "Adversarial gate (mechanisable half)"],
  ].filter(([rec]) => rec);
  for (const [rec, label] of denovo) {
    if (out.length) out.push("");
    out.push(receiptBlock(rec, label));
  }
  if (!denovo.length)
    out.push(
      absent(
        "SPEC.md §P3/§P4 require what the encoding decided, including every ambiguity fork and every externally-settled resolution.",
        "`p3-encode`, `p4-forks` and `p5-gate` are not declared at this milestone — they validate de novo deposits, and this run replayed the committed corpus — so this run made no encoding decisions and opened no forks. The encoding it exercised is the committed corpus.",
      ),
    );
  if (r) {
    out.push("");
    out.push(
      `**What was checked about the committed encoding:** ${r.status} — ${r.reason ?? ""}`,
    );
    if (r.oracle)
      out.push(
        "",
        `Oracle (\`${r.oracle.class}\`): \`${r.oracle.cmd}\``,
        "",
        r.oracle.because ?? "",
      );
    for (const n of r.notes || [])
      out.push(`\n> *claimed, not verified* (${n.author}): ${n.text}`);
  }
  return out.join("\n");
}

/**
 * Every stage this report does not otherwise narrate.
 *
 * WHY THIS EXISTS. The verdict gloss above claims, of a COMPLETE run, that
 * "every non-PASS receipt carries a reason that appears below". That was a
 * standing falsehood the moment a non-PASS receipt existed outside the sites
 * named in this file: `projectionsTable`/`projectionsDetail` narrate exactly
 * `p7-*`, and every other block is hard-wired to a stage name. `p9-report`
 * escaped the hole only because it can emit nothing but PASS or a hard failure.
 * `p9-explain` cannot — it is DEGRADED whenever a narrative section is
 * unreviewed, which is its normal state — so a real, reasoned, non-PASS receipt
 * reached the journal and no reader. MEASURED on run 2026-08-03-3f45e62b-004:
 * five of six non-PASS reasons reached the report and `p9-explain`'s did not.
 *
 * The set is computed by SUBTRACTION rather than listed, so the next stage
 * added anywhere in the pipeline lands here by default instead of vanishing.
 * A stage that gets its own narrated site later simply stops appearing here.
 */
const NARRATED_ELSEWHERE = new Set([
  "p0-preflight",
  "p1-ingest",
  "p2-sweep",
  "p3-check",
  "p3-encode",
  "p4-forks",
  "p5-gate",
  "p6-tests",
  "p8-diff", // narrated whole in triageSection()
]);
function otherStagesSection() {
  const rows = stageEnds.filter(
    (r) => !NARRATED_ELSEWHERE.has(r.stage) && !r.stage.startsWith("p7-"),
  );
  if (!rows.length)
    return absent(
      "Every receipt on this journal must reach a reader, whatever stage wrote it — the verdict gloss above promises exactly that.",
      "every stage of this run is accounted for under one of the headings above, so there is nothing left over.",
    );
  const out = [
    "The stages above are narrated under the heading they belong to. These are the rest — reporting stages, and anything added to the pipeline that has no heading of its own yet. They are here because the verdict gloss at the top of this report promises that every non-PASS receipt's reason appears below, and a stage with no site is how that promise quietly stops being true.",
    "",
  ];
  for (const r of rows.sort((a, b) => a.stage.localeCompare(b.stage))) {
    out.push(receiptBlock(r, `\`${r.stage}\``));
    out.push("");
  }
  return out.join("\n");
}

function comparisonSection() {
  return absent(
    "SPEC.md §P9 requires a factual note of disagreement wherever another system has published its own representation of the same rule.",
    "no stage in this milestone reads another system's representation. Making that comparison is R2's read-only probe, and any contact is HG2's subject.",
  );
}

function triageSection() {
  // p8-diff (2026-08-09) is this section's stage: it runs SPEC.md §8's diff
  // oracle over the declared surface map and emits the triage table with every
  // row UNTRIAGED — the three dispositions are judgements, owned by the skill
  // and then HG1, never by a script. Its receipt renders here, whole, and this
  // is its narrated site (it is in NARRATED_ELSEWHERE below).
  const r = byStage.get("p8-diff");
  if (!r)
    return absent(
      "SPEC.md §8's triage table classifies each disagreement between the de novo encoding and the committed corpus as encoding error / genuine ambiguity / improvement over the hand corpus.",
      "`p8-diff` — the stage that runs the diff oracle (`etc/go/lib/denovo-diff.mjs`) over the subject's declared surface map — has no receipt in this run. It is declared at milestone `g2`; a `g1` run replays one encoding and compares nothing.",
    );
  const m = r.metrics || {};
  const head =
    r.status === "SKIPPED" || r.status === "DEGRADED"
      ? []
      : [
          `The comparator evaluated **${esc(m.evaluations ?? "?")}** (pair, row) cells over ${esc(m.pairs ?? "?")} declared pair(s): ${esc(m.agreed ?? "?")} agreed, **${esc(m.diverged ?? "?")} diverged**, ${esc(m.untriaged ?? "?")} untriaged. Every divergence witness is emitted \`UNTRIAGED\` in the \`denovo-diff.md\` artifact; triaging them (encoding error / genuine ambiguity / improvement) is the reviewer's act, and a run that finds a divergence is §8's *better* pass.`,
          "",
        ];
  return [...head, receiptBlock(r, "`p8-diff`")].join("\n");
}

// The one place this renderer looks at anything other than the journal, and it
// looks only to CONTRADICT the journal where the journal has gone stale. It
// prints no figure taken from disk: the bytes and sha256 columns are still the
// recorded ones, and the state column says whether they are still true.
function artifactState(a) {
  if (a.absent) return "ABSENT";
  const p = isAbsolute(a.path) ? a.path : resolve(rundir, a.path);
  if (!existsSync(p)) return "GONE";
  try {
    return sha256File(p) === a.sha256 ? "on disk" : "CHANGED";
  } catch {
    return "UNREADABLE";
  }
}

function artifactsTable() {
  const rows = [];
  let notOnDisk = 0;
  for (const r of stageEnds) {
    for (const a of r.artifacts || []) {
      const state = artifactState(a);
      if (state !== "on disk") notOnDisk++;
      rows.push(
        `| \`${r.stage}\` | \`${basename(a.path)}\` | ${a.absent ? "—" : a.bytes} | \`${a.absent ? "—" : a.sha256.slice(0, 23)}…\` | ${state === "on disk" ? state : `**${state}**`} |`,
      );
    }
  }
  if (!rows.length)
    return absent(
      "Every status must point at an artifact.",
      "no receipt names one, which should be impossible.",
    );
  const table = [
    "| stage | artifact | bytes (recorded) | sha256 (recorded) | state now |",
    "| --- | --- | --- | --- | --- |",
    ...rows,
  ].join("\n");
  if (!notOnDisk) return table;
  return [
    `**${notOnDisk} of the ${rows.length} artifacts this run recorded no longer hash as recorded.** The bytes and sha256 ` +
      `columns below are what the receipts said at the time; the last column is what the disk says now. A ` +
      `\`GONE\` or \`CHANGED\` row means this report's evidence for that stage's status cannot be re-checked ` +
      `from this run directory. Re-derive with \`etc/go/go.sh verify\`, which reports the same rows and exits 1.`,
    "",
    table,
  ].join("\n");
}

const MILESTONE_GLOSS = {
  g1: "the replay run. The existing corpus is driven through every reachable projection; nothing is encoded from source.",
  g2: "the de novo run.",
};
const VERDICT_GLOSS = {
  COMPLETE:
    "COMPLETE means every declared stage has a receipt, no receipt is BROKEN, every non-PASS receipt carries a reason that appears below, and every gate is signed or explicitly waived. It is completeness of accounting, NOT greenness: legs below may report NOT-EXECUTABLE, DEGRADED or NOT-REGENERATED, and each says why.",
  INCOMPLETE:
    "INCOMPLETE means a declared stage has no receipt, or a non-PASS receipt gave no reason. The gaps are listed below.",
  GATE: "GATE means a human gate was not satisfied and the run refused to continue past it.",
  BROKEN:
    "BROKEN means a harness defect, not a finding about the corpus. Nothing below should be read as a statement about the encoding.",
};

const values = {
  "run.id": begin?.run_id ?? "(none)",
  "run.milestone_upper": (begin?.milestone ?? "?").toUpperCase(),
  "run.milestone_gloss":
    MILESTONE_GLOSS[begin?.milestone] ?? "(no gloss recorded)",
  "run.subject": begin?.subject ?? "(none)",
  "run.repo_head": begin?.repo_head ?? "(none)",
  "run.tree_state": begin?.tree_state ?? "(unknown)",
  "run.fixed_now": begin?.fixed_now ?? "(unpinned)",
  "run.l4_binary": begin?.l4_binary ?? "(none)",
  "run.journal_path": journalPath,
  "run.record_count": String(records.length),
  "run.chain_state": chain.ok
    ? "verifies"
    : `**DOES NOT VERIFY** — ${chain.problems.join("; ")}`,
  "run.verdict": end?.verdict ?? mv.verdict,
  "run.verdict_gloss":
    VERDICT_GLOSS[end?.verdict ?? mv.verdict] ?? "(no gloss recorded)",
  "gates.table": gatesTable(),
  "sections.source": sourceSection(),
  "sections.sweep": sweepSection(),
  "sections.encoding": encodingSection(),
  "projections.table": projectionsTable(),
  "projections.detail": projectionsDetail(),
  "sections.tests": testsSection(),
  "sections.comparison": comparisonSection(),
  "sections.other_stages": otherStagesSection(),
  "sections.triage": triageSection(),
  "artifacts.table": artifactsTable(),
  "footer.generated": `*Generated by \`etc/go/report/render-report.mjs\` from \`${journalPath}\`. Nothing in this report was typed; every figure resolves from a journal row.*`,
};

let md = template.replace(/<!--[\s\S]*?-->\n?/, "");
md = md.replace(/\{\{([^}]+)\}\}/g, (_, key) => {
  const k = key.trim();
  if (!(k in values)) {
    process.stderr.write(
      `render-report.mjs: UNRESOLVED PLACEHOLDER {{${k}}} — a claim with no journal row cannot be printed.\n`,
    );
    process.exit(4);
  }
  return values[k];
});

const leftover = md.match(/\{\{[^}]*\}\}/g);
if (leftover) {
  process.stderr.write(
    `render-report.mjs: unresolved placeholders remain: ${leftover.join(", ")}\n`,
  );
  process.exit(4);
}

const written = [];
const outDir = outIdx >= 0 ? resolve(args[outIdx + 1]) : resolve(rundir);
if (formats.includes("md")) {
  const p = resolve(outDir, "report.md");
  writeFileSync(p, md);
  written.push(p);
}
if (formats.includes("html")) {
  // Deliberately minimal: a <pre> wrapper, no markdown engine, no dependency.
  // The markdown IS the report; the HTML is a convenience and says so.
  const p = resolve(outDir, "report.html");
  const escapeHtml = (s) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  writeFileSync(
    p,
    `<!doctype html><meta charset="utf-8"><title>${escapeHtml(values["run.milestone_upper"])} conversion report — ${escapeHtml(values["run.subject"])}</title>` +
      `<style>body{font:14px/1.55 ui-monospace,Menlo,monospace;max-width:60rem;margin:2rem auto;padding:0 1rem}pre{white-space:pre-wrap}</style>` +
      `<p><em>This HTML is a convenience wrapper. <code>report.md</code> is the report.</em></p><pre>${escapeHtml(md)}</pre>\n`,
  );
  written.push(p);
}

for (const p of written) process.stdout.write(`render-report: wrote ${p}\n`);
process.exit(0);
