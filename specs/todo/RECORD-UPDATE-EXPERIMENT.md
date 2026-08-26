# Record-Update Readability Experiment — §8.1 / §9 step 0 of `RECORD-UPDATE-SPEC.md`

> **Status (2026-08-24): PREPARED, NOT RUN.** Version A below is extracted verbatim from
> `jl4/examples/legal/bna/bna.l4` on this branch @ `d55fb196`. Version B is **to be written by
> hand** and the verdict section is empty. This file is the materials and protocol for the
> experiment the spec's §8.1 names as R1's cheapest falsification, which §9 orders **before**
> implementation.

## 1. Roles

- **Version A** — the shipped constructor-factory idiom, machine-encoded (the BNA corpus was not
  hand-authored). Extracted verbatim in §5; do not edit it.
- **Version B** — the same fixtures and scenario groups, re-expressed against canonical bases in
  the **proposed** `BUT WITH` syntax (spec R2). To be **hand-written by Meng**. It will not compile
  until the feature lands — it is a paper artifact for the judgment. Afterwards it is intended for
  the human-written L4 style corpus, and once the feature ships it becomes the seed for rewriting
  `bna.l4`'s fixtures.
- **Judge** — a knowledge engineer who wrote _neither_ version (with A machine-written and B by
  Meng, Aswathy is the natural fit). The judge answers §4 in writing, and should not be told which
  version is the proposal.

## 2. Task for the author of Version B

1. Define **one canonical base** — e.g. `` `a UK-born child` ``: the all-FALSE / zero-valued
   19-field `PersonProfile` literal, spelled once in full. (`Peter` stays as he is — a historic
   lineage fixture — and his variant below is your first rewrite.)
2. Re-express in `BUT WITH` form: (a) `` `Peter with the subsection (3) limbs satisfied` ``;
   (b) the six named lead cases; (c) every inline factory call in Groups 1–6. Group 7
   (`AdoptionCase`) is out of scope.
3. Syntax per the spec: `<name> BUT WITH field IS value, …` — layout or commas; computed fields may
   not be supplied; **no chaining in one expression** (v1) — chain by naming intermediate fixtures
   instead (`` `the rebutted foundling` MEANS `the foundling` BUT WITH … ``); a parenthesised head
   is legal.
4. Your judgment calls are part of the experiment: which fields each scenario updates (including
   whether to touch `name`, and what to do with the inert `date found abandoned`), whether one base
   suffices or several read better, and whether some sites are honestly better left as factories.
   **A mixed verdict is a legitimate outcome** — "updates for scenario variation, factories where a
   parameter must be mandatory" would be a finding, not a failure.

## 3. Traps in the source — read before rewriting

- **The dob coupling.** Every birth factory sets _two_ fields from one parameter: `date of birth`
  IS dob _and_ `date found abandoned` IS dob. The second is inert whenever the two
  found-abandoned booleans are FALSE. Decide deliberately whether B updates it, and say why in a
  comment — the decision is itself data.
- **The foundling's opposed booleans.** `a foundling found on` drives
  `found abandoned … in the United Kingdom` and `… in a qualifying territory` in opposition from
  one parameter (`IS NOT`). B must write both fields explicitly.
- **Mandatory vs optional.** A's `GIVEN` parameters are _demanded_ by the type checker at every
  call; B's deltas are _optional_, so forgetting one silently inherits the base. Notice whether
  that possibility worries you while writing, and write it down if it does — it bears directly on
  §8.1.

## 4. Judge protocol — answer in writing, in order

1. **Comprehension probe, A.** Without scrolling to the factory definition: what facts does
   ``(`a child born in the United Kingdom on` (YMD 1983 1 1) FALSE TRUE FALSE)`` assert?
2. **Comprehension probe, B.** The same exercise for a Version B site of the author's choosing.
3. **Delta visibility.** In which version is it easier to see what each scenario varies from its
   lead case?
4. **The maintenance question — the one §8.1 turns on.** Which version would you rather maintain
   across five years of amendments to the Act? And did any B site leave you unsure what an
   unwritten field held?

**Kill criterion (spec §8.1):** if the judge would keep the factories, R1 flips to "don't ship".
Record the verdict in §7 with a date, whichever way it goes.

## 5. Version A — verbatim from `bna.l4` @ `d55fb196` (do not edit)

The `PersonProfile` declaration is at `bna.l4:102-148`; `Peter` (the full-literal lineage fixture,
retained in both versions) at `:607-627`.

```l4
-- Peter again, with both subsection (3) limbs deliberately satisfied — the
-- parent later becomes settled AND an application is made while he is a
-- minor — so that the Group 4 negative on this fixture is carried by the
-- "not already a British citizen" chapeau ALONE.
`Peter with the subsection (3) limbs satisfied` MEANS PersonProfile WITH
    name                                              IS "Peter"
    `born in the United Kingdom`                      IS TRUE
    `born in a qualifying territory`                  IS FALSE
    `date of birth`                                   IS YMD 1983 5 3
    `father or mother a British citizen at the time of the birth`                                          IS TRUE
    `father or mother settled in the United Kingdom or the territory of birth at the time of the birth`    IS FALSE
    `father or mother a member of the armed forces at the time of the birth`                               IS FALSE
    `found abandoned as a new-born infant in the United Kingdom`                                           IS FALSE
    `found abandoned as a new-born infant in a qualifying territory`                                       IS FALSE
    `date found abandoned`                            IS YMD 1983 5 3
    `the contrary shown, rebutting the subsection (2) presumption`                                         IS FALSE
    `a British citizen under section 10A`             IS FALSE
    `while a minor, father or mother became a British citizen or became settled in the United Kingdom`     IS TRUE
    `while a minor, father or mother became a member of the armed forces`                                  IS FALSE
    `while a minor, an application made for registration as a British citizen`                             IS TRUE
    `an application for registration made after attaining the age of ten years`                            IS FALSE
    `greatest number of days absent from the United Kingdom in any one of the first ten years of life`     IS 0
    `the Secretary of State treats the subsection (4) residence requirement as fulfilled`                  IS FALSE
    `of good character, where the good character requirement applies`                                      IS TRUE


-- Boundary-sweep constructor for birth cases: a child born in the United
-- Kingdom, varying the birth date and the three parent statuses.
GIVEN dob              IS A DATE
      `citizen parent` IS A BOOLEAN
      `settled parent` IS A BOOLEAN
      `forces parent`  IS A BOOLEAN
GIVETH A PersonProfile
`a child born in the United Kingdom on` dob `citizen parent` `settled parent` `forces parent` MEANS PersonProfile WITH
    name                                              IS "a UK-born child"
    `born in the United Kingdom`                      IS TRUE
    `born in a qualifying territory`                  IS FALSE
    `date of birth`                                   IS dob
    `father or mother a British citizen at the time of the birth`                                          IS `citizen parent`
    `father or mother settled in the United Kingdom or the territory of birth at the time of the birth`    IS `settled parent`
    `father or mother a member of the armed forces at the time of the birth`                               IS `forces parent`
    `found abandoned as a new-born infant in the United Kingdom`                                           IS FALSE
    `found abandoned as a new-born infant in a qualifying territory`                                       IS FALSE
    `date found abandoned`                            IS dob
    `the contrary shown, rebutting the subsection (2) presumption`                                         IS FALSE
    `a British citizen under section 10A`             IS FALSE
    `while a minor, father or mother became a British citizen or became settled in the United Kingdom`     IS FALSE
    `while a minor, father or mother became a member of the armed forces`                                  IS FALSE
    `while a minor, an application made for registration as a British citizen`                             IS FALSE
    `an application for registration made after attaining the age of ten years`                            IS FALSE
    `greatest number of days absent from the United Kingdom in any one of the first ten years of life`     IS 0
    `the Secretary of State treats the subsection (4) residence requirement as fulfilled`                  IS FALSE
    `of good character, where the good character requirement applies`                                      IS TRUE

-- The same, born in a qualifying territory (e.g. Bermuda, Gibraltar).
GIVEN dob              IS A DATE
      `citizen parent` IS A BOOLEAN
      `settled parent` IS A BOOLEAN
      `forces parent`  IS A BOOLEAN
GIVETH A PersonProfile
`a child born in a qualifying territory on` dob `citizen parent` `settled parent` `forces parent` MEANS PersonProfile WITH
    name                                              IS "a territory-born child"
    `born in the United Kingdom`                      IS FALSE
    `born in a qualifying territory`                  IS TRUE
    `date of birth`                                   IS dob
    `father or mother a British citizen at the time of the birth`                                          IS `citizen parent`
    `father or mother settled in the United Kingdom or the territory of birth at the time of the birth`    IS `settled parent`
    `father or mother a member of the armed forces at the time of the birth`                               IS `forces parent`
    `found abandoned as a new-born infant in the United Kingdom`                                           IS FALSE
    `found abandoned as a new-born infant in a qualifying territory`                                       IS FALSE
    `date found abandoned`                            IS dob
    `the contrary shown, rebutting the subsection (2) presumption`                                         IS FALSE
    `a British citizen under section 10A`             IS FALSE
    `while a minor, father or mother became a British citizen or became settled in the United Kingdom`     IS FALSE
    `while a minor, father or mother became a member of the armed forces`                                  IS FALSE
    `while a minor, an application made for registration as a British citizen`                             IS FALSE
    `an application for registration made after attaining the age of ten years`                            IS FALSE
    `greatest number of days absent from the United Kingdom in any one of the first ten years of life`     IS 0
    `the Secretary of State treats the subsection (4) residence requirement as fulfilled`                  IS FALSE
    `of good character, where the good character requirement applies`                                      IS TRUE

-- A foundling: place and date of birth, and parentage, are unknown — the
-- subsection (2) deeming supplies them. `date of birth` is set to the
-- found date only because the record requires a value; no subsection (2)
-- path reads it. `in the United Kingdom` FALSE means found in a
-- qualifying territory instead.
GIVEN `found date`            IS A DATE
      `in the United Kingdom` IS A BOOLEAN
      `contrary shown`        IS A BOOLEAN
GIVETH A PersonProfile
`a foundling found on` `found date` `in the United Kingdom` `contrary shown` MEANS PersonProfile WITH
    name                                              IS "a foundling"
    `born in the United Kingdom`                      IS FALSE
    `born in a qualifying territory`                  IS FALSE
    `date of birth`                                   IS `found date`
    `father or mother a British citizen at the time of the birth`                                          IS FALSE
    `father or mother settled in the United Kingdom or the territory of birth at the time of the birth`    IS FALSE
    `father or mother a member of the armed forces at the time of the birth`                               IS FALSE
    `found abandoned as a new-born infant in the United Kingdom`                                           IS `in the United Kingdom`
    `found abandoned as a new-born infant in a qualifying territory`                                       IS NOT `in the United Kingdom`
    `date found abandoned`                            IS `found date`
    `the contrary shown, rebutting the subsection (2) presumption`                                         IS `contrary shown`
    `a British citizen under section 10A`             IS FALSE
    `while a minor, father or mother became a British citizen or became settled in the United Kingdom`     IS FALSE
    `while a minor, father or mother became a member of the armed forces`                                  IS FALSE
    `while a minor, an application made for registration as a British citizen`                             IS FALSE
    `an application for registration made after attaining the age of ten years`                            IS FALSE
    `greatest number of days absent from the United Kingdom in any one of the first ten years of life`     IS 0
    `the Secretary of State treats the subsection (4) residence requirement as fulfilled`                  IS FALSE
    `of good character, where the good character requirement applies`                                      IS TRUE

-- A child born in the United Kingdom to parents with no qualifying status
-- at the birth (visitors, students, unsettled migrants), varying the
-- later-life events that drive subsections (3) and (3A).
GIVEN dob                                    IS A DATE
      `parent later a citizen or settled`    IS A BOOLEAN
      `parent later in the forces`           IS A BOOLEAN
      `application while a minor`            IS A BOOLEAN
GIVETH A PersonProfile
`a child of visitors born on` dob `parent later a citizen or settled` `parent later in the forces` `application while a minor` MEANS PersonProfile WITH
    name                                              IS "a child of visitors"
    `born in the United Kingdom`                      IS TRUE
    `born in a qualifying territory`                  IS FALSE
    `date of birth`                                   IS dob
    `father or mother a British citizen at the time of the birth`                                          IS FALSE
    `father or mother settled in the United Kingdom or the territory of birth at the time of the birth`    IS FALSE
    `father or mother a member of the armed forces at the time of the birth`                               IS FALSE
    `found abandoned as a new-born infant in the United Kingdom`                                           IS FALSE
    `found abandoned as a new-born infant in a qualifying territory`                                       IS FALSE
    `date found abandoned`                            IS dob
    `the contrary shown, rebutting the subsection (2) presumption`                                         IS FALSE
    `a British citizen under section 10A`             IS FALSE
    `while a minor, father or mother became a British citizen or became settled in the United Kingdom`     IS `parent later a citizen or settled`
    `while a minor, father or mother became a member of the armed forces`                                  IS `parent later in the forces`
    `while a minor, an application made for registration as a British citizen`                             IS `application while a minor`
    `an application for registration made after attaining the age of ten years`                            IS FALSE
    `greatest number of days absent from the United Kingdom in any one of the first ten years of life`     IS 0
    `the Secretary of State treats the subsection (4) residence requirement as fulfilled`                  IS FALSE
    `of good character, where the good character requirement applies`                                      IS TRUE

-- The subsection (4) family: UK-born to non-qualifying parents, varying
-- the residence record, the over-ten application, the subsection (7)
-- dispensation, and good character.
GIVEN dob                     IS A DATE
      `days absent`           IS A NUMBER
      `application after ten` IS A BOOLEAN
      `waiver`                IS A BOOLEAN
      `good character`        IS A BOOLEAN
GIVETH A PersonProfile
`a ten-year applicant born on` dob `days absent` `application after ten` `waiver` `good character` MEANS PersonProfile WITH
    name                                              IS "a ten-year applicant"
    `born in the United Kingdom`                      IS TRUE
    `born in a qualifying territory`                  IS FALSE
    `date of birth`                                   IS dob
    `father or mother a British citizen at the time of the birth`                                          IS FALSE
    `father or mother settled in the United Kingdom or the territory of birth at the time of the birth`    IS FALSE
    `father or mother a member of the armed forces at the time of the birth`                               IS FALSE
    `found abandoned as a new-born infant in the United Kingdom`                                           IS FALSE
    `found abandoned as a new-born infant in a qualifying territory`                                       IS FALSE
    `date found abandoned`                            IS dob
    `the contrary shown, rebutting the subsection (2) presumption`                                         IS FALSE
    `a British citizen under section 10A`             IS FALSE
    `while a minor, father or mother became a British citizen or became settled in the United Kingdom`     IS FALSE
    `while a minor, father or mother became a member of the armed forces`                                  IS FALSE
    `while a minor, an application made for registration as a British citizen`                             IS FALSE
    `an application for registration made after attaining the age of ten years`                            IS `application after ten`
    `greatest number of days absent from the United Kingdom in any one of the first ten years of life`     IS `days absent`
    `the Secretary of State treats the subsection (4) residence requirement as fulfilled`                  IS `waiver`
    `of good character, where the good character requirement applies`                                      IS `good character`


-- Named lead cases.
`the foundling`           MEANS `a foundling found on` (YMD 2020 6 1) TRUE FALSE
`the rebutted foundling`  MEANS `a foundling found on` (YMD 2020 6 1) TRUE TRUE
`the forces child`        MEANS `a child born in the United Kingdom on` (YMD 2015 6 1) FALSE FALSE TRUE
`the child of visitors`   MEANS `a child of visitors born on` (YMD 2012 5 10) TRUE FALSE TRUE
`the ten-year lead case`  MEANS `a ten-year applicant born on` (YMD 1995 3 1) 90 TRUE FALSE TRUE
`the applicant of bad character` MEANS `a ten-year applicant born on` (YMD 1995 3 1) 90 TRUE FALSE FALSE

§§ `Group 1 — subsection (1), boundaries at commencement and the appointed day`

-- Sergot et al.'s Peter, on the current text: born in the UK in 1983 to a
-- British-citizen parent.
#ASSERT     `a British citizen by virtue of subsection (1) or (2)` `Peter`
-- Born on commencement day itself, to a settled (not citizen) parent:
-- limb (b), and the "after commencement" boundary.
#ASSERT     `a British citizen by virtue of subsection (1) or (2)` (`a child born in the United Kingdom on` (YMD 1983 1 1) FALSE TRUE FALSE)
-- One day earlier: the 1981 Act confers nothing (the 1948 Act governed).
#ASSERT NOT `a British citizen by virtue of subsection (1) or (2)` (`a child born in the United Kingdom on` (YMD 1982 12 31) TRUE FALSE FALSE)
-- Born in the UK to parents with no qualifying status: not a citizen at birth.
#ASSERT NOT `a British citizen by virtue of subsection (1) or (2)` `the child of visitors`
-- Born in a qualifying territory ON the appointed day, settled parent: in.
#ASSERT     `a British citizen by virtue of subsection (1) or (2)` (`a child born in a qualifying territory on` (YMD 2002 5 21) FALSE TRUE FALSE)
-- One day before the appointed day: out.
#ASSERT NOT `a British citizen by virtue of subsection (1) or (2)` (`a child born in a qualifying territory on` (YMD 2002 5 20) FALSE TRUE FALSE)

§§ `Group 2 — subsection (1A), boundary at the relevant day (13 January 2010)`

-- Born in the UK ON the relevant day to an armed-forces parent: in.
#ASSERT     `a British citizen by virtue of subsection (1A)` (`a child born in the United Kingdom on` (YMD 2010 1 13) FALSE FALSE TRUE)
-- One day earlier: out.
#ASSERT NOT `a British citizen by virtue of subsection (1A)` (`a child born in the United Kingdom on` (YMD 2010 1 12) FALSE FALSE TRUE)
-- The route also runs in a qualifying territory.
#ASSERT     `a British citizen by virtue of subsection (1A)` (`a child born in a qualifying territory on` (YMD 2012 3 1) FALSE FALSE TRUE)
#ASSERT     `a British citizen by virtue of subsection (1A)` `the forces child`
-- No armed-forces parent: the limb fails.
#ASSERT NOT `a British citizen by virtue of subsection (1A)` (`a child born in the United Kingdom on` (YMD 2015 6 1) FALSE FALSE FALSE)

§§ `Group 3 — subsection (2), the foundling presumption`

#ASSERT     `deemed by subsection (2) to satisfy subsection (1)` `the foundling`
-- The deeming feeds subsection (1): the foundling is a citizen at birth.
#ASSERT     `a British citizen by virtue of subsection (1) or (2)` `the foundling`
-- The presumption is rebuttable: the contrary shown, the deeming fails.
#ASSERT NOT `a British citizen by virtue of subsection (1) or (2)` `the rebutted foundling`
-- Found before commencement: the deeming does not run.
#ASSERT NOT `deemed by subsection (2) to satisfy subsection (1)` (`a foundling found on` (YMD 1982 6 1) TRUE FALSE)

§§ `Group 4 — subsection (3), registration after a parent qualifies`

#ASSERT     `entitled to be registered under subsection (3)` `the child of visitors`
-- No application made while a minor: limb (b) fails.
#ASSERT NOT `entitled to be registered under subsection (3)` (`a child of visitors born on` (YMD 2012 5 10) TRUE FALSE FALSE)
-- The parent never becomes a citizen or settled: limb (a) fails.
#ASSERT NOT `entitled to be registered under subsection (3)` (`a child of visitors born on` (YMD 2012 5 10) FALSE FALSE TRUE)
-- Peter is already a British citizen by virtue of subsection (1). On plain
-- Peter this negative is overdetermined — limbs (a) and (b) fail on his
-- facts too — so by itself it does not demonstrate the chapeau.
#ASSERT NOT `entitled to be registered under subsection (3)` `Peter`
-- The chapeau in isolation: both while-a-minor limbs satisfied, and the
-- entitlement still fails, solely because Peter is already a British
-- citizen by virtue of subsection (1).
#ASSERT NOT `entitled to be registered under subsection (3)` `Peter with the subsection (3) limbs satisfied`

§§ `Group 5 — subsection (3A), registration after a parent joins the forces`

#ASSERT     `entitled to be registered under subsection (3A)` (`a child of visitors born on` (YMD 2012 5 10) FALSE TRUE TRUE)
-- Born before the relevant day: the (3A) chapeau fails (though (3) may
-- still serve such a person on its own facts).
#ASSERT NOT `entitled to be registered under subsection (3A)` (`a child of visitors born on` (YMD 2005 5 10) FALSE TRUE TRUE)
-- No application made while a minor: limb (b) fails.
#ASSERT NOT `entitled to be registered under subsection (3A)` (`a child of visitors born on` (YMD 2012 5 10) FALSE TRUE FALSE)

§§ `Group 6 — subsection (4) with (7), boundary at 90 days; and the C3 grant gate`

-- Exactly 90 days absent in the worst year: within the ceiling.
#ASSERT     `entitled to be registered under subsection (4)` `the ten-year lead case`
-- One day more: outside.
#ASSERT NOT `entitled to be registered under subsection (4)` (`a ten-year applicant born on` (YMD 1995 3 1) 91 TRUE FALSE TRUE)
-- The same excess, but the Secretary of State exercises the subsection (7)
-- dispensation: entitled.
#ASSERT     `entitled to be registered under subsection (4)` (`a ten-year applicant born on` (YMD 1995 3 1) 91 TRUE TRUE TRUE)
-- No application made after attaining ten: the application limb fails.
#ASSERT NOT `entitled to be registered under subsection (4)` (`a ten-year applicant born on` (YMD 1995 3 1) 90 FALSE FALSE TRUE)
-- The s 41A good-character gate (modification C3) sits on the GRANT, not
-- the entitlement: the applicant of bad character remains entitled under
-- s 1(4), but registration may not be granted.
#ASSERT     `entitled to be registered under subsection (4)` `the applicant of bad character`
#ASSERT     `registration may be granted` `the ten-year lead case` (`entitled to be registered under subsection (4)` `the ten-year lead case`)
#ASSERT NOT `registration may be granted` `the applicant of bad character` (`entitled to be registered under subsection (4)` `the applicant of bad character`)
```

## 6. Version B — hand-written, in the proposed syntax

_To be written. Do not machine-generate: half the point is banking human-written L4 for the style
corpus, and the other half is that the act of writing it is part of the measurement (§3, third
trap)._

## 7. Verdict

_Pending. Record: the judge's four answers, the date, and the §8.1 disposition (R1 stands / R1
flips)._
