import type { Preload } from '../preload'

/**
 * Viswanathan Ramachandran v PP [2003] SGHC 183, quoting Carl Elias Moses v PP [1995] 3 SLR 748 — generated from the corpus fixture(s)
 *  by the bench extractor
 * (scratchpad/extract-fixtures.py, 2026-09-17): the facts records are the
 * ones the L4 asserts against, so the carousel shows what the corpus proves.
 * The narrative, reply and evidence graph are authored for the demo.
 */
export const CARL_ELIAS_MOSES: Preload = {
  id: 'carl-elias-moses',
  title: 'Warrants entrusted, proceeds kept (s 406 — the charge as laid)',
  citation:
    'Viswanathan Ramachandran v PP [2003] SGHC 183, quoting Carl Elias Moses v PP [1995] 3 SLR 748',
  prompt:
    "Carl Elias Moses was a dealer's representative at Trans-Pacific Credit Pte Ltd. On 23 October 1989 the company handed him 2,000 Overseas Union Bank Warrant 1994 to deliver to DBS Securities under contract 414270/501, and to pay the sale proceeds back to the company. He delivered the warrants as instructed, collected the proceeds from DBS, and kept the money. We want to charge criminal breach of trust: entrusted with the warrants, misappropriated the proceeds. I have the contract note, the DBS payment record and the company's complaint.",
  reply:
    'I cannot frame that charge, and the reason is in the section. **s 405** says whoever is entrusted with property and dishonestly misappropriates **that property** commits criminal breach of trust — the property misappropriated must be the property entrusted. On your account the property entrusted was the **warrants**, and he delivered them exactly as directed; what he kept was the **proceeds**. Asked "did he misappropriate that property?" of the warrants, the honest answer is no, and the card on the right shows the refusal naming that element.\n\nThis is the flaw the High Court found in the *Carl Elias Moses* charge. The cure is to move the **entrustment** onto the proceeds: he was entrusted with the money DBS paid, for the purpose of paying it to the company, and that he kept. Load the next sample to see the amended charge framed.',
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
        'made out': false,
        refusal:
          'A charge under section 406 would assert that the facts fulfil every legal condition of criminal breach of trust (CPC s 123(5)). On the facts given they do not: dishonestly misappropriates or converts to his own use THAT property, dishonestly uses or disposes of THAT property in violation of a direction of law or of a legal contract, or intentionally suffers any other person to do so — where “that property” is the property entrusted and nothing else; the elements of section 405 taken together.',
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
          'entrusted by': '',
          property: '2,000 Overseas Union Bank Warrant 1994',
          'property, in short': 'warrants',
          'purpose of the entrustment':
            'for the purpose of delivering these warrants on behalf of Trans-Pacific Credit Pte Ltd (“the company”) to DBS Securities Pte Ltd pursuant to a sale (per contract number 414270/501) of the said warrants, and thereafter to pay the proceeds of the said sale to the company',
          'entrusted with property': true,
          'entrusted with dominion over property': false,
          dishonestly: true,
          'misappropriates that property': false,
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
          id: 's-contract',
          kind: 'documentary',
          title: 'Contract note 414270/501',
        },
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
          id: 'f-entrusted',
          text: 'The company handed him the warrants to deliver to DBS.',
          sourceIds: ['s-contract', 's-fir'],
        },
        {
          id: 'f-delivered',
          text: 'He delivered the warrants and DBS paid the proceeds to him.',
          sourceIds: ['s-dbs'],
        },
      ],
      support: [
        {
          section: '406',
          field: 'entrusted with property',
          factIds: ['f-entrusted'],
        },
        {
          section: '406',
          field: 'dishonestly',
          factIds: ['f-delivered'],
        },
      ],
    },
  },
}
