import { Schema, Pretty, JSONSchema } from 'effect'
import { VersionedDocId } from './versioned-doc-id.js'

/**********************
      VizExpr IR
************************

The following is pretty much adapted / copied from the interfaces sketched at
https://github.com/legalese/lam4/blob/main/experiments/ide-interfaces/l4extensionprototype/src/interfaces/decisionLogicIRNode.ts

The main difference is that I'm experimenting with using Effect schemas,
in order to get functionality like serialization/deserialization, generation of the corresponding JSON Schemas, and better error messages.

-----------------
  Design intent
-----------------

I framed the visualizer inputs in terms of PL concepts,
as opposed to 'lower-level' graph visualization concepts (e.g. overlaying and connecting nodes),
because my understanding was that Matthew Waddington wanted
the produced components to be things that other legal DSLs can also benefit from.
In particular, he seemed to want something like
a 'L4-lite' intermediate representation whose semantics was mostly confined to propositional logic,
and that other legal DSLs can either compile to (so as, e.g., to use tools whose inputs
are in terms of this intermediate representation)
or extend with their own features.

Furthermore, if the visualizer inputs were framed in terms of, e.g., 'lower-level' graph visualization concepts,
that wouldn't be very different from visualization tools that already exist for visualizing graphs.

The other design goal was to try to come up with something that's simple while still being relatively extensible.
If there are things that do not seem easily extensible, please do not hesitate to point those out.

---------------------------------------
  Relationship to previous prototypes
---------------------------------------
In coming up with the following, I
* looked through all the visualization-related components we've previously done (mathlangvis, Jules' ladder diagram, Meng's layman, vue pure pdpa)
and did a quick personal assessment of their software interfaces, design intents,
and practical pros and cons when it came to re-using them for this usecase.
 (In particular, I've run and played with most of them.)
* also looked at Maryam's https://github.com/Meowyam/lspegs

If it seems like there are aspects of extant work that have not been considered in the following,
it's likely because they are either not needed for the v1 mvp or looked like they'd have other practical disadvantages.
*/

/***************************
  Common types and schemas
****************************/

/*
Note: We need some type declarations, in addition to the Effect schemas,
in order to implement recursive and mutually recursive schemas.
See https://effect.website/docs/schema/advanced-usage/#recursive-schemas
*/

/***********************************************************
        Name
  (a label / 'RawName' and a Unique for equality of exprs)
*************************************************************/

export const Name = Schema.Struct({
  /** Uniques for checking whether, e.g., two UBoolVar IRNodes actually refer to the same proposition.
   *
   * UBoolVar IRNodes that refer to the same proposition can nevertheless differ
   * in virtue of eg having different nlg annotations.  */
  unique: Schema.Number,
  label: Schema.String,
})

export interface Name {
  /** For equality of exprs */
  readonly unique: Unique
  /** The label is what gets displayed in or around the box. */
  readonly label: string
}

export type Unique = number

/*******************************
           IRId
********************************/

/** Stable IDs useful for things like bidirectional synchronization down the road */
export const IRId = Schema.Struct({
  id: Schema.Number,
})

/** Stable IDs useful for things like bidirectional synchronization down the road */
export interface IRId {
  readonly id: number
}

/*****************
  Core IR node
*****************/

export interface IRNode {
  /** Discriminating property for IRNodes */
  readonly $type: string
  /** (Stable) ID for this IRNode */
  readonly id: IRId
}

export const IRNode = Schema.Struct({
  $type: Schema.String,
  id: IRId,
})

/*******************************
     IR node for Ladder viz
********************************/

export interface FunDecl extends IRNode {
  readonly $type: 'FunDecl'
  readonly name: Name
  readonly params: readonly Name[] // TODO: Will worry about adding type info later
  readonly body: IRExpr
}

/** The Ladder graph visualizer focuses on boolean formulas. */
export type IRExpr =
  | And
  | Or
  | Not
  | Implies
  | UBoolVar
  | TrueE
  | FalseE
  | App
  | InertE

/* Thanks to Andres for pointing out that an n-ary representation would be better for the arguments for And / Or.
It's one of those things that seems obvious in retrospect; to quote
Brent Yorgey: "The set of booleans forms a monoid under conjunction (with identity True), disjunction (with identity False)" */

/**
* Preconditions / assumptions
* - The visualizer assumes that any nested ANDs/ORs have already been 'flattened'.
    E.g., nested exprs like (AND [a (AND [b])]) should have already been rewritten to (AND [a b]).
    This should be done in order to reduce visual clutter in the generated graph; but the visualizer will not do this sort of flattening.
*/
export interface And extends IRNode {
  readonly $type: 'And'
  readonly args: readonly IRExpr[]
}

/**
* Preconditions / assumptions
* - The visualizer assumes that any nested ANDs/ORs have already been 'flattened'.
    E.g., nested exprs like (AND [a (AND [b])]) should have already been rewritten to (AND [a b]).
    This should be done in order to reduce visual clutter in the generated graph; but the visualizer will not do this sort of flattening.
*/
export interface Or extends IRNode {
  readonly $type: 'Or'
  readonly args: readonly IRExpr[]
}

export interface Not extends IRNode {
  readonly $type: 'Not'
  readonly negand: IRExpr
}

/**
 * Material implication — the SEAM between a rule's scope and its requirement
 * (ladder DESIGN §25).
 *
 * Emphatically NOT sugar for `Not scope Or requirement`. That expansion is
 * truth-functionally perfect and shape-destroying: it discards the scope /
 * requirement split — the first two questions anyone asks of a rule ("does this
 * bite me?", then "so what must be true?") — and, worse, it cannot tell apart the
 * two cases a reader most needs told apart. A window the rule never reached (N/A)
 * and a window that complies BOTH satisfy `NOT P OR Q`. Same value; different ink.
 *
 * Consumers that want only the Boolean FUNCTION (BDD compilation, question
 * ordering) may read it classically and are correct to. Consumers that draw a
 * PICTURE may not; use `expandImplies` if you have no seam of your own.
 */
export interface Implies extends IRNode {
  readonly $type: 'Implies'
  readonly scope: IRExpr
  readonly requirement: IRExpr
  /** The connective AS THE DRAFTER WROTE IT: `'IMPLIES'` or `'=>'`. §17's argument
   *  for inert prose, applied to the operator — the picture does not get to invent
   *  a register the source did not use. (Never `'MUST'`: there is no constitutive
   *  MUST in L4. MUST is regulative, and the ladder does not draw those.) */
  readonly seam: string
}

export interface App extends IRNode {
  readonly $type: 'App'
  readonly fnName: Name
  readonly args: readonly IRExpr[]
  /** Stable UUIDv5 derived from function name, atom label, and input refs. */
  readonly atomId: string
}

/** For the original Viz / IRExpr (as opposed to the values that the frontend evaluator uses) */
export type UBoolValue = Schema.Schema.Type<typeof UBoolValue>
export type BoolValue = Schema.Schema.Type<typeof BoolValue>
export type Value = UBoolValue

export type UBoolVar = Schema.Schema.Type<typeof UBoolVar>

/** Inert elements are grammatical scaffolding that always evaluate to True */
export type InertE = Schema.Schema.Type<typeof InertE>

/***********************************
  The corresponding Effect Schemas
************************************/

export const IRExpr = Schema.Union(
  Schema.suspend((): Schema.Schema<And> => And),
  Schema.suspend((): Schema.Schema<Or> => Or),
  Schema.suspend((): Schema.Schema<Not> => Not),
  Schema.suspend((): Schema.Schema<Implies> => Implies),
  Schema.suspend((): Schema.Schema<UBoolVar> => UBoolVar),
  Schema.suspend((): Schema.Schema<TrueE> => TrueE),
  Schema.suspend((): Schema.Schema<FalseE> => FalseE),
  Schema.suspend((): Schema.Schema<App> => App),
  Schema.suspend((): Schema.Schema<InertE> => InertE)
).annotations({ identifier: 'IRExpr' })

export const App = Schema.Struct({
  $type: Schema.tag('App'),
  id: IRId,
  fnName: Name,
  args: Schema.Array(IRExpr),
  /** Stable UUIDv5 derived from function name, atom label, and input refs. */
  atomId: Schema.String,
}).annotations({ identifier: 'App' })

// // TODO: Need to look more carefully at L4's NamedExpr
// export const NamedExpr = Schema.Struct({
//   $type: Schema.tag('NamedExpr'),
//   id: IRId,
//   name: Name,
//   expr: IRExpr,
// }).annotations({ identifier: 'NamedExpr' })

// export const AppNamed = Schema.Struct({
//   $type: Schema.tag('AppNamed'),
//   id: IRId,
//   fnName: Name,
//   args: Schema.Array(NamedExpr),
// }).annotations({ identifier: 'AppNamed' })

export const FunDecl = Schema.Struct({
  $type: Schema.tag('FunDecl'),
  id: IRId,
  name: Name,
  params: Schema.Array(Name),
  body: IRExpr,
}).annotations({ identifier: 'FunDecl' })

export const And = Schema.Struct({
  $type: Schema.tag('And'),
  id: IRId,
  args: Schema.Array(IRExpr),
}).annotations({ identifier: 'And' })

export const Or = Schema.Struct({
  $type: Schema.tag('Or'),
  id: IRId,
  args: Schema.Array(IRExpr),
}).annotations({ identifier: 'Or' })

export const Not = Schema.Struct({
  $type: Schema.tag('Not'),
  negand: IRExpr,
  id: IRId,
}).annotations({ identifier: 'Not' })

export const Implies = Schema.Struct({
  $type: Schema.tag('Implies'),
  id: IRId,
  scope: IRExpr,
  requirement: IRExpr,
  seam: Schema.String,
}).annotations({ identifier: 'Implies' })

export const BoolValue = Schema.Union(
  Schema.Literal('FalseV'),
  Schema.Literal('TrueV')
)
export const UBoolValue = Schema.Union(BoolValue, Schema.Literal('UnknownV'))

export const UBoolVar = Schema.Struct({
  $type: Schema.tag('UBoolVar'),
  value: UBoolValue,
  id: IRId,
  name: Name,
  canInline: Schema.Boolean,
  /** Stable UUIDv5 derived from function name, atom label, and input refs. */
  atomId: Schema.String,
  /**
   * The atom's BOOLEAN `TYPICALLY` default, if it refers to a boolean binder
   * that declared one (`TRUE`/`FALSE`); otherwise `null`/absent. Populated by
   * the Haskell ladder builder. A rebuttable presumption (§22): drives both the
   * tentative rendering and the question-ordering prior. Only boolean binders
   * contribute — a numeric/string `TYPICALLY` is never a probability over a
   * derived comparison, so it never appears here. See `typicallyBridge`.
   */
  typically: Schema.optional(Schema.NullOr(Schema.Boolean)),
}).annotations({ identifier: 'UBoolVar' })

/** We have an IRId even for bool lits b/c it's useful to be able to associate IRExprs with the Lir nodes that they get translated to */
export const TrueE = Schema.Struct({
  $type: Schema.tag('TrueE'),
  id: IRId,
  name: Name,
}).annotations({ identifier: 'TrueE' })
export type TrueE = Schema.Schema.Type<typeof TrueE>

export const FalseE = Schema.Struct({
  $type: Schema.tag('FalseE'),
  id: IRId,
  name: Name,
}).annotations({ identifier: 'FalseE' })
export type FalseE = Schema.Schema.Type<typeof FalseE>

/**
 * Context for inert elements - determines evaluation value.
 * InertAnd → evaluates to True (identity for AND)
 * InertOr → evaluates to False (identity for OR)
 */
export type InertContext = Schema.Schema.Type<typeof InertContext>
export const InertContext = Schema.Union(
  Schema.Literal('InertAnd'),
  Schema.Literal('InertOr')
).annotations({ identifier: 'InertContext' })

/**
 * Inert elements are grammatical scaffolding that evaluate to the identity
 * for their containing boolean operator (True for AND, False for OR).
 */
export const InertE = Schema.Struct({
  $type: Schema.tag('InertE'),
  id: IRId,
  /** The inert text (grammatical scaffolding) */
  text: Schema.String,
  /** Context determines evaluation: InertAnd→True, InertOr→False */
  context: InertContext,
}).annotations({ identifier: 'InertE' })

/***********************************
  Wrapper / Protocol interfaces
************************************/

/** The payload for RenderAsLadder */
export type RenderAsLadderInfo = Schema.Schema.Type<typeof RenderAsLadderInfo>

export const RenderAsLadderInfo = Schema.Struct({
  verDocId: VersionedDocId,
  funDecl: FunDecl,
}).annotations({ identifier: 'RenderAsLadderInfo' })

/*************************
    Decode
**************************/

export function makeVizInfoDecoder() {
  return Schema.decodeUnknownEither(RenderAsLadderInfo)
}

/***********************************
      Implication, classically
************************************/

/** Largest node id anywhere in the tree — so a rewrite can mint ids that cannot collide. */
function maxNodeId(e: IRExpr): number {
  switch (e.$type) {
    case 'And':
    case 'Or':
      return e.args.reduce((m, a) => Math.max(m, maxNodeId(a)), e.id.id)
    case 'Not':
      return Math.max(e.id.id, maxNodeId(e.negand))
    case 'Implies':
      return Math.max(e.id.id, maxNodeId(e.scope), maxNodeId(e.requirement))
    case 'App':
      return e.args.reduce((m, a) => Math.max(m, maxNodeId(a)), e.id.id)
    default:
      return e.id.id
  }
}

/**
 * Rewrite every `Implies` to its classical equivalent, `NOT scope OR requirement`.
 *
 * This is a LOSSY rewrite, and deliberately so — it is the escape hatch for
 * consumers that have no seam of their own and must render or compile something
 * anyway (chiefly the original ladder visualizer, whose LIR predates `Implies`).
 * What it loses is precisely what DESIGN §25 is about: after this runs, a rule that
 * never reached the case and a rule the case satisfies are the same TRUE, and no
 * downstream picture can tell them apart. If you are drawing, prefer the seam.
 *
 * Node ids are preserved where they can be (the `Or` inherits the `Implies`' id,
 * which is now free); the one synthesized `Not` per implication gets a fresh id
 * minted past the tree's maximum, so nothing collides with a positional key.
 */
export function expandImplies(expr: IRExpr): IRExpr {
  let next = maxNodeId(expr) + 1
  const fresh = (): IRId => ({ id: next++ })
  const go = (e: IRExpr): IRExpr => {
    switch (e.$type) {
      case 'Implies': {
        const not: Not = {
          $type: 'Not',
          id: fresh(),
          negand: go(e.scope),
        }
        const or: Or = {
          $type: 'Or',
          id: e.id,
          args: [not, go(e.requirement)],
        }
        return or
      }
      case 'And':
        return { ...e, args: e.args.map(go) }
      case 'Or':
        return { ...e, args: e.args.map(go) }
      case 'Not':
        return { ...e, negand: go(e.negand) }
      case 'App':
        return { ...e, args: e.args.map(go) }
      default:
        return e
    }
  }
  return go(expr)
}

/***********************************
        TYPICALLY bridge
************************************/

/**
 * Soft prior weights for a boolean atom's `TYPICALLY` presumption (question-
 * ordering spec §4 / §6.1): soft (0.9 / 0.1), not hard (1 / 0), so a presumed
 * atom sinks to the end of the ask-order yet is still asked if it would flip the
 * outcome — safer for high-stakes rules.
 */
export const TYPICALLY_TRUE_WEIGHT = 0.9
export const TYPICALLY_FALSE_WEIGHT = 0.1

/** Structural mirror of ladder-core's `Provenance` (kept local so `@repo/viz-expr`
 *  needs no dependency on `@repo/ladder-core`). */
export type TypicallyProvenance = 'given' | 'default'

export interface TypicallyMaps {
  /**
   * Per-atom prior P(atom = TRUE), keyed by `name.unique`. Only atoms whose
   * binder declared a boolean `TYPICALLY` appear; an absent entry means
   * prior-free (0.5 downstream). Feed straight into `compileDecisionQuery`'s
   * `weights` parameter.
   */
  readonly weights: ReadonlyMap<Unique, number>
  /**
   * Per-node provenance keyed by `id.id` (the positional NodeId). Only nodes
   * riding a `TYPICALLY` presumption are recorded, as `default` (render
   * tentative); everything else is implicitly `given` (absent ⇒ given, matching
   * `ViewSpec.provenance`). Feed into the ladder ViewSpec's `provenance` map.
   */
  readonly provenance: ReadonlyMap<number, TypicallyProvenance>
}

/**
 * The single shared extraction (question-ordering spec §8, "build once, two
 * consumers"): ONE walk over the wire IR reads each `UBoolVar.typically` and
 * produces BOTH the question-ordering weights and the tentative-render
 * provenance. Do not re-derive either map elsewhere — that is the duplication
 * the spec forbids.
 *
 * Only boolean binders contribute a weight (a numeric/string `TYPICALLY` is not
 * a probability over a derived comparison, so the Haskell side never sets
 * `typically` for those — this walk simply trusts that field).
 */
export function typicallyBridge(expr: IRExpr): TypicallyMaps {
  const weights = new Map<Unique, number>()
  const provenance = new Map<number, TypicallyProvenance>()
  const go = (e: IRExpr): void => {
    switch (e.$type) {
      case 'UBoolVar': {
        const t = e.typically
        if (t === true || t === false) {
          weights.set(
            e.name.unique,
            t ? TYPICALLY_TRUE_WEIGHT : TYPICALLY_FALSE_WEIGHT
          )
          provenance.set(e.id.id, 'default')
        }
        return
      }
      case 'Not':
        go(e.negand)
        return
      // The seam is not a barrier: an atom's prior is a fact about the atom, and a
      // rule's atoms live on BOTH sides of the implication.
      case 'Implies':
        go(e.scope)
        go(e.requirement)
        return
      case 'And':
      case 'Or':
        e.args.forEach(go)
        return
      // App / TrueE / FalseE / InertE carry no atom prior; App is an opaque
      // leaf atom (its args are not decision-query variables).
      default:
        return
    }
  }
  go(expr)
  return { weights, provenance }
}

/***********************************
        Examples of usage
************************************/

// Example of how to use Effect to decode an unknown input

// const decode = Schema.decodeUnknownEither(IRExpr)

/** Example of an unknown input */
// const egAtomicPropWalks = {
//   $type: 'UBoolVar',
//   value: 'True',
//   id: { id: 1 },
//   name: { label: 'walks', unique: 2 }
// }

// const result = decode(egAtomicPropWalks)
// console.log(result)

/*************************
    Utils
**************************/

/** See https://effect.website/docs/schema/pretty/ */
export function getLadderIRPrettyPrinter() {
  return Pretty.make(RenderAsLadderInfo)
}

/** Get a JSON Schema version of the RenderAsLadderInfo */
export function exportRenderAsLadderInfoToJSONSchema() {
  return JSON.stringify(JSONSchema.make(RenderAsLadderInfo))
}
// console.log(exportRenderAsLadderInfoToJSONSchema())
