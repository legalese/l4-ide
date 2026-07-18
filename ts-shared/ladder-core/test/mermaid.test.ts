/** mermaid.ts (DESIGN §24, carrier I-d) — IRExpr → Mermaid `railroad-beta`.
 *
 * The load-bearing correctness property is about INERT (§17). In the ladder, an
 * inert child of an OR is a heading or "or"-glue and carries NO current. But every
 * child of a railroad `choice` is a live BRANCH — so emitting the prose as a rung
 * silently adds a free pass-through path and makes the disjunction trivially
 * satisfiable. That bug shipped in the first draft and was caught only by looking
 * at the render, so it is pinned here.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { toMermaidRailroad } from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  Leaf,
  Inert,
  And,
  Or,
  Not,
} from "../src/index.js";

let c = 0;
const nid = () => ++c;
const leaf = (label: string): Leaf => ({
  $type: "UBoolVar",
  id: nid(),
  label,
  atomId: label,
});
const inert = (text: string): Inert => ({
  $type: "InertE",
  id: nid(),
  text,
  context: "InertOr",
});
const and = (args: IRExpr[], label?: string): And => ({
  $type: "And",
  id: nid(),
  args,
  label,
});
const or = (args: IRExpr[], label?: string): Or => ({
  $type: "Or",
  id: nid(),
  args,
  label,
});
const not = (negand: IRExpr): Not => ({ $type: "Not", id: nid(), negand });

const decl = (body: IRExpr, name = "r"): FunDecl => ({
  id: nid(),
  name,
  params: [],
  body,
});

const emit = (fn: FunDecl, o = {}) =>
  toMermaidRailroad(fn, { frontmatter: false, ...o });

test("And → sequence, Or → choice, Leaf → nonterminal", () => {
  const out = emit(decl(and([leaf("a"), or([leaf("b"), leaf("c")])])));
  assert.match(out, /sequence\(/);
  assert.match(out, /choice\(/);
  assert.match(out, /nonterminal\("a"\)/);
});

test("inert in a SERIES rides the wire as a terminal", () => {
  const out = emit(decl(and([leaf("a"), inert("and"), leaf("b")])));
  assert.match(
    out,
    /sequence\(nonterminal\("a"\), terminal\("and"\), nonterminal\("b"\)\)/,
  );
});

test("inert in an OR must NOT become a branch of the choice", () => {
  // the bug: choice(terminal("either"), a, terminal("or"), b) adds a free
  // pass-through path — the disjunction becomes trivially satisfiable.
  const out = emit(
    decl(or([inert("either"), leaf("a"), inert("or"), leaf("b")])),
  );
  // The leading run is hoisted in FRONT of the fan (the drafter's preamble survives);
  // the medial "or" is dropped, because the fan already performs it visually; and the
  // choice contains only the two operative rungs.
  assert.equal(
    out,
    'r = sequence(terminal("either"), choice(nonterminal("a"), nonterminal("b")));',
  );
});

test("a NOT over a NAMED subtree factors into its own rule (isomorphic)", () => {
  const covers = and([leaf("upper"), leaf("side")], "A.3 covers");
  const out = emit(decl(or([not(covers), leaf("met")]), "complies"));
  // the head references it by name, negated…
  assert.match(out, /nonterminal\("NOT A.3 covers"\)/);
  // …and the subtree becomes a rule of its own, prose intact
  assert.match(
    out,
    /A_3_covers = sequence\(nonterminal\("upper"\), nonterminal\("side"\)\)/,
  );
  assert.ok(!out.includes("WARNING"), "should not need De Morgan");
});

test("a NOT over an atom is a polarity on the contact, not a gate", () => {
  const out = emit(decl(and([not(leaf("registered")), leaf("paid")])));
  assert.match(out, /nonterminal\("NOT registered"\)/);
  assert.ok(!out.includes("choice("), "no gate should be synthesized");
});

test("a NOT over an UNNAMED group falls back to De Morgan, and says so", () => {
  const out = emit(decl(not(and([leaf("a"), leaf("b")]))));
  // ¬(a ∧ b) ≡ ¬a ∨ ¬b
  assert.match(out, /choice\(nonterminal\("NOT a"\), nonterminal\("NOT b"\)\)/);
  // …and warns, because the shape no longer mirrors the source text
  assert.match(out, /%% WARNING: De Morgan/);
});

test("rule identifiers are sanitized; labels keep their punctuation", () => {
  const out = emit(
    decl(leaf("openable parts ≥ 1.7m"), "window complies with A.3"),
  );
  assert.match(out, /^window_complies_with_A_3 = /m);
  assert.match(out, /nonterminal\("openable parts ≥ 1.7m"\)/);
});

test("frontmatter carries the railroad theme config when asked", () => {
  const out = toMermaidRailroad(decl(leaf("a")), {});
  assert.match(out, /^---\nconfig:\n  railroad:/);
  assert.match(out, /^railroad-beta$/m);
});
