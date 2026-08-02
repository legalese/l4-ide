#!/usr/bin/env node
// The subject resolver: sidecar in, environment out.
//
// A subject is a per-body-of-law sidecar directory, etc/go/subjects/<id>/,
// carrying subject.json (machine-readable facts), pins.json (the CLI surface),
// known-defects.json (measured negative controls) and NOTES.md (free prose —
// read by humans and the skill, NEVER by scripts, and deliberately not
// validated here). The driver, libs and phase scripts are subject-generic; if
// a fact is about one body of law rather than about the pipeline, it belongs
// in the sidecar, not in a script.
//
// Usage:
//   node etc/go/lib/subject.mjs <id>              # shell-safe GO_S_* lines to eval
//   node etc/go/lib/subject.mjs <id> bpmn-rules   # TAB-separated "rule<TAB>stem" lines
//   node etc/go/lib/subject.mjs --list            # available subject ids, one per line
//
// Validation is refuse-by-default: an unknown key anywhere in subject.json is
// an error, and every referenced file must exist unless its key is declared
// optional-existence below. A leg entry with a missing golden is a hard error
// naming the offending path. Exit: 0 ok · 2 unknown subject / invalid
// descriptor / usage.
//
// L4_GO_SUBJECTS_DIR overrides the subjects root (the selftest uses this to
// aim the resolver at a deliberately broken sidecar); paths inside a
// descriptor stay repo-root-relative regardless.

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../../..");
const SUBJECTS_DIR = process.env.L4_GO_SUBJECTS_DIR
  ? resolve(process.env.L4_GO_SUBJECTS_DIR)
  : resolve(HERE, "../subjects");

// Canonical p7 leg order; also the closed set of declarable legs. go.sh
// declares a milestone stage iff the descriptor's legs object has the entry.
export const LEG_ORDER = [
  "p7-dmn",
  "p7-dmn-md",
  "p7-bpmn",
  "p7-ladder",
  "p7-lts",
  "p7-mcp",
  "p7-tnr",
  "p7-wizard",
  "p7-akn",
];

// Per-leg key schema: r = required (file must exist), o = optional (file must
// exist if declared), x = declared path whose EXISTENCE is optional — the
// phase itself owns the absent-file story (p7-dmn reports NOT-EXECUTABLE when
// the cases file is missing; that is a designed status, not a config error).
const LEG_KEYS = {
  "p7-dmn": { golden: "r", fidelity_golden: "r", cases: "x" },
  "p7-dmn-md": { golden: "r", fidelity_golden: "r" },
  "p7-bpmn": { expected_dir: "dir", rules: "rules" },
  "p7-ladder": {
    npm_dir: "dir",
    npm_script: "str",
    demo_entry: "r",
    figures_dir: "dir",
  },
  "p7-lts": {},
  "p7-mcp": {},
  "p7-tnr": { golden: "r", wizard_golden: "o" },
  "p7-wizard": {},
  "p7-akn": {},
};

// GO_S_* names for leg path/string keys, so phase scripts read one flat env.
const LEG_ENV = {
  "p7-dmn": {
    golden: "GO_S_DMN_GOLDEN",
    fidelity_golden: "GO_S_DMN_FIDELITY_GOLDEN",
    cases: "GO_S_DMN_CASES",
  },
  "p7-dmn-md": {
    golden: "GO_S_DMNMD_GOLDEN",
    fidelity_golden: "GO_S_DMNMD_FIDELITY_GOLDEN",
  },
  "p7-bpmn": { expected_dir: "GO_S_BPMN_EXPECTED_DIR" },
  "p7-ladder": {
    npm_dir: "GO_S_LADDER_NPM_DIR",
    npm_script: "GO_S_LADDER_NPM_SCRIPT",
    demo_entry: "GO_S_LADDER_DEMO_ENTRY",
    figures_dir: "GO_S_LADDER_FIGURES_DIR",
  },
  "p7-tnr": {
    golden: "GO_S_TNR_GOLDEN",
    wizard_golden: "GO_S_TNR_WIZARD_GOLDEN",
  },
};

function die(msg) {
  process.stderr.write(`subject.mjs: ${msg}\n`);
  process.exit(2);
}

function listSubjects() {
  if (!existsSync(SUBJECTS_DIR)) return [];
  return readdirSync(SUBJECTS_DIR)
    .filter((d) => existsSync(resolve(SUBJECTS_DIR, d, "subject.json")))
    .sort();
}

function refuseUnknown(id) {
  const avail = listSubjects();
  process.stderr.write(
    `subject.mjs: subject '${id}' has no sidecar under ${SUBJECTS_DIR}.\n` +
      `  Available subject(s): ${avail.length ? avail.join(", ") : "(none)"}\n\n` +
      `  To add one: create etc/go/subjects/<id>/ with subject.json (id, display_name,\n` +
      `  citation, source_url, corpus.main [+ optional corpus.wizard], checks, and a 'legs'\n` +
      `  object declaring exactly the projection legs the subject supports, each with its\n` +
      `  committed golden/cases paths, repo-root-relative), pins.json (the CLI surface,\n` +
      `  measured against that corpus), known-defects.json (measured negative controls,\n` +
      `  empty groups say why), and NOTES.md (free-prose idiosyncrasies; scripts never\n` +
      `  read it). The driver declares a milestone stage iff 'legs' has the entry, so a\n` +
      `  subject with no wizard and no regulative rules simply omits those legs and the\n` +
      `  milestone verdict stays honest. Any existing sidecar under etc/go/subjects/ is\n` +
      `  a worked example.\n`,
  );
  process.exit(2);
}

function checkKeys(where, obj, allowed) {
  for (const k of Object.keys(obj)) {
    if (!allowed.includes(k))
      die(`${where}: unknown key '${k}' (allowed: ${allowed.join(", ")})`);
  }
}

function mustExist(where, rel) {
  const abs = resolve(REPO, rel);
  if (!existsSync(abs))
    die(`${where}: referenced file does not exist: ${abs} (from '${rel}')`);
  return abs;
}

function mustBeDir(where, rel) {
  const abs = resolve(REPO, rel);
  if (!existsSync(abs) || !statSync(abs).isDirectory())
    die(
      `${where}: referenced directory does not exist: ${abs} (from '${rel}')`,
    );
  return abs;
}

export function loadSubject(id) {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(id)) refuseUnknown(id);
  const dir = resolve(SUBJECTS_DIR, id);
  const descPath = resolve(dir, "subject.json");
  if (!existsSync(descPath)) refuseUnknown(id);

  let desc;
  try {
    desc = JSON.parse(readFileSync(descPath, "utf8"));
  } catch (e) {
    die(`${descPath} is not valid JSON: ${e.message}`);
  }

  checkKeys(`subject.json`, desc, [
    "_comment",
    "id",
    "display_name",
    "citation",
    "source_url",
    "corpus",
    "checks",
    "legs",
  ]);
  for (const k of ["id", "display_name", "citation", "source_url"]) {
    if (typeof desc[k] !== "string" || !desc[k])
      die(`subject.json: '${k}' must be a non-empty string`);
  }
  if (desc.id !== id)
    die(`subject.json: id '${desc.id}' does not match directory name '${id}'`);

  if (typeof desc.corpus !== "object" || desc.corpus === null)
    die(`subject.json: 'corpus' must be an object`);
  checkKeys("corpus", desc.corpus, ["main", "wizard"]);
  if (typeof desc.corpus.main !== "string")
    die(`subject.json: corpus.main is required`);
  const corpusMain = mustExist("corpus.main", desc.corpus.main);
  const corpusWizard = desc.corpus.wizard
    ? mustExist("corpus.wizard", desc.corpus.wizard)
    : "";

  if (typeof desc.checks !== "object" || desc.checks === null)
    die(`subject.json: 'checks' must be an object`);
  checkKeys("checks", desc.checks, ["min_dated_arms", "min_assertions"]);
  for (const k of ["min_dated_arms", "min_assertions"]) {
    if (!Number.isInteger(desc.checks[k]) || desc.checks[k] < 0)
      die(`checks.${k}: must be a non-negative integer`);
  }

  if (typeof desc.legs !== "object" || desc.legs === null)
    die(`subject.json: 'legs' must be an object`);
  checkKeys("legs", desc.legs, LEG_ORDER);

  const env = {};
  const legs = LEG_ORDER.filter((l) => l in desc.legs);
  for (const leg of legs) {
    const entry = desc.legs[leg];
    if (typeof entry !== "object" || entry === null)
      die(`legs['${leg}'] must be an object`);
    const schema = LEG_KEYS[leg];
    checkKeys(`legs['${leg}']`, entry, Object.keys(schema));
    for (const [key, kind] of Object.entries(schema)) {
      const val = entry[key];
      const where = `legs['${leg}'].${key}`;
      if (val === undefined) {
        if (kind === "o") continue;
        die(`${where} is required`);
      }
      if (kind === "rules") {
        if (
          typeof val !== "object" ||
          val === null ||
          Object.keys(val).length === 0
        )
          die(
            `${where} must be a non-empty object of rule-name -> golden-stem`,
          );
        for (const [rule, stem] of Object.entries(val)) {
          if (typeof stem !== "string" || !/^[A-Za-z0-9._-]+$/.test(stem))
            die(
              `${where}['${rule}']: stem '${stem}' is not a plain filename stem`,
            );
          mustExist(
            `${where}['${rule}']`,
            `${entry.expected_dir}/${stem}.bpmn`,
          );
        }
        continue;
      }
      if (typeof val !== "string" || !val)
        die(`${where} must be a non-empty string`);
      const envName = LEG_ENV[leg]?.[key];
      if (kind === "str") {
        if (envName) env[envName] = val;
        continue;
      }
      const abs =
        kind === "dir"
          ? mustBeDir(where, val)
          : kind === "x"
            ? resolve(REPO, val) // declared path; the phase owns absence
            : mustExist(where, val);
      if (envName)
        env[envName] = kind === "dir" && key === "figures_dir" ? val : abs;
    }
  }
  if (legs.includes("p7-wizard") && !corpusWizard)
    die(
      `legs['p7-wizard'] is declared but corpus.wizard is not: the wizard leg renders the wizard module, so a subject with no wizard module omits the leg`,
    );

  const pins = resolve(dir, "pins.json");
  const defects = resolve(dir, "known-defects.json");
  if (!existsSync(pins)) die(`${dir}/pins.json is required and missing`);
  if (!existsSync(defects))
    die(`${dir}/known-defects.json is required and missing`);

  return {
    desc,
    env: {
      GO_S_ID: desc.id,
      GO_S_DISPLAY_NAME: desc.display_name,
      GO_S_CITATION: desc.citation,
      GO_S_SOURCE_URL: desc.source_url,
      GO_S_DIR: dir,
      GO_S_CORPUS: corpusMain,
      GO_S_WIZARD: corpusWizard,
      GO_S_PINS: pins,
      GO_S_KNOWN_DEFECTS: defects,
      GO_S_MIN_DATED_ARMS: String(desc.checks.min_dated_arms),
      GO_S_MIN_ASSERTIONS: String(desc.checks.min_assertions),
      GO_S_LEGS: legs.join(" "),
      ...env,
    },
  };
}

// Shell-safe single-quoting: close, escape, reopen.
const sq = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;

if (import.meta.url === `file://${process.argv[1]}`) {
  const [, , idOrFlag, sub] = process.argv;
  if (!idOrFlag) die("usage: subject.mjs <id> [bpmn-rules] | --list");
  if (idOrFlag === "--list") {
    process.stdout.write(listSubjects().join("\n") + "\n");
    process.exit(0);
  }
  const { desc, env } = loadSubject(idOrFlag);
  if (sub === "bpmn-rules") {
    const rules = desc.legs["p7-bpmn"]?.rules ?? {};
    for (const [rule, stem] of Object.entries(rules))
      process.stdout.write(`${rule}\t${stem}\n`);
    process.exit(0);
  }
  if (sub) die(`unknown subcommand '${sub}'`);
  for (const [k, v] of Object.entries(env))
    process.stdout.write(`${k}=${sq(v)}\n`);
  process.exit(0);
}
