# Multilingual L4 — language-tagged `@nlg`, and the trilingual Penal Law

_Status: **§§3–4 are IMPLEMENTED AND MERGED; §5 and the pilot are still proposals.**
Updated 2026-09-19. §4 (the `%` and `]` escapes) merged as PR #415, §4.1(a)'s `\>` escape for
`@ref` as PR #418, this spec's own revisions as #416, the `#962` schema-golden fix as #419, and
the language tag itself as **#423** — verified in `unstable` by feature presence
(`MkLangTag`, `NlgLangTagSpec`), not by report. Multiplicity, selection and
`prettyLayout`'s annotation loss are on `fix/prettylayout-nlg` and `lang/nlg-multiplicity`.
**A bilingual document set is producible today**: two `@nlg:xx` renderings on one name, and
`l4 nlg --lang he` / `--lang en` over one encoding. §8a records what was built, what was
deliberately not, and the one live defect found on the way._ Every measurement in §2 was executed on 2026-09-17 against `unstable` @
`cab6988d0` and canon `mengwong/drafts` @ `61a4755`. Eight measurement errors in earlier drafts
of this file have been corrected in place, each re-measured rather than taken on report —
§2.3's gap count (twice: 76 → 52 → 59, the last on 2026-09-21), §2.4's annotation census and its bare-inline count, a line citation, three
dangling cross-references, `L4.Nlg`'s size, and §4's claim about where decoding happens; §2.4 and §4.1 carry
the corrections rather than hiding them. Written on branch `spec/multilingual-nlg`; §4.1 and
R-M7 by the `nlg-locale` session.\_

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

1. Parallel encodings drift and nothing catches it. The Penal Law is 651 sections under active
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

- **The tree is well-formed.** 673 section-template events in document order (666 `ח:סעיף` + 7 `ח:סעיף*`; see the count note under §2.3), **0 subsections appearing
  before any section**, and only **12 level skips** out of 1,334 subsection nodes (99.1% clean).
- **Sections are self-describing.** `{{ח:סעיף|2|ענישה לפי חקיקת משנה|תיקון: תשנ״ד־3, תשפ״ב־2}}`
  carries number, title _and_ an inline amendment trail. **456 of 651 sections (70%)** carry a
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
Hebrew sections : 651
English sections: 592
in BOTH         : 592          <- 100% of the English exists in the Hebrew
ENGLISH-only    :   0
English coverage of Hebrew: 90.9%
```

**Zero English-only sections.** The translation never contradicts the current Hebrew; it only
stops short. That is the best possible shape for version skew — the gap is purely additive and
fully enumerable. The 59 sections needing fresh translation:

```
34J1, 34W, 40A-40O (15), 50, 51, 51H1, 51J1, 71C, 71D, 71E, 86B, 122A, 138,
144D, 144D1, 144D2, 144D3, 188, 205D, 207, 210, 211, 212, 213, 265, 266,
275A, 275B, 301A, 301B, 301C, 311A, 332A, 347B, 357, 358, 359, 360, 368C1,
382A, 384A, 428A, 428B, 434, 435
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
> of this section read "76 Hebrew-only sections"; that draft's correction said 52.
> (iii) **Corrected 2026-09-21 (HEPTAGON): 52 was also wrong, by seven, and so was every figure
> derived from the Hebrew inventory.**
> The normaliser accepted `\d+` plus Hebrew letters and nothing after, so a section id with a
> **trailing digit** — a second-level insertion such as `144ד1`, the section inserted after `144ד` —
> was silently dropped from the Hebrew side.
> Seven sections have that shape: `34י1`, `51ח1`, `51י1`, `144ד1`, `144ד2`, `144ד3`, `368ג1`
> (`34J1`, `51H1`, `51J1`, `144D1`–`144D3`, `368C1` after gematria).
> All seven are real, titled sections — `34י1` is the defence-of-dwelling provision, `144ד2` is
> incitement to violence — and none is in the ICJ text, so all seven belong in the gap list above.
> Hebrew inventory 644 → **651**; Hebrew-only 52 → **59**; coverage 91.9% → **90.9%**.
> The two findings that matter did not move: **zero English-only sections**, and 592 in both.
> Two things about how this was found are worth more than the number.
> The 651 came from a different instrument — counting `ח:סעיף` templates by part in the deposited
> wikitext, where it is also the figure in canon's `subject.json` since `5cf2878` — and the 644 was
> only ever "the number this script printed", with no second count to disagree with it.
> And the previous correction, "the true figure is 52", was written with exactly the confidence
> this note now has; it was one comparison against an independent count away from being caught.
> Every number in §2.2 and §2.3 is now produced by the runnable code in §9, and a re-run that
> disagrees with this section says which figure moved.
> Note also that `455 of 673` in §2.2 divided by a denominator containing the 7 `ח:סעיף*`
> schedule items, which are a different template; over the 651 sections of the Act it is 456 (70%).
> The non-greedy regex that produced 455 also stops at the first `}}` of a cross-reference nested
> inside a section title, missing the trail on `34כג`, `40א` and `86א`; count on the header line.

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
5. **The bare `[…]` form is deliberately NOT taggable** (R-M1, ruled 2026-09-17). It carries
   short parameter glosses — `[person]`, `[the foo]` — not sentences, which is the term-glossary
   layer rather than the rendering layer. `[@he …]` is **pre-approved** as its spelling if and
   when the need is actually encountered; it is not to be built speculatively.

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

The heralded form is the easy half and has no collision: 2 of the 140 `@nlg` lines contain a
colon and both are `--` comments, so `@nlg:he` is free to take there.

> **RULED 2026-09-17 (Meng).** `@nlg:he` on the heralded form. The bare `[…]` form **stays
> untaggable**, because the two populations carry different things — 131 heralded annotations
> carry sentences, ~50+ bare inline ones carry short glosses. **`[@he …]` is pre-approved** as
> the bare form's spelling for when a real need appears, so that decision does not have to be
> re-litigated then; it is explicitly not a licence to build it now.
>
> `@nlg he "…"` was **rejected on measurement**: a double quote is ordinary prose today, and two
> annotations in `doc/reference/syntax/` already open with one — so that spelling would change
> the meaning of text shipping as documentation about how to write `@nlg`.

**Type changes.** `AnnoType` stays; the language rides on the NLG payload:

```haskell
data TAnnotations = ... | TNlg !Text !AnnoType          -- today
                  | ... | TNlg !(Maybe LangTag) !Text !AnnoType   -- proposed
```

`L4.Nlg` (509 lines at `cab6988d0`) selects by requested locale with explicit fallback. **A miss must be
visible**: rendering an English page for a name that has only `@nlg:he` must emit the Hebrew
_and record the fallback in the projection's fidelity report_, never silently substitute.

### 3.1 What the tag actually touches — mapped 2026-09-18

Seven parallel readers over the subsystems, plus a completeness critic that overturned a
consensus of four of them (§4.1(c) carries that correction). Everything below was measured on
`lang/ref-escape`; probes were run with the installed `l4`, which is older than that branch but
newer than every construct probed.

**The blocker is not the lexer, and it fails silently.** `Extension.nlg` is a **single slot**
(`Syntax.hs:867`, `annNlg :: Lens' Anno (Maybe Nlg)`), and `HasNlg Name`
(`ResolveAnnotation.hs:387-401`) handles two `@nlg` on one name by emitting an `Ambiguous`
**warning and attaching neither**. Reproduced: `@nlg` and `@nlg:he` on one `DECIDE` gives
`Severity: Warning`, **exit 0**, and a render that falls back to the bare name — so the spec's own
bilingual example renders nothing for that name even with a perfect lexer. A half-wired tag
**erases prose while the build stays green**, which is §4.1(c)'s failure one layer up.

**`@nlg:he` is already accepted today, silently, as English prose.** Measured: it lexes to the NLG
fragments `":he" "the" …`, `l4 check` exits 0 with no diagnostic, `l4 render` prints
`… :he the taxpayer owing k is caught`, and `l4 format` round-trips byte-identically. **So a
Hebrew fixture written before the feature lands is green and wrong, and no golden catches it.**
`@lang en`, by contrast, is a hard lex error today (`unexpected '@'`, exit 1) — nothing written
against `@lang` can silently change meaning. The two halves of the proposal have opposite safety
properties and that should drive which lands first.

**The renderer has no notion of language at all — measured, and it makes the degenerate default
more degenerate than §8 assumed.** A Hebrew `@nlg` renders Hebrew **today**, with no tag, no
`@lang`, and no change to anything:

```l4
DECIDE `chayav` @nlg הנישום החייב ב-%a% נתפס
  IF a > 5
#EVAL `chayav` 7
```

→ `l4 nlg` prints `הנישום החייב ב-`a` נתפס with 7`, and `l4 render --format text` prints
`Chayav holds if הנישום החייב ב-a נתפס.` So the renderer emits whatever bytes the annotation
holds; **English is a property of the corpus, not of the renderer**, and there is no language
concept anywhere for a tag to extend. The tag does not teach L4 to speak Hebrew — it can already
do that. What the tag adds is the ability to hold **more than one** rendering of the same name,
which is why §3.1.1 puts the single-slot repair first and the syntax second.

**There are two lexers for `@nlg`, not one.** The outer `nlgAnnotation` (`Lexer.hs:432`) captures
the line into `TNlg`; the parser then **rebuilds** the annotation's source text with `toNlgAnno`
and **re-lexes** it with a second lexer, `nlgTokenPayload` (`Lexer.hs:788`) — and it is those inner
tokens that land in the Anno (`Parser.hs:211`) and that exactprint re-emits
(`ExactPrint.hs:40`). Both must learn the tag. Omitting the inner one is the silent failure;
omitting the outer one is loud. Two consequences:

- the text handed to `execNlgLexer` must stay **byte-identical** to the source slice, because
  inner token positions are seeded by advancing from the outer position (`Lexer.hs:871-884`) —
  stripping the tag before re-lexing shifts every inner column silently;
- `lineNlg` matches the prefix by **exact token equality** (`Parser.hs:177` via `:316-321`), so the
  moment `TNlgPrefix` carries a payload it stops matching. It must become a predicate match; the
  pattern already exists two functions away in `descP` and `fixityP`.

**The precedent to copy is `@infixl 6`** — a typed discriminator in the token constructor plus an
opaque rest-of-line `Text`, re-emitted as a pure function of that field (`Lexer.hs:1265`), with the
payload validated late in the type checker. `TNlg` itself has only **5 mentions** in the tree
(`Lexer.hs:74, 757, 1257`; `Parser.hs:155, 198`), so the constructor surface is genuinely small.

**A locale must not be threaded as a parameter.** `L4.Nlg` has 13 `Linearize` instances, 103 `lin`
call sites and 34 `linearize` call sites, and every instance body is purely monoidal — a parameter
rewrites all of them, whereas making `LinTree` a Reader-and-Writer newtype leaves almost all
untouched. The class signature is free to change: `Linearize` has **no instances outside
`L4/Nlg.hs`** and `linearize` is **never called outside it**. Only `simpleLinearizer` escapes, at
14 call sites across 5 modules.

**A fidelity report already exists, and it does not reach far enough.**
`jl4-core/src/L4/Interchange/Fidelity.hs` has the whole discipline — `.fidelity.txt` sidecars, 64
committed goldens, a `--fail-on blocking|lossy|advisory` gate, and `etc/go` comparing them. But it
is reachable from **four backends only**, and of the six things that consume `@nlg`, just
`L4.Relational.Lower` has a channel in scope (`Relational/Lower.hs:195`). `l4 render`, `l4 nlg`,
LSP hover and `L4.Blawx.Lower` have no report at all and return bare `Text`. **So §3's requirement
that a locale miss be recorded rather than silently substituted is a larger piece of work than the
tag itself**, and it should not gate the tag.

**Nothing of this exists yet:** `LangTag`, `@lang`, and BCP 47 anything measure **0 hits** tree-wide.

#### 3.1.1 Suggested split — three PRs, in this order

1. **Multi-`@nlg` attachment.** `Maybe Nlg` becomes a per-language collection;
   `ResolveAnnotation` partitions by tag; a duplicate tag is a check error. **No user-visible
   syntax**, so it lands alone and its blast radius is the 10 read sites, not the language.
2. **The tag.** Both lexers, `toNlgAnno`, both `displayTokenType` arms, the predicate match — plus
   one `#EVAL` over a head-trailing-annotated corpus name, which turns `.nlg.golden` into a witness
   for free (§4.1(c)). **Based on `unstable`, not stacked on the #962 fix** (§8 step 2). This is the
   step that carries the documentation obligation, because it is the first point at which a user
   can write the thing.
3. **Locale selection and fidelity.** `LinTree` as Reader-and-Writer; extend the fidelity channel
   to the `@nlg` consumers that have none.

## 4. Annotation escapes — `\%` and `\]` in `@nlg`, `\>` in `@ref` — IMPLEMENTED, not merged

Independent of the language work and being landed first, because both are live defects today
(§2.4). **Branch `fix/nlg-escapes`, PR #415; built, tested and gated 2026-09-17, reviewed
adversarially (§4.1), not merged.** The branch has been rebased since, so PR #415 is the stable
handle and a quoted SHA is not.

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

> **Ruling — `\>` escapes a right angle bracket in `@ref`. RULED 2026-09-17 (Meng);
> IMPLEMENTED 2026-09-18 on `lang/ref-escape`, PR #418, stacked on #415.** A literal `>>` inside `<<…>>` was unrepresentable before this work and
> the `\%`/`\]` escape deliberately did not extend to it — `refAnnotation` is a second
> annotation family, and widening to it on a fix branch's own initiative was not that branch's
> call. Raised by the `hebrew` session, deferred by this one, and then **ruled the other way**:
> take the escape.
>
> **The reason the deferral was right is also the design constraint.** The escape could not
> simply be re-shared into `inlineAnno`, because **nothing decodes `@ref` text** —
> `unescapeNlgText` is reached only from the NLG linearizer. An escape the lexer consumes and
> nothing decodes keeps the backslash for ever and makes the pre-escape text unwritable, which
> is exactly the regression §4.1(a) records. So `\>` needs a decode site on the `@ref` path,
> found by auditing what consumes ref text, before the lexer half is touched. Doing the lexer
> half alone would reproduce the half-wired failure of §4.1(c) in a second family.
>
> **How it was done, because the deferral named the precondition.** The audit the deferral
> asked for found the decode site, and it is not the one the NLG half uses: `@ref` text never
> reaches the linearizer. It reaches the reader through the parser, so the decode is
> `unescapeRefText` applied where the parser stores the citation on the `Ref` node
> (`L4/Parser.hs:127`), which is off the print path — the exact printer walks the annotation's
> tokens, not this field, so `exactprint identity` still holds. `L4.Lexer.isRefEscapable` is
> the `@ref` counterpart of `isNlgEscapable` and admits `\\` and `\>` only. A lone `>` stays
> ordinary, which is what keeps `<<s.5 > s.3>>` lexing, and has its own test. Five cases in
> `RefAnnotationSpec`.
>
> **Two record-keeping notes, because this ruling was briefly hard to find, which is the
> failure this section exists to prevent.** First, the commit was rebased when a docs commit
> landed beneath it, so the SHA it was first announced under (`d0fd5b9a4`) no longer resolves;
> the change carried forward is the same diff, compared byte for byte. Second, it is not on
> `fix/nlg-escapes` and never was — §4.1(a) is that branch UN-widening off `@ref`, and the
> escape is a separate stacked PR precisely so the un-widening and the re-widening are
> reviewable apart. A reader looking for it on #415 will correctly fail to find it, which is
> how the `hebrew` session came to ask whether a ruling had been silently dropped. It had not.

**(b) The lexer and the decoder disagreed about what an escape is.** The lexer consumed `\`
plus _any_ character; `unescapeNlgText` decodes only `\\`, `\%`, `\]`. A pair the lexer
swallowed and the decoder ignored changes what an annotation **captures** without changing
what it **renders** — and it turned two shapes that lex today into parse errors, including an
`@nlg` line annotation ending in a backslash, where there is no closing herald and so nothing
to escape. `L4.Lexer.isNlgEscapable` is now the single set both sides use.

> **Naming the set is not the same as using it (2026-09-18).** The decoder went on restating it
> as a literal — ``c `elem` "\\%]"`` — four lines under a haddock paragraph that said the set
> _was_ `isNlgEscapable`, so the file asserted an invariant it did not enforce. It now calls the
> predicate. No behaviour changed, because the literal and the predicate denoted the same three
> characters; the point is that they can no longer drift, and the drift they would have had is
> silent — a fourth escapable character would give a lexer that consumes `\[` as a unit and a
> decoder that leaves the backslash in, with the comment still reading correctly. Found by the
> `hebrew` session reading the branch rather than the diff.

**(c) The feature was half-wired, and the corpus goldens could not see it.**
`unescapeNlgText` was reached only from `Linearize Nlg`, and an earlier draft of this section
asserted that was "the single point where annotation text becomes output". **That was false.**
`l4 render` (text, html, json, akn), the LSP document webview and `l4 blawx` each emitted the
backslash to the reader. Worse, deleting every call site left the whole suite green: nothing
asserted rendered annotation text — **no `.nlg.golden` in the tree witnesses annotation prose at
all**. The repair adds `NlgRenderSpec`, which drives `buildDocument` end to end.

> **Correction 2026-09-18 — "and nothing could" was too strong, and the error is instructive.**
> This paragraph used to continue "…and nothing could", explaining that `Linearize (Directive
Resolved)` routes `#EVAL` through `linearize e` rather than `lin e`, so the golden is
> structurally blind. **Measured: it is not blind, it is un-exercised.** A head-trailing
> annotation does reach `.nlg.golden`, because `Linearize (Expr Resolved)` calls `lin` on the
> applied head name:
>
> ```l4
> DECIDE `head trail` @nlg A: the head-trailing sentence about %a%
>   IF a > 5
> #EVAL `head trail` 7
> ```
>
> → `l4 nlg` prints `A: the head-trailing sentence about `a` with 7`. The same file with the
> annotation in the after-`GIVETH` line position prints the bare `` `after giveth` with 7 ``.
> That position is the one the corpus uses throughout — `jl4/examples/ok/nlg-percent.l4` puts
> `@nlg 5% with %amount%` above its `DECIDE` — which is why every existing golden shows bare
> names and why the blindness looked structural.
>
> **The claim was a measurement of the corpus read as a statement about the instrument**, which
> is the same scope error as §4.1(c)'s own opening confession one layer up. Two practical
> consequences. Building a second end-to-end harness in the `NlgRenderSpec` shape is **not**
> required to witness selection: one `#EVAL` over a head-trailing-annotated name in any goldened
> corpus file makes `.nlg.golden` a first-class witness, for free. And the position matrix is
> itself the finding worth keeping — of five placements, only above-`GIVEN` and head-trailing
> render at all, so **where an annotation sits decides whether it is output**, which the language
> tag work inherits whole.

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

**Nothing owed — and the one item listed here has been withdrawn on its merits, not dropped.**
An earlier draft of this section wanted a corpus `.l4` case carrying a backslash inside `<<…>>`.
The `hebrew` session — whose bug §4.1(a) records — argued it out, and the argument is right.
Such a file would assert that `<<sec 3\>>` type-checks cleanly. But type-checking cleanly is
what the BASELINE does, and it is also what the broken version did whenever a later `>>`
existed: it swallowed a whole rule and still reported success. The corpus case would have been
green through the entire lifetime of the bug it was meant to guard. It is not a guard; it is a
guard-shaped object.

The instrument that does catch it is fragment-level, and it is already written.
`RefAnnotationSpec`'s "keeps a trailing backslash as ordinary text rather than escaping the
closer" asserts that the captured text of `<<see s.5\>>` is exactly `see s.5\`, and it goes red
the moment anyone re-widens the escape back into the shared `inlineAnno` body — the exact
regression §4.1(a) is about. It was mutation-checked when it was added.

**The general lesson is worth more than the case, and generalises past this branch:** a corpus
file tests that something is ACCEPTED; only an assertion over the captured fragment tests WHAT
was accepted. Where a defect changes what a construct captures rather than whether it lexes,
adding a corpus file is the intuitive move and the useless one.

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

| #        | question                                                                                        | state                                                                                                                                                                                                                                                                                                                                                   |
| -------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **R-M1** | `@nlg:he` vs `@nlg he "…"` vs a separate `@lang` block — which surface syntax?                  | **ANSWERED 2026-09-17 (Meng)**, §3: **`@nlg:he`** on the heralded form; the bare `[…]` form stays **untaggable**, its `[@he …]` spelling **pre-approved** for when a need appears. `@nlg he "…"` rejected on measurement — a `"` is ordinary prose and two `doc/reference/syntax/` annotations already open with one                                    |
| **R-M2** | How does a module declare its default language for untagged `@nlg`?                             | **ANSWERED 2026-09-17 (Meng)**, §3: absent declaration means **`en`**, and a module-level `@lang` is **required** in any module that uses a tag. Backward-compatible for all 131 existing annotations, and forces explicitness exactly where ambiguity can arise                                                                                        |
| **R-M3** | Escape convention for a literal `%` and `]`?                                                    | **ANSWERED 2026-09-17**, §4: **backslash** (`\%`, `\]`, `\\`). Doubling does not generalise to `]`, and L4 string literals already use Haskell escapes. Measured 0 corpus uses of either convention, so both were free to take                                                                                                                          |
| **R-M4** | One canonical encoding + `@nlg` (B), not parallel per-language encodings (A), for the Penal Law | **ANSWERED 2026-09-17**, §1. Driven by: 651 sections under active amendment (the row read 644 when ruled; corrected per §2.3 note (iii), and the argument is unchanged); Amendment 155 reached Wikisource in 7 days; and the legal-status argument in §1, point 3                                                                                       |
| **R-M5** | Which language is canonical for `il/penal-law-1977`?                                            | **ANSWERED 2026-09-17**: **Hebrew.** It is the enacted and binding text, it is the only one on Wikisource, and it is the only one current to Amendment 155                                                                                                                                                                                              |
| **R-M6** | Is the ICJ English text usable for `@nlg:en`?                                                   | **ANSWERED 2026-09-17 (Meng).** _Depositing_ it in canon: **NO.** Link to it and use it internally as a working alignment document; it does not enter `canon`. _Consulting_ it: **yes**, and it is the better use — see §6.1. Nothing in the pilot depends on the deposit, so declining costs nothing and removes the licence question                  |
| **R-M7** | Confirm the Hebrew-binds / Arabic-special-status claim against primary sources                  | **ANSWERED 2026-09-17**, §1 point 3: Interpretation Law 5741-1981 §24 and Basic Law: Nation-State §4, both read in the primary text. The rule is language-of-enactment rather than "Hebrew always"; it reaches Hebrew here by application. Verified by the `nlg-locale` session                                                                         |
| **R-M8** | Where do Arabic renderings come from, given no Arabic statute text exists?                      | **ANSWERED 2026-09-17 (Meng): drop the Arabic output.** Basic Law §4(b) makes Arabic a reader aid, so nothing operational depends on it, and there is no Arabic reviewer — note the Hebrew encoding has had no Hebrew-language review either, only mechanical verification. Pilot ships `he` canonical + `@nlg:en`; revisit `ar` when a reviewer exists |

#### 6.2 Implementation status of R-M1 and R-M2, recorded 2026-09-19

Both were ANSWERED in 2026-09-17. Neither is fully built, and the gap in each is worth stating
where the ruling is, rather than leaving a reader to infer from the code that the ruling moved.

**R-M1 — the bare `[…]` form is still untaggable, by instruction.** §8 step 3 says in terms:
_"Do not build the bare form's `[@he …]` spelling: pre-approved, not commissioned."_ That was
followed. **The need it was pre-approved against has now appeared**, and it is worth naming
precisely rather than leaving as a preference: `L4.Print.prettyLayout` must emit an annotation
in the bracket form, because the heralded form runs to end of line and would swallow the rest
of a printed `DECIDE`. With no bracket spelling for a tag, `prettyLayout` keeps only a name's
DEFAULT rendering — so a bilingual module through `l4 batch`, the REPL, or the DMN exporter's
fallback comes back monolingual. `l4 format` is byte-exact and loses nothing, so the authoring
path is safe; it is the re-render path that is lossy. Commissioning `[@he …]` closes it.
Measured 2026-09-19: no `.l4` file in the tree contains `[@`, so the spelling is free.

**R-M2 — SHIPPED 2026-09-19, superseding the paragraph below.** `@lang he` exists: a
module-level declaration, lexed with the same `isLangTagChar` subtag grammar as `@nlg:he`, and
meaning exactly "every untagged `@nlg` in this module is `he`". Absent declaration means `en`,
as ruled. Implemented by STAMPING untagged annotations with the module's language after
parsing and before attachment, which has three consequences worth knowing:

- it is order-independent — a declaration at the foot of the file governs the head of it,
  because the stamp runs over a complete `PState`;
- `@lang he` and tagging every herald `:he` are the same thing by construction rather than by
  care, which is the equivalence that justifies Meng's preference for one declaration over 56
  tags (`specs` §8a.2 records the test that asserts it);
- the "untagged wins as the default" rule became "the MODULE's language wins", which is the
  same rule stated for a world where nothing is untagged any more.

Two knock-on effects. A module with `@lang he` and an explicit `@nlg:he` on one name now has
two Hebrew renderings and is reported as ambiguous — correct, and new. And the ambiguity
diagnostic can no longer distinguish "untagged" from "tagged", because by the time it runs
nothing is untagged; it says so in one sentence instead of guessing.

**The residual wrinkle, recorded rather than fixed:** absent-means-`en` labels a monolingual
Hebrew module as English. That is the Penal Law pilot's exact shape, and R-M2's "required in
any module that uses a tag" does not reach it, because such a module uses no tags. Nothing
observable is wrong today — it renders Hebrew either way — and it becomes wrong when §5's
fidelity channel starts asking which rules lack a translation. The cheap fix is to declare
`@lang he`, which the documentation now tells Hebrew authors to do.

**Superseded, kept because it is the reasoning that preceded the change:** there is no `@lang`,
and untagged means "unlabelled" rather than "`en`". The ruling
is that a module-level `@lang` is required in any module that uses a tag, and that its absence
means `en`. What shipped instead: the DEFAULT rendering is the untagged annotation if there is
one and otherwise the first in source order, and `--lang xx` falls back to it.

The two coincide on everything observable today, which is why this was not treated as blocking:
for a module whose untagged annotations are English, `--lang en` reaches them by fallback and
`--lang he` reaches the `@nlg:he` ones directly, exactly as `@lang en` would give. **Where they
stop coinciding is fidelity reporting.** Under fallback you cannot distinguish "this rule has a
real Hebrew rendering" from "this rule fell back", because both return a rendering; with
`@lang he` declared, the untagged ones are known to BE Hebrew and the question has an answer.
That is precisely what §5's fidelity channel needs, so `@lang` is owed before §5, not before a
bilingual set.

**A third, smaller deviation.** §3.1.1 step 1 says a duplicate tag should be _"a check error"_.
It is a WARNING, as two untagged annotations on one name already were. Escalating would turn
existing modules red for a condition the compiler has always tolerated, and the diagnostic is
the same either way; the warning now names the colliding language. Revisit with R-M2, since a
declared `@lang` is what would make "duplicate" unambiguous enough to be fatal.

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

**The 59-section gap (§2.3) is where this stops helping**, and it stops abruptly — those sections
have no counterpart to consult, so their English is ours alone and should be marked as such.

## 7. What this spec does NOT decide

- **The Penal Law encoding itself.** This is the multilingual mechanism. What of 651 sections
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

1. **Annotation escapes (R-M3).** ~~Smallest, independent, fixes two live defects.~~ **Done,
   awaiting review, as a STACK of two PRs** — and it was not the smallest. `\%` and `\]` for
   `@nlg` are PR #415 (`fix/nlg-escapes`); `\>` for `@ref` is PR #418 (`lang/ref-escape`),
   which sits on top of it and must merge second, because #415's own repair was to un-widen
   the shared lexer body off `@ref` and #418 re-widens it deliberately, with a decode site.
   It reached a second annotation family, a second lexer and three renderers before it was
   finished; §4.1 is the account. Read that before step 2, because the language tag touches
   the same three places and the same green-gate-proves-nothing trap applies to it.
2. **Fix smucclaw/l4-ide#962 (§2.6) — a precondition for the ENCODING, but not for the tag.** Non-ASCII in a
   `.schema.golden` is double-encoded and the corruption round-trips, so the suite stays green
   while storing mojibake. A Hebrew-canonical encoding writes one schema golden per file, so
   this lands on every one of them silently. **Ruled 2026-09-17 (Meng): fix it**, before any
   Hebrew golden is blessed — otherwise the first thing the encoding proves is the wrong thing.

   **Measured 2026-09-18 — this does NOT make step 3 stack on it.** A Hebrew `@nlg` string does
   not reach a `.schema.golden` at all: `@nlg` and `@desc` are separate `Extension` fields
   (`Syntax.hs:901` vs `:904`) and `annNlg` has zero occurrences in `L4/JsonSchema.hs` or
   `L4/Export.hs`, the only two modules the schema golden uses. Hebrew reaches a schema golden by
   two **other** routes, both the fixture author's to control: identifier **names** (witnessed —
   `fristberechnung.schema.golden` carries `die maßgebenden Orte` from a file with no `@desc` and
   no `@nlg`) and **`@desc`** (witnessed — 11 `"description"` strings in
   `regcf-wizard.schema.golden`), and only where the file has an `@export` at all: **386 of 503**
   schema goldens are the literal string `No @export annotations found in file`. So the ordering
   constraint is real for the Hebrew encoding and absent for the language tag.

3. **Language tag (R-M1, R-M2 — both now ruled, §3). DONE 2026-09-19**, across #423 (the tag),
   #427 + #429 (multiplicity, selection, `prettyLayout`), and the `@lang` work in §8a.2.
   R-M1's bare-form spelling remains deliberately unbuilt; see §6.2. `@nlg:he` on the heralded form only;
   absent `@lang` means `en`. Lexer, `L4.Nlg` selection, check error on duplicates, goldens.
   Untagged behaviour must be provably unchanged — assert against **every heralded annotation in
   the tree, counted at the commit under test**, not against a number quoted from here. The count
   moves with the branch: 131 at `cab6988d0`, and 133 real of 143 lines (130 heralded, 10 in
   comments) on `lang/ref-escape`, which adds documentation examples. A recount is one command;
   a stale constant silently weakens the assertion.
   Do **not** build the bare form's `[@he …]` spelling: pre-approved, not commissioned.

   **This step carries a documentation obligation, and `specs/` does not discharge it**
   (CLAUDE.md §6: a user-writable construct needs a page under `doc/` in the shipping PR).
   Three things are owed, and none is optional:

   - a `@nlg:xx` section in `doc/reference/syntax/README.md`, stating the limit that the
     bare `[…]` form is **not** taggable;
   - a fix to `doc/tutorials/natural-language-functions/optimising-natural-language-generation.md`,
     which today says L4 renders "formatted **English** prose" and treats English as a property
     of the renderer rather than as a default — that sentence becomes false the moment a tag
     ships;
   - guidance on **producing a bilingual set of documents** from one encoding, which is the
     thing the tag is actually for. Write that as the general case and derive the current
     behaviour from it: **with no `@nlg:xx` tags and no `@lang`, English is the degenerate
     default** — one language, selected by having no alternative. A reader who meets the
     degenerate case first will read the tag as an exception; a reader who meets the general
     case first will read today's behaviour as the special case it is.

     **Measured 2026-09-18, and it makes that sentence stronger than it looks (§3.1):** the
     renderer has no language concept whatsoever — a Hebrew `@nlg` renders Hebrew today, untagged.
     So do not write that L4 "renders English" and gains other languages; write that L4 renders
     **whatever the annotation says**, that a corpus written in English therefore reads as
     English, and that the tag adds the ability to carry **more than one** rendering per name.
     The existing tutorial sentence — "render your rules back into formatted English prose"
     (`doc/tutorials/natural-language-functions/optimising-natural-language-generation.md:7`) —
     is wrong in exactly this way today, before any tag ships.

   An executable example belongs in a `.l4` file under `doc/`, not only in a fenced block:
   `doc/test-docs.sh` type-checks the former and not the latter.

4. **Projection locale (§5).** Start with `l4 render` and the docs, which have no interactive
   surface; the wizard and ladder diagrams follow.
5. **Penal Law pilot.** One chapter, Hebrew-canonical, with `@nlg:en` informed by the ICJ text
   — **consulted, never deposited** (R-M6) — to exercise the whole path before committing to
   651 sections. **No `@nlg:ar`** (R-M8).

## 8a. What was built, 2026-09-19

Two branches, stacked, both on `unstable` after #423.

**`fix/prettylayout-nlg` — `prettyLayout` stopped dropping every annotation**
(smucclaw/l4-ide#966). The hook is the NAME printer, and that is a measurement rather than a
plan: an `@nlg` attaches to a `Name` node and to nothing else, including one written under an
expression, which lands on the last `Name` in that expression's range. Emission is the bracket
form, which is forced — the heralded form would swallow the rest of a printed line. A close
bracket is escaped on the way out, and so is a LONE TRAILING BACKSLASH: a line annotation may
end in one, and copied through it escapes the `]` the printer appends, so the printed module
swallowed five following lines and stopped parsing. **The corpus round-trip suite found that,
not the unit tests**, which had the bare-`]` case and not this one; it is the clearest argument
this spec has for why the whole-corpus property earns its twelve minutes.

Also `\[` now decodes (Meng, 2026-09-19). It protects nothing — a bare `[` is ordinary text in
both forms — but an author escaping a citation's closing bracket escapes the opening one in the
same keystroke, and `[see note \[3\] here]` rendered as `see note \[3] here`: half the pair
decoded and a backslash nobody wrote reached the prose, silently.

**`lang/nlg-multiplicity` — several renderings per name, and a way to ask for one.** The
collision became per-LANGUAGE instead of per-name; the default rule is untagged-else-first,
which is what keeps all ~28 existing readers of `annNlg` correct without being touched;
selection is a rewrite (`L4.Nlg.selectLanguage`) that promotes the requested rendering into the
slot every consumer already reads, rather than a parameter threaded through `Linearize` and its
six consumers. `selectLanguage Nothing` is the identity, so the `.nlg.golden` producer is
byte-identical by construction. `l4 nlg --lang he` is the CLI surface.

**One narrowing, decided on evidence: a TYPE never carries an annotation into print.** A
`Type'` is printed in places that are not source — an evaluation result, a diagnostic, an LSP
hover — and an annotation re-emitted there is noise. The witness arrived as a moved golden:
`ok/nlg-percent.l4`'s `#CHECK` answered `BOOLEAN [5% with %amount%]`. Two further leak sites
turned up behind it, and the order they were found in is the lesson — the `Type'` instance
first, then the value printer (`ValAssumed` / `ValUnappliedConstructor` / `ValConstructor`,
where a legitimately annotated `ASSUME`d name would have leaked too), and finally
`goDisplayTy`, a **hand-written mirror of the `Type'` instance** which is the copy a `#CHECK`
actually goes through. Fixing the instance moved no golden; fixing the mirror did. Whoever
touches type printing should know the two exist and are not kept in step by anything.

### 8a.1 A live defect found on the way — annotation placement is silently wrong

**Measured 2026-09-19.** An annotation attaches to the name it FOLLOWS. Two consequences nobody
had written down:

- `GIVEN a IS A STRING @nlg the amount` — the trailing form — attaches to **`STRING`**, not to
  the parameter `a`.
- An `@nlg` on its own line above a `DECIDE` attaches to the **`GIVETH` type name**, not to the
  rule.

Both then render nothing, and nothing reports it: the annotation DID attach, so there is no
`NotAttached` warning. The witness is decisive and embarrassing — **`jl4/examples/ok/nlg-percent.l4`
uses the second shape throughout, and its own `.nlg.golden` shows bare names for all seven of
its annotations.** The file that exists to test `@nlg` renders none of its own. Across ten
sampled files, 11 of 116 annotations sit on a builtin type name; `prelude.l4` has 0 of 67, so
the idiomatic style avoids it by habit rather than by construction.

**RULED 2026-09-19 (Meng), and implemented.** Trailing a line, an annotation describes what is
on that line; starting a line of its own, it describes what follows — with ONE exception, ruled
separately the same day: inside a record-field list, an annotation on its own line describes the
field ABOVE it. A field list is a column of things rather than a sequence of declarations, and
the evidence is that authors write it that way: across three independently generated Hebrew
encodings, field and parameter heralds are the largest single category — 100 of 334 — and every
one is written below its field (measured by the `ofek` session; our own corpus contains
essentially none of that shape, so no golden of ours would ever have raised the question).

The field name therefore claims two disjoint regions: everything before its type, which is its
own trailing gloss, and everything on a later line. What falls between — trailing the TYPE on
the field's own line — stays with the type, which is what keeps `ok/nlg_declare1.l4`'s
deliberate `head [Get First Element] IS AN a [Start Element]` working. Giving the name the whole
line instead makes those two collide and loses both; that was measured before it was narrowed.

There is precedent for the fix inside the same pass: a **leading `@ref` already attaches
FORWARD**, to the declaration that follows it, and `RefAnnotationSpec` pins that specifically
("attaches a leading `@ref` to the first declaration, not the Module"). `@nlg` attaching
backward to the nearest preceding type name is the asymmetry. Changing it is a semantics ruling
that moves goldens, so it is **not** taken here; it is offered to Meng as **MISTLETOE** — the
annotation kisses whoever happens to be standing next to it.

### 8a.2 `@lang` — shipped 2026-09-19

Meng fired PASSPORT on 2026-09-19 ("Re labeling the heralds we should make use of `@lang` if it
has arrived"), after a Hebrew re-voiced Ofek encoding was tagged per herald — 56 `@nlg:he`
lines — because `@lang` did not exist. It does now, and those collapse to one line.

What landed: a `TLang` token keeping the raw remainder verbatim so exactprint re-emits the
declaration byte for byte; collection through the same annotation channel as `@desc`, so its
tokens ride in the same hidden cluster; the stamp described in §6.2; and `pickDefault` restated
in terms of the module's language.

Six unit tests and one corpus file (`ok/nlg-module-lang.l4`, whose `.nlg.golden` renders
**Hebrew** by default, which is the first `.nlg.golden` in the tree that witnesses a language
choice rather than a bare name). The test that matters most is the equivalence one: a module
with `@lang he` and an untagged herald produces the identical attachment to a module with
`@nlg:he` and no declaration. Everything else follows from that being true.

**Not done, and not asked for** (PASSPORT scoped it out): the bare inline `[…]` form stays
untaggable (R-M1), no Arabic, no projection locale, and no change to the Ofek encodings — GM
owns collapsing the 56 tags now that `@lang` exists.

## 9. Reproducing the measurements

All inputs are already deposited; nothing needs re-fetching.

```bash
CANON=~/src/legalese/canon/subjects/il/penal-law-1977/source
# 2.2 template inventory and tree well-formedness
python3 - "$CANON/penal-law-1977.wikitext"     # see §2.2 for the regexes
# 2.3 requires the ICJ PDF, which is deliberately NOT in canon (R-M6: consult, never deposit):
curl -sfL -o /tmp/icj.pdf \
  https://www.icj.org/wp-content/uploads/2013/05/Israel-Penal-Law-5737-1977-eng.pdf
pdftotext /tmp/icj.pdf /tmp/icj.txt
# 2.2 + 2.3 section counts and the inventory diff (added 2026-09-21; prints every §2.2/§2.3 figure)
python3 - "$CANON/penal-law-1977.wikitext" /tmp/icj.txt <<'EOF'
import re, sys
G = {'א':1,'ב':2,'ג':3,'ד':4,'ה':5,'ו':6,'ז':7,'ח':8,'ט':9,'י':10,'כ':20,'ך':20,'ל':30,
     'מ':40,'ם':40,'נ':50,'ן':50,'ס':60,'ע':70,'פ':80,'ף':80,'צ':90,'ץ':90,'ק':100,'ר':200,'ש':300,'ת':400}
txt = open(sys.argv[1], encoding='utf-8').read(); L = txt.split('\n')
starts = [i for i, l in enumerate(L) if l.startswith('{{ח:קטע1')]
body = '\n'.join(L[:starts[3]])                       # parts 0, A, B — not the comparison table
ids = re.findall(r'\{\{ח:סעיף\|([^|}]*)', body)     # plain template only; ח:סעיף* is schedule items
def norm(s):                                          # 144ד1 -> 144D1 ; 34יא -> 34K (gematria)
    n, suf, tail = re.match(r'^(\d+)([\u0590-\u05FF]*)(\d*)$', s.strip()).groups()
    v = sum(G[c] for c in suf); return f"{n}{chr(64+v) if v else ''}{tail}"
heb = {norm(s) for s in ids}
hdrs = [txt[m.start():txt.find('\n', m.start())] for m in re.finditer(r'\{\{ח:סעיף\|', body)]
print('Act sections            :', len(ids), '   with תיקון: trail:', sum('תיקון:' in h for h in hdrs))
eng = {m.group(1) for m in re.finditer(r'^(\d+[A-Z]*)\.', open(sys.argv[2], encoding='utf-8').read(), re.M)}
print('English sections        :', len(eng)); print('in BOTH                 :', len(heb & eng))
print('ENGLISH-only            :', sorted(eng - heb)); print('HEBREW-only             :', len(heb - eng))
print(f'English coverage of Hebrew: {100*len(heb & eng)/len(heb):.1f}%')
EOF
# expected on revision 3023424: 651 / 456 / 592 / 592 / [] / 59 / 90.9%
# 2.4 @nlg has no language field and no escape
grep -n "nlgAnnotation ::\|nlgExprDelimiterSymbol\|^nlgString ::" -A 6 \
  jl4-core/src/L4/Lexer.hs
```
