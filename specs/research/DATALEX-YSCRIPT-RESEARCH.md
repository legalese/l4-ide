# L4 → DataLex/yscript: expressive overlap and feasibility

_Status: **research memo, complete.** Commissioned 2026-09-08 by Meng, who asked for the DataLex
project's `yscript` language to be added to the transpiler-backend backlog — tentatively "within
the Prolog family" — alongside LegalRuleML (already researched, see
[LEGALRULEML-RESEARCH.md](LEGALRULEML-RESEARCH.md)). No transpiler is being built now; this memo
and its companion do the research and leave representative examples so a future session can decide
whether to. Evidence marks follow that memo's convention: **[E]** = primary document fetched and
read directly in this session (page numbers cite the PDF actually opened); **[E via fetch]** = a
web page fetched and summarised by the fetch tool's own model, not re-verified by direct quotation
here; **[U]** = secondary — a search-result characterisation, a citation to a manual this session
could not open, or hearsay._

---

## A. Verdict

**Research it now, build nothing yet — and the premise needs one correction.** DataLex is real,
active, and well-documented: AustLII (the Australasian Legal Information Institute) has run it
since the 1990s, and its current incarnation — the `yscript` language plus the `ylegis`
natural-language preprocessor — is the subject of a live UNSW/AustLII publication programme
(2021–2023) that this memo read directly **[E]**. But the premise that motivated researching it
alongside PROLEG and the other logic-programming legs — "possibly within the Prolog family" — does
not survive contact with the primary source. yscript is not a Prolog dialect, does not compile to
or from Prolog, and its own documentation never mentions Prolog. Its closest kin in this repo's
own family taxonomy (`BACKEND-PORTFOLIO-SPEC.md` §1.1) is **DocAssemble** — a natural-language,
citation-linked, dialogue-driven consultation engine — not PROLEG or swipl. Where it does genuinely
rhyme with the logic-programming legs is narrower and more interesting than "same family": its
`Why?`/`How?`/verbose-trace/Report explanation apparatus is an independently-built, decades-old
answer to exactly the audit-grade-explanation problem this project's `#TRACE` and the reasoning
family's justification trees (s(CASP)) are built to solve — and its `ylegis` format is an existing,
shipped attempt at the same "legislation that is also the code" isomorphism L4 itself is chasing,
achieved with a far weaker grammar (single proposition per clause, explicit `and:`/`or:` connectives)
than L4's typed functional core.

## B. What DataLex/yscript actually is

**History and status.** yscript descends from an "expert system shell" called `ysh`, later
integrated into a web front end called `wysh` ("web-ysh"), and is now the rule language of AustLII's
DataLex applications-development environment **[E, footnote 62 of the paper cited below]**. AustLII
is a 30-year-old free-access-to-law institute (the Australasian sibling of Cornell's LII), and
DataLex is its "Rules as Code" (RaC) platform — used to encode legislation as interactive
"consultations" that a citizen or advisor runs against their own facts. The project is under active
publication as of 2023 **[E]**: Mowbray, Chung & Greenleaf, "Explainable AI (XAI) in Rules as Code
(RaC): The DataLex approach", Elsevier manuscript (CC-BY-NC-ND 4.0), published version at
`sciencedirect.com/science/article/pii/S0923649622001692`; companion overview Mowbray, Greenleaf &
Chung, "Law as Code: Introducing AustLII's DataLex AI", UNSW Law Research Paper 21-81 (16 Nov 2021,
SSRN 3971919) **[U, cited by the paper this memo read, not independently opened — SSRN blocked this
session's fetcher with an HTTP 403]**. AustLII explicitly scopes current DataLex deployments to
**educational and testing purposes**, not production legal advice **[E via fetch, COHUBICOL
typology page]** — a caveat this project's own "man on the street" nonconsumer target market should
weigh, since it is the same market DataLex has been serving, cautiously, for years.

**License and availability.** The yscript interpreter and yscript library are open source under the
**GNU Affero GPL**, with source distributed as a tarball from `datalex.org/src/ys/ys-latest.tar.gz`
**[E, footnote 60/61 of the paper]**. AGPL is copyleft over network use — any service built on the
interpreter must offer its own source — a materially different posture than this project's own
licensing and worth flagging early if a future emitter or embedding were ever considered. yscript
codebases (the actual rule files, as opposed to the interpreter) are "generally publicly available"
and distributed under open-content licences by convention, not by the interpreter's own license
terms **[E]**. Full manuals exist — "Coding in yscript" (May 2021) and the "DataLex Developer's
Manual" (June 2021) — but this session could not fetch either PDF directly: `austlii.community`
returns an interstitial bot-check page to automated fetchers, and this memo's yscript/ylegis code
knowledge instead comes from the worked examples reproduced **verbatim** inside the paper this
session did read directly, which functions as a faithful secondary specification of the syntax
**[E, see the exact figures reproduced in §C below]**.

**The language, in its own terms.** yscript is "a language for representing and manipulating
propositions", with a "quasi-natural-language 'English-like' syntax" deliberately designed to avoid
programming-language symbols so that non-programmers — specifically, lawyers and legislative
drafters without a computing background — can write and audit it directly **[E]**. It is
declarative by default (rules state relationships between facts) with imperative extensions, and
supports two authoring routes to the same executable artifact:

1. **Direct yscript authoring** — a human writes `RULE ... PROVIDES ... ONLY IF ...` clauses by
   hand, one rule per legislative provision, by convention (the "isomorphic representation" the
   paper treats as a load-bearing design goal, not an incidental style choice) **[E]**.
2. **`ylegis`** — a preprocessor that takes an existing section of legislation, written in a
   near-conventional legislative drafting style but with premises and conclusions linked by an
   explicit `and:`/`or:` vocabulary, and mechanically emits a "first draft" of yscript for it
   **[E]**. The claim is stronger than "generates code from text": the `ylegis` _source itself_ is
   simultaneously legislation and code — "if a piece of legislation is written using the ylegis
   format, an intermediate yscript version will be generated automatically during execution on
   which explanations will be based without having to code a separate version of the legislation
   in yscript" **[E, quoted verbatim]**.

**Execution model.** Running yscript code produces a _consultation_: the interpreter asks the user
questions (backward-chaining, goal-directed — it seeks values for facts a rule needs), and as new
facts become known it re-derives what else can now be concluded (a forward-propagation step),
restarting evaluation from the top with the enlarged fact set rather than continuing an in-flight
derivation **[E via fetch, O'Hanley]**. The language **disallows recursion**, which the same source
gives as the reason its negation semantics stays simple — there is no need for a fixpoint theory
when rule dependency cannot cycle **[E via fetch, O'Hanley]**; that is the same stratification
concern `LOGIC-PROGRAMMING-BACKENDS-SPEC.md` §2.5 raises for the LP legs, solved here by
disallowing the general case entirely rather than checking for it. A secondary characterisation
(unattributed in this session's search results, so marked accordingly) states that yscript's
expressive power is, at bottom, **propositional logic** **[U]** — consistent with the "no
recursion, no general terms" reading above, and a useful calibration: this is closer to a
decision-table / boolean-network engine dressed in English than to a general Horn-clause solver.

**Explanation apparatus.** This is DataLex's most distinctive and most L4-relevant feature. Every
consultation exposes, live, at every question:

- **`Why?`** — why is this question being asked (which rule needs this fact, and for what
  higher-level conclusion) **[E]**.
- **`How?`** — for any conclusion reached, which facts and which rule derived it **[E]**.
- **`What if?`** — try a hypothetical answer to the current question without committing to it
  **[E]**.
- **`Forget`** — retract a previously-given fact; the interpreter re-asks whatever depended on it
  **[E]**.
- **Verbose mode** — show every rule as it fires, live, during the consultation (Figure 7 of the
  paper shows a real `RULE Section 8 ...` firing trace against the _Foreign Relations (State and
  Territory Arrangements) Act 2020_ (Cth)) **[E]**.
- **Report** — at consultation end, a generated natural-language document explaining, from the
  fired rules and the user's own answers, why the final conclusion follows **[E]**.

None of this is separately authored: "there is no separate coding of what a codebase should 'do',
nor for specific explanations or other system dialog. All interactions are generated automatically
from the facts contained in the rules" **[E, quoted verbatim]**. That is a stronger claim than this
project currently makes for any shipped backend — DocAssemble's dialogue and Blawx's NLG both
consume authored `@nlg`/prefill metadata; DataLex's is derived purely from the rule structure and
the (English-like) rule text itself, with no separate template layer at all.

**Case-based reasoning.** A secondary source names a component called **PANNDA** ("Precedent
Analysis by Nearest-Neighbour Discriminant Analysis") that compares fact bundles against
formalised precedents as a case-based-reasoning supplement to yscript's rule-based reasoning
**[U, via fetch, COHUBICOL]**. This traces to Zeleznikow & Stranieri's much older DataLex-family
work (the _Split-Up_ family-law-property system) and this memo did not independently verify it
against a primary source; it is noted here because it means "DataLex" is not purely rule-based even
though "yscript" — the part relevant to a transpiler — is.

## C. Worked examples (verbatim, primary source)

All three examples below are reproduced character-for-character from Figures 2, 9 and 10 of
Mowbray, Chung & Greenleaf (2022/2023), read directly in this session **[E]**. They are the closest
thing to "the manual" this session could obtain, since the dedicated yscript/ylegis manuals 403'd
every fetch attempt.

**Direct yscript, from a real DataLex codebase** (_Foreign Relations (State and Territory
Arrangements) Act 2020_ (Cth), s10):

```
RULE Section 10 - Core foreign arrangements PROVIDES
the arrangement is a "core foreign arrangement" under section 10(2) ONLY IF
    the arrangement is a "foreign arrangement" under section 6 AND
    the Australian entity is a "core State/Territory entity" under
    section 10(3) AND
    the non-Australian entity is a "core foreign entity" under section 10(4)

RULE Section 10(3) PROVIDES
the Australian entity is a "core State/Territory entity" under section 10(3)
ONLY IF
    section 7(a) applies OR
    section 7(b) applies OR
    section 7(c) applies
```

**The same style, but nested, from a second worked example** (_Hairdressers Act 2003_ (NSW), s4(1)
— hand-coded in yscript from the statute text):

```
RULE Section 4 - When is an individual "qualified to act as a hairdresser"
PROVIDES
SUBRULE Section 4(1)
SUBRULE Section 4(2)

RULE Section 4(1) PROVIDES
the hairdresser is qualified to act as a hairdresser ONLY IF
    section 4(1)(a) applies OR
    section 4(1)(c) applies OR
    section 4(1)(d) applies

RULE Section 4(1)(a) PROVIDES
section 4(1)(a) applies ONLY IF
    the hairdresser has been awarded a hairdressing qualification AND
    the qualification was awarded by a registered training organisation AND
    the qualification is an "authorised qualification" under section 4(2)

RULE Section 4(1)(c) PROVIDES
section 4(1)(c) applies ONLY IF
    a determination has been made under section 37 of the Apprenticeship and
    Traineeship Act 2001 that the hairdresser is adequately trained to pursue
    the recognised trade vocation of hairdressing (because the hairdresser has
    acquired the competencies of the recognised trade vocation)

RULE Section 4(1)(d) PROVIDES
section 4(1)(d) applies ONLY IF
    the hairdresser has held, or been taken to have held, a licence under
    Part 6 (Regulation of the hairdressing trade) of the Shops and Industries
    Act 1962 AND the licence was limited to carrying out beauty treatment only
```

**The same s4(1), in `ylegis` format** — legislative drafting close to the statute's own prose, with
premises and conclusions related by explicit connective keywords rather than nested `RULE`
declarations:

```
4. When is an individual "qualified to act as a hairdresser"?
(1) An individual is qualified to act as a hairdresser if--
    (a) the individual has been awarded an authorised qualification by a
    registered training organisation; or
    (c) a determination has been made under section 37 of the
    Apprenticeship and Traineeship Act 2001 that the individual is adequately
    trained to pursue the recognised trade vocation of hairdressing (because the
    hairdresser has acquired the competencies of the recognised trade
    vocation); or
    (d) the individual has at any time held, or been taken to have held, a
    licence under Part 6 (Regulation of the hairdressing trade) of the
    Shops and Industries Act 1962 and the licence was limited to carrying out
    beauty treatment only.
```

The `ylegis` form is visibly closer to how an L4 drafter would want to _read_ a statute (the paper's
own figure captions call it "close to existing conventional legislative drafting"); the plain
`yscript` form is closer to what an L4 `DECIDE`/`MEANS` chain already looks like once flattened —
`section 4(1)(a) applies ONLY IF <conjunction>` is structurally the same shape as an L4 boolean
`DECIDE` over a `WHERE` clause, minus types, minus records, minus numeric or date computation.

## D. Stratum-by-stratum overlap

| L4 stratum                                                         | yscript construct                                                                                                                                                                                                                                                        | Verdict                              |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------ |
| Constitutive core, boolean `DECIDE`/`MEANS` over `AND`/`OR`        | `RULE ... PROVIDES ... ONLY IF <conjunction/disjunction>` — a direct structural match on the propositional fragment                                                                                                                                                      | **CLEAN** (propositional slice only) |
| Records/enums, typed data                                          | none — facts are named propositions or simple string/numeric slots filled by consultation answers, no declared types, no record shape                                                                                                                                    | **OUT / EMULATED**                   |
| `NUMBER`/`DATE`/`STRING`                                           | supported as plain fact values inside a consultation, but with no documented numeric type discipline (no exact-rational analogue found)                                                                                                                                  | **RESTRICTED, unverified**           |
| Recursion, higher-order functions                                  | recursion is disallowed by the language itself **[E via fetch]**                                                                                                                                                                                                         | **OUT, by design**                   |
| `PARTY p MUST/MAY/SHANT`, deontic layer                            | no counterpart found — yscript concludes facts, not obligations; the worked examples are all "does X apply", never "who must do X"                                                                                                                                       | **OUT**                              |
| `HENCE`/`LEST`, `WITHIN` deadlines                                 | no counterpart found                                                                                                                                                                                                                                                     | **OUT**                              |
| Ambiguity register (`Alternatives`)                                | no explicit multi-reading construct; the closest analogue is a per-fact **"Uncertain"** answer state during consultation (Figure 6), which records "the user does not know", not "there are two competing legal readings" — a different kind of uncertainty              | **OUT (different concept)**          |
| `MAYBE BOOLEAN` (`JUST TRUE`/`JUST FALSE`/`NOTHING`)               | a fact can be answered, denied, or left as "Uncertain"/unasked — a three-state shape that rhymes with L4's `MAYBE BOOLEAN`, though the interpreter's closed-world default for an unproven fact was not confirmed against a primary source                                | **RESTRICTED, plausible analogue**   |
| `#TRACE` / audit-grade explanation                                 | `Why?`/`How?`/verbose rule-firing trace/end-of-session Report — independently built, decades-old, and the paper's central thesis is exactly this project's own "counter hallucination with guardrailed, robust left-brain logic" pitch, applied to a non-LLM rule engine | **CLEAN, strongest overlap**         |
| `@ref` citation/provenance                                         | consultation UI hyperlinks every reference to the source Act/section on AustLII directly, live, during the dialogue                                                                                                                                                      | **CLEAN**                            |
| Isomorphic source-to-code mapping (this project's own house value) | the explicit, named design goal of both plain yscript authoring and, more strongly, `ylegis` ("legislation is code")                                                                                                                                                     | **CLEAN, strongest conceptual echo** |
| `TYPICALLY` defaults                                               | no counterpart found                                                                                                                                                                                                                                                     | **OUT**                              |
| Effects/ledger (`FETCH`/`RECORD`/`COMMIT`)                         | none — DataLex answers questions about a fact situation; it does not act on external systems                                                                                                                                                                             | **OUT**                              |

## E. Family placement: not the Prolog family

The originating question was whether yscript belongs "within the Prolog family" alongside PROLEG,
swipl, ASP/clingo, Logical English and ErgoAI in `LOGIC-PROGRAMMING-BACKENDS-SPEC.md`. On the
evidence gathered, **no**:

- Nothing in the paper, the search results, or the secondary characterisations mentions Prolog,
  Horn clauses, SLD resolution, or any LP substrate underneath the yscript interpreter. The
  interpreter is described entirely in its own terms (goal-directed questioning, forward
  fact-propagation, restart-on-new-fact), which is a distinct implementation lineage from the
  Prolog-descended engines this project already tracks.
- The LP family's defining axis (`LOGIC-PROGRAMMING-BACKENDS-SPEC.md` §1, "what each preserves of
  L4's meaning" — multiplicity, burden of proof, defeasible priority) has no yscript column to add:
  yscript has none of multiplicity (no stable-model enumeration), burden allocation (no
  plaintiff/defendant marking of exceptions), or defeasible priority (no override/exception
  construct). Its one genuinely distinctive dimension — live, structure-derived explanation with no
  separate authoring — sits outside that table's axes entirely.
- Its nearest sibling **in this project's own six-family taxonomy** (`BACKEND-PORTFOLIO-SPEC.md`
  §1.1) is **DocAssemble**: both are dialogue-driven, citation-linked, natural-language-facing
  consultation engines aimed at end-users rather than lawyers, and both make interaction-family
  claims (the "ask the citizen" family), not reasoning-family claims in the sense that swipl/ASP/
  PROLEG/Ergo do (multiplicity, burden, override-as-a-construct).

So the honest placement is: **add DataLex/yscript to the census as a `FUTURE` row under the
Interaction family**, cross-referencing this memo, rather than folding it into the Prolog-family
spec. If a future session pursues it, the natural sequencing sits _after_ DocAssemble (the nearer
sibling) rather than after the LP legs.

## F. Feasibility, if ever pursued

Not scoped as a real proposal — no `R1..Rn` ruling ladder is written here, because nothing is
committed. Noted for whoever picks this up:

- **The propositional slice is easy; everything else is not there to take.** A hypothetical emitter
  would cover boolean `DECIDE`/`MEANS` chains over `AND`/`OR`/`NOT` — exactly the `ok/logic.l4`-style
  fragment — and stop. No records, no numbers with a defined precision contract, no dates, no
  regulative layer, no temporal axis. This is a narrower fragment than any backend currently in the
  census; OpenFisca's and Catala's exportable cores both dwarf it.
  the value proposition would not be "run L4 logic on yscript" but "demonstrate L4's isomorphic
  formalisation claim against a second, independently-designed isomorphic-formalisation tool" — a
  comparison piece, not an execution target.
- **No differential oracle exists.** Unlike swipl/clingo/s(CASP), there is no evident way to invoke
  the yscript interpreter as a subprocess and script a comparison against `L4.EvaluateLazy` from
  this session's research — the interpreter's invocation surface (a source tarball plus a
  Communities collaborative-editing environment) was not characterised deeply enough here to say
  whether headless batch execution (the DocAssemble/`etc/validate-dmn.mjs` posture, I4) is even
  possible without the AustLII web UI. That is the first thing a real proposal would need to
  establish.
- **AGPL is a real constraint**, not a formality, if the interpreter itself were ever vendored or
  called as a service rather than used purely as an offline validation oracle akin to `xmllint` for
  LegalRuleML.
- **The explanation apparatus is the actual prize**, and it is a UX/design prior-art question more
  than a transpiler question: DataLex's `Why?`/`How?`/verbose-trace/Report cluster is a
  fully-worked, shipped answer to "how do you show a non-lawyer end user that the system's
  conclusion follows from the rules and their own answers, with citations" — the same problem this
  project's web wizards (Housing Act, Reg CF) and `#TRACE` are solving independently. Reading the
  full "Coding in yscript" and "DataLex Developer's Manual" PDFs (both 403'd this session; try a
  real browser session or an institutional proxy) before designing L4's own explanation UI further
  would be cheap due-diligence against reinventing a decades-old wheel.
- **Update, same day:** this observation turned out to have a concrete, already-built landing
  spot. `jl4-query-plan`'s ROBDD substrate (`doc/reference/query-planning/README.md`) already
  computes the dependency closures and `restrict` sequences that would make `Why?`/`How?`/
  `What if?`/`Forget` cheap to expose — the gap is only that today's wizard throws that structure
  away after each "what's next" call. Backlogged in `specs/roadmap/future-features.md`
  ("Interactive explanation surface for the query planner").

## G. Sources

**Primary, read directly in this session [E]:** Mowbray, A., Chung, P. & Greenleaf, G.,
"Explainable AI (XAI) in Rules as Code (RaC): The DataLex approach" (13 May 2022 pre-publication
draft; published version at Elsevier, `sciencedirect.com/science/article/pii/S0923649622001692`,
CC-BY-NC-ND 4.0; PDF obtained via UTS OPUS,
`opus.lib.uts.edu.au/bitstream/10453/172255/3/pub.1147503917 AM.pdf`) — read in full (pages 1-19 of
20), §§5.1-5.8 and Figures 2-10 specifically for yscript/ylegis syntax and the explanation
apparatus.

**Fetched and summarised by the fetch tool's model, not independently re-verified by quotation
[E via fetch]:** COHUBICOL publications typology page on DataLex
(`publications.cohubicol.com/typology/datalex/`) — paradigm characterisation, PANNDA, scholarly
critique (translation-quality risk, non-judicial-coder authority limits, maintenance overhead,
"educational and testing purposes only" restriction); William O'Hanley, "Visual propositional logic
with yscript" (`wohanley.com/posts/visual-yscript/`) — the `RULE ... PROVIDES ... ONLY IF` minimal
example, the goal-rule/first-rule execution-start rule, the no-recursion-simplifies-negation claim,
and the restart-on-new-fact execution model.

**Attempted and blocked (HTTP 403 to every fetch method tried, including a browser-UA `curl` and a
jina.ai reader proxy) — cited here only via what other sources quote or describe [U]:** the
`ys-manual.pdf` ("Coding in yscript", Andrew Mowbray, May 2021) and the "DataLex Developer's Manual"
(June 2021), both at `austlii.community/foswiki/pub/DataLex/WebHome/`; `datalex.org` itself;
`classic.austlii.edu.au/au/journals/UNSWLRS/2021/81.pdf` (the "Law as Code" overview paper, UNSW Law
Research Paper 21-81 / SSRN 3971919). All three are cited _by_ the paper this session did read, so
the facts attributed to them above are one hop removed from primary, not invented.

**Secondary, via search-engine result summaries only, not fetched [U]:** the seven-component
DataLex toolkit list (yscript language, yscript interpreter, `ylegis` preprocessor, `ylegis`
"formal mode", DataLex Application Development Tools, default consultation UI, DataLex Community
development environment); the AGPL-license and source-tarball facts (corroborated independently by
the primary-source footnote above, so treated as confirmed); the characterisation of yscript's
expressive power as "basically, propositional logic" (unattributed paper, found only in a search
snippet — track down the actual citation before repeating this claim with confidence); DataLex's
own source code (as opposed to the yscript interpreter) reportedly not being publicly available
despite the web application being accessible.

**Related work already in this repo, for cross-reference:** `LEGALRULEML-RESEARCH.md` (the sibling
memo commissioned in the same request); `BACKEND-PORTFOLIO-SPEC.md` §1.1 (six-family taxonomy) and
§2.3 (Interaction census, where this memo's FUTURE row is added); `LOGIC-PROGRAMMING-BACKENDS-SPEC.md`
§1 (the LP lattice's preserved-dimension table, against which §E above found no fit).
