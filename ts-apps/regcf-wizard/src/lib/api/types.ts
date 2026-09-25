// Shared schema types come from the jl4-client-rpc package ROOT. (The
// '/custom-protocol' subpath is NOT exported — the package exports only '.', so
// importing the subpath fails under moduleResolution:bundler.)
export type {
  FunctionParameter,
  FunctionParameters,
  ExportedFunctionInfo,
} from 'jl4-client-rpc'

// ---------------------------------------------------------------------------
// The four record return types of `regcf-wizard.l4`, transcribed from the LIVE
// wire (not from the .l4 source) so the field names below are the JSON keys.
// Every one is validated on arrival: a redeployed or edited façade — exactly the
// drafter-authored workflow this demo showcases — could drop or rename a key,
// and an unvalidated `false` reads as a clean bill of health.
//
// MAYBE fields arrive as `null` when absent (measured: an accredited investor's
// `your 12 month limit` is `null`, not an object). That is the agreed lowering.
// ---------------------------------------------------------------------------

export interface RaiseAssessment {
  'you can use Reg CF': boolean
  'the most you can raise now': number
  blockers: string[]
  'financial statements you must provide': string
  'why those financial statements': string
  'what you must still line up': string[]
  'after you raise you must': string[]
  caveats: string[]
  /** R8's disclosure for the founder surface: the date this answer states. */
  'law as in force': string
}

export interface InvestmentLimitAnswer {
  'you have no limit': boolean
  'your 12 month limit': number | null
  'you have already used': number
  'you can still invest': number | null
  'we measured against': number
  'which limb applies': string
  'how this is worked out': string
  caveats: string[]
}

export interface ResaleAnswer {
  'you may transfer': boolean
  'days you must still wait': number
  why: string
  caveats: string[]
}

export interface ReportingExitAnswer {
  'you may stop reporting': boolean
  'the conditions that let you stop': string[]
  'while the duty runs you must': string[]
  caveats: string[]
}

// ---------------------------------------------------------------------------
// The elicitation (query-plan) wire shapes — the subset this client reads.
// ---------------------------------------------------------------------------

/** The six-value verdict vocabulary, as `Backend/DecisionQueryPlan.hs` emits it. */
export type Verdict =
  | 'Holds'
  | 'Fails'
  | 'Undetermined'
  | 'Vacuous'
  | 'Inconsistent'
  | 'Tautology'

export interface PlanAtom {
  atomId: string
  label: string
  /** The stable positional key. THIS is the ladder join key — see client.ts. */
  unique: number
  inputRefs: string[]
}

export interface QueryPlanResponse {
  verdict: Verdict
  determined: boolean | null
  ranked: PlanAtom[]
  stillNeeded: PlanAtom[]
  ladder?: unknown
  note?: string
}

// ---------------------------------------------------------------------------

/** The collected form facts. A recursive plain object keyed by the ORIGINAL
 *  spaced L4 field names (the keys the eval endpoint expects). */
export type FormValue =
  | string
  | number
  | boolean
  | null
  | FormState
  | FormValue[]
export interface FormState {
  [key: string]: FormValue
}
