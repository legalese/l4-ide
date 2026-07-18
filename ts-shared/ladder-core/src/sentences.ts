/**
 * Sentence expander (ported from the `layman` prototype). Enumerates an
 * And/Or tree into the full set of combinations — one sentence per way the rule
 * can be satisfied — the surplusage/scenario view that complements the ladder.
 *
 * The rules, mirroring `layman`'s all/any/element/plain:
 *   • And  → a PRODUCT: cross-join the children's sentence sets, in source order
 *            (conjunction reads as a sequence — inert glue prose stays inline).
 *   • Or   → a UNION: each non-inert alternative branches into its own sentence(s).
 *            (Inert children of an Or are connective glue like "or" and a heading
 *            preamble; they are dropped from the branches, matching layman, whose
 *            `any` held bare elements.)
 *   • Not  → wraps each inner sentence as `NOT (…)`.
 *   • Leaf → its label; Inert → its text (kept as inline prose inside an And).
 *
 * Fold-aware (like layman's collapsed/expanded `show`): a node in `foldSet`
 * collapses to a single inline token — `(a or b or c)` for an Or, the joined
 * prose for an And — so it contributes ONE factor instead of branching. With
 * nothing folded you get the full cartesian product; fold a disjunction to tame
 * the blow-up. Pure: no DOM, no layout.
 */
import type { FunDecl, IRExpr, NodeId } from "./types.js";

/** Strip the L4 backtick quoting on identifiers for readable prose. */
const clean = (s: string) => s.replace(/`/g, "").trim();

function leafLabel(e: IRExpr): string {
  switch (e.$type) {
    case "UBoolVar":
    case "TrueE":
    case "FalseE":
      return clean(e.label);
    case "App":
      return clean(e.label);
    case "InertE":
      return clean(e.text);
    default:
      return "";
  }
}

/** Non-inert children of an And/Or (the real operands, minus glue prose). */
const operands = (args: readonly IRExpr[]) =>
  args.filter((a) => a.$type !== "InertE");

/** Collapse a whole subtree to a single inline string (for folded nodes). */
function inline(e: IRExpr): string {
  switch (e.$type) {
    case "And":
      return e.args.map(inline).filter(Boolean).join(" ");
    case "Or": {
      const parts = operands(e.args).map(inline).filter(Boolean);
      return parts.length > 1 ? `(${parts.join(" or ")})` : (parts[0] ?? "");
    }
    case "Not":
      return `NOT (${inline(e.negand)})`;
    default:
      return leafLabel(e);
  }
}

const join = (a: string, b: string) => [a, b].filter(Boolean).join(" ");
function crossJoin(a: string[], b: string[]): string[] {
  if (!a.length) return b;
  if (!b.length) return a;
  const out: string[] = [];
  for (const x of a) for (const y of b) out.push(join(x, y));
  return out;
}

function sentences(e: IRExpr, folded: ReadonlySet<NodeId>): string[] {
  if (folded.has(e.id)) return [inline(e)];
  switch (e.$type) {
    case "And":
      // product across children, inert prose riding inline as a 1-element set
      return e.args.reduce<string[]>(
        (acc, a) => crossJoin(acc, sentences(a, folded)),
        [],
      );
    case "Or":
      // union over the real alternatives; glue/preamble inert children dropped
      return operands(e.args).flatMap((a) => sentences(a, folded));
    case "Not":
      return sentences(e.negand, folded).map((s) => `NOT (${s})`);
    default: {
      const l = leafLabel(e);
      return l ? [l] : [];
    }
  }
}

/**
 * Enumerate every combination of a decision body into sentences. Pass the
 * `foldSet` from your `ViewSpec` to keep folded disjunctions inline. Returns the
 * de-duplicated sentence list in enumeration order.
 */
export function expandSentences(
  root: FunDecl | IRExpr,
  foldSet: ReadonlySet<NodeId> = new Set(),
): string[] {
  const body: IRExpr = "body" in root ? root.body : root;
  const all = sentences(body, foldSet);
  const seen = new Set<string>();
  return all.filter((s) => s && !seen.has(s) && (seen.add(s), true));
}
