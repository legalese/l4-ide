/**
 * `verdictFor` — the six-row table (§E1/S9, DESIGN §25f).
 *
 * verdictFor is the PICTURE's verdict: it reads the three-valued node values the ladder draws.
 * On every determinate input it agrees row-for-row with `BooleanDecisionQuery.verdictOf`
 * (Haskell) and `boolean-analysis`' `verdictOf` (TS) — the §25f rows are all there, so the
 * header never commits the N/A-vs-complies error. The two rows a `NOT scope OR requirement`
 * expansion cannot express — `NotApplicable` (vacuously TRUE, rule never bit) and
 * `Undetermined`-with-met-requirement — are pinned below.
 *
 * It is SOUND but NOT COMPLETE relative to the ROBDD (found by the Step 1 adversarial review):
 * on a tautological/contradictory subformula with an unknown atom (`a ∨ ¬a`, `a ∧ ¬a`) the
 * Kleene `nodeValue` leaves the subtree `UnknownV` while the ROBDD reduces it, so verdictFor is
 * conservatively `Undetermined` where `verdictOf` settles. The last `describe` block pins that
 * boundary as INTENDED: the imprecision is always toward `Undetermined` (never a wrong definite
 * verdict) and faithful to the grey the ladder draws.
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

/* ---- SOUND, not COMPLETE: the boundary the Step 1 adversarial review found ---- */
// `nodeValue` is Kleene three-valued and evaluates each occurrence independently, so it does
// NOT recognise `a ∨ ¬a` / `a ∧ ¬a` while `a` is unknown — the ROBDD in `verdictOf` does. These
// pin verdictFor's CONSERVATIVE answer as INTENDED: it matches the grey the ladder draws, and
// its imprecision is always toward `Undetermined`, never a wrong definite verdict. A caller that
// needs the reduced answer reads it off the query engine (boolean-analysis), not off the picture.

const or = (args: IRExpr[]): IRExpr => ({ $type: "Or", id: nid(), args });
const not = (negand: IRExpr): IRExpr => ({ $type: "Not", id: nid(), negand });

test("no-seam tautology `a OR NOT a` (a unknown) ⇒ conservatively Undetermined (ROBDD: Holds)", () => {
  const a1 = leaf("a");
  const a2 = leaf("a"); // same proposition, second position (shares a Unique in real wire IR)
  const taut: FunDecl = {
    id: nid(),
    name: "taut",
    params: [],
    body: or([a1, not(a2)]),
  };
  assert.equal(verdictFor(taut, val({})), "Undetermined");
  // and it is SOUND: once the atom is actually known, it settles correctly either way
  assert.equal(
    verdictFor(taut, val({ [a1.id]: "TrueV", [a2.id]: "TrueV" })),
    "Holds",
  );
  assert.equal(
    verdictFor(taut, val({ [a1.id]: "FalseV", [a2.id]: "FalseV" })),
    "Holds",
  );
});

test("no-seam contradiction `a AND NOT a` (a unknown) ⇒ conservatively Undetermined (ROBDD: Fails)", () => {
  const a1 = leaf("a");
  const a2 = leaf("a");
  const contra: FunDecl = {
    id: nid(),
    name: "contra",
    params: [],
    body: and([a1, not(a2)]),
  };
  assert.equal(verdictFor(contra, val({})), "Undetermined");
});

test("seam whose scope is a tautology ⇒ Undetermined, not the ROBDD's Complies — and never a WRONG verdict", () => {
  const a1 = leaf("a");
  const a2 = leaf("a");
  const c = leaf("c");
  const tautScope: FunDecl = {
    id: nid(),
    name: "compliant",
    params: [],
    body: {
      $type: "Implies",
      id: nid(),
      scope: or([a1, not(a2)]), // always true, but Kleene can't see it while a is unknown
      requirement: c,
      seam: "IMPLIES",
    },
  };
  // ROBDD verdictOf would say Complies (scope reduces to TRUE, c=TRUE). verdictFor is
  // conservative — but crucially it does NOT say Complies or NotApplicable wrongly.
  assert.equal(verdictFor(tautScope, val({ [c.id]: "TrueV" })), "Undetermined");
  // once the scope's atom is pinned so Kleene sees TRUE, the verdict lands correctly:
  assert.equal(
    verdictFor(
      tautScope,
      val({ [a1.id]: "TrueV", [a2.id]: "TrueV", [c.id]: "TrueV" }),
    ),
    "Complies",
  );
});
