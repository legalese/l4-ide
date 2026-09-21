# sg-miles-card — subject idiosyncrasies

Free prose about **this subject**, for humans and for the skill. **No script reads this file.**
Machine-readable facts live in `subject.json`; the CLI-surface pin in `pins.json`; the negative
controls in `known-defects.json`. When a fact below stops being true, fix it here in the same
change that moved it.

Written 2026-09-21, for someone arriving cold. The design document it implements is
`mengwong/homelab`, branch `miles-card-l4-spec`, `docs/projects/miles-card/SPEC-miles-card-l4-encoding.md`
(canonical there; not copied here).

---

## 1. Read this first: the source is contract, not law, and the answer is not advice

Every subject beside this one under `etc/go/subjects/` encodes an instrument in force, or a
research fixture.
**This one encodes the reward-programme terms and conditions of eight Singapore consumer cards**, as
the issuers published them and as retrieved on 2026-09-21: DBS yuu, DBS Woman's World, UOB Lady's
Solitaire, HSBC Revolution, Citi Rewards, POSB PAssion, UOB PRVI Miles and Citi PremierMiles.
The PDFs are committed at `jl4/examples/legal/miles-card/source/` so an issuer's revision shows
up as a diff; the issuers say in each document that they may vary the terms without notice.

Nothing produced from this subject is advice about what any card will actually pay.
The encoding states what the text says, with the clause cited, and marks as `Unconfirmed` or
`Source expired` what the text does not settle.

### Why the subject exists

Not for the cards.
The corpus has four properties that are hard to find together (spec §1): it carries two
**pre-registered discrepancies** between the household's hand-maintained cheat sheet and the
issuers' own text, found by hand before any formalisation; it comes **pre-split into model and
properties** (the T&Cs are the model, the cheat sheet's waterfall rows are assertions over it);
it has a **consumer app in daily use** whose data table is the projection target; and it is
**personally owned**, so it is publishable in full.

The acceptance test is spec §1's: the encoding must surface both discrepancies as failed
assertions without being told where to look.
Section 5 below records how that test is run and what it found.

---

## 2. What the primary texts settled that the spec left open

Read on 2026-09-21 from the committed PDFs (via `pdftotext -layout`; search the `.txt` in
paragraph mode, the lines are hard-wrapped).

| question                   | spec said                                   | the text says                                                                                                                                                                                               | where                                    |
| -------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| PAssion cap basis          | unconfirmed                                 | **calendar month**: "Qualifying Month" is defined by a table of calendar months                                                                                                                             | `posb-passion-yuu-tnc` cl.8(e)           |
| PAssion promotion currency | —                                           | **the Promotion Period ended 30 Sep 2025** ("valid from 1 October 2023 to 30 September 2025"); the document is "Updated as of 30 May 2025" and nothing held renews it                                       | cl.3                                     |
| PAssion cap                | "S$25 / 5,000 yuu Points rebate cap"        | confirmed: 15X bonus, "Capped at a maximum of S$25 cash rebate (5,000 yuu Points) ... per Qualifying Month"; the threshold is S$300 at Participating Stores **and** S$400 at non-Participating              | cl.8(a)–(b)                              |
| UOB attribution date       | —                                           | **posting date**: "computed based on the date that the transaction is posted on UOB's systems"                                                                                                              | `uob-ladys-cards-tnc` cl.8               |
| Solitaire rate             | cheat sheet: 6 mpd "(4 card + 2 savings)"   | the T&C states 10X UNI$ per S$5 = **4 miles per S$1**; the savings-account uplift is in no held document                                                                                                    | cl.2(c), heading A                       |
| Solitaire Dining category  | —                                           | MCC 5811, 5812, **5814**, 5499 — fast food and food delivery are Dining                                                                                                                                     | Schedule 1                               |
| Solitaire Family category  | —                                           | MCC 5411, 5641                                                                                                                                                                                              | Schedule 1                               |
| HSBC dining MCCs           | app note: bakery 5462 "is NOT a Dining MCC" | HSBC's Eligible Transactions list includes **5462 Bakeries** and 5441 under "Dining excluding hotel dining"; 5814 is **not** listed                                                                         | `hsbc-revolution-reward-points-tnc` cl.7 |
| HSBC 19-point tier         | —                                           | 19 bonus points (cap 22,800) with a S$50,000 Deposits ADB in an Everyday Global Account; otherwise 9 (cap 9,000)                                                                                            | cl.7.1(ii), 7.2                          |
| Woman's World rate         | —                                           | base 1X + bonus 9X per S$5 online = 10 DBS Points per S$5, cap "the first S$1,000 of online spend per calendar month", by transaction date                                                                  | `dbs-womans-card-tnc` cl.16–19           |
| yuu Amex vs Visa           | —                                           | at 7-Eleven (before 13 Aug 2026) and Charge+, "Points will not be awarded for any transactions made with DBS yuu American Express Card"; so the network is part of the card's identity in the domain module | `dbs-yuu-card-tnc` Appendix 1            |

Two things in the spec that the texts confirm exactly: Citi's cap is "9,000 Bonus Points per
**statement month**" (cl.13), the one non-calendar cap; and Citi's mobile-wallet exclusion sits
on the online limb cl.6(ii) only, with no wallet language on the MCC limb cl.6(i).

---

## 3. The encoding's shape, and the Catala constraint that shaped it

Layered as the spec's §5: a dmnmd decision table for merchant→category (layer 1, kept from
commit `5cf5d611f`), L4 rule modules per card over one shared domain module (layer 2), and
provenance on every answer (layer 4). Allocation across the month (layer 3) is out of scope.

**Every rule takes its inputs positionally. No module uses a section `GIVEN`.**
The corpus must lower to Catala (spec §2) and `l4 catala` refuses a section `GIVEN` read by
any non-`@export` helper; the escape hatch — export every reader — costs one published Catala
scope per helper.
The `ofek` encoding in `legalese/canon` declined the construct for the same reason (its NOTES.md
§11).

**`catala typecheck` is the gate, not the L4 exit code**, and the `p7-catala` leg exists to
record it.
The spec's §2.2 premise — that a non-exported helper between two exported rules emits Catala
`l4 catala` accepts and `catala typecheck` rejects (smucclaw/l4-ide#958) — is stale on this
binary (`7af775364`): the refusal ruled in `CATALA-EXPORT-SPEC.md` §8.1.1 is built and the
emitter now exits 1 on that shape. The leg still gates on the toolchain because the class of
defect is real: on 2026-09-21 the emitter accepted a record whose every field is STRING and
emitted an empty structure Catala rejects.

**Every definition states its `GIVETH`.** The emitter refuses a helper whose result type is
inferred ("has no GIVETH; a Catala toplevel declaration needs its result type stated"), and
`l4 check` is silent about it. Measured 2026-09-21 by the leg's positive control on chubb.

**The emitter could not see imported DECLAREs** on `7af775364`: a rule returning a record from
an `IMPORT`ed module was refused as "outside the v1 Catala fragment". Reproduced on a two-line
probe; fixed at `6186d996c` (branch `catala/imported-types`, merged into this branch), which also
elides a structure that loses every field to R11 instead of emitting an empty one, and refuses two
imported modules that declare the same type name (a third defect the closure made reachable).

**Catala has no strings, and the T&Cs key merchants and exclusions by name.** Measured
2026-09-21: a rule that compares a `STRING` is refused ("`STRING` has no Catala counterpart
(§4.8)"); an uninspected string field is elided (R11); a record whose fields are all strings
emitted an empty structure Catala rejected (defect, fixed on `catala/imported-types`). The
encoding therefore splits the string work from the rules: layer 1 (`classify.l4`) reads
`merchant name` and `transaction description` with the prefix builtin `CONTAINS haystack needle`
(documented in `jl4/examples/ok/string-primitives.l4`; three encoders reported "no substring
test" after probing lowercase names, which is why this sentence exists) and assigns the closed
enumerations `Merchant`, `Description pattern` and `Charge kind`; the card modules read only
those. A single-file probe of that shape — enum match, `elem` over a list of an enum, a `DATE`
comparison in the direct form — lowered with `catala typecheck: successful`, `no overlapping
exceptions` and 8 of 8 `clerk` tests agreeing with L4. Note that `daydate`'s `Day d` wrapper does
NOT lower ("unbound reference … Date to days"); compare dates directly.

**No non-exported rule may call an exported one, and that includes test wrappers.** Once the
exporter collected fixtures reachable from directives (the fourth fix), the illustration sections'
"answer for" convenience wrappers — plain rules that call the module's `@export` so assertions stay
short — were refused with the #958 message, correctly. Ruled 2026-09-21: inline the wrappers at the
assertion sites; never `@export` a test wrapper, which would publish fixtures on the MCP surface.
Fixture VALUES stay named; only rules that call the export go.

**Defeasibility is hand-rolled.** L4 has no `DESPITE`/`SUBJECT TO`; exclusion lists are encoded
as priority-ordered `BRANCH` guards. Every site where a native construct would have collapsed
several rules into one is listed in `jl4/examples/legal/miles-card/DEFEASIBILITY-SITES.md`,
written as the modules were, not reconstructed afterwards.

---

## 4. Two axes for "contactless", and a value called Unknown

"Contactless" is overloaded.
The domain module splits it into the **credential** the cardholder presents (physical card,
wallet token, Amaze) and the **indicator** the merchant's acquirer attaches (online,
card-present).
Three issuers say in terms that they do not determine the indicator (DBS Woman's cl.13, Citi
cl.6(ii), HSBC cl.6).
It is therefore latent to the cardholder at decision time, carries an explicit `Unknown`, and
every rule that reads it returns both conditional rates with `depends on the merchant
indicator` TRUE and the headline `miles per dollar` set to the lower branch.
Version 3 of the consumer app was a confident, wrong renderer; this is the mechanism that
stops the generator reproducing that.

---

## 5. The acceptance test (spec §1) — how it is run

The cheat sheet's waterfall rows are deposited as an **additional encoding**
`cheatsheet-2026-06`, written by an agent who was shown the cheat sheet and the domain module's
signatures and NOT the card modules.
`p6-tests` over that encoding is expected to report `DEGRADED`, and its assert report is the
acceptance artifact: the test passes iff the §4.1 row (Woman's World wallet tap as online) and
the §4.2 row (Citi "never Apple Pay", unqualified) are among the failures.

**Transcription rule, corrected once and before the formal run (2026-09-21).** The first
transcription set each fixture's `merchant indicator` to whatever the row's claim implied ("counts
as online" became `Flags online`), which made the assertion vacuous: the discrepancy is precisely
that the cheat sheet assumes the indicator. The rule was corrected on principle to "a fixture
carries only facts the cardholder can depose to at the moment of paying", so every fixture's
indicator is `Unknown`, uniformly; and "never via Apple/Google Pay" was instantiated universally
over the file's own 32 fixtures rather than over a hand-picked merchant. The change is recorded in
the claims file's header. It made the assertions disagree MORE, not less, and it is stated here so
nobody reads it as the test being redefined after the fact.

**Pre-pass snapshot, 2026-09-21 (before the string-free second pass; not the formal receipt):**
126 of 180 satisfied, 54 failed. Both pre-registered rows are among the failures: the Woman's
World cell "Kris+/mobile-wallet in-store (counts as online)" and the Citi cell "Does NOT earn:
mobile wallet (Apple/Google Pay)" on the fixtures where Citi's MCC limb applies. The other clusters:
Solitaire "6 mpd" on every row (the T&C says 4; the savings uplift is unheld), PAssion "5 mpd"
everywhere (the promotion expired 30 Sep 2025 on its own terms), Revolution 4 mpd at 7-Eleven and
Cheers (MCC 5411 is not on HSBC's list), the PAssion MYR row (cl.7(d) excludes foreign currency),
and every "online" Woman's World row (the indicator is Unknown, so the headline is the lower
branch — category (d), an honest gap, to be triaged).

**Formal result: NOT YET RUN.** This paragraph is replaced by the receipt hash and the failing rows
when `p6-tests` has run over `cheatsheet-2026-06`.

The committed corpus stays green: rows the test proved unsupported are restated in
`miles-card-disputed.l4` as `#ASSERT NOT (...)` with `Disputed by source` status and both
citations.

---

## 6. The modules' own gates, as measured at the end of the second pass (2026-09-21)

Every issuer module is string-free and lowers to Catala with zero refusals on the exporter at
l4-ide `5f5ff3062` (the four fixes), verified per module by its encoder on the four gates: `l4
check`, `l4 run` (counting Error-severity diagnostics, not the exit code, which is 0 on a failed
assertion), `l4 catala`, and `etc/validate-catala.mjs` (typecheck, overlap proof, `clerk test`
re-running the emitted module against values L4 computed).

| module                                       | assertions | Catala refusals | `clerk` tests agreeing |
| -------------------------------------------- | ---------- | --------------- | ---------------------- |
| `dbs-yuu.l4`                                 | 55         | 0               | 112                    |
| `dbs-womans-world.l4`                        | 88         | 0               | 178                    |
| `citi-rewards.l4`                            | 127        | 0               | 230                    |
| `hsbc-revolution.l4`                         | 123        | 0               | 250                    |
| `uob-ladys-solitaire.l4`                     | 125        | 0               | 242                    |
| `posb-passion.l4`                            | 67         | 0               | 128                    |
| `flat-cards.l4`                              | 29         | 0               | 60                     |
| `miles-card-cases.l4` (through the composer) | 102        | —               | —                      |

Two limits of that evidence, stated so the numbers are not over-read.
A directive that reads an elided `STRING` field (`conditions`, `pool`) passes under `l4 run` and
cannot become a Catala test scope; and a direct `#EVAL` of a whole `Rate answer` becomes a test
scope with no expected value, because a record with an elided field has no Catala JSON rendering.
So the `clerk` figures come from the scalar-field assertions, and the pool-identity and
condition-text claims are checked in L4 only.

Two domain constructors are still wanted and were deliberately not added mid-pass, because the
second pass wrote total `CONSIDER`s over the enumerations that growing them would break: a
description family for HSBC cl.4's professional-services merchants (bullet 6) and something that
names HSBC's own Tax Payment Facility (cl.4 bullet 10's carve-back, now unreachable, so a tax
payment through it answers zero); UOB cl.35's `NORWDS*` prefix and Citi's `SPL AUTO*`/`TL-ABT`
descriptions likewise have no family. Each is pinned by an assertion that will fail when the
constructor arrives.

## 7. Ownership

The cheat sheet (`[S5]`) and the original `which-card.html` belong to Alexis and are read-only;
neither is committed here.
The T&C PDFs are the issuers' published documents, mirrored for versioning.
The L4 is Meng's, and moves to `legalese/canon` under `subjects/sg/miles-card/` once it lands
here (spec: correct the canonical-copy line in both places when that happens).
