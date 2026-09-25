/**
 * Sentence expander tests. The canonical case is `layman`'s own example —
 * `all: [any:[alice,bob], plain:loves, any:[carol,dave]]` — plus fold-taming and
 * the inert-style s415 shape (glue "or" prose dropped from Or branches).
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { expandSentences } from "../src/index.js";
import type { IRExpr, And, Or, Leaf, Inert, Not } from "../src/index.js";

let n = 0;
const id = () => ++n;
const leaf = (label: string): Leaf => ({
  $type: "UBoolVar",
  id: id(),
  label,
  atomId: label,
});
const inert = (text: string, context: "InertAnd" | "InertOr"): Inert => ({
  $type: "InertE",
  id: id(),
  text,
  context,
});
const and = (args: IRExpr[]): And => ({ $type: "And", id: id(), args });
const or = (args: IRExpr[]): Or => ({ $type: "Or", id: id(), args });
const not = (negand: IRExpr): Not => ({ $type: "Not", id: id(), negand });

test("layman example: (alice|bob) loves (carol|dave) => 4 combinations", () => {
  const alice = leaf("alice"),
    bob = leaf("bob"),
    carol = leaf("carol"),
    dave = leaf("dave");
  const tree = and([
    or([alice, bob]),
    inert("loves", "InertAnd"),
    or([carol, dave]),
  ]);
  assert.deepEqual(expandSentences(tree), [
    "alice loves carol",
    "alice loves dave",
    "bob loves carol",
    "bob loves dave",
  ]);
});

test("folding a disjunction keeps it inline => fewer sentences", () => {
  const alice = leaf("alice"),
    bob = leaf("bob"),
    carol = leaf("carol"),
    dave = leaf("dave");
  const ab = or([alice, bob]);
  const tree = and([ab, inert("loves", "InertAnd"), or([carol, dave])]);
  // fold the alice/bob disjunction -> it collapses to "(alice or bob)" (one factor)
  assert.deepEqual(expandSentences(tree, new Set([ab.id])), [
    "(alice or bob) loves carol",
    "(alice or bob) loves dave",
  ]);
});

test("inert glue inside an Or is dropped; backticks stripped", () => {
  // mirrors the s415 `deception` node: [inert preamble, byDeceiving, inert "or", concealment]
  const deception = or([
    inert("there is a deception", "InertOr"),
    leaf("`by deceiving`"),
    inert("or", "InertOr"),
    leaf("`dishonest concealment`"),
  ]);
  assert.deepEqual(expandSentences(deception), [
    "by deceiving",
    "dishonest concealment",
  ]);
});

test("NOT wraps each inner sentence", () => {
  const tree = and([
    leaf("capacity"),
    not(or([leaf("under duress"), leaf("mistaken")])),
  ]);
  assert.deepEqual(expandSentences(tree), [
    "capacity NOT (under duress)",
    "capacity NOT (mistaken)",
  ]);
});

test("count is the product of unfolded disjunction arities", () => {
  const tree = and([
    or([leaf("a"), leaf("b"), leaf("c")]),
    or([leaf("x"), leaf("y")]),
  ]);
  assert.equal(expandSentences(tree).length, 6); // 3 * 2
});

test("duplicate sentences are de-duplicated", () => {
  const tree = or([leaf("same"), leaf("same"), leaf("other")]);
  assert.deepEqual(expandSentences(tree), ["same", "other"]);
});
