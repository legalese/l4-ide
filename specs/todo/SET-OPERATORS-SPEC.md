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
| Mixfix operators           | **Exist** (`specs/done/mixfix-operators.md`). Let a library define `a UNION b MEANS …` with **no lexer change** — bare, no backticks: _"backticks simply allow identifiers to contain whitespace… you may omit them entirely"_ (verified live 2026-07-18, §5.1). Backticks are needed only for **multi-word names** (`` `is in` ``) and **keyword-colliding names** (`` `LESS` `` — bare `LESS` is a lexer keyword). Mixfix has **no precedence** (parentheses required).                        |

**The headline consequence:** almost all of this feature can ship **as prelude code, with zero
compiler changes.** The compiler work is confined to ergonomics — bare keywords and precedence.

## 3. Design decisions

### D1 — A real `Set a` type, not `LIST` sugar

**Decision: introduce `SET OF a` as a library type**, following the prelude's `PAIR` precedent
(`DECLARE PAIR OF a, b`, `prelude.l4:577`) — which is an even better template than `Dictionary`,
because the `OF`-style declaration buys the type-position syntax for free (§D7):

```l4
DECLARE SET OF a
    HAS contents IS A LIST OF a
```

**Machine-verified 2026-07-18** (`l4 run`, zero compiler changes): this declaration checks; so do
`GIVETH A SET OF a` in signatures, `SET OF someList` as constructor application, and
`SET WITH contents IS …` record syntax. It is a plain parametric **record wrapper** (a product
type with one field) — _not_ an enum (`IS ONE OF`): the element type `a` is open, and the
contents are runtime values, not compile-time constructors. Enums enter the picture as the
natural _element_ type — see §D7.

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
      p IS A SET OF a
      q IS A SET OF a
GIVETH A SET OF a
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

| Route                         | Cost                                                  | Gets you                                                                                                                                   |
| ----------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| **A. Mixfix, in the prelude** | Zero compiler change.                                 | **`A UNION B` — bare, today** (§5.1-verified). But **no precedence** (parens for anything compound), and no bare `LESS` (lexer keyword). |
| **B. Real keywords**          | Lexer entries + precedence-table rows in `Parser.hs`. | `A UNION B INTERSECT C` — correct precedence, plus bare `LESS`.                                                                            |

**Decision: Phase 1 ships route A** (prove the semantics, zero risk), **Phase 2 promotes to route
B** once the vocabulary settles. Route A is better than this table originally believed — the
production spellings `A UNION B` / `A INTERSECT B` already work bare — so what B actually buys
is **precedence** and **bare `LESS`**, not de-backticking. In Phase 1, set difference either
wears backticks (`` A `LESS` B ``) or ships bare under a keyword-free alias — **`WITHOUT` and
`EXCEPT` are both unclaimed identifiers** (verified against `Lexer.hs`; of the §D2 vocabulary
only `LESS` and `MINUS` are keywords).

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
      p IS A SET OF a
      q IS A SET OF a
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

### D7 — Literal syntax: `SET` mirrors `LIST`, because L4 has no square brackets

Caught in review (Meng, 2026-07-18): earlier drafts wrote `setFromList [alice, bob]` — but **L4
has no `[…]` list literals.** The term-level list syntax is the keyword form
`LIST alice, bob, carol` (`Parser.hs:1818`, layout-aware: items may continue on more-indented
lines). So the set syntax should **parallel `LIST` at both levels**:

| Position | `LIST` today             | `SET` proposal          | Status                                        |
| -------- | ------------------------ | ----------------------- | --------------------------------------------- |
| type     | `LIST OF a`              | `SET OF a`              | ✅ **works today** — free via §D1's `DECLARE` |
| term     | `LIST alice, bob, carol` | `SET alice, bob, carol` | Phase 3 — needs a lexer keyword + production  |
| term     | —                        | `SET OF someList`       | ✅ **works today** — constructor application  |

All the ✅ rows were **machine-verified 2026-07-18** with `l4 run` on a probe file — including the
pleasant surprise that the unparenthesized nesting works:

```l4
probe MEANS SET OF LIST 1, 2, 3     -- LIST binds greedily; SET OF receives the whole list ✓
```

`SET` the name is unclaimed (no lexer token, nothing in the prelude), and `PAIR` proves all-caps
library type names are legal — **`SET` only _looks_ like a keyword**, which is exactly the
ergonomic effect we want at zero compiler cost.

**The Phase 3 ergonomic** is the variadic term literal `SET alice, bob, carol` — a clone of the
`list` production at `Parser.hs:1818` (same `listItemThreshold` layout machinery), desugaring to
dedup'd construction. That is deferred alongside the other keyword work in §D5's route B.

**The dedup caveat, and its resolution.** The raw constructor `SET OF xs` does **not** dedup, so
"`contents` is duplicate-free" cannot be a construction invariant unless we hide the constructor
— and L4 has no module-privacy to hide it with. **Decision: make the _observers_
quotient-respecting instead.** Membership (`any` over `contents`) and mutual-subset `__EQUALS__`
(§D6) are already duplicate-insensitive; the only operations that must dedup on read are
`setSize` (count `dedup contents`, not `count contents`) and printing. Then a duplicated
representation is semantically invisible, `setFromList`/the Phase-3 literal dedup merely as an
optimization, and no invariant is load-bearing. This is the standard quotient-type move, and it
is _simpler_ than policing construction.

**Enums are the natural element type, not the underlying representation.** `SET OF a` wraps a
`LIST OF a`; it does not build on `IS ONE OF`. But when `a` _is_ an enum, the element domain is
finite and closed, and two upgrades unlock: (i) an **absolute complement** becomes computable —
`universe LESS s`, where `universe` enumerates the constructors — whereas for open `a` only the
relative complement `LESS` exists; and (ii) §11.6's Defeater 2 (co-extensiveness, `A ≡ B`)
becomes decidable against the whole domain, not just the enumerated contents. The CONSIDER
exhaustiveness machinery already walks enum constructor lists, so (i) has in-tree precedent.

#### D7.1 — Erasing the otiose `LIST`: two routes to `SET OF 1, 2, 3`

Review quip (Meng, 2026-07-18), too good to lose: in `SET OF LIST 1, 2, 3` the embedded `LIST`
is — **by this spec's own canon** — otiose, and the drafter is presumed not to intend a term to
be otiose. So what does it take to write `SET OF 1, 2, 3` directly?

**Load-bearing fact (verified in-tree): `SET OF 1, 2, 3` already _parses_.** Term-level
`f OF x, y` is ordinary application syntax — the `app` production (`Parser.hs:1945`) reads it as
`App SET [1, 2, 3]`. The phrase dies only in the type checker, where `matchFunTy`
(`TypeCheck.hs:2319`) finds a one-field constructor applied to three arguments. **This is not a
grammar problem; it is an arity problem.** Which suggests fixing it where it fails:

**Route α — typechecker elaboration (recommended).** In `App` inference (`TypeCheck.hs:1684`),
when the head resolves to a record constructor with **exactly one field of type `LIST OF a`**,
add a resolution alternative that collects the arguments into a `List` literal and retries:
`App SET [e₁, …, eₙ] ⇒ App SET [List [e₁, …, eₙ]]`. The checker's application resolution is
already alternative-driven — that is precisely how magic-name overloading dispatches — so this
is an idiomatic, contained change, not surgery.

- **It is a conservative extension.** The alternative fires only where direct application fails,
  and every program it rescues is _today a type error_. No existing program changes meaning.
  Exact fit wins: `SET OF xs` (where `xs` is already a list) keeps its verified wrap-this-list
  reading.
- **Corner case, document it:** for sets _of lists_, `SET OF (LIST 1, 2)` takes the exact-fit
  reading — the two-element set `{1, 2}` — not the singleton `{⟨1,2⟩}`. A singleton containing a
  list needs `setFromList (LIST (LIST 1, 2))`.
- **It generalizes.** Any single-list-field record gets variadic construction for free
  (`Dictionary OF pair₁, pair₂, …` falls out). Decide whether to gate the rule to `SET` or adopt
  it whole as a general variadic-constructor rule — SETL heritage either way.
- **No dedup at the elaboration site** — the quotient-observer decision above already makes raw
  contents semantically harmless.

**Route β — the keyword literal `SET 1, 2, 3`** — the strict parallel to `LIST 1, 2, 3` (note
that the `LIST` term literal takes **no `OF`** either): lexer `TKSet` plus a clone of the `list`
production (`Parser.hs:1817`), desugaring to `setFromList`. Costlier than it looks: once `SET`
is a keyword, every position where `SET` must still act as a _name_ — `tyApp` (precedent:
`tokenAsName (TKeywords TKList)`, `Parser.hs:1096`), the `DECLARE` head, term application,
`WITH` record heads, patterns — needs a `tokenAsName` admission. And β must **not** swallow
`OF`: if the literal accepted `SET OF xs`, it would silently flip that phrase's meaning from
wrap-list to singleton-containing-a-list.

**Verdict: α delivers the requested spelling with zero grammar changes and no new keyword; β is
cosmetic completion that can come later or never.** α slots into Phase 3 (the first
compiler-touching phase) and likely obviates β.

**DECIDED (Meng, 2026-07-18): route α adopted.** β stays in the spec as the rejected
alternative, for the record.

## 4. Proposed prelude sketch

Illustrative, not verified against the checker — treat as pseudocode in L4's clothing:

```l4
§§ `Sets`

DECLARE SET OF a
    HAS contents IS A LIST OF a       -- verified: checks today (§D1, §D7)

-- construction
GIVEN a IS A TYPE
GIVETH A SET OF a
emptySet MEANS SET WITH contents IS EMPTY

GIVEN a IS A TYPE
      xs IS A LIST OF a
GIVETH A SET OF a
setFromList xs MEANS SET WITH contents IS nub xs        -- nub = dedup, already in the prelude

-- membership: the disjunctive core (§1)
GIVEN a IS A TYPE
      x IS AN a
      s IS A SET OF a
GIVETH A BOOLEAN
x `is in` s MEANS any (EQUALS x) (s's contents)

-- the three canonical operators
GIVEN a IS A TYPE
      p IS A SET OF a
      q IS A SET OF a
GIVETH A SET OF a
p `UNION` q MEANS setFromList (p's contents FOLLOWED BY q's contents)

GIVEN a IS A TYPE
      p IS A SET OF a
      q IS A SET OF a
GIVETH A SET OF a
p `INTERSECT` q MEANS SET WITH contents IS
    filter (GIVEN x YIELD x `is in` q) (p's contents)

GIVEN a IS A TYPE
      p IS A SET OF a
      q IS A SET OF a
GIVETH A SET OF a
p `LESS` q MEANS SET WITH contents IS
    filter (GIVEN x YIELD NOT (x `is in` q)) (p's contents)

-- overloads (§D3, §D4) — free, no compiler change
GIVEN a IS A TYPE
      p IS A SET OF a
      q IS A SET OF a
GIVETH A SET OF a
`__PLUS__`  p q MEANS p `UNION` q
`__MINUS__` p q MEANS p `LESS`  q
`__AND__`   p q MEANS p `UNION` q     -- the term-level AND. Lint fires here.
`__OR__`    p q MEANS p `UNION` q     -- see Open Question Q2
```

## 5. Worked example — the two ANDs, side by side

The acceptance test for this whole spec:

```l4
DECLARE Person
    HAS name  IS A STRING
        state IS A STRING

`new yorkers`   MEANS SET OF LIST alice, bob      -- no square brackets in L4 (§D7)
`new jerseyans` MEANS SET OF LIST carol

-- term-level AND → union. Three eligible people.
`eligible` MEANS `new yorkers` AND `new jerseyans`
#EVAL setSize `eligible`                          -- expect 3   (∪)

-- sentence-level AND → conjunction. Both conditions of one punishment.
`violates 8th amendment` MEANS `is cruel` AND `is unusual`
#EVAL `violates 8th amendment`                    -- expect BOOLEAN  (∧)
```

Same token. Different types. Different operators. **Both correct.** And the first one raises a
hint in the IDE telling the drafter that `UNION` was the reading taken.

### 5.1 More worked examples — strings and sum types (machine-verified 2026-07-18)

The following all **run today** (`l4 run`, zero compiler changes) against a ~50-line prelude
sketch: `SET OF a` + `setFromList` (via prelude `nub`), `` `is in` `` (via prelude `elem`),
`` `is subset of` ``, `` `set equals` `` (mutual subset), `UNION` (via prelude `append`),
`INTERSECT`, `` `LESS` ``, `setSize`. **Ten `#EVAL`s, ten expected answers — Phase 1 is
not a sketch, it is a prototype.** Phase-1 spellings shown — note `UNION` and `INTERSECT` are
**bare**, no backticks, at definition and call sites alike (re-verified after Meng challenged
the backtick claim); only multi-word names and the keyword-colliding `` `LESS` `` wear
backticks. The route-α form (`SET OF "a", "b", …`) is noted where it will apply.

**Strings — the §11.5 trichotomy, all three rows executable.** The legal discriminator is the
extensional relationship between the operand sets, so each case is just data:

```l4
-- Royal Trust: education ⊆ welfare. The intersective reading of
-- "education AND welfare" collapses to education — "welfare" is otiose.
`education purposes` MEANS setFromList (LIST "schools", "universities", "scholarships")
`welfare purposes`   MEANS setFromList (LIST "schools", "universities", "scholarships",
                                             "housing", "recreation")
#EVAL `education purposes` `is subset of` `welfare purposes`          -- TRUE ✓
#EVAL setSize (`education purposes` INTERSECT `welfare purposes`)   -- 3 ✓  (= education)

-- NY/NJ: disjoint operands, empty intersection → Defeater 1 fires
`new yorkers`   MEANS setFromList (LIST "alice", "bob")
`new jerseyans` MEANS setFromList (LIST "carol")
#EVAL setSize (`new yorkers` UNION `new jerseyans`)                 -- 3 ✓
#EVAL setSize (`new yorkers` INTERSECT `new jerseyans`)             -- 0 ✓  (otiose ⇒ UNION?)

-- Koh Lau Keow: co-extensive operands → Defeater 2 (exegetical)
`home uses`      MEANS setFromList (LIST "refuge", "residence")
`sanctuary uses` MEANS setFromList (LIST "residence", "refuge")
#EVAL `home uses` `set equals` `sanctuary uses`                       -- TRUE ✓  (alias?)

-- Re Best: proper overlap, both terms do work → literal reading
`charitable objects` MEANS setFromList (LIST "almshouse", "school")
`benevolent objects` MEANS setFromList (LIST "school", "social club")
#EVAL setSize (`charitable objects` INTERSECT `benevolent objects`) -- 1 ✓  (no lint)
```

**Sum types — eligibility by state.** Structural `EQUALS` covers enum constructors, so
membership, subset, and set-equality work on `IS ONE OF` types with no extra machinery — and the
finite constructor universe makes the **absolute complement** real (§D7):

```l4
DECLARE State IS ONE OF NY, NJ, CT

`the tri-state universe` MEANS setFromList (LIST NY, NJ, CT)
`eligible states`        MEANS setFromList (LIST NY, NJ)

#EVAL NY `is in` `eligible states`                                    -- TRUE ✓
#EVAL CT `is in` `eligible states`                                    -- FALSE ✓
#EVAL setSize (`the tri-state universe` `LESS` `eligible states`)     -- 1 ✓  (absolute complement)
#EVAL (setFromList (LIST NJ, NY, NJ)) `set equals` `eligible states`  -- TRUE ✓  (order & dups invisible)
```

After route α, the constructions shed their `LIST`:
`setFromList (LIST NY, NJ)` → `SET OF NY, NJ`;
`setFromList (LIST "refuge", "residence")` → `SET OF "refuge", "residence"`.

**Three syntax findings from the probe** (each empirically confirmed — including one false
belief of this spec's own, caught by Meng in review):

1. **Backticks are NOT operator syntax — an earlier draft of this spec (and its §2 table) said
   they were required at call sites, and that was wrong.** Bare `A INTERSECT B` and `A UNION B`
   work at definition and call sites alike; all ten `#EVAL`s re-verified bare. The governing
   rule is `mixfix-operators.md`'s: _"backticks simply allow identifiers to contain whitespace
   or punctuation; they do not tell the parser that something is an operator."_ Backticks are
   needed exactly twice in the Phase-1 vocabulary: **multi-word names** (`` `is in` ``,
   `` `set equals` ``) and **keyword collisions** — which is the next finding.
2. **The `LESS THAN` landmine (§D5) is real and the error is exactly as baffling as predicted:**
   bare `A LESS B` inside parentheses reports _"unexpected `(`"_ at the opening parenthesis,
   three tokens before the actual problem, because the keyword `LESS` starts the `LESS THAN`
   branch, which fails hard with no `try`. Backticked `` A `LESS` B `` escapes the keyword and
   works. First-hand confirmation that `Parser.hs:1491` is the highest-risk line — and the
   reason Phase 1 difference is either backticked or spelled `WITHOUT`/`EXCEPT` (both unclaimed
   identifiers; §D5).
3. **Mixfix has no precedence against juxtaposition**: `` f x `set equals` y `` needs
   `` (f x) `set equals` y ``. Also `WITH` record construction resists a less-indented
   continuation line — prefer `setFromList (…)` over multi-line `SET WITH contents IS …`.

Prelude inventory note: `nub` (dedup), `elem` (membership), and `append` all exist already —
the §4 sketch's helper burden is smaller than drafted.

## 6. Implementation phases

- **Phase 0 — spec review.** This document. Settle D1–D5 and Q1–Q4.
- **Phase 1 — prelude only, zero compiler change.** `SET OF a` + `is in`, `UNION`, `INTERSECT`,
  `LESS`, `subset`, `setSize`, list↔set conversions, all as mixfix over prelude `nub`/`elem`/
  `append`. Golden tests in `jl4/examples/ok/set-operators.l4`. **Prototyped and verified
  2026-07-18 — the §5.1 probe runs all ten `#EVAL`s green on today's compiler**; landing it is
  transcription, not development.
- **Phase 2 — the overloads.** `__PLUS__`, `__MINUS__`, `__AND__`, `__OR__` on `Set a`. Add the
  §5 worked example as the acceptance test. This is where the paper-worthy behaviour appears.
- **Phase 3 — keywords + precedence.** Lexer entries for `UNION`/`INTERSECT`; bare `LESS`;
  precedence rows per §D5; **the `try` fix at `Parser.hs:1491`**; the §D7.1 route-α elaboration
  (variadic `SET OF 1, 2, 3` via arg-collection in the typechecker — likely obviating the
  route-β `SET alice, bob, carol` keyword literal).
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

> "if 'welfare' is to be given any separate meaning at all it must be something different from and
> wider than mere education, **for otherwise the word becomes otiose**." … "their Lordships need
> say no more than that they agree with Blake C.J. and the Court of Appeal that the phrase
> '**education and welfare**' in this will **inevitably falls to be construed disjunctively**."

That is an **anti-surplusage / anti-otiosity** argument — structurally **the same move _Pulsifer_
makes** (Subparagraph A does no work on the joint reading). In both jurisdictions the union
reading is **bought with a redundancy canon, not with the conjunction's lexical meaning**. (The
Board reaches it through **_Re Eades_ [1920] 2 Ch 353** (Sargant J), which frames the choice as
"the change of the word 'and' into 'or'.")

**And the contrast case proves it.** _Re Best_ [1904] 2 Ch 354 read "charitable **and** benevolent"
**conjunctively** and **saved** the gift. Same connective, opposite result. What distinguishes them
is **not the word `and`** but whether the intersective reading is **vacuous**: in _Royal Trust_,
education ⊆ welfare, so the intersection collapses to "education" and "welfare" does no work; in
_Re Best_, charitable ∩ benevolent is a contentful set.

_(✅ **VERIFIED first-hand** against the primary source — BAILII [1986] UKPC 34 (= [1986] 1 WLR
1001 = [1986] 3 All ER 423), PC Appeal No. 37 of 1984, delivered 23 June 1986, **[Delivered by
Lord Oliver of Aylmerton]**. Both "otiose" and "falls to be construed disjunctively" confirmed
verbatim; see §12.5. Only `Re Best` now remains unconfirmed at first hand.)_

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

## 11. Singapore authority (lawplain corpus, 2026-07-15)

Searched the Singapore judgments corpus directly. **This is the most valuable authority we have
found** — not because it says something new, but because two Court of Appeal judgments, both led
by **Menon CJ**, come out **opposite ways on the same word**, and the reason they diverge is
_computable_. Together with a third case on the "exegetical" connective, they yield a complete
**trichotomy driven by the extensional relationship between the two operand sets** — which is
exactly the thing a set-aware language can see and a prose drafter cannot.

### 11.1 _Nam Hong Construction v Kori Construction_ [2016] SGCA 42 — AND read as UNION

Menon CJ (authoring), Phang JA, Chong J. Building Control Act (Cap 29, 1999 Rev Ed) s 2(1),
definition of "specialist building works", para (d): "structural steelwork comprising—
(i) fabrication of structural elements; (ii) erection work like site cutting, site welding and
site bolting; **and** (iii) installation of steel supports for geotechnical building works". Does
a contractor need **all three**, or **any one**?

**Held: disjunctive. Any one suffices.** A genuine AND→union, in a _definition_, with no negation
anywhere — the clean instance _Pulsifer_ is not.

The echo of _Pulsifer_ is uncanny (¶19):

> "It is common ground that **both the conjunctive and disjunctive interpretations are
> grammatically possible**. … Whether one reading or the other is to be preferred **turns on
> Parliamentary intention**."

Two apex courts, two continents, eight years apart: **grammar underdetermines; context decides.**
(Compare Kagan's "Really, it all depends.")

**And the decisive argument was otiosity** (¶26):

> "On the conjunctive interpretation, the performance of fabrication work and/or erection work of
> any dimension would not fall within the definition … **This renders the carve-outs in s 29A(1)
> of the Act completely otiose.** To us, this is a strong indication that Parliament intended that
> para (d) be read disjunctively."

Same move as _Royal Trust_ ("otherwise the word becomes otiose"), same move as _Pulsifer_
(Subparagraph A does no work). **Third jurisdiction, same trigger.**

_(✅ **VERIFIED first-hand** against elitigation `2016_SGCA_42`, 2026-07-18: coram, statute, and
¶19 + ¶26 all confirmed verbatim; see §12.7.)_

### 11.2 _Sit Kwong Lam v MCST 2645_ [2018] SGCA 14 — AND read as CONJUNCTION

Menon CJ, Prakash JA, Chong JA — **the same court, two years later, going the other way.** BMSMA
s 2(1) "common property": "(i) not comprised in any lot …; **and** (ii) used or capable of being
used … by occupiers of 2 or more lots".

**Held: conjunctive. Both limbs required.** ¶42 states the **default**, and cites the _Nam Hong_
litigation only to distinguish it. (**Pin-cite correction, verified 2026-07-18:** what ¶42
actually cites is the **High Court decision below** — _Kori Construction (S) Pte Ltd v Nam Hong
Construction & Engineering Pte Ltd_ [2015] 2 SLR 616 — **not** the CA judgment [2016] SGCA 42.
Cite it accordingly.)

> "**In ordinary usage**, however, **the word 'and' has a conjunctive effect**, as opposed to the
> word 'or', which has a disjunctive effect. The Respondent … cited [_Kori v Nam Hong_ [2015] 2
> SLR 616 (HC)] as authority for the proposition that … the word 'and' could be interpreted as
> either conjunctive or disjunctive, depending on the context. **This might be so, but** in the
> present case, we were satisfied that the word 'and' clearly had a conjunctive meaning …"

**And here is the anti-defeater — the meaningful-variation canon** (¶43), which is _also_
computable:

> "Sub-sections (a) and (b) were separated by the word '**or**' … It would be **unlikely** then to
> find … that **within the same definition**, Parliament had decided to use **two different words,
> 'and' and 'or', to achieve the same disjunctive effect**. Rather, the more logical conclusion was
> that Parliament had clearly appreciated the difference … and had **consciously used** these two
> words to convey the meaning that it intended."

**If the drafter uses both connectives contrastively in the same instrument, they knew the
difference — so do not second-guess the connective.** That is a scan of the enclosing scope, and
we can do it.

_(✅ **VERIFIED first-hand** against elitigation `2018_SGCA_14`, 2026-07-18: coram — Menon CJ
(authoring), Prakash JA, Chong JA — and ¶42 + ¶43 confirmed verbatim, subject to the pin-cite
correction above; see §12.7.)_

### 11.3 _Koh Lau Keow v AG_ [2013] SGHC 155 — a **third** sense: the exegetical connective

A charitable trust for use as "a **home or sanctuary** for Chinese women vegetarians of the
Buddhist faith". Held: "or" is **exegetical**, not alternative (¶31) — the two words name _the same
thing_.

This is **neither ∪ nor ∩**. It is **apposition / aliasing**: `A ≡ B`. "Falklands **or** Malvinas."
Picarda, quoted at ¶28:

> "The primary meaning of 'or' is disjunctive, but there is a secondary meaning which may perhaps
> be called **exegetical or explanatory**. So used the word is equivalent to '**alias**' or
> '**otherwise called**' … However, this use of the word 'or' is **possible only if the words or
> phrases which it joins connote the same thing and are interchangeable one with the other**."

_Chichester_ is to the same effect — and it is now **verified first-hand** (BAILII [1944] UKHL 2 =
[1944] AC 341; §12.6). The House of Lords holds "charitable **or** benevolent" void for
uncertainty precisely because the two words do **not** coincide: _"the two words 'charitable' and
'benevolent' do not ordinarily mean the same thing; they overlap … but also [each covers]
something which is not covered by the other."_ The exegetical escape is available _only_ when the
alternatives are convertible — the Lords describe it as _"an exegetical link between convertible
and equivalent synonyms."_ That is the co-extensiveness (`A ≡ B`) precondition, from the primary
source. And the judge's test in _Koh Lau Keow_ is **literally a set-overlap computation** (¶29):

> "This poses the question **whether 'home' and 'sanctuary' sufficiently overlap in meaning** such
> that 'or' can be interpreted exegetically."

_(✅ **VERIFIED first-hand** against elitigation `2013_SGHC_155`, 2026-07-18: Tay Yong Kwang J;
the Picarda quote (¶28, from the 4th ed 2010, p 330), the ¶29 "sufficiently overlap" test, and
the holding — ¶31: "Looking at the Declaration of Trust as a whole, I hold that 'home or
sanctuary' is to be interpreted exegetically and not conjunctively as true alternatives" — all
confirmed verbatim; see §12.7.)_

### 11.4 _PP v Low Kok Heng_ [2007] SGHC 123 — the principle, stated flatly

V K Rajah JA. The headnote itself carries: _"Statutory Interpretation — Construction of statute —
Whether 'or' could mean 'and'"_. At ¶69:

> "It is a **settled principle** of statutory interpretation that **not every application of the
> word 'or' produces a disjunctive result**."

_(✅ **VERIFIED first-hand** against elitigation `2007_SGHC_123`, 2026-07-18 — superseding the
earlier corpus-truncation caveat. ¶69 confirmed verbatim (the court's own emphasis falls on
"every"), the catchwords do carry "Statutory Interpretation — Construction of statute — Whether
'or' could mean 'and'", and the statute is s 133 of the Bankruptcy Act (Cap 20, 2000 Rev Ed) —
"no intent to defraud or to conceal the state of his affairs". ¶69 grounds the principle in
\_Rickerby v Nicholson_ [1912] 1 IR 343 at 348 (Ross J): the word "or" is "often used … not to
connect real alternatives, but merely to connect different words expressing the same or a cognate
idea" — which is the exegetical row of §11.5's trichotomy, stated in 1912. See §12.7.)\_

### 11.5 ⭐ The trichotomy — one canon, three readings, all computable

Put the Singapore cases beside the US/UK ones and a **single meta-canon** — _the drafter wasted no
word_ — generates **three different readings depending only on the extensional relationship between
the two operand sets**:

| Extensional relation of `A`, `B`          | Forced reading                                    | Why (the same canon)                           | Authority                                                                                         |
| ----------------------------------------- | ------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| **`A ∩ B = ∅`** (disjoint)                | **UNION** — the `AND` is a join                   | the _intersective_ reading makes a term otiose | _Nam Hong_ [2016] SGCA 42; _A-G Bahamas v Royal Trust_ [1986] 1 WLR 1001; _Pulsifer_ (surplusage) |
| **`A ≡ B`** (co-extensive)                | **EXEGETICAL** — `or` = "alias", "that is to say" | the _alternative_ reading makes a term otiose  | _Koh Lau Keow_ [2013] SGHC 155; _Chichester_ (Lord Simonds); Picarda                              |
| **`A ∩ B ≠ ∅`, `A ≠ B`** (proper overlap) | **LITERAL** — take the connective as written      | no otiosity; **both terms do work**            | _Re Best_ [1904] 2 Ch 354; _Sit Kwong Lam_ [2018] SGCA 14                                         |

**The connective never changes meaning. The _sets_ do.** That is the whole insight, and it is why
this belongs in a language with a set type rather than in a style guide.

### 11.6 The decision procedure (supersedes §10.5)

```
DEFAULT           AND = ∧ (intersection)   OR = ∨ (union)          [Sit Kwong Lam ¶42]

DEFEATER 1        A ∩ B = ∅   ⇒  warn: the intersective reading is otiose.
                               "Did you mean UNION?"                [Nam Hong ¶26; Royal Trust]

DEFEATER 2        A ≡ B       ⇒  warn: the alternatives are co-extensive.
                               "Is this an exegetical OR (an alias)?"  [Koh Lau Keow ¶29-31]

ANTI-DEFEATER     the enclosing instrument uses AND *and* OR contrastively
                               ⇒  suppress. The drafter knew the difference.  [Sit Kwong Lam ¶43]

ESCAPE HATCH      AMBIGUOUS marker ⇒ suppress; the vagueness is deliberate.   [Allen 1957, §9.4]
```

Every line of that is mechanisable, and **every line has apex-court authority.** Defeater 1 and
the anti-defeater are cheap (an emptiness test; a scan of the enclosing `§` scope). Defeater 2
needs co-extensiveness, which for finite enumerated sets is just mutual subset — the very
`__EQUALS__` overload §D6 already requires.

**This supersedes §10.5's single empty-intersection lint.** Same idea, but the Singapore pair
supplies (i) the _default_ the lint deviates from, (ii) a _second_ defeater we had missed
entirely, and (iii) an _anti-defeater_ that will keep the false-positive rate down — which is the
difference between a lint people keep on and a lint people disable.

### 11.7 Why this matters beyond the lint

_Nam Hong_ and _Sit Kwong Lam_ are the **worked example the papers have been missing**: same court,
same Chief Justice, same word, opposite outcomes — and the difference is not linguistic intuition
but a **structural property of the denoted sets** that a compiler can check and a human reading
prose cannot. That is the "detect ≠ resolve" thesis with Singapore Court of Appeal authority
behind it, in the jurisdiction where L4's pilots actually run.

~~**TODO before publication:** pull the two SGCA judgments in full from elitigation (the lawplain
`body_text` truncates at 60k) and verify the paragraph numbers quoted above against the official
report.~~ **DONE 2026-07-18 — all four Singapore judgments verified first-hand against
elitigation; see §12.7.**

## 12. Citation verification against primary sources

Verifying the citations flagged as unverified in §9.6 and §10.4 against primary sources, across
several passes and providers: legal-data-hunter / official U.S. Reports (§12.1–12.3, 2026-07-15),
BAILII (§12.5–12.6), and elitigation (§12.7). Pass 1 pulled **_Pulsifer_ from the official U.S.
Reports preliminary print (601 U.S. 124–186)** — so the pin cites below are to the **official
pagination**, not the slip opinion.

### 12.1 Verified verbatim, with pin cites

| Claim (as written in §10.1)                                              | Status          | Pin cite                |
| ------------------------------------------------------------------------ | --------------- | ----------------------- |
| "two grammatically permissible ways … not a matter of grammatical rules" | ✅ **verbatim** | 601 U.S. at **133**     |
| "Really, it all depends."                                                | ✅ **verbatim** | 601 U.S. at **140**     |
| drink-and-drive vs. eat-and-drink-before-surgery                         | ✅ **verbatim** | 601 U.S. at **141**     |
| Gorsuch's "charitable and educational institutions"                      | ✅ **verbatim** | 601 U.S. at **166–167** |

Bonus catch (majority, at 140): the Court notes **the dissent concedes the point** — "even the
dissent must in the end concede … that whether a speaker 'intend[s] for a listener to distribute
words implicitly' depends on the context."

### 12.2 Two gaps from §9.6 now closed — and **Kirk is fully vindicated**

Pass 1 wrongly told us to discard Maurice Kirk (§10.7 already flagged this; here is the receipt):

> **"M. Kirk, _Legal Drafting: The Ambiguity of 'And' and 'Or_,' 2 Tex. Tech. L. Rev. 235, 239–240
> (1971)"** — cited by **Gorsuch, J., dissenting**, 601 U.S. at 166.

Alongside him, two more pass-1 gaps close:

- **Reed Dickerson**, _The Fundamentals of Legal Drafting_ § 6.2, pp. 109–110 (2d ed. 1986) —
  cited by Gorsuch at 166. (Pass 1 only ever saw Dickerson second-hand.)
- **Senate Office of the Legislative Counsel, _Legislative Drafting Manual_ 64–65 (1997)** — cited
  by Gorsuch at ~161. **This is the legislative-drafting-manual authority pass 1 declared
  "effectively UNANSWERED."**

And **Ken Adams is cited by the _majority_** (601 U.S. at 136–37) — for the _distributed_ reading
under a negative:

> "a manual of contract drafting observes that '[t]he more natural meaning' of '**Acme shall not
> notify Able and Baker**' is '**Acme shall not notify Able and shall not notify Baker**' …
> K. Adams, _A Manual of Style for Contract Drafting_ § 11.16, p. 212 (3d ed. 2013)."

So Adams lands on the Government's side of the De Morgan question. Gorsuch cites him too
(§§ 11.9–11.11, p. 211) — **both opinions cite MSCD.**

### 12.3 ⭐ A **fourth** trigger, and it is already L4's type distinction

Kirk and Dickerson, via Gorsuch (601 U.S. at 166–67), locate the ambiguity in **grammatical
number** — and say so in terms that are, for us, startling:

> "that '**singular**' construction '**tends to avoid the ambiguity**' about distribution that a
> '**plural**' construction can invite. … The multiple '**institutions**' might distribute across
> the multiple listed traits to describe both 'charitable institutions and educational
> institutions.' … Or the term 'institutions' might not distribute, so the phrase describes only
> institutions that are both charitable and educational. **But if there is just a single
> 'institution,' any ambiguity dissipates**: 'A charitable and educational institution' is an
> institution with both traits."

Read that again with L4's types in mind:

| Surface form                                      | Grammatical number | What `AND` is doing                                     | L4 type   |
| ------------------------------------------------- | ------------------ | ------------------------------------------------------- | --------- |
| "a charitable **and** educational institution"    | **singular**       | Boolean conjunction of two **predicates** on one entity | `BOOLEAN` |
| "charitable **and** educational institution**s**" | **plural**         | join over two **collections**                           | `Set a`   |

**The courts' "number" trigger _is_ L4's type distinction.** Singular head ⇒ scalar ⇒ predicate
conjunction (∧), unambiguous. Plural head ⇒ collection ⇒ `Set`-valued, and the union reading
becomes available. This is the same discriminator Heycock & Zamparelli reach (number, not the
conjunction — §9.3), the same one Winter reaches (WS blocked under the indefinite article — §10.3),
and now the same one the Supreme Court of the United States reaches by way of a 1971 Texas Tech law
review article.

**Four independent traditions, one discriminator, and it is the thing our type checker already
computes.** That is the strongest argument in the whole spec for doing this in a typed language
rather than a style guide — and it means §D4's type-directed dispatch is not a hack but a
_reconstruction of the legal test_.

**Amend §11.6:** add number/arity as the **zeroth** check — if the operands are scalars, `AND` is
`∧` and no diagnostic fires at all. The defeaters only ever apply to `Set`-typed operands.

### 12.4 English/Commonwealth line — verification status

**legal-data-hunter has _zero_ sources for GB** (`discover_sources("GB")` → `[]`), so first-hand
verification of the English/Commonwealth cases had to come from elsewhere. Current status:

| Case                                                    | Status                             | Source of verification                               |
| ------------------------------------------------------- | ---------------------------------- | ---------------------------------------------------- |
| _A-G of the Bahamas v Royal Trust Co_ [1986] 1 WLR 1001 | ✅ **VERIFIED first-hand** (§12.5) | BAILII [1986] UKPC 34 (PDF)                          |
| _Chichester Diocesan Fund v Simpson_ [1944] AC 341      | ✅ **VERIFIED first-hand** (§12.6) | BAILII [1944] UKHL 2 (full HTML)                     |
| _Re Best_ [1904] 2 Ch 354                               | 🟡 second-best (§12.6)             | **characterised by the HL in verified _Chichester_** |
| _Re Eades_ [1920] 2 Ch 353                              | 🟡 second-best                     | quoted _in Royal Trust_, now verified (§12.5)        |

**No case now rests on secondary reproductions alone.** _Re Best_ is the only one whose _own
report_ is still unobtained — but its holding is no longer uncorroborated: the House of Lords in
_Chichester_ (verified) describes it directly (§12.6). For publication it is still worth pulling
the _Re Best_ report itself from **ICLR / Westlaw / HeinOnline**, but it is no longer a bare
citation risk, and _Re Eades_ [1920] 2 Ch 353 (cited inside _Royal Trust_) stands as a further
same-line fallback.

### 12.5 ✅ _Royal Trust_ retrieved and verified — BAILII [1986] UKPC 34

Retrieved the full judgment PDF from BAILII (2026-07-15). Getting to it was the "**Beware of the
Leopard**" experience — the notice _was_ on display, just: behind an **Anubis JS proof-of-work
wall** (a `200` is a disguised "Making sure you're not a bot!" challenge; `curl`/WebFetch get the
wall, only a real browser clears it); at an **unguessable filename** (`1986_34.pdf`, not the
expected `34.html`); as a **PDF-only** page ("A HTML version of this file isn't available"); with
**no text layer** (image scan — screenshot-read page by page). CommonLII, for its part, returns
**0 documents** for the case despite holding _Bahamas Law Reports (Solomon)_.

**Everything in §10.4 / §11.4 now confirmed against the primary source:**

| Element                              | Confirmed                                                                                                                                     |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Neutral / parallel citations         | **[1986] UKPC 34 = [1986] 1 WLR 1001 = [1986] 3 All ER 423** (BAILII header)                                                                  |
| Court below / appeal no.             | Court of Appeal of the Commonwealth of the Bahamas; PC Appeal No. 37 of 1984                                                                  |
| Date                                 | delivered **23 June 1986**                                                                                                                    |
| Board                                | Lords Keith of Kinkel, Templeman, Griffiths, **Oliver of Aylmerton**, Goff of Chieveley                                                       |
| Author of the advice                 | **"[Delivered by Lord Oliver of Aylmerton]"** — as §11.4 stated                                                                               |
| Ratio (verbatim)                     | "the phrase '**education and welfare**' in this will **inevitably falls to be construed disjunctively**" (agreeing with **Blake C.J.** below) |
| Otiosity reasoning (verbatim, twice) | "for otherwise **the word becomes otiose**"; "the reference to 'welfare' would **again become otiose**"                                       |
| Authority relied on                  | **_Re Eades_ [1920] 2 Ch 353** (Sargant J) — the conjunctive/disjunctive dichotomy, "the change of the word 'and' into 'or'"                  |

**Bonus for §11.5:** the Board's reasoning is a clean, negation-free `AND`→disjunctive holding
whose engine is _explicitly_ otiosity — first-hand primary-source confirmation of the trichotomy's
top row, in the exact terms the spec predicted. And it independently surfaces _Re Eades_ as a
second authority in the same line.

**Correction to an earlier prediction:** §12.4 previously guessed BAILII's `UKPC` collection was
"substantively post-1996." Wrong — BAILII has backfilled 1986 (the case is [1986] UKPC 34). The
obstacle was never coverage; it was the Leopard.

### 12.6 ✅ _Chichester_ retrieved — and it cracks _Re Best_ second-hand

Searching BAILII for _Re Best_ (2026-07-15) returned **0 matches** across two queries (the "Re
Best" hits are all modern _best-interests_ cases). **_Re Best_ [1904] 2 Ch 354 is not on BAILII**
— unsurprising, as BAILII's free English holdings skip Law Reports Chancery of that vintage.

But the same search surfaced **_Chichester Diocesan Fund v Simpson_ [1944] UKHL 2** (= [1944] AC
341 = [1944] 2 All ER 60) as **full text** — and it does double duty:

1. **It verifies §11.3's _Chichester_ dictum first-hand.** The House of Lords holds "charitable
   **or** benevolent" void for uncertainty because the words do not coincide — _"the two words
   'charitable' and 'benevolent' do not ordinarily mean the same thing; they overlap … but also
   [each covers] something which is not covered by the other"_ — and confines the exegetical
   reading to _"an exegetical link between convertible and equivalent synonyms."_ That is exactly
   the `A ≡ B` co-extensiveness precondition of the trichotomy's EXEGETICAL row (§11.5), in the
   Lords' own words.

2. **It characterises _Re Best_ directly**, which is the next best thing to the report itself:

   > "the strict rule only applies if … the two substantives or adjectives are to be read
   > disjunctively. If they are to be read conjunctively, then there is only one class or area of
   > selection, and if that is charitable, the bequest is good. **Such a case is illustrated by
   > _in re Best_, 1904, 2 Ch. 354, where the two adjectives 'charitable' and 'benevolent,'
   > coupled it is true by 'and' … were held to describe a single class, the members of which
   > combine the qualities of charitable and benevolent.**"

   That is precisely the §10.4 / §11.5 claim for _Re Best_ — "charitable **and** benevolent" read
   **conjunctively** ⇒ one (non-vacuous) class ⇒ gift **valid** — now underwritten by a verified
   House of Lords speech. The trichotomy's "proper overlap ⇒ literal/conjunctive" row is
   confirmed against primary authority even though the 1904 report stayed out of reach.

**Net effect on §12.4:** two rows upgrade at once. _Chichester_ 🟡→✅ (first-hand), and _Re Best_
🔴→🟡 (characterised inside verified _Chichester_). No claim in this document now rests on
secondary reproductions alone.

### 12.7 ✅ The Singapore quartet verified against elitigation (2026-07-18)

Closes §11.7's TODO. All four Singapore judgments pulled in full from elitigation
(`https://www.elitigation.sg/gd/s/<year>_<court>_<no>` — no bot wall, unlike BAILII's Leopard),
and every quoted paragraph checked against the official text:

| Case                           | Source          | Checked                              | Result                                                                                                                             |
| ------------------------------ | --------------- | ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| _Nam Hong_ [2016] SGCA 42      | `2016_SGCA_42`  | coram; statute; ¶19; ¶26             | ✅ all verbatim. Menon CJ authored. Definition is "specialist building works" para (d), Building Control Act (Cap 29, 1999 Rev Ed) |
| _Sit Kwong Lam_ [2018] SGCA 14 | `2018_SGCA_14`  | coram; BMSMA definition; ¶42; ¶43    | ✅ verbatim, **one pin-cite correction**: ¶42 cites the **HC** decision _Kori v Nam Hong_ [2015] 2 SLR 616, not [2016] SGCA 42     |
| _Koh Lau Keow_ [2013] SGHC 155 | `2013_SGHC_155` | judge; Picarda ¶28; ¶29; holding ¶31 | ✅ all verbatim. Tay Yong Kwang J. Picarda is 4th ed (2010) p 330                                                                  |
| _Low Kok Heng_ [2007] SGHC 123 | `2007_SGHC_123` | judge; catchwords; ¶69               | ✅ all verbatim. V K Rajah JA. Emphasis in ¶69 falls on "every"                                                                    |

Two small dividends beyond confirmation:

1. **The pin-cite correction in _Sit Kwong Lam_ ¶42** (HC citation, not CA) — exactly the class
   of error this verification campaign exists to catch before a reviewer does.
2. **_Rickerby v Nicholson_ [1912] 1 IR 343 at 348** surfaces inside verified ¶69 as the
   root authority for the exegetical `or` — "not to connect real alternatives, but merely to
   connect different words expressing the same or a cognate idea." The trichotomy's EXEGETICAL
   row now has an Irish 1912 ancestor beneath Picarda and _Koh Lau Keow_.

**Verification ledger, whole spec:** every case cited in §§10–12 is now either ✅ first-hand
(_Pulsifer_, _Royal Trust_, _Chichester_, _Nam Hong_, _Sit Kwong Lam_, _Koh Lau Keow_,
_Low Kok Heng_) or 🟡 characterised inside a verified primary source (_Re Best_, _Re Eades_,
_Rickerby_). The only remaining publication nicety is pulling _Re Best_ [1904] 2 Ch 354 from a
paid reporter (ICLR / Westlaw / HeinOnline).
