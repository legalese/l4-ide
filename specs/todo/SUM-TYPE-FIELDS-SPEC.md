# Fields on sum types: one selector per shared field, and no projection without narrowing

**Status (2026-09-09): RULED by Meng, NOT BUILT.** Meng's mark, 2026-09-09, on being shown the two
hazards below and the Haskell/OCaml comparison: _"Dying at run time is a bad look for a language in
the FP tradition. … Write it up — let's take the best of both worlds from Haskell and OCaml."_ The
rules in §3 are that ruling written out. Implementation was started the same day on
`lang/whose-opening`; this header is updated when it lands. Nothing in this document describes the
tree as it is today except §1 (measured) and §4 (measured); §3 and §5 describe what will be true.

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
narrowing constructor). There is no run-time path: after S2, the `CONSIDER`-has-no-branch message
of §1.1 is unreachable from a projection.

**S3 — narrowing is a check-time fact, not only a run-time filter.** A binder introduced under a
constructor pattern is **narrowed** to that constructor for the purpose of S2, in every position
that introduces one:

- the quantifier's narrowing constructor — `EVERY Tenant t …` narrows `t` for the filter, the
  action, and the act's `WITHIN`/`HENCE`/`LEST` (the same positions §2.4 says `t` scopes over);
- a `CONSIDER … WHEN Tenant t THEN …` branch narrows `t` for that branch's body;
- a function or `GIVEN` parameter is **not** narrowed by anything: `GIVEN a IS AN Actor` leaves `a`
  at the whole type, so `a's monthly_rent` is an S2 error there until the body narrows it.

A binder that is not under any pattern "could still be" every constructor of its type.

**S4 — the diagnostic.** S2's message must be recognisable to a drafter who never wrote a
`CONSIDER`. The shape:

> `monthly_rent` is a field of `Tenant` only, but `a` could also be a `Landlord`. Narrow `a` first —
> `EVERY Tenant a …`, or `CONSIDER a WHEN Tenant t THEN … t's monthly_rent …` — or give `Landlord` a
> `monthly_rent` too.

The exact wording is the implementer's; the three contents — field, missing arms, repair — are not.

**S5 — what this does for `WHOSE`.** `EVERY-EACH-QUANTIFIER-SPEC.md` §13.6.1 found that the
corrected totality rule (open the fields present on every constructor the member could still be)
opened exactly the set that could not be read. Under S1 that set is a set of total, unambiguous
selectors; under S3 with a narrowing constructor it is that arm's fields. The intersection rule is
therefore **safe to open** once this document is built, and `WHOSE`'s check-time "naming the missing
cast" promise is S2+S4 applied inside the filter — not a separate mechanism.

## 4. Blast radius, and the gate S2 must pass before it is an error

**S1 is a widening.** Every program that type-checks today keeps type-checking with the same
meaning: a single-arm field's selector is unchanged, and a multi-arm same-typed field goes from
unreadable to readable. The one narrowing is same-name-_different_-type across arms, which today is
accepted (two selectors, disambiguated by expected type) and becomes a declaration error. **Gate:**
count corpus declarations of that shape before landing; each is a site to fix in the same PR.

**S2 is potentially a narrowing of the accepted language**, and that is the measurement on which
its landing shape turns. Any corpus `e's f` where `e`'s type is a sum and `f` is not on every arm
type-checks today and would not after S2. This cannot be counted by grep — it needs the checker.
**Gate, in order:**

1. Implement S2 as a **warning** first, run the full golden suite, and count the sites it fires on.
2. **Zero sites** → promote to an error in the same change; land as an error.
3. **Non-zero sites** → read each. A site the checker can see is narrowed by an enclosing pattern is
   an S3 gap, not a drafter error — fix S3. A site that is a genuine partial projection is repaired
   in the corpus in the same PR (a narrowing pattern, or a field on the missing arm), and S2 is
   then promoted to an error. **S2 does not land as a warning.** Meng's mark is that run-time death
   is not acceptable; a warning is the GHC compromise this document exists to decline.

**S3 is additive** for the quantifier (today's run-time roll filter is unchanged; the checker
learns what the evaluator already does). For `CONSIDER … WHEN` it depends on what the checker does
today with a pattern-bound variable's type, which the implementation must measure first — if
`WHEN Tenant t` already types `t` as the arm, S3 is a no-op there.

## 5. Implementation sketch — what the first reader of the code should verify, not follow blindly

This is where the work is expected to land; the implementer re-checks each anchor.

1. **Selector generation** (`inferConDecl` `:1530-1553`, `inferSelector` `:1599-1616`). Group a
   type's fields by name across all its constructors before minting selectors. One group → one
   `Resolved` selector, one `CheckInfo`, one `KnownTerm … Selector` of type `T → fieldT`. A group
   whose members disagree on type → S1's declaration error. `ensureDistinct NonDistinctSelectors`
   stays per-constructor (a constructor still may not declare one name twice).
2. **The selector's body.** Today one `CONSIDER` branch per selector; after S1 one selector carries
   a branch per declaring constructor. Find where that body is synthesised (the desugar that
   produces the `CONSIDER` §1.1's message came from) and widen it.
3. **Narrowing in the check environment.** `KnownTerm ty kind` carries no constructor information.
   Add the narrowing — the set of constructors a local binder could still be, or `Nothing` for
   "all" — on the local binding, and set it at the three sites of S3. For the quantifier it is
   `checkDeonton`'s `extendKnown` (`:1941`), where the narrowing constructor is already resolved
   eleven lines earlier and thrown away (`checkQuantifierCast` `:2004-2010`).
4. **Totality at the projection** (`inferRecordProjection` `:3047-3053`, `resolveProjectionLabel`
   `Types.hs:1387-1389`). After the label resolves to a selector, compare the selector's declaring
   constructors against the base binder's narrowing; a base that could still be a constructor the
   selector does not cover is an S2 error with S4's contents.
5. **Evaluator.** `Proj` lowers to selector application (`Machine.hs:836-837`) and needs no change
   if the merged selector's body is total over its arms. Confirm rather than assume.
6. **Consumers.** Everything that enumerates a type's selectors — LSP hover/completion, the schema
   export, NLG, the transpiler lowerings that read record fields — sees one selector where it saw
   N. Grep for the consumers of `Selector` and of `inferSelector`'s `CheckInfo`.
7. **Goldens and docs.** New `ok/` fixtures for S1 (shared field read on both arms, armed and
   traced) and S3 (narrowed projection); new `not-ok/tc/` fixtures for S1's type-disagreement error
   and S2's partial-projection error with S4's message; the `.l4` and its four goldens in one
   commit, read before blessing, grepped for absolute paths. A `doc/` page or section — audience:
   a drafter who has never read this file — saying what a field on several arms means and why a
   projection can be refused.

## 6. Not ruled here

- **Same name, different types across arms, as two selectors chosen by expected type.** L4's
  resolution is type-directed and could support it; Haskell forbids it; S1 follows Haskell because
  a drafter reading `a's amount` should not need the expected type to know which `amount`. Revisit
  only with a use case.
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
