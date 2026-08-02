# Charities (Jersey) Law 2014 — the charity test, encoded de novo

A cleanroom smoke test: the charity-test cluster of the **Charities (Jersey) Law 2014** (L.41/2014),
encoded from the primary source in inert house style, with every interpretive choice registered.

| file                                     | what it is                                                                        |
| ---------------------------------------- | --------------------------------------------------------------------------------- |
| [`SOURCE-EXTRACT.md`](SOURCE-EXTRACT.md) | verbatim source text with fetch provenance and quote-hygiene statement            |
| [`charity-test.l4`](charity-test.l4)     | the encoding — 1 472 lines, 45 `@ref` citations, 102 `#ASSERT`s                   |
| `README.md`                              | this file: article map, ambiguity register, run evidence, integrity declaration   |

---

## 1. Provenance

| field          | value                                                                                      |
| -------------- | ------------------------------------------------------------------------------------------ |
| Source         | `https://www.jerseylaw.je/laws/current/l_41_2014`                                          |
| Retrieved      | 2026-08-02, HTTP `200`, 524 973 bytes, no WAF, **no Wayback fallback needed**               |
| Edition        | Official Consolidated Version under the Legislation (Jersey) Law 2021                      |
| Point in time  | "Showing the law from 16 October 2025 to Current"                                          |
| Quote hygiene  | every quoted string extracted mechanically from that fetch; nothing reconstructed from memory |

**Temporal axis — why there are no boundary pairs.** The mission asks for boundary pairs on dated
provisions. There are none to write, and that is a finding rather than an omission: Articles 5, 6
and 7 carry **no endnote marker** in the consolidated version, meaning they stand as enacted and
have never been textually amended. (Contrast Article 1, which carries endnote `[1]` — amended five
times — and Article 2(1), endnote `[2]`.) The cluster also contains no monetary figure, no
commencement-sensitive constant and no time-limited provision, so there is nothing for
`RULES EFFECTIVE DATE` to select over. The temporal axis here lives entirely in the choice of
point-in-time version, which is pinned above, in `SOURCE-EXTRACT.md`, and in the file header.

---

## 2. Scope encoded — article map

| provision                | what it does                                            | encoded as                                                                                      |
| ------------------------ | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| **Art 5(1)**             | the charity test                                        | `` `the entity meets the charity test` `` (the `@export`ed entry point)                          |
| Art 5(1)(a)              | all purposes charitable or ancillary                    | `` `5(1)(a) — all of its purposes are charitable or ancillary` `` (`all` over the purpose list)  |
| Art 5(1)(a)(i)           | charitable purposes                                     | `` `the purpose is a charitable purpose` ``                                                      |
| Art 5(1)(a)(ii)          | purely ancillary or incidental                          | `` `(ii) — the purpose is purely ancillary or incidental` `` (with the A9 referential gate)      |
| Art 5(1)(b)              | public benefit to a reasonable degree                   | `` `5(1)(b) — public benefit` ``                                                                 |
| **Art 5(2)**             | government-control carve-out                            | `` `5(2) — the government-control disqualification applies` ``                                   |
| Art 5(2), direction mode | activities directed or controlled by (a)/(b)/(c)        | `` `5(2) — direction or control by a listed person is expressly permitted` ``                    |
| Art 5(2), governor mode  | any governor to be (a)/(b)/(c)                          | `` `5(2) — governorship by a listed person is expressly permitted` ``                            |
| Art 5(2), trailing       | "acting in that capacity"                               | a conjunct on the disqualification                                                               |
| **Art 5(3)**            | Ministerial Order disapplying 5(2)                      | negative limb on the disqualification                                                            |
| Art 5(4)–(8)             | guidance machinery                                      | **out of scope** (procedural; the only deontic material nearby)                                  |
| **Art 6(1)(a)–(p)**      | the sixteen charitable purposes                         | one named limb per head, disjoined in `` `the purpose falls within paragraph (1)` ``             |
| Art 6(2)(a)              | health *widened* to sickness/disease/suffering          | extra operand disjoined into head (d)                                                            |
| Art 6(2)(b)(i)–(ii)      | citizenship *widened* to regeneration, civic promotion  | two extra operands disjoined into head (f)                                                       |
| Art 6(2)(c)              | "sport" *gated* to physical skill and exertion          | conjunct on head (h)                                                                             |
| Art 6(2)(d)(i)–(ii)      | recreation *gated* to need-based or public-at-large     | `` `(2)(d) — the recreational-facilities restriction is satisfied` ``, conjunct on head (i)      |
| Art 6(2)(e)              | (1)(n) includes accommodation or care                   | **inert, no operand** — see ambiguity **A2**                                                     |
| Art 6(2)(f)              | philosophical belief *deemed* analogous to (c)          | independent route into head (p)                                                                  |
| Art 6(3)–(4)             | States' power to add heads by Regulations               | **out of scope** (amendment power, not a test)                                                   |
| **Art 6(5)**             | political-purposes carve-out                            | `` `(5) — the purpose is excluded as political` ``, applied at **both** 5(1)(a) limbs            |
| **Art 7(2)(a)**          | mandatory comparison                                    | procedural conjunct of `` `the public benefit determination was properly made` ``                |
| **Art 7(2)(b)**          | unduly-restrictive question, if section-of-public only  | proviso limb `(NOT trigger) OR asked`; the *answer* is non-operative — see **A7**                |
| **Art 7(3)(a)**          | no presumption of public benefit                        | procedural conjunct — see **A8**                                                                 |
| **Art 7(3)(b)**          | identified individuals are not a section of the public  | **hard bar** overriding the 5(1)(b) judgement — see **A6**                                       |
| Art 7(4)                 | guidance on public benefit                              | **out of scope**                                                                                 |
| **Art 1**                | "charitable purpose", "constitution", "governor", "purpose", "Minister" | carried inert; the definitional chain is made visible                             |
| **Art 2(4), (6), (7)**   | referents of constitution / purpose / governor          | carried inert (entity-type dispatch selects *which document or person*, not the test's logic)    |

**Deliberately out of scope:** Parts 2 and 4–7 entirely (the Commissioner, the register,
registration and deregistration, misconduct and required-steps, the tribunal, offences), Article
2(1)–(3), (5), (8)–(10), and the remaining Article 1 definitions. Per the scope ruling this is the
test/purposes/carve-outs core, not the whole Law.

**No regulative rule appears in this file, deliberately.** The whole cluster is constitutive — it
says when a state of affairs *obtains*, never who must do what by when. The nearest deontic
material (Art 5(4)–(8), 7(4): the Commissioner *must* publish guidance, *must* consult, the Minister
*must* lay a copy before the States) is out of scope, and is where a `PARTY … MUST … WITHIN` would
belong.

---

## 3. The ambiguity register

Twelve interpretive choices. Each is marked `-- AMBIGUITY A<n>` in `charity-test.l4` at the site
where it bites, with both readings spelled out. This table and those comments must agree.

| #       | provision       | the question                                                      | reading (i)                                                                    | reading (ii)                                                            | **taken** | why                                                                                                                                                                     | exercised by                                                                                            |
| ------- | --------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| **A1**  | 6(2)(c)         | "sport that involves physical skill **and** exertion"             | conjunctive: both skill and exertion                                            | hendiadys: one compound idea, either component suffices                  | **(i)**   | "and" is the drafter's conjunction, and the provision is a *narrowing* one — it exists to keep something out of (1)(h), which only (i) does                                | `a spectator-pastime purpose` vs `a physical-sport purpose`                                              |
| **A2**  | 6(2)(e)         | "(1)(n) **includes** relief given by accommodation or care"       | declaratory: (1)(n)'s "in need" element still governs                          | free-standing: providing care is itself enough for head (n)              | **(i)**   | (2)(e) speaks of "relief", a word it takes from (1)(n), which supplies that relief's object; (ii) would make a commercial care home charitable                            | contributes **no operand** — the asymmetry against (2)(a)/(2)(b) is the observable                       |
| **A3**  | 6(1)(p)         | "may reasonably be regarded as analogous"                        | open evaluative standard, judged afresh                                        | closed list: only what 6(2)(f) deems analogous                           | **(i)**   | "may reasonably be regarded" is the language of judgement; 6(2)(f) reads as one instance, not an exhaustive definition                                                    | modelled as an **input** judgement — a stated limit on what this formalisation can verify                |
| **A4**  | 6(5)            | scope of the political carve-out                                 | purpose-level: disqualifies the *purpose*; entity fails via 5(1)(a)            | entity-level: the entity is itself outside the Law                       | **(i)**   | 6(5)'s grammatical subject is "the purpose of advancing …" and its predicate classifies a purpose, not an entity                                                          | the two readings agree on the answer and differ on the **reason reported** — which is the point          |
| **A5**  | 7(1)            | does Art 7 fix the *meaning* or only *bind three officers*?      | rule of construction, binding on everyone                                      | addressee-limited to Commissioner, tribunal, court                       | **(i)**   | (ii) makes the charity test mean different things by who applies it — an entity failing before the Commissioner but passing on self-assessment                            | 7(3)(b) is applied unconditionally                                                                       |
| **A6**  | 7(3)(b)         | operative force                                                   | substantive bar: such an entity does not provide public benefit                | evidential only: may not *treat* them as a section of the public         | **(i)**   | the provision does not stop at the treating-as rule — "and accordingly must not treat **an entity** … as providing public benefit" is a conclusion about the entity        | `the grandchildren's trust` (finding is affirmative, bar still defeats it)                               |
| **A7**  | 7(2)(b)         | does an "unduly restrictive" condition **defeat** public benefit? | consideration only; the 5(1)(b) judgement absorbs it                           | defeater                                                                | **(i)**   | the statute distinguishes its own modalities in adjacent paragraphs — 7(2) "must have regard to" vs 7(3) "must not"; (ii) collapses that distinction                       | `the school with an unduly restrictive fee` — **the choice most likely to be wrong**; see §6             |
| **A8**  | 7(2), 7(3)(a)   | consequence of a *defective determination*                        | validity: determination defective, entity's status unaffected                  | truth: a defective determination cannot establish public benefit         | **(i)**   | 7(2) and 7(3)(a) address "the person determining the question" and regulate *how* it is answered; nothing in them speaks to the entity                                     | `the church whose benefit was presumed` — improperly made **and** meets the test                         |
| **A9**  | 5(1)(a)(ii)     | ancillary "to any of **its charitable purposes**" — when it has none | referential: presupposes a charitable purpose to attach to; all-ancillary fails | literal-flag: take the characterisation as given; all-ancillary passes   | **(i)**   | "its charitable purposes" is a definite reference the entity must satisfy; (ii) admits an entity entirely incidental to nothing                                            | `the charity shop with nothing behind it` (fails) vs `the poverty trust with a charity shop` (passes)    |
| **A10** | 5(1)(a)         | "all of its purposes" when it has **no** purposes                | vacuous truth: limb (a) passes                                                 | existential import: a purposeless entity fails (a)                       | **(i)**   | the standard reading of a universal, and what `all` implements; limb (b) usually catches such an entity anyway                                                             | `the entity with no purposes` — **pinned deliberately**; see §6                                          |
| **A11** | 5(1)(b)         | who may rely on "intends to provide"                             | applicants only                                                                | anyone; the parenthesis merely spells out the common case                | **(i)**   | "in the case of an applicant" is a restrictive qualifier that would do no work under (ii)                                                                                  | `the applicant not yet operating` (passes) vs `the dormant registered charity` (fails)                   |
| **A12** | 5(2)            | reach of the tabulated list (a)–(c)                              | distributed: the list serves **both** modes — six permission limbs             | second-mode-only: attaches to "governors to be" alone                    | **(i)**   | (ii) leaves "directed or otherwise controlled by" dangling with no object, which is not a possible reading of the sentence                                                 | `the Ministerially directed trust` (direction mode) vs `the States-governed foundation` (governor mode)  |

A thirteenth reading was considered and is **not** an ambiguity: whether Art 5(2) can bite on an
entity that already fails 5(1). The text ("An entity that **otherwise meets** the charity test,
nevertheless does not meet that test") makes 5(2) a defeater on a passing entity, but since the
overall test is a conjunction the truth value is identical either way. It differs only in the reason
reported, and is recorded as a modelling note in the file rather than as a registered ambiguity.

---

## 4. Assertions and run evidence

**102 `#ASSERT` directives — 47 positive, 55 negative.** Every encoded limb has at least one negative
assertion; both carve-outs are exercised in both directions.

Command and verbatim output:

```
$ JL4_LIBRARY_PATH=…/charities-cleanroom/jl4-core/libraries \
  …/x/l4/build/l4/l4 check jl4/examples/legal/charities-cleanroom/charity-test.l4
EXIT 0
Check succeeded.
```

```
$ … l4 run jl4/examples/legal/charities-cleanroom/charity-test.l4
EXIT 0
#ASSERT directives in source:  102
Evaluation blocks in output:   102
"assertion satisfied":         102
"assertion failed":              0
```

> **Read the assertion count, not the exit code.** `l4 run` exits `0` even when assertions fail —
> confirmed against every mutant in §5, all of which exited `0` while reporting failures. The green
> signal for this file is **`grep -c "assertion failed" == 0` with 102 `assertion satisfied`**, not
> `$? == 0`. Any CI wrapper for this corpus must assert on the counts.

Coverage by cluster:

| section                                        | asserts | notes                                                                                       |
| ---------------------------------------------- | ------: | -------------------------------------------------------------------------------------------- |
| 6(1) heads, positive and negative              |      13 | each named head exercised negatively                                                        |
| 6(2)(a) health widening                        |       2 | reached *only* through the widening — the purpose does not claim to advance health          |
| 6(2)(c) sport gate                             |       4 | both purposes claim head (h); only the gate separates them                                  |
| 6(2)(d) recreation gate                        |       4 | gate and head asserted separately, both ways                                                |
| 6(2)(f) philosophical-belief deeming           |       3 | reached *only* through the deeming — no analogy judgement was made                          |
| 6(5) political carve-out                       |       7 | including: a political purpose still *falls within* (1) but is not a *charitable purpose*   |
| 5(1)(a)(ii) ancillary limb + A9 gate           |       4 | same purpose, two entities, opposite results                                                |
| 5(1)(a) "all of its purposes"                  |       7 | includes the A10 empty-list pin                                                             |
| 5(1)(b) and Article 7 public benefit           |      12 | A6 bar, A7 non-defeater, A11 both ways                                                      |
| 7(2)/7(3)(a) determination validity (A8)       |       9 | including the divergence: improperly made **and** meets the test                            |
| 5(2)/5(3) government-control carve-out         |      14 | both modes, all three listed persons, the capacity qualifier, the Order                     |
| end-to-end charity test                        |      23 | 11 pass, 12 fail                                                                            |

---

## 5. Mutation testing — evidence that the assertions bite

102 green assertions prove nothing on their own if they are vacuous. Six mutants were built by
inverting a load-bearing decision, each run against the unmodified assertion suite:

| mutant | the mutation                                                    | failing assertions |
| ------ | ---------------------------------------------------------------- | -----------------: |
| M1     | `all` → `any` in 5(1)(a)                                        |                 12 |
| M2     | drop the 5(3) Order defeater                                    |                  4 |
| M3     | 6(2)(c) sport gate: conjunction → disjunction                   |                  4 |
| M4     | drop the A9 referential gate on the ancillary limb              |                  6 |
| M5     | drop the 7(3)(b) bar from 5(1)(b)                               |                  4 |
| M6     | drop the applicant gate from the A11 intention limb             |                  6 |

Every mutation is caught, and each by more than one assertion. The mutants live only in the
scratchpad; they are not committed.

---

## 6. Where this encoding is most likely to be wrong

Stated plainly, because a formalisation that only advertises its confidence is not auditable.

1. **A7 — the "unduly restrictive" condition as a mere consideration.** This is the choice most
   exposed to Jersey practice having hardened the other way. If the Commissioner's published
   guidance under Art 5(4) treats an unduly restrictive fee as fatal, reading (ii) is right and this
   file is wrong. It is deliberately isolated in a single field that contributes no operand, so
   flipping it is a one-line change plus one assertion.
2. **A10 — vacuous truth over an empty purpose list.** An entity with no purposes passes 5(1)(a) and
   turns entirely on 5(1)(b). The uncomfortable edge is asserted rather than hidden
   (`the entity meets the charity test` `` `the entity with no purposes` ``). The real risk is not
   legal but operational: an ingestion pipeline that silently drops unparsed purposes would convert
   a failing entity into a passing one. Any input path feeding this module must reject an empty
   purpose list rather than pass it through.
3. **A3 — 6(1)(p) analogy as an input.** This module records *who decided* an analogy; it does not
   decide one. Head (p) is therefore only as good as its input, and no assertion here can test the
   reasonableness of an analogy judgement.
4. **The Art 5(4) guidance is not modelled at all.** Art 5(5) makes it mandatory for *any person*
   determining the test to have regard to the Commissioner's guidance. That guidance is a live
   source of law for this cluster and is out of scope here. A determination computed by this module
   is therefore incomplete as a matter of Art 5(5) even when every assertion is green.
5. **Art 2's entity-type dispatch is carried inert.** Whether a given arrangement is an "entity" at
   all (Art 2(1), amended by R&O.56/2025), and which document is its "constitution", are treated as
   resolved before this module runs.

---

## 7. Cleanroom integrity declaration

This encoding was produced **de novo from the primary source**. Specifically:

- **Sources used, exhaustively:** `https://www.jerseylaw.je/laws/current/l_41_2014` (one fetch,
  2026-08-02); the `writing-l4-rules` skill and its `references/drafting-patterns.md`;
  `jl4-core/libraries/prelude.l4` (to confirm the signatures of `all` and `any`); and
  `jl4/examples/legal/regcf/regcf.l4` — a **different subject** (SEC Regulation Crowdfunding), read
  for house style only, as the brief permits.
- **No prior encoding of this Law was consulted.** No file or directory whose path matches `*charit*`
  was opened anywhere in this repo or any sibling worktree, other than the output directory
  `jl4/examples/legal/charities-cleanroom/` created by this task and the worktree root
  `l4wt/charities-cleanroom` itself. No search for such a corpus was made.
- **`lexipedia.xyz` was not fetched.** `specs/todo/lexipedia-superset/LEXIPEDIA-PROBE.md` and every
  other probe or comparison document was not opened.
- **The repo was not grepped for charity-related terms.** The only greps run against repo files
  targeted `all`/`any` in the prelude, field-name and `#ASSERT` style in `regcf.l4`, and counts
  within this task's own output files.

### Disclosed contamination

**One item, disclosed.** `references/drafting-patterns.md`, which the skill directs the reader to and
which this task's brief explicitly names as available, contains a worked discussion of `MAYBE`-vs-
total-enum return types that cites, as its example, four functions in a file at
`paper/case-studies/charities-jersey-2014/part-6-use-of-terms.l4`. Reading that reference therefore
revealed **the existence and path of a prior Charities (Jersey) 2014 encoding**, and three incidental
facts about it: that it encodes **Part 6** of the Law, that it contains functions named
`the entity's/person's liability under Article 21/23` returning `MAYBE Part6Penalty`, and that
`Part6Penalty` is a four-field record.

What follows from that, honestly stated:

- The file itself was **not opened**, and no further detail about it was sought.
- The leaked facts concern **Part 6 (offences and penalties under Articles 21 and 23)**, which is
  **outside this task's scope** and is not encoded here. Nothing in this file's article map, logic,
  ambiguity register, scenarios or assertions derives from them.
- The leak is about *return-type shape*, not about the charity test's substance. It could not have
  informed any of the twelve interpretive choices.
- Because the reference was named as permitted reading, this is not a breach of the brief. It is
  disclosed because the experiment is a **provenance control**, and a reviewer assessing
  independence should know that the existence and rough contents of a sibling encoding were
  unavoidably visible from within the sanctioned toolset — and that the guidance file, not the
  agent, is where that channel lives. If the cleanroom is repeated, `drafting-patterns.md` is the
  leak to plug.

Beyond that item, the encoding is independent.
