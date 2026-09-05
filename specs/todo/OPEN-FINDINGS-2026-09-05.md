# Open findings, 2026-09-05

> **Status: OPEN. None of these is fixed, and none has a branch as of 2026-09-05.** This file is
> not a spec and rules nothing. It is the durable home for defects and open questions that were
> found while a batch of design rulings was being recorded, and that would otherwise have existed
> only in a scratchpad and in one session's messages. Each entry carries a **witness** you can run
> and a **mechanism** you can read, so that acting on it needs no archaeology.
>
> **Scope.** Findings only. The rulings themselves are in their own documents:
> `IMPLICIT-PROPS-DESIGN.md` §11, `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` §11,
> `SET-OPERATORS-SPEC.md` §18, `TEMPORAL-RULE-VERSION-DESIGN.md` §1.4.3.
>
> **Every finding has a stable id, `OF-n`, and the id is the handle — not its position in this
> file, and not a section number in some other spec.** Ids are never reused and never renumbered;
> new findings take the next free number. Cite `OF-3`, not "§3 of the findings file". This exists
> because three branches appended to `IMPLICIT-PROPS-DESIGN.md` §11 on one day and collided, which
> is what a positional handle does under concurrency.
>
> **Who found what is deliberately not recorded.** What is recorded is what was measured, when,
> and on which binary — because that is what a later reader has to re-check.

## Cautions for anyone re-checking these

**Line numbers here are `origin/unstable` at `b2a3faac`, and they drift between branches.** Three
different line numbers were in circulation for one function on one day: `mergeResultTypeInto` is at
`TypeCheck.hs:4847` on `b2a3faac`, at `:4891` on `props/tdnr-collapse`, and was cited as `:4958`
from a third tree. **Always name the tree with the line.** Twice on 2026-09-05 a borrowed
`file:line` would have caused a wrong action, and once (**OF-6**) the citation was right while the
verification had been taken against the wrong branch — so "which branch" belongs in the same reflex
as "which line".

**Three branches appended to `IMPLICIT-PROPS-DESIGN.md` §11 on one day, and the numbers collide.**
As of 2026-09-05: `props/assume-sweep` defines **§11.14** (sequencing item 6), `props/tdnr-collapse`
defines **§11.15** (the section-binder pairing fix), and `props/rulings` defines **§11.14, §11.15
and §11.16** (R13, R14, the cross-`IMPORT` defect). A bare "§11.15" is therefore ambiguous until
those branches have all landed and one of them has renumbered. **Cite the branch with the number
until then**, and prefer the stable ruling id (`R13`, `R14`) where one exists, since R-numbers do
not shift when a list grows.

**A retracted cause is not finished until whatever rested on it has been re-derived.** _A wrong
cause does not stay in the sentence that states it — it propagates into whatever was built to check
the claim, and a test written against a misdiagnosed symptom is worse than none, because it reports
green._ The instance that produced this is in **OF-1**: a mechanism claim was retracted, and the
retraction exposed that the fix's own acceptance marker had been written against the misdiagnosed
symptom. When you retract a cause, grep for what cites it — tests first.

**`grep -c` over an `.l4` file counts comments.** `regcf-denovo.l4` matches its floor binding eight
times outside the declaration and has seven arms; the eighth, at `:3035`, is inside prose. Drop
lines whose first non-space characters are `--`.

---

## OF-1 — declaration-order sensitivity in TDNR candidate resolution. RECORDED ELSEWHERE

**Do not re-record this here.** It is written up in full, with its four-line witness and its
mechanism, in `IMPLICIT-PROPS-DESIGN.md` §11.15 on branch `props/tdnr-collapse` ("Correction to the
finding this discharges"). In one line: a bare `ASSUME f IS A FUNCTION FROM … TO …` reaches the
scan phase with no result type, because `scanFunSigAssume`'s `mergeResultTypeInto` returns an
empty-`GIVEN`/no-`GIVETH` signature unchanged and drops the type, so a use checked before
`inferAssume` reaches it sees a candidate that unifies with anything.

Three properties of it are worth repeating **because they change how you test it**: it is order
_sensitive_ (the `#EVAL` above the two `ASSUME`s gives one `AmbiguousTermError`, below them gives
zero); the same overload written as two `DECIDE`s, or as `ASSUME`s in `GIVEN`/`GIVETH` form, is
order-**in**sensitive; and it **predates section binders**, so it is not a props defect and will not
be fixed by anything in that programme.

**Entered here only so that a reader of this file is not told seven findings and given six.**

**And one thing worth keeping beyond the finding itself: the wrong cause had reached a test.**
`props/assume-sweep` §11.14 originally offered `macma3.l4` as a second instance of the
section-binder collapse — the two "multiple definitions" diagnostics vanish on migration, which is
true — and attributed the vanishing to that collapse, which is not. `gm-assume-sweep` retracted it
visibly in `9af84932` ("the effect was real, the cause was not") rather than quietly editing it out,
and the retraction is what exposed the real damage: **the acceptance test for the fix rested on the
misattributed symptom.** Its marker had read "`macma3.l4`'s two suppressed 'multiple definitions'
errors must come back"; a fix could have satisfied that for the wrong reason, or failed it while
being correct. The repaired marker reads "the printed module must keep every binding rather than
only the first", and says in terms that `macma3.l4` is **not** part of the acceptance test.

The general shape, which is why it is recorded here and not only in that branch's history: **a
wrong cause does not stay in the sentence that states it.** It propagates into whatever was built to
check the claim, and a test written against a misdiagnosed symptom is worse than no test, because it
reports green. When a mechanism claim is retracted, the retraction is not finished until whatever
was built on it has been re-derived.

## OF-2 — `isSectionBinderElaboration` keys on the raw name. RECORDED ELSEWHERE

**Do not re-record this here either.** Same section, same branch (`props/tdnr-collapse`,
`IMPLICIT-PROPS-DESIGN.md` §11.15, "Not fixed here, same family"), where it is written up with the
repair options. In one line: `L4.Names.isSectionBinderElaboration` (`jl4-core/src/L4/Names.hs:48-51`
on `b2a3faac`) tests ``rawName (getName n) `elem` ns``, and the docstring's ground for that —
"a section that also spells out an `ASSUME`of a name its own`GIVEN` binds is already a duplicate
definition, so the name-based test has no reachable false positive" (`Names.hs:45-47`) — **is false
under type-directed name resolution**, where two same-named `ASSUME`s at different types are not a
duplicate definition.

**What this file adds: where it bites and how loudly.** Evaluation is unaffected — the elaborations
stay distinct and they are what evaluates. The damage is at the printer and therefore at everything
that re-emits a module through it: `prettyLayout` drops the hand-written `ASSUME` as though it were
the binder's elaboration, so the printed module fails to type-check. `l4 batch` re-emits through
`prettyLayout`, so it **fails loudly rather than answering wrongly**. Three call sites share the
helper: `Print.hs:588`, `Names.hs:77`, `Export.hs:455`.

**This blocks `PROPS-REDTEAM-2026-09-03.md` §6 item 7 (migration and deprecation).** It is exactly
the shape the corpus sweep produces wherever a section acquires a binder while keeping an overloaded
`ASSUME` of the same name.

**The "zero instances today" bound is dated and expires on a known event.** On `b2a3faac`, 7 `.l4`
files carry a section binder (13 sites) and none pairs one with a hand-written overloaded `ASSUME`.
On `props/assume-sweep` it is **76 files / 110 sites** (measured 2026-09-05, counting a `GIVEN`
indented past a `§` on the line after the heading). The bound expires when that branch lands, or
sooner if anyone hand-writes the pair. **Do not quote "zero instances" without the date and the
ref.**

---

## OF-3 — `l4 batch`'s generated wrapper lands inside whatever section is open at end of file

**Severity: loud failure, not a wrong answer. No owner. Owed upstream as an issue.**

**Mechanism.** `jl4/app/L4/Cli/Batch.hs:341-342` builds the program it evaluates by plain text
concatenation:

```haskell
      let wrapperCode     = generateBatchWrapper exportFn.exportName givenParams assumeParams input
          combinedProgram = filteredSource <> wrapperCode
```

`generateBatchWrapper` emits at column 1, and `filteredSource` is `prettyLayout filteredModule`,
which does not close the module's sections. So the wrapper's definitions are parsed as members of
whichever `§` is still open at the end of the file, and they are **qualified by it**. Where the
export reads a binder belonging to a _different_ section, the wrapper defines the name in the wrong
place and the run fails.

**Witness** (`l4-base2`, `unstable` + #333 + #334; reproduced 2026-09-05):

```l4
IMPORT prelude

§ `A`
    GIVEN n IS A NUMBER

@export
GIVETH A NUMBER
`from A` MEANS n

§ `B`
    GIVEN n IS A NUMBER

GIVETH A NUMBER
`from B` MEANS n
```

```
$ l4 batch wrapperscope.l4 -e 'from A' -i '{"n":7}'
… "status":"error" …
  There are multiple definitions for the identifier n …
    B.n (defined at wrapperscope.l4.batch1.l4:26:1-2) of type NUMBER
    B.n (defined at wrapperscope.l4.batch1.l4:8:11-12) of type NUMBER
```

`26:1-2` is the wrapper, at **column 1**, and the diagnostic qualifies it **`B.`** — it landed
inside `§ B`. **Control**, the same file with `§ B` deleted so that `§ A` is the open section:
`{"result":7,"status":"success"}`.

**What would close it.** The wrapper has to be emitted at module scope regardless of the source's
section structure — either by closing the sections in `filteredSource`, or by emitting the wrapper
before rather than after it, or by having `prettyLayout` render an explicit end. Any of the three
needs a fixture in `jl4/tests-cli` of the shape above.

**Reachability: LIVE TODAY, not latent — corrected 2026-09-05 after this entry was first written.**
The original text here said "low … section binders exist in seven files, all fixtures". One of those
seven is **`doc/reference/syntax/section-given-example.l4`, a shipped documentation example linked
from a doc page**, and it is already broken:

```
$ l4 batch doc/reference/syntax/section-given-example.l4 -i '{"amount":100,"applicable rate":0.1,"surcharge":2}'
… "status":"error", "output":null …
  There are multiple definitions for the identifier `applicable rate` …
    `Ordinary signatures`.`applicable rate` (defined at …batch1.l4:37:1-18) of type NUMBER
    Rates.`Concessionary rates`.`applicable rate` (defined at …batch1.l4:11:11-28) of type NUMBER
```

The file's last section is `§ Ordinary signatures`, and that is what the wrapper's redefinition at
line 37 is qualified by. **Nothing catches this**: `doc/test-docs.sh` runs `l4 check` on the file,
which succeeds, and never runs `l4 batch`.

**And the population grows by an order of magnitude very soon.** Measured 2026-09-05 by counting a
`GIVEN` indented past a `§` on the line after the heading: `b2a3faac` has **7 files / 13 sites**;
`props/assume-sweep` has **76 files / 110 sites**. Every file the sweep gives a section binder to,
and whose last section is not the one its export reads from, joins this.

---

## OF-4 — BPMN: what an exclusive gateway does with a `null` from a `businessRuleTask`. UNMEASURED

**Status: an open question, not a finding. Nothing here is measured, and it is written down as
unmeasured deliberately rather than guessed at.**

**Why it matters now.** `IMPLICIT-PROPS-DESIGN.md` §11.9.1 rules that a reachable `REFUSE` lowers to
FEEL `null` in DMN. BPMN wires to DMN through `businessRuleTask`, so a refusing decision can now
hand a `null` to a gateway that has to branch on it. Nobody has run that.

**The question, in three parts.** When a `businessRuleTask` returns `null` and an `exclusiveGateway`
downstream branches on that result, does the process (a) take the default flow, (b) take no flow and
stall, or (c) raise? **And do the two engines agree?** A silent divergence here is the same class of
defect as the measured `null`-against-`<outputValues>` divergence between KIE and Camunda.

**The rig already exists, so this is a measurement, not a project.** `jl4/examples/bpmn/expected/`
holds the artifacts; `regcf-advertising.bpmn` and `regcf-reporting.bpmn` each carry both a
`businessRuleTask` and two `exclusiveGateway`s, which is the combination in question;
`etc/bpmn-kie-baseline.txt` is the jBPM/KIE baseline and says at its head that it is "measured, not
intended". The experiment is to drive one of those two through a case whose decision refuses, on
both engines, and record what each does.

**Until it is measured, no document should assert what BPMN does with a refusal.**

---

## OF-5 — a `WHERE` local silently shadows a section `GIVEN` of the same name

**Severity: silent wrong answer. No defect owner; a documentation owner exists.**

**Mechanism.** R3 (`IMPLICIT-PROPS-DESIGN.md` §11.4) enforces one binder per name per root, and R5
(§11.7) ranks `WHERE`/`LET` locals innermost, above section `GIVEN`s. Those two are consistent, but
the check that would report the collision never fires: the local is a 0-ary definition with no
`GIVEN` of its own, so the one-name-per-root check does not see it as a binder at all. The shadow is
therefore legal, intended by the ranking, and **completely unannounced**.

**Witness** (`l4-base2`; reproduced 2026-09-05):

```l4
§ `Rates`
    GIVEN n IS A NUMBER

@export
GIVETH A NUMBER
`reads the binder` MEANS n

@export
GIVETH A NUMBER
`shadows the binder` MEANS n
    WHERE
        n MEANS 51
```

With `n` supplied as **4**, in one evaluation:

| entrypoint           | result |
| -------------------- | ------ |
| `reads the binder`   | **4**  |
| `shadows the binder` | **51** |

`l4 check` reports `Check succeeded`; `l4 run` emits **zero** diagnostics at `Warning` or above;
both `l4 batch` rows report `"status":"success"`. The caller supplied a value, the model ignored it,
and nothing said so.

**What would close it.** A warning at the point a `WHERE`/`LET` local shadows a visible section
binder — not an error, because the ranking is deliberate and R5 rules it. The honest minimum is that
supplying a value which is then shadowed should not be silent, since that is a caller-visible lie.

**Related, and not the same.** This is distinct from `LET` shadowing a name in scope, which is
already an error (R9, §11.13). The gap is specifically the 0-ary `WHERE` local.

---

## OF-6 — smucclaw/l4-ide#948 is fixed on `unstable` and live on `main`

**Status: a disagreement about state, recorded with the measurement rather than resolved by
assertion. Nothing has been posted to the issue.**

A design card asserted the issue was fixed and cited `MixfixRegistry.hs:70`. A later review reported
it still live, citing `Parser/MixfixRegistry.hs:56-64`, on the ground that `gatherTop`'s catch-all
`_ -> mempty` swallows a `Section`, so `prelude.l4` — which wraps its whole body in `§ Prelude` —
registers zero mixfix hints. **Both are partly right, and the difference is the branch.**

**Measured 2026-09-05.** On `b2a3faac` (`origin/unstable`), `jl4-core/src/L4/Parser/MixfixRegistry.hs`
carries, at `:70`, ahead of the catch-all at `:71`:

```haskell
      Section _ (MkSection _ _ _ _ decls) -> foldMap gatherTop decls
```

with a comment at `:64-69` naming the `§ Prelude` case verbatim. It arrived in `355ea081`
(2026-09-04 22:51 +0800), which is on the ancestry path through `1b49b57c`, "Merge pull request
#333". **On `origin/main` the catch-all is at line 64 with no `Section` case** — which is exactly
the window the later review quoted. So the card's line number was right; its directory
(`Parser/`, not `Mixfix/`) was wrong; and its conclusion is right for `unstable` and wrong for
`main`.

**Witness — the bug reproduces on demand across the fix boundary.** The mechanism reported by the
review is correct: an empty registry skips the keyword gate and accepts identifier chains
permissively, so the defect only bites a module that declares an operator of its own AND uses one
from the prelude. No corpus file has that combination. This one does:

```l4
IMPORT prelude

GIVEN a IS A NUMBER
      b IS A NUMBER
GIVETH A NUMBER
a `plussed with` b MEANS a PLUS b

`s` MEANS SET OF 1, 2, 3
`t` MEANS 2 `is in` `s`

#EVAL 1 `plussed with` 2
#EVAL `t`
```

| binary                               | file                                 | result                                                      |
| ------------------------------------ | ------------------------------------ | ----------------------------------------------------------- |
| post-#333 (`unstable` + #333 + #334) | as above                             | `3`, `TRUE`, **0 errors**                                   |
| 2026-08-27 build (pre-#333)          | as above                             | parser **error**, ``unexpected `is in` ``, at `13:13-13:20` |
| 2026-08-27 build (pre-#333)          | as above, **local operator deleted** | 0 errors                                                    |

The third row is the control: with the registry empty the gate is off and the same prelude operator
parses, which is why this survived so long.

**The honest statement of state is neither "fixed" nor "open":** the root cause is repaired on
`unstable` by #333 and is still present on `main`, so the issue closes when `unstable` reaches
`main`. **Do not close it on the strength of a `main` checkout, and do not keep it open on the
strength of an `unstable` one.**

**Consequence for the implicit-prelude work.** An implicit prelude gives every file the
`IMPORT prelude` this defect needs. On `unstable` the hints now cross the `§ Prelude` wrapper and
the probe above passes, so #948 is a neighbour. On `main` it is a hard prerequisite. Which one
applies depends on the base that work is cut from.

---

## OF-7 — the read-set does not cross an `IMPORT`, and neither does the supply path

**Severity: a false green, then a loud failure. Ruled, not built. The ORDERING is ruled in
`IMPLICIT-PROPS-DESIGN.md` §11.16 — the refusal first, the closure second — and this is the record
that ruling points at.** Also listed in `PROPS-REDTEAM-2026-09-03.md` §7.

**The hole, measured 2026-09-05** (probe `scratchpad/consult/adv-d5/cf5.l4` + `lib_c.l4`, run on
`l4-base2`). `lib_c.l4` declares a section `GIVEN rate3 IS A NUMBER TYPICALLY 0.05` and a helper
`scaled3` that reads it. `cf5.l4` imports `lib_c` and exports `top5 m MEANS scaled3 m`. Then:

| command                                        | result                                                                                                                       |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `l4 batch cf5.l4 -i in5.json --validate-only`  | `{"errors":[],"input":{"m":100,"rate3":0.99},"status":"valid"}` — **a false green**                                          |
| `l4 batch cf5.l4 -i in5.json`                  | `status: error`, "I could not continue evaluating, because I needed to know the value of `rate3` but it is an assumed term." |
| the same with `rate3` **omitted** from the row | byte-identical error                                                                                                         |

So `rate3` is neither demanded nor delivered: `--validate-only` passes an input that cannot
evaluate, and a value supplied under that name is **accepted into the row and ignored**.

**Both halves must be named, or the next person fixes the half that makes it worse.**

1. **The read-set collector does not follow `IMPORT`.** Its three sites are per-module by type
   signature: `assumesFromModule :: Module Resolved -> …` (`Export.hs:300`),
   `decideBodiesFromModule :: Module Resolved -> …` (`Export.hs:377`, the call graph's edge table),
   and `rewriteModuleAssumes :: … -> Module Resolved -> Module Resolved` (`Export.hs:441`). The
   card's prior analysis said the fix is "confined to one module: `Export.hs` is the only place the
   closure is computed"; it is one of four sites, and the fourth is not in `Export.hs` at all.
2. **The supply path cannot deliver across an `IMPORT` even if the collector did.** `l4 batch`
   supplies a read binder by **rewriting the module's source**: it drops the binder's declaration
   and redefines it over the decoded row in a generated wrapper (`jl4/app/L4/Cli/Batch.hs:221-236`,
   which explains why a `LET` would not do), then concatenates
   `filteredSource <> wrapperCode` (`Batch.hs:340-342`). `filteredSource` is
   `prettyLayout filteredModule`, and `prettyLayout` **re-emits the `IMPORT`** verbatim
   (`jl4-core/src/L4/Print.hs:561-563`), so the imported module is re-resolved from disk and the
   rewrite never reaches it.

**Therefore the refusal comes first.** Closing the collector over imports, on its own, converts a
false green into a **demanded-then-silently-ignored** parameter — the schema would require `rate3`,
`--validate-only` would enforce it, and `Batch.hs` would still be unable to put the value where the
callee reads it. `l4 check`/`l4 batch` must **refuse** an export whose read-set crosses an `IMPORT`
before the closure is allowed to find one.

**Exposure today: zero corpus files.** Measured 2026-09-05 over the **25 distinct module names
appearing in an `IMPORT` line** across `jl4 jl4-core doc`: **three** of them contain an `ASSUME` at
all — `jl4-core/libraries/daydate.l4:104`, `jl4/examples/legal/regcf/regcf.l4:143` and `:486`, and
`jl4/experiments/thailand-cosmetics/prelude.l4:665` (`ASSUME TBD`, a vendored copy of the stdlib's)
— and **all four lines are refusal-role**, so none of them is in the discharge population. (The
card said "every one at `ASSUME` = 0 except regcf's two"; it missed `daydate` and the vendored
prelude. Its conclusion is unchanged and slightly strengthened: **zero term-role `ASSUME`s live in
an imported module today.**) Section `GIVEN` exists in only 7 files on `b2a3faac`, all fixtures added by
PR #333, and none of them is imported — **but that is a dated bound on one ref**: on
`props/assume-sweep` it is 76 files, and any of them that another module imports puts this defect
in reach. Re-measure before quoting the exposure. (`gm-discharge` measured the same independently and recorded the same
deferral.) **After discharge the exposed population is
every file that imports a migrated domain module** — 664 `ASSUME` lines in 105 files become section
binders in exactly the modules other files import, which is R0's committed cost arriving.

**One sequencing disagreement with the card's prior analysis, resolved in favour of the earlier
fix.** It proposed updating `doc/reference/syntax/section-given.md:164` "in the same PR as the fix,
not before". That line said the crossing behaviour is "not asserted"; it is now measured. Leaving a
known false green documented as unknown for the length of a queue is the drift the user-level
`CLAUDE.md` rule 1 forbids, so the page is corrected in this change and says what happens today.

---

## OF-8 — the KIE/Camunda DMN harness compiles with `--release 11`

**Severity: toolchain. A fix is identified and deliberately NOT applied.**

`etc/kie-dmn-check/run.sh:81` compiles the harness's Java source with
`javac -nowarn --release 11`. Raising it to `--release 21` is the identified fix and was **held
back on purpose**: it changes what every CI run compiles, so it is not a change to make inside an
unrelated PR.

**Recorded so the decision is not re-litigated from scratch.** The next person to hit this should
know that the number is deliberate, that the reason is blast radius rather than compatibility, and
that the change wants its own PR with the DMN engine jobs run green on it.

---

## OF-9 — R3 root-form placement dependence — REPORTED, NOT REPRODUCED HERE

**Severity: unknown until reproduced. Recorded on report, and labelled as such.**

Reported 2026-09-05: a directive of the form `#EVAL f WITH foo IS 4` answers **40** when placed
under `§§ 1` and stops with **"… is an assumed term"** when placed under `§§ 2`, in a module whose
subtraction rule is absent. If that holds, it is a placement dependence in how a root's requirement
is resolved under R3 — the same _shape_ as OF-1 (an answer that depends on where a line sits) but a
different mechanism, since R3 is about section visibility rather than about scan-time candidate
types.

**This entry carries no witness file and was not re-measured for this record**, unlike OF-3, OF-5,
OF-6 and OF-7. Treat it as a lead to reproduce, not as a measured finding — and when it is
reproduced, replace this paragraph with the file and the two outputs.

---

## OF-10 — `jl4-lsp`'s out-of-scope quick fix inserts an `ASSUME`, which R0 deprecates

**Severity: low. Already scheduled, recorded so it is not forgotten between now and then.**

`outOfScopeAssumeQuickFix` (`jl4-lsp/app/LSP/L4/Handlers.hs:1010`, offered at `:336`) resolves an
out-of-scope name by offering to insert an `ASSUME`. R0 (`IMPLICIT-PROPS-DESIGN.md` §11.1)
deprecates `ASSUME`, so the editor's own quick fix will be generating the deprecated spelling for as
long as it stands.

**Ruled to land with `PROPS-REDTEAM-2026-09-03.md` §6 item 5 (discharge), not before** — the quick
fix cannot offer a section `GIVEN` until the section-binder path is the one the compiler discharges.
Entered here only because "scheduled" and "remembered" are different states.

---

## Owed upstream

Filed by whoever holds GitHub write authority; **nothing here has been posted**.

| finding    | what to file                                                                                                                                                                                        |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| OF-3       | New issue, and **live on a shipped doc example** rather than latent: `l4 batch`'s wrapper is scoped by the last open `§`. Witness, control and the `section-given-example.l4` instance are in OF-3. |
| OF-5       | New issue: a `WHERE` local silently shadows a section `GIVEN`; ask for a warning, not an error.                                                                                                     |
| OF-4       | No issue yet — measure first. An issue asserting a behaviour nobody has run would be the thing this file exists to prevent.                                                                         |
| OF-6       | **#948: neither close nor re-open on today's evidence.** Comment the branch split if anything at all.                                                                                               |
| OF-7       | Nothing yet — the ruling (refusal first) is not built, and an issue before the branch exists would only restate `IMPLICIT-PROPS-DESIGN.md` §11.16.                                                  |
| OF-8       | Nothing — a toolchain decision, not a defect; it wants a PR, not an issue.                                                                                                                          |
| OF-9       | Nothing until it is reproduced. It is recorded on report and says so.                                                                                                                               |
| OF-10      | Nothing — scheduled behind discharge.                                                                                                                                                               |
| OF-1, OF-2 | Nothing new — they live in `IMPLICIT-PROPS-DESIGN.md` §11.15 on `props/tdnr-collapse`.                                                                                                              |
