// Soundness-check emitted BPMN 2.0 by playing the token game on it.
//
// This is the SECOND opinion that `etc/validate-bpmn.mjs` cannot be. That
// script parses with `bpmn-moddle` — the library `bpmn-js`, and therefore
// Camunda Modeler, reads BPMN with — and so it answers "will this file open?".
// K4 in specs/todo/lexipedia-superset/SPEC.md is exactly that claim and this
// script does not replace it. But a parser cannot see a diagram that can never
// finish, and the exporter's own defect history is the argument: the first
// version passed bpmn-moddle at ZERO warnings across 1581 green examples while
// emitting a converging parallel gateway that counted edges rather than tokens
// — a join waiting forever for a token nothing would ever send. See `addJoin`
// in jl4-core/src/L4/Bpmn/Lower.hs, and the demonstration in
// jl4/examples/bpmn/unsound/.
//
// So: translate the process to a workflow net and explore its reachable
// markings exhaustively. What is checked, in the vocabulary of van der Aalst's
// workflow-net soundness:
//
//   S1  option to complete   from every reachable marking, the empty marking
//                            (every token consumed) is still reachable
//   S2  no deadlock          no reachable marking is stuck with tokens left —
//                            S1's failure mode, reported separately because it
//                            is the one with a readable witness
//   S3  no dead flow node    every node fires in at least one run
//   S4  safe (1-bounded)     no sequence flow ever holds two tokens
//
// S1/S2 are the properties the historical bug violated. S3 catches a branch
// wired so it can never be entered. S4 catches a fork whose tokens pile up.
//
// PROPER COMPLETION IS DELIBERATELY NOT AN ERROR HERE. A classic WF-net demands
// exactly one token in one sink; BPMN instead completes when every token has
// been consumed, and consuming several at several end events is legal. The
// exporter emits precisely that shape on purpose — a `RAND` whose branches
// cannot be joined is drawn as a fork with no join and reported as `P-NOJOIN`
// (see jl4/examples/bpmn/README.md). Flagging it would be flagging the design.
// Peak concurrent tokens is reported as information instead.
//
// ZERO INSTALL, ZERO DEPENDENCIES. Node only, no network:
//
//   node etc/check-bpmn-soundness.mjs jl4/examples/bpmn/expected/*.bpmn
//
// It deliberately does NOT use bpmn-moddle. Reading the XML independently
// means a disagreement between the two scripts about what the graph even is
// shows up as a disagreement, rather than being inherited from a shared parser.
// It is not a substitute for validate-bpmn.mjs: it assumes the file is
// well-formed BPMN and refuses rather than guesses when it is not.
//
// Exit codes:  0 sound   1 unsound   2 usage/parse error   3 UNSUPPORTED
// An unsupported construct exits NON-ZERO and says so. It never passes quietly:
// silently reporting a check that was not run is the failure mode this whole
// exercise exists to avoid.

import { readFileSync } from "node:fs";

const MAX_STATES = 200_000;
const MAX_TOKENS_PER_PLACE = 4;

// ---------------------------------------------------------------------------
// A small BPMN reader
// ---------------------------------------------------------------------------

// Node kinds the token game knows how to play. Anything else is refused.
const ACTIVITIES = new Set([
  "task",
  "userTask",
  "serviceTask",
  "scriptTask",
  "manualTask",
  "businessRuleTask",
  "sendTask",
  "receiveTask",
  "callActivity",
]);
const PASSTHROUGH = new Set([
  ...ACTIVITIES,
  "intermediateCatchEvent",
  "intermediateThrowEvent",
]);
const XOR_GATEWAYS = new Set(["exclusiveGateway", "eventBasedGateway"]);
const AND_GATEWAYS = new Set(["parallelGateway"]);
// Present in BPMN, meaningful, and NOT modelled here. Refuse loudly.
const REFUSED = {
  inclusiveGateway:
    "an inclusive gateway's join waits on a set of branches decided at runtime; " +
    "its token game needs the branch conditions this checker does not read",
  complexGateway:
    "a complex gateway's activation rule is an arbitrary expression",
  subProcess:
    "a sub-process has its own token scope; this checker plays one process only",
  transaction: "a transaction sub-process adds compensation semantics",
  adHocSubProcess: "an ad-hoc sub-process has no sequence flow to play",
};

function stripNoise(xml) {
  return xml
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, "")
    .replace(/<\?[\s\S]*?\?>/g, "");
}

// Attributes may hold a quoted '>', so the tag body allows quoted runs and
// bans a bare '>'. Anything this does not match is not a tag.
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

// Returns { processes: [...], refusals: [...] }. One entry per <process>.
function readBpmn(xml) {
  const text = stripNoise(xml);
  const refusals = [];
  const processes = [];
  const stack = [];
  let current = null; // the process being filled
  let inDiagram = 0;

  for (const m of text.matchAll(TAG_RE)) {
    const [, closing, qname, attrChunk] = m;
    const name = localName(qname);
    const isOpen = !closing;
    const isLeaf = m[0].endsWith("/>");

    // The BPMNDiagram subtree reuses names like `plane`; never read it.
    if (name === "BPMNDiagram" || name === "BPMNPlane") {
      if (isOpen && !isLeaf) inDiagram++;
      else if (closing) inDiagram = Math.max(0, inDiagram - 1);
      continue;
    }
    if (inDiagram > 0) continue;

    if (closing) {
      const popped = stack.pop();
      if (popped === "process") current = null;
      continue;
    }
    if (!isLeaf) stack.push(name);

    const a = attrsOf(attrChunk);

    if (name === "process") {
      current = {
        id: a.id ?? `process_${processes.length}`,
        name: a.name ?? a.id ?? "",
        nodes: new Map(), // id -> { id, kind, name, boundaries: [] }
        flows: [], // { id, source, target }
        boundaries: [], // { id, name, attachedTo, interrupting }
      };
      processes.push(current);
      continue;
    }
    if (!current) continue; // laneSet inside collaboration, extensions, etc.

    if (name in REFUSED) {
      refusals.push(`${name} ${a.id ?? "(no id)"}: ${REFUSED[name]}`);
      continue;
    }
    if (name === "sequenceFlow") {
      current.flows.push({
        id: a.id ?? `flow_${current.flows.length}`,
        source: a.sourceRef,
        target: a.targetRef,
      });
      continue;
    }
    if (name === "boundaryEvent") {
      current.boundaries.push({
        id: a.id,
        name: a.name ?? "",
        attachedTo: a.attachedToRef,
        // BPMN's default for cancelActivity is true.
        interrupting: a.cancelActivity !== "false",
      });
      current.nodes.set(a.id, {
        id: a.id,
        kind: "boundaryEvent",
        name: a.name ?? "",
      });
      continue;
    }
    if (
      name === "startEvent" ||
      name === "endEvent" ||
      PASSTHROUGH.has(name) ||
      XOR_GATEWAYS.has(name) ||
      AND_GATEWAYS.has(name)
    ) {
      current.nodes.set(a.id, { id: a.id, kind: name, name: a.name ?? "" });
    }
  }
  return { processes, refusals };
}

// ---------------------------------------------------------------------------
// BPMN -> workflow net
// ---------------------------------------------------------------------------
//
// Places are sequence flows, plus one `act:<id>` per activity that carries a
// boundary event — that place is "this activity is running", and it is what
// makes an interrupting boundary a genuine race rather than a second edge.
//
// Transitions:
//   activity, no boundary   one per incoming flow: consume it, produce every
//                           outgoing flow
//   activity + boundaries   enter (incoming -> act:), complete (act: ->
//                           outgoing), and per boundary either act: -> the
//                           boundary's outgoing (interrupting: the two arms
//                           are mutually exclusive — TWO EDGES, ONE TOKEN) or
//                           act: -> act: + outgoing (non-interrupting)
//   parallel gateway        consume EVERY incoming, produce EVERY outgoing
//   exclusive gateway       one per (incoming, outgoing) pair
//   end event               consume incoming, produce nothing
//
// The parallel-gateway rule is the whole point. Nothing else in BPMN can wait.

function buildNet(proc) {
  const problems = [];
  const inc = new Map(); // node id -> [flow]
  const out = new Map();
  for (const f of proc.flows) {
    if (!proc.nodes.has(f.source))
      problems.push(
        `sequence flow ${f.id}: sourceRef ${f.source} is not a flow node`,
      );
    if (!proc.nodes.has(f.target))
      problems.push(
        `sequence flow ${f.id}: targetRef ${f.target} is not a flow node`,
      );
    (out.get(f.source) ?? out.set(f.source, []).get(f.source)).push(f);
    (inc.get(f.target) ?? inc.set(f.target, []).get(f.target)).push(f);
  }
  const incoming = (id) => inc.get(id) ?? [];
  const outgoing = (id) => out.get(id) ?? [];

  const attached = new Map(); // activity id -> [boundary]
  for (const b of proc.boundaries) {
    if (!proc.nodes.has(b.attachedTo)) {
      problems.push(
        `boundary event ${b.id}: attachedToRef ${b.attachedTo} is not a flow node`,
      );
      continue;
    }
    if (!attached.has(b.attachedTo)) attached.set(b.attachedTo, []);
    attached.get(b.attachedTo).push(b);
  }

  const P = (f) => `flow:${f.id}`;
  const A = (id) => `act:${id}`;
  const transitions = []; // { id, node, label, consume: [], produce: [] }
  const initial = new Map();
  const starts = [];

  for (const node of proc.nodes.values()) {
    const id = node.id;
    const ins = incoming(id);
    const outs = outgoing(id);
    const bnds = attached.get(id) ?? [];

    if (node.kind === "boundaryEvent") continue; // handled with its activity

    if (node.kind === "startEvent") {
      if (ins.length === 0) {
        starts.push(node);
        for (const f of outs) initial.set(P(f), (initial.get(P(f)) ?? 0) + 1);
        continue;
      }
      // A start event with an incoming flow is malformed; play it as a relay
      // so the rest of the report still means something.
      problems.push(`start event ${id} has an incoming sequence flow`);
    }

    if (node.kind === "endEvent") {
      if (outs.length > 0)
        problems.push(`end event ${id} has an outgoing sequence flow`);
      for (const f of ins)
        transitions.push({
          id: `${id}@${f.id}`,
          node: id,
          label: `${describe(node)} (consume ${f.id})`,
          consume: [P(f)],
          produce: [],
        });
      if (ins.length === 0)
        problems.push(`end event ${id} is unreachable: no incoming flow`);
      continue;
    }

    if (AND_GATEWAYS.has(node.kind)) {
      if (ins.length === 0) {
        problems.push(`parallel gateway ${id} has no incoming flow`);
        continue;
      }
      transitions.push({
        id,
        node: id,
        label: describe(node),
        consume: ins.map(P),
        produce: outs.map(P),
      });
      continue;
    }

    if (XOR_GATEWAYS.has(node.kind)) {
      if (ins.length === 0) {
        problems.push(`exclusive gateway ${id} has no incoming flow`);
        continue;
      }
      if (outs.length === 0)
        problems.push(`exclusive gateway ${id} has no outgoing flow`);
      for (const i of ins)
        for (const o of outs)
          transitions.push({
            id: `${id}@${i.id}->${o.id}`,
            node: id,
            label: `${describe(node)} (${i.id} -> ${o.id})`,
            consume: [P(i)],
            produce: [P(o)],
          });
      continue;
    }

    // Activity or intermediate event.
    if (ins.length === 0 && node.kind !== "startEvent")
      problems.push(
        `${node.kind} ${id} has no incoming flow: nothing can start it`,
      );
    if (outs.length === 0 && bnds.length === 0)
      problems.push(`${node.kind} ${id} has no outgoing flow (implicit end)`);

    if (bnds.length === 0) {
      for (const f of ins)
        transitions.push({
          id: `${id}@${f.id}`,
          node: id,
          label: `${describe(node)} (in ${f.id})`,
          consume: [P(f)],
          produce: outs.map(P),
        });
      if (node.kind === "startEvent" && ins.length === 0)
        /* already seeded above */ void 0;
      continue;
    }

    for (const f of ins)
      transitions.push({
        id: `${id}:enter@${f.id}`,
        node: id,
        label: `start ${describe(node)}`,
        consume: [P(f)],
        produce: [A(id)],
      });
    if (node.kind === "startEvent" && ins.length === 0) initial.set(A(id), 1);
    transitions.push({
      id: `${id}:complete`,
      node: id,
      label: `complete ${describe(node)}`,
      consume: [A(id)],
      produce: outs.map(P),
    });
    for (const b of bnds) {
      const bOuts = outgoing(b.id);
      if (bOuts.length === 0)
        problems.push(`boundary event ${b.id} has no outgoing flow`);
      transitions.push({
        id: `${b.id}:fire`,
        node: b.id,
        label: `${b.interrupting ? "interrupt" : "trigger"} ${describe(node)} via boundary ${b.id}${b.name ? ` "${b.name}"` : ""}`,
        consume: [A(id)],
        produce: b.interrupting ? bOuts.map(P) : [A(id), ...bOuts.map(P)],
      });
    }
  }

  if (starts.length === 0) problems.push("process has no start event");
  return {
    transitions,
    initial,
    starts,
    problems,
    incoming,
    outgoing,
    attached,
  };
}

function describe(node) {
  return node.name ? `${node.id} "${node.name}"` : node.id;
}

// ---------------------------------------------------------------------------
// The token game
// ---------------------------------------------------------------------------

function markingKey(m) {
  const parts = [];
  for (const [p, c] of m) if (c > 0) parts.push(c === 1 ? p : `${p}*${c}`);
  return parts.sort().join("|");
}

function explore(net) {
  const t0 = markingKey(net.initial);
  const states = new Map(); // key -> { marking, from, via }
  states.set(t0, { marking: net.initial, from: null, via: null });
  const preds = new Map([[t0, []]]);
  const succCount = new Map();
  const fired = new Set(); // transition ids
  const firedNodes = new Set();
  let peak = 0;
  let unsafePlaces = new Set();
  let overflowed = false;
  const queue = [t0];

  while (queue.length) {
    const key = queue.shift();
    const { marking } = states.get(key);
    let total = 0;
    for (const c of marking.values()) total += c;
    if (total > peak) peak = total;

    let enabled = 0;
    for (const t of net.transitions) {
      let ok = true;
      for (const p of t.consume)
        if ((marking.get(p) ?? 0) < 1) {
          ok = false;
          break;
        }
      if (!ok) continue;
      enabled++;
      fired.add(t.id);
      firedNodes.add(t.node);

      const next = new Map(marking);
      for (const p of t.consume) next.set(p, next.get(p) - 1);
      for (const p of t.produce) {
        const c = (next.get(p) ?? 0) + 1;
        if (c > 1) unsafePlaces.add(p);
        if (c > MAX_TOKENS_PER_PLACE) overflowed = true;
        next.set(p, c);
      }
      if (overflowed) break;
      const nk = markingKey(next);
      if (!preds.has(nk)) preds.set(nk, []);
      preds.get(nk).push(key);
      if (!states.has(nk)) {
        if (states.size >= MAX_STATES) {
          overflowed = true;
          continue;
        }
        states.set(nk, { marking: next, from: key, via: t.label });
        queue.push(nk);
      }
    }
    succCount.set(key, enabled);
    if (overflowed) break;
  }

  // Which markings can still reach "every token consumed"?
  const canComplete = new Set();
  if (states.has("")) {
    const back = [""];
    canComplete.add("");
    while (back.length) {
      const k = back.pop();
      for (const p of preds.get(k) ?? [])
        if (!canComplete.has(p)) {
          canComplete.add(p);
          back.push(p);
        }
    }
  }

  const deadlocks = [];
  const stuck = [];
  for (const [k] of states) {
    if (succCount.get(k) === 0 && k !== "") deadlocks.push(k);
    if (!canComplete.has(k)) stuck.push(k);
  }
  return {
    states,
    preds,
    fired,
    firedNodes,
    peak,
    unsafePlaces,
    overflowed,
    deadlocks,
    stuck,
    completable: states.has(""),
  };
}

function traceTo(states, key) {
  const steps = [];
  let k = key;
  while (k !== null && states.get(k)?.via) {
    steps.push(states.get(k).via);
    k = states.get(k).from;
  }
  return steps.reverse();
}

// Say WHY a marking is stuck: for each stranded token, which transitions want
// it and what else they are still waiting for.
function explainStuck(net, marking) {
  const lines = [];
  for (const [place, count] of marking) {
    if (count < 1) continue;
    lines.push(`token on ${place}${count > 1 ? ` (x${count})` : ""}`);
    for (const t of net.transitions) {
      if (!t.consume.includes(place)) continue;
      const missing = t.consume.filter((p) => (marking.get(p) ?? 0) < 1);
      if (missing.length)
        lines.push(
          `    blocks ${t.label} — still waiting on ${missing.join(", ")}`,
        );
    }
  }
  return lines;
}

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------

const files = process.argv.slice(2).filter((a) => !a.startsWith("-"));
const verbose = process.argv.includes("--verbose");
if (files.length === 0) {
  console.error(
    "usage: node etc/check-bpmn-soundness.mjs FILE.bpmn [FILE.bpmn ...] [--verbose]",
  );
  process.exit(2);
}

let worst = 0;
for (const file of files) {
  let parsed;
  try {
    parsed = readBpmn(readFileSync(file, "utf8"));
  } catch (err) {
    console.error(`${file}: PARSE ERROR ${err.message}`);
    worst = Math.max(worst, 2);
    continue;
  }
  if (parsed.refusals.length) {
    console.error(`${file}: UNSUPPORTED — NOT CHECKED`);
    for (const r of parsed.refusals) console.error(`  - ${r}`);
    worst = Math.max(worst, 3);
    continue;
  }
  if (parsed.processes.length === 0) {
    console.error(
      `${file}: UNSUPPORTED — NOT CHECKED: no <process> element found`,
    );
    worst = Math.max(worst, 3);
    continue;
  }

  for (const proc of parsed.processes) {
    const label = `${file} [${proc.name || proc.id}]`;
    const net = buildNet(proc);
    if (net.starts.length > 1) {
      console.error(
        `${label}: UNSUPPORTED — NOT CHECKED: ${net.starts.length} start events; ` +
          "each starts its own instance and this checker plays one",
      );
      worst = Math.max(worst, 3);
      continue;
    }
    if (net.starts.length === 0) {
      console.error(
        `${label}: UNSUPPORTED — NOT CHECKED: no start event to put a token on`,
      );
      worst = Math.max(worst, 3);
      continue;
    }

    const r = explore(net);
    if (r.overflowed) {
      console.error(
        `${label}: UNBOUNDED or TOO LARGE — NOT CHECKED: exceeded ` +
          `${MAX_TOKENS_PER_PLACE} tokens on a place or ${MAX_STATES} markings. ` +
          "An unbounded net is itself a defect; a large one needs a real model checker.",
      );
      worst = Math.max(worst, 3);
      continue;
    }

    const deadNodes = [...proc.nodes.values()].filter(
      (n) => !r.firedNodes.has(n.id) && n.kind !== "startEvent",
    );
    const doomed = r.stuck.filter((k) => !r.deadlocks.includes(k));

    const results = [
      ["S1 option to complete", r.completable && r.stuck.length === 0],
      ["S2 no deadlock", r.deadlocks.length === 0],
      ["S3 no dead flow node", deadNodes.length === 0],
      ["S4 safe (1-bounded)", r.unsafePlaces.size === 0],
    ];
    const sound = results.every(([, ok]) => ok) && net.problems.length === 0;

    console.log(`${label}: ${sound ? "SOUND" : "UNSOUND"}`);
    for (const [name, ok] of results)
      console.log(`  ${ok ? "PASS" : "FAIL"}  ${name}`);
    console.log(
      `  info  ${r.states.size} reachable markings, peak ${r.peak} concurrent token(s), ` +
        `${net.transitions.length} net transitions`,
    );

    for (const p of net.problems) console.log(`  STRUCTURE  ${p}`);

    if (r.deadlocks.length) {
      console.log(
        `  ${r.deadlocks.length} deadlocked marking(s). Shortest witness:`,
      );
      const shortest = r.deadlocks
        .map((k) => [k, traceTo(r.states, k)])
        .sort((a, b) => a[1].length - b[1].length)[0];
      for (const [i, step] of shortest[1].entries())
        console.log(`      ${i + 1}. ${step}`);
      console.log(`    stuck here, nothing is enabled:`);
      for (const l of explainStuck(net, r.states.get(shortest[0]).marking))
        console.log(`      ${l}`);
      if (verbose)
        for (const k of r.deadlocks)
          console.log(`    deadlock marking: ${k || "(empty)"}`);
    }
    if (doomed.length)
      console.log(
        `  ${doomed.length} further marking(s) can still move but have no path to completion left`,
      );
    if (!r.completable)
      console.log(
        `  completion is unreachable from the start: no run consumes every token`,
      );
    for (const n of deadNodes)
      console.log(`  DEAD  ${describe(n)} (${n.kind}) can never fire`);
    for (const p of r.unsafePlaces)
      console.log(`  UNSAFE  ${p} can hold more than one token`);

    if (!sound) worst = Math.max(worst, 1);
  }
}
process.exit(worst);
