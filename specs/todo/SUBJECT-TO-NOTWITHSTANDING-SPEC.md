> **Status (audited 2026-07-03):** OPEN — analysis-only; none of the proposed override constructs are implemented.
>
> - `SUBJECT TO`/`NOTWITHSTANDING`/`DESPITE`/`EXCEPT WHEN`/`WITHOUT AFFECTING` are not lexer keywords (`jl4-core/src/L4/Lexer.hs:230-299`) and appear nowhere in core; no priority-graph or defeater machinery.
> - Only `UNLESS` exists as a keyword (`Lexer.hs:298`) but without the defeasibility semantics §6.1 proposes. "Next Steps" remain unstarted.
> - §9 (`APPLIES`, added 2026-08-16) is likewise PROPOSED, not implemented — `APPLIES` is not a lexer keyword, and no per-provision applicability projections are derived anywhere in core.
> - §10 (defeasance by recorded act, added 2026-08-28) is likewise PROPOSED, not implemented — no power/immunity constructs and no ledger-consulting defeasible nodes exist in core.

> **Prior art from the backend portfolio (added 2026-08-16):** two independently-implemented,
> battle-tested target-side defeasibility mechanisms — and one ratified interchange standard —
> now serve as existence proofs for the
> semantics this spec proposes, surfaced by the transpiler bridges:
>
> - **Catala's `label`/`exception` DAG** over default terms — formalised in F\*, with sibling
>   exceptions conflicting unless prioritised; Catala's own compiler flattens the priority
>   structure into total option-typed code, which is the piggyback route for any Catala→L4
>   import. See `CATALA-EXPORT-SPEC.md` §5.2 (draft PR #260).
> - **Blawx's defeat triples** (`overrules`/`blawx_defeated` over s(CASP)) — override structure
>   survives as data naming which section defeats which, i.e. exception relations without burden
>   attribution. See `BLAWX-EXPORT-SPEC.md` §1.1/§5.2 (draft PR #261).
> - **LegalRuleML's `Override`/`OverrideStatement` with the `StrictStrength`/`DefeasibleStrength`/`Defeater`
>   trio** (OASIS Standard, Core v1.0 §4.2.1, 2021-08-30) — the same strict/defeasible/defeater
>   design §5.2 below describes via Prakken & Sartor, ratified as an international standard with
>   an XML surface syntax and worked through lex specialis/superior/posterior. This proposal is
>   not inventing a mechanism; it is adopting the standardized one. See
>   `specs/research/LEGALRULEML-RESEARCH.md` §B(v).
>
> Consolidated here by the portfolio session per the one-file-one-editor convention
> (`specs/proposals/BACKEND-PORTFOLIO-SPEC.md` §8) while three bridge sessions were live.

# SUBJECT TO / DESPITE / NOTWITHSTANDING: Taxonomic Analysis and Specification

**Status:** Draft
**Author:** Research compilation for L4 language design
**Date:** 2025-01-23
**Revised:** 2026-06-17 — added §2.8–2.9 (override as aspect-oriented _advice_; amendment as homoiconic source rewrite + the modular-verification boundary), §5.5–5.6 (AOP; PROLEG / negation-as-failure), §6.5–6.6 (advice as the organizing principle; relationship to `TYPICALLY`).
**Revised:** 2026-08-16 — added §9 (`APPLIES`: the read side of override — the four-conjunct applicability decomposition, post-weaving semantics, closed-world elaboration and its cliff into homoiconicity, the _-plies_ philology) plus §9 references.
**Revised:** 2026-08-19 — §9.4 corpus quotes upgraded from schematic/paraphrase to verbatim: Companies Act 2006 s 724 replaces the invented two-step example, HRA 1998 s 10(1)(a)/(4) now quoted rather than paraphrased; both verified against legislation.gov.uk (in-browser — direct fetches are bot-walled).
**Revised:** 2026-08-28 — added §10 (defeasance by recorded act: the discretionary override — Hohfeldian power/immunity typing, the three strengths of fiat, the ledger as defeater store, the control-effect / intuitionistic reading) plus §10 references. Same-day companions: `doc/concepts/legal-modeling/residual.md` (the residual bridge) and `paper/hohfeld-higher-order/DESIGN.md` (2026-08-28 addendum).
**Branch:** mengwong/spec-notwithstanding

---

## 1. Introduction

This document catalogues the various uses of `SUBJECT TO`, `DESPITE`, and `NOTWITHSTANDING` in legal texts before proposing a formal semantics for L4. Legal drafters use these terms to express priority relations, exceptions, overrides, and conditional applicability. However, careful examination reveals these keywords serve multiple distinct semantic functions that must be disambiguated for computational purposes.

### 1.1 Motivation

L4 aims to formalize legal rules with mathematical precision. The keywords "subject to," "despite," and "notwithstanding" appear frequently in statutes and contracts, but their semantics are surprisingly complex:

- They establish **priority relations** between conflicting provisions
- They act as **input filters** that modify which cases a rule applies to
- They act as **output modifiers** that transform results under certain conditions
- They create **exception carve-outs** from general rules
- They signal **defeasibility** of conclusions

Without formal treatment, these constructs remain as informal comments in L4 code (as seen in the Singapore Data Protection Act example: `Subject to exceptions` IS A BOOLEAN`). This specification aims to promote them to first-class language constructs.

### 1.2 Key Insight: Directionality

The fundamental distinction between these keywords is **directionality** in document structure:

| Keyword           | Appears In                  | Points To        | Effect                      |
| ----------------- | --------------------------- | ---------------- | --------------------------- |
| `SUBJECT TO`      | Main/subordinate clause     | Exception clause | "I yield to that provision" |
| `NOTWITHSTANDING` | Exception/prevailing clause | Main clause      | "I override that provision" |
| `DESPITE`         | Exception/prevailing clause | Main clause      | Same as NOTWITHSTANDING     |

As noted in drafting literature: "notwithstanding looks back whilst subject to looks forward."

---

## 2. Taxonomy of Usage Patterns

Based on extensive analysis of legal texts, we identify **seven distinct semantic functions** these keywords serve. Each has different computational implications.

### 2.1 Priority Declaration (Pure Precedence)

**Pattern:** Establishing which of two potentially conflicting provisions prevails.

**Examples:**

```
-- SUBJECT TO form (in subordinate clause)
"The licensee may operate during normal business hours,
 SUBJECT TO the restrictions in Section 5."

-- NOTWITHSTANDING form (in prevailing clause)
"NOTWITHSTANDING Section 3, the Director may grant
 extensions in exceptional circumstances."
```

**Semantics:** When provisions A and B both apply to the same facts and yield conflicting conclusions, the priority declaration determines which conclusion holds.

**Computational model:**

```
priority(A, B) = B  -- "A SUBJECT TO B" means B wins conflicts
priority(A, B) = A  -- "A NOTWITHSTANDING B" means A wins conflicts
```

**Legal sources:**

- U.S. Supreme Court in _Cisneros v. Alpine Ridge Group_ (1993): "a 'notwithstanding' clause signals the drafter's intention that the provisions of the 'notwithstanding' section override conflicting provisions."
- Indian courts: Non obstante clauses "perform the function of removing impediments created by other provisions."

### 2.2 Exception/Carve-Out (Scope Limitation)

**Pattern:** Excluding certain cases from the scope of a general rule.

**Examples:**

```
"All employees are entitled to 20 days annual leave,
 SUBJECT TO the exclusions for part-time workers in Schedule 2."

"Vehicles must not exceed 30 mph,
 NOTWITHSTANDING which, emergency vehicles responding to calls
 may exceed this limit."
```

**Semantics:** The exception clause defines a subset of inputs for which the main rule does not apply (or applies differently).

**Computational model:**

```haskell
-- Main rule with exception
rule(x) =
  if exception_applies(x)
  then exception_result(x)  -- or: rule_does_not_apply
  else main_result(x)
```

**Key distinction from Priority:** Priority resolves conflicts between two independently applicable rules. Exception carve-outs prevent the main rule from applying at all to certain cases.

### 2.3 Condition Precedent (Triggering Condition)

**Pattern:** Making rule applicability contingent on another condition being satisfied.

**Examples:**

```
"Payment shall be made within 30 days,
 SUBJECT TO the goods having passed inspection."

"The agreement becomes effective on the Closing Date,
 SUBJECT TO all regulatory approvals having been obtained."
```

**Semantics:** The main obligation only arises if the condition is met. This is not an exception but a prerequisite.

**Computational model:**

```haskell
-- Condition precedent
obligation_exists(x) =
  condition_satisfied(x) && base_obligation_would_apply(x)
```

**Legal doctrine:** Courts distinguish conditions precedent (must happen before duty arises) from conditions subsequent (terminate existing duty). "Subject to" can signal either.

### 2.4 Proviso/Qualification (Output Modification)

**Pattern:** Modifying the conclusion or output of a rule rather than its applicability.

**Examples:**

```
"The tenant may make improvements to the property,
 SUBJECT TO obtaining landlord's written consent."

-- The right exists, but is qualified/constrained

"Benefits shall be paid monthly,
 NOTWITHSTANDING WHICH, the first payment may be pro-rated."
```

**Semantics:** The rule applies and produces a base result, which is then modified by the qualifying clause.

**Computational model:**

```haskell
-- Output modification
final_result(x) = modify(base_result(x), qualification(x))

-- Example: permission with constraint
may_improve(tenant) = Permission {
  action = Improve,
  constraint = RequiresConsent(landlord)
}
```

**Key distinction:** The rule applies; its output is transformed. Compare to Exception (rule doesn't apply) and Priority (rule's output is replaced).

### 2.5 Savings/Preservation Clause (Non-Interference)

**Pattern:** Declaring that a new provision does not affect existing rights or other provisions.

**Examples:**

```
"This Section 12 is SUBJECT TO and shall not limit or restrict
 the rights granted under Section 8."

"NOTWITHSTANDING the foregoing, nothing in this Agreement shall
 be construed to waive Party A's rights under the Master Agreement."
```

**Semantics:** An explicit declaration of non-conflict, preserving co-existence of provisions.

**Computational model:**

```haskell
-- Preservation: both provisions remain in force
-- No priority determination needed; they don't conflict
applies(section_12, x) = ... -- unchanged
applies(section_8, x) = ...  -- also unchanged
```

**Drafting note:** This is often defensive drafting to prevent unintended implied repeal.

### 2.6 Scope/Domain Restriction (Input Filter)

**Pattern:** Narrowing the domain of inputs to which a rule applies.

**Examples:**

```
"For the purposes of this Part,
 'employee' means any person employed under a contract of service,
 SUBJECT TO the exclusions in paragraph (b)."

"This regulation applies to all data controllers,
 NOTWITHSTANDING WHICH, controllers processing fewer than
 5000 records annually are exempt from Section 4."
```

**Semantics:** The rule's input domain is filtered before evaluation.

**Computational model:**

```haskell
-- Domain restriction
rule_applies_to(x) = in_base_domain(x) && not(excluded(x))

-- Or equivalently as a filter:
applicable_inputs = filter (not . excluded) base_domain
```

**Key distinction from Exception:** Input filtering happens before rule evaluation; exceptions can reference the rule's intermediate computations.

### 2.7 Defeasibility Marker (Rebuttable Conclusion)

**Pattern:** Signaling that a conclusion is provisional and may be defeated by new information.

**Examples:**

```
"A child born in the UK to British parents is British,
 SUBJECT TO any determination to the contrary under Section 40."

"The contract shall be deemed valid,
 NOTWITHSTANDING WHICH, either party may challenge validity
 on grounds of fraud or duress."
```

**Semantics:** The conclusion holds by default but can be overridden by defeating conditions discovered later.

**Computational model:**

```haskell
-- Defeasible rule
conclusion(x) =
  if defeating_condition(x)
  then defeated_result(x)
  else default_result(x)

-- With explicit uncertainty
conclusion(x) = Defeasible {
  default = default_result(x),
  defeaters = [defeating_condition_1, defeating_condition_2, ...],
  confidence = provisional
}
```

**Connection to default logic:** This aligns with Reiter's default logic and the notion of non-monotonic reasoning. See L4's existing `doc/default-logic.md`.

### 2.8 Unifying view: every override is _advice_ (B wraps A)

The seven functions in §2.1–2.7 read like seven mechanisms; they are better understood as **seven positions of one mechanism**. In "A `SUBJECT TO` B," B _wraps_ A. Borrowing the vocabulary of aspect-oriented programming (Kiczales et al.), B is **advice** applied at A's **join point**, and the _kind_ of advice determines which face of the taxonomy you see:

| Mode (what B changes)          | Advice kind | `proceed()` behaviour                | Subsumes                                             | Legal reading                                |
| ------------------------------ | ----------- | ------------------------------------ | ---------------------------------------------------- | -------------------------------------------- |
| A's **inputs / applicability** | `before`    | call A with transformed/guarded args | condition precedent (2.3), domain restriction (2.6)  | "subject to approval"; "for the purposes of" |
| A's **output**                 | `after`     | call A, then transform the result    | proviso / qualification (2.4)                        | "subject to obtaining consent"               |
| **whether A runs at all**      | `around`    | may _decline_ to call A              | priority (2.1), exception (2.2), defeasibility (2.7) | "notwithstanding"; "except when"             |
| **nothing** (explicit no-wrap) | identity    | always proceed, change nothing       | savings / preservation (2.5)                         | "without affecting"; "shall not limit"       |

The load-bearing primitive is `around`-advice's **`proceed()`**: B receives A as a _suspended computation_ and decides (a) whether to run it, (b) with what inputs, and (c) what to do with its result. (The OOP gloss is identical — B overrides A's method and may or may not call `super()`.) Everything in §2.1–2.7 is then a special case:

- **"Notwithstanding"** = around-advice that _declines_ `proceed()` — B's result replaces A's entirely.
- **"Subject to … provided that …"** = `before` (guard the input) composed with a **proviso** = `after` (transform the output).
- **Savings clause** = the _identity_ advice — an explicit declaration that B does **not** wrap A, defeating implied override (§4.4).
- **Defeasibility** (2.7) = around-advice whose decision to proceed depends on whether a defeater fired — i.e. NAF / default logic under the hood (§5.3, §5.6).

So the apparent seven collapse to **two boundary transforms (in, out) + one control decision (proceed?)** — the full override lattice. This also closes the loop with the regulative layer: the deontic clause `PARTY p MUST X SUBJECT TO (p SHANT Y) LEST Z` is exactly around-advice that, on the prohibited event Y, refuses `proceed()` and runs the handler Z. The cancellation-scope reading (structured concurrency) and the advice reading are the same construct.

### 2.9 The third mode: modifying A's _internals_ (amendment as homoiconic rewrite)

`before`/`after`/`around` all treat A as a **black box** — they touch only its inputs, its output, and whether it runs. A fourth, strictly more invasive mode modifies A's **internal logic**: _"in section A, the word 'X' shall be construed as 'Y'."_ Computationally this is a **macro / homoiconic source rewrite** — B receives A's _code_ (its AST), not its behaviour, and edits it. This is the exact shape of a **legislative amendment** (a textual/structural change), as distinct from an _override_ (a behavioural interception).

The distinction is a hard design boundary, because it decides whether modular verification survives:

|                | Behavioural override (boundary advice) | Textual amendment (internal rewrite) |
| -------------- | -------------------------------------- | ------------------------------------ |
| What changes   | A's _behaviour_ at runtime             | A's _text_                           |
| A in isolation | still readable / verifiable            | no longer meaningful on its own      |
| Composition    | A and B analysed separately            | must re-analyse the rewritten A′     |
| CS analogue    | decorator / middleware / AOP advice    | macro / quasiquotation / transform   |

**Design rule (the verification boundary).** Boundary advice (`before`/`after`/`around`) is first-class and statically analysable. Internal rewriting is **not** a runtime homoiconic mechanism; it is an explicit **source-to-source transform that _materialises_ a fresh, re-typecheckable `.l4` provision A′.** This mirrors how a _consolidated statute_ publishes the amended text rather than the amendment diff: you keep the full homoiconic power for amendments, but you materialise the result so the amended provision can still be read and verified standalone. (It is the same discipline the PROLEG→L4 transpiler adopts: emit concrete `.l4`, validate by re-running the typechecker — never trust an un-materialised transform.)

---

## 3. Related Legal Principles

### 3.1 Lex Specialis Derogat Generali

The principle that specific law overrides general law. When both apply to the same facts:

```
General rule: All vehicles must stop at red lights.
Specific rule: Emergency vehicles may proceed through red lights when responding.
```

This is an implicit priority relation. `NOTWITHSTANDING` makes it explicit.

### 3.2 Lex Posterior Derogat Priori

Later law overrides earlier law. Relevant when:

- Amendment acts modify existing statutes
- Contract amendments override original terms

### 3.3 Non Obstante (Latin Root)

The Latin term "non obstante" (notwithstanding) has a rich history in statutory interpretation, particularly in Indian and Commonwealth jurisdictions:

- Creates "overriding effect" over conflicting provisions
- Does NOT repeal conflicting provisions; merely displaces them for specific cases
- Must be interpreted in context of statutory purpose
- Cannot "whittle down" the principal provision it modifies

### 3.4 Provisos vs. Exceptions

Legal drafting distinguishes:

| Construct         | Function                     | Position                      |
| ----------------- | ---------------------------- | ----------------------------- |
| **Proviso**       | Qualifies the main provision | Introduced by "provided that" |
| **Exception**     | Carves out cases from scope  | Can appear anywhere           |
| **Saving clause** | Preserves existing rights    | Usually at end                |

A proviso "must be read and understood in conjunction with the main provision" while an exception "operates independently."

---

## 4. Problematic Patterns and Ambiguities

### 4.1 Scope Ambiguity

```
"NOTWITHSTANDING anything to the contrary in this Agreement..."
```

What does "anything" include? All provisions? Only provisions in the same Part? The drafter may not have fully enumerated the provisions being overridden.

**Recommendation:** Require explicit references: `NOTWITHSTANDING Section 5.2`

### 4.2 Circular Priority

```
Section A: "NOTWITHSTANDING Section B, ..."
Section B: "NOTWITHSTANDING Section A, ..."
```

Two mutually-overriding provisions create a paradox.

**Computational solution:** Detect cycles in priority graph; flag as error.

### 4.3 Layered Exceptions

```
Rule: All employees get 20 days leave
  Exception 1: Part-time workers get 10 days
    Exception to Exception 1: Part-time workers with 10+ years get 20 days
      Exception to Exception to Exception 1: Unless they declined in writing
```

Deep nesting creates comprehension problems.

**Computational solution:** Flatten to decision tree; verify completeness.

### 4.4 Implicit vs. Explicit Override

Sometimes override is implied by document structure (later provision implicitly overrides earlier). Other times it's explicit. Mixing modes in the same document creates confusion.

### 4.5 The "Despite" Alternative

"Despite" is semantically equivalent to "notwithstanding" but:

- Less formal/legalistic
- Fewer ambiguity issues (not confused with "subject to")
- Preferred by plain language advocates

---

## 5. Comparison with Other Formalisms

### 5.1 Catala

The Catala language (catala-lang.org) handles exceptions with explicit scope labels:

```catala
scope IncomeTax:
  definition tax equals income * 0.20

  exception definition tax under condition
    income < 10000
  equals 0
```

Exceptions are tied to specific definitions, with explicit conditions.

### 5.2 Defeasible Logic

Formal defeasible logic systems (Prakken, Sartor) use:

- Strict rules: `A -> B` (cannot be defeated)
- Defeasible rules: `A => B` (can be defeated)
- Defeaters: `A ~> ~B` (attacks but doesn't establish)
- Priority ordering on rules

### 5.3 Answer Set Programming

ASP handles exceptions through negation as failure:

```prolog
flies(X) :- bird(X), not abnormal(X).
abnormal(X) :- penguin(X).
```

### 5.4 Contract-Specific Languages (CSL, etc.)

Contract specification languages like CSL use temporal operators and explicit breach/fulfillment states rather than override semantics.

### 5.5 Aspect-Oriented Programming (the wrapping model)

AOP (Kiczales et al., 1997; AspectJ) is the most direct computational model for §2.8. _Advice_ (`before` / `after` / `around`) runs at _join points_ selected by a _pointcut_; `around` advice's `proceed()` decides whether and how to invoke the wrapped code. The mapping is exact: the override clause is the advice, the **explicit cross-reference** ("`NOTWITHSTANDING` Section 5.2") is the pointcut selecting A, and "notwithstanding" is `around` advice that declines to `proceed()`. AOP also supplies the cautionary note — unrestricted pointcuts make programs hard to reason about, the analogue of §4.1's "anything to the contrary," which is why §6.5 insists on explicit join-point references.

### 5.6 PROLEG and the negation-as-failure gloss

PROLEG (Satoh et al., JURISIN 2010) is a pointed precedent for how to _surface_ defeasibility. It deliberately **refuses to expose first-class negation-as-failure**; instead a rule carries named exceptions — `H <= B`, `exception(H, E)`, with exceptions-to-exceptions for counter-rebuttals — and the "no applicable exception" step (the NAF) is hidden inside the meta-interpreter. The documented motive is familiarity: "general rule + exceptions" is how _lawyers_ reason; it is equally how _imperative programmers_ read "default behaviour + exception handling," and how _logicians_ read default logic — one construct, three familiar audiences.

The deeper lesson for `SUBJECT TO`: legal negation/override is **never neutral**. `exception(H, E)` is strictly more expressive than `H :- …, not E`, because it also records _who bears the burden_ of establishing the exception (plaintiff proves the rule's facts; defendant the exception; plaintiff the counter-exception) — information that bare NAF erases. So an L4 override construct should be able to **carry the burden allocation**, not just the truth condition. (L4's PROLEG bridge maps `exception(H, E)` → `… AND NOT E` for decision-only fidelity — sound only when the signed dependency graph is **stratified** — and preserves the burden layer separately; see the PROLEG↔L4 transpiler notes and `TYPICALLY-DEFAULTS-SPEC.md` for the presumption side.)

---

## 6. Observations for L4 Language Design

### 6.1 Multiple Constructs Needed

The seven semantic functions identified suggest L4 needs multiple distinct constructs, not a single overloaded keyword:

| Function               | Suggested L4 Construct                                |
| ---------------------- | ----------------------------------------------------- |
| Priority declaration   | `SUBJECT TO` / `NOTWITHSTANDING` as explicit priority |
| Exception carve-out    | `EXCEPT WHEN` clause                                  |
| Condition precedent    | `REQUIRES` or `GIVEN THAT`                            |
| Output modification    | `QUALIFIED BY` or modifier syntax                     |
| Preservation           | `WITHOUT AFFECTING`                                   |
| Domain restriction     | Input type constraints                                |
| Defeasibility          | `UNLESS` with defeater semantics                      |
| Applicability citation | `APPLIES` — reads the woven result (§9)               |

### 6.2 Reader-Friendliness

Following drafting best practices:

- Prefer `SUBJECT TO` in the subordinate clause (alerts reader to exception)
- Use explicit section references, not "anything to the contrary"
- Consider whether exception or condition precedent is the right model

### 6.3 Composition with Existing L4 Features

L4 already has:

- `CONSIDER` / `WHEN` for conditional logic
- `MEANS` / `DECIDE` for definitions
- Optional/Maybe types for missing information
- `OTHERWISE` for defaults

New constructs should compose naturally with these.

### 6.4 Type-Level Considerations

Override semantics may need type-level representation:

- A "defeasible Boolean" that can be defeated
- A "provisional result" that may be superseded
- Priority annotations on rules

### 6.5 The advice model as the organizing principle

§2.8 suggests L4 should expose override not as seven keywords but as **advice with an explicit kind and an explicit join point**:

```
-- PROPOSED: override as explicit, analysable advice
A SUBJECT TO B            -- around: B may decline to proceed (full override / "notwithstanding")
A PROVIDED THAT g         -- before: guard the input (PROVIDED already exists)
A QUALIFIED BY q          -- after:  transform the output (proviso)
A WITHOUT AFFECTING C     -- identity: explicit non-wrap (savings clause)
```

Each names the **target provision explicitly** (the pointcut), so the override graph is inspectable — directly enabling the acyclicity/completeness checks of §4.2 and Open Question §7.5. Internal amendments are a separate, _materialising_ form (§2.9):

```
-- PROPOSED: textual amendment → emits a fresh, re-typechecked provision A′
AMEND A REPLACING `X` WITH `Y`
```

### 6.6 Relationship to TYPICALLY (defaults are the simplest advice)

A rebuttable presumption (`TYPICALLY`, see `TYPICALLY-DEFAULTS-SPEC.md`) is just the _weakest_ `before`-advice: it supplies a **missing input** before A runs. This unifies the two specs along a single axis of increasing strength:

| Construct                        | Advice kind    | What it touches                        |
| -------------------------------- | -------------- | -------------------------------------- |
| `TYPICALLY v`                    | `before`       | fills an _absent_ input with a default |
| `PROVIDED g`                     | `before`       | _guards_ an input / applicability      |
| `QUALIFIED BY q`                 | `after`        | transforms the _output_                |
| `SUBJECT TO` / `NOTWITHSTANDING` | `around`       | controls _whether A runs_              |
| `AMEND`                          | source rewrite | edits A's _internals_ (materialised)   |

Defaults, provisos, and overrides are therefore not separate features but points on one advice lattice — a single mental model for the whole "subject to" family, with the burden-of-proof attribution (§5.6) as an orthogonal annotation each can carry.

---

## 7. Open Questions

1. **Granularity:** Should override apply to entire rules or individual conclusions?

2. **Temporal dynamics:** Can priority change over time? (e.g., grace periods)

3. **Procedural vs. substantive:** Do these keywords affect how rules are evaluated (procedure) or what they mean (substance)?

4. **Explanation generation:** How should evaluation traces explain override decisions?

5. **Verification:** Can we statically verify that override relations are acyclic and complete?

6. **Interoperability:** How do these map to other legal formalization languages?

7. **Applicability reads:** the `APPLIES` read side raises its own set — see §9.9.

---

## 8. Next Steps

1. **Gather corpus examples:** Collect real statutory and contract examples using each pattern
2. **Propose concrete syntax:** Design L4 keyword syntax for each semantic function
3. **Define formal semantics:** Specify evaluation rules precisely
4. **Implement prototype:** Add to L4 parser and evaluator
5. **Test with real documents:** Validate against British Nationality Act, PDPA, etc.
6. **Prototype the read side (§9):** derive per-provision `inScope` / `excluded` / `triggered` / `applies` / `satisfied` projections during elaboration, and pilot them on the Contracts (Rights of Third Parties) Act 2001 (§9.4), whose nine sections exercise every role in the design.

---

## 9. APPLIES: Citing Applicability (the Read Side of Override)

> **Status (2026-08-16):** PROPOSED, not implemented. `APPLIES` is not a lexer keyword (zero
> occurrences in `jl4-core/src/L4/Lexer.hs`), and no per-provision applicability projections are
> derived anywhere in core. Recorded here because this spec's own semantic models already lean on
> an informal `applies(section, x)` meta-predicate (§2.5, §2.6) without ever defining it — and
> because the write side (§2.8, §6.5) and this read side are one machinery that should be designed
> together.

### 9.1 The phenomenon

Legal texts routinely condition one provision on the **applicability of another provision**, cited
by its label:

> "Subsections (2) to (5) apply where proceedings for the enforcement of a term of a contract are
> brought by a third party in reliance on section 2."
> — Contracts (Rights of Third Parties) Act 2001 (Singapore), s 4(1)

This is a mild homoiconicity: `section 2` is a term in the instrument's own domain of discourse,
and _applies_ is a predicate **about a rule**, evaluated against the case at hand. Since L4
renders a constitutive rule as `antecedent IMPLIES consequent`, the tempting one-line expansion is

> "section A.1 applies" ≡ "the antecedent of A.1's `IMPLIES` holds"

That is one of the readings drafters intend — and not the most common one. Getting `APPLIES` right
requires a fuller expansion.

### 9.2 The four-conjunct decomposition

"Provision S applies to case c at time t" decomposes into up to four independently owned tests:

| #   | Conjunct           | Question answered                                                | Owning machinery                                                                       |
| --- | ------------------ | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| 1   | `inForce S t`      | Is S part of the instrument version in force at t?               | temporal axis: `EVAL … UNDER RULES EFFECTIVE AT` (`TEMPORAL_EVAL_SPEC.md`)             |
| 2   | `inScope S c`      | Does c fall within S's own application provisions?               | von Wright's _condition of application_; explicit "Application" sections               |
| 3   | `NOT excluded S c` | Does no carve-out, override, or disapplication displace S for c? | this spec: §2.1 priority, §2.2 exceptions, §2.6 domain restriction — i.e. woven advice |
| 4   | `triggered S c`    | Does S's operative antecedent hold of c?                         | the `IMPLIES` antecedent                                                               |

Different citation forms mean different prefixes of the conjunction:

| Citation form                                     | Usual meaning                                                      |
| ------------------------------------------------- | ------------------------------------------------------------------ |
| "This section applies where X" (self-declaration) | S _defining_ its own conjunct 2 (often folding conjunct 4 into it) |
| "Where section 5 applies, the person must …"      | conjuncts 1–3 — the operative antecedent is still to come          |
| "if the exemption in section 5 applies"           | all four conjuncts                                                 |
| "section 5 does not apply where Y"                | not a read at all — a **write** to conjunct 3 (§2.2)               |

Conjunct 1 is why _applies_ is inherently time-indexed: a provision has separate temporal
dimensions of existence, force, and applicability (Hernández Marín & Sartor 1999), a separation
the Akoma Ntoso legislative-XML metadata model likewise hard-codes as distinct force / efficacy /
application intervals. L4 already owns this axis through the four `EVAL` pins; `APPLIES` composes
with it rather than re-inventing it.

### 9.3 Post-weaving semantics: APPLIES reads the woven rule

§2.8 models every override as advice woven around a target provision. `APPLIES` must be evaluated
**after weaving**: when CRTPA s 4(1) says "in reliance on section 2", it means section 2 _as
limited by_ s 7's exceptions and s 3's variation regime — never the naked text of s 2.

This yields the duality this section exists to record:

- `SUBJECT TO` / `NOTWITHSTANDING` / `EXCEPT WHEN` / `WITHOUT AFFECTING` (§6.5) are **writes**:
  advice that edits conjuncts 2–3 (or wraps the output).
- `APPLIES` is the **read**: would the woven provision fire on this case?

One machinery, two ends. In advice vocabulary, conjunct 2 is the provision's own `before` guard,
conjunct 3 is the accumulated foreign `around` advice declining to `proceed()`, conjunct 4 is the
body's antecedent, and conjunct 1 selects _which version_ of provision-plus-advice gets woven at
all. It follows that the applicability-citation graph and the override graph of §4.2 are the
_same graph_, sharing one acyclicity/stratification check (§9.6).

### 9.4 Drafters already write the decomposition

The strongest argument that `APPLIES` deserves surface syntax: modern drafting already factors
provisions this way. The standard two-step idiom writes the applicability predicate and the
operative rule as separate subsections — verbatim, Companies Act 2006 (UK) s 724 (Treasury
shares):

> "(1) This section applies where– (a) a limited company makes a purchase of its own shares in
> accordance with Chapter 4, and (b) the purchase is made out of distributable profits. \[…]
> (3) Where this section applies the company may— (a) hold the shares (or any of them), or
> (b) deal with any of them, at any time, in accordance with section 727 or 729."

— in line with drafting guidance (OPC) that the main proposition should not be buried among its
conditions. The same section then reads its own predicate **retrospectively**: treasury shares
are, per s 724(5)(a), shares that "were (or are treated as having been) purchased by it in
circumstances in which this section applies" — an evaluation of `applies` at the past time of
purchase, which is conjunct 1 of §9.2 doing real work (and grist for §9.9.4). Human Rights Act
1998 (UK) s 10 self-declares in the same style — "This section applies if— (a) a provision of
legislation has been declared under section 4 to be incompatible with a Convention right …" —
an applicability condition that cites the _exercise of another section's power_ — and s 10(4)
extends it: "This section also applies where the provision in question is in subordinate
legislation and has been quashed, or declared invalid, by reason of incompatibility with a
Convention right …".

The Singapore Contracts (Rights of Third Parties) Act 2001 exhibits the whole design in nine
sections:

| Provision | Text (abridged)                                                                           | Role in this design                                                |
| --------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| s 2(1)    | "Subject to the provisions of this Act, a person who is not a party … may … enforce …"    | the operative rule, opening with a global acknowledgment of writes |
| s 4(1)    | "Subsections (2) to (5) apply where proceedings … are brought … in reliance on section 2" | the read: an applicability gate                                    |
| s 5       | "Section 2 does not affect any right of the promisee …"                                   | savings = identity advice (§2.5, §2.8)                             |
| s 7       | "Section 2 does not confer any right … in the case of a contract on a bill of exchange …" | a pure write-side section: serial edits to s 2's exclusion set     |

Two structural observations. First, the citable unit is any labelled node — s 4(1) gates
_subsections_ — so the projections of §9.5 must attach to every structural node, not only `§`
provisions. Second, isomorphic formalization (Bench-Capon & Coenen) wants each of these provisions
represented as its own unit; the derived-projection design gives that for free, since s 7's
clauses remain separate writes rather than being inlined into s 2's text.

### 9.5 Proposed elaboration: derived projections under a closed world

For every labelled provision `S`, the elaborator derives a record of projections:

```l4
-- Conceptually: every labelled provision
§ `S`
GIVEN c IS A Case
DECIDE ...            -- operative rule: triggered c IMPLIES effect c

-- elaborates to derived projections:
--   `S inScope`   : Case -> BOOLEAN   -- its own Application provisions        (conjunct 2)
--   `S excluded`  : Case -> BOOLEAN   -- accumulated from foreign advice:
--                                     --   SUBJECT TO / NOTWITHSTANDING /
--                                     --   EXCEPT WHEN write here              (conjunct 3)
--   `S triggered` : Case -> BOOLEAN   -- the operative antecedent              (conjunct 4)
--   `S applies`   : Case -> BOOLEAN   -- inScope AND NOT excluded AND triggered,
--                                     --   under the version selected by       (conjunct 1)
--   `S satisfied` : Case -> BOOLEAN   -- the compliance projection (§9.8)
```

with a surface citation form along the lines of:

```l4
GIVEN c IS A Case
DECIDE `enhanced duty applies to` c IF
      `Section 2` APPLIES TO c        -- read side: the woven, in-force Section 2
  AND `additional condition` c
```

Design notes:

- **Explicit argument passing.** S's projections are functions of S's `GIVEN`s; the citing site
  supplies them. Implicit capture by name coincidence would be fragile and unhygienic.
- **Projection selection.** Which prefix of the four conjuncts a bare `APPLIES` denotes is open
  (§9.9.1); explicit qualifiers are the conservative default until the corpus survey answers.
- **`satisfied` = complies.** For a constitutive rule, truth of the whole conditional; for a
  regulative rule, absence of violation — the Andersonian reduction (Anderson 1958; Meyer 1988),
  connecting to the deontic status machinery of `HOMOICONICITY-SPEC.md` R1.

**Closed-world elaboration.** Within one instrument the provision universe is closed at compile
time, so every `APPLIES` citation elaborates to ordinary first-order calls — no reification, no
runtime rule registry. Even "anything in this Part" (§4.1) becomes a finite conjunction over known
provisions: §4.1's recommendation of explicit references turns from a prohibition into a
compile-time expansion. Three citation forms fall off this cliff into genuine homoiconicity
(`HOMOICONICITY-SPEC.md` R10):

1. **Open quantification across instruments** — "subject to any other written law" ranges over
   provisions the compiler cannot enumerate.
2. **Application with modification** — "section 5 applies as if the reference to X were a
   reference to Y", and the whole _mutatis mutandis_ genre. This is not a predicate read but a
   rewrite of the reified rule followed by a read of the rewrite. Under the verification boundary
   of §2.9 it is handled as an `AMEND`-style **materialisation**: produce S′, re-typecheck it,
   then read `S′ applies`. Within one instrument this stays static; modifying _another_
   instrument's text requires that instrument's reified AST.
3. **Provisions created or modified at runtime** (`HOMOICONICITY-SPEC.md` R2–R7), whose
   applicability is a query over the runtime registry, not a static call.

### 9.6 Static checks: the applicability graph must be stratified

Quotation of applicability invites paradox:

```
Section A: "This section applies where section B does not apply."
Section B: "This section applies where section A does not apply."
```

This is the non-stratified negation-as-failure shape: no unique model. Because §9.3 makes the
read edges part of the same graph as §4.2's override edges, one compiler pass covers both: build
the provision-citation graph (positive and negative `applies` edges plus advice edges), require
stratification of the negative edges (the same condition §5.6 already imposes on the PROLEG
bridge), and reject or warn on violation. Precedent: Sergot et al.'s British Nationality Act
formalisation ran statutory cross-references through negation as failure and depended on exactly
this discipline; the BNA's own "This section applies to a person who …" style is the two-step
idiom of §9.4.

### 9.7 Prior art

The decomposition is old; the contribution here is wiring it into one language surface.

- **Condition of application as a separate norm component** — von Wright (1963) distinguishes a
  norm's _condition of application_ from its content: conjunct 2 predates us by sixty years.
- **Applicable vs applying** — Hage's Reason-Based Logic (Hage 1996, 1997; Verheij 1996) makes
  precisely the distinction between a rule being _applicable_ (conditions satisfied) and the rule
  _applying_ (consequence attaching), with applicability only a **defeasible reason** for
  application. The gap between the two is where conjunct 3 — and §2.7's defeasibility — lives.
- **Applicability as an object of argument** — Prakken & Sartor (1996) let parties argue about
  whether a rule applies and which rule prevails, making applicability and priority first-class
  moves rather than fixed metadata.
- **Temporal dimensions of validity** — Hernández Marín & Sartor (1999) separate a norm's
  existence, force, and applicability in the event calculus; Akoma Ntoso encodes force / efficacy
  / application as distinct intervals. Conjunct 1.
- **Provisions that modify provisions** — Governatori, Palmirani, Riveret, Rotolo & Sartor (2005)
  and Governatori & Rotolo (2010) give formal semantics for norm modification, abrogation, and
  annulment: the write side taken to its limit, and the formal backdrop for §2.9 and §9.5(2).
- **Mechanised statutory cross-reference** — Sergot et al. (1986) on the BNA is the founding
  precedent for evaluating "applies"-style cross-references computationally.
- **Isomorphism** — Bench-Capon & Coenen (1992): represent each source provision as its own
  knowledge-base unit. Application provisions and exception sections earn their own projections
  (§9.4) precisely on this principle.

### 9.8 Philological note: the _-plies_ family

_Applies_, _implies_, _complies_: the shared tail suggests one Latin root, and for two of the
three it is real. _Apply_ < _applicare_ (_ad_ + _plicare_), **to fold onto** — the rule folded
onto the facts. _Imply_ < _implicare_ (_in_ + _plicare_), **to fold in** — the consequent folded
into the antecedent. But _comply_ is a false member of the club: it descends from _complēre_,
**to fill up** (the root of _complete_), reaching English via Italian _complire_ / Spanish
_cumplir_, and drifted into the _-ply_ spelling by attraction to _ply / pliant_. The near-miss is
semantically perfect: you do not fold an obligation — you **fill** it. Performance fills the hole
in the world that an obligation opens, which is the Andersonian reduction again: to comply is to
stay violation-free.

So the trio maps exactly onto the projections of §9.5:

| Word     | Root                   | Projection                               |
| -------- | ---------------------- | ---------------------------------------- |
| applies  | _applicare_, fold onto | `S applies` — the rule reaches this case |
| implies  | _implicare_, fold in   | the connective inside the rule           |
| complies | _complēre_, fill up    | `S satisfied` — the obligation is filled |

And the evaluator's trace output is the family's fourth member: _explicate_ (_ex_ + _plicare_),
to **unfold**.

### 9.9 Open questions specific to the read side

1. **Default projection:** which prefix of the four conjuncts does a bare `APPLIES` denote?
   Needs the corpus survey of §8.1; explicit qualifiers are the conservative interim answer.
2. **Defeasible reads:** Reason-Based Logic says applicability is only a _reason_ for
   application. Should `S APPLIES` return the defeasible Boolean of §6.4 rather than a plain one,
   so a later defeater can rebut the read itself?
3. **Stable labels:** reads must survive renumbering of the cited provision — ties into
   exactprint and the `AMEND` materialisation story (§2.9).
4. **Reading events, not predicates:** HRA s 10 triggers on a declaration _made under_ section 4
   — a read of another provision's **output event** in the regulative trace, not of a static
   predicate. How does `APPLIES` interact with the ledger (`RECORD`/`ATTEST`) and the LTS?
   CA 2006 s 724(5)(a) is the temporal form of the same question: shares "purchased by it in
   circumstances in which this section applies" evaluates `applies` **as of the past purchase**,
   i.e. a conjunct-1-pinned read against the trace.
5. **Cross-instrument reads:** "applies for the purposes of this Act" versus reading another
   instrument entirely — is that an `IMPORT` of the other instrument's projections, pinned to a
   version via conjunct 1?

---

## 10. Defeasance by Recorded Act: the Discretionary Override

> Added 2026-08-28, distilled from a design conversation (session `paper-residuals`) building on
> the residual-obligation / residual-control-rights bridge in
> `doc/concepts/legal-modeling/residual.md`. PROPOSED, not implemented — nothing in this section
> exists in core. The paper-facet record of the same material is the 2026-08-28 addendum in
> `paper/hohfeld-higher-order/DESIGN.md`.

### 10.1 The phenomenon: a third defeater source

§2's taxonomy defeats provision A with provision B — rule against rule. §2.9 defeats A by
rewriting its text. There is a third defeater source, pervasive in both private and public law,
in which A yields not to a sibling rule but to **an empowered actor's act**:

- "We reserve the right to modify these terms…" — the unilateral variation clause
- "…unless the Minister otherwise determines"; "the Registrar may waive this requirement"
- "except with the prior written consent of the Lender"
- HRA 1998 s 10 (already quoted verbatim in §9.4): a Minister may by remedial order amend
  primary legislation — a statutory power to defeat statute, triggered by a court's s 4
  declaration
- rulebook-wide exemption powers of the LPA s 34(2) type (see
  `paper/political-economy/SIDEBAR-unauthorised-practice.md`): a dispensation power held but,
  on the record, never exercised

Grammatically these often wear the same `SUBJECT TO` clothing as §2 — §2.7's own first example
("subject to any determination to the contrary under Section 40") is one. Semantically they
differ in kind: **the defeater is not resident in the rulebook.** It is a speech act that may or
may not have happened, performed by an actor the rule names, on grounds the rule constrains.
Call this **defeasance by recorded act**.

### 10.2 The Hohfeldian type: powers and immunities over the advice lattice

`paper/hohfeld-higher-order/DESIGN.md` reads Hohfeld's second-order square as operators over
first-order deontic positions: a power is a `MAY` whose argument is another deontic position.
The discretionary override is that arrow applied to _this spec's_ defeat lattice: the empowered
actor holds a `MAY` over whether A `proceed()`s (§2.8). The adviser is an actor's act rather
than a provision; the advice-kind taxonomy of §2.8 carries over unchanged, and what is new is an
**authorisation index** (who may install the advice) and an **evidence requirement** (the act
must be on the record — §10.4).

The dual constructor is entrenchment, Hohfeld's immunity/disability axis: a savings clause
(§2.5) indexed by _actor_ rather than by provision. Sketch syntax, to be bikeshed:

```
-- around-advice installable by an actor, not a provision
A SUBJECT TO DETERMINATION BY `the Minister` ON GROUNDS OF g

-- disability / entrenchment: the actor-indexed savings clause
A IMMUNE FROM VARIATION BY `the Registrar`
```

So the wrapper is not `Rule -> Rule` but `Power actor grounds procedure -> Rule -> Rule`, with
`Immune actor` as its negation at the same order. The same constructor pair serves private law
("we reserve the right…") and public law (the Minister's determination); the two differ only in
the review standard attached to the exercise (§10.7.2).

### 10.3 The three strengths of fiat

A single "Fiat" mechanism would flatten three legally distinct acts. They differ in what the act
fixes, in scope, in mechanism, and — decisively — in the standard a reviewing court applies:

| strength          | the act fixes                       | advice kind (§2.8)                    | mechanism                                            | scope                   | public-law review                    | private-law review     |
| ----------------- | ----------------------------------- | ------------------------------------- | ---------------------------------------------------- | ----------------------- | ------------------------------------ | ---------------------- |
| **determination** | the _answer_, for one case          | `around`, declining `proceed()`       | ledger event + early return (§10.4–10.5)             | instant case only       | procedural fairness                  | _Braganza_ rationality |
| **variation**     | the _rule_, prospectively           | none — this is §2.9 amendment         | materialised rewrite A′, version-tagged              | class-wide, prospective | vires                                | unfair-terms control   |
| **dispensation**  | _applicability_, for a named person | `before` guard (`UNLESS exempted(p)`) | ledger-backed exemption predicate; rule stays intact | named person(s)         | consistency / legitimate expectation | waiver, estoppel       |

George Clooney's fast-tracked naturalisation decomposes cleanly: a **dispensation** from the
language requirement plus a **determination** of the ultimate question, neither of which
**varies** the Code civil for anyone else.

**Design rule (no flattening).** Three constructs, not one: a flattened `Fiat` erases exactly
the index review needs. The audit trail of a determination records a case; of a variation, a
provision version; of a dispensation, a person.

**Design rule (variation materialises).** Fiat-the-rule is an amendment and takes §2.9's route:
an explicit source-to-source transform materialising a re-typecheckable A′. The varied rule is a
new version along an _authority_ axis exactly parallel to the temporal axis the shipped
`EVAL … UNDER RULES EFFECTIVE AT` machinery (`jl4-core/src/L4/TemporalContext.hs`) already
gives us; evaluation under a variation is evaluation under the version the empowered actor
enacted.

### 10.4 Mechanism: the ledger is the defeater store

A discretionary act is an **event in the state ledger** — machinery L4 already has
(`RECORD`/`COMMIT`/`ATTEST`/`RECALL`; see `skills/writing-l4-rules/references/state-ledger.md`).
A ministerial determination is an `ATTEST`ed official-record entry naming the power exercised,
the grounds asserted, and the content decided. Evaluation of a defeasible node then:

1. `RECALL` the official record for a valid exercise of the governing power over this node and
   these facts;
2. if one exists, return the fiat content, **labelled as fiat** (§10.5's design rule);
3. otherwise fall through to ordinary derivation.

Morally: `ReaderT Ledger (Either Fiat)`. No new runtime state is required; the novelty is (a)
the typed wrapper naming who may write such entries and on what grounds, and (b) the trace
discipline:

**Design rule (provenanced fiat).** A fiat answer is never silent. Its explanation trace cites
the empowering provision, the recorded act (actor, ledger timestamp), and the grounds asserted —
"by determination of the Minister under s 34(2), recorded at t". That is an honest, checkable
citation: explainability survives contact with discretion instead of being embarrassed by it.

**Design rule (invalid exercise is a verdict, not a type error).** An act by an actor without
the power, outside its grounds, or absent from the ledger does not fail silently and is not
unrepresentable — it evaluates to an **invalid exercise**, a first-class outcome. Review needs
to _reason about_ unlawful exercises; a representation that cannot express them cannot check
them.

### 10.5 The intuitionistic reading: discretion as a control effect

Ordinary L4 derivation is constructive: the evaluation trace is a proof term, and an answer
carries the evidence that produced it. A defeasible conclusion that is neither established nor
refuted is the **residual** — the undecided middle; incomplete contract theory calls authority
over that middle a _residual control right_ (`doc/concepts/legal-modeling/residual.md`).

A discretionary power is a **licence to decide the undecided middle**, and its exercise — the
early return with the fiat answer — is, under Curry–Howard, precisely a **control effect**:
Griffin (1990) showed that control operators inhabit the classical axioms (`call/cc` : Peirce's
law). The architecture that falls out:

- the object-language derivation is **intuitionistic** — every answer carries its proof;
- empowered actors are **handlers** (Plotkin–Pretnar) installed above the computation, one per
  institutional layer; §2.8's `proceed()` is the handler's _resume_;
- a handler may resume (the derivation continues; the power lay dormant) or abort with a
  provenanced fiat — a logged, localised application of excluded middle;
- **appeal is the outer handler**: the court's quashing power is a handler over the Minister's
  handler; the institutional hierarchy _is_ the handler stack, and `lift` is an appeal.

Slogan: _fiat is double-negation elimination as an act of state — classical reasoning admitted
into an intuitionistic system only at named points, by named actors, leaving a named trace._

### 10.6 Prior art and the claimed delta

The neighbouring formalisms, and what each lacks for §10's purposes:

- **Jones & Sergot (1996)** — institutional power via the counts-as conditional. Classical
  modal; no proof objects, no exercise semantics.
- **Gelati, Governatori, Rotolo & Sartor (2004)** — declarative power, representation, mandate
  in defeasible logic; **Governatori & Rotolo (2010**, already cited under §9's references**)**
  — abrogation vs annulment, which is the variation/determination distinction operating at the
  rulebook level. Proof-theoretic and constructive-_flavoured_ (a defeasible tag and its
  negation can both fail to be provable — no excluded middle for defeasible conclusions), but
  the proof tags are meta-level annotations, not proof terms: no Curry–Howard content.
- **Prakken & Sartor** argumentation — grounded semantics is a least fixpoint (constructive
  flavour again), but arguments remain meta-level objects.
- **eFLINT (2020)** — executable Hohfeld; operational, not type-theoretic.
- **Catala (§5.1)** — the one neighbour that genuinely went the intuitionistic direction: a
  typed default calculus mechanised in F\*. But its exceptions are static rule-against-rule
  structure — no actor index, no speech-act defeater, no power/immunity layer.
- **LegalRuleML `Override`** — interchange data; no semantics of exercise at all.

The delta this section claims: **actor-indexed defeasance with control-operator semantics and
proof-term provenance** — powers as handlers, fiat as a provenanced classical hole in an
intuitionistic derivation. We have not found this move in the legal-logic literature. **A
focused prior-art verification pass is owed before the claim is made in print** — the
`hohfeld-higher-order` facet's own deep-research pass demoted its headline claim, and this one
should expect the same scrutiny.

### 10.7 Open questions specific to discretion

1. **Procedure index.** Many powers are conditional on procedure (consultation, laying before
   Parliament, giving reasons). Is procedure a type index on `Power`, a runtime guard, or both?
2. **Grounds review.** _Braganza_ (private) and Wednesbury/proportionality (public) as
   pluggable review standards over the one `Power` constructor — how much belongs in-language
   versus in the verifier?
3. **The tower.** Powers over powers: the court quashes the Minister; the legislature strips
   the court. Termination/stratification interacts with §4.2 (circular priority) and with the
   planned "Who May Change the Rules" facet (`paper/README.md`) — layered amendment authority
   is this tower at the rulebook level.
4. **Burden interaction (§5.6).** Who must prove the act happened, and who that it was valid?
5. **Notice.** Dispensations for named persons live in the official record; what does a third
   party's evaluation see? (Publicity of the ledger; cf. gazettal practice.)

---

## References

### Legal Drafting

- Adams, K. "A Notwithstanding Sideshow." Adams on Contract Drafting. [Link](https://www.adamsdrafting.com/a-notwithstanding-sideshow/)
- Weagree. "Notwithstanding in Contracts." [Link](https://weagree.com/clm/contracts/contract-wording/notwithstanding/)
- UpCounsel. "Notwithstanding Meaning in Law." [Link](https://www.upcounsel.com/notwithstanding-legal-use)
- LawProse. "Lesson #196: Notwithstanding." [Link](https://lawprose.org/lawprose-lesson-196-notwithstanding/)

### Statutory Interpretation

- Congressional Research Service. "Notwithstanding Clauses." [PDF](https://sgp.fas.org/crs/misc/notwith.pdf)
- Capitol Weekly. "The Use of Notwithstanding Clauses in California Legislation." [Link](https://capitolweekly.net/the-use-of-notwithstanding-clauses-in-california-legislation/)
- SCC Times. "Circumscribing Non Obstante Clauses." [Link](https://www.scconline.com/blog/post/2023/06/16/circumscribing-non-obstante-clauses-tracing-the-new-jurisprudence/)
- LawCrust. "Non Obstante Clause in Interpretation of Statutes." [Link](https://lawcrust.com/non-obstante-clause/)

### Defeasibility and Formal Methods

- Stanford Encyclopedia of Philosophy. "Defeasible Reasoning." [Link](https://plato.stanford.edu/entries/reasoning-defeasible/)
- Prakken, H. "The Three Faces of Defeasibility in the Law." _Ratio Juris_ (2004). [Link](https://onlinelibrary.wiley.com/doi/abs/10.1111/j.0952-1917.2004.00259.x)
- NDPR. "Allowing for Exceptions: A Theory of Defences and Defeasibility in Law." [Link](https://ndpr.nd.edu/reviews/allowing-for-exceptions-a-theory-of-defences-and-defeasibility-in-law/)
- Schauer, F. "Is Defeasibility an Essential Property of Law?" [PDF](http://www.horty.umiacs.io/courses/readings/schauer-defeasibility.pdf)

### Legal Principles

- US Legal Forms. "Lex Specialis Derogat Generali." [Link](https://legal-resources.uslegalforms.com/l/lex-specialis-derogat-generali)
- iPleaders. "Non-Obstante Clause." [Link](https://blog.ipleaders.in/all-you-need-to-know-about-non-obstante-clause/)
- LII. "Condition Precedent." [Link](https://www.law.cornell.edu/wex/condition_precedent)

### Aspect-Oriented & Computational Models

- Kiczales, G. et al. "Aspect-Oriented Programming." _ECOOP_ (1997) — advice, pointcuts, `around` / `proceed`.
- AspectJ Programming Guide — `before` / `after` / `around` advice and `proceed()` semantics.
- Gamma, Helm, Johnson, Vlissides. _Design Patterns_ (1994) — the Decorator pattern (object-level wrapping).

### Legal Logic Programming (PROLEG / negation as failure)

- Satoh, K. et al. "PROLEG: An Implementation of the Presupposed Ultimate Fact Theory of Japanese Civil Code by PROLOG Technology." _JURISIN_ (2010). [PDF](https://research.nii.ac.jp/~ksatoh/juris-informatics-papers/jurisin2010-ksatoh.pdf)
- "PROLEG: Practical Legal Reasoning System." _Springer_ (2023). [Link](https://link.springer.com/chapter/10.1007/978-3-031-35254-6_23)
- "Can Legislation Be Made Machine-Readable in PROLEG?" _arXiv_ (2026). [Link](https://arxiv.org/html/2601.01477)

### Applicability of Norms (§9)

- von Wright, G.H. _Norm and Action: A Logical Enquiry_. Routledge & Kegan Paul (1963) — the _condition of application_ as a component of a norm distinct from its content.
- Hage, J. "A Theory of Legal Reasoning and a Logic to Match." _Artificial Intelligence and Law_ 4 (1996) 199–273 — Reason-Based Logic's distinction between a rule being _applicable_ and the rule _applying_.
- Hage, J. _Reasoning with Rules: An Essay on Legal Reasoning and Its Underlying Logic_. Kluwer (1997).
- Verheij, B. _Rules, Reasons, Arguments: Formal Studies of Argumentation and Defeat_. PhD thesis, Universiteit Maastricht (1996).
- Prakken, H. & Sartor, G. "A Dialectical Model of Assessing Conflicting Arguments in Legal Reasoning." _Artificial Intelligence and Law_ 4 (1996) 331–368 — applicability and priority as objects of argument.
- Sergot, M.J., Sadri, F., Kowalski, R.A., Kriwaczek, F., Hammond, P. & Cory, H.T. "The British Nationality Act as a Logic Program." _Communications of the ACM_ 29(5) (1986) 370–386 — mechanised statutory cross-reference; negation as failure over provisions.
- Hernández Marín, R. & Sartor, G. "Time and Norms: A Formalisation in the Event-Calculus." _Proceedings of ICAIL 1999_, 90–100 — separating a norm's existence, force, and applicability in time.
- Palmirani, M. & Vitali, F. "Akoma-Ntoso for Legal Documents." In _Legislative XML for the Semantic Web_, Springer (2011) — force / efficacy / application as distinct metadata intervals.
- Governatori, G., Palmirani, M., Riveret, R., Rotolo, A. & Sartor, G. "Norm Modifications in Defeasible Logic." _JURIX 2005_ — formal semantics for provisions that modify other provisions.
- Governatori, G. & Rotolo, A. "Changing Legal Systems: Legal Abrogation and Annulment in Defeasible Logic." _Logic Journal of the IGPL_ 18(1) (2010) 157–194.
- Bench-Capon, T. & Coenen, F. "Isomorphism and Legal Knowledge Based Systems." _Artificial Intelligence and Law_ 1(1) (1992) 65–86 — one source provision, one representation unit.
- Anderson, A.R. "A Reduction of Deontic Logic to Alethic Modal Logic." _Mind_ 67 (1958) 100–103 — obligation as violation-freedom: the `satisfied` / complies projection.
- Meyer, J.-J.Ch. "A Different Approach to Deontic Logic: Deontic Logic Viewed as a Variant of Dynamic Logic." _Notre Dame Journal of Formal Logic_ 29(1) (1988) — the dynamic-logic form of the Andersonian reduction.

### Statutes and Drafting Guidance Cited in §9

- Contracts (Rights of Third Parties) Act 2001 (Singapore). [SSO](https://sso.agc.gov.sg/Act/CRTPA2001) — s 2 (operative rule), s 4(1) (applicability gate), s 5 (savings), s 7 (write-side "Exceptions" section). Verified against the current revised edition via the lawplain corpus, 2026-08-16.
- Companies Act 2006 (UK), s 724 (Treasury shares). [legislation.gov.uk](https://www.legislation.gov.uk/ukpga/2006/46/section/724) — the two-step idiom verbatim in (1)/(3); (5)(a) reads the applicability predicate retrospectively. Quotes verified against the current revision via legislation.gov.uk, 2026-08-19.
- Human Rights Act 1998 (UK), s 10. [legislation.gov.uk](https://www.legislation.gov.uk/ukpga/1998/42/section/10) — "This section applies if …" self-declaration whose trigger (1)(a) cites a declaration made under s 4; s 10(4) is the "also applies" extension. Quotes verified against the current revision via legislation.gov.uk, 2026-08-19.
- Office of the Parliamentary Counsel (UK). _Drafting Guidance_ (March 2024). [PDF](https://assets.publishing.service.gov.uk/media/660407d091a320001a82b06b/2024.03.19.Drafting-guidance.pdf) — clause structure: conditions versus the main proposition.

### Philology (§9.8)

- Etymonline: [apply](https://www.etymonline.com/word/apply), [imply](https://www.etymonline.com/word/imply), [comply](https://www.etymonline.com/word/comply); OED "comply, v.²" — _apply_ / _imply_ < Latin _plicare_ (fold); _comply_ < Latin _complēre_ (fill up), the _-ply_ spelling by attraction to "ply".

### Discretionary Power and Control (§10)

- Hohfeld, W.N. "Some Fundamental Legal Conceptions as Applied in Judicial Reasoning." _Yale Law Journal_ 23 (1913) 16–59 — the power/liability and immunity/disability axes.
- Jones, A.J.I. & Sergot, M. "A Formal Characterisation of Institutionalised Power." _Journal of the IGPL_ 4(3) (1996) 427–443 — the counts-as conditional.
- Gelati, J., Governatori, G., Rotolo, A. & Sartor, G. "Normative Autonomy and Normative Co-ordination: Declarative Power, Representation, and Mandate." _Artificial Intelligence and Law_ 12 (2004) 53–81.
- Griffin, T. "A Formulae-as-Types Notion of Control." _POPL_ (1990) — `call/cc` inhabits Peirce's law; classical axioms as control operators.
- Plotkin, G. & Pretnar, M. "Handlers of Algebraic Effects." _ESOP_ (2009) — the handler-stack reading of §10.5.
- Merigoux, D., Chataing, N. & Protzenko, J. "Catala: A Programming Language for the Law." _ICFP_ (2021) — the typed default calculus, mechanised in F\*.
- van Binsbergen, L.T., Liu, L.-C., van Doesburg, R. & van Engers, T. "eFLINT: a Domain-Specific Language for Executable Norm Specifications." _GPCE_ (2020).
- _Braganza v BP Shipping Ltd_ [2015] UKSC 17 — rationality review imported into _contractual_ discretion; the private/public unification of §10.7.2.
- _Associated Provincial Picture Houses Ltd v Wednesbury Corp_ [1948] 1 KB 223.
- Grossman, S. & Hart, O. (1986); Hart, O. & Moore, J. (1990) — residual control rights; full citations and the incomplete-contracts bridge in `doc/concepts/legal-modeling/residual.md`.

### Related L4 Documentation

- `doc/default-logic.md` - L4's treatment of default reasoning
- `doc/regulative.md` - Regulative rule semantics
- `jl4/experiments/Singapore-Data-Protection-Act.l4` - Example using "subject to" informally
- `specs/todo/TEMPORAL_EVAL_SPEC.md` - the `EVAL … UNDER RULES EFFECTIVE AT` axis (§9.2 conjunct 1)
- `specs/todo/HOMOICONICITY-SPEC.md` - R10 owns the citation forms that escape §9.5's closed world

---

## Appendix A: Example Corpus (To Be Expanded)

### A.1 Priority Declaration Examples

```
-- From securities regulations
"NOTWITHSTANDING Rule 144, restricted securities may be sold
 pursuant to an effective registration statement."

-- From employment law
"Annual leave entitlement is SUBJECT TO the maximum accrual
 limits in Company Policy 4.2."
```

### A.2 Exception Examples

```
-- From tax code
"All income is taxable, SUBJECT TO the exemptions in Schedule A."

-- From data protection
"Personal data shall not be processed, NOTWITHSTANDING WHICH,
 processing is permitted for the purposes listed in Article 6."
```

### A.3 Condition Precedent Examples

```
-- From contract law
"The purchase shall complete SUBJECT TO satisfactory survey."

-- From regulatory approval
"The merger is SUBJECT TO approval by the Competition Authority."
```

### A.4 Canadian Charter Section 33

The canonical constitutional example:

```
"Parliament or the legislature of a province may expressly declare
 in an Act of Parliament or of the legislature, as the case may be,
 that the Act or a provision thereof shall operate NOTWITHSTANDING
 a provision included in section 2 or sections 7 to 15 of this Charter."
```

This allows legislatures to override certain Charter rights for renewable 5-year periods.
