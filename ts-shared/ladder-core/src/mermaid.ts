/**
 * IRExpr -> Mermaid `railroad-beta` (DESIGN §24, carrier I-d).
 *
 * The fourth emit, and the cheapest, because Mermaid's railroad grammar *is* our
 * IR, near enough:
 *
 *     And   ->  sequence(...)      series on one wire
 *     Or    ->  choice(...)        stacked rungs fanning off a common node
 *     Leaf  ->  nonterminal("…")   a boxed, operative atom
 *     Inert ->  terminal("…")      unboxed grammatical prose (§17)
 *
 * So this is a pretty-printer over the same tree that feeds `layout()`, not a
 * second renderer. That matters: a Mermaid ladder written BY HAND would be a
 * second, unverified source of truth, free to drift from the L4 — the exact
 * inversion `logic-not-flowcharts.md` exists to condemn. GENERATED, it is a view,
 * and the thesis holds.
 *
 * Why bother, when we already emit SVG and ASCII? Because github.com renders
 * ```mermaid fences natively, and a generated fence is still **text in the
 * Markdown**: it diffs semantically (`git diff` shows "in a wall" changing, not
 * 200 lines of path coordinates), needs no binary in the repo, and no build
 * tooling at render time.
 *
 * ## Negation
 *
 * Railroad has no NOT — but it does not need one (DESIGN §21a). A negated ATOM is
 * a polarity on a contact, not a gate: `─┤/├─`, the normally-closed contact of
 * IEC 61131-3. Two routes, both supported:
 *
 *   - **fold it** (preferred, and isomorphic): a NOT over a *named* subtree emits
 *     `nonterminal("NOT <name>")`, and the subtree becomes its own railroad RULE.
 *     Railroad is a grammar notation, so this reproduces the L4's own factoring
 *     rule-for-rule, and every word of inert prose stays where the drafter put it.
 *   - **De Morgan** (fallback): push the negation down to the leaves. Correct, but
 *     it rewrites the shape — and it silently falsifies inert prose, since the "and"
 *     joining a conjunction becomes an "or" in the dual. So we WARN, not fix: the
 *     prose is emitted verbatim and flagged, because quietly rewriting a drafter's
 *     words is worse than showing that the dual no longer reads like the statute.
 */
import type { FunDecl, IRExpr, NodeId, And, Or } from "./types.js";

export interface MermaidOpts {
  /** Nodes to emit as their own named rule (grammar factoring). Reuse the §16
   *  foldSet: folding a subtree and naming a subtree are the same operation. */
  readonly factor?: ReadonlySet<NodeId>;
  /** Theme colours. 'ink' for print-ish/monochrome. */
  readonly theme?: "screen" | "ink";
  /** Emit the `---\nconfig:` frontmatter. Off if you are embedding in one yourself. */
  readonly frontmatter?: boolean;
}

/* ------------------------------------------------------------------ helpers */

/** Mermaid string literals are double-quoted; there is no escape, so fold to a
 *  typographic quote rather than emit something that will not parse. */
const lit = (s: string) => s.replace(/`/g, "").replace(/"/g, "”").trim();

/** A subtree's name: explicit label -> leading inert (the Pre) -> synthesized.
 *  Same precedence as layout.ts's foldLabel, deliberately. */
function nameOf(e: IRExpr): string {
  if (e.$type === "And" || e.$type === "Or") {
    if (e.label) return e.label;
    const lead: string[] = [];
    for (const a of e.args) {
      if (a.$type === "InertE") lead.push(a.text);
      else break;
    }
    if (lead.length) return lead.join(" ");
    const n = e.args.filter((a) => a.$type !== "InertE").length;
    return e.$type === "And" ? `all of ${n}` : `any of ${n}`;
  }
  if (e.$type === "InertE") return e.text;
  if (e.$type === "Not") return `NOT ${nameOf(e.negand)}`;
  if (e.$type === "Implies")
    return (
      e.label ?? `${nameOf(e.scope)} ${e.seam ?? "⇒"} ${nameOf(e.requirement)}`
    );
  return e.label;
}

/** A railroad rule identifier. Mermaid wants a bare token here. */
const ident = (s: string) =>
  s
    .replace(/`/g, "")
    .trim()
    .replace(/[^A-Za-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .replace(/^(\d)/, "r$1") || "rule";

/** De Morgan: push a negation down to the leaves (DESIGN §21a). Used only when a
 *  negand cannot be factored out into its own rule. */
function pushNot(e: IRExpr, nid: () => NodeId): IRExpr {
  switch (e.$type) {
    case "And":
      return {
        $type: "Or",
        id: nid(),
        args: e.args.map((a) => pushNot(a, nid)),
      } as Or;
    case "Or":
      return {
        $type: "And",
        id: nid(),
        args: e.args.map((a) => pushNot(a, nid)),
      } as And;
    case "Not":
      return e.negand; // ¬¬x = x
    case "InertE":
      // Prose has no dual. Keep the drafter's words; the caller warns.
      return e;
    default:
      return { ...e, label: `NOT ${e.label}` };
  }
}

/* ---------------------------------------------------------------- the emit */

export function toMermaidRailroad(fn: FunDecl, opts: MermaidOpts = {}): string {
  const factor = opts.factor ?? new Set<NodeId>();
  const rules: string[] = [];
  const emitted = new Set<NodeId>();
  const warnings: string[] = [];
  let counter = 1e6;
  const nid = () => ++counter;

  /** Render an expression inline; a `factor`ed subtree becomes a reference and is
   *  queued as its own rule instead. */
  function go(e: IRExpr, top = false): string {
    if (!top && factor.has(e.id) && (e.$type === "And" || e.$type === "Or")) {
      queue(e);
      return `nonterminal("${lit(nameOf(e))}")`;
    }
    switch (e.$type) {
      case "InertE":
        return `terminal("${lit(e.text)}")`;

      // AND: inert prose rides the wire, and railroad renders a `terminal` in a
      // sequence as exactly that — unboxed grey text on the line (§17). Keep it.
      case "And": {
        const kids = e.args.map((a) => go(a));
        return kids.length === 1 ? kids[0] : `sequence(${kids.join(", ")})`;
      }

      // OR: inert prose must NOT survive into the `choice`. In the ladder an inert
      // child of an OR is a HEADING (or "or"-glue in the gap) and carries no
      // current — but every child of a railroad `choice` is a live BRANCH. Emit the
      // prose as a rung and you have added a free pass-through path, which makes the
      // disjunction trivially satisfiable. So: hoist the leading run out in front of
      // the fan (where it reads as the drafter's preamble), and drop the medial glue,
      // whose only job — "or" — the fan already performs visually.
      case "Or": {
        const lead: string[] = [];
        let i = 0;
        while (i < e.args.length && e.args[i].$type === "InertE")
          lead.push((e.args[i++] as { text: string }).text);
        const rungs = e.args.slice(i).filter((a) => a.$type !== "InertE");
        const kids = rungs.map((a) => go(a));
        const fan = kids.length === 1 ? kids[0] : `choice(${kids.join(", ")})`;
        return lead.length
          ? `sequence(terminal("${lit(lead.join(" "))}"), ${fan})`
          : fan;
      }
      case "Not": {
        const n = e.negand;
        // Preferred: the negand is a named/factored subtree -> "NOT <name>", and the
        // subtree is emitted as its own rule. Isomorphic; prose survives intact.
        if (
          (n.$type === "And" || n.$type === "Or") &&
          (factor.has(n.id) || n.label)
        ) {
          queue(n);
          return `nonterminal("NOT ${lit(nameOf(n))}")`;
        }
        // Atom: a polarity on the contact (§21a). No gate needed.
        if (n.$type !== "And" && n.$type !== "Or" && n.$type !== "Not")
          return `nonterminal("NOT ${lit(nameOf(n))}")`;
        // Fallback: De Morgan. Correct, but it rewrites the shape — and the inert
        // prose no longer reads like the statute (an "and" should have become an
        // "or"). Warn rather than silently rewrite the drafter's words.
        warnings.push(
          `De Morgan applied to an unnamed subtree: the diagram no longer mirrors the source text, and any inert prose inside it now reads against the grain. Give the subtree a label, or add it to \`factor\`, to keep the isomorphism.`,
        );
        return go(pushNot(n, nid));
      }
      // §25.6 — IMPLIES as the BOTTLENECK. `sequence(P, IMPLIES, Q)`: one path, no
      // bypass ink, reading as the statute's own sentence. Under a strict railroad
      // grammar a `sequence` is concatenation (P ∧ Q), so a purist would miss the
      // vacuous case — but the seam is labelled with the drafter's own connective, and
      // no reader parses "covered — IMPLIES — compliant" as a conjunction. The word
      // carries the semantics. NEVER use `optional(Q)`: that is an UNGATED bypass
      // (Q ∨ ⊤), which says the requirement is MOOT — the picture we want, meaning
      // the exact opposite.
      case "Implies":
        return `sequence(${go(e.scope)}, terminal("${lit(e.seam ?? "⇒")}"), ${go(e.requirement)})`;
      default:
        return `nonterminal("${lit(e.label)}")`;
    }
  }

  function queue(e: And | Or): void {
    if (emitted.has(e.id)) return;
    emitted.add(e.id);
    rules.push(`${ident(nameOf(e))} = ${go(e, true)};`);
  }

  // the head rule first, then whatever it referenced (in reference order)
  const head = `${ident(fn.name)} = ${go(fn.body, true)};`;
  const body = [head, ...rules].join("\n");

  if (opts.frontmatter === false)
    return warnings.length
      ? `${body}\n${warnings.map((w) => `%% WARNING: ${w}`).join("\n")}`
      : body;

  const ink = opts.theme === "ink";
  const cfg = [
    "---",
    "config:",
    "  railroad:",
    `    nonTerminalFill: "#ffffff"`,
    `    nonTerminalStroke: "${ink ? "#222222" : "#2f7a3f"}"`,
    `    nonTerminalTextColor: "#111111"`,
    `    terminalFill: "transparent"`,
    `    terminalStroke: "transparent"`,
    `    terminalTextColor: "#888888"`,
    `    lineColor: "#8a8a8a"`,
    `    markerFill: "#222222"`,
    `    strokeWidth: 1.5`,
    `    fontSize: 15`,
    "---",
    "railroad-beta",
  ].join("\n");

  return [cfg, body, ...warnings.map((w) => `%% WARNING: ${w}`)].join("\n");
}
