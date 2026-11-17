# O4 option B: event-record defaults, parked

**Status, 2026-11-18: parked, not landed.**
Option A is in force: the service refuses an event's party or action record that leaves out a field with a `TYPICALLY` default, in both modes (`refuseEventRecordGaps` in `jl4-service/src/Backend/Jl4.hs`), a nested record included.
Option B, which would let `soft` take such a default and list it in `presumed`, was built and reviewed twice on 2026-11-18, and its last state is commit `c99088fbb`, kept on a branch named `feat/o4-b-event-defaults` that is in no pull request.
It lands when the three changes in §5 are made and the tests in §6 pass in a fresh full gate.
How this page was verified: the findings are an independent reviewer's measurements, replayed on a service built from `c99088fbb`; the author of this page re-read the recorded answers (they are in `o4-b-review-repros/`) and the line numbers of §4 against `c99088fbb`, and did not re-run the requests.

## 1. What the card asked for

Card O4 (ruled 2026-10-11) asked for listing a default of an event's party or action record: `soft` takes it, `hard` refuses it.
Its ruling note says to keep A until B lists, and the wave's rule was that if B cannot clear its bar, A stays for the whole piece.
Its four conditions, as the wave was briefed on them:

1. Three service tests, for a party record, an action record and a nested record: a default the answer reads shows `soft` answering with the field listed in `presumed`; an event skipped by an expiry or by an earlier mismatch lists nothing; `hard` refuses.
   If the listing cannot be made to hold, A stays.
2. B still accepts the constructor-keyed nested record that clients send today (`{"zhome": {"Address": {"zip": 5}}}`).
3. Until B lands, the published schema stops promising the default for event records (this is a separate change; see `TYPICALLY-ONE-BEHAVIOUR-SPEC.md`, O4 and U4 constraint 3).
4. Under B a verdict can rest on a default the client left out of an event although the request states the party in its arguments; `presumed` shows it and does not make it correct.

The O4 and U4 lines of `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` are the owning record of the ruling; this page is the record of the build and why it stopped.

## 2. What was built

Every record an event writes as a party or an action is generated as a top-level definition of its own, numbered per event (`event 0 party`, `event 0 party 1`), and a nested record is referred to by name.
The evaluator reports the site where the checker filled in a default; the service maps the site to the path the request wrote (`events[0].party.licence`) only if the site's line, counted from the end of the generated program, is exactly one definition line and the column is where the construction starts, and refuses the request otherwise.
`hard` refuses the same paths, from the same renderer.
In `jl4-core`, the normal form of a breach leaves out the event behind each failure (nothing prints it), and the comparison of an event's party with the obligation's takes back its reports of defaults when the event's action then does not match.
The first review of the build (2026-11-18) found, and the branch fixed with a test each: a nested record that took a field written after it (F1), a default listed for an event the answer did not carry (F2), `hard` not refusing a default of a `ONE OF` payload or of a rule used as a constructor (F3), a path that named the wrong one of two identical events (F4), and a party default listed for an event skipped on its action (F7).
It did not change a `MAYBE` field written as a record, which is read as `NOTHING` without a warning (F5; present on `unstable` already, documented in `jl4-service/README.md`).
`jl4-service/test/EventRecordSpec.hs` holds 39 examples, 14 of them the groups of a property test over 84 generated record shapes and 174 request pairs.

## 3. Why it is parked: the second review

An independent reviewer replayed the branch at `c99088fbb`.
It found no event-record path (`events[i]...`) wrongly listed or left out where the verdict rests on it, in any shape it tried.
It also found these, and the decision of 2026-11-18 was that B does not clear the bar, so A stays.
The requests are in `o4-b-review-repros/` (see its `README.md`).

| id  | what                                                                                                                                                                                                                                                                                                                           | kind                              | status                                           |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------- | ------------------------------------------------ |
| S1  | The retraction drops a default the verdict rests on. Trigger: an `EVALTRACE` evaluated inside a field of an obligation's party, and an earlier event skipped by its action. It hits an argument's default and the rules' own defaults too, not only event records.                                                             | silent, a wrong answer            | measured (`nestarg-*`, `nest-*`)                 |
| S1b | The same mechanism, found by argument: a cell leaves the table of defaults at its first report, so a later read of it reports nothing; if the comparison forced it and a value-keeping computation read it later in the same stretch, the retraction takes back the only report.                                               | silent, a wrong answer            | argued, no reproducer                            |
| C1  | Over-listing: a skipped event lists a default although the answer is the same with the field written either way. Skip exits: a false `PROVIDED`; an act before its window opens; a party field that differs after the defaulted one; the `MAYBE`-of-record `NOTHING` defect. This breaks condition 1; the verdict stays right. | wrong `presumed`, a right verdict | measured (`guard-*`, `early-*`, `ord-*`, `mb-*`) |
| P1  | At realistic sizes the service refuses a request B should answer: 150 events each leaving out one of 20 fields, or 80 events leaving out all 20, give HTTP 500 "Evaluation resource limit exceeded" at the default 256 MB. The cause is argued, not measured (below).                                                          | loud                              | measured (`p2one-*`, `p2loop-*`)                 |
| H1  | `hard` refuses an event that writes every input of a rule used as a constructor (`Not a constructor 'mkAddr' ...`), which option A would have answered.                                                                                                                                                                        | loud, a regression for `hard`     | measured (`fk-w-hard`)                           |

**S1.**
In `nestarg-2` the argument leaves out `licence` (default `"full"`), a `drive` event comes first, then the matching `wear seatbelt` event: the value is `FULFILLED` and `presumed` is `[]`.
With `licence` written `"learner"` (`nestarg-2w`) the value is a residual obligation, so the verdict does rest on the default; `nestarg-2h` shows `hard` refusing it, which is right.
The cause, read in `Machine.hs` at `c99088fbb` (`forcedByPartyComparison`, lines 667-680): it takes the nearest `UpdateThunk` or `Contract8` frame, and inside the party field's computation that frame is the inner run's `Contract8`, so the inner force counts as made by the outer comparison; it lies inside the outer marks, so the outer action mismatch takes it back, and the thunk keeps its value, so nothing reads the default again.
This falsifies the assumption that no other comparison runs between the two marks.
It cannot occur without the F7 retraction: at `112c9c7dd`, the commit before it, nothing removes a report (`git show 112c9c7dd:jl4-core/src/L4/EvaluateLazy/Machine.hs` has no `retractPresumed`).
The smallest fix the reviewer found: record the stack depth of the stretch's own `Contract8` in the `Contract7` handler beside `partyForces`; make `forcedByPartyComparison` return the depth of the `Contract8` it found, store it in the report, and take back only reports at the stretch's depth.

**S1b.**
`notePresumedForce` (lines 742-750) deletes a cell from the table of defaults at its first report.
The depth fix of S1 does not cover S1b.
The comment above `retractPresumed`, that a computation's read stays listed, holds only when the computation read the cell first.

**P1.**
Not the retraction: 400 skipped events with 20 fields each are answered.
The likely cause is `eventRecordDefault`, called once per presumed entry from `deonticPresumed`, which rebuilds the event definitions (`CodeGen.hs`, the `eventDefinitions` call near line 827) and re-splits the program and the wrapper into lines (near line 836) every time.
The fix: build the definitions and a map from line to definition once per request.
With a 2 GB limit, 200 events by 20 fields by 4 obligations took 0.98 s against 0.82 s with every field written (measured by the reviewer).

**H1.**
At `112c9c7dd` the check looked a key up in the declared constructors with a default of no fields; the refusal came with the review fix that made `hard` refuse any key that is not a declared constructor.
The choice was recorded as assumed, not ruled (choice (b) in the message of commit `a6f9b8356`): refuse rather than work out what a rule leaves to its defaults.
It is optional to change.

## 4. The skip exits in `Machine.hs`, and what the retraction covers

Line numbers are those of `jl4-core/src/L4/EvaluateLazy/Machine.hs` at `c99088fbb`.

| exit                                      | where                                                                                       | covered by the retraction                                                                                                                                                                 |
| ----------------------------------------- | ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| action does not match                     | `patternMatchFailure`, the `Contract11` case, 5438-5442 (frame pushed at 3507)              | yes, the only exit it covers                                                                                                                                                              |
| party differs                             | `Contract8`, `ValBool False`, 3510-3516 (equality forces fields up to the first difference) | no                                                                                                                                                                                        |
| `PROVIDED` false                          | `Contract10`, `ValBool False`, 3629-3636 (party and action matched)                         | no                                                                                                                                                                                        |
| window not open (act before its `AFTER`)  | `Contract10`, `ValBool True` with `opens`, 3547-3567                                        | no                                                                                                                                                                                        |
| expiry                                    | `Contract5`, 3235; the expiry branch, 3461-3479                                             | nothing to retract: the revealing event's party is never compared; without a `LEST` the event is printed in the breach (3478) and listed by design; with a `LEST` it is re-offered (3479) |
| party or `PROVIDED` depends on an unknown | 3519 and after 3636                                                                         | not a skip: the evaluation is stuck                                                                                                                                                       |

**Why covering the other exits naively makes S1 fire more often.**
`PROVIDED` runs in the obligation's own environment (`env Map.union henceEnv`, line 3532), so it can read the cells the comparison already reported; those reads report nothing, because the cell left the table at its first report.
If `PROVIDED` is false the skip rests on that read (`MUST pay ... PROVIDED driver's licence EQUALS "full" LEST officer MUST fine`: the skip leads to expiry and a `LEST` residual that never prints the driver), and a retraction there leaves `driver.licence` unlisted, silently.
For an early act the skip rests on time alone, but a `WHERE` value cached while `PROVIDED` ran can carry the read into the `LEST` (the S1b shape).

## 5. What it would take to land, in this order

0. **The S1 depth fix first.** Every retraction exit added later makes S1 fire more often.
1. **A settle design.**
   A direct force reports, but leaves its cell in the table of defaults until the stretch settles, so every later read inside the stretch (`PROVIDED`, a value-keeping computation, a `WHERE` value) reports again, as a force that the retraction keeps.
   At a match the stretch's cells are dropped; at each skip exit (action mismatch, `PROVIDED` false, early act) only the direct reports are taken back.
   A stuck evaluation and an exception unwinding through `Contract11` must settle the stretch too.
   This closes S1b at the existing exit and covers two of the C1 exits.
   The party-differs frame (`ScrutinizeEnvironment` and `ScrutinizeActions` in `ContractFrame.hs`) must carry the marks, as `ActionDoesn'tmatch` does.
   Estimated 50 to 80 lines in `Machine.hs` and `ContractFrame.hs`; the risk is moderate and in the safe direction (a missed settle leaves cells registered: extra reports, never a missing entry); the cost is one report per read of a still-registered cell, bounded by one stretch.
2. **A ruling on a party that differs.**
   The verdict rests only on the deciding field (and its nested path), so listing the other defaults the equality forced is over-listing.
   Covering it needs the record equality (`runBinOpEquals`, shared by every `=` in the language) to mark before each field under `Contract8` and keep only the deciding field's forces: moderate size, medium to high risk.
   The alternative is to rule it acceptable (the listing is of what was forced, and this was forced; T6 says "listing only the defaulted inputs actually forced") and to narrow the docs' sentence "an event the answer did not rest on lists nothing".
3. **A ruling on expiry.**
   Does a revealing event that the breach prints (a bare `MUST ... WITHIN` with no `LEST`) count as "rests on"?
   Today its defaults are listed when it is printed and not when a `LEST` hides it.
   The wave's reviewer treated this as a ruling, not a defect.

Also owed, independent of the three: build the definitions and the line map once per request (P1), and decide whether `hard` should answer an event that writes every input of a rule used as a constructor (H1).

## 6. Tests to add first

The settle design (§5.1) needs four tests; only the first is known to be red on `c99088fbb` (it is S1):

- a nested `EVALTRACE` after an event skipped by its action (`nestarg-*`);
- a `PROVIDED` that reads the party, with a `LEST`;
- a read cached in a `WHERE` value;
- an early act.

The property and the examples in `EventRecordSpec.hs` also need four additions:

1. the nested `EVALTRACE` case above, red today;
2. skipped events that list: a false `PROVIDED`, an act before its window opens, and a defaulted field declared before the field that differs (the branch's fixtures all declare the key field first, which hid this);
3. scale under the default 256 MB: 150 events each leaving out one field (P1);
4. the property itself, which sends one event per request, never runs `hard` and always declares the key field first: extend it to pairs of events, to `hard`, and to a defaulted field declared first.

## 7. What held

All on `c99088fbb`, per the reviewer.

- Several obligations on one event stream: `RAND` (also three-way), `ROR`, the `LEST` re-offer, `HENCE` and `LEST` at one position, `SHANT`, an `EVERY` barrier. The answers were right and the listing moved with the default.
- Event index 10 and above; two identical events.
- Pairs of events against an independent oracle, 9 of 9: depth 3, an enum, `MAYBE`, a list of records, a constructor-keyed nested record, `RAND`.
- Single events: depth 3, an enum, `TYPICALLY NOTHING`, a field named like its type; lists of records (path `events[0].party.homes[1].Address.floor`); `JUST`-wrapped records and imported types.
- The path mapping: `" WITH "` in names, non-ASCII names, a 230-character name; a newline, carriage return, U+2028, U+0085, a tab, a quote and a backslash in values round-trip; the same characters in names are refused, loudly, in both modes. No request listed a wrong event or field.
- `hard` refuses every path `soft` lists; `/evaluation` and `/evaluation/batch` agree. MCP is not compared under `hard`, because it evaluates `soft` whatever the request says (`McpServer.hs`, lines 648 and 656; the `presumption` argument is the U3 change).
- Condition 2: the constructor-keyed nested record is accepted in every shape tried.
- The normal-form change of F2: `revealedBy` is read only inside the machine, on values, before the normal form, and by one view in `ValueLazy.hs`; no reader in `jl4-service`, `jl4/app` or `jl4-lsp`.
- The early exit of `retractPresumed`: the counter only rises, so `upto > from` holds exactly when a report was made, nested reports included.

## 8. Known, not introduced by B

A `MAYBE`-of-record field written in an event as an object of two or more keys is read as `NOTHING` (the `FnObject _ -> Right "NOTHING"` fallback of `fnLiteralToL4Expr`, already on `origin/unstable` when B was built).
Under B it can make a listing point at the wrong cause: in `mb-gap` the event is skipped because its `zhome` was read as `NOTHING`, yet `presumed` lists `licence`.
Changing the fallback is a separate decision, with an unmeasured blast radius.

## 9. Decisions this page leaves to the maintainer

- §5.2: field-granular listing for a party that differs, or the narrower promise.
- §5.3: whether a printed revealing event "rests on" its defaults.
- Whether to build the settle design at all, given that A refuses the requests concerned and condition 3 (the schema change) is published separately.
- The question of F7, which of two readings of "lists nothing" holds for an event skipped on its action, is not asked while B is parked; it comes back with B.
