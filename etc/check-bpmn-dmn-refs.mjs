// Does every BPMN businessRuleTask point at a decision that actually EXISTS in
// the emitted DMN?
//
// This is the gate on PROCESS-TRACK.md §8.3's linkage. The exporter is built so
// a dangling reference is unrepresentable — `L4.Bpmn.Wiring` indexes the
// emitted DRG, so a decision that was never emitted is simply not in the table
// and its gateway is left unwired — but "unrepresentable by construction" is a
// claim about code, and this script is the claim about the ARTIFACTS. The two
// fail differently: a refactor that starts re-deriving ids from the L4 source
// would keep every Haskell test green and break exactly this.
//
// What a businessRuleTask asserts, and what is checked:
//
//   implementation="http://www.jboss.org/drools/dmn"   the rule language
//   <dataInput name="namespace"> + assignment          the DMN targetNamespace
//   <dataInput name="model">     + assignment          the DMN <definitions> @name
//   <dataInput name="decision">  + assignment          a <decision> @name in it
//
// That triple is the whole of the engine's lookup key, so checking it is
// checking what an engine would do. A task missing any of the three, or naming
// a (namespace, model) pair no supplied DMN provides, or naming a decision that
// pair does not contain, is a HARD ERROR — never a warning. A dangling
// decisionRef is the one defect this linkage can have that a reader cannot see:
// the diagram still draws, the file still parses, and the delegation silently
// does nothing.
//
// A BPMN file with no businessRuleTask at all is fine and says so. What is NOT
// fine is being handed no DMN: with nothing to resolve against, every reference
// would "pass" vacuously, which is the failure mode this file exists to avoid.
//
// ZERO INSTALL, ZERO DEPENDENCIES — Node only, no network:
//
//   node etc/check-bpmn-dmn-refs.mjs jl4/examples/bpmn/expected/*.bpmn \
//                                    jl4/examples/dmn/expected/regcf-corpus.dmn
//
// Files are classified by extension, in any order. It reads the XML itself
// rather than through bpmn-moddle, for the same reason
// etc/check-bpmn-soundness.mjs does: a disagreement between two readers about
// what the file says should surface as a disagreement.
//
// Exit codes:  0 every reference resolves   1 a reference dangles   2 usage

import { readFileSync } from "node:fs";

// ---------------------------------------------------------------------------
// A minimal XML scanner, shared in spirit with check-bpmn-soundness.mjs
// ---------------------------------------------------------------------------

function stripNoise(xml) {
  return xml.replace(/<!--[\s\S]*?-->/g, "").replace(/<\?[\s\S]*?\?>/g, "");
}

// Attributes may hold a quoted '>', so the tag body allows quoted runs and bans
// a bare '>'. Anything this does not match is not a tag.
const TAG_RE = /<(\/?)([A-Za-z_][\w.:-]*)((?:"[^"]*"|'[^']*'|[^>"'])*)>/g;
const ATTR_RE = /([\w.:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;

function localName(qname) {
  const i = qname.indexOf(":");
  return i === -1 ? qname : qname.slice(i + 1);
}

function attrsOf(chunk) {
  const out = {};
  for (const m of chunk.matchAll(ATTR_RE)) out[localName(m[1])] = m[2] ?? m[3];
  return out;
}

// XML entity references, for the handful an exporter emits. Numeric forms are
// included because the BPMN emitter escapes newlines and tabs that way.
function unescapeXml(s) {
  return s
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&#x([0-9A-Fa-f]+);/g, (_, h) =>
      String.fromCodePoint(parseInt(h, 16)),
    )
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

// The text content of the element opening at `from`, when it is a simple leaf.
// Returns null if the next thing after the open tag is another tag.
function leafTextAfter(text, from) {
  const m = /^([^<]*)</.exec(text.slice(from));
  return m ? unescapeXml(m[1]).trim() : null;
}

// ---------------------------------------------------------------------------
// Reading the two sides
// ---------------------------------------------------------------------------

// Every <decision> a DMN document declares, keyed by (namespace, model).
function readDmn(file, xml) {
  const text = stripNoise(xml);
  let namespace = null;
  let model = null;
  const decisions = new Map(); // name -> id

  for (const m of text.matchAll(TAG_RE)) {
    const [, closing, qname, attrChunk] = m;
    if (closing) continue;
    const name = localName(qname);
    const a = attrsOf(attrChunk);
    if (name === "definitions") {
      namespace = a.namespace ?? null;
      model = a.name ?? null;
      continue;
    }
    // Only top-level <decision>; DMNDI's <DMNShape dmnElementRef=…> is a
    // different element and never matches.
    if (name === "decision" && a.name) decisions.set(a.name, a.id ?? "(no id)");
  }

  if (namespace === null || model === null) {
    return { error: `${file}: <definitions> has no namespace and/or no name` };
  }
  return { file, namespace, model, decisions };
}

// Every <businessRuleTask> a BPMN document declares, with the three constants
// its dataInputAssociations assign.
function readBpmn(file, xml) {
  const text = stripNoise(xml);
  const tasks = [];
  let current = null; // the businessRuleTask being filled
  let pendingTarget = null; // the dataInput a dataInputAssociation points at
  let inputNames = new Map(); // dataInput id -> its @name

  for (const m of text.matchAll(TAG_RE)) {
    const [, closing, qname, attrChunk] = m;
    const name = localName(qname);
    const after = m.index + m[0].length;

    if (closing) {
      if (name === "businessRuleTask") current = null;
      if (name === "dataInputAssociation") pendingTarget = null;
      continue;
    }

    const a = attrsOf(attrChunk);

    if (name === "businessRuleTask") {
      current = {
        id: a.id ?? "(no id)",
        name: a.name ?? "",
        implementation: a.implementation ?? null,
        values: new Map(), // "namespace" | "model" | "decision" -> value
      };
      inputNames = new Map();
      tasks.push(current);
      continue;
    }
    if (!current) continue;

    if (name === "dataInput" && a.id && a.name) {
      inputNames.set(a.id, a.name);
      continue;
    }
    if (name === "targetRef") {
      const ref = leafTextAfter(text, after);
      if (ref) pendingTarget = inputNames.get(ref) ?? null;
      continue;
    }
    if (name === "from") {
      const v = leafTextAfter(text, after);
      if (pendingTarget !== null && v !== null)
        current.values.set(pendingTarget, v);
      continue;
    }
  }
  return { file, tasks };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const DROOLS_DMN = "http://www.jboss.org/drools/dmn";
const REQUIRED = ["namespace", "model", "decision"];

const args = process.argv.slice(2);
if (args.length === 0) {
  console.error(
    "usage: node etc/check-bpmn-dmn-refs.mjs FILE.bpmn [FILE.bpmn ...] FILE.dmn [FILE.dmn ...]",
  );
  process.exit(2);
}

const bpmnFiles = args.filter((f) => f.endsWith(".bpmn"));
const dmnFiles = args.filter((f) => f.endsWith(".dmn"));
const unknown = args.filter((f) => !f.endsWith(".bpmn") && !f.endsWith(".dmn"));
if (unknown.length) {
  console.error(`not a .bpmn or .dmn file: ${unknown.join(", ")}`);
  process.exit(2);
}
if (bpmnFiles.length === 0) {
  console.error("no .bpmn files given — nothing to check");
  process.exit(2);
}
// Refusing here rather than passing vacuously: see the header. A run with no
// DMN would report every reference as unresolvable anyway, but saying "0 of 0
// checked, OK" is how a narrowed glob turns a gate into decoration.
if (dmnFiles.length === 0) {
  console.error("no .dmn files given — every reference would be unresolvable");
  process.exit(2);
}

const models = new Map(); // `${namespace} ${model}` -> { file, decisions }
let failed = false;

for (const file of dmnFiles) {
  const d = readDmn(file, readFileSync(file, "utf8"));
  if (d.error) {
    console.error(d.error);
    process.exit(2);
  }
  models.set(`${d.namespace} ${d.model}`, d);
  console.log(
    `${file}: model "${d.model}" @ ${d.namespace} — ${d.decisions.size} decision(s)`,
  );
}

for (const file of bpmnFiles) {
  const { tasks } = readBpmn(file, readFileSync(file, "utf8"));
  const problems = [];

  for (const t of tasks) {
    const where = `businessRuleTask ${t.id}${t.name ? ` "${t.name}"` : ""}`;

    if (t.implementation !== DROOLS_DMN) {
      problems.push(
        `${where}: implementation is ${t.implementation ?? "(absent)"}, expected ${DROOLS_DMN}`,
      );
      continue;
    }
    const missing = REQUIRED.filter((k) => !t.values.has(k));
    if (missing.length) {
      problems.push(
        `${where}: no assigned value for dataInput(s) ${missing.join(", ")}`,
      );
      continue;
    }

    const ns = t.values.get("namespace");
    const model = t.values.get("model");
    const decision = t.values.get("decision");
    const target = models.get(`${ns} ${model}`);
    if (!target) {
      problems.push(
        `${where}: no supplied DMN declares model "${model}" at namespace ${ns}`,
      );
      continue;
    }
    if (!target.decisions.has(decision)) {
      problems.push(
        `${where}: model "${model}" has no <decision name="${decision}"> ` +
          `(it has ${target.decisions.size}: ${[...target.decisions.keys()].slice(0, 5).join(", ")}…)`,
      );
      continue;
    }
  }

  if (problems.length === 0) {
    const n = tasks.length;
    console.log(
      n === 0
        ? `${file}: OK — no businessRuleTask, nothing to resolve`
        : `${file}: OK — ${n} businessRuleTask reference(s), all resolve`,
    );
  } else {
    failed = true;
    console.error(`${file}: ${problems.length} dangling reference(s)`);
    for (const p of problems) console.error(`  - ${p}`);
  }
}

process.exit(failed ? 1 : 0);
