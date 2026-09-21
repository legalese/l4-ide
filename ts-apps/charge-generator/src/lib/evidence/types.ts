/**
 * The evidence graph: Charge → Element → Fact → Source.
 *
 * A charge asserts that every element of the offence is fulfilled (CPC 2010
 * s 123(5)). Each element rests on facts; each fact rests on something an
 * investigating officer can produce. The source kinds follow Singapore practice
 * rather than the "affidavit" of the original brief:
 */
export type SourceKind =
  /** A witness's statement recorded by the police under CPC s 22. */
  | 'witness-statement-s22'
  /** The accused's statement after the s 23 caution. */
  | 'cautioned-statement-s23'
  /** A conditioned statement admissible without the maker under s 264. */
  | 'conditioned-statement-s264'
  /** Real evidence, marked as an exhibit (P1, P2, …). */
  | 'exhibit'
  /** Documents, CCTV, records. */
  | 'documentary'
  /** A Health Sciences Authority or other expert report. */
  | 'forensic-report'
  /** The First Information Report — how the police came to know. */
  | 'first-information-report'
  /** A file the officer uploaded to the interview, before it is classified. */
  | 'upload'

export const SOURCE_KIND_LABEL: Record<SourceKind, string> = {
  'witness-statement-s22': 'Witness statement (CPC s 22)',
  'cautioned-statement-s23': 'Cautioned statement (CPC s 23)',
  'conditioned-statement-s264': 'Conditioned statement (CPC s 264)',
  exhibit: 'Exhibit',
  documentary: 'Documentary',
  'forensic-report': 'Forensic report',
  'first-information-report': 'First Information Report',
  upload: 'Uploaded file',
}

export interface Source {
  readonly id: string
  readonly kind: SourceKind
  /** "Statement of Wong Fei Hsia", "Exhibit P3 — the price tag". */
  readonly title: string
  /** Who made it, if a statement. */
  readonly maker?: string
}

export interface Fact {
  readonly id: string
  /** One sentence, in the officer's words. */
  readonly text: string
  /** Where it comes from. Empty = asserted, not yet sourced. */
  readonly sourceIds: readonly string[]
  /** A quotation from the source, if the interview extracted one. */
  readonly quote?: string
}

/** An element of a charge (a ladder leaf) and the facts it rests on. */
export interface ElementSupport {
  readonly section: string
  /** The facts-record path of the leaf, joined with '/'. */
  readonly field: string
  readonly factIds: readonly string[]
}

export interface EvidenceGraph {
  readonly sources: readonly Source[]
  readonly facts: readonly Fact[]
  readonly support: readonly ElementSupport[]
}

export const EMPTY_GRAPH: EvidenceGraph = {
  sources: [],
  facts: [],
  support: [],
}
