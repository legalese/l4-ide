#!/usr/bin/env node
/**
 * Guards FOUNDATION.md R4: each guided fact vocabulary must be a MECHANICAL
 * transliteration of its one source schema. If they drift, the guided cells
 * measure whichever schema disambiguated better rather than the languages, and
 * the comparison is void. Run this whenever any schema file changes.
 *
 * Two triples are checked: the as-published arm (schema.md + schema-prolog.md +
 * schema-l4.md) and the restored arm (schema-restored*.md), same rules.
 *
 * Transliteration rules, enforced here:
 *   neutral `foo_bar`  ->  Prolog `claim_foo_bar(C, Value)`
 *   neutral `foo_bar`  ->  L4 record field `foo bar`
 */
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), "utf8");
const problems = [];

/**
 * Comparing field NAMES is not enough, and this is not a hypothetical.
 *
 * The first schema-l4.md shipped to the l4-guided trials had all 18 fields, in
 * order, and did not compile: multi-word field names need backticks, and the
 * `arose out of` helper was written `` c `elem` cs `` when L4 has no
 * backtick-infix calling convention. The Prolog schema loaded fine. So the two
 * guided cells were NOT equivalently guided — the L4 encoders had to repair the
 * vocabulary before they could use it — and R4 was violated in the one place
 * the name comparison could not see. A schema that does not compile is not a
 * mechanical transliteration of anything.
 */
function compiles(blocks, ext, run) {
  const dir = mkdtempSync(join(tmpdir(), "schema-parity-"));
  const f = join(dir, `schema${ext}`);
  writeFileSync(f, blocks);
  try {
    const out = run(dir, f);
    return { ok: true, out };
  } catch (e) {
    return { ok: false, out: (e.stdout || "") + (e.stderr || e.message || "") };
  }
}

function checkTriple(label, srcFile, plFile, l4File) {
  // Source: numbered rows of the field table only.
  const source = [
    ...read(srcFile).matchAll(/^\|\s*(\d+)\s*\|\s*`([a-z0-9_]+)`\s*\|/gm),
  ].map((m) => m[2]);

  const prolog = [
    ...read(plFile).matchAll(/^claim_([a-z0-9_]+)\(C,\s*Value\)\./gm),
  ].map((m) => m[1]);

  // L4 fields live between HAS and the closing fence; spaces stand in for underscores.
  const l4Block =
    /DECLARE Claim\n([\s\S]*?)\n```/.exec(read(l4File))?.[1] ?? "";
  const l4 = [
    ...l4Block.matchAll(/^\s*(?:HAS\s+)?`([a-z][a-z ]*?)`\s+IS A /gm),
  ].map((m) => m[1].trim().replace(/ /g, "_"));

  const cmp = (name, got) => {
    const missing = source.filter((f) => !got.includes(f));
    const extra = got.filter((f) => !source.includes(f));
    if (missing.length)
      problems.push(`${label}/${name}: MISSING ${missing.join(", ")}`);
    if (extra.length)
      problems.push(`${label}/${name}: EXTRA ${extra.join(", ")}`);
    if (!missing.length && !extra.length && got.join("|") !== source.join("|"))
      problems.push(
        `${label}/${name}: same fields, DIFFERENT ORDER (source: ${source.join(", ")})`,
      );
  };
  cmp("prolog", prolog);
  cmp("l4", l4);

  const l4Src =
    "IMPORT prelude\n\n" +
    [...read(l4File).matchAll(/```l4\n([\s\S]*?)```/g)]
      .map((m) => m[1])
      .join("\n\n");
  const l4c = compiles(l4Src, ".l4", (dir, f) =>
    execFileSync("l4", ["check", f], {
      encoding: "utf8",
      env: {
        ...process.env,
        JL4_LIBRARY_PATH:
          process.env.JL4_LIBRARY_PATH ??
          resolve(here, "../../../jl4-core/libraries"),
      },
    }),
  );
  const l4ok = /Check succeeded/.test(l4c.out || "");
  if (!l4ok)
    problems.push(
      `${label}/l4: ${l4File} does NOT compile — ${(l4c.out || "").slice(0, 400)}`,
    );

  // Only the helper block is code; the claim-fact block documents what a query supplies.
  const plBlocks = [
    ...read(plFile).matchAll(/```prolog\n([\s\S]*?)```/g),
  ].map((m) => m[1]);
  const plc = compiles(plBlocks.at(-1), ".pl", (dir, f) =>
    execFileSync("swipl", ["-q", "-g", "halt", f], { encoding: "utf8" }),
  );
  const plok = plc.ok && !/Syntax error|Unknown procedure/i.test(plc.out || "");
  if (!plok)
    problems.push(
      `${label}/prolog: ${plFile} helpers do NOT load — ${(plc.out || "").slice(0, 400)}`,
    );

  console.log(
    `${label}: compiles l4 ${l4ok ? "yes" : "NO"} · prolog ${plok ? "yes" : "NO"} · fields source ${source.length} · prolog ${prolog.length} · l4 ${l4.length}`,
  );
}

checkTriple("as-published", "schema.md", "schema-prolog.md", "schema-l4.md");
checkTriple(
  "restored",
  "schema-restored.md",
  "schema-restored-prolog.md",
  "schema-restored-l4.md",
);

if (problems.length) {
  problems.forEach((p) => console.error("  " + p));
  process.exit(1);
}
console.log("R4 parity OK — both triples agree on field set and order, and compile.");
