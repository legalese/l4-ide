# Props: the proposal, as it stands on 2026-09-04

_Status: **a proposal, not implemented.** R0 is ruled (2026-09-04, `IMPLICIT-PROPS-DESIGN.md`
§11.1). R1, R2, R3, R4 and R8 were ruled in conversation on 2026-09-04 and are recorded in
`IMPLICIT-PROPS-DESIGN.md` §11.2–§11.6; R5–R7 and R9–R12 are candidates awaiting Meng's marks on
the rulings sheet. This revision replaces every earlier
stratum of the file: the 2026-09-03 reduced position, the 2026-09-03/04 refinement minutes, the
second red team's verified findings and the four verbatim red-team reports are all in git history
at `d119c521` and are not restated here. Every count below carries the date it was measured and
the tree it was measured on; re-verify before relying. Probes ran on `~/.local/bin/l4` dated
2026-08-27, which lags `unstable`._

Supersedes, in part, `PROPS-SCOPE-HANDOFF.md`: its §2 "third reading" (the `§` hierarchy is the
scope tree) is refuted by measurement (§5 item 2 below). Its prior-art survey (§3) and boundaries
(§7) stand. Decisions are recorded only in `IMPLICIT-PROPS-DESIGN.md` §11; this file argues, it does
not decide.

---

## 1. The position

**`ASSUME` is deprecated (R0, ruled).** Its term role becomes a **section-level `GIVEN`**, which the
compiler **discharges** into an ordinary parameter of every definition that transitively reads it.
**Supply is application**: the existing named-argument `WITH`, with nothing new in the grammar.
Its type role becomes an empty `DECLARE`. Its refusal role becomes `REFUSE`, a throw that cannot
be caught and can be statically analysed.

| job of `ASSUME` today              | destination                                                             | status                    |
| ---------------------------------- | ----------------------------------------------------------------------- | ------------------------- |
| suppliable term (~550 uses)        | section `GIVEN`, discharged by the compiler (§2.1–§2.4)                 | mechanism = R1–R5, R8–R11 |
| uninterpreted type (`… IS A TYPE`) | empty `DECLARE T`, which parses today (`ok/set-operators-nested.l4:36`) | available today           |
| refusal / typed bottom             | `REFUSE "…"`, uncatchable, boundary-only, in no schema (§2.8)           | specification = R7        |

What the compiler adds is the threading authors were expected to write by hand: Meng's own
history of the keyword is that "everybody assumed we would deprecate it in favour of more regular
given-parameterized functions with purity." Discharge is that, with the pass-through parameters
written by the compiler. The cost of writing them by hand was measured on 2026-09-03: **506 of
1,112 record-typed `GIVEN` slots in the legal corpus are pure pass-through**, never `'s`-accessed
in their own body (`probate-administration-act.l4` 87 of 183, `intestate-succession-act.l4` 82 of
122). The factoring it buys was measured on 2026-09-04 over 1,860 `GIVEN` parameter slots in 26
legal files: **889 (48%) repeat an identical name and type declared earlier in the same section;
1,177 (63%) repeat one earlier in the same file.** `regcf.l4:280-330` opens eight consecutive
functions with `GIVEN issuer IS AN IssuerProfile`.

The name for the mechanism is **Coq `Section`/`Variable` discharge**: each definition is abstracted
over exactly the section variables it transitively uses, recursive groups discharged as a block.
It is also the dictionary-passing translation of Lewis, Launchbury, Meijer and Shields, "Implicit
Parameters: Dynamic Scoping with Static Types" (POPL 2000); a flat coeffect in Petricek, Orchard
and Mycroft, "Coeffects" (ICFP 2014); Agda's parameterised modules; Isabelle's `locale … fixes`;
Lean 4 `variable`. It is not an OCaml functor (uniform, generative, explicitly applied); what looked
functor-like in the first sketch was a dedicated supply keyword, which no prior art has, because
supply is application.

## 2. The design

### 2.1 Declaring: the section `GIVEN` (R3, R4)

A `GIVEN` attached to a section heading declares a binder for the whole module, with the heading
as its documented home and as the tiebreak when two sections declare the same name.

```l4
§ `1. Issuer eligibility — Rule 100(b)`
    GIVEN issuer IS AN IssuerProfile

@ref 17 CFR 227.100(b)(2)
GIVETH A BOOLEAN
`(b)(2) — an Exchange Act reporting company` MEANS
    issuer's `subject to the requirement to file reports pursuant to section 13 or section 15(d) of the Exchange Act`
```

**Spelling, R4 (ruled 2026-09-04).** The binder is written on the line after the heading,
indented: a `GIVEN` belongs to the section iff its keyword sits at a column greater than the
heading's `§`. Meng: "next-line-after-section, indented, to be the convention; having a GIVEN at
the rhs of the section heading text just looks weird." The heading-line form `§ ⟨name⟩ GIVEN …`
is not adopted. A column-1 `GIVEN` stays the next declaration's signature. Measured 2026-09-04:
the rival "adjacency" rule (the `GIVEN` right after a heading is the section's) would reinterpret
**160** sites in the legal corpus where a section's first function opens with a `GIVEN`; the
indentation rule collides with **zero** existing lines, there being no indented `GIVEN` in the
corpus. Both forms parse on the 2026-08-27 binary and both attach the `GIVEN` to the _next
definition_ (probe q9, Appendix A), so the parser changes: `MkSection` gains a `Maybe (GivenSig n)`,
`section n` takes `optional (indented givens headerColumn)`, and both printers, `Rules.ExactPrint`
and `L4.Print.prettyLayout`, emit the indented form with round-trip goldens per `CLAUDE.md` §3.2.

The dedent hazard is real and is mitigated rather than avoided: a formatter or a paste that
dedents a section binder re-attaches it to the next definition, and the seasoned rater's 130-line
rewrite of Reg CF §3 produced 21 errors on today's binary, five at `Range 1:1-1:1` about `_self`,
because an indented `GIVEN` had attached to `DECLARE InvestorProfile`. Three mitigations: a
column-1 `GIVEN` immediately after a heading whose names the next head does not bind is a **check
error** (today it silently makes the next definition a function of those names, probe q9); the
formatter never moves a `GIVEN` across the column boundary; and a diagnostic about an implicit
names the heading line it was declared on. The keyword candidates are struck: `WHEREAS` (a recital
is a statement of fact by the parties, Greer v Kettle [1938] AC 156, presumptively non-operative
where the operative words are clear, Re Moon, ex p Dawes (1886) 17 QBD 275, applied in [2001] SGCA
41; every legal reader read it as non-operative); `WHEREIN` (characterises an element already
introduced, limits only conditionally, MPEP 2111.04; both beginner raters confused it with
`WHERE`); the drafter's `IN THIS SECTION x IS A T` stays noted as the reach-by-words spelling if
one is ever wanted. The examples in this file use the ruled spelling.

**Visibility, R3 (amended 2026-09-04 at Meng's direction).** A section `GIVEN` is resolved exactly
as a top-level name is today: `selectByProximity` (`jl4-core/src/L4/TypeCheck/Types.hs:902`)
prefers the nearest ancestor section and falls back to all candidates when no ancestor matches, so
a binder under a title `§` reaches a sibling `§` and a grandchild `§§` whenever it is the only
candidate. **Same-named binders in different sections are distinct binders**, each read by its own
section and its descendants, exactly as two `ASSUME`s or two definitions are today. **One binder
per name is enforced per root, not per module.** A directive or export whose read-set contains
two binders spelled `foo` is a check error naming both by section (`` `Sections 1 and 2`.foo ``,
`` `Sections 3 and 4`.foo ``); a root that reads only one supplies it as plain `WITH foo IS …`.
The ways out each say what was meant: hoist `foo` to the title heading if it is one thing; rename
one if they are two; bridge at the call, `g WITH foo IS foo`, if section 2's `foo` is section 1's
for that call, which the error should offer. Different-type same-name binders are distinct in the
same way, the per-root check catching a root that reaches both.

This replaced the first draft's "one binder per name per module", which would have merged
silently the drafting pattern Meng put on 2026-09-04, "for the purposes of sections 1 and 2, foo
means apple; for the purposes of sections 3 and 4, foo means banana", laid out as he intends the
module mechanism to allow it:

```l4
§ toplevel

DECLARE Fruit IS ONE OF Apple, Banana

§§ `1`
foo MEANS Apple
r1 MEANS foo                   -- Apple

§§ `2`
foo MEANS Apple
r2 MEANS foo                   -- Apple

§§ `3`
foo MEANS Banana
r3 MEANS foo                   -- Banana

§§ `4`
foo MEANS Banana
r4 MEANS foo                   -- Banana

§§ `5`
r5 MEANS foo                   -- error: multiple definitions, toplevel.`1`.foo … toplevel.`4`.foo
```

As definitions this runs today on the FIX D branch exactly so, and a reader placed in `§ toplevel`
is ambiguous like `r5`, both the right answer, since the statute defined `foo` for neither; the
shipped 2026-08-27 binary reports `r1`–`r3` ambiguous as well, which is the not-yet-inferred
candidate defect FIX D repairs (probe meng-fruit, Appendix A). The same file with
`ASSUME foo IS A Fruit` in each section checks identically, and that is the rule section `GIVEN`
inherits. Stated as it ships, not as Coq: 7 of 26 legal files have a title `§` that is a _sibling_
of the operative sections, not their ancestor (`regcf.l4`'s title is one of eleven siblings), so
"the module is the title `§`" is false as a tree statement, and statutes re-declare the same
binder per section (Bribery Act 2010 ss 1, 2, 6 each re-declare "P"), which distinct binders
allow and "extension only" would have forbidden. Two shipped defects are repaired first (§7): a
parent's own reference goes ambiguous whenever a descendant rebinds the name, and
`SECTION-LEXICAL-SCOPING-SPEC.md` §3.3.4 says a sibling must qualify while the implementation
says it need not.

**Nesting.** A binder on a heading covers every definition in every section beneath it. That is
the one nesting pattern the corpus exercises: 2,407 of 2,409 legal-corpus definitions sit in leaf
sections (2026-09-04), so a parent section with rules of its own is a two-case rarity. A child
re-declaring an ancestor's name is a distinct binder that shadows within the child's subtree, as
today. A parent reading a name that several children declare is ambiguous, as today (probe
meng-fruit, the `top` reader). A child's binder is visible upward and sideways when it is the only
candidate; no legal file relies on that (of 33 term-role `ASSUME`s, 30 are read only in their own
section, 3 from a sibling, 0 from a parent or child in either direction, 2026-09-04). Supply never
qualifies a name, because a root that reaches two same-named binders is already an error. The
nearest-ancestor tiebreak is therefore the whole scoping rule, and headings are placement.

**Tier is measured, never declared.** Whether a binder is _world_ (one value per request) or
_subject_ (varies per case) is classified by call-site variation, by the exporter's existing
census, never by where the `GIVEN` sits. The sample that hoisted "the date of such offer or sale"
(17 CFR 227.100(a)(1), a per-transaction date; the de novo encoding's directives use 13 distinct
dates) onto a heading and thereby asked it once per batch is the witness for why.

### 2.2 Discharge: the read-set is one compiler fact

```
R(f)                 = reads(f) ∪ ⋃ { R(g) | g referenced in f }      -- least fixpoint over call-graph SCCs
R(LET x = v IN e)    = (R(e) \ {x}) ∪ R(v)                              -- context subtraction
```

`reads(f)` is the set of section binders `f`'s body names. Every definition with non-empty `R(f)`
is elaborated to take those binders as parameters, **trailing** its positional ones (R10: leading
implicits displace OpenFisca's subject entity, `mSubj = firstJust`, run-verified 2026-09-04); every
reference passes them through unchanged; a `WITH` or `LET` binding a member of `R(f)` at a call
site becomes application. After elaboration the program is plain L4 with `GIVEN`s: no environment,
no pin, no cache-fingerprint axis; "assumed term" survives only as "unsupplied at the root".
Recursive groups are discharged as a block. Nothing implicit crosses `IMPORT`: discharge happens at
the module boundary, and an importer sees ordinary parameters (this is also why `REFUSE` must land
before discharge, §2.8: `daydate.l4:104`'s refusal would otherwise become a parameter of every
importer calling `YMD`).

The runtime shape is a compiler choice: per-field (Coq-exact) or one record per module, which
preserves sharing of 0-ary dated constants (`the rules in force include` in `regcf.l4` has ten
readers). Unmeasured; backends project per-field from `R(f)` either way.

**Across sections.** The buffet is per definition, laid out by lexical position, and a call passes
requirements upward without the caller having to see them:

```l4
§ `1`
    GIVEN alpha IS A NUMBER

GIVETH A NUMBER
f MEANS alpha PLUS g                  -- R(f) = {`1`.alpha} ∪ R(g) = {`1`.alpha, `2`.beta}

§ `2`
    GIVEN beta IS A NUMBER

GIVETH A NUMBER
g MEANS beta TIMES 2                  -- R(g) = {`2`.beta}

#EVAL f WITH alpha IS 1, beta IS 2    -- 5
```

`f` inherits `beta` without naming it; hover on `f` says "reads beta via g, declared at § 2". `f`
may read `beta` bare, resolution finding the one candidate, and may override it with
`g WITH beta IS v`, which names `g`'s parameter and so works whether or not `beta` is visible from
§ 1. The buffet at `g` is § 2's whoever calls it. If both sections declare `foo` and both `f` and
`g` read it, `R(f)` holds `` `1`.foo `` and `` `2`.foo `` and the per-root error of §2.1 fires at any
root that evaluates `f`. Measured 2026-09-04 on the legal corpus: 312 calls cross a section into a
definition that shares a `GIVEN` with two or more of its section-mates, all of them between
siblings or cousins, none between a parent and a child; in 195 of them the caller carries the
same-named `GIVEN`, which under the R2 recommendation it drops.

The read-set exists **twice** today and is **missing where it bites** (as of 2026-09-03):
`jl4-core/src/L4/Catala/Lower.hs:969-985` (a fixpoint) and `Docassemble/Lower.hs:541-557` each
compute it privately, while the HTTP schema (`FunctionSchema.hs:276-300`), the direct evaluator
(`jl4-service/src/Backend/Jl4.hs:558`) and the WASM ABI (`jl4-mlir/src/L4/MLIR/Lower.hs:677`)
all use `collectReferencedUniques` (`jl4-core/src/L4/Export.hs:354`), which is one body deep.
Run-verified 2026-09-04: `l4 batch --validate-only` accepts a request missing the `ASSUME` a
helper reads, then evaluation is `Stuck`. The transitive pass is a bug fix with no language change
and is step one of everything else; it is built on `fix/export-transitive-readset` (§7).

### 2.3 Resolving a name (R2)

A bare name in a body must resolve, at the definition, to one of: a `WHERE`/`LET` local, the
function's own `GIVEN`, a field opened from one (§2.7), or a module-visible section `GIVEN`. Else
it is a **check error at the definition**. There is no "then the caller chain": with that in the
resolution order a misspelt name stops being an error and becomes an inferred request parameter at
the root, which no cited prior art permits (Coq, Lean, Isabelle and GHC `?x` all require a
declaration or a sigil).

The open question is what a **function's own `GIVEN`** does for a callee that reads a section
binder of the same name. The trap, reduced to four lines (sample S10(a), 2026-09-04):

```l4
§ `1. Issuer eligibility — Rule 100(b)`
    GIVEN issuer IS AN IssuerProfile

GIVETH A BOOLEAN
`the issuer is a reporting company` MEANS                 -- reads the SECTION issuer
    issuer's `subject to the requirement to file reports …`

GIVEN issuer IS AN IssuerProfile                           -- same name, same type
GIVETH A BOOLEAN
`this issuer is a reporting company` issuer MEANS         -- its own GIVEN wins in this body
    `the issuer is a reporting company`                    -- which issuer does the callee see?

#EVAL `this issuer is a reporting company` `a reporting issuer`
```

- **R2 as it stands on the sheet:** the caller's same-named `GIVEN` _supplies_ the section binder,
  so the `#EVAL` answers for `` `a reporting issuer` ``; a function `GIVEN` that restates a visible
  section `GIVEN` at the same type is a **warning** ("redundant restatement") and is the supply; at
  a different type, an error. Ground: drafting's consistent-expression presumption says a restated
  "the issuer" is the same issuer (Courtauld v Legh; Bennion s 21.3), and both beginner raters read
  it that way cold.
- **The recommendation put to Meng on 2026-09-04, not yet marked:** a function `GIVEN` **never
  flows** to a callee; only section `GIVEN`s and an explicit `WITH`/`LET` supply; and a function
  `GIVEN` that restates a visible section `GIVEN` is a **check error**, so a name has exactly one
  binder in a module. The `#EVAL` above is then an error at the definition, pointing at the
  restating `GIVEN`, and the fix is to delete it. Grounds: today's binary already answers by binding
  (probe t3, Appendix A: `GIVEN x` shadows `ASSUME x` inside its own body and a sibling reading `x`
  still sees the `ASSUME`); every cited prior art binds lexically; and the rule costs nothing
  today, because, measured 2026-09-04 across **607 files** (the l4-ide corpus, libraries, `doc/`,
  and `legalese/canon`), there are **235** term-role `ASSUME` names and **2,311** function `GIVEN`
  names and **no file** in which the two sets overlap. The rule governs only the migration state.
  The one witness in the corpus, the §7 caller at `regcf.l4:882`, is handled by dropping its own
  `GIVEN issuer` when section 1's binder is introduced (§3). A genuine per-call variation is still
  written, as `WITH issuer IS …` at the call; a helper that is genuinely polymorphic over issuers
  names its parameter something other than the section binder, which makes the polymorphism
  visible.

**Why a function `GIVEN` should not flow automatically**, put to Meng on 2026-09-04 and accepted
("a good balance between referential transparency and DWIM convenience"). What it would buy is
real: the corpus is dense with the shape, 195 of the 312 cross-section calls above coming from a
caller with a same-named `GIVEN`, and every one of them works unedited under automatic flow. What
it costs: (i) a name coincidence becomes a binding, so a private rename in a caller silently
changes what a callee three calls down reads, and a parameter called `issuer` because it holds an
issuer, the one an intermediary is affiliated with say, rebinds every callee that reads the
offering's `issuer` with no diagnostic anywhere, the corpus house style of naming parameters after
what they hold making collisions the norm; (ii) `R(f)` stops being the callee's: how much of it
survives to the root depends on parameter names along the call chain, so one export has different
request forms depending on who calls what, and provenance becomes "the nearest caller up the
stack with a parameter of that name" instead of a static line number; (iii) one program has two
readings, S10(a), and today's binary gives the lexical one; (iv) every tradition that had it gave
it up: LISP 1.5 and early Emacs Lisp bound every parameter dynamically, Common Lisp kept dynamic
binding only for variables declared `special`, which is exactly the section-`GIVEN`/function-`GIVEN`
line, GHC's `?x` is bound only by `let ?x` and never by a lambda parameter, Coq's section variables
are bound by declaration, React's props do not become context until a Provider says so; (v) the
saving is one migration edit while the hazard is permanent, and under the amended R3 most of the
195 sites vanish anyway, the restatement becoming an error, the caller dropping the `GIVEN`, the
value flowing. The residual price shows in iteration: a quantifier over a household whose body
calls a rule reading the section binder `applicant` cannot name its lambda parameter `applicant`;
it writes `WITH applicant IS member` at the one place a different value is intended.

Either way the earlier "one name, one type, per module" observation stands as a check that fires
only when a name is read implicitly, now per root under the amended R3. Measured 2026-09-03 over 1,774 `GIVEN` slots and 559 distinct
names in the legal corpus: 17 names are bound at more than one type corpus-wide, 9 within a single
file, all one-letter conveniences (`a`, `b`, `f`, `p`, `w`) or a `DATE` vs `MAYBE DATE` lifting.
Requirements are therefore sets; no row polymorphism.

### 2.4 Supplying a value (R1, amended)

**A call site is entirely positional or entirely named.** There is no mixed form: `f x WITH y IS v`
is a parse error today ("unexpected WITH", probe `mixed`, Appendix A) and was never live code. This
is the amendment Meng directed on 2026-09-04 ("all positional or all by-name but not an admixture");
it replaces the sheet's original R1, which had proposed writing a new mixed grammar. Measured
2026-09-04: no mixed site exists in the corpus because none can parse; on the order of a thousand
all-named `WITH` sites do (971 named-application sites by the session's count; 1,416 `WITH` tokens
in 179 of 608 `.l4` files on a plain re-count over `jl4/examples`, `jl4-core/libraries`, `doc/` and
canon); and the corpus already calls the same function both ways at different sites (`is adult`:
one `WITH` site, fourteen positional).

So the grammar is unchanged. The one compiler change is in `supplyAppNamed`
(`jl4-core/src/L4/TypeCheck.hs:2976`), which today raises `IncompleteAppNamed` for any omitted
parameter: under R1 a `WITH` site **may omit** any parameter that is flowed from a visible section
binder or has a `TYPICALLY` default, and a section `GIVEN` in the callee's read-set is a
**suppliable name** at a `WITH` site. Implicits are keyword-only: at a positional site they must
flow or default, and an implicit that does neither is an error at the root naming the binder and
the chain of calls that needs it. On an `@export` nothing fails: an unsupplied binder becomes a
request parameter (§2.10).

```l4
#EVAL `the issuer's headroom under the twelve month cap`
      WITH issuer IS acme, offering IS `acme's offering`, `the date of the offer or sale` IS Date 1 7 2026
-- interp takes its TYPICALLY; omit the date and the check error names it and the chain
```

**À la carte and the buffet.** A `WITH` names only what it overrides; every other binder in the
callee's read-set keeps flowing, and the named ones are what the callee's subtree sees from there
down. Supplying a binder at a call removes it from the caller's read-set along that path (the
`LET` subtraction rule of §2.2), so the root is not asked for it unless another path reads it. The
one price of all-or-nothing is that a site naming one implicit must name every explicit parameter
too, never the section binders it leaves alone. Supplying a name the callee neither takes nor
reads is an error today ("could not find a definition for the identifier zzz", probe oversupply)
and stays one, as the typo guard. There is no record-spread form: a record-typed binder is one
dish, its fields reached by `r's f` or opened lexically (§2.7); measured 2026-09-04 across the
corpus and canon, six named arguments have the shape `name IS r's field` and none has
`name` equal to `field`, so nothing is asking for one.

`WITH` binds loosely: it runs to the comma or end of line, so `#ASSERT f WITH a IS 3 EQUALS 4`
parses as `a IS (3 EQUALS 4)`. Tightening it would break two corpus sites (2026-09-04); it stays,
with a check hint when a `WITH` value's outermost operator is a comparison.

### 2.5 Defaults (R8)

`TYPICALLY` has **one behaviour**: a defaulted `GIVEN`, section or function, may be omitted at any
supply site, and the evaluator honours the default. Today it has three images: the schema marks a
defaulted parameter both `required` and defaulted, Catala makes it a caller-overridable `context`
(`Catala/Lower.hs:1136-1153`), the evaluator discards it (probe t4), and the reference page says
"It does **not** change evaluation" (`doc/reference/types/TYPICALLY.md:37`, `typically-example.l4`).
Every directive and trace output names each parameter that took its default; exports publish it
as optional with the default _and a description_ (today the description is empty,
`FunctionSchema.hs:283`); a defaulted `Interpretation`-typed binder is linted, because a fixture
that passes only under a defaulted `interp` passes only under the non-binding SEC staff reading
and says so nowhere. The page and the example are corrected in the same change.

**Where the default is applied.** After discharge a defaulted binder is a trailing parameter of
every function that transitively reads it, and every intermediate call passes it through
unchanged; the only site at which it can be absent is the root (a directive, an export request, a
service call). So the default is filled in **once per evaluation**, every reader sees the same
value, and a `WITH alpha IS 5` at an inner call is an override for that subtree (§2.6), not a
second default. Today neither omission works: at a named site the checker says "you forgot to
supply … a of type NUMBER", at a positional site it is an arity error, and the evaluator discards
the default in any case (probes typ1 and t4, Appendix A).

**Three rules, agreed by Meng on 2026-09-04:**

1. **Positional sites omit nothing explicit.** Under R1 a positional call supplies every explicit
   parameter; a function's own defaulted `GIVEN` may be omitted only at a named site. The only
   parameters absent at a positional site are section binders, which flow or default.
2. **One declaration owns the default.** Each binder has exactly one declaration and its
   `TYPICALLY` lives there. (As first agreed this read "a restatement in a sibling or child may not
   carry its own `TYPICALLY`"; under the amended R3 of the same day a same-named `GIVEN` in another
   section is a distinct binder with its own default, so the rule reduces to the sentence above.)
3. **A default is a module-scope expression.** It may refer to another binder or to a definition
   (`GIVEN beta IS A NUMBER TYPICALLY phi`, where `phi MEANS alpha TIMES 2`), and is evaluated
   lazily at the root after supply. Section placement is irrelevant, visibility being module-flat;
   what matters is the read-set. **Cycle:** `b ∈ R*(default(b))`, the binder transitively read by
   its own default, is a check error at the declaration, so a definition among the rules that read
   `beta` bare cannot be `beta`'s default, while one that reads only `alpha` can be. **Closure:**
   `R(default(b))` joins the requirement of every root that may use the default, so an export that
   reads `beta` and never mentions `alpha` still lists `alpha` as a request parameter, required
   unless `alpha` defaults too. The expression is type-checked against the binder's declared type,
   as the literal is today (probe typ5). Today a `TYPICALLY` value must be a literal, a number, a
   string, or a nullary constructor, and naming a definition is a check error whether or not
   there is a cycle (probes typ3, typ4); an operator is a parse error (probe typ2). The restriction
   exists for the schema's sake, and the source-text carriage below is what lets this rule lift it.

**Side effect, noted by Meng on 2026-09-04.** This expands `TYPICALLY` from a literal annotation
into a defaulted expression, a language change in its own right, independent of the environment
work; `doc/reference/types/TYPICALLY.md` must say so when R8 lands, alongside the correction that
defaults now change evaluation.

**Two surfaces, confirmed with Meng on 2026-09-04.** _Provenance in the trace_: a discharged binder
that was supplied is an ordinary bound argument and the trace (`L4.EvaluateLazy.Trace`) already
records it as one; a binder that took its default gets a new trace event naming the binder, the
declaration line the default came from, and the value, and an inner `WITH` override shows as the
argument it is, at its site. That event is what every directive's "alpha took its default 10" line
is rendered from. _The JSON schema_: a `TYPICALLY` parameter is **absent from `required`** and
carries `default` and `description`. Today it is required regardless
(`FunctionSchema.hs:286-301`: every `ASSUME` parameter is in `required`, and a `GIVEN` is required
unless `MAYBE`-typed), and `typicallyToJson` (`:322-330`) emits a `default` only for a numeric or
string literal or `TRUE`/`FALSE`; a default that is an expression under rule 3 has no JSON value,
so the schema marks the parameter optional and carries the default as its L4 source text in a
sibling key (`x-l4-default`) rather than omitting it.

### 2.6 Hypotheticals (R9)

At a directive, supply is `WITH`. An in-body hypothetical ("under the strict reading") may use
`LET` reaching callees, or, more simply, `e WITH x IS v` at any site as the one mechanism; the
seasoned raters preferred the latter, and it leaves no dynamic binder to explain. Whichever
survives: a `LET` scopes over a trailing `WITH`; `WHERE` never supplies (19 `WHERE`-local names
coincide with `GIVEN` names in the corpus, 2026-09-04); a `LET` binding a section-binder name that
nothing under it reads is a warning; and the read-set subtraction rule of §2.2 applies. Today a
`LET` shadowing a same-named `GIVEN` in scope is a "multiple definitions" error (probe q13). For
DMN, rebinding the rule date drops per ruling R-C of `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §15.12.1;
any other binder is the exporter's existing tier-2 BKM case.

Deeming ("treated as … for the purposes of subsection (1)", BNA 1981 s 1(2), `bna.l4:263-276`)
rebinds the **subject**, not the world: it is a record update on a `GIVEN`, which is why `BUT WITH`
(`RECORD-UPDATE-SPEC.md`, smucclaw#438) is wanted independently and is not the environment's
`local`.

### 2.7 Opened fields (R5)

The fields of a record-typed `GIVEN`, function or section, are in scope by bare name **within the
function that declares or sees the binder, and never in its callees**. Precedent: computed fields
already see sibling fields bare (`COMPUTED-FIELDS-SPEC` line 80; `ok/computed-fields.l4`). Flowing
opened fields to callees would be the row polymorphism on field names that §2.3 disclaims.

Rank, innermost first: `WHERE`/`LET` locals; the function's own `GIVEN`; fields opened from it;
section `GIVEN`s; fields opened from those; selectors (selector resolution stays type-directed as
today, `inferSelector`, `TypeCheck.hs:1312`). A collision between two opened records sharing a
field name is an error at the read naming both records and at the declaration that opens the
second; `facts's field` is always available. The corpus house style names a parameter after its
own field (`amount's amount`, `the witness's the witness`; 15 field names are also `GIVEN` names in
the charities cleanroom, five at mismatched types, 2026-09-04), and the computed-field precedent
resolves a clash by silently preferring the field (probe q17: field 26 beat top-level 99, no
error), which is why the rank is written down. A bare opened field elaborates to
`Proj (App r []) field` in a post-typecheck elaborated AST that every backend consumes, since every
backend keys on that projection shape and consumes `Module Resolved` directly and no stage produces
the projection today (`Desugar.hs:266-330` rewrites at parse time on `Expr Name`). Only binders are
suppliable at `WITH`, not opened fields. In reserve, favoured by the seasoned raters: opt-in
opening per binder (`GIVEN facts IS A `The facts` OPENED`) so a reviewer can see binding class.

### 2.8 Refusal (R7), and the taxonomy of non-answers

`REFUSE "message"` is an expression at any type. Evaluating it stops with the message as a distinct
outcome, _declined_, neither an error nor an unknown fact. It appears in no schema. Meng's
characterisation (2026-09-04): **a throw that cannot be caught and can be statically analysed.**

```l4
@ref Ruling R2 (CORPUS-TRACK §8)
GIVETH A NUMBER
`no Regulation Crowdfunding figure exists before commencement on 2016-05-16` MEANS
    REFUSE "no Regulation Crowdfunding figure exists before commencement on 2016-05-16"
-- the eight OTHERWISE arms that reach it (regcf.l4:154, :166, :175, :185, :195, :205, :215, :409) do not change
```

1. **Uncatchable is what makes it analysable.** With no handler stack, "can this rule refuse?" is
   reachability over the call graph, the same fixpoint as the read-set:
   `Ref(f) = refusals in f ∪ ⋃ { Ref(g) | g referenced in f }`. Every function carries two inferred
   signatures, the read-set (the coeffect: what it needs) and the refusal set (the effect: how it
   may decline), both on hover, both in the export schema. `Ref(f)` is syntactic and, under
   laziness, an over-approximation ("may refuse"); it is reported **per reason string**, because a
   boolean badge says nothing when the commencement refusal is reachable from every dated constant
   in Reg CF. The verification rung answers "for which inputs does this export refuse?" as
   satisfiability, yielding a region.
2. **Uncatchable is what keeps it honest.** The Reg CF authors avoided `NOTHING` because `NOTHING`
   can be handled: a downstream `CONSIDER` launders a refusal into a default. `REFUSE` cannot be
   converted by any rule; only the boundary observes it.
3. **It composes with the legal devices without a catch.** A statute avoids a refusal by changing
   what is asked, deeming being a record update on the subject before the rule runs, never by
   handling it after. `SUBJECT TO` overrides a conclusion, not a refusal.

Specification, per R7: a **throw at force, never a value** (built on the `ValAssumed` path it would
be a lazy value, printed as data at the root, dropped by the print-depth cutoff, unobserved inside
an unforced closure); `#ASSERT REFUSED e`, with an optional message, and a **three-valued assertion
outcome**, since today `#ASSERT P` and `#ASSERT NOT P` both report "assertion failed" when `P`
raises (probe pC, 2026-09-04) and no boundary can be pinned; house style **one named definition per
refusal** with its `@ref`, readers byte-identical, polymorphic ones declared `GIVEN a IS A TYPE`
(a 0-ary `x MEANS REFUSE "…"` is otherwise monomorphic, probe pD2); `TBD` becomes a one-line prelude
definition over `REFUSE`, excluded from `Ref(f)` and warned separately as a placeholder that should
be zero at release. **Refusal is order-dependent under lazy `AND`/`OR`** (`FALSE AND x` answers,
`x AND FALSE` refuses) and so diverges from FEEL's commutative Kleene logic; the region is
well-defined only if the verifier models left-to-right demand. This is written down, not fixed.

**Per-backend image**, which no backend has today (every one lowers the refusal `ASSUME` as a
suppliable input, run-verified 2026-09-04): DMN omits the refusing row, reports a non-Blocking
`D-REFUSE` with the reason, and adds a `MayRefuse` safety kind that does not withdraw `DMN-SAFE`
(FEEL `null` is already spent on `NOTHING`, so `REFUSE → null` would launder; `analyzeSafety`
deliberately treats an assumed term as not partial, so `D-PARTIAL` is the wrong class); Catala
emits no definition (its ladder veto exempts consequences); Docassemble a terminal screen;
evaluator, CLI, batch and service a `refused` kind on all six surfaces. The temporal design's
generated "not in force on <day>" arm (`TEMPORAL-RULE-VERSION-DESIGN.md` item 3) is reconsidered as
a **gate** rather than a refusal, per the split row below.

| non-answer                               | construct            | who handles it                                   | catchable       |
| ---------------------------------------- | -------------------- | ------------------------------------------------ | --------------- |
| a value that may be absent               | `MAYBE`              | the rule, by matching                            | yes, as a value |
| an expected failure with a reason        | `EITHER`             | the rule or its caller                           | yes, as a value |
| a fact not yet known                     | an unsupplied binder | the boundary asks                                | n/a             |
| the law does not apply / is not in force | a value or gate      | savings and transitional provisions can reach it | yes             |
| the model does not cover this            | `REFUSE`             | the boundary only                                | no              |
| a breach                                 | `LEST`               | the obligation's own branch                      | structured      |
| an overridden conclusion                 | `SUBJECT TO`         | the overriding rule                              | structured      |

The fourth row was split from the fifth on the legal lens's finding: pre-commencement is
determinate and reachable by savings provisions (SG Interpretation Act 1965 s 16(1)(b)–(c)), and a
provision that operates on non-application is unencodable over a `REFUSE`. `daydate`'s
out-of-range month is **invalid input**, the `EITHER` row, not a refusal. Catch-anywhere exceptions
are out (§5), and the `MAYBE`/`EITHER` propagation sugar once proposed for the first two rows is
withdrawn (R6, §5).

### 2.9 What the reader sees (R11)

No sigil in source. Hover on a definition shows the inferred clause that the first sketch wanted
authored:

```
`the issuer's headroom under the twelve month cap`
  GIVEN   offering
  reads   issuer                           via `the amount already sold …`
          interp                           via `the amount already sold …`   (TYPICALLY `the staff reading`)
          `the date of the offer or sale`  via `the amount already sold …`
  refuses "no Regulation Crowdfunding figure exists before commencement on 2016-05-16"
  pure    no
```

A rendered document ends with an index of defined expressions and their read-sets, as UK and SG
statutes publish an index of defined expressions (CA 2006 Sch 8) rather than marking each use. A
definition with an empty read-set and an empty refusal set gets a purity badge for free. Hover at a
call site says where each flowed value came from, and a diagnostic about an implicit names the
heading line it was declared on: the personas asked for both.

**`@reads` (R11).** A function may annotate an implicit it reads, `@reads interp — this decision is
where the look-through fork bites`, or override the section's `@desc` with its own, so that the
per-decision fork register survives hoisting. The de novo Reg CF encoding carries five different
descriptions of `interp` (`regcf-denovo.l4:3043-3078`), each naming which contested reading that
decision turns on, and the wizard's per-question help is built from them; the legal lens rated
their collapse a loss of legal meaning.

### 2.10 Backends (R10)

The read-set pass lands first, replacing the two private copies and the shallow collector (§2.2).
Then: the export schema is keyed by (name, tier) with an `x-l4-tier` annotation; check rejects an
explicit parameter sharing a name with a discharged implicit (today the two collapse to one
property with the name listed twice in `required`, `FunctionSchema.hs:299-300`); defaulted
implicits are not `required`; `BatchRequest` (`jl4-service/src/Types.hs:376-405`) gains a `world`
object so a batch supplies the world once and the subject per case, which nothing provides today
(OpenFisca's entity-vs-`parameters(period)` split is the prior art); discharged implicits **trail**
positional parameters; OpenFisca puts scalar implicits in `parameters(period)` and refuses record
ones; DMN lowers discharged implicits as decide parameters, not free terms, so that `paramGroups`
(`Dmn/Lower.hs:3756`) merges same-named same-typed parameters into one `inputData` as it already
does for the eight limbs of Rule 100(b). `imaginary-alcohol-act.l4` migrates as fourteen scalar
section `GIVEN`s, not one record: one record collapses fourteen requirement edges into one for DMN,
Docassemble refuses a record-typed input (`Docassemble/Lower.hs:941`), and scalars keep the rule
bodies byte-identical without needing field-opening.

### 2.11 Temporal, last

`RULES EFFECTIVE DATE` becomes a prelude-declared binder and `EVAL UNDER RULES EFFECTIVE AT d e`
a `WITH`, once sharing is measured. Demand today (2026-09-03): all 19 legal-corpus uses (17 in
`regcf.l4` fixtures, `regcf-wizard.l4:630`, one in the de novo file) sit at the outermost position
of a directive or export body, zero inside a rule, quantifier or lambda. The per-day interval
iterators rebind per iteration by construction (`Machine.hs:1253-1302`) and would need a rank-2
implicit; not designed.

## 3. Worked example: Reg CF Rule 100(b)

`jl4/examples/legal/regcf/regcf.l4:279-333` (verbatim before, sample S4 after). Eight consecutive
definitions open with `GIVEN issuer IS AN IssuerProfile`; the six limb bodies read `issuer's …`;
two bodies call the limbs; one caller lives in a different top-level section (§7, :882); two
`#ASSERT`s at :1001-1004 supply from the root. This is the sample every lens rated highest: "the
one place the construct is isomorphic with its source" (legal lens).

```l4
§ `1. Issuer eligibility — Rule 100(b)`
    GIVEN issuer IS AN IssuerProfile

@ref 17 CFR 227.100(b)(1)
GIVETH A BOOLEAN
`(b)(1) — not organized under State or territorial law` MEANS
        "(1)" ... NOT issuer's `organized under, and subject to, the laws of a State or territory of the United States or the District of Columbia`

@ref 17 CFR 227.100(b)(2)
GIVETH A BOOLEAN
`(b)(2) — an Exchange Act reporting company` MEANS
        "(2)" ... issuer's `subject to the requirement to file reports pursuant to section 13 or section 15(d) of the Exchange Act`

-- (b)(3) to (b)(6) likewise: the GIVEN line and the positional `issuer` go, the body is byte-identical

@ref 17 CFR 227.100(b) — the disjunction of exclusions
GIVETH A BOOLEAN
`issuer is excluded by Rule 100(b)` MEANS
        "(b) Applicability. The crowdfunding exemption shall not apply to transactions involving the offer or sale of securities by any issuer that:"
    ..  `(b)(1) — not organized under State or territorial law`
    ..  `(b)(2) — an Exchange Act reporting company`
    ..  `(b)(3) — an investment company`
    ..  `(b)(4) — subject to a bad-actor disqualification`
    ..  `(b)(5) — delinquent in ongoing annual reports`
    ..  `(b)(6) — no specific business plan, or a blank-check business plan`

@ref 17 CFR 227.100(b) — eligibility is the negation of the exclusions
GIVETH A BOOLEAN
DECIDE `issuer is eligible` IF
    NOT `issuer is excluded by Rule 100(b)`
```

The cross-section caller, `:873-882`, today declares its own `GIVEN issuer` and passes it
positionally. Under the R2 recommendation it **drops** its own `GIVEN issuer` (the restatement
would be the check error) and reads section 1's binder like everything else; under R2 as first
drafted it keeps it, with a redundancy warning, and the binding supplies the callee. Either way the
call loses its argument:

```l4
GIVEN offering    IS AN Offering
      …
DECIDE `the transaction qualifies for the section 4(a)(6) exemption` offering investor amount arrangement filing IF
        "(a) Exemption. An issuer may offer or sell securities in reliance on section 4(a)(6) of the Securities Act of 1933, provided that:"
    ... `issuer is eligible`
    AND `offering is within the offering limit` offering

#ASSERT     `issuer is eligible` WITH issuer IS `a clean issuer`
#ASSERT NOT `issuer is eligible` WITH issuer IS `a foreign issuer`
```

What changed: eight identical `GIVEN` lines became one; eight heads lost a positional parameter;
six bodies are byte-identical; seven call sites in the two calling bodies lost an argument; the
`#ASSERT`s supply by name. Under DMN the eight limbs already share one `input_issuer` via
`paramGroups`; after discharge the same merge applies to the section binder.

## 4. The rulings

The canonical statement of each is on the rulings sheet (artifact "Twelve Rulings on Props",
`fdc2631d`); what follows is the same text condensed, with status. A ruling is recorded only in
`IMPLICIT-PROPS-DESIGN.md` §11, dated.

| #   | status                                                                                           | holding (condensed)                                                                                                                                                                                                                                                                                                                                                                           | alternative on the sheet                                                                                                                                                                                     |
| --- | ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| R0  | **RULED 2026-09-04**                                                                             | `ASSUME` is deprecated: term → section `GIVEN` with discharge; type → empty `DECLARE`; refusal → `REFUSE`.                                                                                                                                                                                                                                                                                    | —                                                                                                                                                                                                            |
| R1  | **RULED 2026-09-04** in conversation; `IMPLICIT-PROPS-DESIGN.md` §11.2                           | A call site is entirely positional or entirely named. Grammar unchanged; `supplyAppNamed` may omit a flowed or defaulted parameter; a section `GIVEN` in the read-set is a suppliable name; implicits keyword-only. (Original R1 had proposed a new mixed grammar `f x WITH y IS v`; struck, never live code.)                                                                                | Positional implicits as leading parameters, which forces an order onto a set; argued against by two lenses.                                                                                                  |
| R2  | **RULED 2026-09-04** in conversation, the recommendation taken; `IMPLICIT-PROPS-DESIGN.md` §11.3 | Resolution lexical, no caller chain; a bare name resolves to own `GIVEN`, opened field or section `GIVEN` or is a check error. Sheet holding: a caller's same-named `GIVEN` supplies the section binder; same-type restatement warns, different-type errors.                                                                                                                                  | **Recommended:** a function `GIVEN` never flows; restatement of a visible section `GIVEN` is a check error. Measured cost: zero.                                                                             |
| R3  | **RULED 2026-09-04** in conversation; `IMPLICIT-PROPS-DESIGN.md` §11.4                           | Visibility as shipped, nearest ancestor with fallback; same-named section binders in different sections are distinct binders; one binder per name **per root**, a root reaching two being a check error naming both by section (hoist, rename, or bridge with `g WITH foo IS foo`); fix the parent-ambiguity defect and the §3.3.4 drift first; tier by call-site variation, never placement. | Coq subtree visibility: matches "in this Part" literally, breaks the nine sibling-section declarations, buys nothing the tiebreak lacks. Or the first draft's one binder per module, rejected in §5 item 13. |
| R4  | **RULED 2026-09-04** in conversation; `IMPLICIT-PROPS-DESIGN.md` §11.6                           | The binder is the indented `GIVEN` on the line after the heading, keyword right of the `§`; the heading-line form is not adopted; a column-1 `GIVEN` after a heading whose names the next head does not bind is a check error; the formatter never moves a `GIVEN` across the column boundary; `WHEREAS`/`WHEREIN` struck; round-trip goldens on both printers.                               | The heading-line form, which the red team had proposed for its lack of an indentation hazard; struck as looking weird.                                                                                       |
| R5  | candidate                                                                                        | Field-opening lexical only, ranked as §2.7, collision error at read and at the opening declaration, elaborated to `Proj`, binders only at `WITH`.                                                                                                                                                                                                                                             | Opt-in `OPENED` per binder; or no opening at all.                                                                                                                                                            |
| R6  | withdrawn                                                                                        | The `MAYBE`/`EITHER` propagation sugar is withdrawn, declined on measurement (§5). The taxonomy stands.                                                                                                                                                                                                                                                                                       | Keep it with five conditions (use-site `?`, bind at nearest failure-typed node, lambda its own boundary, `JUST` explicit, elaborate to `CONSIDER`).                                                          |
| R7  | candidate                                                                                        | `REFUSE` as §2.8: throw at force; `#ASSERT REFUSED`; three-valued assertions; one named definition per refusal; per-backend image; `Ref(f)` per reason, `TBD` excluded; taxonomy row split.                                                                                                                                                                                                   | Keep pre-commencement as a refusal per corpus ruling R2 and accept that transitional provisions cannot be encoded over it.                                                                                   |
| R8  | **RULED 2026-09-04** in conversation; `IMPLICIT-PROPS-DESIGN.md` §11.5                           | `TYPICALLY` one behaviour as §2.5, filled in once at the root; positional sites omit nothing explicit; one declaration owns the default; a default is a module-scope expression, cycles a check error.                                                                                                                                                                                        | Defaults stay documentation; a section binder needing a default is a definition with an override.                                                                                                            |
| R9  | candidate                                                                                        | `WITH` at directives; `LET`-reaching-callees or `e WITH x IS v` in bodies; `LET` over trailing `WITH`; `WHERE` never supplies; DMN per R-C.                                                                                                                                                                                                                                                   | Drop `LET`-reaching-callees; rebinding is application at any site. Preferred by the seasoned raters.                                                                                                         |
| R10 | candidate                                                                                        | Backends as §2.10; implicits trail; alcohol act as fourteen scalars.                                                                                                                                                                                                                                                                                                                          | Each backend places implicits from the read-set as a separate list (the same thing from the other side).                                                                                                     |
| R11 | candidate                                                                                        | `@reads x — …` or a function-level `@desc` override, so the fork register survives hoisting.                                                                                                                                                                                                                                                                                                  | Accept the collapse (rated a loss of legal meaning).                                                                                                                                                         |
| R12 | candidate; **fixes built** (§7)                                                                  | Six pre-existing defects are fixed now, ruling or no ruling.                                                                                                                                                                                                                                                                                                                                  | None sensible.                                                                                                                                                                                               |

## 5. Rejected, with the witness for each

Kept so that no later session re-proposes one without meeting its witness.

1. **`ASSUMING` as Reader `local`, dynamic binding as machine state.** The one ambient field today,
   the rule date, is machine state (`Machine.hs`, `putTemporalContext`); making it correct under
   laziness needed a two-pass deep force plus snapshot and a per-axis cache fingerprint
   (`TemporalContext.hs`), and `ok/temporal-pin-deep.l4` cases I/J/K still answer the unpinned value
   through closures by design. N user fields multiply all three costs. Dynamic scoping is an effect
   and does not survive call-by-need; implicit parameters are a coeffect and do (Yang 2020). In
   this evaluator Reader `local` is either dynamic-and-deep-pinned or lexical-and-shallow (the
   service's `LetIn` inlining, `Backend/Jl4.hs:639-665`, reaches only the inlined body because
   every top-level decide closes over the module environment); only compile-time discharge is both
   correct and cheap.
2. **`§`-subtree scoping.** Statutes declare reach by words and put interpretation sections as
   siblings, often last (BNA 1981 s 50 of 53; CA 2006 Part 38); the corpus does the same
   (`british-citizen-act.l4:3-12` declares 7 under `§§ Assumptions`, consumed at :81-155;
   `promissory-note.l4:226-228` in an end-of-file appendix, consumed at :15 and :302;
   `regcf.l4:143` → `:409`). 9 of 39 unique legal declarations go dark under subtree scoping
   (2026-09-03); 0 of 39 want it; and nearest-ancestor tiebreak visibility already ships.
3. **The enforced earmuff** (no function `GIVEN` may shadow a section binder, as a lint). It
   reversed shipped FIX A (`ok/section-scoping-param-not-shadowed.l4`) and contradicted Coq, Lean
   and GHC, guarding a capture hazard that cannot occur once names resolve statically. Note that
   the R2 recommendation re-introduces a **narrower** rule as a check error: not "no shadowing" but
   "no restatement of a visible section binder", measured at zero cost.
4. **Authored `TAKING`.** Inference is a displayed compiler fact, never written.
5. **The DMN "literal → specialise, computed → drop" rules.** Specialisation is ladder rung 2,
   which ruling R-C stops at rung 0; "computed → drop" would delete the Reg CF wizard's rebind. A
   binder lowers iff it is single-valued per evaluation.
6. **"Then the caller chain" in name resolution.** Turns a typo into a request parameter (§2.3).
7. **A new mixed supply grammar `f x WITH y IS v`.** Never parsed, never live; replaced by R1 as
   amended (§2.4).
8. **`WHEREAS`.** Wrong speech act for a typed free variable (§2.1).
9. **"Coq `Section`/`Variable` exactly", "the module is the title `§`", "extension only".** False
   as tree statements for 7 of 26 legal files, and forbids what statutes do (§2.1).
10. **Catch-anywhere exceptions.** Under laziness which exception you catch depends on evaluation
    order (Peyton Jones, Reid, Hoare, Marlow, Henderson, "A Semantics for Imprecise Exceptions",
    PLDI 1999); catching is sound only at the boundary, which is `REFUSE`. A DRG has no control
    flow to lower a catch to; the legal meaning of "catch" is defeasance, already `SUBJECT TO` and
    `MUST … LEST …`.
11. **`MAYBE`/`EITHER` propagation sugar (R6).** Seven of seven rating sets called the sample
    confusing or misleading. No use-site marker, so a `GIVETH` edit twenty lines away silently
    rewrites a body; "FEEL null propagation is literally this semantics" is false (FEEL `and`/`or`
    are Kleene, `null = null` is true, propagation ignores the decision's type); under call-by-need
    a bind under a constructor cannot fire and hoisting changes strictness; a lambda has no result
    to escape to; Docassemble refuses every produced `MAYBE`; population 28 `GIVETH A MAYBE`
    functions, 0 exported; and the deleted line `WHEN NOTHING THEN NOTHING`
    (`guardianship-of-infants-act.l4:174`) is the encoder's visible allocation of the not-proved
    case, which three Acts allocate differently.
12. **Tier by placement.** A heading-declared per-transaction date got asked once per batch (§2.1).
13. **One binder per name per module** (R3 as first drafted). It merges silently the statute's
    "for the purposes of sections 1 and 2 … for the purposes of sections 3 and 4" when the two
    are same-typed inputs, which is the case where they must not merge; replaced by distinct
    binders per section and one binder per root (§2.1, 2026-09-04).

## 6. Order of work

1. **Read-set pass**, one module, transitive over SCCs, closed at lambdas, replacing the Catala and
   Docassemble copies and the shallow collector; the helper-reads-a-binder export test first. Built
   on `fix/export-transitive-readset` (§7).
2. **Shipped section-scoping repairs**: the parent-ambiguity defect and the §3.3.4 drift. Built on
   `fix/section-scoping-ambiguity` (§7).
3. **`REFUSE`** (R7) and the empty-`DECLARE` migration of the type role, so that no refusal and no
   sort is ever suppliable, before any discharge crosses `IMPORT`.
4. **Section binder parse** per R4, with the misattachment check error and both printers' goldens.
5. **Discharge** = elaboration; `supplyAppNamed` relaxed per R1; resolution per R2; `TYPICALLY`
   honoured per R8; `WITH`/`LET` per R9; field-opening per R5 with the elaborated-AST stage.
6. **Consumers**: hover, index, `@reads`; schema tiers; `BatchRequest.world`; DMN, Catala,
   Docassemble, OpenFisca, MLIR per R10; trace needs nothing new, a supplied binder being an
   ordinary bound argument.
7. **Migration and deprecation**: a warning in `l4 check` with a code action that rewrites a term
   `ASSUME` to the ruled spelling, the warning not landing before the code action can; then corpus
   and docs, `doc/reference/types/ASSUME.md` carrying the notice and the recipe (`CLAUDE.md` §6);
   then keyword removal together with the dead `LocalAssume` grammar (`Syntax.hs:454`,
   `Parser.hs:502`; 0 legal-corpus uses, refused by Docassemble).
8. **Temporal**, last (§2.11).

**Migration recipe by role** (counts 2026-09-04: 664 `ASSUME` lines in 105 files; legal 54, ok 97,
not-ok 20, experiments 418, doc 71, libraries 2, tests-cli 2; 113 type-role): term `ASSUME` →
section `GIVEN` under the nearest heading, the 9 of 39 legal declarations that sit in a sibling
section hoisting to the title `§`, which is a no-op for visibility under R3; type `ASSUME` → an
empty `DECLARE T` (parses today: `ok/set-operators-nested.l4:36`, `ok/consider-simple.l4:3`);
refusal `ASSUME` → one named `REFUSE` definition per refusal (`regcf.l4:143, :486`,
`daydate.l4:104`, prelude `TBD` at `prelude.l4:761`, DMN fixtures `dmn/gst-rate.l4:63`,
`dmn/ymd-dates.l4:84`). Function-typed `ASSUME` (`anti-social.l4:12-28`, 21 legal, 284 in
experiments) is a `DECLARE` record in disguise and migrates to one (`IMPLICIT-PROPS-DESIGN.md`
§10.6). Getting-started tutorial: the first rule keeps its function `GIVEN person`; hoisting the
varying subject onto a heading teaches the wrong instinct (sample S1 was mis-cut that way).

## 7. Defects that stand regardless (R12)

Each reproduces on the 2026-08-27 binary; none depends on the environment design. Four branches
were built against `origin/unstable` (`7ed1589e`) by a two-round fix-and-verify workflow on
2026-09-04, each verified by an independent agent in a disposable worktree. **As of 2026-09-04 all
four are local, unpushed, and awaiting Meng's word before any PR is opened.**

| defect                                                                                                                                                                                                                                 | branch                                 | commits                                                    |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- | ---------------------------------------------------------- |
| the export schema's one-body-deep collector; `l4 batch` binding a directly-read `ASSUME` as a positional argument; same-name `GIVEN`/`ASSUME` collapse; an `ASSUME`'s `@desc` missing from its schema entry; jl4-mlir's arity mangling | `fix/export-transitive-readset`        | `de4f0b2b`, `306164b7`, `bca5d5d3`                         |
| a parent section's own reference ambiguous whenever a descendant rebinds the name (FIX D); candidates unnamed by section; `SECTION-LEXICAL-SCOPING-SPEC.md` §3.3.4 stated as shipped; residue p12 recorded open                        | `fix/section-scoping-ambiguity`        | `cfae309b`, `4357e163`, `60cd1479`, `0b4d461c`, `27f5b72c` |
| `#ASSERT` collapsing an exception to a plain failure in both polarities; an `#ASSERT` reducing to a bare assumed term reported as undecided; `#CHECK` and the REPL's `:type` printing inference gensyms                                | `fix/assert-check-reporting`           | `82152cdc`, `af9f13e1`, `a46ac120`, `2c9e3f30`, `1679c8d4` |
| the tutorial's flat `#CHECK rule WITH fact IS TRUE` form that does not run (`encoding-legislation.md:115-122`, `ASSUME.md`); a citation to a file not in the tree; the retracted binding claim's other copy                            | `fix/docs-assume-supply-and-citations` | `47580bf3`, `785c8b2d`, `b3ec6f30`                         |

Still open, filed here and not yet on a branch: `TYPICALLY`'s three images (§2.5, folded into R8);
the dead `LocalAssume` grammar (§6 item 7); function-typed `ASSUME` refused by every backend
(§6 recipe).

## 8. Measurements relied on

| what                                                                                                                              | value                                       | date       | scope                                                       |
| --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- | ---------- | ----------------------------------------------------------- |
| record-typed `GIVEN` slots that are pure pass-through                                                                             | 506 of 1,112                                | 2026-09-03 | legal corpus                                                |
| `GIVEN` slots repeating an identical name+type earlier in the same section / same file                                            | 889 (48%) / 1,177 (63%) of 1,860            | 2026-09-04 | 26 legal files                                              |
| `GIVEN` names bound at more than one type                                                                                         | 17 corpus-wide, 9 in one file, of 559 names | 2026-09-03 | legal corpus                                                |
| legal files whose title `§` is a sibling of the operative sections                                                                | 7 of 26                                     | 2026-09-04 | legal corpus                                                |
| sites reinterpreted by an "adjacency" section-binder rule / lines colliding with the indented rule                                | 160 / 0                                     | 2026-09-04 | legal corpus                                                |
| term-role `ASSUME` names / function `GIVEN` names / files where the sets overlap                                                  | 235 / 2,311 / 0 of 607 files                | 2026-09-04 | l4-ide corpus + libraries + `doc/` + canon                  |
| named-application `WITH` sites / mixed sites                                                                                      | 971 / 0 (cannot parse)                      | 2026-09-04 | session count; 1,416 tokens in 179 of 608 files on re-count |
| unique legal `ASSUME` declarations that go dark under `§`-subtree scoping                                                         | 9 of 39                                     | 2026-09-03 | legal corpus                                                |
| `ASSUME` lines / files, and type-role lines                                                                                       | 664 / 105, 113 type-role                    | 2026-09-04 | whole tree                                                  |
| Haskell files / occurrences / entry points that collect, bind, promote or lower `ASSUME`                                          | 35 / 752 / 16                               | 2026-09-04 | jl4-core 618, jl4-service 88, jl4-mlir 46                   |
| readers of the commencement refusal                                                                                               | 8                                           | 2026-09-04 | `regcf.l4`                                                  |
| `GIVETH A MAYBE` functions / exported                                                                                             | 28 / 0                                      | 2026-09-04 | legal corpus                                                |
| `EVAL UNDER RULES EFFECTIVE AT` uses, all at outermost position                                                                   | 19                                          | 2026-09-03 | legal corpus                                                |
| `WHERE`-local names coinciding with `GIVEN` names                                                                                 | 19                                          | 2026-09-04 | legal corpus                                                |
| legal-corpus definitions in leaf sections / in a section that has child sections                                                  | 2,407 / 2                                   | 2026-09-04 | legal corpus                                                |
| term-role `ASSUME`s read only in their own section / from a sibling / from a parent or child                                      | 30 / 3 / 0 of 33                            | 2026-09-04 | legal corpus (48 / 39 / 9 / 0 counting function-typed)      |
| cross-section calls into a definition sharing a `GIVEN` with ≥2 section-mates / caller has the same-named `GIVEN` / parent↔child | 312 / 195 / 0                               | 2026-09-04 | legal corpus                                                |
| names defined by `MEANS` in ≥2 sections of one file / `ASSUME`s so declared                                                       | 1 (a mixfix false positive) / 0             | 2026-09-04 | legal corpus                                                |
| named arguments of the shape `name IS r's field` / with `name` = `field`                                                          | 6 / 0                                       | 2026-09-04 | corpus + canon                                              |
| field names that are also `GIVEN` names / at mismatched types                                                                     | 15 / 5                                      | 2026-09-04 | charities cleanroom                                         |

## 9. Open

- Meng's marks on R5–R7 and R9–R12 (R1, R2, R3, R4 and R8 are ruled, §4). Accepted rulings go
  to `IMPLICIT-PROPS-DESIGN.md` §11 dated; modified ones come back here for argument.
  here for argument.
- Whether to push the four §7 branches and open PRs into `unstable`.
- Runtime shape (per-field vs one record per module) and its sharing cost; unmeasured.
- Whether `ASSUME` visibility crosses `IMPORT` today; asserted by no team, verified by none. The
  design says nothing implicit crosses `IMPORT` after discharge, which does not depend on the
  answer.
- The rank-2 implicit the per-day iterators would need (§2.11).

## Appendix A. Probes and observed outputs

Run on `~/.local/bin/l4 run` (binary dated 2026-08-27), 2026-09-03 unless marked. Kept as snippets,
not `.l4` files, so they cannot fall into a golden glob.

```l4
-- t7-named: named application exists today
GIVEN a IS A NUMBER
      b IS A NUMBER
GIVETH A NUMBER
f a b MEANS a MINUS b
#EVAL f WITH b IS 1, a IS 3          -- observed: 2
```

```l4
-- mixed (2026-09-04): the mixed form is a parse error; it was never live code
#EVAL f 3 WITH b IS 1                -- observed: parser error at 5:11-5:15, caret under WITH
```

```l4
-- t1-let: LET does not reach the callee today (lookup by Unique, Machine.hs ~3204-3212)
ASSUME x IS A NUMBER
f MEANS x PLUS 1
#EVAL LET x = 41 IN f                -- observed: "needed to know the value of x but it is an assumed term"
#EVAL LET x = 41 IN x PLUS 1         -- observed: 42
```

```l4
-- t3-shadow: a function GIVEN shadows a same-named ASSUME inside its own body only (FIX A)
ASSUME x IS A NUMBER
GIVEN x IS A NUMBER
GIVETH A NUMBER
g x MEANS x PLUS 1
h MEANS x PLUS 1
#EVAL g 1                            -- observed: 2
#EVAL h                              -- observed: assumed-term error
```

```l4
-- t4-typically: the evaluator discards the default
ASSUME x IS A NUMBER TYPICALLY 41
f MEANS x PLUS 1
#EVAL f                              -- observed: assumed-term error
```

```l4
-- t8-with-assume: WITH cannot supply an ASSUME today (f takes no parameters)
ASSUME x IS A NUMBER
f MEANS x PLUS 1
#EVAL f WITH x IS 41                 -- observed: check error at 3:7-3:21
```

```l4
-- q9 (2026-09-04): a GIVEN under a heading attaches to the next definition and is suppliable
§ `S`
GIVEN a IS A NUMBER
GIVETH A NUMBER
f MEANS a PLUS 1
#EVAL f WITH a IS 41                 -- observed: 42
```

```l4
-- q13 (2026-09-04): LET shadowing a same-named GIVEN in scope is an error today
GIVEN x IS A NUMBER
GIVETH A NUMBER
f x MEANS LET x = 41 IN x PLUS 1
#EVAL f 1                            -- observed: check error 3:25-3:31 "There are multiple definitions for the identifier x"
```

```l4
-- typ1 (2026-09-04): a default never fills in today, at either kind of site
GIVEN a IS A NUMBER TYPICALLY 10
      b IS A NUMBER
GIVETH A NUMBER
f a b MEANS a PLUS b
#EVAL f WITH b IS 1                  -- observed: check error "you forgot to supply the following arguments: a of type NUMBER"
#EVAL f 1                            -- observed: check error "expects 2 arguments, but you are applying it to 1 argument"
```

```l4
-- typ2 (2026-09-04): TYPICALLY takes an atom today
ASSUME x IS A NUMBER TYPICALLY 41
ASSUME y IS A NUMBER TYPICALLY x PLUS 1   -- observed: parse error at 2:34-2:38 "unexpected PLUS"
```

```l4
-- typ3 / typ4 / typ5 (2026-09-04): a definition as a default is refused today, with or without a cycle;
-- the literal is type-checked
ASSUME alpha IS A NUMBER TYPICALLY 10
ASSUME beta  IS A NUMBER TYPICALLY phi         -- observed: check error "The TYPICALLY value for `beta` must be a literal:
GIVETH A NUMBER                                --   a number, a string, or a nullary constructor such as TRUE, FALSE or NOTHING."
phi MEANS alpha TIMES 2                        --   (typ3; typ4, with `phi MEANS beta PLUS 1`, gives the same error)
ASSUME gamma IS A NUMBER TYPICALLY "no"        -- observed (typ5): "expected to be of type NUMBER but is here of type STRING"
```

```l4
-- nest (2026-09-04, shipped binary): visibility across nesting is module-flat today
§ outer
ASSUME alpha IS A NUMBER
o2 MEANS beta PLUS 100          -- parent reads a child's binder: resolves
§§ inner
ASSUME beta IS A NUMBER
i1 MEANS alpha PLUS beta        -- child reads ancestor + own: resolves
§§ inner2
s1 MEANS beta PLUS alpha        -- sibling reads inner's binder: resolves
-- observed: no check errors; each #EVAL fails only for want of a value
```

```l4
-- nest2 (2026-09-04): a child re-declaring the ancestor's name breaks the PARENT's own reference today
§ outer
ASSUME alpha IS A NUMBER
o1 MEANS alpha PLUS 1           -- observed (shipped): "multiple definitions for the identifier alpha" at 5:10
§§ inner
ASSUME alpha IS A NUMBER
i1 MEANS alpha PLUS 2           -- observed: resolves to inner's
-- the FIX D branch resolves o1 to outer's
```

```l4
-- reach-def / reach-asm (2026-09-04): per-section same-name, siblings; FIX D branch
§ `Sections 1 and 2`
foo MEANS "apple"               -- or: ASSUME foo IS A STRING
s1 MEANS foo                    -- observed (FIX D): resolves; (shipped): ambiguous
§ `Sections 3 and 4`
foo MEANS "banana"
s3 MEANS foo                    -- observed: resolves, both binaries
§ `Section 5`
s5 MEANS foo                    -- observed: "multiple definitions … `Sections 3 and 4`.foo … `Sections 1 and 2`.foo"
```

```l4
-- meng-fruit (2026-09-04): the layout in §2.1; FIX D branch evaluates r1..r4 to Apple, Apple, Banana, Banana;
-- a reader in `§ toplevel` and one in §§ `5` are ambiguous over all four; shipped binary also flags r1..r3.
-- Note `§§ 1` with a bare number is a parse error ("unexpected 1"); the heading needs backticks.
```

```l4
-- oversupply (2026-09-04): a named argument the callee does not take
GIVEN a IS A NUMBER
GIVETH A NUMBER
f a MEANS a PLUS 1
#EVAL f WITH a IS 1, zzz IS 2        -- observed: "I could not find a definition for the identifier zzz"
```
