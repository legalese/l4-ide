import type { Preload } from '../preload'

/**
 * Penal Code 1871 s 378, Illustration (q) — generated from the corpus fixture(s)
 *  by the bench extractor
 * (scratchpad/extract-fixtures.py, 2026-09-17): the facts records are the
 * ones the L4 asserts against, so the carousel shows what the corpus proves.
 * The narrative, reply and evidence graph are authored for the demo.
 */
export const LIM_WEI_MING: Preload = {
  id: 'lim-wei-ming',
  title: "A bank transfer from someone else's account (s 379)",
  citation: 'Penal Code 1871 s 378, Illustration (q)',
  prompt:
    "Lim Wei Ming got into Goh Siew Lan's internet banking on 3 March 2021 at about 11.15 pm from his flat at Blk 123 Ang Mo Kio Avenue 3 and moved $4,500 from her account into his own. She noticed the next day and reported it. I have her statement, the bank's transaction log and the IP records. Theft?",
  reply:
    "Yes. Since 2020 s 378 covers intangible property: a person **moves** money by transferring it from one account to another (Explanation 6), and money is **movable property** (s 22). He took it **dishonestly** — a wrongful gain to himself — **out of Goh Siew Lan's possession** and **without her consent**, so **theft (s 378)** is made out and the charge lies under **s 379**. This is Illustration (q) to the section almost word for word.\n\nUnder CPC s 125 illustration (a) a theft charge need not say how the theft was done, so the body is short; the bank log and IP records go to the evidence graph rather than into the charge.",
  tools: [
    {
      name: 'list_offences',
      args: {},
      result: '(8 sections)',
    },
    {
      name: 'facts_schema',
      args: {
        section: '379',
      },
    },
    {
      name: 'evaluate',
      args: {
        section: '379',
        facts: '(the record below)',
      },
      result: {
        'made out': true,
      },
    },
    {
      name: 'propose_charge',
      args: {
        section: '379',
      },
    },
  ],
  result: {
    turns: [],
    uploads: [],
    pins: [],
    charges: [
      {
        section: '379',
        facts: {
          particulars: {
            accused: 'Lim Wei Ming',
            date: 'the 3rd day of March 2021',
            time: '11.15 pm',
            place: 'Blk 123 Ang Mo Kio Avenue 3',
            'co-accused': '',
            'common intention': false,
          },
          victim: 'Goh Siew Lan',
          'victim described as': '',
          'victim pronoun': 'she',
          'the property': 'moneys amounting to $4,500/-',
          'intending to take': true,
          dishonestly: true,
          'movable property': true,
          'out of the possession of any person': true,
          "without that person's consent": true,
          'moves that property': true,
          'in order to such taking': true,
        },
      },
    ],
    evidence: {
      sources: [
        {
          id: 's-tan',
          kind: 'witness-statement-s22',
          title: 'Statement of Goh Siew Lan',
          maker: 'Goh Siew Lan',
        },
        {
          id: 's-log',
          kind: 'documentary',
          title: 'Bank transaction log, 3 March 2021',
        },
        {
          id: 's-ip',
          kind: 'documentary',
          title: 'IP access records',
        },
      ],
      facts: [
        {
          id: 'f-transfer',
          text: "$4,500 moved from Goh Siew Lan's account to Lim's.",
          sourceIds: ['s-log'],
        },
        {
          id: 'f-noconsent',
          text: 'Goh Siew Lan did not authorise the transfer.',
          sourceIds: ['s-tan'],
        },
        {
          id: 'f-ip',
          text: "The session came from Lim's flat.",
          sourceIds: ['s-ip'],
        },
      ],
      support: [
        {
          section: '379',
          field: 'moves that property',
          factIds: ['f-transfer'],
        },
        {
          section: '379',
          field: "without that person's consent",
          factIds: ['f-noconsent'],
        },
        {
          section: '379',
          field: 'dishonestly',
          factIds: ['f-transfer', 'f-ip'],
        },
        {
          section: '379',
          field: 'out of the possession of any person',
          factIds: ['f-transfer'],
        },
      ],
    },
  },
}
