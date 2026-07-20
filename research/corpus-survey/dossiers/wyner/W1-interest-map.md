# W1 — Adam Wyner: interest map

*Built from the W0 harvest (OpenAlex `A5063413613` + DBLP `73/3639`): 154 works, 1991–2025,
~2,150 citations. Data-hygiene caveat: OpenAlex appears to have merged at least one namesake — a
"Medical Entomology and Zoology" entry and the lone 1991 item are almost certainly not this Adam
Wyner — so treat the 154 count as an upper bound; the threads below are robust regardless.*

## The shape of the career

- **2006–2009 — entry into AI & Law**: legal case-based reasoning, argument schemes, OWL
  ontologies for CBR. He arrives via *argumentation* and *knowledge representation*, not NLP.
- **2010–2019 — peak (12–15 works/yr)**: the productive core. Three strands run in parallel —
  argumentation mining from legal text, controlled natural language / LegalRuleML, and legal
  ontologies / NLP pipelines. This decade is where L4's CNL paper meets him.
- **2020–2025 — LLM era + stewardship**: fewer but higher-level pieces — retrospectives on the
  field, special-issue editorship, and hybrid symbolic/ML work.

## The threads (what he actually works on)

1. **Argumentation — theory *and* mining** (his spine, ~41 argumentation-tagged works). Formal
   side: argumentation schemes for legal CBR formalized in **ASPIC+** (Prakken, Bench-Capon,
   Atkinson 2013). Empirical side: **text-mining arguments** from legal cases (Mochales-Palau,
   Moens 2010 — 138 cites) and from product reviews (2012). He treats argument *structure* as the
   organizing unit of legal text.
2. **Legal case-based reasoning** — argument schemes over the CATO/HYPO factors–dimensions
   tradition; an OWL ontology for legal CBR (2008). Deeply tied to Bench-Capon/Atkinson/Ashley.
3. **Controlled Natural Language** — co-author of the field-defining survey *On Controlled Natural
   Languages: Properties and Prospects* (2010, with Fuchs, Schwitter, Kuhn, Sowa et al.). This is
   the single most direct point of contact with L4's CNL paper.
4. **LegalRuleML** — **OASIS LegalRuleML** (2013) and its *Design Principles and Foundations*
   (2015), with Athan, Governatori, Palmirani, Paschke. Standards, interoperability, deontic +
   defeasible + temporal markup for legal sources. He is an interoperability-standards person.
5. **Rule extraction / ingestion** — *On Rule Extraction from Regulations* (2011, w/ Peters):
   explicitly a **linguistically-oriented, rule-based** pipeline "in contrast to a machine learning
   approach," aimed at translating regulation into *executable logic*. His methodological signature.
6. **Legal KR & ontologies / NLP** — LKIF-adjacent ontologies, semi-automated ontology
   construction, legal QA, recognizing cited facts/principles, rhetorical-role labeling. Empirical,
   annotation-based, evaluation-heavy (reports κ, precision/recall, inter-annotator agreement).
7. **Field stewardship** — lead/among-authors on *A History of AI & Law in 50 Papers* (2012, 164
   cites — our recall benchmark) and *Thirty Years of AI & Law: the Third Decade* (2022). He curates
   the field's memory and is alert to the symbolic→ML shift.

## Collaboration structure

- **Core**: Trevor Bench-Capon (31), Katie Atkinson (21) — the Liverpool argumentation nucleus.
- **Deontic/standards**: Governatori (8), Palmirani (7), Paschke (7), Athan (5) — the LegalRuleML group.
- **Reasoning theory**: Sartor (9), Prakken (7). **NL/ontology**: Lévy (9), Nazarenko (9), Pan (9),
  Peters (7), van Engers (7). **Swansea/newer**: Fawei, Straß, Davis, Lin.
- Venues: LNCS (31), FAIA/JURIX (20), *Artificial Intelligence and Law* (11), *Argument & Computation*.

## Where he intersects L4 (the CNL-paper surface)

- **CNL proper** — he co-wrote the taxonomy L4's CNL claim will be measured against.
- **Ingestion** — his rule-extraction-from-regulations pipeline is the linguistically-grounded
  cousin of L4's isomorphic formalization; a natural *contrast/borrow*.
- **LegalRuleML** — the interoperability standard L4 must position relative to (export? align?).
- **Argumentation & defeasibility** — his lifelong lens; he will ask where it sits in L4's semantics.
- **Evaluation culture** — his NLP work is empirically evaluated; he'll expect readability/usability
  evidence, not assertion.
- **Linguistic grounding over ML** — his stated preference; aligns with L4's symbolic core.

→ These six are the seams the co-authored paper is built on, and the ground for the W2 persona.
