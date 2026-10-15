# Skeptic reply: TURDUCKEN design.md (inline `ONE OF` on a record field), 2026-10-14

VERDICT: weakens

Every recount below ran the design's own scripts (`measure/census.py`, `candidates.py`, `extra.py`, `invented.py`) over trees extracted with `git archive` at the SHAs the note names: l4-ide `708c40f72` (`jl4/examples/{ok,legal,canon}`) and commons `f8ee9266` (the 555 `encodings/` dirs in `measure/encdirs.txt`).
`scripts/robust.py` classifies every byte-identical copy in its own directory and keeps the most-shared reading. It gives the same figures as `census.py` at these SHAs.
Probes are in `p/`. The binary was the `l4-ln-551` snapshot, copied in and deleted afterwards.

## Fact-check

### Census
- WRONG: "164 of 2,988 enums (5.5%)". At the named SHAs it is **147** (144 field + 3 payload), 4.9%.
  The design's census read a working tree that held 73 gitignored files, not `f8ee9266`.
  Those are `vendor.sh` copies in `il/employed-parent-monthly-net/encodings/legalese-2026-10-il-07/` (its `.gitignore` says so; `git status --ignored` lists exactly 73).
  The census keeps the first byte-identical copy in walk order and resolves users only within that copy's directory.
  So the il-07 copies were kept, the home copies were dropped, and users that were never vendored disappeared.
  17 of the 39 il-07 "candidates" are `shared` in their home directory; 164 − 17 = 147.
- WRONG: "39 come from one encoding (il-07)". All 39 are vendored copies of other encodings' nouns files (il36-nouns 8, ito-il28-nouns 8, ito-il08-nouns 7, nhi-il25-nouns 6, and others), and none is in an il07 file. At the SHAs the largest contributor is il/income-tax-ordinance, with 16.
- WRONG: "2,497 files, 160 dropped". At the SHAs it is 2,424 files with 87 dropped; 2,337 files and 2,988 enums are unchanged.
- WRONG: "369 also named by a rule". At the SHAs it is **385**, so field-only enums are 147 of 532 (28%), and the ratio is 2.6 rather than 2.25. That strengthens §7.2.
- WRONG: "90 adjacent, 73 separated, median 6". At the SHAs: 81 adjacent, 65 separated, 1 in another file, median 4, max 241.
- WRONG: "90 of the 164 in October-run dirs". At the SHAs: 73 of 147.
- CONFIRMED: 964 enums used only in one GIVEN, 230 only in one GIVETH; 4 of 2,562 records.
- STALE/inconsistent: the per-tree split "291 + 23 / 2,799 + 157" does not add up to 2,988 / 164. Each figure is a standalone run, and the two overlap through the canon mirror (about 102 enums). Commons alone at the SHA has 140 candidates.
- CONFIRMED with a gap: the positive control passes. It tests tokenising, the governing keyword, importer-relative resolution and puns. It has no case of a byte-identical module in two directories, which is the case that produced the error above. The hand precision check grepped the same directory the census used, so it could not catch the error either.
- MISSING, from the design's own `extra.py` at the SHAs: for **54 of 147 candidates the type name already equals the field name** (case, article and punctuation aside: `Role`/`role`, `Purpose`/`purpose`, `Kind of Statement`/`kind of statement`), and in 45 more one name contains the other. Only 48 are unrelated. No candidate field carries TYPICALLY.

### Isomorphism (§3.4)
- CONFIRMED: 20 of 24 candidate type names are absent from the source text.
- MISSING: the same test applied to the parts of the generated name.
  The record name is absent from the source in 24 of 24 and the field name in 16 of 24 (`scripts/fieldsrc.py`).
  `<record>'s <field>` is therefore built from names the encoder also invented.
- MISSING: readability of the generated names. 38 of 147 fields and 34 records start with an article: "The readings's the reading of the adaptation year", "Matter's the kind", "Formation's the section 19(2) declaration was made by".
  5 of the 30 names that carry a citation lose it: "A reading of regulation 3(b) on rounding …" becomes "The readings of the withholding rules's the share".
  4 candidates are Hebrew records, which would get an English `'s` ("מורה's מעמד ההשכלה").

### Code claims (integ `1747606b1`)
- CONFIRMED: fact 1 (p1a fails at `ONE` with the quoted expectation list); fact 6 (p2 fails; p2b and oneline-ok pass; filed as smucclaw/l4-ide#1045, OPEN, which the note predates).
- CONFIRMED: fact 2. `reqParam` is at Parser.hs:1725-1735 and `conDecl`/`recordDecl'` at :899-930. `TypedName` occurs only in `RecordDecl` and `MkConDecl` (Syntax.hs:260, :277). `separator` also accepts `:`, which the note does not mention.
- CONFIRMED: facts 3, 4 and 5 (twoenums, p4 and p5 re-run; p6 is a loud ambiguity error). Also checked: an unbackticked `GIVEN t IS A Plot's tenure` is a loud "unexpected 's".
- CONFIRMED with a correction: "78 types have an apostrophe". There are 78 DECLARE lines but 69 distinct names.
- CONFIRMED: fact 7, desugarComputedFields at Desugar.hs:291-355 and the pass order at TypeCheck.hs:261-273.
- CONFIRMED: 62 `MkTypedName` sites in 22 files; 20 modules mention `EnumDecl`.
- CONFIRMED: fact 9, Batch.hs:302-303 and REPL Main.hs:587; both print `tcRes.module'`.
- CONFIRMED: facts 10 and 11 (FunctionSchema.hs:45, :215-240; OpenApiDoc.hs:480-489; ResolveAnnotation.hs:463-469). `Compatibility.hs` does not compare `x-l4-type`, so §5.10's claim that a later promotion is "additive" holds for the redeploy guard.
- CONFIRMED: the C++ probes (unnamed.cc runs, unnamed-bad.cc and ret.cc give the quoted errors). The DMN, OCaml, C# and Dhall quotes are in `priorart/`. Nuance: C++ names an unnamed member enum by `decltype` and by its source location. It never gives the enum an ordinary identifier, so "exact precedent" overstates the match.
- CONFIRMED, by running the exporters on the hand-lifted probe `p/lifted.l4`: Catala gives `PlotSTenure`; DMN gives `name="Plot_s_tenure" label="Plot's tenure"`; docassemble asks per field and never shows the type name.
  Blawx gives `plot_s_tenure` and "is a plot s tenure"; with a plain `Tenure` type and a `tenure` field, Blawx fails with a name collision, so the generated name happens to help there.
  OpenFisca fails both ways, for an unrelated reason.
- WRONG: §5.7 "its wording will name the type". The non-exhaustive CONSIDER warning names only the missing branch, "WHEN Lodger THEN" (p/q3).
- UNVERIFIED in the note; answered here (§5.11, §8): **`l4 render` shows the generated name to the reader.** On the lifted probe it prints "Plot's tenure means one of Owner, Tenant, or Lodger." and "tenure — Plot's tenure", and in the Provisions "the plot's tenure is Tenant".
  The defined term and the projection phrase sit side by side.
  `l4 nlg` and the ladder do not print type names (Ladder.hs has no `EnumDecl` case).
- MISSING: **the precedent's own reader-facing defect.**
  `l4 render --include-unused` on `jl4/examples/ok/computed-fields.l4` drops all four computed fields of `Person`: age, adult, minor and category.
  The "computed as" branch at Export/Document.hs:993 cannot fire on a desugared record, and :479 with `isComputedSelector` (:652, a `"_self"` name test) hides the selector.
  Dmn/Lower.hs:1172-1175 says it deliberately does not use that name test ("A name test is what R8-f was").
  So the lift precedent already carries two provenance mechanisms and one silent loss.
- MISSING: where the provenance mark lives. The `ComputedSelector` precedent lives in `resolvedInfo`, and `Serialise Anno` (Syntax.hs:1825-1827) keeps only `pmSynthetic`.
  Compiler.hs:276-300 documents that this loss once broke `/ladder`. Today the restart path re-checks from source, but it falls back to `bundle.sbModule` when there is no source (:323-326).
- MISSING: the predecessor's naming trilemma. GIVETH-MULTIPLE's verdict says no naming scheme is "simultaneously stable, collision-free and readable". §6 answers the seven GIVETH-INLINE findings and not this one.
  It partly re-bites. Readability fails as shown above. Collision-freedom fails for payload fields: fact 3 lets two enums share a constructor, so `Holding`'s `Lease HAS term …` and `Interest`'s `Lease HAS term …` both lift to `` `Lease's term` ``.
  Probe q5 shows the sharing is legal today; q4 shows the lifted pair is a loud "multiple definitions for `Lease's term`" error at a name the author never wrote. The §5.1 error table does not cover that case.
- MISSING: a second copy of the figures. Memory `inline-one-of-turducken.md` repeats 164 / 369 / 90 / median 6 and says the census was "reproduced"; it needs the same correction.
- MISSING: the fork-register share. About 31 of 147 candidates are R4 fork registers (`r4-fork-ruled.md`: one enum per fork point, all fork points as fields of one Interpretation record). The idea memory `forks-exposed-via-service.md` would publish those records through the service schema, which is where §5.10 omits `x-l4-type`.
