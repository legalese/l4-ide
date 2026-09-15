# Fact schema, RESTORED-fixture variant — L4 transliteration

**Mechanically derived from `schema-restored.md`. Do not edit independently.**
This block is compiled by `bench/check-schema-parity.mjs`; see `schema-l4.md` for the incident
that made compilation part of the check.
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
      `confined in us hospital`                    IS A BOOLEAN
      `continuous confinement days`                IS A MAYBE NUMBER
      `claim made setting out basis`               IS A BOOLEAN
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
