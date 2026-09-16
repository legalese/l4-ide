# CNL affordances — prior art / related work

> Resource triage for the CNL-affordances facet (and for the drafter-facing question the facet
> shares with the Elhanan Schwartz / Matthew Waddington threads: how a legislative drafter gets
> machine checking without leaving prose). Started 2026-09-16. **Nothing listed here has been read
> unless its line says so.** Items are catalogued from the OSF API (`api.osf.io/v2/nodes/yzf6x`), > not from the documents themselves; re-verify before citing, per the user-level `CLAUDE.md` > "mark twain" rule. Sister file: [`../bounded-deontics/related-work.md`](../bounded-deontics/related-work.md). ## Computer-Readable Legislation Project (CRLP), Jersey — OSF project `yzf6x`

- **Home:** <https://osf.io/yzf6x/> (overview: <https://osf.io/yzf6x/overview>) · site <https://crlp-jerseyldo.github.io>
- **Run by:** the Legislative Drafting Office of Jersey (States Greffe). **Contributors on OSF:**
  Matthew Waddington, Laurence Diver, Tin San Leon Qiu, Brenda De Louche.
- **Self-description:** "Parsing and marking up the logical structure of draft legislation so that
  computers can navigate it — using the insights of legislative drafters in Commonwealth countries."
- **Tags:** artificial intelligence · computational law · law · legislation · legislative drafting ·
  logic · rules as code. Created 2024-02-11, last modified 2026-02-10 (API `date_modified`).
- **Why it matters to us:** this is the drafting office that authored against L4 directly (the
  "if-then draft → L4 → logic map" pipeline on `jl4.legalese.com`; their own words, "L4 is now being
  taken forward by Legalese"). It is the one existence proof of a drafting office adopting a formal
  language rather than calling one as a service, and Waddington is the person the CNL-convergence
  argument was made to. Their "non-tech rigour" material is the drafter-side half of that argument.

### Linked from the project wiki (none read)

| what                                                                                                        | where                                                                                                |
| ----------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Waddington, "Digitising legislation: progress and prospects" (SocArXiv preprint)                            | <https://osf.io/preprints/socarxiv/fpczw>                                                            |
| Waddington, "Rules As Code: Drawing Out the Logic of Legislation for Drafters and Computers" (SSRN 4299375) | <https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4299375> — SSRN is bot-walled; download by hand |
| LDO's related output from before CRLP                                                                       | <https://osf.io/9gwvk>                                                                               |
| CRLP YouTube playlist · "Rules as Code" playlist (others' talks)                                            | `PLxI6pLSZVXTqp-BZ2f3uQ3m-mFp2nP4br` · `PLxI6pLSZVXTp3BA9IBK-Q_yZukyImMcnq`                          |

### Files on the top-level project (none read)

- `Computer Readable Legislation Project Report R-24-2026.pdf` + `CRLP report Exec Summary.pdf` — the 3-year report to the States Assembly (also at `statesassembly.je`, R.24/2026). - `Jersey's project on parsing drafts for if-then structures for Rules as Code — Loophole 2023-09
Waddington.pdf` — _The Loophole_ is CALC's journal; the citable write-up of the if-then method. - `Automated Decision-Making in Public Law, McQuilton pre-print.pdf` - `SMU CLAWCON 2023-07 legislative drafter's perspective on Computational Law, CRLP.pptx` - `Computer-Readable Legislation Project — LVI Vienna 2023.pptx` · `CRLP-CALC-Jamaica2024.pptx` - `rules-as-code-jersey-ldo-output-so-far-aug-2022.pdf` · `Plan for first stages of the CRLP.pdf`

### Components (sub-projects), with their files

**1. What might an IDE-like drafting tool look like?** — <https://osf.io/uk2vy/> (16 items). The
one most directly adjacent to our work and to Schwartz et al.'s ILDE paper.

- `Draft to If-Then to L4 to visualiser.pdf` — **the L4 pipeline, in their words.** - `Visualising logical structure with L4` (wiki page) · `Overview of all elements of CRLP work with CDLaw Singapore 2024-25.pdf` — the SMU Centre for Digital Law collaboration.
- `Legislative drafters in the shallow end — RaC Guild Sept 2025, Waddington.pptx` — title alone
  is the adoption argument ("drafters won't learn a language"); read before the Schwartz follow-up.
- `How drafters can make interactive maps of provisions — CALC Europe, Belfast 2025.pdf` - `ILDE mockup screenshot.png` + `undefineds` / `must not` / `Defined terms` mock-up decks — Diver's `crlp-jerseyldo.github.io/ilde-mockup` (pure UI markup; **not** the L4 pipeline — do not conflate). - `Drafting tool — extracts from CRLP CALC2024.pptx`

**2. Improving rigour in legislative drafting — lessons from logic & computing** —
<https://osf.io/vpwrs/> (4). "Taking what we have learnt from modern logic and computing, but
applying it to drafting without any tech." This is the CNL-affordances facet's natural prior art:
the drafter-side discipline that the language then mechanises.

- `Drafting the legislative sentence — taking care with must, may, is.pdf` — deontic surface syntax from a drafter's chair; compare L4's `MUST`/`MAY`/`IS`. - `Updating Legislative Sentence for AI Age — CALC2026 Singapore.pdf` — newest (2026). - `Legislative drafter guidance and training material — CRLP plan as at 28-2-24.pdf` - `Non-tech rigour — extract from CRLP CALC2024.pptx`

**3. Parsing exercises** — <https://osf.io/qg4pb/> (10). Imaginary provisions + enacted ones,
marked up "in QnA Markup, Mermaid Markdown, and Excel spreadsheets, possibly with versions in L4
and Blawx."

- `British Nationality Act s1 parsed for logic & Excel 13-5-24.pdf` — **same statute as our de-novo BNA corpus** (`jl4/examples/legal/bna/`); a direct comparison is available for free. - `Example provisions for parsing logical structures.pdf` · `Examples for parsing.docx` - `Problems with "may" in review provisions.docx` — a `MAY` semantics worry; relevant to the
  deontics paper too.
- `Farming Act s8 coloured — offence.docx` · `Rules as Code Jersey — parsing drafts for if-then — CALC2022.pptx` · `Jersey parsing for if-then for RAC — Loophole 2023-09.pdf` - wiki pages `Logic`, `Spreadsheets if-then`.

**4. Artificial Intelligence and legislation** — <https://osf.io/bkjqx/> (8). "Includes project
with Google Cloud AI, through Digital Jersey, to automate identifying logical and other elements in
existing legislation." Relevant to the `go` pipeline's extraction stage and to Kant/Chubb's
guided-vs-unguided finding.

- `Using generative AI for computer-readable legislation.pdf` · wiki `Testing generative AI to draft legislation`
- `Notes for Developers of AI Chatbots for Jersey Legislation.pdf` - `AI sandwich — CRLP for CALC AI group.pptx` · `CRLP — CALC AI Working Group 25-7-25.pptx` · `CRLP work on AI and legislation — CIAJ2026.pdf` · `Waddington AI4Legs.pptx` · `CRLP CALC2024 extracts — AI.pptx`

**5. "Common Legislative Solutions" Jerseyfied, parsed & digitised** — <https://osf.io/ywq82/>
(2). Model provisions ("Common Legislative Solutions" is the UK Office of the Parliamentary
Counsel's pattern book) parsed for logic, "to look for problems which should be fixed in the model
versions." A pattern-book of provisions is the drafter-side analogue of the skill's
`source-patterns.md` phrasebook. - `Common Legislative Solutions.pdf` · `CLS extract from CRLP CALC2024.pptx`

## Suggested reading order (for the Schwartz follow-up and the facet)

1. `Legislative drafters in the shallow end` (RaC Guild, Sept 2025) — the adoption argument from
   the drafter who adopted.
2. `Draft to If-Then to L4 to visualiser.pdf` — what they actually built on us. 3. `Drafting the legislative sentence — must, may, is` — the CNL half of the facet. 4. `BNA s1 parsed for logic & Excel` against our BNA corpus — a free comparison.
3. The Loophole 2023-09 paper — the citable one.
