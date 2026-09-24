# L4 ↔ RegelSpraak: expressive overlap and feasibility

_Status: **research memo, complete, 2026-09-24.** Commissioned 2026-09-24 by Meng ("research
RegelSpraak as a possible transpilation candidate and add it to our backlog"). No transpiler is
built here. This memo does the research, keeps representative examples, and proposes a census row
(§H) so a future session can decide whether to build one. Evidence marks follow
[DATALEX-YSCRIPT-RESEARCH.md](DATALEX-YSCRIPT-RESEARCH.md). **[E]** means the primary source was
read directly in this session: PDF text extracted and read (page numbers are PDF pages), an embedded
image read and transcribed, or a repository cloned and read at a named commit. **[E via fetch]**
means a web page summarised by the fetch tool's model and not re-quoted. **[U]** means secondary, a
search-result characterisation, or unverified. Several relationships assumed in the commission
turned out wrong or unsupported; each is marked **Premise correction** where it arises._

---

## A. Verdict

**Research it now and build nothing yet. If we do build, import comes first, and it goes through
ALEF's model files rather than the Dutch text.**

RegelSpraak is the Belastingdienst's controlled natural language (CNL) for executable tax rules. It
is real and operational at scale: born at the end of 2009, with an income-tax calculation service in
production since 2019 **[E, spec v2.3.0 pp.8–9]**. Two recent facts make it a better candidate than
yscript or LegalRuleML were. First, the language has a current, public, versioned specification:
v2.3.0, dated 4-12-2025, 149 pages, with an EBNF chapter. It is also **"Alle rechten voorbehouden"**
(all rights reserved) **[E, p.1]**. Second, its toolchain **ALEF** went open source under
**EUPL-1.2** on 2026-05-29. ALEF was last committed to on 2026-09-22 and includes an interpreter, a
Java generator and a headless project builder **[E, `belastingdienst/ALEF` @ `31bbe71`]**.

So I3's **executed round-trip** tier is reachable in principle, which neither yscript nor
LegalRuleML could offer. The catch is that ALEF is a JetBrains MPS **projectional** editor with no
text parser for RegelSpraak. The route to execution therefore runs through ALEF's `.mps` model XML,
not the prose.

**Family and fit.** It belongs in the **execution** family, beside OpenFisca.

- **Where it matches L4.** It is the closest numeric match after Catala: "in basis alleen maar
  rationele getallen" (in principle only rational numbers), with exact division
  **[E, spec p.65 fn.19; typeringen v2.3.0 p.13]**. Its dated `regelversie` (rule version) is L4's
  rule-version axis.
- **Where it exceeds L4.** It has first-class time-varying attributes, units, mandatory rounding and
  built-in distribution. That is evidence flowing target→L4, as Catala and Blawx supplied for
  defeasibility.
- **What it lacks.** It has no regulative layer and no exception or priority construct.
- **Where it is dangerous.** Its per-operator empty-value tables make naive `MAYBE` lowering a silent
  miscompile.

**Import is what a Dutch government customer would more plausibly pay for,** because ALEF projects
carry expert-authored test sets that act as an independent oracle. But no production corpus is
public (§G).

## B. What RegelSpraak actually is

**History** **[E, spec v2.3.0 §2.1 pp.8–9]**. SBVR and RuleSpeak were tried first and found "niet
strikt genoeg" (not strict enough), so "eind 2009 RegelSpraak geboren" (RegelSpraak was born at the
end of 2009). The first tooling was RuleXpress plus an in-house ANTLR/Eclipse compiler. In 2010 the
income-tax pre-check rules were converted, and 2011/12 brought the "Wendbare Wetsuitvoering" (agile
law execution) vision. A 2015 proof of concept on the Zorgverzekeringswet (Health Insurance Act)
produced the first ALEF, which "met de codegenerator omgezet in Blaze-rules" (converted the rules
into Blaze rules with its code generator). The income-tax calculation service, built wholly in ALEF,
has run in production since 2019. Since then RegelSpraak has spread to "InkomensHeffing,
LoonHeffing, Inning, Toeslagen, Schenk- en Erfbelasting, Milieubelasting" (income tax, payroll tax,
collection, benefits, gift and inheritance tax, environmental tax).

The CNL 2021 paper (Corsius et al.) dates the RuleXpress exploration to 2007. It reports 2300+ Excel
rules semi-automatically converted, and calls the result "a robust and scalable infrastructure which
to our knowledge has no precedent" **[E, pp.2–6]**. The JetBrains MPS case study (undated; it cites
a 2018 meetup) gives about 6M returns a year and says "ALEF generates code for the FICO Blaze rule
engine … deployed as a decision service on the Mainframe" **[E, pp.1–2]**.

**Premise correction: Blaze, not Blueriq.** No primary source read here links RegelSpraak or ALEF to
Blueriq. Blueriq is a separate commercial platform with its own method page on regels.overheid.nl
**[E, `MinBZK/regels.overheid.nl` `…/methods/BLUERIQ.md`]**. A search summary asserting an
"alignment" between them was the summariser's inference, not a source. The historical engine is
**FICO Blaze Advisor**. The public ALEF tree has no Blaze generator (grep over `languages/`).
Instead it generates **Java** over its own `merlin` runtime (MPS baseLanguage templates in
`languages/merlin*/generator`) and service contracts (`serviceNaarOpenApi`, `serviceNaarWsdl`,
`serviceNaarXsd`) **[E]**. A test model titled "Zonder tijdzones (alleen Blaze)" (without time
zones, Blaze only) **[E]** suggests that Blaze survives internally **[U]**.

**GegevensSpraak is real, and it is the data half.** "Met GegevensSpraak leg je vast met welke
gegevens gerekend wordt" (with GegevensSpraak you record which data is calculated with) **[E,
p.8]**. Chapter 3 covers object types (animate or inanimate, which decides the pronoun "hij/zijn",
he/his), attributes, `kenmerken` (characteristics), domains, dimensions, units and unit systems,
timelines, parameters, fact types with roles, and day types.

**The spec defines itself by the implementation.** It calls itself "gebaseerd op de implementatie in
ALEF" (based on the implementation in ALEF) and pins an ALEF version to each spec version (v2.3.0 ↔
13.5.0) **[E, pp.6–8]**. Public ALEF is at v14.8.0 (2026-08-11), so the spec lags by a major version
**[E, git tags]**. A 2022 HAN study sketched big-step semantics for four concepts. It concluded that
a faithful spec "erg veel kennis van de werking van ALEF vereist" (requires a great deal of
knowledge of how ALEF works) **[E, Hofmans p.29]**. No complete formal semantics exists.

**Governance and licence.** Spec versions 1.00 (2023-05-01) through 2.3.0 are published on the
Wendbare Wetsuitvoering Pleio community as three PDFs: the main spec, `typeringen` (typing,
empty-value and precision tables) and `syntaxdiagrammen` (syntax diagrams). The contact address is
`RegelSpraak@belastingdienst.nl` **[E, Pleio page `291f5846…`, updated 2025-12-04]**. All three PDFs
are © Belastingdienst, all rights reserved. We cite them and never vendor them or their EBNF. That
the EU treats a language's functionality as uncopyrightable (SAS v WPL, C-406/10) is recalled, not
re-read **[U]**, and is not legal advice.

ALEF is EUPL-1.2 with Apache, EPL and MIT third-party parts. It has 64 public commits squashed from
an internal history whose issue keys reach ALEF4844, 10 authors, 28 stars, 11 forks and 43 open
issues, and it needs JDK 17+ (CI uses 21) and MPS 2025.1 **[E]**.

**Premise correction: other users.** No evidence was found for UWV, DUO or SVB. The one documented
outside user is **Virtueel Inkomstenloket (VIL)**, run by the municipalities of Utrecht, Amersfoort,
Buren and Eindhoven. It is described as "de eerste die deze informatie gebruikt, buiten de
Belastingdienst zelf" (the first to use this outside the Belastingdienst itself) **[E,
`…/Virtueel-Inkomstenloket/01-Introductie.md` @ `8c6aa0a`]**. VIL published two ALEF-rendered
regulations (Utrecht's valid from 2021) and a demo SOAP service, which did not respond on 2026-09-24
**[E]**. "Toeslagen" (benefits) is listed as a domain _inside_ the Belastingdienst (spec p.9).

**Premise correction: rule kinds.** The result-part actions are nine **[E, p.101]**:
`Gelijkstelling` (equate), `Kenmerktoekenning` (assign a characteristic), `ObjectCreatie` (create an
object), `FeitCreatie` (create a fact), `Consistentieregel` (consistency rule), `Initialisatie`
(initialise), `Verdeling` (distribute), `Dagsoortdefinitie` (define a day type) and
`Startpuntbepaling` (set a start point; new in v2.3.0). `Beslistabel` (decision table) is **not** a
rule kind. It is "een presentatievorm om gelijkstellingen op te nemen" (a presentation form for
equations), limited to equations and characteristic assignments, with AND-only conditions **[E, spec
ch.12; ALEF `docs/regels/Beslistabel.md`]**.

**Execution and tests.** Rules are declarative, and non-declarative flows are **deprecated** **[E,
ALEF `docs/besturing/flow.md`]**. Cycles are errors, except in a rule group marked recursive, which
needs an object-creation rule bounded by a value limit and an iteration cap (§9.10) **[E]**. Within
a rule, conditions are checked left to right before the variables that need them, so "een eventuele
deling door 0 wordt voorkomen" (a possible division by zero is prevented) (§11.1 p.120) **[E]**.

Tests are an **ALEF** construct (Testspraak), absent from the spec's table of contents. A `Testset`
has a validity period and one test date per year. A `Testgeval` (test case) pairs "de volgende
situatie:" (the following situation) with "moet het volgende resultaat hebben:" (must have the
following result). There are coverage reports, and a per-value "?" opens the fired rule with its
concrete inputs **[E, ALEF `docs/testen/*`, `docs/quick-start.md`]**.

## C. Worked examples (verbatim, primary sources)

Whitespace is normalised from PDF extraction; the wording is unaltered. Glosses are mine.

**A rule with a variable part** (spec §4.4 p.41, from the TOKA case, the spec's fictional running
example) **[E]**:

```
Parameter de volwassenleeftijd : Numeriek met eenheid jaren
Regel Kenmerktoekenning persoon minderjarig
  geldig altijd
    Een Natuurlijk persoon is minderjarig
    indien X kleiner is dan de volwassenleeftijd.
    Daarbij geldt:
      X is de tijdsduur van zijn geboortedatum tot de datum van de vlucht in hele jaren.
```

_Gloss:_ a natural person is _minor_ if X < the adult-age parameter, where X is the time from their
birth date to the flight date, in whole years. In L4 this is a `DECIDE … IF … WHERE`. The unit
`jaren` (years) has no L4 counterpart.

**A production income-tax rule** (Eerste Kamer annex "Voorbeeld van een Regelspraak-regel", dated
2021-10-12 by its URL; the rule is an embedded image, transcribed here) **[E]**:

```
Regel vermoedelijk onroerende zaken of rechten op onroerende zaken in Nederland 01VJ
  geldig vanaf 1-1-2018
    Een natuurlijke persoon heeft vermoedelijk onroerende zaken of rechten op onroerende zaken in Nederland
    indien hij aan alle volgende voorwaarden voldoet:
    • hij is een buitenlandse belastingplichtige IB
    • hij voldoet aan ten minste één van de volgende voorwaarden:
        •• zijn waarde in Nederland gelegen onroerende zaken over het vorige belastingjaar is groter dan 0
        •• zijn waarde rechten op in Nederland gelegen onroerende zaken over het vorige belastingjaar is groter dan 0
```

_Gloss:_ a foreign income-tax payer is presumed to hold Dutch real estate, or rights to it, if
either of last year's values exceeds 0. The annex grounds this in art. 6 AWR, the inspector's
discretion to invite a return. It stresses that the rule is "preciezer dan in de onderliggende
documenten" (more precise than the underlying documents) about which conditions are cumulative and
which alternative. That is the ambiguity-resolution role L4 claims for itself. The bullet depth
(`•`/`••`) is the AND/OR tree, the same shape as an L4 ladder.

**A real municipal regulation, kept disjoint by hand** (Utrecht Individuele Inkomenstoeslag, ALEF
HTML report on `commonground.gitlab.io`, rules 01 and 06 of 8+; one elision marked) **[E]**:

```
Regel Uit te keren toeslag bedrag 01
  Bronnen: … Beleidsregel Individuele Inkomenstoeslag gemeente Utrecht
  geldig vanaf 2021
  Het Uit te keren individuele inkomenstoeslag van een Aanvraag moet gesteld worden op 51
  indien aan alle volgende voorwaarden wordt voldaan:
  • de Aanvraag heeft Aanvrager die woonachtig is in Utrecht
  • de AOW leeftijd behaald is gelijk aan onwaar
  • …   [three further equality conditions and an income ceiling, elided here]
  • het Vermogen is kleiner of gelijk aan de BOVENGRENS_VERMOGEN_HOOG .
Regel Uit te keren toeslag bedrag 06
  geldig vanaf 2021
  Het Uit te keren individuele inkomenstoeslag van een Aanvraag moet gesteld worden op 0
  indien de AOW leeftijd behaald gelijk is aan waar .
```

_Gloss:_ the supplement is €51 for this profile and €0 once state-pension age is reached. The
`Bronnen` (sources) line plays the role of our `@ref`. Nothing orders these rules, so the author
keeps them disjoint by hand. That is I7's problem, shown in public.

## D. Stratum-by-stratum overlap

| L4 stratum                                         | RegelSpraak construct                                                                                                                                                                                                                                                                                 | Verdict                                                  |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| Records `DECLARE … HAS`                            | `Objecttype` with typed attributes; relations as `Feittype`s with roles, navigated as "zijn reis" (his trip)                                                                                                                                                                                          | **CLEAN** (flat); nesting **EMULATED**                   |
| Enums `IS ONE OF`                                  | `Domein` over an enumeration (`'Friesland'`, …)                                                                                                                                                                                                                                                       | **CLEAN**, payload-free only                             |
| `BOOLEAN` predicates                               | `kenmerk` via `Kenmerktoekenning` (is een / heeft / is); Boolean attributes                                                                                                                                                                                                                           | **CLEAN**                                                |
| `GIVEN`/`GIVETH`/`DECIDE`/`MEANS`                  | `Gelijkstelling` assigns an _attribute of an object_ ("De X van een Y moet berekend worden als …"); no parameterised functions                                                                                                                                                                        | **RESTRICTED** (entity-bound, OpenFisca-shaped)          |
| `CONSIDER`/`BRANCH`/`IF`                           | Separate rules with `indien` (if) guards, or decision-table rows (AND-only); no first-match, no priority                                                                                                                                                                                              | **RESTRICTED**; I7 disjointness proof required           |
| `NUMBER` (exact rational)                          | Numeriek is a whole number, N decimals, or "getal" (number); rationals only; exact division; five rounding modes; rounding **mandatory** before assigning to fewer decimals                                                                                                                           | **CLEAN**, best match after Catala                       |
| (none)                                             | Unit systems with automatic conversion (`km`, `jr`, `€ per maand`); `Percentage`                                                                                                                                                                                                                      | **TARGET-RICHER**                                        |
| `DATE`                                             | Datum-tijd at day or ms granularity; `tijdsduur van … tot …` (duration from … to …); `jaar uit` (year of); `Dagsoort` (day type, e.g. working day); `eerste paasdag` (Easter Sunday)                                                                                                                  | **CLEAN**; target richer; I9 applies                     |
| `MAYBE`                                            | `leegwaarde` (empty value) with **per-operator** tables: `plus`/`min`/`maal` treat empty as 0; `verminderd met` (reduced by) with an empty left side gives empty; X ÷ empty is an Error but empty ÷ empty is 0; empty in a date comparison gives `onwaar` (false), and both empty give `fout` (error) | **HAZARD**: naive lowering is a silent miscompile        |
| `LIST` + prelude aggregations                      | `som van` (sum), `aantal` (count), `minimale/maximale waarde van` (min/max), `eerste/laatste van` (first/last) over role-reachable instances; `alle` / `ten minste één` (all / at least one); sub-selection                                                                                           | **CLEAN** over object sets; scalar lists restricted      |
| Recursion, higher-order                            | Cycles forbidden; recursion only in a group marked recursive, bounded by object creation and an iteration cap                                                                                                                                                                                         | **OUT** (bounded emulation only)                         |
| Rule versions (`EVAL … UNDER RULES EFFECTIVE AT`)  | `regelversie` `geldig vanaf … t/m …` (valid from … up to and including …), non-overlapping, selected by the `rekendatum` (calculation date)                                                                                                                                                           | **CLEAN**; same shape as OpenFisca's dated formulas      |
| Valid time (`VALUE AT`, `EVER`/`ALWAYS BETWEEN`)   | First-class per-attribute `tijdlijnen` (timelines); pointwise lifting at `knips` (cut points); `tijdsevenredig deel` (time-proportional share); `gedurende de tijd dat` (during the time that); `gedurende het gehele jaar` (for the whole year)                                                      | **TARGET-RICHER**: evidence for L4's TEMPORAL series     |
| `PARTY … MUST/MAY/SHANT`, `WITHIN`, `HENCE`/`LEST` | None. "moet" means compute ("moet berekend worden") or validate ("moet ongelijk zijn"), never an obligation                                                                                                                                                                                           | **OUT**                                                  |
| Defeasibility (`SUBJECT TO`, spec-only)            | No override construct. Only the rule predicates `regelversie … is gevuurd` (has fired) / `is inconsistent`, plus `Initialisatie` as a fallback when a value is still empty (§9.6)                                                                                                                     | **OUT**: a fifth SUBJECT-TO datapoint, the negative case |
| `TYPICALLY`                                        | `Initialisatie` is an _operative_ fallback, not metadata-only prefill                                                                                                                                                                                                                                 | **DIFFERENT CONCEPT**                                    |
| `#EVAL`/`#ASSERT`, `#TRACE`                        | ALEF `Testset`/`Testgeval` with a calculation date, forced parameters and coverage; an executed-rule list with inline values                                                                                                                                                                          | **CLEAN** / **PARTIAL** (tooling, not language)          |
| `@ref`                                             | Per-rule `Bronnen` (sources) links; upstream annotation via Wetsanalyse                                                                                                                                                                                                                               | **CLEAN**                                                |
| (none)                                             | `Consistentieregel` (input validation, uniqueness); `ObjectCreatie`/`FeitCreatie`; `Verdeling` (ranking, pro rata, caps, remainder)                                                                                                                                                                   | **OUT / EMULATED** (library functions)                   |
| Effects/ledger                                     | None                                                                                                                                                                                                                                                                                                  | **OUT**                                                  |

## E. Family placement

**Execution, beside OpenFisca.** Both assign derived attributes to entities ("De X van een Y"), both
select dated rule versions by a calculation date, and both feed mass-calculation services.
`BACKEND-PORTFOLIO-SPEC.md` §2.1 calls OpenFisca "the only backend … that consumes the temporal layer
today". RegelSpraak would be the second, and it is richer in time than either. A text export that no
engine runs would be a documentation-family artifact (§F).

## F. Toolchain and oracle (I2/I3)

| candidate engine                                | open?                                                                                                                               | runs what                                                                                                                                                                        | oracle?                                                                                                                                         |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **ALEF** headless project build                 | **yes**, EUPL-1.2                                                                                                                   | an ALEF project (`.mps`) via `scripts/build-alef-project.sh` → `alefProjectBuild.jar`: build, generate Java service (Maven), run service tests, JUnit report **[E, `App.java`]** | **in principle.** Needs MPS 2025.1 + JDK 17+ + Maven. ALEF's own CI uses `xvfb-run` **[E]**; whether a project build needs a display is **[U]** |
| ALEF in-IDE interpreter                         | yes                                                                                                                                 | test sets, interactively (`solutions/interpreter.runtime`)                                                                                                                       | no (GUI)                                                                                                                                        |
| `igochkov/vscode-regelspraak` language server   | **no.** The client is Apache-2.0, but the server is "proprietary … licensed for use only as part of this extension" **[E, NOTICE]** | textual `.rgs` + `*.test.rgs`; single author (per NOTICE); created 2026-08-06; dialect extended past v2.3.0 (`Regelgroep`, `Gegevensbron`); has an ALEF importer                 | **no**; a second opinion at most                                                                                                                |
| `MinBZK/NRML` `transformations/regelspraak.xsl` | yes, EUPL-1.2                                                                                                                       | _generates_ RegelSpraak text from NRML JSON; executes nothing; dormant since 2025-10-07 **[E]**                                                                                  | no; prior art for a text emitter                                                                                                                |
| VIL demo SOAP service (`open-regels.nl:8443`)   | n/a                                                                                                                                 | two municipal rule sets                                                                                                                                                          | no; did not respond on 2026-09-24 **[E]**                                                                                                       |

**Text export stops at the golden tier.** Textual export following the v2.3.0 EBNF can only reach the
golden tier, like yscript and LegalRuleML, because no open engine parses RegelSpraak text. ALEF itself
imports CSV only "als commentaar" (as comments)
**[E, `languages/regelspraak/languageModels/plugin.mps`]**.

**The executed round-trip needs an `--alef` mode.** It would emit MPS persistence-v9 models for the
object model, the rule groups, and test sets whose expected values come from `L4.EvaluateLazy` (I2),
never from ALEF's own run. It would then build them headlessly.

- **Tractable:** every `.mps` carries a self-describing registry mapping concept IDs to names. I
  enumerated 151 `regelspraak`, 20 `regelspraak.tijd`, 12 `gegevensspraak.tijd` and 31
  `beslistabelspraak` concepts **[E]**.
- **Brittle:** the format is bound to a pinned ALEF release and its migrations.

**Import can be checked against something independent.** An ALEF project's own expert-authored test
sets give import a route to the **law-validated** tier, which the golden-only candidates (yscript,
LegalRuleML) lack.

## G. Direction: which way would a customer pay for?

**Export (L4 → RegelSpraak)** is modest. The Belastingdienst will not switch authoring languages: it
has 15 years, an MDSE competence centre, Wetsanalyse training and production services behind
RegelSpraak. The buyers would be _adopters_ of its method, such as VIL municipalities or ICTU
projects, wanting L4-authored rules delivered as an ALEF project that yields a SOAP/OpenAPI decision
service. Export also carries a surface cost. RegelSpraak names are Dutch noun phrases with articles,
plurals `(mv: …)` and pronouns that depend on animacy. An English L4 source would need a Dutch
lexicon layer, the same dependency as our `@nlg` work, or it would produce Dutch-shaped English
(I5).

**Import (ALEF project → L4)** is more valuable. L4 adds disjointness and coverage checking of
priority-free rule sets (ROBDD, the verification family). It adds the regulative wrapper RegelSpraak
lacks: filing and payment deadlines, and art. 6 AWR's may-invite power. And it gives one-hop export
to OpenFisca, DMN, docassemble and Catala for partner agencies.

**The blocker is data.** The production corpus (income tax, payroll tax, Toeslagen, …) was not found
published. What is public is small: the spec's fictional TOKA case (all rights reserved), ALEF's 26
`*_Test` solutions (EUPL; good parser fixtures), two VIL regulations as HTML only, and a third-party
dialect rendering of the Minimum Wage Act in 27 notebooks. So a real engagement presupposes a
customer handing over its ALEF projects.

## H. Feasibility sketch, CLI, and census row

If pursued, sequence the work in three steps.

1. **Import from `.mps`.** Start with ALEF's feature-test solutions. Each ALEF test set becomes L4
   `#ASSERT`s, so the import is judged by expectations authored outside L4.
2. **Textual export (golden tier)** of the constitutive core. That means records, payload-free enums
   and attribute equations. It means `regelversie`s derived from year-guarded `BRANCH`, reusing the
   OpenFisca dated-formula lowering. And it means exact numbers with explicit precision and
   rounding.
3. **`--alef` export** for the executed round-trip, once a headless ALEF project build is shown to
   work. Per I4 it skips silently when absent.

**Refuse, loudly:** a `MAYBE` reaching any operator whose empty-value table departs from L4's;
`CONSIDER`/`BRANCH` without a disjointness proof (I7); anything regulative; parameterised functions
that cannot be bound to an entity; higher-order code; and, on import, `ObjectCreatie`, `FeitCreatie`
and `Verdeling` until L4 states an encoding for them. Timelines on import need a ruling the TEMPORAL
series has not made: lower them to `DATE → a`, or refuse them.

**CLI.** The CLI is being restructured so that every transpiler target is `l4 export FORMAT`, and
this proposal follows that convention:

```
l4 export regelspraak FILE [--output DIR] [--alef DIR]   # text (golden); --alef: ALEF project for the headless oracle
l4 import regelspraak PATH                               # PATH = ALEF project/solution dir (.mps); text import deferred
```

**Proposed census row: `BACKEND-PORTFOLIO-SPEC.md` §2.1 Execution**, in that table's
`| target | state | owning artifact |` format:

```
| RegelSpraak / ALEF (Belastingdienst) | **FUTURE** — researched 2026-09-24; verdict: an operational Dutch CNL for executable tax rules (Belastingdienst since 2009; income-tax calculation service in production since 2019) whose toolchain ALEF went open source (EUPL-1.2) on 2026-05-29 while the language spec (v2.3.0, 2025-12-04) remains "alle rechten voorbehouden". Closest numeric match after Catala (rationals only, exact division); dated `regelversie`s match L4's rule-version axis; first-class timelines, units and mandatory rounding exceed L4 (evidence flowing target→L4). No regulative layer, no override construct, per-operator empty-value semantics a `MAYBE` miscompile hazard. Executed round-trip reachable in principle only via ALEF's MPS model format and headless build, not via the CNL text; import (ALEF project → L4, judged against its own expert test sets) is the more valuable direction, but no production corpus is public **[E]** | `specs/research/REGELSPRAAK-RESEARCH.md` |
```

## I. Related Dutch ecosystem

**Wetsanalyse / JAS.** The Ausems, Bulles & Lokin method (Boom), built on its "juridisch
analyseschema" (legal analysis scheme). The abbreviation "JAS" is not in the source read here
**[U]**. It is step 1 of Wendbare Wetsuitvoering, and RegelSpraak/ALEF is step 2 **[E, ALEF
`docs/achtergrondinformatie`; regels.overheid.nl `WETSANALYSE.md`]**. Lokin (Ministry of Finance)
co-authored the CNL 2021 paper.

**FLINT.** An act/fact/duty interpretation method. Its register page says two things of note
**[E, `flint/methodebeschrijving/04-PERSPECTIEF.md`]**:

- Both "de wetsanalyse aanpak van de Belastingdienst" (the Belastingdienst's Wetsanalyse approach)
  and "het norm engineering programma van TNO" (TNO's norm engineering programme) build on this line
  of work. The page also links a TNO-hosted norm editor.
- RegelSpraak is "een poging om regels op een meer formele manier vast te leggen" (an attempt to
  record rules more formally), but a shared government standard "tot nu toe … niet gelukt" (has not
  yet been achieved).

eFLINT is already cited in `SUBJECT-TO-NOTWITHSTANDING-SPEC.md`.

**regels.overheid.nl (MinBZK).** A method register listing RegelSpraak, ALEF, Wetsanalyse, FLINT,
Blueriq, OpenFisca and others. It was read via its GitHub monorepo, because the site failed DNS from
this sandbox **[E]**.

**RegelRecht (MinBZK).** EUPL; a Rust engine over a YAML law format; 30+ laws; very active. Its
RFC-011 (Accepted, 2025-11-05) rates "Regelspraak / RuleSpeak (Adoption: Low)" as an execution
language, and Catala "Low" too **[E]**. So BZK's machine-law effort chose _not_ to build on
RegelSpraak. That leaves a second Dutch format, with L4-as-hub between the two an open question.

**NRML (MinBZK).** "Datalog met JSON syntax" (Datalog with JSON syntax), which calls itself
RegelSpraak's "complementaire inverse" (complementary inverse). It has a RegelSpraak text XSLT and a
TOKA encoding, and has been dormant since 2025-10-07 **[E]**.

**RegelspraakEN.** `diederikd/RegelspraakEN` is an "English version of Regelspraak" as an MPS
language, last pushed 2023-05-15, with 0 stars. It is known from GitHub metadata only **[U]**.

**Premise correction: Catala POC.** None was found. No source links Catala to the Belastingdienst or
RegelSpraak; the only Catala mention in this ecosystem is RegelRecht's "Low" rating.

## J. Open questions

1. **Conflicting assignments.** What does ALEF do when two non-`Initialisatie` rules assign the same
   attribute of one instance? The spec text, as searched, is silent. The third-party engine labels
   values `eindwaarde`/`overschreven` (final / overwritten), which implies last-write-wins **[E,
   README]**. ALEF's own behaviour is **[U]**, and it decides whether the I7 lowering is sound.
2. **Headless build and binaries.** Does `build-alef-project.sh` run without a display, and how fast
   is a minimal project? It gates tier 2, and nobody has run it. `release.yml` uploads artifacts, but
   the releases API was unreachable from here **[U]**; tags v14.5.0–v14.8.0 exist **[E]**.
3. **Units and timelines in L4.** Should L4 grow them? Route that evidence to `DATE-LIBRARY-SPEC.md`
   and the TEMPORAL series.
4. **Corpus access.** Would the Belastingdienst, ICTU/VIL or a partner agency share ALEF projects
   for an import pilot? The answer decides whether import is research or product.
5. **Spec licence.** Could the spec be opened for a conformance suite? Until then, emitters cite it
   and never copy it.

## K. Sources

**Primary, read directly [E]:** _RegelSpraak-specificatie_ v2.3.0 (Belastingdienst, 4-12-2025, 149
pp.) with the _typeringen_ annex v2.3.0 (38 pp.) and v1.2.0 (2024-04-11), at
`wendbarewetsuitvoering.pleio.nl/attachment/entity/{3c7995d6…, c6738c40…, 87fba6cb…}`; the Pleio
pages "Specificaties RegelSpraak" and "Historie van RegelSpraak" (read via the site's GraphQL API);
Corsius, Hoppenbrouwers, Lokin, Baars, Sangers-van Cappellen & Wilmont, "RegelSpraak: a CNL for
Executable Tax Rules Specification", CNL 2021, `aclanthology.org/2021.cnl-1.6.pdf` (7 pp., figures
read as images); the Eerste Kamer annex
`eerstekamer.nl/overig/20211012/voorbeeld_van_een_regelspraak/…`; the JetBrains "MPSQuest DTO Case
Study"; Hofmans, HAN (2022); the repositories `belastingdienst/ALEF` @ `31bbe71` (README, NOTICE,
`docs/**`, `AlefJava/`, `scripts/`, workflows, structure models), `igochkov/vscode-regelspraak` @
`a18e0ae`, `MinBZK/regels.overheid.nl` @ `8c6aa0a`, `MinBZK/NRML` @ `40ba02a` and
`MinBZK/regelrecht` @ `996e766`; and the VIL reports at
`commonground.gitlab.io/virtueel-inkomstenloket/regels/`.

**[E via fetch]:** Belastingdienst, "Zo kunnen we onze beslissingen beter uitleggen" (2024-04-18).

**[U]:** search summaries pairing Blueriq with RegelSpraak; whether Blaze is still in production;
whether an ALEF project build needs a display; the EU copyright point; the Eerste Kamer annex's
parent document; whether VIL's `.mps` sources are published; and CNL 2021 papers 1.9 and 1.13.

**Related work in this repo:** `BACKEND-PORTFOLIO-SPEC.md` §§1.1 and 2.1 and I2/I3/I5/I7/I8/I9;
`DATALEX-YSCRIPT-RESEARCH.md` and `LEGALRULEML-RESEARCH.md` (the golden-only precedents);
`SUBJECT-TO-NOTWITHSTANDING-SPEC.md`; `DATE-LIBRARY-SPEC.md` and `TEMPORAL-RULE-VERSION-DESIGN.md`.
