import type { Preload } from '../preload'

/**
 * Chan Yok Tuang v PP [2008] SGHC 137 — generated from the corpus fixture(s)
 *  by the bench extractor
 * (scratchpad/extract-fixtures.py, 2026-09-17): the facts records are the
 * ones the L4 asserts against, so the carousel shows what the corpus proves.
 * The narrative, reply and evidence graph are authored for the demo.
 */
export const CHAN_YOK_TUANG: Preload = {
  id: 'chan-yok-tuang',
  title: '"I will shoot her to death" at the lockup (s 506 — no charge)',
  citation: 'Chan Yok Tuang v PP [2008] SGHC 137',
  prompt:
    'On 16 May 2007 at the Central Police Division lockup, Chan Yok Tuang, in custody, said in Hokkien "I will shoot her to death" about SSSgt Jessie Lim Geok Hwee, the officer who had arrested him. He says he was angry about the arrest and wanted to lodge a complaint against her, and there is nothing to suggest he meant her to be frightened. The station officer who heard it has given a statement. Criminal intimidation?',
  reply:
    'On these facts **no charge under s 506 can be framed**, for two reasons the section makes visible.\n\n- The words threaten injury to her **person** (death), not to her **reputation**. The original charge pleaded reputation, and the High Court set the conviction aside for exactly that mismatch. If you plead the injury the words actually threaten, that element is satisfied.\n- **Mens rea is missing.** s 503 requires the threat to be made **with intent to cause alarm**, or to make her do or omit something. Your account is that he was angry and wanted to complain, and nothing shows he meant her to be alarmed. The card on the right refuses the charge and names that element.\n\nIf further evidence shows he intended her to be alarmed — for example, that he repeated the threat to her face — set that element and the charge is framed, aggravated because the threat is to cause death.',
  tools: [
    {
      name: 'list_offences',
      args: {},
      result: '(8 sections)',
    },
    {
      name: 'facts_schema',
      args: {
        section: '506',
      },
    },
    {
      name: 'evaluate',
      args: {
        section: '506',
        facts: '(the record below)',
      },
      result: {
        'made out': false,
        refusal:
          'A charge under section 506 would assert that the facts fulfil every legal condition of criminal intimidation (CPC s 123(5)). On the facts given they do not: with intent to cause alarm to that person, or to cause that person to do any act which he is not legally bound to do, or to omit to do any act which that person is legally entitled to do; the elements of section 503 taken together.',
      },
    },
    {
      name: 'propose_charge',
      args: {
        section: '506',
      },
    },
  ],
  result: {
    turns: [],
    uploads: [],
    pins: [],
    charges: [
      {
        section: '506',
        facts: {
          particulars: {
            accused: 'Chan Yok Tuang',
            date: '16 May 2007',
            time: '',
            place: 'the Central Police Division lockup',
            'co-accused': '',
            'common intention': false,
          },
          victim: 'SSSgt Jessie Lim Geok Hwee',
          'victim described as': '',
          'victim pronoun': 'she',
          'threat words': 'I will shoot her to death',
          language: 'Hokkien',
          'threatened the victim': true,
          person: true,
          reputation: false,
          property: false,
          'person of one in whom interested': false,
          'reputation of one in whom interested': false,
          'cause alarm': false,
          'do an act not legally bound to do': false,
          'omit an act legally entitled to do': false,
          death: true,
          'grievous hurt': false,
          'the destruction of any property by fire': false,
          'an offence punishable with death or with imprisonment for 7 years or more':
            false,
        },
      },
    ],
    evidence: {
      sources: [
        {
          id: 's-officer',
          kind: 'witness-statement-s22',
          title: 'Statement of the station officer who heard the words',
        },
        {
          id: 's-chan',
          kind: 'cautioned-statement-s23',
          title: 'Cautioned statement of Chan Yok Tuang',
          maker: 'Chan Yok Tuang',
        },
      ],
      facts: [
        {
          id: 'f-words',
          text: 'He said in Hokkien "I will shoot her to death" about SSSgt Lim.',
          sourceIds: ['s-officer'],
        },
        {
          id: 'f-complain',
          text: 'He says he was angry and wanted to lodge a complaint against her.',
          sourceIds: ['s-chan'],
        },
      ],
      support: [
        {
          section: '506',
          field: 'threatens another with injury',
          factIds: ['f-words'],
        },
        {
          section: '506',
          field: 'to his person',
          factIds: ['f-words'],
        },
      ],
    },
  },
}
