#!/usr/bin/env node
// Label-order lint over LABEL-ONLY inert strings in an .l4 module.
//
// WHAT IT IS FOR. Under the enumeration-label ruling (2026-08-03) an inert
// string that merely restates the active node beside it is deleted, and the
// statutory item label survives on the node's own line, joined by `...`:
//
//     ..  "(1)" ... transfer's `to the issuer of the securities`
//
// Once the labels are the only inert text left in a rule, they are a sequence,
// and a sequence can be checked. A rule whose labels read (1) (3) (2) is either
// mis-transcribed or is quoting the source out of order; either way a reader
// deserves to be told.
//
// WHY WARNING LEVEL, and why gaps are not even that. Meng's ruling, verbatim:
// "real legislation goes wobbly". A consolidated Act carries repealed limbs, so
// (a) (c) (d) is the NORMAL shape of live text, not a defect — gaps are counted
// and reported as information and nothing else. Out-of-ORDER is rarer and more
// suspicious, so it earns a warning line in the receipt notes. NEITHER moves the
// stage's status. A check that can turn a corpus red for quoting its own source
// faithfully would be worse than no check.
//
// THE AMBIGUITY THIS HAS TO SURVIVE. `(i)` is both the ninth letter and the
// roman numeral one, and legislation uses both schemes, sometimes in the same
// Act. Rather than guess, a run is read under EVERY scheme its tokens admit and
// is out of order only if NO reading orders it. That is the conservative
// direction for a warning: it under-reports rather than crying wolf.

const LABEL_RE = /^(?:\((?:[0-9]+[A-Za-z]*|[A-Za-z]+)\))+\.?$/;
const PART_RE = /\(([^()]+)\)/g;

// A label-only inert string is one whose ENTIRE content is enumerators. Anything
// carrying a rubric ("(b) Educational materials. (1)") or statutory prose is not
// a label for this purpose and is skipped rather than parsed — the corpus keeps
// such strings deliberately, and mis-parsing them would invent findings.
export const parseLabel = (text) => {
  const t = text.trim();
  if (!LABEL_RE.test(t)) return null;
  const parts = [...t.matchAll(PART_RE)].map((m) => m[1]);
  return parts.length ? parts : null;
};

const ROMAN = { i: 1, v: 5, x: 10, l: 50, c: 100, d: 500, m: 1000 };

// Strict-ish roman: value it the usual subtractive way, then require the
// canonical rendering to round-trip. That rejects "iiii" and "vx" without a
// table, and keeps "iv"/"ix"/"xl" working.
const romanValue = (s) => {
  if (!/^[ivxlcdm]+$/.test(s)) return null;
  let total = 0;
  for (let i = 0; i < s.length; i++) {
    const here = ROMAN[s[i]];
    const next = i + 1 < s.length ? ROMAN[s[i + 1]] : 0;
    total += here < next ? -here : here;
  }
  return romanOf(total) === s ? total : null;
};

const romanOf = (n) => {
  const table = [
    [1000, "m"],
    [900, "cm"],
    [500, "d"],
    [400, "cd"],
    [100, "c"],
    [90, "xc"],
    [50, "l"],
    [40, "xl"],
    [10, "x"],
    [9, "ix"],
    [5, "v"],
    [4, "iv"],
    [1, "i"],
  ];
  let out = "";
  let rest = n;
  for (const [v, s] of table) {
    while (rest >= v) {
      out += s;
      rest -= v;
    }
  }
  return out;
};

// Alphabetic, spreadsheet-column style: a=1 … z=26, aa=27. Case-insensitive,
// because (A)/(B) and (a)/(b) are both used and never mixed inside one run.
const alphaValue = (s) => {
  if (!/^[A-Za-z]+$/.test(s)) return null;
  let n = 0;
  for (const ch of s.toLowerCase()) n = n * 26 + (ch.charCodeAt(0) - 96);
  return n;
};

// Numeric with an optional inserted-provision suffix: 1 < 1A < 1B < 2. This is
// how UK and US drafters insert without renumbering, and treating "1A" as a
// fresh number would report every insertion as a gap.
const numericValue = (s) => {
  const m = /^([0-9]+)([A-Za-z]*)$/.exec(s);
  if (!m) return null;
  return { major: Number(m[1]), minor: alphaValue(m[2]) ?? 0 };
};

// The readings a single token admits, as {scheme, key} where key is comparable
// within a scheme. A token may admit several; the run picks.
const readings = (tok) => {
  const out = [];
  const num = numericValue(tok);
  if (num) out.push({ scheme: "numeric", key: [num.major, num.minor] });
  const rom = romanValue(tok.toLowerCase());
  if (rom !== null) out.push({ scheme: "roman", key: [rom, 0] });
  const alp = alphaValue(tok);
  if (alp !== null) out.push({ scheme: "alpha", key: [alp, 0] });
  return out;
};

const cmpKey = (a, b) => a[0] - b[0] || a[1] - b[1];

// Successor distance under a scheme, for the gap count. Only the major position
// counts: (1) then (1A) is an insertion, not a gap.
const gapBetween = (a, b) => Math.max(0, b[0] - a[0] - 1);

// Read a run of tokens under one scheme, if every token admits it.
const runUnder = (tokens, scheme) => {
  const keys = [];
  for (const tok of tokens) {
    const r = readings(tok).find((x) => x.scheme === scheme);
    if (!r) return null;
    keys.push(r.key);
  }
  return keys;
};

const SCHEMES = ["numeric", "roman", "alpha"];

// Score one run of sibling labels. Returns the best reading: ordered if any
// scheme orders it, and the gap count from that same scheme.
export const scoreRun = (tokens) => {
  let best = null;
  for (const scheme of SCHEMES) {
    const keys = runUnder(tokens, scheme);
    if (!keys) continue;
    let ordered = true;
    let gaps = 0;
    for (let i = 1; i < keys.length; i++) {
      if (cmpKey(keys[i - 1], keys[i]) >= 0) ordered = false;
      gaps += gapBetween(keys[i - 1], keys[i]);
    }
    const cand = { scheme, ordered, gaps };
    // Prefer an ordered reading; among ordered readings prefer the one that
    // needs the fewest gaps to explain the run.
    if (
      !best ||
      (cand.ordered && !best.ordered) ||
      (cand.ordered === best.ordered && cand.gaps < best.gaps)
    ) {
      best = cand;
    }
  }
  return best ?? { scheme: null, ordered: true, gaps: 0 };
};

// A RULE, for this lint, is a maximal contiguous run of non-blank lines — the
// same notion p3-check.sh's temporal-closure check already uses for "the
// declaration's own block". A fixed n-line window gets this wrong in both
// directions; blank-line separation is what the corpora actually observe.
const blocksOf = (lines) => {
  const out = [];
  let cur = null;
  lines.forEach((line, i) => {
    if (line.trim() === "") {
      cur = null;
      return;
    }
    if (!cur) {
      cur = { from: i, lines: [] };
      out.push(cur);
    }
    cur.lines.push({ n: i + 1, text: line });
  });
  return out;
};

// Inert strings sit at the head of an operand: optionally behind `..`, `...`,
// `AND`, `OR`, `NOT`. A string anywhere else on the line is an argument or a
// CONCAT fragment and is not a label.
const INERT_RE = /^\s*(?:(?:\.\.\.|\.\.|AND|OR|NOT)\s+)*"((?:[^"\\]|\\.)*)"/;

// Group consecutive labels that are siblings: same arity, same prefix. `(b)(1)`
// followed by `(b)(2)` is a run; `(b)(1)` followed by `(c)(1)` starts a new one.
const sibling = (a, b) =>
  a.length === b.length &&
  a.slice(0, -1).join("\u0000") === b.slice(0, -1).join("\u0000");

export const scanText = (text, path = "<text>") => {
  const warnings = [];
  let labels = 0;
  let gaps = 0;
  for (const block of blocksOf(text.split("\n"))) {
    const found = [];
    for (const { n, text: line } of block.lines) {
      if (/^\s*--/.test(line)) continue; // prose
      const m = INERT_RE.exec(line);
      if (!m) continue;
      const parts = parseLabel(m[1]);
      if (parts) found.push({ n, raw: m[1], parts });
    }
    labels += found.length;
    let i = 0;
    while (i < found.length) {
      let j = i + 1;
      while (j < found.length && sibling(found[j - 1].parts, found[j].parts))
        j++;
      if (j - i >= 2) {
        const run = found.slice(i, j);
        const s = scoreRun(run.map((x) => x.parts[x.parts.length - 1]));
        gaps += s.gaps;
        if (!s.ordered) {
          warnings.push(
            `${path.split("/").pop()}:${run[0].n}: labels out of order — ` +
              run.map((x) => `"${x.raw}"`).join(" ") +
              (s.scheme ? ` (read as ${s.scheme})` : ""),
          );
        }
      }
      i = j;
    }
  }
  return { labels, warnings, gaps };
};

export const scanFiles = (paths, readFile) => {
  const all = { labels: 0, warnings: [], gaps: 0 };
  for (const p of paths) {
    const r = scanText(readFile(p), p);
    all.labels += r.labels;
    all.gaps += r.gaps;
    all.warnings.push(...r.warnings);
  }
  return all;
};

// CLI: `node etc/label-order.mjs FILE…` prints `labels gaps warnings` on the
// first line and one warning per line after it, and always exits 0. The go
// pipeline's p3-check.sh (legalese/l4-pipeline) reads exactly that, so change
// the format there in the same breath. Its tests are that repository's
// selftest.mjs, "label-order checks".
if (
  process.argv[1] &&
  import.meta.url.endsWith(process.argv[1].split("/").pop())
) {
  const { readFileSync } = await import("node:fs");
  const r = scanFiles(process.argv.slice(2), (p) => readFileSync(p, "utf8"));
  process.stdout.write(`${r.labels} ${r.gaps} ${r.warnings.length}\n`);
  for (const w of r.warnings) process.stdout.write(`${w}\n`);
}
