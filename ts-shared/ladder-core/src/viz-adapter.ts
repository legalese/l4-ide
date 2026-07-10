/**
 * viz-adapter — the P2 bridge from the LSP wire IR (`@repo/viz-expr`) into
 * ladder-core's local `IRExpr` (DESIGN §11 "Keep" — consume the existing protocol
 * as-is; TODO §A1). The two IRs are deliberately near-identical (P0 kept a local
 * mirror), so this is a mechanical, positional-identity-preserving map plus a
 * side-channel that lifts each leaf's `value` into a `ViewSpec.valuation` map.
 *
 * What this file is NOT: it does not carry TYPICALLY / provenance (TODO §B, owned
 * by the `typically` v2 session — the wire `UBoolVar` has no such field yet), and
 * it does not talk to the LSP (that is A2's transport layer — this operates on an
 * already-decoded `FunDecl`).
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
  NodeId,
  UBoolValue,
} from "./types.js";

/** The result of decoding a wire `FunDecl`: the ladder tree plus the valuation
 *  side-channel lifted from inline leaf values. Feed `valuation` straight into
 *  `defaultViewSpec({ valuation })` (or merge with live eval results, A3). */
export interface DecodedViz {
  readonly fn: FunDecl;
  /** Positional (keyed by node id) T/F/U lifted from `UBoolVar.value`. */
  readonly valuation: Map<NodeId, UBoolValue>;
}

/** Decode a wire `FunDecl` into a ladder `FunDecl` + valuation side-channel. */
export function fromVizFunDecl(viz: VizFunDecl): DecodedViz {
  const valuation = new Map<NodeId, UBoolValue>();
  const body = convert(viz.body, valuation);
  const fn: FunDecl = {
    id: viz.id.id,
    name: viz.name.label,
    params: viz.params.map((p) => p.label),
    body,
  };
  return { fn, valuation };
}

/** Decode a bare wire `IRExpr` (e.g. an inlined sub-expression) the same way. */
export function fromVizExpr(viz: VizIRExpr): {
  readonly expr: IRExpr;
  readonly valuation: Map<NodeId, UBoolValue>;
} {
  const valuation = new Map<NodeId, UBoolValue>();
  const expr = convert(viz, valuation);
  return { expr, valuation };
}

function convert(e: VizIRExpr, valuation: Map<NodeId, UBoolValue>): IRExpr {
  switch (e.$type) {
    case "And": {
      const node: And = {
        $type: "And",
        id: e.id.id,
        args: e.args.map((a) => convert(a, valuation)),
        // wire And/Or carry no name today; when a NamedExpr wrapper lands
        // (viz-expr.ts ~L198, TODO §G5) its name becomes `label`.
      };
      return node;
    }
    case "Or": {
      const node: Or = {
        $type: "Or",
        id: e.id.id,
        args: e.args.map((a) => convert(a, valuation)),
      };
      return node;
    }
    case "Not": {
      const node: Not = {
        $type: "Not",
        id: e.id.id,
        negand: convert(e.negand, valuation),
      };
      return node;
    }
    case "UBoolVar": {
      // Lift the inline value into the positional valuation side-channel; the
      // ladder leaf itself is value-free. UnknownV carries no information, so we
      // skip it (absent => unknown in the kernel) to keep the map lean.
      if (e.value !== "UnknownV") valuation.set(e.id.id, e.value);
      const leaf: Leaf = {
        $type: "UBoolVar",
        id: e.id.id,
        label: e.name.label,
        atomId: e.atomId,
      };
      return leaf;
    }
    case "App": {
      // §23 membrane leaf. Args are literal/value children rendered "drawn open"
      // (D1); A1 keeps the leaf flat but preserves `atomId` for eval addressing
      // and the predicate name as the label.
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
