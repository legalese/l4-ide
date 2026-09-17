import type { Preload } from '../preload'

/**
 * Lewis Christine v Public Prosecutor [2001] SGHC 113 — the flagship case.
 * The facts record below is the same fixture the corpus asserts against
 * (`cheating-415-417-420.l4`, `Lewis Christine`), so the charge the carousel
 * shows after replay is byte-for-byte the reported s 420 charge, modulo the
 * citation form. The evidence graph is illustrative: the judgment names the
 * cashier, the price tag (exhibit P3 in the plan's reading) and the appellant's
 * own admission; the source kinds are Singapore's.
 */
export const LEWIS_CHRISTINE: Preload = {
  id: 'lewis-christine',
  title: 'Price-tag switch at Seiyu (cheating, s 420)',
  citation: 'Lewis Christine v PP [2001] SGHC 113',
  prompt:
    'Complainant is Wong Fei Hsia, a cashier at Seiyu Departmental Store, Parkway Parade. On 24 April 2000 at about 8.10 pm a customer, Christine Lewis, brought a "Pochacco" pencil casing to the till. The tag on it read $5.25 but the item is priced at $16.95; store staff later found the $5.25 tag had been taken off a cheaper item. The accused paid $5.25 and left with the casing. She has given a cautioned statement admitting she swapped the tags because she wanted the casing for less. I have the cashier\'s statement, the two price tags and the CCTV still. What can we charge?',
  reply:
    'On these facts the elements of **cheating** (s 415) are all present, and the deception induced the cashier to **deliver property** — so the aggravated form under **s 420** is made out, not just s 417.\n\n' +
    'Walking the section:\n\n' +
    '- **by deceiving any person** — she deceived the cashier into believing the price was $5.25 (the swapped tag; Explanation 1 also covers concealment).\n' +
    '- **dishonestly** — she intended a wrongful gain to herself of $11.70 (s 24(a)); her cautioned statement says as much.\n' +
    '- **induced the person so deceived to deliver property** — the cashier handed over the casing for $5.25.\n\n' +
    'Both charges are on the right: **s 420** first, and **s 417** as the simple alternative on the same facts — the difference is only the punishing section. Click `dishonestly` off on either card and watch s 420 withdraw while s 417 stands, because s 415 accepts fraud or dishonesty but s 420 requires dishonesty. Each element is pinned to its evidence. Two things to confirm before the charge is finalised: the exact time on the receipt, and whether the CCTV still shows the tag being swapped or only the purchase.',
  tools: [
    {
      name: 'list_offences',
      args: {},
      result: [
        '417 cheating',
        '420 cheating and dishonestly inducing a delivery of property',
        '379 theft',
        '384 extortion',
        '392 robbery',
        '406 criminal breach of trust',
        '506 criminal intimidation',
        '323A hurt',
      ],
    },
    {
      name: 'evaluate',
      args: { section: '420', facts: '(the Cheating Facts record below)' },
      result: { 'made out': true },
    },
    { name: 'propose_charge', args: { section: '420' } },
    {
      name: 'evaluate',
      args: { section: '417', facts: '(the same record)' },
      result: { 'made out': true },
    },
    { name: 'propose_charge', args: { section: '417' } },
  ],
  result: {
    turns: [],
    uploads: [
      {
        id: 'u1',
        name: 'statement-wong-fei-hsia.pdf',
        type: 'application/pdf',
        size: 48210,
      },
      {
        id: 'u2',
        name: 'cautioned-statement-lewis.pdf',
        type: 'application/pdf',
        size: 31877,
      },
      { id: 'u3', name: 'cctv-till-4.png', type: 'image/png', size: 402113 },
    ],
    pins: [],
    charges: [
      {
        section: '420',
        facts: {
          particulars: {
            accused: 'Christine Lewis',
            date: 'the 24th day of April 2000',
            time: '8.10 pm',
            place:
              'the Seiyu Departmental Store at Parkway Parade Shopping Centre',
            'co-accused': '',
            'common intention': false,
          },
          victim: 'Wong Fei Hsia',
          'victim described as': 'the cashier of Seiyu Departmental Store',
          'victim pronoun': 'she',
          'deceived the victim': true,
          'the deception':
            'to believe that the price of a "Pochacco" pencil casing is worth $5.25, when in actual fact, you knew that the price of the said item is worth $16.95',
          fraudulently: false,
          dishonestly: true,
          deliver: true,
          'cause the delivery': false,
          'consent that any person shall retain any property': false,
          'the property': 'the said item for only $5.25',
          intentionally: false,
          do: false,
          'omit to do': false,
          'the act or omission': '',
          causes: false,
          'likely to cause': false,
          damage: false,
          harm: false,
          body: false,
          mind: false,
          reputation: false,
          property: false,
          'make, alter or destroy a valuable security': false,
          'by remote communication': false,
        },
      },
      {
        section: '417',
        facts: {
          particulars: {
            accused: 'Christine Lewis',
            date: 'the 24th day of April 2000',
            time: '8.10 pm',
            place:
              'the Seiyu Departmental Store at Parkway Parade Shopping Centre',
            'co-accused': '',
            'common intention': false,
          },
          victim: 'Wong Fei Hsia',
          'victim described as': 'the cashier of Seiyu Departmental Store',
          'victim pronoun': 'she',
          'deceived the victim': true,
          'the deception':
            'to believe that the price of a "Pochacco" pencil casing is worth $5.25, when in actual fact, you knew that the price of the said item is worth $16.95',
          fraudulently: false,
          dishonestly: true,
          deliver: true,
          'cause the delivery': false,
          'consent that any person shall retain any property': false,
          'the property': 'the said item for only $5.25',
          intentionally: false,
          do: false,
          'omit to do': false,
          'the act or omission': '',
          causes: false,
          'likely to cause': false,
          damage: false,
          harm: false,
          body: false,
          mind: false,
          reputation: false,
          property: false,
          'make, alter or destroy a valuable security': false,
          'by remote communication': false,
        },
      },
    ],
    evidence: {
      sources: [
        {
          id: 's-wong',
          kind: 'witness-statement-s22',
          title: 'Statement of Wong Fei Hsia',
          maker: 'Wong Fei Hsia',
        },
        {
          id: 's-lewis',
          kind: 'cautioned-statement-s23',
          title: 'Cautioned statement of Christine Lewis',
          maker: 'Christine Lewis',
        },
        {
          id: 's-p3',
          kind: 'exhibit',
          title: 'P3 — the $5.25 and $16.95 price tags',
        },
        {
          id: 's-cctv',
          kind: 'documentary',
          title: 'CCTV still, till 4, 20:10',
        },
      ],
      facts: [
        {
          id: 'f-tag',
          text: 'The casing carried a $5.25 tag taken from a cheaper item.',
          sourceIds: ['s-wong', 's-p3'],
        },
        {
          id: 'f-price',
          text: 'The casing is priced at $16.95.',
          sourceIds: ['s-wong', 's-p3'],
        },
        {
          id: 'f-admit',
          text: 'She swapped the tags to get the casing for less.',
          sourceIds: ['s-lewis'],
        },
        {
          id: 'f-paid',
          text: 'The cashier accepted $5.25 and handed over the casing.',
          sourceIds: ['s-wong', 's-cctv'],
        },
      ],
      support: [
        {
          section: '420',
          field: 'deceived the victim',
          factIds: ['f-tag', 'f-price'],
        },
        {
          section: '420',
          field: 'dishonestly',
          factIds: ['f-admit', 'f-price'],
        },
        { section: '420', field: 'deliver', factIds: ['f-paid'] },
        {
          section: '417',
          field: 'deceived the victim',
          factIds: ['f-tag', 'f-price'],
        },
        {
          section: '417',
          field: 'dishonestly',
          factIds: ['f-admit', 'f-price'],
        },
        { section: '417', field: 'deliver', factIds: ['f-paid'] },
      ],
    },
  },
}
