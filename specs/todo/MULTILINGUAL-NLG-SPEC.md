# Multilingual L4 — language-tagged `@nlg`, and the trilingual Penal Law

_Status: **proposed, not landed — with one exception.** §4 (the `%` and `]` escapes) is
**implemented, gated and adversarially reviewed** on branch `fix/nlg-escapes` (`590bc3c56` +
`53e9420d9`) and is **not merged**; everything else here is a proposal and no part of it is
implemented. Every measurement in §2 was executed on 2026-09-17 against `unstable` @
`cab6988d0` and canon `mengwong/drafts` @ `61a4755`. Seven measurement errors in earlier drafts
of this file have been corrected in place, each re-measured rather than taken on report —
§2.3's gap count, §2.4's annotation census and its bare-inline count, a line citation, three
dangling cross-references, `L4.Nlg`'s size, and §4's claim about where decoding happens; §2.4 and §4.1 carry
the corrections rather than hiding them. Written on branch `spec/multilingual-nlg`; §4.1 and
R-M7 by the `nlg-locale` session._

**One-line summary.** L4 can already be _written_ in any language — Hebrew identifiers work
today, verified — but it can only be _read back_ in one, because `@nlg` carries a single
untagged string per name. This spec adds a language tag to `@nlg`, gives it escapes for the
`%` delimiter and the `]` terminator, and teaches the projections a locale. The driving case is the Israeli Penal Law
5737-1977, whose Hebrew source is excellent and whose English translation is a **strict subset**
of it — measured, not assumed.

Everything asserted as "measured" below was executed this session and the command is given so it
can be re-run. Everything else is marked as proposal. §7 lists what is still open.

---

## 1. Why this is not "just add a translation"

An L4 identifier is one string. `` `the person is eligible` `` cannot simultaneously be
`` `הזכאות מתקיימת` `` and `` `يحق للشخص` ``. So multilingual L4 has exactly two shapes:

**(A) Parallel encodings** — one module set per language. This is what the Ofek Hadash Hebrew
sibling (`canon subjects/il/ofek-hadash-2008/encodings/legalese-he`) is doing, deliberately, as
an experiment on a 3,184-line encoding that is not under active amendment.

**(B) One canonical encoding plus a rendering layer** — identifiers in the authoritative
language, with `@nlg` carrying the other languages, and projections selecting by locale.

**This spec chooses (B) for the Penal Law, and (A) stays an experiment.** Three reasons; the
third decides it.

1. Parallel encodings drift and nothing catches it. The Penal Law is 644 sections under active
   amendment — Amendment 155 landed 2026-06-30 and was on Wikisource by 2026-07-07.
2. Renderings are what a projection layer is for. The wizard, ladder diagrams, docassemble
   output and `doc/` pages all want the reader's language, not the encoder's.
3. **(B) is the legally correct shape and (A) is not.** **Interpretation Law 5741-1981 §24**
   (הנוסח המחייב) provides that the binding text of a law is the text **in the language in which
   it was given** — with a proviso for a pre-State law given in English for which a נוסח חדש was
   determined under s.16 of the Law and Administration Ordinance 5708-1948, where the new
   version binds. Note the rule is **language-of-enactment, not "Hebrew always"**; secondary
   summaries that render §24 as "the Hebrew versions will be the guiding versions" are stating a
   consequence, not the provision. It reaches Hebrew for _this_ statute by application: the
   Penal Law is a נוסח מאוחד given in Hebrew (ס״ח תשל״ז, 226), superseding the Criminal Code
   Ordinance 1936, which was authoritative in English. So the 1936 English is displaced rather
   than parallel. **Basic Law: Israel as the Nation-State of the Jewish People §4** confirms
   Hebrew as the State language with Arabic holding special status — and the Knesset's own PDF
   labels its English rendering "unofficial", which is the neatest evidence for the whole
   argument. An Arabic or English rendering is therefore a reader aid and can never be the
   operative text; encoding them as peer modules would assert a parity that does not exist,
   while `@nlg` states exactly what they are.

---

## 2. What was measured

### 2.1 Wikisource carries Hebrew only

| language | on Wikisource | evidence                                                                                                   |
| -------- | ------------- | ---------------------------------------------------------------------------------------------------------- |
| Hebrew   | **yes**       | `he.wikisource.org/wiki/חוק_העונשין`, rev 3023424, deposited at `canon subjects/il/penal-law-1977/source/` |
| English  | **no**        | one search hit, a mention inside _R. v. Morgentaler_ (a Canadian case)                                     |
| Arabic   | **no**        | 140 hits, all Palestinian-Israeli accords and commentary; no Israeli statute text                          |

So the "pull all three off Wikisource" plan is not available. **The other two languages must be
generated from the encoding, not ingested beside it** — which is what (B) does anyway.

### 2.2 The Hebrew source is unusually good

The wikitext is not prose. It is the ספר החוקים הפתוח project's `ח:` template vocabulary —
24 distinct templates, 4,448 uses, maintained by `OpenLawBot`:

```
   666  ח:סעיף     section            909  ח:תת    subsection level 1
     7  ח:סעיף*    section (variant)  364  ח:תתת   level 2
     4  ח:קטע1     part                55  ח:תתתת  level 3
    21  ח:קטע2     chapter              6  ח:תתתתת level 4
    75  ח:קטע3     sign/sub-chapter   561  ח:ת     typed paragraph
 1,085  ח:פנימי    internal x-ref     180  ח:הערה  note
```

Re-run: `python3` over `source/penal-law-1977.wikitext`, counting `{{\s*(ח:[^|}\n]+?)\s*[|}]`.

Three properties matter for isomorphic encoding:

- **The tree is well-formed.** 673 section events in document order, **0 subsections appearing
  before any section**, and only **12 level skips** out of 1,334 subsection nodes (99.1% clean).
- **Sections are self-describing.** `{{ח:סעיף|2|ענישה לפי חקיקת משנה|תיקון: תשנ״ד־3, תשפ״ב־2}}`
  carries number, title _and_ an inline amendment trail. **455 of 673 sections (67%)** carry a
  `תיקון:` trail, so per-section provenance is free.
- **Definitions are semantically tagged.** `{{ח:ת|סוג=הגדרה}}` marks a definition paragraph —
  **73** of them. That is the `DECLARE`/`MEANS` boundary handed to us by the source.
- **There is a link graph.** 1,085 internal cross-references over 613 distinct targets. Most
  referenced: `סעיף 61` (19), `סעיף 368א` (14), `פרק ז` (13).

### 2.3 The English translation is a strict subset — the key finding

The complete English text exists at
`https://www.icj.org/wp-content/uploads/2013/05/Israel-Penal-Law-5737-1977-eng.pdf`
(146 pages, 348,647 characters, extracts cleanly with `pdftotext`). The ICJ hosts it in its
**SOGI national legislation** database with _no stated translator, date, amendment currency or
copyright_ — the page offers only a download link dated "Feb 9, 1978". Provenance is the
problem here, not completeness.

Comparing section inventories, with Hebrew suffixes normalised as **gematria** (`יא` = 11 → `K`,
not `J`+`A`):

```
Hebrew sections : 644
English sections: 592
in BOTH         : 592          <- 100% of the English exists in the Hebrew
ENGLISH-only    :   0
English coverage of Hebrew: 91.9%
```

**Zero English-only sections.** The translation never contradicts the current Hebrew; it only
stops short. That is the best possible shape for version skew — the gap is purely additive and
fully enumerable. The 52 sections needing fresh translation:

```
34W, 40A-40O (15), 50, 51, 71C, 71D, 71E, 86B, 122A, 138, 144D, 188, 205D,
207, 210, 211, 212, 213, 265, 266, 275A, 275B, 301A, 301B, 301C, 311A,
332A, 347B, 357, 358, 359, 360, 382A, 384A, 428A, 428B, 434, 435
```

And the gap is legible rather than scattered — it clusters on identifiable reform blocks:
`40A-40O` is the sentencing-principles chapter (תשע״ב / 2012), `301A-301C` the murder reform
(תשע״ט / 2019, amended תשפ״ו / 2026), `428A-428B` protection racket (תשפ״ג / 2023).

> **Two measurement errors were made and corrected while producing this table; both inflated the
> gap, and both are worth recording because either would have shipped a false number.**
> (i) Transliterating Hebrew suffixes letter-by-letter rather than as gematria turned `34יא`
> into `34JA` instead of `34K`, manufacturing ~24 phantom divergences in the 34-series alone.
> (ii) Requiring whitespace after the section period (`^\s*(\d+)([A-Z]*)\.\s`) missed every
> section the PDF typesets as `34R.(a)` or `34S.For`, dropping 24 real matches. The first draft
> of this section read "76 Hebrew-only sections"; the true figure is 52.

### 2.4 `@nlg` today: one language, no escape

Read from `jl4-core/src/L4/Lexer.hs` on `unstable`:

```haskell
nlgAnnotation :: Lexer (Text, AnnoType)
data AnnoType = InlineAnno | LineAnno          -- the whole type; no language field

nlgExprDelimiterSymbol :: Char
nlgExprDelimiterSymbol = '%'

nlgString :: Lexer Text
nlgString = takeWhile1P (Just "character")
              (\c -> c `notElem` nlgSpecialChars && not (isSpace c))
  where nlgSpecialChars = [ nlgInlineAnnotationCloseChar, nlgExprDelimiterSymbol ]
```

- **No language tag exists.** One untagged string per name. **131 annotations** across the
  corpus, all English. (`grep -c '@nlg'` reports 140 _lines_; 9 of those are `--` comments
  that merely mention it. Count annotations, not lines.)
- **No escape mechanism exists anywhere.** There is no backslash handling in the NLG path.

> **Prior art, and it narrows this considerably.** smucclaw/l4-ide#957 already fixed the
> common case by making the delimiters **tight**: `% word %` with spaces is prose, not a
> reference, so `@nlg 5% with %amount%` binds only `amount`. That fix ships with a corpus
> witness (`jl4/examples/ok/nlg-percent.l4`) and a unit spec
> (`jl4-core/test/NlgPercentSpec.hs`) whose header explains why both are needed — the corpus
> golden can witness the loud half (captured word not in scope → type error) but not the quiet
> half (captured word in scope → binds the wrong parameter, silently). **Read that spec before
> touching this area; it is the model for how to test it.**
>
> What tightness does **not** reach is a `%…%` pair with _no internal whitespace_, which is
> what the escape below is for. The residue is narrow but real.

> **Correction, 2026-09-17.** An earlier draft of this section read "**a literal `%` in an
> `@nlg` annotation is unrepresentable**". That was wrong, and it was wrong in the way this
> repo's anti-drift rules warn about: it was inferred from reading `nlgString` and never
> executed. `nlgString` is only the tokenizer; a later parser decides what is an
> interpolation, and it is far more forgiving than the character class suggests. The measured
> behaviour is below and is **narrower, but worse**, because the failure is silent.

**Measured with `l4 nlg` on 2026-09-17** (the `l4 nlg` subcommand prints the linearization,
which is the `.nlg.golden` payload):

| written                     | renders as                    | verdict                             |
| --------------------------- | ----------------------------- | ----------------------------------- |
| `10% of %n%`                | `10% of ` + _n_               | fine — a lone `%` is safe           |
| `%n% is 50%`                | _n_ + ` is 50%`               | fine                                |
| `10%%  of %n%`              | `10%% of ` + _n_              | `%%` is **not** an escape today     |
| `between 10%and%20 for %n%` | `between 10` + _and_ + `20 …` | **silently wrong**                  |
| `x %nosuchname% y`          | `x ` + _nosuchname_ + ` y`    | **no error for an unresolved name** |

So the real defect is not "`%` is unrepresentable" but: **a `%…%` pair enclosing a bare word
with no internal whitespace is interpolated, and a name that resolves to nothing renders as a
quoted name instead of erroring.** Two silent failures composing — and the first is exactly
the residue #957's tightness rule leaves behind, since tightness keys on whitespace.

**The close bracket is a separate defect, and it fails loudly.** The two annotation forms
differ because `nlgAnnotation = lineAnno "@nlg" <|> inlineAnno "[" "]"` tries `lineAnno`
first:

- `lineAnno` is `takeWhileP (/= '\n')` — it grabs the rest of the line raw, so `]` and `[` are
  ordinary characters there. `@nlg the levy [see s.3] on %n%` renders correctly.
- `inlineAnno` is `manyTill_ anySingle (string "]")` — it stops at the **first** `]`. This is
  reached by a **bare** `[…]` annotation, not by `@nlg […]`. Measured: a bare
  `` `the levy on` n [a ] literal] MEANS … `` fails with `unexpected ]`, because ` literal]`
  is left for the enclosing parser.

| form          | literal `%`                                      | literal `]`                           |
| ------------- | ------------------------------------------------ | ------------------------------------- |
| `@nlg …` line | safe unless `%word%` with no spaces (**silent**) | safe, passes through                  |
| `[…]` bare    | safe                                             | truncates → `unexpected ]` (**loud**) |

Sorting these by how they fail is what decides the priority: the `]` case announces itself and
the `%` case does not, so the `%` case is the one that reaches production.

Corpus exposure: of the 131 annotations, **0** contain `%%` and **0** contain a backslash, so
any escape convention is free to adopt — nothing existing uses the characters an escape would
claim.

> **Correction, 2026-09-17.** An earlier draft added "there are 2 bare inline annotations". That
> number measured the wrong thing: the command was `grep -c '@nlg *\['`, which counts `@nlg [`
> — and those are **line**-form annotations with decorative brackets, since `lineAnno "@nlg"` is
> tried first. The count of annotations reaching `inlineAnno` _that_ way is **zero**. Bare
> `[…]` annotations, which do reach it, are common corpus-wide. **So a change to `inlineAnno`
> has a wide blast radius, not a two-site one** — and it is wider still because `inlineAnno` has
> a second caller, `refAnnotation`'s `<<`/`>>` (§4).

### 2.6 A live defect that lands on every Hebrew golden — smucclaw/l4-ide#962

**`.schema.golden` files double-encode every non-ASCII character** (`BL.unpack` over UTF-8
bytes), and the corruption **round-trips**, so the golden suite stays green while storing
mojibake. Independently reproduced here on 2026-09-17: the same German source text appears as

```
fristberechnung.schema.golden : eine WillenserklÃ¤rung ist abzugeben    <- ä as C3 83 C2 A4
fristberechnung.ep.golden     : § 186–193                              <- correct
```

so it is specific to the schema goldens, not to the corpus file. Two schema goldens in the tree
carry non-ASCII today and both are affected.

**This is on the critical path for §3 and for §8 step 4.** A Hebrew-canonical encoding produces a
schema golden per file, so every one would silently carry corrupted Hebrew, and re-running the
suite would confirm it as correct. Fix #962 before blessing any Hebrew golden, or the first
thing the encoding proves is the wrong thing. It belongs to the same family as the `%` defect in
§2.4 and the `prettyLayout` gap in the repo's own `CLAUDE.md` §3.2.1: **loud failures teach, and
silent ones ship.**

### 2.5 Non-Latin identifiers already work

Verified 2026-09-16 (see `skills/writing-l4-rules` and the `multilingual-l4-hebrew` memory).
`L4.Lexer.identifier` is `satisfy isAlpha` + `isAlphaNum`, and Haskell's `isAlpha` is Unicode
general-category-based, so Hebrew (`Lo`) and Arabic pass with no special casing. Backticked
names use `isPrint`. `l4 format` round-trips Hebrew byte-identical.

**The one hard limit:** bidi control marks (RLM U+200F, LRM U+200E, category `Cf`) are a **lex
error** inside backticks — `isPrint` is `False` for `Cf`. A `.l4` file cannot carry the marks an
editor would want for RTL display and must rely on the viewer's bidi algorithm. This constrains
§5.

---

## 3. Proposed: language-tagged `@nlg`

**Surface syntax (proposal, R-M1 open):**

```l4
GIVEN person IS A Person
GIVETH A BOOLEAN
DECIDE `the person is criminally liable` IF ...
  @nlg     %person% is criminally liable
  @nlg:he  %person% נושא באחריות פלילית
  @nlg:ar  %person% يتحمل المسؤولية الجنائية
```

Requirements:

1. **Untagged `@nlg` keeps working unchanged.** All 131 existing annotations must lex, parse and render
   exactly as now. Untagged means "the module's default language".
2. **The tag is a BCP 47 language subtag** (`he`, `ar`, `en`, `en-GB`), validated at lex time
   against a shape, not a closed list.
3. **A module declares its own default language** so untagged annotations are not implicitly
   English. Proposal: a module-level `@lang he` annotation; R-M2.
4. **Duplicate tags on one name are a check error**, not last-wins.
5. **Whatever the spelling, it must work for the bare `[…]` form too** — and that is the
   constraint that actually narrows R-M1. See below.

**Measured 2026-09-17, and it rules out more than it looks.** The `@nlg:he` spelling in the
block above only works on the LINE form. The inline form has no herald to hang a tag on:
`toAnno`'s inline branch is `oh <> t <> ch`, i.e. `[` + text + `]`, with no free position. So
a tagged inline annotation has to put the tag INSIDE the brackets — `[he: …]` — and that
collides with prose, because a colon is an ordinary character in annotation text today:

| written                       | renders as (`l4 render --format text`) |
| ----------------------------- | -------------------------------------- |
| `[he: a colon in prose, %c%]` | `he: a colon in prose, c`              |
| `["the quoted form", %n%]`    | `"the quoted form", n`                 |

Two consequences, and neither is obvious from the line form alone:

- **`[he: …]` is ambiguous with existing prose** and cannot be adopted without a rule for
  telling a tag from a sentence that happens to begin with a two-letter word and a colon.
- **`@nlg he "…"` is worse than it looks**, because a double quote is ordinary text too. Two
  annotations in the tree already open with one — `doc/reference/syntax/annotation-example.l4`
  and `directive-example.l4`, both **user-facing documentation** — so that spelling changes
  the meaning of text that ships as an example of how to write `@nlg`.

The line form is the easy half and has no collision: 2 of the 140 `@nlg` lines contain a
colon and both are `--` comments, so `@nlg:he` is free to take there. **R-M1 should be decided
on the inline form, not the line form**, and the options worth costing are a distinct herald
(`[he| …]`, `[@he …]`) or leaving the inline form untaggable and requiring the line form for
any non-default language. This is evidence for the ruling, not the ruling: R-M1 stays OPEN.

**Type changes.** `AnnoType` stays; the language rides on the NLG payload:

```haskell
data TAnnotations = ... | TNlg !Text !AnnoType          -- today
                  | ... | TNlg !(Maybe LangTag) !Text !AnnoType   -- proposed
```

`L4.Nlg` (509 lines at `cab6988d0`) selects by requested locale with explicit fallback. **A miss must be
visible**: rendering an English page for a name that has only `@nlg:he` must emit the Hebrew
_and record the fallback in the projection's fidelity report_, never silently substitute.

## 4. Escapes for `%` and `]` — IMPLEMENTED on `fix/nlg-escapes`, not merged

Independent of the language work and being landed first, because both are live defects today
(§2.4). **Branch `fix/nlg-escapes` (`590bc3c56` + `53e9420d9`); built, tested and gated
2026-09-17, reviewed adversarially (§4.1), not merged.**

**Convention chosen: backslash.** `\%` → literal `%`, `\]` → literal `]`, `\\` → literal `\`.
Any other `\x` is left untouched — the lexer consumes exactly the three escapes the decoder
honours, so a backslash that cannot begin one stays an ordinary character, as it was before
escapes existed. Nothing existing changes because **no `.l4` file in the tree contains a
backslash at all** (measured 2026-09-17 at `cab6988d0`). That is a measurement, not a
guarantee: an annotation that did contain `\%`, `\]` or `\\` would now render differently.

Backslash over the printf-style `%%` that an earlier draft recommended, for two reasons:
doubling does not generalise — `]]` as an escape for `]` reads badly and collides with the eye
inside a bracketed annotation — and L4 string literals already use Haskell escapes
(`showStringLit`), so backslash is the convention the language has. Both are equally safe to
adopt: §2.4 measured 0 uses of either in the corpus.

**The implementation constraint that shapes this.** `TNlg`'s text is re-emitted verbatim by
`toNlgAnno` for exactprint (`Lexer.hs:1122`), and `jl4-test` asserts an `exactprint identity`
law. So escapes must **not** be decoded at annotation-capture time. The split, mirroring how
`TStringLit` carries `raw` and `decoded`:

- `inlineNlgAnno` — the `[…]` lexer — keeps the backslash in the captured text, and only stops
  treating `\]` as the terminator. The raw slice still round-trips.
- `nlgString` — the second-pass tokenizer over already-captured annotation text — consumes an
  escape as a **unit** but keeps it **verbatim**. Consuming it as a unit is what stops the `%`
  in `\%` from reaching `nlgExprDelimiter` and opening an interpolation.
- `L4.Nlg.unescapeNlgText` decodes, at **every** render site.

> **Do not decode in `nlgString`.** It was written that way first and it is wrong, because
> `displayTokenType` maps `TNlgString t -> t` (`Lexer.hs:1126`) — that token's text is what
> exactprint re-emits, so `nlgString` is on the **print** path as much as the render path.
> Measured with the decode there: `l4 format` stripped the backslash from both forms, turning
> `[a \] literal]` into `[a ] literal]`, which no longer parses, and `10\%and\%20` into
> `10%and%20`, which parses and **silently means something else**. The loud half would have
> been caught by any round-trip test; the silent half is the one that reaches production.

### 4.1 What an adversarial review changed, and the two rulings inside it

The first cut (`590bc3c56`) passed the full gate — build, 3,467 golden examples, `exactprint
identity`, the `prettyLayout` round-trip, `l4-cli-test`, `jl4-core-test`. A four-dimension
adversarial pass over it returned **15 findings, 0 refuted**. Three mattered, and the green
gate is the reason they are worth recording rather than just fixing.

**(a) `@ref` was collateral damage.** `inlineAnno` has two callers, and the escape went into
the shared body, so it reached `refAnnotation`'s `<<`/`>>` form. Nothing decodes a ref escape,
so `<<sec 3\>>` did not merely capture the wrong text — `\>` was consumed as a unit and the
annotation ran on to the **next** `>>` in the file, or, with none, failed the whole file's lex
pointing at end-of-input rather than at the annotation. The repair splits the function:
`inlineAnno` returns to its base body for `@ref`, and the NLG form gets `inlineNlgAnno`.
Because `]` is one character, the `notFollowedBy` machinery that kept `<<a > b>>` working is
no longer needed and went with it.

> **Ruling — a literal `>>` inside `<<…>>` stays unrepresentable.** It was unrepresentable
> before this work and the escape does not extend to it. `refAnnotation` is outside what this
> spec rules on, and widening a change to a second annotation family on a fix branch's own
> initiative is not that branch's call. The mechanism would be cheap — the decode side would
> need `>` added — but it wants its own ruling. Raised by the `hebrew` session, agreed here.

**(b) The lexer and the decoder disagreed about what an escape is.** The lexer consumed `\`
plus _any_ character; `unescapeNlgText` decodes only `\\`, `\%`, `\]`. A pair the lexer
swallowed and the decoder ignored changes what an annotation **captures** without changing
what it **renders** — and it turned two shapes that lex today into parse errors, including an
`@nlg` line annotation ending in a backslash, where there is no closing herald and so nothing
to escape. `L4.Lexer.isNlgEscapable` is now the single set both sides use.

**(c) The feature was half-wired, and the corpus goldens could not see it.**
`unescapeNlgText` was reached only from `Linearize Nlg`, and an earlier draft of this section
asserted that was "the single point where annotation text becomes output". **That was false.**
`l4 render` (text, html, json, akn), the LSP document webview and `l4 blawx` each emitted the
backslash to the reader. Worse, deleting every call site left the whole suite green: nothing
asserted rendered annotation text, and nothing could — **no `.nlg.golden` in the tree
witnesses annotation prose at all**, because that golden linearizes _directives_ and
`Linearize (Directive Resolved)` routes `#EVAL` through `linearize e` rather than `lin e`. The
repair adds `NlgRenderSpec`, which drives `buildDocument` end to end.

> **Ruling — `Relational.Lower.linearNlg` does NOT decode, and that is deliberate.** Its
> output is re-scanned for `%name%` slots by `Blawx.Lower.scanNlg`. Decoding there turns
> `10\%and\%20` back into `10%and%20` and manufactures exactly the phantom slot the escape
> exists to prevent — `slotNameShaped "and"` is `True`. The decode belongs to the literal
> chunks the scan returns, i.e. in `nlgChunks`. Worth recording because two of the three
> reviewers proposed decoding at both sites and the dissenting one was right: the majority
> reading would have reintroduced the bug one layer down. The invariant is now a comment at
> `linearNlg` so the next reader does not "fix" it.

**Every new test was mutation-checked** — the fix was broken three ways and each test watched
to go red: an unwired decoder turns 3 of `NlgRenderSpec`'s 4 examples red (the 4th is its own
positive control and correctly stays green), re-sharing the escaping body turns the
trailing-backslash `@ref` case red, and an escape no longer consumed as a unit turns the new
fragment-level assertion red. That last one matters most: the _existing_ escaped-percent test
passes on the **pre-fix** lexer too, because #957's tightness rule already declines `% and %`
— so the entire `nlgString` hunk could have been reverted with every test green.

**The consumer audit, now done — and it came up clean.** An earlier draft of this section
listed the other consumers of the relational IR's `@nlg` fields
(`tdNlg`/`adNlg`/`rfNlg`/`dsNlg`) as an unaudited leak. Measured 2026-09-17: all four are
`linearNlg`-fed and so all carry escapes undecoded, as does `rpNlg`, which they flow into.
Outside `Relational.Lower` and `Relational.IR` they reach **exactly two readers**:
`Blawx.Lower`'s `attrNlg` (twice) and `relationship`, all three of which route through
`nlgChunks` and are therefore already covered; and `Relational.Debug`, which dumps the IR and
is the golden contract for the relational middle-end — where **verbatim is correct**, because
a dump that decoded would disagree with what the IR holds and would hide this invariant from
the goldens that exist to expose it. The audit is recorded at `linearNlg` with line numbers,
not here, because that is where the next person to add a consumer will be reading.

**Still owed.** One thing only: there is no corpus `.l4` case carrying a backslash inside
`<<…>>`, so the `@ref` half of §4.1(a) is pinned by `RefAnnotationSpec` but not by the corpus.

## 5. Proposed: locale in the projections

There is **no i18n layer in `ts-apps/` today** — the `lang=` hits are incidental (`app.html`
carries `lang="en"`).

1. Projections take a locale: the wizard, ladder diagrams, `l4 docassemble`, `l4 render`.
2. **RTL.** Hebrew and Arabic are both RTL, so `dir="rtl"` plus a correct `lang` attribute
   serves both and the work is shared. Arabic additionally needs shaping and ligatures, which
   browsers handle — this is a font-stack concern, not a layout one.
3. **The `.l4` source stays free of bidi control characters** (§2.5). Display-side correctness
   is the renderer's job, driven by `dir`/`lang`, never by characters embedded in the source.
4. Mixed-direction content (an RTL sentence containing a Latin citation or a number) is where
   this gets hard. Isolate interpolated spans with `<bdi>` rather than control characters.

## 6. Rulings

| #        | question                                                                                        | state                                                                                                                                                                                                                                                                           |
| -------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **R-M1** | `@nlg:he` vs `@nlg he "…"` vs a separate `@lang` block — which surface syntax?                  | **OPEN**                                                                                                                                                                                                                                                                        |
| **R-M2** | How does a module declare its default language for untagged `@nlg`?                             | **OPEN**                                                                                                                                                                                                                                                                        |
| **R-M3** | Escape convention for a literal `%` and `]`?                                                    | **ANSWERED 2026-09-17**, §4: **backslash** (`\%`, `\]`, `\\`). Doubling does not generalise to `]`, and L4 string literals already use Haskell escapes. Measured 0 corpus uses of either convention, so both were free to take                                                  |
| **R-M4** | One canonical encoding + `@nlg` (B), not parallel per-language encodings (A), for the Penal Law | **ANSWERED 2026-09-17**, §1. Driven by: 644 sections under active amendment; Amendment 155 reached Wikisource in 7 days; and the legal-status argument in §1, point 3                                                                                                           |
| **R-M5** | Which language is canonical for `il/penal-law-1977`?                                            | **ANSWERED 2026-09-17**: **Hebrew.** It is the enacted and binding text, it is the only one on Wikisource, and it is the only one current to Amendment 155                                                                                                                      |
| **R-M6** | Is the ICJ English text usable for `@nlg:en`?                                                   | **SPLIT 2026-09-17.** _Depositing_ it in canon stays **OPEN** — complete (592/592 match Hebrew, §2.3) but no stated translator, date or licence. _Consulting_ it is **ANSWERED: yes**, and is the better use — see §6.1                                                         |
| **R-M7** | Confirm the Hebrew-binds / Arabic-special-status claim against primary sources                  | **ANSWERED 2026-09-17**, §1 point 3: Interpretation Law 5741-1981 §24 and Basic Law: Nation-State §4, both read in the primary text. The rule is language-of-enactment rather than "Hebrew always"; it reaches Hebrew here by application. Verified by the `nlg-locale` session |
| **R-M8** | Where do Arabic renderings come from, given no Arabic statute text exists?                      | **OPEN.** Note the scope is a _term glossary_, not a 644-section translation — the encoding's vocabulary, not the statute                                                                                                                                                       |

### 6.1 The ICJ text as a Rosetta Stone, not a source

The provenance problem in R-M6 is a **redistribution** problem, not a **reading** problem. We do
not need a licence to consult a translation for terminology; we need one to ship it. So the
useful role for the ICJ text is as a bilingual alignment corpus, not as a deposited source:

- It is already aligned at section granularity, and the alignment is now measured — 592 sections
  present in both, 0 English-only (§2.3). That is a **parallel corpus of 592 Hebrew/English
  section pairs** for free.
- It answers the question that actually slows an encoder down: _what does this Hebrew term of art
  become in English?_ — `מחשבה פלילית`, `רשלנות`, `עבירת מטרה`, `הסתברות קרובה לוודאי`. Those are
  the `@nlg:en` strings, and having a published translation's word for each is worth more than
  inventing one.
- Consulting it leaves no trace in canon that needs a licence. What lands is _our_ `@nlg:en`
  string, informed by it.

This also means it can guide the encoding more indirectly, which is the subtler benefit: where
the Hebrew is structurally ambiguous, a professional translator has already committed to a
reading, and a disagreement between that reading and ours is a signal worth stopping on. Treat a
divergence as a question to resolve against the Hebrew, never as a defect in either text.

**The 52-section gap (§2.3) is where this stops helping**, and it stops abruptly — those sections
have no counterpart to consult, so their English is ours alone and should be marked as such.

## 7. What this spec does NOT decide

- **The Penal Law encoding itself.** This is the multilingual mechanism. What of 644 sections
  gets encoded, and in what order, belongs in a Penal Law subject spec. The `pacing_note` in
  `canon subjects/il/penal-law-1977/subject.json` already pairs it with `sg/penal-code-1871` and
  asks for one ontology of offence elements across both — that constraint is not addressed here.
- **Whether `ח:` wikitext gets a real parser.** §2.2 measures that the structure is clean enough
  to warrant one. Building it is separate work.
- **Machine translation.** Nothing here proposes generating `@nlg` strings automatically. Every
  measurement above is about _where authored text comes from_.
- **GF / Grammatical Framework.** Prior work concluded hand-written GF grammars are infeasible
  at this scale; this spec deliberately proposes flat per-name strings instead. If that is
  revisited, it supersedes §3.

## 8. Suggested order of work

1. **`%` and `]` escapes (R-M3).** ~~Smallest, independent, fixes two live defects.~~ **Done
   on `fix/nlg-escapes`, awaiting review** — and it was not the smallest. It reached a second
   annotation family, a second lexer and three renderers before it was finished; §4.1 is the
   account. Read that before step 2, because the language tag touches the same three places
   and the same green-gate-proves-nothing trap applies to it.
2. **Language tag (R-M1, R-M2).** Lexer, `L4.Nlg` selection, check error on duplicates, goldens.
   Untagged behaviour must be provably unchanged — assert against the existing 131 annotations.
3. **Projection locale (§5).** Start with `l4 render` and the docs, which have no interactive
   surface; the wizard and ladder diagrams follow.
4. **Penal Law pilot.** One chapter, Hebrew-canonical, with `@nlg:en` drawn from the ICJ text
   _subject to R-M6_, to exercise the whole path before committing to 644 sections.

## 9. Reproducing the measurements

All inputs are already deposited; nothing needs re-fetching.

```bash
CANON=~/src/legalese/canon/subjects/il/penal-law-1977/source
# 2.2 template inventory and tree well-formedness
python3 - "$CANON/penal-law-1977.wikitext"     # see §2.2 for the regexes
# 2.3 requires the ICJ PDF, which is NOT in canon (R-M6 unresolved):
curl -sfL -o /tmp/icj.pdf \
  https://www.icj.org/wp-content/uploads/2013/05/Israel-Penal-Law-5737-1977-eng.pdf
pdftotext /tmp/icj.pdf /tmp/icj.txt
# then diff section inventories, normalising Hebrew suffixes as GEMATRIA (§2.3)
# 2.4 @nlg has no language field and no escape
grep -n "nlgAnnotation ::\|nlgExprDelimiterSymbol\|^nlgString ::" -A 6 \
  jl4-core/src/L4/Lexer.hs
```
