/**
 * The interview's tools. The model gathers facts and asks questions; the LAW is
 * decided by jl4-service evaluating the encoded sections. No tool here decides
 * whether an offence is made out — every verdict and every sentence of a
 * charge comes back from `charge under s N`.
 */
import { betaZodTool } from '@anthropic-ai/sdk/helpers/beta/zod'
// zod v4 API: the SDK's betaZodTool types its schema against zod 4, which zod
// 3.25 ships under this subpath.
import { z } from 'zod/v4'
import { OFFENCES, offenceBySection } from '$lib/catalogue'
import type { Charge } from '$lib/api/types'
import type { EvidenceGraph, SourceKind } from '$lib/evidence/types'
import { EMPTY_GRAPH } from '$lib/evidence/types'
import { addFact, addSource, factsFor, support } from '$lib/evidence/graph'
import { readAt } from '$lib/charges/leaf-field'
import { elementsOf, evaluateCharge, fieldsOf } from './service'

/** What a turn of the interview establishes, sent to the browser at the end. */
export interface CaseResult {
  charges: {
    section: string
    facts: Record<string, unknown>
    charge?: Charge
  }[]
  evidence: EvidenceGraph
  withdrawn: string[]
}

export type ToolEvent = { name: string; args: unknown; result: unknown }

const SOURCE_KINDS: readonly SourceKind[] = [
  'witness-statement-s22',
  'cautioned-statement-s23',
  'conditioned-statement-s264',
  'exhibit',
  'documentary',
  'forensic-report',
  'first-information-report',
  'upload',
]

const sectionArg = z
  .string()
  .describe(
    'The punishing section, e.g. "420" — one of the sections list_offences returns'
  )

function findOffence(section: string) {
  const o = offenceBySection(section.replace(/^s\s*/i, '').trim())
  if (!o)
    throw new Error(
      `No offence is encoded under section ${section}. Encoded: ${OFFENCES.map((x) => x.section).join(', ')}`
    )
  return o
}

/** Build the tool set for ONE request, closed over its result accumulator. */
export function interviewTools(
  initial: CaseResult,
  onTool: (e: ToolEvent) => void
) {
  const result: CaseResult = {
    charges: initial.charges.map((c) => ({ ...c, facts: { ...c.facts } })),
    evidence: initial.evidence ?? EMPTY_GRAPH,
    withdrawn: [],
  }

  const traced =
    <I, O>(name: string, f: (i: I) => Promise<O>) =>
    async (input: I): Promise<string> => {
      let out: O
      try {
        out = await f(input)
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e)
        onTool({ name, args: input, result: { error: msg } })
        throw e
      }
      onTool({ name, args: input, result: out })
      return typeof out === 'string' ? out : JSON.stringify(out)
    }

  const listOffences = betaZodTool({
    name: 'list_offences',
    description:
      'The Penal Code 1871 offences this deployment can frame a charge under: the punishing section, the name of the offence, and the defining section its elements come from. Call this first.',
    inputSchema: z.object({}),
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    run: traced('list_offences', async (_: Record<string, never>) =>
      OFFENCES.map((o) => ({
        section: o.section,
        offence: o.title,
        elements_from: o.defines,
      }))
    ),
  })

  const factsSchemaTool = betaZodTool({
    name: 'facts_schema',
    description:
      'The facts record an offence is evaluated on: every field with the question it answers. Boolean fields are the ELEMENTS of the offence (the ladder leaves); string fields are the particulars the charge recites (CPC s 124) and the "to wit" wording. Use the field names EXACTLY as returned, nested fields as objects (e.g. particulars.accused).',
    inputSchema: z.object({ section: sectionArg }),
    run: traced('facts_schema', async ({ section }: { section: string }) => {
      const o = findOffence(section)
      const [fields, elements] = await Promise.all([fieldsOf(o), elementsOf(o)])
      return { section: o.section, offence: o.title, elements, fields }
    }),
  })

  const factsArg = z
    .record(z.string(), z.unknown())
    .describe(
      'The facts record, keyed by the field names facts_schema returned (nested records as objects). Leave out what is not yet known — an unknown element counts as NOT made out.'
    )

  const evaluate = betaZodTool({
    name: 'evaluate',
    description:
      'Evaluate a facts record against an offence. Returns whether every element is made out, the charge as the encoded section frames it, or the refusal naming the elements that are missing, plus the elements not yet known. This is the ONLY way to decide whether a charge lies; never decide it yourself.',
    inputSchema: z.object({ section: sectionArg, facts: factsArg }),
    run: traced(
      'evaluate',
      async ({
        section,
        facts,
      }: {
        section: string
        facts: Record<string, unknown>
      }) => {
        const o = findOffence(section)
        const [charge, elements] = await Promise.all([
          evaluateCharge(o, facts as Record<string, unknown>),
          elementsOf(o),
        ])
        const unknown = elements.filter(
          (e) =>
            readAt(facts as Record<string, unknown>, e.split('/')) === undefined
        )
        return { ...charge, 'elements not yet known': unknown }
      }
    ),
  })

  const proposeCharge = betaZodTool({
    name: 'propose_charge',
    description:
      'Put a charge on the carousel for the officer, with the facts record it rests on. Call evaluate first; propose only what is made out, unless the officer asked to see a refusal. Re-proposing a section replaces its facts.',
    inputSchema: z.object({ section: sectionArg, facts: factsArg }),
    run: traced(
      'propose_charge',
      async ({
        section,
        facts,
      }: {
        section: string
        facts: Record<string, unknown>
      }) => {
        const o = findOffence(section)
        const charge = await evaluateCharge(o, facts as Record<string, unknown>)
        const entry = {
          section: o.section,
          facts: facts as Record<string, unknown>,
          charge,
        }
        result.charges = [
          ...result.charges.filter((c) => c.section !== o.section),
          entry,
        ]
        result.withdrawn = result.withdrawn.filter((s) => s !== o.section)
        return {
          proposed: o.section,
          'made out': charge['made out'],
          text: charge.text,
          refusal: charge.refusal,
        }
      }
    ),
  })

  const withdrawCharge = betaZodTool({
    name: 'withdraw_charge',
    description: 'Take a proposed charge off the carousel.',
    inputSchema: z.object({ section: sectionArg }),
    run: traced('withdraw_charge', async ({ section }: { section: string }) => {
      const o = findOffence(section)
      result.charges = result.charges.filter((c) => c.section !== o.section)
      result.withdrawn = [...result.withdrawn, o.section]
      return { withdrawn: o.section }
    }),
  })

  const attachSchema = z.object({
    section: sectionArg,
    element: z
      .string()
      .describe(
        'The element (boolean field path) this fact supports, e.g. "dishonestly" or "theft/movable property"'
      ),
    fact: z
      .string()
      .describe('One sentence, the fact as the officer would state it'),
    source_kind: z.enum(SOURCE_KINDS as [SourceKind, ...SourceKind[]]),
    source_title: z
      .string()
      .describe(
        'e.g. "Statement of Wong Fei Hsia", "Exhibit P3 — the price tags"'
      ),
    source_maker: z
      .string()
      .optional()
      .describe('Who made the statement, if a statement'),
    quote: z
      .string()
      .optional()
      .describe('A short verbatim quotation from the source'),
  })
  type AttachInput = z.infer<typeof attachSchema>

  const attachFact = betaZodTool({
    name: 'attach_fact',
    description:
      "Record what an element of a charge rests on: a fact in the officer's words, and the source it comes from (a CPC s 22 witness statement, a s 23 cautioned statement, a s 264 conditioned statement, an exhibit, a document/CCTV, a forensic report, the First Information Report, or an uploaded file). Quote the source where you can. An element with no fact attached is a gap the officer must fill.",
    inputSchema: attachSchema,
    run: traced('attach_fact', async (i: AttachInput) => {
      const o = findOffence(i.section)
      const slug = (s: string) =>
        s
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, '-')
          .replace(/^-|-$/g, '')
      const srcId = `src-${slug(i.source_title)}`
      const factId = `fact-${slug(i.fact).slice(0, 48)}`
      let g = addSource(result.evidence, {
        id: srcId,
        kind: i.source_kind,
        title: i.source_title,
        maker: i.source_maker,
      })
      g = addFact(g, {
        id: factId,
        text: i.fact,
        sourceIds: [srcId],
        quote: i.quote,
      })
      const existing = factsFor(g, o.section, i.element).map((f) => f.id)
      g = support(g, {
        section: o.section,
        field: i.element,
        factIds: [...existing.filter((x) => x !== factId), factId],
      })
      result.evidence = g
      return { attached: i.element, to: o.section, facts: existing.length + 1 }
    }),
  })

  const tools = [
    listOffences,
    factsSchemaTool,
    evaluate,
    proposeCharge,
    withdrawCharge,
    attachFact,
  ].map((t) => ({ ...t, eager_input_streaming: true }))
  return { tools, result }
}
