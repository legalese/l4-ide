import type { Preload } from '../preload'

/**
 * Chen Weixiong Jerriek v PP [2003] SGHC 103 — the attempt limb, generated
 * from the corpus fixture `Chen Weixiong Jerriek, the attempt` (added to
 * robbery-390-392.l4 2026-09-21). Same violence as the base sample, but the
 * taking never completed, so s 392 refuses and s 393 (attempt to commit
 * robbery) is what the facts support.
 */
export const CHEN_WEIXIONG_ATTEMPT: Preload = {
  id: 'chen-weixiong-attempt',
  title: 'Handphone robbery, but the phone was never taken (s 393)',
  citation: 'Chen Weixiong Jerriek v PP [2003] SGHC 103',
  prompt:
    'Same three men, same void deck of Blk 121 Lor 1 Toa Payoh, same 5 July 2002 at about 1 pm. This time Ng Juin Chye Joel held onto his handphone — Chen and the others slapped him and banged his head against the wall trying to make him hand it over, but he never let go and they fled without it. Ng has given a statement; there is a medical report of a contusion. What can we charge Chen with?',
  reply:
    'The violence happened, but the taking did not: `moves that property` is FALSE on these facts, so `commits theft` fails, `theft is robbery` fails, and `commits robbery` refuses — **s 392 cannot be laid**.\n\nThat is exactly what **s 393** is for: attempt to commit robbery. Its one element, `attempting to commit robbery`, is TRUE on the same facts, and the charge recites the same violence — "did **attempt to rob** one Ng Juin Chye Joel of a handphone valued at about $450/-" — read with s 34 for the common intention.\n\nA source gap worth noting: nothing was recovered, because nothing was taken. There is no exhibit here — only Ng\'s statement and the medical report carry this charge.',
  tools: [
    {
      name: 'list_offences',
      args: {},
      result: '(8 sections)',
    },
    {
      name: 'facts_schema',
      args: {
        section: '393',
      },
    },
    {
      name: 'evaluate',
      args: {
        section: '393',
        facts: '(the record below)',
      },
      result: {
        'made out': true,
      },
    },
    {
      name: 'propose_charge',
      args: {
        section: '393',
      },
    },
  ],
  result: {
    turns: [],
    uploads: [],
    pins: [],
    charges: [
      {
        section: '393',
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
            'moves that property': false,
            'in order to such taking': false,
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
          'in order to commit theft': true,
          'in committing the theft': false,
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
          'attempting to commit robbery': true,
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
          id: 's-med',
          kind: 'forensic-report',
          title: 'Medical report, contusion to the head',
        },
      ],
      facts: [
        {
          id: 'f-tried',
          text: 'The three surrounded Ng and demanded the phone, but he did not let go and they fled without it.',
          sourceIds: ['s-ng'],
        },
        {
          id: 'f-hurt',
          text: 'Ng was slapped and his head banged against the wall.',
          sourceIds: ['s-ng', 's-med'],
        },
      ],
      support: [
        {
          section: '393',
          field: 'theft/dishonestly',
          factIds: ['f-tried'],
        },
        {
          section: '393',
          field: 'theft/intending to take',
          factIds: ['f-tried'],
        },
        {
          section: '393',
          field: 'in order to commit theft',
          factIds: ['f-tried'],
        },
        {
          section: '393',
          field: 'hurt',
          factIds: ['f-hurt'],
        },
        {
          section: '393',
          field: 'wrongful restraint',
          factIds: ['f-hurt'],
        },
        {
          section: '393',
          field: 'attempting to commit robbery',
          factIds: ['f-tried'],
        },
      ],
    },
  },
}
