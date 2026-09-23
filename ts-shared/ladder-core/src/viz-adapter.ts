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
  readonly valuation: Map<NodeId, UBoolValue>;
  readonly provenance: Map<NodeId, Provenance>;
  readonly defaults: Map<NodeId, UBoolValue>;
  readonly uniqueByNode: Map<NodeId, Unique>;
  readonly atomIdByNode: Map<NodeId, string>;
}

const emptySink = (): Sink => ({
  valuation: new Map(),
  provenance: new Map(),
  defaults: new Map(),
  uniqueByNode: new Map(),
  atomIdByNode: new Map(),
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

/** Decode a wire `FunDecl` into a ladder `FunDecl` + valuation/provenance/identity. */
export function fromVizFunDecl(viz: VizFunDecl): DecodedViz {
  const sink = emptySink();
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
export function fromVizExpr(viz: VizIRExpr): DecodedIdentity & {
  readonly expr: IRExpr;
  readonly valuation: Map<NodeId, UBoolValue>;
  readonly provenance: Map<NodeId, Provenance>;
  readonly defaults: Map<NodeId, UBoolValue>;
} {
  const sink = emptySink();
  const expr = convert(viz, sink);
  return {
    expr,
    valuation: sink.valuation,
    provenance: sink.provenance,
    defaults: sink.defaults,
    ...identityOf(sink),
  };
}

function convert(e: VizIRExpr, sink: Sink): IRExpr {
  const { valuation, provenance } = sink;
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
