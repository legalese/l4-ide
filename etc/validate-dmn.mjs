// Validate emitted DMN 1.3 XML by parsing it with `dmn-moddle` -- the moddle
// descriptor Camunda's own DMN tooling (dmn-js / dmn-migrate) is built on. This
// is a real check, not a well-formedness check: dmn-moddle knows the DMN 1.3
// metamodel, so it reports unknown elements, unknown attributes, and children
// that do not belong to the type they appear under.
//
// It does NOT check XSD sequence order, and it does not execute anything. Read
// "0 warnings" as "every element and attribute we emitted is one DMN 1.3
// defines, in a place it is allowed to be", not as "Camunda will import this".
//
// Run WITHOUT installing anything into the repo (package.json and the lockfile
// are deliberately left alone):
//
//   npx --yes --package=dmn-moddle node etc/validate-dmn.mjs jl4/examples/dmn/expected/reg-cf.dmn
//
// With no arguments it validates every *.dmn under jl4/examples/dmn/expected/.
// Exits non-zero if any file fails to parse or produces warnings.

import { readFile, readdir } from "node:fs/promises";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

// `npx --package=X node script.mjs` installs X into ~/.npm/_npx/<hash>/node_modules
// and puts only its .bin on PATH -- node still resolves `require` from the
// SCRIPT's directory, which is inside the repo and has no node_modules. So find
// the npx cache directory on PATH and require from there. This is the price of
// not adding a dependency to package.json; the lockfile on this repo is already
// drifted and a new entry would block CI.
function loadDmnModdle() {
  const candidates = [import.meta.url];
  for (const entry of (process.env.PATH ?? "").split(":")) {
    if (entry.includes("_npx") && entry.endsWith("node_modules/.bin")) {
      candidates.push(join(dirname(entry), "anchor.js"));
    }
  }
  const failures = [];
  for (const from of candidates) {
    try {
      const mod = createRequire(from)("dmn-moddle");
      // dmn-moddle 12 is CJS and exports { DmnModdle }; older majors default-exported it.
      return mod.DmnModdle ?? mod.default ?? mod;
    } catch (err) {
      failures.push(err.message);
    }
  }
  console.error(
    "could not load dmn-moddle. Run this script as:\n" +
      "  npx --yes --package=dmn-moddle node etc/validate-dmn.mjs\n" +
      failures.map((m) => `  - ${m}`).join("\n"),
  );
  process.exit(2);
}

const DmnModdle = loadDmnModdle();

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const defaultDir = join(repoRoot, "jl4", "examples", "dmn", "expected");

async function targets() {
  const args = process.argv.slice(2);
  if (args.length > 0) return args;
  const entries = await readdir(defaultDir);
  return entries
    .filter((f) => f.endsWith(".dmn") && !f.endsWith(".actual.dmn"))
    .map((f) => join(defaultDir, f));
}

const moddle = new DmnModdle();
let failed = 0;

for (const file of await targets()) {
  const xml = await readFile(file, "utf8");
  let result;
  try {
    result = await moddle.fromXML(xml, "dmn:Definitions");
  } catch (err) {
    console.error(`FAIL  ${file}\n  ${err.message}`);
    failed++;
    continue;
  }

  const warnings = result.warnings ?? [];
  const defs = result.rootElement;
  const decisions = (defs.drgElement ?? []).filter(
    (e) => e.$type === "dmn:Decision",
  );
  const inputs = (defs.drgElement ?? []).filter(
    (e) => e.$type === "dmn:InputData",
  );
  const tables = decisions.filter(
    (d) => d.decisionLogic?.$type === "dmn:DecisionTable",
  );
  const literals = decisions.filter(
    (d) => d.decisionLogic?.$type === "dmn:LiteralExpression",
  );

  // Cross-check the two invariants a moddle parse will not: every rule is as
  // wide as the table, and every href resolves to an element in the file.
  const ids = new Set((defs.drgElement ?? []).map((e) => e.id));
  const problems = [];
  for (const d of tables) {
    const t = d.decisionLogic;
    const width = (t.input ?? []).length;
    for (const rule of t.rule ?? []) {
      if ((rule.inputEntry ?? []).length !== width) {
        problems.push(
          `rule ${rule.id}: ${(rule.inputEntry ?? []).length} input entries, table has ${width} columns`,
        );
      }
    }
  }
  for (const d of decisions) {
    for (const ir of d.informationRequirement ?? []) {
      const href = ir.requiredDecision?.href ?? ir.requiredInput?.href;
      if (!href || !href.startsWith("#") || !ids.has(href.slice(1))) {
        problems.push(
          `decision ${d.id}: dangling information requirement href ${href}`,
        );
      }
      if (ir.requiredDecision?.href === `#${d.id}`) {
        problems.push(
          `decision ${d.id}: requires itself (DMN 7.3.1 forbids this)`,
        );
      }
    }
  }

  const status =
    warnings.length === 0 && problems.length === 0 ? "OK   " : "WARN ";
  console.log(
    `${status} ${file}\n` +
      `       ${decisions.length} decision(s): ${tables.length} table(s), ${literals.length} literal expression(s); ` +
      `${inputs.length} inputData; ${(defs.dmnDI?.diagrams ?? []).length} diagram(s)`,
  );
  for (const w of warnings) console.log(`       moddle warning: ${w.message}`);
  for (const p of problems) console.log(`       structural: ${p}`);
  if (warnings.length || problems.length) failed++;
}

process.exit(failed === 0 ? 0 : 1);
