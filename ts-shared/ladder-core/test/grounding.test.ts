/**
 * `ViewSpec.grounding` and `ViewSpec.respectDefaults` — the two epistemic knobs.
 *
 * `NEGATION-AS-FAILURE-SPEC.md` calls the default value *"the knob that turns NAF into
 * general defeasible / default reasoning"*, where flipping it FALSE→TRUE *"is exactly
 * the closed-world / open-world switch"*. These tests pin that knob, and — more
 * importantly — the two invariants that keep it from becoming a truth-value hack:
 *
 *   1. it collapses at the ELIMINATOR, never in the data (render state stays honest);
 *   2. it defaults for SILENCE, never overruling what the source actually said.
 *
 * Lose either and the ladder starts asserting things nobody claimed.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { layout, defaultViewSpec, estimateMetrics } from "../src/index.js";
import type {
  FunDecl,
  Grounding,
  IRExpr,
  NodeId,
  Provenance,
  Scene,
  ScenePrim,
  UBoolValue,
} from "../src/index.js";

const leaf = (id: NodeId, label: string): IRExpr => ({
  $type: "UBoolVar",
  id,
  label,
});
const and = (id: NodeId, args: IRExpr[]): IRExpr => ({
  $type: "And",
  id,
  args,
});
const or = (id: NodeId, args: IRExpr[]): IRExpr => ({ $type: "Or", id, args });

interface Opts {
  vals?: Array<[NodeId, UBoolValue]>;
  defs?: Array<[NodeId, UBoolValue]>;
  prov?: Array<[NodeId, Provenance]>;
  grounding?: Grounding;
  respectDefaults?: boolean;
  showCurrent?: boolean;
}
const sceneOf = (body: IRExpr, o: Opts = {}): Scene =>
  layout(
    { id: 1, name: "r", params: [], body } satisfies FunDecl,
    defaultViewSpec({
      valuation: new Map(o.vals ?? []),
      defaults: new Map(o.defs ?? []),
      provenance: new Map(o.prov ?? []),
      grounding: o.grounding ?? "none",
      respectDefaults: o.respectDefaults ?? true,
      showCurrent: o.showCurrent ?? true,
    }),
    estimateMetrics,
  );

const boxFor = (s: Scene, id: NodeId) =>
  s.prims.find(
    (p): p is Extract<ScenePrim, { kind: "box" }> =>
      p.kind === "box" && p.id === id,
  )!;
const breaks = (s: Scene) =>
  s.prims.filter((p) => p.kind === "glyph" && p.role === "open-contact");
const tags = (s: Scene) =>
  s.prims
    .filter(
      (p): p is Extract<ScenePrim, { kind: "text" }> =>
        p.kind === "text" && (p.tag === "typically" || p.tag === "assumed"),
    )
    .map((p) => p.text);
/** Flows on CONTACT-carrying connectors. The left power rail is excluded: it is the
 *  supply, not a contact, and is closed by definition whatever the atoms say. */
const flows = (s: Scene) =>
  s.prims.flatMap((p) =>
    (p.kind === "curve" || (p.kind === "wire" && p.role !== "rail")) && p.flow
      ? [p.flow]
      : [],
  );

const conj = () => and(2, [leaf(3, "a"), leaf(4, "b")]);

/* ------------------------------------------------------------ the default path */

test("grounding 'none' is the honest Kleene picture — and the pre-existing behaviour", () => {
  const s = sceneOf(conj(), { vals: [[3, "TrueV"]] });
  assert.equal(s.complete, false, "an unproven path is not a made circuit");
  assert.equal(s.provisional, false);
  assert.equal(boxFor(s, 4).state, "inert");
  assert.equal(tags(s).length, 0);
});

/* -------------------------------------------------- invariant 1: the eliminator */

test("grounding drives CONDUCTION but never RENDER STATE — an assumed atom still draws unanswered", () => {
  // This is the invariant that keeps the knob honest. Under closed-world the circuit
  // must read as broken, but leaf 4 must NOT acquire the ink of a tested-and-false
  // contact: §25.4 tells N/A from undetermined by exactly that ink, and a viewer
  // setting is not allowed to forge a finding.
  const s = sceneOf(conj(), { vals: [[3, "TrueV"]], grounding: "closed" });
  assert.equal(s.complete, false, "closed world: unproven b stops the circuit");
  assert.equal(boxFor(s, 4).state, "inert", "still grey — nobody asked");
  assert.equal(
    breaks(s).length,
    0,
    "an assumption must not draw a tested break",
  );
});

test("a genuinely FALSE atom keeps its break; grounding changes nothing about it", () => {
  for (const grounding of ["none", "closed", "open"] as const) {
    const s = sceneOf(conj(), { vals: [[4, "FalseV"]], grounding });
    assert.equal(boxFor(s, 4).state, "dead", `${grounding}: still dead`);
    assert.equal(breaks(s).length, 1, `${grounding}: still one break`);
    assert.equal(s.complete, false, `${grounding}: a false contact stops it`);
  }
});

/* ------------------------------------------------ invariant 2: silence, not speech */

test("grounding fills SILENCE only — it never overrules a value the source stated", () => {
  // The L4 author who wrote `holds p` here and `presumed q` there has already chosen,
  // per use site; that choice lands in the valuation and this global knob cannot reach
  // it. Open-world must not flip a stated FALSE to true.
  const s = sceneOf(conj(), {
    vals: [
      [3, "TrueV"],
      [4, "FalseV"],
    ],
    grounding: "open",
  });
  assert.equal(s.complete, false, "a stated FALSE survives open-world");
  assert.equal(boxFor(s, 4).state, "dead");
});

/* ------------------------------------------------------------- the two readings */

test("open world closes an unproven series; closed world opens it", () => {
  assert.equal(sceneOf(conj(), { grounding: "open" }).complete, true);
  assert.equal(sceneOf(conj(), { grounding: "closed" }).complete, false);
});

test("closed world settles a disjunction to FALSE, which is the NAF reading", () => {
  const s = sceneOf(or(2, [leaf(3, "a"), leaf(4, "b")]), {
    grounding: "closed",
  });
  assert.equal(s.complete, false);
});

test("an assumed closure is capped at STREAMER — never full leader weight", () => {
  // §20's lightning model already means "closed, but not confirmed" for a local
  // streamer and for a §22 presumption. An assumption is the third reason, same ink.
  const s = sceneOf(conj(), { grounding: "open" });
  assert.ok(flows(s).includes("streamer"));
  assert.ok(
    !flows(s).includes("closed"),
    "nothing here is confirmed, so nothing draws as confirmed",
  );
});

test("`provisional` separates 'the circuit is made' from 'made out of what'", () => {
  const allGiven = sceneOf(conj(), {
    vals: [
      [3, "TrueV"],
      [4, "TrueV"],
    ],
  });
  assert.equal(allGiven.complete, true);
  assert.equal(
    allGiven.provisional,
    false,
    "answered facts are not provisional",
  );

  const assumed = sceneOf(conj(), { grounding: "open" });
  assert.equal(assumed.complete, true, "…made…");
  assert.equal(assumed.provisional, true, "…but entirely on assumptions");

  const mixed = sceneOf(conj(), { vals: [[3, "TrueV"]], grounding: "open" });
  assert.equal(mixed.provisional, true, "one assumed contact is enough");
});

test("an assumed atom is tagged with the reading applied to it", () => {
  assert.deepEqual(tags(sceneOf(conj(), { grounding: "open" })), [
    "assumed true",
    "assumed true",
  ]);
  assert.deepEqual(tags(sceneOf(conj(), { grounding: "closed" })), [
    "assumed false",
    "assumed false",
  ]);
});

/* -------------------------------------------------------- the defaults axis (§22) */

test("respectDefaults:false withdraws the PRESUMPTION — Left (Just b) becomes Left Nothing", () => {
  const on = sceneOf(conj(), {
    vals: [[3, "TrueV"]],
    defs: [[4, "TrueV"]],
    prov: [[4, "default"]],
  });
  assert.equal(on.complete, true, "the presumption closes the circuit");
  assert.equal(boxFor(on, 4).state, "live");
  assert.deepEqual(tags(on), ["typically"]);

  const off = sceneOf(conj(), {
    vals: [[3, "TrueV"]],
    defs: [[4, "TrueV"]],
    prov: [[4, "default"]],
    respectDefaults: false,
  });
  assert.equal(
    off.complete,
    false,
    "without the presumption, nothing closes it",
  );
  assert.equal(boxFor(off, 4).state, "inert", "back to an open question");
  assert.deepEqual(
    tags(off),
    ["typically off"],
    "the mark survives: a reader must still see WHERE a presumption was available",
  );
  assert.ok(boxFor(off, 4).tentative, "and it keeps the tentative dash");
});

test("respectDefaults:false NEVER touches the user's own answer, TYPICALLY leaf or not", () => {
  // The bug this exists to stop. `provenance: 'default'` marks a DECLARATION site — the
  // drafter wrote a TYPICALLY here — and is true whether or not the presumption is the
  // thing currently supplying the value. Keying the withdrawal off it therefore deleted
  // the user's ANSWER on any atom that happened to carry a TYPICALLY clause. Worse, on the
  // real decode path the adapter marks provenance but supplies no default value at all, so
  // deleting user answers was the ONLY thing the switch could ever do.
  const s = sceneOf(conj(), {
    vals: [
      [3, "TrueV"],
      [4, "TrueV"], // the USER clicked this one true
    ],
    defs: [[4, "FalseV"]], // …over a source presumption that says otherwise
    prov: [[4, "default"]],
    respectDefaults: false,
  });
  assert.equal(s.complete, true, "the user's answer survives");
  assert.equal(boxFor(s, 4).state, "live");
  assert.deepEqual(
    tags(s),
    ["typically"],
    "and it is NOT labelled 'typically off' — nothing was withheld from it",
  );
  assert.equal(
    s.provisional,
    false,
    "an answered atom is a finding, however many TYPICALLYs surround it",
  );
});

test("an answer beats a presumption even when defaults are respected", () => {
  const s = sceneOf(conj(), {
    vals: [
      [3, "TrueV"],
      [4, "FalseV"],
    ],
    defs: [[4, "TrueV"]],
    prov: [[4, "default"]],
  });
  assert.equal(
    boxFor(s, 4).state,
    "dead",
    "Right (Just b) wins over Left (Just b)",
  );
  assert.equal(s.complete, false);
});

test("a presumption alone makes the verdict provisional", () => {
  const s = sceneOf(conj(), {
    vals: [[3, "TrueV"]],
    defs: [[4, "TrueV"]],
    prov: [[4, "default"]],
  });
  assert.equal(s.complete, true);
  assert.equal(
    s.provisional,
    true,
    "riding a TYPICALLY is not a grounded finding",
  );
});

test("withdrawing a default leaves an open question that grounding may then answer", () => {
  const s = sceneOf(conj(), {
    vals: [[3, "TrueV"]],
    defs: [[4, "TrueV"]],
    prov: [[4, "default"]],
    respectDefaults: false,
    grounding: "closed",
  });
  assert.equal(s.complete, false);
  assert.deepEqual(
    tags(s),
    ["assumed false (typically off)"],
    "and the tag names both things that happened to this leaf",
  );
});

test("a leaf with no default in play is untouched by the defaults switch", () => {
  const s = sceneOf(conj(), {
    vals: [
      [3, "TrueV"],
      [4, "TrueV"],
    ],
    respectDefaults: false,
  });
  assert.equal(s.complete, true);
});

/* ------------------------------- provisionality is POLARITY-BLIND if you test identity */

test("an assumption reaching the verdict through a NOT still counts as provisional", () => {
  // `naf p MEANS NOT (holds p)` is the canonical negation-as-failure shape, and here the
  // assumption contributes by NOT conducting — so no node on the conducting path is itself
  // assumed. Testing node identity misses it entirely and paints the full made-green on a
  // circuit resting on an unanswered atom.
  const body = and(2, [
    leaf(3, "eligible"),
    { $type: "Not", id: 4, negand: leaf(5, "disqualified") },
  ]);
  const s = sceneOf(body, { vals: [[3, "TrueV"]], grounding: "closed" });
  assert.equal(s.complete, true, "closed world completes it…");
  assert.equal(s.provisional, true, "…on an atom nobody answered");
  assert.equal(
    boxFor(s, 5).state,
    "inert",
    "and the atom itself still renders unanswered",
  );
});

test("an assumption reaching the verdict through VACUITY still counts as provisional", () => {
  const body = and(2, [
    {
      $type: "Implies",
      id: 3,
      scope: leaf(4, "in scope"),
      requirement: leaf(5, "met"),
      seam: "IMPLIES",
    },
  ]);
  const s = sceneOf(body, { grounding: "closed" });
  assert.equal(s.complete, true, "vacuously true, so the series conducts");
  assert.equal(
    s.provisional,
    true,
    "but only because the scope was assumed out",
  );
});

test("nothing is provisional when every contact was actually answered", () => {
  const s = sceneOf(conj(), {
    vals: [
      [3, "TrueV"],
      [4, "TrueV"],
    ],
    grounding: "closed",
  });
  assert.equal(s.complete, true);
  assert.equal(s.provisional, false);
});

/* --------------------------------------------------------- the seam (§25.4 lamps) */

const rule = (): IRExpr => ({
  $type: "Implies",
  id: 2,
  scope: leaf(3, "in scope"),
  requirement: leaf(4, "met"),
  seam: "IMPLIES",
});

const coils = (s: Scene) =>
  s.prims.filter(
    (p): p is Extract<ScenePrim, { kind: "coil" }> => p.kind === "coil",
  );
const notes = (s: Scene) =>
  s.prims.flatMap((p) =>
    p.kind === "text" && p.tag === "note" ? [p.text] : [],
  );

test("an unknown scope lights no lamp — undetermined is not a verdict", () => {
  const s = sceneOf(rule(), { vals: [[4, "TrueV"]] });
  assert.deepEqual(
    coils(s).map((c) => c.lit),
    [false, false],
  );
  assert.deepEqual(notes(s), [], "and it is NOT reported as N/A");
});

test("closed world turns an unknown scope into N/A — but says the reading did it", () => {
  const s = sceneOf(rule(), { vals: [[4, "TrueV"]], grounding: "closed" });
  assert.deepEqual(
    coils(s).map((c) => c.lit),
    [false, false],
  );
  assert.deepEqual(notes(s), ["N/A — on this reading of the unanswered facts"]);
});

test("a definitively false scope keeps the unqualified N/A wording", () => {
  for (const grounding of ["none", "closed", "open"] as const) {
    const s = sceneOf(rule(), { vals: [[3, "FalseV"]], grounding });
    assert.deepEqual(notes(s), ["N/A — the rule does not reach this case"]);
  }
});

test("open world can light a lamp the honest picture leaves dark", () => {
  const s = sceneOf(rule(), { vals: [[3, "TrueV"]], grounding: "open" });
  const [green, red] = coils(s);
  assert.equal(green.lit, true, "unproven requirement read as met ⇒ complies");
  assert.equal(red.lit, false);
});

test("closed world reads an unproven requirement as a BREACH", () => {
  const s = sceneOf(rule(), { vals: [[3, "TrueV"]], grounding: "closed" });
  const [green, red] = coils(s);
  assert.equal(green.lit, false);
  assert.equal(
    red.lit,
    true,
    "obligation-discharge semantics: unproven ⇒ not done",
  );
  assert.equal(
    boxFor(s, 4).state,
    "inert",
    "and the requirement box still shows it was never answered",
  );
});
