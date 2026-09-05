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
> **Who found what is deliberately not recorded.** What is recorded is what was measured, when,
> and on which binary — because that is what a later reader has to re-check.

## 0. Two cautions for anyone re-checking these

**Line numbers here are `origin/unstable` at `b2a3faac`, and they drift between branches.** Three
different line numbers were in circulation for one function on one day: `mergeResultTypeInto` is at
`TypeCheck.hs:4847` on `b2a3faac`, at `:4891` on `props/tdnr-collapse`, and was cited as `:4958`
from a third tree. **Always name the tree with the line.** Twice on 2026-09-05 a borrowed
`file:line` would have caused a wrong action, and once (§6 below) the citation was right while the
verification had been taken against the wrong branch — so "which branch" belongs in the same reflex
as "which line".

**`grep -c` over an `.l4` file counts comments.** `regcf-denovo.l4` matches its floor binding eight
times outside the declaration and has seven arms; the eighth, at `:3035`, is inside prose. Drop
lines whose first non-space characters are `--`.

---

## 1. Declaration-order sensitivity in TDNR candidate resolution — ALREADY RECORDED ELSEWHERE

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

**Entered here only so that a reader of this file is not told six findings and given five.**

## 2. `isSectionBinderElaboration` keys on the raw name — ALREADY RECORDED ELSEWHERE

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

---

## 3. `l4 batch`'s generated wrapper lands inside whatever section is open at end of file

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

**Reachability today: low, and that is why it survived.** It needs an export whose read-set names a
binder from a section that is not the last one open. Section binders exist in seven files, all
fixtures. It becomes reachable the moment `props/assume-sweep` lands, which is why it is filed now.

---

## 4. BPMN: what an exclusive gateway does with a `null` from a `businessRuleTask` — UNMEASURED

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

## 5. A `WHERE` local silently shadows a section `GIVEN` of the same name

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

## 6. smucclaw/l4-ide#948 — fixed on `unstable`, live on `main`

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

## 7. What is owed upstream

Filed by whoever holds GitHub write authority; **nothing here has been posted**.

| finding | what to file                                                                                                                |
| ------- | --------------------------------------------------------------------------------------------------------------------------- |
| §3      | New issue: `l4 batch`'s wrapper is scoped by the last open `§`. Witness and control are in §3 above.                        |
| §5      | New issue: a `WHERE` local silently shadows a section `GIVEN`; ask for a warning, not an error.                             |
| §4      | No issue yet — measure first. An issue asserting a behaviour nobody has run would be the thing this file exists to prevent. |
| §6      | **#948: neither close nor re-open on today's evidence.** Comment the branch split if anything at all.                       |
| §1, §2  | Nothing new — they live in `IMPLICIT-PROPS-DESIGN.md` §11.15 on `props/tdnr-collapse`.                                      |
