# Fields on sum types: one selector per shared field, and no projection without narrowing

**Status (2026-09-09): RULED by Meng, and BUILT. On `lang/whose-opening`: S1, S2, S3 and S4 are all
in the tree, and S2 is an ERROR — §4's gate has been run end to end (steps 1, 2 and 3).**
The warning form S2 briefly wore so §4's three rigs could count the corpus is GONE: there is no flag
that restores it, and `PartialProjection` is a `CheckError` (`TypeCheck/Types.hs:149`) whose renderer
`prettyPartialProjection` (`TypeCheck.hs:6903`) is reached from `prettyCheckError`. The run-time
death of §1.1 is no longer reachable from a type-checking program except through the measured,
stated gaps in §5.1 — **one** permissive hole with a demonstrated user (an untyped `GIVEN` column of
a multi-clause group), one that exists only for re-parsed printer output, and four silent bails
inside the check itself. §4.1 records the measured counts and where the measurement contradicted §4's
predictions; §4.2 records the six repairs, the promotion, and what they cost; §4.3 the fixtures.
S5 remains DESIGN — `WHOSE` is not built.
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
will be true.

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
now, where a partial selector still reaches run time (§5.1's two holes, and any `l4 run` on a file
that failed to check), is:

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
and keeps the exhaustiveness sentence. `ok/sum-fields/partial-selector-runtime.l4` pins the new
message — it is under `ok/` precisely because it checks clean and then dies, which is what §5.1's
untyped-`GIVEN` hole means.

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
  (`TypeCheck.hs`'s exhaustiveness check, `patternHasOpaque` at `:4018`) — ~~and the residual must
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
- the **connective** is `could also be` for `NotNarrowed`, `NarrowedByWhen`, `NarrowedByCast`,
  `NarrowedByEarlierClauses`, `NarrowedByResidual` and `NarrowedByExhaustedBranches`, and
  `can only be` for `NarrowedByConstruction` — the one reason under which no set-shrinking happened
  at all, because the base **is** that constructor syntactically.

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
  `actus-core.l4:311` is rewritten as ``WHEN `ACTUS Other` s THEN s``, and drafters write one more
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
both counts. The permissive exits from `checkPartialProjection` are: the untyped-`GIVEN` clause
column (§5.1 item 1), the re-parsed-printer-output case (item 2), and four silent bails — not a
`KnownTerm _ Selector`, no `selectorDomainType` head, an unenumerable universe (`CONTRACT`), or an
empty `declared` (item 3). The measured six is therefore a lower bound on the language's real
exposure.

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
> S2. The file that demonstrates the surviving hole is
> `ok/sum-fields/partial-selector-runtime.l4`.

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
  `NarrowedByEarlierClauses`, the ninth reason, is pinned next door in
  `not-ok/tc/partial-projection-fallthrough.l4` because it needs a clause group to exist at all.
  `NarrowedByCast` had **no witness anywhere in the tree** before case 8, which is the same zero
  coverage §4 records for the quantifier-narrowed projection.
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

1. **Selector generation** (`inferConDecl` `:1530-1553`, `inferSelector` `:1599-1616`). Group a
   type's fields by name across all its constructors before minting selectors. One group → one
   `Resolved` selector, one `CheckInfo`, one `KnownTerm … Selector` of type `T → fieldT`. A group
   whose members disagree on type → S1's declaration error. `ensureDistinct NonDistinctSelectors`
   stays per-constructor (a constructor still may not declare one name twice).
   **Corrected:** the grouping cannot live in `inferConDecl` — only `inferTypeDecl`'s `EnumDecl`
   arm (`:1448-1453`) holds all the constructors, and field types must be resolved across arms
   before any selector is minted. Later arms get `defAka` (same `Unique`, their own name and range).
   **BUILT 2026-09-09** as `inferConDecls` (`TypeCheck.hs:1941`, with Note [One selector per
   shared field] at `:1881` and `data FieldOccurrence` at `:1927` — re-measured 2026-09-10; the
   anchors first written here were from the S1 tree and the two commits since have moved them, so
   treat every line number in this §5 as needing a `grep` before it is trusted), which both the `EnumDecl`
   arm (`:1448-1454`) and the `RecordDecl` arm (via `inferConDecl` `:1533`, the one-arm case) go
   through; `inferSelector` is gone. The error is `SharedFieldTypeMismatch Name [(Name, Name, Type'
Resolved)]` (`TypeCheck/Types.hs:143`, `rangeOf` `:531` anchored on the first occurrence),
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
   fields are stored **positionally** (`ValueLazy.hs:83`) and two arms may place the field
   differently. **S1's checker and evaluator halves must land in one commit**, and the guard is a
   probe with the shared field at index 1 on one arm and 0 on the other. **BUILT 2026-09-09** as
   `evalConDecls` (`Machine.hs:4233-4276`; the `:4207-4231`/`:4230` anchors above are the pre-S1
   tree, and `updateTerm` is now `:4181`): one closure per selector `Unique`, its body a `CONSIDER`
   with one branch per declaring constructor, each carrying that constructor's own arity and that
   field's index; `scanTypeDecl` (`:4015-4019`) dedupes by `Unique` so `preAllocate` allocates one
   cell. The guard is `ok/sum-fields/shared-field.l4`, whose `Landlord HAS addr, name` /
   `Tenant HAS name, rent` reads both arms, positionally and through `WITH`, and through a
   `GIVEN a IS AN Actor` reader. Cosmetic only: the closure's lambda argument is named after the
   FIRST declaring constructor, as the one-arm code named it; nothing prints it.
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
   building — every line number in it is pre-S1 and none of them survives.** As of this commit:
   `data CheckEnv` is `Types.hs:905-1010`, `localBindings` is `:965`, and the new
   `narrowings :: !(Map Unique Narrowing)` is `:975` (appended LAST, deliberately — see the next
   point). `checkDeonton` is `TypeCheck.hs:2095`, its member binding `:2092-2094`, the narrowing
   constructor resolved at `:2049` (the "45 lines above" survives exactly), and stored in the AST at
   `:2112`. `checkBranch` is `:4331`, `checkConsider` is `:3026`.

   - **"four construction sites" is wrong: there are four record CONSTRUCTIONS and a FIFTH
     occurrence.** `TypeCheck.hs:365` is a POSITIONAL pattern over every field of `CheckEnv`, whose
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
     (`TypeCheck.hs:2939`, over `data ArmEffect` at `:2900`), which tests irrefutability directly —
     every sub-pattern a plain variable — rather than testing for the absence of two opaque shapes.
     `patternHasOpaque` (`:3683`) is UNCHANGED: it answers a different question, and `checkConsider`
     and `checkClauseMatrix` depend on its current answer. The two disagreeing is correct.
   - **A bare identifier does NOT parse as `Var`.** `atomicExpr'` produces `App ann n []` and nothing
     normalises it later; `Var` is a pattern synonym for exactly that shape, and is otherwise emitted
     only by the computed-field rewrite and the clause-matrix fallthrough. A base test written as
     `case e of Var _ r -> …` compiles, type-checks and NEVER FIRES — S3 would silently do nothing
     and S2 would then refuse every drafter-written projection. `classifyBase` (`:2613`) matches both
     shapes, and consults `entityInfo` rather than the syntax, which is what gives §3 S3's
     "a nullary constructor is statically that constructor" exception for free.
   - **The alias rule needed no new state.** `constBodies` already holds every nullary `MEANS` body,
     including local `WHERE`/`LET` ones, and `checkExpr`'s `Where` case runs `inferLocalDecl` before
     the body — so resolving the chain AT THE READ (`lookupNarrowing`, `:2686`) is both possible and,
     per §3 S3, required: it is what makes an alias bound outside a `CONSIDER` and read inside two
     branches see each branch's own narrowing.

4. **Totality at the projection.** ~~`inferRecordProjection` is `:3125-3152` (`:3047-3072` is the
   `Proj` dispatcher); the insertion point is after `matchFunTy` (`:3137`).~~ Those anchors are
   pre-S1. The selector's declaring constructors need **no new state**: each constructor's
   `KnownTerm conType Constructor` already names its selectors' own `Def`s as the argument names,
   and `constructorsInScopeFromEntityInfo` enumerates a type's constructors — both confirmed while
   building. **BUILT 2026-09-09** (`checkPartialProjection`, `TypeCheck.hs:2817`, under
   Note [S2: no projection without narrowing]; drained by `flushPartialProjections` `:2891` from
   `inferTopDecl` `:903`; rendered by `prettyPartialProjection` `:6903`) — as a warning in
   `0ea70d3f` for the length of §4's gate step 1, then **promoted to a `CheckError` in the same
   change as the six repairs** (§4.2). With **four** insertion points, not one, because §3
   S2's second ruling covers three forms: `inferRecordProjection` (`a's f`), the `Proj` dispatcher's
   qualified-name branch (`` `Section`.f ``), `inferExpr`'s **`Var`** case (a bare selector as a
   value), and `inferFlatApp`'s `directApp`/`variadicRescue` (`f a`). The bare form lands in the
   `Var` case and not in `inferFlatApp`: a bare identifier parses as `App ann n []`, `Var` is a
   pattern synonym for exactly that, and the `Var` arm sits above the `App` arm.

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

   **What is built instead is deferral**, which needs no change to `severity` and none to
   `viableCandidate`. The obligation is parked on a new `CheckState.pendingPartialProjections` and
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
   hole. `desugarCFDeclare` (`L4/Desugar.hs:270-280`) pattern-matches `RecordDecl` and never
   `EnumDecl`, so a computed field can only ever be declared on a single-constructor record and can
   never be partial.

5. **Evaluator.** ~~needs no change if the merged selector's body is total over its arms.~~
   **Backwards — nothing makes it total.** See item 2.
6. **Consumers.** ~~sees one selector where it saw N.~~ **Backwards for almost all of them:** the
   schema, NLG and transpiler consumers read the AST's `ConDecl` field lists by name **text** and
   are unaffected. Exactly two `Unique`-keyed consumers change — the evaluator environment, and
   DMN's `selectorNames`/`fieldScopes` (`Dmn/Lower.hs:3987-3994`), which must be deduped by
   `Unique` or a merged field's FEEL step becomes `name_2` — **BUILT 2026-09-09**, `nubOrdOn
getUnique` on the `EnumDecl` case. Hover and `@desc` are range-keyed and
   survive `defAka`; find-references improves; completion goes from two byte-identical items to one.
   Docassemble **already refuses** the S1-merged shape with a CI-pinned message
   (`Docassemble/Lower.hs:2320-2353`) — under S1 those are one field, so that refusal must be
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
   S2 made false; the section now states the four ways to narrow AND, per CLAUDE.md §6's "state the
   limits", the four shapes that are NOT narrowed (a `GIVEN` parameter, a non-binder base, a
   refutable `WHEN` arm, an alias that names something other than a binder).

### 5.1 What S2 does not guarantee — one permissive hole, one printer-only hole, four silent bails, one restrictive limit

Only a **permissive** gap lets the run-time death of §1.1 through. None is a reason not to promote;
all are reasons to say so out loud, because §3.2's asymmetry cuts the other way for a rule that
_fails to reject_: there is no error message to teach the lesson.

> **REWRITTEN 2026-09-09. The hole this section was built around is CLOSED** (commit `655b272b`),
> and the paragraph below that said the repair "is unsound and must not be built" was describing a
> _different_ repair from the one that was built. The struck text is kept because §4.2, §4.1,
> `jl4/tests/DmnExport.hs` and `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` all cite "§5.1 hole 1" by number,
> and because deleting it would destroy the evidence that the ruling moved.

1. ~~**A later clause of a multi-clause `DECIDE`/`MEANS` group carries no S2 guarantee.**~~
   **CLOSED 2026-09-09, and replaced by the much narrower residual below.**

   ~~`L4.Parser.matchClauses` compiles clauses 2..n into a `LET`-bound nullary decide
   (`__pm_fallthrough_k`) referenced from the `OTHERWISE` of every column, and `checkExpr` checks a
   `LetIn`'s declarations **before** its body — so that body is checked entirely outside the
   `OTHERWISE` whose residual is meant to cover it. So S2 records **nothing** inside a synthesised
   fall-through body (`CheckEnv.inSyntheticFallthrough`).~~ That field no longer exists.

   The struck paragraph then said: _"Covering clause matrices properly means narrowing at the
   **clause-matrix level** — per column, per clause, off `dHead.rappForm` — not through the
   desugared `LET`."_ **That is exactly what was built**, so the adjacent warning that "the obvious
   repair is unsound and must not be built" stands as written and was never violated: the unsound
   repair it names is copying one residual onto the `__pm_fallthrough_` binding, which is not what
   `clauseColumnFacts` does. It reads the source clause matrix (`Extension.pmMatrix`) and computes a
   real per-column, per-clause possible-set; a constructor leaves a column's set only when an
   earlier clause certainly matches every tuple carrying it there. `markFallthrough` then installs
   clause k+1's entry over `__pm_fallthrough_k`'s body as an ordinary `Narrowing`.

   Measured on this branch's binary, with the type declared:

   ```l4
   DECLARE Actor IS ONE OF
       Landlord
       Agent
       Tenant   HAS monthly_rent IS A NUMBER
   GIVEN s IS AN Actor
   GIVETH A NUMBER
   DECIDE r Landlord IS 0
   DECIDE r s        IS s's monthly_rent   -- REFUSED at check time
   ```

   > `monthly_rent` is a field of `Tenant` only.
   > But `s` could also be `Agent`, which has no `monthly_rent`.
   >
   > The clauses above this one already match `Landlord`,
   > so `Agent` is what is left to reach here.

   Drop `Agent` from the type and the same program is **accepted** and evaluates `0` / `1500`. The
   asymmetry §1.1 complained of — the `CONSIDER` spelling refused, the `DECIDE` spelling silently
   fatal — is gone. `NarrowedByEarlierClauses` is the reason that renders it; `ok/sum-fields/fallthrough.l4`
   and `not-ok/tc/partial-projection-fallthrough.l4` are the fixtures.

   **What survives is one column shape, and it is the only permissive hole with a demonstrated
   user.** An **untyped** `GIVEN` column is still an inference variable when the narrowing table is
   built — the table has to be built before the body is checked — so that column gets no
   possible-set, and an un-narrowed read on it (or on a catch-all binder or `MEANS` alias of it)
   inside a later clause is suppressed. `CheckEnv.clauseSuppressColumns` carries exactly those
   columns; `isFallthroughColumnRead` is the test. Measured: the program above with `GIVEN s` and no
   type reports `Check succeeded.` and then dies, and `ok/sum-fields/partial-selector-runtime.l4` is
   that file, under `ok/` precisely because it checks clean. Closing it needs the column's type
   earlier than the checker has it.

2. **A module that has been through `prettyLayout` and re-parsed keeps the old, wider suppression.**
   `l4 batch`, the REPL and the print round-trip test re-emit the desugared tree, and
   `Extension.pmMatrix` does not survive printing — there is no clause group left to analyse, only
   the `__pm_fallthrough_` bindings. `CheckEnv.clauseNarrowings` is therefore a `Maybe`, and
   `Nothing` restores suppression for un-narrowed bare-binder reads.

   This is **not** a language-level hole: the source was checked against the real matrix on the
   first pass, and this exists so `l4 batch` does not reject a file `l4 check` has just accepted. It
   is also strictly narrower than the old behaviour — a bare selector used as a value and a
   constructed base stay checked even here.

3. **Four silent bails inside `checkPartialProjection` itself, all permissive.** These were stated
   only in §4.1 and belong here. `checkPartialProjection` records nothing when the resolved name is
   not a `KnownTerm _ Selector`; when `selectorDomainType` finds no type-application head; when the
   constructor universe is unenumerable (`Set.null universe` — `CONTRACT` is deliberately excluded
   from the enumeration); or when `declared` is empty, which means the model above is wrong about
   the selector and reporting from a wrong model is worse than not reporting. None has a
   demonstrated user; they are read off the guard and the `unless`, not probed.

4. **A projection _named_ in a `WHERE` is checked un-narrowed — RESTRICTIVE, not permissive.**
   `CONSIDER a WHEN Tenant t THEN rent OTHERWISE 0 WHERE rent MEANS a's monthly_rent` is refused
   though it is total and lazy, because the `WHERE`'s declarations are checked before the body that
   narrows. A different direction from §3.1, which is about aliasing the **base**, not naming the
   **projection**. Because it is restrictive it surfaces as a refusal a drafter can act on (measured:
   it renders the `NotNarrowed` message), and it cannot cause a run-time death; the repair is to
   move the read inside the branch.

Two smaller notes, both restrictive and both silent:

- an alias defined in an **imported** module gets no narrowing — both import merge sites reset
  `constBodies`;
- a mis-spelled constructor pattern (`WHEN Agency` for `Agent`) resolves via
  ``inferPatternApp … `orElse` inferPatternVar`` to a fresh catch-all binder, which consumes
  nothing, so the residual stays too big. The residual's soundness now depends on that `orElse`;
  a change to it moves this rule.

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
- `doc/reference/types/DECLARE.md` — the drafter-facing sections "A field on several constructors"
  (S1) and "A field on only some constructors" (S2/S3/S4), with
  `shared-field-example.l4` and `partial-field-example.l4` beside them. BUILT 2026-09-09.
- `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` R4-a — its example is now unreachable by construction; §4.2
  above records what that changed in `sumtype.l4`, `DmnExport.hs` and the KIE MustFail leg.
