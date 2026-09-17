import type { Preload } from '../preload'

/**
 * Ang Boon Han v PP [2024] SGHC 221 — generated from the corpus fixture(s)
 *  by the bench extractor
 * (scratchpad/extract-fixtures.py, 2026-09-17): the facts records are the
 * ones the L4 asserts against, so the carousel shows what the corpus proves.
 * The narrative, reply and evidence graph are authored for the demo.
 */
export const ANG_BOON_HAN: Preload = {
  id: 'ang-boon-han',
  title: 'A push that broke a wrist (s 323A)',
  citation: 'Ang Boon Han v PP [2024] SGHC 221',
  prompt:
    "On 15 May 2021 at about 10.30 pm near bus stop 46229 along Woodlands Ave 2, Ang Boon Han pushed Lam Mian Sern in the chest with both hands, once. Lam fell backwards onto his right hand and fractured the distal radius and scaphoid. Ang says he only meant to shove him away. I have Lam's statement, the hospital report and Ang's cautioned statement.",
  reply:
    'The push was done **with the intention of causing hurt** — a shove is meant to hurt, if only a little — and it **did cause hurt**, so it is **voluntarily causing hurt (s 321)**. What he intended was **not grievous**; what he actually caused, two fractures, **is grievous** (s 320). That split is exactly what **s 323A** punishes, and the charge is on the right with the injury recited "to wit".\n\nThe hospital report carries the grievous-hurt element; Ang\'s own statement carries the intent element (he meant to shove, not to break bones). If the medical evidence showed he foresaw a fall onto a hard surface, s 322 might be argued instead, but nothing you have said supports that.',
  tools: [
    {
      name: 'list_offences',
      args: {},
      result: '(8 sections)',
    },
    {
      name: 'facts_schema',
      args: {
        section: '323A',
      },
    },
    {
      name: 'evaluate',
      args: {
        section: '323A',
        facts: '(the record below)',
      },
      result: {
        'made out': true,
      },
    },
    {
      name: 'propose_charge',
      args: {
        section: '323A',
      },
    },
  ],
  result: {
    turns: [],
    uploads: [],
    pins: [],
    charges: [
      {
        section: '323A',
        facts: {
          particulars: {
            accused: 'Ang Boon Han',
            date: '15 May 2021',
            time: '10.30pm',
            place:
              'in the vicinity of bus stop no. 46229 along Woodlands Ave 2',
            'co-accused': '',
            'common intention': false,
          },
          victim: 'Lam Mian Sern',
          'victim described as': '',
          'the manner':
            'by using both hands to push the chest of the said Lam Mian Sern once, causing him to fall backward and on his right hand, which was used to cushion his impact, resulting in the said Lam Mian Sern suffering fractures of both the distal radius and scaphoid at the right wrist',
          'intention of causing hurt': true,
          'knowledge of being likely to cause hurt': false,
          'cause hurt': true,
          'not grievous': true,
          grievous: true,
        },
      },
    ],
    evidence: {
      sources: [
        {
          id: 's-lam',
          kind: 'witness-statement-s22',
          title: 'Statement of Lam Mian Sern',
          maker: 'Lam Mian Sern',
        },
        {
          id: 's-hosp',
          kind: 'forensic-report',
          title:
            'Hospital report — fractures of the distal radius and scaphoid, right wrist',
        },
        {
          id: 's-ang',
          kind: 'cautioned-statement-s23',
          title: 'Cautioned statement of Ang Boon Han',
          maker: 'Ang Boon Han',
        },
      ],
      facts: [
        {
          id: 'f-push',
          text: 'Ang pushed Lam in the chest with both hands, once.',
          sourceIds: ['s-lam', 's-ang'],
        },
        {
          id: 'f-fracture',
          text: 'Lam fell and fractured the distal radius and scaphoid.',
          sourceIds: ['s-hosp'],
        },
        {
          id: 'f-shove',
          text: 'Ang says he only meant to shove him away.',
          sourceIds: ['s-ang'],
        },
      ],
      support: [
        {
          section: '323A',
          field: 'intention of thereby causing hurt',
          factIds: ['f-push', 'f-shove'],
        },
        {
          section: '323A',
          field: 'does thereby cause hurt',
          factIds: ['f-fracture'],
        },
        {
          section: '323A',
          field: 'the hurt actually caused is grievous',
          factIds: ['f-fracture'],
        },
        {
          section: '323A',
          field: 'the hurt intended or known to be likely is not grievous',
          factIds: ['f-shove'],
        },
      ],
    },
  },
}
