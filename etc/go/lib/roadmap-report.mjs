#!/usr/bin/env node
// Render an encoding roadmap as COMPLETION.md — the tabular summary of what a
// subject's encoding covers, what it deliberately does not, and what is still
// owed.
//
// WHY THIS EXISTS. P3's oracle is `l4 check` and nothing else, so a module that
// encodes Chapter 1 and stops typechecks exactly as well as one that encodes
// the whole Act. Under-coverage was the pipeline's one large defect with no
// detector: a run could report PASS across every stage over a fifth of a
// statute. `register-validate.mjs encoding-roadmap` makes coverage checkable;
// this makes it READABLE, which is the half that gets looked at.
//
// The layout is chosen for one failure in particular. Units are rendered in
// SOURCE ORDER, and the coverage strip prints one glyph per unit in that order,
// so "encoded the first four and stopped" is a shape you see before you read
// anything -- a solid run followed by a wall of dots. A sorted table, or a
// table grouped by disposition, would hide exactly that.
//
// Usage:
//   roadmap-report.mjs <roadmap.json> [--out COMPLETION.md]
//   roadmap-report.mjs --selftest
//
// Exit: 0 rendered · 1 the roadmap has deferred units (unfinished work, said
// out loud) · 2 usage or unreadable input.

import { readFileSync, writeFileSync } from "node:fs";

const GLYPH = {
  encoded: "#",
  inert: "+",
  "out-of-scope": "-",
  deferred: ".",
};

const LABEL = {
  encoded: "encoded",
  inert: "inert",
  "out-of-scope": "out of scope",
  deferred: "DEFERRED",
};

export function render(rm) {
  const units = rm.units;
  const n = units.length;
  const by = (d) => units.filter((u) => u.disposition === d);
  const counts = Object.fromEntries(
    Object.keys(GLYPH).map((d) => [d, by(d).length]),
  );
  const pct = (k) => (n === 0 ? "0.0" : ((k / n) * 100).toFixed(1));

  // "Accounted for" is deliberately NOT "encoded". A unit ruled out of scope
  // with a reason is a decision that was made and can be reviewed; a deferred
  // unit is work nobody has done. Collapsing the two would let a roadmap reach
  // 100% by deferring everything, which is the exact self-deception this
  // artifact exists to prevent.
  const accounted = counts.encoded + counts.inert + counts["out-of-scope"];

  const out = [];
  out.push(`# Coverage — ${rm.subject} / ${rm.encoding}`);
  out.push("");
  out.push(
    `Generated from the encoding roadmap. Do not edit by hand: edit the roadmap and re-render.`,
  );
  out.push("");
  out.push(
    `**Source.** \`${rm.source.document_id}\`, enumerated at ${rm.granularity} level.`,
  );
  out.push(`**Basis.** ${rm.source.enumeration_basis}`);
  if (rm.source.enumeration_complete === false) {
    out.push("");
    out.push(
      `> **The enumeration itself is incomplete.** ${rm.source.enumeration_note}`,
    );
    out.push(
      `> Every figure below is a proportion of what was enumerated, not of the source.`,
    );
  }
  out.push("");

  out.push("## Summary");
  out.push("");
  out.push("| disposition | units | share |");
  out.push("| --- | ---: | ---: |");
  for (const d of Object.keys(GLYPH))
    out.push(`| ${LABEL[d]} | ${counts[d]} | ${pct(counts[d])}% |`);
  out.push(`| **total enumerated** | **${n}** | |`);
  out.push("");
  out.push(
    `**Accounted for: ${accounted} of ${n} (${pct(accounted)}%)** — encoded, carried inert, or ruled out of scope with a reason.`,
  );
  if (counts.deferred > 0) {
    out.push("");
    out.push(
      `> **${counts.deferred} unit(s) deferred.** This encoding is not finished, and says so. Deferred units are listed below with the reason each was left.`,
    );
  }
  out.push("");

  out.push("## Coverage in source order");
  out.push("");
  out.push("```");
  // wrap at 60 so a long statute stays inside a readable column
  const strip = units.map((u) => GLYPH[u.disposition] ?? "?").join("");
  for (let i = 0; i < strip.length; i += 60) out.push(strip.slice(i, i + 60));
  out.push("```");
  out.push("");
  out.push(
    `\`#\` encoded · \`+\` inert · \`-\` out of scope · \`.\` deferred — one glyph per unit, in source order. A solid run that stops is what an abandoned encoding looks like.`,
  );
  out.push("");

  if (counts.deferred > 0) {
    out.push("## Deferred — what is still owed");
    out.push("");
    out.push("| unit | title | reason |");
    out.push("| --- | --- | --- |");
    for (const u of by("deferred"))
      out.push(`| \`${u.id}\` | ${esc(u.title)} | ${esc(u.reason ?? "")} |`);
    out.push("");
  }

  out.push("## Every unit");
  out.push("");
  out.push("| unit | title | disposition | where |");
  out.push("| --- | --- | --- | --- |");
  for (const u of units) {
    const where =
      (u.modules ?? []).map((m) => `\`${m}\``).join("<br>") ||
      esc(u.reason ?? "");
    out.push(
      `| \`${u.id}\` | ${esc(u.title)} | ${LABEL[u.disposition]} | ${where} |`,
    );
  }
  out.push("");
  return out.join("\n");
}

// A pipe inside a cell silently ends the column and shifts every value right of
// it into the wrong header -- a corruption that still renders as a valid table.
function esc(s) {
  return String(s).replace(/\|/g, "\\|").replace(/\n/g, " ");
}

function selftest() {
  const cases = [];
  const mk = (units) => ({
    kind: "encoding-roadmap",
    roadmap_version: "1.0.0",
    subject: "t",
    encoding: "e",
    granularity: "section",
    source: {
      document_id: "d",
      enumeration_basis: "the arrangement of sections",
      enumeration_complete: true,
    },
    units,
  });
  const u = (id, disposition, extra = {}) => ({
    id,
    title: `s ${id}`,
    disposition,
    ...extra,
  });

  const abandoned = render(
    mk([
      u("1", "encoded", { modules: ["a.l4"] }),
      u("2", "encoded", { modules: ["a.l4"] }),
      u("3", "deferred", { reason: "ran out of session" }),
      u("4", "deferred", { reason: "ran out of session" }),
    ]),
  );
  cases.push(["abandoned run shows a cliff", abandoned.includes("##..")]);
  cases.push([
    "deferred units get their own section",
    abandoned.includes("## Deferred — what is still owed"),
  ]);
  cases.push([
    "deferred does not count as accounted for",
    abandoned.includes("**Accounted for: 2 of 4 (50.0%)**"),
  ]);
  cases.push([
    "unfinished encoding says so",
    abandoned.includes("is not finished, and says so"),
  ]);

  const done = render(
    mk([
      u("1", "encoded", { modules: ["a.l4"] }),
      u("2", "out-of-scope", { reason: "procedural machinery" }),
    ]),
  );
  cases.push(["complete run reaches 100%", done.includes("(100.0%)")]);
  cases.push([
    "no deferred section when nothing is deferred",
    !done.includes("## Deferred"),
  ]);

  const piped = render(
    mk([u("1", "encoded", { modules: ["a.l4"], title: undefined })]),
  );
  cases.push(["renders without throwing", typeof piped === "string"]);

  const esc1 = esc("a | b");
  cases.push(["a pipe in a cell is escaped", esc1 === "a \\| b"]);

  let bad = 0;
  for (const [name, ok] of cases) {
    if (!ok) bad++;
    process.stdout.write(`  ${ok ? "ok  " : "FAIL"} ${name}\n`);
  }
  process.stdout.write(
    `roadmap-report selftest: ${cases.length - bad}/${cases.length} passed\n`,
  );
  return bad === 0 ? 0 : 1;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const argv = process.argv.slice(2);
  if (argv[0] === "--selftest") process.exit(selftest());
  if (argv.length === 0 || argv[0].startsWith("--")) {
    process.stderr.write(
      "usage: roadmap-report.mjs <roadmap.json> [--out COMPLETION.md]\n" +
        "       roadmap-report.mjs --selftest\n",
    );
    process.exit(2);
  }
  let rm;
  try {
    rm = JSON.parse(readFileSync(argv[0], "utf8"));
  } catch (e) {
    process.stderr.write(
      `roadmap-report: cannot read ${argv[0]}: ${e.message}\n`,
    );
    process.exit(2);
  }
  const text = render(rm);
  const oi = argv.indexOf("--out");
  if (oi !== -1 && argv[oi + 1]) writeFileSync(argv[oi + 1], text + "\n");
  else process.stdout.write(text + "\n");
  const deferred = rm.units.filter((u) => u.disposition === "deferred").length;
  process.exit(deferred > 0 ? 1 : 0);
}
