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

export type NodeId = number

/** Mirror of viz-expr's UBoolValue. */
export type UBoolValue = 'TrueV' | 'FalseV' | 'UnknownV'

/** Operative atom — carries current; renders as a BOX. */
export interface Leaf {
  readonly $type: 'UBoolVar' | 'App' | 'TrueE' | 'FalseE'
  readonly id: NodeId
  readonly label: string
  readonly atomId?: string
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
  readonly $type: 'InertE'
  readonly id: NodeId
  readonly text: string
  readonly context: 'InertAnd' | 'InertOr'
}

/**
 * OPTIONAL human name for a subtree (see DESIGN §16 / answer to "does the IR need
 * a way to label a subtree?"). Today the wire IR has NO such field on And/Or;
 * absent => the core synthesizes a label. When present (e.g. fed from the L4
 * DECIDE/Where name a subtree was inlined from, via a NamedExpr wrapper), folding
 * shows something legible like "there is a deception".
 */
export interface And {
  readonly $type: 'And'
  readonly id: NodeId
  readonly args: readonly IRExpr[]
  readonly label?: string
}

export interface Or {
  readonly $type: 'Or'
  readonly id: NodeId
  readonly args: readonly IRExpr[]
  readonly label?: string
}

export interface Not {
  readonly $type: 'Not'
  readonly id: NodeId
  readonly negand: IRExpr
}

export type IRExpr = Leaf | Inert | And | Or | Not

export interface FunDecl {
  readonly id: NodeId
  readonly name: string
  readonly params: readonly string[]
  readonly body: IRExpr
}

/* -------------------------------------------------------------- ViewSpec */

/** Orthogonal to T/F/U; see DESIGN §15.1. Default 'inert'. */
export type State = 'live' | 'inert' | 'dead' | 'eliminable'

export type Scale = 'full' | 'small' | 'tiny'
export type Orient = 'LR' | 'TB'
export type Theme = 'screen' | 'ink'

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
export type ConnectiveStyle = 'on-wire' | 'above-wire' | 'below-wire' | 'straddle-wire'

export interface ViewSpec {
  readonly foldSet: ReadonlySet<NodeId>
  readonly states: ReadonlyMap<NodeId, State>
  readonly scale: Scale
  readonly orient: Orient
  readonly theme: Theme
  readonly connectiveStyle: ConnectiveStyle
}

export function defaultViewSpec(partial: Partial<ViewSpec> = {}): ViewSpec {
  return {
    foldSet: partial.foldSet ?? new Set(),
    states: partial.states ?? new Map(),
    scale: partial.scale ?? 'full',
    orient: partial.orient ?? 'LR',
    theme: partial.theme ?? 'screen',
    connectiveStyle: partial.connectiveStyle ?? 'straddle-wire',
  }
}

/* -------------------------------------------------------------- Scene IR */

export interface Pt {
  x: number
  y: number
}
export interface Rect {
  x: number
  y: number
  w: number
  h: number
}

export type ScenePrim =
  | {
      kind: 'box'
      id: NodeId
      rect: Rect
      role: 'leaf' | 'placeholder'
      state: State
      folded?: boolean
    }
  | { kind: 'wire'; path: Pt[]; role: 'rail' | 'rung' | 'stub'; state: State }
  | { kind: 'glyph'; at: Pt; role: 'open-contact' | 'power-terminal' }
  | {
      kind: 'text'
      at: Pt
      text: string
      anchor: 'start' | 'middle'
      state: State
      tag?: 'otiose' | 'title' | 'note' | 'heading' | 'connective'
      size?: number
      /** node id this text belongs to (heading -> its group; label -> its box) —
       *  used by renderers for click targets and FLIP matching. */
      id?: NodeId
    }

export interface Scene {
  size: { w: number; h: number }
  prims: ScenePrim[]
}

/* -------------------------------------------------------------- TextMetrics */

/**
 * Injected (DESIGN §3.2). P0 uses a cheap estimator; browser uses Canvas
 * measureText; Node-for-print uses fontkit on the SAME font (font parity, §4.4).
 */
export interface TextMetrics {
  width(text: string, sizePx: number): number
  lineHeight(sizePx: number): number
}
