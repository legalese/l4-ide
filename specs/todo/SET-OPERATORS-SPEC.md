# Set-Theoretic Operators for L4

> **Status (2026-07-28):** Phases 1–3a and 3d are SHIPPED in the prelude on `unstable` (`SET OF a`,
> `UNION`/`INTERSECT`/`` `LESS` ``/`WITHOUT`, `PLUS`/`MINUS`/`EQUALS` overloads, variadic
> `SET OF`, fixity annotations). The `AND`/`OR`-on-sets half of Phase 2 is **REVERSED — see §16**:
> those two overloads were removed from the prelude on 2026-07-28 for a measured exponential
> typechecking cost ([smucclaw/l4-ide#929](https://github.com/smucclaw/l4-ide/issues/929)).
> Phase 4 (the lint) remains unbuilt. Earlier sections are retained unrenumbered because code and
> goldens cite them; read §D4, §5, §6 Phase 2, §9.5, and §10.5 together with §16.
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
  grammar with a **declared precedence table** (`Parser.hs:1496-1522`) — plus the thing legal
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

| Thing                      | Status                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A `SET` type               | **Does not exist.** L4 has `LIST OF a` only.                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Operator overloading       | **Exists**, via magic names. `jl4-core/src/L4/TypeCheck/Environment.hs:81-95` maps `__PLUS__`, `__MINUS__`, `__TIMES__`, `__DIVIDE__`, `__LT__`, `__LEQ__`, `__GT__`, `__GEQ__`, **`__AND__`**, **`__OR__`**, `__NOT__`, `__CONS__`, `__EQUALS__`.                                                                                                                                                                                                                        |
| How you overload           | Define a function with the magic name; resolution is **by argument type**. See `jl4/examples/ok/overloaded.l4`, which overloads `PLUS`/`MINUS`/`TIMES`/`LESS THAN` for a `Vector` record.                                                                                                                                                                                                                                                                                 |
| Library-defined containers | **Precedent exists.** `Dictionary` is declared _in the prelude_, not the compiler: `DECLARE Dictionary k v HAS contents IS A LIST OF PAIR OF k, v` (`jl4-core/libraries/prelude.l4:793`), with `dictUnion` / `dictUnionWith` alongside.                                                                                                                                                                                                                                   |
| `LESS`                     | Token **already exists** (`Lexer.hs:281`, `TKLess`) but the parser only ever consumes it as the two-token sequence `LESS THAN` → `Lt` (`Parser.hs:1491`). **Bare `LESS` is unclaimed.**                                                                                                                                                                                                                                                                                   |
| `PLUS` / `MINUS`           | `Lexer.hs:274-275`; precedence 6, `AssocLeft` (`Parser.hs:1492-1493`).                                                                                                                                                                                                                                                                                                                                                                                                    |
| `AND` / `OR`               | Precedence 3 / 2, `AssocRight` (`Parser.hs:1484-1485`).                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Mixfix operators           | **Exist** (`specs/done/mixfix-operators.md`). Let a library define `a UNION b MEANS …` with **no lexer change** — bare, no backticks: _"backticks simply allow identifiers to contain whitespace… you may omit them entirely"_ (verified live 2026-07-18, §5.1). Backticks are needed only for **multi-word names** (`` `is in` ``) and **keyword-colliding names** (`` `LESS` `` — bare `LESS` is a lexer keyword). Mixfix has **no precedence** (parentheses required). |

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

**Status upgrade (machine-verified 2026-07-18): these overloads are not mere aliases — they are
currently the _only_ bare-and-precedence-correct spellings.** Because `PLUS`/`MINUS` are keyword
operators in the parser's table (prio 6, `AssocLeft`) that desugar to overloadable magic names,
the D3 overloads inherit **real precedence and associativity** with zero compiler work. Verified
live: `setSize (a1 MINUS b1)` → 1, `setSize (a1 PLUS b1)` → 4, `5 MINUS 2` → 3 (numeric
dispatch untouched), and the unparenthesized compound **`a1 PLUS b1 MINUS b1` → `{1}`** —
left-associated at prio 6, no parens, no backticks. Until Q5 resolves, `MINUS` is therefore the
ergonomic recommendation for set difference in running text (Oracle SQL precedent, §D6), with
`LESS` remaining the aspirational drafting canon pending Phase 3c. The trap warning above
applies with full force — the lint should fire on these spellings too.

### D4 — `AND` on sets: overload it, then _lint_ it. (The important one.)

> **REVERSED 2026-07-28 (Meng) — see §16.** The "resolve" half of this decision shipped and was
> then removed: a second `__AND__`/`__OR__` candidate makes typechecking exponential (base 3) in
> `AND`/`OR` chain **depth** ([smucclaw/l4-ide#929](https://github.com/smucclaw/l4-ide/issues/929)).
> Term-level union is spelled `UNION` explicitly; `AND`/`OR` on sets is a type error. The
> "detect" half (the lint) survives unchanged in principle — the detection site is now the type
> error itself. Reinstatement is contingent on a typechecker memoisation fix; §16 has the
> measurements and the contingency.

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

| Route                         | Cost                                                  | Gets you                                                                                                                                 |
| ----------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **A. Mixfix, in the prelude** | Zero compiler change.                                 | **`A UNION B` — bare, today** (§5.1-verified). But **no precedence** (parens for anything compound), and no bare `LESS` (lexer keyword). |
| **B. Real keywords**          | Lexer entries + precedence-table rows in `Parser.hs`. | `A UNION B INTERSECT C` — correct precedence, plus bare `LESS`.                                                                          |

**Decision: Phase 1 ships route A** (prove the semantics, zero risk), **Phase 2 promotes to route
B** once the vocabulary settles. Route A is better than this table originally believed — the
production spellings `A UNION B` / `A INTERSECT B` already work bare — so what B actually buys
is **precedence** and **bare `LESS`**, not de-backticking. In Phase 1, set difference either
wears backticks (``A `LESS` B``) or ships bare under a keyword-free alias — **`WITHOUT` and
`EXCEPT` are both unclaimed identifiers** (verified against `Lexer.hs`; of the §D2 vocabulary
only `LESS` and `MINUS` are keywords).

**Proposed precedence for route B**, slotting into the table at `Parser.hs:1496-1522`:

| Operator    | Prio | Assoc       | Rationale                                                                                                                   |
| ----------- | ---- | ----------- | --------------------------------------------------------------------------------------------------------------------------- |
| `UNION`     | 6    | `AssocLeft` | Mirrors `PLUS` (6). Union is the additive join.                                                                             |
| `LESS`      | 6    | `AssocLeft` | Mirrors `MINUS` (6).                                                                                                        |
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

**Post-decision corroboration — the backtick retraction (§5.1 finding 1) strengthens α
a fortiori.** That episode was an accidental controlled experiment in keyword cost versus
identifier cost, and every arm of it points the same way:

1. **`LESS` is the cautionary tale for β.** Everything that went wrong in the probe — the
   baffling error three tokens from the fault, the backtick-escaping, the pending `try` fix —
   happened _because `LESS` is a lexer keyword_ squatting on a word that wanted to be an
   identifier. β would do precisely that to `SET`, a word that must simultaneously keep working
   as a name in `DECLARE` heads, type applications, `WITH` constructions, and patterns.
2. **`UNION`/`INTERSECT` bare are the advertisement for α's world.** They deliver the production
   surface at zero cost _because they are not keywords_. `SET` currently enjoys the same status;
   β would revoke it, α preserves it.
3. **α's mechanism is house style, not a novelty.** The December-2025 change
   (`mixfix-operators.md`): the typechecker already reinterprets misparsed
   `App operand [keyword]` fragments so postfix mixfix works unparenthesized — rescue-by-
   elaboration, applied only where the parse-level reading would be a type error. α is the same
   bargain, with the same conservative-extension bound.
4. **β's residual payoff shrank to the `OF`-less spelling `SET 1, 2, 3`** — its polish argument
   evaporated with the backtick retraction, and `SET OF 1, 2, 3` is arguably the better legal
   register anyway ("the set of A, B, and C").

The honest cost of α, for the record: each elaboration rule makes checker behaviour slightly
less predictable from syntax alone. The conservative-extension property is the containment —
α only assigns meaning to programs that are errors today, so it cannot change any existing
meaning. Same bargain as December 2025.

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

> **Note (2026-07-28):** the `__AND__`/`__OR__` lines of this sketch shipped and were then
> removed — see §16. The `__PLUS__`/`__MINUS__` lines remain in the prelude.

## 5. Worked example — the two ANDs, side by side

> **AMENDED 2026-07-28 by §16:** the term-level line of this acceptance test is now written
> `` `eligible` MEANS `new yorkers` UNION `new jerseyans` `` — `AND` between two sets is a type
> error, pinned by `jl4/examples/not-ok/tc/set-and-unoverloaded.l4`. The shipped acceptance test
> is `jl4/examples/ok/set-operators-overloads.l4`.

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
   branch, which fails hard with no `try`. Backticked ``A `LESS` B`` escapes the keyword and
   works. First-hand confirmation that `Parser.hs:1491` is the highest-risk line — and the
   reason Phase 1 difference is either backticked or spelled `WITHOUT`/`EXCEPT` (both unclaimed
   identifiers; §D5).
3. **Mixfix has no precedence against juxtaposition**: ``f x `set equals` y`` needs
   ``(f x) `set equals` y``. Also `WITH` record construction resists a less-indented
   continuation line — prefer `setFromList (…)` over multi-line `SET WITH contents IS …`.

Prelude inventory note: `nub` (dedup), `elem` (membership), and `append` all exist already —
the §4 sketch's helper burden is smaller than drafted.

## 6. Implementation phases

_(Restructured 2026-07-18: the old "Phase 3 — keywords + precedence" bundled three unrelated
things, one of which is now under active challenge. Split into 3a/3b/3c so each can land — or
die — on its own merits.)_

- **Phase 0 — spec review.** This document. **COMPLETE 2026-07-18**: D1–D7, Q2, Q4, Q5,
  α-vs-β, and the Q3 fence all settled (Q3's substantive distribution semantics deferred to
  the EVERY-EACH joint read, by design).
- **Phase 1 — prelude landing, zero compiler change.** `SET OF a` + `is in`, bare `UNION`, bare
  `INTERSECT`, `` `LESS` `` (backticked — lexer keyword; consider bare `WITHOUT`/`EXCEPT` as the
  drafting-canon alias, both verified unclaimed), `subset`, `setSize`, list↔set conversions,
  over prelude `nub`/`elem`/`append`. Golden tests in `jl4/examples/ok/set-operators.l4`.
  **Prototyped and verified 2026-07-18 — the §5.1 probe runs all ten `#EVAL`s green on today's
  compiler**; landing it is transcription, not development.
- **Phase 2 — the overloads.** `__PLUS__`, `__MINUS__`, `__AND__`, `__OR__` on `SET OF a`. Add
  the §5 worked example as the acceptance test. This is where the paper-worthy behaviour
  appears. **PARTIALLY REVERSED 2026-07-28 (§16):** `__PLUS__`/`__MINUS__` (and the §D6
  `__EQUALS__` guard) stay; `__AND__`/`__OR__` are removed for the measured exponential
  typechecking cost, pending memoisation.
- **Phase 3a — route-α elaboration** (§D7.1, DECIDED): variadic construction
  `SET OF 1, 2, 3` via argument-collection in the typechecker. First compiler-touching change;
  independent of everything below.
- **Phase 3b — precedence for identifier operators: REOPENED, BUILT as option A, in the merge queue (§13.2 outcome).**
  The original assessment recommended building nothing (the §D3/§D4 overloads cover the
  capabilities; the only residual gap was the literal words `UNION`/`INTERSECT` carrying
  precedence). Meng then greenlit the fixity mechanism as a decoupled timeboxed spike, and it
  **shipped as PR [legalese/l4-ide#128](https://github.com/legalese/l4-ide/pull/128)** (see
  §13.2 OUTCOME): `@infixl`/`@infixr`/`@infix N` declarations for binary identifier operators,
  the flat-App re-association proving out exactly as §13.1 predicted, adversarially reviewed
  and green — **in the merge queue as of 2026-07-18, not yet on `unstable`.**
  **Q5 answer upgraded from (C)+(D) to option A.**
- **Phase 3d — prelude fixity landing (follow-up unlocked by Phase 3b).** Once #128 lands
  (in the merge queue as of 2026-07-18), add
  the fixity declarations to the set vocabulary in the prelude: `@infixl 6` on `UNION` and
  `WITHOUT`/`EXCEPT` (same precedence, both left-associative), `@infixl 7` on `INTERSECT` (binds
  tighter, à la ×/+ — so `a UNION b INTERSECT c` groups as `a UNION (b INTERSECT c)`). Purely
  prelude annotations, zero compiler change; because there is no default fixity this is a strict
  conservative extension. Then §D5 route B (keywordizing `UNION`/`INTERSECT`) is **formally
  buried** — no keyword tax was ever needed — and Phase 3c's `LESS`-as-`Minus` alias remains the
  only reason to touch the keyword operator table.
- **Phase 3c — bare `LESS`**, if ever: unreachable via fixity (a fixity mechanism cannot rescue
  a word the lexer already owns), but there is now a **discovered cheap design — `LESS` as a
  surface alias for the `Minus` node.** Restructure the operator-table entry at `Parser.hs:1491`
  to consume `TKLess` then branch on an _optional_ `TKThan`: with `THAN` → `Lt` at prio 4
  (today's behaviour, unchanged); without → the `Minus` builder at prio 6. Roughly five lines;
  no lexer change (`TKLess` exists); no new magic name (rides `__MINUS__`, so sets get
  difference by the D3 overload and numbers get "the salary `LESS` deductions" — genuinely good
  drafting register — for free); and the restructure _subsumes_ the `try` fix rather than
  adding to it. **Untried as of 2026-07-18** — nobody has yet built the `try`/`optional`
  variant; needs a feature-branch spike with regression tests around `LESS THAN`
  (comparison unchanged, layout edge cases, error quality).
  _Considered and rejected (Meng's quip, 2026-07-18): `THAN` as a high-precedence identity
  operator, so `LESS` "works magic like `MINUS`" and `LESS THAN` reduces to `LESS`._ The
  identity version is unsound — `x LESS THAN y : BOOLEAN` and `x LESS y : NUMBER` would become
  the same expression, erasing the only token overload resolution could dispatch on. The
  repaired version (`THAN : a → Comparand a`, a marker constructor; `__LESS__` dispatches on
  the wrapper) is sound and would even make comparison user-extensible — but it needs _more_
  parser surgery than the optional-`THAN` design above, and extensible comparison is more
  directly had by relaxing `__LT__`'s `variants` pin (`Environment.hs:86`). Dominated on every
  axis by boring alternatives; recorded because the failure mode (a transparent operator
  erasing a type distinction) is exactly this spec's subject matter in miniature.
- **Phase 4 — the lint.** Diagnostic + quick-fix per the §11.6 decision procedure (zeroth
  check: scalar operands exit; Defeater 1 empty-intersection; Defeater 2 co-extension;
  anti-defeater contrastive-connective scan; `AMBIGUOUS` escape hatch), hung off
  `Lint/AndOrDepth.hs`. Independent of 3a–3c. This is the part that turns a language feature
  into a _product_ feature.

## 7. Open questions

- **Q1 — `Set` vs `LIST` ergonomics.** Do we auto-coerce `LIST OF a` → `Set a` at operator sites?
  Convenient, but silent coercion is exactly the kind of magic that costs us explainability.
  Leaning **no**: require explicit `setFromList`.
- ~~**Q2 — What does `OR` on two sets mean?**~~ **RESOLVED — `UNION`, same as `AND`.** The
  collapse is real (Adams & Kaye's "ironic twist"), it is a defeasible default rather than a
  semantics, and the lint carries the disambiguation load. See §9 (authorities), §9.5
  (consequences for §D4), §11.6 (decision procedure). _(2026-07-28: the semantic answer stands —
  both connectives on sets denote union — but neither is an overload any more; both are written
  `UNION`. See §16.)_
- **Q3 — Sets of parties and deontics.** "Residents of NY and NJ **must** file" distributes an
  obligation over a set of parties. That is the same distribution question as
  [`EVERY-EACH-QUANTIFIER-SPEC.md`](EVERY-EACH-QUANTIFIER-SPEC.md), and it touches the
  actor-indexed action work. Needs a joint read; do not design in isolation.
  **ADOPTED (Meng sign-off, 2026-07-18) — fence it, don't decide it:** Phases 1–4 define sets in the
  _constitutive_ layer only; this spec assigns **no meaning** to a `SET OF`-typed term in the
  party position of a deontic. The distribution menu — one several obligation per member?
  joint? joint and several? collective? — is precisely the common-law joint/several-liability
  taxonomy, and it must be designed with the EVERY-EACH and actor-indexed-actions machinery,
  not smuggled in under a set-operators spec. The fence costs nothing today (nothing in
  Phases 1–2 touches `PARTY` positions) and prevents accidental semantics from leaking in
  the meantime.
- ~~**Q4 — Ordering/canonicalization.**~~ **RESOLVED — see §D6.**
- **Q5 — Precedence via fixity declarations instead of keywords?** (Opened 2026-07-18, from the
  §5.1 backtick retraction.) Since identifier operators already work bare, keywordizing
  `UNION`/`INTERSECT` (§D5 route B) buys _only_ precedence — at the keyword tax `LESS`
  exemplifies. A Haskell-`infixl`/`infixr`-style **fixity declaration** for identifier
  operators (e.g. a decorator on the operator's definition) would deliver precedence while
  keeping the words ordinary identifiers, and would generalize to every future library
  operator, not just the set vocabulary. GHC precedent: fixity is not a parser feature —
  operator chains parse provisionally and the renamer re-associates. L4 analogue: re-associate
  in the same phase as (or adjacent to) the December-2025 misparsed-`App` reinterpretation.
  Note the limit: fixity cannot rescue lexer keywords, so bare `LESS` is out of its reach
  regardless (Phase 3c). **Assessment of implementation cost in progress; decides Phase 3b.**
  And note a **third option with real support in this spec's own framing: no precedence, ever.**
  L4's mixfix already _"deliberately refuses implicit precedence"_ (§0), and §0's rung 1 says
  implicit precedence is exactly how `8÷2(2+2)` happens. On that view `A UNION B INTERSECT C`
  _should_ be a parse error demanding parentheses, and Phase 3b is not deferred but rejected.
  The ladder visualizer weakens the worry (the binding is always renderable), but for a
  drafting canon, mandatory explicit grouping may be the more on-message answer. And there is a
  **fourth option, which exists today and is verified (§D3): ride the overloadable keyword
  operators.** `PLUS`/`MINUS` (and `AND`/`OR`, §D4) already sit in the parser's precedence
  table and desugar to magic names, so their `Set` overloads are bare _and_ precedence-correct
  now — `a1 PLUS b1 MINUS b1` evaluates unparenthesized. Coverage: union (`PLUS`, `AND`, `OR`)
  and difference (`MINUS`, plus `LESS` after the Phase-3c alias) — but **not intersection**
  (no keyword to ride; `TIMES` rejected by §D3). So the Q5 decision is four-way:
  (A) fixity declarations, (B) keywords, (C) parens forever, (D) keyword-operator overloads —
  with D already in hand and A/B/C only needed for what D cannot cover (`UNION`/`INTERSECT`
  as _words_ with precedence).
  **RESOLVED (Meng sign-off, 2026-07-18): (C)+(D) adopted for this spec; (B) dead; (A)
  proceeds as the decoupled experiment per
  [`FIXITY-DECLARATIONS-SPEC.md`](FIXITY-DECLARATIONS-SPEC.md).**
  **REOPENED (2026-07-18): (A) DONE — PR
  [legalese/l4-ide#128](https://github.com/legalese/l4-ide/pull/128), green and in the merge
  queue (branch HEAD `e61dbf30`); not yet on `unstable`.** Final Q5 disposition: **(A) fixity**
  is the answer for
  `UNION`/`INTERSECT` as words with precedence; (D) keyword-operator overloads remain in hand
  for the union/difference vocabulary; (B) keywords are dead; (C) parens-forever is superseded
  by (A) but stays available for any operator left undeclared (there is no default fixity).
  Follow-up: Phase 3d adds the prelude `@infixl` annotations. See §13.2 OUTCOME.

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

> **Items 1–2 REVERSED 2026-07-28 (§16)** — not on the merits argued here, which stand, but on a
> measured implementation cost: the overloads make typechecking exponential in `AND`/`OR` chain
> depth. Items 3–4 (lint both connectives; the deliberate-ambiguity marker) remain live for
> Phase 4, with the type error currently doing the surfacing work.

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

> _(Item 1 REVERSED 2026-07-28, §16 — the overloads are removed; the non-vacuity diagnostic of
> items 2–4 remains the Phase-4 design, now advising on explicit `UNION`/`INTERSECT` sites.)_

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

## 13. Fixity-declaration assessment (Q5) — subagent report, 2026-07-18

Full A–E assessment of a Haskell-`infixl`/`infixr`-style fixity mechanism for identifier
operators, run read-only against the tree with `l4`-binary probes. Distilled here; the verdict
reshapes Phase 3b.

### 13.1 Architecture findings

- **GHC model:** fixity is resolved in the _renamer_, not the parser — operator chains parse to
  a provisional flat shape and are re-associated once fixities are in scope. Fixity is
  module-scoped, imports carry it, undeclared defaults to `infixl 9`. (Agda/Coq resolve at
  parse time via precedence graphs — more powerful, far more invasive.)
- **L4 is already GHC-shaped, by accident.** Bare `1 UNION 2 INTERSECT 3` parses today to a
  **flat n-ary App** — `App UNION [1, 2, App INTERSECT [], 3]` (`mixfixChainExpr`,
  `Parser.hs:1643-1676`; verified via `l4 ast`). That is exactly the pre-renamer input a
  re-association pass wants, sitting in parser output for free. Today the Dec-2025 matcher
  fails such chains on arity — `matchLinearAfterHeadKeyword` requires equal lengths
  (`TypeCheck.hs:2945`) — verified: even `1 UNION 2 UNION 3` errors; parenthesized works. So
  identifier operators currently have _neither_ precedence _nor_ associativity.
- **Minimal design, if ever built:** an `@infixl 6`-style **decorator** on the operator's
  definition, riding the existing `@desc`/`@export`/`@nlg` annotation rail (no new keyword, no
  new decl form); a **shunting-yard pre-pass in the typechecker** at the `App` inference site
  (the parser's mixfix registry is module-local — `Parser/MixfixRegistry.hs:56-73` — only the
  typechecker's registry unions imports, `TypeCheck.hs:190`); fixity ships with the registry
  (one extra map-union in `unionMixfixRegistry`, `TypeCheck/Types.hs:359-364`); **no default
  fixity** — undeclared chains stay parens errors, so the feature is strictly additive; the
  keyword table is untouched, cross-family precedence stays parens-mandatory.
- **Cost: ~5–8 person-days.** Crux (M/L): disambiguating binary-operator chains from genuine
  n-ary mixfix patterns (identical flat shape — must not steal `if/then/else`), and keeping
  source-range annotations honest through re-association (`rebuildMixfixAppAnno` is 2-hole
  today; wrong holes silently break `#EVAL` lenses, `TypeCheck.hs:3033-3039`).

### 13.2 Verdict: build nothing for this spec

With the §D3/§D4 overloads verified (union bare-and-precedenced three ways — `PLUS`, `AND`,
`OR`; difference one way — `MINUS`), **the capabilities are covered and fixity's unique residual
payoff is the literal words `UNION`/`INTERSECT` carrying precedence — a register preference,
not a capability gap.** Even intersection has a latent precedence-correct ride: `__TIMES__`
exists at prio 7 > `PLUS`'s 6 (`Environment.hs:83`), declined on §D3's register grounds.
5–8 days with an M/L disambiguation risk does not clear that bar.

The general argument — every future library operator gains precedence; operators stay ordinary
identifiers (no keyword tax, no `LESS` problem); the parse shape and import plumbing fit like a
glove — **remains sound, and fixity is the right shape if L4 ever commits to user-declared
precedence as a language feature.** But that is a **platform investment to schedule on its own
merits, decoupled from set operators** — build it when a second or third library wants
declared-precedence operators, not to precedence-enable one word.

**Q5 recommendation: (C) + (D).** Compound identifier-operator expressions parenthesize —
consonant with §0's own PEMDAS framing and mixfix's deliberate refusal of implicit precedence —
while the keyword-operator overloads carry the bare ergonomics. (B) keywords: dead. (A) fixity:
rescheduled to the platform backlog (candidate for `specs/roadmap/`). Signed off (Meng,
2026-07-18).

**UPDATE (Meng, 2026-07-18): option A greenlit as a decoupled, timeboxed EXPERIMENT** — branch
brief at [`FIXITY-DECLARATIONS-SPEC.md`](FIXITY-DECLARATIONS-SPEC.md), to be attempted in a
parallel session. The verdict above stands as a _dependency_ ruling: set-operators Phases 1–3a
proceed regardless and take no dependency on the experiment. If the spike lands, Q5 reopens
per that brief's §8; if it dies, its §7 kill criteria route the post-mortem back to this
section and (C)+(D) closes permanently.

**OUTCOME (2026-07-18): the spike is DONE and green. Q5 reopens with option A real.**
`@infixl` / `@infixr` / `@infix N` declarations for binary identifier operators shipped on
branch `mengwong/fixity-declarations` (HEAD `e61dbf30`, work-head `8ba51c1d`) as
**PR [legalese/l4-ide#128](https://github.com/legalese/l4-ide/pull/128)** into `unstable` —
green (jl4-test 1221/0, jl4-core-test 208/0, l4-cli-test 55/0), all checks CLEAN, **in the
merge queue** as of 2026-07-18 (not yet on `unstable`; HEAD there is still `5ca076a6`). The parser was untouched — the flat-App parse shape and registry import
plumbing fit exactly as §13.1 predicted; a shunting-yard pre-pass in the typechecker
re-associates the chain, and fixity rides `MixfixInfo` through `IMPORT` for free. A
6-dimension adversarial review (3 refuters/finding) surfaced 8 findings, all fixed:
chiefly an n-ary-theft guard (a consecutive-param mixfix pattern matched the same flat shape)
now closed by dry-running the real matcher, and an attachment-adjacency bug (a `@infixl`
stranded above a directive/import/`WHERE` leaked to a distant later definition) now closed by
document-order claiming + a misplaced-annotation warning. **No default fixity**, so declaring
it for the set vocabulary changes nothing for any operator left alone; the one constraint is
that all overloads under one canonical name must agree on their fixity (else a chain over them
errors at the use site). Effect on this spec: option A is now the real answer for
`UNION`/`INTERSECT` as _words_ with precedence, not just (C)+(D). See the Phase table and the
Q5 resolution below for the follow-up (add `@infixl` to the prelude operators; §D5 route B
formally buried).

### 13.3 Independent findings (act on regardless of Q5)

- **`l4 format` is already lossy on bare infix mixfix**: `1 UNION 2` formats to prefix
  `UNION 1 2`; `1 UNION 2 UNION 3` garbles to `UNION UNION 1 2 UNION 3`. Pre-existing, fixity
  or no fixity. Re-verified first-hand (semantics preserved on the single-op case — formatted
  output still evaluates 3/6 — but the CNL register is destroyed, and non-typechecking chains
  format to reordered soup with exit 0). **Filed as
  [smucclaw/l4-ide#918](https://github.com/smucclaw/l4-ide/issues/918)** for another session.
- **Erratum:** this spec's `Parser.hs:1481-1497` citations were stale and are corrected to
  `Parser.hs:1496-1522` (17-row body at `:1502-1518`). Inline `Parser.hs:1491` cites for the
  `LESS THAN` row refer to the pre-drift line; the row now lives inside `:1502-1518`.
- Probe files preserved in the session scratchpad (`fixity-chain-probe.l4`,
  `fixity-ast-probe.l4`, `fixity-sameop-probe.l4`, `fixity-parens-probe.l4`, `fmt-single.l4`).

## 14. Implementation findings (Phases 1–3a built + adversarially reviewed, 2026-07-18)

Phases 1, 2, and 3a are implemented on two branches (`mengwong/set-operators-phase1`:
prelude + examples; `mengwong/set-operators-route-alpha`: the §D7.1 elaboration), both green
across the full golden suite, then put through a 33-agent adversarial review (5 lenses × 2
refuters per finding: 14 raw, 11 confirmed, all addressed or pinned). What the
implementation taught us, superseding parts of §D6/§D7:

1. **§D6's `__EQUALS__` plan fails as designed — and the failure is better than the plan.**
   The builtin `__EQUALS__` is `FOR ALL A. A → A → BOOLEAN` and the checker has **no
   specificity preference**, so a SET overload makes bare `EQUALS` on two sets an
   **ambiguity error**, not extensional equality. Kept deliberately: a loud error beats
   silently order-sensitive structural equality (detect ≠ resolve). Blessed spelling:
   `` `set equals` ``. A not-ok golden documents when to celebrate: if it ever passes, the
   checker gained specificity and bare set-EQUALS became extensional.
2. **The quotient is one level deep, and §D7's "semantically invisible" claim was too
   strong.** Element comparison is builtin structural equality, so it does not compose:
   `SET OF SET OF a` compares inner sets by representation ({{1,2}} ∩ {{2,1}} = ∅), and a
   set wrapped in ANY container (record field, PAIR, LIST, MAYBE) compares structurally
   under bare `EQUALS` with no diagnostic — the ambiguity guard fires only on directly
   SET-typed operands. Honestly scoped in the prelude header; pinned by
   `ok/set-operators-nested.l4`. **Phase 4 gains two lint triggers:** (i) instantiating
   SET's element parameter at a type containing SET; (ii) `EQUALS` where either operand's
   type contains SET at any depth.
3. **Route α as first written violated its own conservative-extension promise.** The rescue
   fired per resolution CANDIDATE, so a same-named function/constructor pair where the dead
   constructor branch previously lost now became AmbiguousTermError (4 verified repros, one
   via the prelude's own `Dictionary`). Fixed: the rescue is a **per-call-site biased
   fallback** — direct inference first; rescue participates only when the entire resolution
   has zero successes — via a new `orElseKeepAll` combinator (plain `orElse` filters to
   successes-only, which starves `prune` of `ambiguousTerm`'s curated error candidates and
   degrades multi-overload diagnostics to internal errors; found the hard way).
4. **The infix spelling `1 Bag 2` does not fire the rescue** — chain-parsed heads are
   synthesized rangeless and `withRange` silently skips the Constructor stamp. Desirable,
   but accidental; documented on `isConstructorKind` and pinned in the limits golden.
5. **Smaller notes:** SET's field is `elements` (the natural `contents` collided with
   `Dictionary`'s field, breaking previously-unique untyped projections); the Partee & Rooth
   comments in prelude/examples were tightened to attribute only the type-directed dispatch,
   per §9.3's own warning; deferred with in-code notes — "LIST literal" error attribution at
   rescued sites, and OF/comma semantic-token loss at rescued sites (highlighting-only).

## 15. Phase 3d BLOCKED — prelude-fixity-export bug (2026-07-18)

Prepping the Phase 3d prelude annotations (`@infixl 6` on `UNION`/`WITHOUT`, `@infixl 7` on
`INTERSECT`) surfaced a blocker in the just-landed fixity feature (#128). The annotations are
written and correctly placed, but they are **currently inert**: bare `a UNION b INTERSECT c`
still fails to re-associate ("trying to apply `a` … to 4 arguments"), while the parenthesized
form works.

**Root cause, isolated by bisection (all single-path `l4 run`, well-formed inputs):**

| Where the `@infixl` operator is defined                                                    | Bare-identifier chain re-associates?   |
| ------------------------------------------------------------------------------------------ | -------------------------------------- |
| In the **importing file** itself                                                           | ✅ yes                                 |
| In a **user library** imported by name (`IMPORT defs`) — literal _and_ identifier operands | ✅ yes                                 |
| In the **prelude** (`IMPORT prelude`)                                                      | ❌ **no** — re-association never fires |

The discriminator is decisive: a **fresh** operator (`p UNIONX q MEANS p`, no overloads, no
self-reference) **appended to `prelude.l4`** and reached via `IMPORT prelude` does **not**
re-associate, yet the _identical_ operator in a `defs.l4` reached via `IMPORT defs` does. So it
is neither polymorphism, nor the `__PLUS__`/`__AND__`/`__OR__` overloads, nor `@nlg`, nor
identifier operands, nor cross-module import in general (all independently cleared). It is
specific to **fixity declared inside the prelude not flowing to importers.** #128's own
`fixity-cross-module-*` tests only exercise a library imported by name with literal operands,
so the prelude path was never covered.

**Consequences:**

1. Phase 3d cannot deliver bare unparenthesized set-operator chains until this is fixed. The
   annotations are committed to branch `mengwong/set-operators-phase3d` with in-code inert-notes;
   they are a **strict conservative extension** (parenthesized chains and all existing programs
   are unaffected — verified), so they do no harm while inert. **Not PR'd.**
2. This is a bug in #128 (or the prelude load path), not in this spec's design. Hand to the
   fixity implementer: check how the prelude's `MixfixRegistry`/`tcdMixfixRegistry` fixity map
   is built and exported versus a name-imported user library — likely the prelude is loaded via
   a path that drops or never populates the per-name fixity entries. A regression test in the
   shape of the table above (prelude-defined `@infixl` operator, bare chain in an importer)
   should accompany the fix.
3. Q5's "(A) fixity is the answer for `UNION`/`INTERSECT` as words with precedence" holds as a
   design conclusion, but its _realization_ for the prelude waits on this fix. Until then, the
   shipped ergonomics remain (D) overloads (`PLUS`/`MINUS` bare + precedence-correct) and (C)
   parentheses for the word operators.

### 15.1 RESOLVED (2026-07-18, fixity implementer): NOT a #128 bug — stale prelude loaded

Investigated by the fixity implementer with `Debug.Trace` instrumentation of the parser's
fixity collection (`addFixityCommentsToAst`) and the checker's `applyFixityAnnotation`, across
both code paths. **The fixity feature is not at fault; fixity propagates through library imports
correctly. Phase 3d is UNBLOCKED — the annotations simply weren't reaching the loaded prelude.**

Root cause: `l4` was importing a **different `prelude.l4` than the one being edited.** Library
resolution (`resolveLibraryFromFilesystem`, `LSP.L4.Rules`) searches, in order:
`JL4_LIBRARY_PATH` → root dir → importing-file dir → **XDG (`~/.local/share/jl4/libraries/`)** →
bundled (near the exe) → embedded (compiled-in). On this machine the XDG entry is a **symlink to
the _main_ checkout**:

```
~/.local/share/jl4/libraries/prelude.l4 -> ~/src/legalese/l4-ide/jl4-core/libraries/prelude.l4
```

which has **zero** `@infixl`. So with `JL4_LIBRARY_PATH` unset, `IMPORT prelude` loaded the main
checkout's prelude (no fixity annotations) — the edited worktree prelude was never consulted.
The parser collected **0** fixity tokens for that prelude (traced), so no operator got a fixity,
so no chain re-associated. `IMPORT defs` "worked" only because `defs` is not a library name on any
of those search paths, so it resolved to the file actually next to the importer.

Decisive A/B (same binary, same importer, only the loaded prelude changes):

| `JL4_LIBRARY_PATH`                                      | prelude loaded                      | `1 UNIONX 2 UNIONX 3`      |
| ------------------------------------------------------- | ----------------------------------- | -------------------------- |
| `<worktree>/jl4-core/libraries` (edited, has `@infixl`) | edited                              | ✅ re-associates (→ 6)     |
| `<main-checkout>/jl4-core/libraries` (no `@infixl`)     | stale                               | ❌ "could not find UNIONX" |
| unset                                                   | XDG symlink → main checkout (stale) | ❌ (the reported symptom)  |

**To land Phase 3d:** run with `JL4_LIBRARY_PATH` pointed at the branch's `jl4-core/libraries`
(or repoint/remove the XDG symlink) so the edited prelude is the one loaded. For the _shipped_
product this is a non-issue: the embedded prelude is compiled from the committed `prelude.l4` at
release-build time, so once the Phase 3d annotations are committed and a release is built, users
get them via the embedded copy. The annotations themselves are correct and inert until loaded, so
they can land now.

Secondary observation (pre-existing, not fixity-specific): the XDG/bundled search entries can
**shadow both** the intended file and the embedded copy, and `GetMixfixRegistry`'s inline
resolver vs `GetImports` can in principle pick different sources — a dev-environment footgun worth
a separate cleanup (cf. the "XDG library shadow" already noted elsewhere), but out of scope here.
**No fix to #128 is required; no regression test for a non-bug.** §15's items 1–3 above stand as
the original (mis-attributed) hypothesis, retained for the record; this subsection is the verdict.

### 15.2 Re-opened: §15.1's fix is necessary but NOT sufficient (2026-07-18, verified)

Crediting §15.1: the XDG-symlink stale-prelude issue is **real and confirmed** — with
`JL4_LIBRARY_PATH` unset, `IMPORT prelude` loads the main checkout's un-annotated prelude, and
my original §15 mechanism ("prelude-defined fixity never flows to importers") was **wrong**:
a name-imported library's fixity flows fine. Corrections owed and paid.

**But Phase 3d is still blocked.** With the annotated worktree prelude _verifiably loaded_ via
`JL4_LIBRARY_PATH` (canary operator resolves; no "not found"), the §15.1 A/B test case
re-associates but the **actual set operators do not.** Reconciled side-by-side, one file, one
binary, `JL4_LIBRARY_PATH=<worktree>/jl4-core/libraries`:

| Expression                                                                   | operator / operands         | re-associates?       |
| ---------------------------------------------------------------------------- | --------------------------- | -------------------- |
| `1 UNIONX 2 UNIONX 3` (§15.1's test, temp-added to prelude)                  | NUMBER / literal            | ✅                   |
| `aa UNION bb UNION cc` (Phase 3d's real case)                                | prelude SET / identifier    | ❌ "apply to 4 args" |
| `(setFromList(LIST 1)) UNION (…) UNION (…)`                                  | prelude SET / parenthesized | ✅                   |
| `aa MYUNION bb MYINT cc`, `MYUNION`/`MYINT` in a small **name-imported** lib | SET / identifier            | ✅                   |

The discriminators §15.1 didn't vary: the failing case is **the prelude's own SET operators with
bare identifier operands**. It is not the symlink (annotated prelude confirmed loaded), not
literals-vs-identifiers alone (name-imported SET lib with identifier operands works), not
polymorphism / `@nlg` / the `__PLUS__`-`__AND__`-`__OR__` overloads / the `WITHOUT`-alias-on-
backticked-`LESS` (each independently cleared in a small lib). It reproduces with a **byte-identical
copy of the full prelude imported under a different name** (`IMPORT pp`), so it is not the filename
`prelude` either — it is something in the **full prelude's ~1290-line content** that the small
libraries lack.

**Minimal repro (no symlink involved — pure `JL4_LIBRARY_PATH`):**

```
# in a scratch dir D containing a copy of the annotated prelude.l4:
cp <worktree>/jl4-core/libraries/prelude.l4 D/          # has @infixl 6 UNION / 7 INTERSECT
cat > D/mini.l4 <<'X'
IMPORT prelude
@infixl 6
GIVEN a IS A TYPE
      p IS A SET OF a
      q IS A SET OF a
GIVETH A SET OF a
p MYUNION q MEANS p
X
cat > D/use.l4 <<'X'
IMPORT prelude
IMPORT mini
aa MEANS setFromList (LIST 1)
bb MEANS setFromList (LIST 2)
#EVAL setToList (aa MYUNION bb MYUNION aa)     -- ✅ re-associates (name-imported mini)
#EVAL setToList (aa UNION bb UNION aa)          -- ❌ does not (prelude's own UNION)
X
JL4_LIBRARY_PATH=D l4 run D/use.l4
```

`MYUNION` (from the tiny `mini`) chains; `UNION` (from the full prelude) does not — same file,
same operands, same load path.

**Hand back to the fixity implementer** (their `Debug.Trace` on `addFixityCommentsToAst` /
`applyFixityAnnotation` is the right tool): trace how many fixity tokens are collected for the
**full prelude** vs `mini`, and whether the prelude's fixity map survives into the registry the
importer re-associates against. Likely candidates: a size/position limit in fixity-comment
collection, or a specific earlier prelude definition that interrupts it.

**Phase 3d status:** annotations remain committed on `mengwong/set-operators-phase3d` (correct,
inert, conservative extension — the branch's full suite is green because nothing _uses_ bare
prelude set chains yet). **Not merged.** Two paths forward once diagnosed: (a) the real fix in
fixity-collection, or (b) fallback — ship the set vocabulary as a separate `IMPORT sets` library
rather than in the prelude, since **name-imported libraries already propagate fixity correctly**
(verified). (b) costs an explicit import but works today; weigh against the "auto-available"
goal.

### 15.3 RESOLVED (2026-07-19, fixity implementer): real bug found + fixed — PR #131

§15.2's hand-back was right to reopen, and its instinct ("trace the full prelude vs mini") was
the right method — but the candidate ("a size/position limit in fixity-comment collection")
was wrong. Traced with `Debug.Trace` on `addFixityCommentsToAst`, `applyFixityAnnotation`,
`chainOperatorFixity`, and `tryReassociateFixityChain`, all four stages verify **correct** for
the prelude's UNION: the `@infixl` is collected (1 token), attached to the UNION `Decide`
(honored, not dropped), populated into `MixfixInfo.fixity`, propagated to the importer's
registry, and found by `chainOperatorFixity` (`fixities=[Just (6,FixityLeft)]`). Attachment and
import flow were never the problem.

**The actual bug is the parser's flat-chain SHAPE, which differs by operand kind.** A chain over
LITERAL operands emits an operator-head App (`App UNION [1, 2, App INTERSECT [], 3]`); a chain
over bare-IDENTIFIER operands juxtaposition-parses to an operand-head App
(`App aa [Var UNION, bb, Var UNION, aa]` — first operand as head, operators as arg markers).
The re-association pre-pass only understood the operator-head shape, so it misread the
operand-head one (treating `aa` as the head operator and the `UNION` markers as operands), hit
its own "operator in an operand slot" guard, and declined. Every #128 golden used literal
operands, so the entire identifier-operand class — which is what the prelude's set operators
over named values are, and what §15.2's `aa UNION bb UNION aa` exercises — was untested.

This also explains §15.2's puzzle (mini's MYUNION works, prelude's UNION doesn't, byte-identical
content): a small lib's operator happens to be in the importer's parser mixfix-hints so its
chain parses operator-head, whereas the full prelude's UNION isn't hinted the same way at the
use site so it parses operand-head. The single (non-chain) `aa UNION bb` always worked (the
typecheck-level reinterpret handles either shape); only the CHAIN exposed the gap.

**Fix shipped as PR [legalese/l4-ide#131](https://github.com/legalese/l4-ide/pull/131)**
(`mengwong/fixity-operand-head-fix`, off current `unstable`): `normalizeChain` handles both flat
shapes and yields a uniform (operands, operators) list; a ≥2-operator guard stops a plain
`a op b` (and the nested binaries the pass emits) from looping. Regression
`ok/fixity-identifier-operands.l4` pins same-op, mixed-precedence, and mixed identifier/literal
chains. Verified end-to-end: the annotated prelude's `aa UNION bb UNION aa` now re-associates.
Suites green (jl4-test 1225/0, jl4-core-test 208/0).

**Phase 3d verdict: keep sets in the prelude; option (b) is NOT needed.** The "ship a separate
`IMPORT sets` library" fallback would only have masked this — it works today merely because a
small lib parses operator-head; it would leave every future large-lib or identifier-operand
chain latently broken, and would not give bare `a UNION b` from the prelude. With #131 the root
cause is gone, so the Phase 3d annotations on `mengwong/set-operators-phase3d` become live once
#131 lands on `unstable` and that branch rebases onto it. Recommend: land #131, rebase phase3d,
drop the "currently INERT" in-code notes on the prelude set operators, and PR phase3d.

**DONE (2026-07-19): all of the above executed.** #131 landed on `unstable` (`735433e7`); `mengwong/set-operators-phase3d` rebased onto it; bare prelude chains verified re-associating (`aa UNION bb INTERSECT cc` = `aa UNION (bb INTERSECT cc)`, INTERSECT@7 > UNION@6); inert notes dropped; acceptance golden `jl4/examples/ok/set-operators-precedence.l4` added (each bare chain paired with its parenthesized reading); full suite 1481/0. Shipped as **PR [legalese/l4-ide#133](https://github.com/legalese/l4-ide/pull/133)**. Phase 3d COMPLETE; sets stay in the prelude (option (b) rejected).

## 16. REVERSED 2026-07-28 — the `AND`/`OR`-on-sets overloads are removed from the prelude

**Decision (Meng, 2026-07-28): deprecate the `__AND__`/`__OR__` SET overloads now.** Term-level
set union is written `UNION` explicitly. `AND`/`OR` between two `SET`-typed operands is a type
error against the sole remaining candidate, the predefined boolean `__AND__`/`__OR__` — pinned
by `jl4/examples/not-ok/tc/set-and-unoverloaded.l4`. Filed upstream as
[smucclaw/l4-ide#929](https://github.com/smucclaw/l4-ide/issues/929) (open).

### 16.1 The driving measurement (2026-07-27/28)

With two candidates for `__AND__` (predefined boolean + the prelude SET overload) plus the
`ambiguousTerm` fallback, the checker re-checks argument subtrees **per candidate with no
memoisation** (`inferFlatApp`/`matchFunTy`; profile hotspots `$fAlternativeCheck`,
`distributeWith`, `Text` compare) — measured **2.96× per operand** in flat chains, i.e. **base 3
in tree depth**:

| flat `TRUE AND … AND TRUE`, `IMPORT prelude` | time          |
| -------------------------------------------- | ------------- |
| N=12                                         | 2.76s         |
| N=13                                         | 8.14s         |
| N=14                                         | 23.17s        |
| N=15                                         | 71.75s        |
| N=16+                                        | timeout >120s |

Controls: **without** the prelude, flat N=28 checks in 0.04s; a **balanced** 32-operand tree
checks in 0.39s (the exponent is depth, not operand count); and a user-declared second `__AND__`
overload in a plain file reproduces the blow-up exactly — the mechanism is any second candidate
for the magic name, not the prelude per se.

The corpus casualty: `paper/case-studies/charities-jersey-2014/part-3-charity-test.l4:184-211`
transcribes Article 6(1) as a 27-operand disjunction, which extrapolates to ~10⁷ s (about a
year) of typechecking. With the two overloads stripped it checks in 0.70s, and the full
`jl4-test` golden suite drops 176s → 127s.

Measured blast radius of the removal across 1731 `jl4-test` examples: exactly
`ok/set-operators-overloads.l4` (reworked to `UNION`, 3 golden facets) and
`not-ok/tc/set-equals-ambiguous.golden` (embeds a prelude source span, shifted by the deleted
lines). Shipped docs (`doc/reference/libraries/sets.md` + `sets-example.l4`,
`doc/tutorials/set-operators/sets-and-the-two-ands.md`) updated in the same change.

### 16.2 What stays

- **`__PLUS__`/`__MINUS__` on sets (§D3) stay**, as do `UNION`/`INTERSECT`/`` `LESS` ``/
  `WITHOUT` and the `__EQUALS__` ambiguity guard (§D6, §14.1). They carry the same
  second-candidate mechanism; they await a **typechecker memoisation fix on a parallel track**
  rather than removal, because arithmetic/set chains in the corpus are short where `AND`/`OR`
  chains are exactly how statutes write 27-limb conditions.
- **The semantic rulings stand.** Q2 (`OR` on sets = union), the §9/§10/§11 authority record,
  and the §11.6 trichotomy are unaffected — what changed is only _who_ performs the resolution:
  the drafter writes `UNION` in the source instead of the checker dispatching on types.
- **Phase 4 (the lint) stays live**, redirected: with the overloads gone, the type error itself
  is the detection site for a transcribed set-`AND`, and the non-vacuity/otiosity diagnostics
  (§10.5, §11.6) attach to explicit `UNION`/`INTERSECT` sites.

### 16.3 The un-un-overloading contingency

The overloads may be **reconsidered** ("un-un-overloading") only if the typechecker work
delivers a genuine big-O improvement — polynomial checking of N-operand `AND`/`OR` chains in
the presence of a second candidate, demonstrated on the charities corpus, not a constant-factor
win. Until then, isomorphic transcription of a set-flavoured `and` costs one explicit word, and
buys back the ability to typecheck statutes at all.

> **CONDITION MET 2026-07-29 — the perf ground has shifted; the ruling has not.** The
> typechecker fix landed as [legalese/l4-ide#169](https://github.com/legalese/l4-ide/pull/169)
> — a definite-incompatibility overload **pre-filter** plus a lazy ambiguity fallback, not the
> memoisation this section anticipated. Measured on the charities corpus: part-3 (the 27-operand
> disjunction) 0.72 s, part-7 1.4 s, flat chains flat through N=512, with a second candidate in
> scope. So the demonstration this section demanded exists, with two residual caveats: operands
> headed by registered mixfix names conservatively decline the pre-filter (they keep today's
> fork cost), and balanced trees whose _every_ operand is itself an overloaded connective still
> fork polynomially. **Un-un-overloading is therefore now a live option, and the question
> reduces to the semantic argument** (§9.3, §9.5, §10.6: `AND` = `OR` = union erases a
> distinction no authority endorses, and the type error surfaces a real drafting choice). This
> section records that the perf precondition is satisfied; it does not reinstate the overloads.

### 16.4 What review changed

This section, the header status block, and the dated notes at §D4, §4, §5, §6 Phase 2, §7 Q2,
§9.5, and §10.5 were added 2026-07-28 when the reversal landed; no earlier text was deleted or
renumbered, so pre-reversal prose in §D4/§5/§9.5/§10.5 still argues for the overloads — read it
as the record of the design that shipped and was measured, not as current behaviour. This spec
file also moved from branch `docs/set-operators-spec` onto `unstable` in the same change, so the
reversal and its owning document land together; the copy on `docs/set-operators-spec` predates
§16 and is superseded.

## 17. Coordination as list formation — the factored-form analysis (2026-07-29)

**Status: analysis and recommended style, recorded after discussion with Meng 2026-07-29. The
"enumeration recognition" normaliser of §17.6 is PROPOSED, NOT BUILT.** Every L4 example in this
section was typechecked and evaluated against the post-§16 tree (prelude without the `AND`/`OR`
set overloads) before being written down; the anti-pattern was separately confirmed to be a type
error.

### 17.1 The linguistic claim

"Residents of NY and NJ may apply" is conjunction reduction — the factored surface of "residents
of NY and residents of NJ." Three facts about the construction are load-bearing:

1. **The factored/distributed flip.** As a membership predicate, x ∈ (NY ∪ NJ) ⟺ x ∈ NY **∨**
   x ∈ NJ: the distributed form of a nominal _and_ is a logical _or_. The prelude states this
   law in a comment at its `is in`/`UNION` definitions ("x `is in` (p UNION q) exactly when
   x `is in` p OR x `is in` q").
2. **Nominal _and_ is ambiguous between ∪ and ∩.** "Residents of NY and NJ may apply" is union;
   "citizens of France and Germany" (dual nationals) is intersection. Distribution
   disambiguates. The removed overload did not merely collapse `AND` with `OR` (§16): it
   silently always chose ∪, deciding an interpretive question without recording it.
3. **The terminal connective is agreement morphology, not an operator.** The same extension
   surfaces with _and_, _or_, or nothing, selected by the grammatical environment rather than
   by the set operation: "residents of NY, NJ, **and** CT may apply" (affirmative); "is she a
   resident of NY, NJ, **or** CT?" (interrogative); "no resident of NY, NJ, **or** CT may
   apply" (negative polarity); "residents of NY, NJ, CT" (telegraphic asyndeton). A morpheme
   selected by mood and polarity is agreement — the audible close-bracket of an enumeration.
   The construction is `x elem [a, …, z]`: the list is the semantic object, the comma is the
   true separator, and the pre-final connective closes the list. (_O'Connor v. Oakhurst Dairy_,
   851 F.3d 69 (1st Cir. 2017), is the exhibit for the list boundary being where the real
   ambiguity lives; Maine's legislative fix was re-punctuation — semicolons — not re-wording.)

Statutory sub-paragraph enumerations institutionalize this: "(a) …; (b) …; … (y); **or**
(z) …" places the connective exactly once, penultimately, and drafting convention reads it as
distributing over every limb.

### 17.2 The same error, computationally

§16.1's detonation was this category error made mechanical. Article 6(1) of the Charities
(Jersey) Law is a flat 27-limb enumeration; transcribing its terminal connective as a _binary
operator_ binarized a list into a depth-27 leaning chain, and the measured blow-up was
exponential **in that artificial depth** — the balanced 32-operand tree checked in 0.39 s while
flat 16-operand chains timed out (§16.1). The pathology was never "27 operands"; it was
list-shaped law forced through operator-shaped syntax. The ladder visualizer's IR, by contrast,
already models `And`/`Or` as **n-ary**.

### 17.3 Recommended style — the NY/NJ example, five ways

All verified green. `alice` resides in NY, `carol` in NJ, `dave` in CT.

**Style 1 — enumerated values + membership (the default recommendation).** When the statute
enumerates _attribute values_ (states), the enumeration is the object and membership is the
logic. This is also the form DMN can render natively (§17.5):

```l4
GIVEN p IS A Person
GIVETH A BOOLEAN
`may apply` p MEANS
    p's `state of residence` `is in` (SET OF "NY", "NJ")
```

**Style 2 — sets of people, explicit `UNION`.** When populations are themselves the objects of
the rule (quotas, apportionment, counting):

```l4
`eligible population` MEANS `new yorkers` UNION `new jerseyans`
#EVAL setSize `eligible population`            -- 2
#EVAL carol `is in` `eligible population`      -- TRUE
```

**Style 3 — distributed predicates, infix + dittos.** The fully distributed boolean form;
maximally ladder-friendly as-is, and the shape §17.6's normaliser would produce mechanically
from Style 1. The predicate is defined **infix** (subject-first, on the prelude's `p UNION q`
model), and the repeated `p `resides in``prefix is elided with **caret dittos** — each`^`
copies the token from the line above at the same column, so the second disjunct reads as pure
delta, spreadsheet-style, and the enumeration's list-nature shows in the source layout:

```l4
GIVEN p IS A Person
      s IS A STRING
GIVETH A BOOLEAN
p `resides in` s MEANS p's `state of residence` EQUALS s

GIVEN p IS A Person
GIVETH A BOOLEAN
`may apply` p MEANS
       p `resides in` "NY"
    OR ^ ^            "NJ"
```

**Style 4 — `any`-fold over the enumeration.** The list-shaped form for _predicate_ limbs; the
prelude's `any`/`all` carry `@nlg` templates already. NOTE: L4 functions are **not curried** —
there is no partial application, so the fold takes an explicit lambda:

```l4
`may apply` p MEANS
    any (GIVEN s YIELD p `resides in` s) (LIST "NY", "NJ")
```

**Style 5 — inert: the statute's very token rides as scaffolding.** An inert string in `OR`
context evaluates to `FALSE`, the identity — so the source's word "and" stays visible in the
code (and in the ladder, as an `InertE` leaf) while the operative connective is the honest `OR`:

```l4
GIVEN `is a resident of New York`   IS A BOOLEAN
      `is a resident of New Jersey` IS A BOOLEAN
DECIDE `may apply per s 1` IF
        "residents of"
    ..  `is a resident of New York`
    ..  "and"
    ..  `is a resident of New Jersey`
```

This dissolves the isomorphism tension of §16: token fidelity via scaffolding, semantic honesty
via lifted structure — without any set overload.

**Anti-pattern (pinned):** `` `new yorkers` AND `new jerseyans` `` — type error since §16, by
design; the error is the point where the drafter must choose ∪ vs ∩ and record it.

### 17.4 Per-consumer preferences

| setting                  | prefers                    | why                                                                 |
| ------------------------ | -------------------------- | ------------------------------------------------------------------- |
| token isomorphism        | factored                   | transcribe the source's "and" — served by Style 5, not by overloads |
| interpretive isomorphism | `UNION` / `is in` explicit | records the ∪-vs-∩ ruling where it was made                         |
| inert style              | indifferent (dissolves it) | the token rides inert; the logic distributes                        |
| DMN export               | distributed membership     | unary-test alternation is native; set values stay `Any`             |
| ladder diagrams          | distributed / n-ary        | branches render; a factored set expression is an opaque `App` leaf  |

### 17.5 The DMN connection: rows are boxes, tables are unions of boxes

FEEL's unary-test alternation `"NY","NJ"` is itself a factored comma-notation — DMN
independently evolved §17.1's conclusion (enumeration kept, morpheme dropped). Formally: a
decision-table **row**, read across columns, is a conjunction of per-column disjunctions — CNF
restricted to **univariate clauses**, i.e. an axis-aligned **box** (a Cartesian product of one
admissible set per column). The **table** is a union of boxes (DNF over box-shaped rows), and a
**FIRST**-hit table is a decision list — ordered DNF whose "no earlier row fired" negations are
carried by vertical position alone. Three connectives, zero connective tokens: conjunction by
column-juxtaposition, inner disjunction by comma, outer disjunction by row-stacking.

The univariate restriction is load-bearing in both directions: it is why decision-table
completeness/overlap analysis is tractable (two boxes intersect iff every column's cell-sets
intersect — column-wise, no SAT), and why non-box logic (`x = a ∨ y = b`) forces combinatorial
row-splitting. That is exactly the seam the GuardedRows normaliser sits on: L4 guards are
general boolean structure; a table is emittable only when they normalise to boxes.

### 17.6 PROPOSED, NOT BUILT: enumeration recognition

A canonical n-ary list-membership shape — recognising `x is in (SET OF …)`, `any p (LIST …)`,
and `Or`-of-membership chains as one construct — rendered per consumer in its native
compression: the ladder as a **menu box** (one group, list rows, any-suffices layout); DMN as
the unary-test alternation; NLG as the syndetic list whose terminal token is _regenerated from
the grammatical context_ (mood/polarity, §17.1.3) rather than stored. One Haskell pass, every
consumer, on the GuardedRows precedent. Nothing is implemented as of 2026-07-29.

### 17.7 Consequence for §16.3's contingency

Un-un-overloading is deflated a step further than §16.3's CONDITION MET note left it: every
consumer either prefers the distributed form or is indifferent, the only argument for the
factored set form is token isomorphism, and Style 5 serves token isomorphism _better_ than the
overloads did — without the `AND`/`OR` collapse, without the silent ∪ choice. Restoring the
overloads would sanctify the agreement morpheme as an operator: encoding the one token in the
sentence that carries no meaning.
