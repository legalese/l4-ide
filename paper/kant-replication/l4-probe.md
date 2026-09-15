# Can L4 express the Chubb/Codex policy faithfully?

Probe run 2026-08-31. Every claim below was produced by running the binary at
`/Users/mengwong/src/legalese/l4wt/callgraph-materiality/dist-newstyle/build/aarch64-osx/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4`
with `JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/callgraph-materiality/jl4-core/libraries`,
or by reading a named `file:line` in that tree. Probe sources are in
`/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/c1881847-0452-4e2d-bab9-49cb2315f002/scratchpad/kant-repl/runs/probe/`.

**Headline.** L4 expresses this policy more faithfully than the Prolog encodings the paper studied,
and the reason is not raw expressiveness — it is that the three things the paper found Prolog
smuggling past the reader (a calendar approximation, a two-valued reading of a three-valued
condition, and a homogeneous reading of a heterogeneous list) all become _things you must write
down_ in L4. Two of the four Prolog failure classes are caught by the compiler; one is caught only
if you write scenario tests; one is caught by the compiler _only if_ you give the quantities
distinct types, which the paper's own relative-date convention actively discourages.

---

## 1. Month arithmetic: L4 has it, calendar-correctly, and the paper did not need to sidestep

**Answer: month-granular arithmetic exists as a first-class stdlib function with documented,
cross-engine-validated end-of-month semantics.** The relative-months workaround the paper's prompt
imposes (`prompts/A32-unguided-policy.txt`: _"Assume that all dates/times in any query to this code
… will be given RELATIVE to the effective date … there will never be a need to calculate the time
elapsed between two dates"_) is not needed in L4, and it costs something real (see §4b(ii)).

### Evidence

`jl4-core/libraries/daydate.l4:406` defines `add months`, and `:421` defines `add years` on top of
it. The 20-line comment at `daydate.l4:382-401` is worth quoting because it is exactly the
question clause 1.3 raises:

> Add a whole number of months or years to a date, **CLAMPING** the day to the last day of the
> target month when the original day does not exist there. 31 January plus one month is 29 February
> in a leap year and 28 February otherwise; the first anniversary of 29 February 2024 is 28 February 2025.
>
> The clamp is not one convention picked from several. It is what Excel's EDATE does, what
> `actus-schedule` already did for schedule generation, and — MEASURED on 2026-08-05 against
> Drools/KIE 8.44.0.Final and Camunda 8.7.6 (zeebe-dmn) — what FEEL's `date + duration("P1Y")` does
> on both DMN engines, over months and years alike, in all six probed cases.

That is the answer to "which anniversary convention?" being _recorded and justified in the tree_
rather than chosen silently by a model at generation time.

`runs/probe/p1-months.l4`, run verbatim:

```l4
IMPORT daydate

`effective date` MEANS YMD 2025 1 31

`6th month anniversary` MEANS `add months` `effective date` 6
`7th month anniversary` MEANS `add months` `effective date` 7

#EVAL `effective date`
#EVAL `6th month anniversary`
#EVAL `7th month anniversary`
#EVAL `add months` (YMD 2025 1 31) 1
#EVAL `add years`  (YMD 2024 2 29) 1
#EVAL `add years`  `effective date` 1
#EVAL `6th month anniversary` `is before` `7th month anniversary`
#EVAL `effective date` PLUS (6 TIMES `Days in a month`)
#EVAL `effective date` PLUS 180
```

Output (`l4 run`, exit 0):

```
Evaluation[1]  DATE OF 31, 1, 2025      -- effective date
Evaluation[2]  DATE OF 31, 7, 2025      -- 6th month anniversary
Evaluation[3]  DATE OF 31, 8, 2025      -- 7th month anniversary
Evaluation[4]  DATE OF 28, 2, 2025      -- 31 Jan + 1 month, CLAMPED (not 3 March)
Evaluation[5]  DATE OF 28, 2, 2025      -- 29 Feb 2024 + 1 year
Evaluation[6]  DATE OF 31, 1, 2026      -- one-year term, clause 3.6
Evaluation[7]  TRUE                     -- DATE is ordered; deadlines compare directly
Evaluation[8]  DATE OF  1, 8, 2025      -- the "6 average months in days" approximation
Evaluation[9]  DATE OF 30, 7, 2025      -- the "180 days" approximation
```

Three things fall out:

- **Evaluations 2 vs 8 vs 9 differ.** The month-correct 6-month anniversary of 31 Jan 2025 is
  31 July; six average months of 30.436875 days is 1 August; 180 days is 30 July. A wellness visit
  on 31 July 2025 is timely on one reading and out of time on another. A day-granular encoding has
  to pick one and does not tell you it picked.
- **DATE is an ordered type.** `is before` / `is after` / `__LT__` are overloaded on DATE at
  `daydate.l4:707,713,718`, so clause 1.3's "no later than" is a direct comparison, not a serial
  subtraction.
- **`YMD y m d` is the strict constructor** (`daydate.l4:104-117`): it bounds-checks and refuses a
  rolled component, so `YMD 2023 2 29` and a day/month transposition stop evaluation loudly.
  `Date d m y` is the lenient, rolling sibling. That distinction is itself a fidelity tool — an
  effective date read off a signature block goes through the strict one.

### What the workaround costs, precisely

If you _do_ adopt the paper's relative-months convention, three costs are measurable in this tree:

1. **The calendar question is not answered, only deferred to whoever computes the query.** "Month 6"
   in a query is a number; whether 31 July or 1 August satisfies it is decided outside the encoding,
   unreviewably.
2. **Clause 3.6's "period of one year from that date" and clause 1.2's "midnight … on the last day
   of the policy term" cannot be evaluated at all** without a real effective date, so the
   cancellation instant (see §5) is unencodable.
3. **Age and elapsed-months become the same type**, which is what re-opens Prolog failure class (b).
   Demonstrated in §4b(ii) below with a wrong answer and no diagnostic.

---

## 2. Clause 1.1(3): "still pending OR has been satisfied in a timely fashion"

**Answer: name the third state as a type, derive the status from an assessment date, and read the
disjunction off the status.** L4 gives you two independent ways to do this — a constitutive enum
(recommended, because clause 1.3's deadlines are absolute) and the regulative layer (which gives
pending/fulfilled/breached natively but whose deadlines are relative; see §5).

The reason this matters is not ergonomics. Writing the three states down **exposes a real
contradiction between 1.1(3) and 1.2** that a boolean encoding hides:

- 1.1(3) says the policy is in effect if 1.3 is _pending or timely-satisfied_.
- 1.2 says cancellation is deemed to occur if 1.3 _has not been satisfied in a timely fashion_.

Read literally, 1.2's negation swallows `Pending` too — the policy is cancelled from day one until
the wellness visit is confirmed. 1.1(3) shows the drafter did not mean that. A two-valued encoding
must silently pick one; a three-valued encoding can write both down and evaluate the difference.

### Evidence

`runs/probe/p2-threestate.l4`:

```l4
DECLARE `Condition 1.3 status` IS ONE OF
  Pending             -- the 7-month deadline has not yet arrived
  `Satisfied timely`  -- visit by month 6, confirmation by month 7
  Missed              -- the deadline arrived and the condition was not met

DECLARE `Wellness facts`
  HAS `effective date`    IS A DATE
      `assessment date`   IS A DATE      -- when we ask; usually the hospitalisation
      `visit date`        IS A MAYBE DATE
      `confirmation date` IS A MAYBE DATE

GIVEN f IS A `Wellness facts`
GIVETH A `Condition 1.3 status`
`condition 1.3 status` MEANS
  IF   `clause 1.3 performed` f
  THEN `Satisfied timely`
  ELSE IF NOT ((f's `assessment date`) `is after` (`confirmation deadline` f))
       THEN Pending
       ELSE Missed

GIVEN f IS A `Wellness facts`
GIVETH A BOOLEAN
`limb 1.1(3) holds` MEANS
  CONSIDER `condition 1.3 status` f
  WHEN Pending            THEN TRUE
  WHEN `Satisfied timely` THEN TRUE
  WHEN Missed             THEN FALSE

`1.2 cancels -- literal reading` MEANS
  NOT (`condition 1.3 status` f EQUALS `Satisfied timely`)

`1.2 cancels -- reading harmonised with 1.1(3)` MEANS
  `condition 1.3 status` f EQUALS Missed
```

Output (`l4 run`, exit 0, all four `#ASSERT`s satisfied):

```
Evaluation[1]  Pending             -- month 3, nothing done yet
Evaluation[2]  Missed              -- month 9, nothing done
Evaluation[3]  Missed              -- visit in time, confirmation late
Evaluation[4]  `Satisfied timely`  -- both in time
Evaluation[5]  TRUE                -- 1.2 LITERAL reading, on the Pending claim
Evaluation[6]  FALSE               -- 1.2 HARMONISED reading, on the same claim
Evaluations[7-10]  assertion satisfied  (x4)
```

Evaluations 5 and 6 are the payoff: the two readings of 1.2 **agree everywhere except on
`Pending`**, and the encoding says so out loud instead of choosing.

Three design points that make this work:

- **The third state only exists relative to an assessment date.** `Pending` is not a property of the
  facts, it is a property of the facts _as at a moment_. The record therefore carries
  `assessment date` alongside the effective date — clause 1.1 anchors it at "the time of the
  hospitalisation … on which the claim … is premised".
- **`MAYBE DATE` distinguishes "no visit" from "a late visit"** — `WHEN NOTHING THEN FALSE` in
  `happened no later than`. Prolog's negation-as-failure conflates them.
- **`CONSIDER` over the enum is exhaustiveness-checked** (§4e), so adding a fourth state later —
  e.g. `Waived` — turns every reader of the status into a compile-time warning rather than a silent
  fall-through.

---

## 3. Clause 2.1: a list whose items are not the same kind of thing

Items 1–4 are activities an injury can "arise directly or indirectly out of". Item 5 is a **status
of the claimant at the time of hospitalisation**: an injury does not arise out of being 80 in the
same sense it arises out of skydiving. Item 5 also has a textual tell — it is the only item that
begins with "If", i.e. the only one not grammatically continuing the chapeau.

**Answer: do not flatten the five into five booleans. Give each ground its own operand type, so the
mismatch sits in the `DECLARE` where a reader sees it, and write the competing readings as two
named functions.** L4 does not — and should not — pick a reading for you; what it gives you is a
place to put both, and a witness fact that separates them.

### Evidence

`runs/probe/p3-heterogeneous-list.l4`:

```l4
DECLARE `Hazardous activity` IS ONE OF
  Skydiving, `Military service`, `Fire fighting`, `Police service`

DECLARE Claim
  HAS `activities the injury arose out of` IS A LIST OF `Hazardous activity`
      `age at hospitalisation`             IS A NUMBER
      `age contributed to the injury`      IS A BOOLEAN

-- Reading A: item 5 is a STANDALONE status bar; the causal chapeau does not reach it.
`item 5 -- reading A, standalone status bar` MEANS
  c's `age at hospitalisation` AT LEAST 80

-- Reading B: the chapeau reaches item 5, so age must be a direct or indirect CAUSE.
`item 5 -- reading B, chapeau reaches item 5` MEANS
      c's `age at hospitalisation` AT LEAST 80
  AND c's `age contributed to the injury`

`struck by lightning at 82` MEANS Claim WITH
  `activities the injury arose out of` IS EMPTY
  `age at hospitalisation`             IS 82
  `age contributed to the injury`      IS FALSE
```

Output:

```
Evaluation[1]  TRUE   -- reading A excludes the 82-year-old lightning victim
Evaluation[2]  FALSE  -- reading B does not
Evaluation[3]  assertion satisfied  -- the readings agree on `skydiving at 40`
Evaluation[4]  assertion satisfied
Evaluation[5]  assertion satisfied  -- fold form agrees with the hand-written OR
Evaluation[6]  assertion satisfied
```

The structural moves that carry the weight:

- **The operand types differ and the types say so.** `injury arose out of` takes a
  `Hazardous activity`; item 5 takes a `NUMBER` of years. There is no type at which all five items
  are the same predicate, and the encoding does not manufacture one.
- **Items 1–4, being genuinely homogeneous, get a fold** —
  ``any (GIVEN a YIELD `injury arose out of` c a) `every hazardous activity` `` — which makes the
  disjunction structural rather than four hand-typed `OR`s. Item 5 stays outside the fold, and the
  fact that it _cannot_ be folded in is the encoding's way of showing it is a different kind of
  thing. (This is exactly where a Prolog encoding drops five sibling clauses into one predicate and
  the distinction disappears.)
- **`age contributed to the injury` is an explicit field that only reading B consults.** Its
  presence in the record is the marker that a causal question about age is being asked at all; a
  reader can grep for it.

---

## 4. Do L4's types and exhaustiveness catch the four Prolog failure classes?

| #   | Failure class                                       | Caught?                                                             | How                                                                  |
| --- | --------------------------------------------------- | ------------------------------------------------------------------- | -------------------------------------------------------------------- |
| (a) | exclusions conjunctive when text means disjunctive  | **No** at check time; **yes** at run time _if_ scenario tests exist | `l4 check` succeeds; a `#ASSERT` reports `assertion failed`          |
| (b) | date passed where age expected                      | **Yes, at check time** — but only if the two have distinct types    | `DATE` vs `NUMBER` type error; **not** caught when both are `NUMBER` |
| (c) | reference to a rule that does not exist             | **Yes, at check time**                                              | "I could not find a definition for the identifier"                   |
| (d) | syntax error making the file unrunnable             | **Yes, at parse time**                                              | parser error with caret, line and expected-token set; exit 1         |
| (e) | _bonus:_ a missing branch over an enumerated ground | **Warning at check time**, error at run time                        | "The following branches still need to be considered"                 |

### (a) AND for OR — NOT caught by the type system. Demonstrated.

`runs/probe/p4a-and-for-or.l4` writes clause 2.1 twice, once with `OR` and once with `AND`:

```l4
`clause 2.1 -- correct, disjunctive` MEANS
      c's skydiving OR c's military OR c's firefight OR c's police
   OR (c's age) AT LEAST 80

`clause 2.1 -- BUG, conjunctive` MEANS
      c's skydiving AND c's military AND c's firefight AND c's police
  AND (c's age) AT LEAST 80

#ASSERT `clause 2.1 -- BUG, conjunctive` `plain skydiving claim`
```

```
$ l4 check p4a-and-for-or.l4
Check succeeded.                     (exit 0)

$ l4 run p4a-and-for-or.l4
Evaluation[1]  TRUE                  -- correct, disjunctive
Evaluation[2]  FALSE                 -- BUG, conjunctive: skydiving claim not excluded
Evaluation[3]  assertion failed
```

Both are `BOOLEAN`-typed and both typecheck. **Nothing but a scenario test catches this** — which is
the argument for the negotiation-time test suite, not an argument about types.

> **Caveat worth flagging, measured.** A failed `#ASSERT` does **not** set a non-zero exit code, and
> the JSON envelope's top-level `ok` stays `true`:
>
> ```
> $ echo '#ASSERT FALSE' > p7.l4 ; l4 run p7.l4 >/dev/null 2>&1 ; echo $?
> 0
> $ l4 run --json p7.l4
> {"ok": true, "results": [{"kind":"assertion","range":"p7.l4:1:1-14","value":false}]}
> ```
>
> The failure _is_ machine-readable (`results[].value == false`, and a `DiagnosticSeverity_Error`
> line in the diagnostics), but a CI step that only checks the exit status of `l4 run` will not see
> it. By contrast a check or parse error under `l4 run` **does** exit 1 (verified on 4b, 4c, 4d).

### (b) Date where an age was expected — CAUGHT at check time.

`runs/probe/p4b-date-for-age.l4`:

```l4
GIVEN `age at hospitalisation` IS A NUMBER
GIVETH A BOOLEAN
`item 5 bites` MEANS `age at hospitalisation` AT LEAST 80

`the hospitalisation date` MEANS YMD 2025 6 1

#EVAL `item 5 bites` `the hospitalisation date`
```

```
$ l4 check p4b-date-for-age.l4
  Severity: DiagnosticSeverity_Error
  Message:
    The first argument of function
      `item 5 bites` (defined at p4b-date-for-age.l4:8:1-15)
    is expected to be of type
      NUMBER
    but is here of type
      DATE
                                      (exit 1)
```

### (b)(ii) …but only if they have different types — and the paper's convention makes them the same

This is the sharpest finding of the probe. Under the relative-months convention the paper's prompt
mandates, "months since the effective date" and "age in years" are **both plain `NUMBER`s**, and the
error walks straight back in. `runs/probe/p4b2a-unwrapped.l4`:

```l4
GIVEN `age in years` IS A NUMBER
GIVETH A BOOLEAN
`item 5 bites, unwrapped` MEANS `age in years` AT LEAST 80

`months since effective date, at hospitalisation` MEANS 84   -- month 84 = year 7

#EVAL `item 5 bites, unwrapped` `months since effective date, at hospitalisation`
```

```
$ l4 run p4b2a-unwrapped.l4
Evaluation[1]  TRUE                  (exit 0, no diagnostics)
```

84 months is not 84 years old. The policy excludes the claim; there is no complaint. **The repair is
nominal wrapper types**, and it works — `runs/probe/p4b2-units.l4`:

```l4
DECLARE `Years of age`   HAS years  IS A NUMBER
DECLARE `Months elapsed` HAS months IS A NUMBER

GIVEN a IS A `Years of age`
GIVETH A BOOLEAN
`item 5 bites, wrapped` MEANS (a's years) AT LEAST 80

#EVAL `item 5 bites, wrapped` (`Months elapsed` WITH months IS 84)
```

```
$ l4 check p4b2-units.l4
    The first argument of function
      `item 5 bites, wrapped` (defined at p4b2-units.l4:25:1-24)
    is expected to be of type
      `Years of age`
    but is here of type
      `Months elapsed`
                                      (exit 1)
```

So: L4 catches failure class (b) **by construction if you use real `DATE`s** (§1), and **only if you
opt into wrapper types** if you follow the paper's relative-number convention. The convention that
was adopted to make Prolog tractable is the one that disarms the type checker.

### (c) Reference to a rule that does not exist — CAUGHT at check time.

`runs/probe/p4c-missing-rule.l4`:

```l4
`clause 2.1 excludes` MEANS
      `item 5 bites` age
   OR `skydiving exclusion applies` age    -- never defined anywhere
```

```
$ l4 check p4c-missing-rule.l4
  Severity: DiagnosticSeverity_Error
  Message:
    I could not find a definition for the identifier
      `skydiving exclusion applies`
    which I have inferred to be of type:
      FUNCTION FROM NUMBER TO BOOLEAN
                                      (exit 1)
```

Note it _reports the inferred type of the thing you forgot to write_, which is a usable stub
specification. This is structurally different from Prolog's `procedure does not exist`, which fires
only when the goal is reached.

### (d) Syntax error — CAUGHT at parse time.

`runs/probe/p4d-syntax-error.l4` (`AT LEAST` with no right operand):

```
$ l4 check p4d-syntax-error.l4
  Source:   parser
      |
    7 | `item 5 bites` MEANS age AT LEAST
      |                          ^^
    unexpected AT
    expecting %, (, ;, Float Literal, Numeric Literal, OF, String Literal, WHERE,
    end of input, identifier, infix identifier, mixfix keyword, space token, or •
                                      (exit 1)
```

Two real ones I hit while writing these probes, both caught the same way with a caret and a location:
`` `add months` f's `effective date` 6 `` (field access needs parens before another argument), and a
misaligned second `GIVEN` parameter (`by` at column 6 under `d` at column 7).

### (e) Bonus: a forgotten exclusion, when the grounds are a type — WARNING at check time.

`runs/probe/p4e-nonexhaustive.l4` declares the five grounds as an enum and handles only four:

```
$ l4 check p4e-nonexhaustive.l4
  Severity: DiagnosticSeverity_Warning
  Message:
    The following branches still need to be considered:
      WHEN <…>.`Age 80 or over` THEN
Check succeeded.                      (exit 0)

$ l4 run p4e-nonexhaustive.l4
Result:
  The value `Age 80 or over` reached a CONSIDER that has no branch for it.
  Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
  The typechecker's exhaustiveness warning lists all missing branches.
                                      (exit 0)
```

It is a **warning, not an error**, and neither `check` nor `run` exits non-zero. (The suppression
annotation is `@nonexhaustive` — `jl4-core/src/L4/TypeCheck.hs:659`, `jl4-core/src/L4/Export.hs:73`.)
So the coverage guarantee for "did you handle every exclusion ground?" is real but advisory; getting
it enforced means treating warnings as errors in whatever runs the check.

---

## 5. Two further fidelity findings the probe turned up

### 5a. The regulative layer gives pending/fulfilled/breached natively — but its deadlines are _relative_, and clause 1.3's are _absolute_

Clause 1.3 is obligation-shaped, so the obvious move is `PARTY … MUST … WITHIN …`.
`runs/probe/p5-regulative.l4` does that, converting the month deadlines to the numeric tick axis:

```l4
`days to month 6` MEANS Day (`add months` `effective date` 6) MINUS Day `effective date`  -- 181
`days to month 7` MEANS Day (`add months` `effective date` 7) MINUS Day `effective date`  -- 212

`clause 1.3` MEANS
  PARTY `The Insured`
  MUST `attend wellness visit`
  WITHIN `days to month 6`
  HENCE ( PARTY `The Insured`
          MUST `supply written confirmation`
          WITHIN `days to month 7`
          HENCE FULFILLED
          LEST BREACH )
  LEST BREACH
```

The three states come out for free:

```
#TRACE with no acts at all        -> the un-reduced contract term  (= still PENDING)
#TRACE visit@120, confirm@150     -> FULFILLED
#TRACE visit@120, confirm@400     -> DEONTIC BREACHED: BREACH
```

**But the inner `WITHIN` is measured from the parent's discharge, not from tick 0.** Measured:

```
#TRACE visit@120, confirm@300  -> FULFILLED     -- 300 > 212 absolute, but 300-120 = 180 < 212
#TRACE visit@120, confirm@331  -> FULFILLED     -- 331-120 = 211, just inside
#TRACE visit@120, confirm@400  -> BREACHED      -- 400-120 = 280, outside
```

So the naive nesting silently converts clause 1.3's _absolute_ 7-month deadline into a 7-month
window running from the wellness visit. That is a different contract. This is documented, not a bug:

- `doc/concepts/legal-modeling/regulative-rules.md:185` — "There is no special syntax for anchoring a
  deadline to a named event — the timeline is purely numeric, and every `WITHIN` window starts when
  its obligation becomes active."
- `doc/concepts/legal-modeling/regulative-rules.md:211` and `doc/reference/regulative/README.md:405-410`
  — "`BEFORE` (absolute deadlines, like 'by 1 January 2026') is planned but not yet implemented."

**Consequence for a faithful encoding: use the constitutive form of §2 for clause 1.3**, where both
deadlines are absolute dates derived from the effective date, and reserve the regulative form for
clause 3.2.1's arbitration timers, whose windows genuinely _are_ relative to an event ("within three
months from the day such parties are unable to settle").

### 5b. Clause 1.2's "midnight, US Eastern time then in effect" is directly expressible, DST-aware

"Then in effect" is the DST-aware reading, and `jl4-core/libraries/timezone.l4:6,10-11` maps both
`EST` and `EDT` to `America/New_York` precisely so the tz database picks the offset for the actual
date. `runs/probe/p6-cancellation-instant.l4`:

```
Evaluation[1]  DATE OF 31, 1, 2026            -- last day of the one-year term
Evaluation[2]  2026-02-01T00:00:00-0500       -- cancellation instant, winter offset
Evaluation[3]  2025-07-01T00:00:00-0400       -- a summer instant, offset moves
```

This clause is **unencodable at all** under the relative-months convention, since it needs a real
calendar date and a real zone.

---

## 6. New syntax trap found (not in `l4-syntax-traps` memory)

**An `IMPORT` placed after a `§` section heading is silently ineffective.** No diagnostic mentions
the import; you get a cascade of "could not find a definition" errors for every library name, which
reads like a library-path problem and is not.

```
$ printf '§ `hdr`\n\nIMPORT daydate\n\n#EVAL `Days in a week`\n' > p0b.l4 ; l4 run p0b.l4
    I could not find a definition for the identifier
      `Days in a week`

$ printf 'IMPORT daydate\n\n#EVAL `Days in a week`\n' > p0.l4 ; l4 run p0.l4
Result:
  7
```

The names do not become section-qualified either — `hdr.`Days in a week``also fails. **Put every`IMPORT`before the first`§`.** (Also worth knowing: `daydate`does *not* re-export`prelude`, so
`elem`/`any`/`map`/`filter`need their own`IMPORT prelude`.)

---

## 7. Verdict

| Policy feature                            | L4 fidelity                                                                                                         |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| 1.3 month anniversaries                   | **Native.** `add months`, clamping, cross-validated against Excel/Drools/Camunda                                    |
| 1.1(3) three-state condition              | **Native**, two ways; the enum form also exposes the 1.1(3)/1.2 contradiction                                       |
| 1.1 conjunction of four limbs             | Trivial                                                                                                             |
| 1.2 cancellation grounds                  | Expressible; the "not satisfied in a timely fashion" limb is genuinely ambiguous and L4 makes you say which reading |
| 1.2 midnight US Eastern, DST-aware        | **Native** (`timezone.l4`, `datetime.l4`)                                                                           |
| 2.1 causal chapeau + heterogeneous item 5 | Expressible with both readings side by side; **L4 will not choose for you, which is the correct behaviour**         |
| 2.1 disjunctive structure                 | Expressible; **not enforced** — `AND` for `OR` typechecks                                                           |
| 3.2.1 arbitration windows                 | Regulative `WITHIN` fits (event-relative windows)                                                                   |
| 3.6 one-year term                         | **Native** (`add years`)                                                                                            |
| Absolute deontic deadlines (`BEFORE`)     | **Not implemented** — documented gap; use the constitutive form                                                     |

The four Prolog failure classes: **(c) and (d) are caught by the compiler unconditionally; (b) is
caught by the compiler when the quantities are honestly typed and missed entirely when they are both
`NUMBER`; (a) is caught only by scenario tests.** Which is to say the type system buys you three of
four, and the fourth is exactly the one the paper's own testing thesis is about.
