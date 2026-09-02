-- | Classify a 'L4.Relational.IR.RelProgram' into a 'L4.Blawx.IR.BlawxDoc'.
--
-- This layer is deliberately thin (BLAWX-EXPORT-SPEC R2): DNF, ANF,
-- aggregate recognition and guard-prefix materialisation already happened in
-- "L4.Relational.Lower". What remains here is /classification/ and the
-- target-lexical work the shared IR refuses to do:
--
-- * name mangling into Blawx atoms ('blawxAtom') + the injective, global
--   collision check (one namespace: categories, attributes, relationships,
--   constructors, skolems, string atoms — the atom IS the predicate in
--   Blawx), following the OpenFisca @pyIdent@\/@checkCollisions@ discipline;
-- * the one linear sort-recovery pass per clause (head → 'rpParams', 'RProj'
--   → 'rfSort', 'RCall' → callee 'rpResult', 'REval'\/aggregate → number,
--   'RFindAll' → list), driving @REq@\/@RNeq@ dispatch and declaration typing;
-- * negation dispatch by callee kind (R5): 'RInput' → classical @-p@,
--   'RComputed'\/'RAuxiliary' → NAF @not p@;
-- * skolemisation of query subjects (one constant per @(rqId, rvId)@);
-- * Blawx-specific rejections, each a named diagnostic: relationship arity
--   above 10, 'RUnstratified', 'RMod', non-integral literals while the R7
--   measurement gate holds, and equality\/disequality whose operand sort
--   contains a declared record ('recordIdentity', §11 W1).
--
-- == Decisions made here (P1 stage B), so nobody re-derives them
--
-- __The @REq@\/@RNeq@ dispatch__ (the choice "L4.Relational.IR" says every
-- emitter must make explicitly): an equality whose either operand is
-- /numeric/ — a number literal, or a variable whose recovered sort is
-- 'RSNum' — becomes @blawx_comparison(X,eq\/neq,Y)@ (CLP, per R7); every
-- other equality becomes unification @X = Y@ (@REq@) or
-- @blawx_diseq(X,Y)@ (@RNeq@). @=:=@-style arithmetic equality on an atom
-- would raise rather than fail, which is why the split is by operand sort
-- and not by operator. __An operand whose sort contains a declared record is
-- refused__ rather than dispatched at all ('recordIdentity', spec §11 W1): the
-- two languages disagree on what equality of a record /means/, so any answer
-- would be a guess. An @ASSUME@d abstract category is /not/ a declared record
-- for this purpose and still unifies. See that function's haddock.
--
-- __The boolean-projection peephole__: @'RProj' a f V@ over a
-- 'RSBool'-sorted field followed immediately by @'RUnify' V ('RTBool' b)@
-- collapses to the signed unary goal @f(A)@ \/ @-f(A)@ (classical — the
-- field is an input, so an absent input fails loudly, R5). The lowering
-- always emits the pair adjacently (the unify is the projection's first
-- use); a boolean projection consumed any other way is out of fragment and
-- rejected by name.
--
-- __Predicate classification__: params @[record\/enum]@ → attribute of that
-- category (unary when 'rpResult' is 'Nothing', binary otherwise); total
-- arity 3–10 otherwise → relationship; total arity ≤ 2 that is not
-- attribute-shaped (a list-recursive helper like @sumlist\/2@, or the
-- synthesised @member\/2@) → __no declaration block__, rules only: Blawx's
-- relationship blocks start at arity 3, and s(CASP) needs no declaration to
-- execute. The block-fidelity gap this leaves for such predicates is
-- recorded for P3 (they have no scenario-editor image either way). The one
-- shape that is not merely undeclared but __refused__ is an 'RInput' landing
-- in that last bucket: an input is a fact the scenario editor and the
-- interview must be able to state, and a fact with no category subject has no
-- block to state it in (see 'declarations').
--
-- __The two sources of 'RInput' are declared from different places.__ A
-- stored record field's block comes from the record ('fieldAttribute'); a
-- top-level @ASSUME@\'s comes from the classifier, through the same
-- 'attributeBlock', so the two spellings of one fact emit identical
-- declarations. Categories likewise come from @DECLARE@d records, @ASSUME@d
-- types ('rpgAbstract') and enums, in that order.
--
-- __Category guards__: every clause of a predicate with record- or
-- enum-sorted head parameters gets @cat(X)@ goals prepended, in parameter
-- order — the generator's rules always establish the subject's category
-- first, and the accepted exemplar does the same.
--
-- __@#pred@ NLG sourcing — deviation from R10's letter, reported as a
-- finding__: 'rpNlg'\/'rfNlg' are linearised sentences whose parameter slots
-- are plain words ("the loyalty bonus earned by m" — the @%m%@ marker does
-- not survive 'L4.Relational.Lower''s linearisation), so they cannot be
-- decomposed into the prefix\/infix\/postfix slot structure the block model
-- /stores/ — and an undecomposable sentence would break the R12 fixpoint
-- and the P5 lift. Until slot-structured NLG rides the IR, every
-- declaration's slots are synthesised from the mangled atom: category
-- @"is a ⟨pretty⟩"@ (article by initial vowel), boolean attribute postfix
-- @⟨pretty⟩@, value attribute infix @"has ⟨pretty⟩ of"@, relationship
-- prefixes @""@\/@"and"@ with postfix @"are related as ⟨pretty⟩"@ — all
-- guaranteed non-empty in interior positions (empty middles would emit the
-- generator's preserved double spaces) and quote-free (the @*_nlg@ facts
-- carry slot text unescaped).
--
-- __Mangling__ ('blawxAtom'): strip backticks, split @camelCase@ at a
-- lower\/digit→upper boundary, map every non-ASCII-alphanumeric to a
-- separator, lowercase, join with @_@ (so @isVeteran@ → @is_veteran@,
-- @eligible for benefit@ → @eligible_for_benefit@). Non-ASCII letters are
-- dropped, not transliterated (no unicode-normalisation dependency; a name
-- that mangles to nothing gets the @p_@ prefix and, being shared, fails the
-- injectivity check loudly). A result that would end @_\d+@ gains a
-- trailing @x@ — the UI validator silently rewrites that suffix, which
-- would break the R12 fixpoint.
--
-- __Skolems__: one constant per @(rqId, rvId)@ — first letter of the
-- subject's category atom plus a 1-based per-letter, per-query ordinal
-- (@a1@); an ordinal that lands on a declared atom is bumped, not rejected
-- (renaming a synthesised constant is safe precisely because nothing else
-- names it; declared names are never renamed, per the OpenFisca
-- discipline). Reuse of the same constant across two tests is deliberate —
-- tests never load together.
--
-- == Stage-C decisions
--
-- __Bodyless clauses are fact blocks, not degenerate rules.__ A clause whose
-- converted body is empty (@running total([], 0)@ — a structural-recursion
-- base case with no record parameter, so no category guard either) would
-- reproduce the generator's own @\") :- .\"@, which is not consultable
-- Prolog and would break tier 1. Blawx has no empty-conditions rule in
-- practice — a user states such a base case as a standalone fact block — so
-- the clause lowers to 'L4.Blawx.IR.BFact' (possibly non-ground: a
-- universally quantified fact is ordinary Prolog and an ordinary block).
-- The cost is that the base case is not @according_to@-attributed to its
-- section; the bare predicate is what rules consume, so answers are
-- unchanged.
--
-- __Multi-goal @findall@ bodies are factored through a fresh auxiliary
-- predicate__ ('factorFindAlls', a pre-pass over the 'RelProgram'). Blawx's
-- @collect_list@ block renders its search stack via Blockly's
-- @statementToCode@, whose @scrub_@ concatenates chained blocks with NO
-- separator — so a multi-block search is not merely unfaithful, it is
-- garbage; the only block image of a conjunctive search is a single call to
-- a predicate defined by its own rule. The synthesised predicate is named
-- @\<decision\> generator@ (then @… generator b@, @c@ … within one
-- decision), is 'RAuxiliary', gets a dependency edge from its decision (so
-- R4 files it in the same section), and its clause is the factored body
-- verbatim.
--
-- __Dates are rejected by name.__ The middle-end carries a @DATE@-sorted
-- field as @'RSOpaque' \"DATE\"@; Blawx v1 rejects it with the named
-- diagnostic @dates (Blawx v1)@ pointing at @DATE-LIBRARY-SPEC.md@
-- (R-D1\/R-D4 record the eventual convention) rather than the generic
-- unknown-sort refusal.
--
-- == Review-pass decisions (P1 stage D)
--
-- __Titles are CLEAN-importable by construction__: suffix-only @.l4@ strip,
-- first character uppercased ('capitalizeFirst') — clean-law 0.0.4 (the
-- version Blawx pins) rejects a lowercase-initial title at import time,
-- which would make the whole @.blawx@ unimportable. A title whose first
-- character is not a letter (a digit-initial module basename) still fails
-- CLEAN's grammar; that residue is accepted as out of fragment.
--
-- __String atoms are program-globally injective__ ('stringAtomTable'):
-- distinct spellings mangling to one atom are rejected by name, and
-- skolemisation avoids the finished table, so no string can be conflated
-- with another string, a declared name, or a skolem constant.
--
-- __One @#abducible@ interview test per module__ ('interviewTest', R11 as
-- ruled) when the module has input predicates — of either source, so a module
-- with no @DECLARE@ at all still gets one; test-name slugs are checked for
-- uniqueness ('checkTestNames').
--
-- __A section's @rule_text@ falls back through the citation__: @\@desc@, then
-- @\@ref@, then the @\"Definition of x.\"@ stub (see 'lowerBlawx'). @\@nlg@
-- remains deliberately unconsumed here, for the reason recorded above.
module L4.Blawx.Lower
  ( lowerBlawx
  ) where

import Base
import Control.Applicative ((<|>))
import qualified Base.Map as Map
import qualified Base.Text as Text
import Data.Char (chr, isAsciiLower, isAsciiUpper, isDigit, ord, toLower, toUpper)
import qualified Data.Set as Set

import L4.Blawx.IR
import L4.Parser.SrcSpan (SrcRange)
import L4.Relational.IR
import L4.Syntax (Unique (..))

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

-- | Lower a relational program to a Blawx document. Errors accumulate within
-- each stage (naming, classification, clauses, queries), following the shared
-- 'LowerError' convention; the stages themselves are sequential because each
-- consumes the previous stage's environment.
lowerBlawx :: RelProgram -> Either [LowerError] BlawxDoc
lowerBlawx prog0 = do
  checkStratified prog0
  -- Sort recovery for the factoring pre-pass needs the field tables, which do
  -- not depend on the pre-pass; the real environment is then rebuilt so the
  -- synthesised generator predicates go through the same mangling and
  -- collision check as everything else.
  env0 <- buildEnv prog0
  let prog = factorFindAlls env0 prog0
  env1 <- buildEnv prog
  -- String-literal atoms are collected program-wide BEFORE any conversion:
  -- the mangling ("foo bar" → foo_bar) is not injective, so two distinct
  -- spellings landing on one atom must be a named rejection, not a silent
  -- conflation — and skolemisation must know every string atom up front so a
  -- minted constant can never coincide with one (see 'stringAtomTable').
  strTable <- stringAtomTable env1 prog
  let env = env1 { envStringAtoms = strTable }
  let exported = [ p | p <- prog.rpgPreds, p.rpExported ]
  when (null exported) $
    Left [ blawxErr "" Nothing LENoExport
             "no @export decision reached the Blawx classifier" ]
  let secOf = sectionAssignment prog exported
      nSecs = length exported
  declBlocks <- declarations env prog
  ruleBySec  <- ruleBlocks env prog secOf
  qtests     <- collectE [ convertQuery env q | q <- prog.rpgQueries ]
  interview  <- interviewTest env prog exported
  let tests = qtests <> maybeToList interview
  checkTestNames tests
  let rootStacks =
        [ declBlocks | not (null declBlocks) ]
          <> [ enumFacts | let enumFacts = enumConstructorFacts env prog
             , not (null enumFacts) ]
      rootWs = [ MkBWorkspace { bwName = BRoot, bwStacks = rootStacks, bwComment = Nothing }
               | not (null rootStacks) ]
      secWs =
        [ MkBWorkspace
            { bwName   = bSec i
            , bwStacks = [ [b] | b <- Map.findWithDefault [] i ruleBySec ]
            , bwComment = Nothing
            }
        | i <- [1 .. nSecs]
        ]
      -- CLEAN's title grammar (clean-law 0.0.4, the version Blawx pins)
      -- requires the first word to start with an uppercase character; a
      -- lowercase title raises ParseException in RuleDoc.save() during the
      -- import view's pre_save signal, making the whole .blawx unimportable.
      -- So: suffix-only extension strip (never a global ".l4" substitution),
      -- then uppercase the first character — of the § heading too, since an
      -- unimportable title is worse than a re-cased one. Section eIds
      -- (sec_1..sec_n) do not depend on the title text.
      fallback = fromMaybe prog.rpgSource (Text.stripSuffix ".l4" prog.rpgSource)
      title = capitalizeFirst (fromMaybe fallback prog.rpgTitle)
  pure MkBlawxDoc
    { bdName       = title
    , bdRuleText   = MkBRuleText
        { brTitle    = title
        , brSections =
            [ MkBSection
                { bsNumber = i
                -- @\@desc@ first, then the @\@ref@ citation, then a stub. The
                -- citation is a worse section text than prose and a much better
                -- one than "Definition of x." — a corpus annotated for
                -- provenance rather than for explanation (a statute encoding
                -- with a @\@ref@ per section) gets its section headings for
                -- free, and R4's promise that a target-side answer lifts back
                -- to a citation stops depending on whether the author also
                -- wrote prose. 'refText' has already stripped the @\@ref@
                -- herald; 'squash' flattens a multi-line citation AND maps
                -- em\/en dashes to hyphens: CLEAN gives an em dash STRUCTURAL
                -- meaning in section bodies (a legislative sub-paragraph
                -- introduction), so a mid-text em dash silently swallows
                -- every following section into this one — measured 2026-08-19
                -- against the pinned clean-law: a 14-section rule_text whose
                -- section 1 contained "hearing—" produced an AKN with ONLY
                -- sec_1, breaking every later citation link (/rule/sec_N/
                -- 500s). Same family as 'capitalizeFirst''s title guard.
                , bsText   = squash (fromMaybe (stubSection p) (p.rpDesc <|> p.rpRef))
                }
            | (i, p) <- zip [1 ..] exported
            ]
        }
    , bdWorkspaces = rootWs <> secWs
    , bdTests      = tests
      -- import-only (the observed doc_selector labels); Mode-A export has
      -- none, so EmitXml falls through to its computed label
    , bdDocPartNames = mempty
    }
 where
  stubSection p = "Definition of " <> p.rpName.rnBase <> "."
  squash =
    Text.unwords . Text.words . Text.replace "\x2014" "-" . Text.replace "\x2013" "-"

-- | Blawx v1 rejects a non-stratified program with a named diagnostic: its
-- L4-oracle determinism obligation does not tolerate multiple stable models,
-- even though s(CASP) itself would (the middle-end records, this leg rejects
-- — the #258 §2.5 division of labour).
checkStratified :: RelProgram -> Either [LowerError] ()
checkStratified prog = case prog.rpgStrata of
  RStratified _ -> Right ()
  RUnstratified sccs ->
    Left
      [ blawxErr "" Nothing
          (LEUnsupported "unstratified negation (Blawx v1)")
          ( "a cycle through negation has more than one stable model, which the \
            \Blawx leg's determinism obligation cannot honour: "
              <> Text.intercalate "; "
                   [ Text.intercalate " -> " (map (.rnBase) scc) | scc <- sccs ]
          )
      ]

-- ---------------------------------------------------------------------------
-- Naming environment
-- ---------------------------------------------------------------------------

data Env = MkEnv
  { envAtoms     :: !(Map Unique BName)
    -- ^ every named entity's mangled atom, keyed by identity
  , envAtomTexts :: !(Set Text)
    -- ^ the occupied atom texts (skolems and string atoms must not land here)
  , envStringAtoms :: !(Map Text Text)
    -- ^ every string literal's atom → its source spelling, precollected over
    -- the whole program ('stringAtomTable'); injective by construction, and
    -- consulted by 'skolemise' so a skolem never lands on a string atom
  , envPredKind  :: !(Map Unique RPredKind)
  , envPredResult :: !(Map Unique (Maybe RSort))
  , envFieldSort :: !(Map Unique RSort)
  , envFieldCat  :: !(Map Unique RName)   -- ^ field → owning record
  , envDeclRecords :: !(Set Unique)
    -- ^ the @DECLARE … HAS@ record names, and only those. 'RSRecord' also
    -- carries an @ASSUME T IS A TYPE@ ("L4.Relational.IR": one constructor for
    -- both, because every declaration-side use wants \"a category named /n/\"),
    -- so a consumer that needs to tell a record from an abstract category looks
    -- the name up here — which is what 'recordInSort' does, and the reason
    -- 'recordIdentity' refuses the first and admits the second.
  }

buildEnv :: RelProgram -> Either [LowerError] Env
buildEnv prog = do
  atoms <- mangleAll entities
  pure MkEnv
    { envAtoms     = atoms
    , envAtomTexts = Set.fromList [ bNameText n | n <- Map.elems atoms ]
    , envStringAtoms = Map.empty   -- filled by 'stringAtomTable' in 'lowerBlawx'
    , envPredKind  = Map.fromList [ (p.rpName.rnUnique, p.rpKind) | p <- prog.rpgPreds ]
    , envPredResult = Map.fromList [ (p.rpName.rnUnique, p.rpResult) | p <- prog.rpgPreds ]
    , envFieldSort = Map.fromList
        [ (f.rfName.rnUnique, f.rfSort) | r <- prog.rpgRecords, f <- r.rrFields ]
    , envFieldCat  = Map.fromList
        [ (f.rfName.rnUnique, r.rrName) | r <- prog.rpgRecords, f <- r.rrFields ]
    , envDeclRecords = Set.fromList [ r.rrName.rnUnique | r <- prog.rpgRecords ]
    }
 where
  entities =
    [ (r.rrName, "record", r.rrProv.rpvRange) | r <- prog.rpgRecords ]
      <> [ (f.rfName, "field", Nothing) | r <- prog.rpgRecords, f <- r.rrFields ]
      -- An ASSUMEd TYPE is a category and needs an atom like any other: it is
      -- declared, it is the subject of its attributes' blocks, and it must be
      -- in the injectivity check or a record and an assumed type spelled alike
      -- would silently become one category.
      <> [ (a.raName, "assumed type", a.raProv.rpvRange) | a <- prog.rpgAbstract ]
      <> [ (e.reName, "enum", e.reProv.rpvRange) | e <- prog.rpgEnums ]
      <> [ (c, "enum constructor", e.reProv.rpvRange)
         | e <- prog.rpgEnums, c <- e.reCons ]
      <> [ (p.rpName, "predicate", p.rpProv.rpvRange) | p <- prog.rpgPreds ]

-- | Mangle every entity once (an input predicate shares its field's 'Unique'
-- and therefore its atom) and check injectivity plus the reserved list.
mangleAll :: [(RName, Text, Maybe SrcRange)] -> Either [LowerError] (Map Unique BName)
mangleAll items =
  let (errs, _, byUnique) = foldl' step ([], Map.empty, Map.empty) items
  in  if null errs then Right byUnique else Left errs
 where
  step acc@(errs, byText, byUnique) (rn, what, rng)
    | Map.member rn.rnUnique byUnique = acc
    | otherwise =
        let atomT = blawxAtom rn.rnBase
        in case mkBName (Just rn.rnUnique) atomT of
             Nothing ->
               ( errs
                   <> [ blawxErr rn.rnBase rng
                          (LEUnsupported "unmanglable name (Blawx)")
                          ( "the " <> what <> " name `" <> rn.rnBase
                              <> "` mangles to `" <> atomT
                              <> "`, which is not a valid Blawx atom" ) ]
               , byText, byUnique )
             Just bn
               | isReservedAtom atomT ->
                   ( errs
                       <> [ blawxErr rn.rnBase rng
                              (LEUnsupported "reserved Blawx/Prolog name")
                              ( "the " <> what <> " name `" <> rn.rnBase
                                  <> "` mangles to the reserved atom `" <> atomT
                                  <> "` — rename it in the L4 source" ) ]
                   , byText, byUnique )
               | Just other <- Map.lookup atomT byText ->
                   ( errs
                       <> [ blawxErr rn.rnBase rng
                              (LEUnsupported "name collision (Blawx)")
                              ( "distinct L4 definitions `" <> other.rnBase
                                  <> "` and `" <> rn.rnBase
                                  <> "` both mangle to the Blawx atom `" <> atomT
                                  <> "` — rename one" ) ]
                   , byText, byUnique )
               | otherwise ->
                   ( errs
                   , Map.insert atomT rn byText
                   , Map.insert rn.rnUnique bn byUnique )

-- | See the module header for the algorithm and its deliberate limits.
blawxAtom :: Text -> Text
blawxAtom raw =
  let noTicks  = Text.filter (/= '`') raw
      split'   = camelSplit noTicks
      cleaned  = Text.map (\c -> if plainChar c then toLower c else ' ') split'
      joined   = Text.intercalate "_"
                   (filter (not . Text.null) (Text.split (\c -> c == ' ' || c == '_') cleaned))
      prefixed = case Text.uncons joined of
        Just (c, _) | isAsciiLower c -> joined
        _                            -> "p_" <> joined
  in  if trapSuffix prefixed then prefixed <> "x" else prefixed
 where
  plainChar c = isAsciiLower c || isAsciiUpper c || isDigit c || c == '_'
  -- the UI validator rewrites atoms ending @_\d+@; see 'mkBName'
  trapSuffix t =
    let ds = Text.takeWhileEnd isDigit t
    in  not (Text.null ds) && "_" `Text.isSuffixOf` Text.dropWhileEnd isDigit t

-- | @isVeteran@ → @is Veteran@; an upper run is left alone (@HTTPServer@ →
-- @h_t_t_p…@ is ugly but injective-safe, and no such name is in the corpus).
camelSplit :: Text -> Text
camelSplit t = Text.pack (go (Text.unpack t))
 where
  go (a : b : rest)
    | (isAsciiLower a || isDigit a) && isAsciiUpper b = a : ' ' : go (b : rest)
    | otherwise                                       = a : go (b : rest)
  go xs = xs

-- | The reserved list from @p1-design/emit-plan.md@ §10, verified against the
-- Blawx libraries at checkout @02eded1@.
isReservedAtom :: Text -> Bool
isReservedAtom t = "blawx_" `Text.isPrefixOf` t || t `Set.member` reservedAtoms

reservedAtoms :: Set Text
reservedAtoms = Set.fromList
  [ -- Blawx library predicates
    "holds", "according_to", "opposes", "overrules"
  , "date_compare", "date_add", "duration_compare"
  , "count_blawx_list", "sum_blawx_list", "average_blawx_list"
  , "min_blawx_list", "max_blawx_list"
    -- functor/sentinel atoms
  , "date", "datetime", "time", "duration", "bot", "eot", "user", "not_applicable"
    -- Prolog / s(CASP) syntax
  , "is", "not", "findall", "false", "true", "dynamic", "pred", "abducible"
  , "mod", "div", "rem"
  ]

atomOf :: Env -> RName -> Either [LowerError] BName
atomOf env rn = case Map.lookup rn.rnUnique env.envAtoms of
  Just bn -> Right bn
  Nothing ->
    Left [ blawxErr rn.rnBase Nothing LEUnbound
             ("`" <> rn.rnBase <> "` was not named by the Blawx mangling pass") ]

-- | Precollect every string literal in the program (clause heads and bodies,
-- query arguments, scenario facts, expected values) into an injective table
-- atom → source spelling. 'blawxAtom' is not injective (@"foo bar"@ and
-- @"Foo Bar"@ both mangle to @foo_bar@), so without this pass two distinct
-- strings would silently unify into one constant and change answers; a
-- collision — with another spelling or with a declared atom — is a named
-- rejection instead (a string is quoted verbatim in the source, so renaming
-- one is not ours to do). 'skolemise' consults the finished table so a
-- minted skolem constant can never land on a string atom either; the reverse
-- direction needs no check precisely because the table is complete before
-- the first skolem is minted.
stringAtomTable :: Env -> RelProgram -> Either [LowerError] (Map Text Text)
stringAtomTable env prog =
  let (allErrs, table) = foldl' step ([], Map.empty) (clauseStrs <> queryStrs)
  in  if null allErrs then Right table else Left allErrs
 where
  step (errs, tbl) (fn, s) =
    let atomT = blawxAtom s
    in  if atomT `Set.member` env.envAtomTexts
          then ( errs
                   <> [ blawxErr fn Nothing
                          (LEUnsupported "string literal collides with a declared name (Blawx)")
                          ( "the string literal \"" <> s <> "\" mangles to the atom `"
                              <> atomT <> "`, which is already a declared name — \
                                \rename the definition or change the string" ) ]
               , tbl )
          else case Map.lookup atomT tbl of
            Just other | other /= s ->
              ( errs
                  <> [ blawxErr fn Nothing
                         (LEUnsupported "string literal collision (Blawx)")
                         ( "distinct string literals \"" <> other <> "\" and \"" <> s
                             <> "\" both mangle to the Blawx atom `" <> atomT
                             <> "` and would be silently conflated — rewrite one" ) ]
              , tbl )
            _ -> (errs, Map.insert atomT s tbl)
  clauseStrs =
    [ (p.rpName.rnBase, s)
    | p <- prog.rpgPreds
    , cl <- p.rpClauses
    , s <- concatMap termStrs cl.rcHead <> concatMap goalStrs cl.rcBody
    ]
  queryStrs =
    [ ("#" <> q.rqId, s)
    | q <- prog.rpgQueries
    , s <- concatMap termStrs q.rqArgs
             <> concatMap (concatMap termStrs . (.rfaArgs)) q.rqFacts
             <> concatMap termStrs (maybeToList q.rqExpected)
    ]
  termStrs = \case
    RTStr s    -> [s]
    RTCons h t -> termStrs h <> termStrs t
    _          -> []
  goalStrs = \case
    RCall _ ts        -> concatMap termStrs ts
    RNotCall _ ts     -> concatMap termStrs ts
    RProj subj _ _    -> termStrs subj
    RUnify _ t        -> termStrs t
    RMatch _ _        -> []
    RCmp _ x y        -> termStrs x <> termStrs y
    REval _ _         -> []
    RFindAll _ body _ -> concatMap goalStrs body
    RAggregate {}     -> []

-- ---------------------------------------------------------------------------
-- findall factoring (see the module header: one block per search)
-- ---------------------------------------------------------------------------

data FacSt = MkFacSt
  { fasFresh :: !Int                 -- ^ next synthesised-'Unique' ordinal
  , fasCount :: !(Map Unique Int)    -- ^ generators minted per decision
  , fasAux   :: ![RPred]             -- ^ collected, in reverse mint order
  , fasDeps  :: ![RDepEdge]
  }

-- | Rewrite every multi-goal 'RFindAll' body into a single call to a fresh
-- 'RAuxiliary' predicate whose one clause is the body verbatim. The
-- generator's arguments are exactly the body's variables that are visible
-- outside it (the template included); body-local variables stay local.
factorFindAlls :: Env -> RelProgram -> RelProgram
factorFindAlls env prog =
  let (preds', st) =
        runState (traverse factorPred prog.rpgPreds) (MkFacSt 1 Map.empty [] [])
  in  prog
        { rpgPreds = preds' <> reverse st.fasAux
        , rpgDeps  = prog.rpgDeps <> reverse st.fasDeps
        }
 where
  factorPred p = do
    cls <- traverse (factorClause p) p.rpClauses
    pure p { rpClauses = cls }

  factorClause p cl = do
    let sorts = varSorts env p cl
        headIds = Set.fromList [ v.rvId | v <- concatMap termVars cl.rcHead ]
    body' <- goGoals p cl sorts headIds cl.rcBody
    pure cl { rcBody = body' }

  goGoals p cl sorts amb gs = traverse one (zip [0 :: Int ..] gs)
   where
    siblingIds i = Set.fromList
      [ v.rvId | (j, g) <- zip [0 ..] gs, j /= i, v <- goalVars g ]
    one (i, RFindAll tmpl body out) = do
      let inner = amb <> siblingIds i
                    <> Set.fromList [tmpl.rvId, out.rvId]
      body' <- goGoals p cl sorts inner body
      if length body' <= 1
        then pure (RFindAll tmpl body' out)
        else do
          let args =
                [ v
                | v <- nubOrdOn (.rvId) (concatMap goalVars body')
                , v.rvId `Set.member` inner
                ]
          nm <- mintGenerator p cl sorts args body'
          pure (RFindAll tmpl [RCall nm (map RTVar args)] out)
    one (_, g) = pure g

  mintGenerator p cl sorts args body' = do
    st <- get
    let k = 1 + Map.findWithDefault 0 p.rpName.rnUnique st.fasCount
        -- " b", " c", … from the second generator of one decision on; a bare
        -- ordinal would end the mangled atom @_\d+@ (the UI validator trap)
        suffix
          | k == 1    = ""
          | otherwise = " " <> Text.singleton (chr (ord 'a' + k - 1))
        base = p.rpName.rnBase <> " generator" <> suffix
        u = MkUnique
              { sort = 'b'   -- 'b' for Blawx; the middle-end's own mints use 'x'
              , unique = st.fasFresh
              , moduleUri = p.rpProv.rpvUnique.moduleUri
              }
        nm = MkRName { rnText = base, rnBase = base, rnUnique = u }
        auxPred = MkRPred
          { rpName      = nm
          , rpKind      = RAuxiliary
          , rpParams    =
              [ Map.findWithDefault (RSOpaque "findall generator argument")
                  v.rvId sorts
              | v <- args
              ]
          , rpResult    = Nothing
          , rpRecursion = RNonRecursive
          , rpClauses   =
              [ MkRClause
                  { rcHead        = map RTVar args
                  , rcBody        = body'
                  , rcGuardPrefix = 0
                  , rcProv        = cl.rcProv
                  }
              ]
          , rpExported  = False
          , rpDesc      = Just "findall generator, factored so the search is a single block"
          , rpNlg       = Nothing
          , rpRef       = Nothing
          , rpProv      = MkRProv { rpvUnique = u, rpvRange = cl.rcProv.rpvRange }
          }
    put st
      { fasFresh = st.fasFresh + 1
      , fasCount = Map.insert p.rpName.rnUnique k st.fasCount
      , fasAux   = auxPred : st.fasAux
      , fasDeps  =
          MkRDepEdge { redFrom = p.rpName, redTo = nm, redSign = RPositive }
            : st.fasDeps
      }
    pure nm

-- ---------------------------------------------------------------------------
-- Classification and declarations
-- ---------------------------------------------------------------------------

-- | What a predicate is, in Blawx's ontology.
data PredClass
  = PCAttrBool !RName          -- ^ unary attribute of the category
  | PCAttrValue !RName !BValueType
  | PCRelationship ![BValueType]
  | PCUndeclared               -- ^ arity ≤ 2, not attribute-shaped: rules only

classifyPred :: Env -> RPred -> Either [LowerError] PredClass
classifyPred env p = case (p.rpParams, p.rpResult) of
  ([s], Nothing) | Just cat <- categoryOf s -> Right (PCAttrBool cat)
  ([s], Just res) | Just cat <- categoryOf s ->
    PCAttrValue cat <$> valueType env p res
  (params, res)
    | arity > 10 ->
        Left [ blawxErr p.rpName.rnBase p.rpProv.rpvRange LEArity
                 ( "`" <> p.rpName.rnBase <> "` needs a Blawx relationship of arity "
                     <> Text.textShow arity <> ", above the block ceiling of 10" ) ]
    | arity >= 3 ->
        PCRelationship <$> collectE (map (valueType env p) (params <> maybeToList res))
    | otherwise -> Right PCUndeclared
   where
    arity = length params + maybe 0 (const 1) res

-- | The category a sort names, if it names one. Blawx's ontology is
-- category-centric: a declaration block hangs off a subject, and a sort that is
-- not a category cannot be one. 'RSRecord' covers both a declared record and an
-- @ASSUME@d type ("L4.Relational.IR"), which is exactly the collapse this leg
-- wants — the two produce the same category block.
categoryOf :: RSort -> Maybe RName
categoryOf = \case
  RSRecord r -> Just r
  RSEnum r   -> Just r
  _          -> Nothing

-- | An attribute/relationship argument's declared Blawx value type.
valueType :: Env -> RPred -> RSort -> Either [LowerError] BValueType
valueType env p = blawxValueType env p.rpName.rnBase p.rpProv.rpvRange

-- | Sort → Blawx value type, with the two named rejections: dates (v1, by
-- name — see the module header) and everything else the ontology cannot
-- declare.
blawxValueType :: Env -> Text -> Maybe SrcRange -> RSort -> Either [LowerError] BValueType
blawxValueType env who rng = \case
  RSBool     -> Right BVBoolean
  RSNum      -> Right BVNumber
  RSEnum e   -> BVCategory <$> atomOf env e
  RSRecord r -> BVCategory <$> atomOf env r
  RSList _   -> Right BVList
  RSOpaque t | t `elem` (["DATE", "TIME", "DATETIME", "DURATION"] :: [Text]) ->
    Left [ blawxErr who rng
             (LEUnsupported "dates (Blawx v1)")
             ( "`" <> who <> "` involves the sort " <> t
                 <> "; date/time values are rejected in Blawx v1 — \
                   \specs/todo/DATE-LIBRARY-SPEC.md (R-D1/R-D4) records the \
                   \eventual convention (functor-wrapped integer POSIX \
                   \seconds, UTC midnight)" ) ]
  s ->
    Left [ blawxErr who rng
             (LEUnsupported "sort with no Blawx value type")
             ( "`" <> who <> "` involves the sort "
                 <> Text.textShow s <> ", which Blawx's ontology cannot declare" ) ]

-- | The @root_section@ declaration stack, in the order of
-- @p1-design/emit-plan.md@ §11: categories (records, then @ASSUME@d types, then
-- enums), field attributes, @ASSUME@d-input attributes, decision attributes,
-- relationships.
--
-- __The two kinds of 'RInput' are declared from different places, and that is
-- why the filter is a membership test rather than a kind test.__ A
-- field-derived input already has its block from 'fieldAttribute' (built from
-- the record, which is where the field's owning category is written down), so
-- putting it through 'classifyPred' as well would declare it twice. An
-- @ASSUME@-derived input has no field twin and nothing else to build a block
-- from, so it goes through the classifier like any other predicate — and gets
-- the /same/ 'attributeBlock', which is what makes an @ASSUME@d boolean and a
-- boolean field emit byte-identical @blawx_attribute@, @*_nlg@ and
-- @:- dynamic@ lines. An input predicate shares its field's 'Unique' when it
-- has one ('mangleAll'), so the test is exact.
declarations :: Env -> RelProgram -> Either [LowerError] [BBlock]
declarations env prog = do
  cats <- collectE $
    [ categoryBlock r.rrName r.rrProv | r <- prog.rpgRecords ]
      <> [ categoryBlock a.raName a.raProv | a <- prog.rpgAbstract ]
      <> [ categoryBlock e.reName e.reProv | e <- prog.rpgEnums ]
  fieldAttrs <- collectE
    [ fieldAttribute r f | r <- prog.rpgRecords, f <- r.rrFields ]
  classified <- collectE
    [ (p,) <$> classifyPred env p | p <- prog.rpgPreds, not (isFieldInput env p) ]
  let (inputCls, computedCls) = partition (\(p, _) -> p.rpKind == RInput) classified
  -- An input that 'classifyPred' cannot place has no Blawx image at all: no
  -- declaration block, no attribute selector, and no block in
  -- 'L4.Blawx.EmitXml' it could be stated with, which is the R12 blank-row loss
  -- the fixpoint harness fails on.
  --
  -- __The refused band is total arity ≤ 2 that is not attribute-shaped, and
  -- nothing else.__ Blawx hangs a declaration block off a subject, so at that
  -- end the ontology is category-centric: arity 0 (a bare proposition), a
  -- non-category arity 1, and every arity 2 other than @(category) -> value@
  -- land in 'PCUndeclared'. From total arity 3 up the input is declared as a
  -- /relationship/ instead, whose arguments 'valueType' types individually and
  -- does NOT require to be categories — so an @ASSUME@ over two @NUMBER@s
  -- returning a @NUMBER@ is accepted here. The condition is therefore a floor
  -- with a hole in it, not a blanket "first parameter must be a category"; the
  -- message below and BLAWX-EXPORT-SPEC §6.1 both say so explicitly, because an
  -- earlier wording of each claimed the blanket rule and contradicted the code.
  --
  -- Refused HERE and not in the middle end on purpose: `RInput/0` is a
  -- perfectly good relational predicate that a swipl or Logical English leg can
  -- emit, and narrowing the shared layer to fit one target's block palette is
  -- the inversion of #258 §2.5's division of labour.
  case [ blawxErr p.rpName.rnBase p.rpProv.rpvRange
           (LEUnsupported "input predicate with no category subject (Blawx)")
           ( "`" <> p.rpName.rnBase <> "` is an input of total arity "
               <> Text.textShow (length p.rpParams + maybe 0 (const 1) p.rpResult)
               <> ", which Blawx has no declaration block for. At total arity 2 \
                 \or below an input must be ATTRIBUTE-shaped — exactly one \
                 \parameter, category-sorted (an ASSUMEd TYPE, a record or an \
                 \enum), plus at most a result — because a fact is stated in \
                 \Blawx by hanging an attribute off its subject. Relationship \
                 \blocks, whose arguments need not be categories, start at \
                 \total arity 3" )
       | (p, PCUndeclared) <- inputCls
       ] of
    []   -> Right ()
    errs -> Left errs
  inputAttrs <- collectE
    [ predAttribute p cat vt
    | (p, cls) <- inputCls
    , Just (cat, vt) <- [attrOf cls]
    ]
  declAttrs <- collectE
    [ predAttribute p cat vt
    | (p, cls) <- computedCls
    , Just (cat, vt) <- [attrOf cls]
    ]
  rels <- collectE
    [ relationship p vts | (p, PCRelationship vts) <- classified ]
  pure (cats <> fieldAttrs <> inputAttrs <> declAttrs <> rels)
 where
  attrOf = \case
    PCAttrBool cat     -> Just (cat, BVBoolean)
    PCAttrValue cat vt -> Just (cat, vt)
    _                  -> Nothing
  categoryBlock rn prov = do
    n <- atomOf env rn
    pure $ BDeclareCategory MkBCategoryDecl
      { bcName    = n
      , bcPrefix  = ""
      , bcPostfix = isATxt (bNameText n)
      , bcProv    = Just (rn.rnUnique, prov.rpvRange)
      }
  fieldAttribute r f = do
    cat <- atomOf env r.rrName
    n   <- atomOf env f.rfName
    vt  <- valueTypeField f
    pure (attributeBlock cat n vt (f.rfName.rnUnique, Nothing))
  -- fields have no RPred to blame, so they name themselves
  valueTypeField f = blawxValueType env f.rfName.rnBase Nothing f.rfSort
  predAttribute p cat vt = do
    catAtom <- atomOf env cat
    n       <- atomOf env p.rpName
    pure (attributeBlock catAtom n vt (p.rpName.rnUnique, p.rpProv.rpvRange))
  attributeBlock cat n vt prov =
    BDeclareAttribute MkBAttributeDecl
      { baCategory = cat
      , baName     = n
      , baType     = vt
      , baOrder    = BOrderOV
      , baPrefix   = ""
      , baInfix    = case vt of
          BVBoolean -> ""   -- rendered @not_applicable@ by the emitter
          _         -> "has " <> prettyAtom (bNameText n) <> " of"
      , baPostfix  = case vt of
          BVBoolean -> prettyAtom (bNameText n)
          _         -> ""
      , baProv     = Just prov
      }
  relationship p vts = do
    n <- atomOf env p.rpName
    pure $ BDeclareRelationship MkBRelationshipDecl
      { brName     = n
      , brTypes    = vts
      , brPrefixes = "" : replicate (length vts - 1) "and"
      , brPostfix  = "are related as " <> prettyAtom (bNameText n)
      , brProv     = Just (p.rpName.rnUnique, p.rpProv.rpvRange)
      }

-- | Whether an 'RInput' predicate came from a stored record field (as opposed
-- to a top-level @ASSUME@). The join is the 'Unique': an input predicate built
-- from a field carries that field's identity, which is why it also carries the
-- field's atom ('mangleAll').
isFieldInput :: Env -> RPred -> Bool
isFieldInput env p = p.rpKind == RInput && Map.member p.rpName.rnUnique env.envFieldCat

prettyAtom :: Text -> Text
prettyAtom = Text.replace "_" " "

-- | See the title derivation in 'lowerBlawx': CLEAN requires an
-- uppercase-initial title, or the import view rejects the whole document.
--
-- CLEAN's title grammar also rejects an em\/en dash — measured against the
-- pinned clean-law inside the Blawx container (2026-08-19): a title @Act X — Y@
-- raises @ParseException: found '—'@ in @generate_akn@ during
-- @RuleDoc.save()@, making the import 500; @-@, commas, and parentheses all
-- parse, and body text tolerates em dashes fine. So the TITLE channel maps
-- em\/en dashes to an ASCII hyphen; the L4 source keeps its typography, and
-- @\@desc@\/section prose is untouched.
capitalizeFirst :: Text -> Text
capitalizeFirst t = case Text.uncons (dashSafe t) of
  Just (c, rest) -> Text.cons (toUpper c) rest
  Nothing        -> t
 where
  dashSafe = Text.replace "\x2014" "-" . Text.replace "\x2013" "-"

isATxt :: Text -> Text
isATxt atom =
  let p = prettyAtom atom
      article = case Text.uncons p of
        Just (c, _) | c `elem` ("aeiou" :: String) -> "is an "
        _                                          -> "is a "
  in  article <> p

-- | One membership fact per enum constructor: the enum type is a category and
-- its constructors are its (only) members.
enumConstructorFacts :: Env -> RelProgram -> [BBlock]
enumConstructorFacts env prog =
  [ BFact True catAtom [BTAtom consAtom]
  | e <- prog.rpgEnums
  , Just catAtom <- [Map.lookup e.reName.rnUnique env.envAtoms]
  , c <- e.reCons
  , Just consAtom <- [Map.lookup c.rnUnique env.envAtoms]
  ]

-- ---------------------------------------------------------------------------
-- Sections (R4)
-- ---------------------------------------------------------------------------

-- | Which numbered section each rule-bearing predicate belongs to: exported
-- decisions get sections 1..n in 'rpgPreds' order; a helper (auxiliary or
-- non-exported computed) is filed with the first exported decision that
-- transitively depends on it. benefit.l4's @bonus@ lands in @sec_2@ this way.
sectionAssignment :: RelProgram -> [RPred] -> Map Unique Int
sectionAssignment prog exported =
  foldl' claim base (zip [1 ..] exported)
 where
  base = Map.fromList [ (p.rpName.rnUnique, i) | (i, p) <- zip [1 ..] exported ]
  deps = Map.fromListWith (<>)
           [ (e.redFrom.rnUnique, [e.redTo.rnUnique]) | e <- prog.rpgDeps ]
  claim m (i, p) =
    foldl' (\mm u -> Map.insertWith (\_new old -> old) u i mm) m
           (reachable [p.rpName.rnUnique] Set.empty)
  reachable [] _ = []
  reachable (u : us) seen
    | u `Set.member` seen = reachable us seen
    | otherwise = u : reachable (Map.findWithDefault [] u deps <> us) (Set.insert u seen)

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

-- | Every clause of every rule-bearing predicate, grouped by section number,
-- in 'rpgPreds' \/ 'rpClauses' order within each section.
ruleBlocks :: Env -> RelProgram -> Map Unique Int -> Either [LowerError] (Map Int [BBlock])
ruleBlocks env prog secOf = do
  rules <- collectE
    [ fmap (sec,) (convertClause env p (bSec sec) cl)
    | p <- prog.rpgPreds
    , not (null p.rpClauses)
    , let sec = Map.findWithDefault 1 p.rpName.rnUnique secOf
    , cl <- p.rpClauses
    ]
  pure (Map.fromListWith (flip (<>)) [ (sec, [b]) | (sec, b) <- rules ])

-- | Per-clause conversion: name the variables, recover their sorts, prepend
-- the category guards, then map the goals. A clause with no conditions at
-- all lowers to a fact block rather than the generator's degenerate
-- @\") :- .\"@ rule — see the module header (stage-C decisions).
convertClause :: Env -> RPred -> BSectionRef -> RClause -> Either [LowerError] BBlock
convertClause env p sec cl = do
  headAtom <- atomOf env p.rpName
  let names = nameVars (concatMap termVars cl.rcHead <> concatMap goalVars cl.rcBody)
      sorts = varSorts env p cl
      cctx  = MkCCtx { ccFn = p.rpName.rnBase, ccNames = names, ccSorts = sorts }
  headTerms <- collectE (map (convertTerm env cctx) cl.rcHead)
  guards    <- categoryGuards env cctx p cl
  body      <- convertGoals env cctx cl.rcBody
  pure $ case guards <> body of
    [] -> BFact True headAtom headTerms
    conds -> BAttributedRule MkBRule
      { brSection    = sec
      , brConclusion = MkBConclusion { bcSign = True, bcPred = headAtom, bcArgs = headTerms }
      , brConditions = conds
      , brDefeasible = False
        -- Mode A has no applicability layer; see IR.brInapplicable
      , brInapplicable = False
      , brProvenance = Just (cl.rcProv.rpvUnique, cl.rcProv.rpvRange)
      }

data CCtx = MkCCtx
  { ccFn    :: !Text
  , ccNames :: !(Map Int Text)
  , ccSorts :: !(Map Int RSort)
  }

-- | @cat(X)@ for each record- or enum-sorted head parameter bound to a
-- variable, in parameter order.
categoryGuards :: Env -> CCtx -> RPred -> RClause -> Either [LowerError] [BGoal]
categoryGuards env cctx p cl = collectE
  [ (\cat -> BGCall True cat [BTVar (bvar cctx v)]) <$> atomOf env rn
  | (RTVar v, s) <- zip cl.rcHead p.rpParams
  , rn <- case s of
      RSRecord r -> [r]
      RSEnum r   -> [r]
      _          -> []
  ]

-- | The goal-by-goal classification table (@p1-design/emit-plan.md@ §4), with
-- the boolean-projection peephole's one-goal lookahead.
convertGoals :: Env -> CCtx -> [RGoal] -> Either [LowerError] [BGoal]
convertGoals env cctx = go
 where
  go [] = Right []
  go (RProj subj f v : rest)
    | Just RSBool <- Map.lookup f.rnUnique env.envFieldSort = case rest of
        (RUnify v' (RTBool b) : rest') | v' == v -> do
          fa <- atomOf env f
          s  <- convertTerm env cctx subj
          (BGCall b fa [s] :) <$> go rest'
        _ ->
          Left [ blawxErr cctx.ccFn Nothing
                   (LEUnsupported "boolean projection (Blawx)")
                   ( "a projection of boolean field `" <> f.rnBase
                       <> "` is not immediately consumed by a TRUE/FALSE test" ) ]
    | otherwise = do
        fa <- atomOf env f
        s  <- convertTerm env cctx subj
        (BGCall True fa [s, BTVar (bvar cctx v)] :) <$> go rest
  go (g : rest) = (<>) <$> one g <*> go rest
  one = \case
    RCall n args -> do
      a  <- atomOf env n
      ts <- collectE (map (convertTerm env cctx) args)
      pure [BGCall True a ts]
    RNotCall n args -> do
      a  <- atomOf env n
      ts <- collectE (map (convertTerm env cctx) args)
      -- R5: an input predicate's absence must fail loudly (classical -p);
      -- a computed/auxiliary decision is a total definition (NAF not p)
      pure $ case Map.lookup n.rnUnique env.envPredKind of
        Just RInput -> [BGCall False a ts]
        _           -> [BGNaf a ts]
    RProj _ f _ ->
      -- unreachable: 'go' consumes every RProj before delegating to 'one'
      Left [ blawxErr cctx.ccFn Nothing
               (LEUnsupported "internal: RProj reached the non-projection arm")
               ("projection of `" <> f.rnBase <> "` escaped the classifier's lookahead") ]
    RUnify v t -> case t of
      RTBool _ ->
        -- Reachable exactly when a bare BOOLEAN-typed variable (a plain
        -- BOOLEAN GIVEN parameter — a boolean *field* is consumed by the
        -- projection peephole above, and a boolean-returning call has no
        -- output argument) is tested for TRUE/FALSE. The rejection is
        -- fragment policy: a free-standing boolean has no Blawx term image.
        -- One error per DNF clause that tests the variable is deliberate —
        -- each is a real occurrence site.
        Left [ blawxErr cctx.ccFn Nothing
                 (LEUnsupported "bare BOOLEAN parameter (Blawx)")
                 ( "the BOOLEAN-valued variable `" <> bvarText (bvar cctx v)
                     <> "` has no Blawx image — only unary attributes carry \
                       \truth; model it as a boolean attribute of a category \
                       \(a record field) instead of a bare BOOLEAN parameter" ) ]
      _ -> do
        t' <- convertTerm env cctx t
        pure [BGUnify (BTVar (bvar cctx v)) t']
    RMatch v c -> do
      ca <- atomOf env c
      pure [BGUnify (BTVar (bvar cctx v)) (BTAtom ca)]
    RCmp op x y -> do
      x' <- convertTerm env cctx x
      y' <- convertTerm env cctx y
      let numeric = isNumeric cctx x || isNumeric cctx y
      case op of
        RLt  -> pure [BGCompare BLt  x' y']
        RLeq -> pure [BGCompare BLte x' y']
        RGt  -> pure [BGCompare BGt  x' y']
        RGeq -> pure [BGCompare BGte x' y']
        -- the explicit REq/RNeq dispatch: see the module header
        REq  | numeric -> pure [BGCompare BEq x' y']
        RNeq | numeric -> pure [BGCompare BNeq x' y']
        REq  -> [BGUnify x' y'] <$ recordIdentity env cctx "EQUALS" x y
        RNeq -> [BGDiseq x' y'] <$ recordIdentity env cctx "a disequality" x y
    REval v e -> do
      e' <- convertArith env cctx e
      pure [BGIs (bvar cctx v) e']
    RFindAll tmpl body out -> do
      -- Invariant: bodies reaching this arm are single-goal by construction —
      -- 'factorFindAlls' rewrote every multi-goal search into one call to a
      -- fresh auxiliary predicate before conversion began. The "," join in
      -- the emitter's BGFindall arm is totality, not fidelity (Emit.hs says
      -- the same).
      body' <- convertGoals env cctx body
      pure [BGFindall (bvar cctx tmpl) body' (bvar cctx out)]
    RAggregate op list out ->
      pure [BGAggregate (aggFn op) (bvar cctx list) (bvar cctx out)]
  aggFn = \case
    RSum     -> BSum
    RCount   -> BCount
    RMinimum -> BMin
    RMaximum -> BMax
    RAvg     -> BAverage

convertArith :: Env -> CCtx -> RArith -> Either [LowerError] BArith
convertArith env cctx = \case
  RANum q -> BANum <$> integral cctx.ccFn q
  RAVar v -> Right (BAVar (bvar cctx v))
  RANeg e -> BANeg <$> convertArith env cctx e
  RABin op l r -> case op of
    RMod ->
      Left [ blawxErr cctx.ccFn Nothing
               (LEUnsupported "modulo (Blawx)")
               "Blawx's calculation block has + - * / only; MOD has no image" ]
    _ -> BABin (arithOp op) <$> convertArith env cctx l <*> convertArith env cctx r
 where
  arithOp = \case
    RAdd -> BAdd
    RSub -> BSub
    RMul -> BMul
    RDiv -> BDiv
    RMod -> BDiv  -- unreachable: RMod rejected above

-- | Non-integral literals are rejected while the R7 measurement gate holds
-- (see BLAWX-EXPORT-SPEC §8.8; the measurement is re-run as part of P1).
integral :: Text -> Rational -> Either [LowerError] Rational
integral fn q
  | isIntegralRational q = Right q
  | otherwise =
      Left [ blawxErr fn Nothing
               (LEUnsupported "non-integral numeric literal (R7 gate)")
               "represent money as cents-as-integers, or wait for the R7 ruling" ]

isIntegralRational :: Rational -> Bool
isIntegralRational q = q == fromInteger (round q :: Integer)

convertTerm :: Env -> CCtx -> RTerm -> Either [LowerError] BTerm
convertTerm env cctx = \case
  RTVar v    -> Right (BTVar (bvar cctx v))
  RTNum q    -> BTNum <$> integral cctx.ccFn q
  RTAtom c   -> BTAtom <$> atomOf env c
  RTStr s    -> BTAtom <$> stringAtom env cctx.ccFn s
  RTBool _   ->
    Left [ blawxErr cctx.ccFn Nothing
             (LEUnsupported "boolean in term position (Blawx)")
             "a boolean value has no Blawx term image; only unary attributes carry truth" ]
  RTNil      -> Right BTNil
  RTCons h t -> BTCons <$> convertTerm env cctx h <*> convertTerm env cctx t

-- | A string literal becomes an atom in the one global namespace; a mangled
-- string that lands on a /declared/ atom would silently conflate two
-- identities, so it is rejected rather than renamed (a string is quoted
-- verbatim in the source — renaming it would change which facts it matches).
stringAtom :: Env -> Text -> Text -> Either [LowerError] BName
stringAtom env fn s =
  let atomT = blawxAtom s
  in case mkBName Nothing atomT of
       Just bn | not (atomT `Set.member` env.envAtomTexts) -> Right bn
       _ ->
         Left [ blawxErr fn Nothing
                  (LEUnsupported "string literal (Blawx)")
                  ( "the string literal \"" <> s
                      <> "\" cannot become a fresh Blawx atom (invalid or collides \
                         \with a declared name)" ) ]

-- ---------------------------------------------------------------------------
-- Variables: naming and sorts
-- ---------------------------------------------------------------------------

bvar :: CCtx -> RVar -> BVar
bvar cctx v =
  MkBVar (Map.findWithDefault ("V" <> Text.textShow v.rvId) v.rvId cctx.ccNames)

bvarText :: BVar -> Text
bvarText (MkBVar t) = t

-- | First-appearance naming from the middle-end's rendering hints, uniquified
-- within the clause by a numeric suffix (@Years@, @Years2@, …). A trailing
-- digit is safe on a /variable/ — the @_\d+@ trap is the atom validator's.
nameVars :: [RVar] -> Map Int Text
nameVars = go Map.empty Set.empty
 where
  go named _ [] = named
  go named used (v : vs)
    | Map.member v.rvId named = go named used vs
    | otherwise =
        let base = varBase v.rvHint
            nm | base `Set.member` used = bump (2 :: Int) base
               | otherwise              = base
        in  go (Map.insert v.rvId nm named) (Set.insert nm used) vs
    where
      bump i base
        | cand `Set.member` used = bump (i + 1) base
        | otherwise              = cand
        where cand = base <> Text.textShow i

varBase :: Text -> Text
varBase h =
  let cleaned = Text.filter (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c == '_') h
      alpha   = Text.dropWhile (\c -> not (isAsciiLower c || isAsciiUpper c)) cleaned
  in  case Text.uncons alpha of
        Just (c, rest) -> Text.cons (toUpper c) rest
        Nothing        -> "V"

termVars :: RTerm -> [RVar]
termVars = \case
  RTVar v    -> [v]
  RTCons h t -> termVars h <> termVars t
  _          -> []

goalVars :: RGoal -> [RVar]
goalVars = \case
  RCall _ ts          -> concatMap termVars ts
  RNotCall _ ts       -> concatMap termVars ts
  RProj s _ v         -> termVars s <> [v]
  RUnify v t          -> v : termVars t
  RMatch v _          -> [v]
  RCmp _ x y          -> termVars x <> termVars y
  REval v e           -> v : arithVars e
  RFindAll t body out -> t : concatMap goalVars body <> [out]
  RAggregate _ l out  -> [l, out]
 where
  arithVars = \case
    RANum _     -> []
    RAVar v     -> [v]
    RANeg e     -> arithVars e
    RABin _ l r -> arithVars l <> arithVars r

-- | The one linear sort-recovery pass the shared IR's haddock prescribes.
-- Only completeness enough for the @REq@ dispatch and guards is needed; an
-- unknown sort simply reads as non-numeric.
varSorts :: Env -> RPred -> RClause -> Map Int RSort
varSorts env p cl = foldl' goalSort headSorts cl.rcBody
 where
  headSorts = foldl' headTerm Map.empty
    (zip cl.rcHead (p.rpParams <> maybeToList p.rpResult))
  headTerm m (t, s) = case (t, s) of
    (RTVar v, _)               -> Map.insert v.rvId s m
    (RTCons h rest, RSList el) -> headTerm (headTerm m (h, el)) (rest, RSList el)
    _                          -> m
  goalSort m = \case
    RProj _ f v ->
      maybe m (\s -> Map.insert v.rvId s m) (Map.lookup f.rnUnique env.envFieldSort)
    RCall n args
      | Just (Just res) <- Map.lookup n.rnUnique env.envPredResult
      , (RTVar v : _) <- reverse args
        -> Map.insert v.rvId res m
      | otherwise -> m
    RNotCall {} -> m
    RUnify v t -> case t of
      RTNum _ -> Map.insert v.rvId RSNum m
      _       -> m
    RMatch {} -> m
    RCmp {} -> m
    REval v _ -> Map.insert v.rvId RSNum m
    RFindAll tmpl body out ->
      let m' = foldl' goalSort m body
      in  Map.insert out.rvId
            (RSList (Map.findWithDefault (RSOpaque "findall template") tmpl.rvId m')) m'
    RAggregate _ _ out -> Map.insert out.rvId RSNum m

isNumeric :: CCtx -> RTerm -> Bool
isNumeric cctx = \case
  RTNum _ -> True
  RTVar v -> Map.lookup v.rvId cctx.ccSorts == Just RSNum
  _       -> False

-- | The declared record a term's recovered sort __contains__, paired with that
-- sort, if it contains one. Everything record-shaped is a variable by the time
-- it reaches here (the middle-end is in ANF: a record-typed @GIVEN@ parameter,
-- the target of an 'RProj' over an object-valued field, and the result of a
-- record-returning 'RCall' are all variables carrying their sort out of
-- 'varSorts').
--
-- __The search descends 'RSList' and 'RSMaybe'__, because a container of
-- records diverges exactly as a bare record does: L4 compares the container
-- element-wise by value, Blawx unifies it element-wise by atom, and the
-- occurrence-keyed flattening gives the elements different atoms. Measured
-- 2026-09-02: before the descent, a @LIST OF Player@ field compared with
-- @EQUALS@ lowered clean and emitted @Members = Members2@ (§11 W1). @RSList@ of
-- @RSMaybe@ of a record is reachable — 'blawxValueType' types any @RSList@ as
-- @BVList@ without looking inside — which is what
-- @jl4\/examples\/blawx\/not-ok\/record-identity-list.l4@ exercises; a bare
-- @MAYBE@ record is refused earlier, by that same ontology check.
--
-- __An @ASSUME T IS A TYPE@ is deliberately not a record here.__ 'RSRecord'
-- carries both a @DECLARE … HAS@ record and an abstract category, and
-- "L4.Relational.IR" says a consumer that needs to tell them apart looks the
-- name up among the declared records — which is what 'envDeclRecords' is. The
-- distinction matters because an abstract category has no fields for L4 to
-- compare structurally: its values are atoms on both sides, @=@ on atoms is the
-- faithful image, and refusing it would delete an emission that works and
-- recommend an edit (compare a FIELD) that has nothing to name.
recordInSort :: Env -> CCtx -> RTerm -> Maybe (RName, RSort)
recordInSort env cctx = \case
  RTVar v -> do
    s <- Map.lookup v.rvId cctx.ccSorts
    fmap (\r -> (r, s)) (peel s)
  _ -> Nothing
 where
  peel = \case
    RSRecord r | Set.member r.rnUnique env.envDeclRecords -> Just r
    RSList s  -> peel s
    RSMaybe s -> peel s
    _         -> Nothing

-- | An 'RSort' in the surface language's spelling, for a diagnostic. Names are
-- 'rnBase' — this is the message a reader of the @.l4@ sees, not the debug dump
-- ("L4.Relational.Debug".@renderSort@ renders the same shapes against a
-- 'DisplayNames' map instead).
sortText :: RSort -> Text
sortText = \case
  RSBool     -> "BOOLEAN"
  RSNum      -> "NUMBER"
  RSString   -> "STRING"
  RSEnum n   -> n.rnBase
  RSRecord n -> n.rnBase
  RSList s   -> "LIST OF " <> sortText s
  RSMaybe s  -> "MAYBE " <> sortText s
  RSOpaque t -> t

-- | __Record identity does not survive the flattening__ (BLAWX-EXPORT-SPEC
-- §11 W1, measured 2026-09-02). L4 compares records __by value__; Blawx
-- compares objects __by atom__; and R11's query flattening emits one object per
-- /occurrence/ of a record value, so two structurally equal records reach
-- s(CASP) as two distinct atoms and the comparison answers differently — the
-- §3.2.1 failure class, source that parses, type-checks and means something
-- else. It was silent until this refusal: the first Rock Paper Scissors
-- encoding lowered clean, L4 said @TRUE@ and the tier-1 harness said no model
-- (@jl4\/examples\/blawx\/not-ok\/record-identity.l4@ is that encoding, kept).
--
-- __What is refused is exactly this__: an 'REq' or 'RNeq' either of whose
-- operands is a variable whose recovered sort /contains/ a declared record sort
-- — directly, or under any nesting of @LIST OF@ and @MAYBE@ ('recordInSort').
-- Nothing else. An @ASSUME@d abstract category is not refused (see
-- 'recordInSort'), and a record-sorted operand whose sort did not survive into
-- 'varSorts' — an 'RSOpaque', say — is not detected at all, because there is
-- nothing left in the sort to detect. No such case is known to be reachable in
-- the M1 fragment; none was constructed.
--
-- Refusing is a v1 measure, not the fix. The fix is to hash-cons
-- structurally-equal record arguments in 'skolemise' so one distinct value
-- becomes one object, after which this check lifts; §11 W1 records it as the
-- next step. Until then the diagnostic must name a reachable edit, so it names
-- both: state the rule once per slot (which needs no identity — that is what
-- the shipped @rps.l4@ does), or compare a field whose sort /is/ an atom.
recordIdentity :: Env -> CCtx -> Text -> RTerm -> RTerm -> Either [LowerError] ()
recordIdentity env cctx opName x y =
  case recordInSort env cctx x <|> recordInSort env cctx y of
    Nothing         -> Right ()
    Just (cat, srt) ->
      Left [ blawxErr cctx.ccFn Nothing
               (LEUnsupported "record identity (Blawx)")
               ( opName <> " on operands of " <> operand cat srt
                   <> " has no faithful Blawx image: L4 compares records by \
                      \value, Blawx compares objects by atom, and the query \
                      \flattening (R11) emits one object per occurrence of a \
                      \record value — so two structurally equal `" <> cat.rnBase
                   <> "` records arrive as two distinct atoms and the comparison \
                      \silently answers differently. State the rule once per slot \
                      \so no identity is needed (see jl4/examples/blawx/rps.l4), \
                      \or compare an enum- or number-valued FIELD of the two \
                      \records instead of the records themselves" ) ]
 where
  -- The bare case keeps its original wording; a container says what it is and
  -- then names the record inside it, because "of record type `Player`" would be
  -- a false description of a `LIST OF Player` operand.
  operand cat = \case
    RSRecord _ -> "record type `" <> cat.rnBase <> "`"
    s -> "type `" <> sortText s <> "`, which contains the record type `"
           <> cat.rnBase <> "`,"

-- ---------------------------------------------------------------------------
-- Queries → tests (R11)
-- ---------------------------------------------------------------------------

-- | One 'BTest' per @#EVAL@\/@#ASSERT@: category facts, the flattened input
-- facts (booleans as signed unary facts, never @fact_scenario@), the
-- @#ASSERT@ constraint, then the query as the last block of its own stack.
convertQuery :: Env -> RQuery -> Either [LowerError] BTest
convertQuery env q = do
  goalAtom <- atomOf env q.rqGoal
  skolems  <- skolemise env q
  let fctx = MkFCtx { fcFn = "#" <> q.rqId, fcSkolems = skolems }
  catFacts <- collectE
    [ (\cat -> BFact True cat [BTAtom sk]) <$> atomOf env catName
    | (_, (sk, catName)) <- skolems
    ]
  facts    <- collectE (map (convertFact env fctx) q.rqFacts)
  args     <- collectE (map (convertFactTerm env fctx) q.rqArgs)
  let outVar = [ MkBVar (varBase v.rvHint) | v <- maybeToList q.rqOut ]
      queryArgs = args <> map BTVar outVar
  constraint <- case (q.rqKind, q.rqExpected) of
    (RQAssert, Just expected) -> do
      -- runtime-checked on the Blawx side too: the constraint forbids models
      -- where the asserted goal fails (NAF is right regardless of kind here —
      -- the goal is a computed decision, never an input)
      expectedTs <- case (q.rqOut, expected) of
        (Just _, t)            -> (: []) <$> convertFactTerm env fctx t
        (Nothing, RTBool True) -> pure []
        (Nothing, t)           ->
          Left [ blawxErr fctx.fcFn q.rqProv.rpvRange
                   (LEUnsupported "#ASSERT shape (Blawx)")
                   ( "a boolean #ASSERT can only expect TRUE; got "
                       <> Text.textShow t ) ]
      pure [BConstraint [BGNaf goalAtom (args <> expectedTs)]]
    _ -> pure []
  pure MkBTest
    { btName   = slugify q.rqId
    , btStacks = [ catFacts <> facts <> constraint
                 , [BQuery [BGCall True goalAtom queryArgs]]
                 ]
    , btComment = Nothing
    , btProv   = Just (q.rqProv.rpvUnique, q.rqProv.rpvRange)
    }

-- | R11 as ruled ("as proposed"): __one @#abducible@ interview test per
-- module__ — the module's input predicates (and their owning categories)
-- declared abducible, then the first exported decision queried over free
-- variables. This is what powers Blawx's hypothetical reasoning and
-- "Relevant Statements" (spec §4.10); the shipped witness for the byte shape
-- is @numerical_constraints.yaml@'s test (@#abducible person(Person).@ /
-- @#abducible age(Person,Age).@ / @?- is_sucker(Person).@ — one block per
-- stack). Decisions made here, so nobody re-derives them:
--
-- * emitted only when the module has at least one 'RInput' predicate: with
--   nothing to abduce the query would run the decision over wholly unbound
--   arguments, which for a recursive module (sumlist) is an unbounded
--   search, not an interview. __This is a ruling, not a deferral.__ P1 left
--   it open whether a module with no /record/ inputs could get an interview;
--   the @ASSUME@ widening answers half of it — an @ASSUME@-style module has
--   no @DECLARE@ at all and still gets one, because 'RInput' no longer
--   implies \"stored field\" — and closes the other half: @sumlist@ has
--   neither kind of input (its parameters are @LIST OF NUMBER@), so it gets
--   no interview permanently. The gate is \"has an abducible input\", and a
--   list-recursive module has none in either source;
-- * variable naming follows the declaration blocks' convention (@X@ /
--   @X,Y@; @A@… above arity 2) — each directive's variables scope to
--   itself, so sharing letters is cosmetic and matches the shipped example;
-- * the query subject is the FIRST exported decision (document order): the
--   spec says one test per module and does not rank decisions, and first-in-
--   file is the module's headline decision by the R4 section convention;
-- * the test is named @interview@ and rides last, after the per-directive
--   tests; the tier-1 harness skips it when pairing tests with oracles (it
--   has no L4 oracle — abduction is not evaluation).
interviewTest :: Env -> RelProgram -> [RPred] -> Either [LowerError] (Maybe BTest)
interviewTest env prog exported = case (inputs, exported) of
  ([], _)         -> Right Nothing
  (_, [])         -> Right Nothing  -- unreachable: lowerBlawx rejects no-export
  (_, first0 : _) -> do
    catAbds <- collectE
      [ (\a -> BAbducible a [BTVar (MkBVar "X")]) <$> atomOf env cat
      | cat <- cats
      ]
    inpAbds <- collectE
      [ (\a -> BAbducible a (map (BTVar . MkBVar) (declVars (inputArity p))))
          <$> atomOf env p.rpName
      | p <- inputs
      ]
    qAtom <- atomOf env first0.rpName
    let qArity = length first0.rpParams + maybe 0 (const 1) first0.rpResult
        query  = BQuery [BGCall True qAtom (map (BTVar . MkBVar) (declVars qArity))]
    pure $ Just MkBTest
      { btName   = "interview"
      , btStacks = [ [b] | b <- catAbds <> inpAbds ] <> [[query]]
      , btComment = Nothing
      , btProv   = Nothing
      }
 where
  inputs = [ p | p <- prog.rpgPreds, p.rpKind == RInput ]
  -- The subject's category, read off the predicate's OWN signature rather than
  -- from the field table, because an ASSUME-derived input has no field to look
  -- up. Byte-identical on a field-derived input: 'inputPreds' builds its
  -- rpParams as @[RSRecord \<owning record\>]@, from the same walk that fills
  -- @envFieldCat@.
  cats = nubOrdOn (.rnUnique)
    [ cat
    | p <- inputs
    , (s : _) <- [p.rpParams]
    , Just cat <- [categoryOf s]
    ]
  -- Its arity, likewise from the signature — and equal to the arity of the
  -- declaration block, which is the shape the abducible has to match. A boolean
  -- attribute is unary (truth rides the sign): a stored BOOLEAN field spells
  -- that as @rpResult = Just RSBool@ and an ASSUMEd boolean as
  -- @rpResult = Nothing@ (the output argument is dropped), and both land on 1.
  inputArity p =
    length p.rpParams + case p.rpResult of
      Just RSBool -> 0
      Just _      -> 1
      Nothing     -> 0
  declVars n
    | n <= 2    = take n ["X", "Y"]
    | otherwise = take n ["A","B","C","D","E","F","G","H","I","J"]

-- | Test names are Django's @(ruledoc, slug)@ URL identity: a duplicate is
-- unreachable or ambiguous after import, so — mirroring the atom-collision
-- discipline — duplicates are rejected by name rather than uniquified
-- silently.
checkTestNames :: [BTest] -> Either [LowerError] ()
checkTestNames tests =
  case [ n | (n : _ : _) <- group (sort [ t.btName | t <- tests ]) ] of
    [] -> Right ()
    dups ->
      Left
        [ blawxErr "" Nothing
            (LEUnsupported "test name collision (Blawx)")
            ( "distinct test directives slugify to the same Blawx test name(s) "
                <> Text.intercalate ", " [ "`" <> d <> "`" | d <- dups ]
                <> " — Django resolves tests by (ruledoc, slug), so a duplicate \
                  \is unreachable after import; rename the directive(s)" )
        ]

data FCtx = MkFCtx
  { fcFn      :: !Text
  , fcSkolems :: ![(Int, (BName, RName))]   -- ^ rvId → (constant, category)
  }

-- | Ground every subject variable: first letter of the category atom plus a
-- per-letter, per-query ordinal, bumped past any declared atom.
skolemise :: Env -> RQuery -> Either [LowerError] [(Int, (BName, RName))]
skolemise env q = go [] Map.empty subjects
 where
  -- every variable anywhere in the query, in first-appearance order
  vars = nubOrdOn (.rvId)
    (concatMap termVars q.rqArgs <> concatMap (concatMap termVars . (.rfaArgs)) q.rqFacts)
  subjects = vars
  categoryFor v =
    listToMaybe
      [ catName
      | f <- q.rqFacts
      , (RTVar v' : _) <- [f.rfaArgs]
      , v'.rvId == v.rvId
      , Just catName <- [Map.lookup f.rfaPred.rnUnique env.envFieldCat]
      ]
  go acc _ [] = Right (reverse acc)
  go acc counters (v : vs) = case categoryFor v of
    Nothing ->
      Left [ blawxErr ("#" <> q.rqId) q.rqProv.rpvRange
               (LEUnsupported "query subject of unknown category (Blawx)")
               ( "the query variable `" <> v.rvHint
                   <> "` has no input facts naming a declared record field, so its \
                     \category (and skolem constant) cannot be recovered" ) ]
    Just catName -> do
      catAtom <- atomOf env catName
      let initial = Text.take 1 (bNameText catAtom)
          taken t = t `Set.member` env.envAtomTexts
                      || t `Map.member` env.envStringAtoms
                      || t `elem` [ bNameText sk | (_, (sk, _)) <- acc ]
          next :: Int -> (Int, Text)
          next i =
            let cand = initial <> Text.textShow i
            in  if taken cand then next (i + 1) else (i, cand)
          (used, skText) = next (1 + Map.findWithDefault 0 initial counters)
      case mkBName Nothing skText of
        Nothing ->
          Left [ blawxErr ("#" <> q.rqId) q.rqProv.rpvRange
                   (LEUnsupported "skolem naming (Blawx)")
                   ("could not mint a skolem constant `" <> skText <> "`") ]
        Just sk ->
          go ((v.rvId, (sk, catName)) : acc) (Map.insert initial used counters) vs

convertFact :: Env -> FCtx -> RFact -> Either [LowerError] BBlock
convertFact env fctx f = do
  a <- atomOf env f.rfaPred
  case (Map.lookup f.rfaPred.rnUnique env.envFieldSort, f.rfaArgs) of
    -- a boolean field's fact is the signed unary assertion (R5's loud-absence
    -- side: FALSE is stated classically, not left to fail)
    (Just RSBool, [subj, RTBool b]) -> do
      s <- convertFactTerm env fctx subj
      pure (BFact b a [s])
    _ -> do
      ts <- collectE (map (convertFactTerm env fctx) f.rfaArgs)
      pure (BFact True a ts)

convertFactTerm :: Env -> FCtx -> RTerm -> Either [LowerError] BTerm
convertFactTerm env fctx = \case
  RTVar v -> case lookup v.rvId fctx.fcSkolems of
    Just (sk, _) -> Right (BTAtom sk)
    Nothing ->
      Left [ blawxErr fctx.fcFn Nothing
               (LEUnsupported "unskolemised query variable (Blawx)")
               ("variable `" <> v.rvHint <> "` reached fact emission unskolemised") ]
  RTNum q    -> BTNum <$> integral fctx.fcFn q
  RTAtom c   -> BTAtom <$> atomOf env c
  RTStr s    -> BTAtom <$> stringAtom env fctx.fcFn s
  RTBool _   ->
    Left [ blawxErr fctx.fcFn Nothing
             (LEUnsupported "boolean in term position (Blawx)")
             "a boolean fact value must ride its field's sign, not a term" ]
  RTNil      -> Right BTNil
  RTCons h t -> BTCons <$> convertFactTerm env fctx h <*> convertFactTerm env fctx t

-- | Django test-name slug: @[-a-zA-Z0-9_]+@.
slugify :: Text -> Text
slugify t =
  let kept = Text.filter (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c == '_' || c == '-') t
  in  if Text.null kept then "test" else kept

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

blawxErr :: Text -> Maybe SrcRange -> LowerErrorKind -> Text -> LowerError
blawxErr fn rng kind msg =
  MkLowerError { errFn = fn, errRange = rng, errKind = kind, errMsg = msg }

-- | Validation-style accumulation: every 'Left' contributes its errors.
collectE :: [Either [LowerError] a] -> Either [LowerError] [a]
collectE es = case concat [ e | Left e <- es ] of
  []   -> Right [ a | Right a <- es ]
  errs -> Left errs
