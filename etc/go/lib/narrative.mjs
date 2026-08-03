// The checked-in narrative: its manifest, its provenance, its drift, and the
// lint that keeps a document full of numbers from becoming a second place where
// numbers are typed by hand.
//
// EXPLAINER-REPORT-SPEC.md §5 and §6 own the design; this file is its
// enforcement. Three ideas, in order of how much they matter:
//
//   1. CITATIONS (§6.2). A digit-run of two or more characters in a narrative
//      file must be inside a {{placeholder}} resolved from the journal, or
//      inside a citation whose SOURCE LINE IS RE-READ AND MATCHED at render
//      time, or inside one of the statutory-coordinate tokens allowlisted
//      below. "Do not type numbers" is not enforceable as a rule about
//      drafting. It is enforceable as a rule about re-reading the source.
//
//   2. PROVENANCE (§5.3-§5.4). Every narrative file declares the sources it was
//      drafted from, with their digests. Three independent drifts follow: the
//      narrative changed, a source changed, or a review no longer covers the
//      text it signed. Each renders its own banner and degrades the receipt.
//      Drift NEVER suppresses a section: a drifted section is still printed,
//      behind its banner, because suppression would let a drafter make an
//      inconvenient paragraph disappear by touching its source.
//
//   3. RESERVED VOCABULARY (§6.5). Narrative prose may not carry run-status
//      words except inside a placeholder. "All 70 assertions pass" is a run
//      claim frozen into prose: true the day it is drafted, false the first
//      time a test regresses, and confident either way.
//
// This module reads files and computes digests. It writes nothing, and it never
// calls ledger.append.

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { sha256File, sha256Text } from "./ledger.mjs";

/** Bumped when manifest.json's or provenance.json's shape changes. */
export const EXPLAINER_SCHEMA = 1;
export const NARRATIVE_SCHEMA = 1;

/**
 * Status vocabulary a narrative file may not use outside a placeholder. The
 * first eight are verdict.mjs's STATUSES, listed here as literals ON PURPOSE:
 * importing them would make this ban follow a rename silently, and the ban is
 * about the WORDS a reader sees, not about the lattice.
 */
export const RESERVED_STATUS_WORDS = [
  "PASS",
  "DEGRADED",
  "NOT-EXECUTABLE",
  "NOT-REGENERATED",
  "UNVERIFIED",
  "NOT-BUILT",
  "SKIPPED",
  "BROKEN",
  "COMPLETE",
  "INCOMPLETE",
];

/**
 * The subset checked in ANY CASE, rather than only as the uppercase literal.
 *
 * The ban was anchored to the uppercase spelling, so it caught `DEGRADED` and
 * missed `degraded` — and MEASURED on the shipped deposit, `limits.encoding.md`
 * carried "The pipeline's encoding check rides degraded on that count", which is
 * a run status frozen into prose, true only because one stage happened to be
 * DEGRADED on the run that drafted it, and invisible to the one check that
 * exists to catch exactly that.
 *
 * It is a SUBSET and not the whole list, because the cost of a lint is measured
 * in false positives: "pass", "broken" and "complete" are ordinary English and
 * occur in ordinary sentences ("one house rule broken and tolerated"), where
 * flagging them would train a drafter to work around the check rather than
 * obey it. The words below have no such ordinary use in this genre — a
 * narrative sentence containing "degraded" or "skipped" is nearly always a run
 * fact somebody typed. In their uppercase spelling ALL ten remain banned,
 * because uppercase is unambiguous.
 */
export const CASE_INSENSITIVE_STATUS_WORDS = [
  "DEGRADED",
  "NOT-EXECUTABLE",
  "NOT-REGENERATED",
  "UNVERIFIED",
  "NOT-BUILT",
  "SKIPPED",
  "INCOMPLETE",
];
export const RESERVED_STATUS_PHRASES = [
  "all tests pass",
  "all assertions pass",
  "fully verified",
];

/**
 * Digit-bearing tokens a narrative file may carry without a citation.
 *
 * Every one of these is a STATUTORY OR SPEC COORDINATE — an address, not a
 * measurement. `Rule 100(b)(5)` names a paragraph; `$124,000` states what that
 * paragraph says, and only the second can be wrong about the world. A token
 * that could be a measurement does not belong on this list.
 */
export const NARRATIVE_ALLOWED_DIGIT_TOKENS = [
  /\b17 CFR Part 227\b/g,
  /\b17 CFR 227\.\d+(?:\([a-z0-9]+\))*/g,
  /\b227\.\d+(?:\([a-z0-9]+\))*/g,
  /\bRules?\s+\d+[A-Za-z]?(?:\([a-z0-9A-Z]+\))*(?:\s*(?:,|and|–|-|through)\s*\d+[A-Za-z]?(?:\([a-z0-9A-Z]+\))*)*/g,
  /\b[Ss]ections?\s+\d+[A-Za-z]?(?:\([a-z0-9A-Z]+\))*/g,
  /\b\d+[A-Za-z]?(?:\([a-z0-9A-Z]+\))+/g,
  /\bForm C(?:-[A-Z]{1,2})?\b/g,
  /\bG[0-4]\b/g,
  /\bP(?:10|[1-9])\b/g,
  /\bR[0-7]\b/g,
  /\bE\d{1,2}\b/g,
  /\bHG[12]\b/g,
  /\bDMN 1\.3\b/g,
  /\bAKN 3\.0\b/g,
  /\bBPMN 2\.0\b/g,
  /§+ ?\d+(\.\d+)*/g,
  /\bv0\b/g,
];

/** [text](src:path#L12-L34 "mode") — the only way a figure may be written. */
export const CITATION_RE =
  /\[([^\]]+)\]\((src|art):([^)\s"#]+)(?:#L(\d+)(?:-L(\d+))?)?(?:\s+"([^"]*)")?\)/g;

// ------------------------------------------------------------------- loading

function fail(problems, message) {
  problems.push(message);
  return null;
}

/**
 * Read manifest.json. Returns { manifest, problems }. A problem here is a
 * SCHEMA violation — unparseable JSON, a missing file, a decline with no
 * reason — and the caller treats it as BROKEN, because it is a defect in the
 * deposit's shape rather than a finding about its content.
 */
export function loadManifest(dir) {
  const problems = [];
  const p = resolve(dir, "manifest.json");
  if (!existsSync(p))
    return { manifest: null, problems: [`no manifest.json at ${p}`] };
  let m;
  try {
    m = JSON.parse(readFileSync(p, "utf8"));
  } catch (e) {
    return {
      manifest: null,
      problems: [`${p} is not valid JSON: ${e.message}`],
    };
  }
  if (m.explainer_schema !== EXPLAINER_SCHEMA)
    fail(
      problems,
      `manifest.json: explainer_schema ${m.explainer_schema} != ${EXPLAINER_SCHEMA}`,
    );
  if (typeof m.title !== "string" || !m.title)
    fail(problems, "manifest.json: 'title' must be a non-empty string");
  const spine = m.spine ?? {};
  const named = [];
  const slot = (key, obj) => {
    if (!obj) return fail(problems, `manifest.json: spine.${key} is missing`);
    if ("declined" in obj) {
      // A decline must carry a reason for the same reason a gate waiver must:
      // a declination with no reason cannot be printed, and a slot that
      // vanishes silently is the failure the whole spine exists to prevent.
      if (typeof obj.declined !== "string" || !obj.declined)
        fail(
          problems,
          `manifest.json: spine.${key}.declined must be a non-empty reason string`,
        );
      return;
    }
    for (const part of ["file", "law", "encoding", "intro"]) {
      const v = obj[part];
      if (v === undefined || v === null) continue;
      if (typeof v !== "string" || !v)
        fail(problems, `manifest.json: spine.${key}.${part} must be a path`);
      else if (!existsSync(resolve(dir, v)))
        fail(
          problems,
          `manifest.json: spine.${key}.${part} names ${v}, which does not exist`,
        );
      else named.push(v);
    }
  };
  for (const key of [
    "orientation",
    "pictures",
    "time",
    "limits",
    "sweep",
    "call_to_action",
  ])
    slot(key, spine[key]);
  if (!Array.isArray(spine.body))
    fail(problems, "manifest.json: spine.body must be an array");
  else
    spine.body.forEach((entry, i) => {
      if (typeof entry?.id !== "string" || !entry.id)
        fail(problems, `manifest.json: spine.body[${i}].id is required`);
      if (typeof entry?.heading !== "string" || !entry.heading)
        fail(problems, `manifest.json: spine.body[${i}].heading is required`);
      slot(`body[${i}]`, entry);
    });
  return { manifest: m, problems, files: named };
}

/** Read provenance.json. Same contract as loadManifest. */
export function loadProvenance(dir) {
  const problems = [];
  const p = resolve(dir, "provenance.json");
  if (!existsSync(p))
    return { records: [], problems: [`no provenance.json at ${p}`] };
  let j;
  try {
    j = JSON.parse(readFileSync(p, "utf8"));
  } catch (e) {
    return { records: [], problems: [`${p} is not valid JSON: ${e.message}`] };
  }
  if (j.narrative_schema !== NARRATIVE_SCHEMA)
    fail(
      problems,
      `provenance.json: narrative_schema ${j.narrative_schema} != ${NARRATIVE_SCHEMA}`,
    );
  const records = Array.isArray(j.records) ? j.records : [];
  if (!Array.isArray(j.records))
    fail(problems, "provenance.json: 'records' must be an array");
  for (const r of records) {
    if (typeof r.file !== "string" || !r.file)
      fail(problems, "provenance.json: a record has no 'file'");
    // §5.3: drafted_from is the drift anchor, so it is mandatory and non-empty.
    // A narrative file with no declared source is not draftable — there is
    // nothing for a later run to compare against.
    if (!Array.isArray(r.drafted_from) || r.drafted_from.length === 0)
      fail(
        problems,
        `provenance.json: ${r.file} declares no drafted_from source; drift cannot be detected for it`,
      );
  }
  return { records, problems };
}

// --------------------------------------------------------------------- drift

/**
 * The three drift classes for one provenance record, computed by re-hashing.
 *
 * Returns { narrative, sources[], review, state }. `state` is the DERIVED
 * review state: `unreviewed | reviewed | stale`. `stale` is never written by a
 * human — it is what a recorded `reviewed` becomes when the text or a source
 * has moved underneath it.
 */
export function driftFor(record, { repoRoot, dir }) {
  const filePath = resolve(dir, record.file);
  const onDisk = existsSync(filePath) ? sha256File(filePath) : null;
  const narrative =
    onDisk === null
      ? { kind: "missing", recorded: record.sha256, now: null }
      : onDisk === record.sha256
        ? null
        : { kind: "changed", recorded: record.sha256, now: onDisk };

  const sources = [];
  for (const s of record.drafted_from ?? []) {
    const abs = resolve(repoRoot, s.path);
    const now = existsSync(abs) ? sha256File(abs) : null;
    if (now === null) sources.push({ ...s, kind: "missing", now: null });
    else if (now !== s.sha256) sources.push({ ...s, kind: "changed", now });
  }

  const rec = record.review ?? { state: "unreviewed" };
  let state = rec.state ?? "unreviewed";
  let review = null;
  if (state === "reviewed") {
    const textMoved = rec.reviewed_sha256 !== onDisk;
    const movedSources = (rec.reviewed_sources ?? []).filter((s) => {
      const abs = resolve(repoRoot, s.path);
      return !existsSync(abs) || sha256File(abs) !== s.sha256;
    });
    if (textMoved || movedSources.length) {
      state = "stale";
      review = { textMoved, movedSources };
    }
  }
  return { narrative, sources, review, state };
}

// ---------------------------------------------------------------------- lint

/**
 * Lint one narrative file against §6.2 and §6.5.
 *
 * Returns [{ line, code, message }]. Fenced code blocks are exempt from the
 * digit rule for the reason render-report.mjs exempts them from the template's:
 * a fenced block is a command to run, not a claim about the world.
 */
export function lintNarrative(text) {
  const out = [];
  const lines = String(text).split("\n");
  let inFence = false;
  lines.forEach((line, i) => {
    const n = i + 1;
    if (/^```/.test(line.trim())) {
      inFence = !inFence;
      return;
    }
    if (inFence) return;

    for (const w of RESERVED_STATUS_WORDS) {
      const anyCase = CASE_INSENSITIVE_STATUS_WORDS.includes(w);
      const re = new RegExp(
        `(^|[^A-Za-z0-9{-])${w}([^A-Za-z0-9}-]|$)`,
        anyCase ? "i" : "",
      );
      if (re.test(line))
        out.push({
          line: n,
          code: "N-STATUS",
          message: `reserved run-status word '${w}'${anyCase ? " (in any case)" : ""}; a run fact belongs in a placeholder resolved from the journal, never frozen into prose`,
        });
    }
    for (const p of RESERVED_STATUS_PHRASES) {
      if (line.toLowerCase().includes(p))
        out.push({
          line: n,
          code: "N-STATUS",
          message: `reserved phrase '${p}'; state the measured counts as placeholders instead`,
        });
    }

    // A citation-looking construct that does not parse is worse than none: it
    // reads as checked and is not. Every `](src:` / `](art:` in the line must
    // fall inside a span that the full grammar matched.
    const spans = [...line.matchAll(new RegExp(CITATION_RE.source, "g"))].map(
      (m) => [m.index, m.index + m[0].length],
    );
    for (const m of line.matchAll(/\]\((?:src|art):[^)]*\)?/g)) {
      const at = m.index;
      if (!spans.some(([s, e]) => at >= s && at < e))
        out.push({
          line: n,
          code: "N-CITE-SYNTAX",
          message: `citation does not parse: ${m[0].slice(0, 80)}`,
        });
    }

    let scrubbed = line
      .replace(new RegExp(CITATION_RE.source, "g"), "")
      .replace(/\{\{[^}]*\}\}/g, "");
    for (const re of NARRATIVE_ALLOWED_DIGIT_TOKENS)
      scrubbed = scrubbed.replace(new RegExp(re.source, re.flags), "");
    const stray = scrubbed.match(/\d{2,}/g);
    if (stray)
      out.push({
        line: n,
        code: "N-DIGIT",
        message: `uncited figure(s) ${[...new Set(stray)].join(", ")}; every number must be a placeholder resolved from the journal or a citation whose source line this renderer re-reads`,
      });
  });
  return out;
}

// ---------------------------------------------------------------- citations

const digitsOf = (s) => String(s).replace(/\D+/g, "");

/**
 * Normalise a window of source text for the digit check: drop the separators a
 * human writes inside a number, then take every maximal digit run. A target
 * matches when it is a substring of one run.
 *
 * KNOWN INCOMPLETENESS, recorded rather than hidden (§6.2). Dates do not
 * digit-match: `2016-05-16` normalises to one string and the corpus writes
 * `Date 16 5 2016`. A date citation must use "verbatim" or "unchecked:". This
 * checker catches the failure; it does not prevent the mistake.
 */
function digitRuns(window) {
  return window.replace(/(\d)[,_](?=\d)/g, "$1").match(/\d+/g) ?? [];
}

/**
 * Normalise a window, and a quotation, for the "verbatim" check.
 *
 * The check is about the WORDS, not about how the source file happened to wrap
 * them. A sentence in the corpus is usually a run of `--` comment lines, so a
 * quotation of it spans line breaks and comment markers that are not part of
 * the sentence. Leading comment markers are dropped and every whitespace run is
 * collapsed, on both sides, before comparing.
 *
 * WHAT THIS COSTS, said plainly: "verbatim" therefore means "these words, in
 * this order, in the cited window", not "these bytes". It does not detect a
 * requotation that changed the line breaks, and it is not meant to.
 */
const flatten = (s) =>
  String(s)
    .replace(/^[ \t]*--[ \t]?/gm, " ")
    .replace(/\s+/g, " ")
    .trim();

/**
 * Resolve every citation in `text`.
 *
 * `resolveSrc(path)` returns the absolute path of a repo file, or null.
 * `resolveArt(basename)` returns { path, ok, detail } for an artifact THIS RUN
 * attested, having already compared its recorded sha256 with the current one —
 * so an `art:` citation into a file that changed after its receipt is reported,
 * not silently believed.
 *
 * Returns { text, findings, total, unchecked }. The returned text has each
 * citation replaced by its rendered form; a citation that does not resolve
 * renders the figure followed by a visible complaint, because a figure that
 * silently loses its citation is the state this whole grammar exists to
 * prevent.
 */
export function resolveCitations(text, { resolveSrc, resolveArt }) {
  const findings = [];
  let total = 0;
  let unchecked = 0;
  const outText = String(text).replace(
    new RegExp(CITATION_RE.source, "g"),
    (_whole, label, scheme, target, from, to, title) => {
      total++;
      const mode = !title
        ? "digit"
        : title === "verbatim"
          ? "verbatim"
          : title.startsWith("unchecked:")
            ? "unchecked"
            : "bad-mode";
      const coord = `${target}${from ? `:${from}${to ? `-${to}` : ""}` : ""}`;
      const cite = (extra) =>
        `${label} \`⟨${coord}⟩\`${extra ? ` ${extra}` : ""}`;
      const complain = (code, detail) => {
        findings.push({ code, target: coord, detail });
        return cite(`**⚠ CITATION DOES NOT RESOLVE** — ${detail}`);
      };

      if (mode === "bad-mode")
        return complain(
          "C-MODE",
          `link title "${title}" is neither "verbatim" nor "unchecked: <reason>"`,
        );

      let abs = null;
      if (scheme === "src") {
        abs = resolveSrc(target);
        if (!abs) return complain("C-MISSING", `no file at \`${target}\``);
      } else {
        const a = resolveArt(target);
        if (!a)
          return complain(
            "C-ARTIFACT-UNKNOWN",
            `no receipt in this run names an artifact \`${target}\``,
          );
        if (a.ambiguous)
          return complain(
            "C-AMBIGUOUS",
            `more than one artifact in this run is named \`${target}\``,
          );
        if (!a.ok)
          return complain(
            "C-ARTIFACT-CHANGED",
            `\`${target}\` no longer hashes as its receipt recorded`,
          );
        abs = a.path;
      }

      if (mode === "unchecked") {
        unchecked++;
        return cite(`*(${title.replace(/^unchecked:\s*/, "unchecked — ")})*`);
      }

      const lines = readFileSync(abs, "utf8").split("\n");
      const a = from ? Number(from) : 1;
      const b = to ? Number(to) : from ? Number(from) : lines.length;
      if (a < 1 || b > lines.length || a > b)
        return complain(
          "C-RANGE",
          `lines ${a}-${b} are outside \`${target}\`, which has ${lines.length}`,
        );
      const window = lines.slice(a - 1, b).join("\n");

      if (mode === "verbatim") {
        if (!flatten(window).includes(flatten(label)))
          return complain(
            "C-NOMATCH",
            `the cited window does not contain the quoted words`,
          );
        return cite();
      }
      const want = digitsOf(label);
      if (!want)
        return complain(
          "C-NODIGITS",
          `the default check is a digit match and this citation's text has no digits; use "verbatim"`,
        );
      if (!digitRuns(window).some((run) => run.includes(want)))
        return complain(
          "C-NOMATCH",
          `the cited window contains no digit run containing ${want}`,
        );
      return cite();
    },
  );
  return { text: outText, findings, total, unchecked };
}

/** sha256 of a string, re-exported so callers need not import ledger twice. */
export { sha256Text };
