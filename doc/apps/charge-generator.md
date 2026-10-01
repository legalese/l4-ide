# Charge generator

A police investigating officer, or a prosecutor, has to turn an account of what happened into a
**charge**: a short document that names the offence, the section that punishes it, and the
particulars of who did what, when and where. In Singapore the charge is itself a legal form.
The Criminal Procedure Code 2010 says what it must contain (ss 123–124), when it must also say
_how_ the offence was committed (s 125), and — the sentence the whole tool is built on — that
**making a charge asserts that every legal condition of the offence is fulfilled** (s 123(5)).

The charge generator is a proof-of-concept web app that operationalises an L4 encoding of six
Penal Code 1871 offences. Describe the case, upload what you have, and it gives back the charges
the encoded law supports, each one drawn as a diagram of the section, recited in the statutory
form, and pinned to the evidence it rests on. The app is at `ts-apps/charge-generator`; the law
it runs is not in the app at all.

## Where the law is

The encodings live in the `legalese/canon` repository, under
`subjects/sg/penal-code-1871/encodings/legalese/`, and are deployed to `jl4-service` as one
bundle. There is one module per offence family — cheating (ss 415, 417, 420), theft (378–379),
extortion (383–384), robbery (390, 392, 394), criminal breach of trust (405–406), criminal
intimidation (503–506), hurt (321, 323A) — plus a general module for the definitions every
offence shares (ss 22–25) and for the form of a charge, and a "charge sheet" that lists which
sections a whole complaint makes out.

Each offence module exports three things per punishing section:

| export                       | what it is                                                               |
| ---------------------------- | ------------------------------------------------------------------------ |
| `cheats`, `commits theft`, … | the defining section as a boolean rule — the ladder of its elements      |
| `offence under s 420`        | the punishing section as a boolean rule, calling the defining one        |
| `charge under s 420`         | a `Charge` record: whether it is made out, the charge text, or a refusal |

The `Charge` text is **built by the L4**, not by the app or by the model. When an element is
not made out there is no text; the record carries a **refusal** naming the elements that are
missing. That is s 123(5), made executable.

## What the officer sees

The page has two panes.

**The interview** (left) is a chat. An assistant, running server-side against the deployment,
reads the account and any uploads (statements, exhibits, CCTV stills as PDF or images), asks for
what is missing, and proposes charges. It has no authority over the law: its tools are `list
offences`, `facts schema`, `evaluate`, `propose charge` and `attach fact`, and every verdict and
every sentence of a charge comes back from `jl4-service`. A "load a sample" widget cycles
through the reported cases the corpus is validated against; when the submitted text matches a
sample exactly, the app replays the canned conversation without calling the model, behind a
"… some moments later …" spinner, so the demo runs offline and repeatably.

**The charges** (right) are a carousel, one card per punishing section:

- **The ladder.** The section drawn from the deployed rule, with the defining section's ladder
  stacked beneath it when the offence calls one (robbery stacks theft and extortion). Click an
  element to toggle it — unknown → true → false — and the charge below rewrites itself, because
  the facts record is re-evaluated by the service on every click. Turn `dishonestly` off on a
  s 420 card and the charge withdraws with a refusal; turn `fraudulently` on and s 417 stands
  while s 420 does not.
- **The charge**, as it would be read to the accused, in the CPC form: "You, …, are charged
  that you, on or about …, at …, Singapore, did …, and you have thereby committed an offence
  punishable under section … of the Penal Code 1871." The particulars it recites (names,
  dates, the "to wit" wording) are editable under the card.
- **What it rests on.** An evidence graph — charge → elements → facts → sources — with the
  source kinds Singapore practice uses: a witness statement recorded under CPC s 22, the
  accused's cautioned statement under s 23, a conditioned statement under s 264, an exhibit, a
  document or CCTV, a forensic report, the First Information Report. A dashed node is a gap:
  an element no fact supports yet, which is the next question to ask.

## The bench

The corpus is validated against reported cases whose judgments quote the charge verbatim. Five
are positive oracles — the encoded section reproduces the charge's body word for word — and two
are **refusals**, which is where s 123(5) becomes visible:

| case                                                          | section         | what it shows                                                                                            |
| ------------------------------------------------------------- | --------------- | -------------------------------------------------------------------------------------------------------- |
| Lewis Christine v PP [2001] SGHC 113                          | 420             | the price-tag switch; the flagship recital                                                               |
| Sarjit Singh Rapati v PP [2005] SGHC 28                       | 384 r/w 34      | extortion by fear of harm to another person; the common-intention rider                                  |
| Chen Weixiong Jerriek v PP [2003] SGHC 103                    | 392 r/w 34, 394 | robbery composed from theft; a theft charge need not state the manner (s 125 illus (a))                  |
| Carl Elias Moses, in Viswanathan Ramachandran [2003] SGHC 183 | 406             | **refused**: the property misappropriated must be the property entrusted; the amended charge is framed   |
| Chan Yok Tuang v PP [2008] SGHC 137                           | 506             | **refused**: the words threaten the person, not the reputation pleaded, and there was no intent to alarm |
| Ang Boon Han v PP [2024] SGHC 221                             | 323A            | hurt intended as slight that turned out grievous                                                         |
| s 378 Illustration (q)                                        | 379             | theft of money by bank transfer                                                                          |

## Limits

- Six offence families and s 301. Nothing else in the Code is encoded, and the assistant
  cannot charge what is not deployed.
- The s 34 common-intention rider is a clause in the charge header, not an encoded rule. No
  abetment (s 109), no attempt (s 511), no amalgamated charges (CPC s 124(4)).
- The header of the charge is normalised to one form; the reported charges vary in
  punctuation ("at or about", "Chapter 224"), and the bench asserts the body, not the header.
- The evidence graph is kept by the app, not by the L4. Nothing in the corpus models proof.
- The encodings have not been reviewed by a lawyer. They are a draft row in the canon repository,
  and the row's `NOTES.md` records every interpretation call the encoders made.

## Running it

```
cabal build jl4-service && $(cabal list-bin jl4-service) --port 18099 --store-path /tmp/jl4-store
CANON_DIR=~/src/legalese/canon npm run seed --workspace=charge-generator
npx turbo run dev --filter=charge-generator
```

The live interview needs an Anthropic credential on the server (`ANTHROPIC_API_KEY`); without
one, the samples still replay and every card still works, because the cards talk to
`jl4-service` directly.
