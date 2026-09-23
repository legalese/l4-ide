#!/usr/bin/env node
// Build the app's outcome table BY RUNNING THE ENCODING.
//
// The app must not restate the law in JavaScript. So this script writes one
// `#EVAL` per scenario into a temporary L4 module, runs `l4 run --json` over
// it, and records what the ENCODING answered. Every number the app displays
// comes from here; nothing in the app computes a share.
//
// Exact fractions: L4 numbers are exact rationals, but the printer renders a
// non-integer through Double, so a one-third share arrives as
// 0.3333333333333333 (jl4-core/src/L4/Utils/Ratio.hs). We recover the exact
// fraction by bounded continued-fraction expansion and then CHECK it: the
// recovered fractions must sum to exactly 1. If any scenario fails that check
// it is reported and the decimal is kept, so a recovery that silently went
// wrong cannot reach the app as a confident fraction.
//
// Usage: node build-scenarios.mjs [--out outcomes.json]

import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const CORPUS = join(HERE, "..");
const L4 = process.env.L4;
if (!L4) {
  console.error("build-scenarios: set L4 to a built l4 binary");
  process.exit(2);
}

// ---------------------------------------------------------------------------
// The scenarios. Each names the facts a user would actually be asked for, in
// the axes the tool offers: a house or not, a spouse or not, children or not.
// `family` fields are lists of [name, survived, [issue...]].
// ---------------------------------------------------------------------------
const P = (name) => ({ name, survived: true, issue: [] });
const GONE = (name, issue) => ({ name, survived: false, issue });

const HOUSE = { immovable: 900000, movable: 100000 };
const NOHOUSE = { immovable: 0, movable: 250000 };

const SCENARIOS = [
  { id: "spouse-only-house", label: "Spouse, no children — with a flat",
    story: "Married, no children, both parents gone. The HDB flat and the savings.",
    estate: HOUSE, spouses: [P("Spouse")] },
  { id: "spouse-only-nohouse", label: "Spouse, no children — no property",
    story: "Married, no children, no parents surviving. Savings only.",
    estate: NOHOUSE, spouses: [P("Spouse")] },
  { id: "spouse-two-kids-house", label: "Spouse and two children — with a flat",
    story: "The commonest shape: a surviving spouse and two adult children.",
    estate: HOUSE, spouses: [P("Spouse")], children: [P("Child A"), P("Child B")] },
  { id: "spouse-one-kid-house", label: "Spouse and one child — with a flat",
    estate: HOUSE, spouses: [P("Spouse")], children: [P("Child A")] },
  { id: "spouse-parents-house", label: "Spouse and parents, no children",
    story: "No children, but both parents survive. Rule 4, not rule 1 — the case a precedence bug in the encoding got wrong.",
    estate: HOUSE, spouses: [P("Spouse")], parents: [P("Mother"), P("Father")] },
  { id: "kids-only-house", label: "Two children, no spouse",
    story: "Widowed or unmarried, two surviving children.",
    estate: HOUSE, children: [P("Child A"), P("Child B")] },
  { id: "three-kids", label: "Three children, no spouse",
    story: "A third each — and three thirds are exactly the whole estate.",
    estate: HOUSE, children: [P("Child A"), P("Child B"), P("Child C")] },
  { id: "grandchildren-represent", label: "A child died first, leaving grandchildren",
    story: "One child survives; the other died before the parent, leaving two children of their own.",
    estate: HOUSE, children: [P("Child A"), GONE("Child B", [P("Grandchild 1"), P("Grandchild 2")])] },
  { id: "child-died-childless", label: "A child died first, leaving nobody",
    story: "An extinct line is not a share: the surviving child takes everything.",
    estate: HOUSE, children: [P("Child A"), GONE("Child B", [])] },
  { id: "parents-only", label: "Parents only",
    story: "No spouse, no children. Both parents survive.",
    estate: HOUSE, parents: [P("Mother"), P("Father")] },
  { id: "siblings-only", label: "Brothers and sisters only",
    story: "No spouse, no children, no parents.",
    estate: HOUSE, siblings: [P("Sister"), P("Brother")] },
  { id: "grandparents-only", label: "Grandparents only",
    estate: HOUSE, grandparents: [P("Grandmother"), P("Grandfather")] },
  { id: "uncles-aunts-only", label: "Uncles and aunts only",
    estate: HOUSE, unclesaunts: [P("Uncle"), P("Aunt")] },
  { id: "nobody", label: "No relatives at all",
    story: "Rule 9: the estate goes to the Government as bona vacantia.",
    estate: HOUSE },
  { id: "two-widows", label: "Two lawful widows and two children",
    story: "Section 8: the wives share between them the one share a single wife would have taken — it dilutes the wives, never the children.",
    estate: HOUSE, spouses: [P("First wife"), P("Second wife")], children: [P("Child A"), P("Child B")] },
  { id: "debts-eat-in", label: "Spouse and two children, with debts",
    story: "Section 5 distributes what is left AFTER the expenses of due administration. The shares are the same; the money is not.",
    estate: { immovable: 900000, movable: 100000, expenses: 30000, debts: 400000 },
    spouses: [P("Spouse")], children: [P("Child A"), P("Child B")] },
  { id: "foreign-domicile", label: "Lived abroad, owned a Singapore flat",
    story: "Section 4 splits the estate: the flat is governed by this Act, the bank account by the law of the domicile.",
    estate: HOUSE, domiciled: false, spouses: [P("Spouse")], children: [P("Child A")] },
  { id: "muslim-estate", label: "A Muslim estate",
    story: "Section 2 puts this outside the Act entirely. The tool refuses rather than answering.",
    estate: HOUSE, muslim: true, spouses: [P("Spouse")], children: [P("Child A")] },
];

// ---------------------------------------------------------------------------
// Emit L4
// ---------------------------------------------------------------------------
const q = (s) => `"${String(s).replace(/"/g, '\\"')}"`;
const person = (p) =>
  `(Person WITH \`name\` IS ${q(p.name)}, \`survived the deceased\` IS ${p.survived ? "TRUE" : "FALSE"}, \`issue\` IS ${plist(p.issue || [])})`;
const plist = (ps) => (ps.length === 0 ? "EMPTY" : `(LIST ${ps.map(person).join(", ")})`);

function scenarioL4(s, i) {
  const e = s.estate;
  return `
\`case ${i}\` MEANS
  Case WITH
      \`deceased\` IS (Deceased WITH \`name\` IS ${q(s.label)}
                              , \`date of death\` IS YMD 2026 1 15
                              , \`domiciled in Singapore\` IS ${s.domiciled === false ? "FALSE" : "TRUE"}
                              , \`Muslim\` IS ${s.muslim ? "TRUE" : "FALSE"})
    , \`family\` IS (Family WITH \`surviving spouses\` IS ${plist(s.spouses || [])}
                          , \`children\` IS ${plist(s.children || [])}
                          , \`parents\` IS ${plist(s.parents || [])}
                          , \`siblings\` IS ${plist(s.siblings || [])}
                          , \`grandparents\` IS ${plist(s.grandparents || [])}
                          , \`uncles and aunts\` IS ${plist(s.unclesaunts || [])})
    , \`estate\` IS (Estate WITH \`immovable property in Singapore\` IS ${e.immovable}
                          , \`movable property in Singapore\` IS ${e.movable}
                          , \`funeral, testamentary and administration expenses\` IS ${e.expenses || 0}
                          , \`debts and liabilities\` IS ${e.debts || 0})
    , \`will\` IS NOTHING

#EVAL (\`the intestate distribution for\` \`case ${i}\`)'s \`governed by this Act\`
#EVAL (\`the intestate distribution for\` \`case ${i}\`)'s \`shares\`
#EVAL (\`the intestate distribution for\` \`case ${i}\`)'s \`note\`
#EVAL \`the property this Act distributes in\` \`case ${i}\`
#EVAL \`distributable estate of\` \`case ${i}\`
#EVAL \`what happens next in\` \`case ${i}\`
#EVAL \`the Act governing the distribution in\` \`case ${i}\`
#EVAL \`the ordinary timeline for\` \`case ${i}\`
`;
}

const module = `IMPORT prelude
IMPORT daydate
IMPORT \`sg-succession-domain\`
IMPORT \`sg-isa\`
IMPORT \`sg-succession\`

§ \`scenario grid (generated by app/build-scenarios.mjs -- do not edit)\`
${SCENARIOS.map(scenarioL4).join("\n")}`;

const tmp = mkdtempSync(join(tmpdir(), "sgscen-"));
const modPath = join(CORPUS, ".scenarios-generated.l4");
writeFileSync(modPath, module);

let out;
try {
  out = execFileSync(L4, ["run", "--json", modPath], {
    cwd: CORPUS, maxBuffer: 64 * 1024 * 1024, encoding: "utf8",
    env: { ...process.env, JL4_LIBRARY_PATH: process.env.JL4_LIBRARY_PATH || "" },
  });
} finally {
  rmSync(modPath, { force: true });
  rmSync(tmp, { recursive: true, force: true });
}

const results = JSON.parse(out).results.filter((r) => r.kind === "value").map((r) => r.value);
const PER = 8;
if (results.length !== SCENARIOS.length * PER) {
  console.error(`build-scenarios: expected ${SCENARIOS.length * PER} values, got ${results.length}`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Recover exact fractions, then CHECK them
// ---------------------------------------------------------------------------
function toFraction(x, maxDen = 10000) {
  // bounded continued fraction; returns [num, den] or null
  let h1 = 1, h0 = 0, k1 = 0, k0 = 1, b = x;
  for (let i = 0; i < 40; i++) {
    const a = Math.floor(b);
    let h2 = a * h1 + h0, k2 = a * k1 + k0;
    if (k2 > maxDen) break;
    [h0, h1, k0, k1] = [h1, h2, k1, k2];
    if (Math.abs(h1 / k1 - x) < 1e-12) return [h1, k1];
    const frac = b - a;
    if (frac < 1e-12) break;
    b = 1 / frac;
  }
  return Math.abs(h1 / k1 - x) < 1e-9 ? [h1, k1] : null;
}
const gcd = (a, b) => (b ? gcd(b, a % b) : a);

const TIMELINE_RE =
  /`Timeline event` OF \(DATE OF (\d+), (\d+), (\d+)\), ("(?:[^"\\]|\\.)*"), ("(?:[^"\\]|\\.)*")/g;
const SHARE_RE = /Share OF ("(?:[^"\\]|\\.)*"), (-?[0-9.eE+-]+), ("(?:[^"\\]|\\.)*")/g;
const unq = (s) => JSON.parse(s);

const problems = [];
const scenarios = SCENARIOS.map((s, i) => {
  const [governed, sharesRaw, note, reach, distributable, next, governingAct, timelineRaw] =
    results.slice(i * PER, i * PER + PER);
  const shares = [];
  for (const m of sharesRaw.matchAll(SHARE_RE)) {
    const dec = Number(m[2]);
    const fr = toFraction(dec);
    shares.push({ taker: unq(m[1]), decimal: dec, basis: unq(m[3]),
                  fraction: fr ? { n: fr[0] / gcd(fr[0], fr[1]), d: fr[1] / gcd(fr[0], fr[1]) } : null });
  }
  // the check: recovered fractions must sum to exactly 1 (or there are none)
  if (shares.length) {
    let n = 0, d = 1, exact = true;
    for (const sh of shares) {
      if (!sh.fraction) { exact = false; break; }
      n = n * sh.fraction.d + sh.fraction.n * d; d *= sh.fraction.d;
      const g = gcd(n, d); n /= g; d /= g;
    }
    if (!exact || n !== 1 || d !== 1) {
      problems.push(`${s.id}: recovered fractions sum to ${exact ? `${n}/${d}` : "an unrecoverable value"}, not 1`);
      shares.forEach((sh) => { sh.fraction = null; });
    }
  }
  return {
    id: s.id, label: s.label, story: s.story || null,
    facts: {
      house: (s.estate.immovable || 0) > 0, immovable: s.estate.immovable || 0,
      movable: s.estate.movable || 0, expenses: s.estate.expenses || 0, debts: s.estate.debts || 0,
      spouses: (s.spouses || []).length, children: (s.children || []).length,
      parents: (s.parents || []).length, siblings: (s.siblings || []).length,
      domiciled: s.domiciled !== false, muslim: !!s.muslim,
    },
    governedByTheAct: governed === "TRUE",
    note: unq(note),
    distributes: Number(reach),
    distributableEstate: Number(distributable),
    shares,
    whatHappensNext: unq(next),
    governingAct: unq(governingAct),
    timeline: [...timelineRaw.matchAll(TIMELINE_RE)].map((m) => ({
      date: `${m[3]}-${String(m[2]).padStart(2, "0")}-${String(m[1]).padStart(2, "0")}`,
      event: unq(m[4]), basis: unq(m[5]),
    })),
  };
});

if (problems.length) {
  console.error("build-scenarios: EXACTNESS CHECK FAILED for:");
  for (const p of problems) console.error("  " + p);
  console.error("  (those scenarios keep their decimals; nothing is displayed as an exact fraction)");
}

const outPath = join(HERE, "outcomes.json");
writeFileSync(outPath, JSON.stringify({
  generated_by: "jl4/examples/legal/sg-succession/app/build-scenarios.mjs",
  provenance: "Every value below is what the L4 encoding answered; nothing here is computed in JavaScript.",
  exactness_failures: problems,
  scenarios,
}, null, 2) + "\n");
console.log(`build-scenarios: ${scenarios.length} scenarios -> ${outPath}`);
console.log(`  exact fractions recovered for ${scenarios.filter((s) => s.shares.every((x) => x.fraction)).length}/${scenarios.length}`);
