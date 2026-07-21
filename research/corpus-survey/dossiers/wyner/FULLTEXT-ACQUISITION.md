# Wyner full-text acquisition (green-OA only)

> Full text was gathered from **open sources only**: the author's own self-archived copies (recovered from the Internet Archive Wayback Machine, since his `wyner.info` file host has lapsed), plus OpenAlex / Unpaywall / arXiv / Semantic Scholar open-access locations. **No Sci-Hub, no paywall circumvention** — paywalled items are recorded, not forced.

## Coverage

- **Distinct works with full text held: 46 of 154** (~30%). The 154 denominator is the raw OpenAlex/DBLP work-list, which per the W1 caveat includes a few namesakes and non-article items, so this understates coverage of his genuine papers.
- On disk we hold **74 self-archive files**; 61 are papers (counted here) and 13 are grey literature (slides, CV, CFPs, workshop front-matter) kept as extras.
- **His self-archive (author copies): 61 PDFs** recovered via Wayback — the dominant channel, heavy on his 2008–2014 argumentation / CBR / CNL / LegalRuleML core (many are workshop papers with no DOI and no gold OA).
- **Metadata channel (OpenAlex/Unpaywall/arXiv/S2): 24 PDFs** — thin, because most of his DOI-bearing work sits behind Springer LNCS / IOS / ACM.
- Self-archive files confidently matched to a work-list row: 56; 5 more are held but not cleanly linked (older/renamed).

### By year (held / total)

| Bucket | Held | Total |
|---|---:|---:|
| pre-2010 | 3 | 18 |
| 2010-2019 | 36 | 106 |
| 2020-2025 | 7 | 30 |

### By research thread (held)

| Thread | Held |
|---|---:|
| argumentation | 19 |
| cnl | 7 |
| kr-nlp | 5 |
| legalruleml | 4 |
| cbr | 3 |
| other | 3 |
| stewardship | 3 |
| rule-extraction | 2 |

## Per-channel PDF sources

- Wayback self-archive: **61**
- openalex-best: 15
- longtail-s2: 5
- openalex-loc: 3
- stored-oa: 1

## Highest-cited works still WITHOUT full text

These are the papers a human would pull via licensed institutional access later (mostly Springer/IOS/ACM). Ranked by citations.

| Cites | Year | Title | metadata |
|---:|---:|---|---|
| 80 | 2013 | A formalization of argumentation schemes for legal case-based reasonin | failed |
| 78 | 2015 | LegalRuleML: Design Principles and Foundations | paywalled |
| 71 | 2012 | Semi-Automated Argumentative Analysis of Online Product Reviews | paywalled |
| 54 | 2008 | An ontology in OWL for legal case-based reasoning | paywalled |
| 53 | 2007 | Argument Schemes for Legal Case-based Reasoning | failed |
| 48 | 2021 | DeepRhole: deep learning for rhetorical role labeling of sentences in  | paywalled |
| 33 | 1998 | Subject-Oriented Adverbs are Thematically Dependent | paywalled |
| 32 | 2007 | OWL ontology of basic legal concepts (LKIF-Core) | failed |
| 31 | 2018 | A Methodology for a Criminal Law and Procedure Ontology for Legal Ques | paywalled |
| 27 | 2008 | Towards flexible types with constraints for manner and factive adverbs | paywalled |
| 26 | 2007 | Arguments, Values and Baseballs: Representation of Popov v. Hayashi | failed |
| 24 | 2013 | Argument schemes for reasoning with legal cases using values | paywalled |
| 21 | 2010 | A Framework for Enriched, Controlled On-line Discussion Forums for e-G | failed |
| 17 | 2007 | OWL ontology of basic legal concepts (LKIF-Core). Estrella: Deliverabl | failed |
| 17 | 2015 | Using Argumentation to Structure E-Participation in Policy Making | paywalled |
| 16 | 2010 | Towards Annotating and Extracting Textual Legal Case Elements | failed |
| 16 | 2013 | Argumentation Schemes for Reasoning about Factors with Dimensions | paywalled |
| 16 | 2016 | Working on the argument pipeline: Through flow issues between natural  | failed |
| 15 | 2008 | Three Senses of “Argument” | paywalled |
| 15 | 2013 | LegalRuleML: From Metamodel to Use Cases | paywalled |
| 14 | 2010 | From Policy-Making Statements to First-Order Logic | paywalled |
| 14 | 2012 | An Empirical Approach to the Semantic Representation of Laws | failed |
| 13 | 2013 | A Study on Translating Regulatory Rules from Natural Language to Defea | failed |
| 12 | 2015 | Sentiment–topic modeling in text mining | paywalled |
| 11 | 2017 | Extracting and Understanding Contrastive Opinion through Topic Relevan | failed |

## Notes

- PDFs live in `dossiers/wyner/pdfs/` (metadata) and `dossiers/wyner/pdfs/selfarchive/` (author copies); both are gitignored.
- Self-archive→work matching is heuristic (year + venue acronym + title token + author surname); the distinct-held count is therefore ±a few.
- Self-archive files not linked to a work-list row: WynerBench-CaponDunneThreeFinal.pdf, WynerGovernatoriH-R.pdf, WynerOnBench-CaponEtAl1987.pdf, WynerOnHafner1987.pdf, WynerOnRisslandDaniels1995.pdf.
