# Dialects: `main` and `unstable` are two compilers

This skill describes L4 as it is on `unstable`.
`main` is a different compiler.
Text written from this skill, without asking which compiler will read it, is rejected by `main`, and in a few places below it is accepted and read differently.
A rejection looks like a mistake in your file, when it is the wrong compiler.

Two questions are easy to run together, and this page keeps them apart.

- **The compiler you run** is the `l4` you write and test with.
  `l4 --version` names it: a leading number, as in `1.6.98 (main, 7689b0d, 2026-10-19)`, is a `main` build, and `unstable-` with a date is the prerelease shelf.
- **The dialect you write** is the target: the compiler that has to read the finished file.
  The brief names it.
  If the brief is silent, the target is `main`.
  It is `unstable` only when the brief says so.

Running an `unstable` binary does not license `unstable` syntax.
Encodings are often written with an `unstable` binary and filed in commons, where a `main` build has to be able to read them, so `main` is the default target.
Step 0 of [SKILL.md](../SKILL.md) is the short form of this.
This page is the detail.

## What was measured

Measured 2026-10-19.
`main` moves, so a row is true of the build named here and no other.
A brief that says the target is `main` means this build or a later one, and this build is the minimum.

- **`main`** is build 98, whose `l4 --version` prints `1.6.98 (main, 7689b0d, 2026-10-19)`.
  Build 97 (`1.6.97 (main, 5e3b1cf, 2026-10-17)`) differs in one pull request, described under "Build 97 to build 98" below.
- **`unstable`** is the prerelease-shelf build `unstable-20261015-8730d3f`, whose `l4 --version` prints `unstable-20261015-8730d3f (unstable, 8730d3f, 2026-10-15)`.
- **The documented examples.**
  Of the 108 `.l4` files under `doc/` at `b932724d3`, `main` rejects 42 and the shelf build rejects none.
  The shelf build is six commits older than that tree and still rejects none, so none of the 42 is the shelf being too old: the zero is the control.
- **The probes.**
  `references/dialect-probes/` holds 105 small files, each the whole of one test, named by what they show:

  - a number, `01` to `58`: `unstable` accepts it and `main` rejects it;
  - `alt-`: the spelling to write on `main` instead, which passes on both;
  - `same-`: reads the same on both (where there are assertions, their counts match);
  - `degrades-`: passes `l4 check` on both and means something else, or less, on `main`;
  - `run-`: passes `l4 check` on both and is read with `l4 run`;
  - `main-`: `main` accepts it and `unstable` rejects it;
  - `unstable-`: `unstable` rejects it and `main` accepts it.

  `main` rejects exactly the 58 numbered files.
  The shelf build rejects exactly nine: the three `main-*` files, the five `unstable-refuses-*` files and `unstable-reads-field-for-constructor`.
  The probes are deliberately odd `.l4`, so a repo-wide checker can object to one: `etc/check-not-precedence.mjs` does to `unstable-refuses-not-and`, which therefore carries the `NOT-REACH-OK` marker that checker honours.

To refresh this page, run both binaries over both sets from the root of an l4-ide checkout, and compare with the numbers above:

```bash
etc/dialect-census.sh <main l4> doc
etc/dialect-census.sh <unstable l4> doc
etc/dialect-census.sh <main l4> skills/writing-l4-rules/references/dialect-probes
etc/dialect-census.sh <unstable l4> skills/writing-l4-rules/references/dialect-probes
```

The script prints one line per failing file, with the first error, and a summary count.
`encoding-a-subject/assets/fetch-main-l4.sh` prints the path of a main build, fetching it if need be.
Quote the `--version` line of each binary you ran, as above.
A binary older than the files it reads fails on new syntax and looks like a broken example.
If the unstable run fails any of the 108, that binary is older than the tree, and those files say nothing about `main`.

### Build 97 to build 98

One pull request separates them (legalese/l4-ide#719).
It renamed `` `IS INTEGER` `` to `ISINTEGER` and `` `WAIT UNTIL` `` to `WAITUNTIL`, keeping no alias, and removed the temporal built-ins: `` `EVAL AS OF SYSTEM TIME` ``, `` `EVAL UNDER VALID TIME` ``, `` `EVAL UNDER RULES EFFECTIVE AT` ``, `` `EVAL UNDER RULES ENCODED AT` ``, `` `EVER BETWEEN` ``, `` `ALWAYS BETWEEN` ``, `` `WHEN LAST` ``, `` `WHEN NEXT` `` and `` `VALUE AT` ``.
It also made `DO` a modal of its own, so `MUST DO` no longer parses.
On build 97 the three `EVAL` forms exist and take a `NUMBER` date serial, not a `DATE`.
The shelf build has none of the new spellings, so for these constructs the two compilers now accept different text; the table gives a portable idiom for `IS INTEGER` and for `WAIT UNTIL`.
That is the only difference between the builds that the probes found: probes 01 to 53 fail on build 97 with the same first error (but for 38 to 40), probes 54 to 58 pass on it, and `main-isinteger` and `main-waituntil` fail on it.

## Status on `main`

Each row gives one of three words for what `main` does with the construct.

- **reads**: `main` accepts it and means what `unstable` means.
- **degrades**: `main` accepts it and means something else, or something less. `l4 check` says nothing, and `check.sh` does not see it: it counts error diagnostics and assertion lines, and a `#TRACE` prints neither, so a different trace outcome moves no count.
- **rejects**: `main` gives a parse or type error, and the main check goes red.

## Writing for `main` while running `unstable`

1. Write and iterate with the `unstable` binary if you like.
   Stay with what **reads**.
   Where a row says **rejects**, write what its last column says, or leave the provision out and mark it "not encodable on main" in the coverage table of `NOTES.md`.
2. Before you call a module done, run `check.sh` in the encoding directory.
   The target is `main` unless you set `L4_TARGET=unstable`.
   It fetches the newest main build with `fetch-main-l4.sh` (cached), runs every module with both binaries, and compares the four counts.
   A line that says `reads differently on main` is a module `main` cannot read as it stands, because its counts differ or because `main` did not finish it in `L4_MAIN_TIMEOUT` seconds (300 unless set).
   Exit status 2 means the main step could not run (no main build for this platform, no network, no `fetch-main-l4.sh` beside `check.sh`), and then the check is not done.
3. Know what the check cannot see.
   It does not see a different `#TRACE` outcome.
   Only an error, or an `#ASSERT` that comes out differently, moves a count.
   Three rows differ in what they do, and the check passes all three: an input named in an action, a `MAY` with a `LEST`, and a language tag on `@nlg`.
   Use the spelling the table gives, and compare the two builds' output for every trace yourself: run each file with both builds and read the outcomes.
4. A few constructs have no spelling both compilers read: anything the table says to leave out, and `WAITUNTIL` or `ISINTEGER` where no portable idiom fits (the table gives one for each common use).
   A module that needs one cannot be written with the shelf build.
   Run it with a main build as your `l4` (`L4=$(fetch-main-l4.sh)`); `check.sh` then compares `main` with itself, which proves nothing about `unstable`, so say in `NOTES.md` that the module is main-only.
5. Do not get past a **rejects** row with an `ASSUME` stand-in.
   It type-checks and cannot evaluate: the assertions that reach it fail on both compilers (`degrades-assume-stand-in`).
6. Record the target and the main build in the deposit; `encoding-a-subject`'s `references/canon-deposit.md` says where.

## Silent: `main` raises no error

These rows matter most, because nothing tells you.
In the first, fourth and sixth, `main` answers differently; in the second, third, fifth and seventh, `unstable` refuses what `main` accepts.

<!-- prettier-ignore -->
| Spelling | `unstable` | `main` build 98 | On `main`, write instead |
| --- | --- | --- | --- |
| An input named in an action: `GIVEN creditor …` then `MUST Pay Borrower creditor 10` (`run-must-names-an-input`) | Compares the payload with the input: paying the wrong party leaves the obligation open. | **degrades**: `creditor` is a fresh name that matches any payload: paying a stranger **fulfils** the obligation. | `MUST Pay Borrower payee 10 PROVIDED payee EQUALS creditor` (`run-must-guard-instead`). Same traces, same verdicts for `MUST`, `MAY` and `SHANT`; only the layout of the residual obligation differs. `main`'s own spelling is `EXACTLY`, which `unstable` warns is being retired, and which failed on `main` for a multi-field action (`run-exactly-with-an-input`, `Internal error: creditor is not in scope`). |
| `NOT a AND b` or `NOT a OR b` on one line, with no brackets (`unstable-refuses-not-and`, `unstable-refuses-not-or`) | An error: it reads as `NOT (a AND b)` and asks you to write the brackets. | **reads**: accepted, and read as `NOT (a AND b)`, or `NOT (a OR b)`: `NOT TRUE AND FALSE` is `TRUE`. | Bracket it: `(NOT a) AND b`, or `NOT (a AND b)` (`alt-not-and-bracketed`). Or put `NOT a` and the connective on separate lines at the same indent, which both read the same (`same-not-on-two-lines`). Here `unstable` is the stricter compiler. |
| A party that is not the action's performer, which is the action's first actor-typed field. An obligation: `PARTY Drinker MUST eat` where `eat` is `Action OF Eater, "eat"`, a record (`unstable-refuses-wrong-performer`). An event in a `#TRACE`: `PARTY Drinker DOES eat` (`unstable-refuses-wrong-performer-event`), or `PARTY Lender DOES Pay Borrower Lender 10` for a constructor `Pay HAS payer, to, amount` (`unstable-refuses-wrong-performer-event-ctor`) | An error: `An actor may only perform its own actions.` For a constructor action it checks events only: the obligation `PARTY Lender MUST Pay Borrower Lender 10` is clean on both (`same-constructor-obligation-unchecked`). | **reads**: accepted, with no warning. In a trace the stranger's event is passed over and the obligation stays open. | Name the performer in the action and make the `PARTY` match it: `PARTY Eater MUST eat`. `main` will not catch a mismatch, so check it by eye. Here too `unstable` is the stricter compiler, for records and for the events of constructors, and not for the obligation of a constructor. |
| A language tag on an `@nlg` herald: `@nlg:pt o valor %amount% excede o limite` (`degrades-nlg-language-tag`) | The herald is tagged `pt`, so a rule can carry renderings in several languages. | **degrades**: read as an untagged `@nlg` whose text begins `:pt` (`l4 ast` shows `TNlgString ":pt"`). | Write the herald without a tag; `main` has no per-language heralds. |
| A constructor named like a field of a record input: `b's kind EQUALS Alpha`, where `b` has a field `Alpha` too (`unstable-reads-field-for-constructor`) | The field wins, because the fields of an input are in scope by name (field opening): a warning says so, and the comparison then fails to type-check. | **reads**: the constructor, as written. | Give the constructor and the field different names. `check.sh` goes red on this, and it is `unstable` that misreads it. |
| A `MAY` with an explicit `LEST`: `MAY Pay Borrower Lender 10 WITHIN 5 HENCE FULFILLED LEST BREACH`, when nothing is done in time (`run-may-lest-lapse`) | The permission lapses into the `LEST`: `DEONTIC BREACHED`. | **degrades**: `main` ignores a `LEST` after `MAY`, as its own skill says, and the lapse is `FULFILLED`. | If inaction should be a breach, make it a `MUST`: a lapsed `MUST` is a breach on both. If it should have no consequence, leave the `LEST` off: a lapsed `MAY` without one is `FULFILLED` on both. |
| An infix `EXPONENT` in a module with any `IMPORT`: `IMPORT prelude` then `#EVAL 2 EXPONENT 10` (`main-infix-exponent`) | An error: `unexpected EXPONENT`, after `IMPORT prelude`, `IMPORT daydate`, `IMPORT math` or `IMPORT currency` alike. The same line in a module with no `IMPORT` is accepted. | **reads**: `1024`, with or without an import. | The prefix form, `EXPONENT 2 10`, which both read the same (`alt-exponent-prefix`). |

The first row has a loud half: read `creditor` again in `HENCE` and `main` stops with `There are multiple definitions for the identifier creditor` (probe 43), which names the wrong thing, since the fault is in the action.
The `PROVIDED` spelling removes both (`alt-must-guard-then-hence`).
The same guard is how a field of an input is compared on `main` (`run-field-in-guard`, and see probe 51).

## Loud, and the message names the wrong thing

`main` rejects these and its message points somewhere else.
Read the row before you read the message.

<!-- prettier-ignore -->
| Spelling | `unstable` | `main` build 98 | On `main`, write instead |
| --- | --- | --- | --- |
| A section `GIVEN` (probes 06 to 12) | In scope for every rule under the heading. | **rejects**: Belongs to the next rule only. Seven different messages, listed below this table. | A `GIVEN` on every rule that reads the input (`alt-section-given-on-each-rule`). |
| `BOOLEAN TYPICALLY TRUE` on a field (15) | Accepted. | **rejects**: `The arities of the types do not match. I expected 0 arguments, but I found 2.` | Leave the default out; see `TYPICALLY` below. |
| `DECLARE Applicant` with no body (17) | Accepted: an opaque type. | **rejects**: `unexpected GIVEN`, at the next declaration. | Give the type one field (`alt-record-not-opaque`). |
| `RULES EFFECTIVE DATE AT LEAST d` (36) | Accepted. | **rejects**: ``There are multiple definitions for the identifier `__GEQ__` `` | Take the date as a `GIVEN` input of the rule (`alt-rule-date-as-input`). |
| A date made with `YMD` and compared: `d AT LEAST YMD 2025 7 1` (53) | Accepted. | **rejects**: ``There are multiple definitions for the identifier `__GEQ__` `` | `d AT LEAST (Date 1 7 2025)`, day first (`alt-date-compared`). Alone, the same `YMD` fails plainly: see "Loud and plain" below. |
| `AFTER 3 WITHIN 30`, `AFTER 3 BEFORE d` (32, 33) | Accepted: the edges of the window. | **rejects**: `You are trying to apply order … (which is not a function)`; `The function pay … expects 1 argument`. | Nothing: `main` reads `AFTER 3` as more arguments of the action. |
| `BREACH BY LIST a, b` (34) | Accepted. | **rejects**: `The HENCE clause of a regulative rule is expected to be of type DEONTIC OF …` | `BREACH BY` one party, or `BREACH BECAUSE "…"` (`alt-breach-by-one-party`, `alt-breach-because`). |
| A rule applied inside `MUST (…)`: ``MUST (`payment by` Alice 1500)`` (42) | Accepted. | **rejects**: ``I could not find a definition for the identifier `payment by` `` | Write the constructor: `MUST Pay Alice 1500` (`alt-must-a-constructor`). |
| Field opening: a rule whose `GIVEN` is a record reads `` `the age` `` bare (41) | Accepted. | **rejects**: ``There are multiple definitions for the identifier `__GEQ__` `` | Name the input: `` person's `the age` `` (`alt-field-through-input`). |

Three of these rows give the same message about a comparison operator: `RULES EFFECTIVE DATE` (probe 36), field opening (41) and `YMD` in a comparison (53).
The operator is `__GEQ__` for `AT LEAST` and `__LT__` for `LESS THAN`.
It is not the fault: a name `main` does not know sits beside it, so look there.

A section `GIVEN` followed by exactly one rule compiles on `main` (`alt-section-given-one-rule`), which is why a small file hides it.
What `main` says depends on what follows the `GIVEN`:

<!-- prettier-ignore -->
| What follows the section `GIVEN` | `main` says | Probe |
| --- | --- | --- |
| A second rule that reads the input | `I could not find a definition for the identifier rate` | 06 |
| A directive such as `#EVAL` | `unexpected #EVAL` | 07 |
| An ordinary `GIVEN` | `unexpected GIVEN` | 08 |
| A `§§` heading | `unexpected §` | 09 |
| An input the next rule does not read, supplied with `WITH` | `In the application of … you forgot to supply the following arguments` | 10 |
| A later rule that uses the rule which took the input | ``The first argument of function `__TIMES__` … is expected to be of type NUMBER``, because that rule is now a function | 11 |
| Inputs of function type, as in the `FOR ALL` examples | `The names in a type signature must match those in the definition` | 12 |

## Loud and plain

`main` rejects these and the message names the cause, or near enough.

<!-- prettier-ignore -->
| Spelling | `unstable` | `main` build 98 | On `main`, write instead |
| --- | --- | --- | --- |
| `@lang pt` as the first line of a module (01) | Accepted. | **rejects**: `unexpected '@'` | Nothing: leave it out. `main` has no module language declaration. |
| An `@infixl`, `@infixr`, `@infix`, `@nonassertable` or `@nonexhaustive` line, or any `@word` `main` does not know (45 to 48) | Known, or a warning that the annotation is unknown and is ignored. | **rejects**: `unexpected '@'` | Drop the line, and bracket operator chains by hand. `@export`, `@desc`, `@nlg`, `@ref`, `@ref-map` and `@ref-src` are fine (`alt-annotations-main-knows`). |
| `REFUSE "reason"` (02) | Accepted. | **rejects**: `I could not find a definition for the identifier REFUSE` | Return a `MAYBE`, with `NOTHING` for "this case is not covered" (`alt-maybe-nothing`). The rule's result type changes. |
| `#ASSERT REFUSED e` (03) | Accepted. | **rejects**: `I could not find a definition for the identifier REFUSED` | On the `MAYBE` spelling, `#ASSERT e EQUALS NOTHING` (`alt-maybe-nothing`). |
| `#ASSERT REFUSED e BECAUSE "reason"` (04) | Accepted. | **rejects**: `unexpected BECAUSE` | Nothing: a `MAYBE` carries no reason. Put the reason in a comment. |
| `YMD 2026 10 19` (05) | Accepted; refuses an out-of-range month or day. | **rejects**: `I could not find a definition for the identifier YMD` | `Date 19 10 2026`, day first (`alt-date`). `Date` rolls an out-of-range day over instead of refusing, on both compilers: `Date 29 2 2023` is `Date 1 3 2023` (`alt-date-rolls-over`, read with `l4 run`). Compared with a date, `YMD` fails differently: see above. |
| `TYPICALLY 2` or `TYPICALLY "Singapore"` on a field; `TYPICALLY 18` on a `GIVEN` (13, 14, 16) | Accepted: the default for a case that leaves the fact out. | **rejects**: `unexpected 2`, `unexpected "Singapore"`, `unexpected 18` | Leave it out (`alt-no-typically`). `main` has no defaults: put the presumed value in the `@desc`, and have the caller supply every fact. |
| Sets: `SET OF`, `setFromList`, `setSize`, `` `is in` ``, `UNION` (18 to 22) | In the prelude, with `emptySet`, `setToList`, `is subset of`, `set equals`, `INTERSECT`, `LESS`, `WITHOUT` | **rejects**: `I could not find a definition for the identifier`, for each name | A `LIST OF` and `elem` (`alt-list-elem`). Five names have probes here; the rest are in the same block of the unstable prelude, and a second reader's probes of them found each missing on `main` too. |
| `IMPORT hierarchy`, ``IMPORT `negation-as-failure` `` (49, 50) | In the binary. | **rejects**: `I could not find a module with this name` | Nothing. The other 20 libraries under `jl4-core/libraries/` import on both compilers. |
| The ledger: `RECORD`, `COMMIT`, `ATTEST`, `RECALL`, `RECALL OFFICIAL's` (23 to 27, 52) | Accepted. | **rejects**: `unexpected IS` after `RECORD`, `COMMIT` and `ATTEST`; `could not find a definition` for `RECALL` | Nothing: do not encode a ledger on `main`. Pass the facts in as `GIVEN` inputs. |
| `EVERY Tenant t`, `EVERY Tenant t IN tenants`, `WHOSE …` (28 to 30) | Accepted, with a join line such as `ONCE ALL HAVE`. | **rejects**: `unexpected MUST`; `unexpected IN` | One obligation for one named party: take the party as a `GIVEN` input, write `PARTY t`, and compare the action's payload to it in a `PROVIDED` guard (`alt-party-as-input`). There is no group and no join on `main`. |
| `WITHIN 5 OF THE DEADLINE`, `OF THE JOIN` (31) | Accepted: counts from the earlier deadline. | **rejects**: `unexpected OF` | `WITHIN 5` (`alt-within`) counts from when the obligation is entered, which is a different meaning: say so in a comment. |
| The same name defined in two nested `§` sections (35) | Accepted: a use reads the nearest. | **rejects**: ``There are multiple definitions for the identifier `prescribed rate` `` | Give them different names. |
| `RULES EFFECTIVE DATE` on its own (37) | Accepted: the version date of the rules. | **rejects**: ``I could not find a definition for the identifier `RULES EFFECTIVE DATE` `` | Take the date as a `GIVEN` input of the rule (`alt-rule-date-as-input`). |
| The temporal built-ins: `` `EVAL UNDER VALID TIME` ``, `` `EVAL AS OF SYSTEM TIME` ``, `` `EVAL UNDER RULES EFFECTIVE AT` `` with a date (38 to 40), `` `VALUE AT` `` (57), `` `EVER BETWEEN` `` (58) | Present; the `EVAL` forms take a `DATE`. | **rejects**: ``I could not find a definition for the identifier `EVAL UNDER VALID TIME` ``: removed in build 98. | Nothing on `main` from build 98: you cannot evaluate a rule at a date there. Take the rule-version date as a `GIVEN` input and give each vintage its own tests (`alt-rule-date-as-input`). |
| `` `IS INTEGER` `` (54) | Accepted. | **rejects**: ``I could not find a definition for the identifier `IS INTEGER` ``: build 98 spells it `ISINTEGER`, with no alias. | `FLOOR x EQUALS x`, which agrees on both for whole numbers, fractions, negatives and zero (`alt-is-integer-by-floor`). `ISINTEGER` is main's spelling (`main-isinteger`), and `unstable` rejects it. |
| ``(`WAIT UNTIL` 8)`` in a `#TRACE` (55) | Accepted: the house form in the skills. | **rejects**: ``I could not find a definition for the identifier `WAIT UNTIL` ``: build 98 spells it `WAITUNTIL`, with no alias. | An event at that time by a party the rule does not constrain, such as `PARTY Seller DOES pay AT 8`: the clock moves the same way on both (`alt-wait-by-an-event-of-another-party`). It needs an action that party can perform; where there is none, `WAITUNTIL 8` is main's spelling (`main-waituntil`), and `unstable` rejects it. |
| `MUST DO pay` (56) | Accepted. | **rejects**: `unexpected DO`: from build 98 `DO` is a modal of its own. | Drop the `DO`: `MUST pay`. |
| A `\[` or `\]` inside an inline `[…]` annotation (44) | Accepted: a literal bracket. | **rejects**: `unexpected %`, because the annotation ended at the first `]` | Put no bracket inside an inline annotation (`alt-inline-bracket`). |
| A field read in an action's argument: `MAY Take Official (c's measure)` (51) | Accepted. | **rejects**: `unexpected 's` | `MAY Take Official m PROVIDED m EQUALS c's measure` (`run-field-in-guard`). |

## Reads the same

These **read**: the same four counts on both compilers, where a probe has assertions to count.

- The annotations `@export`, `@desc`, `@ref`, `@ref-map`, `@ref-src` and an untagged `@nlg` (`alt-annotations-main-knows`).
- Naming the inputs of a call with `WITH` (`same-with-named-inputs`).
- `EITHER` with `LEFT`, `RIGHT` and `CONSIDER` (`same-either`).
- Qualified section paths and `AKA` on a section heading (`same-qualified-section-path`, `same-aka-section`).
- A rule name that contains a word like `by` (`same-mixfix-name`).
- Records and their construction with `WITH` (`same-record-with`).
- `BREACH BY` one party, and `BREACH BECAUSE` (`alt-breach-by-one-party`, `alt-breach-because`).
- `Date d m y` (`alt-date`).

## The documented pages, by cause

The 42 pages under `doc/` that `main` rejects, with the row that explains the first error on each.
A parse error hides any type error after it, so a page can carry a second cause behind the first.
Two kinds of evidence are used.
"Rewritten" means a scratch copy of the page, with each section `GIVEN` turned into module-level `ASSUME` lines, passes `l4 check` on `main`, so the section `GIVEN` is the whole cause.
"Probe" means the page's first error is the error a numbered probe gives.

- **Section `GIVEN`, rewritten (13):**
  `reference/operators/and-example.l4`, `or-example.l4`, `not-example.l4`, `implies-example.l4`, `unless-example.l4`,
  `reference/operators/arithmetic/arithmetic-example.l4`, `reference/operators/comparisons/comparisons-example.l4`,
  `reference/functions/decide-example.l4`,
  `reference/types/a-an-example.l4`, `assume-example.l4`, `either-example.l4`, `for-all-example.l4`,
  `tutorials/getting-started/encoding-legislation-example.l4`.
- **Section `GIVEN`, probe (4):**
  `reference/functions/with-example.l4` (probe 11),
  `reference/syntax/comment-example.l4` and `identifier-example.l4` (probe 10),
  `tutorials/section-given/what-a-section-needs-to-know.l4` (probe 06).
- **Section `GIVEN` and a second cause (2):**
  `reference/syntax/section-given-example.l4`, whose first error is `TYPICALLY 2` (probe 13);
  `reference/syntax/field-opening-example.l4`, whose first error is field opening (probe 41).
- **`REFUSE`, `REFUSED`, `BECAUSE` (3):**
  `reference/control-flow/refuse-example.l4`, `concepts/legal-modeling/non-answers-example.l4`, `tutorials/refuse/when-a-rule-cannot-answer.l4` (probes 02 to 04).
- **Sets (1):** `reference/libraries/sets-example.l4` (probes 18 to 22).
- **`EVERY`, `WHOSE` (3):** `reference/regulative/every-example.l4`, `every-run-example.l4`, `whose-example.l4` (probes 28 to 30).
- **`OF THE DEADLINE`, `OF THE JOIN` (3):** `reference/regulative/within-example.l4`, `reference/regulative/after-example.l4`, `tutorials/obligations/what-follows.l4` (probe 31).
- **`BREACH BY LIST` (1):** `reference/regulative/because-example.l4` (probe 34).
- **`TYPICALLY` (1):** `reference/types/typically-example.l4` (probes 13, 14).
- **Opaque `DECLARE` (1):** `reference/types/opaque-example.l4` (probe 17).
- **The ledger (1):** `tutorials/multi-temporal-modeling/bna-adoption-two-axes.l4` (probe 52).
- **`RULES EFFECTIVE DATE` (1):** `tutorials/multi-temporal-modeling/gst-rate-change-example.l4` (probe 36).
- **Nested sections sharing a name (1):** `reference/syntax/sections-example.l4` (probe 35).
- **An inline annotation with `\[` (1):** `reference/syntax/annotation-example.l4` (probe 44); it also has a section `GIVEN`, hidden behind the parse error.
- **`` `WAIT UNTIL` `` (5):**
  `reference/regulative/deontic-example.l4`, `courses/advanced/module-a1-regulatory-examples.l4`, `tutorials/obligations/one-obligation.l4` and `several-parties.l4` (probe 55; rewritten: with `WAITUNTIL n` in place of ``(`WAIT UNTIL` n)`` each passes on build 98);
  `concepts/legal-modeling/regulative-layer-whole-example.l4`, which then fails on a rule applied inside `MUST (…)` (probe 42).
- **An input named in an action, read again in `HENCE` (1):** `courses/advanced/module-a3-contracts-examples.l4` (probe 43).

All paths are under `doc/`.
None of the 42 is unattributed.
