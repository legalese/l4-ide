#!/usr/bin/env node
// Build the app's outcome tables BY RUNNING THE ENCODING.
//
// The app must not restate the law in JavaScript. So this script writes one
// `#EVAL` per question into a temporary L4 module, runs `l4 run --json` over
// it, and records what the ENCODING answered. Every number the app displays
// comes from here. Nothing in app/index.html computes an entitlement.
//
// One asymmetry is deliberate and is the reason the two tables below are built
// separately. The PACKAGE-side questions are total from a 2009 birth onward,
// because life.gov.sg's cohort table reaches that far. The COMPARISON against
// the outgoing schemes needs the Baby Bonus rate table, which this encoding
// holds only from 2015-01-01, and below that the encoding REFUSES — an ASSUME
// bottom that stops evaluation rather than quoting a rate nobody measured. So
// comparison `#EVAL`s are emitted only for the cohorts that have one, and the
// app renders a dash for the rest. Emitting them for every child and letting
// the run stall would lose the whole batch to one out-of-scope question.
//
// Usage: L4=/path/to/l4 node build-scenarios.mjs [--out outcomes.json]

import { execFileSync } from "node:child_process";
import { writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const CORPUS = join(HERE, "..");
const L4 = process.env.L4;
if (!L4) {
  console.error("build-scenarios: set L4 to a built l4 binary");
  process.exit(2);
}
const OUT = (() => {
  const i = process.argv.indexOf("--out");
  return i > 0 ? process.argv[i + 1] : join(HERE, "outcomes.json");
})();

// --- the axes ---------------------------------------------------------------
// A child per birth year from 2009 (the oldest cohort the Package reaches) to
// 2028 (the first full post-commencement cohort), at four birth orders: 1st,
// 2nd, 3rd and 5th. Those four are the outgoing scheme's own co-matching
// bands ($4,000 / $7,000 / $9,000 / $15,000), so the grid shows the cap change
// at every step it actually has.
const ORDERS = [1, 2, 3, 5];
const YEARS = [];
for (let y = 2009; y <= 2028; y++) YEARS.push(y);

// Mid-June births, so a child is unambiguously "turning n" in the year the
// scheme's calendar-year banding says they are.
const DOB = (y) => ({ y, m: 6, d: 15 });
const EARLIEST_COMPARISON = 2015; // see the header note

const CHILDREN = [];
for (const y of YEARS) for (const o of ORDERS) CHILDREN.push({ dob: DOB(y), order: o });

// Two cliff pairs the year grid cannot show, because they are a day apart.
const CLIFFS = [
  { dob: { y: 2023, m: 2, d: 13 }, order: 1, note: "the last day before the Budget 2023 Cash Gift enhancement" },
  { dob: { y: 2023, m: 2, d: 14 }, order: 1, note: "the first day of it" },
  { dob: { y: 2023, m: 2, d: 13 }, order: 3, note: "the same day, third child" },
  { dob: { y: 2023, m: 2, d: 14 }, order: 3, note: "the same day, third child" },
  { dob: { y: 2027, m: 3, d: 31 }, order: 1, note: "the last day before the Package commences" },
  { dob: { y: 2027, m: 4, d: 1 }, order: 1, note: "the first day of the Package" },
  { dob: { y: 2027, m: 3, d: 31 }, order: 3, note: "the same day, third child" },
  { dob: { y: 2027, m: 4, d: 1 }, order: 3, note: "the same day, third child" },
];
for (const c of CLIFFS) CHILDREN.push(c);

// The CDA co-matching window: how much headroom lapses on 30 September 2027,
// for a family that has already been co-matched some amount.
const WINDOWS = [];
for (const o of ORDERS) for (const got of [0, 3000, 5000, 8000, 12000])
  WINDOWS.push({ dob: DOB(2026), order: o, got });

// Childcare leave. Months served spans the Act's own graduation bands; the
// daily rates straddle the $500 reimbursement limit, which is where the
// employer's bill stops being covered.
const LEAVE = [];
for (const kids of [1, 2, 3])
  for (const months of [2, 3, 6, 8, 10, 12])
    for (const rate of [200, 400, 500, 600, 800, 1200])
      LEAVE.push({ kids, months, rate });

// --- generate ---------------------------------------------------------------
const ymd = (b) => `YMD ${b.y} ${b.m} ${b.d}`;
const childL4 = (c, i) => `
\`child ${i}\` MEANS Child WITH
    \`name\` IS "child ${i}"
    \`date of birth\` IS ${ymd(c.dob)}
    \`is a Singapore citizen\` IS TRUE
    \`birth order\` IS ${c.order}
    \`parents lawfully married\` IS TRUE`;

// Eight Package-side values per child, in a fixed order the reader below relies on.
const packageEvals = (i) => [
  `#EVAL \`settled lines for\` \`child ${i}\``,
  `#EVAL \`settled gift for\` \`child ${i}\``,
  `#EVAL \`Child Credits for\` \`child ${i}\``,
  `#EVAL \`the First Step Grant for\` \`child ${i}\``,
  `#EVAL \`settled cap for\` \`child ${i}\``,
  `#EVAL \`the PSEA top-up for\` \`child ${i}\``,
  `#EVAL \`Large Family MediSave Grant for\` \`child ${i}\``,
  `#EVAL \`Large Family LifeSG Credits paid to\` \`child ${i}\``,
].join("\n");
const PACKAGE_PER = 8;

// Three comparison values, emitted only for cohorts that have a rate table.
const comparisonEvals = (i) => [
  `#EVAL \`the change to the cash line for\` \`child ${i}\``,
  `#EVAL \`settled cap change for\` \`child ${i}\``,
  `#EVAL \`settled support change for\` \`child ${i}\``,
].join("\n");
const COMPARISON_PER = 3;

const windowL4 = (w, i) => `
\`window ${i}\` MEANS ChildFacts WITH
    \`date of birth\` IS ${ymd(w.dob)}
    \`is a Singapore citizen\` IS TRUE
    \`birth order\` IS ${w.order}
    \`co-matching already received\` IS ${w.got}

#EVAL (\`the co-matching window for\` \`window ${i}\`)'s \`the cap until 30 September 2027\`
#EVAL (\`the co-matching window for\` \`window ${i}\`)'s \`the cap from 1 October 2027\`
#EVAL (\`the co-matching window for\` \`window ${i}\`)'s \`headroom that lapses on that day\``;
const WINDOW_PER = 3;

const leaveL4 = (v, i) => `
\`leave ${i}\` MEANS LeaveFacts WITH
    \`children aged under seven\` IS ${v.kids}
    \`children aged seven to twelve\` IS 0
    \`months served this period\` IS ${v.months}
    \`gross daily rate\` IS ${v.rate}
    \`is the natural father\` IS FALSE

#EVAL (\`childcare leave under the rules effective on\` (YMD 2026 1 1) \`leave ${i}\`)'s \`days under the Act as it stands\`
#EVAL (\`childcare leave under the rules effective on\` (YMD 2027 4 1) \`leave ${i}\`)'s \`days under the announced scheme\`
#EVAL (\`childcare leave under the rules effective on\` (YMD 2026 1 1) \`leave ${i}\`)'s \`the employer's cost today\`
#EVAL (\`childcare leave under the rules effective on\` (YMD 2027 4 1) \`leave ${i}\`)'s \`the employer's cost as announced\``;
const LEAVE_PER = 4;

const comparable = CHILDREN.map((c) => c.dob.y >= EARLIEST_COMPARISON);

const module = `IMPORT prelude
IMPORT daydate
IMPORT \`sg-child-support-domain\`
IMPORT \`sg-csp\`
IMPORT \`sg-childcare-leave\`
IMPORT \`sg-child-support\`

§ \`scenario grid (generated by app/build-scenarios.mjs -- do not edit)\`

TIMEZONE IS "Asia/Singapore"

GIVETH A DATE
\`the settled Package\` MEANS YMD 2027 10 1

GIVEN child IS A Child
GIVETH A NUMBER
\`settled lines for\` child MEANS \`EVAL UNDER RULES EFFECTIVE AT\` \`the settled Package\` (\`the five Package lines for\` child)

GIVEN child IS A Child
GIVETH A NUMBER
\`settled gift for\` child MEANS \`EVAL UNDER RULES EFFECTIVE AT\` \`the settled Package\` (\`the cash actually paid as a Gift to\` child)

GIVEN child IS A Child
GIVETH A NUMBER
\`settled cap for\` child MEANS \`EVAL UNDER RULES EFFECTIVE AT\` \`the settled Package\` (\`the co-matching cap for\` child)

GIVEN child IS A Child
GIVETH A NUMBER
\`settled cap change for\` child MEANS \`EVAL UNDER RULES EFFECTIVE AT\` \`the settled Package\` (\`the change to the co-matching cap for\` child)

GIVEN child IS A Child
GIVETH A NUMBER
\`settled support change for\` child MEANS \`EVAL UNDER RULES EFFECTIVE AT\` \`the settled Package\` (\`the change to maximum support for\` child)

${CHILDREN.map(childL4).join("\n")}

§§ \`package lines\`
${CHILDREN.map((_, i) => packageEvals(i)).join("\n")}

§§ \`comparison against the outgoing schemes, where a rate table exists\`
${CHILDREN.map((_, i) => (comparable[i] ? comparisonEvals(i) : "")).filter(Boolean).join("\n")}

§§ \`co-matching windows\`
${WINDOWS.map(windowL4).join("\n")}

§§ \`childcare leave\`
${LEAVE.map(leaveL4).join("\n")}
`;

const modPath = join(CORPUS, ".scenarios-generated.l4");
writeFileSync(modPath, module);
let out;
try {
  out = execFileSync(L4, ["run", "--json", "--fixed-now=2026-08-25T00:00:00Z", modPath], {
    cwd: CORPUS, maxBuffer: 256 * 1024 * 1024, encoding: "utf8",
    env: { ...process.env, JL4_LIBRARY_PATH: process.env.JL4_LIBRARY_PATH || "" },
  });
} finally {
  rmSync(modPath, { force: true });
}

const values = JSON.parse(out).results.filter((r) => r.kind === "value").map((r) => r.value);
const nComparable = comparable.filter(Boolean).length;
const expected =
  CHILDREN.length * PACKAGE_PER +
  nComparable * COMPARISON_PER +
  WINDOWS.length * WINDOW_PER +
  LEAVE.length * LEAVE_PER;
if (values.length !== expected) {
  console.error(`build-scenarios: expected ${expected} values, got ${values.length}`);
  console.error("The encoding answered a different number of questions than were asked.");
  console.error("That is a real disagreement, not a formatting problem — do not paper over it.");
  process.exit(1);
}

const num = (v) => (typeof v === "number" ? v : Number(v));
let k = 0;
const children = CHILDREN.map((c) => {
  const [lines, gift, credits, fsg, cap, psea, lfmg, lflc] = values.slice(k, k + PACKAGE_PER).map(num);
  k += PACKAGE_PER;
  return { dob: c.dob, order: c.order, note: c.note || null,
           lines, gift, credits, fsg, cap, psea, lfmg, lflc, delta: null };
});
CHILDREN.forEach((_, i) => {
  if (!comparable[i]) return;
  const [cash, cap, total] = values.slice(k, k + COMPARISON_PER).map(num);
  k += COMPARISON_PER;
  children[i].delta = { cash, cap, total };
});
const windows = WINDOWS.map((w) => {
  const [before, after, lapsing] = values.slice(k, k + WINDOW_PER).map(num);
  k += WINDOW_PER;
  return { ...w, before, after, lapsing };
});
const leave = LEAVE.map((v) => {
  const [actDays, announcedDays, actCost, announcedCost] = values.slice(k, k + LEAVE_PER).map(num);
  k += LEAVE_PER;
  return { ...v, actDays, announcedDays, actCost, announcedCost };
});

const payload = {
  generated_by: "app/build-scenarios.mjs",
  encoding: "jl4/examples/legal/sg-child-support",
  rule_dates: { package_settled: "2027-10-01", act_today: "2026-01-01", announced_leave: "2027-04-01" },
  comparison_floor: `${EARLIEST_COMPARISON}-01-01`,
  counts: { children: children.length, windows: windows.length, leave: leave.length, values: values.length },
  children, windows, leave,
};
writeFileSync(OUT, JSON.stringify(payload, null, 2) + "\n");
console.log(`build-scenarios: ${values.length} values from the encoding -> ${OUT}`);
console.log(`  ${children.length} children, ${windows.length} co-matching windows, ${leave.length} leave scenarios`);
