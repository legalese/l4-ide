// Validate emitted BPMN 2.0 with the library Camunda Modeler reads BPMN with.
//
// `bpmn-moddle` is what `bpmn-js` — and therefore Camunda Modeler — uses to
// parse a .bpmn file. If it reports no warnings and every reference resolves,
// the file will open in the Modeler; K4 in
// specs/todo/lexipedia-superset/SPEC.md is exactly that claim, and this script
// is the evidence for it.
//
// Run WITHOUT installing anything into this repo (its lockfile is drifted and a
// new dependency would block CI):
//
//   npx --yes --package=bpmn-moddle node etc/validate-bpmn.mjs jl4/examples/bpmn/expected/offering.bpmn
//
// Exits non-zero on a parse error, a moddle warning, or a dangling reference.

import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";

// Resolve bpmn-moddle from wherever it was provided, never from this repo:
// npx puts it in ~/.npm/_npx/<hash>/node_modules and only advertises it on
// PATH, and a manual `npm install --prefix` advertises it on NODE_PATH.
const BpmnModdle = await loadBpmnModdle();

async function loadBpmnModdle() {
  const roots = [
    import.meta.url,
    ...(process.env.NODE_PATH ?? "").split(":").filter(Boolean),
    ...(process.env.PATH ?? "")
      .split(":")
      .filter((p) => p.includes("_npx") && p.endsWith(".bin"))
      .map((p) => resolve(p, "..")),
  ];
  for (const root of roots) {
    try {
      const req = createRequire(
        root.startsWith("file:") ? root : `${root}/anchor.js`,
      );
      // v10 is ESM; require() hands back the namespace, whose named export is
      // BpmnModdle. Older CJS builds put the constructor on default / module.
      const mod = req("bpmn-moddle");
      return mod.BpmnModdle ?? mod.default ?? mod;
    } catch {
      /* try the next root */
    }
  }
  console.error(
    "Could not find bpmn-moddle. Run this script as:\n" +
      "  npx --yes --package=bpmn-moddle@10 node etc/validate-bpmn.mjs FILE.bpmn\n" +
      "or install it outside the repo and point NODE_PATH at it:\n" +
      '  npm install --no-save --prefix "$TMPDIR/bpmnval" bpmn-moddle@10\n' +
      '  NODE_PATH="$TMPDIR/bpmnval/node_modules" node etc/validate-bpmn.mjs FILE.bpmn',
  );
  process.exit(2);
}

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error("usage: node etc/validate-bpmn.mjs FILE.bpmn [FILE.bpmn ...]");
  process.exit(2);
}

const moddle = new BpmnModdle();
let failed = false;

for (const file of files) {
  const xml = readFileSync(file, "utf8");
  let result;
  try {
    result = await moddle.fromXML(xml, "bpmn:Definitions");
  } catch (err) {
    console.error(`${file}: PARSE ERROR ${err.message}`);
    failed = true;
    continue;
  }

  const { rootElement, warnings } = result;
  const problems = [
    ...(warnings ?? []).map((w) => `moddle warning: ${w.message}`),
  ];

  // Collect everything with an id, then check that the references we emit
  // actually resolve. bpmn-moddle resolves references itself, so a dangling
  // one surfaces as an unresolved-reference warning; this is belt and braces,
  // and it also checks the diagram covers the process.
  const ids = new Set();
  const nodes = [];
  const flows = [];
  const walk = (el) => {
    if (!el || typeof el !== "object") return;
    if (el.id) ids.add(el.id);
    if (el.$type === "bpmn:SequenceFlow") flows.push(el);
    else if (/^bpmn:(Task|.*Event|.*Gateway)$/.test(el.$type ?? ""))
      nodes.push(el);
    for (const [key, value] of Object.entries(el)) {
      if (key.startsWith("$")) continue;
      if (Array.isArray(value)) value.forEach(walk);
      else if (value && typeof value === "object" && value.$type) walk(value);
    }
  };
  walk(rootElement);

  for (const flow of flows) {
    if (!flow.sourceRef)
      problems.push(`sequence flow ${flow.id} has no resolved sourceRef`);
    if (!flow.targetRef)
      problems.push(`sequence flow ${flow.id} has no resolved targetRef`);
  }
  for (const node of nodes) {
    if (node.$type === "bpmn:BoundaryEvent") {
      if (!node.attachedToRef)
        problems.push(
          `boundary event ${node.id} has no resolved attachedToRef`,
        );
      if (!(node.eventDefinitions ?? []).length) {
        problems.push(
          `boundary event ${node.id} has no trigger (BPMN forbids a "none" boundary event)`,
        );
      }
    }
  }

  // Diagram interchange: every flow node and every sequence flow must be drawn.
  const drawn = new Set();
  for (const diagram of rootElement.diagrams ?? []) {
    for (const child of diagram.plane?.planeElement ?? []) {
      if (child.bpmnElement?.id) drawn.add(child.bpmnElement.id);
      if (
        child.$type === "bpmndi:BPMNEdge" &&
        (child.waypoint ?? []).length < 2
      ) {
        problems.push(`edge ${child.id} has fewer than two waypoints`);
      }
    }
  }
  for (const el of [...nodes, ...flows]) {
    if (!drawn.has(el.id))
      problems.push(`${el.$type} ${el.id} has no diagram interchange`);
  }

  if (problems.length === 0) {
    console.log(
      `${file}: OK — 0 warnings, ${nodes.length} flow nodes, ${flows.length} sequence flows, all drawn`,
    );
  } else {
    failed = true;
    console.error(`${file}: ${problems.length} problem(s)`);
    for (const p of problems) console.error(`  - ${p}`);
  }
}

process.exit(failed ? 1 : 0);
