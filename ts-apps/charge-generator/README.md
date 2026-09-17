# charge-generator

A proof-of-concept for an investigating officer or public prosecutor: describe
what happened, upload what you have, and get back the charges the Singapore
Penal Code 1871 supports — each drawn as a ladder diagram of the section, each
recited in the statutory form of a charge, each pinned to the evidence it rests
on.

The law is not in this app. It is in
`legalese/canon:subjects/sg/penal-code-1871/encodings/legalese/*.l4`, deployed to
`jl4-service` as `sg-penal-code`. This client asks, renders, and refuses to
guess:

- **The ladder** is the section, drawn from the deployed rule (`GET …/ladder`).
  Click an element to toggle it — Unknown → True → False — and the charge below
  rewrites itself, because the sentence is built by the L4 (`charge under s N`
  returns a `Charge` record) and re-evaluated on every click.
- **The charge** is the form the Criminal Procedure Code 2010 prescribes
  (ss 123–126). Under s 123(5) making a charge asserts that every legal
  condition of the offence is fulfilled, so when an element is off the card
  shows a **refusal** naming the missing elements instead of a sentence.
- **The evidence graph** is charge → elements → facts → sources, with Singapore's
  source kinds (CPC s 22 witness statements, s 23 cautioned statements, s 264
  conditioned statements, exhibits, documentary, forensic reports, the First
  Information Report). A dashed node is a gap: the next question to ask.
- **The interview** is a chat over the deployment. A "load a sample" widget
  cycles through the reported cases the corpus is validated against; when the
  submitted text matches a sample exactly, the app replays the canned
  transcript behind a "… some moments later …" spinner and never calls the
  model. Anything else goes to `/api/interview`, the server route that holds
  the Anthropic key (not wired in this PR; it answers 501).

## Run it

```
# 1. jl4-service, built from this tree
cabal build jl4-service && $(cabal list-bin jl4-service) --port 18099 --store-path /tmp/jl4-store

# 2. seed the deployment from the canon clone
CANON_DIR=~/src/legalese/canon npm run seed --workspace=charge-generator

# 3. the app
npx turbo run dev --filter=charge-generator
```

`VITE_JL4_BASE_URL` / `VITE_JL4_DEPLOYMENT` override the service origin and
deployment id; any new origin must also be added to `connect-src` in
`svelte.config.js` or the browser blocks the fetch silently.

## What is measured, not assumed

- Ladder leaves are labelled by pretty-printing the expression, so a leaf reads
  `f's deliver` / `` f's `cause the delivery` `` and `lib/charges/leaf-field.ts`
  parses the label back to a field path. A call to another rule (`cheats f`) is
  one leaf; its value is `verdictFor` on that rule's own ladder, which the card
  stacks underneath.
- The ladder/query-plan join is `unique`, never `atomId` (regcf-wizard README).
- A partial facts record is completed against the export's schema before the
  wire (`lib/charges/schema-fill.ts`): an unknown element is FALSE, because a
  charge cannot assert what is not known.

## Tests

`npm test --workspace=charge-generator` runs the pure halves: the label→field
join, the valuation, the schema completion, the evidence layout and the preload
matcher.
