import type { Preload } from '../preload'

/**
 * Viswanathan Ramachandran v PP [2003] SGHC 183 — generated from the corpus fixture(s)
 *  by the bench extractor
 * (scratchpad/extract-fixtures.py, 2026-09-17): the facts records are the
 * ones the L4 asserts against, so the carousel shows what the corpus proves.
 * The narrative, reply and evidence graph are authored for the demo.
 */
export const CARL_ELIAS_MOSES_AMENDED: Preload = {
  id: 'carl-elias-moses-amended',
  title: 'Proceeds entrusted, proceeds kept (s 406 — the charge amended)',
  citation: 'Viswanathan Ramachandran v PP [2003] SGHC 183',
  prompt:
    "Same case as before, amended: Carl Elias Moses, as the company's dealer's representative, received the proceeds of the sale of 2,000 Overseas Union Bank Warrant 1994 from DBS Securities under contract 414270/501, to be paid to Trans-Pacific Credit Pte Ltd, and dishonestly kept them. Frame the criminal breach of trust charge on that footing.",
  reply:
    'Now the property is one thing throughout: he was **entrusted with the proceeds**, for the purpose of paying them to the company, and **dishonestly misappropriated the said proceeds**. Every element of **s 405** is made out and the **s 406** charge on the right recites the entrustment and the misappropriation of the same property, as CPC s 125 requires for this offence.\n\nWhat still needs a source: the DBS payment record shows the proceeds reached him; the company\'s complaint shows they never reached it. A statement from the company\'s accounts officer would close the gap on "dishonestly" — that he had no authority to hold the money.',
  tools: [
    {
      name: 'list_offences',
      args: {},
      result: '(8 sections)',
    },
    {
      name: 'facts_schema',
      args: {
        section: '406',
      },
    },
    {
      name: 'evaluate',
      args: {
        section: '406',
        facts: '(the record below)',
      },
      result: {
        'made out': true,
      },
    },
    {
      name: 'propose_charge',
      args: {
        section: '406',
      },
    },
  ],
  result: {
    turns: [],
    uploads: [],
    pins: [],
    charges: [
      {
        section: '406',
        facts: {
          particulars: {
            accused: 'Carl Elias Moses',
            date: '23 October 1989',
            time: '',
            place: 'the premises of Trans-Pacific Credit Pte Ltd',
            'co-accused': '',
            'common intention': false,
          },
          'entrusted by': 'Trans-Pacific Credit Pte Ltd (“the company”)',
          property:
            'the proceeds of the sale of 2,000 Overseas Union Bank Warrant 1994',
          'property, in short': 'proceeds',
          'purpose of the entrustment':
            'received by you from DBS Securities Pte Ltd pursuant to a sale (per contract number 414270/501) of the said warrants, for the purpose of paying the same to the company',
          'entrusted with property': true,
          'entrusted with dominion over property': false,
          dishonestly: true,
          'misappropriates that property': true,
          'converts that property to his own use': false,
          'uses that property': false,
          'disposes of that property': false,
          'any direction of law prescribing the mode in which such trust is to be discharged':
            false,
          'any legal contract, express or implied, which he has made touching the discharge of such trust':
            false,
          'intentionally suffers any other person to do so': false,
        },
      },
    ],
    evidence: {
      sources: [
        {
          id: 's-dbs',
          kind: 'documentary',
          title: 'DBS Securities payment record',
        },
        {
          id: 's-fir',
          kind: 'first-information-report',
          title: 'Complaint by Trans-Pacific Credit Pte Ltd',
        },
      ],
      facts: [
        {
          id: 'f-proceeds',
          text: 'DBS paid the sale proceeds to him, to be paid to the company.',
          sourceIds: ['s-dbs'],
        },
        {
          id: 'f-kept',
          text: 'The proceeds never reached the company.',
          sourceIds: ['s-fir'],
        },
      ],
      support: [
        {
          section: '406',
          field: 'entrusted with property',
          factIds: ['f-proceeds'],
        },
        {
          section: '406',
          field: 'misappropriates that property',
          factIds: ['f-kept'],
        },
        {
          section: '406',
          field: 'dishonestly',
          factIds: ['f-kept'],
        },
      ],
    },
  },
}
