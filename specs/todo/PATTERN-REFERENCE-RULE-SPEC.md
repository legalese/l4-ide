# Pattern names refer when they can — retiring `EXACTLY`

**Status: BUILT `41809c4d` (2026-09-16T12:56:24+08:00); not merged.** §1's ruling is Meng's and is unchanged
since he gave it on 2026-09-16. R1–R7, the corpus sweep, the printer change and the docs/skill
rewrite (§4 onward) are built and committed on `lang/action-binder-reference`, verified green by
`etc/verify-branch.sh` (full, not `--quick`) at this commit — nothing below describes a plan. Every
claim about the tree was checked against `41809c4d` (base `unstable` @ `11b7534b`) on 2026-09-16
unless a different tree is named beside it. Appendix A's measurements were re-taken at `11b7534b` in
Phase A and supersede the `95dcd92d` design-memo numbers this section carried before the build; A.1
records the small delta (canon vendoring landed between the memo and this base).

Branch: `lang/action-binder-reference`, worktree `~/src/legalese/l4wt/exactly-lexical`.

---

## 1. The ruling

Meng, 2026-09-16, three marks in one sitting. First the question that opened it:

> _"when we were inventing EXACTLY syntax we must have discussed the possibility of defeating
> shadowing by the obvious technique of: if the variable is already in the symbol context, then
> bind to that, else let it be free; that way there would be no need for EXACTLY and the whole
> bug class gets eliminated. can you surmise why we ended up with explicit EXACTLY?"_

Then, after a lexical-only version of that rule was put to him with before/after examples:

> _"Ok. This sounds good. Let's spec the work and include the rewrite of the existing corpus
> accordingly together with resetting goldens."_

Then the sharper question, which is the one this spec answers:

> _"I suppose there's no way to get rid of the EXACTLY keyword entirely and have the system just
> do the right thing at each instance? The principle I have in mind is that, if we know enough to
> call it an error, we know enough to correct the error."_

And the decision, on the recommendation in §4:

> _"I take your recommendation. Write the spec to this recommendation and launch Opus and Sonnet
> agents to execute."_

**What is ruled:** a bare name in a deontic action pattern refers to the thing it names when it
names anything, and is a fresh wildcard only when it names nothing (or only a field selector).
Expressions are admitted in pattern position without a keyword. `EXACTLY` is deprecated, not
removed: it still parses, still means what it meant, and warns with its replacement. The `EVERY`
rebind error is retired. The corpus is swept and its goldens reset in the same PR. Whether the
same rule extends to `CONSIDER` is decided by measurement (§4 R6), not here.

**The principle, stated as the design rule:** wherever the checker could emit "you almost
certainly meant the reference, write `EXACTLY`", it instead takes the reference. A diagnostic
survives only where the checker genuinely cannot pick the correction (§4 R7).

---

## 2. The defect

The action after `MUST`/`MAY`/`SHANT`/`DO` is parsed as an ordinary pattern, the same production
`CONSIDER … WHEN` uses (`jl4-core/src/L4/Parser.hs:2811-2851`). A bare name in argument position
becomes `PatApp n []`; the checker tries constructor resolution and otherwise makes a **fresh
binder** with no lookup of `n` in the term environment (`TypeCheck.hs:3631-3632`, then
`inferPatternVar` at `:3653`). At run time a `PatVar` binds the scrutinee unconditionally
(`EvaluateLazy/Machine.hs:2564`); a `PatExpr` is evaluated and compared for equality (`:2576`).

So this, from the reference manual's own example (`doc/reference/regulative/deontic-example.l4:80`):

```l4
GIVEN price IS A NUMBER
GIVETH A DEONTIC Actor Action
`sale contract` MEANS
    PARTY Seller
    MUST `deliver goods` "merchandise"
    WITHIN 14
    HENCE
        PARTY Buyer
        MUST `pay invoice` price
        WITHIN 30
```

is `FULFILLED` when the buyer pays 1 (measured: memo §1.4 and §2.3, probe `de.l4`). `price` in
the action is a new name matching any amount; the `GIVEN` is silently shadowed; the file checks
clean and exits 0. The only observable is a wrong verdict. Upstream issue **smucclaw/l4-ide#955**
(2026-09-07) states the same hazard for `PARTY p MUST Sign p`.

The memo counted 34 argument-position binders spelled like a local or same-module name; 33 are this
bug, the 34th is the negative fixture for the `EVERY` error; 0 are deliberate shadowing. A further
26 binders are spelled like a **field selector** of the action's own record (`Pay Alice \`Ms Ng\`
amount`); every one is a deliberate wildcard named after the slot it fills. Appendix A has the
tables.

---

## 3. How the keyword got here

Recorded so the next reader does not assume the marker was a considered choice for deontics.

- **2025-05-06, upstream #390 "Kosmikus/contracts" (Andres Löh).** Actions became patterns,
  inheriting `CONSIDER`'s pattern language: a lowercase name always binds. The corpus of the day
  pinned a value with a guard — `MUST payment fine PROVIDED fine = 10` in `ok/contracts.l4`.
- **2025-06-03, upstream #524 "[chore] allow the use of the EXACTLY keyword" (mangoiv).** Added
  `TKExact`, `patExpr`, `PatExpr`, and `inferPattern (PatExpr …)`, as a **general** pattern-position
  expression: the same commit added `CONSIDER 5 WHEN EXACTLY 3`. The `contracts.l4` guard was
  rewritten to `MUST EXACTLY payment fine WHERE fine MEANS 10`. A chore-grade PR: the minimal
  escape hatch, not a deontic design decision.
- **2026-06-24, `34a7c1c5` "deontic MUST/MAY action checks its declared type, not a fresh
  binder".** The first step in this spec's direction, taken at the **head** position only:
  `checkActionPattern` (`TypeCheck.hs:2204-2212`) treats a bare action name that resolves to an
  in-scope non-constructor term as a reference. Its comment names the footgun in terms. It was safe
  to stop there because the head has a declared expected type, so an accidental capture surfaces
  as a type mismatch; an argument slot gives no such net.
- **2026-09-07, `QuantifierVariableRebound`** (`TypeCheck.hs:1975`, message `:6033-6045`). The
  `EVERY` build met the same hazard for the roll variable and chose a third path: refuse, and tell
  the author to write `EXACTLY t`. Its message is the checker naming the correction it declines to
  make — the sentence Meng's principle in §1 is aimed at.

Meng's reading of this history (2026-09-16), recorded as his surmise and not verified with either
author: _"I have to imagine that Andreas and mangoiv had vague plans to eventually move in this
direction but lacked the round tuits at the time to grind out the work needed. Especially when
there were competing priorities."_ The record is consistent with it — a chore-labelled escape
hatch, then a year later the head-position rule with a comment that reads as the first instalment
— but that is all the record says.

---

## 4. The rule

### R1. A bare name in an action argument position resolves in this order

For `PatApp n []` in any argument position of a regulative action pattern (and, unchanged, at the
head — `checkActionPattern` already does this for arity 0):

| `n` resolves to                                                                                                 | reading                                                          |
| --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| any data constructor                                                                                            | constructor pattern (unchanged)                                  |
| a **lexical local** — GIVEN, lambda parameter, WHERE/LET local, outer action binder, CONSIDER or EVERY variable | **reference** (`PatExpr (Var n)`), type-checked against the slot |
| any other in-scope term that is not a selector — same-module top-level, section-level, `ASSUME`d, **imported**  | **reference**, plus the R5 notice                                |
| only `Selector` / `ComputedSelector` candidates, or nothing                                                     | fresh binder (unchanged)                                         |

The checker can already tell lexical from module-level: `extendKnownMany` marks its bindings in
`CheckEnv.localBindings` (`TypeCheck/Types.hs:727`, `:1981-1987`, whose comment lists "parameters,
WHERE/LET, pattern variables, type variables"), and `extendKnownGlobalMany` (`:1989`) does not.
`TermKind` (`Syntax.hs:795-803`) alone is **not** the discriminator: a WHERE local and a top-level
`MEANS` are both `Computable`. Use `localBindings` for the lexical row and `TermKind` for the
selector carve-out.

Why imports are references and not wildcards: under a deprecated `EXACTLY`, `MUST Pay
importedLandlord` with the import treated as "not in scope for this purpose" would be a silent
wildcard — the defect of §2 reintroduced for one class of name. The rule is uniform: **a pattern
name never silently shadows anything in scope.** Selectors are the one carve-out because a
selector is a function and can never be the intended value in an action slot; all 26 corpus
sites of that spelling are deliberate wildcards (Appendix A.4).

Overloading: a name with both a constructor and a term candidate keeps constructor semantics
(unchanged from `namesNonConstructorTerm`, `TypeCheck.hs:2218`). A lexical local whose type does
not fit the slot is a type error, not a fallback to a wildcard (§4 R7).

**CORRECTED 2026-09-16 (Phase E review, Phase F build): the selector carve-out is an ARGUMENT
rule, and the parenthetical above — "and, unchanged, at the head" — was false of the build as first
written.** Base's head rule (`namesNonConstructorTerm`, `34a7c1c5`) counted a selector as a term,
so `PARTY Buyer MUST amount`, where `amount` is a field of the action's own record, was a reference
and failed the head's declared type. Applying row 4 at the head as well turned that compile error
into a fresh name at the head — and a fresh name at the head matches **every** action, so
`PARTY Buyer MUST amount` was discharged by `ship 3`, silently, with `Check succeeded`. The
carve-out now applies only where its evidence was gathered (the 26 argument-position wildcards of
Appendix A.4); at the head a selector-spelled name stays a reference. Fixture:
`jl4/examples/not-ok/tc/action-head-selector.l4`.

**ADDED 2026-09-16 (Phase E review, Phase F build): `ASSUME`d referents are ruled IN, deliberately,
and the run-time failure is accepted.** R1's third row lists `ASSUME`d terms as references, and
under it `ASSUME price IS A NUMBER` + `MUST pay price` fails at the first `#TRACE` with "trying to
check equality on types that do not support it" where base answered `FULFILLED`. That is the right
trade and it is not a defect: base's answer was a silent wrong verdict (the wildcard of §2), and an
uninterpreted term does not evaluate anywhere else either (CLAUDE.md §5). A loud failure replaces a
quiet wrong one. Function-typed referents are the case that _is_ refused, at check time — see R7.

### R2. Expressions are admitted in pattern position without a keyword

Anything in pattern position that is **not** a name, a literal, a constructor application, a cons
or a parenthesised pattern is an expression, evaluated and compared for equality — what `PatExpr`
does today. Literals already work without the keyword: measured 2026-09-16 with the
`lang/r5-field-opening` worktree binary (base `0b640727`), `MUST pay 100` stays pending on `pay 1`
and is fulfilled by `pay 100`, and `CONSIDER 3 WHEN 3` matches only 3 (probe `lit3.l4`). Arithmetic
does not: `MUST pay (price PLUS 50)` is a parser error, `unexpected PLUS` (probe `lit.l4`). The
build re-measures both on this branch's own binary.

Acceptance cases for the grammar: `MUST pay (price PLUS 50)`; `MUST Deliver (t's landlord) what`;
`MUST pay (Money 1000 "USD")` (already a constructor pattern; must keep working);
`MUST Receipt landlord t (amount MINUS 5)`. Inside a constructor application an expression argument
is a `PatExpr` argument. The parser tries the pattern reading first and takes the expression
reading only where the pattern reading cannot apply; the build reports where backtracking was
needed and what it costs.

### R3. `EXACTLY` is deprecated, not removed

`EXACTLY e` still parses to `PatExpr e` and means what it means today. The checker emits
`CheckWarning (DeprecatedExactly …)` — the `DeprecatedAssume` shape (`TypeCheck/Types.hs:279`,
severity `SWarn`, LSP `Deprecated` tag) — whose text gives the exact replacement: for a name
operand, drop the keyword; for an expression operand, drop the keyword and keep the parentheses.
~~Dropping the keyword is always meaning-preserving under R1/R2: an operand that resolves to nothing
is already an error today (`not-ok/tc/every-unbound-variable.l4`), and one that resolves only to a
selector is already a type error, so no surviving `EXACTLY` operand can become a wildcard.~~

**CORRECTED 2026-09-16 (Phase A2 measurement, Phase B build).** That sentence is false for one
class of operand, and it is false in the direction that matters. An operand resolving to nothing
_is_ an error today — but the error is `could not find a definition`, and under R1 dropping the
keyword replaces that error with a **fresh wildcard that matches anything**, which is the §2 defect
itself. The reasoning confused "already an error" with "still an error afterwards".

So the warning is conditional, and `DeprecatedExactlyInfo.advice` is an `ExactlyAdvice`
(`jl4-core/src/L4/TypeCheck/Types.hs`, computed by `exactlyReplacement`,
`jl4-core/src/L4/TypeCheck.hs`). For a bare-name operand whose R1 reading is `ReadsAsBinder` — it
names nothing in scope, or only a field selector — the warning still says the keyword is being
retired but **does not offer the drop**, and says instead that dropping it would change what the
rule requires. Every other operand class is safe and gets its pasteable line: a literal is already
a literal in pattern position, a constructor is already a constructor pattern, and a reference is
what `EXACTLY` meant.

Phase A2 measured the corpus: **one** site is in the unsafe class,
`jl4/examples/not-ok/tc/every-unbound-variable.l4:11`, which is the fixture for that very error and
which §5.1 already keeps. So the sweep is unaffected; what changes is that the checker can no
longer mislead a future author into the defect.

**CORRECTED AGAIN 2026-09-16 (Phase E review, Phase F build): there are TWO unsafe classes, not
one, and the second one type-checks either way.** A bare-name operand that names a data constructor
**as well as** a value reads differently with the keyword and without it: `EXACTLY n` evaluates `n`
as an expression and finds the value, while the bare name takes R1's first row and is the
constructor pattern. Measured on `jl4/examples/ok/regulative-exactly-constructor-overload.l4`, with
the `GIVEN red` supplied as `green`: `MUST paint (EXACTLY red)` is discharged by `paint green` and
`MUST paint red` is not. The warning was recommending that exact edit, on a file `l4 check` called
clean before and after — the §2 defect shape, introduced by the migration advice itself. So
`ExactlyAdvice` has a third case, `KeepItShadowedByConstructor`, whose message names the collision
and asks for a rename. `actionNameReading` tells the two constructor readings apart
(`ReadsAsConstructor` / `ReadsAsConstructorShadowingTerm`); the pattern semantics of both are
unchanged, the distinction exists only so the advice can be honest.

Compound operands were checked and are safe as they stand: `prettyLayout` prints an application in
its `OF` form (`Money OF amt`), which the pattern production cannot read, so a pasted replacement
cannot fall back into a constructor pattern with fresh names.

The prerelease shelf ships `unstable` to outside users (CLAUDE.md §1), so removal of the keyword is
a **separate ruling** for Meng, after at least one shelf cut with the warning live (§10).

### R4. `QuantifierVariableRebound` is retired

Under R1, `EVERY Tenant t MUST Sign t` means the member; the error's message ("this would be a
fresh name matching anyone") would be false. Remove the check at `TypeCheck.hs:1973-1975`, the
constructor, the message, and the `EVERY.md` paragraph that documents it. Its fixture
`jl4/examples/not-ok/tc/every-rebinds-variable.l4` moves to `jl4/examples/ok/every/` as a positive
fixture with a trace in which a stranger's signature does **not** discharge the member's duty and
the member's own does.

### R5. A notice, never a request, for non-lexical captures

When R1 takes the third row — a pattern name referring to a top-level, section-level, `ASSUME`d or
imported term — the checker emits a `CheckInfo`-severity notice naming what was referred to and
where it is defined, in the `ActionPatternReference` shape (`SInfo`; `jl4-core/src/L4/TypeCheck/Types.hs:205-217` —
not `SuspiciousBinderPattern`, an older, unrelated shape this section named before the
implementation settled). It asks the drafter for
nothing. Its job is the one thing no marker-free design can make loud: a top-level name added
later that captures what used to be a wildcard. It does not fire for lexical locals (that reading
is unambiguous and the corpus is unanimous) and not for constructors. The build reports how many
fire over the swept corpus; if the count is noisy, the severity is Meng's to lower, not the
build's.

**NARROWED 2026-09-16 (Phase E review, Phase F build): arity-0 only.** R1's applied form — a head
that names something in scope and takes arguments, `(`Forfeiture Reason` `award state`) — was also
drawing the notice, whose text ("refers to … rather than introducing a new name of its own", "a
placeholder that matches anything") is false of an applied head: it could never have introduced a
name, and base refused the same text outright with "I could not find a definition". Three of the 26
notices in the goldens were that class, all in `legal/ceo-performance-award.l4`(:360, :364, :415),
and they are gone. Measured after the fix —`grep -rc "rather than introducing a new name of its own" --include=\*.golden .`— **19** notices
remain over the whole corpus, every one of them a name that really could have been a placeholder.
(Two of the difference are not this narrowing: restoring`ok/regulative-exactly-later-argument.l4`
to the keyword turns two of its notices into deprecation warnings.) That is the count for Meng's
severity question in §10.2.

**Phase D's raw count, which the golden-grep figure above undercounts and explains why.** Before
the arity-0 fix, `l4 check` over every one of the 1066 tracked `.l4` files (not only the goldened
subset — `etc/`'s scratch `count-notices.sh`, on the pre-fix snapshot `l4-diff`) found **72** R5
notices across 21 files, and **1** deprecation warning (the kept `not-ok/tc/every-unbound-variable.l4`
fixture; at that point in the build `ok/regulative-exactly-later-argument.l4` had not yet had its
keyword restored, so its would-be deprecation warnings were still counted as R5 notices — 7 of the
72). Per file: `doc/reference/regulative/every-example.l4` 4 · `every-run-example.l4` 3 ·
`doc/tutorials/obligations/several-parties.l4` 3 · `jl4/examples/legal/ceo-performance-award.l4` 3 ·
`jl4/examples/legal/promissory-note.l4` 3 · `jl4/examples/not-ok/tc/every-join-under-party.l4` 1 ·
`jl4/examples/ok/every/barrier.l4` 1 · `fork.l4` 2 · `nested.l4` 2 · `rand.l4` 1 · `run-barrier.l4` 1 ·
`run-fork.l4` 2 · `run-in.l4` 1 · `jl4/examples/ok/regulative-exactly-later-argument.l4` 7 ·
`jl4/examples/ok/regulative-reference-outer.l4` 2 · `jl4/experiments/jerseyCharities2-tests.l4` 13 ·
`jl4/experiments/jerseyCharities2.l4` 13 · `promissory-note-amount.l4` 3 · `promissory-note-list.l4` 1 ·
`promissory-note-tracking.l4` 3 · `safe-post-new.l4` 3.

Of the 72, **13** are the applied-call-head reading this section's own "NARROWED" fix removes, and
the fix's effect is wider than the 3 (ceo-performance-award) already counted above: re-checked
directly against the branch binary (`41809c4d`), `jl4/experiments/jerseyCharities2.l4` and its
`-tests` twin each drop from 13 notices to 8 (5 removed each; sites `:858 :912 :913 :921 :1031`,
e.g. `commencement` inside `(addDays commencement 28)`, itself one argument of an outer
`RequiredStepsNotice` application), and `ceo-performance-award.l4` drops from 3 to 0 — 5+5+3=13,
confirmed by direct measurement, not by repeating the earlier count. Neither `jerseyCharities2.l4`
nor its `-tests` twin is under a goldened glob (`jl4/experiments/` is in none of `jl4-test`'s globs,
CLAUDE.md §3.1), which is why their 26 combined notices never reached the `*.golden` grep this
section's "19" is based on: the raw, whole-corpus count and the golden-text count are measuring
different populations, not disagreeing about the same one.

### R6. `CONSIDER` is measured first and extended only if its numbers look like the deontic ones

`CONSIDER … WHEN` shares the pattern language, and R1 could be applied there by the same code.
It is **not** applied by this spec. Two reasons. The memo's survey covered deontic actions only.
And in `CONSIDER` a pattern that becomes a `PatExpr` changes exhaustiveness analysis — commit
`14b380bc` (2026-07-03) stands pattern analysis down for `CONSIDER`s with literal or expression
patterns — which feeds the DMN lowering and the GuardedRows normaliser. Phase A runs the survey
over `CONSIDER` binders with the same scope model. **Criterion to extend:** every binder that
collides with a lexical local or same-module term is, on reading the file, intended as a
reference, and none is a deliberate shadowing wildcard. If the count is zero or the criterion
holds, the build applies R1–R3 to `CONSIDER` in the same PR and records the numbers here. If any
site is a deliberate wildcard, the rule stays deontic-only, `EXACTLY` stays undeprecated in
`CONSIDER`, and the site list goes to §10 for Meng.

**DECIDED 2026-09-16 (phase B, commit `b8f2dc3b`, 2026-09-16T09:20:31+08:00), by the criterion above: DEONTIC-ONLY.** R1, R2 and R3 are
**not** applied to `CONSIDER`; `EXACTLY` stays undeprecated there and remains the only way to pin a
value in a `WHEN`.

Phase A1 measured, at base `11b7534b`, with the same scope model as the deontic survey: 993
`CONSIDER` nodes, 2303 branches, 1094 branch bare-name binders, **57** colliding with an in-scope
term — 35 selector-only, **22 local-or-module** (18 `GIVEN`, 4 `import`; none from a desugared
multi-clause `DECIDE`). The numbers are in Appendix A.5.

The criterion asked whether every colliding binder is, on reading the file, intended as a
reference. It is not — **all 22 are deliberate wildcards**, and several would break outright:

- **The `Maybe`-unwrap idiom, 8 sites** (`jl4-core/libraries/prelude.l4:481, 493, 504, 533` and
  their `thailand-cosmetics/prelude.l4` copies at `405, 417, 427, 454`). `fromMaybe default x`
  is written `CONSIDER x WHEN NOTHING THEN default WHEN JUST x THEN x`: the inner `x` rebinds to
  the **unwrapped payload**, and the arm body needs that payload, not the outer `MAYBE a`. Under
  R1 the inner `x` would refer to the scrutinee, making the arm an equality test `x == JUST x` —
  a self-referential type error that breaks `fromMaybe`, `maybe`, `orElse` and `maybeToList`, i.e.
  the standard library.
- **The mnemonic payload name, 7 sites** (`prelude.l4:691, 692`; `ok/datatypes.l4:68, 69, 78`;
  `ok/nlg_decide3.l4:15, 17`, plus `thailand-cosmetics/prelude.l4:600, 601`). `either left right x`
  writes `WHEN LEFT a THEN left a` where the outer `a` is a **type variable**. An equality reading
  is not even meaningful — you cannot compare a value to a type — so the collision is with
  something that could never have been the intended referent.
- **`Restart at`, 2 sites** (`jl4-core/libraries/hierarchy.l4:257, 267`). The binder `at` shadows
  both prelude's list-indexing `at` and the module's own `Restart.at` selector, and the arm
  computes `at PLUS 1` on the constructor's own NUMBER payload.
- **`count`, 2 sites** (`jl4/experiments/safe-post.l4:173, 451`), same shape.
- The remaining site (`jl4/experiments/base-money.l4:23`) is the same unwrap idiom.

The asymmetry is worth stating because it is the reason the two positions get different rules. A
`CONSIDER` pattern **destructures**: rebinding a name to a payload of a different type is the
idiom, and the scrutinee is right there on the same line, so the reader can see what is being taken
apart. A deontic action pattern does not destructure anything the reader can see — there is no
scrutinee in the text, only a future event — so a name there has nothing to be "the payload of",
and a silent rebind has no local evidence at all. The same syntax is doing two different jobs.

Per R6 this is not fallout for §10: the criterion was applied and it decided. What is left open is
whether `CONSIDER` should ever get a **different** treatment (for instance, a notice when a branch
binder shadows a same-typed lexical local), which is a separate question this spec does not open.

### R7. What remains an error, and why the principle does not reach it

A reference whose type does not fit the slot — `GIVEN amount IS A NUMBER` and `MUST Deliver amount`
where `Deliver`'s field is a `Thing` — is a type error with two possible corrections (a wildcard
that wants a different spelling, or an action whose type is wrong), and the checker cannot pick.
This is the same trade `checkActionPattern`'s comment already records for the head position.
The message should say both corrections.

**EXTENDED 2026-09-16 (Phase E review, Phase F build): a pinned value that cannot be COMPARED is
the second error, for the same reason.** An action holding a value accepts only events carrying
that same value, which is an equality test, and a **function** has no equality. So
`GIVEN g IS A FUNCTION FROM NUMBER TO NUMBER` with `MUST apply g` can never match anything: base
made it a wildcard and answered `FULFILLED`, and R1 as first built type-checked clean and then died
at the first `#TRACE` with "trying to check equality on types that do not support it", naming
neither `g` nor the slot. It is now `ActionPatternNotComparable`, raised at check time, in argument
position only — at the head a function-typed action already fails the rule's declared
`DEONTIC OF …` type, and that message is the better one. Both spellings are refused, because
`EXACTLY g` and the reference R1 synthesises are the same pinned pattern. The two corrections it
names are R7's two. Fixture: `jl4/examples/not-ok/tc/action-pinned-function.l4`.

Note what is **not** carved out. Extending R1 row 4 to every function-typed referent would have
kept those files running, by making the name a silent wildcard — which is the trade §2 exists to
refuse. The selector carve-out survives on evidence (26 corpus sites, all deliberate wildcards),
not on the fact that a selector is a function.

**What review changed.** Three findings from the Phase E review were reproduced against the
pre-fix snapshot (`l4-diff`) and fixed in Phase F; each is verified here against the built tree,
not just described:

- **HIGH — the `EXACTLY` deprecation warning recommended a replacement that silently changes the
  rule's meaning, for an operand naming both a constructor and a term.** Reproduced with
  `jl4/examples/ok/regulative-exactly-constructor-overload.l4` (`GIVEN red` supplied as `green`):
  `paint (EXACTLY red)` is `FULFILLED`, but the warning's own recommended edit, `paint red`, reads
  under R1's first row as the _constructor_ pattern and is not — the §2 defect, reintroduced by the
  migration advice itself. Fixed by telling the two constructor readings apart:
  `ActionNameReading` gained `ReadsAsConstructorShadowingTerm` (`jl4-core/src/L4/TypeCheck.hs:2263-2287`),
  returned by `actionNameReading` (`TypeCheck.hs:2306-2321`) exactly when a name has both a
  `Constructor` candidate and a non-selector value candidate — pattern semantics are unchanged,
  since `inferPattern` still treats it as `ReadsAsConstructor`. `DeprecatedExactlyInfo`'s
  `replacement :: Maybe Text` became `advice :: ExactlyAdvice` (`jl4-core/src/L4/TypeCheck/Types.hs:323-363`)
  with three cases — `DropTheKeyword` / `KeepItUnresolved` / `KeepItShadowedByConstructor` — the
  third naming the collision and asking for a rename, with its own message
  (`TypeCheck.hs:6457-6465`). Golden: `jl4/examples/ok/tests/regulative-exactly-constructor-overload.golden`.
- **MEDIUM — the printer re-emitted a pinned name bare even where the same overload made that a
  different pattern.** `printActionPattern` printed `paint (EXACTLY red)` as `paint red`, changing
  which colour discharges the obligation on re-parse — a residual round-tripping into a different
  meaning while the round-trip property (parse → print → parse → type-check) stayed green, the
  same §3.2.1 shape the evaluation differential exists to catch by hand. Fixed by provenance
  rather than by scope: `printPinned` (`jl4-core/src/L4/Print.hs:1043-1052`) keeps the keyword,
  parenthesised, for any `PatExpr` whose own annotation carries the `EXACTLY` token, and prints
  bare only for one the checker itself synthesised — sound because R1 only synthesises a `PatExpr`
  for a name it has already resolved to a non-constructor, so the bare print re-parses to the same
  reference. `exactlyKeywordRange` moved from `TypeCheck.hs` to `jl4-core/src/L4/Syntax.hs:809-828`
  so the checker and the printer read one definition.
- **MEDIUM — R1 turned a wildcard into an equality test against a value that has no equality, for
  function-typed slots.** `GIVEN g IS A FUNCTION FROM NUMBER TO NUMBER` with `MUST apply g`: base
  made `g` a silent wildcard and answered `FULFILLED`; R1 as first built type-checked the file
  clean and then died at the first `#TRACE` with "trying to check equality on types that do not
  support it," naming neither `g` nor the slot. Fixed with a new check-time error,
  `ActionPatternNotComparable (Expr Name) (Type' Resolved)` (`TypeCheck/Types.hs:219-225`, `rangeOf`
  at `:586`), raised in `inferPattern`'s `PatExpr` case (`TypeCheck.hs:3907-3926`) when the pinned
  expression's inferred type is a function type and the position is `InActionArgument` — covering
  both an author-written `EXACTLY g` and the reference R1 synthesises, since both produce the same
  `PatExpr`. Fixture: `jl4/examples/not-ok/tc/action-pinned-function.l4`.

Two more Phase E findings are recorded next to the rule tables they correct, rather than repeated
here, per `CLAUDE.md`'s "a decision is recorded in its owning document": R1's selector carve-out is
an argument-position-only rule (above, "CORRECTED"), and R5 fires at arity 0 only (§4 R5,
"NARROWED"). All five are why the CORRECTED/EXTENDED/NARROWED markers are spread through §4, §5 and
§6 instead of collected in one diff.

---

## 5. The corpus sweep

At `11b7534b` there are **190** `EXACTLY` tokens in tracked `.l4` files (comments included), in:
`jl4/examples/ok` 18 files, `not-ok` 12, `legal` 6, `doc/tutorials/obligations` 3,
`doc/reference/regulative` 3, and one file each in `paper/case-studies/charities-jersey-2014`,
`jl4/experiments`, `jl4/examples/lsp`, `docassemble`, `blawx`, `doc/courses/advanced`,
`doc/concepts/legal-modeling`. **None in `jl4/examples/canon/`**, the vendored mirror, which must
not be edited here (CLAUDE.md §3.1; `etc/sync-canon.mjs --check` would refuse the PR). 25 markdown
pages outside `specs/` mention the keyword.

1. **Drop `EXACTLY` at every use** in deontic actions (and in `CONSIDER` iff R6 extends), keeping
   parentheses around expression operands. Meaning-preserving by R3, and the sweep proves it: for
   every file with a `#TRACE` or `#EVAL`, `l4 run` output before and after the edit, both under
   the **new** binary, must be identical apart from the deprecation warning. One exception is
   kept: `not-ok/tc/every-unbound-variable.l4` keeps its `EXACTLY` because its purpose is the
   unbound-operand error; its golden gains the deprecation warning.

   **CORRECTED 2026-09-16 (Phase E review, Phase F build), twice.** (a) Three more files keep the
   keyword, because a deprecated construct still needs fixtures: `ok/regulative-exactly-later-argument.l4`
   was swept and thereby lost its own subject (it is the `PatApp1` later-argument scope regression),
   so it is restored to the keyword and gains bare twins at its foot; it is now also where the
   warning's _pasteable_ branch is pinned, which nothing covered. `ok/regulative-exactly-constructor-overload.l4`
   and `not-ok/tc/action-pinned-function.l4` are new and keep it deliberately. (b) The sweep dropped
   the keyword but left the parentheses that had bracketed it, so 94 argument slots across 26 files
   read `Sign (t)` where R3 asks for `Sign t` — cosmetic in the corpus, not cosmetic in the pages
   that quote it (`doc/reference/regulative/EVERY.md` showed `Sign t` against an `every-example.l4`
   that said `Sign (t)`) and not cosmetic in the goldens, where the parens were the diagnostic's
   anchor (`every-cast-not-party` pointed at `(s)`, columns 28-31, while quoting `s`). Stripped, with
   a per-file `l4 run` differential over all 26 showing the Result blocks unchanged and only
   diagnostic ranges moving.

2. **The 34 hazard sites** (Appendix A.3) change meaning without changing text — that is the fix.
   Where a trace exists, add one mismatching event so the golden witnesses the narrowing:
   at minimum `doc/reference/regulative/deontic-example.l4` (§2's example) and the moved `EVERY`
   fixture. `jl4/examples/legal/ceo-performance-award.l4` is under a goldened glob and its
   residuals will re-print; the diff must be read and explained, not blessed blind.
3. **Docs.** Every page in the 25 that teaches `EXACTLY` is rewritten to teach the rule — in the
   reader's world (CLAUDE.md §6): "a name in an action refers to the thing it names; a new name
   is a placeholder that matches anything" — with one deprecation note in
   `doc/reference/regulative/DEONTIC.md` and `README.md`. The stale README paragraph "Order
   EXACTLY arguments before pattern names … currently rejected at evaluation time" (memo §1.4) goes.
   `doc/reference/regulative/EVERY.md:220-228` (the retired error) goes. `doc/reference/GLOSSARY.md`
   entry updated. `doc/test-docs.sh` must pass with **this branch's** `l4` first on `PATH`
   (CLAUDE.md §3.1, the stale `~/.local/bin/l4` trap).
4. **The skill.** `skills/writing-l4-rules/` (`SKILL.md`, `references/regulative.md`,
   `source-patterns/05-…`, `06-…`) corrected here. The `legalese/l4-plugin` copy is generated and
   its generator is not on `unstable` (CLAUDE.md §1.0); the PR says the port is owed and the GM
   hand-ports after merge.
5. **Checker comments.** `TypeCheck.hs:1966-1975` and `:2186-2212` describe the old world; rewrite
   them to describe R1.
6. **Goldens.** After the sweep, one blessing pass: run `cabal test jl4-test`, read every changed
   `.actual` against its golden and classify the diff (warning removed; residual re-printed; error
   retired; new fixture; new trace), then bless by deleting only those goldens and running the
   suite twice (`failFirstTime`; **there is no `--accept` flag**). `etc/check-corpus-goldens.mjs`
   clean. `grep -c /Users/` over every new golden is zero (CLAUDE.md §3.1.1).

---

## 6. The printer

`L4.Print.prettyLayout` today prints a `PatExpr` as `(EXACTLY e)` (memo §2.3: the
`ceo-performance-award` residuals print `(EXACTLY Milestone Type)`). Under R3 that would print a
deprecated form. Change: a `PatExpr (Var n)` prints as `n`; a `PatExpr` of a literal prints the
literal; any other `PatExpr e` prints as `(e)`. Re-parsing the printed module under R1/R2 yields
the same resolved pattern because scope is the same module. The round-trip property in
`jl4/tests/Main.hs` (parse → print → parse → type-check) covers the first two; **the evaluation
differential of CLAUDE.md §3.2.1 is owed by hand** because `L4/Print.hs` is in the diff, with the
binary snapshotted first. `Rules.ExactPrint` is untouched (tokens).

**CORRECTED 2026-09-16 (Phase E review, Phase F build): "a `PatExpr (Var n)` prints as `n`" is
unsound for one name, and the sentence about round-tripping above was the confident version of the
same mistake.** Where `n` names a data constructor as well as a value, the printed bare name
re-parses under R1 row 1 as the **constructor pattern**, which is not what the pinned expression
meant — measured on `ok/regulative-exactly-constructor-overload.l4`, where `paint (EXACTLY red)`
printed as `paint red` and the residual changed which colour discharged the obligation. The printer
has no scope and cannot test for the overload, so it uses provenance instead: a pinned pattern
whose **source wrote the keyword** prints the keyword back (`exactlyKeywordRange`, moved to
`L4.Syntax` so the printer and the checker read it the same way), and one the checker **synthesised
for a bare name** prints bare — which is sound by construction, because R1 only synthesises for a
name it has already resolved to a non-constructor. After the sweep the second kind is almost all of
them, so residuals still print in the new spelling, which is what this section wanted.

**The differential was run twice, and the first run was measuring a stale instrument** — the
familiar §3.2.1 shape in a new place. `cabal build all` does **not** build test suites, so
`cabal list-bin jl4-test` handed back the phase-D binary and the printed modules came from the old
printer; `cmp` against the earlier snapshot showed the two byte-identical. Rebuild with
`--enable-tests` before snapshotting. Second run, 393 modules printed, 235 comparable: **230
identical, 5 differing**, all five accounted for and none of them this branch's — `ok/excel-date/serials.l4`
and `ok/ledger/bitemporal-recall.l4` stamp wall-clock time (§3.2.1 names both), `ok/mixfix-garden-path.l4`
is the loud failure §3.2.2 documents, and `legal/sg-succession/sg-wills.l4` with its
`canon/` mirror differ by a recursion-depth overflow in the printed module that **reproduces at
base**, on `l4-base` with a base-printed module.

---

## 7. Other consumers of `PatExpr`

Fourteen modules mention `PatExpr` at this base: `Catala/Lower`, `Dmn/Analysis`,
`EvaluateLazy/Machine`, `Export/Document`, `Parser/ResolveAnnotation`, `TypeCheck/Annotation`,
`Viz/GuardedRows`, `Desugar`, `Print`, `Parser`, `Nlg`, `Syntax`, `StateGraph`, `TypeCheck`.
While R6 keeps the rule deontic-only, the set of `PatExpr` values reaching the `CONSIDER`-side
consumers (Catala, DMN, GuardedRows, Nlg) does not change. `StateGraph` and `Export/Document` read
regulative patterns and must be checked. Phase A inventories each consumer's handling; the build
lists any whose output changes and why.

---

## 8. The LSP

The "which reading did the machine take" signal leaves the text. Its home is hover: on a pattern
name, "refers to `price`, GIVEN at line 57" or "binds a new name". Semantic tokens distinguishing
binder from reference are the durable version and are **not** in this PR (smucclaw#954 notes no
LSP golden covers a regulative rule at all); hover is a SHOULD if it is cheap in
`jl4-lsp/src/LSP/L4/Rules.hs`, otherwise deferred to §10.

---

## 9. Acceptance

- `etc/verify-branch.sh /Users/mengwong/src/legalese/l4wt/exactly-lexical` green (full, not
  `--quick`), and the script's own "not run" list stated in the PR.
- New fixtures under `jl4/examples/ok/regulative/` (or beside their siblings): R1 lexical
  reference for each binder kind; R1 top-level and imported reference with the R5 notice in the
  golden; R1 selector-spelled wildcard unchanged; R2 each acceptance case; R7 type mismatch under
  `not-ok/tc/`; the moved `EVERY` fixture. Each `ok/` fixture carries a trace with one matching
  and one mismatching event.
- Deprecation warnings over the swept corpus: exactly the kept `not-ok` fixture. R5 notices:
  counted and reported.
- Evaluation differential (§6) run and reported: files compared, files differing, each difference
  explained.
- `doc/test-docs.sh` green with the branch binary first on `PATH`.
- `R6` decided by the criterion, with the `CONSIDER` numbers recorded in Appendix A.5.
- This spec's status header updated to BUILT with the commit, and Appendix A replaced by the
  base-`11b7534b` measurements.

---

## 10. Open, for Meng

1. **Keyword removal.** When, after the deprecation has shipped on at least one shelf cut.
2. **R5 severity.** The count is now known — **19** notices over the swept corpus by the
   golden-text measure (§4 R5), or 59 by the broader whole-corpus `l4 check` measure that also
   reaches the two non-goldened `jerseyCharities2` files (§4 R5, "Phase D's raw count"). Meng's to
   set (`SInfo` today); nothing in the build depends on which way this goes.
3. **R5 field opening** (`IMPLICIT-PROPS-DESIGN.md` §11.7, in build on `lang/r5-field-opening`).
   An opened field spelled like the action's own slot — `amount` in `Pay t landlord amount` inside
   a rule that opens a record with an `amount` — would flip from wildcard to reference under R1 if
   opened fields are lexical locals. Rule when R5 lands; this spec takes no position.
4. **Semantic tokens** for binder vs reference (§8). Hover was not added either (checked: the only
   LSP change on this branch, `jl4-lsp/src/LSP/L4/Rules.hs`, is the `Deprecated` tag on
   `DeprecatedExactly`, R3's own diagnostic — nothing about which reading R1 took). Still open.

**Settled by the build, and removed from this list rather than left to look open:** R6 fallout —
"only if the `CONSIDER` measurement finds a deliberate shadowing site" (the condition this item was
conditioned on). The measurement (Appendix A.5) found none: all 22 colliding `CONSIDER` binders are
deliberate wildcards (§4 R6), so the criterion applied cleanly and decided DEONTIC-ONLY with nothing
left over for Meng to rule on.

---

## Appendix A. Measurements (re-taken at `11b7534b`, superseding the `95dcd92d` memo)

Method: `etc/survey-pattern-binders.py --mode deontic`, now committed under `etc/` (the memo's own
`exactly_survey.py`, ported and hardened per the tool's own docstring). Unlike the memo, it does
**not** prefilter files by a `MUST`/`MAY`/`SHANT`/`DO` grep — a multi-clause `DECIDE` that desugars
to a regulative pattern carries no such literal token — so it walks `l4 ast` over every one of the
**1066** tracked `.l4` files (`git ls-files '*.l4'`), against the base binary (`l4-base`, `11b7534b`;
no code changes on top of it at this base), with the scope model in the tool's own module docstring:
module top level (`MEANS`/`ASSUME`/`DECLARE` and selectors, including nested `SECTION`s and one
level of `IMPORT`), section `GIVEN`s, a rule's own `GIVEN`/app-form params, `WHERE`/`LET` locals,
lambda params, `CONSIDER`/`EVERY` binders, and an outer action's own binders for `PROVIDED`/`HENCE`.

**53** of the 1066 did not yield a survey record — the full list is in the tool's own JSON output
(`files_failed`). They are not all the same kind of failure: **25** are the survey script's own
regex-based re-parse of `l4 ast`'s dump choking on a construct it does not handle (multi-line
strings and a few bracket forms — `PARSE FAIL` in the tool's stderr, one line per file, confirmed by
count); the remaining **28** are `l4 ast` itself returning nothing usable — deliberate `not-ok`/
parse-error fixtures, layout fixtures, and files with a third-party import the survey does not
resolve (`llm.l4` and its two importers). Three further files carry a one-level unresolved import
the survey notes but does not fail on: `llm` (`jl4/examples/advanced/legislative-ingestion.l4`,
`jl4/examples/ok/ai-simple.l4`) and `jerseyCharities2` (`jl4/experiments/jerseyCharities2-tests.l4`).

### A.1 Headline

| measure                                                                      |       count |
| ---------------------------------------------------------------------------- | ----------: |
| deontic action patterns (all modals)                                         |         757 |
| — with ≥1 argument                                                           |         229 |
| head is a constructor                                                        |         706 |
| head is `EXACTLY` (whole action)                                             |          35 |
| head is a bare name referencing a GIVEN / top-level (the `34a7c1c5` path)    |      4 / 11 |
| head is a bare-name wildcard binder (matches nothing in scope)               |           1 |
| argument-position bare-name binders                                          |          85 |
| argument-position `EXACTLY` references                                       |         114 |
| — of which `EXACTLY <name in scope>` / `EXACTLY (expr)` / the not-ok fixture | 107 / 6 / 1 |
| binders colliding with an in-scope term                                      |          62 |
| — with a field selector only (deliberate wildcards)                          |          26 |
| — with a local or module name (the hazard)                                   |          36 |
| binders colliding with an **imported** name                                  |           0 |

Every one of these is +2 (patterns, args, binders, collisions, hazard) or unchanged from the memo's
`95dcd92d` numbers, and the entire delta traces to one file,
`jl4/examples/canon/sg/child-support/sg-childcare-leave.l4`, vendored into the tree by PR #398
("canon-vendor", merged as `11b7534b`) after the memo ran. See A.3.

### A.2 The 36, by innermost colliding scope

GIVEN 18 · WHERE local 6 · top-level MEANS/DECIDE 6 · outer action binder 4 · CONSIDER binder 1 ·
EVERY variable 1. Of these, 35 are the hazard (the file makes the reference intent plain), 0 are
deliberate shadowing, 1 is the `EVERY` error's own negative fixture. (Memo: GIVEN 17, outer action
binder 3, 34 total — both buckets gain exactly the one new file's two sites; see A.3.)

### A.3 The hazard sites

`doc/reference/regulative/deontic-example.l4` :61 :80 :279 :290 (`price`, `price`,
`expressPrice`, `price`); `doc/courses/advanced/module-a1-regulatory-examples.l4:196` (`matter`);
`module-a2-cross-cutting-examples.l4` :174 :202 :253 :258 :281 :285 :370 :376 (`violation`,
`notice`, `decision` ×4, `amount`, `the late amount`); `module-a3-contracts-examples.l4` :234 :331
:335 (`amount`, `m`, `m`); `jl4/examples/legal/ceo-performance-award.l4:391` (`Milestone Type`,
WHERE local; **goldened**); `jl4/experiments/promissory-note-amount.l4` :84 :97 :105
(`The Lender`, top-level); `safe-post-new.l4` :343 ×2 :398 ×2 :430 ×2 (`conversion shares`,
`share class`, `investor entitlement`, `the Purchase Amount Currency`, `Cash-Out Amount`);
`patterns_and_idioms.l4` :157 :170 ×2 :182 :191 :593 ×2 (`amount`, `goods`, `buyer`,
`serviceType`, `provider`, `loanAmount`, `lender`); `not-ok/tc/every-rebinds-variable.l4:13`
(`t`, the fixture).

**NEW since the memo** (landed by PR #398's canon vendoring, present only at `11b7534b`):
`jl4/examples/canon/sg/child-support/sg-childcare-leave.l4` :259 :262 (`days` colliding with its
rule's own `GIVEN`; `days` again, this time colliding with an outer action's own binder as well as
the `GIVEN`). Both read, on inspection, as the same hazard as the other 34 — the file's own drafter
plainly meant the `GIVEN` value, not a fresh wildcard.

### A.4 The 26 selector-spelled wildcards

Unchanged in both count and membership at `11b7534b` (checked against the full `selector_sites`
list, not just the count). Every one read is a deliberate wildcard named after the slot, usually
refined by `PROVIDED`: `Pay Alice \`Ms Ng\` amount` (`doc/tutorials/obligations/several-parties.l4:201`),
`Deliver (EXACTLY theLandlord) what`and`Pay (EXACTLY t) (EXACTLY theLandlord) amount`
(`doc/reference/regulative/every-example.l4:23,40,63`), `ok/every/\*.l4`, `maintain eligible
service status Service Status PROVIDED …`, `Convert SAFE issue PROVIDED issue EQUALS …`.

### A.5 `CONSIDER` binders (Phase A1, base `11b7534b`, measured 2026-09-16, tool committed as `1b0b5bfe` at 2026-09-16T09:20:03+08:00)

Tool: `etc/survey-pattern-binders.py`, `--mode consider`, over the same 1066 tracked `.l4` files
(the same 53 files fail to yield a record, for the same two reasons as A.1 — confirmed identical
file lists between the two modes' runs).

| measure                                                      |                  count |
| ------------------------------------------------------------ | ---------------------: |
| `CONSIDER` nodes (literal + desugared multi-clause `DECIDE`) |                    993 |
| branches (`WHEN` + `OTHERWISE`)                              |                   2303 |
| branch bare-name binders                                     |                   1094 |
| binders colliding with an in-scope term                      |                     57 |
| — selector-only                                              |                     35 |
| — local-or-module (the candidates for R1)                    |                     22 |
| — of those, from a desugared multi-clause `DECIDE`           |                      0 |
| by innermost non-selector collision bucket                   | `GIVEN` 18, `import` 4 |

All 22 are deliberate wildcards; see §4 R6 for the reading of each and the decision.

### A.6 Literals and expressions in pattern position

Re-measured 2026-09-16 on **this branch's own binary** (`41809c4d`, copied from the phase-F snapshot
`l4-fix2`/`jl4-test-fix2` to `work-g/l4`; not the `lang/r5-field-opening` worktree the first
measurement used). Probe `lit3.l4`: `MUST pay 100` pending on `pay 1`, `FULFILLED` on `pay 100`;
`CONSIDER 5 WHEN 3` → `"other"`, `CONSIDER 3 WHEN 3` → `"three"` — unchanged from the earlier probe,
as expected (R1/R2 do not touch literal patterns).

The arithmetic case changed, because R2 is what makes it change: probe `r2.l4`'s
`MUST pay (price PLUS 50)` (`GIVEN price IS A NUMBER`) now **type-checks** (`Check succeeded`,
where the pre-R2 binary gave the parser error `unexpected PLUS`) and evaluates correctly —
`PARTY Tenant DOES pay 150` fulfils it when `price = 100`, `PARTY Tenant DOES pay 100` leaves it
pending. The other three R2 acceptance-case probes in the same file check and run as R2 specifies:
`MUST payM (Money 1000 "USD")` (already a constructor pattern) is unaffected;
`MUST Receipt landlord t (amount MINUS 5)` resolves the same way as the `pay` case;
`MUST Deliver (p's landlord) what` checks clean.

---

## Appendix B. Build plan (the ultracode workflow)

One worktree, one `cabal` at a time (CLAUDE.md §2.1). Parallel agents edit disjoint file sets and
never build; only sequential agents build or commit. The `l4` and `jl4-test` binaries are
snapshotted to the session scratchpad after each build and every probe points at the snapshot.

| phase | model               | work                                                                                                                                                                                                                       |
| ----- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A0    | sonnet              | first build; snapshot binaries                                                                                                                                                                                             |
| A     | sonnet ×3, parallel | port + run the survey (deontic re-measure at this base; `CONSIDER` for R6); inventory every `EXACTLY` use with operand class; inventory the 25 pages and the §7 consumers                                                  |
| B     | opus                | R1, R2, R3, R4, R5, R7, §6 printer, checker comments, new fixtures (no goldens yet); build; `jl4-core-test`; decide R6 from A's numbers by the criterion; commit                                                           |
| C     | sonnet ×4, parallel | the sweep by partition (`ok`+`not-ok`; `legal`+`lsp`+`docassemble`+`blawx`+`experiments`+`paper`; `doc/**` `.l4` and pages; `skills/` + spec cross-references); per-file run differential under the snapshot; docs rewrite |
| D     | opus                | commit the sweep; blessing pass (§5.6); `verify-branch.sh` full; `test-docs.sh`; evaluation differential; commit                                                                                                           |
| E     | opus ×3, parallel   | adversarial verify, one lens each: soundness of R1/R2 (construct a program whose meaning changes wrongly); every golden diff explained; every claim in docs and this spec matches the tree                                 |
| F     | opus                | fix confirmed findings; re-run the gate; commit                                                                                                                                                                            |
| G     | sonnet              | update this spec's status and Appendix A; commit                                                                                                                                                                           |

Deputies and workflow agents do not push, open PRs, comment on PRs or file issues; the GM does.
