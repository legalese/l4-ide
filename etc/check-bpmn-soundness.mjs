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
// Alongside those, and reported as `STRUCTURE`, are the well-formedness rules
// that make the token game meaningful in the first place: a dangling
// sourceRef/targetRef, a start event with an incoming flow, an end event with an
// outgoing one, a node nothing can start — and a gateway whose declared
// `gatewayDirection` contradicts its own edges, which is schema-valid, invisible
// to bpmn-moddle, and shipped once. See `buildNet`. A STRUCTURE finding makes
// the file UNSOUND, because a file that lies about its own shape is not one any
// verdict should be read off.
//
// A PARTIAL IMPLEMENTATION THAT TURNS A REFUSAL INTO A WRONG ANSWER IS A
// REGRESSION, even though it is strictly more done — and "more done" is what
// makes it tempting to ship. This file has the instance: the reader learned to
// nest one commit before `expandScopes` existed, and in between, a file with a
// sub-process stopped saying "NOT CHECKED: this checker plays one process only"
// and started saying "UNBOUNDED or TOO LARGE", which is false and tells a
// reader nothing they can act on. The refusal was restored and the expansion
// landed whole. If you are part-way through teaching this checker a new
// construct, leave the refusal standing until the new path is complete.
//
// PROPER COMPLETION IS DELIBERATELY NOT AN ERROR HERE. A classic WF-net demands
// exactly one token in one sink; BPMN instead completes when every token has
// been consumed, and consuming several at several end events is legal. The
// exporter emits precisely that shape on purpose — a `RAND` whose branches
// cannot be joined is drawn as a fork with no join and reported as `P-NOJOIN`
// (see jl4/examples/bpmn/README.md). Flagging it would be flagging the design.
// Peak concurrent tokens is reported as information instead.
//
// AN ERROR OR TERMINATE END EVENT CLEARS EVERY TOKEN. An uncaught error at the
// top level ends the process instance; it does not consume one token and leave
// its siblings running. The exporter says the same thing in its own words —
// `P-NOJOIN` in jl4/examples/bpmn/expected/offering.fidelity.txt reads "a branch
// here can reach BREACH, whose error end abandons its siblings rather than
// waiting for them" — and jBPM confirms it by ABORTING the instance the moment
// `offering.bpmn`'s BREACH fires, three branches still unrun.
//
// An earlier version of this file modelled every end event as a plain one-token
// sink, which was wrong in the *conservative* direction: terminate-as-sink can
// only leave extra tokens stranded, so it never turned an unsound diagram sound.
// It would, though, have called the first diagram that put a joined branch
// beside a BREACH branch UNSOUND for a defect in this checker rather than in the
// diagram — and `P-NOJOIN` exists precisely to approach that shape. Modelled
// properly now, and reported: because completion can then be reached by
// terminating, the report says how many markings can complete ONLY that way.
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
  // A callActivity is atomic HERE, and a subProcess is refused, which looks
  // inconsistent until you look at the reader. The asymmetry is not about token
  // scope — both return to their single outgoing flow — it is that this reader
  // is FLAT. A `<subProcess>`'s children live in the same document, so its inner
  // start event and tasks would be scanned straight into the parent process's
  // node map and played as if they were siblings. A callActivity's callee is a
  // different document this checker never opens, so treating the call as one
  // opaque step is exactly right. The exporter emits neither today.
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
  let current = null; // the CONTAINER being filled: a process, or a sub-process scope
  let inDiagram = 0;
  let openEnd = null; // the <endEvent> currently open, if any

  // This reader used to be flat, and `subProcess` was refused because of it: a
  // sub-process's children live in the same document, so they would be scanned
  // straight into the parent's node map and played as siblings. It now keeps a
  // stack of containers instead, so a scope's children are its own.
  //
  // `scopes` is the container stack; `current` is its top. `activities` is the
  // stack of activity elements currently open, so that a
  // <multiInstanceLoopCharacteristics> can be recorded on the activity that
  // encloses it — which is the parent element, not the container.
  const scopes = [];
  const activities = [];

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
      if (popped === "process") {
        scopes.pop();
        current = null;
      }
      if (popped === "subProcess") {
        // Read here, expanded by `expandScopes`, which is where what can and
        // cannot be played is decided. Nothing is refused at read time.
        scopes.pop();
        current = scopes[scopes.length - 1] ?? null;
        activities.pop();
      }
      if (ACTIVITIES.has(popped)) activities.pop();
      if (popped === "endEvent") openEnd = null;
      continue;
    }
    if (!isLeaf) stack.push(name);

    const a = attrsOf(attrChunk);

    // An uncaught error end, and a terminate end, both END THE INSTANCE: every
    // remaining token is discarded rather than left running. Recorded on the end
    // event that encloses the definition.
    if (
      openEnd &&
      (name === "errorEventDefinition" || name === "terminateEventDefinition")
    ) {
      openEnd.terminating = true;
      openEnd.terminatingVia = name;
      continue;
    }

    // An ESCALATION end does neither: it throws to a catcher, and a
    // non-interrupting boundary on the enclosing scope catches it without
    // cancelling anything. That is the only construct BPMN has for "this member
    // breached and the others carry on", so it is read rather than treated as a
    // plain end. See `expandScopes`.
    if (openEnd && name === "escalationEventDefinition") {
      openEnd.throwsEscalation = true;
      continue;
    }

    if (name === "process") {
      current = {
        id: a.id ?? `process_${processes.length}`,
        name: a.name ?? a.id ?? "",
        nodes: new Map(), // id -> { id, kind, name, boundaries: [] }
        flows: [], // { id, source, target }
        boundaries: [], // { id, name, attachedTo, interrupting }
      };
      processes.push(current);
      scopes.push(current);
      continue;
    }
    if (!current) continue; // laneSet inside collaboration, extensions, etc.

    // Object.hasOwn, not `in`: `in` walks Object.prototype, so an element named
    // `constructor` or `toString` would "match" and yield a function body as its
    // refusal reason.
    // A sub-process is a node in its parent AND a container of its own. Its
    // boundary events are siblings in the parent (they attach to it from
    // outside), so only sequence flows and flow nodes go inward.
    if (name === "subProcess") {
      const scope = {
        id: a.id,
        name: a.name ?? "",
        nodes: new Map(),
        flows: [],
        boundaries: [],
      };
      const node = {
        id: a.id,
        kind: "subProcess",
        name: a.name ?? "",
        scope,
      };
      current.nodes.set(a.id, node);
      if (isLeaf) {
        // <subProcess/> with no children: an empty scope, which is legal and
        // behaves as a pass-through. Nothing to push.
        continue;
      }
      scopes.push(scope);
      current = scope;
      activities.push(node);
      continue;
    }

    // <multiInstanceLoopCharacteristics> belongs to the activity that ENCLOSES
    // it, which is the open element rather than the open container: on a task
    // there is no container at all. `isSequential` defaults to true per the
    // XSD, which is the opposite of what the exporter writes, so it is read
    // rather than assumed.
    if (name === "multiInstanceLoopCharacteristics") {
      const owner = activities[activities.length - 1];
      if (owner)
        owner.multiInstance = {
          isSequential: a.isSequential !== "false",
          completionCondition: false,
        };
      continue;
    }
    if (name === "completionCondition") {
      const owner = activities[activities.length - 1];
      if (owner?.multiInstance) owner.multiInstance.completionCondition = true;
      continue;
    }

    if (Object.hasOwn(REFUSED, name)) {
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
      const node = { id: a.id, kind: name, name: a.name ?? "" };
      // Kept only for gateways, and only so `buildNet` can hold the file to its
      // own claim. Nothing in the token game reads it.
      if (XOR_GATEWAYS.has(name) || AND_GATEWAYS.has(name))
        node.gatewayDirection = a.gatewayDirection;
      current.nodes.set(a.id, node);
      if (name === "endEvent" && !isLeaf) openEnd = node;
      // An open activity can enclose a <multiInstanceLoopCharacteristics>.
      if (ACTIVITIES.has(name) && !isLeaf) activities.push(node);
    }
  }
  return { processes, refusals };
}

// ---------------------------------------------------------------------------
// Sub-process scopes -> a flat net, by COPY-EXPANSION
// ---------------------------------------------------------------------------
//
// A multi-instance scope is played by building n STRUCTURAL COPIES of its
// interior, spliced between a synthetic parallel split and join. The whole
// design rests on ONE INVARIANT:
//
//   NO COPY SHARES A PLACE WITH ANY OTHER COPY.
//
// Two results follow, and they are corollaries rather than separate rules:
//
//   * THE EXPANSION IS A P/T NET. A transition needs a fixed input set. A
//     cancel on the SCOPE would have to consume the running places of whichever
//     copies happen to be live, which is not fixed — so it is not expressible
//     here, and it is refused rather than approximated. ("First token out wins"
//     would strand the other copies and report UNSOUND for an artifact of the
//     model.)
//   * n = 2 IS A SOUND CUTOFF. The expansion is a symmetric product, so a
//     structural property that holds of two independent copies holds of n by
//     symmetry. n = 3 is not "more thorough": it buys only more interleavings
//     of the same structures, at k^n for an interior of k states. It could only
//     catch a defect that depends on a specific count >= 3, and the exporter
//     emits no such construct.
//
// THAT CUTOFF HAS AN EXPIRY. `ONCE SOME m OF … HAVE` (EVERY-EACH-QUANTIFIER-SPEC
// phase 3) fires on m tokens in a SHARED ACCUMULATOR: expressible in P/T, but
// the accumulator is not 1-safe and the copies are no longer independent, so it
// breaks the invariant and the cutoff at the same moment. The MODEL needs
// revisiting then, not just the constant. `ONCE sum OF amount AT LEAST rent`
// accumulates an arbitrary quantity that is not a token count at any n; that one
// belongs in REFUSED when it lands.
//
// WHY BOTH n = 0 AND n = 2, AND NEVER n = 1 ALONE:
//
//   n = 0  checks the OUTSIDE of the scope — with no copies the interior is
//          empty, so the question is what the process does when the cast is
//          empty. Measured in the evaluator, that is where the two join lines
//          diverge most: a barrier fires its continuation ("all zero of them
//          have acted" is vacuously true) and a fork fires nothing.
//   n = 1  would make a fork and a barrier indistinguishable — one copy, one
//          continuation, either way. A gate exploring only n = 1 would go green
//          on a drawing that had lost its join, which is the defect
//          legalese/l4-ide#395 fixed, reproduced inside the checker that exists
//          to catch it.
//   n = 2  is the least n that tells them apart.
//
// WHAT "SOUND AT 0 INSTANCES" DOES NOT MEAN, because the two claims want to
// collapse and they have different evidence and different owners. Soundness
// here is about TOKEN FLOW: the net completes, nothing strands, nothing
// deadlocks. Whether an empty cast is drawn CORRECTLY is a different claim
// entirely, and it is settled by the shape rather than by this gate — the
// fork's continuation sits inside the instance, so zero instances give zero
// continuations, while a barrier's sits outside and still fires once. That is a
// question about what the diagram MEANS, answered in the exporter and in the
// quantifier spec, and this checker cannot see it. "We explored n = 0" must
// never be read as "the empty-cast case is verified".
const INSTANCE_COUNTS = [0, 2];

// Does this end event throw rather than end? An escalation end inside a scope
// is caught by a non-interrupting boundary on the scope, which is how BPMN says
// "this member breached; the others carry on".
const isThrow = (node) => node.kind === "endEvent" && node.throwsEscalation;

// Expand every sub-process scope in `proc` into `n` copies of its interior.
// Returns a flat process plus the copy -> source id map every finding is
// reported through, because `Task_0#1` names nothing a reader can find in the
// file.
function expandScopes(proc, n) {
  const refusals = [];
  const notes = []; // said out loud, but not a defect
  const sourceOf = new Map(); // copy id -> source id
  const nodes = new Map();
  const flows = [];
  const boundaries = [];

  const scopeNodes = [...proc.nodes.values()].filter(
    (x) => x.kind === "subProcess",
  );
  if (scopeNodes.length === 0)
    return {
      proc,
      refusals,
      notes,
      sourceOf,
      fanIn: new Set(),
      expanded: false,
    };

  const scopeIds = new Set(scopeNodes.map((x) => x.id));

  // Boundaries on a scope: only the non-interrupting kind can be played, and it
  // is played by routing the interior's throws straight to its outgoing flow.
  const scopeBoundary = new Map(); // scope id -> boundary
  for (const b of proc.boundaries) {
    if (!scopeIds.has(b.attachedTo)) {
      boundaries.push(b);
      continue;
    }
    if (b.interrupting) {
      refusals.push(
        `boundaryEvent ${b.id}: an INTERRUPTING boundary on sub-process ` +
          `${b.attachedTo} cancels whichever instances are live, which is not a ` +
          `fixed set of places and so is not expressible as a P/T transition. ` +
          `Model the deadline inside the instance instead, where each copy ` +
          `carries its own race.`,
      );
      continue;
    }
    scopeBoundary.set(b.attachedTo, b);
  }

  // Everything that is not a scope, and not a boundary on one, survives as is.
  const onAScope = new Set(
    proc.boundaries.filter((b) => scopeIds.has(b.attachedTo)).map((b) => b.id),
  );
  for (const x of proc.nodes.values()) {
    if (x.kind === "subProcess") continue;
    // A boundary on a scope is not an ordinary node here: at n > 0 it is
    // rebuilt as the relay the interior's throws flow into, and at n = 0 it is
    // dropped with the region behind it.
    if (onAScope.has(x.id)) continue;
    nodes.set(x.id, x);
  }

  const rewritten = new Map(); // scope id -> { split, join }
  const droppedSources = new Set(); // nodes not built at this count
  for (const sc of scopeNodes) {
    const mi = sc.multiInstance;
    if (mi?.isSequential) {
      refusals.push(
        `subProcess ${sc.id}: a SEQUENTIAL multi-instance scope is a loop, not ` +
          `a parallel expansion; its token game is not this one`,
      );
      continue;
    }
    // THE EXECUTABLE FORM OF A DESIGN DECISION. A completionCondition says the
    // scope completes before its instances do — which is right for a
    // prohibition drawn as a multi-instance TASK, where there is no interior
    // for the rule to govern, and wrong for a scope, where the instances left
    // running when it fires would have to be cancelled: the same
    // not-a-fixed-set-of-places problem as an interrupting boundary. The
    // exporter is not supposed to put one here; this is the guard that says so
    // where the violation would occur rather than in a comment somewhere else.
    if (mi?.completionCondition) {
      refusals.push(
        `subProcess ${sc.id}: a completionCondition on a SCOPE would complete it ` +
          `while instances are still running, and cancelling those is not a ` +
          `fixed set of places. A completion rule belongs on a multi-instance ` +
          `TASK, which has no interior for it to govern.`,
      );
      continue;
    }
    if ([...sc.scope.nodes.values()].some((x) => x.kind === "subProcess")) {
      refusals.push(
        `subProcess ${sc.id}: a nested scope; this expansion is one level deep`,
      );
      continue;
    }

    const split = `${sc.id}:split`;
    const join = `${sc.id}:join`;
    nodes.set(split, {
      id: split,
      kind: "parallelGateway",
      name: `${sc.name || sc.id} (split)`,
    });
    nodes.set(join, {
      id: join,
      kind: "parallelGateway",
      name: `${sc.name || sc.id} (join)`,
    });
    sourceOf.set(split, sc.id);
    sourceOf.set(join, sc.id);
    rewritten.set(sc.id, { split, join });

    // A non-interrupting boundary becomes an ordinary relay node: the interior's
    // throws flow into it and out along its own edges, and the copies that did
    // not throw carry on to the join. That IS the non-interrupting semantics.
    // ...but only when there are instances to throw. At n = 0 nothing inside
    // can escalate, so a relay here would be an orphan with no incoming flow —
    // a STRUCTURE finding about the checker's own construction rather than
    // about the file. It is dropped instead, along with its outgoing edges, and
    // whatever they led to is simply unreachable at this count. S3 is asked
    // across counts, so a breach end that only fires when somebody breaches is
    // not reported as dead.
    const b = n > 0 ? scopeBoundary.get(sc.id) : undefined;
    if (b) {
      nodes.set(b.id, {
        id: b.id,
        kind: "intermediateCatchEvent",
        name: b.name,
      });
      sourceOf.set(b.id, b.id);
    }
    if (n === 0)
      for (const bb of scopeBoundary.values()) droppedSources.add(bb.id);

    const inner = sc.scope;
    const innerStarts = [...inner.nodes.values()].filter(
      (x) => x.kind === "startEvent",
    );
    const innerEnds = [...inner.nodes.values()].filter(
      (x) => x.kind === "endEvent",
    );
    const throwing = innerEnds.filter(isThrow);
    // Asked of the FILE, not of this count: whether a throw has a catcher is a
    // property of the diagram, and at n = 0 the relay is deliberately not built.
    if (throwing.length && !scopeBoundary.has(sc.id)) {
      refusals.push(
        `subProcess ${sc.id}: an escalation end event inside it has nothing to ` +
          `catch it — a non-interrupting boundary on the scope is what makes ` +
          `one member's breach visible without cancelling the others`,
      );
      continue;
    }

    if (n === 0) {
      // An empty collection completes the activity at once and takes its
      // outgoing flow. Nothing inside runs — which is the whole point of the
      // n = 0 pass.
      flows.push({ id: `${sc.id}:empty`, source: split, target: join });
    }
    for (let i = 0; i < n; i++) {
      const cp = (id) => `${id}#${i}`;
      // One "this instance is finished" gateway per COPY, XOR, merging every
      // path that reaches a normal end inside it.
      //
      // Without it the join waits on one token per (instance x arrival flow),
      // and an interior with two ways to reach its end — the act completing,
      // or its deadline expiring — deadlocks the moment every instance takes
      // the same one of them. Measured on the emitter's own `modals-may-fork`
      // golden: at n = 2, both directors let the permission lapse, both
      // boundary flows carry a token, and the join sits waiting forever on the
      // two flows out of the task nobody performed. The file was correct; the
      // model was counting arrivals where the semantics count instances.
      //
      // XOR is right here because a sub-process instance completes when it has
      // no tokens left, and these copies hold exactly one: an interrupting
      // boundary makes "performed" and "expired" exclusive. An interior that
      // really does run two tokens concurrently has to rejoin them at a
      // parallel gateway before its end event, and if it does not, that is an
      // uncontrolled merge S4 reports on its own.
      const done = `${sc.id}:done#${i}`;
      nodes.set(done, {
        id: done,
        kind: "exclusiveGateway",
        name: `${sc.name || sc.id} (instance ${i} done)`,
      });
      sourceOf.set(done, sc.id);
      flows.push({ id: `${sc.id}:done#${i}->join`, source: done, target: join });
      for (const x of inner.nodes.values()) {
        if (x.kind === "startEvent" || x.kind === "endEvent") continue;
        nodes.set(cp(x.id), { ...x, id: cp(x.id), name: x.name });
        sourceOf.set(cp(x.id), x.id);
      }
      for (const bb of inner.boundaries) {
        boundaries.push({
          ...bb,
          id: cp(bb.id),
          attachedTo: cp(bb.attachedTo),
        });
        nodes.set(cp(bb.id), {
          id: cp(bb.id),
          kind: "boundaryEvent",
          name: bb.name,
        });
        sourceOf.set(cp(bb.id), bb.id);
      }
      // A THROWING end event is TWO facts, and the model needs both.
      //
      // It throws the escalation, which the non-interrupting boundary catches;
      // and it consumes this path's token, which — since a copy holds exactly
      // one — means the instance is FINISHED. BPMN completes a sub-process
      // instance when it has no tokens left, and an escalation end leaves none.
      //
      // Routing the throw straight at the catcher, as this did until
      // 2026-09-19, recorded only the first: a copy that threw never signalled
      // its own `done`, so the scope's join waited on it forever. Measured on
      // the exporter's tenancy-fork golden with its breach end made
      // non-terminating — 2 deadlocked markings, S1 and S2 red, on a correct
      // file. It was invisible while the breach end was an ERROR end, because
      // reaching one discards every remaining token and so rescued exactly
      // those markings: the file scored SOUND, and 39 of its 67 markings could
      // "complete" ONLY by terminating. A gate passing for that reason is not
      // passing.
      //
      // So the throw is a node of its own with two outgoing flows. An ordinary
      // (non-gateway) node produces EVERY outgoing flow from one incoming
      // token, which is BPMN's uncontrolled parallel split and is what makes
      // these two facts simultaneous rather than a choice. 1-safety is
      // unaffected: the two targets are different places, each holding one.
      for (const e of innerEnds.filter(isThrow)) {
        if (!b) continue; // n = 0, or refused above for want of a catcher
        const th = cp(`${e.id}:throw`);
        nodes.set(th, {
          id: th,
          kind: "intermediateThrowEvent",
          name: e.name,
        });
        sourceOf.set(th, e.id);
        flows.push({ id: `${th}->catch`, source: th, target: b.id });
        flows.push({ id: `${th}->done`, source: th, target: done });
      }

      const startIds = new Set(innerStarts.map((x) => x.id));
      const endOf = new Map(innerEnds.map((x) => [x.id, x]));
      for (const f of inner.flows) {
        const src = startIds.has(f.source) ? split : cp(f.source);
        let tgt;
        if (endOf.has(f.target)) {
          const e = endOf.get(f.target);
          tgt = isThrow(e) ? cp(`${e.id}:throw`) : done;
        } else {
          tgt = cp(f.target);
        }
        flows.push({ id: cp(f.id), source: src, target: tgt });
      }
    }
  }

  // Kept for n = 0, where no copy exists to reach the join at all.
  //
  // It used to carry more weight than that, and wrongly: it read "if NO
  // interior path ends normally — every one of them throws — then nothing
  // reaches the join". That was a workaround for the defect fixed above,
  // treating the all-throw case as special instead of noticing that a throwing
  // instance still finishes. The mixed case — some copies throw, some do not —
  // fell through it and deadlocked. A rule that handles the extreme and not the
  // general one is a sign the semantics are wrong, not the boundary condition.
  for (const [scId, { join }] of rewritten) {
    if (flows.some((f) => f.target === join)) continue;
    notes.push(
      `subProcess ${scId}: no interior path ends normally at ${n} instance(s), ` +
        `so the scope can only be left by escalation — nothing downstream of ` +
        `its ordinary completion is reachable`,
    );
    droppedSources.add(join);
    nodes.delete(join);
  }

  // AT n = 0 THE ESCALATION REGION CANNOT BE ENTERED, so it is not part of the
  // model at this count — and dropping only its entry would leave whatever it
  // led to with no incoming flow, which the structure checks would report as a
  // malformed FILE. That would be a complaint about this construction rather
  // than about the diagram. So the drop is transitive: a node survives only if
  // something still reaches it.
  if (droppedSources.size) {
    for (let changed = true; changed; ) {
      changed = false;
      for (const x of [...nodes.keys()]) {
        if (droppedSources.has(x)) continue;
        // Over the REWRITTEN graph, for the same reason the flow loop below is:
        // a node fed only by a scope is fed, after expansion, by that scope's
        // join, and asking the original flows would say it is still reachable.
        const feeds = [
          ...proc.flows.map((f) => ({
            source: rewritten.get(f.source)?.join ?? f.source,
            target: rewritten.get(f.target)?.split ?? f.target,
          })),
          ...flows,
        ].filter((f) => f.target === x);
        if (feeds.length === 0) continue; // a start event, or already isolated
        if (feeds.every((f) => droppedSources.has(f.source))) {
          droppedSources.add(x);
          nodes.delete(x);
          changed = true;
        }
      }
    }
  }

  for (const f of proc.flows) {
    const toScope = rewritten.get(f.target);
    const fromScope = rewritten.get(f.source);
    // Asked of the REWRITTEN endpoints: a flow out of a scope leaves from the
    // synthetic join, so testing the original `Sub_0` would keep an edge whose
    // source no longer exists and report it as a dangling reference in the file.
    const source = fromScope ? fromScope.join : f.source;
    const target = toScope ? toScope.split : f.target;
    if (droppedSources.has(source) || droppedSources.has(target)) continue;
    flows.push({ id: f.id, source, target });
  }

  // THE ONE PLACE COPIES ARE NOT INDEPENDENT, and it is inherent rather than a
  // modelling choice: every copy's escalation throw funnels into the SAME
  // non-interrupting boundary and leaves along its SINGLE outgoing flow. n
  // members can breach, so that flow can hold up to n tokens.
  //
  // BPMN permits it — a sequence flow is not a 1-safe place in the spec — and
  // it is what "one member breached and the others carry on" MEANS. So S4 is
  // reported as a bound on these flows instead of a failure, and nowhere else.
  // Anything DOWNSTREAM of them is not exempt: today the exporter sends the
  // catch straight to a terminating end, so there is no downstream, and if that
  // ever changes the finding should fire.
  const fanIn = new Set();
  for (const b of scopeBoundary.values())
    for (const f of flows) if (f.source === b.id) fanIn.add(`flow:${f.id}`);

  return {
    proc: { id: proc.id, name: proc.name, nodes, flows, boundaries },
    refusals,
    notes,
    sourceOf,
    fanIn,
    expanded: true,
  };
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

  // gatewayDirection is a CLAIM ABOUT THE EDGES, not a caption on a shape.
  // BPMN 2.0 §10.5.1 Table 10.100:
  //
  //   Unspecified  no constraint (and the XSD default, so an absent attribute
  //                is this and is always fine)
  //   Converging   MUST have multiple incoming, MUST NOT have multiple outgoing
  //   Diverging    MUST have multiple outgoing, MUST NOT have multiple incoming
  //   Mixed        multiple incoming AND multiple outgoing
  //
  // Nothing else in this repo looks: the XSD types the attribute as a plain
  // enumeration, so a gateway declaring the opposite of what its own sequence
  // flows say is schema-valid, and both bpmn-moddle and Xerces pass it at zero
  // warnings. It is checked here because this is the script that already knows
  // every node's real in/out arity.
  //
  // The defect this exists for shipped: regcf-reporting.bpmn declared
  // `Diverging` on a gateway with TWO incoming flows, because the exporter
  // chose the direction in a pass that ran before any edge existed and the
  // `HENCE <this rule>` renewal loop then added a second arrival. Both scripts
  // were green over it.
  for (const node of proc.nodes.values()) {
    if (!XOR_GATEWAYS.has(node.kind) && !AND_GATEWAYS.has(node.kind)) continue;
    const dir = node.gatewayDirection;
    if (dir === undefined || dir === "Unspecified") continue;
    const ni = incoming(node.id).length;
    const no = outgoing(node.id).length;
    const said = `${node.kind} ${node.id} declares gatewayDirection="${dir}" but has ${ni} incoming and ${no} outgoing sequence flow(s)`;
    if (!["Converging", "Diverging", "Mixed"].includes(dir))
      problems.push(
        `${node.kind} ${node.id} declares gatewayDirection="${dir}", which is not one of Unspecified/Converging/Diverging/Mixed`,
      );
    else if (dir === "Diverging" && ni > 1)
      problems.push(
        `${said} — Diverging must not have multiple incoming; this is Mixed`,
      );
    else if (dir === "Converging" && no > 1)
      problems.push(
        `${said} — Converging must not have multiple outgoing; this is Mixed`,
      );
    else if (dir === "Diverging" && no <= 1)
      problems.push(`${said} — Diverging requires multiple outgoing`);
    else if (dir === "Converging" && ni <= 1)
      problems.push(`${said} — Converging requires multiple incoming`);
    else if (dir === "Mixed" && !(ni > 1 && no > 1))
      problems.push(`${said} — Mixed requires multiple of both`);
  }

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
  const transitions = []; // { id, node, label, consume: [], produce: [], clears? }
  const initial = new Map();
  const starts = [];
  const terminators = []; // end events that discard every remaining token

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
      if (node.terminating) terminators.push(node);
      for (const f of ins)
        transitions.push({
          id: `${id}@${f.id}`,
          node: id,
          label: node.terminating
            ? `${describe(node)} (consume ${f.id}, TERMINATES the instance)`
            : `${describe(node)} (consume ${f.id})`,
          consume: [P(f)],
          produce: [],
          // Discards every remaining token, everywhere. See the header.
          clears: !!node.terminating,
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

    // A start event with no incoming flow was seeded and `continue`d above, so
    // anything reaching here has at least one incoming flow.
    if (bnds.length === 0) {
      for (const f of ins)
        transitions.push({
          id: `${id}@${f.id}`,
          node: id,
          label: `${describe(node)} (in ${f.id})`,
          consume: [P(f)],
          produce: outs.map(P),
        });
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
    terminators,
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
  // The same predecessor graph with the terminating end events left out. The
  // difference between the two backward closures is exactly "which markings can
  // only reach completion by aborting the instance", which is worth saying out
  // loud rather than letting a terminate silently satisfy S1.
  const predsLive = new Map([[t0, []]]);
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
      if (t.clears) {
        // An uncaught error end / terminate end ends the instance: every token
        // still in flight is discarded, not left running.
        for (const p of next.keys()) next.set(p, 0);
      } else {
        for (const p of t.produce) {
          const c = (next.get(p) ?? 0) + 1;
          if (c > 1) unsafePlaces.add(p);
          if (c > MAX_TOKENS_PER_PLACE) overflowed = true;
          next.set(p, c);
        }
      }
      if (overflowed) break;
      const nk = markingKey(next);
      if (!preds.has(nk)) preds.set(nk, []);
      preds.get(nk).push(key);
      if (!t.clears) {
        if (!predsLive.has(nk)) predsLive.set(nk, []);
        predsLive.get(nk).push(key);
      }
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
  const backwardFrom = (edges) => {
    const seen = new Set();
    if (!states.has("")) return seen;
    const back = [""];
    seen.add("");
    while (back.length) {
      const k = back.pop();
      for (const p of edges.get(k) ?? [])
        if (!seen.has(p)) {
          seen.add(p);
          back.push(p);
        }
    }
    return seen;
  };
  const canComplete = backwardFrom(preds);
  const canCompleteLive = backwardFrom(predsLive);

  const deadlocks = [];
  const stuck = [];
  let onlyViaTerminate = 0;
  for (const [k] of states) {
    if (succCount.get(k) === 0 && k !== "") deadlocks.push(k);
    if (!canComplete.has(k)) stuck.push(k);
    else if (!canCompleteLive.has(k)) onlyViaTerminate++;
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
    onlyViaTerminate,
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

  for (const proc0 of parsed.processes) {
    const label0 = `${file} [${proc0.name || proc0.id}]`;

    // A process containing a sub-process scope is played once per instance
    // count, and must be sound at EVERY one of them. A process without a scope
    // is played exactly as before — same output, same verdict — so nothing
    // about the fourteen existing goldens moves.
    const hasScope = [...proc0.nodes.values()].some(
      (x) => x.kind === "subProcess",
    );
    const counts = hasScope ? INSTANCE_COUNTS : [null];

    // S3 IS ASKED ACROSS THE COUNTS, NOT WITHIN ONE. At n = 0 a scope has no
    // copies, so everything reachable only through its interior fires zero
    // times — including, for a fork, the boundary that catches a member's
    // breach and the breach end itself. That is not a dead branch; it is what
    // an empty cast MEANS. A node is dead only if it fires in no run at any
    // count, so the fired sets are unioned here, by SOURCE id, before any
    // verdict is read off.
    const firedAnywhere = new Set();
    if (hasScope)
      for (const n of INSTANCE_COUNTS) {
        const pre = expandScopes(proc0, n);
        if (pre.refusals.length) break;
        const preNet = buildNet(pre.proc);
        if (preNet.problems.length || preNet.starts.length !== 1) break;
        const preRun = explore(preNet);
        for (const id of preRun.firedNodes)
          firedAnywhere.add(pre.sourceOf.get(id) ?? id);
      }
    for (const n of counts) {
      const ex =
        n === null
          ? { proc: proc0, refusals: [], sourceOf: new Map(), fanIn: new Set() }
          : expandScopes(proc0, n);
      if (ex.refusals.length) {
        console.error(`${label0}: UNSUPPORTED — NOT CHECKED`);
        for (const r of ex.refusals) console.error(`  - ${r}`);
        worst = Math.max(worst, 3);
        break;
      }
      const proc = ex.proc;
      // Findings name the id a reader can find in the FILE. A copy is reported
      // as its source with the copy in parentheses; `Task_0#1` alone names
      // nothing.
      const srcOf = (id) => {
        const src = ex.sourceOf.get(id);
        return src && src !== id ? `${src} (instance copy ${id})` : id;
      };
      const label = n === null ? label0 : `${label0} @ ${n} instance(s)`;
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
        (x) =>
          !r.firedNodes.has(x.id) &&
          x.kind !== "startEvent" &&
          !firedAnywhere.has(ex.sourceOf.get(x.id) ?? x.id),
      );
      const doomed = r.stuck.filter((k) => !r.deadlocks.includes(k));

      const results = [
        ["S1 option to complete", r.completable && r.stuck.length === 0],
        ["S2 no deadlock", r.deadlocks.length === 0],
        ["S3 no dead flow node", deadNodes.length === 0],
        [
          "S4 safe (1-bounded)",
          [...r.unsafePlaces].every((pl) => ex.fanIn.has(pl)),
        ],
      ];
      const sound = results.every(([, ok]) => ok) && net.problems.length === 0;

      console.log(`${label}: ${sound ? "SOUND" : "UNSOUND"}`);
      for (const [name, ok] of results)
        console.log(`  ${ok ? "PASS" : "FAIL"}  ${name}`);
      console.log(
        `  info  ${r.states.size} reachable markings, peak ${r.peak} concurrent token(s), ` +
          `${net.transitions.length} net transitions`,
      );
      // Say this out loud. Terminating end events make S1 satisfiable by aborting,
      // so a reader must be able to tell "completes" from "gives up".
      if (net.terminators.length) {
        console.log(
          `  info  ${net.terminators.length} terminating end event(s): ` +
            net.terminators.map((t) => describe(t)).join(", ") +
            " — reaching one discards every remaining token",
        );
        console.log(
          `  info  ${r.onlyViaTerminate} marking(s) can reach completion ONLY by terminating`,
        );
      }

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
      for (const note of ex.notes ?? []) console.log(`  info  ${note}`);
      for (const dn of deadNodes)
        console.log(
          `  DEAD  ${describe(dn)} (${dn.kind}) can never fire — ${srcOf(dn.id)}`,
        );
      for (const pl of r.unsafePlaces)
        if (ex.fanIn.has(pl))
          console.log(
            `  info  ${pl} can hold up to ${n} token(s) — the escalation fan-in of a ` +
              `multi-instance scope, where every instance's throw meets the one ` +
              `boundary that catches it. Bounded by the instance count, and the ` +
              `only place copies are not independent.`,
          );
        else console.log(`  UNSAFE  ${pl} can hold more than one token`);

      if (!sound) worst = Math.max(worst, 1);
    }
  }
}
process.exit(worst);
