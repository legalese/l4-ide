import type { Preload } from '../preload'

/**
 * The void-deck robbery, one step short — a CONSTRUCTED counterfactual on the
 * facts of Chen Weixiong Jerriek v PP [2003] SGHC 103, not the case as decided.
 * There the phone was taken and the conviction was under s 392; here it is not,
 * and the corpus fixture `Chen Weixiong Jerriek, the attempt` in
 * robbery-390-392.l4 carries the one changed leaf (`moves that property`).
 *
 * It exists to show the s 392 / s 393 boundary moving: s 392 refuses, s 393
 * frames, and s 394 is unmoved because its own words reach an attempt.
 *
 * The facts record is the one the L4 asserts against. The narrative, reply and
 * evidence graph are authored for the demo.
 */
export const CHEN_WEIXIONG_ATTEMPT: Preload = {
  id: 'chen-weixiong-attempt',
  title: 'Handphone robbery that failed (s 393 read with s 34; s 394)',
  citation: 'constructed on Chen Weixiong Jerriek v PP [2003] SGHC 103',
  prompt:
    'Same case as the void-deck robbery, but Ng never let go of the phone: Chen and the other two surrounded him, demanded it, slapped him and banged his head against the wall, and ran when a resident shouted. Nothing was taken. Ng has given a statement and there is a medical report. What can we charge Chen with now?',
  reply:
    'Nothing was taken, so there is no **theft** under s 378 \u2014 the phone was never moved. s 390(2) upgrades a theft, so without one there is no **robbery**, and **s 392 refuses**: you can see the refusal on its card, naming s 390(1) as the element that fails.\n\nTwo charges survive, and each survives for a reason the section states in its own words:\n\n- **s 393 read with s 34** \u2014 "Whoever attempts to commit robbery". The body reads "did attempt to rob one Ng Juin Chye Joel of a handphone valued at about $450/-". Two to seven years and at least six strokes, against two to ten for the completed offence.\n- **s 394** \u2014 hurt caused "in committing **or in attempting to commit**" robbery. The attempt is inside the section, so this charge is unmoved by the phone staying in Ng\'s hand, and it is the more serious of the two at five to twenty years.\n\nThis is a CONSTRUCTED variation on Chen Weixiong Jerriek v PP [2003] SGHC 103, not what the court found: there the taking succeeded and the conviction was under s 392. It is here to show the s 392 / s 393 boundary moving on one leaf.',
  tools: [
    {
      name: 'list_offences',
      args: {},
      result: '(9 sections)',
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
        'made out': false,
      },
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
          'in carrying away or attempting to carry away property obtained by the theft':
            false,
          'for that end': true,
          'voluntarily causes': true,
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
          'in carrying away or attempting to carry away property obtained by the theft':
            false,
          'for that end': true,
          'voluntarily causes': true,
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
          id: 'f-demand',
          text: 'The three surrounded Ng and demanded the phone; he kept hold of it and they ran.',
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
          field: 'attempting to commit robbery',
          factIds: ['f-demand'],
        },
        {
          section: '393',
          field: 'theft/intending to take',
          factIds: ['f-demand'],
        },
        {
          section: '394',
          field: 'voluntarily causes hurt',
          factIds: ['f-hurt'],
        },
        {
          section: '394',
          field: 'attempting to commit robbery',
          factIds: ['f-demand'],
        },
      ],
    },
  },
}
