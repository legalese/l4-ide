#!/usr/bin/env node
// Render the EXPLAINER from journal.ndjson, the subject's checked-in narrative,
// and the artifacts this run's receipts attest — and from nothing else.
//
// The audit report (report/template.md + render-report.mjs) accounts for what a
// run did and is unreadable to anyone outside the project. This is its
// reader-facing sibling: it explains the body of law, and — interleaved, never
// bolted on — what happened when somebody tried to make that law executable.
//
// EXPLAINER-REPORT-SPEC.md owns the design. Five rules are enforced here rather
// than by convention:
//
//   1. The template carries no measured numbers. Same bare-digit-run check the
//      audit report's template gets, same allowlist, run before the journal is
//      opened. Exit 4.
//   2. An unresolved placeholder is a hard error. Exit 4.
//   3. Every OTHER number lives in a narrative file, where it must be a
//      placeholder or a citation whose source line is RE-READ AND MATCHED here,
//      at render time (lib/narrative.mjs). A citation that does not resolve
//      prints the figure followed by a visible complaint and degrades the run.
//   4. A section whose licensing receipt is missing renders ABSENT with the
//      reason, never omitted — and an unreviewed narrative section renders
//      behind a draft banner, never silently.
//   5. Nothing is read from disk that this run's journal does not attest,
//      except the narrative (whose digests are recorded in provenance.json) and
//      the sources those narrative citations name.
//
// WHY THE JOURNAL FOLD IS DUPLICATED rather than lifted into a shared library:
// EXPLAINER-REPORT-SPEC.md §3.5. D2 says the audit report's invariant survives
// completely untouched, and selftest.mjs asserts things about
// render-report.mjs's SOURCE TEXT, so a refactor that moved code out of it
// could turn an unrelated assertion red. The duplication is defended by an
// equality test (selftest.mjs, "both renderers fold one journal the same way"),
// not by care. If that test cannot be written, this decision is wrong.
//
// Usage: node etc/go/report/render-explainer.mjs RUNDIR [--format md,html] [--out DIR]
// Exit:  0 rendered · 2 usage · 4 template defect, unresolved placeholder,
//        no run_begin, or a malformed narrative deposit

import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { sha256File, verify } from "../lib/ledger.mjs";
import { loadSubject } from "../lib/subject.mjs";
import {
  driftFor,
  lintNarrative,
  loadManifest,
  loadProvenance,
  resolveCitations,
} from "../lib/narrative.mjs";
import {
  decisionTables,
  drgCounts,
  ruleDateTables,
} from "../lib/dmn-tables.mjs";
import {
  escapeAttr,
  escapeText,
  lintMarkdown,
  mdToHtml,
  rawToken,
} from "./md-lite.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../../..");
const TEMPLATE = resolve(HERE, "explainer-template.md");

// Tokens that may legitimately carry digits in the template: spec coordinates
// and standard version numbers. Copied from render-report.mjs deliberately —
// see the header note on why that file is not opened by this build.
const ALLOWED_DIGIT_TOKENS = [
  /\b17 CFR Part 227\b/g,
  /\bG[0-4]\b/g,
  /\bP(?:10|[1-9])\b/g,
  /\bR[0-7]\b/g,
  /\bE\d{1,2}\b/g,
  /\bHG[12]\b/g,
  /\bDMN 1\.3\b/g,
  /\bAKN 3\.0\b/g,
  /\bBPMN 2\.0\b/g,
  /§ ?\d+(\.\d+)*/g,
  /\bv0\b/g,
];

// One inline <style>, no external resource of any kind, and the document must
// remain legible with CSS disabled: the draft banners are text, and the styling
// only makes them easier to see. The ladder SVGs carry an opaque white
// background rect of their own — the artifact is the evidence and is not edited
// — so in dark mode they are BOXED on a light card rather than stripped.
const STYLE = `
:root{--fg:#16181d;--bg:#fbfbf9;--muted:#5c6069;--rule:#d8d8d2;--accent:#7a1f1f;--card:#fff}
@media (prefers-color-scheme:dark){:root{--fg:#e6e6e1;--bg:#14161a;--muted:#a0a4ad;--rule:#333840;--accent:#e8a0a0;--card:#fff}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
 font:16px/1.65 Georgia,"Iowan Old Style","Times New Roman",serif}
main{max-width:46rem;margin:0 auto;padding:3rem 1.25rem 6rem}
h1{font-size:1.9rem;line-height:1.2;margin:0 0 1rem}
h2{font-size:1.4rem;margin:3rem 0 .75rem;padding-top:.5rem;border-top:2px solid var(--rule)}
h3{font-size:1.15rem;margin:2rem 0 .5rem}
h4{font-size:1rem;margin:1.5rem 0 .4rem;color:var(--accent);letter-spacing:.02em}
p,li{margin:.7rem 0}
code,pre{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:.85em}
pre{background:rgba(127,127,127,.1);padding:.75rem 1rem;border-radius:4px;overflow-x:auto}
blockquote{margin:1.2rem 0;padding:.6rem 0 .6rem 1rem;border-left:4px solid var(--accent);
 color:var(--muted);background:rgba(127,127,127,.06)}
blockquote p{margin:.35rem 0}
table{border-collapse:collapse;width:100%;font-size:.87rem;font-family:ui-monospace,Menlo,monospace}
th,td{border:1px solid var(--rule);padding:.35rem .5rem;text-align:left;vertical-align:top}
th{background:rgba(127,127,127,.12)}
.scroll{overflow-x:auto;max-width:100%}
figure{margin:1.75rem 0}
figure .scroll{background:var(--card);border:1px solid var(--rule);border-radius:4px;padding:.5rem}
figure svg{max-width:none;height:auto}
figcaption{color:var(--muted);font-size:.85rem;margin-top:.5rem}
hr{border:0;border-top:1px solid var(--rule);margin:2.5rem 0}
a{color:inherit}
`;

// ------------------------------------------------------------------ arguments
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
  process.stderr.write(
    "usage: render-explainer.mjs RUNDIR [--format md,html] [--out DIR]\n",
  );
  process.exit(2);
}
const journalPath = resolve(rundir, "journal.ndjson");
if (!existsSync(journalPath)) {
  process.stderr.write(`render-explainer.mjs: no journal at ${journalPath}\n`);
  process.exit(2);
}

// --- template hygiene, checked before anything is rendered -------------------
const template = readFileSync(TEMPLATE, "utf8");
{
  let scrubbed = template
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/```[\s\S]*?```/g, "")
    .replace(/\{\{[^}]*\}\}/g, "");
  for (const re of ALLOWED_DIGIT_TOKENS) scrubbed = scrubbed.replace(re, "");
  const stray = scrubbed.match(/\d{2,}/g);
  if (stray) {
    process.stderr.write(
      `render-explainer.mjs: TEMPLATE DEFECT — literal numbers in ${TEMPLATE}: ${[...new Set(stray)].join(", ")}\n` +
        `Every run fact must be a {{placeholder}} resolved from a journal row, and every figure about\n` +
        `the law or the encoding must live in a narrative file where it is placeholder-resolved or\n` +
        `citation-checked. A number typed into the template is a claim with no evidence behind it and\n` +
        `no mechanism that would ever notice it going stale.\n`,
    );
    process.exit(4);
  }
}

// --- the journal fold (duplicated from render-report.mjs; see header) --------
const chain = verify(journalPath);
const records = chain.records;
const begin = records.find((r) => r.kind === "run_begin");
const end = records.filter((r) => r.kind === "run_end").pop();
const allStageEnds = records.filter((r) => r.kind === "stage_end");
// Latest row per stage wins; earlier rows remain on the journal as history.
const stageEnds = [...new Map(allStageEnds.map((r) => [r.stage, r])).values()];
const gateRecs = records.filter((r) => r.kind === "gate");
const byStage = new Map(stageEnds.map((r) => [r.stage, r]));

if (!begin) {
  process.stderr.write(
    `render-explainer.mjs: ${journalPath} has no run_begin record, so there is no run to explain. ` +
      `Refusing to render a document whose every run fact would be a placeholder.\n`,
  );
  process.exit(4);
}

const declared = begin.declared_stages ?? [];
const gateStates = [...new Map(gateRecs.map((g) => [g.gate, g])).values()].map(
  (g) => ({
    gate: g.gate,
    state: g.state,
    reason: g.reason,
    signature_file: g.signature_file,
    seq: g.seq,
  }),
);
// The RECORDED verdict is the only verdict this document will print.
//
// It used to fall back to `milestoneVerdict(...)` when no `run_end` existed
// yet, and that produced a FALSE STATEMENT in the copy that carries a hash:
// `p9-explain` renders inside its own stage, before its own `stage_end` and
// before `run_end`, so the recomputation saw a declared stage with no receipt
// and printed `run verdict | **INCOMPLETE**` — while the derived copy the run
// writes afterwards printed `COMPLETE` over the same run. MEASURED on run
// 2026-08-03-3f45e62b-004: 29 records vs 31, INCOMPLETE vs COMPLETE, and the
// attested copy was the wrong one. A recomputation mid-run is not a verdict; it
// is a partial sum. So where the run has not ended, say exactly that.
const verdict = end?.verdict
  ? `**${end.verdict}**`
  : "not yet recorded — this render was taken before `run_end`, so the run had not reached a verdict. " +
    "The audit report carries it; re-render this page after the run ends and this row fills in.";

/**
 * The gates, in the header, because a verdict without them is half a sentence.
 *
 * The audit report prints a Gates table and defines COMPLETE as including
 * "every gate is signed or explicitly waived". This document printed the
 * verdict and NOT the gates, so a reader of run 2026-08-03-3f45e62b-004 saw
 * `run verdict COMPLETE` under a header claiming the document may make no claim
 * the audit report cannot support — while the report, three lines from the same
 * journal row, recorded HG1 as waived with its reason. MEASURED: the string
 * "HG1" did not occur anywhere in that explainer. A waiver is the single fact
 * that most changes what a green verdict means, so it rides in the header.
 */
const gatesSummary = gateStates.length
  ? gateStates
      .map((g) => {
        if (g.state === "satisfied")
          return `**${g.gate}** satisfied by \`${g.signature_file ?? "(no signature file recorded)"}\``;
        if (g.state === "waived")
          return `**${g.gate} WAIVED** — ${String(g.reason ?? "(no reason recorded)").replace(/\|/g, "\\|")}. Nobody reviewed what this gate covers.`;
        return `**${g.gate} ${String(g.state).toUpperCase()}** — ${String(g.reason ?? "(no reason recorded)").replace(/\|/g, "\\|")}`;
      })
      .join("; ")
  : "no gate row is on this journal, so no human gate was recorded either way";

// ------------------------------------------------------------------- helpers
const esc = (s) =>
  String(s ?? "")
    .replace(/\|/g, "\\|")
    .replace(/\n/g, " ");
const absent = (what, who) => `**ABSENT.** ${what} ${who}`;
/**
 * One leg's status line.
 *
 * The explanation is the receipt's `reason`, or failing that its oracle's
 * `because`, and it is printed VERBATIM — never re-cased, never given a
 * terminal stop. Those strings are written as sentence FRAGMENTS ("the emitted
 * DMN was executed by both target engines on committed cases and agreed"),
 * because in the audit report they follow a label. Joining one after a full
 * stop produced "reports **PASS**. the emitted DMN was executed …", which reads
 * as a broken sentence, and capitalising it here would be editing the evidence
 * to make the prose tidy. An em dash makes the fragment a clause, which is what
 * it is. MEASURED on run 2026-08-03-3f45e62b-002, where all four leg lines and
 * the deployment line read that way.
 */
const legLine = (what, r) => {
  const says = String(r.reason ?? r.oracle?.because ?? "").trim();
  // A terminal stop, added only where the fragment does not already end in
  // punctuation. This is typography, not editing: nothing is re-cased, nothing
  // is re-worded, and no character inside the quoted evidence changes. MEASURED
  // on run 2026-08-03-3f45e62b-004, where two of four leg lines ran into the
  // next paragraph ("…never as a pass", "…and agreed") and two did not.
  const stopped = says && !/[.!?…]$/.test(says) ? `${says}.` : says;
  return `${what} reports **${r.status}**${r.label ? ` (${r.label})` : ""}${stopped ? ` — ${stopped}` : "."}`.trim();
};
const short = (s) => String(s ?? "").slice(0, 23) + "…";

/** Artifacts this run attests, indexed by basename, each re-hashed now. */
const artifactIndex = new Map();
for (const r of stageEnds) {
  for (const a of r.artifacts ?? []) {
    if (a.absent) continue;
    const key = basename(a.path);
    const p = isAbsolute(a.path) ? a.path : resolve(rundir, a.path);
    const prior = artifactIndex.get(key);
    if (prior) {
      prior.ambiguous = true;
      continue;
    }
    let ok = false;
    try {
      ok = existsSync(p) && sha256File(p) === a.sha256;
    } catch {
      ok = false;
    }
    artifactIndex.set(key, {
      path: p,
      stage: r.stage,
      bytes: a.bytes,
      recorded: a.sha256,
      ok,
      ambiguous: false,
    });
  }
}
const resolveArt = (name) => artifactIndex.get(name) ?? null;
const resolveSrc = (rel) => {
  const p = resolve(REPO, rel);
  return existsSync(p) ? p : null;
};
/** Read an attested artifact, or null. Never reads a file no receipt names. */
function readArtifact(name) {
  const a = resolveArt(name);
  if (!a || a.ambiguous || !a.ok) return null;
  try {
    return readFileSync(a.path, "utf8");
  } catch {
    return null;
  }
}

// --------------------------------------------------------------- the subject
const subjectId = begin.subject;
const { desc, env } = loadSubject(subjectId);
const explainerDir = env.GO_S_EXPLAINER_DIR
  ? resolve(env.GO_S_EXPLAINER_DIR)
  : null;

if (!explainerDir) {
  process.stderr.write(
    `render-explainer.mjs: subject '${subjectId}' declares no 'explainer' section in subject.json, ` +
      `so it has no narrative to render. That is a clean absence, not a defect: the stage reports ` +
      `SKIPPED with this reason rather than rendering an empty document.\n`,
  );
  process.exit(3);
}

const man = loadManifest(explainerDir);
const prov = loadProvenance(explainerDir);
const schemaProblems = [...man.problems, ...prov.problems];
if (schemaProblems.length) {
  process.stderr.write(
    `render-explainer.mjs: the narrative deposit at ${explainerDir} is malformed:\n` +
      schemaProblems.map((p) => `  - ${p}\n`).join("") +
      `A malformed deposit is a defect in the deposit's SHAPE, which is a harness/config problem, ` +
      `not a finding about the narrative's content. Content findings degrade; this refuses.\n`,
  );
  process.exit(4);
}
const manifest = man.manifest;
const provByFile = new Map(prov.records.map((r) => [r.file, r]));

// ----------------------------------------------------------------- narrative
const findings = []; // { kind, file, detail } — everything that degrades the run
const sectionStates = []; // one row per rendered narrative part, for §S8
let citationsTotal = 0;
let citationsUnchecked = 0;
let citationsUnresolved = 0;

const SOURCE_LIST = (rec) =>
  (rec?.drafted_from ?? [])
    .map((s) => `\`${s.path}\`${s.anchor ? ` (${s.anchor})` : ""}`)
    .join(", ") || "(no source declared)";

/**
 * One narrative part, rendered whole: banners first, then the prose with every
 * citation resolved.
 *
 * The banners are the point. A section whose provenance record is missing, whose
 * text has moved since that record was written, whose source has moved, or whose
 * review no longer covers it, is STILL PRINTED — behind a banner that says so.
 * Suppressing it would let a stale document look tidy, and would let a drafter
 * make an inconvenient paragraph disappear by touching its source.
 */
function narrativePart(rel, { slot }) {
  const abs = resolve(explainerDir, rel);
  const text = readFileSync(abs, "utf8");
  const rec = provByFile.get(rel);
  const banners = [];
  let state = "unreviewed";

  if (!rec) {
    banners.push(
      `**NO PROVENANCE RECORD.** \`${rel}\` is not listed in \`provenance.json\`, so nothing records what it was drafted from and no drift can be detected for it.`,
    );
    findings.push({
      kind: "provenance-missing",
      file: rel,
      detail: "no record",
    });
  } else {
    const d = driftFor(rec, { repoRoot: REPO, dir: explainerDir });
    state = d.state;
    if (d.narrative) {
      banners.push(
        d.narrative.kind === "missing"
          ? `**FILE MISSING.** \`${rel}\` is recorded in \`provenance.json\` and is not on disk.`
          : `**UNRECORDED EDIT.** This text has changed since its provenance record was written (recorded \`${short(d.narrative.recorded)}\`, on disk \`${short(d.narrative.now)}\`). Nothing below has been checked against its sources.`,
      );
      findings.push({
        kind: "narrative-drift",
        file: rel,
        detail: d.narrative.kind,
      });
    }
    for (const s of d.sources) {
      banners.push(
        `**SOURCE MOVED.** Drafted from \`${s.path}\` at \`${short(s.sha256)}\`; that file ${s.kind === "missing" ? "is no longer on disk" : `now hashes \`${short(s.now)}\``}. The prose below may describe text that no longer exists.`,
      );
      findings.push({ kind: "source-drift", file: rel, detail: s.path });
    }
    if (d.review) {
      findings.push({
        kind: "review-drift",
        file: rel,
        detail: "review is stale",
      });
    }
    if (state !== "reviewed") {
      const stale =
        state === "stale" ? " — the review no longer covers this text" : "";
      banners.push(
        `**DRAFT — claimed, not verified${stale}.** Drafted by \`${rec.drafted_by ?? "(unrecorded)"}\` on \`${rec.drafted_on ?? "(unrecorded)"}\` from ${SOURCE_LIST(rec)}. No reviewer has signed this text.`,
      );
    }
  }

  // §6.3: the lint is a DEPOSIT check, reported against the file at a line a
  // person can go fix, not a warning smuggled into the rendered page.
  for (const f of [...lintNarrative(text), ...lintMarkdown(text)])
    findings.push({
      kind: "lint",
      file: rel,
      detail: `${rel}:${f.line} [${f.code}] ${f.message}`,
    });

  const cited = resolveCitations(text, { resolveSrc, resolveArt });
  citationsTotal += cited.total;
  citationsUnchecked += cited.unchecked;
  citationsUnresolved += cited.findings.length;
  for (const f of cited.findings)
    findings.push({
      kind: "citation",
      file: rel,
      detail: `[${f.code}] ${f.target} — ${f.detail}`,
    });

  sectionStates.push({
    slot,
    file: rel,
    state,
    reviewer: rec?.review?.reviewer ?? null,
    drafted_by: rec?.drafted_by ?? null,
    drafted_on: rec?.drafted_on ?? null,
    sources: (rec?.drafted_from ?? []).map((s) => s.path),
    citations: cited.total,
    unchecked: cited.unchecked,
  });

  const bannerBlock = banners.length
    ? banners.map((b) => `> ${b}`).join("\n>\n") + "\n\n"
    : "";
  return bannerBlock + cited.text.trim() + "\n";
}

/** A spine slot that the manifest declined, rendered as a stated declination. */
const declined = (what, why) =>
  `**DECLINED.** ${what} This subject's manifest declines the slot: ${why}`;

function slotBlock(key, { slot, heading = null }) {
  const s = manifest.spine?.[key];
  if (!s)
    return absent(
      `This document's spine has a \`${key}\` slot.`,
      "The subject's manifest declares none.",
    );
  if ("declined" in s)
    return declined(`This document's spine has a \`${key}\` slot.`, s.declined);
  const parts = [];
  for (const part of ["file", "intro", "law", "encoding"]) {
    const rel = s[part];
    if (!rel) continue;
    if (part === "encoding" && heading) parts.push(`${heading}\n`);
    parts.push(narrativePart(rel, { slot: `${slot}.${part}` }));
  }
  return (
    parts.join("\n") ||
    absent(
      `The \`${key}\` slot declares no narrative file.`,
      "Nothing to render.",
    )
  );
}

// ---------------------------------------------------------------- S2, body
function bodySection() {
  const body = manifest.spine?.body ?? [];
  if (!body.length)
    return absent(
      "The body is where the law and its formalization interleave.",
      "This subject's manifest declares no body sections.",
    );
  const out = [];
  for (const entry of body) {
    out.push(`### ${entry.heading}`);
    out.push("");
    if (entry.law)
      out.push(narrativePart(entry.law, { slot: `body.${entry.id}.law` }));
    // `encoding: null` is a LEGAL, SILENT declination. It operationalises "where
    // there is no honest observation about the formalization, say nothing rather
    // than padding": a section cannot be padded into existence by a drafter who
    // feels a gap, only filled by a claim that carries a citation.
    if (entry.encoding) {
      out.push("");
      out.push("#### In the encoding");
      out.push("");
      out.push(
        narrativePart(entry.encoding, { slot: `body.${entry.id}.encoding` }),
      );
    }
    out.push("");
  }
  return out.join("\n");
}

// ------------------------------------------------------------- S3, pictures
const rawBlocks = {}; // sentinel key -> HTML
const mdBlocks = {}; // sentinel key -> markdown

/** The key-decision selection and its rationale, read from where they live. */
function ladderWhy() {
  const entry = desc.legs?.["p7-ladder"]?.demo_entry;
  const out = new Map();
  if (!entry) return out;
  const p = resolve(REPO, entry);
  if (!existsSync(p)) return out;
  const src = readFileSync(p, "utf8");
  const re =
    /decision:\s*"([^"]+)",\s*\n\s*slug:\s*"([^"]+)",\s*\n\s*why:\s*"((?:[^"\\]|\\.)*)"/g;
  for (const m of src.matchAll(re))
    out.set(m[2], { decision: m[1], why: m[3].replace(/\\"/g, '"') });
  return out;
}

function svgViewport(svg) {
  const w = /\bwidth="([\d.]+)"/.exec(svg)?.[1];
  const h = /\bheight="([\d.]+)"/.exec(svg)?.[1];
  const vb = /\bviewBox="([^"]+)"/.exec(svg)?.[1];
  return { w, h, vb };
}

function ladderSubsection() {
  const r = byStage.get("p7-ladder");
  if (!r)
    return absent(
      "A ladder diagram draws one decision's Boolean structure: an AND is a series circuit, an OR a parallel one, and each leaf is a field name carrying the regulation's own words.",
      declared.includes("p7-ladder")
        ? "`p7-ladder` is declared at this milestone and produced no receipt, so no figure is attested."
        : "`p7-ladder` is not declared for this subject, so no figure is attested.",
    );
  const why = ladderWhy();
  const svgs = (r.artifacts ?? []).filter(
    (a) => !a.absent && a.path.endsWith(".svg"),
  );
  if (!svgs.length)
    return [
      `**${r.status}**${r.reason ? ` — ${r.reason}` : ""}`,
      "",
      absent(
        "The ladder leg ran.",
        "Its receipt names no `.svg` artifact, so there is no attested figure to inline.",
      ),
    ].join("\n");

  const out = [
    legLine("The ladder leg", r),
    "",
    "Each figure below is the committed SVG, inlined byte-for-byte after its recorded sha256 was re-checked. None is edited, re-laid-out or trimmed — **trimming is transcription**, and a trimmed ladder is a different rule. The caption is the reason the decision was selected, read from the subject's own demo entry point rather than re-decided here.",
    "",
  ];
  let n = 0;
  for (const a of svgs) {
    const slug = basename(a.path).replace(/\.svg$/, "");
    const key = `ladder-${slug}`;
    const p = isAbsolute(a.path) ? a.path : resolve(rundir, a.path);
    let svg;
    try {
      svg = readFileSync(p, "utf8");
    } catch {
      out.push(
        absent(
          `The figure \`${basename(a.path)}\` is named by the \`p7-ladder\` receipt.`,
          "It is not readable from this run directory.",
        ),
        "",
      );
      continue;
    }
    if (sha256File(p) !== a.sha256) {
      findings.push({
        kind: "artifact-changed",
        file: basename(a.path),
        detail: "the ladder figure no longer hashes as its receipt recorded",
      });
      out.push(
        `**ARTIFACT CHANGED.** \`${basename(a.path)}\` no longer hashes as the \`p7-ladder\` receipt recorded it, so it is not inlined here.`,
        "",
      );
      continue;
    }
    const { w, h } = svgViewport(svg);
    const meta = why.get(slug);
    const wide = Number(w) > 1400;
    const caption =
      `\`${slug}\` — ${meta ? `**${escapeText(meta.decision)}**. ${escapeText(meta.why)}` : "no rationale is recorded for this slug in the subject's demo entry point"}` +
      `. Scene ${w} × ${h}, measured off the file at render time.` +
      (wide
        ? " This one is far wider than it is tall and scrolls sideways: an AND is a series circuit whose scene width is the sum of its children's, and leaf labels never wrap. A correct diagram and an awkward figure."
        : "");
    rawBlocks[key] =
      `<figure class="fig${wide ? " wide" : ""}"><div class="scroll">${svg}</div><figcaption>${mdToHtml(caption).replace(/^<p>|<\/p>$/g, "")}</figcaption></figure>`;
    // NOT AN IMAGE LINK. It used to be `![slug](jl4/examples/…/figures/x.svg)`,
    // a REPO-relative path emitted into a document that lives under TMPDIR, so
    // all six embeds were broken links in the markdown carrier — MEASURED on
    // run 2026-08-03-3f45e62b-004: 6 of 6 targets did not exist relative to the
    // file. An absolute path would resolve on the machine that rendered it and
    // nowhere else. So the markdown says where the picture is and does not
    // pretend to draw it, and the header says the same thing above the fold.
    mdBlocks[key] = [
      `*Figure \`${slug}\` — drawn in \`explainer.html\`. The source SVG is \`${a.path.startsWith(REPO) ? a.path.slice(REPO.length + 1) : a.path}\`.*`,
      "",
      `*${caption}*`,
    ].join("\n");
    out.push(rawToken(key), "");
    n++;
  }
  return out.join("\n");
}

function ltsSubsection() {
  const r = byStage.get("p7-lts");
  const intro =
    "A decision has no state; you evaluate it. A regulative rule has a lifecycle — a duty that is live, fulfilled, breached or renewed — so it induces a labelled transition system, and only that can be drawn as a process. This is the one place where the split between the constitutive rules and the deontic ones becomes a picture.";
  if (!r)
    return [
      intro,
      "",
      absent(
        "The state-graph leg emits one graph per regulative rule.",
        declared.includes("p7-lts")
          ? "`p7-lts` is declared at this milestone and produced no receipt."
          : "`p7-lts` is not declared for this subject.",
      ),
    ].join("\n");

  const svgs = (r.artifacts ?? []).filter(
    (a) => !a.absent && /state-graphs\/.*\.svg$/.test(a.path),
  );
  const dots = (r.artifacts ?? [])
    .filter((a) => !a.absent && a.path.endsWith(".dot"))
    .map((a) => `\`${basename(a.path)}\``);
  const head = legLine("The state-graph leg", r);
  if (!svgs.length)
    return [
      intro,
      "",
      head,
      "",
      absent(
        "The state machines were emitted as GraphViz DOT and not rendered.",
        `No \`dot\` binary was on PATH for this run. This repository has no DOT-to-SVG path of its own — DOT carries no coordinates, so rendering it means running a layout engine, and committing a rendered copy would create a picture with no drift guard at all. The DOT is at ${dots.length ? dots.join(", ") : "the paths this leg's receipt names"}, and \`dot -Tsvg\` reproduces the picture.`,
      ),
    ].join("\n");

  const out = [intro, "", head, ""];
  let namespaced = 0;
  for (const a of svgs) {
    const p = isAbsolute(a.path) ? a.path : resolve(rundir, a.path);
    if (!existsSync(p) || sha256File(p) !== a.sha256) continue;
    const svg = readFileSync(p, "utf8");
    // The split filenames are positional and do NOT say which rule is which;
    // the rule name lives in the DOT graph attribute, so read it from there.
    const dot = p.replace(/\.svg$/, ".dot");
    const label = existsSync(dot)
      ? (/label="([^"]*)"/.exec(readFileSync(dot, "utf8"))?.[1] ?? basename(p))
      : basename(p);
    const key = `lts-${basename(p, ".svg")}`;
    rawBlocks[key] =
      `<figure class="fig"><div class="scroll">${namespaceIds(svg, key)}</div><figcaption>${escapeText(label)} — rendered from the emitted DOT by the <code>dot</code> binary on the machine that ran this.</figcaption></figure>`;
    mdBlocks[key] =
      `*State machine: ${label} — drawn in \`explainer.html\`. The rendered SVG is \`${basename(p)}\` and its GraphViz source is \`${basename(dot)}\`, both under this run's \`artifacts/\`.*`;
    out.push(rawToken(key), "");
    namespaced++;
  }
  if (namespaced > 1)
    out.push(
      `Inlining ${namespaced} GraphViz pictures into one page collides their internal identifiers: \`dot\` numbers its nodes and edges from one per file, so every graph here defines \`graph0\`, \`node1\` and \`edge1\`. An \`<svg>\` element is **not** an identifier scope, so all of them would land in one document namespace. MEASURED on this document before the fix: ${namespaced * 9} definitions of 9 names. Nothing referenced them, so nothing drew wrong — but a DOT that used a gradient or a clip path would emit \`url(#…)\`, the first definition would win for every picture, and two of the three would silently render with the first one's fill. So each figure's identifiers are prefixed with its own slug **in this page only**. The \`.svg\` and \`.dot\` artifacts on disk are untouched and remain the evidence; nothing above this paragraph claims these pictures are inlined byte for byte, and the ladder figures — which do make that claim — carry no identifiers at all.`,
      "",
    );
  return out.join("\n");
}

/**
 * Prefix every `id` an inlined SVG defines, and every intra-document reference
 * to one, with that figure's own key.
 *
 * ONLY the LTS figures go through this, and the distinction is load-bearing:
 * the ladder subsection tells the reader its SVGs are inlined byte for byte
 * after a hash check, so rewriting one would make that sentence false. The
 * ladder exporter emits no `id` at all (MEASURED: zero in all six committed
 * figures), so it never needs this and never gets it.
 */
function namespaceIds(svg, prefix) {
  const names = [
    ...new Set([...svg.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1])),
  ];
  let out = svg;
  for (const n of names) {
    const lit = n.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    out = out
      .replace(new RegExp(`(\\sid=")${lit}(")`, "g"), `$1${prefix}--${n}$2`)
      .replace(new RegExp(`url\\(#${lit}\\)`, "g"), `url(#${prefix}--${n})`)
      .replace(
        new RegExp(`((?:xlink:)?href=")#${lit}(")`, "g"),
        `$1#${prefix}--${n}$2`,
      );
  }
  return out;
}

function bpmnSubsection() {
  const r = byStage.get("p7-bpmn");
  const intro =
    "A BPMN process is the same duty drawn as a workflow: the base case that imposes no duty at all, the renewal loop, and the guards the regulation writes outside the duty.";
  if (!r)
    return [
      intro,
      "",
      absent(
        "The BPMN leg emits one process per regulative rule.",
        declared.includes("p7-bpmn")
          ? "`p7-bpmn` is declared at this milestone and produced no receipt."
          : "`p7-bpmn` is not declared for this subject.",
      ),
    ].join("\n");
  const out = [intro, "", legLine("The BPMN leg", r), ""];
  // What the projection CANNOT say, quoted from the fidelity report rather than
  // paraphrased — a paraphrase of a finding is a different finding.
  const fid = (r.artifacts ?? [])
    .filter((a) => !a.absent && a.path.endsWith(".fidelity.txt"))
    .map((a) => basename(a.path));
  // The report's shape: a `[CODE] severity — element` line, then the finding
  // itself indented on the line after it. The finding sentence is what gets
  // quoted; the element id is the address, not the claim.
  const quoted = [];
  for (const name of fid) {
    const text = readArtifact(name);
    if (!text) continue;
    const lines = text.split("\n");
    lines.forEach((line, i) => {
      const m = /^\[([A-Z]+\d*|[A-Z]-[A-Z]+)\]\s+(\w+)\s+—\s+(\S+)$/.exec(
        line.trim(),
      );
      if (!m || quoted.some((q) => q.code === m[1])) return;
      const says = (lines[i + 1] ?? "").trim();
      if (!says || says.startsWith("[")) return;
      quoted.push({ code: m[1], severity: m[2], at: m[3], says, from: name });
    });
  }
  if (quoted.length) {
    out.push(
      "What the emitted processes could not say, quoted from the fidelity reports this run attests — one row per distinct finding code, in the reports' own words:",
      "",
      "| code | severity | what the projection could not say |",
      "| --- | --- | --- |",
      ...quoted.map(
        (q) => `| \`${q.code}\` | ${q.severity} | ${esc(q.says)} |`,
      ),
      "",
      "The `F1` row is the one to sit with. A prohibition has no shape in this notation, so a diagram of a prohibition, read literally, tells you to do the thing the rule forbids. A hand-drawn diagram of the same rule has exactly the same defect and no note beside it saying so.",
      "",
    );
  } else {
    out.push(
      absent(
        "Each emitted process ships a fidelity report naming what the projection lost.",
        "No `.fidelity.txt` artifact of this leg is readable from this run directory, so none is quoted.",
      ),
      "",
    );
  }
  out.push(
    "No process picture is inlined. Both exporters emit full diagram interchange — the coordinates are already computed — so drawing them needs a serializer rather than a layout engine, and that serializer is not built. This paragraph is the absence, stated with its reason, rather than a promise.",
  );
  return out.join("\n");
}

function dmnSubsection() {
  const r = byStage.get("p7-dmn");
  const intro =
    "A DMN decision requirements graph is the same rules as tables: inputs on the left, one row per case, and a hit policy saying how the rows combine.";
  if (!r)
    return [
      intro,
      "",
      absent(
        "The DMN leg emits the whole corpus as a decision requirements graph.",
        declared.includes("p7-dmn")
          ? "`p7-dmn` is declared at this milestone and produced no receipt."
          : "`p7-dmn` is not declared for this subject.",
      ),
    ].join("\n");

  const out = [intro, "", legLine("The DMN leg", r), ""];
  const dmnName = (r.artifacts ?? [])
    .map((a) => basename(a.path ?? ""))
    .find((n) => n.endsWith(".dmn"));
  const xml = dmnName ? readArtifact(dmnName) : null;
  if (!xml) {
    out.push(
      absent(
        "The tables below are read out of the emitted artifact, never transcribed.",
        `No readable \`.dmn\` artifact of this run is attested${dmnName ? ` (\`${dmnName}\` is named by the receipt and does not hash as recorded, or is gone)` : ""}, so no table is shown.`,
      ),
    );
    return out.join("\n");
  }
  const counts = drgCounts(xml);
  const tables = decisionTables(xml);
  out.push(
    `Read out of \`${dmnName}\` at render time, after re-checking the sha256 its receipt recorded: ${counts.decisions} decisions, ${counts.businessKnowledgeModels} business knowledge models, ${counts.inputData} input data elements and ${counts.itemDefinitions} item definitions. Of the ${counts.decisionTables} decision tables in the file, ${tables.length} sit on a decision and are listed below; the rest sit inside a business knowledge model, which is a callable rather than a node, and are reached by invocation.`,
    "",
    "| decision | hit policy | inputs | rules |",
    "| --- | --- | --- | --- |",
    ...tables.map(
      (t) =>
        `| ${esc(t.name)} | \`${t.hitPolicy}\` | ${t.inputs.length} | ${t.rules.length} |`,
    ),
    "",
  );
  const dated = ruleDateTables(tables);
  if (dated.length) {
    out.push(
      "**The rule-date tables.** These are the exhibit: the temporal axis as a table. The input is typed `date`, the rows are half-open FEEL intervals, the hit policy is `UNIQUE` so exactly one regime can apply, and the annotation column carries each regime's own citation.",
      "",
    );
    for (const t of dated) {
      out.push(`\`${t.name}\` — hit policy \`${t.hitPolicy}\``, "");
      out.push(
        `| ${t.inputs.map((i) => esc(i.expression ?? i.label)).join(" | ")} | ${t.outputs.map((o) => esc(o.label ?? "out")).join(" | ")} | ${t.annotations.map(esc).join(" | ")} |`,
      );
      out.push(
        `| ${[...t.inputs, ...t.outputs, ...t.annotations].map(() => "---").join(" | ")} |`,
      );
      for (const rule of t.rules)
        out.push(
          `| ${[...rule.entries, ...rule.output].map(esc).join(" | ")} | ${esc(rule.annotation)} |`,
        );
      out.push("");
    }
  } else {
    out.push(
      absent(
        "The rule-date table is the temporal axis drawn as a table.",
        "No emitted decision table takes the rule date as an input, so this corpus has no temporal regime to show here.",
      ),
      "",
    );
  }

  // The dmnmd cross-check: two readers of the same decision must agree on the
  // table's shape, or one of them is wrong. A disagreement is a finding.
  const mdName = (byStage.get("p7-dmn-md")?.artifacts ?? [])
    .map((a) => basename(a.path ?? ""))
    .find((n) => n.endsWith(".dmn.md"));
  const mdText = mdName ? readArtifact(mdName) : null;
  if (mdText) {
    const mdTables = (mdText.match(/^\|/gm) ?? []).length;
    const mdHeads = [...mdText.matchAll(/^##\s+(.*)$/gm)].map((m) =>
      m[1].trim(),
    );
    out.push(
      "**And the counterpoint.** The same corpus, projected into the markdown decision-table dialect, is the most honest artifact in the set and the least useful one — which is why it ships. Its loss report is the document; the table is the leftover.",
      "",
      `\`${mdName}\` carries ${mdHeads.length} table heading(s) and ${mdTables} table row(s), against the ${counts.decisionTables} decision tables in the DMN above. Everything the dialect's grammar cannot say — a computed column header, a date cell, a business knowledge model — is omitted rather than approximated, and the omission is itemised.`,
      "",
      "```",
      mdText.trim().split("\n").slice(0, 20).join("\n"),
      "```",
      "",
    );
    // The two artifacts spell the SAME decision differently — the markdown
    // dialect keeps the L4 name in backticks (`ongoing reporting obligation`),
    // the DMN sanitises it (ongoing_reporting_obligation) — so a naive
    // name-equality join silently matches nothing and the cross-check becomes a
    // loop that never runs. Normalise both sides to letters and digits.
    const key = (s) =>
      String(s)
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "");
    let compared = 0;
    for (const h of mdHeads) {
      const t = tables.find((x) => key(x.name ?? "") === key(h));
      if (!t) continue;
      compared++;
      const rows = (mdText.split(`## ${h}`)[1] ?? "").split(/\n##\s/)[0];
      const n = (rows.match(/^\|\s*\d/gm) ?? []).length;
      if (n && n !== t.rules.length)
        findings.push({
          kind: "dmnmd-disagreement",
          file: mdName,
          detail: `'${h}': the markdown dialect renders ${n} rule row(s) where the emitted DMN carries ${t.rules.length}`,
        });
    }
    // An oracle that compared nothing must say so. "No disagreement" and "no
    // comparison" look identical in a report and mean opposite things.
    out.push(
      compared
        ? `Where both projections produced a table for the same decision — ${compared} of them — their rule counts were compared, and a disagreement would be a finding in this document's own provenance section rather than a silent difference.`
        : absent(
            "Where both projections produce a table for the same decision, their shapes are cross-checked against each other.",
            "No decision has a table in both, so nothing was cross-checked here. That is a statement about coverage, not a clean result.",
          ),
      "",
    );
  }
  return out.join("\n");
}

function picturesSection() {
  const s = manifest.spine?.pictures;
  const intro =
    s && !("declined" in s) && s.intro
      ? narrativePart(s.intro, { slot: "pictures.intro" })
      : "";
  const sub = (heading, body) => `### ${heading}\n\n${body}\n`;
  return [
    intro,
    sub("Ladder diagrams — the shape of a decision", ladderSubsection()),
    sub("State machines — the shape of a duty", ltsSubsection()),
    sub("Processes — the duty as a workflow", bpmnSubsection()),
    sub("Decision tables — the rules as a grid", dmnSubsection()),
  ]
    .filter(Boolean)
    .join("\n");
}

// ----------------------------------------------------------------- S6, sweep
function sweepSection() {
  const r = byStage.get("p2-sweep");
  const head = manifest.spine?.sweep;
  const narrative =
    head && !("declined" in head) && head.file
      ? narrativePart(head.file, { slot: "sweep" }) + "\n\n"
      : "";
  if (r)
    return (
      narrative +
      [
        `**${r.status}**${r.reason ? ` — ${r.reason}` : ""}`,
        "",
        "Note what validating a register does not establish: whether the sweep behind it was **wide enough** is unfalsifiable by construction. A register that searched nothing validates exactly as cleanly as one that searched everything.",
      ].join("\n")
    );
  // Quoted, not softened. A lay-reader-friendly rewording of this paragraph
  // would be a different claim, and the difference would be invisible.
  return (
    narrative +
    absent(
      "This pipeline has a stage that searches for external modification — court decisions, agency interpretive guidance, rules in flight — and records what it searched, not only what it found.",
      "`p2-sweep` is not declared at this milestone. Nothing was searched, so nothing may be reported as searched, and this document makes no claim that the encoding is current with respect to courts, C&DIs, no-action letters, or rules in flight. (At `g2` the stage validates a deposited register — but note that validating a register is not performing a sweep: no procedure enumerates the searches that should have run.)",
    )
  );
}

// -------------------------------------------------------------------- S7, CTA
function ctaSection() {
  const s = manifest.spine?.call_to_action;
  const narrative =
    s && !("declined" in s) && s.file
      ? narrativePart(s.file, { slot: "call_to_action" })
      : absent(
          "This document ends with directions for using the encoding yourself.",
          "The subject's manifest declares no call-to-action narrative.",
        );
  const r = byStage.get("p7-mcp");
  // COUNTS, LABELLED AS COUNTS — and now the NAMES, because a count is not a
  // list. This block has been wrong twice. It first read
  // `Tools the deployment reported: \`10\``, which used the service's TOTAL
  // where the leg's own reason says the module contributed 6 and the other 4
  // are jl4-service's generic file-browsing tools. It then printed both counts
  // and said the names lived only in a log — true at the time, and it left the
  // narrative free to enumerate the tools by hand, which it did, and got the
  // number wrong. `p7-mcp.sh` now records `tool_names` on the receipt, so the
  // list is a run fact like every other number here and the prose enumerates
  // nothing.
  const names = String(r?.metrics?.tool_names ?? "")
    .split(/[,\s]+/)
    .filter(Boolean);
  const both =
    r && r.metrics?.tools && r.metrics?.corpus_tools
      ? `\nThe service enumerated \`${esc(r.metrics.tools)}\` tools for this deployment, of which \`${esc(r.metrics.corpus_tools)}\` are the module's own exported entry points and the rest are jl4-service's generic file-browsing tools, which say nothing about this corpus.` +
        (names.length
          ? ` The module's tools, as the service named them: ${names.map((n) => `\`${esc(n)}\``).join(", ")}.`
          : ` This run's receipt carries no \`tool_names\` metric, so the names are only in the leg's own log artifact and are not repeated here.`)
      : "";
  const measured = r
    ? ["", legLine("The deployment leg of this run", r), both].join("\n")
    : [
        "",
        absent(
          "Where a deployment was reached, the counts below are the ones the service reported.",
          "No deployment was reached in this run, so nothing is reported about one. Deploying to a host other people can reach is outward-facing and is gated; this document therefore describes how to run it on your own machine and claims nothing about any hosted service.",
        ),
      ].join("\n");
  return narrative + "\n" + measured;
}

// ------------------------------------------------------------ S8, provenance
function provenanceSection() {
  const rows = sectionStates.map(
    (s) =>
      // The source column carries the FULL repo-relative path, not the
      // basename. Basenames rendered `README.md, README.md` for a section
      // drafted from two different READMEs — MEASURED on run
      // 2026-08-03-3f45e62b-003, where four sections cite two READMEs each and
      // one cites three files whose basenames collide. A provenance table whose
      // reader cannot tell which file is meant is not a provenance table.
      `| \`${s.slot}\` | \`${s.file}\` | ${s.state === "reviewed" ? "reviewed" : `**${s.state}**`} | ${s.state === "reviewed" ? `\`${s.reviewer ?? "(unrecorded)"}\`` : "—"} | \`${s.drafted_by ?? "—"}\` | ${s.drafted_on ?? "—"} | ${s.citations} (${s.unchecked} unchecked) | ${s.sources.map((p) => `\`${esc(p)}\``).join(", ") || "—"} |`,
  );
  const findingRows = findings.map(
    (f) => `| \`${f.kind}\` | \`${esc(f.file)}\` | ${esc(f.detail)} |`,
  );
  // MEASURED COVERAGE, not a slogan. This paragraph used to open "Every claim
  // in this document is either a run fact resolved from the journal, or a
  // citation …", and the table three lines below it refuted that on run
  // 2026-08-03-3f45e62b-004: five sections carried `0 (0 unchecked)`, two of
  // them whole sections of law. A document that publishes its own coverage
  // table must not print a summary the table contradicts, so the summary is
  // computed FROM the table.
  const uncited = sectionStates.filter((s) => s.citations === 0);
  const coverage =
    `Every **run fact** in this document — every count, status, verdict and figure read out of an artifact — resolves from a row of this run's journal; none is typed into the template, and the renderer refuses to start if one is. ` +
    `Every **figure about the law or the encoding** that carries a citation had its source line re-opened and matched while this page was rendering: ${citationsTotal} citation(s), ${citationsUnchecked} of them exempted from the digit check with a stated reason, ${citationsUnresolved} that did not resolve.` +
    (uncited.length
      ? ` **${uncited.length} of the ${sectionStates.length} narrative sections carry no citation at all** — ${uncited.map((s) => `\`${s.slot}\``).join(", ")} — so nothing mechanical stands behind their prose, and the review that would is the one this repository cannot yet perform. They are listed here rather than left for a reader to derive from the table.`
      : ` Every narrative section carries at least one citation.`) +
    " This section is where a sceptic starts.";
  return [
    coverage,
    "",
    "### Every narrative section, and what backs it",
    "",
    "| slot | file | review | reviewer | drafted by | drafted on | citations | drafted from |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ...(rows.length ? rows : ["| (none) | | | | | | | |"]),
    "",
    "### What this run found about the deposit",
    "",
    ...(findingRows.length
      ? ["| kind | file | detail |", "| --- | --- | --- |", ...findingRows]
      : ["Nothing: no drift, no lint complaint, no unresolved citation."]),
    "",
    "### What the checks do and do not establish",
    "",
    "- **A citation check bounds transcription error. It does not bound misreading.** A figure appearing at the cited line does not prove the sentence around it is true.",
    "- **A dated figure does not digit-match.** A date citation is checked verbatim against a quoted fragment, or marked unchecked with a reason. The unchecked count above is the size of that exclusion, printed because an exclusion nobody can size is an exclusion nobody believes.",
    "- **The `anchor` field in a provenance record is documentation, not a check.** Line ranges move; the digest is the check, and the anchor tells a human reviewer where to look.",
    "- **A review is per section and per source digest.** It goes stale automatically when the text or a cited source moves, and a stale review renders as a draft.",
    "",
    "### Which copy of this document has a hash, and which one you are reading",
    "",
    "`p9-explain` renders a PRELIMINARY copy into this run's `artifacts/` directory and records its sha256 on its own receipt. That copy is taken inside the stage, before the stage's own `stage_end` and before `run_end`, so it is a few journal rows short of this one and its verdict row says so in as many words. The copy at the run's top level — the one you are almost certainly reading — is rendered after `run_end` and is **derived, not attested**: no receipt hashes it. That is deliberate and it is the weaker-sounding of two guarantees that only look alike. A hash says *these bytes are the ones the stage wrote*. Re-derivation says *these bytes are what the journal, the narrative and the artifacts produce*, which is the claim worth having, and the command below is how you take it rather than being given it.",
    "",
    "### Re-derive this document without trusting it",
    "",
    "```",
    `node etc/go/report/render-explainer.mjs ${resolve(rundir)} --format md,html`,
    `etc/go/go.sh verify --run-id ${begin.run_id} --gates`,
    "```",
    "",
    "The first re-renders this page — both carriers — from the journal, the narrative and the artifacts; the second re-reads the journal, re-hashes every artifact a receipt names, and recomputes the milestone verdict. Neither runs a build, calls a model, or makes a network request.",
  ].join("\n");
}

// ------------------------------------------------------------------- assemble
const orientation = slotBlock("orientation", { slot: "orientation" });
const body = bodySection();
const pictures = picturesSection();
const time = slotBlock("time", {
  slot: "time",
  heading: "#### In the encoding",
});
// No `#### In the encoding` heading here: the Limits slot is ABOUT the
// encoding end to end, so a sub-heading separating it from a law thread that
// does not exist would announce a division the section does not have.
const limits = slotBlock("limits", { slot: "limits" });
const sweep = sweepSection();
const cta = ctaSection();
const provenance = provenanceSection();

const draftCount = sectionStates.filter((s) => s.state !== "reviewed").length;
// THE BANNER STATES THE GAP THAT EXISTS, NOT THE ONE THAT WOULD BE TIDIER.
//
// It used to say review "is a detached signature over the section's text and
// the digests of the sources it was drafted from; today this repository has no
// enrolled signer" — present tense, describing a mechanism that is not built.
// MEASURED: `grep -rn 'l4-go-narrative\|narrative-verify' etc/go/` matches
// nothing. `driftFor` reads `record.review.state`, which is a plain JSON string,
// so a hand-written `"state": "reviewed"` with matching digests renders as
// reviewed, with a named reviewer, behind no banner and past no check. The
// missing piece is a VERIFIER, not a key. That is the sentence a reader needs,
// because it tells them what a future `reviewed` row would and would not be
// worth.
const REVIEW_MECHANISM =
  "What `reviewed` would mean here is not yet decided by any code: `provenance.json` carries a `review` field, this renderer re-checks that the text and the cited sources still hash as that field recorded them, and it goes stale automatically when either moves — but **nothing verifies a signature over a narrative section**, because no such verifier is built (the gate signatures under `etc/go/gate-verify.sh` are a different mechanism, over a different payload). Until one is, a `reviewed` row would be believed rather than checked. No row in this deposit claims to be reviewed, so the document is honest today by having nothing to be wrong about.";
const banner = draftCount
  ? `> **${draftCount} of ${sectionStates.length} narrative sections in this document are AGENT-DRAFTED AND NOT REVIEWED.** They are marked individually below. A drafted section is a claim, not a finding.\n>\n> ${REVIEW_MECHANISM}`
  : `> Every narrative section in this document records a review over its text and its sources.\n>\n> ${REVIEW_MECHANISM}`;

// JOURNAL-DERIVED, not disk-derived. Testing `existsSync(rundir/report.md)`
// made this row disagree between the two renders of the same run: inside
// `p9-explain` the report exists only under `artifacts/`, so the attested copy
// said "not present in this run directory" while the derived copy carried a
// link. Whether `p9-report` ran is a fact about the run and belongs on the
// journal; whether a file has been copied yet is a fact about the clock.
const p9r = byStage.get("p9-report");
const reportPointer = p9r
  ? `[\`report.md\`](report.md) — the audit account of this same run; \`p9-report\` reported **${p9r.status}**`
  : declared.includes("p9-report")
    ? "`report.md` — `p9-report` is declared at this milestone and left no receipt, so no audit report is accounted for"
    : "`report.md` — `p9-report` is not declared for this run, so there is no audit account to link to";

const values = {
  "explainer.title": manifest.title,
  "run.id": begin.run_id ?? "(none)",
  "run.milestone_upper": (begin.milestone ?? "?").toUpperCase(),
  "run.subject": begin.subject ?? "(none)",
  "run.subject_display": desc.display_name,
  "run.citation": desc.citation,
  "run.repo_head": begin.repo_head ?? "(none)",
  "run.tree_state": begin.tree_state ?? "(unknown)",
  "run.fixed_now": begin.fixed_now ?? "(unpinned)",
  "run.journal_path": journalPath,
  "run.record_count": String(records.length),
  "run.chain_state": chain.ok
    ? "verifies"
    : `**DOES NOT VERIFY** — ${chain.problems.join("; ")}`,
  "run.verdict": verdict,
  "gates.summary": gatesSummary,
  "report.pointer": reportPointer,
  "narrative.banner": banner,
  "narrative.draft_count": String(draftCount),
  "narrative.section_count": String(sectionStates.length),
  "citations.total": String(citationsTotal),
  "citations.unchecked": String(citationsUnchecked),
  "citations.unresolved": String(citationsUnresolved),
  "sections.orientation": orientation,
  "sections.body": body,
  "sections.pictures": pictures,
  "sections.time": time,
  "sections.limits": limits,
  "sections.sweep": sweep,
  "sections.cta": cta,
  "sections.provenance": provenance,
  "footer.generated": `*Generated by \`etc/go/report/render-explainer.mjs\` from \`${journalPath}\`, the narrative at \`${explainerDir.startsWith(REPO) ? explainerDir.slice(REPO.length + 1) : explainerDir}\`, and the artifacts this run's receipts attest. No figure in it was typed into a template.*`,
};

let md = template.replace(/<!--[\s\S]*?-->\n?/, "");
// Narrative blocks may themselves carry placeholders, so substitution runs to a
// fixed point rather than once. An unknown key is still a hard error wherever
// it appears — including inside a narrative file, which is how §6.5's ban on
// frozen run claims stays enforceable.
for (let pass = 0; pass < 4 && /\{\{[^}]+\}\}/.test(md); pass++) {
  md = md.replace(/\{\{([^}]+)\}\}/g, (_, key) => {
    const k = key.trim();
    if (!(k in values)) {
      process.stderr.write(
        `render-explainer.mjs: UNRESOLVED PLACEHOLDER {{${k}}} — a claim with no journal row cannot be printed.\n`,
      );
      process.exit(4);
    }
    return values[k];
  });
}
const leftover = md.match(/\{\{[^}]*\}\}/g);
if (leftover) {
  process.stderr.write(
    `render-explainer.mjs: unresolved placeholders remain: ${leftover.join(", ")}\n`,
  );
  process.exit(4);
}

// ---------------------------------------------------------------- the carriers
const outDir = outIdx >= 0 ? resolve(args[outIdx + 1]) : resolve(rundir);
const written = [];

if (formats.includes("md")) {
  let text = md;
  for (const [k, v] of Object.entries(mdBlocks))
    text = text.split(rawToken(k)).join(v);
  text = text.replace(
    /⟦RAW:[^⟧]*⟧/g,
    "*(figure omitted from the markdown carrier)*",
  );
  const p = resolve(outDir, "explainer.md");
  writeFileSync(p, text);
  written.push(p);
}

if (formats.includes("html")) {
  const p = resolve(outDir, "explainer.html");
  const bodyHtml = mdToHtml(md, { raw: rawBlocks });
  writeFileSync(
    p,
    [
      `<!doctype html><meta charset="utf-8">`,
      `<meta name="viewport" content="width=device-width,initial-scale=1">`,
      `<title>${escapeAttr(manifest.title)}</title>`,
      `<style>${STYLE}</style>`,
      `<main>${bodyHtml}</main>`,
      "",
    ].join(""),
  );
  written.push(p);
}

const summary = {
  run_id: begin.run_id,
  subject: subjectId,
  verdict: end?.verdict ?? null,
  sections: sectionStates.length,
  draft_sections: draftCount,
  citations_total: citationsTotal,
  citations_unchecked: citationsUnchecked,
  citations_unresolved: citationsUnresolved,
  findings,
  written,
};
writeFileSync(
  resolve(outDir, "explainer.summary.json"),
  JSON.stringify(summary, null, 2) + "\n",
);
written.push(resolve(outDir, "explainer.summary.json"));

for (const p of written) process.stdout.write(`render-explainer: wrote ${p}\n`);
process.stdout.write(
  `render-explainer: ${sectionStates.length} narrative section(s), ${draftCount} unreviewed; ` +
    `${citationsTotal} citation(s), ${citationsUnchecked} unchecked, ${citationsUnresolved} unresolved; ` +
    `${findings.length} finding(s)\n`,
);
process.exit(0);
