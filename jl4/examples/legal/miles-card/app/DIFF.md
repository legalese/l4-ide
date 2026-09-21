# `D.generated.js` against the app's hand-edited `D[]`

Generated array: `D.generated.js`, built by `gen-d.mjs` from `scenarios.json` and the L4 encoding.
Hand-edited array: the `const D=[…]` in `docs/projects/miles-card/app/which-card.html` in the
homelab checkout, Meng's fork of the app (Alexis's original sits beside it as
`which-card.alexis-original.html` and is not touched). Neither is copied into this repository; the
generator reads a copy only when given `--reference`.

Taken against the copy at homelab commit `48c1bcc` ("docs(miles-card): spec + primary T&C corpus
for the L4 encoding", 2026-09-21), which was that path's current content when this was written.
Reproduce it with:

```sh
node gen-d.mjs --reference <homelab>/docs/projects/miles-card/app/which-card.html
```

**Nothing below has been fixed on either side.** This is a report, not a patch. Several of the
disagreements are the app being right and the encoding being incomplete, several are the reverse,
and a few are neither — they are artifacts of which single transaction was chosen to stand for a
row that covers several merchants. Each entry says which.

Both arrays have **51 rows in the same order**, and `n`, `k` and `mcc` are byte-identical, because
`scenarios.json` copied those three fields out of the app. Nine rows are the clock and clipboard
reference cards; they carry no transaction and are not generated.

---

## Scoreboard

Every card slot in the app was matched against the same card in the generated row, and every card
the generator emitted that the app does not list was counted too. 364 comparisons:

| class                                             | count |
| ------------------------------------------------- | ----- |
| (a) the encoding disagrees with the app           | 29    |
| (b) the app carries something the encoding cannot | 16    |
| (c) rendering, curation or scenario choice only   | 319   |

The 29 in class (a) fall into six findings, and the 16 in class (b) into three. Class (c) is mostly
one thing: the app shows the two to five cards worth using and the generator shows every card that
earns anything, which is 193 of the 319.

A further 39 of class (c) are the app not listing POSB PAssion on a row where the encoding also
says it earns nothing — agreement, not curation, and counted separately for that reason. Those 39
appeared only when the drop rule changed; see §a2.

---

## (a) The encoding disagrees with the app

### a1. The merchant indicator is not a fact the app can assert — 18 slots, 10 rows

Rows 2, 6, 7, 8, 9, 12, 16, 23, 24, 48.

The app states a flat `4 mpd · S$1k/mo` for Woman's World, Citi Rewards or HSBC Revolution. The
encoding answers `4 mpd if the merchant flags online, else 0.4`, because whether the charge posts
as online is decided by the merchant's acquirer and not by the issuer. Three issuers say so in the
same words, and all three are cited on the generated slot: `[dbs-womans-card-tnc cl.13]`,
`[citi-rewards-10x-tnc cl.6(ii)]`, `[hsbc-revolution-reward-points-tnc cl.6]`.

This is the disagreement the app was already half-aware of. Its own row 11 note and its Sources row
say exactly this about Woman's World and about an Apple Pay tap. The finding is that the same
reasoning applies to Lazada, Shopee, Amazon, Netflix, StarHub, a hotel, a ClassPass studio and a
Gojek ride, and the app asserts a flat rate on all of them.

Worth noting where the two branches are not 4 and 0.4: on the overseas row the Woman's World
card-present branch is **1.2**, not 0.4, because foreign-currency spend earns its own rate.

### a2. PAssion's promotion ended on 30 September 2025 — 3 slots, 3 rows

Rows 2, 3, 25. App: `5 mpd · S$507/mo` and `~4.5 mpd · S$507/mo`. Encoding: **0 mpd**, with
`status` = `Source expired`, citing `[posb-passion-yuu-tnc cl.3]` — "The Promotion is valid from 1
October 2023 to 30 September 2025" — and cl.4, which counts only transactions charged inside that
period. No document in the corpus renews it.

**This is the most consequential single difference, and an earlier version of this generator hid
it.** The drop rule removed any card answering 0 mpd, so PAssion was absent from all 42 generated
rows, and with it the only `EXPIRED` pill the table would ever have carried — the reason deleted
along with the rate.

**Changed 2026-09-21: a zero answer whose status is `Source expired` is now kept.** PAssion appears
on all 42 rows at `0 mpd` with an `EXPIRED` pill, sorted last because it earns nothing. Ordinary
`Verified` and `Unconfirmed` zeroes are still dropped. The 3 slots counted above are the rows where
the app also lists PAssion and quotes a live rate for it; on the other 39 the app does not list it,
which is agreement rather than disagreement and is counted in class (c) as `APP-OMITS-ZERO`.

What a reader now sees on rows 2, 3 and 25 is the app's `5 mpd` beside the encoding's `0 mpd ·
EXPIRED`, which is the comparison that should be made. What the renderer does with a zero-rate slot
is the app's call and is not decided here: the row carries the pill, the citation and the reason,
and hiding it again would be a rendering choice rather than a data one.

### a3. HSBC Revolution's cl.7 MCC table does not contain the MCCs of four rows — 4 slots, 4 rows

| row | the app says                    | the encoding says | why                                                                 |
| --- | ------------------------------- | ----------------- | ------------------------------------------------------------------- |
| 17  | 7-Eleven, `4 mpd · contactless` | 0.4 mpd           | 5411 is absent from the whole cl.7 table                            |
| 18  | Cheers, `4 mpd · contactless`   | 0.4 mpd           | 5411, same                                                          |
| 38  | hair/nails/spa, `4 mpd`         | 0.4 mpd           | 7230 is absent; 5977 is too                                         |
| 42  | Decathlon, `4 mpd · in store`   | 0.4 mpd           | 5941 is absent — 5655, sports **apparel**, is the one that is there |

Both slots cite `[hsbc-revolution-reward-points-tnc cl.7]` and cl.8, the base-rate clause it fell
through to.

Rows 17 and 18 are the app contradicting itself, not just the encoding: its own Revolution
reference row already says "Does NOT earn: grocery contactless". Rows 38 and 42 are new.

### a4. Three of the four bakery/bubble-tea merchants are not yuu Participating Merchants — 2 slots, row 22

App: `DBS yuu 10 mpd · S$822/mo · scan app`. Encoding: **0.14 mpd** on both networks, citing
`[dbs-yuu-card-tnc cl.8]`, whose Participating Merchant list is closed and names Cold Storage, CS
Fresh, Jasons Deli, Giant, Guardian, 7-Eleven, foodpanda, Gojek, SimplyGo, Charge+, CHAGEE and
Singtel. BreadTalk, Toast Box and Thye Moh Chan are **PAssion** merchants (cl.5(ii)), not yuu ones.
Only CHAGEE on that row is a yuu merchant, and only for orders placed in the CHAGEE app.

### a5. The yuu American Express card earns nothing at Charge+ — 1 slot, row 15

App: one `DBS yuu` slot at `10 mpd · S$822/mo if cap room`. Encoding: the Visa earns 10.08 and the
American Express earns **0.28**, citing `[dbs-yuu-card-tnc cl.Appendix 1 — Charge+]`. The app has
one yuu row where the terms have two cards.

### a6. A bakery MCC is not a UOB Dining MCC — 1 slot, row 22

App: `Solitaire — Dining 6 mpd`. Encoding: **0.4 mpd**, with the condition "The Schedule 1 category
for this transaction is: none", citing `[uob-ladys-cards-tnc cl.Schedule 1]` and cl.4(b).

**Read this one with its scenario.** Row 22 names no MCC, and `scenarios.json` chose BreadTalk at 5462. The app's own cafes row already says 5462 "is NOT a Dining MCC", so the two agree about the
rule and differ only because the app's row assumed a different MCC than the fixture did. A CHAGEE
or Toast Box transaction coding 5814 would land in Dining.

---

## (b) The app carries something the encoding cannot

### b1. Standard Chartered Smart is not a card in the corpus — 4 slots, rows 1, 13, 16, 22

`6% cashback if listed`, `6% cashback`, `6% cashback · ~S$60/mo`, `6% · Toast Box only`. The
`Card` enum has nine constructors and SC Smart is not one; its T&C is listed in the spec as still
to obtain. Two things would be needed, not one: the card, and a cashback denomination —
`Rate answer` is miles-denominated throughout and has no percentage field.

### b2. PayAll is a rail, not a card — 3 slots, rows 26, 36, 37

`PremierMiles via PayAll — ~1.2 mpd · fee applies`. `Transaction` has no notion of a payment
facilitator standing between the cardholder and the merchant, and `Rate answer` has no fee side, so
an answer of the form "it earns, but it costs you 2%" cannot be expressed. The same gap would swallow
CardUp and iPaymy, which appear in the corpus only as `Description pattern` constructors on
exclusion lists.

### b3. The Lady's Savings Account uplift — 9 slots, rows 0, 1, 2, 3, 4, 5, 10, 18, 21

App: `Solitaire 6 mpd`. Encoding: `4 mpd`, and it says why on the slot itself: "A Lady's Savings
Account uplift above 4 miles per S$1 is NOT in this document and is unconfirmed here. What the held
T&C states is 10X UNI$ per S$5, which is 4 miles per S$1."

This is a deliberate refusal recorded in `miles-card-domain.l4`, not an oversight. It is also the
largest single block of numeric disagreement in the table, and it will stay 4 until the savings
promotion's own terms are obtained. **A reader looking at the generated array with no context will
read `4 mpd` as a correction of the app. It is not; it is an abstention.**

---

## (c) Rendering, curation and scenario choice

319 comparisons, in five groups.

**c1. The app curates and the generator does not — 193.** The app shows the two to five cards worth
reaching for. The generator emits every card that earns anything, plus the kept-zero one, and after
the drop rule that is 9 slots on 37 rows, 8 on one and 4 on the remaining four. Among them are
`DBS yuu 0.14 mpd` on every non-yuu merchant and `Citi PremierMiles 1.2 mpd` on all 42 rows.
Choosing which to show is an editorial judgement the generator does not make.

Three of those omissions look like candidate findings rather than curation, because the encoding
puts a card at or near the top of a row the app does not list it on at all:

- row 25, Malaysian Ringgit: the encoding gives `UOB Lady's Solitaire 4 mpd` and
  `HSBC Revolution 4 mpd` on a Johor restaurant charge, above the PRVI 2.4 the app leads with.
- row 22, bakery: `HSBC Revolution 4 mpd` tops the generated row, MCC 5462 being row 44 of the
  cl.7 table. The app does not list Revolution here.
- row 50, "Anything else": `HSBC Revolution 4 mpd`, because the fixture's 5999 is row 42 of that
  same table. A true catch-all MCC would not be, so read this one as a scenario artifact.

**c2. Ordering — every row with a conditional answer.** The generator sorts by `miles per dollar`,
which for a conditional answer is the **lower** branch, so `4 mpd if the merchant flags online,
else 0.4` sorts at 0.4 and lands below a flat 1.4. No generated row has a conditional answer in the
top slot; several app rows do. The sort is conservative by construction and is not what the app
does.

**c3. Number and unit wording — 86.** `10.08 mpd` against the app's `10 mpd`; `S$822.86/mo` against
`S$822/mo`; `S$1,000/mo · calendar month` against `S$1k`; `uncapped` against `uncapped` with no
basis. One of these is not pure wording: on the public-transport row the generated cap is
**S$811.27**, not S$822.86, because SimplyGo earns 35.5 **bonus** points per dollar (9.5 under
cl.7(a) plus 26 under cl.7(b)) where a yuu merchant earns 35 (9 plus 26), so the same 28,800-point
bonus cap admits fewer dollars of spend. The app's single `S$822/mo` covers both.

**c4. One scenario cannot carry a row about two MCCs — 1 counted, 3 affected.** Row 44 states its
own hedge, `6 mpd IF it codes 5499`, and the fixture picked 5995, so the two do not actually
disagree; the app's conditional was simply not exercised. Rows 5 (5411 or 5499) and 21
(5812/5814/5499) have the same shape and happened not to produce a numeric mismatch. Each
`mccChoice` in `scenarios.json` records which code was chosen and why.

**c5. The app omits a card that earns nothing — 39.** Every one of these is POSB PAssion on a row
the app never recommended it for, kept in the generated array at `0 mpd · EXPIRED` by the status
exception in §a2. The two sides agree; the generator is simply saying out loud what the app says by
omission. This group did not exist before the drop rule changed, and it is the whole of the class
(c) increase from 280 to 319.

---

## What a row needed that the domain does not have

1. **A cashback card and a cashback denomination.** b1. Four rows lead with a percentage.
2. **A fee-bearing payment rail.** b2. Three rows route a bill through PayAll for a fee.
3. **Two MCCs for one row.** c4, rows 5, 21, 22, 44. `Transaction` has one
   `merchant category code`, and the app's answer for these rows is a fork on which code the
   merchant registered. It takes two scenarios, and the projection has no way to join them.
4. **Several merchants behind one row, answering differently.** a4 and a5, rows 12 and 22. One
   scenario per row cannot say "Gojek earns 10 and Grab earns 0.14", which is what the app's note
   says in prose.
5. **Cap room.** Row 15's `if cap room` and the app's whole tap-to-demote interaction need to know
   how much of a cap is left. `Month position` deliberately excludes it — the allocation problem is
   out of scope by spec §6 — so the generated `cap` can only ever state the cap, never the room.
6. **A savings-account balance.** b3. Declined on purpose, and the reason is on every Solitaire
   slot.

Two further limits are in the fixture set rather than the domain, and are cheap to lift:

7. **`charge kind` is `Retail purchase` on all 42 scenarios.** Row 46 is about gift cards and wallet
   top-ups, and a top-up may well post as `Cash advance or quasi-cash`. The constructor exists; no
   scenario uses it, so the exclusions that key on it are untested here.
8. **`merchant indicator` is `Unknown` on all 42 scenarios**, by instruction, which is what makes a1
   visible. Nothing exercises the `Flags online` or `Flags card-present` branches.

Finally, the status pills. Three of the four are now exercised against this corpus: no pill on 218
slots, `UNCONFIRMED` on 97, and `EXPIRED` on 42 — one per row, all of them PAssion, reaching the
renderer because of the §a2 change.

`DISPUTED` is the one branch still unreachable. `Disputed by source` maps to it and no module
returns that status, because `miles-card-disputed.l4` is empty until the formal acceptance run fills
it from the pipeline's assert report. Two things follow, and the second is the one that bites:
the pill is untested, and the drop rule does **not** keep a zero answer whose status is
`Disputed by source` — only `Source expired` is in that set, deliberately, since a rule written for
a case that cannot yet arise is a rule nobody can check. Whoever fills that module should revisit
both.
