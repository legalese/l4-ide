/**
 * viz-adapter — the P2 bridge from the LSP wire IR (`@repo/viz-expr`) into
 * ladder-core's local `IRExpr` (DESIGN §11 "Keep" — consume the existing protocol
 * as-is; TODO §A1). The two IRs are deliberately near-identical (P0 kept a local
 * mirror), so this is a mechanical, positional-identity-preserving map plus a
 * side-channel that lifts each leaf's `value` into a `ViewSpec.valuation` map.
 *
 * It also lifts each `UBoolVar`'s TYPICALLY default into a second side-channel,
 * `ViewSpec.provenance` (TODO §B): a leaf whose wire `typically` is a CONCRETE
 * boolean (true OR false) rides a rebuttable presumption and is marked `default`;
 * `null`/absent leaves the node unset (ViewSpec treats absent as `given`). The
 * wire schema is `optional(NullOr(Boolean))`, so a non-presumed atom arrives as
 * `null` — we must not read that as a default. A concrete boolean, not mere
 * presence, decides provenance; the raw boolean payload is reserved for the v2
 * weight extractor (`typicallyBridge`), so this one wire field feeds both
 * consumers.
 *
 * What this file is NOT: it does not talk to the LSP (that is A2's transport layer
 * — this operates on an already-decoded `FunDecl`).
 *
 * The three shape differences, reconciled here:
 *  1. ids — wire `IRId {id:number}` -> ladder `NodeId` (bare number). Identity is
 *     PRESERVED (A2: "atomId identity is preserved"; the same holds for node ids,
 *     which the positional `valuation`/`states`/`foldSet` keys depend on).
 *  2. names — wire `Name {unique,label}` -> ladder's flat `label:string`. The
 *     `unique` is dropped (ladder keys leaves by `atomId`, DESIGN §15.2).
 *  3. values — wire leaves carry an inline `value`; ladder leaves do not. Each
 *     `UBoolVar.value` is lifted OUT into the returned `valuation` map (keyed by
 *     node id, positional). `TrueE`/`FalseE` keep their inherent value in the
 *     kernel (`nodeValue`), so they need no valuation entry.
 *
 * `App` (DESIGN §23 / TODO §D) maps to a ladder `App` LEAF carrying its `atomId`
 * and the `fnName` label. Rendering its interior ("drawn open") is D1's job; A1
 * only needs the leaf to exist and to be eval-addressable by `atomId`.
 *
 * CALLS. A call leaf (a `UBoolVar` with `canInline`, or an `App` of a rule of the module)
 * may carry `expansion`: the callee's body with the actual arguments substituted, which the
 * server must send in the caller's atomId namespace (the contract in `viz-expr`'s
 * `UBoolVar.expansion`). jl4-lsp sends it only when a client asks: `l4.visualize`'s
 * fourth argument `{"expandCalls": true}`; the tests read a capture made that way
 * (`test/fixtures/call-expansions.json`). `opts.calls` chooses what to do with it:
 *  - `"leaf"` (the default) ignores it, so the output is exactly what it was before the
 *    field existed — every figure, golden and test that predates call panels is unchanged;
 *  - `"expand"` decodes the call as a group `{ $type: "And", id: <call id>, label: <call
 *    as written>, call: true, args: [<expansion>] }` — a call panel, foldable by its id.
 */
import type {
  FunDecl as VizFunDecl,
  IRExpr as VizIRExpr,
} from "@repo/viz-expr";
import type {
  FunDecl,
  IRExpr,
  Leaf,
  Inert,
  And,
  Or,
  Not,
  Implies,
  NodeId,
  Unique,
  UBoolValue,
  Provenance,
} from "./types.js";

/**
 * The identity index a decoded tree needs to be driven by the IDE evaluator (§E1/S1).
 *
 * `unique`/`atomId` are keyed per drawn node (`NodeId`); the inverses are PLURAL because
 * one proposition can occupy several positions — `nodesByUnique.get(u)` is every box that
 * must move when the user binds `u`. `unique`/`nodesByUnique` cover `UBoolVar` only (the
 * atoms the evaluator's `Assignment` keys on); `atomId` covers `UBoolVar` and `App` (both
 * eval-addressable, `App` via `evalApp`).
 *
 * In `calls: "expand"` mode `atomId` ALSO covers call panels: an `And` group with
 * `call: true` is indexed under its call leaf's atomId, so a folded copy of a call links to
 * every other copy. Such an entry is a GROUP, not a leaf — tell them apart by `And.call` —
 * and must not be handed to `evalApp` as though it were one.
 */
export interface DecodedIdentity {
  readonly uniqueByNode: Map<NodeId, Unique>;
  readonly nodesByUnique: Map<Unique, NodeId[]>;
  readonly atomIdByNode: Map<NodeId, string>;
  readonly nodesByAtomId: Map<string, NodeId[]>;
}

/** The result of decoding a wire `FunDecl`: the ladder tree, the valuation/provenance
 *  side-channels lifted from inline leaf fields, and the identity index (§E1/S1). Feed
 *  `valuation` straight into `defaultViewSpec({ valuation })` (or merge with live eval
 *  results, A3). */
export interface DecodedViz extends DecodedIdentity {
  readonly fn: FunDecl;
  /** Positional (keyed by node id) T/F/U lifted from `UBoolVar.value`. */
  readonly valuation: Map<NodeId, UBoolValue>;
  /** Positional (keyed by node id) provenance lifted from `UBoolVar.typically`;
   *  a node is present here as `"default"` iff its wire `typically` key was present. */
  readonly provenance: Map<NodeId, Provenance>;
  /** Positional VALUES of those presumptions — §22's `Left`. Feed straight to
   *  `ViewSpec.defaults`, which lays them under `valuation` without overwriting it. */
  readonly defaults: Map<NodeId, UBoolValue>;
}

/** Everything `convert` fills as it walks. Bundling the side-channels keeps the recursive
 *  signature to two args and makes adding a channel a one-line change, not a re-thread. */
interface Sink {
  readonly calls: CallMode;
  readonly valuation: Map<NodeId, UBoolValue>;
  readonly provenance: Map<NodeId, Provenance>;
  readonly defaults: Map<NodeId, UBoolValue>;
  readonly uniqueByNode: Map<NodeId, Unique>;
  readonly atomIdByNode: Map<NodeId, string>;
  /** Node ids already decoded (expand mode only — see `convert`). */
  readonly seen: Set<NodeId>;
}

const emptySink = (opts: FromVizOpts): Sink => ({
  calls: opts.calls ?? "leaf",
  valuation: new Map(),
  provenance: new Map(),
  defaults: new Map(),
  uniqueByNode: new Map(),
  atomIdByNode: new Map(),
  seen: new Set(),
});

/** Build the plural inverse of a per-node map (one key can land on several positions). */
function invert<K>(byNode: Map<NodeId, K>): Map<K, NodeId[]> {
  const out = new Map<K, NodeId[]>();
  for (const [node, key] of byNode) {
    const existing = out.get(key);
    if (existing) existing.push(node);
    else out.set(key, [node]);
  }
  return out;
}

const identityOf = (s: Sink): DecodedIdentity => ({
  uniqueByNode: s.uniqueByNode,
  nodesByUnique: invert(s.uniqueByNode),
  atomIdByNode: s.atomIdByNode,
  nodesByAtomId: invert(s.atomIdByNode),
});

/**
 * What to do with a call leaf's wire `expansion` (see the file header).
 * `"leaf"`: ignore it — the call is one box, as before expansions existed.
 * `"expand"`: decode it as a call panel, a `call: true` group under the call's own id.
 */
export type CallMode = "leaf" | "expand";

export interface FromVizOpts {
  /** Default `"leaf"`. */
  readonly calls?: CallMode;
}

/** Decode a wire `FunDecl` into a ladder `FunDecl` + valuation/provenance/identity. */
export function fromVizFunDecl(
  viz: VizFunDecl,
  opts: FromVizOpts = {},
): DecodedViz {
  const sink = emptySink(opts);
  const body = convert(viz.body, sink);
  const fn: FunDecl = {
    id: viz.id.id,
    name: viz.name.label,
    params: viz.params.map((p) => p.label),
    body,
  };
  return {
    fn,
    valuation: sink.valuation,
    provenance: sink.provenance,
    defaults: sink.defaults,
    ...identityOf(sink),
  };
}

/** Decode a bare wire `IRExpr` (e.g. an inlined sub-expression) the same way. */
export function fromVizExpr(
  viz: VizIRExpr,
  opts: FromVizOpts = {},
): DecodedIdentity & {
  readonly expr: IRExpr;
  readonly valuation: Map<NodeId, UBoolValue>;
  readonly provenance: Map<NodeId, Provenance>;
  readonly defaults: Map<NodeId, UBoolValue>;
} {
  const sink = emptySink(opts);
  const expr = convert(viz, sink);
  return {
    expr,
    valuation: sink.valuation,
    provenance: sink.provenance,
    defaults: sink.defaults,
    ...identityOf(sink),
  };
}

/**
 * A call's label for its panel: the wire spells a call `` `is creditworthy` OF a `` or
 * `limb OF a, b`; the panel says `is creditworthy a` and `limb a b`. Backticks go, as they
 * do in the decision heading, the sentences and mermaid; the ` OF ` and the commas between
 * arguments go too, but only at the top level — inside backticks, a string literal, or round
 * or square brackets they belong to an argument, and a string literal is copied untouched.
 * Leaf mode does not use this: a call drawn as one box shows its wire label as it is, and a
 * term inside a panel keeps its backticks, so the same call reads differently in the two
 * modes (WHERE-INLINING-SPEC §10.3).
 *
 * The label is PREFIX-NORMALISED, not the call as the drafter wrote it. A mixfix call
 * arrives from jl4-lsp in its surface form (`` a `is older than` b ``), because the LSP
 * stamps mixfix calls with their patterns before drawing (`stampMixfixCalls`), and is
 * shown as `a is older than b`; from a server that does not stamp them (jl4-service) it
 * arrives in prefix form (`` `is older than` OF a, b ``) and is shown as
 * `is older than a b`.
 */
export function callLabel(wire: string): string {
  const parts: string[] = [];
  let cur = "";
  let depth = 0;
  let quoted = false; // inside backticks
  let str = false; // inside a "string literal"
  let sawOf = false;
  for (let i = 0; i < wire.length; i++) {
    const c = wire[i]!;
    if (str) {
      cur += c;
      if (c === "\\" && i + 1 < wire.length) cur += wire[++i]!;
      else if (c === '"') str = false;
      continue;
    }
    if (!quoted && c === '"') {
      str = true;
      cur += c;
      continue;
    }
    if (c === "`") quoted = !quoted;
    else if (!quoted && (c === "(" || c === "[")) depth++;
    else if (!quoted && (c === ")" || c === "]")) depth--;
    const top = !quoted && depth === 0;
    if (top && !sawOf && wire.startsWith(" OF ", i)) {
      parts.push(cur);
      cur = "";
      sawOf = true;
      i += 3;
      continue;
    }
    if (top && sawOf && wire.startsWith(", ", i)) {
      parts.push(cur);
      cur = "";
      i += 1;
      continue;
    }
    cur += c;
  }
  parts.push(cur);
  // backticks go everywhere except inside a string literal
  const unquote = (s: string) =>
    s.replace(/("(?:[^"\\]|\\.)*")|`/g, (_m, lit) => lit ?? "");
  return parts
    .map((s) => unquote(s).trim())
    .filter((s) => s !== "")
    .join(" ");
}

/**
 * The call panel for a call leaf that carries an expansion (`calls: "expand"` only).
 *
 * The group takes the call leaf's id, so `foldSet.has(id)` folds the panel back to the one
 * box the call was, and a click on that box addresses the same id. Its identity goes into
 * the atomId index under that id — a folded `is creditworthy a` is the same proposition as
 * every other copy of that call — but NOT into the unique index, which holds leaves only
 * (`Leaf.unique`'s invariant), and the call leaf's own `value`/`typically` are not lifted:
 * a valuation entry on a group is an OVERRIDE (DESIGN §19) and would pin the panel.
 */
function callPanel(
  id: NodeId,
  wireLabel: string,
  atomId: string,
  expansion: VizIRExpr,
  sink: Sink,
): And {
  sink.atomIdByNode.set(id, atomId);
  return {
    $type: "And",
    id,
    label: callLabel(wireLabel),
    call: true,
    args: [convert(expansion, sink)],
  };
}

function convert(e: VizIRExpr, sink: Sink): IRExpr {
  const { valuation, provenance } = sink;
  // An expansion merges a second run of server ids into one tree. If the server ever broke
  // S2's fresh-id contract, two nodes would share an id and silently swap valuation,
  // provenance and atomId between unrelated boxes. Fail loudly instead.
  if (sink.calls === "expand") {
    if (sink.seen.has(e.id.id))
      throw new Error(
        `viz-adapter: node id ${e.id.id} occurs twice in an expanded tree — an expansion ` +
          `must use ids fresh across the whole FunDecl`,
      );
    sink.seen.add(e.id.id);
  }
  switch (e.$type) {
    case "And": {
      const node: And = {
        $type: "And",
        id: e.id.id,
        args: e.args.map((a) => convert(a, sink)),
        // wire And/Or carry no name today; when a NamedExpr wrapper lands
        // (viz-expr.ts ~L198, TODO §G5) its name becomes `label`.
      };
      return node;
    }
    case "Or": {
      const node: Or = {
        $type: "Or",
        id: e.id.id,
        args: e.args.map((a) => convert(a, sink)),
      };
      return node;
    }
    case "Not": {
      const node: Not = {
        $type: "Not",
        id: e.id.id,
        negand: convert(e.negand, sink),
      };
      return node;
    }
    case "Implies": {
      // The seam (DESIGN §25), carried through intact. This is the one place the
      // new renderer earns its keep over the old one: every other consumer of the
      // wire IR has to flatten this to `NOT scope OR requirement` and lose the
      // scope/requirement split. The ladder keeps it and draws two sinks.
      const node: Implies = {
        $type: "Implies",
        id: e.id.id,
        scope: convert(e.scope, sink),
        requirement: convert(e.requirement, sink),
        seam: e.seam,
      };
      return node;
    }
    case "UBoolVar": {
      if (sink.calls === "expand" && e.expansion)
        return callPanel(e.id.id, e.name.label, e.atomId, e.expansion, sink);
      // Lift the inline value into the positional valuation side-channel; the
      // ladder leaf itself is value-free. UnknownV carries no information, so we
      // skip it (absent => unknown in the kernel) to keep the map lean.
      if (e.value !== "UnknownV") valuation.set(e.id.id, e.value);
      // Lift TYPICALLY into provenance: a CONCRETE boolean (true OR false) marks
      // the leaf `default` (a false default is still a default). `null`/absent is
      // "no default" — the wire schema is `optional(NullOr(Boolean))`, so a
      // non-presumed atom arrives as `null`, which must NOT be read as a default.
      // Gate on true/false, matching viz-expr's `typicallyBridge`. Orthogonal to
      // `value`. Presence-of-a-boolean, not truthiness, decides provenance.
      if (e.typically === true || e.typically === false) {
        provenance.set(e.id.id, "default");
        // …and lift the PAYLOAD too, into `defaults` — the `Left` half of §22's
        // `Either (Maybe Bool) (Maybe Bool)`. Provenance alone says a presumption was
        // DECLARED here; only the value says what it presumes, and without it a viewer
        // switching defaults off has nothing to withdraw and `layout` has nothing to lay
        // under an unanswered leaf. The boolean was already on the wire and was being
        // dropped on the floor.
        sink.defaults.set(e.id.id, e.typically ? "TrueV" : "FalseV");
      }
      // §E1/S1: carry the semantic identity the evaluator keys on. `unique` and the
      // unique-maps are UBoolVar-only; `atomId` also indexes App below.
      sink.uniqueByNode.set(e.id.id, e.name.unique);
      sink.atomIdByNode.set(e.id.id, e.atomId);
      const leaf: Leaf = {
        $type: "UBoolVar",
        id: e.id.id,
        label: e.name.label,
        atomId: e.atomId,
        unique: e.name.unique,
        canInline: e.canInline,
      };
      return leaf;
    }
    case "App": {
      if (sink.calls === "expand" && e.expansion)
        return callPanel(e.id.id, e.fnName.label, e.atomId, e.expansion, sink);
      // §23 membrane leaf. Args are literal/value children rendered "drawn open"
      // (D1); A1 keeps the leaf flat but preserves `atomId` for eval addressing
      // and the predicate name as the label. Addressed by `atomId` (via `evalApp`),
      // NOT by `unique` — so it is in the atomId index but not the unique one.
      sink.atomIdByNode.set(e.id.id, e.atomId);
      const leaf: Leaf = {
        $type: "App",
        id: e.id.id,
        label: e.fnName.label,
        atomId: e.atomId,
      };
      return leaf;
    }
    case "TrueE": {
      const leaf: Leaf = { $type: "TrueE", id: e.id.id, label: e.name.label };
      return leaf;
    }
    case "FalseE": {
      const leaf: Leaf = { $type: "FalseE", id: e.id.id, label: e.name.label };
      return leaf;
    }
    case "InertE": {
      const node: Inert = {
        $type: "InertE",
        id: e.id.id,
        text: e.text,
        context: e.context,
      };
      return node;
    }
    default: {
      // Exhaustiveness guard: if the wire union grows a member, this fails to
      // compile (and throws loudly at runtime) instead of silently dropping it.
      const _never: never = e;
      throw new Error(
        `viz-adapter: unhandled wire node ${JSON.stringify(_never)}`,
      );
    }
  }
}

/**
 * One click, every copy: set `value` on the clicked node AND on every node that is the same
 * proposition — the same `atomId` (`identity.nodesByAtomId`) — and on no other. `UnknownV`
 * clears those entries instead of storing an unknown. A node with no atomId (a constant, a
 * plain group) changes alone. Returns a new map; `valuation` is not touched.
 *
 * Sameness is the atomId the server computed in the CALLER's context after substitution, so
 * the `a` inlined from `limb a b` IS the caller's `a` and links to it, while `limb a b` and
 * `limb c d` share nothing. This helper only reads that identity; it never derives one.
 */
export function spreadValue(
  identity: Pick<DecodedIdentity, "atomIdByNode" | "nodesByAtomId">,
  nodeId: NodeId,
  value: UBoolValue,
  valuation: ReadonlyMap<NodeId, UBoolValue>,
): Map<NodeId, UBoolValue> {
  const atomId = identity.atomIdByNode.get(nodeId);
  const same = (atomId !== undefined && identity.nodesByAtomId.get(atomId)) || [
    nodeId,
  ];
  const out = new Map(valuation);
  for (const n of same) {
    if (value === "UnknownV") out.delete(n);
    else out.set(n, value);
  }
  return out;
}
