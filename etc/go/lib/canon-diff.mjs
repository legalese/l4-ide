#!/usr/bin/env node
// Canonicalise-then-diff: the differential oracle for the export legs.
//
// A bare byte-diff of `l4 export … --to dmn` against the committed golden is
// RED on day one, and the reason is a defect in the GOLDEN RUNNER, not in the
// exporter. Every canonicalisation below therefore carries a `because` naming
// the file:line that causes it and a `delete_when` naming the condition under
// which the entry must be removed. A canonicalisation with no `because` is a
// lie about how much the diff proved, so this module refuses to load one.
//
// Usage:  node etc/go/lib/canon-diff.mjs ACTUAL EXPECTED [--report FILE]
// Exit:   0 identical after declared canonicalisation
//         1 differs (the differing lines go to stdout)
//         2 usage / a file is missing
//         4 a canonicalisation entry is malformed (repo defect)

import { existsSync, readFileSync, writeFileSync } from "node:fs";

/**
 * MEASURED 2026-08-02 on this worktree (HEAD 162e5070):
 *   l4 export jl4/examples/legal/regcf/regcf.l4 --to dmn -o /tmp/x.dmn
 *   diff /tmp/x.dmn jl4/examples/dmn/expected/regcf-corpus.dmn | wc -l   →  92
 * every differing line is `(main.l4:L:C-C)` in the golden against
 * `(regcf.l4:L:C-C)` from the CLI, in @ref provenance text. After the D1
 * rewrite below the diff is EMPTY (verified).
 */
export const CANONICALISATIONS = [
  {
    id: "D1-golden-runner-source-uri",
    because:
      "jl4/tests/DmnExport.hs:3212 — `drgFlavoredWith = drgGeneral emptyVFS id` typechecks the golden with an EMPTY virtual file system, so no source URI reaches the @ref renderer and provenance renders the placeholder `main.l4`. The CLI has a real file path and renders `regcf.l4`. The exporter output is identical in every other byte.",
    delete_when:
      "the golden runner threads the real source path (a VFS seeded with the fixture, or drgAsCli's path plumbed into drgGeneral) and jl4/examples/dmn/expected/*.dmn are regenerated carrying real basenames. At that point this entry MUST be deleted; until then, this leg's diff does not prove the two files are byte-identical, only that they agree modulo the placeholder.",
    contradicts: [
      "jl4/examples/legal/regcf/PROJECTIONS.md — 'Every one of 1-3 reproduces byte for byte from the command line'",
      "jl4/tests/DmnExport.hs:3157 — 'Keeping this in step with L4.Cli.Export.exportDmn is what makes every DMN golden reproducible from the command line'",
    ],
    // Applied to the EXPECTED side only: we rewrite the golden's placeholder to
    // the basename the CLI would have used, never the other way round, so a
    // genuine CLI regression that emitted `main.l4` would still be caught.
    //
    // Anchored to `main.l4:<digit>`, i.e. the placeholder immediately followed
    // by a source position. That is narrow enough not to touch prose that
    // happens to mention main.l4, and wide enough to catch both renderings the
    // exporter uses — `(main.l4:1:1-2:3)` in @ref provenance and `at
    // main.l4:704:1-713:84` in a fidelity finding. An earlier version matched
    // only the parenthesised form and left one fidelity line differing, which
    // is precisely the half-applied canonicalisation this table exists to make
    // visible.
    side: "expected",
    apply: (text, { actualBasename }) =>
      text.replace(/\bmain\.l4:(?=\d)/g, `${actualBasename}:`),
  },
];

function validateTable() {
  const bad = [];
  for (const c of CANONICALISATIONS) {
    if (!c.id) bad.push("a canonicalisation has no id");
    if (!c.because || c.because.length < 40)
      bad.push(
        `${c.id}: 'because' must name the file:line that causes the difference`,
      );
    if (!c.delete_when)
      bad.push(
        `${c.id}: 'delete_when' must name the condition under which this entry is removed`,
      );
    if (!["expected", "actual", "both"].includes(c.side))
      bad.push(`${c.id}: 'side' must be expected|actual|both`);
    if (typeof c.apply !== "function")
      bad.push(`${c.id}: 'apply' is not a function`);
  }
  return bad;
}

export function canonDiff(actualPath, expectedPath, { actualBasename }) {
  let a = readFileSync(actualPath, "utf8");
  let e = readFileSync(expectedPath, "utf8");
  const applied = [];
  for (const c of CANONICALISATIONS) {
    const before = { a, e };
    if (c.side === "actual" || c.side === "both")
      a = c.apply(a, { actualBasename });
    if (c.side === "expected" || c.side === "both")
      e = c.apply(e, { actualBasename });
    if (a !== before.a || e !== before.e) applied.push(c.id);
  }
  if (a === e) return { identical: true, applied, diff: [] };

  const al = a.split("\n");
  const el = e.split("\n");
  const diff = [];
  const n = Math.max(al.length, el.length);
  for (let i = 0; i < n && diff.length < 400; i++) {
    if (al[i] !== el[i])
      diff.push({
        line: i + 1,
        actual: al[i] ?? "(eof)",
        expected: el[i] ?? "(eof)",
      });
  }
  return { identical: false, applied, diff };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const bad = validateTable();
  if (bad.length) {
    for (const b of bad)
      process.stderr.write(`canon-diff.mjs: BROKEN — ${b}\n`);
    process.exit(4);
  }
  const args = process.argv.slice(2);
  const reportIdx = args.indexOf("--report");
  const report = reportIdx >= 0 ? args[reportIdx + 1] : null;
  const files = args.filter(
    (a, i) => !a.startsWith("--") && !(reportIdx >= 0 && i === reportIdx + 1),
  );
  if (files.length !== 2) {
    process.stderr.write(
      "usage: canon-diff.mjs ACTUAL EXPECTED [--report FILE]\n",
    );
    process.exit(2);
  }
  const [actual, expected] = files;
  for (const f of [actual, expected]) {
    if (!existsSync(f)) {
      process.stderr.write(`canon-diff.mjs: missing ${f}\n`);
      process.exit(2);
    }
  }
  const actualBasename =
    actual
      .split("/")
      .pop()
      .replace(/\.(dmn|dmn\.md|md|bpmn|xml|txt)$/, "") + ".l4";
  // The basename the CLI stamps is the SOURCE file's, not the output's, so it
  // is passed in explicitly by the phase script when it differs.
  const basename = process.env.L4_GO_SOURCE_BASENAME || actualBasename;
  const res = canonDiff(actual, expected, { actualBasename: basename });

  const lines = [];
  lines.push(`canon-diff ${actual} vs ${expected}`);
  lines.push(
    `  canonicalisations applied: ${res.applied.length ? res.applied.join(", ") : "(none)"}`,
  );
  for (const c of CANONICALISATIONS.filter((c) => res.applied.includes(c.id))) {
    lines.push(`  [${c.id}] because: ${c.because}`);
    lines.push(`  [${c.id}] delete when: ${c.delete_when}`);
  }
  lines.push(
    res.identical
      ? "  VERDICT: identical after canonicalisation"
      : `  VERDICT: ${res.diff.length} differing line(s)`,
  );
  for (const d of res.diff.slice(0, 40)) {
    lines.push(`    ${d.line} actual   | ${d.actual}`);
    lines.push(`    ${d.line} expected | ${d.expected}`);
  }
  const text = lines.join("\n") + "\n";
  process.stdout.write(text);
  if (report) writeFileSync(report, text);
  process.exit(res.identical ? 0 : 1);
}
