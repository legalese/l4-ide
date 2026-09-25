# P4b — the `ASSUME` → `RInput` widening: design plan

_Design pass only. Nothing here is landed; every claim about the tree was read on 2026-08-19 at
the paths cited, and every claim about behaviour after the change is written in the conditional.
No `cabal` was run for this document._

Authority: `specs/todo/BLAWX-EXPORT-SPEC.md` §4.10 / §6 / R5 / R11 (ruled), `specs/todo/BLAWX-P4-BRIEF.md`
(working brief). Where the brief and the tree disagree, §0 records it.

---

## 0. Three corrections to the brief, before the design

**0.1 The relational middle end is NOT shared.** The brief says "catala/docassemble/openfisca
consume `RelProgram`". They do not. Every importer of `L4.Relational.*` in the tree:

```
jl4-core/src/L4/Blawx/Lower.hs:149    import L4.Relational.IR
jl4-core/test/RelationalSpec.hs:27-28 import L4.Relational.{IR,Lower}
jl4/app/L4/Cli/Blawx.hs:36-37         import L4.Relational.{IR,Lower}
jl4/tests/RelationalExport.hs:28-29   import L4.Relational.{Debug,Lower}
```

`L4/Catala/`, `L4/Docassemble/`, `L4/OpenFisca/` have their own front ends. **Blawx is the only
consumer.** This shrinks the blast radius to 13 relational Debug goldens + 4 `.blawx` + 4 `.pl` +
`RelationalSpec`, which is what makes §4's additivity proof tractable. It also means the widening
cannot break another backend, and the brief's warning to that effect can be retired.

**0.2 `imaginary-alcohol-act.l4` is not unlockable by this widening, and must not be a P4b seed.**
Its seven `ASSUME`s are nullary (`ASSUME \`the person is a body corporate\` IS BOOLEAN`,
`:33-39`) and — decisively — **all three of its `DECIDE`s are also nullary** (`:41`, `:68`, `:92`:
no `GIVEN`, no subject). `L4.Blawx.EmitXml.predicateNode` (`:652-655`) answers a zero-argument
predicate with

```haskell
[] -> gap ("goal " <> n) "no Blawx block applies a zero-argument predicate"
```

An `XmlGap` blanks the whole row's `xml_content` while `scasp_encoding` stays non-empty — which
is precisely the R12 data-loss condition `jl4/tests-cli/Main.hs:372-396` (`noBlankedBlawxRow`)
exists to fail on, and which the headless fixpoint harness fails on too. Blawx's ontology is
category-centric: a proposition with no subject has no block, no declaration, and no interview
line. So the alcohol act is out **for a reason that has nothing to do with `ASSUME`**, and
widening `ASSUME` would not move it one step closer. It becomes a **not-ok fixture** (§5, F7),
not a seed.

The P4b seed is therefore **`anti-social.l4` alone** (`jl4/examples/legal/anti-social.l4`, 49
lines), whose `ASSUME`s are the arity-1 function shape Blawx can actually declare.

**0.3 The ruled spec already says this widening is in the fragment; the code says it is not.**
`BLAWX-EXPORT-SPEC.md:309` lists "`ASSUME`d inputs → declared predicates; `#abducible` in the
interview test" as **CLEAN**, `:456-457` says "L4's `ASSUME`d inputs land there naturally", and §6
(`:547`) lists "`ASSUME`d inputs" inside the v1 source fragment. Meanwhile
`jl4-core/src/L4/Relational/IR.hs:472-483` states the opposite in the present tense. P4b closes a
**spec-vs-tree gap**, and the `RInput` haddock must be _rewritten_, not appended to (house rule:
a stale claim is worse than a missing one).

---

## 1. What the tree does today

| site                            | file:line                        | behaviour                                                                                   |
| ------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------- |
| `ctxAssumes :: Set Unique`      | `Relational/Lower.hs:278-283`    | collected for ONE purpose: to diagnose a reference well                                     |
| populated                       | `Relational/Lower.hs:658-659`    | `[getUnique r \| Assume _ (MkAssume _ _ (MkAppForm _ r _ _) _ _) <- decls]`                 |
| consumed                        | `Relational/Lower.hs:1189-1193`  | in `anfTerm`'s `App` chain, **after** `lookupCall`: bail `LEUnsupported "top-level ASSUME"` |
| local `ASSUME`                  | `Relational/Lower.hs:1076-1078`  | `bailIn … (LEUnsupported "local ASSUME")` — separate site, separate reason                  |
| `ctxSigs`                       | `Relational/Lower.hs:660-669`    | built from `tops` (i.e. `Decide` only) — so an `ASSUME`d name never resolves as a call      |
| record-field inputs             | `Relational/Lower.hs:2449-2474`  | `inputPreds`: one `RPred` per stored field **that a projection reached** (`used` set)       |
| `RInput` doc                    | `Relational/IR.hs:472-483`       | "In M1 this is exactly a stored record field"                                               |
| Blawx: declarations skip inputs | `Blawx/Lower.hs:627`             | `[ … \| p <- prog.rpgPreds, p.rpKind /= RInput ]`                                           |
| Blawx: field attributes         | `Blawx/Lower.hs:624-625,649-655` | `fieldAttribute` over `rpgRecords` — the input's declaration block                          |
| Blawx: interview `cats`         | `Blawx/Lower.hs:1142-1146`       | category recovered via `env.envFieldCat` — **field-only**                                   |
| Blawx: interview `inputArity`   | `Blawx/Lower.hs:1147-1151`       | via `env.envFieldSort` — **field-only**; `RSBool → 1`, else `2`                             |
| Blawx: `rule_text`              | `Blawx/Lower.hs:219`             | `squash (fromMaybe (stubSection p) p.rpDesc)` — `rpRef` never read                          |

The consequence, precisely: `anfTerm`/`anfPred` reach an `ASSUME`d name only after
`lookupCall` (`:1154`, `:1536`) has declined, because `ctxSigs` has no entry for it. **Adding the
entry is the whole widening**; the `:1189` arm then becomes the residue for what stays out.

Prior art that must be kept consistent: `L4.Export` already does this move for the web-app leg —
`extractAssumedDependencies` (`Export.hs:362-376`) appends **referenced** `ASSUME`s to an
`@export`ed function's parameter list, gated on reachability from the `DECIDE` body, and
`assumesFromModule` (`:293-306`) **drops function-typed `ASSUME`s**. That filter is the exact
complement of ours (§2.6): a future reader who finds the two will otherwise conclude one is a bug.

---

## 2. The design

### 2.1 Shape of the lowered predicate

A top-level `ASSUME` that is **referenced by a lowered clause** becomes one `RPred`:

```haskell
MkRPred
  { rpName      = rName assumedRes
  , rpKind      = RInput
  , rpParams    = <arrow spine of the ASSUME signature, sorted>
  , rpResult    = if isBoolSort res then Nothing else Just res   -- lowerSpec's own convention
  , rpRecursion = RNonRecursive
  , rpClauses   = []                                              -- IR.hs:523 stays true
  , rpExported  = False
  , rpDesc      = <@desc on the ASSUME>
  , rpNlg       = <@nlg, linearised>
  , rpRef       = <@ref>
  , rpProv      = MkRProv { rpvUnique = …, rpvRange = rangeOf assume }
  }
```

Three decisions inside that, each with its reason:

- **`rpResult = Nothing` for a boolean `ASSUME`.** This is `lowerSpec`'s convention
  (`Lower.hs:2429`, `dsResult = if isBoolSort rs then Nothing else Just rs`) and it is what makes
  `csBool` true, which is what makes `anfPred:1541-1542` emit `RCall`/`RNotCall` — i.e. a signed
  unary goal, which is R5's classical `-p` on an input. Note this **differs from a boolean record
  field**, whose `RPred` carries `rpResult = Just RSBool` (`inputPreds:2455`) because it is reached
  through `RProj`+`RUnify` and collapsed by the Blawx boolean-projection peephole. The two
  spellings converge on the same emitted goal `is_authorised(X)`; §7 turns that into a test.
- **Parameters come from the arrow spine, flattened.** `FUNCTION FROM A AND B TO BOOLEAN` and
  `FUNCTION FROM A TO FUNCTION FROM B TO BOOLEAN` both give `rpParams = [A, B]`. A `Fun` appearing
  _inside_ a parameter is a function-typed parameter, which §6 of the ruled spec puts out of the
  fragment — rejected (§5, F2).
- **`@desc`/`@nlg`/`@ref` carry through**, mirroring `rfDesc`/`rfNlg` on a field (`Lower.hs:673-678`).
  Without this, the widening would hand Blawx a declaration with no NLG material and no citation,
  and §4.9's channel would be dead for exactly the corpus shape that has nothing else.

### 2.2 Reachability gate — this is what buys additivity

`inputPreds` (`:2449-2474`) already only emits a field an `RProj` reached. The `ASSUME` path uses
the identical technique over the same `computed <> aux` list, collecting callee names instead of
projected fields:

```haskell
assumedInputPreds :: Ctx -> [RPred] -> [RPred]
-- admits an assumed name iff some lowered clause carries `RCall n …` / `RNotCall n …`
-- with n.rnUnique in ctx.ctxAssumeDefs; walks ctxAssumeOrder (source order), never a Map
```

Order is `ctxAssumeOrder` for the same reason `ctxRecOrder` exists (`:261-271`): a `Unique`-keyed
iteration would let a declaration inserted early in a file permute an unrelated golden.

### 2.3 `ASSUME`d TYPEs become abstract categories

`anti-social.l4` has five `ASSUME T IS A TYPE`. Today `sortOfType` (`:366-379`) finds `T` in
neither `seRecords` nor `seEnums` and yields `RSOpaque "Person"`, which
`Blawx.blawxValueType:610-614` rejects ("sort with no Blawx value type") and which makes
`lowerSpec:1630-1638` emit an `R-SORT` fidelity note.

Rejected option — **a new `RSort` constructor** (`RSAbstract`): every `RSort` match in Lower,
Debug, Blawx/Lower, Blawx/Emit, Blawx/EmitXml has to gain an arm, and any that carries a
catch-all silently gets it wrong. Cost out of proportion to a category with no fields.

Rejected option — **fold into `ctxRecords`** as a zero-field record: cheapest, but it makes
`rpgRecords` (documented `IR.hs:549` as "a `DECLARE … HAS` record") lie, and `recordOf` would
then accept an abstract type as a record-literal head in `queryArg`.

**Chosen:** a new `SortEnv` field `seAbstract :: Map Unique RName`, one new `sortOfType` arm
returning `RSRecord` (so every downstream consumer keeps working unchanged — `RSRecord` already
means "a category-shaped sort" to every one of them), and a new `RelProgram` field
`rpgAbstract :: ![RAbstractDef]` carrying name + provenance. `RSRecord`'s haddock gains the
sentence that it names a category, which may be a `DECLARE`d record or an `ASSUME`d type, and
that `rpgRecords` holds only the former.

An abstract category is emitted into `rpgAbstract` only when it is the sort of a parameter or
result of an admitted predicate — same reachability discipline as everything else here.

### 2.4 Blawx: declarations

`declarations` (`Blawx/Lower.hs:619-635`) changes in three places:

1. `cats` gains `[categoryBlock a.raName a.raProv | a <- prog.rpgAbstract]`, appended after
   records and before enums (deterministic; no existing fixture has any).
2. The filter `p.rpKind /= RInput` (`:627`) becomes `not (isFieldInput env p)`, where
   `isFieldInput env p = Map.member p.rpName.rnUnique env.envFieldCat`. **Field inputs stay
   excluded** — they already get their block from `fieldAttribute` (`:649-653`) and including
   them would double-declare. `ASSUME` inputs have no field twin and fall through to
   `classifyPred`.
   - _Why a membership test and not a new `RPredKind`._ R5's semantics ("input → classical `-p`")
     is identical for both sources, so a new kind would force every `rpKind == RInput` site to be
     re-examined for a distinction that does not exist there. The `mangleAll` haddock (`:291-292`)
     already states that an input predicate shares its field's `Unique`, so the test is exact.
     Recorded as a ruling so nobody re-opens it; the alternative (a `rpInputOrigin` field, forced
     onto every construction site by `-Wmissing-fields` under `-Werror`) is named and declined.
3. The emission order becomes `cats <> fieldAttrs <> assumedInputAttrs <> declAttrs <> rels` —
   **inputs together, before computed attributes.** This is what lets §7's twin differential be a
   byte comparison rather than a set comparison.

`classifyPred` (`:567-586`) is reused verbatim: `([RSRecord T], Nothing)` → `PCAttrBool T`
(exactly a boolean field's block), `([RSRecord T], Just s)` → `PCAttrValue T`, arity 3–10 →
`PCRelationship`. **`PCUndeclared` on an input is a new named rejection** (§5, F7): a predicate
with no category-sorted subject has no Blawx attribute image, which is the arity-0 case and the
nullary-value case in one diagnostic.

`attributeBlock` (`:660-674`) is reused **unchanged** for the `ASSUME` path. This is a hard
requirement, not a convenience: it is what makes an `ASSUME`d boolean and a boolean field emit
byte-identical `blawx_attribute/…`, `*_nlg`, and `:- dynamic n/1.` lines.

`syCats` (`EmitXml.hs:378`) is derived from emitted `BDeclareCategory` blocks, so abstract
categories reach `predicateNode`'s category arm for free.

### 2.5 Blawx: the interview test, and the P1 earmark

`interviewTest` (`:1118-1154`) is already kind-based where it matters —
`inputs = [p | p <- prog.rpgPreds, p.rpKind == RInput]` (`:1141`) picks up `ASSUME`-derived
inputs with **no change**. Two helpers below it are field-based and must be generalised:

```haskell
-- was: Map.lookup p.rpName.rnUnique env.envFieldCat
cats = nubOrdOn (.rnUnique) [ c | p <- inputs, RSRecord c : _ <- [p.rpParams] ]
--                              (also RSEnum, matching classifyPred's categoryOf)

-- was: case Map.lookup p.rpName.rnUnique env.envFieldSort of Just RSBool -> 1; _ -> 2
inputArity p = length p.rpParams
             + case p.rpResult of Just RSBool -> 0; Just _ -> 1; Nothing -> 0
```

Both are byte-identical on the existing seeds — proof in §4.3/§4.4.

**The P1 earmark, revisited.** The earmark was "interview tests for modules with no record
inputs — sumlist got none". Three findings:

- The earmark is **discharged by `antisocial.l4`**: it has zero `DECLARE`s and will still emit an
  interview, because after the widening `RInput` no longer implies "record field". That is exactly
  what §4.10 promised ("L4's `ASSUME`d inputs land there naturally").
- **`sumlist` still gets none, and that is now permanent, not deferred.** Its parameters are
  `LIST OF NUMBER`; it has no `ASSUME`s and nothing abducible. The reason in the haddock
  (`:1105-1108`) — "with nothing to abduce the query would run the decision over wholly unbound
  arguments, which for a recursive module is an unbounded search, not an interview" — survives the
  widening untouched. The haddock bullet must be **reclassified from an earmark to a ruling**, and
  say why: the gate is "has an abducible input", and a list-recursive module has none in either
  source.
- The haddock's source claim ("an input predicate is a stored field", `:1147-1148`) is one of the
  stale-in-the-present-tense sentences this change creates; rewrite it, do not append.

### 2.6 The residue: what `:1189` still says

After the widening, an admitted `ASSUME` never reaches `:1189` (it matches `lookupCall` at
`:1154`). The arm stays, narrowed, for the `ASSUME`s §5 keeps out — and its message must stop
saying "there is no definition to lower and no value the L4 oracle could differentially check",
which will no longer be the general truth. New message names the specific reason (higher-order
signature / a TYPE used in value position / a sort the fragment refuses) and points at §7's twin
discipline for the oracle question.

`localDecide`'s `LocalAssume` bail (`:1076-1078`) is **unchanged in behaviour**, and its message
gains the contrast: a top-level `ASSUME` now lowers to an input predicate; a local one is scoped
to a single definition, has no module-level identity for a declaration block, and nothing can
abduce it. Fixture F4 pins that the widening did not "helpfully" travel to this site.

### 2.7 The `rpDesc <|> rpRef` one-liner

```haskell
-- Blawx/Lower.hs:219
bsText = squash (fromMaybe (stubSection p) (p.rpDesc <|> p.rpRef))
```

Three arms, and each needs a witness (§6):

| arm | condition                    | `text:` value          |
| --- | ---------------------------- | ---------------------- |
| A   | `@desc` present (`@ref` too) | the `@desc` prose      |
| B   | `@ref` only                  | the citation, squashed |
| C   | neither                      | `Definition of <n>.`   |

Arm C is already witnessed by all four existing seeds. Arms A and B are new and both land in the
**new** seed, so **no existing golden moves** — verified: `grep -n "@ref\|@desc\|@nlg"
jl4/examples/blawx/*.l4 jl4/examples/blawx/not-ok/*.l4` returns nothing today. The regression case
is a `tests-cli` assertion on the three `text:` values plus the goldens themselves; put the arm-A
and arm-B decisions **adjacent in the file** so a future reordering of `exported` cannot swap
which section carries which without failing.

`refText` (`Lower.hs:538-542`) already strips the `@ref` prefix and trims; `squash` collapses
whitespace. A multi-line `@ref` is therefore safe.

---

## 3. Every code site that changes

### `jl4-core/src/L4/Relational/IR.hs`

| #   | site                       | change                                                                                                                                                                                                               |
| --- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `RPredKind`'s `RInput` doc | `:472-483` **rewritten**: two sources (stored field, top-level `ASSUME`), how they are told apart, and the reachability gate. Delete the "A top-level `ASSUME` is /not/ lowered to one" paragraph — do not hedge it. |
| 2   | `RSort`'s `RSRecord` doc   | `:393` — names a category; `DECLARE`d record or `ASSUME`d type                                                                                                                                                       |
| 3   | new `RAbstractDef`         | `{ raName :: !RName, raProv :: !RProv }`, beside `RRecordDef`                                                                                                                                                        |
| 4   | `RelProgram`               | new field `rpgAbstract :: ![RAbstractDef]`; `-Wmissing-fields` (in `-Wall`, fatal) forces the one construction site                                                                                                  |
| 5   | `rpClauses` doc            | `:523` "empty exactly when `rpKind` is `RInput`" — still true, no change; verify, do not edit                                                                                                                        |

### `jl4-core/src/L4/Relational/Lower.hs`

| #   | site                            | change                                                                                                                                                                                              |
| --- | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 6   | new `AssumeDef` type            | beside `TopDef` (`:225-238`): res, params `[RSort]`, result `Maybe RSort`, desc/nlg/ref, range                                                                                                      |
| 7   | `SortEnv` (`:252-255`)          | new `seAbstract :: !(Map Unique RName)`; extend the haddock's "load-bearing" note to cover it                                                                                                       |
| 8   | `sortOfType` (`:366-379`)       | one arm after the `seEnums` arm: `\| Just a <- Map.lookup u se.seAbstract -> RSRecord a`                                                                                                            |
| 9   | `Ctx` (`:278-283`)              | `ctxAssumes :: Set Unique` → `ctxAssumeDefs :: !(Map Unique AssumeDef)` + `ctxAssumeOrder :: ![Unique]` + `ctxAbstractOrder :: ![Unique]`; haddock rewritten (it currently states the old policy)   |
| 10  | `buildCtx` sortEnv (`:611-614`) | populate `seAbstract` from `Assume … (Just Type{})` declarations                                                                                                                                    |
| 11  | `buildCtx` (`:658-659`)         | build `ctxAssumeDefs`/`ctxAssumeOrder`/`ctxAbstractOrder` from the `Assume` decls; classify each ASSUME as admitted or refused **here**, so the diagnostic names the declaration, not the first use |
| 12  | `buildCtx` ctxSigs (`:660-669`) | **the core change** — one `CallSig` per admitted `ASSUME`: `csName`, `csPre = []`, `csBool = isBoolSort result`                                                                                     |
| 13  | `anfTerm` (`:1189-1193`)        | narrowed residue arm + rewritten message (§2.6)                                                                                                                                                     |
| 14  | `localDecide` (`:1076-1078`)    | message only; behaviour unchanged                                                                                                                                                                   |
| 15  | new `assumedInputPreds`         | beside `inputPreds` (`:2449`), same `used`-set shape over `RCall`/`RNotCall` callees                                                                                                                |
| 16  | new `orderedAbstract`           | beside `orderedRecords` (`:2368-2369`)                                                                                                                                                              |
| 17  | `assemble` (`:2335-2365`)       | `inputs = inputPreds … <> assumedInputPreds …`; `rpgAbstract = <reachable abstract categories>`                                                                                                     |
| 18  | sort checking                   | run `checkFragmentSorts` (`:399-408`) over each admitted ASSUME's params+result, so DATE/MAYBE are refused **on the way in** with the existing diagnostics and named ranges                         |
| 19  | new higher-order refusal        | a `Fun` inside an ASSUME parameter → `LEHigherOrder`, message consistent with `:1181-1185`                                                                                                          |
| 20  | module header (`:16`)           | the pipeline comment lists `inputPreds`; add the assumed leg                                                                                                                                        |
| 21  | `anfPred` (`:1532-1545`)        | **no change** — it works through `ctxSigs`. Named here so the reviewer knows it was checked, not missed.                                                                                            |

### `jl4-core/src/L4/Relational/Debug.hs`

| #   | site            | change                                                                                                                                                         |
| --- | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 22  | `renderProgram` | new `section "abstract categories:" …` between `records:` and `enums:`. `section` drops an empty list (`:117`), so this is invisible on every existing golden. |
| 23  | `displayNames`  | include abstract-category names in the disambiguation pass, or two categories spelled alike print alike                                                        |

### `jl4-core/src/L4/Blawx/Lower.hs`

| #   | site                                      | change                                                                                                |
| --- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------- | ----------------- |
| 24  | `:219`                                    | `p.rpDesc <                                                                                           | > p.rpRef` (§2.7) |
| 25  | `declarations` `cats` (`:621-623`)        | + abstract categories                                                                                 |
| 26  | `declarations` filter (`:627`)            | `p.rpKind /= RInput` → `not (isFieldInput env p)`                                                     |
| 27  | `declarations` order (`:635`)             | `cats <> fieldAttrs <> assumedInputAttrs <> declAttrs <> rels`                                        |
| 28  | new `isFieldInput`                        | `Map.member p.rpName.rnUnique env.envFieldCat`                                                        |
| 29  | new rejection                             | input classifying `PCUndeclared` → `LEUnsupported "input predicate with no category subject (Blawx)"` |
| 30  | `interviewTest` `cats` (`:1142-46`)       | from `rpParams` (§2.5)                                                                                |
| 31  | `interviewTest` `inputArity` (`:1147-51`) | from `rpParams`/`rpResult` (§2.5)                                                                     |
| 32  | `interviewTest` haddock (`:1105-08`)      | earmark → ruling (§2.5)                                                                               |
| 33  | module header (`:41-48`, `:134-36`)       | classification + interview bullets name the `ASSUME` source                                           |

### Untouched, and why (checked, not skipped)

- `Blawx/Emit.hs` — reads no provenance (`grep -n "Prov" → 0 hits`), so the `.pl` text is
  unaffected by the new `rpProv` ranges. This is what makes §7 possible.
- `Blawx/EmitXml.hs:652-655` — the zero-argument `gap` stays. It becomes unreachable for inputs
  (rejected earlier, #29) but is still the backstop for a zero-arity computed decision.
- `jl4-core/test/RelationalSpec.hs` — imports `IR` + `buildDepGraph`/`stratify` only; no `RSort`
  constructor added, so no arm to add. It **will** need `rpgAbstract` if it constructs a
  `RelProgram` literal — check at build time; `-Wmissing-fields` will say so.
- `L4.Export` — untouched. §2's `ASSUME` handling is deliberately the complement of
  `assumesFromModule`'s function-typed filter; add a cross-reference comment at both sites so the
  next reader does not "fix" one to match the other.

---

## 4. Additivity proof

**Claim: no existing fixture can change. Zero.**

**4.1 The blast radius is 21 goldens.** By §0.1, `RelProgram` has one consumer. The observation
points are `jl4/examples/relational/expected/` (13 files) and `jl4/examples/blawx/expected/`
(4 `.blawx` + 4 `.pl`).

**4.2 Not one of them contains an `ASSUME`.**

```
$ grep -rc "ASSUME" jl4/examples/relational/ jl4/examples/blawx/ | grep -v ":0"
(no output)
```

So for all 21: `ctxAssumeDefs` is empty ⇒ `ctxSigs` is unchanged (#12 adds nothing) ⇒ `seAbstract`
is empty ⇒ `sortOfType` is unchanged (#8 never matches) ⇒ `assumedInputPreds` returns `[]` (#15,
#17) ⇒ `rpgAbstract` is `[]` ⇒ `section "abstract categories:"` prints nothing (#22) ⇒ #13, #18,
#19, #29 never fire.

**4.3 The three changes that touch a shared path anyway.** These run on every module and so must
be argued individually, not covered by 4.2:

- **#30, `interviewTest.cats`.** For a field input, `inputPreds:2454` sets
  `rpParams = [RSRecord rd.rrName]` while `envFieldCat:279-280` maps the field's unique to
  `r.rrName` — the same `RName`, from the same `orderedRecords ctx` walk. The `nubOrdOn` runs over
  the same `inputs` list in the same order. Same values, same order ⇒ byte-identical.
- **#31, `interviewTest.inputArity`.** A field input always has a one-element `rpParams` and
  `rpResult = Just fd.rfSort` (`:2454-2455`). Old: `RSBool → 1`, else `2`. New: `1 + 0` and
  `1 + 1`. Identical on the whole domain ⇒ byte-identical.
- **#26, the `declarations` filter.** With no `ASSUME`s in the tree, every `RInput` in every
  fixture is a field input, so `not (isFieldInput env p)` filters exactly the set
  `p.rpKind /= RInput` filtered ⇒ byte-identical.

**4.4 The `rpDesc <|> rpRef` change (#24) is inert on the existing seeds.**

```
$ grep -n "@ref\|@desc\|@nlg" jl4/examples/blawx/*.l4 jl4/examples/blawx/not-ok/*.l4
(no output)
```

Every exported predicate in all four seeds has `rpDesc = Nothing` **and** `rpRef = Nothing`, so
`fromMaybe (stubSection p)` fires on both the old and new expression ⇒ byte-identical.
(`tiers.l4` is the only `@ref`-bearing fixture in the tree and is relational-only; `Debug`
prints `ref:` from `rpRef` directly, untouched by #24.)

**4.5 The new arity-0 refusal (#29) hits nothing.**

```
$ grep -rn "/0 :" jl4/examples/relational/expected/
(no output)
```

No fixture has a zero-parameter predicate, so no existing module can newly fail.

**4.6 Residual risk.** The only way this is wrong is if a change lands outside the list in §3 —
in particular if #8's new `sortOfType` arm is placed **before** the `booleanUnique`/`numberUnique`
guards (it must be last), or if #27's reordering is applied to `fieldAttrs` as well as the new
list. Both are caught by the existing goldens on the first `cabal test`, which is the point.

---

## 5. What stays out, and the fixtures that pin it

Every exclusion here is a **named diagnostic**, never a silent drop — #258 §6.1's rejection census
counts by kind, and a narrowing that surfaces as "unbound reference" is a narrowing nobody can
count.

| id  | construct                                                                    | why out                                                                                                                                                                                                        | diagnostic                                                                           |
| --- | ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| F1  | **local `ASSUME`** (`Lower.hs:1076`)                                         | scoped to one definition; no module-level identity for a declaration block, nothing to abduce                                                                                                                  | `LEUnsupported "local ASSUME"` (existing, reworded)                                  |
| F2  | **higher-order `ASSUME` parameter** — `FUNCTION FROM (FUNCTION FROM …) TO …` | §6 of the ruled spec puts function-typed parameters out; the middle end is first-order Horn                                                                                                                    | `LEHigherOrder` (new)                                                                |
| F3  | **`DATE`/`MAYBE`-sorted `ASSUME`**                                           | already out for every other signature; the point of running `checkFragmentSorts` on the way in is that the range names the `ASSUME`, not the first use                                                         | `LEDate` / `LEMaybe` (existing, new reach)                                           |
| F4  | **`ASSUME T IS A TYPE` used in value position**                              | a category is a sort, not a term                                                                                                                                                                               | narrowed `:1189` arm (new message)                                                   |
| F5  | **unreferenced `ASSUME`**                                                    | not a refusal — silently contributes nothing, exactly as an unprojected record field does. This is the additivity gate (§2.2) and needs a fixture, not a diagnostic                                            | (none)                                                                               |
| F6  | **`TYPICALLY` default on an `ASSUME`** (5th `MkAssume` field)                | §5.1 already lists `TYPICALLY` as OUT-dropped-with-a-note. Do not read the field; emit the existing note if present                                                                                            | fidelity note, not an error                                                          |
| F7  | **`ASSUME`/`DECIDE` with no category-sorted subject** (the alcohol shape)    | Blawx's ontology is category-centric: no declaration block, no `unary_attribute_selector`, and `EmitXml:652-655` has no block at all — the row would blank, which is the R12 loss `noBlankedBlawxRow` fails on | `LEUnsupported "input predicate with no category subject (Blawx)"` (new, Blawx-side) |

**F7 is Blawx-side, not middle-end-side, on purpose.** A nullary `ASSUME` is a perfectly good
`RInput/0` in the relational IR and a future non-Blawx consumer (Logical English, PROLEG, plain
swipl) has an image for it. Refusing it in `Relational.Lower` would narrow the shared layer to fit
one target's block palette — the exact inversion of #258 §2.5's division of labour ("the middle
end records, this leg rejects"). So `relational/assumed-nullary.l4` **lowers** and has a Debug
golden; `blawx/not-ok/zero-arity.l4` **fails** with F7's message.

**F7's scope, CORRECTED 2026-08-19 (`fix-dispositions.md` F2/F6).** The row above reads as though
the condition were "has a category-sorted subject", full stop. It is not, and `classifyPred` never
implemented that: the refused band is **total arity ≤ 2 that is not attribute-shaped**. So an
arity-2 input _with_ a category first parameter is refused too (`blawx/not-ok/arity-two.l4`), and
from total arity 3 up an input is declared as a **relationship** whose arguments need not be
categories at all — MEASURED: an `ASSUME` over two `NUMBER`s returning a `NUMBER` is accepted and
fully declared. The diagnostic text and `BLAWX-EXPORT-SPEC.md` §6.1 now say this; the boundary is
pinned in `jl4-core/test/BlawxAssumeSpec.hs` from both sides.

---

## 6. The exact fixture and golden list

### New relational fixtures (`jl4/examples/relational/`)

| file                             | goldens                                | pins                                                                                                                                                                                                                                                                                                                                                                |
| -------------------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `assumed.l4`                     | `expected/assumed`                     | the canonical widening: `ASSUME Person IS A TYPE` → abstract category; boolean `ASSUME` → `input p/1 : (goal)`; value `ASSUME` (`FROM Person TO Conduct`) → `input conduct/1 : Conduct`; a `@desc`+`@ref`-annotated `ASSUME` (annotation carry-through); **one unreferenced `ASSUME` that must NOT appear in `predicates:`** (F5); the `abstract categories:` block |
| `assumed-nullary.l4`             | `expected/assumed-nullary`             | F7's middle-end half: `ASSUME x IS BOOLEAN` lowers to `input x/0 : (goal)` — this is the golden that proves the refusal is Blawx's, not the IR's                                                                                                                                                                                                                    |
| `not-ok/assumed-higher-order.l4` | `expected/not-ok-assumed-higher-order` | F2                                                                                                                                                                                                                                                                                                                                                                  |
| `not-ok/assumed-date.l4`         | `expected/not-ok-assumed-date`         | F3, and that the range names the `ASSUME`                                                                                                                                                                                                                                                                                                                           |
| `not-ok/local-assume.l4`         | `expected/not-ok-local-assume`         | F1 — the site at `:1076` that a careless widening would take along                                                                                                                                                                                                                                                                                                  |

Registered in `jl4/tests/RelationalExport.hs`: 2 × `goldenProgram`, 3 × `goldenErrors`.
`goldenErrors` refuses a fixture that lowers (`:129-130`), so F1–F3 cannot rot into successes.

### New Blawx fixtures (`jl4/examples/blawx/`)

| file                   | goldens                                                         | pins                                                                                                                                                                                                                                                                                                                              |
| ---------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `antisocial.l4`        | `expected/antisocial.blawx`, `expected/antisocial.pl`           | the P4b showcase: 5 abstract categories (one unreferenced → absent), 7 boolean `ASSUME` attributes, 2 value `ASSUME` attributes, 2 lambda-lifted `WHERE` helpers, the `@ref`-only export (arm B) and the `@desc`+`@ref` export (arm A), and an `interview` test on a module with **zero `DECLARE`s** — the P1 earmark's discharge |
| `antisocial-twin.l4`   | `expected/antisocial-twin.blawx`, `expected/antisocial-twin.pl` | the semantic twin (§7): identical logic spelled with `DECLARE` records whose field names are spelled **exactly** as the `ASSUME` names; carries every `#EVAL`/`#ASSERT` and every `-- L4 oracle ==>` comment                                                                                                                      |
| `not-ok/zero-arity.l4` | (none — `expectFail`)                                           | F7, in the `imaginary-alcohol-act.l4` shape                                                                                                                                                                                                                                                                                       |

`jl4/tests-cli/Main.hs` additions:

- 4 × `expectGolden` (`antisocial` / `antisocial-twin` × `.blawx` / `--scasp .pl`)
- `noBlankedBlawxRow` list `["benefit","mortality","scores","sumlist"]` → `+ ["antisocial","antisocial-twin"]`
- 1 × `expectFail` on `not-ok/zero-arity.l4` asserting `"no category subject"` in stderr
- 1 structural `it` asserting: the three `text:` arms (§2.7), `#abducible person(X).`,
  `#abducible is_authorised(X).`, `#abducible conduct(X,Y).`, and `?- may_issue_…(X,Y).`

`etc/blawx-tier1-harness.py`: `SEEDS = [… , "antisocial", "antisocial-twin"]`.
`antisocial` has no evaluable directives, so it contributes 0 oracles and 0 non-interview tests;
the `len(oracles) != len(tests)` guard (`:245`) passes at `0 == 0` — **verify this at build time
rather than trusting it**, because a 0-test seed silently contributing nothing is the failure mode
the guard exists to prevent.

`etc/blawx-fixpoint-harness.mjs`: glob-driven over `jl4/examples/blawx/expected/*.blawx`
(`:380`) — no registration needed; the obligation is that every new row has non-empty
`xml_content`, which F7 exists to guarantee.

---

## 7. The oracle problem, solved by construction

`ASSUME` is uninterpreted, so `l4 run` cannot anchor an `ASSUME`-side expectation. Worse, and more
specifically: `lowerQuery`'s facts come **only** from record-literal query arguments
(`queryArg:2130-2149`), so an `#EVAL` in an `ASSUME`-style module lowers to a query with an empty
scenario — an input predicate with no clauses and no facts simply fails, and the Blawx test would
answer "no model" for every input. That is not a weak oracle; it is a wrong one.

The brief's twin discipline is the right answer, and this design **sharpens it from an assertion
into a proof**:

1. `antisocial-twin.l4` spells its record fields with **exactly** the `ASSUME` names
   (`` `is authorised` ``, `conduct`, `effect`, …) and its records with the `ASSUME`d type names
   (`Person`, `Receiver`, `Conduct`, `Effect`).
2. On the twin, `person's \`is authorised\``lowers to`RProj`+`RUnify TRUE`, which the Blawx
boolean-projection peephole collapses to the signed unary goal `is_authorised(P)`. On the
`ASSUME` side, `` `is authorised`person `` lowers to`RCall is_authorised [P]`. **Both emit
the same goal text.** Likewise `receiver's conduct`and`conduct OF receiver`both emit`conduct(R, C)`.
3. `attributeBlock` is shared (§2.4), `Emit.hs` reads no provenance, and §2.4's ordering rule puts
   the input attributes in the same slot on both sides. So the two `.pl` files should differ
   **only** in their `ruledoc` title and their test rows.

The harness (`etc/blawx-assume-twin.mjs`, new, optional-when-present like the others) normalises
the title and drops the test rows, then compares the remainder **byte for byte**. If it passes,
"one logic, two spellings" is measured, not claimed; the twin's `#EVAL`s (which _do_ run under
`l4 run`) then carry the tier-1 oracle for the shared logic, and the `interview` rows on both
sides are a second, free cross-check.

> **CORRECTED 2026-08-19 (`fix-dispositions.md` F7).** Byte identity did hold, and that is exactly
> why the last clause is wrong: once the two programs are identical, running one of them twice is a
> re-execution, not a cross-check. The property being established IS the byte identity — measured
> fatally by `twin_preflight` in `etc/blawx-tier1-harness.py` and by `twinsAgree` in
> `jl4/tests-cli/Main.hs`. The replay is kept because it executes the artifact a Blawx reader would
> load and because it is what starts failing if identity is ever lost, but the harness now counts
> replayed rows apart from the distinct population and says so on its summary line. Do not quote
> the combined figure as coverage.

If byte-identity turns out to be unreachable for a reason this design did not foresee, the fallback
ladder — in this order, each labelled in the harness — is: (a) compare the rule stacks only, with
the ontology header sorted; (b) compare the s(CASP) modulo a declared atom-renaming table; (c)
hand-derived expectations, **labelled as unanchored in the harness output**, which the brief
correctly calls the last resort. Do not silently descend the ladder; record which rung landed in
this file.

---

## 8. Build order

1. `RelProgram.rpgAbstract` + `RAbstractDef` + the two haddock rewrites (#1–#5). Build. Existing
   goldens must be byte-stable: this step alone proves §4.2's mechanism.
2. `SortEnv.seAbstract` + `sortOfType` arm + `Ctx` reshape + `ctxSigs` extension (#6–#12, #18, #19).
   Build + `cabal test jl4-test` (relational goldens). Still byte-stable.
3. `assumedInputPreds` + `assemble` + Debug block (#15–#17, #22, #23), then `relational/assumed.l4`
   and the three not-ok fixtures. **First new goldens.** Read them before blessing.
4. Blawx declarations + interview + F7 (#25–#33), then `blawx/antisocial*.l4`. Second batch.
5. `rpDesc <|> rpRef` (#24) last, so its golden delta is isolated and reviewable on its own.
6. Harnesses: tier-1 `SEEDS`, fixpoint glob check, the new twin differential.

Each step is one `cabal` invocation at a time in this worktree.

---

## 9. What the build changed (2026-08-19, after the fact)

Written by the implementing agent, against the tree as landed. Everything in §§1–8 above was
written before any `cabal` ran; this section records where the plan and the tree disagree, so the
plan is not read as a description of what shipped. Measurements here were taken on this worktree.

### 9.1 The blocker the plan did not see: `@export` refuses a function-typed `ASSUME`

`L4.Export.validateExportInputs` (`Export.hs:507-510`, via `checkAssumeFunctionInputs`) makes it a
**type error** for an `@export`ed `DECIDE` to reference an `ASSUME` whose declared type is a
function — `ExportFunctionTypeInput`, "Function type inputs are not supported for @export" — because
`L4.Export` appends referenced `ASSUME`s to the export's parameter list and a function cannot cross
the web app's JSON boundary. The relational lowering is export-rooted, so **a module written in the
`ASSUME f IS A FUNCTION FROM Person TO BOOLEAN` spelling has no root and cannot be lowered at all**.
Measured: `l4 blawx` on such a file exits 1 before the middle end runs.

This lands directly on §0.2 and §6: `jl4/examples/legal/anti-social.l4` is written entirely in that
spelling (which is also why its own decision is not `@export`ed), so a Blawx seed copied from it
verbatim would fail type checking, not lowering. The seed has to be **re-spelled**:

```
GIVEN p IS A Person
ASSUME `is authorised` p IS A BOOLEAN
```

whose declared type is `BOOLEAN`, not an arrow, and which therefore passes. `jl4/examples/ok/signatures.l4:9-10`
shows the form is long-standing L4, not an invention.

Both spellings are admitted by the middle end (§9.2), so nothing has to move if the export rule is
later relaxed. Whether it should be — an `ASSUME`d predicate is a perfectly good logic-program
input and a nonsensical form field — is a question for the coordinator, not for this PR.

### 9.2 Two `ASSUME` spellings, not one

`assumeDef` flattens the arrow spine **and** reads app-form binders typed by the `ASSUME`'s own
`GIVEN` signature; a mixture is flattened binders-first. The plan assumed only the arrow spine and
would have refused the only spelling an exported module can use.

### 9.3 Refusals: three, not five, and two the plan did not list

The plan's F1–F4 are implemented as written (F1 local `ASSUME`, F2 higher-order parameter, F3
`DATE`/`MAYBE` via one shared `fragmentSortError` table, F4 an `ASSUME`d TYPE in value position).
F5 (unreferenced) is a silent non-emission with a fixture, as planned. F7 is Blawx-side, as ruled.
Two more were needed and are named diagnostics like the rest:

- **`ASSUME without a declared signature`** — nothing to build a predicate interface from.
- **`ASSUMEd TYPE constructor`** — `ASSUME T x IS A TYPE`. Only the nullary spelling is a category;
  a parameterised one sorts nothing and is not a term either.

F6 (`TYPICALLY`) became a **new** fidelity code, `R-TYPICALLY`. The plan said to "emit the existing
note"; there was no existing note, and a dropped default with no note is exactly the silent loss
§5 forbids. `assumed-nullary.l4` is its witness. An `ASSUME` whose sort the fragment cannot name
also earns the `R-SORT` note that `lowerSpec` emits for a decision — input predicates do not go
through `lowerSpec`, so `assumedNotes` emits it.

### 9.4 Fixtures: what was built, and what was not

Built, all green: `relational/assumed.l4`, `relational/assumed-nullary.l4`,
`relational/not-ok/assumed-signatures.l4` (F2 + `DATE` + `MAYBE`, batched),
`relational/not-ok/local-assume.l4`, each with its Debug golden.

Renamed from the plan: `not-ok/assumed.l4` → `not-ok/assumed-signatures.l4`. `RelationalExport`
checks each fixture under its own **basename** as the module name and every provenance comment
prints it, so two fixtures called `assumed.l4` would have made two goldens claim one origin.

**Not built, and owed:** the Blawx seeds (`blawx/antisocial.l4`, its twin,
`blawx/not-ok/zero-arity.l4`), the tier-1 `SEEDS` extension, and §7's twin differential harness. Those are corpus
work and were out of this agent's scope. The Blawx side of the widening is instead pinned by
`jl4-core/test/BlawxAssumeSpec.hs` — thirteen examples running the real pipeline (type check →
`lowerModule` → `lowerBlawx` → `renderBlawxYaml`) over inline sources, covering the category and
attribute declarations, R5 classical negation on an `ASSUME`d input, the reachability gate, the
`#abducible` interview on a module with **no** `DECLARE`, the no-double-declaration property that
the changed `declarations` filter could have broken, all three `rule_text` arms, and both
refusals. A seed golden is still the right home for the byte shape; this is what holds until one
exists.

### 9.5 Additivity, measured

Every existing golden is byte-identical: 13 relational Debug goldens, 4 `.blawx` + 4 `.pl`
(compared with `diff` against a freshly built `l4`). Suites: `jl4-test` 2585 examples / 0 failures,
`l4-cli-test` 264 / 0, `jl4-core-test` 301 / 0. `cabal build all` clean under `-Werror`.

§4.6's named residual risk — the new `sortOfType` arm placed before the builtin guards — did not
materialise: the arm is last, after `seRecords` and `seEnums`, so a `DECLARE` and a builtin both
still win over an `ASSUME`d type of the same name.
