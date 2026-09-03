# YC SAFE as a product line: encoding, generator, next-round paperwork

_Status: **PROPOSED 2026-09-04, with a first build landed the same day.** §12 (the build
ledger) says, row by row, what exists in the two trees and what evidence it has; anything not
marked BUILT there is a plan. The rulings in §11 were made under the autonomy Meng granted
and have not been reviewed. This document
supersedes §7 (open questions) and §8 (next actions) of `SPEC-NOTES.md`; the findings D1–D10
and the prior-art survey in that file stay authoritative and are not repeated here._

_Evidence legend: **[M]** measured in this session against the fetched YC documents or the
tree, with the command or file named; **[R]** ruled by Meng, with the date; **[U]** believed,
not verified._

---

## 0. One paragraph

The Y Combinator SAFE is a standard form: six Post-Money instruments (three economic
variants for the US, one for each of Singapore, Canada and the Cayman Islands) plus four pro
rata side letters, all under CC BY-ND 4.0, each carrying a representation that the parties
have not modified the form "except to fill in blanks and bracketed terms". That sentence is
the product specification. The blanks are the parameter set; the bracketed terms are the
variation points; everything else is invariant and must be reproduced verbatim. So the
deliverable is not an encoding pipeline run but a **generator**: deal parameters in, one
executable SAFE per investor out, each a PDF that carries its own L4 encoding in XMP; and a
**next-round module** that takes Series A parameters and produces the conversion schedule
and post-round cap table that the SAFE's arithmetic determines. The L4 encoding is factored
so that the economic variant is **data** (one sum type, one arithmetic function) while the
document is **specialised per form** (one template per instrument), because that is the
shape the measured differences have (§3).

---

## 1. Why the encoding pipeline is the wrong tool, and what it lends

`etc/go/go.sh` (`specs/todo/single-instruction-demo/SPEC.md`) is shaped for enacted law:
P1 fetches a source with an in-force banner and an amendment-annotation inventory; P2 sweeps
forward for what courts and regulators have done to the text; P7 projects the encoding to
DMN/BPMN/AKN; G1/G2 verdicts are about a corpus replay or a de-novo comparison. None of
those is the question here **[M: `.claude/skills/running-the-l4-pipeline/SKILL.md`, read
2026-09-04]**:

| pipeline stage        | for a statute                      | for a standard form                                                      |
| --------------------- | ---------------------------------- | ------------------------------------------------------------------------ |
| P1 source bundle      | in-force banner, F/C annotations   | edition + variant matrix; a `.docx` with a footer carrying the licence   |
| P2 modification sweep | case law, guidance, proposed rules | the publisher's own changelog (User Guide Appendix III) and nothing else |
| P3 encode             | one module per body of law         | one core + a term type; the _document_ is what specialises               |
| P4 forks              | ambiguities in one text            | the same, plus the fixpoint choice (D6)                                  |
| P5 gate               | isomorphism to the statute         | isomorphism to the form **and** the generator's round-trip proof (§5.3)  |
| P7 projections        | DMN, BPMN, AKN, docassemble        | the filled document, the conversion schedule, the XMP payload            |
| §8 acceptance         | de novo vs corpus                  | the User Guide's worked examples reproduced to the share (§7)            |

What transfers unchanged: the **source-bundle register** (sha256, retrieval method, archive
URL for the Wayback fetches), the **fork register** in its R4 form (a fork is one field of an
`Interpretation` record threaded as a `GIVEN`), and **cases as tests**. What does not: the
driver, the receipts, the milestone verdicts, the projection legs. **[R 2026-09-04, this
session, on Meng's own framing that "the encoding pipeline we have built may not be entirely
the right tool"]** — the pipeline is not run; its registers are reused.

---

## 2. Sources, with provenance

Fetched 2026-09-04 from `https://www.ycombinator.com/documents` (asset paths under
`/assets/ycdc/`), sha256 recorded in the source bundle **[M: `curl` + `shasum -a 256`]**:

| form              | file                                               |    size | note                                                            |
| ----------------- | -------------------------------------------------- | ------: | --------------------------------------------------------------- | --------- | ----------------- |
| US, valuation cap | `Postmoney Safe - Valuation Cap Only - FINAL.docx` |  55,762 | the baseline; "Version 1.2" per footer                          |
| US, discount      | `Postmoney Safe - Discount Only - FINAL.docx`      |  47,628 |                                                                 |
| US, MFN           | `Postmoney Safe - MFN Only - FINAL.docx`           |  49,313 |                                                                 |
| SG, valuation cap | `… (Singapore) FINAL.docx`                         |  57,988 | "Singapore Version 1.x" footer                                  |
| CA, valuation cap | `… (Canada) FINAL.docx`                            |  73,714 |                                                                 |
| KY, valuation cap | `… (Cayman) FINAL.docx`                            |  56,260 |                                                                 |
| side letters ×4   | `Pro Rata Side Letter[ (SG                         |      CA | KY)].docx`                                                      | ~23–25 KB | US footer © 2018 |
| User Guide        | `SAFE User Guide.pdf`                              | 685,212 | 33 pp.; Appendix II = worked examples; Appendix III = changelog |

**Licence [M: `unzip -p … word/footer*.xml`]:** every form's footer reads "© 2023 Y
Combinator Management, LLC. This form is made available under a Creative Commons
Attribution-NoDerivatives 4.0 License (International) … You may modify this form so you can
use it in transactions, but please do not publicly disseminate a modified version of the
form without asking us first." Appendix III (v1.0 note) states the purpose: that republished
copies be "the actual safe documents, rather than modified versions that might confuse
people into thinking that they are viewing or using the 'standard' versions."

Consequences, recorded as **R9** in §11: the source `.docx` and its verbatim Markdown
extraction may be deposited with attribution; the generator's output for a transaction is
what the licence and the instrument itself invite; a _template_ (the form with its blanks
marked as holes) is derived mechanically from the verbatim text and proven to reproduce it
(§5.3), so it is not a modified form; and whether an **L4 formalisation** is an "adaptation"
under CC BY-ND is a real question this spec records and does not resolve. The encoding
quotes clauses in comments with attribution and never republishes a modified form.

**Pre-Money SAFE (2013–2018) [M]:** YC no longer hosts it. The Wayback Machine holds the
2014-10-06 captures of `SAFE_Cap.docx`, `SAFE_Discount.docx`, `SAFE_Cap_Discount.docx`,
`SAFE_MFN.docx` (the closest capture to 2018-08-01 is the same 2014 file, so the pre-money
text did not change on that URL) and a 2017-09-10 capture of `SAFE_Primer.rtf`. These are
the texts van der Meyden analysed (`SPEC-NOTES.md` §2). Per canon's conventions (§4) they are
a **distinct leaf**, deposited as sources only; encoding them is the paper track, not this
build.

**Editions [M: User Guide Appendix III]:** v1.0 2018-09-28 (post-money introduced, CC BY-ND
adopted, pro rata moved to a side letter); v1.1 2021-08-28 (cap-and-discount variant
withdrawn); v1.2 2023-02 (Safe Preferred Stock definition adds "liquidation multiple";
assignment proviso on domicile removed; MFN "Subsequent Convertible Securities" excludes side
letters). The version stamps in the fetched files' headers **[M: deposit agent,
`word/header*.xml`]** are: US valuation cap and discount **1.2**; US MFN **1.3** (Appendix III
describes no 1.3, and the User Guide's own Q7 quotes the MFN header as 1.1 — so the MFN form
has moved twice since the guide was last edited, and nothing here reconstructs the diff);
Singapore, Canada and Cayman "Version 1.2" each; the US side letter 1.0 (© 2018); the three
non-US side letters unstamped (© 2021); the four pre-money forms unstamped and **unlicensed**
(no footer, no "Y Combinator" anywhere in their text — the CC BY-ND footer was a 2018
addition, so the pre-money leaf's terms are UNDETERMINED). The generator must record the edition
from the form's own header stamp (`source/footers.json`), not from the deal, and must refuse a
deal whose `form.edition` names a different one — a requirement on `etc/safe/gen.mjs`, whose
state §12 reports.

---

## 3. The variation points, measured

Method: `pandoc --to gfm --wrap=none` on each `.docx`, one paragraph per line, then
`git diff --no-index --word-diff` of every form against the US valuation-cap baseline
**[M]**. The full register is `variation-register.md` beside this file (§12 says whether it
landed); this section states what the factoring rests on.

### 3.1 The fill-in surface is the parameter set

Bracketed terms per form **[M: `grep -oE '\[[^]]*\]'` on the Markdown]**:

| hole                                                  | US cap | US discount | US MFN |        SG        |                CA                |          KY           |
| ----------------------------------------------------- | :----: | :---------: | :----: | :--------------: | :------------------------------: | :-------------------: |
| Company Name (cover, preamble, signature block)       |   ✔   |     ✔      |   ✔   |        ✔        |                ✔                |          ✔           |
| Investor Name                                         |   ✔   |     ✔      |   ✔   |        ✔        |                ✔                |          ✔           |
| Purchase Amount `$[___]`                              |   ✔   |     ✔      |   ✔   |      `US$`       |              `US$`               |         `US$`         |
| Date of Safe                                          |   ✔   |     ✔      |   ✔   |        ✔        |                ✔                |          ✔           |
| State of Incorporation                                |   ✔   |     ✔      |   ✔   |        —         | `[Canada / Applicable Province]` |           —           |
| Post-Money Valuation Cap `$[___]`                     |   ✔   |      —      |   —    |        ✔        |                ✔                |          ✔           |
| Discount Rate `[100 minus the discount]%`             |   —    |     ✔      |   —    |        —         |                —                 |           —           |
| Governing Law Jurisdiction                            |   ✔   |     ✔      |   ✔   | fixed: Singapore |       `Province of [___]`        | fixed: Cayman Islands |
| Company Registration number                           |   —    |      —      |   —    |  ✔ (`{. . .}`)  |                —                 |           —           |
| signatory name / title, address, email (both parties) |   ✔   |     ✔      |   ✔   |        ✔        |                ✔                |          ✔           |

The three non-US forms print the money blanks as `US$[___]` (register J5), and Singapore
alone adds a registration-number blank on the cover (J6) — both found by the register, not
by the first grep, which is why the register exists.

That is Meng's list — name, address, date, amount, discount, cap, MFN, jurisdiction, and a
list of investors — with one instrument per investor because the form is bilateral. Two
things the table teaches: the discount form's blank is the **rate** (80%), not the discount
(20%), so the generator computes it; and the non-US forms have **fewer** blanks, not more,
because governing law is fixed by the form.

### 3.2 The economic axis changes arithmetic in two places and definitions in one block

Word-diff counts against the US cap baseline **[M]**: discount 50 changed lines, MFN 60.
Everything that changed is one of:

- **the cover term line** — "Post-Money Valuation Cap is $[…]" / "Discount Rate is [100 minus
  the discount]%" / absent (MFN);
- **§1(a) Equity Financing** — cap: "the greater of (1) Purchase Amount ÷ lowest Standard
  Preferred price, or (2) Purchase Amount ÷ Safe Price"; discount: "Purchase Amount ÷ Discount
  Price" only; MFN: "Purchase Amount ÷ lowest Standard Preferred price" only;
- **§1(b) Liquidity Event** — cap: "greater of (i) Purchase Amount (Cash-Out Amount) or (ii)
  the amount payable on Purchase Amount ÷ Liquidity Price (Conversion Amount)", Liquidity
  Price = cap ÷ Liquidity Capitalization; discount: same shape, Liquidity Price = fair market
  value of Common at the Liquidity Event × Discount Rate; MFN: Purchase Amount only, no
  Conversion Amount, and §1(d)'s "Conversion Amount" paragraph reads "Cash-Out Amount";
- **§2 definitions present** — cap carries Company Capitalization, Converting Securities,
  Liquidity Capitalization, Options, Promised Options, Unissued Option Pool, Safe Price; the
  discount form drops all seven and adds Discount Price; the MFN form drops all seven and
  adds Subsequent Convertible Securities plus a new **§3 "MFN" Amendment Provision**, which
  renumbers §3–5 to §4–6 and adds "and Section 3" to the majority-in-interest carve-out;
- **cosmetic** — `[Company Name]` vs `[COMPANY NAME]` on the cover, one blank's underscore
  count.

Nothing else moved: §1(c)–(e), §3 Company Representations, §4 Investor Representations, §5
Miscellaneous are byte-identical modulo renumbering. So the economic variant is **one value
and two arithmetic branches**; encoding it as three modules would triplicate ~90% of the
text for a difference a `CONSIDER` expresses in twelve lines. That is ruling **R3**.

### 3.3 The jurisdiction axis changes text, not arithmetic

US → SG: 108 changed lines **[M]**; CA and KY comparable. The classes: securities-law
legends and an advisory banner; a systematic vocabulary substitution (Stock → Shares,
stockholder → shareholder, certificate of incorporation → constitution); the incorporation
phrase; governing law fixed rather than blank; the tax-characterisation clause; and the
Change of Control / Direct Listing / Dissolution definitions widened for non-US corporate
law (scheme of arrangement, amalgamation, "Group Companies", non-US exchanges). The last
group is substantive but it defines **event predicates the encoding takes as inputs** — an
Equity Financing, Liquidity Event or Dissolution Event either occurred or did not — not
arithmetic the encoding computes. The formulas in §1(a)–(b) and the §2 capitalisation
definitions are the same in all four cap-only forms **[M: register J25 — "the arithmetic
is fully invariant on the jurisdiction axis"; the bullet lists match word for word after
the vocabulary substitutions]**. The register flags eight jurisdiction differences as
substantive (J14–J18, J20, J21, J31): a register-of-members obligation on conversion
(Cayman), the tax-free-reorganisation trigger no longer tied to the US Code, the Change of
Control test (a beneficial-ownership threshold in the US; a transfer to affiliated persons,
a scheme of arrangement or amalgamation, or a group-wide asset sale elsewhere), a non-US
listing counting as a Direct Listing, a listing-based rather than registration-based IPO,
and a Singapore-only power to move the investor into an SPV without its consent. All of
them define **events or obligations**, none of them a formula. So jurisdiction selects a **template family** and
constrains the **parameter set** (§3.1), and the L4 carries it only as an enum used for
validation. That is ruling **R3** too.

### 3.4 The axes do not interact, because only one cell exists off the diagonal

Non-US forms exist only for the valuation-cap variant **[M: the YC page lists exactly six
SAFEs]**. The product matrix is `{US} × {cap, discount, MFN} ∪ {SG, CA, KY} × {cap}`. A
generator that accepts `(variant, jurisdiction)` must refuse the five cells YC does not
publish rather than synthesise them, because synthesising one would be exactly the
"modified version" the licence asks people not to disseminate.

### 3.5 What the register found that the factoring did not need

`variation-register.md` §E lists twelve surprises. The ones a user of the forms should
know, each checkable against the deposited text:

- **Canada's form defines the class the investor receives by reference to a term it never
  defines.** Its "Safe Preferred Shares" definition is the only place the word "Stock"
  survives in any non-US form ("…the series of Preferred Stock issued to the Investor…"),
  and "Preferred Stock" is defined nowhere in it.
- **Cayman's side letter and Cayman's SAFE disagree on the class name** ("Standard
  Preferred Shares" versus "Standard Preference Shares"); the side letter tracks Canada's.
- **The MFN form's §1(d) contradicts itself**: substituting "Cash-Out Amount" for
  "Conversion Amount" throughout left one paragraph ranking the Cash-Out Amount senior to
  Common and the next ranking it on par with Common.
- **Singapore's form drops the Company's right to void the Safe** if the investor turns
  out not to be accredited; the other three keep it.
- **The pro rata right terminates at the initial closing of the Equity Financing** — the
  same closing at which the shares it entitles the holder to buy are sold. Identical in
  all four side letters.
- **Cayman's securities legend is a corrupted find-and-replace** ("…sold or otherwise
  transferred, SUBJECT TO SECURITY or hypothecated…").

None of these changes the encoding's arithmetic. All of them are the kind of thing the
generator's output inherits verbatim, because the licence and the instrument's own
representation forbid fixing them. They are recorded so nobody mistakes them for
transcription errors.

---

## 4. Where things live

Canon's directory conventions already name this subject **[M: `git -C ~/src/legalese/canon
show docs/directory-conventions:docs/directory-conventions.md` §1, §3]**:
`subjects/contracts/investment/yc-safe-postmoney/` — genre tree, `form_kind:
"standard-form"`, `governing_law` a `subject.json` field, editions in `subject.json`, the
edition an encoding covers in its `encoding.json`, and "distinct instruments in a family
(pre-money vs post-money SAFE) are distinct leaves". Meng ruled those conventions on
2026-08-05; nothing has been filed under `contracts/` yet, so this is the first row and it
seeds `subjects/contracts/GENRES.md` with the four genres the conventions name.

```
canon/subjects/contracts/
  GENRES.md                                  insurance, investment, leasing, lending
  investment/yc-safe-postmoney/
    subject.json                             form_kind, governing_law per variant, editions, licence
    NOTES.md
    SOURCE-LICENSE.md                        CC BY-ND 4.0; what is and is not done under it
    source/
      docx/*.docx                            the ten forms + User Guide, byte-exact
      md/*.md                                pandoc gfm, one paragraph per line, verbatim
      footers.json                           per-form header/footer text pandoc drops (licence line, version stamp)
      SHA256SUMS
    registers/
      source-bundle.json                     retrieval facts, sha256, archive URLs
      fork-register.json                     F1 fixpoint, F2 partition procedure, … (§6.4)
    templates/
      <jurisdiction>/<variant>.md.mustache   derived from source/md by etc/safe/make-templates.mjs
      side-letter/<jurisdiction>.md.mustache
      holes.json                             bracket → hole map, per form, with the placeholder text
    encodings/legalese-2026-09/
      encoding.json
      safe.l4  safe-portfolio.l4  safe-round.l4  safe-form.l4
      cases/user-guide-appendix-ii.l4        the worked examples as #ASSERTs
      tests/*.golden                         point-in-time, canon has no CI
  investment/yc-safe-premoney/
    subject.json  NOTES.md  SOURCE-LICENSE.md
    source/  registers/source-bundle.json    2014 Wayback captures; no encoding row yet
```

The **generator** is a tool, so it lives in l4-ide: `etc/safe/` (§8). It takes the subject
directory as an argument and never assumes a checkout location. This spec and the build
ledger live in l4-ide at `specs/todo/yc-safe/`.

---

## 5. The generator

### 5.1 Input: `deal.json`

```json
{
  "form": {
    "family": "postmoney",
    "edition": "1.2",
    "jurisdiction": "us",
    "variant": "cap"
  },
  "company": {
    "name": "ABC, Inc.",
    "incorporation": "Delaware",
    "governingLaw": "Delaware",
    "address": "…",
    "email": "…",
    "signatory": { "name": "…", "title": "CEO" },
    "capTable": {
      "commonOutstanding": 9250000,
      "optionsOutstanding": 300000,
      "promisedOptions": 350000,
      "unissuedOptionPool": 100000
    }
  },
  "safes": [
    {
      "investor": {
        "name": "Investor A",
        "address": "…",
        "email": "…",
        "signatory": { "name": "…", "title": "…" }
      },
      "purchaseAmount": 200000,
      "date": "2026-09-04",
      "terms": { "cap": 4000000 },
      "proRataSideLetter": false
    },
    {
      "investor": { "name": "Investor B", "…": "…" },
      "purchaseAmount": 800000,
      "date": "2026-09-04",
      "terms": { "cap": 8000000 },
      "proRataSideLetter": true
    }
  ],
  "round": {
    "name": "Series A",
    "preMoneyValuation": 15000000,
    "newMoney": 5000000,
    "targetPoolPercent": 10,
    "lead": { "name": "Investor C", "amount": 4000000 }
  }
}
```

`terms` is exactly one of `{ "cap": n }`, `{ "discount": n }` (the discount, e.g. 20; the
form prints the rate 80%), `{ "mfn": true }`. `round` is optional; without it the generator
produces instruments only. Meng's spoken list maps 1:1 onto this shape.

### 5.2 Pipeline per run

```
deal.json
  │  1. validate      l4 run instance.l4  →  every `safe-form.l4` check must be TRUE
  │                   (variant × jurisdiction is a published cell; required holes present;
  │                    discount in (0,100); cap > purchase amount; dates parse)
  │  2. instantiate   write <out>/<safe-id>.l4: IMPORTs the encoding row, binds the deal
  │                   as L4 values, #EVALs the conversion functions — this file IS the
  │                   executable contract and is what gets embedded
  │  3. fill          mustache(template[jurisdiction][variant], holes(deal, safe))  →  .md
  │                   + the footer text from footers.json (licence line is a condition)
  │  4. render        pandoc .md → .pdf (LaTeX engine present [M]); optionally .docx with
  │                   --reference-doc=<source docx> for Word users
  │  5. embed         exiftool: XMP-pdfx:L4 = payload JSON (§5.4); then
  │                   qpdf --add-attachment <safe-id>.l4 (PDF/A-3 style file stream)
  │  6. schedule      if round: l4 run on the instance → conversion-schedule.md + cap-table.json
  └─ manifest.json    every output with sha256, the encoding row's module hashes, tool versions
```

Step 5 happens **before** any signature is applied; the L4 is inside the signed envelope
(`SPEC-NOTES.md` §5). The generator does not sign.

What step 3 appends below the form, after a horizontal rule: the form's own header/footer
strings (the version stamp and the CC BY-ND sentence, from `footers.json`) and one italic
line naming the source `.docx`, the tool, the date and the encoding row, stating that blanks
and bracketed terms were filled and nothing else changed. It is an addition beneath the form,
typographically separated, never an edit inside it. An underlined blank `<u>…</u>` is filled
**inside** its tags, so the form's fill-in rule survives (a bare value would print
`Address:548 Market Street`). The four holes `deal.json` carries no value for — both
signature lines and both address continuation lines — keep their placeholder; the spec did
not say what to do with an unfillable hole, and that is now the rule.

### 5.3 Templates are derived, and the derivation is proven

`etc/safe/make-templates.mjs` reads `source/md/<form>.md` and `templates/holes.json`, which
maps each bracketed literal (`\[Company Name\]`, `$\[_____________\]`, …) to a hole name
**by position** (the cover Company Name and the signature-block COMPANY are different holes
that receive the same value; the two `$[___]` blanks on the cap form are Purchase Amount then
Cap, in document order). It writes `templates/<jurisdiction>/<variant>.md.mustache`. Three facts the first draft of this section got wrong or left unsaid, each measured by the
generator build: the per-form arrays in `holes.json` are named **`brackets`** and `blanks`
(the loader accepts `holes` as an alias, but the name is pinned here so a rename cannot
break a consumer silently); the signature block renders as `\[**COMPANY\]**` with the bold
run opening inside the bracket and closing outside, so the measured literal was one `**`
short in all six SAFEs and the map now carries the extended literal; and a hole name can
have **two distinct literals in one form** (Canada: `[company name]` and `[Company Name]`;
Singapore: `[COMPANY NAME]` and the bold one), rendered as `{{name}}` for the first distinct
literal in document order and `{{name2}}` for the second, with every occurrence of the same
literal sharing one token — the round-trip proof needs that rule to be deterministic. Side
letters carry `variant: null`: one letter serves every SAFE of its jurisdiction, and the
template path `side-letter/<jurisdiction>` says so. The hole vocabulary is the
deposit's, not this document's: `holes.json` was measured form by form and adds five names
the first draft of §3.1 lacked (the Singapore registration number, the two signature lines,
the two second address lines), each flagged in the file.

The **round-trip check** is the "unmodified except blanks" proof: rendering every template
with its holes' original placeholder text must reproduce `source/md/<form>.md` byte for
byte. `etc/safe/check-templates.mjs` does this over all ten forms and exits non-zero on any
difference. It runs in l4-ide's CI only when the canon checkout is present (the
`etc/validate-dmn.mjs` pattern: skip silently when absent; never a build dependency —
`CLAUDE.md` §1.2).

The mustache dialect is the subset the templates need — `{{hole}}`, `{{#section}}`,
`{{^inverted}}`, `{{/section}}`, `{{! comment}}`, no HTML escaping because the output is
Markdown — implemented in ~60 lines in `etc/safe/lib/mustache.mjs` rather than adding a
dependency, because a dependency touches `package-lock.json` and that has blocked TS-touching
PRs before (memory: unstable lockfile drift). If the subset grows past a screen, replace it
with the real library and take the lockfile hit.

### 5.4 The XMP payload (l4meta v0.2 → v1.0)

`smucclaw/l4meta` **[M: cloned, read 2026-09-04; last commit "standardize license", v0.2.0
in CHANGELOG 2021-07-01]** is a Python CLI over `exiftool` that reads and writes **one tag**,
`XMP-pdfx:L4` (and `PDF:L4` in the Info dictionary), whose value is a JSON document as a
string. Its `xmp.config` defines the tag; its `demo/greeting.pdf` carries
`{"greeting": "Hello World!"}`. It is a mechanism with no payload schema — that is what "v0.9
design draft" means and what v1.0 supplies.

Probed here **[M: `exiftool -config xmp.config -o out.pdf "-XMP-pdfx:L4<=meta.json" in.pdf`
on a pandoc PDF; read back with the unmodified l4meta config]**: the write, the read-back and
the raw packet all work, with a multi-line payload containing `§`. So v1.0 keeps l4meta's
tag and config **unchanged** — a 2021 `l4meta out.pdf` invocation reads a 2026 SAFE — and
defines the JSON it carries:

```json
{
  "l4meta": "1.0",
  "instrument": "yc-safe-postmoney",
  "form": { "edition": "1.2", "jurisdiction": "us", "variant": "cap" },
  "source_form_sha256": "<sha256 of the YC .docx this document reproduces>",
  "template_sha256": "<sha256 of the .mustache used>",
  "parameters": { "…the holes for this one instrument, as filled…" },
  "encoding": { "row": "legalese-2026-09", "modules": { "safe.l4": "sha256:…", "…": "…" } },
  "instance": { "path": "<safe-id>.l4", "sha256": "…", "text": "<the instance module, inline>" },
  "generator": { "tool": "etc/safe/gen.mjs", "l4": "<l4 --version>", "commit": "<l4-ide sha>", "at": "<ISO>" }
}
```

`form.edition` in the payload is the edition of **that document's** form, read from its own
header stamp: the SAFE's for a SAFE, the side letter's for a side letter. The US side letter
is stamped 1.0 and the three non-US letters are unstamped, so a side-letter payload may
carry `"edition": null`. `deal.form.edition` names the SAFE only and is compared against
the SAFE's stamp.

Two carriers, as `SPEC-NOTES.md` §5 wanted: the XMP packet for identity and integrity, and
a **PDF file attachment** of the instance `.l4` (qpdf 12.3 `--add-attachment`, present
**[M]**) for the payload, so a reader with any PDF viewer can save the contract's own
program. A second custom namespace (`l4:` with structured fields) was also probed and works,
but is **not** adopted: one tag, one JSON, one schema, and the existing tool still reads it.

### 5.5 Rendering: mustache, not TNR

`l4 render --format text` on `jl4/examples/legal/promissory-note.l4` **[M]** renders the
encoding's definitions as bullet prose ("Monthly Installment Amount is a Money with: …").
That is a view of the _encoding_ — the right thing for `legal/` corpora and the wrong thing
here, where the deliverable must be the publisher's text. The TNR programme
(`specs/todo/NLG-TNR-ROUNDTRIP-SPEC.md`) stays the route for documents that have no
publisher's text; for a standard form the form is the renderer. Ruling **R10**. The
conversion schedule (§7) has no publisher's text and _is_ rendered from the L4, via a small
Markdown table writer in the generator; when the Export.Document house style can carry
arithmetic tables, it should take that job.

---

## 6. The encoding

House rules apply (`writing-l4-rules`; `GIVEN` records not `ASSUME`; `BRANCH` over `ELSE
IF`; `@ref` on every clause; inert-style quotation in comments with attribution).

### 6.1 `safe.l4` — the instrument, single note

Types: `Company` (name, capital-stock counts), `Investor`, `EconomicTerms IS ONE OF
ValuationCap HAS cap | Discount HAS rate | MostFavoredNation`, `Safe` (investor, purchase
amount, date, terms), `EquityFinancing` (lowest Standard Preferred price per share, option
pool increase), `LiquidityEvent` (proceeds, form of consideration), `Capitalization` (the
inputs to the §2 definitions).

Sections mirror the form: §1(a) `conversion shares`, §1(b) `liquidity entitlement`, §1(c)
`dissolution entitlement`, §1(d) `liquidation priority`, §1(e) `terminates`; §2 `Company
Capitalization`, `Liquidity Capitalization`, `Safe Price`, `Liquidity Price`, `Discount
Price`, `Conversion Amount`, `Cash-Out Amount`, `Dividend Amount`; §5(a) `majority in
interest`. The economic variant is dispatched once, in §1(a) and §1(b), by `CONSIDER terms`.

### 6.2 The fixpoint is in the post-money form too, and the User Guide pre-solves it

"Company Capitalization … includes all Converting Securities", and Converting Securities
"includes this Safe" — so the denominator of the Safe Price contains the shares the Safe
Price determines. The User Guide's Appendix II solves it algebraically: Company
Capitalization = 10,000,000 ÷ (100% − 15%) = 11,764,705 **[M: User Guide p. 20]**. That is
D6 (`SPEC-NOTES.md` §3) surviving the 2018 redesign, in a form the redesign made _linear_:
with all notes converting at cap, CC = base ÷ (1 − Σᵢ PAᵢ/Capᵢ), where base is outstanding
Capital Stock + Options + Promised Options + Unissued Pool excluding the round's increase.

**Ruling R6:** the encoding states the definition as written (a recursive equation), states
the closed form as a separate decision, and `#ASSERT`s that the closed form satisfies the
definition on every case. Pre-solving without the assertion would silently make the same
undocumented choice the prose makes; asserting it makes the choice visible and checked.
The fork register records it as **F1** with the User Guide's own worked example as the
authority for the closed form.

### 6.3 `safe-portfolio.l4` — several notes converting together

Per note, §1(a) gives the greater of the price method (PA ÷ lowest Standard Preferred price)
and the cap method (PA × CC ÷ Cap). A note takes the cap method iff the Standard Preferred
price exceeds its Safe Price. But CC depends on which notes take which method **[M: User
Guide Example 1 Q5, p. 22–23: Investor B converts at the Series Seed price, and Investor A's
CC is recomputed as (10,000,000 + 1,216,360) ÷ (100% − 5%) = 11,806,694]**, and the Standard
Preferred price depends on CC through the round (§6.4). The guide runs this once and a half
— all-at-cap, compare, recompute for the switched note — and stops. The encoding iterates
the partition to a fixpoint with a bound of one pass per note, and reports whether the
guide's one-pass answer is the fixpoint. That comparison is the first new finding this
build can produce and it is recorded as **F2** before the number is known.

### 6.4 `safe-round.l4` — the Equity Financing, outside the instrument

The SAFE takes "the lowest price per share of the Standard Preferred Stock" as an **input**.
How a Series A sets that price is the round's business: the guide's convention is price =
pre-money valuation ÷ (fully diluted shares after conversion + option pool increase), with
the pool increase sized so that the _available_ pool after closing is a target fraction of
the post-closing fully diluted total **[M: Example 1 Q2, p. 19–20: 1,695,000 shares for a
10% target]**. That is the option-pool shuffle, a second fixpoint, and it has a closed form:
with k = t·(V + M)/V, Δpool = (k·S − p₀)/(1 − k), where S is the post-conversion fully
diluted count, p₀ the existing available pool, t the target, V the pre-money, M the new
money. Checked against the guide: 1,694,570, which the guide rounds to 1,695,000 **[M:
computed this session]**.

The module boundary is the point: **the SAFE's arithmetic and the round's arithmetic are
mutually dependent**, and the instrument is silent about the round. The next-round
paperwork is therefore not "derived from the SAFE" alone — it is derived from the SAFE plus
a round convention that the term sheet supplies. `deal.json`'s `round` block is that
convention, made explicit. **Ruling R7.**

### 6.5 `safe-form.l4` — parameters and validation

The `Form` record (`jurisdiction`, `variant`, `edition`) and a `published` decision that is
TRUE on the six cells of §3.4; `required holes` per form; `discount rate` = 100 − discount;
`@export`ed `validate deal` returning a list of reasons, empty when the deal is fillable.
This is the module the generator calls first.

### 6.5a Liquidity and Dissolution Events

§1(b)'s "greater of the Cash-Out Amount or the amount payable on the Conversion Amount"
has the same self-reference as §1(a): the Liquidity Capitalization excludes the Safes that
cash out, and whether a Safe cashes out depends on the per-share consideration, which
depends on the Liquidity Capitalization. It closes more cleanly than §1(a): for a cap
Safe, both the Liquidity Price and the per-share consideration scale with 1/LC, so the
choice reduces to **Proceeds versus the cap** and needs no iteration **[M: derived in
`safe-portfolio.l4` `converting at liquidity`; asserted against `safe.l4`'s `takes the
Conversion Amount` on every case]**. A discount Safe always converts (it receives 1/rate
of its money); an MFN Safe never does. The User Guide's Q3 and Q4 (acquired for $10m and
$3m) are reproduced. What the form does not say — what is payable per as-converted share
once some Safes have taken cash ahead of the converters — is fork F5.

### 6.6 Pro rata side letter

Grants the investor the right to buy up to its **pro rata share** of the Standard Preferred
sold in the Equity Financing, where the share is the investor's as-converted ownership
immediately after the safe conversion **[M: `Pro Rata Side Letter.md`; Example 1 Q2:
4,486,719 × 10% = 448,671 shares for $499,998.97]**. Encoded in `safe-portfolio.l4` because
it needs the conversion result; the letter is a second template with its own holes.

---

## 7. Acceptance: the User Guide's numbers, to the share

`cases/user-guide-appendix-ii.l4` asserts, from Example 1 (two post-money notes: $200k at
$4m cap, $800k at $8m cap; founders 9,250,000; options 300,000 + 350,000 promised + 100,000
pool):

| question | quantity                                                               |                                     expected **[M: pp. 19–23]** |
| -------- | ---------------------------------------------------------------------- | --------------------------------------------------------------: |
| Q2       | Company Capitalization, all at cap                                     |                                                      11,764,705 |
| Q2       | Investor A / B conversion shares                                       |                                             588,235 / 1,176,470 |
| Q2       | Series A price, $15m pre, $5m new, 10% pool                            |                                       $1.1144 (Δpool 1,695,000) |
| Q2       | Investor B pro rata shares                                             |                                                         448,671 |
| Q3       | Liquidity at $10m: Conversion Amounts A / B                            |            561,764 / 1,123,529; per share $0.8901; both convert |
| Q4       | Liquidity at $3m                                                       | per share $0.2670; neither converts; each takes Cash-Out Amount |
| Q5       | $8.8m pre: B at price 1,216,360; A at cap with CC 11,806,694 → 590,334 |                                                       as stated |

Example 2 mixes a **pre-money** note with a post-money one (p. 24–30); its post-money half
is asserted, its pre-money half waits for the pre-money leaf's encoding and is recorded as
a pending case, not silently skipped. Rounding: the guide rounds shares down and prices to
four decimals; the cases assert the guide's printed integers after the same rounding, and
the encoding keeps rationals internally.

Where an assertion fails, the fix is to make the encoding match the form, never to loosen
the case — unless the form and the guide disagree, which is a finding (D10's shape) and goes
in the fork register.

---

## 8. Command surface (`etc/safe/`)

```
etc/safe/gen.mjs   fill    --subject DIR --deal deal.json --out DIR [--pdf] [--docx] [--no-embed]
etc/safe/gen.mjs   round   --subject DIR --deal deal.json --out DIR     # conversion schedule + cap table
etc/safe/gen.mjs   liquidity --subject DIR --deal deal.json --out DIR --proceeds N [--indebtedness N] [--promised-options N]
                                                                        # Liquidity Event: who converts, who cashes out, what each is paid
etc/safe/gen.mjs   verify  FILE.pdf                                     # read XMP + attachment, re-hash, compare
etc/safe/make-templates.mjs  --subject DIR                              # source/md + holes.json → templates/
etc/safe/check-templates.mjs --subject DIR                              # the §5.3 round-trip proof
```

`L4` is discovered the way `etc/go` discovers it (`dist-newstyle` in this worktree, then
siblings), never built. `verify` is the second-party check: it needs no deal file, reads what
the PDF carries, re-hashes the attachment against the XMP, and re-runs the instance module.

---

## 9. What is out of scope, and said so

- The NVCA / Series Seed document set (charter, SPA, IRA, voting, ROFR). The conversion
  schedule and cap table are the inputs those documents need; generating them is a separate
  and larger NLG job (`SPEC-NOTES.md` §7 Q7).
- Signing. The generator stops at an embedded, unsigned PDF.
- The static analyses D1, D5, D7, D8 (SMT over reals). They want a different backend;
  the encoding is built so they can be run over it later, and nothing here precludes them.
- Pre-money arithmetic. Sources deposited; encoding deferred to the paper track.
- YC's own "Send a SAFE" tool is not reproduced, studied, or competed with; this is a
  demonstration that an executable form can carry its own semantics.

---

## 10. Open questions (not rulings)

1. **Cap-table input shape.** v1 takes four counts (common, options outstanding, promised,
   unissued pool). Real cap tables have classes, vesting, other convertibles. The
   `holdings.l4` library already has a `Security` enum with `SAFE`; whether to build on it or
   keep the four counts is unruled. v1 keeps the counts.
2. **Rounding rules.** The guide rounds intermediates (the pool increase to the thousand,
   prices to four decimals) and computes onward from them; the form says nothing. Resolved
   at encode time as fork F3 (exact rationals, floor once at the end), not materialised as
   an `Interpretation` field — the difference on the guide's own example is 294 new-money
   shares, and the cases assert to within that. Materialise it if a user ever needs the
   guide's figures reproduced exactly.
3. **`l4 batch` vs instance module.** `l4 batch` validates only primitive params and is
   "lenient on compound types" **[M: `jl4/app/L4/Cli/Batch.hs:346–380`]**; typed JSON
   decoding exists in the evaluator. The generator uses the instance module because that
   file is needed anyway (it is the embedded payload); batch is an optimisation for the
   validation step if it proves to decode records.
4. **Should the filled document also be emitted as `.docx` from the original `.docx`** (run
   substitution with python-docx, present here) rather than via pandoc's reference-doc? It
   would be byte-closer to YC's formatting. Deferred; LibreOffice is absent on this machine
   so a docx→PDF leg could not be tested anyway.

---

## 11. Rulings

| ruling            | state                                                                 | detail                                                                                                                                                       |
| ----------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| R1 home           | **ANSWERED 2026-08-05 (canon conventions Q1–Q6), applied 2026-09-04** | encoding, sources, templates in `canon/subjects/contracts/investment/yc-safe-postmoney/`; tools in l4-ide `etc/safe/`; spec here (§4)                        |
| R2 pipeline       | **ANSWERED 2026-09-04**                                               | `go.sh` not run; source-bundle and fork-register schemas and cases-as-tests reused (§1)                                                                      |
| R3 factoring      | **ANSWERED 2026-09-04, on measurement**                               | economic variant = one sum type + two `CONSIDER` branches; jurisdiction = template family + validation enum; document = one template per published form (§3) |
| R4 templates      | **ANSWERED 2026-09-04**                                               | derived from verbatim source by a positional hole map; round-trip check is the "unmodified except blanks" proof (§5.3)                                       |
| R5 XMP            | **ANSWERED 2026-09-04**                                               | l4meta's `XMP-pdfx:L4` tag and config kept unchanged; payload schema v1.0 defined; plus a PDF attachment of the instance `.l4`; embed before signing (§5.4)  |
| R6 fixpoint       | **ANSWERED 2026-09-04**                                               | definition as written + closed form + assertion that they agree; fork F1 (§6.2)                                                                              |
| R7 round boundary | **ANSWERED 2026-09-04**                                               | Standard Preferred price is an input to the SAFE; the round module owns pricing and the pool shuffle; `deal.json.round` makes the convention explicit (§6.4) |
| R8 pre-money      | **ANSWERED 2026-09-04**                                               | separate leaf, sources only, encoding deferred (§2)                                                                                                          |
| R9 licence        | **ANSWERED 2026-09-04 as to conduct; the adaptation question OPEN**   | verbatim deposit with attribution; transaction fills; derived-and-proven templates; refuse unpublished cells; L4-as-adaptation recorded not resolved (§2)    |
| R10 renderer      | **ANSWERED 2026-09-04, on measurement**                               | mustache over the form; not TNR/Export.Document for the instrument; schedule rendered from L4 (§5.5)                                                         |

Meng has not reviewed R2–R10 as of writing; they are this session's rulings under the
autonomy Meng granted and are listed so a review can contest each one by number.

---

## 12. Build ledger

Filled in at the end of the session that wrote this file (2026-09-04). Each row says what
exists in the tree and what evidence it has. A row that is not here does not exist.

| item                                                                                                                                                                        | state                     | where                                                                                                                                               | evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| this spec, the variation register, the older notes                                                                                                                          | BUILT                     | l4-ide `specs/todo/yc-safe/` on branch `mengwong/yc-safe`                                                                                           | this file; `variation-register.md` (208 lines, 67 variation points, 12 surprises)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| L4 encoding: `safe-form.l4`, `safe.l4`, `safe-portfolio.l4`                                                                                                                 | BUILT                     | canon `subjects/contracts/investment/yc-safe-postmoney/encodings/legalese-2026-09/`                                                                 | `l4 check` clean on all three; `encoding.json` names three entrypoints (`validate deal`, `convert`, `liquidity`) and the batch field orders                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| acceptance cases (§7)                                                                                                                                                       | BUILT                     | `…/cases/user-guide-appendix-ii.l4`                                                                                                                 | 86 `#ASSERT`s satisfied, 0 failed: User Guide Example 1 Q1–Q5 plus synthetic mixed-portfolio and refusal cases; three `#TRACE`s of the MFN §3 provision; golden in `…/tests/`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| fixpoints F1–F2, round F4, rounding F3, liquidity F5                                                                                                                        | BUILT, resolved at encode | `…/registers/fork-register.json`                                                                                                                    | validates against `schemas/fork-register.schema.json` (17 rules, 2 skipped for want of a peer file)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| MFN §3 amendment provision as a regulative rule                                                                                                                             | BUILT                     | `safe.l4` §3                                                                                                                                        | three traces: election in time → FULFILLED; permission lapsing → FULFILLED; Company never restates → residual obligation shown                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| sources + provenance, footers, SHA256SUMS, `subject.json`, `SOURCE-LICENSE.md`, `templates/holes.json`; pre-money leaf (sources only); `GENRES.md`; README + NOTICE updates | BUILT                     | canon `subjects/contracts/…` (branch `mengwong/drafts`)                                                                                             | deposit agent + independent re-check: `shasum -c` 21/21 and 10/10; both `source-bundle.json` files validate (the `digest-matches-local-file` rule proven live against a corrupted digest); `source/md` regenerates byte-for-byte under pandoc 2.9.2.1; `holes.json` measured per form and extends the vocabulary by five names (`companyRegistrationNumber`, `companySignatureLine`, `investorSignatureLine`, `companyAddressLine2`, `investorAddressLine2`); the deposit's own `NOTES.md` records the MFN 1.3 stamp, the deliberate non-slug filenames, the Singapore brace hole, the Canadian DMS footer residue, and that the Wayback availability API is case-sensitive                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| generator `etc/safe/` (§5, §8)                                                                                                                                              | BUILT                     | l4-ide `etc/safe/` (`gen.mjs fill\|round\|verify`, `make-templates.mjs`, `check-templates.mjs`, `check-encoding.mjs`, `lib/`, `test/`, `README.md`) | run by the conductor against the real canon subject on 2026-09-04: `check-templates` 10/10 byte-for-byte (and a corrupted template is caught); `check-encoding` matches every `DECLARE`; `fill --pdf --docx` on `cases/deal.example.json` → 11 files + manifest (two SAFEs, one side letter, each as .md/.l4/.pdf/.docx); `round` → `conversion-schedule.md` + `conversion.json` reproducing Example 1; `verify` re-hashes the attachment, matches all three module hashes and re-checks the instance; XMP read back with l4meta's unmodified config; `qpdf --list-attachments` shows the instance; unpublished cells and a cap ≤ purchase amount are refused with exit 2; `node --test` 26/26; prettier 3.4.2 clean; the edition is read from the form's header stamp and a disagreeing `deal.form.edition` is refused (probed with 1.1 against the 1.2 form); `liquidity --proceeds 10000000` reproduces Q3 (Liquidity Capitalization 11,235,294, both convert). The filled Markdown appends, after a rule, the form's own footer (version stamp, licence sentence) and one italic provenance line saying what was filled — an addition below the form, not a change to it |
| §1(b)/(c)/(d) liquidity and dissolution                                                                                                                                     | BUILT                     | `safe.l4` §1(b)–(e), `safe-portfolio.l4` `liquidity`                                                                                                | Q3/Q4 reproduced: Liquidity Capitalization 11,235,294; per-share $0.8901; both convert at $10m, neither at $3m                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| static analyses D1, D5, D7, D8                                                                                                                                              | NOT BUILT                 | —                                                                                                                                                   | out of scope (§9)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| pre-money arithmetic; NVCA document set; signing; docx-native fill                                                                                                          | NOT BUILT                 | —                                                                                                                                                   | out of scope (§9), open (§10)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
