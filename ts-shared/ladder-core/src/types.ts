/**
 * ladder-core types — the input IR (a self-contained P0 mirror of @repo/viz-expr's
 * IRExpr), the ViewSpec, the Scene IR, and the injected TextMetrics interface.
 *
 * See specs/todo/ladder-diagrams-2026/DESIGN.md §4.2 (Scene IR), §4.3 (ViewSpec),
 * §3.2 (TextMetrics), §16 (folding).
 *
 * P0 keeps the input types local so the kernel runs under `tsx` with zero
 * workspace deps. P2 swaps these for `@repo/viz-expr` (the wire IR), which is
 * structurally identical bar the `label?` discussed below.
 */

/* ----------------------------------------------------------------- input IR */

export type NodeId = number;

/**
 * Semantic identity of a proposition, mirror of viz-expr's `Unique` (TODO §E1 / S1).
 *
 * Distinct from `NodeId`, and the distinction is load-bearing: `NodeId` is POSITIONAL
 * (every drawn box has its own), while `Unique` is SEMANTIC — two `UBoolVar` leaves that
 * refer to the same proposition share a `Unique` but not a `NodeId`. The IDE's evaluator
 * keys its `Assignment` by `Unique`, so a binding on one occurrence must fan out to every
 * `NodeId` that shares the `Unique` (see `DecodedViz.nodesByUnique`). Get this backwards
 * and one diagram shows the same atom with two different values.
 */
export type Unique = number;

/** Mirror of viz-expr's UBoolValue. */
export type UBoolValue = "TrueV" | "FalseV" | "UnknownV";

/**
 * Provenance of a leaf's value (DESIGN §22) — orthogonal to the T/F/U value AND to
 * the render State. `given` = user-/data-supplied (grounded); `default` = riding a
 * TYPICALLY presumption the user hasn't confirmed (rebuttable, tentative). Models
 * the `Left`/`Right` of `Either (Maybe Bool) (Maybe Bool)`: Left (a default) ⇒
 * `default`, Right (user-given) ⇒ `given`. Absent ⇒ `given`. Only meaningful on
 * leaves (a group's value derives; it is never "presumed").
 */
export type Provenance = "given" | "default";

/** Operative atom — carries current; renders as a BOX. */
export interface Leaf {
  readonly $type: "UBoolVar" | "App" | "TrueE" | "FalseE";
  readonly id: NodeId;
  readonly label: string;
  readonly atomId?: string;
  /**
   * Semantic identity (§E1/S1). Set for `UBoolVar` only — the leaves the IDE evaluator
   * addresses by `Unique`. `App` is eval-addressed by `atomId` (via `evalApp`), and
   * `TrueE`/`FalseE` are constants, so neither carries one. The invariant is
   * `leaf.unique !== undefined ⟺ leaf ∈ DecodedViz.nodesByUnique`, which lets a caller
   * read identity off the drawn tree without a side table.
   */
  readonly unique?: Unique;
  /**
   * Whether this atom can be unfolded to its definition (the IDE's `+` button, gated on
   * `inlineExprs`). From the wire `UBoolVar.canInline`; absent on every other leaf kind.
   */
  readonly canInline?: boolean;
}

/**
 * Inert (grammatical scaffolding) — the identity of its context (TRUE under AND,
 * FALSE under OR), so it carries NO current and renders UNBOXED (DESIGN §17).
 * This is the one primitive behind PrePost headings, "any of the following",
 * "… or …" connectives, and inert-style verbatim prose. Position decides render:
 * leading inert in an OR -> heading above the stack; inert in a series -> rides
 * the wire (and a leading one lands to the left of the stack for free).
 */
export interface Inert {
  readonly $type: "InertE";
  readonly id: NodeId;
  readonly text: string;
  readonly context: "InertAnd" | "InertOr";
}

/**
 * OPTIONAL human name for a subtree (see DESIGN §16 / answer to "does the IR need
 * a way to label a subtree?"). Today the wire IR has NO such field on And/Or;
 * absent => the core synthesizes a label. When present (e.g. fed from the L4
 * DECIDE/Where name a subtree was inlined from, via a NamedExpr wrapper), folding
 * shows something legible like "there is a deception".
 */
export interface And {
  readonly $type: "And";
  readonly id: NodeId;
  readonly args: readonly IRExpr[];
  readonly label?: string;
}

export interface Or {
  readonly $type: "Or";
  readonly id: NodeId;
  readonly args: readonly IRExpr[];
  readonly label?: string;
}

export interface Not {
  readonly $type: "Not";
  readonly id: NodeId;
  readonly negand: IRExpr;
}

/**
 * Material implication — the SEAM between scope and requirement (DESIGN §25).
 *
 * `P IMPLIES Q` is NOT sugar for `NOT P OR Q`. That expansion is truth-functionally
 * perfect and SHAPE-DESTROYING: a statute has a SCOPE ("does this bite me?") and a
 * REQUIREMENT ("then what must I do?"), those are the first two questions a lawyer
 * asks, and a disjunction of escape routes answers neither. Drawing it that way is
 * the very sin `logic-not-flowcharts.md` convicts flowcharts of, so the ladder gets
 * a real node.
 *
 * Renders as ONE PATH — `[scope] ══MUST══▶ [requirement]` — with **two sinks** (§25.4):
 * the requirement's verdict throws a CHANGEOVER, lighting a green coil (complies) or
 * a red one (in breach). Vacuity needs no ink at all: if the scope does not conduct,
 * no current leaves it and NEITHER lamp lights. That is N/A, and the reader can see
 * exactly where it stopped.
 *
 * SCOPE (v1): top-level only. A rule *is* an implication; nesting one inside an
 * And/Or is legal but the two-sink form has nowhere to put its lamps, so a nested
 * `Implies` falls back to the `¬P ∨ Q` expansion (see `expandImplies`).
 */
export interface Implies {
  readonly $type: "Implies";
  readonly id: NodeId;
  readonly scope: IRExpr;
  readonly requirement: IRExpr;
  /**
   * The connective AS THE DRAFTER WROTE IT — §17's argument for inert prose, applied
   * to the operator (§25e). From real L4 this is `'IMPLIES'` or `'=>'`, the two ways
   * the language spells the constitutive conditional; the picture does not get to
   * invent a register the source did not use. Absent ⇒ the renderer's own '⇒'.
   *
   * Deliberately NOT `'MUST'`: there is no constitutive MUST in L4. MUST is the
   * regulative deontic keyword (`PARTY p MUST …`), whose consequent is a whole
   * transition system rather than a coil — a different diagram entirely (§25.5).
   */
  readonly seam?: string;
  readonly label?: string;
}

export type IRExpr = Leaf | Inert | And | Or | Not | Implies;

export interface FunDecl {
  readonly id: NodeId;
  readonly name: string;
  readonly params: readonly string[];
  readonly body: IRExpr;
}

/* -------------------------------------------------------------- ViewSpec */

/** Orthogonal to T/F/U; see DESIGN §15.1. Default 'inert'. */
export type State = "live" | "inert" | "dead" | "eliminable";

/**
 * How to read an atom the source left UNGROUNDED — the choice of epistemics, made
 * explicit and reversible (DESIGN §22; `NEGATION-AS-FAILURE-SPEC.md`).
 *
 * The L4 library already ships the three eliminators this mirrors — `holds`
 * (unproven ⇒ FALSE), `presumed` (unproven ⇒ TRUE), `decided` (is there a verdict at
 * all?) — and the spec calls the default value *"the knob that turns NAF into general
 * defeasible / default reasoning"*, where flipping it FALSE→TRUE *"is exactly the
 * closed-world / open-world switch"*. This is that knob, surfaced.
 *
 *   'none'   — Kleene. Unknown stays unknown; the picture shows only what is known.
 *   'closed' — negation as failure. Unproven reads FALSE (`holds`).
 *   'open'   — unproven reads TRUE (`presumed`).
 *
 * TWO INVARIANTS make this principled rather than a global truth-value hack, and both
 * are load-bearing:
 *
 * 1. **Collapse at the eliminator, never in the data.** The grounded reading drives
 *    CONDUCTION (energize / lamps / `complete`) only. Render state — box ink, the
 *    open-contact break — keeps reading the honest three-valued evaluation, so an
 *    assumed atom still draws grey-and-unbroken, never as a tested-and-false contact.
 *    §25.4 reads N/A off exactly that ink, and a grounding switch must not forge it.
 * 2. **It defaults for silence; it never overrules speech.** Grounding applies only
 *    where the source said nothing. An L4 author who wrote `holds p` in one clause and
 *    `presumed q` in another has already chosen per use site — that choice is in the
 *    valuation and this knob cannot reach it. (`NEGATION-AS-FAILURE-SPEC.md` assigns
 *    them by polarity: `presumed`/open for permission, `holds`/closed for obligation
 *    discharge, which is precisely why one global setting could never be the whole
 *    answer.)
 *
 * Closure that rests on an assumption is capped at STREAMER weight (§20/§22) — the
 * lightning model now carries three reasons for provisional closure: locality, a
 * TYPICALLY presumption, and an assumption. One channel, three reasons.
 */
export type Grounding = "none" | "closed" | "open";

export type Scale = "full" | "small" | "tiny";
export type Orient = "LR" | "TB";
export type Theme = "screen" | "ink";

/**
 * The single serializable "what to draw" both web and print accept (DESIGN §4.3).
 * `states` and `foldSet` are keyed by node `id` (POSITIONAL — a repeated atom can
 * be live in one rung and otiose in another; DESIGN §15.2). Leaf *values* would be
 * keyed by atomId; only structural facts (fold, eliminability) are positional.
 */
/** How a conjunctive (series) inert connective relates to the wire (DESIGN §17).
 *  Both 'above'/'below' keep the line UNBROKEN (inert = identity = always conducts):
 *  'on-wire'    — text sits on the line, in a gap the series leaves (it "rides").
 *  'above-wire' — continuous wire; text sits above it (matches OR heading-above, so
 *                 all inert text lives above what it annotates — one reading rule).
 *  'below-wire' — continuous wire; text drops just below it.
 *  'straddle-wire' — long prose word-wraps across the wire (half above, half below,
 *                 the line threading between); ~halves the horizontal footprint at
 *                 the cost of vertical space. Single words fall back to 'above-wire'. */
export type ConnectiveStyle =
  | "on-wire"
  | "above-wire"
  | "below-wire"
  | "straddle-wire";

export interface ViewSpec {
  readonly foldSet: ReadonlySet<NodeId>;
  /**
   * Direct T/F/U valuation, keyed by node `id` (POSITIONAL). For a leaf it's the
   * atom's value; for a GROUP it's an OVERRIDE / pin — the node is treated opaquely
   * with this value, its children not consulted (DESIGN §19). Absent => derived
   * from children (groups) or unknown (leaves).
   */
  readonly valuation: ReadonlyMap<NodeId, UBoolValue>;
  /** Manual render-state override (static demos / eliminable). Wins over the value-
   *  derived state when set. */
  readonly states: ReadonlyMap<NodeId, State>;
  /**
   * Per-leaf provenance (DESIGN §22), keyed by node `id` (POSITIONAL, like `states`
   * / `valuation`). A node mapped to `default` is riding a TYPICALLY presumption:
   * its box renders TENTATIVE (fine-dashed + a `typically` tag) and any current it
   * carries is capped at streamer weight (a rebuttable, not-yet-confirmed closure).
   * Absent ⇒ `given`. Injected data (like `states`); populated upstream from the L4
   * TYPICALLY field once the wire IR carries it. */
  readonly provenance: ReadonlyMap<NodeId, Provenance>;
  /**
   * The VALUES the source's TYPICALLY presumptions supply, keyed by node `id` — kept in
   * their own map, separate from `valuation`, because that separation IS the `Left`/`Right`
   * of `Either (Maybe Bool) (Maybe Bool)` (DESIGN §22):
   *
   *   `valuation` = **Right** — what the user or the data actually said;
   *   `defaults`  = **Left**  — what the drafter presumed in their absence.
   *
   * `valuation` always wins where both have an entry, so an answered question is never
   * overwritten by a presumption. And `respectDefaults` can then withdraw the presumptions
   * without touching a single user answer — which a single merged map makes impossible to
   * do correctly, because once merged there is no longer any way to tell whose value it was.
   *
   * Distinct from `provenance`, which marks a DECLARATION site ("this leaf has a TYPICALLY
   * clause") and is therefore true whether or not the presumption is currently in play.
   */
  readonly defaults: ReadonlyMap<NodeId, UBoolValue>;
  readonly scale: Scale;
  readonly orient: Orient;
  readonly theme: Theme;
  readonly connectiveStyle: ConnectiveStyle;
  /** Render current flow (DESIGN §20): closed connectors thick+dark, open thin+light.
   *  Off by default so static/print demos keep state-coloured connectors. */
  readonly showCurrent: boolean;
  /** How to read an ungrounded atom. Default 'none' — the honest Kleene picture. */
  readonly grounding: Grounding;
  /**
   * Honour the TYPICALLY defaults the L4 source supplies (DESIGN §22)? Default `true`.
   *
   * This is the OTHER axis, and it is genuinely independent of `grounding`: it is the
   * `Left`/`Right` of `Either (Maybe Bool) (Maybe Bool)`, not the Just/Nothing. Turning
   * it off demotes every `Left (Just b)` to `Left Nothing` — the presumption's VALUE is
   * dropped while the mark that one exists is kept — which answers "how much of this
   * verdict rests on presumptions?" by simply removing them and seeing what survives.
   *
   * Off + `grounding: 'none'` is the strictest reading available: only what the user
   * actually told us, with nothing filled in from either direction.
   */
  readonly respectDefaults: boolean;
}

export function defaultViewSpec(partial: Partial<ViewSpec> = {}): ViewSpec {
  return {
    foldSet: partial.foldSet ?? new Set(),
    valuation: partial.valuation ?? new Map(),
    states: partial.states ?? new Map(),
    provenance: partial.provenance ?? new Map(),
    defaults: partial.defaults ?? new Map(),
    scale: partial.scale ?? "full",
    orient: partial.orient ?? "LR",
    theme: partial.theme ?? "screen",
    connectiveStyle: partial.connectiveStyle ?? "straddle-wire",
    showCurrent: partial.showCurrent ?? false,
    grounding: partial.grounding ?? "none",
    respectDefaults: partial.respectDefaults ?? true,
  };
}

/* -------------------------------------------------------------- Scene IR */

export interface Pt {
  x: number;
  y: number;
}
export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** A click affordance the renderer turns into a data-attr; the host wires it.
 *  'value' -> cycle the node's T/F/U; 'fold' -> toggle folding that node. */
export interface ClickAct {
  t: "value" | "fold";
  id: NodeId;
}

/** Current-flow level on a connector (DESIGN §20). The "lightning" model:
 *  - 'closed'   — reached by the LEADER from the source (a complete run so far)
 *  - 'streamer' — LOCAL closure: a conducting element lights its own connectors even
 *                 if the leader hasn't arrived (a ground streamer rising to meet the bolt)
 *  - 'open'     — neither. */
export type Flow = "open" | "streamer" | "closed";

export type ScenePrim =
  | {
      kind: "box";
      id: NodeId;
      rect: Rect;
      role: "leaf" | "placeholder";
      state: State;
      folded?: boolean;
      /** riding a TYPICALLY presumption (DESIGN §22) — render fine-dashed/tentative. */
      tentative?: boolean;
      act?: ClickAct;
    }
  | {
      kind: "wire";
      path: Pt[];
      role: "rail" | "rung" | "stub";
      state: State;
      act?: ClickAct;
      flow?: Flow;
    }
  /** cubic Bézier connector (DESIGN §17a) — the organic fan from a group's port to
   *  each rung, contrasting the rectilinear boxes. Horizontal tangents at both ends. */
  | {
      kind: "curve";
      from: Pt;
      c1: Pt;
      c2: Pt;
      to: Pt;
      role: "conn";
      state: State;
      act?: ClickAct;
      flow?: Flow;
    }
  | {
      kind: "glyph";
      at: Pt;
      role: "open-contact" | "power-terminal" | "inverter" | "changeover";
      /** For `open-contact` only: whose break is this? A `dead` break is a settled fact
       *  and draws in the firm dead ink; an `eliminable` one is a ghost (DESIGN §15.1).
       *  Absent ⇒ ghost, the pre-existing behaviour. */
      state?: State;
      /** …and is the FALSITY itself only presumed (DESIGN §22)? A `TYPICALLY FALSE` leaf
       *  really is false and really does break the circuit, so it earns a break — but a
       *  rebuttable one. Takes §22's fine dash, matching the box it hangs off: the closure
       *  side is already softened this way, and a break is just closure with the sign
       *  flipped. Without this, a presumed-false contact reports as firmly as a tested one. */
      tentative?: boolean;
    }
  /** A SINK (DESIGN §25.4). The right-hand half of a rung, which our diagrams have
   *  never drawn: an implication routes its verdict to one of two lamps. `lit` is the
   *  whole point — count the lit lamps and you have the verdict:
   *    green lit  => in scope, and complies
   *    red lit    => in scope, and IN BREACH
   *    neither    => N/A (the scope did not conduct) or undetermined (something is ?)
   *  For a regulative rule the red lamp is not a lamp but a DOORWAY — it is where
   *  LEST hangs (§25.5). Not in this build. */
  | {
      kind: "coil";
      at: Pt;
      role: "green" | "red";
      lit: boolean;
      label: string;
      id?: NodeId;
    }
  /** NOT scope frame (DESIGN §21) — a light enclosure round a negated complex
   *  subtree, tagged. The inversion itself is the 'inverter' bubble on the output. */
  | { kind: "frame"; rect: Rect; label: string }
  | {
      kind: "text";
      at: Pt;
      text: string;
      anchor: "start" | "middle";
      state: State;
      tag?:
        | "otiose"
        | "title"
        | "note"
        | "heading"
        | "connective"
        | "caret"
        | "typically"
        /** §Grounding — "assumed false" / "assumed true": this atom was never answered
         *  and the reader has chosen an epistemics for it. Distinct from `typically`,
         *  which is a presumption the SOURCE supplied; this one is the reader's. */
        | "assumed"
        | "seam"; // §25 — the MUST / ⇒ connective between scope and requirement
      size?: number;
      /** node id this text belongs to (heading -> its group; label -> its box) —
       *  used by renderers for click targets and FLIP matching. */
      id?: NodeId;
      act?: ClickAct;
    };

export interface Scene {
  size: { w: number; h: number };
  prims: ScenePrim[];
  /**
   * Does the circuit conduct END TO END — source rail through to the sink (DESIGN §20,
   * TODO G1)? A connector's own `flow: "closed"` only says *the leader reached me*; it
   * cannot tell a path that completes from one that energizes half the diagram and then
   * dies at an open contact. That is a whole-scene property, so it lives here rather
   * than on each prim, and renderers use it to distinguish a **made** circuit from a
   * merely live one. `undefined` when current flow is off (`showCurrent: false`).
   *
   * For an `Implies` body this stays false: a rule with two lamps has no single sink to
   * reach, and the lamps already report the verdict (§25.4).
   */
  complete?: boolean;
  /**
   * Does any closure in this scene rest on something the user did not actually assert —
   * a TYPICALLY presumption (§22) or a `grounding` assumption (`Grounding`)?
   *
   * Kept separate from `complete` because the honest answer to "is this circuit made?"
   * has two parts, and merging them is how a picture ends up overclaiming: a circuit can
   * be made ENTIRELY on assumed atoms, and a reader who sees only the made-green would
   * have no way to know. Renderers should soften the made-circuit signal when set.
   */
  provisional?: boolean;
}

/* -------------------------------------------------------------- TextMetrics */

/**
 * Injected (DESIGN §3.2). P0 uses a cheap estimator; browser uses Canvas
 * measureText; Node-for-print uses fontkit on the SAME font (font parity, §4.4).
 */
export interface TextMetrics {
  width(text: string, sizePx: number): number;
  lineHeight(sizePx: number): number;
}
