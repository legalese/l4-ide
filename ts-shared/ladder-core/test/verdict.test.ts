/**
 * `verdictFor` — the six-row table (§E1/S9, DESIGN §25f).
 *
 * This is the SAME table `BooleanDecisionQuery.verdictOf` (Haskell) and
 * `boolean-analysis`' `verdictOf` (TS) implement, and it is asserted here in the same
 * words on purpose: a diagram whose header disagreed with the wizard about a case would
 * be lying to the same user. The two rows that a `NOT scope OR requirement` expansion
 * cannot express — and that the whole seam exists to keep apart — are `NotApplicable`
 * (vacuously TRUE, but the rule never bit) and `Undetermined`-with-met-requirement.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { verdictFor } from "../src/index.js";
import type {
  FunDecl,
  IRExpr,
  Leaf,
  And,
  Implies,
  NodeId,
  UBoolValue,
} from "../src/index.js";

let c = 0;
const nid = () => ++c;
const leaf = (label: string): Leaf => ({
  $type: "UBoolVar",
  id: nid(),
  label,
  atomId: label,
});
const and = (args: IRExpr[]): And => ({ $type: "And", id: nid(), args });

const scopeA = leaf("upper");
const scopeB = leaf("side");
const reqA = leaf("glazed");
const reqB = leaf("shut");
const scope = and([scopeA, scopeB]);
const requirement = and([reqA, reqB]);
const seam: Implies = {
  $type: "Implies",
  id: nid(),
  scope,
  requirement,
  seam: "IMPLIES",
};
const ruleFn: FunDecl = {
  id: nid(),
  name: "compliant",
  params: [],
  body: seam,
};

const val = (v: Record<number, UBoolValue>) =>
  new Map<NodeId, UBoolValue>(
    Object.entries(v).map(([k, x]) => [Number(k), x]),
  );
// pin the two AND groups so the seam's sides are settled without pinning both leaves each
const scopeTrue = { [scopeA.id]: "TrueV", [scopeB.id]: "TrueV" } as const;
const scopeFalse = { [scopeA.id]: "FalseV" } as const; // one false leaf ⇒ the AND is false
const reqTrue = { [reqA.id]: "TrueV", [reqB.id]: "TrueV" } as const;
const reqFalse = { [reqA.id]: "FalseV" } as const;

test("scope FALSE ⇒ NotApplicable — the rule never bit, and vacuous TRUE is not compliance", () => {
  assert.equal(
    verdictFor(ruleFn, val({ ...scopeFalse, ...reqTrue })),
    "NotApplicable",
  );
  // and it stays N/A regardless of the requirement — nothing about Q matters once P is out
  assert.equal(
    verdictFor(ruleFn, val({ ...scopeFalse, ...reqFalse })),
    "NotApplicable",
  );
  assert.equal(verdictFor(ruleFn, val(scopeFalse)), "NotApplicable");
});

test("scope UNKNOWN ⇒ Undetermined, EVEN when the requirement is already met", () => {
  // The sharp case: req met ⇒ the function is vacuously/really TRUE, but we do not know
  // WHICH true it is (N/A vs complies), so the verdict is not settled. This is the row the
  // classical short-circuit gets wrong.
  assert.equal(verdictFor(ruleFn, val(reqTrue)), "Undetermined");
  assert.equal(verdictFor(ruleFn, val({})), "Undetermined");
});

test("scope TRUE, requirement TRUE ⇒ Complies", () => {
  assert.equal(
    verdictFor(ruleFn, val({ ...scopeTrue, ...reqTrue })),
    "Complies",
  );
});

test("scope TRUE, requirement FALSE ⇒ InBreach", () => {
  assert.equal(
    verdictFor(ruleFn, val({ ...scopeTrue, ...reqFalse })),
    "InBreach",
  );
});

test("scope TRUE, requirement UNKNOWN ⇒ Undetermined (an unasked requirement is not a breach)", () => {
  assert.equal(verdictFor(ruleFn, val(scopeTrue)), "Undetermined");
});

/* ---- no seam: a plain function reports its truth value, not a compliance verdict ---- */

const plainA = leaf("a");
const plainB = leaf("b");
const plainFn: FunDecl = {
  id: nid(),
  name: "plain",
  params: [],
  body: and([plainA, plainB]),
};

test("no seam ⇒ Holds / Fails / Undetermined off the function's own value", () => {
  assert.equal(
    verdictFor(plainFn, val({ [plainA.id]: "TrueV", [plainB.id]: "TrueV" })),
    "Holds",
  );
  assert.equal(verdictFor(plainFn, val({ [plainA.id]: "FalseV" })), "Fails");
  assert.equal(
    verdictFor(plainFn, val({ [plainA.id]: "TrueV" })),
    "Undetermined",
  );
});

test("a single-leaf function is a degenerate no-seam case, not a crash", () => {
  const solo = leaf("solo");
  const soloFn: FunDecl = { id: nid(), name: "solo", params: [], body: solo };
  assert.equal(verdictFor(soloFn, val({ [solo.id]: "TrueV" })), "Holds");
  assert.equal(verdictFor(soloFn, val({ [solo.id]: "FalseV" })), "Fails");
  assert.equal(verdictFor(soloFn, val({})), "Undetermined");
});
