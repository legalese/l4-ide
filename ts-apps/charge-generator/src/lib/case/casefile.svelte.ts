import type { Offence } from '$lib/catalogue'
import type { Charge } from '$lib/api/types'
import type { EvidenceGraph } from '$lib/evidence/types'
import { EMPTY_GRAPH } from '$lib/evidence/types'

/** One card on the carousel: a punishing section, its facts, its last recital. */
export interface ProposedCharge {
  readonly id: string
  readonly offence: Offence
  /** The facts record, PARTIAL — missing booleans are unknown. */
  facts: Record<string, unknown>
  /** The last `Charge` the service returned, or null before the first round trip. */
  charge: Charge | null
  pending: boolean
  error: string | null
}

export interface Upload {
  readonly id: string
  readonly name: string
  readonly type: string
  readonly size: number
  /** Extracted text, when the browser could read it. */
  readonly text?: string
}

export interface ToolTrace {
  readonly name: string
  readonly args: unknown
  readonly result?: unknown
}

export interface Turn {
  readonly id: string
  readonly role: 'user' | 'assistant'
  text: string
  streaming?: boolean
  tools?: ToolTrace[]
}

let n = 0
export const freshId = (p: string): string =>
  `${p}-${++n}-${Date.now().toString(36)}`

/**
 * The case file: everything the interview has established, held in one place
 * so the interview pane, the carousel and the evidence graph see the same
 * state. Runes in a `.svelte.ts` module; persisted by the page (not here).
 */
class CaseFile {
  turns = $state<Turn[]>([])
  uploads = $state<Upload[]>([])
  charges = $state<ProposedCharge[]>([])
  evidence = $state<EvidenceGraph>(EMPTY_GRAPH)
  selected = $state(0)
  /** Sections the officer has pinned ("stick to 420"). */
  pins = $state<string[]>([])

  get current(): ProposedCharge | undefined {
    return this.charges[this.selected]
  }

  propose(offence: Offence, facts: Record<string, unknown>): ProposedCharge {
    const existing = this.charges.find(
      (c) => c.offence.section === offence.section
    )
    if (existing) {
      existing.facts = facts
      return existing
    }
    const pc: ProposedCharge = {
      id: freshId('charge'),
      offence,
      facts,
      charge: null,
      pending: false,
      error: null,
    }
    // Push and hand back the PROXIED element, never the raw object: a mutation
    // through the raw object (pc.charge = …) updates nothing on screen.
    this.charges.push(pc)
    return this.charges[this.charges.length - 1]
  }

  withdraw(section: string): void {
    this.charges = this.charges.filter((c) => c.offence.section !== section)
    if (this.selected >= this.charges.length)
      this.selected = Math.max(0, this.charges.length - 1)
  }

  say(role: Turn['role'], text: string, streaming = false): Turn {
    const t: Turn = { id: freshId('turn'), role, text, streaming }
    this.turns.push(t)
    return this.turns[this.turns.length - 1]
  }

  reset(): void {
    this.turns = []
    this.uploads = []
    this.charges = []
    this.evidence = EMPTY_GRAPH
    this.selected = 0
    this.pins = []
  }

  /** A JSON snapshot for localStorage / the replay files. */
  snapshot(): CaseSnapshot {
    return {
      turns: this.turns.map((t) => ({ ...t, streaming: false })),
      uploads: this.uploads,
      charges: this.charges.map((c) => ({
        section: c.offence.section,
        facts: c.facts,
      })),
      evidence: this.evidence,
      pins: this.pins,
    }
  }
}

export interface CaseSnapshot {
  readonly turns: readonly Turn[]
  readonly uploads: readonly Upload[]
  readonly charges: readonly {
    section: string
    facts: Record<string, unknown>
  }[]
  readonly evidence: EvidenceGraph
  readonly pins: readonly string[]
}

export const casefile = new CaseFile()
