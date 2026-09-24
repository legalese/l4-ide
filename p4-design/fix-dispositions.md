# P4 review findings — dispositions

_Written by the builder agent on 2026-08-19, in the `blawx-p4` worktree, after independently
re-verifying every finding against the tree rather than taking the reports on trust. Eight findings
came in; **all eight were confirmed and all eight were fixed**. Nothing was closed as "no change
needed". Nothing was committed._

Each entry says what was verified and how, what changed, and — where the finding offered a choice of
remedies — which was taken and why the other was not.

---

## F1 — `rodents.l4`'s citations invented a clause number and misstated the (b) proviso (major)

**Verified.** `jl4/experiments/classic/vermin_and_rodent.l4:14` does carry the real policy sentence
over an `Inputs` record identical to the seed's; the seed did not use it. `grep -rn "Exclusion 5"`
found the string only in the seed, in `corpus-plan.md` and in `seeds-as-built.md` — never in a
source. `"nor to any ensuing covered loss"` occurs nowhere in the tree. And the fifth citation
glossed the proviso as loss or damage **to** a household appliance / swimming pool / plumbing
system, where the policy's condition is "where an animal causes water **to escape from**" them —
materially different.

**Fixed.** The five `@export` lines are rewritten from the policy sentence, split at its own `(a)` /
`(b)` boundaries; the invented clause number is gone from all five and from the `§` title, which is
now `Home insurance policy — the rodents, insects, vermin and birds exclusion`. A header block in
the seed names the provenance file and line, quotes the sentence, and states the escape-of-water
point explicitly, since that is the one place a reader could re-introduce the error.

Every span still inside `"…"` was machine-checked to be a contiguous substring of the source
sentence (a five-line Python check over the `@export` lines against
`vermin_and_rodent.l4:14`; 5 spans, 0 misses). `p4-design/seeds-as-built.md` §3.2(5) and §3.3 are
rewritten in the same change — §3.3 now records the failure rather than deleting it, because
"verbatim" was the claim that failed and a later editor should be able to see why the table is
worded the way it is.

**Goldens.** `expected/rodents.blawx` regenerated — 14 changed lines: `ruledoc_name`, `rule_text`,
and `doc_part_name` in the file's 12 `attributed_rule` blocks, which is abbreviated from the title's
capitals and so went `HE 1` → `H 1`. `expected/rodents.pl` is **byte-identical** — `rule_text` does
not reach s(CASP), which is itself a useful fact about where the citation lives.

---

## F2 / F6 — the refused arity band, the diagnostic, and §6.1 (major, one defect from two sides)

These are the same defect seen from opposite ends of the arity range, so they were fixed together.

**Verified, with the built `l4`.**

- F2: a module whose `severity exceeds` is `ASSUME`d over `c IS A Consequence` (an `ASSUME`d TYPE)
  and `n IS A NUMBER`, giving `BOOLEAN`, passes `l4 check` and is then refused by `l4 blawx` with
  _"is an input of arity 2 whose first parameter is not a category … an ASSUME must take the thing
  it is about … as its first parameter"_ — advice the author has already followed. There is no edit
  that satisfies that message.
- F6: a `scaled by` `ASSUME`d over two `NUMBER` parameters returning a `NUMBER` — no category
  anywhere — is **accepted**, and emits `blawx_relationship(scaled_by,number,number,number).`, the full NLG and
  `:- dynamic` stack, and `#abducible scaled_by(A,B,C).` So `BLAWX-EXPORT-SPEC.md:564`'s flat "it
  must have a category-sorted first parameter" is false above arity 2.

The code is right and the prose is wrong: `classifyPred` (`jl4-core/src/L4/Blawx/Lower.hs`) tests
`categoryOf` only in its two arity-1 arms, admits total arity 3–10 as a relationship with no sort
condition, and drops everything else at total arity ≤ 2 into `PCUndeclared`. The refused band is
therefore **total arity ≤ 2 that is not attribute-shaped** — a floor with a hole in it.

**Fix taken: F2's option (b), keep the refusal and correct what describes it.** Option (a) —
admitting arity-2 inputs with a category first parameter — is not implementable without inventing a
block: Blawx relationship blocks start at arity 3, `(category) -> value` is already the arity-2
attribute arm, and a `(category, NUMBER)` input would image in `EmitXml` as an object-valued
attribute selector with the NUMBER in the object slot. That is the R12 blank/mis-imaging loss the
refusal exists to prevent. It is also the only choice that leaves every existing golden byte-stable.

Changed, in one pass so the four statements cannot drift apart again:

| site                                                    | what it now says                                                                                                                                      |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `jl4-core/src/L4/Blawx/Lower.hs` (diagnostic)           | names the arity band and the attribute shape; no longer claims anything about the first parameter alone                                               |
| `jl4-core/src/L4/Blawx/Lower.hs` (comment above it)     | states the band, names the arity-3 hole, and says why the wording was corrected                                                                       |
| `specs/todo/BLAWX-EXPORT-SPEC.md` §6 + §6.1             | §6 defers to §6.1; §6.1's first bullet is arity-qualified, and a **new second bullet** records the measured arity-3 behaviour                         |
| `jl4/examples/blawx/alcohol.l4`, `not-ok/zero-arity.l4` | the quoted diagnostic is re-quoted from the new text, and both drop the unqualified "every ASSUME takes the thing it is about as its first parameter" |

**New fixtures**, so the boundary is pinned by tests and not only by prose:

- `jl4/examples/blawx/not-ok/arity-two.l4` — a two-place input **with** a category first parameter,
  refused; registered in `jl4/tests-cli/Main.hs`, which asserts the message names
  `total arity 2` and, negatively, that it no longer says `first parameter is not a category`.
- `jl4-core/test/BlawxAssumeSpec.hs` gains both halves: the arity-2 refusal (asserting the message
  names the band) and the arity-3 **acceptance** (asserting the relationship block and the
  `#abducible` line). The acceptance test is the one that would fail if a later session "fixed"
  `classifyPred` to match the old prose.

The existing zero-arity assertion in `tests-cli` was tightened the same way (it now also checks
`total arity 0` and `start at total arity 3`), since a message that changes shape should break a
test that quotes it.

---

## F3 — `housing-grounds.l4` claimed ground 15's renamed fields were "the statute's OWN words" (minor)

**Verified.** Ground 15's wording, carried verbatim at
`jl4/experiments/housing-act-ground-15.l4:79-81`, contains neither "the person ill-treating the
furniture" nor "who ill-treated the furniture". They are a derived paraphrase.

**Fixed.** The header now says the fields are renamed to name ground 15's own **subject matter**
(ill-treatment, as against ground 13's waste/neglect/default), and adds a note — flagged as a
correction, so it is not silently reverted — that the two phrases are a paraphrase, quoting ground
15's actual wording and pointing at the `@export` line where the verbatim text does live. Comment
only; no golden moves.

The rename itself stands: it resolves a real atom collision **and** restores a distinction the two
grounds draw. Only the provenance claim was wrong.

---

## F4 — the brief's "catala/docassemble/openfisca consume `RelProgram`" (minor)

**Verified.** `grep -rl 'L4\.Relational\|RelProgram' --include=*.hs` over the tree returns exactly:
`jl4-core/src/L4/{Relational/*, Blawx/{IR,Lower,Emit}.hs, Desugar.hs}`,
`jl4-core/test/{RelationalSpec,BlawxAssumeSpec}.hs`, `jl4/app/L4/Cli/Blawx.hs`,
`jl4/tests/RelationalExport.hs`. `L4.Docassemble` and `L4.OpenFisca` exist and do not import it;
there is no Catala module in this tree.

**Fixed.** `specs/todo/BLAWX-P4-BRIEF.md` now states the measurement, names the single consumer,
names the goldens that actually pin the additivity requirement, and says explicitly that the shared
middle end is a forward-looking design commitment rather than a present fact — so nobody spends a
build cycle hunting for docassemble/openfisca goldens of the middle end. Re-formatted with the
pinned `prettier@3.4.2`.

---

## F5 / F7 / F8 — the tier-1 harness (minor ×3, all in `etc/blawx-tier1-harness.py`)

**F5 verified**: the preflight incremented `failures` only when the reason contained `missing .pl`,
so a genuine byte divergence printed a note and the run continued. **F7 verified by measurement**:
`parse_blawx` on `expected/{antisocial,alcohol}.blawx` and their twins returns _equal_ workspace
lists (6 rows and 4 rows respectively, names **and** encodings), so the program the harness
assembles for `alcohol/twin-qN` is character-for-character the one it assembles for
`alcohol-twin/qN` — the replay cannot disagree. **F8 verified by construction and by running it**:
`total` counted only query rows while `failures` also counted whole-seed bail-outs, so the summary
subtracted across two populations.

**Fixed, as one coherent story rather than three patches** — because the three findings interlock:
the property under test is the byte identity; given identity the replay is a tautology; so identity
must be checked fatally and the replay must not be counted as coverage.

- `twin_preflight` now compares **both** the `.pl` (minus the provenance line) **and** the `.blawx`
  workspace encodings — the latter being what the replay actually loads, so the gap closes by
  construction — and **any** divergence is fatal. Its docstring records why the "still a weaker
  cross-check" reading was rejected: with 8 FALSE rows of 18 (alcohol) and 10 of 17 (antisocial), a
  divergence confined to a FALSE-only predicate would leave every one of those rows finding no
  model and "passing" having executed nothing.
- Three counters replace one: `seed_failures` (whole seeds that ran no rows), `query_failures`
  (rows that ran and disagreed), and `replayed` (rows that are twin replays). The summary reads
  `N/N queries passed (D distinct + R twin replays of a byte-identical program, which are
re-executions and not extra coverage)`, plus `; K seed(s) could not be run` when any bailed. The
  exit code is unchanged in meaning: non-zero if either counter is non-zero.
- The TWINS block comment and the module docstring are rewritten to say what is true: the twin
  supplies the **oracle**, the byte identity is the **property**, and the replay is a
  **re-execution**. "One logic, two spellings, cross-checked" is gone.

**Regression-checked by running the failure paths, not by reasoning about them:**

```
$ python3 etc/blawx-tier1-harness.py nosuch1 nosuch2 nosuch3
blawx-tier1: 0/0 queries passed; 3 seed(s) could not be run — programs kept in …
rc=1                                     # was `-3/0 passed`

$ (perturb expected/alcohol.pl: premises( -> premisez(, one occurrence)
blawx-tier1: FAIL alcohol: twin alcohol-twin — s(CASP) DIFFERS from the twin's (first at
line 51: …) — the replay would compare two DIFFERENT programs against one oracle
blawx-tier1: 0/0 queries passed; 1 seed(s) could not be run
rc=1                                     # was: a note, then 18 rows "passing"
```

The perturbation was reverted and the revert verified byte-for-byte with `diff` before anything
else ran.

---

## Final run — the whole tree, after every fix above

All on this worktree, in this order, one `cabal` invocation at a time:

| check                                               | result                                                                                  |
| --------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `cabal build all --enable-tests`                    | **clean** under `-Wall -Werror`                                                         |
| `cabal test jl4-core-test`                          | **303 examples, 0 failures** (was 301; +2 arity boundary tests)                         |
| `cabal test l4-cli-test`                            | **282 examples, 0 failures** (was 281; +1 `arity-two.l4` fixture)                       |
| `cabal test jl4-test`                               | **2585 examples, 0 failures** — unchanged, so no golden outside `examples/blawx/` moved |
| `node etc/check-corpus-goldens.mjs`                 | 355 corpus files, all four goldens present                                              |
| `python3 etc/blawx-tier1-harness.py` (FULL)         | **150 / 150 queries passed** — 115 distinct + 35 twin replays                           |
| `node etc/blawx-fixpoint-harness.mjs`               | **181 rows checked, 0 failed, 0 empty-skipped**; blockly 10.1.3, `jsdomErrors 0`        |
| `npx prettier@3.4.2 --check` on the edited markdown | clean                                                                                   |

Relational goldens (`jl4/examples/relational/expected/*`) and the eight non-rodents Blawx goldens
are byte-stable: `jl4-test`'s count is unmoved and every `expectGolden` in `l4-cli-test` passed
against the committed bytes. The only golden this review rewrote is `expected/rodents.blawx`, for
the citation repair in F1; `expected/rodents.pl` did not move at all.

**Quotable coverage number, for whoever writes §10 P4's EXECUTED entry: 115 distinct tier-1
queries** over ten seeds, plus 35 replays that are re-executions of an already-counted program. Do
not quote 150 as coverage — the harness now prints the split for exactly this reason.
