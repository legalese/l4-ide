import type { Preload } from '../preload'

/**
 * Chen Weixiong Jerriek v PP [2003] SGHC 103 — generated from the corpus fixture(s)
 *  by the bench extractor
 * (scratchpad/extract-fixtures.py, 2026-09-17): the facts records are the
 * ones the L4 asserts against, so the carousel shows what the corpus proves.
 * The narrative, reply and evidence graph are authored for the demo.
 */
export const CHEN_WEIXIONG: Preload = {
  id: 'chen-weixiong',
  title: 'Handphone robbery at a void deck (s 392 read with s 34; s 394)',
  citation: 'Chen Weixiong Jerriek v PP [2003] SGHC 103',
  prompt:
    'On 5 July 2002 at about 1 pm, at the void deck of Blk 121 Lor 1 Toa Payoh, Chen Weixiong Jerriek with Koh Bang Long and Chia Jia Ting Samuel surrounded Ng Juin Chye Joel, demanded his handphone (worth about $450), slapped him and banged his head against the wall, and took the phone. Ng has given a statement; the phone was recovered from Koh; there is a medical report of a contusion. All three were in it together. What can we charge Chen with?',
  reply:
    'This is **robbery**: the taking is a **theft (s 378)** and, in committing it, the group **voluntarily caused hurt and wrongful restraint** and put Ng in **fear of instant hurt** — which is what **s 390(2)** needs to make theft robbery. Two charges lie:\n\n- **s 392 read with s 34** — robbery in furtherance of the common intention. Under CPC s 125 illustration (a) a theft-type charge need not state the manner, so the body reads simply "did rob one Ng Juin Chye Joel of a handphone valued at about $450/-".\n- **s 394** — voluntarily causing hurt in committing the robbery, "to wit, by slapping him and banging his head against the wall".\n\nBoth are on the right, s 392 first. The theft ladder is stacked under the robbery ladder so you can see that every element of the theft is itself made out. The robbery was at 1 pm, so the night-time aggravation in s 392 does not apply; if the time is wrong, change it and the punishment line updates.',
  tools: [
    {
      name: 'list_offences',
      args: {},
      result: '(8 sections)',
    },
    {
      name: 'facts_schema',
      args: {
        section: '392',
      },
    },
    {
      name: 'evaluate',
      args: {
        section: '392',
        facts: '(the record below)',
      },
      result: {
        'made out': true,
      },
    },
    {
      name: 'propose_charge',
      args: {
        section: '392',
      },
    },
    {
      name: 'facts_schema',
      args: {
        section: '394',
      },
    },
    {
      name: 'evaluate',
      args: {
        section: '394',
        facts: '(the record below)',
      },
      result: {
        'made out': true,
      },
    },
    {
      name: 'propose_charge',
      args: {
        section: '394',
      },
    },
  ],
  result: {
    turns: [],
    uploads: [],
    pins: [],
    charges: [
      {
        section: '392',
        facts: {
          particulars: {
            accused: 'Chen Weixiong Jerriek',
            date: 'the 5th day of July 2002',
            time: '1.00pm',
            place: 'void deck of Blk 121, Lor 1 Toa Payoh',
            'co-accused': 'Koh Bang Long and Chia Jia Ting Samuel',
            'common intention': true,
          },
          theft: {
            particulars: {
              accused: 'Chen Weixiong Jerriek',
              date: 'the 5th day of July 2002',
              time: '1.00pm',
              place: 'void deck of Blk 121, Lor 1 Toa Payoh',
              'co-accused': 'Koh Bang Long and Chia Jia Ting Samuel',
              'common intention': true,
            },
            victim: 'Ng Juin Chye Joel',
            'victim described as': '',
            'victim pronoun': 'he',
            'the property': 'a handphone valued at about $450/-',
            'intending to take': true,
            dishonestly: true,
            'movable property': true,
            'out of the possession of any person': true,
            "without that person's consent": true,
            'moves that property': true,
            'in order to such taking': true,
          },
          extortion: {
            particulars: {
              accused: 'Chen Weixiong Jerriek',
              date: 'the 5th day of July 2002',
              time: '1.00pm',
              place: 'void deck of Blk 121, Lor 1 Toa Payoh',
              'co-accused': 'Koh Bang Long and Chia Jia Ting Samuel',
              'common intention': true,
            },
            victim: '',
            'victim described as': '',
            'victim pronoun': 'he',
            'the property extorted': '',
            'the fear': '',
            intentionally: false,
            'put the victim in fear': false,
            'that person': false,
            'any other person': false,
            body: false,
            mind: false,
            reputation: false,
            property: false,
            dishonestly: false,
            'induced the person so put in fear': false,
            'any property': false,
            'valuable security': false,
            'anything signed or sealed which may be converted into a valuable security':
              false,
          },
          'the hurt': 'slapping him and banging his head against the wall',
          'in order to commit theft': false,
          'in committing the theft': true,
          'in carrying away property obtained by the theft': false,
          'in attempting to carry away property obtained by the theft': false,
          'for that end': true,
          voluntarily: true,
          causes: true,
          'attempts to cause': false,
          death: false,
          hurt: true,
          'wrongful restraint': true,
          'fear of instant death': false,
          'fear of instant hurt': true,
          'fear of instant wrongful restraint': false,
          'in the presence of the person put in fear': false,
          'instant death': false,
          'instant hurt': false,
          'instant wrongful restraint': false,
          'to that person': false,
          'to some other person': false,
          'then and there': false,
          'committed after 7 p.m. and before 7 a.m.': false,
          'attempting to commit robbery': false,
          'voluntarily causes hurt': true,
          'such person': true,
          'any other person jointly concerned in committing or attempting to commit such robbery':
            true,
        },
      },
      {
        section: '394',
        facts: {
          particulars: {
            accused: 'Chen Weixiong Jerriek',
            date: 'the 5th day of July 2002',
            time: '1.00pm',
            place: 'void deck of Blk 121, Lor 1 Toa Payoh',
            'co-accused': 'Koh Bang Long and Chia Jia Ting Samuel',
            'common intention': true,
          },
          theft: {
            particulars: {
              accused: 'Chen Weixiong Jerriek',
              date: 'the 5th day of July 2002',
              time: '1.00pm',
              place: 'void deck of Blk 121, Lor 1 Toa Payoh',
              'co-accused': 'Koh Bang Long and Chia Jia Ting Samuel',
              'common intention': true,
            },
            victim: 'Ng Juin Chye Joel',
            'victim described as': '',
            'victim pronoun': 'he',
            'the property': 'a handphone valued at about $450/-',
            'intending to take': true,
            dishonestly: true,
            'movable property': true,
            'out of the possession of any person': true,
            "without that person's consent": true,
            'moves that property': true,
            'in order to such taking': true,
          },
          extortion: {
            particulars: {
              accused: 'Chen Weixiong Jerriek',
              date: 'the 5th day of July 2002',
              time: '1.00pm',
              place: 'void deck of Blk 121, Lor 1 Toa Payoh',
              'co-accused': 'Koh Bang Long and Chia Jia Ting Samuel',
              'common intention': true,
            },
            victim: '',
            'victim described as': '',
            'victim pronoun': 'he',
            'the property extorted': '',
            'the fear': '',
            intentionally: false,
            'put the victim in fear': false,
            'that person': false,
            'any other person': false,
            body: false,
            mind: false,
            reputation: false,
            property: false,
            dishonestly: false,
            'induced the person so put in fear': false,
            'any property': false,
            'valuable security': false,
            'anything signed or sealed which may be converted into a valuable security':
              false,
          },
          'the hurt': 'slapping him and banging his head against the wall',
          'in order to commit theft': false,
          'in committing the theft': true,
          'in carrying away property obtained by the theft': false,
          'in attempting to carry away property obtained by the theft': false,
          'for that end': true,
          voluntarily: true,
          causes: true,
          'attempts to cause': false,
          death: false,
          hurt: true,
          'wrongful restraint': true,
          'fear of instant death': false,
          'fear of instant hurt': true,
          'fear of instant wrongful restraint': false,
          'in the presence of the person put in fear': false,
          'instant death': false,
          'instant hurt': false,
          'instant wrongful restraint': false,
          'to that person': false,
          'to some other person': false,
          'then and there': false,
          'committed after 7 p.m. and before 7 a.m.': false,
          'attempting to commit robbery': false,
          'voluntarily causes hurt': true,
          'such person': true,
          'any other person jointly concerned in committing or attempting to commit such robbery':
            true,
        },
      },
    ],
    evidence: {
      sources: [
        {
          id: 's-ng',
          kind: 'witness-statement-s22',
          title: 'Statement of Ng Juin Chye Joel',
          maker: 'Ng Juin Chye Joel',
        },
        {
          id: 's-phone',
          kind: 'exhibit',
          title: 'P1 — the handphone, recovered from Koh Bang Long',
        },
        {
          id: 's-med',
          kind: 'forensic-report',
          title: 'Medical report, contusion to the head',
        },
      ],
      facts: [
        {
          id: 'f-took',
          text: 'The three surrounded Ng, demanded the phone and took it.',
          sourceIds: ['s-ng', 's-phone'],
        },
        {
          id: 'f-hurt',
          text: 'Ng was slapped and his head banged against the wall.',
          sourceIds: ['s-ng', 's-med'],
        },
      ],
      support: [
        {
          section: '392',
          field: 'theft/dishonestly',
          factIds: ['f-took'],
        },
        {
          section: '392',
          field: 'theft/moves that property',
          factIds: ['f-took'],
        },
        {
          section: '392',
          field: 'in committing the theft',
          factIds: ['f-took'],
        },
        {
          section: '392',
          field: 'hurt',
          factIds: ['f-hurt'],
        },
        {
          section: '392',
          field: 'wrongful restraint',
          factIds: ['f-took'],
        },
        {
          section: '394',
          field: 'voluntarily causes hurt',
          factIds: ['f-hurt'],
        },
      ],
    },
  },
}
