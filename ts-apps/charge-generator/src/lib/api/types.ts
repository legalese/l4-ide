// Shared schema types come from the jl4-client-rpc package ROOT (the
// '/custom-protocol' subpath is not exported).
export type {
  FunctionParameter,
  FunctionParameters,
  ExportedFunctionInfo,
} from 'jl4-client-rpc'

/** The arguments object of a POST …/evaluation: one key per GIVEN. */
export type FormState = Record<string, unknown>

/**
 * The `Charge` record of `penal-code-general.l4`, as the wire returns it —
 * keys are the L4 field names verbatim. Validated on arrival in `validate.ts`:
 * a redeployed corpus could rename a field, and an unvalidated `false` on
 * `made out` would read as a refusal rather than a broken wire.
 */
export interface Charge {
  section: string
  offence: string
  'made out': boolean
  text: string
  refusal: string
  punishment: string
}

export type Verdict =
  | 'true'
  | 'false'
  | 'undetermined'
  | 'unknown'
  | 'error'
  | string

export interface PlanAtom {
  atomId: string
  label: string
  unique: number
  inputRefs: string[]
}

export interface QueryPlanResponse {
  verdict: Verdict
  determined: boolean | null
  ranked: PlanAtom[]
  stillNeeded: PlanAtom[]
  ladder: unknown
  note?: string
}
