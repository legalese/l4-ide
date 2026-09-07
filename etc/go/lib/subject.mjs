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
// declares a projection leg iff the descriptor's legs object has the entry.
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
  // engine_baseline: the exact verdict lines the external DMN engines must
  // print for THIS subject's golden. Optional, because a subject may declare a
  // DMN leg before anyone has run an engine over it -- but once declared, the
  // file must exist, and CI compares against it instead of against a string
  // typed into the workflow. Same shape as etc/bpmn-kie-baseline.txt, which is
  // the proven pattern here: a measurement belongs in a committed file next to
  // the artifact it measures, not in a `grep -q` inside a YAML step where only
  // one subject can ever be named.
  "p7-dmn": {
    golden: "r",
    fidelity_golden: "r",
    cases: "x",
    engine_baseline: "o",
  },
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
    engine_baseline: "GO_S_DMN_ENGINE_BASELINE",
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
      `  citation, source_url, corpus (main = the entry module; optional modules = every\n` +
      `  module of the encoding, in dependency order, main among them; optional wizard\n` +
      `  naming which of them is the wizard), checks, and a 'legs'\n` +
      `  object declaring exactly the projection legs the subject supports, each with its\n` +
      `  committed golden/cases paths, repo-root-relative, plus optional 'natlang_sources',\n` +
      `  'comparison' and 'encodings' objects\n` +
      `  declaring where the G2 deposits live — bundle, register, fork_register, modules,\n` +
      `  surface_map, plus per-deposit 'checks' floors and per-leg 'legs' declarations —\n` +
      `  whose paths' existence on disk is optional because producing them is agent work),\n` +
      `  pins.json (the CLI surface,\n` +
      `  measured against that corpus), known-defects.json (measured negative controls,\n` +
      `  empty groups say why), and NOTES.md (free-prose idiosyncrasies; scripts never\n` +
      `  read it). The driver declares a projection leg iff 'legs' has the entry, so a\n` +
      `  subject whose module set carries no wizard, and no regulative rules, simply omits\n` +
      `  those legs and the run verdict stays honest. Any existing sidecar under etc/go/subjects/ is\n` +
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

/**
 * Resolve a subject, optionally SELECTING one of its encodings.
 *
 * `selectedEncoding` defaults to "primary" — the committed encoding declared
 * under `encoding`. Naming an id from `encodings` makes the run about THAT
 * encoding: its modules and floors arrive under the ordinary `GO_S_ENCODING_*`
 * and `GO_S_MIN_*` names, so nothing downstream has to know which was chosen.
 *
 * That is the whole of R3 in one parameter. Which encoding a run is about is a
 * RUN PARAMETER; it was previously a schema key named after an ordinal
 * (`denovo`) and a capability label (`--milestone g2`, since retired by R9), both
 * of which made a
 * subject's position in its own history something you declare rather than
 * something you ask.
 */
export function loadSubject(id, selectedEncoding = "primary") {
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
    "encoding",
    "checks",
    "legs",
    "natlang_sources",
    "comparison",
    "encodings",
    "explainer",
  ]);
  for (const k of ["id", "display_name", "citation", "source_url"]) {
    if (typeof desc[k] !== "string" || !desc[k])
      die(`subject.json: '${k}' must be a non-empty string`);
  }
  if (desc.id !== id)
    die(`subject.json: id '${desc.id}' does not match directory name '${id}'`);

  if (typeof desc.encoding !== "object" || desc.encoding === null)
    die(`subject.json: 'encoding' must be an object`);
  checkKeys("encoding", desc.encoding, ["main", "wizard", "modules", "state"]);
  if (typeof desc.encoding.main !== "string")
    die(`subject.json: corpus.main is required`);

  // --- encoding.state: written (default) | unwritten -------------------------
  //
  // THE THIRD STATE. Until 2026-08-20 a sidecar could say only two things about
  // its encoding: this file, which must exist, or nothing at all — and `main`
  // is required, so "nothing at all" was not available either. That made the
  // FIRST encoding of a subject homeless: you cannot register a body of law
  // until you have already encoded it, and you cannot run `plan`, `doctor` or
  // any stage against it to find out what encoding it would involve. This is
  // ruling R12 in specs/todo/PIPELINE-ARTIFACT-MODEL-SPEC.md, and it is the
  // reason `go.sh new-subject` could not exist.
  //
  // The fix is a DECLARED state, not a relaxed check. The existence rule a few
  // lines below is deliberate — its own comment says a de novo module's absence
  // is a stage's SKIPPED story while a committed module's absence is a
  // misconfiguration — and simply permitting absence would turn a mistyped path
  // into a silent skip, which is precisely the failure the explainer's
  // "EXPLICIT DECLARATION, not directory discovery" comment refuses further
  // down this file.
  //
  // So the declaration is checked in BOTH directions:
  //
  //   state written (the default, and what every existing sidecar means):
  //     main, wizard and every module MUST exist. Byte-for-byte today's rule,
  //     so a typo still fails loudly naming the path.
  //
  //   state unwritten:
  //     they must NOT exist. Depositing the first module without flipping the
  //     state is itself an error, naming the file and the one-line edit — which
  //     is what stops the declaration from rotting into a lie the moment it
  //     stops being true.
  //
  // Nothing downstream needs teaching. The stages already report a declared
  // module that is not a file as SKIPPED with a named reason and the deposit
  // instruction (p3-check, p6-tests, p8-verify, via go_skip), and digestSet
  // records a missing path as ABSENT rather than skipping it — so an unwritten
  // encoding has a real gate digest, and depositing the first module moves that
  // digest and re-opens HG1, which is the property §6.3 already claims for a
  // post-gate edit.
  const encodingState = desc.encoding.state ?? "written";
  if (encodingState !== "written" && encodingState !== "unwritten")
    die(
      `encoding.state: unknown state '${encodingState}' (expected "written" or "unwritten")`,
    );
  const unwritten = encodingState === "unwritten";

  const encodingPath = (where, rel) => {
    const abs = resolve(REPO, rel);
    if (unwritten) {
      if (existsSync(abs))
        die(
          `${where}: the sidecar declares encoding.state "unwritten", but ${abs} exists.\n` +
            `  The encoding has been written, so the sidecar is now false. Set encoding.state to "written" in ${resolve(SUBJECTS_DIR, id, "subject.json")}\n` +
            `  (or delete the key — "written" is the default). Every stage will then hold this subject to the same rules as any other.`,
        );
      return abs;
    }
    return mustExist(where, rel);
  };

  const encodingMain = encodingPath("corpus.main", desc.encoding.main);
  const encodingWizard = desc.encoding.wizard
    ? encodingPath("corpus.wizard", desc.encoding.wizard)
    : "";

  // --- the corpus module set ------------------------------------------------
  //
  // A subject's encoding is not always one file. Singapore succession law is a
  // shared ontology module plus three statute modules (Wills, Intestate
  // Succession, Probate and Administration) plus a wizard, and every one of
  // them has to be checked, tested, verified and — above all — DIGESTED: the
  // corpus digest is what a human gate binds to, so a digest over the entry
  // module alone would leave a granted HG1 open across an edit to any of the
  // others. That is a false signature, not a cosmetic gap.
  //
  // `encoding.modules` declares the whole set, IN DEPENDENCY ORDER (an ontology
  // module before the statute modules that IMPORT it), and is validated exactly
  // the way `encodings.<id>.modules` is below — with one deliberate difference: a
  // corpus module must EXIST. A de novo module is an agent deposit whose
  // absence is a stage's SKIPPED story; a corpus module is committed, so a
  // missing one is a misconfiguration and says so, naming the path.
  //
  // `main` stays the ENTRY module — the one every single-artifact leg exports
  // from — and `wizard` stays the ROLE POINTER p7-wizard renders. Both are
  // therefore required to be MEMBERS of a declared set: a set that omits one of
  // them is a misdeclaration rather than a shorthand, and it would silently
  // drop that file out of the digest and out of GO_MODULES.
  //
  // Omitting `modules` resolves to exactly the historical set — main, plus the
  // wizard when declared — so an existing sidecar keeps meaning precisely what
  // it meant.
  let encodingModules;
  if (desc.encoding.modules === undefined) {
    encodingModules = encodingWizard
      ? [encodingMain, encodingWizard]
      : [encodingMain];
  } else {
    if (
      !Array.isArray(desc.encoding.modules) ||
      desc.encoding.modules.length === 0
    )
      die(`encoding.modules must be a non-empty array of module paths`);
    encodingModules = [];
    const seenAt = new Map(); // absolute path -> the declared string that got there
    for (const m of desc.encoding.modules) {
      if (typeof m !== "string" || !m)
        die(`encoding.modules: every entry must be a non-empty string`);
      // The env transport is space-separated (GO_S_ENCODING_MODULES, exactly as
      // an additional encoding's modules and GO_S_LEGS). A path with whitespace would split
      // silently into two nonexistent paths, so it is refused here rather than
      // mis-read there.
      if (/\s/.test(m))
        die(
          `encoding.modules['${m}']: a module path may not contain whitespace`,
        );
      const a = encodingPath(`encoding.modules['${m}']`, m);
      if (seenAt.has(a))
        die(
          `encoding.modules['${m}'] duplicates '${seenAt.get(a)}': both resolve to ${a}. The set is the gate digest's file list and the list p3-check/p6-tests/p8-verify iterate, so a repeat would double-count one module's assertions and findings`,
        );
      seenAt.set(a, m);
      encodingModules.push(a);
    }
    if (!seenAt.has(encodingMain))
      die(
        `encoding.modules does not contain corpus.main ('${desc.encoding.main}' -> ${encodingMain}). main is the subject's ENTRY module — the one the single-artifact legs export from — so a module set that omits it is a misdeclaration, not a shorthand`,
      );
    if (encodingWizard && !seenAt.has(encodingWizard))
      die(
        `encoding.modules does not contain corpus.wizard ('${desc.encoding.wizard}' -> ${encodingWizard}). The wizard is a ROLE POINTER into the module set, not a module beside it: leaving it out would drop it from the gate digest, so editing it could not re-open HG1`,
      );
  }
  // Membership set for the de novo identity guard below. Built once, from the
  // resolved set, so that widening the schema cannot leave that guard testing a
  // narrower list than the one the pipeline actually runs over.
  const encodingModuleSet = new Set(encodingModules);

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
  if (legs.includes("p7-wizard") && !encodingWizard)
    die(
      `legs['p7-wizard'] is declared but corpus.wizard is not: the wizard leg renders the wizard module, so a subject with no wizard module omits the leg`,
    );

  // --- what the subject is made of, named by WHAT IT IS ---------------------
  //
  // R2/R3. This used to be one `denovo` object, and `denovo` is an ORDINAL —
  // "the second pass" — so it named a position in the subject's history rather
  // than a thing. Worse, it bundled SIX keys covering FOUR different kinds of
  // thing: the fetched legal text, the case-law sweep, a second encoding of the
  // law, and the declaration that pairs two encodings for comparison. Renaming
  // it wholesale would have moved the category error under a better word, which
  // is why §3.2 deferred the rename until the split was possible.
  //
  // It is possible now, so the four kinds get four homes:
  //
  //   natlang_sources  the fetched legal text, and the sweep's findings —
  //                    NATURAL language, as against the formal language it is
  //                    encoded into. Subject-level: the law is the law, however
  //                    many times it has been encoded.
  //   comparison       the fork register and the surface map — the declarations
  //                    that exist only to relate two encodings to each other.
  //   encodings        ADDITIONAL encodings of the same law, keyed by an
  //                    author-chosen id. `encoding` (singular) remains the
  //                    primary, committed one.
  //
  // AN ID, NOT AN ORDINAL. `encodings["cleanroom-2026-08"]` names the OCCASION,
  // which is a fact about the job; "de novo" named the POSITION, which is a
  // query over history. And the property "de novo" was really reaching for —
  // produced WITHOUT reading a prior encoding — is now derivable rather than
  // declared: it is readset.independence(), which asks whether the producer's
  // read-set contained an `encode` artifact for this subject. §3.3 asked for
  // the pipeline to "stop needing either word"; R4 is what made that reachable.
  //
  // The deposits' EXISTENCE stays deliberately optional (the `x` kind): a
  // deposit the agent has not produced yet is a missing prerequisite the stage
  // reports as SKIPPED with a named reason, not a configuration error.
  const nls = desc.natlang_sources;
  const cmp = desc.comparison;
  const encs = desc.encodings;
  const extra = {
    GO_S_NATLANG_BUNDLE: "",
    GO_S_NATLANG_REGISTER: "",
    GO_S_COMPARISON_FORKS: "",
    GO_S_COMPARISON_SURFACE_MAP: "",
  };

  if (nls !== undefined) {
    if (typeof nls !== "object" || nls === null || Array.isArray(nls))
      die(`subject.json: 'natlang_sources' must be an object`);
    checkKeys("natlang_sources", nls, ["bundle", "register"]);
    for (const [key, envName] of Object.entries({
      bundle: "GO_S_NATLANG_BUNDLE",
      register: "GO_S_NATLANG_REGISTER",
    })) {
      if (nls[key] === undefined) continue;
      if (typeof nls[key] !== "string" || !nls[key])
        die(`natlang_sources.${key} must be a non-empty string`);
      extra[envName] = resolve(REPO, nls[key]);
    }
  }

  if (cmp !== undefined) {
    if (typeof cmp !== "object" || cmp === null || Array.isArray(cmp))
      die(`subject.json: 'comparison' must be an object`);
    checkKeys("comparison", cmp, ["fork_register", "surface_map"]);
    for (const [key, envName] of Object.entries({
      fork_register: "GO_S_COMPARISON_FORKS",
      surface_map: "GO_S_COMPARISON_SURFACE_MAP",
    })) {
      if (cmp[key] === undefined) continue;
      if (typeof cmp[key] !== "string" || !cmp[key])
        die(`comparison.${key} must be a non-empty string`);
      extra[envName] = resolve(REPO, cmp[key]);
    }
  }

  // Additional encodings. Validated wholesale — every declared one, not only
  // the selected one — because a typo in an encoding nobody selected today is
  // still a defect, and a schema that only checks the path being walked lets
  // the other paths rot unobserved.
  //
  // NOT a reuse of LEG_KEYS: that table makes `golden`/`fidelity_golden`
  // required, and an additional encoding HAS no golden — nothing committed to
  // diff it against, which is exactly why its projection legs run emit-only.
  const ALT_LEG_KEYS = { "p7-dmn": { cases: "x" } };
  const ALT_LEG_ENV = { "p7-dmn": { cases: "GO_S_ENCODING_DMN_CASES" } };
  const altEncodings = {};
  if (encs !== undefined) {
    if (typeof encs !== "object" || encs === null || Array.isArray(encs))
      die(`subject.json: 'encodings' must be an object keyed by encoding id`);
    for (const [encId, e] of Object.entries(encs)) {
      // The id is a name, and it must not be able to masquerade as the primary
      // or as an ordinal. `primary` is reserved because that is what the
      // selector calls the committed encoding.
      if (!/^[a-z0-9][a-z0-9._-]*$/.test(encId))
        die(
          `encodings['${encId}']: an encoding id must match [a-z0-9][a-z0-9._-]* — it names an occasion, not a sentence`,
        );
      if (encId === "primary")
        die(
          `encodings['primary']: 'primary' names the committed encoding declared under 'encoding', and may not be redeclared`,
        );
      if (typeof e !== "object" || e === null || Array.isArray(e))
        die(`encodings['${encId}'] must be an object`);
      checkKeys(`encodings['${encId}']`, e, ["modules", "checks", "legs"]);

      const out = {
        GO_S_ENCODING_MODULES: "",
        GO_S_MIN_DATED_ARMS: "",
        GO_S_MIN_ASSERTIONS: "",
        GO_S_ENCODING_DMN_CASES: "",
      };
      // REQUIRED, unlike every other key here. An encoding with no modules is
      // not an under-specified encoding, it is not an encoding — and the old
      // schema allowed exactly that, because `denovo` was a grab-bag in which
      // `modules` was one optional member among six unrelated ones.
      if (e.modules === undefined)
        die(
          `encodings['${encId}'].modules is required: an encoding is its modules`,
        );
      {
        if (!Array.isArray(e.modules) || e.modules.length === 0)
          die(`encodings['${encId}'].modules must be a non-empty array`);
        const abs = [];
        for (const m of e.modules) {
          if (typeof m !== "string" || !m)
            die(
              `encodings['${encId}'].modules: every entry must be a non-empty string`,
            );
          // The env transport is space-separated, matching GO_S_LEGS. A path
          // with whitespace would split silently into two nonexistent paths.
          if (/\s/.test(m))
            die(
              `encodings['${encId}'].modules['${m}']: a module path may not contain whitespace`,
            );
          // An additional encoding that IS the committed one makes the
          // acceptance diff an identity — the comparison would compare a thing
          // with itself and report agreement, which is the most confident way
          // to learn nothing.
          if (encodingModules.includes(resolve(REPO, m)))
            die(
              `encodings['${encId}'].modules['${m}'] is also a committed encoding module. The acceptance diff (SPEC.md §8) compares an additional encoding AGAINST the committed one, so an additional module that IS the committed one makes that comparison an identity`,
            );
          abs.push(resolve(REPO, m));
        }
        out.GO_S_ENCODING_MODULES = abs.join(" ");
      }
      // Floors measure THE ENCODING THEY BELONG TO. A committed floor applied to
      // a fresh deposit would fail a healthy deposit for not being the committed
      // one; a deposit floor applied to the committed encoding would let the
      // committed one shrink unnoticed. Same two keys, same shape, deliberately:
      // the floor's meaning does not change with the encoding, only the
      // population does. Which is why they now live WITH their encoding instead
      // of in a parallel `denovo.checks` — the pairing is structural, not a
      // convention a reader has to hold in their head.
      if (e.checks !== undefined) {
        if (
          typeof e.checks !== "object" ||
          e.checks === null ||
          Array.isArray(e.checks)
        )
          die(`encodings['${encId}'].checks must be an object`);
        checkKeys(`encodings['${encId}'].checks`, e.checks, [
          "min_dated_arms",
          "min_assertions",
        ]);
        for (const [key, envName] of Object.entries({
          min_dated_arms: "GO_S_MIN_DATED_ARMS",
          min_assertions: "GO_S_MIN_ASSERTIONS",
        })) {
          if (e.checks[key] === undefined) continue;
          if (!Number.isInteger(e.checks[key]) || e.checks[key] < 0)
            die(
              `encodings['${encId}'].checks.${key}: must be a non-negative integer`,
            );
          out[envName] = String(e.checks[key]);
        }
      }
      if (e.legs !== undefined) {
        if (
          typeof e.legs !== "object" ||
          e.legs === null ||
          Array.isArray(e.legs)
        )
          die(`encodings['${encId}'].legs must be an object`);
        checkKeys(`encodings['${encId}'].legs`, e.legs, LEG_ORDER);
        for (const [leg, entry] of Object.entries(e.legs)) {
          if (
            typeof entry !== "object" ||
            entry === null ||
            Array.isArray(entry)
          )
            die(`encodings['${encId}'].legs['${leg}'] must be an object`);
          checkKeys(
            `encodings['${encId}'].legs['${leg}']`,
            entry,
            Object.keys(ALT_LEG_KEYS[leg] ?? {}),
          );
          for (const key of Object.keys(ALT_LEG_KEYS[leg] ?? {})) {
            if (entry[key] === undefined) continue;
            if (typeof entry[key] !== "string" || !entry[key])
              die(
                `encodings['${encId}'].legs['${leg}'].${key} must be a non-empty string`,
              );
            out[ALT_LEG_ENV[leg][key]] = resolve(REPO, entry[key]);
          }
        }
      }
      altEncodings[encId] = out;
    }
  }

  // THE SELECTION. A run is ABOUT one encoding, and which one is a run
  // parameter — never a schema key, and never a capability label. The selected
  // encoding populates the ordinary `GO_S_ENCODING_*` and `GO_S_MIN_*`
  // variables, so no phase script branches on an "origin" sentinel: it reads
  // the encoding it was given. That is what deletes p3-check's, p6-tests's and
  // p7-dmn's `GO_MODULES_ORIGIN` arms rather than renaming them.
  if (selectedEncoding !== "primary" && !(selectedEncoding in altEncodings))
    die(
      `--encoding '${selectedEncoding}': subject '${id}' declares no such encoding. Declared: ${
        Object.keys(altEncodings).join(", ") || "(none besides the primary)"
      }`,
    );
  const selected =
    selectedEncoding === "primary" ? null : altEncodings[selectedEncoding];
  // --- the explainer narrative (P9's reader-facing sibling) -----------------
  //
  // EXPLAINER-REPORT-SPEC.md E1-a: EXPLICIT DECLARATION, not directory
  // discovery. Convention over configuration would work here and would need no
  // schema change; it is refused because a mistyped directory name would then
  // yield a fully-ABSENT explainer with no error anywhere — absence experienced
  // as breakage. A subject that declares no `explainer` key gets a clean SKIP
  // with a named reason, which is a different and honest outcome.
  let explainerDir = "";
  if (desc.explainer !== undefined) {
    if (
      typeof desc.explainer !== "object" ||
      desc.explainer === null ||
      Array.isArray(desc.explainer)
    )
      die(`subject.json: 'explainer' must be an object`);
    checkKeys("explainer", desc.explainer, ["dir"]);
    if (typeof desc.explainer.dir !== "string" || !desc.explainer.dir)
      die(`explainer.dir must be a non-empty string`);
    explainerDir = mustBeDir("explainer.dir", desc.explainer.dir);
  }

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
      GO_S_ENCODING: encodingMain,
      GO_S_WIZARD: encodingWizard,
      // The whole encoding, space-separated, in declared (dependency) order —
      // same transport as GO_S_LEGS. GO_S_ENCODING and
      // GO_S_WIZARD stay exactly what they were, the entry module and the
      // wizard role pointer, so the single-module legs read the same value they
      // always did.
      GO_S_ENCODING_MODULES: encodingModules.join(" "),
      // Exported so the report and the plan can SAY "unwritten" rather than
      // leaving the reader to infer it from a run in which every stage skipped.
      // The stages themselves need nothing: a declared path that is not a file
      // is already their SKIPPED story, with the deposit instruction attached.
      GO_S_ENCODING_STATE: encodingState,
      GO_S_PINS: pins,
      GO_S_KNOWN_DEFECTS: defects,
      GO_S_MIN_DATED_ARMS: String(desc.checks.min_dated_arms),
      GO_S_MIN_ASSERTIONS: String(desc.checks.min_assertions),
      GO_S_EXPLAINER_DIR: explainerDir,
      GO_S_LEGS: legs.join(" "),
      ...extra,
      ...env,
      // THE SELECTION WINS, LAST. Spread after the committed defaults so a run
      // about an additional encoding sees that encoding's modules and floors
      // under the ORDINARY names — which is what lets every phase script drop
      // its "origin" branch and simply read the encoding it was handed.
      //
      // A key the selected encoding does not declare lands as "", exactly as an
      // undeclared committed floor would: the stage then reports the floor
      // UNDECLARED rather than silently inheriting the committed one, which
      // would fail a healthy deposit for not being the committed encoding.
      ...(selected ?? {}),
      GO_S_ENCODING_ID: selectedEncoding,
    },
  };
}

// Shell-safe single-quoting: close, escape, reopen.
const sq = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;

if (import.meta.url === `file://${process.argv[1]}`) {
  // `--encoding <id>` is pulled out before the positional split, so it may sit
  // anywhere on the line. It selects WHICH encoding the caller is asking about;
  // omitted, the answer is about the committed one.
  const rawArgs = process.argv.slice(2);
  let wantEncoding = "primary";
  const encIdx = rawArgs.indexOf("--encoding");
  if (encIdx >= 0) {
    if (!rawArgs[encIdx + 1]) die("--encoding needs an encoding id");
    wantEncoding = rawArgs[encIdx + 1];
    rawArgs.splice(encIdx, 2);
  }
  const [idOrFlag, sub] = rawArgs;
  if (!idOrFlag)
    die(
      "usage: subject.mjs <id> [bpmn-rules] [--encoding <enc-id>] | --list | --ci",
    );
  if (idOrFlag === "--list") {
    process.stdout.write(listSubjects().join("\n") + "\n");
    process.exit(0);
  }
  // --ci: every subject's CI-relevant shape, as JSON, in REPO-RELATIVE paths.
  //
  // CI cannot read a sidecar the way a phase script can -- a GitHub workflow
  // step has no GO_S_* environment and a `paths:` filter is static YAML. So the
  // one place that knows what a subject declares emits it, and the workflow
  // consumes it, rather than the workflow keeping its own copy of the answer
  // under a name only one subject will ever match. Paths are relative because
  // that is what a `paths:` filter and a repo-root `run:` step both want; the
  // GO_S_* env transport stays absolute and unchanged.
  // `--encodings`: the ids of a subject's ADDITIONAL encodings, one per line.
  // The driver needs it to answer `--encoding undeclared` — which is a CLAIM
  // that the subject declares none, and is refused with this list when false —
  // and CI needs it to name a subject's deposit encoding instead of keeping its
  // own copy of that answer. It is a listing and not a selection, so it
  // deliberately does not take --encoding.
  if (sub === "--encodings" || sub === "encodings") {
    const { desc } = loadSubject(idOrFlag);
    for (const k of Object.keys(desc.encodings ?? {}))
      process.stdout.write(k + "\n");
    process.exit(0);
  }
  if (idOrFlag === "--ci") {
    const out = listSubjects().map((id) => {
      const { desc } = loadSubject(id);
      const modules = desc.encoding.modules ?? [
        desc.encoding.main,
        ...(desc.encoding.wizard ? [desc.encoding.wizard] : []),
      ];
      const dirs = [
        ...new Set(modules.map((m) => m.slice(0, m.lastIndexOf("/")))),
      ].sort();
      return {
        id,
        display_name: desc.display_name,
        encoding_state: desc.encoding.state ?? "written",
        encoding_dirs: dirs,
        legs: desc.legs,
      };
    });
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
    process.exit(0);
  }
  const { desc, env } = loadSubject(idOrFlag, wantEncoding);
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
