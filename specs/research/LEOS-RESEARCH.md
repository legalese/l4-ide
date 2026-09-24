# L4 TNR → LEOS: can the legislative rendering feed the EU's drafting editor?

_Status: **research memo, complete; nothing built.** Commissioned 2026-09-24 by Meng, who asked
whether LEOS — the European Commission's "Legislation Editing Open Software" — is something the
TNR NLG could be connected to, and to backlog it. Written 2026-09-24 against `unstable` @
`7df7a3ca`. Evidence marks follow `DATALEX-YSCRIPT-RESEARCH.md`: **[E]** = primary source read
directly in this session, or a command executed in it; **[E via fetch]** = a web page summarised
by the fetch tool's own model, not re-quoted; **[U]** = secondary (search snippet, memory, or
unchecked inference). LEOS facts come mostly from its own source: `code.europa.eu/leos/core`,
branch `development`, HEAD `28a66b28` (2026-09-23), shallow-cloned (`leos:` paths below). L4 AKN
output was produced by the `l4` binary shipped in the `l4-ide-build-90` VSIX (2026-08-07) over the
corpus at that build's commit `8917dc3f`. Its `renderAkn` differs from `unstable`'s only in the
FRBR language literal and one deontic preposition; `anchorOf` and `uniqueId` are byte-identical
(diffed) **[E]**._

---

## A. Verdict

**Yes, possible, but not directly and not yet worth building. Backlog as FUTURE, and do the one
cheap thing now that pays off whatever happens next.**

- **LEOS is real and active.** It is open source (EUPL-1.2), maintained by DIGIT, and on 5.x
  (5.4.2 released 2026-07-10, 5.7.0 on `development`), with a documented 198-operation REST API
  **[E]**. The premise's "LEOS 4?" is out of date.
- **LEOS does not import arbitrary Akoma Ntoso.** It edits its own AKN4EU-flavoured profile of EU
  acts, and identifies a document by the first child of `<akomaNtoso>`. Only `<bill>`,
  `<coverPage>` or a `<doc name=…>` from a closed list is accepted. L4 emits `<act name="act">`,
  which falls through (`leos:…/XmlContentProcessorImpl.java:3149-3174`) **[E, code read; not run
  against a live LEOS]**.
- **L4's AKN is not valid even as plain OASIS AKN 3.0 today.** Measured over 169 corpus renders:
  none validates. With two missing metadata elements added, 153 validate, including all 7
  `legal/` files; the other 16 have an empty `<body>` (§D). The structure is already valid.
- **The gap has two layers of very different size.**
  - _Syntax_ is small to medium: schema validity, then the LEOS profile (`bill` root, `xml:id`
    everywhere, a `leos:` metadata block, article/paragraph/point structure).
  - _Jurisdiction_ is large. EU acts are articles plus citations, recitals ("Whereas:") and
    formulae. The TNR spec targets Commonwealth/Singapore style (`NLG-TNR-ROUNDTRIP-SPEC.md`
    §2.1), and no corpus file is an EU act. That is a drafting dialect (§2.8), not an XML fix.
- **LEOS Light suits the round trip.** An external system POSTs one document to
  `/secured/leos-light/import-document` with a `callbackAddress`, a drafter edits it, and LEOS
  POSTs it back **[E]**. The edits arrive marked `leos:softaction="add|del|move_to|…"` with user
  and date **[E]**: TNR §3.3's edit classification, half-done by the editor.
- **Recommended order.** (1) Now: make the AKN schema-valid, move it to `l4 export akn`, and gate
  it with `xmllint` against the OASIS XSD; hours. (2) FUTURE: `l4 export akn4eu` for LEOS Light,
  spiked against a local LEOS only when a partner with a LEOS instance asks. (3) Then
  `l4 import akn4eu --against` as the lens `put`.
- **Cheaper host for a demo.** To show the lens through a real AKN editor sooner, Laws.Africa's
  **Indigo** (AKN-native, LGPL, active, takes AKN XML uploads verbatim) has lower friction (§G).
- **No precedent found.** No rules-as-code or NLG tool is known to feed LEOS; the nearest
  precedents are LEOS's own AI add-ons (§C.4).

## B. What LEOS is

- **Identity.** "LEOS (Legislation Editing Open Software) is a software designed to address the
  need of the public administrations and European Institutions to generate draft legislation in a
  legal XML format" (`leos:RELEASE-NOTES.txt`) **[E]**.
- **Governance.** Lineage runs ISA Action 1.13 → ISA² Action 2016.38 "LegIT" → Digital Europe
  Programme under Interoperable Europe. `publiccode.yml` gives `maintenance.contacts: DIGIT LEOS
team`, `mainCopyrightOwner: European Commission`, `usedBy: European Commission` **[E]**. The
  ISA² fact sheet names "Service in charge SG.A1" (Secretariat-General) **[U, snippet]**. The
  premise's "DIGIT / ISA² / Interoperable Europe" is right in substance.
- **Licence.** `EUPL-1.2`, on core and on `leos/annotate` **[E]**.
- **Versions.** Releases run 1.0.0 (2017-11-14) → 4.0.0 (2023-05-02) → 5.0.0 (2023-12-12) →
  **5.4.2 (2026-07-10), "Compatible with Annotate 5.3.\*, AKN4EU 5.0.0"** **[E via fetch]**.
  `development` says "Release: 5.7.0" **[E]**. The EU Vocabularies dataset lists AKN4EU up to
  5.0.1.0 **[E via fetch]**.
- **Stack.** Java 21 and Maven 3.9.9, Spring 7.0.9, an Angular 21 front end, CKEditor, and a CMIS
  (OpenCMIS) repository. Annotations run as a separate EUPL service, `leos/annotate` **[E]**.
- **Deployment.** Self-hosted: the shipped build "is adapted to run on a local server for demo
  purposes and without proper security mechanisms" (`README.txt`), and the context path is still
  `leos-pilot` **[E]**.
- **Adopters, each checked.** European Commission: in use; the 2023 target was "LEOS for all
  acts in the European Commission by 2025" **[E via fetch]**, and whether it was met is **[U]**.
  Spain: confirmed, a fork "created and maintained by Ministry of Presidency, Justice and Relation
  with the Courts. Spanish Government" at `leos/project-mode/leos-spain`, last commit 2025-08-14
  **[E]**. EDPB: a `leos/project-mode/edpb` subgroup exists; its contents are **[U]**. Greece:
  "willing to experiment" **[U, snippet]**. Italy: only an AI use case (the transposition of the
  maritime spatial planning directive), not an adopter **[E via fetch]**. Estonia: nothing found
  **[U]**.

## C. The format, and what LEOS actually accepts

**C.1 AKN4EU.** AKN4EU is the IMFC's (Interinstitutional Metadata and Formats Committee, since 2018) profile of OASIS AKN. It covers "legal acts adopted through the ordinary legislative
procedure (regulations, directives and decisions), as well as the respective legislative
proposals", and "marks work in progress and has not been fully implemented yet" (op.europa.eu)
**[E via fetch]**.

The AKN4EU documentation Vol. I (Draft 3.0, 2020-03-06, from Cellar) was read directly **[E]**.
It corrects a premise of this commission in three places:

1. **The technical identifier is `xml:id`, not `eId`/`GUID`.** "A 'technical reference' is based
   on the xml:id attribute (the AKN4EU technical identifier)" (§4.4). Structural references are
   ELI URIs.
2. **A document is a `.leg` zip:** "main.xml: the documentCollection …; memorandum\_<id>.xml;
   bill\_<id>.xml; annex\_<id>.xml" (§6.4).
3. **Proposals are `bill`, acts are `act`, and the memorandum is a `doc`.**

The 5.x schema was not obtained; it sits behind a JS "Downloads" tab **[U for 5.x]**. LEOS 5.x
code agrees on all three points.

**C.2 What LEOS validates against.** `AkomantosoXsdValidator` loads a **pre-OASIS "Release
30/03/2017 – Akoma Ntoso 3.0"** XSD: 8,114 lines, against 6,862 in the OASIS 2018 schema **[E]**.
AKN4EU conformance comes from templates plus a structure config rather than a second schema. That
config permits `preface preamble citations citation recitals recital body part title chapter
section article paragraph subparagraph point list clause conclusions heading`
(`structure_01.xml`) **[E]**. The real AKN4EU converter is an external service whose URL is blank
in the open-source config (`common.properties:94-103`) **[E]**; that it is EC-internal is **[U]**.

**C.3 A LEOS bill as it starts life**, verbatim from the regulation template
`docs/Document-templates-and-configuration/BL-023.xml` (trimmed) **[E]**:

```xml
<akomaNtoso xmlns="http://docs.oasis-open.org/legaldocml/ns/akn/3.0" xmlns:leos="urn:eu:europa:ec:leos" …>
    <bill name="REG">
        <meta>
            <identification source="~COM">
                <FRBRWork> … <FRBRcountry value="EU"/> <FRBRprescriptive value="true"/> </FRBRWork>
                <FRBRExpression> … <FRBRlanguage language="eng"/>
                    <preservation xmlns:akn4eu="http://imfc.europa.eu/akn4eu">
                        <akn4eu:akn4euVersion value="4.0.0.0"/> </preservation> </FRBRExpression>
            <references source="~COM">
                <TLCOrganization xml:id="COM" href="http://publications.europa.eu/resource/authority/corporate-body/COM" …/>
            <proprietary source="~_leos">
                <leos:templateVersion>2.0.0</leos:templateVersion> <leos:template>SJ-023</leos:template>
                <leos:docTemplate>BL-023</leos:docTemplate>
        …
        <body xml:id="body">
            <article xml:id="art_1" leos:editable="true" leos:deletable="true">
                <num xml:id="art_1__num" leos:editable="false">Article 1</num>
                <heading xml:id="art_1__heading">Scope</heading>
                <paragraph xml:id="art_1__para_1">
                    <num xml:id="art_1__para_1__num">1.</num>
                    <content xml:id="art_1__para_1__content"><p xml:id="art_1__para_1__content__p">Text...</p>
```

Template ids follow AKN naming-convention syntax. Ids minted later are random: `"ec"` plus 15
characters (`IdGenerator.java`) **[E]**.

**C.4 The ways in, all read from code** **[E]**:

| surface                                                                | takes                                                                                                                                                                                                                                                   | relevance to TNR                                                                                                                                                                              |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `POST /upload`, `/validateLegFile` (`ProposalApi.java:205-216`)        | a whole `.leg` proposal; no `main.xml` → `DOCUMENT_NOT_FOUND` (`ProposalConverterServiceImpl.java:97-161`)                                                                                                                                              | heaviest: a full proposal package                                                                                                                                                             |
| `POST /secured/leos-light/import-document` (`LeosLightApi.java:43-48`) | **one** XML document + `language` + optional `callbackAddress`; `leos:ref` read from metadata (`LeosLightApiServiceImpl.java:144-177`)                                                                                                                  | **the round-trip channel.** Export POSTs the edited file to the callback (`:180-216`). Client profiles `DGT_EDIT` and `DECIDE_EDIT` (`lightProfile.xsd`) show the EC already uses it this way |
| `PUT /{documentRef}/import-elements`, `importoj/`                      | Formex 4 found by ELI (`type/year/number`) via the Cellar SPARQL endpoint, XSLT'd to AKN, then **selected recitals/articles inserted into an existing bill**                                                                                            | the premise's "Formex/EUR-Lex import" is element-level import from the Official Journal, not a document importer                                                                              |
| AI add-ons                                                             | `leos/ai4drpm` (LLM pipelines filling the Legislative Financial and Digital Statement via `leos:aitarget` anchors); `LEOS-SmartFunctionalities/leos_4eu` (definition prompter, reference suggester, reporting-requirement classifier emitting RRMV RDF) | the nearest precedent for an external analysis tool writing into LEOS. None is rules-as-code or NLG                                                                                           |

**Does an imported `xml:id` survive import and editing?** Not established. New nodes get fresh ids,
and no id regeneration on the import path was found, but its absence was not proven **[U]**. It is
the first thing a spike must measure, because the anchor strategy rests on it.

## D. What L4 emits today, exactly

The emitter is `renderAkn` (`jl4-core/src/L4/Export/Render.hs:507-628`). It is reached from
`l4 render --format akn|xml` (`jl4/app/L4/Cli/Render.hs:63-72, 209`), from the LSP request
`l4/exportDocument` (`jl4-lsp/app/LSP/L4/Handlers.hs:937`), and so from the VS Code sidebar
(`ts-apps/vscode/src/sidebar-provider.ts:138,154`) **[E]**. It builds the XML by string
concatenation. What comes out:

- **Namespace and root.** OASIS AKN 3.0, `xmlns="http://docs.oasis-open.org/legaldocml/ns/akn/3.0"`,
  root `<act name="act">` (`:511-512`).
- **Metadata** (`:527-535`). Work, Expression and Manifestation each carry only `FRBRthis`,
  `FRBRuri`, `FRBRdate date="1970-01-01" name="generation"` and `FRBRauthor href="#l4"`.
  - The IRIs are `/akn/doc/main`, `/akn/doc/<lang>@` and `/akn/doc/<lang>@.xml`. They say `doc`
    under an `act` root, have no country, date or number, and write `main` where the naming
    convention writes `!main` (its example is `/akn/kn/act/2007-01-01/1/!main`, `akn-nc-v1.0-os`)
    **[E]**.
  - There is no `FRBRcountry`, no `FRBRlanguage` and no `<references>`, so `#l4` resolves to
    nothing.
- **Structure.** `<preface><longTitle><p>` holds the title (`:514`). `<body>` holds one
  `<section eId="sec_<n>"><num><heading>` per section (`:537-547`). Groups become
  `<hcontainer name="crossHeading">` (`:549-551`). Each declaration becomes
  `<paragraph eId="para_<anchor>"><heading><content>` (`:553-557`). Bodies use `<p>`,
  `<blockList>/<item>` and `<table>` (`:559-628`).
- **Identifiers.** `eId` only: no `wId`, no `GUID`. The `para_` anchor is
  `<sort>_<gensym>_<module-basename>` (`anchorOf`, `:666-673`, over `uniqueId`,
  `Document.hs:1514-1516`), so renaming the file renames every anchor.
- **Documentation and tests.**
  - `l4 render`'s one-line summary still reads `(html|text|json|plan)` (`jl4/app/Main.hs:107`),
    while `--format` help and `doc/tutorials/getting-started/l4-cli.md:273` do list `akn`. The
    "UNDOCUMENTED" note in `etc/go/phases/p7-akn.sh:5-7,79` is therefore half-stale.
  - Tests cover only the FRBR language (`jl4/tests-cli/Main.hs:1642-1666`,
    `jl4-core/test/RenderLangDirSpec.hs:84-108`). The go leg checks well-formedness only
    (`p7-akn.sh:51-62`) **[E]**.

Verbatim `l4 render alcohol-b90.l4 --format akn` (build-90 binary, `xmllint --format`, trimmed)
**[E]**:

```xml
<akomaNtoso xmlns="http://docs.oasis-open.org/legaldocml/ns/akn/3.0">
  <act name="act">
    <meta><identification source="#l4"><FRBRWork><FRBRthis value="/akn/doc/main"/><FRBRuri value="/akn/doc"/>
          <FRBRdate date="1970-01-01" name="generation"/><FRBRauthor href="#l4"/></FRBRWork> …
    <preface><longTitle><p>Imaginary Alcohol Act</p></longTitle></preface>
    <body> …
      <section eId="sec_2"><num>2</num><heading>Provisions</heading>
        <paragraph eId="para_c_14_alcohol-b90"><heading>The person must not sell alcohol</heading>
          <content><p>means all of the following are true:</p>
            <blockList><item><p>the person is a body corporate</p></item> …
              <item><p>the person is a public house is false</p></item> …
```

**Schema validity, measured** **[E]**. Against the OASIS XSD
(`docs.oasis-open.org/legaldocml/akn-core/v1.0/os/part2-specs/schemas/`),
`xmllint --noout --schema akomantoso30.xsd alcohol.akn.xml` gives exactly two errors:

```
element FRBRWork: … Missing child element(s). Expected is one of ( …FRBRauthor, …componentInfo, …preservation, …FRBRcountry ).
element FRBRExpression: … Missing child element(s). Expected is one of ( … …FRBRmasterExpression, …FRBRlanguage ).
```

The same check was run over every build-90 corpus file that renders: 7 `legal/` + 162 `ok/` =
**169 documents**, against both the OASIS XSD and LEOS's 2017 copy (same two errors).

- **As emitted, 0 of 169 are valid.**
- **After adding `<FRBRcountry value="xx"/>` and `<FRBRlanguage language="eng"/>` with `sed`,
  153 of 169 are valid.** That includes all 7 `legal/` files, every deontic body (4 files), the
  table, and the 13 cross-headings.
- **The other 16 fail on an empty `<body>`.** They are fixtures such as `assert.l4` and
  `not-of.l4`, with nothing to render.

So the whole schema gap is two metadata lines plus an empty-document guard.

**Re-measured on `unstable`, same day** **[E]**. A fresh `l4` built from `unstable` @ `7df7a3ca`,
run over the 7 top-level `legal/*.l4` files and all 336 `ok/**` files (343 documents, every one of
which renders):

- **0 of 343 valid as emitted.**
- **310 of 343 valid after the same two FRBR additions**, including all 7 `legal/` files.
- **The other 33 fail only on an empty `<body>`**, the same single error in every case.

So the finding does not depend on the build-90 binary.

**Anchor stability, measured** **[E]**. TNR §2.3 item 6 leaves this "to be measured". Inserting a
single ``ASSUME `the person is a sole trader` IS BOOLEAN`` above the alcohol act's first `ASSUME`
(file copied to `act.l4` for the probe) shifts every later anchor:

- "must not sell alcohol" goes `para_c_14_act` → `para_c_16_act`;
- "may cancel the registration" goes `para_c_32_act` → `para_c_34_act`;
- **`para_c_32_act` now names a different provision** ("The proprietor does so within 5 days…").

Today's `eId` is not a round-trip identity, and it can alias one across versions. The AKN naming
convention puts identity elsewhere anyway (`akn-nc-v1.0-os` §5.3) **[E]**:

- `eId` "needs to be updated regularly whenever the structural role of the element changes";
- `wId` "never changes";
- `GUID` is the "application-specific identifier … no required syntax".

So the TNR §3.2 anchor belongs in `GUID` for OASIS AKN and in `xml:id` for AKN4EU/LEOS. `eId`
should follow the convention (`art_3__para_5__point_c`), and `wId` can carry the he/en
cross-language identity that `MULTILINGUAL-NLG-SPEC.md` needs.

## E. Gap analysis: from L4's AKN to something LEOS accepts, and back

| layer           | today (L4)                                                       | LEOS / AKN4EU wants                                                                                                                                                      | size (**judgement**, not measured)                                                   |
| --------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| OASIS validity  | 2 missing FRBR children; empty-body case                         | —                                                                                                                                                                        | hours; measured to be the whole gap (§D)                                             |
| root / doc type | `<act name="act">`                                               | `<bill name="REG\|DIR\|DEC">` (proposal), or a `<doc name=…>` from a closed list; `.leg` + `main.xml` for full packages                                                  | small, but it fixes the output to "EU proposal"                                      |
| identifiers     | gensym `eId`, unstable (§D)                                      | `xml:id` on every element (the template puts one even on `<p>` and `<num>`)                                                                                              | small once the §3.2 anchor exists; the anchor itself is TNR Phase 4                  |
| metadata        | FRBR stub, `#l4`, 1970-01-01                                     | FRBRcountry `EU`, FRBRlanguage, `akn4euVersion`, TLC refs to OP authority tables, `<proprietary source="~_leos">` with `leos:ref` / `leos:template` / `leos:docTemplate` | small–medium; mostly per-template constants                                          |
| structure       | `section → paragraph(heading, content → blockList/item)`         | `preface / preamble(citations, recitals) / body(… chapter / section / article → paragraph → point / list) / conclusions`, auto-numbered                                  | medium: a new renderer over the same `Document` IR                                   |
| drafting style  | Commonwealth outline ("X means: all of the following are true:") | EU house style: "Article n", "1.", points (a)/(i), "Whereas:", formulae                                                                                                  | **large**: a TNR dialect (§2.8), plus content L4 does not hold (citations, recitals) |
| validation      | well-formedness only                                             | OASIS XSD (we have it); LEOS's 2017 XSD plus template/structure rules                                                                                                    | XSD gate: small. LEOS gate: needs a spike instance                                   |

**What carries over, and what cannot.** TNR's Coode tabulation maps almost one to one onto EU
points: (a)/(b), then (i)/(ii), with "; and"/"; or". The dialect work does not start from zero.
What L4 cannot generate is the **preamble**, meaning legal-basis citations and reasoned recitals.
Those are policy prose with no rule counterpart, and a LEOS-bound document would carry them as
unmanaged text (TNR §3.5).

**Reverse direction (the lens `put`).** A LEOS Light callback or `download-xml-version` returns
LEOS-internal AKN with these properties:

- `xml:id` on every element, and new nodes stamped `ec…`;
- track changes inline, with `leos:softaction` ∈ {`add`, `move_to`, `move_from`, `del`, `trans`,
  `del_trans`, `undelete`, `splitted`} plus `leos:softuser`, `leos:softdate` and
  `leos:softmove_to/from` (`SoftActionType.java:19-27`, `XmlHelper.java:213-224`) **[E]**;
- `leos:origin`, marking which institution's text each node is;
- no annotations: those live in the Annotate service.

Reading that back needs two things:

- **A real namespace-aware XML parser.** `jl4-core` has none: `L4.Blawx.Xml` is explicitly "not an
  XML parser" (`jl4-core/src/L4/Blawx/Xml.hs:10-15`) **[E]**.
- **An aligner keyed on `xml:id`/`GUID`.** The soft actions then answer most of TNR §3.3
  directly: an `add` or `del` of a point is Class B, and an in-node text change with no soft
  action is Class A or B by diff. Accepted versus pending changes must be settled before
  ingesting.

Beyond the lens machinery that TNR Phase 4 already owes, the LEOS-specific reader is roughly a week
**[judgement]**.

## F. Integration paths, ranked

1. **`l4 export akn`, made OASIS-valid (now, independent of LEOS).** Add `FRBRcountry` and
   `FRBRlanguage`, refuse or placeholder an empty body, emit naming-convention IRIs and `eId`s,
   and put the §3.2 anchor in `GUID`. Gate it with `xmllint --schema` against the OASIS XSD, the
   same kind of offline oracle `LEGALRULEML-RESEARCH.md` chose. `p7-akn` then moves from a
   well-formedness oracle (barred from PASS by `verdict.mjs`) to a schema oracle, and every AKN
   consumer gains (Indigo, LIME, Lawmaker, LegisPro), not only LEOS.
2. **`l4 export akn4eu FILE`: one `bill` for LEOS Light `import-document`, returned through
   `callbackAddress` (FUTURE).** Spike first: run `run-leos.sh` locally and learn exactly what
   `validateDocument` rejects in a hand-built minimal bill (note the `FIXME` that tolerates
   `DOCUMENT_PROPOSAL_TEMPLATE_NOT_FOUND`, `ApiServiceImpl.java:677-681`). Then write the emitter
   as a sibling of `renderAkn` over the same IR, with an EU dialect in the house-style table.
3. **`--package leg`: a full `.leg` proposal via `POST /upload`.** Only if a partner needs whole
   proposals; most of the added content (the explanatory memorandum) is not L4's.
4. **`l4 import akn4eu EDITED.xml --against foo.l4`: the lens `put` over LEOS output.** It shares
   the classifier with the `.docx` round trip in TNR Phases 4–5; build it as a second front end to
   that, not as its own system.

## G. Is LEOS the right target? Alternatives

| tool                        | what it is                                                                                                      | format                                                               | open?                             | fit                                                                                                                                                                                                     |
| --------------------------- | --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **LEOS** (EC)               | pre-enactment drafting editor for EU acts                                                                       | AKN4EU/LEOS profile of AKN 3.0 **[E]**                               | EUPL-1.2 **[E]**                  | right audience, strict profile, EU style only; LEOS Light is a ready round-trip channel **[E]**                                                                                                         |
| **Indigo** (Laws.Africa)    | "legislation database for managing, consolidating and publishing legislation in the Akoma Ntoso format" **[E]** | generic AKN 3 (Cobalt, Bluebell) **[E]**                             | LGPL-3; commit 2026-09-23 **[E]** | **lowest friction**: `import_from_upload` takes `text/xml` verbatim and re-stamps metadata from the Work (`indigo_api/importers/base.py:206-214,286-304`) **[E]**. Consolidation, not ministry drafting |
| **LIME** (CIRSFID, Bologna) | markup editor: existing text → AKN                                                                              | AKN **[U]**                                                          | open source per its site **[E]**  | `http://lime.cirsfid.unibo.it` serves a static page, `https` fails, consistent with `LEGALRULEML-RESEARCH.md`'s "refuses connections". Demo **[U]**. Marks up; does not draft                           |
| **LegisPro** (Xcential)     | commercial drafting/amending platform                                                                           | "built to support Akoma Ntoso … as well as … USLM" **[E via fetch]** | commercial **[U]**                | logos: US House, GPO, California, Oregon, UK and Scottish Parliaments, UN **[E via fetch]**; no public API seen                                                                                         |
| **UK Lawmaker** (LDAPP)     | UK/Scottish drafting tool (OPC, both Houses, TNA)                                                               | AKN, eXist, MEAN **[E via fetch; page may be stale]**                | not for outside use **[U]**       | nearest to TNR's Commonwealth style; no external surface known; Propylon's role **[U]**                                                                                                                 |
| **LexML eta** (Brazil)      | web component for "textos articulados"                                                                          | LexML, "Adaptado de Akoma Ntoso 1.0 e Norme in Rete 2.0" **[E]**     | GPL-2 **[E]**                     | active (2026-09-23), but a Brazilian schema and Portuguese drafting rules                                                                                                                               |
| **Bungeni**                 | UN/DESA Africa i-Parliaments suite                                                                              | AKN ancestor **[U]**                                                 | —                                 | site 403; believed defunct **[U]**                                                                                                                                                                      |
| Propylon; Norway/Denmark    | —                                                                                                               | —                                                                    | —                                 | **not researched**                                                                                                                                                                                      |

**Reading.** Which tools' drafters could consume TNR output? LEOS for EU and Member-State
ministries; Lawmaker and LegisPro for Commonwealth and US legislatures. Only LEOS is open. For a
cheap demonstration of the lens through a real AKN editor, Indigo is the better host.

## H. Proposed census row and CLI surface

**Census row for `BACKEND-PORTFOLIO-SPEC.md` §2.6 Documentation.**

- The table has **no AKN row at all**, although AKN has shipped since `2bb2b6d5` (2026-06-14).
- Its TNR row ("BRANCH (`nlg-roundtrip`)") is stale: the spec now lives on `unstable` with the
  2026-09-02 ruling.
- Proposed:

```
| Akoma Ntoso 3.0 / AKN4EU (LEOS) | **SHIPPED, NOT SCHEMA-VALID** (generic AKN via `l4 render --format akn`) + **FUTURE** (AKN4EU for LEOS) — researched 2026-09-24; 0/169 corpus renders valid vs the OASIS XSD, 153/169 after adding `FRBRcountry` + `FRBRlanguage` (the rest: empty `<body>`) **[E]**; eIds are gensyms that shift and alias on insertion **[E]**; LEOS accepts only its own `bill`/`doc` profile with `xml:id` + `leos:` metadata, via `.leg` upload or LEOS Light `import-document` with callback **[E]** | `jl4-core/src/L4/Export/Render.hs` (`renderAkn`); `l4 render --format akn`; `specs/research/LEOS-RESEARCH.md` |
```

**CLI.** Meng proposed the convention `l4 export FORMAT FILE` / `l4 import FORMAT FILE` on
2026-09-24, the day this memo was written. When the memo was written it was **not yet recorded
in the tree**; the restructure that adopts it owns that record, not this memo.

- Today's spelling is `l4 export --to=dmn|dmn-md|bpmn` (`jl4/app/L4/Cli/Export.hs:1`).
- A standing ruling chose **`l4 blawx --import`** over "an `l4 import` family"
  (`BLAWX-EXPORT-SPEC.md:1648-1652`, ANSWERED 2026-08-18).
- Adopting the convention supersedes that ruling, and per `CLAUDE.md` §4 it needs recording in an
  owning document.

Within that convention, I recommend three verbs:

- **`l4 export akn FILE`: generic OASIS AKN 3.0. Yes, move `l4 render --format akn` here.**
  `export` is "a foreign interchange notation … with a fidelity report" (`Main.hs:110`), and AKN
  is an external schema with a validity gate; `render` is for reading views (text, html) and our
  own IR (json, plan). The move brings the fidelity-report discipline: the AKN carries prose
  only, dropping types, `#EVAL` and evaluation semantics, and the user should be told so. Keep
  `render --format akn` as a deprecated alias for one release; its callers are
  `doc/tutorials/getting-started/l4-cli.md:273`, `tests-cli/Main.hs:1642-1666` and
  `p7-akn.sh:36`. The code can stay in `L4.Export.Render` or move to `L4.Export.Akn`; the verb and
  the module need not move together.
- **`l4 export akn4eu FILE [--package xml|leg]`, not `l4 export leos`.** Name the format, not the
  product. AKN4EU is an interinstitutional standard with its own versioned schema (through
  5.0.1.0), consumed by Parliament, Council and the Publications Office as well as LEOS. The EU's
  own pages keep the two apart: it is "to be supported by the tools used in each EU institution,
  such as … LEOS". LEOS specifics are packaging (`--package leg`), and the `leos:` proprietary
  block is harmless elsewhere. Pushing to a running LEOS (authenticated REST) is deployment, not
  export, and stays out of `l4 export`.
- **`l4 import akn4eu EDITED --against foo.l4`** (and `l4 import akn …`): the lens `put`. It reads
  `leos:softaction` when present. It would replace TNR §3.3's working name
  `l4 ingest foo.md --against foo.l4`; that rename is for the TNR spec's owner to rule, flagged
  here and not decided.

## I. Open questions

1. **Does an imported `xml:id` survive?** Through LEOS Light import, editing and export: this
   decides whether anchors survive a LEOS trip (§C.4), and is the spike's first measurement.
2. **What does LEOS's template validation reject** in a minimal hand-built bill? This needs a
   running instance.
3. **Can the OASIS AKN XSD be vendored,** or must the gate fetch it at CI time? It is the same
   question as the LegalRuleML `xmllint` gate; check the OASIS IPR terms.
4. **Does AKN4EU 5.0.x still name `xml:id` as its technical identifier?** Its schema and
   validation framework were not obtained. LEOS 5.x code says yes, but the 5.x standard was not
   re-read.
5. **Is there demand?** Paths 2–4 are worth building only for an EU institution, a Member-State
   ministry (Spain's fork is the live one), or a Laws.Africa-style publisher.

## J. Sources

**Primary [E].** LEOS core (`code.europa.eu/leos/core` @ `28a66b28`): `README.txt`,
`RELEASE-NOTES.txt`, `publiccode.yml`, `docs/…/{BL-023.xml,structure_01.xml}`,
`leos.postman_collection.json`, `leos_service_api-documentation.pdf` (5.6.0-SNAPSHOT, 198 ops),
and the Java classes `AkomantosoXsdValidator`, `ApiServiceImpl`, `ProposalConverterServiceImpl`,
`LeosLightApi{,ServiceImpl}`, `ImportServiceImpl`, `OJDocumentProviderImpl`,
`XmlContentProcessorImpl`, `IdGenerator`, `XmlHelper`, `XmlUtils`, `SoftActionType`,
`LeosCategoryClass`, plus `lightProfile.xsd` and `common.properties`. Also the GitLab API listing
of group `leos` and the READMEs of `ai4drpm`, `leos_4eu` and `leos-core-spain`. Standards: the
OASIS AKN 3.0 XSD (`docs.oasis-open.org/legaldocml/akn-core/v1.0/os/part2-specs/schemas/`), the
AKN naming convention (`…/akn-nc/v1.0/os/akn-nc-v1.0-os.html` §5.3), and AKN4EU documentation
Draft 3.0 Vol. I (Cellar `7675b2e4-5fbb-11eb-8146-01aa75ed71a1`). Other editors:
`github.com/laws-africa/indigo` and `github.com/lexml/lexml-eta`, both @ 2026-09-23. L4 output:
the `l4` binary in `l4-vscode-linux-x64-1.6.90.vsix` (sha256 `23ebb1d4f9b4e64d…`) over the
corpus at `8917dc3f`.

**[E via fetch].** Interoperable Europe's LEOS releases page, its news item "LEOS team looking
back at 2022" (2023-03-16) and "Discover AKN4EU"; the op.europa.eu AKN4EU page and dataset
versions; `xcential.com/legispro`; `legislation.gov.uk/projects/drafting-tool`.

**[U].** The ISA² LegIT fact sheet (SG.A1); Greece; Bungeni's status; Propylon's role in
Lawmaker; the `leos_4eu` committer's Bologna affiliation; Norway and Denmark (not researched).

**In-repo.** `NLG-TNR-ROUNDTRIP-SPEC.md` §§2.1, 2.3, 2.8, 3.2, 3.3, 3.5, 10;
`LEGALRULEML-RESEARCH.md`; `BACKEND-PORTFOLIO-SPEC.md` §2.6; `BLAWX-EXPORT-SPEC.md:1648-1652`;
`MULTILINGUAL-NLG-SPEC.md`.
