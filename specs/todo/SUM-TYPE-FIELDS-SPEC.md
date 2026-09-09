# Fields on sum types: one selector per shared field, and no projection without narrowing

**Status (2026-09-09): RULED by Meng. S1 BUILT on `lang/whose-opening`; S2 and S3 NOT BUILT.**
Meng's mark, 2026-09-09, on being shown the two hazards below and the Haskell/OCaml comparison:
_"Dying at run time is a bad look for a language in the FP tradition. … Write it up — let's take
the best of both worlds from Haskell and OCaml."_ The rules in §3 are that ruling written out.

What is in the tree, as of the S1 commit on `lang/whose-opening` (2026-09-09): the §4 renames
(commit `7cf1e0e9`), then S1's checker half (`inferConDecls`, Note [One selector per shared field]
in `TypeCheck.hs`; the `SharedFieldTypeMismatch` error) and evaluator half (`evalConDecls` in
`Machine.hs`) in one commit, with `ok/shared-field.l4` (the positional guard of §5 item 2, plus
§1.2's program armed and traced) and `not-ok/tc/shared-field-type-mismatch.l4` as their goldens,
and a drafter-facing section in `doc/reference/types/DECLARE.md`. §1.2 now returns `FULFILLED`;
§1.1 is unchanged and still dies at run time, because that is S2's. The whole-tree `l4 check`
sweep for the new declaration error (958 files) found zero sites. One limit recorded in §5 item 1:
"same type" is by `typeKey` on the type as written, so a synonym beside its expansion is refused.

§1 (measured) describes the tree before S1; §3 S2–S5 and §5 items 3–4 describe what will be true.

**Owner:** this file. It is cross-referenced from `EVERY-EACH-QUANTIFIER-SPEC.md` §13.6.1 (which
found the second hazard while asking whether `WHOSE` could be built) and from
`IMPLICIT-PROPS-DESIGN.md` §11.7 R5 (whose "fields present on every constructor" rule depends on §3
S1 to be safe). Corrections to either of those land here first.

---

## 0. A note on the word "cast", because it has two meanings and this document needs both apart

`EVERY-EACH-QUANTIFIER-SPEC.md` uses **cast** in the theatrical sense: the **ensemble of parties** a
quantified obligation binds — "one obligation per member of the cast" (§2.4), "the roll call: where
the cast comes from" (§11.0), "the cast is fixed at arming" (R-T6). That is its primary meaning and
it is not changed here.

The grammar then reads `Pattern ::= Constructor Variable -- EVERY Tenant t: the constructor selects
the cast` (§2.4 `:1001`), and the AST names that constructor slot `Cast`
(`Syntax.hs:439-444`: _"narrowed to those built by the constructor `Cast` when it is given"_). The
slot is so named because the constructor **casts the play** — it picks who is in the ensemble. But
in picking them it also **narrows the member's type** to that constructor's arm, which is the
_type-cast_ sense of the word, and that second sense is the one that matters to this document.

**This document therefore says:**

- **the cast** — the ensemble; the parties bound. Never the constructor.
- **the narrowing constructor** — what the AST calls the `Cast` slot: `Tenant` in `EVERY Tenant t`.
- **narrowing** — the type-level effect: after `EVERY Tenant t`, or inside `WHEN Tenant t THEN …`,
  the binder `t` can only be a `Tenant`, and the checker knows it. This is what OCaml and Rust do
  with a pattern match, and what C-family "cast" does _not_ do (theirs is an unchecked
  reinterpretation; this is a checked refinement).

Where an earlier document says "the cast narrows the roll", read "the narrowing constructor narrows
the roll".

**This binds the documentation this work ships.** `doc/reference/regulative/EVERY.md:345` already
says _"the cast must be a constructor of that type"_ — the forbidden sense, predating this file. New
text must not extend it: write "the narrowing constructor", or name the thing directly
(_"`EVERY Tenant t` tells the checker `t` is a `Tenant`"_). Repairing the pre-existing sentence is a
separate, optional cleanup — a drafter-facing rename of a word in shipped docs, not part of this
ruling.

## 1. Two hazards on a sum type, measured 2026-09-09

All probes run against a binary built from `lang/whose-opening` @ `a619afa6`, `JL4_LIBRARY_PATH`
pinned to that tree's libraries. The probe files are not in the corpus (they would need goldens);
each is reproduced inline where it is load-bearing.

### 1.1 Hazard 1 — a field on _some_ arms: partial projection dies at run time

```l4
DECLARE Actor IS ONE OF
    Landlord
    Tenant   HAS monthly_rent IS A NUMBER
everyone MEANS LIST Landlord, (Tenant OF 1500)
`rich tenants sign` MEANS
    EVERY a IN everyone WHO a's monthly_rent AT LEAST 1000 MUST Sign (EXACTLY a) WITHIN 14
#TRACE `rich tenants sign` AT 0 WITH PARTY (Tenant OF 1500) DOES Sign (Tenant OF 1500) AT 1
```

- **Type-checks clean, with no diagnostic of any kind** (probe E).
- **Armed, dies at run time** (probe E2): _"The value `Landlord` reached a CONSIDER that has no
  branch for it. Add a WHEN branch for this case, or a catch-all OTHERWISE branch."_ The drafter
  wrote no `CONSIDER`; the message describes the desugared selector, not their program.
- **With the narrowing constructor — `EVERY Tenant a IN everyone …` — returns `FULFILLED`** (probe
  F, otherwise byte-identical). The narrowing constructor filters the roll before the filter runs,
  so the projection never meets a `Landlord`. **Narrowing works — at run time.**

### 1.2 Hazard 2 — a field on _every_ arm at the same type: cannot be read at all

```l4
DECLARE Actor IS ONE OF
    Landlord HAS name IS A STRING
    Tenant   HAS name IS A STRING
everyone MEANS LIST (Landlord OF "L"), (Tenant OF "alice")
`alice signs` MEANS
    EVERY a IN everyone WHO a's name EQUALS "alice" MUST Sign (EXACTLY a) WITHIN 14
```

- **The declaration is accepted.** `ok/every/who-filter.l4:10-11` and `ok/every/run-in.l4:19-22`
  both declare `name` on both arms and their goldens read `Typechecking successful`.
  (`EVERY-EACH-QUANTIFIER-SPEC.md` §13.6 point 3 said this was refused at declaration; it was
  retracted 2026-09-09.)
- **The projection fails at check time** (probe G): _"There are multiple definitions for the
  identifier `name` … `name` (defined at :10) of type FUNCTION FROM Actor TO STRING; `name` (defined
  at :9) of type FUNCTION FROM Actor TO STRING"_ — plus a cascading second error on `__EQUALS__`.
  Neither message names an arm.
- **The narrowing constructor does not help** (probe H: `EVERY Tenant a …`, identical failure).

### 1.3 Why: L4 has no "the field `name` of `Actor`" — it has per-constructor selectors

`inferConDecl` runs once per constructor (`TypeCheck.hs:1452`) and calls `inferSelector` once per
field (`:1534`, `:1599-1616`). So `Landlord HAS name` and `Tenant HAS name` mint **two independent
definitions** — two `Unique`s, one spelling, one type `Actor → STRING`. Each is **partial**: it is
a `CONSIDER` over the constructors with one branch, which is exactly what hazard 1's run-time
message is describing. `ensureDistinct NonDistinctSelectors` (`:1531`) runs _inside_
`inferConDecl` over one constructor's own fields, so it can never see a sibling arm — which is why
the declaration is accepted.

So a "shared field" is not one total field. It is two partial functions colliding on a name. The
ambiguity error is the checker correctly reporting that there are two; it simply cannot say which,
and if it picked one, that one would still die on the other arm.

And the narrowing constructor cannot help at check time because it does not narrow the _type_:
`checkDeonton` binds the member as `KnownTerm partyT Local` (`TypeCheck.hs:1941`) whether or not
one is written. The narrowing lives only in the evaluator's roll filter.

## 2. What the two traditions do, and which half of each is worth having

| hazard                        | Haskell                                                                                                                                   | OCaml / Rust                                                                                           |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| field on every arm, same type | **one** selector, total over the declaring constructors; same name at _different_ types is a declaration error                            | no selector at all — fields of a variant's payload are reachable only inside a `match` on that variant |
| field on some arms            | a **partial** selector that compiles and throws `No match in record selector` at run time; `-Wpartial-fields` (GHC 8.4) is the confession | cannot be written: you must narrow first, and the checker holds you to it                              |

Haskell got hazard 2 right and hazard 1 wrong; OCaml and Rust got hazard 1 right and do not offer
the convenience for hazard 2. L4 today gets **both** wrong — hazard 2 is a check-time ambiguity
naming no arm, and hazard 1 is Haskell's run-time throw, minus even the warning.

**The ruling is to take the correct half from each.**

## 3. The rules — RULED 2026-09-09 (Meng), NOT BUILT

**S1 — one selector per shared field (Haskell's half).** When two or more constructors of one sum
type declare a field with the same name **and the same type**, they denote **one** selector, total
over the constructors that declare it. `a's name` in §1.2 resolves, unambiguously, and evaluates on
either arm. Declaring the same field name at **different** types across arms of one type is an
**error at the declaration**, naming both arms and both types (Haskell: _"Constructors Landlord and
Tenant give different types for field name"_).

**S2 — no projection without narrowing (OCaml's half).** A projection `e's f` is a **check-time
error** when `f` is not declared on every constructor that `e` could still be. The error names the
field, the arms that lack it, and the repair (narrow with a constructor pattern, or the quantifier's
narrowing constructor). ~~There is no run-time path: after S2, the `CONSIDER`-has-no-branch message
of §1.1 is unreachable from a projection.~~ **Corrected and extended 2026-09-09 (Meng, second
ruling):** a selector is a first-class function — `Proj` lowers to plain application
(`Machine.hs:836-837`) — so `monthly_rent a` and `map monthly_rent everyone` are the same partial
function and died identically (probe q3). **S2 therefore covers all three forms:** the projection
`e's f`, the application `f e` (checked exactly as `e's f`), and a bare partial selector used as a
value, which has no base to narrow and is refused with "write a `CONSIDER`". Only then is the
run-time death unreachable. The corpus has zero sites of the second and third forms (measured).

**S3 — narrowing is a check-time fact, not only a run-time filter.** The checker records, per
binder, the set of constructors it could still be; absent means every constructor of its type; a
nested narrowing intersects. The sites — **corrected 2026-09-09 after measurement**; the first
draft of this rule misread what a `WHEN` pattern binds:

- the quantifier's narrowing constructor — `EVERY Tenant t …` narrows `t` for the filter, the
  action, and the act's `WITHIN`/`HENCE`/`LEST` (the same positions §2.4 says `t` scopes over);
- a `CONSIDER a … WHEN Tenant t THEN …` branch narrows **the scrutinee `a`**, not `t`. In L4
  `WHEN Tenant t` binds `t` to the constructor's **payload**: `inferPatternApp` checks sub-patterns
  against the constructor's argument types (`TypeCheck.hs:3647-3660`, `matchPatFunTy` `:4162`) and
  the evaluator agrees (`Machine.hs:2558-2560`). Measured: `WHEN Tenant t THEN t's monthly_rent` is
  a **type error** today ("expected to be of type `Actor` but is here of type `NUMBER`"), while
  `WHEN Tenant t THEN a's monthly_rent` checks and evaluates. There is no as-pattern. So what a
  branch narrows is the variable it scrutinises, when that is a bare name. This is flow typing,
  which neither tradition in §2 has in that form; **CONFIRMED 2026-09-09 (Meng)**, and it is the
  counterpart of the `OTHERWISE` ruling below rather than a separate idea — `actus-core.l4:311`
  already depends on the scrutinee being narrowed. The rejected alternative was a no-op at
  `CONSIDER`, with the payload reachable only through pattern binders (`THEN t`,
  `WHEN Tenant name rent THEN rent`), which would have made S2 markedly more restrictive;
- an `OTHERWISE` branch narrows the scrutinee to the **residual** — the constructors the preceding
  `WHEN`s did not consume — and a trailing catch-all `WHEN other THEN …` gives its binder the same
  residual (**RULED 2026-09-09**, Meng). The shipped `jl4-core/libraries/actus-core.l4:297-311`
  depends on this: `OTHERWISE ccy's isoCode` after ten `WHEN`s cover every arm but the one
  declaring `isoCode`.

  **A `WHEN` arm consumes its constructor ONLY IF its sub-patterns are irrefutable** — every one a
  plain variable. An arm whose sub-pattern is a literal, an `EXACTLY`, or a nested constructor
  (`WHEN Tenant 1500`, `WHEN Tenant (EXACTLY threshold)`, `WHEN Tenant (Some n)`;
  `Syntax.hs:567-573`) matches only _some_ values of that constructor, so the constructor **stays in
  the residual**. Without this the residual is unsound and S2's guarantee fails: measured
  2026-09-09, `CONSIDER a WHEN Tenant 1500 THEN 1 OTHERWISE a's deposit` (with `deposit` on
  `Landlord` only) would compute `missing = ∅`, raise nothing, and still die at run time on
  `Tenant OF 1600`. The checker already draws this distinction for exhaustiveness — it refuses to
  reason over opaque arms precisely so "a partial literal match [is not] certified exhaustive"
  (`TypeCheck.hs:2313-2320`, `patternHasOpaque` `:2962-2968`) — and the residual must reuse that
  predicate rather than `hintSuspiciousBinders`' head-only heuristic (`:2889-2896`), which is a
  hint's approximation and not sound for this purpose.

  **An unknown constructor set is "every constructor", never the empty set.** If the scrutinee's
  type is still an inference variable after `applySubst`, or its head is not a key of
  `constructorsInScopeFromEntityInfo` (a type synonym head is not), the candidate set is **empty** —
  and an empty narrowing would make `missing` empty too, silently certifying every projection in
  that body. Record no narrowing in that case, and have S2 intersect any recorded narrowing with the
  selector's own domain before subtracting, so a stale or empty entry can never certify a
  projection. This is the same failure shape as the residual above: a narrowing that is wrong in the
  permissive direction is invisible;

- a base that is **not a bare binder** — `p's birthPlace's val`, `(f a)'s x`, an `IF` or `CONSIDER`
  result — could still be **every** constructor, always; the only repair is to name it
  (`CONSIDER p's birthPlace WHEN Just place THEN …`). Exception: a base that is syntactically a
  constructor application (`(Tenant OF 7)'s rent`, `Tenant WITH …`) or a nullary constructor is
  statically that constructor (taken on the plan's default, §6 item 5);
- a function or `GIVEN` parameter is **not** narrowed by anything: `GIVEN a IS AN Actor` leaves `a`
  at the whole type, so `a's monthly_rent` is an S2 error there until the body narrows it;
- **an alias sees through to what it names** (**RULED 2026-09-09**, Meng). `WHERE b MEANS a`, where
  `a` is a binder, makes `b`'s narrowing `a`'s narrowing. Implement it by resolving the base through
  alias chains **at the read** and consulting the root binder's narrowing in the scope of that read
  — not by copying a narrowing at the binding site. Read-time resolution is what makes an alias bound
  _outside_ the `CONSIDER` and read _inside_ two different branches see each branch's own narrowing;
  and because chains follow resolved `Unique`s rather than names, shadowing is handled by
  construction. Chains stop at the first definition that is not a bare binder: `b MEANS f a` and
  `b MEANS w's inner` are not aliases and get no narrowing.

### 3.1 Why the alias rule is not optional, and what it costs

Flow-sensitive narrowing has a known asymmetry: **let-inlining preserves typeability, let-abstraction
does not.** Replacing `b` by `a` still checks; taking a checking `a's monthly_rent`, naming its base
`b MEANS a`, and reading `b's monthly_rent` would not. Naming a subexpression is supposed to change
nothing, and that is the property at stake — not referential transparency itself, which is untouched:
`b` and `a` denote the same value and evaluate identically (measured 2026-09-09, probe I —
`viaScrutinee` and `viaAlias` return 1500/1500 and 0/0, both green today).

Every flow-sensitive system has this asymmetry — TypeScript's smart casts, Kotlin's, Typed Racket's
occurrence typing. **What those languages have and L4 does not is a soundness excuse.** Kotlin cannot
smart-cast through a `var`; TypeScript needed a dedicated feature (4.4 aliased conditions) restricted
to `const`, because under mutation an alias may stop denoting the same value. **L4 has no mutation**,
so an alias denotes its target unconditionally and there is no soundness obstacle whatsoever. The
cost is bookkeeping, and declining to pay it would bend the property for no reason.

The genuinely hard case remains out of scope, because it needs **expression** identity rather than
binder identity: `CONSIDER w's inner WHEN Tenant t THEN (w's inner)'s monthly_rent` (§6).

**S4 — the diagnostic.** S2's message must be recognisable to a drafter who never wrote a
`CONSIDER`. Two forms, one per base shape (the first draft's repair text did not compile — see S3):

> `monthly_rent` is a field of `Tenant` only, but `a` could also be a `Landlord`. Narrow `a` first —
> `EVERY Tenant a …`, or `CONSIDER a WHEN Tenant t THEN … a's monthly_rent …` (or just `THEN t` when
> the field is the whole payload), or an `OTHERWISE` after the other arms — or give `Landlord` a
> `monthly_rent` too.

> `monthly_rent` is a field of `Tenant` only, but the value it is read from could also be a
> `Landlord`. Name it and narrow it first: `CONSIDER <that value> WHEN Tenant t THEN …`.

The exact wording is the implementer's; the three contents — field, missing arms, repair — are not,
and the phrase _could also be_ is the stable marker the §4 gate greps for.

**S5 — what this does for `WHOSE`.** `EVERY-EACH-QUANTIFIER-SPEC.md` §13.6.1 found that the
corrected totality rule (open the fields present on every constructor the member could still be)
opened exactly the set that could not be read. Under S1 that set is a set of total, unambiguous
selectors; under S3 with a narrowing constructor it is that arm's fields. The intersection rule is
therefore **safe to open** once this document is built, and `WHOSE`'s check-time "naming the missing
cast" promise is S2+S4 applied inside the filter — not a separate mechanism.

### 3.2 The magic budget — a constraint on S3, RECORDED 2026-09-09 (Meng)

> _"The more magic a language contains — and I know these features are intended to make life easier
> for the drafter — the more magic in practice the harder it is to teach and explain and
> troubleshoot. So, a balance to consider."_

Taken as a binding constraint on this ruling, not a preference. Where the budget is actually spent:

| rule                              | magic  | why                                                                          |
| --------------------------------- | ------ | ---------------------------------------------------------------------------- |
| S1, one selector per shared field | none   | it _removes_ a surprise — today one written field is two partial functions   |
| S2, refuse partial projection     | none   | a refusal; the error message is the lesson, delivered when it is needed      |
| S3, `EVERY Tenant t` narrows `t`  | low    | the narrowing constructor is written at the site                             |
| S3, an alias sees through         | low    | it makes _nothing_ happen; noticeable only by its absence (§3.1)             |
| S3, `WHEN Tenant t` narrows `a`   | medium | the drafter wrote `t`; the thing that changed is `a`                         |
| S3, `OTHERWISE` residual          | HIGH   | depends on every preceding branch, and on their sub-patterns' irrefutability |

**So the whole budget is S3's, and most of it is the residual.** The bad day is concrete: one
drafter writes `WHEN Tenant t THEN … OTHERWISE a's deposit` and it works, another writes
`WHEN Tenant 1500 THEN … OTHERWISE a's deposit` and it does not, and the difference is a property of
a sub-pattern three lines above the error.

**The asymmetry that makes this tractable: magic that REJECTS is cheap to teach, magic that ACCEPTS
is expensive.** S2 teaches itself at the moment of failure. S3 accepting means that when it does not
fire, the drafter meets "why did it work there and not here?" with no local explanation.

**Therefore, a hard requirement on S4, and the test of whether a rule has earned its place:** the
diagnostic must explain the **narrowing**, not merely report the missing field. Not _"`deposit` is a
field of `Landlord` only"_ but _"…and the `WHEN Tenant 1500` branch matches only some `Tenant`s, so a
`Tenant` can still reach here."_ **If that sentence cannot be written for a rule, the rule is too
clever and is cut.** The residual rule is the one to test this against first, because it is the one
that needs it most.

Two consequences to carry:

- **Cut order, if teaching proves hard in practice.** Drop the `OTHERWISE` residual first (cost:
  `actus-core.l4:311` is rewritten as `WHEN \`ACTUS Other\` s THEN s`, and drafters write one more
branch); then the `WHEN`-narrows-scrutinee rule (cost: S2 becomes markedly more restrictive).
  Never S1 or S2 — they are the ruling.
- **An explicit escape hatch is worth more than another narrowing rule.** §6's `a's? monthly_rent`
  returning `MAYBE` is the anti-magic lever: it lets a drafter opt out of the narrowing analysis
  entirely and say what they mean, and it is teachable in one sentence. If S3 keeps growing rules to
  cover shapes, that is the signal to build the escape hatch instead.

## 4. Blast radius, and the gate S2 must pass before it is an error

**S1 is a widening**, smaller than first stated. A single-arm field's selector is unchanged, and a
multi-arm same-typed field goes from unreadable to readable. Same-name-_different_-type across arms
is accepted at declaration today, but a read without an expected type is **already** an
`AmbiguousTermError` (measured); S1 moves that to a declaration error. **Measured 2026-09-09 — the
sites that error, every one a declaration nothing reads (grep):** six inside golden globs
(`jl4-core/libraries/actus-core.l4:59-63`, `contractType` at four types; the
`Left HAS payload IS AN a / Right HAS payload IS A b` idiom in `ok/datatypes.l4:22-25`,
`ok/elem.l4:48-51`, `ok/nlg_decide3.l4:1-4`, `ok/nlg_lin2.l4:1-4`,
`lsp/semantic-tokens/declare.l4:16-19`), two under `doc/`
(`doc/courses/advanced/module-a2-cross-cutting-examples.l4:34-36`,
`doc/reference/types/for-all-example.l4:71-74` — and the same block quoted in
`doc/reference/types/for-all.md:58-59`, a seventh copy of the idiom found while renaming), three
green files under `jl4/experiments/`.
**RULED 2026-09-09 (Meng): rename them, following Haskell** — `payload` → `leftValue`/`rightValue`
applied identically in all six; `contractType` → `basicType`/`exoticType`/`combinedType`/
`creditEnhancementType`. The `actus-core` rename is a public API change for any downstream
`Basic WITH contractType IS …`; the tree has none. The use case the first draft of §6 asked for was
considered and declined.

**A second corpus, reviewed 2026-09-09: `~/src/legalese/canon`, 59 `.l4` files, none live.**
Baseline 53 pass / 6 fail, all six pre-existing and unrelated (cross-directory `IMPORT`, a
`NOT`-precedence gotcha, a concatenation fragment). **S1 breaking sites: zero** — no field name
repeats at a different type anywhere. Two same-name-same-type sites (`sg-childcare-leave.l4:240-241`,
`probate-administration-act.l4:2038-2039`) are widened by S1 and are never read today. **S2 breaking
sites: zero.**

**And the reason is worth more than the count.** Every one of the eight sum types with a
some-but-not-all field is read through the **payload binder** — `CONSIDER … WHEN `died on` d THEN d`
— never through `scrutinee's field`. Across the whole corpus the projection form of those ten field
names has **zero** occurrences. So the idiom real drafters already use is the one S2 permits without
any narrowing rule at all: they destructure rather than project.

**What that does to §3.2's budget.** It is evidence _against_ the medium-magic rule and _for_ the
high-magic one, which is the opposite of what one would guess. The `WHEN`-narrows-scrutinee rule has
**no demonstrated user** in either corpus; the `OTHERWISE` residual has exactly one
(`actus-core.l4:311`) and no clean alternative, because an `OTHERWISE` has no pattern to bind from.
The two are not separable — both are the one mechanism "the scrutinee is narrowed by the branch you
are in", which is also the whole of what has to be taught. The teaching cost is therefore not in the
mechanism but concentrated entirely in the **irrefutability sub-rule** on the residual, which is
where §3.2's explain-the-narrowing requirement has to do its work or the rule is cut.

**S2 is a narrowing of the accepted language**, and its landing shape turns on a count a grep
cannot make — it needs the checker, because whether a base is narrowed is a fact about scope, not
spelling. **Gate, in order — unchanged in substance, corrected in mechanics:**

1. Implement S2 as a **warning** first — it exists on the branch only between that step and the
   promotion — and run it over **three rigs**, because the golden suite alone undercounts: (1) the
   golden suite over its globs, collecting `.actual` files; (2) `l4 check` over every `.l4` under
   `doc/`, `jl4/examples/dmn`, the other backend example trees, and `jl4/experiments/`, none of
   which the golden globs reach; (3) `l4-cli-test`, which owns `jl4/examples/dmn/sumtype.l4`. Grep
   all three for the S4 marker phrase.
2. **Zero sites** → promote to an error in the same change.
3. **Non-zero sites** → read each. (A) A site whose base is narrowed by an enclosing `EVERY Ctor`,
   `WHEN Ctor`, or `OTHERWISE` residual that the checker did not see is an **S3 gap** — fix S3, not
   the corpus. (B) A genuine partial projection is repaired in the corpus in the same PR. (C) A file
   that already fails today is ignored and named. Then promote. **S2 does not land as a warning.**
   Meng's mark is that run-time death is not acceptable; a warning is the GHC compromise this
   document exists to decline.

**Expected counts, from reading every declaration and every scoped projection — to be confirmed,
not assumed, by the warning run.** Genuine (B) sites: `jl4/examples/legal/british-citizen-act.l4:94-97`
(four; the base is a projection over a user-declared `Maybe`, so the repair is a `CONSIDER` naming
it, and `Nothing` then yields `FALSE` where it crashed — a semantic change a reviewer must accept on
purpose), `jl4/examples/dmn/sumtype.l4:139-142` (one), `jl4/experiments/safe-post.l4:258` (one).
(A) sites: none expected once S3's `OTHERWISE` residual is built; if `actus-core.l4:311` fires, the
residual is wrong. `sumtype.l4` is the DMN KIE MustFail exhibit for ruling R4-a ("a payload
projection emits L4 no engine can compile"); **RULED 2026-09-09 (Meng): rewrite it with a
`CONSIDER`, let the DMN spec record that R4-a's example is now unreachable by construction, and let
the MustFail expectation change if the model then builds.**

**S3 is additive** for the quantifier (today's run-time roll filter is unchanged; the checker learns
what the evaluator already does). ~~For `CONSIDER … WHEN` … if `WHEN Tenant t` already types `t` as
the arm, S3 is a no-op there.~~ **Wrong, retracted 2026-09-09:** `t` is the payload; S3's `CONSIDER`
case is a NEW check-time fact about the scrutinee (S3 above). And there is **zero** existing
coverage of a quantifier-narrowed projection anywhere in the tree — every `every/` filter uses
`elem` or `EQUALS` — so the new `ok/` fixture is that path's only test, not a supplement.

## 5. Implementation sketch — what the first reader of the code should verify, not follow blindly

This is where the work is expected to land; the implementer re-checks each anchor.

1. **Selector generation** (`inferConDecl` `:1530-1553`, `inferSelector` `:1599-1616`). Group a
   type's fields by name across all its constructors before minting selectors. One group → one
   `Resolved` selector, one `CheckInfo`, one `KnownTerm … Selector` of type `T → fieldT`. A group
   whose members disagree on type → S1's declaration error. `ensureDistinct NonDistinctSelectors`
   stays per-constructor (a constructor still may not declare one name twice).
   **Corrected:** the grouping cannot live in `inferConDecl` — only `inferTypeDecl`'s `EnumDecl`
   arm (`:1448-1453`) holds all the constructors, and field types must be resolved across arms
   before any selector is minted. Later arms get `defAka` (same `Unique`, their own name and range).
   **BUILT 2026-09-09** as `inferConDecls`, which both the `EnumDecl` and the `RecordDecl` arm go
   through. One limit, measured while building: "the same type" is `typeKey` on the field type
   **as written**. A synonym is not expanded, because in the type-declaration phase the environment
   holds a synonym's name but not yet its body (the body goes out through `publicNames` and is seen
   by the term phase); an expansion via `pureExpandSynonym` at this site was tried and was a no-op.
   So `deposit IS A Money` beside `deposit IS A NUMBER` is refused, with both spellings in the
   message. Lifting this needs the synonym bodies threaded into the declaration phase; not done.
2. **The selector's body — there is no desugar.** ~~Find where that body is synthesised (the
   desugar …) and widen it.~~ **Wrong, corrected 2026-09-09.** The body is built at
   module-evaluation time by `evalConDecl` (`Machine.hs:4207-4231`) as a one-branch `CONSIDER`, and
   stored per `Unique` by `updateTerm` (`:4230`) — an unconditional overwrite. So a checker-only S1
   merge is **silently wrong**: the last declaring arm's one-branch closure wins and reads on
   earlier arms die with §1.1's message. No corpus golden would catch it. The evaluator change is
   the widening, not an optional follow-up: one closure per field `Unique`, one branch per
   declaring constructor, each carrying that constructor's own arity and that field's index —
   fields are stored **positionally** (`ValueLazy.hs:83`) and two arms may place the field
   differently. **S1's checker and evaluator halves must land in one commit**, and the guard is a
   probe with the shared field at index 1 on one arm and 0 on the other. **BUILT 2026-09-09** as
   `evalConDecls`; the guard is `ok/shared-field.l4`, whose `Landlord HAS addr, name` /
   `Tenant HAS name, rent` reads both arms, positionally and through `WITH`.
3. **Narrowing in the check environment.** ~~Add it on the local binding … at the three sites.~~
   **Corrected:** `KnownTerm`/`TermKind` is the wrong home — `TermKind` is a `Serialise`d AST type
   read by the LSP, with ~130 sites. The precedented home is a new field on `CheckEnv` beside
   `localBindings` (`Types.hs:717-727`), keyed by binder `Unique`, scoped for free by `local`, with
   four construction sites. And the count is **two binding sites plus one residual**, not three:
   `checkDeonton` `:1941` (all five quantifier positions are inside that block), `checkBranch`
   `:3586` (narrowing the **scrutinee**), and `checkConsider` `:2326` for the `OTHERWISE` residual.
   The narrowing constructor is resolved at `:1896`, 45 lines above — and it is **not** discarded
   (it is stored in the AST at `:1959`, which is what the evaluator's roll filter reads); it is
   merely unused for the member's binding.
4. **Totality at the projection.** `inferRecordProjection` is `:3125-3152` (`:3047-3072` is the
   `Proj` dispatcher); the insertion point is after `matchFunTy` (`:3137`). The selector's declaring
   constructors need **no new state**: each constructor's `KnownTerm conType Constructor` already
   names its selectors' own `Def`s as the argument names (`:1536`, `:1552-1553`), and
   `constructorsInScopeFromEntityInfo` (`:2241-2251`) enumerates a type's constructors. One trap:
   the S2 error is raised inside a forked overload branch, so without an exemption in
   `viableCandidate` (`Types.hs:466-469`) the branch merely fails and `prune` reports
   `AmbiguousTermError` instead of S4 whenever two **types** share the field name — a common shape.
   A `not-ok/tc` fixture must pin that.
5. **Evaluator.** ~~needs no change if the merged selector's body is total over its arms.~~
   **Backwards — nothing makes it total.** See item 2.
6. **Consumers.** ~~sees one selector where it saw N.~~ **Backwards for almost all of them:** the
   schema, NLG and transpiler consumers read the AST's `ConDecl` field lists by name **text** and
   are unaffected. Exactly two `Unique`-keyed consumers change — the evaluator environment, and
   DMN's `selectorNames`/`fieldScopes` (`Dmn/Lower.hs:3987-3991`), which must be deduped by
   `Unique` or a merged field's FEEL step becomes `name_2`. Hover and `@desc` are range-keyed and
   survive `defAka`; find-references improves; completion goes from two byte-identical items to one.
   Docassemble **already refuses** the S1-merged shape with a CI-pinned message
   (`Docassemble/Lower.hs:2320-2353`) — under S1 those are one field, so that refusal must be
   reworded as an exporter limit or lowered to one question (§6 item 4).
7. **Goldens and docs.** New `ok/` fixtures for S1 (shared field read on both arms, armed and
   traced) and S3 (narrowed projection); new `not-ok/tc/` fixtures for S1's type-disagreement error
   and S2's partial-projection error with S4's message; the `.l4` and its four goldens in one
   commit, read before blessing, grepped for absolute paths. A `doc/` page or section — audience:
   a drafter who has never read this file — saying what a field on several arms means and why a
   projection can be refused.

## 6. Not ruled here

- ~~**Same name, different types across arms, as two selectors chosen by expected type.**~~
  **CLOSED 2026-09-09 (Meng): follow Haskell, rename the sites.** The `Left`/`Right` `payload` idiom
  was put forward as the use case this bullet invited and was declined; see §4 for the twelve sites
  (eleven when first counted; the `for-all.md` quotation was the twelfth) and the chosen names.
  Landed as commit `7cf1e0e9`; `git show 7cf1e0e9 -- '*.l4'` is the list of what S1's declaration
  error would otherwise have refused.
- **Docassemble's existing refusal of the merged shape** (`Docassemble/Lower.hs:2320-2353`, fixture
  `docassemble/not-ok/payload-name-collision.l4`, CI-pinned). It tells a drafter to rename what S1
  makes one field. Reword as an exporter limit, or lower a merged field to one question? Open.
- **`@desc`/`@nlg` written differently on two arms of one merged field.** Today each registers under
  its own range, so hover shows the arm's own text and nothing merges. Keep, or make differing
  annotations on one field an error? Open; the plan's default is keep.
- **A syntactically identical non-binder base inside a branch that matched it** —
  `CONSIDER f a WHEN Tenant t THEN (f a)'s rent`. Treated as un-narrowed (§3 S3), since narrowing it
  needs expression identity. Open, and much harder; the repair is to name the value. Measured shape
  that checks and runs **today** and that S2 will refuse:
  `CONSIDER w's inner WHEN Tenant t THEN (w's inner)'s monthly_rent`.
  (The alias case and the scrutinee question that stood here are now ruled — see §3 S3's last two
  bullets and §3.1.)
- **A partial projection that returns `MAYBE`** (`a's? monthly_rent`, or similar). Would give a
  drafter an explicit escape from S2 without a pattern. Not proposed; recorded so the door is known.
- **Per-constructor fields that _share a name on purpose with different meanings_.** S1 merges
  them; a drafter who wants two meanings uses two names. The old spec's "someone will eventually
  want per-constructor fields that share a name" (§13.6 point 3, retracted) is answered: they get
  one field, which is what the name says.

## 7. Where this is recorded

- This file — the rules, the measurements, the gate.
- `EVERY-EACH-QUANTIFIER-SPEC.md` §13.6.1 — found hazard 2 and the terminology drift; points here.
- `IMPLICIT-PROPS-DESIGN.md` §11.7 R5 — its "fields present on every constructor" rule is safe under
  S1; a one-line pointer is added there.
- `doc/` — the drafter-facing page, when built (CLAUDE.md §6: not done until it exists).
