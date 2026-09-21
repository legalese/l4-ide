/**
 * The offences the corpus at `canon/subjects/sg/penal-code-1871/encodings/legalese/`
 * exports, one entry per PUNISHING section — because a charge is laid under the
 * punishing section (CPC s 123(4)), while the ladder that says whether it is made
 * out is the DEFINING section's. The two are kept apart in the corpus and here.
 *
 * `definitionFns` are the boolean exports whose ladders are stacked above the
 * offence ladder on a card: a call to another rule is drawn as ONE leaf on the
 * caller's ladder (`cheats f`), and the reader opens the callee's ladder to see
 * inside it. `verdictFor` on the callee gives that leaf its value locally.
 *
 * Names are the L4 names verbatim; they are URL segments (encoded at use).
 */
export type Family =
  | 'cheating'
  | 'theft'
  | 'extortion'
  | 'robbery'
  | 'misappropriation'
  | 'cbt'
  | 'intimidation'
  | 'hurt'

export interface Offence {
  /** The punishing section, e.g. "420". */
  readonly section: string
  /** The name the Code gives the offence (CPC s 123(2)). */
  readonly title: string
  /** The defining section(s) the elements come from. */
  readonly defines: string
  readonly family: Family
  /** The boolean export the card's main ladder draws. */
  readonly offenceFn: string
  /** The `Charge`-returning export the recital comes from. */
  readonly chargeFn: string
  /** Boolean exports called from `offenceFn`, drawn as stacked sub-ladders. */
  readonly definitionFns: readonly string[]
  /** The facts record type the exports take. */
  readonly factsType: string
  /** The GIVEN name of that record in the exports. */
  readonly factsParam: string
}

export const OFFENCES: readonly Offence[] = [
  {
    section: '417',
    title: 'cheating',
    defines: 's 415',
    family: 'cheating',
    offenceFn: 'offence under s 417',
    chargeFn: 'charge under s 417',
    definitionFns: ['cheats'],
    factsType: 'Cheating Facts',
    factsParam: 'f',
  },
  {
    section: '420',
    title: 'cheating and dishonestly inducing a delivery of property',
    defines: 'ss 415, 420',
    family: 'cheating',
    offenceFn: 'offence under s 420',
    chargeFn: 'charge under s 420',
    definitionFns: ['cheats'],
    factsType: 'Cheating Facts',
    factsParam: 'f',
  },
  {
    section: '379',
    title: 'theft',
    defines: 's 378',
    family: 'theft',
    offenceFn: 'offence under s 379',
    chargeFn: 'charge under s 379',
    definitionFns: ['commits theft'],
    factsType: 'Theft Facts',
    factsParam: 'f',
  },
  {
    section: '380',
    title: 'theft in a dwelling',
    defines: 's 378 (with the place s 380 adds)',
    family: 'theft',
    offenceFn: 'offence under s 380',
    chargeFn: 'charge under s 380',
    definitionFns: ['commits theft'],
    factsType: 'Theft in Dwelling Facts',
    factsParam: 'f',
  },
  {
    section: '384',
    title: 'extortion',
    defines: 's 383',
    family: 'extortion',
    offenceFn: 'offence under s 384',
    chargeFn: 'charge under s 384',
    definitionFns: ['commits extortion'],
    factsType: 'Extortion Facts',
    factsParam: 'f',
  },
  {
    section: '392',
    title: 'robbery',
    defines: 's 390 (with ss 378, 383)',
    family: 'robbery',
    offenceFn: 'offence under s 392',
    chargeFn: 'charge under s 392',
    definitionFns: [
      'commits robbery',
      'theft is robbery',
      'extortion is robbery',
      'commits theft',
      'commits extortion',
    ],
    factsType: 'Robbery Facts',
    factsParam: 'f',
  },
  {
    section: '393',
    title: 'attempt to commit robbery',
    defines: 's 390(2) — the same violence, the taking not completed',
    family: 'robbery',
    offenceFn: 'offence under s 393',
    chargeFn: 'charge under s 393',
    definitionFns: [],
    factsType: 'Robbery Facts',
    factsParam: 'f',
  },
  {
    section: '394',
    title: 'voluntarily causing hurt in committing robbery',
    defines: 'ss 390, 394',
    family: 'robbery',
    offenceFn: 'offence under s 394',
    chargeFn: 'charge under s 394',
    definitionFns: [
      'commits robbery',
      'theft is robbery',
      'extortion is robbery',
      'commits theft',
      'commits extortion',
    ],
    factsType: 'Robbery Facts',
    factsParam: 'f',
  },
  {
    section: '403',
    title: 'dishonest misappropriation of property',
    defines:
      's 403 (this section both defines and punishes — the ladder IS the defining section)',
    family: 'misappropriation',
    offenceFn: 'offence under s 403',
    chargeFn: 'charge under s 403',
    definitionFns: [],
    factsType: 'Misappropriation Facts',
    factsParam: 'f',
  },
  {
    section: '406',
    title: 'criminal breach of trust',
    defines: 's 405',
    family: 'cbt',
    offenceFn: 'offence under s 406',
    chargeFn: 'charge under s 406',
    definitionFns: ['commits criminal breach of trust'],
    factsType: 'CBT Facts',
    factsParam: 'f',
  },
  {
    section: '407',
    title:
      'criminal breach of trust of property entrusted for transportation or storage',
    defines: 's 405 (with the capacity s 407 adds)',
    family: 'cbt',
    offenceFn: 'offence under s 407',
    chargeFn: 'charge under s 407',
    definitionFns: ['commits criminal breach of trust'],
    factsType: 'Aggravated CBT Facts',
    factsParam: 'c',
  },
  {
    section: '408',
    title: 'criminal breach of trust by an employee',
    defines: 's 405 (with the capacity s 408 adds)',
    family: 'cbt',
    offenceFn: 'offence under s 408',
    chargeFn: 'charge under s 408',
    definitionFns: ['commits criminal breach of trust'],
    factsType: 'Aggravated CBT Facts',
    factsParam: 'c',
  },
  {
    section: '409',
    title:
      'criminal breach of trust by a public servant, or by a banker, merchant, agent, director, officer, partner, key executive or fiduciary',
    defines: 's 405 (with the capacity s 409 adds)',
    family: 'cbt',
    offenceFn: 'offence under s 409',
    chargeFn: 'charge under s 409',
    definitionFns: ['commits criminal breach of trust'],
    factsType: 'Aggravated CBT Facts',
    factsParam: 'c',
  },
  {
    section: '506',
    title: 'criminal intimidation',
    defines: 's 503',
    family: 'intimidation',
    offenceFn: 'offence under s 506',
    chargeFn: 'charge under s 506',
    definitionFns: ['commits criminal intimidation'],
    factsType: 'Criminal Intimidation Facts',
    factsParam: 'f',
  },
  {
    section: '323A',
    title: 'voluntarily causing hurt which causes grievous hurt',
    defines: 'ss 321, 323A',
    family: 'hurt',
    offenceFn: 'offence under s 323A',
    chargeFn: 'charge under s 323A',
    definitionFns: ['voluntarily causes hurt'],
    factsType: 'Hurt Facts',
    factsParam: 'f',
  },
]

export const offenceBySection = (s: string): Offence | undefined =>
  OFFENCES.find((o) => o.section === s)

/**
 * The general-definition ladders (ss 23–25). Not charges; drill-downs the card
 * offers beside the `dishonestly` / `fraudulently` leaves (CPC s 126: words in
 * a charge carry the sense the punishing law gives them).
 */
export const DEFINITION_LADDERS = [
  { fn: 'dishonestly within section 24', leaf: 'dishonestly', section: '24' },
  { fn: 'fraudulently within section 25', leaf: 'fraudulently', section: '25' },
] as const
