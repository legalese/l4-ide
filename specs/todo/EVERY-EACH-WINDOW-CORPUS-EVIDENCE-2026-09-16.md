> **Status (2026-09-16):** the measurement that decided R-X5's amendment (`EVERY-EACH-QUANTIFIER-SPEC.md`
> §5.1.2.2). Numbers were computed in code from agent labels; the snapshot, extractor, sampler and every
> label are on the Legalese office machine at `/Volumes/transcend/corpora/pile-of-law/` (Pile of Law,
> Henderson et al. 2022, CC-BY-NC-SA 4.0; 9.6 GB of the drafting-register subsets, `SHA256SUMS` pinned) and
> are re-derivable from `extract.py` → `sample.py` → the classification workflow. A first run of the
> arithmetic dropped 23 of 38 strata through a join bug and concluded the opposite; it was caught by
> cross-checking the classifier counts against the totals and is kept beside the raw data as a warning.

# EVIDENCE B2 — corpus evidence for the `AFTER d1 WITHIN d2` default (two offsets vs re-anchored)

Question (Meng, 2026-09-15): when an L4 rule writes `AFTER d1 WITHIN d2`, is the unmarked reading **two offsets from one anchor** (shape B, `[a+d1, a+d2]`, spec default R-X5) or **re-anchored** (shape C, `[a+d1, a+d1+d2]`, Meng's proposal)? The unmarked form is whichever leaves more wild sentences writable without an explicit `OF` anchor.

Source: 7.7-million-phrase extraction from the Pile of Law drafting-register subsets (legislation: uscode, cfr, state_code, eurlex, us_bills, federal_register, frcp, fre, constitutions; contracts: atticus_contracts, edgar, resource_contracts, cfpb_cc, tos). Provenance `/Volumes/transcend/corpora/pile-of-law/README.md`; extractor `extract.py` (its regex buckets are the strata); sampler `sample.py`. Every number is quoted from the computed run (`computed-b2.json` beside this file). Audit agreement below 0.8 marks a stratum **soft**.

## 1. Answer

Re-anchored wins, narrowly and softly. Across the extraction, the estimated population of re-anchored windows (shape C, `[a+d1, a+d1+d2]`) exceeds that of two-offsets-from-one-anchor windows (shape B, `[a+d1, a+d2]`) in both registers: contracts B 88,882 [33,206–414,507] vs C 136,912 [53,366–486,006], **B:C = 0.65** (conservative interval 0.07–7.8, taken as B.lo/C.hi to B.hi/C.lo); legislation B 30,152 [8,604–150,721] vs C 37,483 [14,129–159,185], **B:C = 0.80** (0.05–10.7). The direct measurement — the `both_edges` stratum, the regex that demands an opener and a closer in one phrase, i.e. the wild analogue of `AFTER d1 WITHIN d2` — is 1 B to 3 C of 80 in contracts (32,557 vs 97,672 phrases) and 0 B to 4 C of 80 in legislation (0 vs 41,835), and four of those seven C's are literally "within d2 after/following the expiration of such d1-period" (shape agreement 0.95 and 0.80). So the reading that leaves more wild sentences writable without an `OF` anchor is Meng's re-anchored one, in both registers. Two caveats bound the claim. First, both shapes are rounding error against the single-closing-edge shape A (contracts 3,910,180; legislation 1,064,488), and the summed B and C intervals overlap almost entirely because both totals are dominated by 1-in-80 hits inside the million-phrase strata. Second, the wild B is not `AFTER d1 WITHIN d2` at all: 74/80 in `contracts/two_offset` and 43/80 in `legislation/at_least_not_more` are "not less than X nor more than Y before/after D", mostly backward from a fixed date, and every B-heavy stratum's notes ask for a signed direction and per-bound units rather than an unmarked default; while the wild C almost always re-anchors on the **end of a named period** ("expiration of the cure period"), which an L4 rule would state through the period's name rather than by eliding an anchor. The default therefore decides a small number of sentences; flipping R-X5 to re-anchored is the corpus-consistent choice, but the larger design pressure is a first-class named period with an `.end`.

## 2. Population by shape, per register

Estimated phrases in the full extraction (per-stratum Wilson estimates, summed; §8 explains why the intervals are conservative).

| Shape                         | Contracts (est. phrases) |        95% interval | Legislation (est. phrases) |      95% interval |
| ----------------------------- | -----------------------: | ------------------: | -------------------------: | ----------------: |
| A single closing edge         |                3,910,180 | 3,485,284–4,254,848 |                  1,064,488 | 965,942–1,167,272 |
| B two offsets, one anchor     |                   88,882 |      33,206–414,507 |                     30,152 |     8,604–150,721 |
| C re-anchored on a period end |                  136,912 |      53,366–486,006 |                     37,483 |    14,129–159,185 |
| O opening edge only           |                  503,950 |     312,675–927,137 |                     83,908 |    53,228–208,687 |
| ABS absolute date             |                  436,276 |     343,404–767,261 |                    332,799 |   244,071–492,814 |
| DUR bare duration             |                  298,747 |     180,901–667,307 |                     54,680 |    39,819–166,313 |
| X false positive              |                  686,458 |   487,585–1,100,515 |                    617,697 |   496,242–784,331 |
| U undecidable                 |                    7,952 |       1,406–291,866 |                        293 |        52–102,293 |

Direct measurement, the `both_edges` stratum (opener and closer in one phrase):

| Register    | Stratum pop |   A |   B |   C |   O | ABS | DUR |   X | B est. (interval)      | C est. (interval)       | Shape agr | Anchor agr |
| ----------- | ----------: | --: | --: | --: | --: | --: | --: | --: | ---------------------- | ----------------------- | --------: | ---------: |
| contracts   |   2,604,593 |  70 |   1 |   3 |   1 |   0 |   3 |   2 | 32,557 (5,756–175,717) | 97,672 (33,428–272,307) |      0.95 |       0.95 |
| legislation |     836,692 |  62 |   0 |   4 |   6 |   2 |   3 |   3 | 0 (0–38,337)           | 41,835 (16,410–101,762) |      0.80 |       0.85 |

Raw sample counts summed over all 19 strata (1,520 hits per register, not population-weighted): contracts B 171 / C 177; legislation B 87 / C 148.

## 3. Opening-edge and closing-edge vocabulary

Sums of `words.open` / `words.close` across the 19 strata per register (1,520 hits each). A compound label ("after/from") is counted under every canonical token it contains, so columns exceed 1,520. Sample sums over regex-selected strata, not population estimates.

| Opening token                                                    | Contracts | Legislation |
| ---------------------------------------------------------------- | --------: | ----------: |
| after                                                            |       476 |         594 |
| following                                                        |       190 |          98 |
| from                                                             |       100 |          95 |
| beginning with / on                                              |       123 |         181 |
| commencing                                                       |        57 |          14 |
| upon                                                             |        24 |          33 |
| not earlier than / no earlier than / not before / no sooner than |       200 |         182 |
| expiry of / end of / lapse of                                    |        97 |         185 |
| not more than / not less than (two-offset bound)                 |       102 |           0 |
| none                                                             |       317 |         458 |

| Closing token                                      | Contracts | Legislation |
| -------------------------------------------------- | --------: | ----------: |
| within                                             |       301 |         301 |
| not later than / no later than / in no event later |       226 |         249 |
| prior to                                           |       119 |          64 |
| before                                             |        85 |          89 |
| on or before                                       |        32 |          17 |
| by                                                 |         8 |          14 |
| not more than                                      |        40 |          31 |
| not less than (two-offset near bound)              |        38 |           0 |
| until / through / ending / during                  |         5 |          29 |
| none                                               |       752 |         749 |
| other                                              |         1 |          15 |

Reading: "after" is the modal opener and "within" the modal closer in both registers, so L4's vocabulary matches the wild one; but "not later than" is a near-equal closer, half of all hits carry no closing word, and in contracts the backward closers ("prior to", "before", "on or before": 236) are three quarters of "within". Several strata note that "within N days **of** X" — no opening word — has no slot in the label set.

## 4. Anchor kinds

Sums of `words.anchor` across strata (1,520 hits per register). E = a party's act or document event; L = another obligation's or period's lifecycle point; D = a defined or fixed date; T = the instrument's own commencement; N = no anchor within ±240 characters; U = undecidable.

| Anchor | Contracts | Legislation |
| ------ | --------: | ----------: |
| E      |       572 |         668 |
| L      |       407 |         312 |
| D      |       351 |         153 |
| N      |       137 |         291 |
| T      |        49 |          93 |
| U      |         4 |           3 |

L:E is 0.71 in contracts and 0.47 in legislation. The L share is inflated by the L-selecting regexes (`after_end_of_period` L 77/80 and 53/80; `after_expiry` 77 and 62; `not_before_expiry` 56 and 37). In the neutral `both_edges` stratum L is 9/80 (contracts) and 11/80 (legislation) against E 52 and 51. Legislation's N 291 reflects the "Upon receipt of X, … shall, within N days, …" idiom, where the anchor is the trigger clause.

## 5. Day-counting conventions

Sums of `words.counting` across strata (1,520 hits per register; compound labels counted under each token).

| Convention                                  | Contracts | Legislation |
| ------------------------------------------- | --------: | ----------: |
| none stated                                 |     1,106 |       1,195 |
| business / working / trading / banking days |       242 |          83 |
| calendar days                               |        38 |          46 |
| exclusive (first day out)                   |        93 |         120 |
| inclusive (first day in)                    |         6 |          70 |
| weekend / holiday / period rollover         |        22 |          16 |
| calendar-unit rounding (month/quarter/year) |        18 |           8 |
| clear days                                  |         2 |           0 |

Three hits in four state nothing (contracts 1,106/1,520; legislation 1,195/1,520). "Exclusive" comes almost entirely from the two `day_after` strata (77/80 and 71/80), where "beginning on the day after X" spells the convention out; legislation's "inclusive" 70 is mostly `commencing_on` (55/80), the federal "N-day period beginning on the date of enactment" idiom, which makes the anchor day day 1. Business-day units are a contracts habit (`day_counting` 62/80); legislation delegates to interpretation acts.

## 6. Precision and audit agreement, per stratum

X = false positives among the 80 labelled; audit = blind second pass over 20; **soft** = shape or anchor agreement below 0.8.

| Stratum                         |       pop |   X | X frac |   U |   B |   C | audit n | shape agr | anchor agr | soft? |
| ------------------------------- | --------: | --: | -----: | --: | --: | --: | ------: | --------: | ---------: | ----- |
| contracts/absolute_date         |   794,845 |  35 |   0.44 |   0 |   0 |   0 |      20 |      1.00 |       1.00 |       |
| contracts/after_duration        |   106,124 |  12 |   0.15 |   0 |   0 |   3 |      20 |      0.75 |       0.95 | soft  |
| contracts/after_end_of_period   |     4,756 |   2 |   0.03 |   0 |   0 |  77 |      20 |      1.00 |       1.00 |       |
| contracts/after_expiry          |   106,682 |  15 |   0.19 |   0 |   0 |  20 |      20 |      0.85 |       0.95 |       |
| contracts/at_least_not_more     |     5,739 |   0 |   0.00 |   0 |  63 |   0 |      20 |      1.00 |       0.90 |       |
| contracts/bare_after            |    57,355 |  23 |   0.29 |   0 |   0 |   2 |      20 |      0.95 |       0.90 |       |
| contracts/bare_within           |   310,663 |   6 |   0.07 |   1 |   0 |   2 |      20 |      0.80 |       0.95 |       |
| contracts/both_edges            | 2,604,593 |   2 |   0.03 |   0 |   1 |   3 |      20 |      0.95 |       0.95 |       |
| contracts/commencing_on         |    72,511 |   0 |   0.00 |   0 |   0 |   8 |      20 |      0.55 |       0.85 | soft  |
| contracts/cooling_off           |   325,491 |  26 |   0.33 |   1 |   0 |   5 |      20 |      0.65 |       0.75 | soft  |
| contracts/date_of_event         |    62,612 |  42 |   0.53 |   0 |   2 |   2 |      20 |      0.75 |       0.80 | soft  |
| contracts/day_after             |     3,510 |   0 |   0.00 |   0 |  12 |  49 |      20 |      0.80 |       0.90 |       |
| contracts/day_counting          |   734,268 |   0 |   0.00 |   0 |   2 |   1 |      20 |      0.90 |       0.65 | soft  |
| contracts/event_anchor          |   709,862 |  14 |   0.17 |   0 |   2 |   2 |      20 |      0.75 |       0.90 | soft  |
| contracts/not_before_expiry     |       717 |   0 |   0.00 |   0 |   5 |   1 |      20 |      0.75 |       0.95 | soft  |
| contracts/not_earlier_than      |    21,028 |   0 |   0.00 |   0 |   9 |   0 |      20 |      0.95 |       0.80 |       |
| contracts/not_later_than        |   276,174 |   0 |   0.00 |   0 |   0 |   1 |      20 |      0.95 |       1.00 |       |
| contracts/two_offset            |    14,020 |   0 |   0.00 |   0 |  74 |   0 |      20 |      1.00 |       0.75 | soft  |
| contracts/within                | 2,462,993 |   0 |   0.00 |   0 |   1 |   1 |      20 |      0.85 |       1.00 |       |
| legislation/absolute_date       |   873,678 |  49 |   0.61 |   0 |   1 |   0 |      20 |      1.00 |       0.35 | soft  |
| legislation/after_duration      |    38,341 |  10 |   0.13 |   0 |   2 |   3 |      20 |      0.80 |       0.95 |       |
| legislation/after_end_of_period |       444 |   0 |   0.00 |   0 |   2 |  78 |      20 |      1.00 |       0.85 |       |
| legislation/after_expiry        |    15,094 |   2 |   0.03 |   0 |   1 |  17 |      20 |      0.90 |       0.85 |       |
| legislation/at_least_not_more   |     2,207 |   1 |   0.01 |   0 |  43 |   0 |      20 |      1.00 |       1.00 |       |
| legislation/bare_after          |    27,981 |  17 |   0.21 |   0 |   2 |   1 |      20 |      0.90 |       0.80 |       |
| legislation/bare_within         |   108,105 |   5 |   0.06 |   0 |   0 |   8 |      20 |      1.00 |       0.75 | soft  |
| legislation/both_edges          |   836,692 |   3 |   0.04 |   0 |   0 |   4 |      20 |      0.80 |       0.85 |       |
| legislation/commencing_on       |    23,373 |   0 |   0.00 |   0 |   1 |   4 |      20 |      0.70 |       1.00 | soft  |
| legislation/cooling_off         |    23,404 |  12 |   0.15 |   1 |   0 |   3 |      20 |      0.85 |       0.80 |       |
| legislation/date_of_event       |    12,600 |  11 |   0.14 |   0 |   0 |   1 |      19 |      0.79 |       0.95 | soft  |
| legislation/day_after           |     1,633 |   1 |   0.01 |   0 |   2 |  16 |      20 |      0.65 |       1.00 | soft  |
| legislation/day_counting        |    42,947 |   9 |   0.11 |   0 |   0 |   1 |      20 |      0.90 |       0.95 |       |
| legislation/event_anchor        |   124,690 |  35 |   0.44 |   0 |   1 |   3 |      20 |      0.95 |       0.95 |       |
| legislation/not_before_expiry   |       227 |   7 |   0.09 |   0 |   5 |   6 |      20 |      1.00 |       0.75 | soft  |
| legislation/not_earlier_than    |     8,251 |   0 |   0.00 |   0 |  10 |   0 |      20 |      0.95 |       1.00 |       |
| legislation/not_later_than      |   181,547 |   0 |   0.00 |   0 |   0 |   2 |      20 |      1.00 |       0.95 |       |
| legislation/two_offset          |    21,529 |   0 |   0.00 |   0 |  16 |   0 |      19 |      1.00 |       1.00 |       |
| legislation/within              |   715,439 |   0 |   0.00 |   0 |   1 |   1 |      20 |      1.00 |       1.00 |       |

Soft strata: contracts `after_duration`, `commencing_on`, `cooling_off`, `date_of_event`, `day_counting`, `event_anchor`, `not_before_expiry`, `two_offset`; legislation `absolute_date`, `bare_within`, `commencing_on`, `date_of_event`, `day_after`, `not_before_expiry`. Among the B/C-bearing strata, `contracts/two_offset` (B 74/80) is soft on anchor only and `legislation/day_after` (C 16/80) on shape; the `after_end_of_period` and `after_expiry` strata and the `both_edges` direct measurement are not soft.

## 7. Ten verbatim exemplars

**Shape B (two offsets, one anchor):**

1. `contracts/at_least_not_more` #2: "Such mailing shall be at least 30 days and not more than 60 days before the date fixed for redemption." — https://github.com/TheAtticusProject/cuad
2. `contracts/two_offset` #20: "shall state a date, which shall be not fewer than 30 days nor more than 60 days after the date such notice is given, on which the termination … is effective. The date so stated … shall be the "date of termination."" — https://github.com/TheAtticusProject/cuad
3. `contracts/both_edges` #8: "within three (3) months prior to or two (2) years following a "Change in Control"" — https://github.com/TheAtticusProject/cuad
4. `legislation/two_offset` #54: "shall file the notice of lien no sooner than 60 days and no later than 120 days after the date on which the lien attached to the real property" — https://drive.google.com/drive/folders/1pwCK380GHW-0d6C5k-CF1YdGgYXu32Hj?usp=sharing
5. `legislation/after_end_of_period` #18: "(A) Not earlier than the third business day following the close of the public comment period; and (B) Not later than the fifth business day following the close of the public comment period" — https://www.govinfo.gov/bulkdata/CFR/2020/CFR-2020.zip

**Shape C (re-anchored on a period end):**

6. `contracts/both_edges` #21: "within five (5) days following the expiration of such ninety (90) day period" — https://github.com/TheAtticusProject/cuad
7. `contracts/after_duration` #22: "If after thirty (30) days from its receipt of an Exercise Notice, the Company has not paid the Exercise Price ..., the Company shall issue to Holder within 10 days thereafter a convertible promissory note" — https://github.com/TheAtticusProject/cuad
8. `contracts/after_end_of_period` #2: "the Company does not make the necessary corrections within thirty days of receipt of your written notice, you may terminate your employment within the ten days following the expiration of such thirty day notice period" — https://github.com/TheAtticusProject/cuad
9. `legislation/both_edges` #64: "within ten (10) days from and after the expiration of the five (5) day period hereinbefore mentioned, agree upon and select and name a third arbitrator" — https://drive.google.com/drive/folders/1pwCK380GHW-0d6C5k-CF1YdGgYXu32Hj?usp=sharing
10. `legislation/bare_within` #11: "if the board does not appoint an eligible person within 10 days, the appointment shall then be made by the Governor within 10 days thereafter" — https://drive.google.com/drive/folders/1pwCK380GHW-0d6C5k-CF1YdGgYXu32Hj?usp=sharing

Exemplar 7 is the closest wild match to the bare surface form `AFTER d1 … WITHIN d2`, and its reading is re-anchored, `[a+30, a+40]`; exemplars 1, 2 and 4 show the wild B form, which names both bounds and needs no default.

## 8. Method and limits

- **Strata are regex buckets.** `extract.py` defines 19 pattern families; each family crossed with the two registers is one stratum, 38 in all. Strata are disjoint by regex, not by meaning.
- **N = 80 per stratum**, drawn by one-pass reservoir sampling (`sample.py`); 3,040 labelled hits. Each hit was labelled for shape (A/B/C/O/ABS/DUR/X/U), opening and closing word, anchor kind and stated counting convention, from ±240 characters of context.
- **Blind audit** of 20 hits per stratum by a second agent (19 in `legislation/date_of_event` and `legislation/two_offset`); `agree` is the fraction on which the two labels coincide.
- **Hits are phrases, not windows.** One window can produce two hits (its opener under `after_duration`, its closer under `within`). Population figures count phrases, not distinct provisions; several strata report heavy verbatim duplication across state codes (`legislation/after_end_of_period`: 444 hits, roughly 170 distinct provisions).
- **Register skew.** The contracts side is dominated by `atticus_contracts` and `edgar`, i.e. US commercial and securities-law drafting (409A, Reg AB, credit agreements); legislation by US federal and state codes, with eurlex and constitutions a small minority.
- **Intervals are per-stratum Wilson 95% intervals, summed.** Summing bounds across 19 strata gives a wider, conservative interval for the total. The B and C totals are dominated by single hits in the million-phrase strata (`contracts/within` 1 B → 30,787; `contracts/both_edges` 1 B → 32,557 and 3 C → 97,672; `legislation/both_edges` 4 C → 41,835), so the point estimates are fragile to one relabel. The B:C ratio intervals in §1 are ratios of summed bounds, wider still.
- **False-positive mass** (contracts X 686,458; legislation X 617,697) comes mainly from `absolute_date` (cohort and applicability bands; 347,745 and 535,128), `contracts/cooling_off` (105,785) and `event_anchor` ("years of service"; 124,226 and 54,552). It does not touch the B:C question but caps any regex-only census.

## 9. What this does NOT settle

- **Whether the literal form `after d1 … within d2` occurs often enough to matter.** No regex isolates it; the strongest witness is a single exemplar (§7 #7). The wild B and C are lexically different from each other and from L4's form, so the corpus says which _meaning_ is commoner, not which meaning drafters attach to L4's _surface form_.
- **Drafter intent in the ambiguous cases.** `contracts/bare_within` #64 ("48 hours written notice … within 24 hours Tenant shall resolve") is undecidable between A and C by wording alone; labels record what ±240 characters support, not what a court would hold.
- **Population-weighted vocabulary, anchor and counting figures.** §§3–5 are equal-weight sums; a stratum of 444 phrases counts as much as one of 2.6 million.
- **The soft strata.** Fourteen of 38 fall below 0.8 on shape or anchor agreement; the direct measurement is not among them, but `legislation/day_after` (C 16/80, shape 0.65) and `contracts/two_offset` (B 74/80, anchor 0.75) are.
- **Whether the default is worth having.** A outnumbers B and C combined about 17:1 in contracts (3,910,180 vs 225,794) and 16:1 in legislation (1,064,488 vs 67,635), and the strata notes converge on other primitives as the binding constraint: a named period with `.end`, signed (backward) offsets, later-of/earlier-of anchor combinators, the "promptly, and in any event within N" pair, calendar snapping, and a scoped day-counting default. The corpus ranks re-anchored above two-offset; it does not rank either above "require the anchor to be written".
- **Non-US and non-English drafting**, and anything after the Pile of Law snapshot.
