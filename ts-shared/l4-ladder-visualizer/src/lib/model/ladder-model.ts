/**
 * LadderModel — the LIR-free ladder model (E1 Step 3, DESIGN §11 "Replace").
 *
 * This is the seam of the whole IDE integration. The old renderer built its evaluator and
 * partial-eval from a tree that `expandImplies` had already flattened (viz-expr-to-lir.ts:73),
 * so the IMPLIES seam was gone before evaluation and the header could only ever say
 * "evaluates to TRUE" — the §25f category error. This model feeds the **raw** wire `FunDecl`
 * to the SAME `Evaluator` and `PartialEvalAnalyzer` (both already carry `Implies` arms), so the
 * seam survives to the verdict for free, and draws through `@repo/ladder-core` instead of Dagre.
 *
 * It is deliberately framework-free: no `LirContext`, no runes. It owns the eval state and
 * derives a `ViewSpec` + `Verdict`; the Svelte displayer (Step 4) holds one of these in `$state`
 * and calls `recompute()` on interaction. That split is the project's own thesis — a pure core
 * with a thin reactive shell — applied to the model layer, and it is what makes the logic here
 * unit-testable without a browser.
 *
 * Scope: this step is the LOCAL partial-eval path. Folding the LSP query-plan asks back in
 * (`elicitationOverrideFromQueryPlan`) and App evaluation via `evalApp` ride on later steps; the
 * hooks (`l4Connection`, `verDocId`) are already threaded so they can land without a reshape.
 */
import type {
  FunDecl as VizFunDecl,
  Unique,
  VersionedDocId,
} from '@repo/viz-expr'
import { fromVizFunDecl, verdictFor, defaultViewSpec } from '@repo/ladder-core'
import type {
  DecodedViz,
  IRExpr,
  NodeId,
  UBoolValue,
  Verdict,
  ViewSpec,
  State,
} from '@repo/ladder-core'
import { Assignment } from '../eval/assignment.js'
import { Evaluator } from '../eval/eval.js'
import type { EvalResult } from '../eval/eval.js'
import { PartialEvalAnalyzer } from '../eval/partial-eval.js'
import type { PartialEvalAnalysis } from '../eval/partial-eval.js'
import {
  veExprToEvExpr,
  toUBoolVal,
  toVEBoolValue,
  cycle,
} from '../eval/type.js'
import type { Expr } from '../eval/type.js'
import type { L4Connection } from '../l4-connection.js'

/** Which elicitation cue a box should wear (DESIGN §19; the ink half of Step 6). */
export type ElicitationMark = 'next' | 'needed'

export interface LadderModelDeps {
  /** Needed only for `App` evaluation (`evalApp`) and inlining; unused for a pure-boolean tree. */
  readonly l4Connection: L4Connection
  readonly verDocId: VersionedDocId
}

export class LadderModel {
  /** The decoded ladder tree + identity index + lifted valuation/provenance (Step 1). */
  readonly decoded: DecodedViz
  /** The RAW wire body, as the evaluator's `Expr` — seam intact, never `expandImplies`d. */
  readonly #evalExpr: Expr
  readonly #analyzer: PartialEvalAnalyzer
  readonly #deps: LadderModelDeps

  #assignment: Assignment
  #foldSet = new Set<NodeId>()
  #evalResult: EvalResult | null = null
  #analysis: PartialEvalAnalysis | null = null
  /** Built once, lazily, by `getLabelForUnique`. */
  #labelByUnique: Map<Unique, string> | null = null

  constructor(funDecl: VizFunDecl, deps: LadderModelDeps) {
    this.decoded = fromVizFunDecl(funDecl)
    this.#evalExpr = veExprToEvExpr(funDecl.body)
    this.#analyzer = new PartialEvalAnalyzer(funDecl.body)
    this.#deps = deps
    this.#assignment = this.#seedAssignment()
  }

  /** Seed the per-Unique assignment from the inline per-node values (Step 1's `valuation`).
   *  The assignment must be DENSE — every atom present, defaulting to `UnknownV` — because the
   *  evaluator reads `assignment.get(unique)` unconditionally and a hole would surface downstream
   *  as `undefined.$type` (matching the old LIR's `getInitialValue` seeding). A repeated
   *  proposition has one Unique, so its several positions collapse to one entry — right, since
   *  they are the same atom and share a value. */
  #seedAssignment(): Assignment {
    const entries: Array<[number, ReturnType<typeof toUBoolVal>]> = []
    for (const [nodeId, unique] of this.decoded.uniqueByNode)
      entries.push([
        unique,
        toUBoolVal(this.decoded.valuation.get(nodeId) ?? 'UnknownV'),
      ])
    return Assignment.fromEntries(entries)
  }

  /* --------------------------------------------------------------- interaction */

  /** Cycle a leaf's value (T→F→U→T) and return whether anything changed. The caller awaits
   *  `recompute()` afterwards. `App` leaves have no Unique (they eval on the backend), so a
   *  click on one is a no-op here — Step 6 routes it through `evalApp`. */
  cycleValue(nodeId: NodeId): boolean {
    const unique = this.decoded.uniqueByNode.get(nodeId)
    if (unique === undefined) return false
    const current = this.#assignment.get(unique) ?? toUBoolVal('UnknownV')
    this.#assignment.set(unique, cycle(current))
    return true
  }

  /** Set a leaf to an explicit value, addressed POSITIONALLY — this is the direction a
   *  click on the picture arrives in, and the node→Unique lookup is what fans one binding
   *  out to every drawn position of a repeated atom (R2). */
  setValue(nodeId: NodeId, value: UBoolValue): boolean {
    const unique = this.decoded.uniqueByNode.get(nodeId)
    if (unique === undefined) return false
    this.#assignment.set(unique, toUBoolVal(value))
    return true
  }

  /**
   * Set an atom by `Unique` — the space the sidebar assigns in.
   *
   * NOTE this is deliberately NOT an R2 fan-out over `nodesByUnique`. The assignment is
   * ALREADY Unique-keyed (see `cycleValue` / `setValue` above, which exist precisely to
   * translate the other way), and the evaluator spreads one binding to every drawn position
   * by itself. Writing the same key once per node would be harmless and would tell the next
   * reader something false about how `#assignment` is keyed.
   *
   * An unknown `Unique` is accepted rather than rejected: the assignment is dense over the
   * atoms that exist, and a stray key simply never gets read.
   */
  setValueForUnique(unique: Unique, value: UBoolValue): void {
    this.#assignment.set(unique, toUBoolVal(value))
  }

  /**
   * The label to show for an atom, for the sidebar's buckets.
   *
   * The LIR had `#uniqueToLabel` built during graph construction; the decoded tree has no
   * label index — `DecodedViz` carries uniqueByNode / nodesByUnique / atomIdByNode /
   * nodesByAtomId and no labels — so build one lazily off `decoded.fn` and keep it. First
   * drawn position wins, which is not a coin-flip: a repeated proposition has ONE Unique,
   * and the wire gives every occurrence of it the same label.
   *
   * Falls back to `#<unique>` rather than throwing: a Unique can reach here from the
   * analysis for an atom the drawn tree does not contain (an `App`'s arguments, say), and a
   * sidebar row with an ugly name beats a crash.
   */
  getLabelForUnique(unique: Unique): string {
    if (!this.#labelByUnique) {
      const m = new Map<Unique, string>()
      const walk = (e: IRExpr): void => {
        switch (e.$type) {
          case 'And':
          case 'Or':
            e.args.forEach(walk)
            return
          case 'Not':
            walk(e.negand)
            return
          case 'Implies':
            walk(e.scope)
            walk(e.requirement)
            return
          case 'InertE':
            return
          default:
            // `leaf.unique !== undefined ⟺ leaf ∈ nodesByUnique` (ladder-core types.ts) —
            // set for UBoolVar only, which is exactly the set the sidebar can bind.
            if (e.unique !== undefined && !m.has(e.unique))
              m.set(e.unique, e.label)
        }
      }
      walk(this.decoded.fn.body)
      this.#labelByUnique = m
    }
    return this.#labelByUnique.get(unique) ?? `#${unique}`
  }

  toggleFold(nodeId: NodeId): void {
    if (this.#foldSet.has(nodeId)) this.#foldSet.delete(nodeId)
    else this.#foldSet.add(nodeId)
  }

  resetBindings(): void {
    this.#assignment = this.#seedAssignment()
    this.#evalResult = null
    this.#analysis = null
  }

  /** Run the evaluator + partial-eval over the current assignment. Async because `App` leaves
   *  round-trip to the backend; a pure-boolean tree resolves without touching it. */
  async recompute(): Promise<void> {
    this.#evalResult = await Evaluator.eval(
      this.#deps.l4Connection,
      this.#deps.verDocId,
      this.#evalExpr,
      this.#assignment
    )
    this.#analysis = this.#analyzer.analyze(this.#assignment, this.#evalResult)
  }

  /* ------------------------------------------------------------------ readouts */

  /** Positional T/F/U per node, projected from the eval result. `intermediate` is keyed by the
   *  wire `IRId` object (`{ id }`), whose `.id` IS the ladder `NodeId` (`fromVizFunDecl` preserves
   *  it) — so this is a value-type conversion plus an unwrap, not a lookup. Before the first
   *  `recompute()`, falls back to the inline valuation Step 1 lifted. */
  get valuation(): Map<NodeId, UBoolValue> {
    if (!this.#evalResult) return new Map(this.decoded.valuation)
    const out = new Map<NodeId, UBoolValue>()
    for (const [irId, val] of this.#evalResult.intermediate)
      out.set(irId.id, toVEBoolValue(val))
    return out
  }

  /**
   * The verdict for the header — NOT the raw truth value (§25f). This is the PICTURE's verdict
   * (`verdictFor`, Kleene), so the header says exactly what the ladder draws. It is SOUND: every
   * definite verdict is correct. It is not COMPLETE: on a tautological/contradictory subformula
   * with an unknown atom it is conservatively `Undetermined` where the wizard's ROBDD would
   * settle (the Step 1 adversarial review found this). That is the right trade for a header sat
   * on the ladder — but if a later step wants the header to match the wizard sidebar EXACTLY, the
   * sharper verdict is available off the query engine when the tree is App-free. Tracked as a
   * follow-up; not worth a redundant BDD compile here until the sidebar integration (Step 6)
   * makes any divergence visible.
   */
  get verdict(): Verdict {
    return verdictFor(this.decoded.fn, this.valuation)
  }

  /** The `ViewSpec` to hand `layout()`. `eliminable` nodes come from the partial-eval's
   *  irrelevant roots (DESIGN §15); provenance is Step 1's lifted TYPICALLY — the first time
   *  it reaches this component at all. */
  get viewSpec(): ViewSpec {
    const states = new Map<NodeId, State>()
    if (this.#analysis)
      for (const irId of this.#analysis.irrelevantRootIds)
        states.set(irId.id, 'eliminable') // IRId {id} -> ladder NodeId
    return defaultViewSpec({
      valuation: this.valuation,
      provenance: this.decoded.provenance,
      states,
      foldSet: new Set(this.#foldSet),
      showCurrent: true,
    })
  }

  /** Which boxes to mark for elicitation, mapped from the analysis's Unique-space answer to
   *  every drawn position of each atom (`nodesByUnique` — the R2 fan-out earns its keep here).
   *  `next` (most valuable to ask) wins over `needed` when an atom is both. */
  get elicitationMarks(): Map<NodeId, ElicitationMark> {
    const marks = new Map<NodeId, ElicitationMark>()
    if (!this.#analysis) return marks
    const paint = (uniques: readonly number[], mark: ElicitationMark) => {
      for (const u of uniques)
        for (const nodeId of this.decoded.nodesByUnique.get(u) ?? [])
          if (mark === 'next' || !marks.has(nodeId)) marks.set(nodeId, mark)
    }
    // paint 'needed' first, then let 'next' overwrite it
    paint(this.#analysis.stillNeeded, 'needed')
    paint(this.#analysis.ranked, 'needed')
    paint(this.#analysis.next, 'next')
    return marks
  }

  /** The partial-eval analysis, for the "Still Needed" sidebar (reused as-is in Step 4). */
  get analysis(): PartialEvalAnalysis | null {
    return this.#analysis
  }

  /** True once the function's value is settled. Note this is NOT the verdict: a settled TRUE
   *  can still be `NotApplicable` (§25f), which is why the header reads `verdict`, not this. */
  get isDetermined(): boolean {
    return this.#analysis?.isDetermined ?? false
  }
}
