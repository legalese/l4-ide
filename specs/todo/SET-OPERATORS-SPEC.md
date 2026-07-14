# Set-Theoretic Operators for L4

> **Status:** DRAFT — design, not yet implemented. No branch cut.
> **Seed:** [`specs/roadmap/future-features.md:17`](../roadmap/future-features.md) — _"Set-theoretic syntax for UNION and INTERSECT. Sometimes set-and means logical-or."_
> That one-liner is the whole of the prior writing on this topic. This spec expands it.

## 0. Framing (for the intro / paper): PEMDAS as a foil

The on-ramp for introductory text is the **"equation that broke the internet"** — `8÷2(2+2)`,
the 2019 viral fight between **1** and **16**. Everyone has seen it; everyone found it maddening;
nobody needs a semantics lecture to feel the problem.

Its value here is **as a foil, not as an analogy** — and getting that right is the whole point.

| Rung | Case                                        | What is in dispute                                                                     | Disease                                | Fix                                      |
| ---- | ------------------------------------------- | -------------------------------------------------------------------------------------- | -------------------------------------- | ---------------------------------------- |
| 1    | `8÷2(2+2)` — 1 vs 16                        | **How the tokens bind.** Nobody disputes what `÷` and `×` _mean_.                      | **Syntactic**                          | Declared precedence; parentheses.        |
| 2    | _Pulsifer_ — `¬(A∧B∧C)` vs `(¬A)∧(¬B)∧(¬C)` | **Scope of the negation.** Operators still classical.                                  | **Syntactic** (same disease as rung 1) | Declared precedence; parentheses.        |
| 3    | "residents of NY and NJ"                    | **What `and` _denotes_** — Boolean meet, or lattice join. The parse is not in dispute. | **Semantic**                           | Types + a lint. Parentheses cannot help. |

The rhetorical move: _"You might think law's and/or problem is just PEMDAS with higher stakes.
It is — right up until it isn't."_ The reader arrives already conceding that notation can fail to
fix meaning, then meets a failure mode that **parenthesization cannot touch**.

Rung 2 is the bridge: **PEMDAS with a prison sentence.** Same underdetermined parse tree, except
the disagreement ran 6–3 in the Supreme Court and a man's liberty turned on it.
**VERIFIED (§10.1): _Pulsifer_ is a negation-scope case, not a set-union case.** The majority kept
`and` **conjunctive** throughout and distributed the negated verb phrase — `¬A ∧ ¬B ∧ ¬C`, which
is `¬(A ∨ B ∨ C)` by De Morgan. **The negation does the union-producing work, not the
conjunction.** Anyone citing _Pulsifer_ for "`and` means union" is overreading it — which is
precisely the category error this spec exists to prevent. It belongs on rung 2 and nowhere else.

**This yields L4's actual contribution: two mechanisms, because there are two diseases.**

- **Rungs 1–2** get the boring, correct, sixty-year-old programming-language answer: an explicit
  grammar with a **declared precedence table** (`Parser.hs:1481-1497`) — plus the thing legal
  drafting has never had: **a visualizer that renders the binding.** The ladder diagrams _are_ the
  answer to PEMDAS. You do not argue about the parse tree; you look at it.
  L4 already practises this: **mixfix operators deliberately refuse implicit precedence** and
  demand explicit grouping (`specs/done/mixfix-operators.md`: _"No implicit precedence rules…
  require explicit grouping"_).
- **Rung 3** gets the type system (§D4) and the ambiguity lint.

**The trap.** Used carelessly, PEMDAS primes the reader to believe _all_ legal ambiguity is a
parenthesization problem. That is the exact misconception this spec exists to kill — and both
leading traditions leave it intact: Adams lumps the classes together under "ambiguity"
(§9.1), and Allen's pulverization **sidesteps** rung 3 rather than distinguishing it (§9.4).
Any write-up must spend rung 3 explicitly saying: **here is where the parentheses run out.**

## 1. Motivation: the disjunctive "AND"

Legal drafters write `AND` where a logician would expect `OR`, and it is not a mistake:

| Clause                                               | Reading                          | Operation     |
| ---------------------------------------------------- | -------------------------------- | ------------- |
| "cruel **and** unusual punishments"                  | must be **both**                 | conjunction ∧ |
| "residents of New York **and** New Jersey may apply" | resident of **either** qualifies | union ∪       |

The second is the notorious "set-and means logical-or" case. It looks paradoxical only because
one word is doing two jobs. Unbundle them and the paradox dissolves:

- **Sentence-level `AND`** conjoins two _predications about the same individual_. It is meet in
  the Boolean algebra `{0,1}` — genuine logical conjunction, an **intersection** of conditions.
- **Term-level `AND`** conjoins two _terms_ to build a larger collection. It is join in a lattice
  of individuals — a **union**.

And union is _defined_ disjunctively at the membership level:

```
x ∈ A ∪ B   ⟺   x ∈ A ∨ x ∈ B
```

So a term-level `AND` that builds a union has an `OR` hiding inside it, one level down, at the
membership test. Same surface word; two different attachment points in the syntax; two different
algebraic operations. Nothing paradoxical — just an overloaded token.

### 1.1 Prior art

This is well-trodden ground, and we should cite it rather than claim it:

- **Partee & Rooth (1983), _Generalized Conjunction and Type Ambiguity_** — the canonical source.
  Their thesis is precisely that `and`/`or` cannot have one uniform Boolean meaning across
  categories: the same lexical item is propositional meet at type `t`, and generalized meet in
  the Boolean algebra of sets/quantifiers at type `⟨e,t⟩` and above. **Type ambiguity is the
  mechanism.** That is exactly the design we adopt below.
- **Link (1983), _The Logical Analysis of Plurals and Mass Terms_** — NP-conjunction as a
  lattice-theoretic sum/join `⊕`, distinct from propositional `∧`. Supplies the algebra.
- **Keenan & Faltz (1985), _Boolean Semantics for Natural Language_**; Gazdar (1980) — the
  cross-categorial generalization.
- Legal-drafting side: the `and`/`or` and `and/or` ambiguity literature (Mellinkoff; Dickerson;
  Scalia & Garner's **Conjunctive/Disjunctive Canon** in _Reading Law_) circles the same problem
  from statutory practice, without the set-theoretic vocabulary.
- **Bench-Capon & Coenen (1992), _Isomorphism and Legal Knowledge Based Systems_** — the AI &
  Law paper that hits this as an _engineering_ problem: naively transcribing statutory `and`/`or`
  into a logic connective can invert the truth conditions, so faithful (isomorphic) formalization
  sometimes requires the knowledge engineer to flip the connective.

What is (as far as we can tell) **not** in the literature is the crisp diagnostic framing —
_the paradox is an artifact of conflating logical-AND with set-union, and set-union is secretly
disjunctive at the membership level_ — nor its use as the basis for a **type-directed
disambiguation** in a legal DSL. That combination is L4's contribution.

## 2. What exists today

Facts, verified against the tree:

| Thing                      | Status                                                                                                                                                                                                                                             |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A `SET` type               | **Does not exist.** L4 has `LIST OF a` only.                                                                                                                                                                                                       |
| Operator overloading       | **Exists**, via magic names. `jl4-core/src/L4/TypeCheck/Environment.hs:81-95` maps `__PLUS__`, `__MINUS__`, `__TIMES__`, `__DIVIDE__`, `__LT__`, `__LEQ__`, `__GT__`, `__GEQ__`, **`__AND__`**, **`__OR__`**, `__NOT__`, `__CONS__`, `__EQUALS__`. |
| How you overload           | Define a function with the magic name; resolution is **by argument type**. See `jl4/examples/ok/overloaded.l4`, which overloads `PLUS`/`MINUS`/`TIMES`/`LESS THAN` for a `Vector` record.                                                          |
| Library-defined containers | **Precedent exists.** `Dictionary` is declared _in the prelude_, not the compiler: `DECLARE Dictionary k v HAS contents IS A LIST OF PAIR OF k, v` (`jl4-core/libraries/prelude.l4:793`), with `dictUnion` / `dictUnionWith` alongside.            |
| `LESS`                     | Token **already exists** (`Lexer.hs:281`, `TKLess`) but the parser only ever consumes it as the two-token sequence `LESS THAN` → `Lt` (`Parser.hs:1491`). **Bare `LESS` is unclaimed.**                                                            |
| `PLUS` / `MINUS`           | `Lexer.hs:274-275`; precedence 6, `AssocLeft` (`Parser.hs:1492-1493`).                                                                                                                                                                             |
| `AND` / `OR`               | Precedence 3 / 2, `AssocRight` (`Parser.hs:1484-1485`).                                                                                                                                                                                            |
| Mixfix operators           | **Exist** (`specs/done/mixfix-operators.md`). Let a library define ``a `UNION` b MEANS …`` with **no lexer change** — but backticks are required at the call site, and mixfix has **no precedence** (parentheses required).                        |

**The headline consequence:** almost all of this feature can ship **as prelude code, with zero
compiler changes.** The compiler work is confined to ergonomics — bare keywords and precedence.

## 3. Design decisions

### D1 — A real `Set a` type, not `LIST` sugar

**Decision: introduce `Set a` as a library type**, following the `Dictionary` precedent exactly:

```l4
GIVEN a IS A TYPE
GIVETH A TYPE
DECLARE Set a
    HAS contents IS A LIST OF a
```

Rationale: overload resolution is **by type**. If sets are just `LIST OF a`, then `AND` on two
lists cannot be distinguished from `AND` on two lists — there is no type to dispatch on, and the
central move of this spec (§D4) becomes impossible. A distinct nominal type is what buys us the
disambiguation. It also lets us state the invariant (`contents` is duplicate-free, order
irrelevant) that `LIST` deliberately does not have.

**Caveat — no typeclasses.** L4 has no constraint mechanism, so `Set a` operations lean on
builtin structural `EQUALS`. That is total and works for any `a`, so it is fine in practice, but
it means we cannot _state_ the "requires equality" precondition in the type. Note it; do not
block on it.

### D2 — Canonical operators: `UNION`, `INTERSECT`, `LESS`

The **canonical, recommended** drafting vocabulary is explicit and unambiguous:

| Operator        | Meaning                       | Legal register                                                            |
| --------------- | ----------------------------- | ------------------------------------------------------------------------- |
| `A UNION B`     | `A ∪ B`                       | "the members of A and of B"                                               |
| `A INTERSECT B` | `A ∩ B`                       | "those who are both"                                                      |
| `A LESS B`      | `A \ B` (relative complement) | **"all employees LESS those on probation"** — idiomatic statutory English |

`LESS` is the prize here. It reads naturally to a lawyer, it is the register legislation already
uses for carve-outs, and — per §2 — bare `LESS` is a free slot in the grammar.

Suggested aliases (bikeshed later): `EXCEPT`, `WITHOUT`, `OTHER THAN` for `LESS`; `IS IN` for
membership; `IS WITHIN` for subset.

### D3 — `PLUS` / `MINUS` overloads: yes, but they carry a trap

You asked about overloading `PLUS` and `MINUS` for set work. It is **free** (§2) and it reads
fine. But it imports a false intuition, and the spec should say so loudly:

> **For numbers, `(a PLUS b) MINUS b == a`. For sets, `(A UNION B) LESS B ≠ A` in general.**

Union is an _idempotent join_ (`A PLUS A == A`), not a group operation. There is no inverse.
A drafter who reasons about `PLUS`/`MINUS` on sets using arithmetic reflexes will write bugs, and
they will be exactly the silent, hard-to-spot kind that L4 exists to prevent.

(Note also: if we wanted `PLUS` to be a genuine Boolean-ring `+`, it would have to mean
_symmetric difference_, not union. We are choosing join-semilattice semantics, not ring
semantics. Worth stating so nobody "fixes" it later.)

**Decision:** provide `__PLUS__` / `__MINUS__` overloads for `Set a` as **convenience aliases**
for `UNION` / `LESS`, but make `UNION` / `LESS` the canonical spelling in docs, examples, and the
`l4` skill. Consider a lint (§D4) nudging `PLUS`-on-`Set` → `UNION`. Do **not** overload `TIMES`
for intersection — the arithmetic analogy is even weaker there and `INTERSECT` is short enough.

### D4 — `AND` on sets: overload it, then _lint_ it. (The important one.)

Because `__AND__` and `__OR__` are overloadable magic names, we can literally do this:

```l4
GIVEN a IS A TYPE
      p IS A Set a
      q IS A Set a
GIVETH A Set a
`__AND__` p q MEANS p UNION q          -- term-level AND: the lattice join
```

Now the two clauses from §1 both type-check, and **the type system picks the right operation**:

```l4
cruel AND unusual          -- BOOLEAN AND BOOLEAN → conjunction ∧
newYorkers AND newJerseyans -- Set AND Set        → union ∪
```

This is Partee & Rooth's type ambiguity, implemented. It is also exactly what makes **isomorphic
formalization** possible: the drafter can transcribe the statute's `and` verbatim, without
first deciding what it means, and still get the right answer.

**But there is a real tension, and it is the crux of this design.** L4's product _is_
explainability. Silently resolving `AND` by type risks _hiding_ the very ambiguity we are in
business to surface. This is our recurring **detect ≠ resolve** seam.

**Decision — do both, and keep them separate:**

1. **Resolve** (permissive): `AND`/`OR` on `Set a` are overloaded as above, so faithful
   transcription of source text works and evaluates correctly.
2. **Detect** (visible): emit an LSP diagnostic at every `AND`/`OR` whose operands resolve to
   `Set` — _"`AND` on SET resolves to UNION (∪). The source text is ambiguous between a
   conjunctive and a set-union reading; consider writing `UNION` explicitly."_ Info/hint
   severity, not an error. Quick-fix: rewrite to `UNION`.

That gives the drafter both: the transcription is isomorphic to the source, **and** the IDE tells
them, at the exact character offset, which reading the machine took and that a human once had to
choose. The ambiguity is neither suppressed nor fatal — it is _surfaced and attributed_. This is
the "avoidable ambiguity tax" story from the papers series, made concrete in a tooltip.

There is an existing and/or lint scaffold to hang this on: `jl4-core/src/L4/Lint/AndOrDepth.hs`
(currently not ellipsis-specific and not yet wired into diagnostics, per the
`future-features.md` audit note).

### D5 — Surface syntax: mixfix now, keywords later

Two routes, and they are not exclusive:

| Route                         | Cost                                                  | Gets you                                                                     |
| ----------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------- |
| **A. Mixfix, in the prelude** | Zero compiler change.                                 | ``A `UNION` B`` — backticks required, **no precedence** (parens everywhere). |
| **B. Real keywords**          | Lexer entries + precedence-table rows in `Parser.hs`. | `A UNION B INTERSECT C` — clean, and correct precedence.                     |

**Decision: Phase 1 ships route A** (prove the semantics, zero risk), **Phase 2 promotes to route
B** once the vocabulary settles. Legal drafters will not tolerate backticks in production text,
so B is the real destination; A is scaffolding.

**Proposed precedence for route B**, slotting into the table at `Parser.hs:1481-1497`:

| Operator    | Prio | Assoc       | Rationale                                                                                                                  |
| ----------- | ---- | ----------- | -------------------------------------------------------------------------------------------------------------------------- |
| `UNION`     | 6    | `AssocLeft` | Mirrors `PLUS` (6). Union is the additive join.                                                                            |
| `LESS`      | 6    | `AssocLeft` | Mirrors `MINUS` (6).                                                                                                       |
| `INTERSECT` | 7    | `AssocLeft` | Mirrors `TIMES` (7). Gives conventional `∩` binds tighter than `∪`: `A UNION B INTERSECT C` = `A UNION (B INTERSECT C)`. ✔ |

All three land **above** comparisons (4) and `AND`/`OR` (3/2), so `A UNION B EQUALS C` parses as
`(A UNION B) EQUALS C`. Correct.

**Implementation landmine — bare `LESS` vs `LESS THAN`.** Line `Parser.hs:1491` currently reads:

```haskell
<|> (\ op -> (4, AssocRight, infix2' Lt op)) <$> ((<>) <$> opToken (TKeywords TKLess) <*> opToken (TKeywords TKThan) <|> …)
```

There is **no `try`**. In megaparsec, `p <|> q` only backtracks if `p` failed _without consuming
input_ — so this alternative consumes `TKLess`, fails to find `TKThan`, and dies hard. Today that
merely means `A LESS B` is a parse error. The moment we add bare `LESS`, this branch **must** be
wrapped in `try` (as the neighbouring `Leq`/`Geq` branches already are) or `LESS THAN` will
shadow set-difference and produce baffling errors. This is the single highest-risk line in the
whole change.

### D6 — Representation: sets as lists. (Resolves Q4.)

**Decision: `Set a` stays a library type backed by `LIST OF a`. We do _not_ unlimber a builtin
`Data.Set`.** Two independent reasons, one blocking and one strategic.

#### The blocking reason: `Data.Set` needs `Ord`, and L4's runtime values don't have one

`Data.Set` requires `Ord` on its element type. L4's runtime value type
(`jl4-core/src/L4/Evaluate/ValueLazy.hs:48-73`) derives only
`(Generic, Show, Functor, Foldable, Traversable)` — **no `Eq`, no `Ord`** — and includes
`ValClosure (GivenSig Resolved) (Expr Resolved) Environment` (line 59). Backing sets with
`Data.Set` would therefore mean inventing a total order over **closures**, and forcing thunks to
compare them, inside a **lazy** machine. That is a deep, invasive change to the evaluator core in
exchange for asymptotics on collections that will realistically hold a dozen parties. Not worth it.

#### The enabling reason: `__EQUALS__` is overloadable

Verified: `Equals` desugars to the magic name `__EQUALS__` (`TypeCheck.hs:1472`), exactly as
`Plus`/`And`/`Or` do (`:1490`, `:1441`, `:1447`). So Q4's `{a,b} ≠ {b,a}` bug is fixable **in the
prelude**, by overloading set equality as mutual subset:

```l4
GIVEN a IS A TYPE
      p IS A Set a
      q IS A Set a
GIVETH A BOOLEAN
`__EQUALS__` p q MEANS (p `is subset of` q) AND (q `is subset of` p)
```

This needs only **element** equality — which is builtin, structural, and total. **No `Ord`
anywhere.** O(n²), which is free at legal scale.

#### Prior art: this shortcut is thoroughly well-trodden

We are emphatically not the first to approximate a set by a de-duplicated list. Representative:

| Language / system             | How                                                                                                                                                                                         |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Prolog `library(ordsets)`** | Sets **are** sorted duplicate-free lists: `ord_union/3`, `ord_intersection/3`, `ord_subtract/3` — precisely our UNION/INTERSECT/LESS triple. Cf. `setof/3` (dedups) vs `bagof/3` (doesn't). |
| **Erlang `ordsets`**          | Same design, inherited from Prolog.                                                                                                                                                         |
| **SQL**                       | `UNION` / `INTERSECT` / `EXCEPT` over bags, with `UNION` dedup'ing and `UNION ALL` not. **Oracle spells `EXCEPT` as `MINUS`.**                                                              |
| **Coq `Coq.Lists.ListSet`**   | `set_union`, `set_inter`, `set_diff` over lists.                                                                                                                                            |
| **Scheme SRFI-1**             | "lset" operations: `lset-union`, `lset-intersection`, `lset-difference`.                                                                                                                    |
| **Common Lisp**               | `union`, `intersection`, `set-difference` on lists.                                                                                                                                         |
| **SETL** (1969)               | The ur-example: sets as a primitive programming construct.                                                                                                                                  |

Two payoffs for us. First, **the SQL row vindicates §D2/§D3's keyword choices**: `UNION`,
`INTERSECT`, `EXCEPT`/`MINUS` is already the vocabulary every enterprise data person knows —
and Oracle's `MINUS` is direct precedent for overloading `MINUS` as set difference. Second,
Prolog's `ordsets` is squarely in **L4's own logic-programming lineage**, so we can cite it rather
than justify from first principles.

#### The catch: "uniq" and "sort" are not the same ask

`uniq` needs only **`Eq`**. `sort` needs **`Ord`**.

Prolog and Erlang can represent sets as _sorted_ dedup'd lists because they have a **standard
order of terms** — a total order over _every_ term (Prolog's `@=<`: `Var < Number < Atom <
String < Compound`). That is the enabling condition, and **L4 has not paid for it**: L4 has
universal structural equality, but its order (`__LT__`) is restricted by `variants` to
`["Number", "String", "Bool"]` (`Environment.hs:86`).

So the two halves land differently:

- **uniq** — available today, polymorphically, free. ✔
- **sort** — **not** available polymorphically. ✘

**Therefore Phase 1 adopts the _unsorted_ lset model** (SRFI-1 / Common Lisp / Coq `ListSet`),
not the Prolog `ordsets` model: dedup on construction, order-insensitive equality via
mutual-subset `__EQUALS__`. No order required.

#### Strategic option (separate decision): a standard order of terms

If L4 ever adopts a Prolog-style **standard order of terms**, sets upgrade to canonical sorted
dedup'd lists and we get, in one stroke: canonical set printing (good for traces and diffs),
O(n log n) set operations, cheap equality, and a general polymorphic `sort` for the whole
language. Closures would be the one hole — Prolog's term order has no closures to worry about;
ours would either exclude functions (runtime error on comparison) or order them by identity.
Comparing sets of functions is a non-use-case in legal drafting, so that hole is acceptable.

This is a **bigger, independently-motivated language decision** and must not be smuggled in under
a set-operators spec. Flagged here, deliberately deferred. If it is ever taken, revisit this
section — the sorted representation strictly dominates.

## 4. Proposed prelude sketch

Illustrative, not verified against the checker — treat as pseudocode in L4's clothing:

```l4
§§ `Sets`

GIVEN a IS A TYPE
GIVETH A TYPE
DECLARE Set a
    HAS contents IS A LIST OF a

-- construction
GIVEN a IS A TYPE
GIVETH A Set a
emptySet MEANS Set WITH contents IS EMPTY

GIVEN a IS A TYPE
      xs IS A LIST OF a
GIVETH A Set a
setFromList xs MEANS Set WITH contents IS dedup xs      -- dedup: needs writing

-- membership: the disjunctive core (§1)
GIVEN a IS A TYPE
      x IS AN a
      s IS A Set a
GIVETH A BOOLEAN
x `is in` s MEANS any (EQUALS x) (s's contents)

-- the three canonical operators
GIVEN a IS A TYPE
      p IS A Set a
      q IS A Set a
GIVETH A Set a
p `UNION` q MEANS setFromList (p's contents FOLLOWED BY q's contents)

GIVEN a IS A TYPE
      p IS A Set a
      q IS A Set a
GIVETH A Set a
p `INTERSECT` q MEANS Set WITH contents IS filter (\x -> x `is in` q) (p's contents)

GIVEN a IS A TYPE
      p IS A Set a
      q IS A Set a
GIVETH A Set a
p `LESS` q MEANS Set WITH contents IS filter (\x -> NOT (x `is in` q)) (p's contents)

-- overloads (§D3, §D4) — free, no compiler change
GIVEN a IS A TYPE
      p IS A Set a
      q IS A Set a
GIVETH A Set a
`__PLUS__`  p q MEANS p `UNION` q
`__MINUS__` p q MEANS p `LESS`  q
`__AND__`   p q MEANS p `UNION` q     -- the term-level AND. Lint fires here.
`__OR__`    p q MEANS p `UNION` q     -- see Open Question Q2
```

## 5. Worked example — the two ANDs, side by side

The acceptance test for this whole spec:

```l4
DECLARE Person HAS name IS A STRING; state IS A STRING

`new yorkers`     MEANS setFromList [alice, bob]
`new jerseyans`   MEANS setFromList [carol]

-- term-level AND → union. Three eligible people.
`eligible` MEANS `new yorkers` AND `new jerseyans`
#EVAL setSize `eligible`                          -- expect 3   (∪)

-- sentence-level AND → conjunction. Both conditions of one punishment.
`violates 8th amendment` MEANS `is cruel` AND `is unusual`
#EVAL `violates 8th amendment`                    -- expect BOOLEAN  (∧)
```

Same token. Different types. Different operators. **Both correct.** And the first one raises a
hint in the IDE telling the drafter that `UNION` was the reading taken.

## 6. Implementation phases

- **Phase 0 — spec review.** This document. Settle D1–D5 and Q1–Q4.
- **Phase 1 — prelude only, zero compiler change.** `Set a` + `is in`, `UNION`, `INTERSECT`,
  `LESS`, `subset`, `setSize`, `dedup`, list↔set conversions, all as mixfix. Golden tests in
  `jl4/examples/ok/set-operators.l4`. Proves the semantics.
- **Phase 2 — the overloads.** `__PLUS__`, `__MINUS__`, `__AND__`, `__OR__` on `Set a`. Add the
  §5 worked example as the acceptance test. This is where the paper-worthy behaviour appears.
- **Phase 3 — keywords + precedence.** Lexer entries for `UNION`/`INTERSECT`; bare `LESS`;
  precedence rows per §D5; **the `try` fix at `Parser.hs:1491`.**
- **Phase 4 — the lint.** Diagnostic + quick-fix for `AND`/`OR` on `Set`, hung off
  `Lint/AndOrDepth.hs`. This is the part that turns a language feature into a _product_ feature.

## 7. Open questions

- **Q1 — `Set` vs `LIST` ergonomics.** Do we auto-coerce `LIST OF a` → `Set a` at operator sites?
  Convenient, but silent coercion is exactly the kind of magic that costs us explainability.
  Leaning **no**: require explicit `setFromList`.
- **Q2 — What does `OR` on two sets mean?** `UNION` is the obvious answer, which makes `AND` and
  `OR` on sets **the same operation** — startling, but arguably correct: "residents of NY and NJ"
  and "residents of NY or NJ" _do_ denote the same eligible population. If that is right, it is a
  genuinely interesting result to write up (and a lint should say so). If it is wrong,
  `INTERSECT` is the alternative and we need an argument for why. **Unresolved; this is the most
  interesting question in the spec.**
- **Q3 — Sets of parties and deontics.** "Residents of NY and NJ **must** file" distributes an
  obligation over a set of parties. That is the same distribution question as
  [`EVERY-EACH-QUANTIFIER-SPEC.md`](EVERY-EACH-QUANTIFIER-SPEC.md), and it touches the
  actor-indexed action work. Needs a joint read; do not design in isolation.
- ~~**Q4 — Ordering/canonicalization.**~~ **RESOLVED — see §D6.**

## 9. Q2 resolved: what the authorities actually say

Researched against primary sources with adversarial verification (2026-07-14). **The collapse is
real, but it is a defeasible default, not a theorem — and the linguists actively reject the naive
`and = union` lexical entry.** Both facts constrain §D4.

### 9.1 The phenomenon has three names, one per discipline

| Discipline            | Name                                                                                                                        | Source                                  |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| Formal semantics      | the **SPLIT** reading (vs. the **JOINT** reading) of DP-internal conjunction                                                | Heycock & Zamparelli (2005)             |
| Contract drafting     | **"Ambiguity of the Part Versus the Whole"** (MSCD ch. 11); the paradigm sub-case is **"The Ambiguity of 'Every X and Y'"** | Adams, MSCD; Adams & Kaye (2006) § IV.G |
| Legal-logic tradition | **"Disjunctive-Conjunctive Ambiguity"**                                                                                     | Layman Allen, 66 Yale L.J. 833, § 10.0  |

### 9.2 Yes, they collapse — and the leading practitioner authority says so outright

**Adams & Kaye, _Revisiting the Ambiguity of "And" and "Or" in Legal Drafting_, 80 St. John's
L. Rev. 1167, 1197–98 (2006)** — the direct precursor to MSCD ch. 11, co-authored with a
linguist. Their conjunctive paraphrase `[46a]` and disjunctive paraphrase `[47a]` are
**character-identical strings**, and they generalize (verbatim):

> "Although _and_ expresses conjunction and _or_ expresses disjunction, **they can serve to
> convey the same meaning**: [46a] and [47a] are identical. … **This phenomenon arises when the
> relevance of two alternatives depends not on the parties but on external factors.** It adds an
> ironic twist to analysis of ambiguity associated with _and_ and _or_."

That last sentence is the **diagnostic we needed**, and it lands squarely on the NY/NJ case:
residency is an _external fact_, not a party's election. They give the phenomenon no name,
calling it only "this phenomenon" and "an ironic twist."

**But two limits the verifiers insisted on, and which we must respect:**

1. The collapse holds only between the two sentences' **most natural readings**. Both remain
   _formally_ ambiguous — the intersection reading of `AND` stays live. A&K's own words on the
   union reading are "**presumably**" and "**Context will often suggest** the intended meaning."
   It is a **defeasible contextual presumption, not a semantic rule.**
2. A&K's collapse examples are not our exact configuration (their conjuncts sit inside a
   post-modifier under "all laws applicable to X and/or Y"). The mapping onto NY/NJ is a
   defensible extrapolation of mechanism, **not a direct citation.**

### 9.3 ⚠️ Do NOT cite the linguists for "`AND` means union"

This is the finding that most constrains §D4. **Heycock & Zamparelli explicitly reject set union
as the denotation of nominal `and`** — verbatim: _"Treating singular split conjunction as set
union, rather than intersection, also fails to yield the correct [result]."_ Their account is a
**Set Product** operation, _"which, in different contexts, can mimic the behavior of intersection
and union."_ And they expressly disclaim a lexical ambiguity (fn. 2).

So **"split reading" names the _data_, not a union semantics for `and`.** On an intersective
semantics the union reading is _"completely unexpected"_ — it is an acknowledged **puzzle**, not
a settled equivalence. The union effect emerges from the interaction of conjunction with
plurality, the determiner, and the predicate — **not** from a disjunctive lexical entry for
`and`.

Crosslinguistic evidence that this is real grammar and not sloppy drafting: English permits
singular splits ("this man and woman are in love"); French and Italian block them; **plural**
splits are permitted in nearly every language surveyed (sole reported exception: Greek).

### 9.4 The prescriptions — and Allen's gift to us

Every authority's cure is **structural or notational, never lexical substitution**:

- **Adams & Kaye:** repeat the head/quantifier per conjunct — "every director **and every**
  officer" (union) vs. "every person who is **both** a director **and** an officer"
  (intersection).
- **Layman Allen, 66 Yale L.J. 833, 858–59 (1957) — "systematic pulverization":** at every
  troublesome connective the drafter is **forced to choose explicitly** among five marked
  symbols: `&` (conjunction), `___` (coimplication), `&OR` (inclusive disjunction), `OR`
  (exclusive disjunction), and — **crucially** — lower-case `or`, **reserved to signal that the
  drafter _wished to be ambiguous_.**

**Allen's fifth symbol is a direct design precedent for L4.** It is a first-class,
machine-readable marker meaning _"the ambiguity here is deliberate."_ That is exactly the escape
valve §D4's lint needs: a drafter who has _seen_ the diagnostic and _intends_ the vagueness must
be able to say so, in the source, rather than suppress the warning. **Proposed: an `AMBIGUOUS`
(or `@ambiguous`) marker that silences the §D4 lint at a site and records the choice in the
trace.** Allen's own modest claim about pulverization is precisely ours: it does not guarantee a
right answer, only that **the choice becomes explicit**.

### 9.5 Consequences for §D4 — tighten, don't abandon

1. **Keep `__AND__` on `Set` = `UNION`.** It is the natural reading, and Adams & Kaye endorse the
   collapse for exactly our fact-pattern. But **frame it as L4 _choosing_ a resolution, not as
   L4 implementing a settled semantics.** The literature does not license the stronger claim.
2. **`__OR__` on `Set` = `UNION` too** (Q2's original worry) — but this now _reinforces_ rather
   than undermines the lint: if `AND` and `OR` on sets evaluate identically, then a drafter who
   wrote one meaning the other gets the same answer, and **only the diagnostic tells them the
   distinction was ever live.** The lint is doing all the work. That is the argument for it.
3. **Lint both `AND` and `OR` on sets**, not just `AND` — and offer Adams & Kaye's own
   expansions as the quick-fixes.
4. **Add the deliberate-ambiguity marker** (§9.4).

### 9.6 Honest gaps in the research

- **Pulsifer v. United States (2024) was never researched** — the single most on-point modern
  judicial authority (the First Step Act safety valve turned entirely on conjunctive vs.
  disjunctive `and`). Nor was Scalia & Garner's Conjunctive/Disjunctive Canon verified. The
  judicial leg rests on Allen's 1957 report plus one 1944 House of Lords case.
- **Yoad Winter is behind a 403** and every Winter claim was refuted or split. His "wide scope"
  account of "every man and woman" is the **most likely place to find the actual explanation**
  and remains unread. `phil.uu.nl/~yoad/papers/fbs-sum.pdf` is the open route.
- **Better case lead, unpursued:** _Attorney-General of the Bahamas v. Royal Trust Co_ [1986] 1
  WLR 1001 (PC) read "education **and** welfare" **disjunctively despite the "and"**, voiding the
  gift — an actual judicial instance of `AND`→union, and a far better fit than _Chichester_
  (which is the mirror case, `OR`→union).
- **Adams does not cite Layman Allen.** Verified by grep of the full text: zero hits for
  "symbolic", "Boolean", "normaliz\*". Adams's apparatus is **grammar-driven** (Huddleston &
  Pullum's CGEL, cited ~14×), not symbolic-logic-driven. **The two traditions are disjoint** —
  which is itself a gap in the literature that L4 sits directly inside.
- **Maurice Kirk's** _Legal Drafting: The Ambiguity of "And" and "Or"_ — **all four claims drawn
  from it were refuted (0-3, 0-3, 0-3, 1-2); the source appears to have been misread.** Do not
  reuse it without going back to the original.

## 8. Related work in-tree

- [`specs/roadmap/future-features.md:17`](../roadmap/future-features.md) — the seed note.
- [`specs/done/mixfix-operators.md`](../done/mixfix-operators.md) — Phase 1's delivery mechanism.
- [`specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md`](EVERY-EACH-QUANTIFIER-SPEC.md) — distribution over
  collections; see Q3.
- [`specs/done/ASYNDETIC-DISJUNCTION-SPEC.md`](../done/ASYNDETIC-DISJUNCTION-SPEC.md) — the other
  place where and/or surface syntax got hard.
- `jl4/examples/ok/overloaded.l4` — the overloading mechanism, by example.
- `jl4-core/libraries/prelude.l4:789+` — `Dictionary`, the template for a library container type.

## 10. The judicial and canon authority (researched 2026-07-15)

Second research pass, four targets, primary sources with adversarial verification. **Headline: the
authority _complicates_ the union claim, and on the strict question of DENOTATION it leans
_contradict_ — while strongly supporting the availability of the union _reading_.** It also
hands us a **new and better lint trigger** (§10.5), which is the most valuable thing to come out
of either pass.

### 10.1 _Pulsifer v. United States_, 601 U.S. 124 (2024) — a De Morgan case. Rung 2 confirmed.

Kagan, J., 6–3 (Roberts, Thomas, Alito, Kavanaugh, Barrett; **Gorsuch dissenting**, joined by
Sotomayor and Jackson). On 18 U.S.C. § 3553(f)(1) — "the defendant does not have— (A) … (B) …
**and** (C) …".

**The Court never turned `and` into `or`.** It kept `and` conjunctive and distributed the negated
verb phrase across the list: `¬A ∧ ¬B ∧ ¬C`, which is `¬(A ∨ B ∨ C)` by De Morgan. The
union-of-disqualifiers effect is produced **entirely by the negation**. The "`and` means `or`"
theory was the Government's _abandoned_ position, disparaged by the dissent and never adopted.

The passage that matters most to us (majority, slip op.):

> "There are **two grammatically permissible** ways to read Paragraph (f)(1). … The choice
> between the two … **is not a matter of grammatical rules**. … Paragraph (f)(1) cannot be
> construed in the abstract, as if all a reader has to go on is the stripped-down phrase 'the
> defendant does not have A, B, and C.' That might require the defendant not to have (A, B, and
> C) — i.e., the combination of the three. Or it might require the defendant not to have A, and
> not to have B, and not to have C — i.e., each of the three. **Really, it all depends.**"

And the discriminator is **the content of the conjuncts, not the syntax**:

> "We interpret the injunction against **drinking and driving** in Pulsifer's way — 'do not (A and
> B)' — because the two activities are usually perilous **only in combination**. We interpret the
> injunction against **eating and drinking before surgery** in the Government's way — 'do not A
> and do not B' — because **each activity alone** is likely to have adverse consequence."

Two delicious details. The Court cites **Huddleston & Pullum's CGEL** (1298–99) — and, at n.4,
**Ken Adams's MSCD § 11.16**. The Supreme Court and this spec are reading the same books.
Separately, **Gorsuch's dissent independently reproduces the joint/split distinction** for
"charitable and educational institutions," and locates it in the **plurality of the head noun**,
not in `and` — a singular head ("a charitable and educational institution") kills the ambiguity.
That converges with Heycock & Zamparelli from the bench.

### 10.2 Scalia & Garner, _Reading Law_ § 12 — the canon preserves De Morgan, and _licenses_ rung 3

The Conjunctive/Disjunctive Canon opens: _"And joins a conjunctive list, or a disjunctive list —
but with negatives, plurals, and various specific wordings there are nuances."_

**It does _not_ encode a negation-context collapse.** Verbatim: _"**After a negative, the
conjunctive `and` is still conjunctive**: Don't drink and drive. You can do either one, but you
can't do them both."_ They name the **"conjunctive negative proof"** (`¬(A∧B∧C)`) against the
**"disjunctive negative proof"** (`¬A∧¬B∧¬C`), and **invoke De Morgan's theorem by name**. So the
canon is on rung 2's side. (Note: the _Pulsifer_ majority went **around** this canon rather than
through it, never citing pp. 119–120.)

**But canon § 12 #4 hands us rung 3 outright** — _"Every (each) husband and father"_ = _"Every
husband and every father."_ **Scalia & Garner's own canon licenses the distributive/union reading
under a universal quantifier.** That is the single strongest canon-based support for the NY/NJ
reading, and it is hiding inside the very canon that otherwise insists `and` is conjunctive.
(#7 "Variant Wordings" separately concedes and/or indifference in a permissive menu lead-in.)

Empirical criticism worth knowing: **Tobia, Slocum & Nourse**, _Statutory Interpretation from the
Outside_, 122 Colum. L. Rev. 213 (2022), tested the canon on ~4,500 laypeople. Ordinary readers
read bare `and` conjunctively (canon supported), but `or` came out mixed — _"In some contexts,
'or' actually expresses 'and' and vice versa."_ **The failure is on the `or` side, not the `and`
side**, and the stimuli were neither benefit-conferring nor negated, so it does not directly test
our problem.

### 10.3 Yoad Winter — the term is **"wide scope" (WS) coordination**, and union is _derived_

Winter's label for our configuration is **wide scope coordination**: `[X coor X] Y` has a WS
reading iff it can be paraphrased `[X Y] coor [X Y]`. His attested datum is the exact structural
analogue of NY/NJ — coordination in the **restrictor of a universal**:

> "(13) John likes **every boy and girl** in the class. → WS: John likes every boy in the class
> and likes every girl in the class." (WS attested.)
> "(14) John likes every boy **or** girl in the class." (WS **unattested**.)

**Mechanism: (a), not (b).** Conjunction is **syncategorematic** — `and` can be _meaningless_,
with the Boolean meet supplied by a grammatical operation; the WS reading is derived via a
Cresswell-style **structured meaning** to which the quantifier applies **pointwise**, yielding a
**conjunction of quantifiers**. Because `every(A) ∧ every(B) ≡ every(A ∪ B)`, **the union is a
derived truth-conditional _equivalence_ for universals — not the denotation of `and`.** Dalrymple's
Strongest Meaning Hypothesis plays **no** role.

⚠️ **Winter explicitly assigns union to `or`**: `[officer or gentleman] = o′ ∪ g′`, versus
`[officer and gentleman] = o′ ∩ g′`. So **do not cite Winter for "`and` = union"** either.

Caveats the verifiers insisted on: this is the **1995 SALT5 paper**, not the 2001 MIT Press book
(the book was 403-walled; the dissertation summary is font-garbled), so read it as time-indexed;
the vote was 2–1; and H&Z classify Winter as an _intersection_ theorist whom their Set Product
supersedes. Also: **WS is blocked under an indefinite article** — _"?John likes some man and
woman."_

### 10.4 _A-G of the Bahamas v. Royal Trust Co_ [1986] 1 WLR 1001 (PC) — real AND→disjunctive

Verified in substance. Lord Oliver of Aylmerton, for the Board. A bequest for "the **education and
welfare** of Bahamian children" was held **not** a valid charitable trust because the phrase fell
to be read **disjunctively** — and "welfare" alone is not exclusively charitable, so the fund
could be applied in perpetuity to non-charitable purposes. **This is the clean, negation-free
judicial instance of AND→union** that _Pulsifer_ is not.

But read the ratio closely, because it is **not a semantic rule about `and`**:

> "it is not easy to imagine a purpose connected with the education of a child which is not also a
> purpose for the child's welfare. Thus, if welfare is to be given any separate meaning at all it
> must be something different from and wider than mere education, **for otherwise the word becomes
> otiose** … the phrase 'education and welfare' in this will inevitably fall[s] to be construed
> disjunctively."

That is an **anti-surplusage / anti-otiosity** argument — structurally **the same move _Pulsifer_
makes** (Subparagraph A does no work on the joint reading). In both jurisdictions the union
reading is **bought with a redundancy canon, not with the conjunction's lexical meaning**.

**And the contrast case proves it.** _Re Best_ [1904] 2 Ch 354 read "charitable **and** benevolent"
**conjunctively** and **saved** the gift. Same connective, opposite result. What distinguishes them
is **not the word `and`** but whether the intersective reading is **vacuous**: in _Royal Trust_,
education ⊆ welfare, so the intersection collapses to "education" and "welfare" does no work; in
_Re Best_, charitable ∩ benevolent is a contentful set.

_(Verification limit: the law report itself is behind Westlaw/vLex. The ratio and Lord Oliver's
authorship rest on multiple consistent secondary reproductions — reliable but not confirmed at
first hand. Get the report before quoting it in a paper.)_

### 10.5 ⭐ The payoff: **non-vacuity is the trigger — and we can compute it**

Two entirely independent traditions converge on the same discriminator, and neither of them is
the conjunction:

- **English charity law** (_Royal Trust_ vs. _Re Best_): the union reading wins exactly when the
  intersective reading would render a term **otiose**.
- **Boolean semantics** (Winter): _"every pianist over 60 **and** below 20 years old"_ — "the
  prominent reading is the contingent WS and **not the vacuously true** NS with the empty common
  noun set."

**The intersective reading is rejected when it is empty or degenerate.** That is a redundancy
canon in law and a non-vacuity preference in semantics, and **it is mechanically checkable.**

**This is a better lint than §D4's.** §D4 fires on _type_ alone ("these operands are `Set`s"),
which is a blunt instrument that will cry wolf on every set-valued `AND`. Instead:

> **Fire the diagnostic when `A INTERSECT B` is empty (or provably empty), because that is
> precisely when the law says the drafter cannot have meant the intersection.**

```
warning: `NY-residents AND NJ-residents` — the intersective reading denotes the EMPTY SET.
         A drafter is presumed not to intend a term to be otiose
         (A-G of the Bahamas v Royal Trust Co [1986] 1 WLR 1001).
         Did you mean UNION?
   fix:  NY-residents UNION NJ-residents
```

That is _Royal Trust_'s otiosity canon, **automated** — and it is cheap, because we already have
`INTERSECT` and an emptiness test. It is also, as far as this research found, **novel**: no one
has mechanised the redundancy canon as an ambiguity detector.

**Amend §D4 accordingly:**

1. **Keep** the `__AND__`/`__OR__`-on-`Set` overloads (faithful transcription still works).
2. **Downgrade** the type-only diagnostic to a hint.
3. **Add the non-vacuity check as the _primary_ diagnostic**, at warning severity. Empty
   intersection ⇒ the drafter almost certainly meant union ⇒ say so, with the citation.
4. Winter's second trigger — **plurality/universal quantification over the restrictor** — is the
   other discriminator, and connects directly to
   [`EVERY-EACH-QUANTIFIER-SPEC.md`](EVERY-EACH-QUANTIFIER-SPEC.md) (Q3). A `Set`-valued `AND`
   under an `EVERY` is the high-confidence union site.

### 10.6 The honest bottom line

**No authority holds that nominal `and` _denotes_ set union.** Winter assigns union to `or`;
Heycock & Zamparelli reject union outright; Scalia & Garner keep `and` conjunctive; _Pulsifer_'s
majority keeps `and` conjunctive; Lord Oliver says the _phrase_ "falls to be construed
disjunctively" **on this will**, not that `and` means `or`.

**But every authority accepts the union _reading_ is available** — Winter attests it under `every`;
Scalia & Garner's own canon #4 licenses it; Gorsuch concedes it; _Royal Trust_ adopts it.

So §D4 must be framed as **L4 choosing a resolution and flagging it**, never as L4 implementing a
settled semantics. And the deepest lesson is _Pulsifer_'s: **"Really, it all depends."** The
connective **underdetermines** the reading. A language that must disambiguate **cannot do it from
`and` alone** — the discriminating features are (i) number on the head noun, (ii) a universal or
deontic operator over the restrictor, and (iii) **whether the intersective reading is vacuous**.
L4 can see (iii) directly, and that is where the lint should live.

### 10.7 Correction to §9.6

Pass 1 concluded that **Maurice Kirk**'s _Legal Drafting: The Ambiguity of "And" and "Or"_,
2 Tex. Tech. L. Rev. 235 (1971), should not be reused because every claim drawn from it was
refuted. **That was a misreading of the source by our agents, not a defect in the source** —
**Gorsuch cites Kirk by name in his _Pulsifer_ dissent**, alongside Dickerson and CGEL. Kirk is a
legitimate, Supreme-Court-cited authority. Go back to the original before citing it, but do not
discard it.
