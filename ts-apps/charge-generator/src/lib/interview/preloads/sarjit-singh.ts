import type { Preload } from '../preload'

/**
 * Sarjit Singh Rapati v PP [2005] SGHC 28 — generated from the corpus fixture(s)
 *  by the bench extractor
 * (scratchpad/extract-fixtures.py, 2026-09-17): the facts records are the
 * ones the L4 asserts against, so the carousel shows what the corpus proves.
 * The narrative, reply and evidence graph are authored for the demo.
 */
export const SARJIT_SINGH: Preload = {
  id: 'sarjit-singh',
  title: 'Extortion at Newton Hawker Centre (s 384 read with s 34)',
  citation: 'Sarjit Singh Rapati v PP [2005] SGHC 28',
  prompt:
    "Two men posing as immigration officers, Sarjit Singh Rapati and Paramjit Singh s/o Buta Singh, stopped a Bangladeshi worker, Md Faruq Ahmed, at a coffeeshop on Rowell Road on 10 July 2003 at about 11 am, inspected his work permit and drove him off in a car SDY 5552 L. They then rang his cousin Mohammad Sharful Islam and told him Faruq would be held until he paid. At about 12.30 pm at the Newton Hawker Centre car-park Sharful handed Sarjit $200 in cash and Faruq was released. I have Sharful's statement, Faruq's statement, the car's registration record and the $200 (recovered from Sarjit). Both men acted together. What charges?",
  reply:
    'The $200 was obtained by **putting Sharful in fear of harm to another person** — his cousin, kept in wrongful confinement — and that fear **dishonestly induced him to deliver property**. Every element of **extortion (s 383)** is present, so a charge under **s 384** lies, and because the two acted in furtherance of a common intention it is framed **read with s 34**.\n\nElements, as the section states them:\n\n- **intentionally puts any person in fear of harm to another person, in body** — the threat to keep Faruq confined.\n- **dishonestly induces the person so put in fear to deliver property** — Sharful handed over $200 to get his cousin released.\n\nThe confinement itself and the personation of an immigration officer are separate offences (ss 342 and 170) not in this deployment, so I have not framed them. I have put the s 384 charge on the right with the elements pinned to the two statements and the recovered cash; the manner clause ("by intentionally putting him in fear that you would continue to keep his cousin … in wrongful confinement") is required by CPC s 125 and is recited from the facts.',
  tools: [
    {
      name: 'list_offences',
      args: {},
      result: '(8 sections)',
    },
    {
      name: 'facts_schema',
      args: {
        section: '384',
      },
    },
    {
      name: 'evaluate',
      args: {
        section: '384',
        facts: '(the record below)',
      },
      result: {
        'made out': true,
      },
    },
    {
      name: 'propose_charge',
      args: {
        section: '384',
      },
    },
  ],
  result: {
    turns: [],
    uploads: [
      {
        id: 'u1',
        name: 'statement-sharful.pdf',
        type: 'application/pdf',
        size: 39120,
      },
      {
        id: 'u2',
        name: 'statement-faruq.pdf',
        type: 'application/pdf',
        size: 35800,
      },
    ],
    pins: [],
    charges: [
      {
        section: '384',
        facts: {
          particulars: {
            accused: 'Sarjit Singh Rapati',
            date: '10 July 2003',
            time: '12.30 pm',
            place: 'Newton Hawker Centre car-park',
            'co-accused':
              'one Paramjit Singh s/o Buta Singh (M/43 yrs, NRIC No. S1436488-I)',
            'common intention': true,
          },
          victim: 'Mohammad Sharful Islam [“Sharful”]',
          'victim described as': 'M/27 yrs',
          'victim pronoun': 'he',
          'the property extorted': 'cash of $200/-',
          'the fear':
            'that you would continue to keep his cousin, one Md Faruq Ahmed [“Faruq”], M/23 yrs, in wrongful confinement',
          intentionally: true,
          'put the victim in fear': true,
          'that person': false,
          'any other person': true,
          body: true,
          mind: false,
          reputation: false,
          property: false,
          dishonestly: true,
          'induced the person so put in fear': true,
          'any property': true,
          'valuable security': false,
          'anything signed or sealed which may be converted into a valuable security':
            false,
        },
      },
    ],
    evidence: {
      sources: [
        {
          id: 's-sharful',
          kind: 'witness-statement-s22',
          title: 'Statement of Mohammad Sharful Islam',
          maker: 'Mohammad Sharful Islam',
        },
        {
          id: 's-faruq',
          kind: 'witness-statement-s22',
          title: 'Statement of Md Faruq Ahmed',
          maker: 'Md Faruq Ahmed',
        },
        {
          id: 's-cash',
          kind: 'exhibit',
          title: 'P1 — $200 in cash recovered from the accused',
        },
        {
          id: 's-car',
          kind: 'documentary',
          title: 'LTA registration record, SDY 5552 L',
        },
      ],
      facts: [
        {
          id: 'f-threat',
          text: 'Sarjit told Sharful his cousin would be held until he paid.',
          sourceIds: ['s-sharful'],
        },
        {
          id: 'f-confined',
          text: 'Faruq was driven off in SDY 5552 L and kept in the car.',
          sourceIds: ['s-faruq', 's-car'],
        },
        {
          id: 'f-paid',
          text: 'Sharful handed Sarjit $200 at the car-park and Faruq was released.',
          sourceIds: ['s-sharful', 's-cash'],
        },
      ],
      support: [
        {
          section: '384',
          field: 'intentionally',
          factIds: ['f-threat'],
        },
        {
          section: '384',
          field: 'put the victim in fear',
          factIds: ['f-threat'],
        },
        {
          section: '384',
          field: 'any other person',
          factIds: ['f-confined'],
        },
        {
          section: '384',
          field: 'body',
          factIds: ['f-confined'],
        },
        {
          section: '384',
          field: 'dishonestly',
          factIds: ['f-paid'],
        },
        {
          section: '384',
          field: 'induced the person so put in fear',
          factIds: ['f-paid'],
        },
        {
          section: '384',
          field: 'any property',
          factIds: ['f-paid'],
        },
      ],
    },
  },
}
