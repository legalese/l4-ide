# Fact schema — L4 transliteration

**Mechanically derived from `schema.md`. Do not edit independently.**

**This block is compiled by `bench/check-schema-parity.mjs`, and that is not decoration.** The
first version shipped to the `l4-guided` trials did NOT compile — multi-word field names need
backticks, and the `arose out of` helper was written ``c `elem` cs`` when L4 has no
backtick-infix calling convention (it parses as applying `c` to two arguments, and `elem` was
never mixfix-registered in the prelude). The Prolog schema loaded cleanly, so the two guided
cells were **not equivalently guided** and R4 was violated in the one place the field-name parity
check could not see. Both defects are fixed; the check now compiles what it compares.
Rule: neutral field `x` becomes a record field of the same words; enums become `DECLARE`d
sum types; `number | none` becomes `MAYBE NUMBER` (`NOTHING` for `none`, `JUST n` otherwise).

```l4
DECLARE Ground IS ONE OF Sickness, `Accidental injury`, Neither

DECLARE Cause IS ONE OF
  Skydiving, `Military service`, Firefighting, `Police service`, Other

DECLARE Claim
  HAS `agreement signed`                           IS A BOOLEAN
      `premium paid month`                         IS A MAYBE NUMBER
      `hospitalization month`                      IS A NUMBER
      `hospitalization ground`                     IS A Ground
      `age at hospitalization`                     IS A NUMBER
      `causes`                                     IS A LIST OF Cause
      `fraud month`                                IS A MAYBE NUMBER
      `misrepresentation month`                    IS A MAYBE NUMBER
      `wellness visit month`                       IS A MAYBE NUMBER
      `wellness visit provider qualified`          IS A BOOLEAN
      `written confirmation month`                 IS A MAYBE NUMBER
      `dispute arisen`                             IS A BOOLEAN
      `unable to settle month`                     IS A MAYBE NUMBER
      `arbitration commenced month`                IS A MAYBE NUMBER
      `valid arbitration award issued`             IS A BOOLEAN
      `written proof of claim month`               IS A MAYBE NUMBER
      `recovery sought month`                      IS A MAYBE NUMBER
      `policy term months`                         IS A NUMBER
```

## Supporting helpers (pre-defined — call them, do not redefine them)

```l4
GIVEN  `event month` IS A MAYBE NUMBER
       `limit month` IS A NUMBER
GIVETH A BOOLEAN
`no later than` MEANS
  CONSIDER `event month`
    WHEN NOTHING THEN FALSE
    WHEN JUST m  THEN m AT MOST `limit month`

GIVEN  cs IS A LIST OF Cause
       c  IS A Cause
GIVETH A BOOLEAN
`arose out of` MEANS elem c cs
```

Write `covered`, a function from a `Claim` to a `BOOLEAN`, true exactly when a benefit is
payable on that claim.
