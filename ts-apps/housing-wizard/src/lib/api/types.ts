// Shared schema types come from the jl4-client-rpc package ROOT. (The
// '/custom-protocol' subpath is NOT exported — the package exports only '.', so
// importing the subpath fails under moduleResolution:bundler.)
export type {
  FunctionParameter,
  FunctionParameters,
  ExportedFunctionInfo,
} from 'jl4-client-rpc'

// The wizard's view of the function's RETURN value — the five verified live keys
// of the L4 `PossessionAssessment` record. The AnswerCard reads these directly
// and performs no independent legal reasoning, so it can never drift from the
// engine.
export interface PossessionAssessment {
  'possession can be ordered': boolean
  'it is mandatory': boolean
  'grounds made out': string[]
  reasons: string[]
  'what this means': string
}

// The jl4-service evaluation response envelope. The success value is wrapped
// under the return-type NAME (e.g. { PossessionAssessment: {...} }). Kept for
// documentation; the client narrows from `unknown` defensively rather than
// trusting this shape blindly.
export type EvalEnvelope =
  | {
      tag: 'SimpleResponse'
      contents: { result: { value: Record<string, unknown> } }
    }
  | { tag: 'Error'; contents: { tag: string; contents: string } }

// The collected form facts. A recursive plain object keyed by the ORIGINAL
// spaced L4 field names (the keys the eval endpoint expects).
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
