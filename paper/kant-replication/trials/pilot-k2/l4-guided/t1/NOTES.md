# Notes — l4-guided / t1

## Check run

Ran (never `l4 run`, never with claim data omitted from the check — only typecheck, no evaluation):

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
```

Both report `Check succeeded.` `apply.l4` imports `policy.l4` and constructs all nine `Claim`
values plus the nine `#EVAL covered qN` directives; `l4 check` type-checks every directive's
expression without evaluating it, so the nine answers were never computed or inspected. Before
writing the real files I typechecked the schema's `DECLARE`/helper block in isolation in a scratch
file (outside the trial directory, containing no claim data and none of the nine questions) to
work out two syntax points documented below; that scratch file did not survive into the trial
directory.

## Necessary, minimal corrections to the schema (not semantic changes)

`inputs/schema.md` says to copy its `DECLARE`s and helpers verbatim. Two lines in it do not
actually compile, and I fixed only those two, changing nothing about names, signatures, or
intended behaviour:

1. **`Claim`'s multi-word field names had no backticks** (e.g. `agreement signed IS A BOOLEAN`).
   L4 requires backtick-quoting for any identifier containing a space; the bare form is a parser
   error (`unexpected signed, expecting IS or space token`). I added backticks to every multi-word
   field name and nothing else — field order, names, and types are otherwise identical to the
   schema.

2. **`` `arose out of` MEANS c `elem` cs `` does not typecheck.** `elem` is defined prefix in
   `jl4-core/libraries/prelude.l4` (`elem x list MEANS ...`) and was never given a mixfix/infix
   definition, so backtick-wrapping it at a call site does not make it infix — L4 does not offer
   Haskell-style ad hoc backtick-infix for arbitrary prefix functions. (Contrast prelude's own
   `` x `is in` s MEANS elem x (s's elements) `` — there, `` `is in` `` is a name that was *defined*
   with `x`/`s` flanking it; `elem` itself is always called prefix, including inside that
   definition.) Confirmed empirically: `l4 check` on the verbatim line reports `I could not find a
   definition for the identifier elem`, and parses `c \`elem\` cs` as `c` applied to two arguments.
   Fixed by writing the body as plain prefix `elem c cs`. The helper's name, `GIVEN`/`GIVETH`
   signature, and behaviour (true iff `c` occurs in `cs`) are unchanged; only this one internal
   expression was rewritten to something that actually resolves to the same thing the schema
   evidently intended.

Also added `IMPORT prelude` at the top of `policy.l4`, which is required for `elem` to resolve
under `l4 check` — despite `doc/reference/libraries/prelude.md` describing prelude as
"auto-imported"/"always available", omitting the explicit `IMPORT` left `elem` unresolved in this
checkout.

Both `no later than` and `arose out of` are otherwise used exactly as given, called prefix in
`GIVEN` order (confirmed by typechecking a throwaway call of each against dummy arguments before
writing `covered`): `` `no later than` (claim's `field`) N `` and `` `arose out of` (claim's causes)
SomeCause ``.

## Judgement calls in `covered` (policy.l4)

- **§1.2's "misrepresentation or material withholding of information"** collapses onto the single
  schema field `misrepresentation month`, since no separate field for "withholding" exists. I did
  not invent one, per the "ONLY these fields" instruction.
- **§3.2.1's 60-day post-proof waiting period** is modelled as 2 months
  (`` `waiting period after proof of claim in months` MEANS 2 ``), since every temporal field in
  the schema is a coarse NUMBER of months and the schema gives no day-level arithmetic to work
  with. This is an approximation of 60 days, not an exact conversion.
- **§1.1(3) "the condition in §1.3 is still pending or has been satisfied in a timely fashion"**:
  modelled as (confirmation ≤ month 7 AND visit ≤ month 6 AND provider qualified) **OR**
  hospitalization itself occurred at or before month 7. The second disjunct reflects that coverage
  attaches at the moment of the covered event; a hospitalization that happens before the §1.3
  deadline can even be said to have lapsed shouldn't be retroactively uncovered by what happens
  (or doesn't) afterward. This is a real interpretive choice, not forced by the text. It only
  matters for claims where the confirmation isn't cleanly timely, i.e. q4/q6/q7/q9 here — for
  those four I deliberately set `hospitalization month` to 9 (past the deadline) specifically so
  this "still pending" escape hatch can't paper over a late confirmation and the outcome turns
  purely on whether the stated confirmation month is itself ≤ 7.
- **"Proof of my wellness visit was provided/submitted N months after..." (q4, q6, q7, q9)** — read
  as the act of supplying confirmation to the insurer, i.e. `written confirmation month` (7-month
  deadline), not the underlying visit's own occurrence (`wellness visit month`, 6-month deadline,
  which none of the nine questions state and which I default to a safe `JUST 1` throughout). This
  reading is load-bearing for q6: 6.5 months is timely against the 7-month confirmation deadline,
  though it would read as late against the 6-month visit deadline if misassigned.
- **q5 — "hospitalized for punching my own face to show off for my friends"**: encoded
  `hospitalization ground IS Neither`, i.e. neither sickness nor accidental injury, because the act
  causing the harm was voluntary rather than unintended. This is genuinely contestable: some
  accident-insurance case law (notably New York's own "accidental result" line, and the policy is
  New York-governed per §3.3.1) treats an unintended *result* of a voluntary act as still
  "accidental," which would instead put this claim inside the covered-ground disjunct. I went with
  the narrower "the act itself must be unintended" reading, partly because it is the more natural
  reading of the bare word "accidental" applied to these facts, and partly because the question's
  own "I did not commit fraud or misrepresentation" clause only makes sense as a real test if the
  actual bar to coverage lies elsewhere (in the ground classification) — otherwise that disclaimer
  is answering a question nobody was asking.
- **q9 — bitten by claimant's own son "while... serving as a police officer"**: read the general
  exclusion's "arising directly or indirectly out of ... service in the police" as requiring an
  actual causal link between the service and the injury, not mere contemporaneous employment
  status. A son's bite has no causal connection to police duties, so `causes IS LIST Other`, not
  `` LIST `Police service` ``. This is deliberately the mirror image of q1 (burns while on duty as
  a firefighter — the duty itself caused the injury) and q8 (injured in a military *training
  exercise* — still service-caused): both of those get the matching excluded `Cause`, because
  there the causal nexus is real.
- **`causes IS LIST Other`** (rather than `EMPTY`) is used whenever no excluded cause is
  implicated, reading `Other` as existing precisely to name "some non-excluded cause" for a claim
  whose `causes` list is always populated and truthful without asserting any of the four excluded
  categories.
- Every field not addressed by a given question is set to a value that satisfies every other
  condition and triggers no other exclusion, per the standing preamble: `agreement signed IS TRUE`,
  `premium paid month IS JUST 0`, `wellness visit month IS JUST 1` /
  `wellness visit provider qualified IS TRUE` (except where the question is itself about wellness
  timing, in which case only `written confirmation month` varies), no dispute/arbitration facts in
  play (`dispute arisen IS FALSE`, arbitration fields `NOTHING`/`TRUE` as appropriate),
  `written proof of claim month` / `recovery sought month` set comfortably ≥ 2 months apart, and
  `policy term months IS 12` throughout (§3.6).

## Scope discipline

Did not open `bench/keys.json`, `fixtures/queries.json`, `artifacts/`, `FOUNDATION.md`,
`source-defects.md`, `README.md`, or `jl4/examples/legal/chubb/`, and did not search the web.
Language reference consulted: the `writing-l4-rules` skill (including `references/gotchas.md`) and
`doc/reference/` (`cheat-sheet.md`, `GLOSSARY.md`, `types/DECLARE.md` and its example files,
`libraries/prelude.md`, `libraries/IMPORT.md`); and, for the `elem` signature only,
`jl4-core/libraries/prelude.l4`.
