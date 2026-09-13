# Fields on sum types: one selector per shared field, and no projection without narrowing

**Status (2026-09-14, verified against a binary built at `7ae280e5`): RULED by Meng, and BUILT. On
`lang/whose-opening`: S1, S2, S3 and S4 are all in the tree, and S2 is an ERROR — §4's gate has been
run end to end (steps 1, 2 and 3). S3's clause-column narrowing is CUT — see §3.2's ruling of
2026-09-13.**
The warning form S2 briefly wore so §4's three rigs could count the corpus is GONE: there is no flag
that restores it, and `PartialProjection` is a `CheckError` (`TypeCheck/Types.hs:149`) whose renderer
`prettyPartialProjection` (`TypeCheck.hs:7016`) is reached from `prettyCheckError`.
§4.1 records the measured counts and where the measurement contradicted §4's
predictions; §4.2 records the six repairs, the promotion, and what they cost; §4.3 the fixtures.
S5 remains DESIGN — `WHOSE` is not built: no parser support, no goldens, nothing.

**There is no longer a DEMONSTRATED permissive hole, and that is a side effect of the cut rather
than a repair anyone set out to make.** Both holes this header used to enumerate — a column whose
constructors S2 could not enumerate (recorded, too narrowly, as "an untyped `GIVEN`"), and a
hand-written **nullary** declaration spelled with the desugarer's reserved fall-through name —
existed only because a column could be _exempted_ from S2. With no clause-column narrowing there is
no exemption to fall into: an un-narrowed read in a later clause reaches the ordinary S2 clamp,
which widens to the whole universe and refuses.

**Read "demonstrated" as written.** §5.1 states the method: two corpus sweeps (no `ok/`, `legal/`,
`doc/` or library file is refused by S2; no file that checks produces the run-time partial-selector
message) plus thirteen probes written to break it, all refused. What it does **not** claim is a
proof — four silent bails remain inside `checkPartialProjection` itself, argued unreachable from the
code rather than measured, and §5.1 item 3 says which argument covers which.

> **What this header claimed, and when.** It said "**one** permissive hole" until 2026-09-10 — from
> a single probe rather than from the code — then **two** from 2026-09-10, derived from
> `clauseColumnUniverse`'s conditions. A **type synonym** on the column type had been a third,
> closed by `5ba5f94b`. All of them are now moot: the function whose conditions the count was
> derived from no longer exists. §5.1 therefore states a measurement and its bounds rather than a
> count derived from any function's guard — because deriving it from a guard is what produced three
> wrong counts in four days, and because one of those counts was wrong in a subtler way still: it
> named a hole by one SPELLING (`GIVEN a` with no type) when the condition also covered a group
> with no signature at all, which is the spelling a drafter reaches by accident.

Meng's mark, 2026-09-09, on being shown the two hazards below and the Haskell/OCaml comparison:
_"Dying at run time is a bad look for a language in the FP tradition. … Write it up — let's take
the best of both worlds from Haskell and OCaml."_ The rules in §3 are that ruling written out.

What is in the tree, as of the S1 commit on `lang/whose-opening` (2026-09-09): the §4 renames
(commit `7cf1e0e9`), then S1's checker half (`inferConDecls`, Note [One selector per shared field]
in `TypeCheck.hs`; the `SharedFieldTypeMismatch` error) and evaluator half (`evalConDecls` in
`Machine.hs`) in one commit, then the corpus fixtures that pin it (S1d): `ok/sum-fields/shared-field.l4`
(the positional guard of §5 item 2, a `GIVEN a IS AN Actor` reader doing `a's name`, and §1.2's
program armed and traced) and `not-ok/tc/sum-field-type-conflict.l4` (the declaration error beside
a merged field on the same type), each with its four goldens, and a drafter-facing section in
`doc/reference/types/DECLARE.md`. §1.2 now returns `FULFILLED`. The whole-tree `l4 check`
sweep for the new declaration error found zero sites. One limit recorded in §5 item 1:
"same type" is by `typeKey` on the type as written, so a synonym beside its expansion is refused.

> **The file count this sweep recorded — 958 — is not reproducible and has been dropped rather than
> guessed at (2026-09-09).** `git ls-tree -r --name-only <c> | grep -c '\.l4$'` gives **960** at the
> S1 commit `73507cd8` and at every commit after it on this branch, and **957** at the rename commit
> `7cf1e0e9` before it. 958 is neither. The zero-sites result is left standing — it is what the run
> reported — but a later gate should re-derive its denominator from `git ls-files '*.l4'` at a
> **named** commit rather than inherit this one. §4.1 does exactly that.

(This paragraph described the tree at the S1 commit, and said there that _"§1.1 is unchanged and
still dies at run time, because that is S2's"_. **That sentence was true then and is FALSE now:**
S2 is built and blocking, so §1.1's program is refused at check time and `ok/sum-fields/narrowing.l4`
is the same program with `EVERY Tenant a`, armed and green.)

§1 (measured) describes the tree before S1. §3 S3 and §5 item 3 are BUILT (commit `92e12d27`);
§3 S2's check and §3 S4's diagnostic are BUILT and BLOCKING — as a warning in `0ea70d3f`, promoted
to an error with the six corpus repairs in the same change (§4.1). Only §3 S5 still describes what
will be true. One S3 site was built and then CUT: the clause-column narrowing, cut at `7ae280e5`
under §3.2's ruling of 2026-09-13.

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

**ANSWERED 2026-09-09: the run-time message quoted above no longer exists, and the second bullet's
complaint about it is discharged.** The quote stays as probe E2 recorded it. What the evaluator says
now, where a partial selector reaches run time, is:

```
The value
  Landlord
has no `monthly_rent` field.
`monthly_rent` is declared on `Tenant` only.
```

It says nothing about a `CONSIDER`, nothing about adding a `WHEN` branch, and — deliberately —
nothing about the exhaustiveness warning, because **no such warning was emitted**. It could not have
been: the `CONSIDER` being fallen off is the selector closure `evalConDecls` synthesises, one arm
per declaring constructor, and it is not in the source to be warned about. Where the read sits in a
multi-clause fall-through the clause group above it is perfectly exhaustive, so the checker has
nothing to say either. The old third sentence sent the reader hunting for a diagnostic that does not
exist, about a construct they did not write — §1.1's own complaint, one layer down.

Mechanically: `UserEvalException` gained `PartialSelector`, distinct from `NonExhaustivePatterns`; a
`Consider` the evaluator synthesises carries `Syntax.SelectorConsider` on its annotation, and the
machine threads that origin to the fall-off. A hand-written non-exhaustive `CONSIDER` is unchanged
and keeps the exhaustiveness sentence.

> **CORRECTED 2026-09-13, and it is a correction with a cost.** This paragraph used to end
> _"`ok/sum-fields/partial-selector-runtime.l4` pins the new message — it is under `ok/` precisely
> because it checks clean and then dies"_. **That fixture is deleted, and it could not be replaced
> in kind**: after the cut, the program it pinned is refused at check time (§3.2's ruling), and
> `l4 run` does not evaluate past a check error — measured, its `#EVAL`s do not run at all — so no
> `.l4` in the tree can put this message in a golden any more. The message above is therefore
> recorded HERE and in `doc/reference/errors/README.md`, and nowhere mechanical. §5.1's measurement
> says the same thing from the other end: no tracked `.l4` that type-checks raises `PartialSelector`
> at run time. Its check-time job moved to case 12 of
> `not-ok/tc/partial-projection-fallthrough.l4`.

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

**Every line number in §1.3 and §1.4 is PRE-S1, and is left that way deliberately** — §1 records the
tree as it was before this ruling, and re-pointing its anchors at today's code would describe a tree
in which the sentences around them are false. `inferSelector` does not exist any more; see §5 item 1
for where the mint went.

`inferConDecl` runs once per constructor (`TypeCheck.hs:1452`, pre-S1) and calls `inferSelector` once
per field (`:1534`, `:1599-1616`, both pre-S1). So `Landlord HAS name` and `Tenant HAS name` mint **two independent
definitions** — two `Unique`s, one spelling, one type `Actor → STRING`. Each is **partial**: it is
a `CONSIDER` over the constructors with one branch, which is exactly what hazard 1's run-time
message is describing. `ensureDistinct NonDistinctSelectors` (`:1531`) runs _inside_
`inferConDecl` over one constructor's own fields, so it can never see a sibling arm — which is why
the declaration is accepted.

So a "shared field" is not one total field. It is two partial functions colliding on a name. The
ambiguity error is the checker correctly reporting that there are two; it simply cannot say which,
and if it picked one, that one would still die on the other arm.

And the narrowing constructor cannot help at check time because it does not narrow the _type_:
`checkDeonton` binds the member as `KnownTerm partyT Local` (`TypeCheck.hs:1941`, pre-S1; it is
`:2583` today, and S3 has since wrapped it in `underNarrowing` so this paragraph's conclusion no
longer holds — see §3 S3) whether or not one is written. The narrowing lives only in the evaluator's roll filter.

## 2. What the two traditions do, and which half of each is worth having

| hazard                        | Haskell                                                                                                                                   | OCaml / Rust                                                                                           |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| field on every arm, same type | **one** selector, total over the declaring constructors; same name at _different_ types is a declaration error                            | no selector at all — fields of a variant's payload are reachable only inside a `match` on that variant |
| field on some arms            | a **partial** selector that compiles and throws `No match in record selector` at run time; `-Wpartial-fields` (GHC 8.4) is the confession | cannot be written: you must narrow first, and the checker holds you to it                              |

Haskell got hazard 2 right and hazard 1 wrong; OCaml and Rust got hazard 1 right and do not offer
the convenience for hazard 2. L4 today gets **both** wrong — hazard 2 is a check-time ambiguity
naming no arm, and hazard 1 is Haskell's run-time throw, minus even the warning.

**The ruling is to take the correct half from each.**

## 3. The rules — RULED 2026-09-09 (Meng); S1, S2, S3 and S4 BUILT; S5 not built

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
(`EvaluateLazy/Machine.hs:866-867`, re-measured 2026-09-10) — so `monthly_rent a` and `map monthly_rent everyone` are the same partial
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
  against the constructor's argument types (`inferPatternApp`, `TypeCheck.hs:4928`; `matchPatFunTy` `:5414`) and
  the evaluator agrees (`PatApp0`/`PatApp1`, `EvaluateLazy/Machine.hs:1272-1289`, re-measured 2026-09-10). Measured: `WHEN Tenant t THEN t's monthly_rent` is
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
  (`TypeCheck.hs`'s exhaustiveness check, `patternHasOpaque` at `:4151`) — ~~and the residual must
  reuse that predicate rather than `hintSuspiciousBinders`' head-only heuristic (`:2889-2896`),
  which is a hint's approximation and not sound for this purpose.~~

  **CORRECTED 2026-09-09, see §5 item 3 — reusing `patternHasOpaque` is UNSOUND**, so the
  instruction struck above was not followed. It recurses through sub-patterns and answers `False`
  for `WHEN Tenant (Some n)`, which is one of the three shapes this very sub-rule names as
  must-not-consume. What is built instead is `armEffect`, which tests irrefutability directly.
  `patternHasOpaque` is unchanged and answers a different question. The rest of the struck sentence
  stands: `hintSuspiciousBinders`' head-only heuristic remains unsound for this purpose, which was
  the point of naming it. (The two line anchors this sentence used to carry, `:2313-2320` and
  `:2962-2968`, were pre-S3 and no longer point at anything relevant.)

  **An unknown constructor set is "every constructor", never the empty set.** If the scrutinee's
  type is still an inference variable after `applySubst`, or its head is not a key of
  `constructorsInScopeFromEntityInfo` (a type synonym head is not), the candidate set is **empty** —
  and an empty narrowing would make `missing` empty too, silently certifying every projection in
  that body. Record no narrowing in that case, and have S2 intersect any recorded narrowing with the
  selector's own domain before subtracting, so a stale or empty entry can never certify a
  projection. This is the same failure shape as the residual above: a narrowing that is wrong in the
  permissive direction is invisible;

- ~~**the clauses of a fused multi-clause group narrow their own column binders.**
  `DECIDE r Landlord IS 0` / `DECIDE r s IS s's monthly_rent` narrows `s` in the second clause to
  everything `Landlord` did not take. This is the `OTHERWISE` residual one level up, spelled without
  a `CONSIDER`, and it is what makes the two spellings of §1.1's program agree.~~

  **CUT 2026-09-13 (Meng), at `7ae280e5`. This is not an S3 site and there is no such narrowing.**
  A partial read in a **later clause** of a multi-clause `DECIDE`/`MEANS` group is **refused
  outright**; it is never narrowed by the clauses above it, not even when the clauses above are
  provably exhaustive over everything that lacks the field. §3.2 records the ruling, the evidence
  ledger that drove it, and the cost Meng accepted; §5.1 item 1 keeps the analysis and its
  soundness argument, which is the only place either survives now that the code is gone.

  The one thing that remains here is **diagnostic**: `CheckEnv.inLaterClause` lets S4 say _"this is
  a later clause of a multi-clause rule, and a later clause is not narrowed by the clauses above
  it"_ rather than `NotNarrowed`'s _"nothing here narrows `a`"_, which reads as a claim about
  clauses that visibly do match constructors. It suppresses nothing and can only change a sentence
  (`NotNarrowedInLaterClause`, `TypeCheck/Types.hs:758`; set by `markLaterClause`,
  `TypeCheck.hs:1046-1049`).

- a base that is **not a bare binder** — `p's birthPlace's val`, `(f a)'s x`, an `IF` or `CONSIDER`
  result — could still be **every** constructor, always; the only repair is to name it
  (`CONSIDER p's birthPlace WHEN Just place THEN …`). Exception: a base that is syntactically a
  constructor application (`(Tenant OF 7)'s rent`, `Tenant WITH …`) or a nullary constructor is
  statically that constructor (taken on the plan's default, §6 item 5);
- a function or `GIVEN` parameter is not narrowed by its **declaration**: `GIVEN a IS AN Actor`
  leaves `a` at the whole type, so `a's monthly_rent` is an S2 error until something narrows it.

  > **This bullet's history, kept because it shows the claim moving twice.** It originally read
  > _"is **not** narrowed by anything … until the **body** narrows it"_. On 2026-09-10 that was
  > CORRECTED, because the clause-order site then in the tree made it false: a `GIVEN` that was a
  > column of a fused clause group **was** narrowed by the clauses above the read, outside every
  > body. **RESTORED 2026-09-13** by §3.2's cut: there is no clause-column narrowing any more, so
  > the original sentence is true again, and a `GIVEN` parameter is narrowed only by something in a
  > body. `doc/reference/types/DECLARE.md` carried the same sentence through both moves and is
  > corrected in the same change as this one.

  So, in full: the **type annotation** narrows nothing, and a `GIVEN` parameter is narrowed only by
  a `CONSIDER`, an `EVERY`, or an alias chain reaching one of those — its position in a clause
  matrix narrows nothing either, and a partial read on it in a later clause is refused (§3.2);

- **an alias sees through to what it names** (**RULED 2026-09-09**, Meng). `WHERE b MEANS a`, where
  `a` is a binder, makes `b`'s narrowing `a`'s narrowing. Implement it by resolving the base through
  alias chains **at the read** and consulting the root binder's narrowing in the scope of that read
  — not by copying a narrowing at the binding site. Read-time resolution is what makes an alias bound
  _outside_ the `CONSIDER` and read _inside_ two different branches see each branch's own narrowing;
  and because chains follow resolved `Unique`s rather than names, shadowing is handled by
  construction. Chains stop at the first definition that is not a bare binder: `b MEANS f a` and
  `b MEANS w's inner` are not aliases and get no narrowing.

  **A chain that ends at a constructor application ends in a narrowing, not in nothing** (built
  2026-09-09, with S2's warning). `theLandlord MEANS Landlord OF "1 Main St", "Ms Ng"` then
  `theLandlord's addr` is the same fact as the inline exception two bullets above — "syntactically a
  constructor application … is statically that constructor" — reached through one nullary `MEANS`
  instead of written in place, and it is sound for the same reason: `constBodies` holds only
  **nullary** `MEANS` bodies, so the binder denotes that construction unconditionally, and L4 has no
  mutation. **This was measured, not anticipated:** without it the two S1 fixtures
  `ok/sum-fields/shared-field.l4` and `not-ok/tc/sum-field-type-conflict.l4` are S2 sites — §4's
  class (A), an S3 gap the gate says to fix in S3 rather than in the corpus. With it, the goldened
  globs contain exactly the sites §4 predicted (§4.1).

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
> `Landlord`. ~~Name it and narrow it first: `CONSIDER <that value> WHEN Tenant t THEN …`.~~

**The second form's repair text is CORRECTED, 2026-09-09, for the same reason the first form's was:
it did not compile.** `CONSIDER <that value> WHEN Tenant t THEN … <that value>'s f …` is refused
again, because a `CONSIDER` narrows **the binder it scrutinises** and a projection is not a binder
(§3 S3, and §6's last-but-two bullet says the same thing in its own words). Every genuine (B) site
the gate found is exactly this shape, so a wrong repair here would have been handed to every one of
them. The two repairs that do compile:

> Give it a name, then narrow the name:
> `CONSIDER v WHEN Just t THEN … v's val … WHERE v MEANS <that value>`
> — or match the payload directly, which needs no name at all:
> `CONSIDER <that value> WHEN Just t THEN t`.

The second is the idiom §4 measured real drafters already using ("they destructure rather than
project").

The exact wording is the implementer's; the three contents — field, missing arms, repair — are not.

**The marker is emitted STRUCTURALLY, not as a per-form prose choice** (built 2026-09-09). A form
that omits it makes a counting gate report a **false zero** and promote a hard error over sites
nobody read, so it cannot be left to each form's prose.

**ANSWERED 2026-09-09: the marker is `" a field of "`, not `could also be`.** It moved, and the
connective it used to be now varies with the narrowing reason.

The old marker cost a sentence that contradicted itself. On a base written **as** a constructor,
`(Landlord OF 4000)'s monthly_rent`, the message said the value _"could **also** be `Landlord`"_ and
then, two lines later, _"It is written here **as** `Landlord`"_. There is no "also": the value is
that constructor and nothing else. The reason the ruling gave for keeping the phrase unconditional
was that "§4's gate detects sites by grepping for it, which would then report a false zero" — **that
gate has now been run and closed** (§4 gate steps 1–3), so the reason has expired, while the prose
defect would have shipped. This paragraph's own last sentence already said a later gate _"should
prefer counting by the constructor over counting by the phrase"_.

What is emitted now:

- the headline's **first line** always reads `` `f` is a field of … ``, from `onlyList`, which has
  a branch for every shape of `declaredBy` including the empty one. `L4.TypeCheck.s4Marker` is that
  literal, named in the source so a gate and the renderer cannot drift apart. It never had to carry
  meaning, so no future edit to how a sentence reads can break a count.
- the **connective** is `could also be` for every reason except `NarrowedByConstruction`, which gets
  `can only be` — the one reason under which no set-shrinking happened at all, because the base
  **is** that constructor syntactically (`connective`, `TypeCheck.hs:7053-7055`). The list this
  bullet used to spell out included `NarrowedByEarlierClauses`, which was deleted with the
  clause-column narrowing on 2026-09-13; the rule was rewritten as "every reason except one" so that
  adding or removing a reason cannot make it stale again.

Witnessed by `not-ok/tc/partial-projection.l4` case 5 and
`not-ok/tc/partial-projection-fallthrough.l4`'s constructed-base case; both goldens re-blessed in
the same change, and each moved by exactly one line.

**A THIRD DEFECT of the same kind, fixed in the same change: the fully exhausted residual.** When a
`CONSIDER`'s arms consume every constructor, the residual set is empty; an empty clamp would certify
every read below it, so the clamp is widened back to the whole type. That widening is sound — the
read is unreachable — but it was recorded by producing **no narrowing at all**, so S4 fell through
to `NotNarrowed` and said _"Nothing here narrows `a`: it is used at the whole type `Actor`"_ about a
read sitting under a fully exhaustive `CONSIDER`. That is the opposite of what happened, and §3.2
rules out exactly this: a diagnostic that explains the narrowing **wrongly** fails S4's acceptance
test as surely as one that does not explain it at all. `NarrowedByExhaustedBranches` now carries the
widening, the message names the arms that took everything, and the repair is to delete the
unreachable arm rather than to narrow anything. Witnessed by `not-ok/tc/partial-projection.l4`
case 7.

**S5 — what this does for `WHOSE`.** `EVERY-EACH-QUANTIFIER-SPEC.md` §13.6.1 found that the
corrected totality rule (open the fields present on every constructor the member could still be)
opened exactly the set that could not be read. Under S1 that set is a set of total, unambiguous
selectors; under S3 with a narrowing constructor it is that arm's fields. **The intersection rule is
therefore safe to open, and the condition is discharged: S1–S4 are built (§4.1, §4.2), so "once this
document is built" is now "now".** `WHOSE`'s check-time "naming the missing cast" promise is S2+S4
applied inside the filter — not a separate mechanism, and measured: `EVERY Landlord a …
a's monthly_rent` already renders it, pinned as case 8 of `not-ok/tc/partial-projection.l4`.

**`WHOSE` itself is still NOT built.** Discharging the condition removes the blocker S5 named; it
does not implement the feature. S5 remains DESIGN, exactly as the status header says.

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

**The table had a seventh row, "S3, clause order narrows a column / HIGHEST", from 2026-09-10 until
2026-09-13. It is GONE, not downgraded** — the rule it priced was cut (see the ruling below), and
leaving a priced row for a rule that does not exist is how a later reader concludes it does. Its
reasoning is worth keeping for whoever tries again: it was rated **above** the residual because it
was the residual's dependency **plus** one more — the `OTHERWISE` residual depends on the preceding
branches and their sub-patterns; this depended on all of that **and** on every other column of every
preceding clause. It is also worth stating that the row was missing for the whole time the rule was
shipping: the rule was built, promoted to an error, and repaired twice while §3.2 — the section
whose job is to price exactly this — did not know it existed.

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

#### THE RULING — Meng, 2026-09-13: the clause-order rule is CUT

> **A partial read in a later clause of a multi-clause rule is REFUSED outright. It is never
> narrowed by the clauses above it.** Always refuses, never dies at run time, one sentence to teach.

Built at `7ae280e5`. This is the first rule §3.2's test has actually cut, and the sentence above is
the whole of the language change: **§3 S3's clause-column bullet is struck, and the magic table's
seventh row is gone.**

**The cost Meng accepted, explicitly and with the program in front of him.**

```l4
DECLARE Solo IS ONE OF
    Freeholder
    Leaseholder HAS ground_rent IS A NUMBER

GIVEN z IS A Solo
GIVETH A NUMBER
DECIDE soloRent Freeholder IS 0
DECIDE soloRent z          IS z's ground_rent   -- REFUSED
```

`Freeholder` is the **only** other arm, so nothing but a `Leaseholder` can reach clause 2: the
program is provably total, and it checked and evaluated correctly before the ruling. It is refused
anyway. The drafter rewrites it as a `CONSIDER`, which does narrow, and the diagnostic spells that
out. Pinned as case 11 of `not-ok/tc/partial-projection-fallthrough.l4`, captioned so that a later
reader does not try to "fix" it.

The trade, in §3.2's own terms: a refusal teaches itself at the moment of failure, and **magic that
ACCEPTS is the expensive kind**, because when it is wrong nobody sees it. A rule that is right about
nine programs and silently fatal on the tenth costs more than a rule that refuses all ten and says
why.

**THE EVIDENCE LEDGER.** Three rounds of work on this one rule produced, cumulatively:

- **2 permissive holes that killed programs at run time.** (i) A **type synonym** on the column type
  — `DECLARE Person IS Actor` — defeated the head-taking, so a **typed** `GIVEN` fell back under the
  blanket suppression and the read died at run time; found and closed at `5ba5f94b`. (ii) A column
  whose type was an unresolved **inference variable** — an untyped `GIVEN`, or a group with no
  signature at all — could not be enumerated before the body was checked, so the read was suppressed;
  it lived under `ok/` as `sum-fields/partial-selector-runtime.l4` **precisely because it checked
  clean and then died**, and it was recorded as "not closable at proportionate cost".
- **1 hygiene hole.** `isSyntheticFallthrough` recognised the desugarer's reserved
  `` `__pm_fallthrough_k` `` name, and a drafter who wrote that name themselves — in backticks, which
  the lexer accepts and `L4.Print.quoteIfNeeded` emits — switched S2 off for their own body. The
  **unary** spelling was closed at `5ba5f94b`; the **nullary** spelling, which is the one the
  desugarer itself emits and therefore cannot be banned, was open the whole time and unstated.
- **4 false-positive refusals** — shapes where an earlier clause consumed nothing and the group was
  refused at the whole column type with no mention of the clause responsible: a literal in an
  earlier clause, an `EXACTLY`/expression pattern, a `FOLLOWED BY` cons pattern, and a refutable
  sub-pattern. A fifth, condition (c) — an earlier clause that is fine in its own column but tests
  some **other** column — is the one that would have generated the support questions, because the
  pattern the drafter is looking at is unimpeachable. Round 3 added another: it refused a group over
  an unenumerable don't-care column **while accepting the identical shape over a `BOOLEAN`**, and
  renaming the don't-care binder changed the answer.
- **2 diagnostics that stated the opposite of the truth.** The second is the one that decided it;
  see below. (The first was `NarrowedByExhaustedBranches`: a read under a fully exhaustive `CONSIDER`
  drew _"Nothing here narrows `a`"_ because the widened-back clamp was recorded as no narrowing at
  all. That one was repaired rather than cut — §3 S4's third defect — and the repair is what
  established the standard the clause rule was then measured against.)

**§3.2'S TEST IS WHAT DECIDED IT.** The requirement above is that the diagnostic must explain the
**narrowing**, and that _"if that sentence cannot be written for a rule, the rule is too clever and
is cut."_ Round 3 produced this, on a program whose clause 1 **demonstrably does** narrow the
column it is complaining about:

> `monthly_rent` is a field of `Renter` only.
> **Nothing here narrows `a`**: it is used at the whole type `Side`…

That is not a sentence that fails to explain the narrowing. It is a sentence that **denies a
narrowing the drafter can see three lines above the error** — the condition §3.2 names as grounds to
cut, and the same defect §3 S4 had already had to repair once. (This message was the round-3
binary's, and is quoted from the ledger put in front of Meng; the code that produced it is deleted,
so it cannot be re-measured. The 2026-09-10 instance below, which _can_ be re-derived from
`5ba5f94b`, is the milder version of the same failure.)

**WHAT A FUTURE IMPLEMENTER WOULD NEED.** Not a warning against trying — a list of what the three
rounds established is actually required, so a fourth does not rediscover it one defect at a time:

- **Resolved-`Unique` identity throughout, never raw names.** Every spelling comparison in this rule
  turned into a defect: `qualifiedAliases` registers a constructor's section-qualified `Name` under
  the **original's** `Unique`, so for anything declared inside a `§` the qualified spelling is the
  only one `entityInfo` holds — which is how an unqualified constructor pattern was mistaken for an
  irrefutable binding (case 15 of the fallthrough fixture).
- **Synonym expansion at the column type**, via the checker's own `rigidHeadOf` (which chases the
  substitution and expands with the argument substitution), not by matching `TyApp` on the
  substituted type.
- **A joint exhaustiveness test across sibling columns**, not a per-clause one. Condition (c) —
  every _other_ column of the earlier clause must match every value of its own column — is not an
  optimisation; without it the residual is unsound.
- **Sub-pattern irrefutability that understands sole-constructor records**, and that answers `False`
  for a nested constructor (`WHEN Tenant (Some n)`), which is what made `patternHasOpaque`
  unreusable here (§5 item 3).
- **The narrowing table built where column types are resolved.** The table must be in scope while
  the body it constrains is checked; resolving an untyped column requires the body to have been
  checked. Both directions are stated in the tree. Holding both means checking the body twice, and
  that is the shape of the real fix, not a smaller one.

And the bar, which is the part that is easy to miss: it is **not** "make it work on the common
case". It is **never permissive, and the diagnostic explains itself** — because a rule that accepts
wrongly has no error message in which to teach the lesson.

#### The clause-order rule against §3.2's own test — RUN 2026-09-10, and it half passes

~~This rule has now produced three defects in one repair round, so the test is applied to it rather
than assumed.~~ **SUPERSEDED 2026-09-13 by the ruling above — the rule is cut.** This subsection is
kept because it is the measurement that the ruling acted on, and because its own conclusion,
_"It is **not** cut today"_, is exactly the sentence that moved. Both messages below are the S4
renderer's actual output on this branch's binary at `5ba5f94b`; neither can be reproduced on today's
binary, which refuses both programs with the later-clause sentence instead.

**It PASSES in the accepting-then-refusing direction**, which is the one §3.2 says is expensive.
When the clauses above **do** consume something and a constructor still survives, the diagnostic
names both halves of the reasoning (`pr/multiclause.l4`):

> `monthly_rent` is a field of `Tenant` only.
> But `s` could also be `Agent`, which has no `monthly_rent`.
>
> The clauses above this one already match `Landlord`,
> so `Agent` is what is left to reach here.

That is exactly the sentence §3.2 demands: it explains the **narrowing**, not just the missing field.
It also now names the surviving constructor by its **unqualified** spelling even when the type is
declared inside a `§` (probe `res/r13`), which it did not before `5ba5f94b`.

**It FAILS when a clause consumes NOTHING, and that is the case a drafter will actually meet.**
Condition (c) is invisible in the output. Probe `pr/m3-sibling-tested.l4` —
`DECIDE f On Landlord IS 0` / `DECIDE f g a IS a's monthly_rent` — is refused with:

> `monthly_rent` is a field of `Tenant` only.
> But `a` could also be `Landlord`, which has no `monthly_rent`.
>
> Nothing here narrows `a`: it is used at the whole type `Actor`,
> so every constructor of `Actor` can reach this read.

"Nothing here narrows `a`" is **true** and **unhelpful**: it does not say that clause 1 would have
narrowed `a` had its `On` column been a plain binder, and the drafter who widens that one unrelated
column watches the error disappear for a reason the compiler never stated. That is §3.2's bad day
almost verbatim, one column over. The identical silence covers a literal or `EXACTLY` sub-pattern in
an earlier clause (probes `pr/m1`, `pr/m4`).

**The consequence, recorded rather than acted on.** Under §3.2's stated test the rule has NOT fully
earned its place, and the cut order below should carry it. ~~It is **not** cut today~~ — **it was
cut three days later; see the ruling above.** The reason given here for not cutting it was measured
rather than preferential: both cuts that were costed — restricting the rule to single-column groups,
and reverting it wholesale — turn `pr/m3-sibling-tested` and `pr/h3-section-2col-death` from a
correct refusal into a program that checks clean and dies at run time, i.e. each cut was strictly
**more permissive** than what was in the tree, which §3.2's own asymmetry ranks worst. What was owed
instead was a message: when a column's possible-set is unnarrowed **and** the enclosing declaration
is a fused clause group, S4 should say which earlier clause failed which condition.

**That message was attempted, in round 3, and is what produced the diagnostic that decided the
ruling.** The alternative the cut took was not on either list: delete the analysis without restoring
anything in its place.

Two consequences to carry:

- **Cut order, if teaching proves hard in practice.** Drop the `OTHERWISE` residual first (cost:
  `actus-core.l4:311` is rewritten as ``WHEN `ACTUS Other` s THEN s``, and drafters write one more
  branch); then the `WHEN`-narrows-scrutinee rule (cost: S2 becomes markedly more restrictive).
  Never S1 or S2 — they are the ruling.

  ~~**The clause-order rule is NOT first in this order, despite scoring HIGHEST above**~~ (added
  2026-09-10). ~~Cutting it does not restore the pre-rule behaviour; it restores a **blanket
  suppression** that accepts programs which die at run time (measured: `pr/m3-sibling-tested`,
  `pr/h3-section-2col-death`). A cut that trades a refusal for a death is not on this list.~~

  **ANSWERED 2026-09-13 by the shape of the cut that was taken, and the answer is the whole reason
  the ruling was available.** The central claim above — that cutting the rule restores a blanket
  suppression, so a cut trades a refusal for a death — assumed the only alternative to the analysis
  was the `Bool` that preceded it. It is not. **No suppression was restored.** The deletion alone
  does the refusing: with no narrowing installed on a column binder, the read falls through to the
  ordinary S2 clamp, which widens to the whole universe and defers a blocking `PartialProjection`.
  So the cut is strictly **more** restrictive than what it replaced, not less, and **both permissive
  holes closed as a side effect** rather than being separately repaired — which is also the answer
  to the "cut that _is_ available" sentence below, since that cut's stated benefit is the one this
  one delivered.

  ~~The cut that _is_ available, if the rule proves unteachable, is to keep the analysis and make S2
  **refuse** every column it could not enumerate instead of suppressing the read — restrictive,
  noisy, and it would close §5.1's remaining permissive holes. That has not been costed against the
  corpus.~~ Superseded: it was never costed, and the cut that landed makes it moot — there is no
  analysis left to keep and no column left to exempt.

  **Read this pair as a method note, not only as a record.** For three days the rule looked
  un-cuttable because both costed cuts were measured and both were worse. What had not been costed
  was the third option, which was not a smaller version of the rule but the absence of one; the
  measurement was sound and the option set was short.

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
`lsp/semantic-tokens/declare.l4:16-19`), **and a seventh copy of the same idiom found only when the
renames were made** — `doc/reference/types/for-all.md:58-59` quotes the block as a fenced `l4`
example, so the page and its example file had to be renamed together or they would have disagreed;
this list was built from `.l4` files and prose copies are invisible to that method. Two under `doc/`
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

### 4.1 The gate's measurement, RUN 2026-09-09

The gate's step 1 was run over all three rigs against the warning form of S2 (which no longer
exists — see the status header), with the worktree binary and `JL4_LIBRARY_PATH` pinned to this
tree's libraries. **Both the expected counts and the measured ones are recorded below**, per §4's own
instruction that the expectations were "to be confirmed, not assumed" — do not overwrite one with the
other.

> **The marker this run grepped for is no longer the marker.** Every `grep 'could also be'` recorded
> below is what was actually run on 2026-09-09 and stays as written. A gate run **after** that date
> must grep `L4.TypeCheck.s4Marker` — the literal `" a field of "` — because the connective now
> varies with the narrowing reason (§3 S4, ANSWERED 2026-09-09). Better still, count by the
> `PartialProjection` constructor and not by prose at all.

| site                                              | expected | measured | class                                   |
| ------------------------------------------------- | -------- | -------- | --------------------------------------- |
| `jl4/examples/legal/british-citizen-act.l4:94-97` | 4        | **4**    | (B) — the `p's birthPlace's val` chains |
| `jl4/examples/dmn/sumtype.l4:139-142`             | 1        | **1**    | (B) — ``disposal's `term in years` ``   |
| `jl4/experiments/safe-post.l4:258`                | 1 (or 2) | **1**    | (B) — `…'s security's Quantity's count` |
| (A) sites, anywhere                               | none     | **none** | S3's residual holds                     |

Everything else in the tree is silent: `ok/**`, `legal/**` apart from the one file, `not-ok/**`,
`lsp/**`, `jl4-core/libraries/*.l4`, all of `doc/`, and every backend example tree.

**Three things the measurement settled that reading could not.**

- **`actus-core.l4:311` does not fire.** §4 said "if it fires, the residual is wrong"; it does not,
  so the `OTHERWISE` residual works on its only demonstrated user.
- **`safe-post.l4` is ONE site, not two.** The open question in §4 was whether `:260`'s
  `…'s security's Instrument` is also partial. It is not. (`safe-post-tests.l4` reports the same
  `safe-post.l4:258` through its `IMPORT`; that is one site surfaced twice, not two sites.)
- **The two S1 fixtures were (A) sites until S3 was extended** to follow an alias chain into a
  constructor application (§3 S3). That is the gate's step 3 rule (A) working exactly as written —
  fix S3, not the corpus — and it is why the corpus was not "repaired" for something that was the
  checker's fault.

**Where the measurement contradicted §4's own description of the gate.** Recorded because §4's gate
text is what a later reader will follow, and two of its three rigs are not what it says they are.

- **§4's gate item 1 is WRONG about rig 3.** It says _"(3) `l4-cli-test`, which owns
  `jl4/examples/dmn/sumtype.l4`"_. It does not. `grep -n sumtype jl4/tests-cli/Main.hs` returns only
  `sumtypeGolden = "examples/dmn/expected/sumtype.dmn"` — the PRE-EMITTED artefact, never the `.l4`.
  The single leg that touches it is `pendingWith`-skipped without `L4_DMN_ENGINE_CHECK=1`. The `.l4`
  SOURCE is owned by **rig 1**, through `jl4/tests/DmnExport.hs`'s `goldenSubjects`. Worse, rig 3
  cannot count S2 sites at all: `l4-cli-test` prints a subprocess's output only when an assertion
  fails, so on a green run its log is empty and `grep 'could also be'` returns a **false zero**. Rig
  3's tree was measured instead by sweeping all 54 `jl4/tests-cli/fixtures/**/*.l4` with `l4 check`
  directly — zero markers. **Report the clean tree, not the zero.**
- **§4's rig-2 file list is not the complement of the golden globs.** Re-derived 2026-09-09 against
  **one named commit**, `0ea70d3f` — the commit the warning form existed on, and so the only tree
  the three-rig measurement could have run against. `git ls-tree -r --name-only 0ea70d3f` gives
  **960** tracked `.l4`. The **nine** golden globs of `jl4/tests/Main.hs` — including
  `not-ok/import/*-refused.l4`, which the repo `CLAUDE.md` §3.1 list omits — cover **464** (461
  without that glob). §4's rig-2 trees (`doc/`, the un-globbed part of `jl4/examples`,
  `jl4/experiments/`) cover **389**, leaving **107 tracked `.l4` in neither**
  (`jl4/tests-cli/fixtures` 54, `jl4-mlir` 21, `paper/` 17, `p4-design/scratch` 11, and **four**
  strays: `etc/m3-probes/distribution-probe.l4`, `jl4-proleg/l4/burden.l4`,
  `jl4/ok/inert/simple.l4`, `skills/writing-l4-rules/assets/example-parking.l4`). All 107 were
  swept — zero markers — and `464 + 389 + 107 = 960` with both `comm` directions empty, so every
  tracked `.l4` was measured exactly once.

  > **This bullet previously read 388 / 108 / "5 strays", which does not close.** Those numbers are
  > reachable only by moving exactly one of three files out of rig 2, and the text never said which;
  > its own breakdown then named five strays where only four files sit outside the listed trees. The
  > three genuinely ambiguous files are `jl4/examples/implicit-assume-test.l4` and the two
  > non-`-refused` files in `jl4/examples/not-ok/import/`, which are in no golden glob **by design**
  > (the refusal glob picks the importer out by name, and the library beside it is deliberately
  > un-globbed). All three are counted in rig 2 above. A later gate should sweep
  > `git ls-files '*.l4'` at a named commit rather than a hand-kept tree list.

- **Rig 1's `lsp` globs cannot carry a checker diagnostic either.** The 12 semantic-tokens and 1
  hover fixtures go through `SemanticTokens.hs`/`Hover.hs`, not `checkFile`, so their `.actual` can
  never hold an S2 message. All 13 were swept directly with `l4 check`: zero markers.

**The zero has stated bounds, and a later reader should quote them rather than the bare count.**
They are enumerated in §5.1, which is where they belong; this paragraph used to state a second bound
that appeared nowhere in §5.1, and used to call it one of "two … both in §5.1", which was wrong on
both counts. ~~The permissive exits from `checkPartialProjection` are: the **two** clause-column
holes of §5.1 item 1 — an untyped `GIVEN` column, and a hand-written nullary declaration spelled
with the desugarer's reserved fall-through name — the re-parsed-printer-output case (item 2), and
four silent bails …~~ **RE-STATED 2026-09-13.** After the cut the clause-column holes and the
printer-only case are all gone — each of them was an _exemption_ from S2 for a column, and there is
no exemption left to fall into. What remains is the **four** silent bails inside the check itself
(§5.1 item 3), none of them with a demonstrated user, and §5.1 records the sweep that found no
tracked `.l4` reaching a run-time partial selector at all. The measured six is still a lower bound
on the language's real exposure, but the gap between it and the truth is now the bails and nothing
else.

> **What this paragraph claimed, and when.** "the untyped-`GIVEN` clause column", singular, until
> 2026-09-10 — the same undercount as the status header's, and written while a **type synonym** on a
> column type was a further exit (closed at `5ba5f94b`). Then **two**, derived from
> `clauseColumnUniverse`'s conditions. Then, from 2026-09-13, **none of that kind**: the function
> those conditions came from is deleted. Three revisions of a count in four days is the reason §5.1
> now states a measurement rather than a derivation from a guard.

### 4.2 Gate steps 2 and 3, DONE 2026-09-09 — the repairs, the promotion, and what they cost

All six (B) sites are repaired, the three rigs re-measured to **zero**, and S2 promoted in the same
change. Promotion was exactly what §4.1 predicted: `PartialProjectionWarning` on `CheckWarning`
became `PartialProjection` on `CheckError`, `addWarning` became `addError` in
`flushPartialProjections`, and the renderer moved caller from `prettyCheckWarning` to
`prettyCheckError`. `severity`'s catch-all does the rest; `severity` and `viableCandidate` are
untouched, as §5 item 4 says they must be.

| file                                        | repair                                                                           | semantics                                                   |
| ------------------------------------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `legal/british-citizen-act.l4:94-97` (four) | `CONSIDER p's birthPlace` / `birthDate` with `WHEN Just …` and `OTHERWISE FALSE` | **CHANGES** — see below                                     |
| `dmn/sumtype.l4:142`                        | `CONSIDER disposal WHEN lease t THEN t OTHERWISE 0`                              | **CHANGES** — see below                                     |
| `experiments/safe-post.l4:258`              | `CONSIDER …'s security's Quantity WHEN Shares count price THEN count / …`        | nominally changes, observably does not (`l4 run` identical) |

**Two consequences a reviewer accepts on purpose, both ruled in §4 before the work started.**

- **`british-citizen-act.l4` now answers `FALSE` where it crashed.** A `NaturalPerson` whose
  `birthPlace` or `birthDate` is `Nothing` used to reach the desugared one-branch `CONSIDER` and die
  at run time with §1.1's message. It now yields `FALSE`, which is also what the statute means: a
  person whose birthplace is not recorded is not shown to have been born in the UK. Blast radius is
  nil beyond that — all four `DECIDE`s are declared and never read in the file, and the file's two
  `#EVAL`s still return `TRUE` / `TRUE` (measured).
- **`sumtype.l4` loses its D-PARTIAL finding, and R4-a's example is unreachable by construction.**
  Measured with `l4 export --to dmn --fidelity-report`: blocking findings 3 → 2,
  `[D-PARTIAL] blocking — decision_stated_term` gone, `D-SUMTYPE` blocking retained, lossy 8 and
  advisory 9 unchanged. `jl4/tests/DmnExport.hs`'s `decision_stated_term` assertion is updated to
  `[("D-SUMTYPE", Blocking)]` with that reasoning written beside it, and all four `expected/sumtype.*`
  goldens are re-blessed. D-PARTIAL keeps its coverage: `deontic-verdict`, `svc` and `regcf-corpus`
  carry it, and its own `describe` block still runs.

**The MustFail expectation: it does NOT flip, and that was MEASURED, not reasoned about.** §4 ruled
_"let the MustFail expectation change if the model then builds"_. It does not build — the fallback
`<text>` is still raw L4 — so `jl4/tests-cli/Main.hs`'s KIE leg stays `HarnessMustFail`. What
changed is the CAUSE STRING, and it was re-measured by running `etc/kie-dmn-check/run.sh` on the
regenerated `sumtype.dmn` (KIE 8.44.0.Final): the leg's
`Unknown variable 'disposal.term_in_years'` becomes
`Error compiling FEEL expression 'CONSIDER disposal WHEN lease t THEN t OTHERWISE 0' … syntax error
near 'disposal'`, with `ERR_COMPILING_FEEL`, `decision_stated_term_literal`, `XSD valid`,
`TYPE_DEF_NOT_FOUND`/`Grade_optional` and `<<< FAILED` all unchanged.

**One thing the promotion broke that §4 did not predict, and it is not a corpus site.**
`jl4/tests/DmnExport.hs`'s _"L11: refuses a projection over a multi-constructor enum missing the
field"_ built its DRG from an inline `` `the radius` s MEANS s's radius ``, and its own comment said
_"`l4 check` says 'Check succeeded' on the rejecting shape"_. Under S2 it does not, so `drgGeneral`'s
`error "source failed to typecheck"` threw instead of the test running. **L11 is not thereby dead
code**, and the replacement fixture is what proves it: the same hazard is still reachable through
§5.1's hole 1 —

```l4
DECLARE Shape IS ONE OF
    Nothingness
    Circle HAS radius IS A NUMBER
GIVEN s IS A Shape
GIVETH A NUMBER
DECIDE `the radius` Nothingness IS 0
DECIDE `the radius` s           IS s's radius
```

— which checks clean, still raises `NonExhaustivePatterns`, and still draws L11's `D-PARTIAL`
(measured). The fixture is now that program, with the reasoning beside it. **This is the first
demonstrated user of §5.1's hole 1**, and it is worth more than the old fixture was: it exhibits the
hole rather than describing it.

> **CORRECTED 2026-09-09, after `655b272b` closed hole 1.** Two of the three claims in the paragraph
> above are now false, and the third is true for a different reason. The program still **checks
> clean** — but not because S2 records nothing inside a fall-through. It checks clean because the
> clause narrowing is now real and _correct_: clause 1 consumes `Nothingness`, so `s` in clause 2 is
> narrowed to `Circle`, and `Circle` **does** declare `radius`. The read is total, so there is
> nothing for S2 to refuse. Measured: `#EVAL` returns `0` and `7`, and **no `NonExhaustivePatterns`
> is raised at all** — the program has no run-time death left in it. It is therefore **not** a
> demonstrated user of hole 1, or of any hole; hole 1 as written no longer exists, and its surviving
> residual needs an **untyped** `GIVEN` column, which this fixture does not have.
>
> L11 is still not dead code, and this fixture still earns its place — the exporter's `D-PARTIAL`
> note is drawn off the IR shape, independently of whether the checker refuses the source, which is
> exactly why the test remains green. But it now demonstrates the exporter's analysis, not a hole in
> S2. ~~The file that demonstrates the surviving hole is
> `ok/sum-fields/partial-selector-runtime.l4`.~~ That file is deleted; there is no surviving hole
> for it to demonstrate (2026-09-13).

> **CORRECTED AGAIN 2026-09-13, and the fixture moved a second time.** The two-clause program above
> no longer type-checks — §3.2's ruling cut the clause narrowing, so clause 2's read is refused
> outright — and `drgGeneral` would throw on it exactly as it did on the pre-S2 source. **The
> rewrite is NOT the `CONSIDER` the refusal recommends**, and the reason constrains every future
> one: `walkIssues` visits every branch body at `LazyPos` (`Dmn/Analysis.hs:517-525` — the
> `IfThenElse`, `MultiWayIf` and `Consider` arms) and L11 is gated on `StrictPos`, so a read narrowed
> by a `WHEN`, an `OTHERWISE`, an `IF` or a multi-way guard draws no note at all — measured, the note
> list came back empty. A `Where` body is the exception that makes the new fixture possible: it is
> walked at the enclosing strictness (`:526`). **Every narrowing form a branch supplies
> puts the read in a lazy position by construction, so no branch-narrowed program can witness L11.**
>
> What is left is the one narrowing that is not a branch: a base written **as** a constructor.
> The fixture is now `` `the radius` MEANS unit's radius WHERE unit MEANS Circle OF 7 ``, which
> checks clean and evaluates `7` (measured 2026-09-13 on the worktree binary at `7ae280e5`). It is a
> **better** witness of what the note is about, not a weaker one: D-PARTIAL over-approximates by
> design, and here it over-approximates visibly — the read provably cannot raise and the note fires
> anyway. It is also the **only** shape left, which is the part a future editor needs: any rewrite
> must keep a `Proj` over such an enum in a STRICT position, and keeping the file merely
> type-checking is not enough.

### 4.3 The fixtures S2, S3 and S4 ship with

- **`ok/sum-fields/narrowing.l4`** — the four narrowing paths, each ARMED. The quantifier's
  narrowing constructor is the one §4 said had **zero** coverage anywhere in the tree, so this is
  that path's only test; the other three are a `WHEN` scrutinee, an `OTHERWISE` residual, and an
  alias, plus an alias chain ending at a construction. `#TRACE` returns `FULFILLED`; the `#EVAL`s
  return 1500 or 0 on the arm they should, except the last pair of the alias chain, which reads 1500
  off `alice` and **4000** off `theLandlord`'s own `deposit` (`narrowing.l4:95`,
  `tests/narrowing.golden:21`). The nine armed values are `FULFILLED`, then 1500, 0, 1500, 0, 1500,
  0, 1500, 4000. (This bullet used to say "every `#EVAL` returns 1500 or 0", which the golden
  contradicts.)
- **`not-ok/tc/partial-projection.l4`** — **eight** sites, ONE PER SHAPE the S4 renderer can produce:
  un-narrowed binder, the refutable-arm residual (whose message names `` `WHEN Tenant 1500` `` — §3.2's
  hard requirement, and the acceptance test for the highest-magic rule), narrowed to the wrong arm by
  a `WHEN`, a non-binder base, a value written as a constructor, the bare selector as a value, the
  fully exhausted residual (`NarrowedByExhaustedBranches`), and — added 2026-09-09 — narrowed to the
  wrong arm by a **quantifier** (`NarrowedByCast`). The renderer branches on `NarrowingReason` and
  `NotNarrowed` splits three further ways on the base's shape, so eight is the full enumeration;
  the ninth reason is pinned next door in `not-ok/tc/partial-projection-fallthrough.l4` because it
  needs a clause group to exist at all. `NarrowedByCast` had **no witness anywhere in the tree**
  before case 8, which is the same zero coverage §4 records for the quantifier-narrowed projection.

  > **The ninth reason changed name and kind on 2026-09-13.** It was `NarrowedByEarlierClauses`, a
  > narrowing — a set of constructors the clauses above had consumed. It is now
  > `NotNarrowedInLaterClause`, which is a **reason without a narrowing**: it is never stored in a
  > `Narrowing` and never shrinks a set, it only replaces `NotNarrowed`'s sentence when the read sits
  > in a later clause. Anything reasoning from the old name is reasoning about a mechanism that is
  > gone.

- **`not-ok/tc/partial-projection-fallthrough.l4`** — **fifteen** cases, and after 2026-09-13 it has
  no green counterpart: `ok/sum-fields/fallthrough.l4` demonstrated the clause narrowing working and
  was deleted with it. Cases 10–14 are the ones the ruling decided, and each is captioned with what
  it was before: the column-name wildcard spelling; **case 11, the accepted cost** (a two-constructor
  type where clause 1 takes the only other arm — provably total, refused anyway, marked DO NOT
  "FIX"); **case 12**, the untyped-`GIVEN` column that used to check clean and die at run time, which
  is where `ok/sum-fields/partial-selector-runtime.l4` went; **case 13**, round 3's false-positive
  refusal over an unenumerable don't-care column, now refused for the honest reason; and a
  three-clause group so the read sits two fall-throughs deep. Case 15 is the sectioned sub-pattern
  and stays last because a `§` heading is open-ended.
- **`not-ok/tc/partial-projection-overload.l4`** — the overload trap of §5 item 4, pinned by CONTENT
  and not merely by redness: two unrelated types both declare `rent`, and the golden holds S2's
  message rather than `AmbiguousTermError` or `InternalAmbiguityError`. If the deferral is ever
  undone, this is the golden that says so.
- **`doc/reference/types/partial-field-example.l4`** — the drafter-facing example, linked from
  `doc/reference/types/DECLARE.md`'s new "A field on only some constructors" section (CLAUDE.md §6).
  That section replaced a bullet which said the partial read _"fails when the program runs, not when
  it is checked"_ — true when it was written and false the moment S2 landed.

## 5. Implementation sketch — what the first reader of the code should verify, not follow blindly

This is where the work is expected to land; the implementer re-checks each anchor.

> **EVERY LIVE ANCHOR IN §5 AND §5.1 WAS RE-MEASURED ON 2026-09-14 AGAINST `7ae280e5`** — the cut
> commit, which is also `lang/whose-opening`'s HEAD as this was written. The cut removed 523 lines
> from `TypeCheck.hs` and 87 from `TypeCheck/Types.hs`, so **every anchor into those two files
> moved**; `EvaluateLazy/Machine.hs`, `Evaluate/ValueLazy.hs`, `Desugar.hs`, `Dmn/Lower.hs`,
> `Docassemble/Lower.hs` and `TypeCheck/Unify.hs` were not touched by it, and their anchors were
> re-verified line by line rather than argued from that fact. Anchors are given as `file:line` for a
> definition's first line.
>
> Three earlier rounds each re-measured _some_ of them and left the rest: `c26496cd` added 91 lines
> to `EvaluateLazy/Machine.hs` and invalidated item 2's three; `ea06a1ce` re-measured item 1 and left
> item 2 wrong, plus two more inside the sentence it was editing; the 2026-09-10 pass re-measured §5
> and left §3's `columnConstructor` anchor stale. **A fourth did it again on 2026-09-13**, this
> time inside the very pass whose subject was the re-measurement: it repointed §5 item 3's and item
> 4's `TypeCheck.hs` anchors and left `data PartialProjection` at `:906` in item 4's own paragraph
> — an anchor that had been correct at `89f07544` and that the cut moved to `:913`. **A partial
> re-measurement is worse than none**, because the ones it fixed vouch for the ones it did not. If
> you re-measure, re-measure the section — and say which commit you measured at, as this note does.
>
> Anchors that are explicitly labelled _pre-S1_ below are **not** re-measured: they are struck text
> kept as evidence that a claim moved, and pointing them at today's tree would erase that. The same
> goes for anchors into code the 2026-09-13 cut DELETED: they are marked as such rather than
> repointed, because there is nothing to repoint them at.

1. **Selector generation** (`inferConDecl` `:1530-1553`, `inferSelector` `:1599-1616`). Group a
   type's fields by name across all its constructors before minting selectors. One group → one
   `Resolved` selector, one `CheckInfo`, one `KnownTerm … Selector` of type `T → fieldT`. A group
   whose members disagree on type → S1's declaration error. `ensureDistinct NonDistinctSelectors`
   stays per-constructor (a constructor still may not declare one name twice).
   **Corrected:** the grouping cannot live in `inferConDecl` — only `inferTypeDecl`'s `EnumDecl`
   arm (`:1448-1453`) holds all the constructors, and field types must be resolved across arms
   before any selector is minted. Later arms get `defAka` (same `Unique`, their own name and range).
   **BUILT 2026-09-09** as `inferConDecls` (`TypeCheck.hs:1705`, with Note [One selector per
   shared field] at `:1645` and `data FieldOccurrence` at `:1691`), which both the `EnumDecl`
   arm of `inferTypeDecl` (`:1549`, calling at `:1554`) and the `RecordDecl` arm (via
   `inferConDecl` `:1634`, calling at `:1636`, the one-arm case) go
   through; `inferSelector` is gone. The error is `SharedFieldTypeMismatch Name [(Name, Name, Type'
Resolved)]` (`TypeCheck/Types.hs:143`, `rangeOf` `:531` anchored on the first occurrence — both
   still correct),
   raised inside the existing `WhileCheckingDeclare`
   context; on disagreement the group falls back to today's per-arm selectors, so a read of the
   disputed field in the same file gets today's ambiguity rather than a cascade. One limit,
   measured while building: "the same type" is `typeKey` on the field type
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
   fields are stored **positionally** — `ValConstructor Resolved [a]`,
   `jl4-core/src/L4/Evaluate/ValueLazy.hs:83`, still the line it was — and two arms may place the
   field differently. **S1's checker and evaluator halves must land in one commit**, and the guard is
   a probe with the shared field at index 1 on one arm and 0 on the other. **BUILT 2026-09-09** as
   `evalConDecls` (`jl4-core/src/L4/EvaluateLazy/Machine.hs:4267-4322`; the `:4207-4231`/`:4230`
   anchors above are the pre-S1 tree, and `updateTerm` is `:4215`): one closure per selector
   `Unique`, its body a `CONSIDER`
   with one branch per declaring constructor, each carrying that constructor's own arity and that
   field's index; `scanTypeDecl` (`:4049-4056`) dedupes by `Unique` (`nubOrdOn getUnique`) so
   `preAllocate` allocates one
   cell. The guard is `ok/sum-fields/shared-field.l4`, whose `Landlord HAS addr, name` /
   `Tenant HAS name, rent` reads both arms, positionally and through `WITH`, and through a
   `GIVEN a IS AN Actor` reader. Cosmetic only: the closure's lambda argument is named after the
   FIRST declaring constructor, as the one-arm code named it; nothing prints it.
   (**Every anchor in this item re-verified UNCHANGED at `7ae280e5`**: the 2026-09-13 cut touched
   `TypeCheck.hs` and `TypeCheck/Types.hs` only, and nothing in the evaluator.)
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

   **BUILT 2026-09-09 (`92e12d27`). Five corrections to the paragraph above, all measured while
   building — every line number in it is pre-S1 and none of them survives.** ~~As of this commit:
   `data CheckEnv` is `Types.hs:905-1010`, `localBindings` is `:965`, and the new
   `narrowings :: !(Map Unique Narrowing)` is `:975`.~~ **Re-measured 2026-09-10**, because the
   `92e12d27` numbers had themselves gone stale and this paragraph is the one a reader trusts:
   ~~`data CheckEnv` is `TypeCheck/Types.hs:927-1093`, `localBindings` is `:987`, and
   `narrowings :: !(Map Unique Narrowing)` is `:997`~~ — **re-measured 2026-09-13 at `7ae280e5`:**
   `data CheckEnv` is `TypeCheck/Types.hs:934-1054`, `localBindings` is `:994`, and
   `narrowings :: !(Map Unique Narrowing)` is `:1004` — appended LAST, deliberately, see the next
   point. ~~the three fields the clause-order rule added since (`clauseNarrowings`,
   `clauseSuppressColumns`, `fallthroughColumns`, `fallthroughUnanalysed`)~~ **All four of those are
   DELETED** with the clause-column narrowing (2026-09-13); the field that now sits last is
   `inLaterClause :: !Bool` (`:1028`), which is diagnostic-only.
   `checkDeonton` is `TypeCheck.hs:2129` (its equation `:2133`), its member binding `:2214`, the
   narrowing constructor built at `:2210-2213` from the cast resolved at `:2150`, and stored in the
   AST at `:2232`. **"the narrowing constructor resolved 45 lines above" no longer survives** — it is
   60 lines above, and the arithmetic was never the point; the ordering is. `checkBranch` is `:4395`
   (its `When` equation `:4399`), `checkConsider` is `:3090`.

   - **"four construction sites" is wrong: there are four record CONSTRUCTIONS and a FIFTH
     occurrence.** `TypeCheck.hs:372-373` is a POSITIONAL pattern over every field of `CheckEnv`, whose
     own comment explains why (a duplicated field name makes a record update ambiguous under
     `DuplicateRecordFields`). It fails with a constructor-arity error, not `-Wmissing-fields`, so it
     is the one site the warning machinery does not point you at — and if the new field is added
     anywhere but LAST, that pattern silently binds the wrong fields to the wrong letters and still
     compiles.
   - **§3 S3's "the residual must reuse `patternHasOpaque`" is UNSOUND and was not built.**
     `patternHasOpaque` recurses through sub-patterns and answers `False` for
     `WHEN Tenant (Some n)` — which is one of the three shapes §3 S3 itself names as MUST-NOT-CONSUME.
     Reusing it would have left the residual wrong in the PERMISSIVE (invisible) direction, the exact
     failure the sub-rule exists to prevent. What is built instead is `armEffect`
     (`TypeCheck.hs:2983`, over `data ArmEffect` at `:2944`), which tests irrefutability directly —
     every sub-pattern a plain variable — rather than testing for the absence of two opaque shapes.
     `patternHasOpaque` (`:3747`) is UNCHANGED: it answers a different question, and `checkConsider`
     and `checkClauseMatrix` depend on its current answer. The two disagreeing is correct.
     `armEffect` survived the 2026-09-13 cut with all four of its call sites (`:3058`, `:4419`,
     `:4466`, and its own Haddock cross-reference at `:3099`): it is the `WHEN`-arm irrefutability
     test, which the `OTHERWISE` residual still needs. What the cut removed at `:4419` is the second
     half of that call's result — a column alias the clause rule fed on; the `catchAllExtra` half is
     an ordinary S3 alias fact and is unchanged.
   - **A bare identifier does NOT parse as `Var`.** `atomicExpr'` produces `App ann n []` and nothing
     normalises it later; `Var` is a pattern synonym for exactly that shape, and is otherwise emitted
     only by the computed-field rewrite and the clause-matrix fallthrough. A base test written as
     `case e of Var _ r -> …` compiles, type-checks and NEVER FIRES — S3 would silently do nothing
     and S2 would then refuse every drafter-written projection. `classifyBase` (`:2647`) matches both
     shapes, and consults `entityInfo` rather than the syntax, which is what gives §3 S3's
     "a nullary constructor is statically that constructor" exception for free.
   - **The alias rule needed no new state.** `constBodies` already holds every nullary `MEANS` body,
     including local `WHERE`/`LET` ones, and `checkExpr`'s `Where` case runs `inferLocalDecl` before
     the body — so resolving the chain AT THE READ (`lookupNarrowing`, `:2720`) is both possible and,
     per §3 S3, required: it is what makes an alias bound outside a `CONSIDER` and read inside two
     branches see each branch's own narrowing.

4. **Totality at the projection.** ~~`inferRecordProjection` is `:3125-3152` (`:3047-3072` is the
   `Proj` dispatcher); the insertion point is after `matchFunTy` (`:3137`).~~ Those anchors are
   pre-S1. The selector's declaring constructors need **no new state**: each constructor's
   `KnownTerm conType Constructor` already names its selectors' own `Def`s as the argument names,
   and `constructorsInScopeFromEntityInfo` (`:2514`) enumerates a type's constructors — both
   confirmed while
   building. **BUILT 2026-09-09** (`checkPartialProjection`, `TypeCheck.hs:2852`, its equation
   `:2862`, under Note [S2: no projection without narrowing] at `:2752`; drained by
   `flushPartialProjections` `:2935` from `inferTopDecl` `:903`, called at `:906`; rendered by
   `prettyPartialProjection` `:7016`) — as a warning in
   `0ea70d3f` for the length of §4's gate step 1, then **promoted to a `CheckError` in the same
   change as the six repairs** (§4.2). With **four** insertion points, not one, because §3
   S2's second ruling covers three forms: `inferRecordProjection` (`a's f`), the `Proj` dispatcher's
   qualified-name branch (`` `Section`.f ``), `inferExpr`'s **`Var`** case (a bare selector as a
   value), and `inferFlatApp`'s `directApp`/`variadicRescue` (`f a`). The bare form lands in the
   `Var` case and not in `inferFlatApp`: a bare identifier parses as `App ann n []`, `Var` is a
   pattern synonym for exactly that, and the `Var` arm sits above the `App` arm.
   The four call sites, re-measured 2026-09-13 at `7ae280e5`: `TypeCheck.hs:2924` (the `f a`
   application, via `checkAppliedSelector`, `inferFlatApp`'s shared helper), `:3859` (the `Proj`
   dispatcher's section-qualified branch, a selector VALUE with no base), `:3944`
   (`inferRecordProjection`) and `:3956` (`inferExpr`'s `Var` case, a bare selector as a value).
   (The 2026-09-10 numbers `:3328`/`:4263`/`:4348`/`:4360` listed the same four sites in a different
   order and named two of them wrongly; the order above is the order they appear in the file.)

   The denominator is the **selector's own domain type head**, not the base's inferred type, which
   makes the whole check substitution-independent and removes the accuracy-versus-timing tension
   §3 S3's sketch has.

   ~~One trap: the S2 error is raised inside a forked overload branch, so without an exemption in
   `viableCandidate` (`Types.hs:466-469`) the branch merely fails and `prune` reports
   `AmbiguousTermError` instead of S4 whenever two **types** share the field name.~~
   **The trap is real; the proposed fix is REPLACED, 2026-09-09.** An exemption in
   `viableCandidate` contradicts `severity`'s documented claim to be "THE canonical severity
   mapping — the one place that decides what blocks", and it keeps a candidate carrying a blocking
   diagnostic _viable_, which `prune` then has to arbitrate — two viable candidates collapse to
   `InternalAmbiguityError`, the same ambiguity-instead-of-S4 outcome moved one step later.

   (`viableCandidate`'s pre-S1 anchor `Types.hs:466-469` is struck text; the function is
   `TypeCheck/Types.hs:510` today.)

   **What is built instead is deferral**, which needs no change to `severity` and none to
   `viableCandidate`. The obligation is parked on a new `CheckState.pendingPartialProjections`
   (`TypeCheck/Types.hs:98`; the `CheckError` constructor `PartialProjection` is `:149` and the
   payload record `data PartialProjection` is `:913` — **it read `:906` until 2026-09-14, which was
   correct at `89f07544` and was moved by the cut; §5's re-measurement note below covers §5 and §5.1,
   and this anchor sits in §5 item 4, so it was in scope and was missed**) and
   drained by `inferTopDecl`, which is the first point above every fork: `Check` returns a list of
   `(result, state)` pairs and `prune` returns exactly one, so the state that continues is the
   winning candidate's — its obligations survive and every loser's are discarded, by the same
   mechanism that already carries `constBodies` out of a fork. The obligation is therefore
   **self-contained**: every name and every list is resolved at the read, because `entityInfo` is
   scoped by `local` and a type `DECLARE`d inside a `WHERE` is out of scope by flush time.
   Measured: two types both declaring `rent`, read at one of them, produces S4's message and not
   `AmbiguousTermError`. **PINNED 2026-09-09** by
   `not-ok/tc/partial-projection-overload.l4`, whose golden holds that message — the fixture asserts
   the CONTENT, not merely that the file is red, because `AmbiguousTermError` would keep it red.

   **One scope limit worth stating so the next reader does not re-derive it, verified not assumed:**
   a COMPUTED field (`MEANS` inside a `DECLARE`) is excluded from S2, and that is sound rather than a
   hole. `desugarCFDeclare` (`L4/Desugar.hs:270-280`, unmoved) pattern-matches `RecordDecl` and never
   `EnumDecl`, so a computed field can only ever be declared on a single-constructor record and can
   never be partial.

5. **Evaluator.** ~~needs no change if the merged selector's body is total over its arms.~~
   **Backwards — nothing makes it total.** See item 2.
6. **Consumers.** ~~sees one selector where it saw N.~~ **Backwards for almost all of them:** the
   schema, NLG and transpiler consumers read the AST's `ConDecl` field lists by name **text** and
   are unaffected. Exactly two `Unique`-keyed consumers change — the evaluator environment, and
   DMN's `selectorNames`/`fieldScopes` (`Dmn/Lower.hs:3990-3995` and `:4017`), which must be deduped by
   `Unique` or a merged field's FEEL step becomes `name_2` — **BUILT 2026-09-09**, `nubOrdOn
getUnique` on the `EnumDecl` case. Hover and `@desc` are range-keyed and
   survive `defAka`; find-references improves; completion goes from two byte-identical items to one.
   Docassemble **already refuses** the S1-merged shape with a CI-pinned message
   (`checkNameCollisions`, `Docassemble/Lower.hs:2320-2368`, its `Why` note at `:2305-2319`) — under S1 those are one field, so that refusal must be
   reworded as an exporter limit or lowered to one question (§6 item 4).
7. **Goldens and docs.** New `ok/` fixtures for S1 (shared field read on both arms, armed and
   traced) and S3 (narrowed projection); new `not-ok/tc/` fixtures for S1's type-disagreement error
   and S2's partial-projection error with S4's message; the `.l4` and its four goldens in one
   commit, read before blessing, grepped for absolute paths. A `doc/` page or section — audience:
   a drafter who has never read this file — saying what a field on several arms means and why a
   projection can be refused. **S1's share BUILT 2026-09-09:** `ok/sum-fields/shared-field.l4`
   (the same field name and type on two arms at different positions; `#EVAL`s on both arms,
   positionally and via `WITH`; `name` as a bare function and under `map`; a
   `GIVEN a IS AN Actor` reader doing `a's name`; §1.2's quantifier program under `#TRACE`,
   `FULFILLED` twice — the second trace's filter reads every member and nobody passes) and
   `not-ok/tc/sum-field-type-conflict.l4` (`name` STRING/NUMBER across Landlord/Tenant, refused;
   `addr` STRING on Landlord and Agent, merged and read on both without a diagnostic — the
   `.golden` holds the declaration error and nothing else). The `ok/` file is also the only witness
   the `prettyLayout round-trip` property has for a merged field. Docs: the "A field on several
   constructors" section of `doc/reference/types/DECLARE.md` and its linked
   `shared-field-example.l4`.

   **S2's, S3's and S4's share BUILT 2026-09-09** — the three corpus fixtures and their twelve
   goldens are listed in §4.2's own subsection, and the drafter-facing half is
   `doc/reference/types/DECLARE.md`'s new "A field on only some constructors" section plus
   `doc/reference/types/partial-field-example.l4` (`doc/test-docs.sh`: 102 L4 files valid, 1469
   links, 0 orphans). That section also **retracted** a sentence the S1 docs left behind — the old
   second bullet said a partial read _"fails when the program runs, not when it is checked"_, which
   S2 made false; the section now states the ways to narrow AND, per CLAUDE.md §6's "state the
   limits", the shapes that are NOT narrowed (a `GIVEN` parameter, a non-binder base, a
   refutable `WHEN` arm, an alias that names something other than a binder).

   **REVISED 2026-09-14 for §3.2's ruling.** The section listed **five** ways to narrow, the fifth
   being clause order; it now lists **four**, and the clause-order material is rewritten as the
   headline case of what does _not_ narrow, with the refusal, its message and a `CONSIDER` repair
   that was compiled and run. Three claims went with it, all now false and all deleted: that clause
   order "narrows only as far as it truly can"; that a clause consumes a case only when its other
   columns accept anything; and that an untyped `GIVEN` is accepted and can die at run time. The
   reserved-name paragraph shrank to one sentence — the name is still reserved, but writing it no
   longer switches the check off. `doc/reference/errors/README.md`'s runtime entry and
   `partial-field-example.l4`'s header carried the same two "not checked" claims and were corrected
   in the same change.

### 5.1 What S2 does not guarantee — no demonstrated permissive hole, four silent bails, two restrictive limits

Only a **permissive** gap lets the run-time death of §1.1 through. None is a reason not to promote;
all are reasons to say so out loud, because §3.2's asymmetry cuts the other way for a rule that
_fails to reject_: there is no error message to teach the lesson.

> **RE-MEASURED 2026-09-14, against a binary built from `lang/whose-opening` at the cut commit
> `7ae280e5`, with `JL4_LIBRARY_PATH` pinned to this worktree's `jl4-core/libraries`.** The count
> this section carries has been wrong three times in five days — **one** permissive hole until
> 2026-09-10 (reasoned from a single probe), **two** from 2026-09-10 (derived from
> `clauseColumnUniverse`'s conditions), with a **type synonym** on the column type having been a
> third that `5ba5f94b` closed. Every one of those counts was derived from a function's guard. That
> function is deleted, so this revision **derives nothing**: it states two sweeps and a probe
> battery, says what each measured, and says where reasoning takes over from measurement. The
> heading, the status header, §4.1 and the three neighbouring documents that repeated the old count
> are corrected in the same change.

#### The measurement, stated before the list it supports

**Sweep 1 — who does S2 refuse?** `l4 check` over all **965** tracked `.l4` files. 129 are red, all
of them for reasons that predate this work (`not-ok/` fixtures, `experiments/`, deliberately broken
CLI fixtures). Re-reading each red file's diagnostics for `s4Marker` (`" a field of "`,
`TypeCheck.hs:6972`, which every S4 headline carries) gives the number that matters: **exactly
three** files in the corpus are refused by S2, and all three are the `not-ok/tc/` fixtures written to
be refused by it — `partial-projection.l4`, `partial-projection-fallthrough.l4`,
`partial-projection-overload.l4`. **No `ok/`, `legal/`, `doc/` or library file is refused by S2 at
all.** This is stated in preference to a before/after diff because it needs no second binary and is
the stronger property: the cut cost the corpus nothing beyond the two fixtures it deleted (§4.3).

**Sweep 2 — does anything that checks still die?** `l4 run` over every one of those 836 files that
`l4 check` accepts, grepping the output for the run-time partial-selector message
(``has no `<field>` field.``, the exact line `EvaluateLazy/Exceptions.hs:166` emits). **Zero
hits.** The grep pattern was validated against the deleted
`ok/sum-fields/tests/partial-selector-runtime.golden`, which contains that line, so the zero is a
measurement and not a pattern that never matched anything.

**One thing to know before you widen that grep, because the obvious widening is not a counterexample.**
Sweep 2's pattern is deliberately the partial-selector message alone. Widening it to include the
other run-time match failure — `reached a CONSIDER that has no branch for it` — returns exactly
one file, `jl4/tests-cli/fixtures/eval-crash.l4`, and that file is **supposed** to do this: it is a
hand-written `CONSIDER` over `MAYBE NUMBER` with no `NOTHING` branch, `@nonexhaustive`-annotated so
the oracle's warning does not fail the run, and it exists to pin the rule (Meng, 2026-08-01) that a
crashed `#EVAL` exits non-zero. It is a drafter's own non-exhaustive match, not a partial selector,
and S2 has nothing to say about it. Confirmed by the independent re-sweep of 2026-09-14, whose
965/836/129 file counts match this section's exactly.

**A probe battery beyond the corpus**, so the zero is not an artefact of what this tree happens to
contain. Every one of these is refused at check time (`l4 check` exit 1), measured 2026-09-14:

| probe                                                          | why it was tried                                                                               |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| untyped `GIVEN` column of a two-clause group                   | this was hole (a); see item 1                                                                  |
| the same group with **no signature at all**                    | the condition is "un-narrowed", not "untyped" — see item 1                                     |
| `` `__pm_fallthrough_0` `` written by the drafter, nullary     | this was hole (b); see item 1                                                                  |
| a type synonym on the column type (`DECLARE Person IS Actor`)  | the hole `5ba5f94b` closed, re-checked after the deletion                                      |
| the two-arm group where clause 1 takes the **only** other arm  | §3.2's accepted cost — refused, deliberately                                                   |
| `ASSUME who IS AN Actor` then `who's monthly_rent`             | an uninterpreted term is still a value at a whole type                                         |
| a lambda read, `map (GIVEN x YIELD x's monthly_rent) everyone` | no clause group, no branch, no binder to narrow                                                |
| a bare selector as a value, `map monthly_rent everyone`        | S2 form 3, which has no base at all                                                            |
| a function-application base, `(idA s)'s monthly_rent`          | a base that is not a bare binder                                                               |
| a `MAYBE` payload binder, `WHEN JUST v THEN v's monthly_rent`  | narrowing through a nested constructor                                                         |
| a **polymorphic** enum, `Box a IS ONE OF Empty / Full HAS it`  | the one shape where the selector's domain is a `TyApp` with a variable argument — see bail (b) |
| a constructor declared inside a `§`                            | the hole that crossed `IMPORT` into shipped libraries                                          |
| an `@nonexhaustive`-annotated `DECIDE` group                   | the annotation does not touch S2                                                               |

**And the route out of a failed check is closed too, which the zero depends on.** `l4 run` does
**not** evaluate past a check error: measured on a two-`#EVAL` file whose group is refused, the run
emits **zero** `Result:` blocks and exits 1. So "it only happens in a program that failed to check"
is not a residual route; it is no route.

**What that does and does not establish.** It establishes that **no `.l4` in this tree, and none of
thirteen probes written to break it, type-checks and then dies on a partial selector**. It does not
establish that none can: items 3's bails are argued from the code, not measured, and the paragraph
that argues them says so. A later reader should quote the sweeps and the probes, not the word
"zero" on its own.

1. ~~**A later clause of a multi-clause `DECIDE`/`MEANS` group carries no S2 guarantee.**~~
   **CLOSED 2026-09-09, narrowed 2026-09-10, and as of 2026-09-13 there is no guarantee to state:
   the narrowing this item was written about is CUT and a later clause is refused outright.**

   > **This item keeps its number on purpose.** §4.1, §4.2, `jl4/tests/DmnExport.hs` and
   > `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` all cite "§5.1 hole 1" by number, so it is superseded in
   > place rather than renumbered away. It is also the **only** surviving home of the soundness
   > argument below: `Note [What a later clause knows about its own columns]` was deleted from
   > `jl4-core/src/L4/TypeCheck.hs` with the code, and the Note that replaced it
   > (`Note [S2 inside a later clause]`, `TypeCheck.hs:999`) says so at the site.

   ~~`L4.Parser.matchClauses` compiles clauses 2..n into a `LET`-bound nullary decide
   (`__pm_fallthrough_k`) referenced from the `OTHERWISE` of every column, and `checkExpr` checks a
   `LetIn`'s declarations **before** its body — so that body is checked entirely outside the
   `OTHERWISE` whose residual is meant to cover it. So S2 records **nothing** inside a synthesised
   fall-through body (`CheckEnv.inSyntheticFallthrough`).~~ That field no longer exists, and neither
   does the analysis that replaced it.

   **What is true now, and it is one sentence.** A partial field read in a later clause of a
   multi-clause group is **refused**, with §3 S4's later-clause message (§3.2 quotes it in full).
   The desugaring is unchanged — `matchClauses` still emits `__pm_fallthrough_k` — but nothing
   installs a narrowing on a column binder and nothing exempts one, so the read reaches the ordinary
   S2 clamp, which widens to the whole universe and defers a blocking `PartialProjection`. The
   refusal is **not** a special case bolted on for later clauses; it is what S2 does to any
   un-narrowed read, and `CheckEnv.inLaterClause` (`TypeCheck/Types.hs:1028`) only changes which
   sentence explains it.

   **Both permissive holes this item used to carry are therefore CLOSED, and neither was repaired.**
   They were closed by subtraction — each was an _exemption_ from S2 for a column whose constructors
   could not be enumerated, and there is no exemption left to fall into:

   - **Hole (a) — a column S2 could not enumerate.** Recorded on 2026-09-10 as "an untyped `GIVEN`
     column", and **that spelling was too narrow, which is worth stating because the published
     bound was wrong for it.** The condition was never "the drafter wrote `GIVEN a` without a
     type"; it was "the column's type is still an inference variable when the narrowing table is
     built", and a group with **no signature at all** — the spelling a drafter reaches by accident —
     met it just as well. Both are now refused: measured 2026-09-14, `GIVEN s` with no type exits 1,
     and the same group with no `GIVEN` and no `GIVETH` exits 1, each with the later-clause message.
     The program that used to check clean and die is pinned as **case 12** of
     `not-ok/tc/partial-projection-fallthrough.l4`.
   - **Hole (b) — a hand-written nullary `` `__pm_fallthrough_<k>` ``.** `isSyntheticFallthrough`
     (`TypeCheck.hs:1100`) still recognises the desugarer's reserved name, because the name cannot
     be banned — `L4.Print.quoteIfNeeded` emits exactly that backticked form and `l4 batch`, the
     REPL and the round-trip test all re-parse it. What it no longer does is **switch S2 off**: its
     only remaining readers are `markLaterClause` (`TypeCheck.hs:1046-1049`), which sets a
     diagnostic flag, and `inNonexhaustiveDecide`. Measured 2026-09-14: the spoof program below
     exits 1 where it used to report `Check succeeded.` and then die.

     ```l4
     GIVEN a IS AN Actor
     GIVETH A NUMBER
     DECIDE outer a IS `__pm_fallthrough_0`
       WHERE
         `__pm_fallthrough_0` MEANS a's monthly_rent   -- REFUSED since 2026-09-13
     ```

     One cosmetic consequence, stated so it is not mistaken for a hole: because
     `isSyntheticFallthrough` is what sets `inLaterClause`, a spoofed name also draws the
     **later-clause** sentence although no clause group exists. It costs a slightly-off sentence on
     an already-refused program. Sharpening it would mean reintroducing a set of the group's column
     binders — the clause bookkeeping §3.2's ruling cut.

   **The soundness argument, kept because §5.1 is now its only home.** If a fourth round ever
   rebuilds this, an earlier clause `i` may remove constructor `c` from column `j`'s possible-set at
   clause `m > i` only if **all** of:

   - **(a)** clause `i`'s pattern in column `j` names a constructor of column `j`'s **own type**,
     decided by `Unique` and never by spelling — `qualifiedAliases` registers a constructor's
     section-qualified `Name` under the **original's** `Unique`, and `entityInfo` is keyed by
     `Unique`, so for anything declared inside a `§` the qualified spelling is the only one that map
     holds;
   - **(b)** it supplies exactly that constructor's arity, and **every** sub-pattern is a plain
     binder — the same irrefutability test `armEffect` applies to a `WHEN` arm, for the same reason
     (`WHEN Tenant 1500` consumes nothing, and neither does `DECIDE f (Tenant 1500) …`);
   - **(c)** **every other column of clause `i` matches every value of its own column.** A clause
     that tests something extra matches fewer tuples, so it consumes nothing anywhere:
     `DECIDE f On Landlord IS 0` does not use up `Landlord`, because `f Off Landlord` skips it;
   - **(d)** column `j`'s own constructor set is **enumerable at the point the table is built** —
     the condition that produced hole (a), and the one §3.2's "what a future implementer would need"
     entry says requires checking the body twice.

   Conditions (a)–(c) err **restrictively** when they fail, which is the direction §3.2 requires;
   (d) errs permissively, which is why it is the one that shipped a run-time death.

2. ~~**A module that has been through `prettyLayout` and re-parsed keeps the old, wider
   suppression.**~~ **GONE 2026-09-13, by construction rather than by repair.** `Extension.pmMatrix`
   still does not survive printing, but nothing reads it any more: `CheckEnv.clauseNarrowings` — the
   `Maybe` whose `Nothing` restored suppression for re-parsed output — is one of the four fields the
   cut deleted. S2's verdict now depends only on narrowing facts that **do** survive printing, so
   `l4 batch`, the REPL and the round-trip test reach the same verdict as `l4 check` on the same
   source, with no `Maybe` in between.

   Verified rather than argued (2026-09-14). The `prettyLayout` round-trip block was run with
   `JL4_PRETTY_DUMP_DIR` set — 367 examples, 0 failures, **366** printed modules written out — and
   then `l4 check` was run on every one of them. All **eight** fused multi-clause corpus files
   (`ok/pattern-matching{,-nullary,-decision-table,-partial-capped,-partial-matrix,-partial-multicolumn,-partial-nonexhaustive,-wildcard-shadow}.l4`)
   exit 0 in printed form, the same verdict their sources get; and **not one of the 366 printed
   modules draws an S2 diagnostic at all**, which is the same answer Sweep 1 gives for their sources.
   Printer output and source now agree by construction, not by a `Maybe`.

   The measurements this item used to carry still hold and are worth keeping: `l4 batch
--validate-only` type-checks the source before re-emitting anything, and `l4 format` — which is
   the exact printer — emits **0** occurrences of `__pm_fallthrough_` on a multi-clause file, so the
   formatter was never a way in either.

3. **Four silent bails inside `checkPartialProjection` itself, and they are the whole of what is
   left.** `checkPartialProjection` (`TypeCheck.hs:2852`) records nothing when: **(a)** the resolved
   name is not a `KnownTerm _ Selector`; **(b)** `selectorDomainType` finds no type-application head;
   **(c)** the constructor universe is unenumerable (`Set.null universe` — an empty universe means
   UNKNOWN, never "no constructors", because `CONTRACT` is deliberately excluded from the
   enumeration by `builtinNonExhaustiveTypeUniques`); or **(d)** `declared` is empty, which means the
   model above is wrong about the selector, and reporting from a wrong model is worse than not
   reporting.

   The function's own Haddock (`TypeCheck.hs:2847-2851`) groups these as **two** silences — "not a
   declared field selector" covering (a), (b) and (d), and "a domain whose constructors cannot be
   enumerated" covering (c). Four code paths, two groups; the two statements agree and are counted
   at different grain.

   **None has a demonstrated user, and none was reachable in probing — but this is STATIC reasoning,
   not measurement, and the distinction is the point of this whole section.** (a) is not a field read
   at all, so the evaluator never synthesises the `ConsiderSelector` that raises `PartialSelector`.
   (b) requires a selector whose instantiated type is not a `Fun` with a `TyApp` domain head, which a
   well-formed selector's type always is — including on a parameterised type, where the domain is
   `TyApp T [v]` and the head survives (measured: the polymorphic-enum probe is refused, not
   silently skipped). (c) needs a type with an empty constructor universe that nonetheless carries a
   user-declared selector, and `CONTRACT` is the only such type and cannot. (d) is
   self-contradictory: the selector would not be a field of its own domain type. I could not
   construct a program that reaches any of them.

   **A consequence to state rather than let a later reader discover.** `PartialSelector` now appears
   **unreachable from any program that type-checks**, so: the run-time message of §1.1 has no corpus
   witness (its fixture was deleted, §4.3, and could not be replaced in kind); the exception
   constructor and DMN's coverage-map entry `PartialSelector _ _ _ -> "L11"` are **defensive rather
   than witnessed**; and `doc/reference/errors/README.md`'s entry for it says so on the page rather
   than promising a reader a route to it.

4. **A projection _named_ in a `WHERE` is checked un-narrowed — RESTRICTIVE, not permissive.**
   `CONSIDER a WHEN Tenant t THEN rent OTHERWISE 0 WHERE rent MEANS a's monthly_rent` is refused
   though it is total and lazy, because the `WHERE`'s declarations are checked before the body that
   narrows. A different direction from §3.1, which is about aliasing the **base**, not naming the
   **projection**. Because it is restrictive it surfaces as a refusal a drafter can act on
   (re-measured 2026-09-14: it renders the `NotNarrowed` message, not the later-clause one — there
   is no clause group here), and it cannot cause a run-time death; the repair is to move the read
   inside the branch.

5. ~~**Five shapes an earlier clause can take that consume NOTHING — RESTRICTIVE, and each one is a
   refusal a drafter will meet**~~ (added 2026-09-10). **SUPERSEDED 2026-09-13: an earlier clause
   consumes nothing, full stop**, so there is no list of exceptional shapes to enumerate and no
   "look up at the earlier clauses' other columns" advice to give. The five — a literal, an
   `EXACTLY`/expression pattern, a `FOLLOWED BY` cons pattern, a refutable sub-pattern, and a clause
   that is fine in its own column but tests some **other** column — are recorded in §3.2's evidence
   ledger as **false-positive refusals**, which is what they were: shapes the rule refused while
   claiming, in the message, that nothing narrowed a column the drafter could see being narrowed.
   They are kept there rather than here because they are now evidence about the rule, not a residual
   of it.

Two smaller notes, both restrictive and both still live:

- an alias defined in an **imported** module gets no narrowing — both import merge sites reset
  `constBodies`;
- a mis-spelled constructor pattern (`WHEN Agency` for `Agent`) resolves via
  ``inferPatternApp … `orElse` inferPatternVar`` to a fresh catch-all binder, which consumes
  nothing, so the residual stays too big (re-measured 2026-09-14: refused, exit 1). The
  `OTHERWISE` residual's soundness still depends on that `orElse`; a change to it moves this rule.

## 6. Not ruled here

- ~~**Same name, different types across arms, as two selectors chosen by expected type.**~~
  **CLOSED 2026-09-09 (Meng): follow Haskell, rename the sites.** The `Left`/`Right` `payload` idiom
  was put forward as the use case this bullet invited and was declined; see §4 for the twelve sites
  (eleven when first counted; the `for-all.md` quotation was the twelfth) and the chosen names.
  Landed as commit `7cf1e0e9`; `git show 7cf1e0e9 -- '*.l4'` is the list of what S1's declaration
  error would otherwise have refused.
- **Docassemble's existing refusal of the merged shape** (`checkNameCollisions`, `Docassemble/Lower.hs:2320-2368`, fixture
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
- `doc/reference/types/DECLARE.md` — the drafter-facing sections "A field on several constructors"
  (S1) and "A field on only some constructors" (S2/S3/S4), with
  `shared-field-example.l4` and `partial-field-example.l4` beside them. BUILT 2026-09-09; **revised
  2026-09-14 for §3.2's ruling** (§5 item 7 lists what changed there and in the two files below).
- `doc/reference/errors/README.md` — the runtime entry "Field read from a constructor that does not
  have it, at runtime". **Revised 2026-09-14:** its "exactly two ways the check cannot rule it out"
  is gone, both routes being closed, and it now says on the page that there is no measured route to
  the message at all and why it is kept anyway (§5.1 item 3).
- `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` R4-a — its example is now unreachable by construction; §4.2
  above records what that changed in `sumtype.l4`, `DmnExport.hs` and the KIE MustFail leg.
  **Revised 2026-09-14:** its L11 bullet said the fixture "checks clean because the clause narrowing
  is correct" and that reading form (1) stays reachable "through both of §5.1 item 1's surviving
  permissive holes". Both halves are false after the cut; what replaces them is the `LazyPos`
  measurement recorded in §4.2 above.
- **Nothing here implies `WHOSE` is built. It is not** — no `TKWhose`, no lexer row, no parser
  support, no golden (re-verified 2026-09-14; all 7 corpus occurrences of the word are English prose
  inside `--` comments). S5 is DESIGN.
