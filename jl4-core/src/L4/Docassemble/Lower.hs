-- | Lower a typechecked L4 module to the docassemble 'DAPackage' IR.
--
-- v1 scope (DOCASSEMBLE-EXPORT-SPEC.md §6): @\@export@-annotated
-- @DECIDE@/@MEANS@ whose parameters are records of primitives (BOOLEAN,
-- NUMBER, STRING, DATE, nullary-constructor enums, nested records) and bare
-- primitives; bodies drawn from the constitutive expression layer. Survival
-- rules:
--
--   * R2 — a record-typed parameter becomes an @objects:@ @DAObject@ instance
--     and /one question per stored field/, so docassemble's backchaining only
--     ever asks the fields the goal's evaluation demands. Labels carry the L4
--     field name verbatim. Sanitised field names are kept out of the
--     @DAObject@ class namespace ('attrIdent'): an attribute that shadows a
--     DAObject method is never sought, and the bound method rides into the
--     expression as a truthy value — a silent wrong verdict.
--   * R3 — every zero-@GIVEN@ @WHERE@ binding and every reachable top-level
--     @DECIDE@ becomes one named @code:@ block, so the L4 structure survives
--     at runtime. Function-valued bindings that are directly applied are
--     beta-reduced at lower time (v1 emits no Python module); un-inlinable
--     higher-order uses are refused by name.
--   * R4 — an exported boolean decision whose body is a top-level
--     @IMPLIES@ is split into scope + requirement variables and a scope-first
--     driver; the classical @not scope or requirement@ is never emitted as
--     the goal. /Nested/ implications read classically.
--
-- Deontic, ledger and IO constructs are refused with a named diagnostic and a
-- 'FidelityNote' ('Blocking'); Rational→float, @TYPICALLY@ prefills and
-- @MAYBE STRING@ erasure are declared 'Advisory' (spec §5).
module L4.Docassemble.Lower
  ( lowerModule
  , LowerError (..)
  , renderLowerError
  ) where

import Base
import Control.Applicative ((<|>))
import Data.Char (isAlphaNum, isDigit, toLower)
import Data.Either (partitionEithers)
import qualified Data.Map.Strict as Map
import Data.Monoid (Any (..))
import qualified Data.Set as Set
import qualified Data.Text as Text

import Optics ((^.), cosmosOf, foldMapOf, gplate)

import L4.Annotation (getAnno)
import L4.Docassemble.IR
import L4.Export
  ( DescFlags (..), ExportedFunction (..), ParsedDesc (..), TypeDescMap
  , buildTypeDescMap, getExportedFunctions, isExportedDecide, parseDescText )
import L4.Interchange.Fidelity
  (FidelityNote (..), FidelityReport (..), FidelitySeverity (..))
import L4.Syntax
import L4.TypeCheck.Environment
  (booleanUnique, dateUnique, justUnique, maybeUnique, nothingUnique, numberUnique, stringUnique)

-- | A reason a module (or one of its decisions) could not be compiled.
data LowerError = MkLowerError
  { errFn  :: !Text  -- ^ the offending decision (empty = module-level)
  , errMsg :: !Text
  }
  deriving stock (Eq, Show)

renderLowerError :: LowerError -> Text
renderLowerError e
  | Text.null e.errFn = e.errMsg
  | otherwise         = "in `" <> e.errFn <> "`: " <> e.errMsg

-- | An internal lowering failure. 'LFBlocked' marks constructs the target has
-- no form for at all (deontic, ledger, IO): at the boundary of a /non-default/
-- export it becomes a 'Blocking' 'FidelityNote' and the export is skipped;
-- anywhere else (helpers, the default export) it hardens into a 'LowerError',
-- because a skipped definition that something surviving depends on would leave
-- a variable no block defines — a silently broken interview.
data LF
  = LFFatal !Text
  | LFBlocked !Text !Text !Text  -- ^ note code, message, what is lost
  deriving stock (Eq, Show)

lfMessage :: LF -> Text
lfMessage = \case
  LFFatal m       -> m
  LFBlocked _ m _ -> m

-- ---------------------------------------------------------------------------
-- Module context (scanned once)
-- ---------------------------------------------------------------------------

data EnumInfo = MkEnumInfo
  { eiName :: !Text
  , eiCons :: ![(Text, Int)]  -- ^ (constructor L4 name, payload arity)
  }

data ConInfo = MkConInfo
  { ciName  :: !Text
  , ciArity :: !Int
  }

-- | A /stored/ record field. Computed (@MEANS@) fields never appear here:
-- 'L4.Desugar.desugarComputedFields' strips them out of the @RecordDecl@
-- before type checking and synthesizes a top-level selector @DECIDE@
-- (@f _self MEANS …@) per field, so in a @Module Resolved@ every remaining
-- field is stored. Projections onto computed fields reach the selector via
-- 'lowerProj''s 'envFuns' fallback and are inlined.
data FieldSpec = MkFieldSpec
  { fsU        :: !Unique
  , fsL4       :: !Text
  , fsSan      :: !Text
  , fsTy       :: !(Type' Resolved)
  , fsDesc     :: !(Maybe Text)
  , fsDefault  :: !(Maybe (Expr Resolved))
  }

data RecordSpec = MkRecordSpec
  { rsName   :: !Text
  , rsFields :: ![FieldSpec]
  }

-- | The two annotations M2 carries off a definition site.
--
-- 'defRef' is the definition's @\@ref@ citation with L4's own syntax removed;
-- 'defDesc' is its @\@desc@ gloss, and only a /plain/ one — the @\@export@ form
-- rides in the same slot ('L4.Export.parseDescText' consumes the keyword) and
-- is the interview's own title prose, not a definition of a term.
data DefAnns = MkDefAnns
  { defRef  :: !(Maybe Text)
  , defDesc :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

data TopDecide = MkTopDecide
  { tdU        :: !Unique
  , tdL4       :: !Text
  , tdSan      :: !Text
  , tdParams   :: ![Resolved]
  , tdBody     :: !(Expr Resolved)
  , tdExported :: !Bool
  , tdAnns     :: !DefAnns
  }

data Ctx = MkCtx
  { ctxEnums    :: !(Map Unique EnumInfo)          -- ^ keyed by enum /type/ unique
  , ctxEnumCons :: !(Map Unique ConInfo)           -- ^ keyed by constructor unique
  , ctxRecords  :: !(Map Unique RecordSpec)        -- ^ keyed by record /type/ unique
  , ctxTop      :: ![TopDecide]                    -- ^ declaration order
  , ctxTopByU   :: !(Map Unique TopDecide)
  , ctxAssumes  :: !(Map Unique (Assume Resolved))
  , ctxTypeDesc :: !TypeDescMap
  , ctxGloss    :: ![(Text, Text)]                 -- ^ the @auto terms:@ glossary (M2)
  , ctxGlossOut :: ![GlossDrop]                    -- ^ glossary entries docassemble cannot carry
  }

buildCtx :: Module Resolved -> Ctx
buildCtx mod' =
  let (enums, enumCons) = collectEnums mod'
      tops = collectTopDecides mod'
      (gloss, glossOut) = collectGlossary mod'
  in MkCtx
       { ctxEnums    = enums
       , ctxEnumCons = enumCons
       , ctxRecords  = collectRecords mod'
       , ctxTop      = tops
       , ctxTopByU   = Map.fromList [ (td.tdU, td) | td <- tops ]
       , ctxAssumes  = collectAssumes mod'
       , ctxTypeDesc = buildTypeDescMap mod'
       , ctxGloss    = gloss
       , ctxGlossOut = glossOut
       }

collectEnums :: Module Resolved -> (Map Unique EnumInfo, Map Unique ConInfo)
collectEnums (MkModule _ _ section) =
  ( Map.fromList [ (u, ei) | (u, ei, _) <- defs ]
  , Map.fromList (concat [ cs | (_, _, cs) <- defs ])
  )
 where
  defs = goSection section
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Declare _ (MkDeclare _ _ (MkAppForm _ tyRes _ _) (EnumDecl _ conDecls)) ->
      let members = [ (resolvedToText c, length cargs) | MkConDecl _ c cargs <- conDecls ]
          cons    = [ (getUnique c, MkConInfo (resolvedToText c) (length cargs))
                    | MkConDecl _ c cargs <- conDecls ]
      in [(getUnique tyRes, MkEnumInfo (resolvedToText tyRes) members, cons)]
    Section _ sub -> goSection sub
    _ -> []

collectRecords :: Module Resolved -> Map Unique RecordSpec
collectRecords (MkModule _ _ section) = Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Declare _ (MkDeclare _ _ (MkAppForm _ recRes _ _) (RecordDecl _ _ fields)) ->
      [ ( getUnique recRes
        , MkRecordSpec
            { rsName   = resolvedToText recRes
            , rsFields =
                [ MkFieldSpec
                    { fsU        = getUnique fRes
                    , fsL4       = resolvedToText fRes
                    , fsSan      = attrIdent (resolvedToText fRes)
                    , fsTy       = fTy
                    , fsDesc     = getDesc <$> (fAnn ^. annDesc)
                    , fsDefault  = mDflt
                    }
                -- the 5th MkTypedName field (computed/MEANS) is always
                -- Nothing post-desugar; see the FieldSpec haddock
                | MkTypedName fAnn fRes fTy mDflt _ <- fields
                ]
            }
        )
      ]
    Section _ sub -> goSection sub
    _ -> []

collectTopDecides :: Module Resolved -> [TopDecide]
collectTopDecides (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Decide topAnn d ->
      let (ps, b) = decideFunShape d
          nm      = resolvedToText (decideName d)
      in [ MkTopDecide
             { tdU        = getUnique (decideName d)
             , tdL4       = nm
             , tdSan      = pyIdent nm
             , tdParams   = ps
             , tdBody     = b
             , tdExported = isExportedDecide d
             , tdAnns     = decideAnns topAnn d
             } ]
    Section _ sub -> goSection sub
    _ -> []

-- ---------------------------------------------------------------------------
-- @\@ref@ citations and the @\@desc@ glossary (M2)
-- ---------------------------------------------------------------------------

-- | Read a definition's citation and gloss.
--
-- A @\@ref@ written above a top-level definition attaches to the /TopDecl/
-- node (@Decide ann d@), and one written above a @WHERE@ binding attaches to
-- the @LocalDecide ann d@ node — not to the inner @MkDecide@ — so both annos
-- are consulted, outer first, exactly as the DMN lowerer does. A node's anno
-- can hold at most one ref and the nearest preceding one wins, every other
-- becoming a @RefNotAttached@ warning (@attachRef@,
-- @ResolveAnnotation.hs:1162-1172@) — which is why each definition is read from
-- its /own/ node and never from a neighbour's.
--
-- The gloss is read from the inner @MkDecide@, where 'attachLeadingDesc' puts
-- it.
decideAnns :: Anno -> Decide Resolved -> DefAnns
decideAnns outerAnn (MkDecide innerAnn _ _ _) = MkDefAnns
  { defRef  = listToMaybe (mapMaybe citationText (refsOf [outerAnn, innerAnn]))
  , defDesc = plainDescOf innerAnn
  }

refsOf :: [Anno] -> [Text]
refsOf anns = [ getRef r | ann <- anns, Just r <- [ann ^. annRef] ]

-- | The user-facing text of a @\@ref@, with L4's own syntax removed.
--
-- The payload of a @\@ref X@ line INCLUDES the herald: @getRef@ hands back
-- @\"\@ref X\"@ verbatim (unlike @getDesc@, which strips). The inline form
-- @\<\<X\>\>@ hands back @\"\<\<X\>\>\"@, delimiters and all. Neither spelling
-- is prose, and neither may reach a user-facing screen.
citationText :: Text -> Maybe Text
citationText raw =
  let afterHerald = Text.strip (fromMaybe stripped (Text.stripPrefix "@ref" stripped))
      stripped    = Text.strip raw
      unwrapped   = case Text.stripPrefix "<<" afterHerald of
        Just inner -> Text.strip (fromMaybe inner (Text.stripSuffix ">>" inner))
        Nothing    -> afterHerald
  in if Text.null unwrapped then Nothing else Just unwrapped

-- | A /plain/ @\@desc@: the @\@export@\/@\@default@ marker rides in the same
-- annotation slot ('L4.Export.parseDescText' consumes the keyword), and that
-- text is the interview's own title prose — already on every verdict screen —
-- rather than the definition of a term.
plainDescOf :: Anno -> Maybe Text
plainDescOf ann = do
  d <- ann ^. annDesc
  let parsed = parseDescText (getDesc d)
  guard (not parsed.flags.isExport)
  guard (not (Text.null parsed.description))
  pure parsed.description

-- | A glossary entry the emitter could not carry, and why. Both reasons are
-- properties of docassemble's @auto terms@ key space, not of the L4 source.
data GlossDrop
  = GlossRegexMeta !Text
    -- ^ the term carries a regular-expression metacharacter
  | GlossKeyCollision !Text !Text
    -- ^ (dropped term, the earlier term whose folded key it collides with)
  deriving stock (Eq, Show)

-- | The @auto terms:@ glossary: every L4 /defined term/ in the module that
-- carries a plain @\@desc@ — each @DECLARE@d type, and each named definition,
-- top-level or @WHERE@-bound — in declaration order, first spelling wins,
-- paired with the entries that had to be dropped ('GlossDrop', declared in the
-- fidelity report by 'glossNotes' — never in silence).
--
-- It is a glossary of the /source/, not of the emitted blocks: docassemble's
-- auto-term regex only fires where the phrase actually occurs in prose, so an
-- entry for a term the interview never mentions is inert, and dropping the
-- unreachable ones would make the glossary depend on which export was compiled.
--
-- Record fields and @GIVEN@ parameters are deliberately absent: their @\@desc@
-- already lands on the question that asks them, as @help:@.
collectGlossary :: Module Resolved -> ([(Text, Text)], [GlossDrop])
collectGlossary (MkModule _ _ section) =
  let (regexSafe, regexBad) = partitionRegexSafe (goSection section)
      (kept, collided)      = dedupOnTerm regexSafe
  in (kept, regexBad <> collided)
 where
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Declare _ (MkDeclare ann _ (MkAppForm _ nm _ _) _) ->
      [ (resolvedToText nm, t) | Just t <- [plainDescOf ann] ]
    Decide _ d    -> decideGloss d
    Section _ sub -> goSection sub
    _             -> []
  decideGloss d@(MkDecide ann _ _ body) =
    [ (resolvedToText (decideName d), t) | Just t <- [plainDescOf ann] ]
      <> bodyGloss body
  bodyGloss = \case
    Where _ b ds -> bodyGloss b <> concatMap localGloss ds
    LetIn _ ds b -> concatMap localGloss ds <> bodyGloss b
    _            -> []
  localGloss = \case
    LocalDecide _ d -> decideGloss d
    LocalAssume _ _ -> []

-- | Docassemble lower-cases and whitespace-collapses every @auto terms@ key
-- (@parse.py:2905@), so two L4 names differing only in case would collide into
-- one YAML mapping entry: the first spelling wins, deterministically.
--
-- What that costs is not a duplicate key but a whole @\@desc@: the loser's
-- definition never reaches the artifact at all. The loss is unavoidable — one
-- of the two must go in either ordering, and the compiled regex is
-- @IGNORECASE@ anyway, so two case-variant entries could never gloss distinctly
-- — but it must not be silent, so the losers come back for 'glossNotes'.
dedupOnTerm :: [(Text, Text)] -> ([(Text, Text)], [GlossDrop])
dedupOnTerm = go Map.empty
 where
  go _ [] = ([], [])
  go seen ((term, defn) : rest)
    | Just winner <- Map.lookup key seen =
        let (kept, dropped) = go seen rest
        in (kept, GlossKeyCollision term winner : dropped)
    | otherwise =
        let (kept, dropped) = go (Map.insert key term seen) rest
        in ((term, defn) : kept, dropped)
   where
    key = foldKey term

-- | Docassemble's own @auto terms@ key normalisation, @parse.py:2905@ at
-- @1b6678384@: @re.sub(r'\\s+', ' ', term.lower())@.
foldKey :: Text -> Text
foldKey = Text.toLower . Text.unwords . Text.words

-- | Split glossary entries into those docassemble can compile into a working
-- auto-term, and those it cannot.
--
-- Docassemble interpolates the key straight into a regular expression with
-- @%@-formatting and NO @re.escape@ — @re.compile(r"(?i){?\\b(%s)\\b}?" %
-- re.sub(r'\\s', r'\\\\s+', lower_term))@, @parse.py:2908@ at @1b6678384@;
-- @re.escape@ appears nowhere in that file. So a metacharacter in an L4 name is
-- not text:
--
--   * an unbalanced @(@ or @[@ raises @re.error@ while the @Interview@ is being
--     constructed, so the emitted interview cannot be loaded /at all/ — and
--     @l4 check@ and @l4 docassemble@ both report success;
--   * a balanced @(…)@ compiles to a capture group, so the pattern no longer
--     matches the term that named it: the entry is dead, and the phrase it does
--     match (parentheses stripped) occurs nowhere.
--
-- Escaping the key is not the repair: docassemble stores the key verbatim as
-- the dictionary key and looks the definition back up by the /matched/ text
-- (@add_terms@, @filter\/html.py:686-703@), so an escaped key renders the
-- literal @[[term]]@ marker instead of a tooltip. Dropping the entry and
-- declaring the loss is the only faithful option — statutory names like
-- @a British citizen by virtue of subsection (1)@ are exactly the shape that
-- trips it.
partitionRegexSafe :: [(Text, Text)] -> ([(Text, Text)], [GlossDrop])
partitionRegexSafe entries =
  ( [ e | e@(term, _) <- entries, not (hasRegexMeta term) ]
  , [ GlossRegexMeta term | (term, _) <- entries, hasRegexMeta term ]
  )

-- | Every character Python's @re@ treats as syntax outside a character class.
-- @re.VERBOSE@ is not set at @parse.py:2908@, so @#@ and whitespace are inert.
hasRegexMeta :: Text -> Bool
hasRegexMeta = Text.any (`Set.member` regexMetaChars)

regexMetaChars :: Set Char
regexMetaChars = Set.fromList ".^$*+?{}[]\\|()"

-- | Citations attached to an /expression/ rather than to a definition. Those
-- are the refs this backend cannot carry: an expression is not a @code:@ block,
-- so there is nothing to hang an @explain()@ call on. Reported, not dropped in
-- silence.
exprRefs :: Expr Resolved -> [Text]
exprRefs =
  foldMapOf (cosmosOf (gplate @(Expr Resolved))) \e ->
    mapMaybe citationText (refsOf [getAnno e])

collectAssumes :: Module Resolved -> Map Unique (Assume Resolved)
collectAssumes (MkModule _ _ section) = Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Assume _ a@(MkAssume _ _ (MkAppForm _ nmRes _ _) _ _) -> [(getUnique nmRes, a)]
    Section _ sub -> goSection sub
    _ -> []

-- | A decision's parameters and its effective body. The @GIVEN@ signature is
-- authoritative when present (the app-form arguments are references to the
-- same bindings); a parameterless definition whose body is a @GIVEN … YIELD@
-- lambda (e.g. the eta-expanded @`not covered if` MEANS GIVEN x YIELD x@ in
-- rodentsAndVermin) is unwrapped into a function.
decideFunShape :: Decide Resolved -> ([Resolved], Expr Resolved)
decideFunShape (MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) _) (MkAppForm _ _ appArgs _) body0) =
  let ps0 = if null givens then appArgs else map givenName givens
  in case (ps0, body0) of
       ([], Lam _ (MkGivenSig _ lps) lbody) -> (map givenName lps, lbody)
       _                                    -> (ps0, body0)

-- ---------------------------------------------------------------------------
-- The lowering environment
-- ---------------------------------------------------------------------------

data InlineFun = MkInlineFun
  { ifU      :: !Unique
  , ifParams :: ![Unique]
  , ifBody   :: !(Expr Resolved)
  }

data Env = MkEnv
  { envVars        :: !(Map Unique Text)            -- ^ reference → interview variable / attribute path
  , envRecVars     :: !(Map Unique (Text, Unique))  -- ^ record-typed vars → (path, record type unique)
  , envMaybeVars   :: !(Map Unique MaybeRepr)       -- ^ MAYBE-typed scalar inputs → erased representation (R8)
  , envFuns        :: !(Map Unique InlineFun)       -- ^ function-valued bindings, inlined at application
  , envEnumCons    :: !(Map Unique ConInfo)
  , envRecords     :: !(Map Unique RecordSpec)
  , envInlineStack :: ![Unique]                     -- ^ inlining in progress (recursion guard)
  }

-- | How an erased @MAYBE@ input represents @NOTHING@ at interview runtime
-- (R8): @yesnomaybe@ stores it as Python @None@; an optional text field
-- submits it as @''@.
data MaybeRepr = ReprNone | ReprEmpty
  deriving stock (Eq, Show)

maybeReprOfTy :: Type' Resolved -> Maybe MaybeRepr
maybeReprOfTy = \case
  TyApp _ n [TyApp _ m []]
    | getUnique n == maybeUnique && getUnique m == booleanUnique -> Just ReprNone
    | getUnique n == maybeUnique && getUnique m == stringUnique  -> Just ReprEmpty
  _ -> Nothing

mkBaseEnv :: Ctx -> Env
mkBaseEnv ctx = MkEnv
  { envVars =
      Map.union
        (Map.fromList [ (td.tdU, td.tdSan) | td <- ctx.ctxTop, null td.tdParams ])
        (Map.fromList [ (u, pyIdent (assumeName a)) | (u, a) <- Map.toList ctx.ctxAssumes ])
  , envRecVars     = Map.empty
  , envMaybeVars   = Map.fromList
      [ (u, mr)
      | (u, MkAssume _ _ _ (Just ty) _) <- Map.toList ctx.ctxAssumes
      , Just mr <- [maybeReprOfTy ty]
      ]
  , envFuns        = Map.fromList
      [ (td.tdU, MkInlineFun td.tdU (map getUnique td.tdParams) td.tdBody)
      | td <- ctx.ctxTop, not (null td.tdParams)
      ]
  , envEnumCons    = ctx.ctxEnumCons
  , envRecords     = ctx.ctxRecords
  , envInlineStack = []
  }

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

lowerModule :: Module Resolved -> Either [LowerError] (DAPackage, FidelityReport)
lowerModule mod' =
  case getExportedFunctions mod' of
    [] -> Left [MkLowerError "" "no @export-annotated DECIDE found to compile to docassemble"]
    efs ->
      let ctx     = buildCtx mod'
          baseEnv = mkBaseEnv ctx

          exportBodies = [ b | ef <- efs, let MkDecide _ _ _ b = ef.exportDecide ]
          rootRefs     = Set.unions (map collectRefs exportBodies)
          reach        = closureRefs ctx rootRefs
          helpers      = [ td | td <- ctx.ctxTop
                              , td.tdU `Set.member` reach
                              , not td.tdExported
                              , null td.tdParams ]
          -- Every reachable top-level body — including parameterized decides,
          -- which survive by INLINING rather than as their own blocks. Their
          -- references still reach the emitted code, so they must count when
          -- deciding which ASSUME questions to emit and which seam goals are
          -- referenced: collecting only export + zero-param-helper bodies
          -- (the pre-repair behaviour) silently dropped an ASSUME question
          -- referenced only through an inlined function, and let a dangling
          -- seam-goal reference through the seamRefErrs guard below.
          reachBodies  = [ td.tdBody | td <- ctx.ctxTop, td.tdU `Set.member` reach ]
          allBodies    = exportBodies <> reachBodies
          allRefs      = Set.unions (rootRefs : map collectRefs reachBodies)
          assumeUs     = allRefs `Set.intersection` Map.keysSet ctx.ctxAssumes

          -- A seam export's goal is deliberately never emitted as a variable
          -- (R4), so another decision referencing it would dangle.
          seamRefErrs =
            [ MkLowerError ef.exportName
                "this seam-shaped export (top-level IMPLIES) is referenced by another \
                \decision; its goal variable is deliberately not emitted (R4), so the \
                \reference would dangle — restructure or un-export it"
            | ef <- efs
            , isSeamShaped ef
            , getUnique (decideName ef.exportDecide) `Set.member` allRefs
            ]

          assumeList = sortOn assumeName
            [ a | (u, a) <- Map.toList ctx.ctxAssumes, u `Set.member` assumeUs ]
          (aErrs, assumeQs) = partitionEithers (map (lowerAssumeQ ctx) assumeList)

          (hErrs, helperCodes) = partitionEithers (map (lowerHelperTop ctx baseEnv) helpers)

          (eErrs, eOuts) = partitionEithers (map (lowerExport ctx baseEnv) efs)
          (skipNotes, units) = partitionEithers eOuts

          allErrs = seamRefErrs <> aErrs <> hErrs <> eErrs
      in if not (null allErrs)
           then Left allErrs
           else if null units
             then Left [ MkLowerError "" $
                           "no exported decision could be emitted — every export was refused: "
                             <> Text.intercalate "; " [ n.message | n <- skipNotes ] ]
             else do
               let objectsEntries = nubOrd (concatMap (.euObjects) units)
                   blocks0 =
                        [ DAObjectsBlock objectsEntries | not (null objectsEntries) ]
                     <> map DACodeBlock (concatMap (.euAttrCodes) units)
                     <> map DAQuestionBlock (concatMap (.euQuestions) units)
                     <> map DAQuestionBlock assumeQs
                     <> map DACodeBlock (concat helperCodes)
                     <> map DACodeBlock (concatMap (.euCodes) units)
                     <> [ DADriverBlock d | u <- units, Just d <- [u.euDriver] ]
                     <> map DAScreenBlock (concatMap (.euScreens) units)
               -- Name collisions are checked before id dedup so a user-facing
               -- collision (two L4 names sanitising to one variable) is
               -- reported as such, not as an internal id collision.
               checkNameCollisions blocks0
               blocks1 <- dedupById blocks0
               -- M2: a verdict screen renders `logic_explanation()` exactly
               -- when something in the module actually calls `explain()`.
               -- Deciding it here, over the finished list, is the only place
               -- that can see the helper blocks as well as the export's own.
               let cited = any (\case DACodeBlock c -> isJust c.cCite; _ -> False) blocks1
                   blocks =
                     [ case b of
                         DAScreenBlock s -> DAScreenBlock s { sCites = cited }
                         other           -> other
                     | b <- blocks1 ]
                   inertFound = any exprHasInert allBodies
                   droppedRefs = nubOrd (concatMap exprRefs allBodies)
                   report = MkFidelityReport
                     { target = "docassemble"
                     , notes  = skipNotes
                                  <> moduleNotes (moduleSource mod') inertFound blocks
                                  <> refNotes (moduleSource mod') droppedRefs
                                  <> glossNotes (moduleSource mod') ctx.ctxGlossOut
                     }
               Right
                 ( MkDAPackage
                     { pkgSource = moduleSource mod'
                     , pkgTitle  = moduleTitleOf mod'
                     , pkgBlocks = blocks
                     , pkgGloss  = ctx.ctxGloss
                     , pkgPlan   = Nothing
                     }
                 , report
                 )

-- | A top-level implication is necessarily boolean, so the seam fires when
-- the declared GIVETH is BOOLEAN /or/ absent.
isSeamShaped :: ExportedFunction -> Bool
isSeamShaped ef =
  let MkDecide _ (MkTypeSig _ _ mGiveth) _ body0 = ef.exportDecide
      seamOK = case mGiveth of
        Just (MkGivethSig _ t) -> isBoolTy t
        Nothing                -> True
  in seamOK && case peelWhere body0 of
       App _ r [_, _] -> resolvedToText r == "__IMPLIES__"
       _              -> False

peelWhere :: Expr Resolved -> Expr Resolved
peelWhere = \case
  Where _ e _ -> peelWhere e
  LetIn _ _ e -> peelWhere e
  other       -> other

isBoolTy :: Type' Resolved -> Bool
isBoolTy = \case
  TyApp _ n [] -> getUnique n == booleanUnique
  _            -> False

-- ---------------------------------------------------------------------------
-- Per-module advisory notes (R6 float, R7 TYPICALLY, R8 MAYBE STRING, Inert)
-- ---------------------------------------------------------------------------

moduleNotes :: Text -> Bool -> [DABlock] -> [FidelityNote]
moduleNotes src inertFound blocks =
     [ MkFidelityNote
         { code = "DA-FLOAT", severity = Advisory, element = src, range = Nothing
         , message = "NUMBER is emitted as docassemble `datatype: number` and Python \
                     \float arithmetic; L4 evaluates numbers as exact Rationals"
         , lost = "exact decimal arithmetic — do not rely on exact equality of computed sums"
         }
     | anyNumeric ]
  <> [ MkFidelityNote
         { code = "DA-TYPICALLY", severity = Advisory, element = src, range = Nothing
         , message = "TYPICALLY defaults prefill these fields (the user still submits \
                     \the screen, so the entering value is user-confirmed): "
                       <> Text.intercalate ", " prefilled
         , lost = "L4's evaluator would have asked with no prefill; a prefilled widget biases the answer"
         }
     | not (null prefilled) ]
  <> [ MkFidelityNote
         { code = "DA-MAYBE-STRING", severity = Advisory, element = src, range = Nothing
         , message = "MAYBE STRING fields are optional text inputs; an empty submission \
                     \is read as NOTHING: " <> Text.intercalate ", " maybeStrs
         , lost = "a deliberately empty answer is indistinguishable from an absent one"
         }
     | not (null maybeStrs) ]
  <> [ MkFidelityNote
         { code = "DA-INERT", severity = Advisory, element = src, range = Nothing
         , message = "inert prose scaffolding was lowered to its boolean identity \
                     \(True in AND context, False in OR context)"
         , lost = "the scaffolding prose itself; it does not appear in the interview"
         }
     | inertFound ]
 where
  questions  = [ q | DAQuestionBlock q <- blocks ]
  codes      = [ c | DACodeBlock c <- blocks ]
  prefilled  = [ q.qVar | q <- questions, isJust q.qDefault ]
  maybeStrs  = [ q.qVar | q <- questions, q.qControl == CtlTextOptional ]
  anyNumeric = any (\q -> q.qControl == CtlNumber) questions
            || any (bodyHasNumeric . (.cBody)) codes

-- | M2: a @\@ref@ that sits on an /expression/ has no @code:@ block to hang an
-- @explain()@ call on, so its citation never reaches a screen. Reported rather
-- than dropped in silence — put the citation on the definition instead.
refNotes :: Text -> [Text] -> [FidelityNote]
refNotes src dropped =
  [ MkFidelityNote
      { code = "DA-REF-EXPR", severity = Advisory, element = src, range = Nothing
      , message = "these @ref citations are attached to an expression rather than to a \
                  \definition, so no `code:` block carries them: "
                    <> Text.intercalate "; " dropped
      , lost = "the citation does not reach the verdict screen — move the @ref onto the \
               \DECIDE or WHERE binding it justifies"
      }
  | not (null dropped) ]

-- | M2: @auto terms:@ entries docassemble's key space cannot carry. Both are
-- 'Lossy' rather than 'Advisory' by the §5 axis — the interview is emitted and
-- decides the same way, but a @\@desc@ the source wrote is gone from the
-- artifact, which is exactly \"expressed, but something the source said is
-- gone\". A silent @(nothing lost)@ over a dropped definition is the failure
-- this note exists to prevent.
glossNotes :: Text -> [GlossDrop] -> [FidelityNote]
glossNotes src drops =
     [ MkFidelityNote
         { code = "DA-GLOSS-REGEX", severity = Lossy, element = src, range = Nothing
         , message = "these L4 defined terms carry a regular-expression metacharacter, \
                     \and docassemble interpolates an `auto terms` key straight into a \
                     \regex with no re.escape (parse.py:2908 at 1b6678384), so the entry \
                     \would either fail to compile — taking the whole interview with it \
                     \— or compile to a pattern that no longer matches its own term: "
                       <> Text.intercalate "; " metaTerms
         , lost = "the glossary tooltip for these terms; rename the term, or move the \
                  \gloss onto a field or parameter, where it lands as `help:` instead"
         }
     | not (null metaTerms) ]
  <> [ MkFidelityNote
         { code = "DA-GLOSS-COLLIDE", severity = Lossy, element = src, range = Nothing
         , message = "docassemble lower-cases and whitespace-collapses every `auto terms` \
                     \key (parse.py:2905 at 1b6678384), so these L4 defined terms fold \
                     \onto an earlier term's key and the FIRST spelling wins: "
                       <> Text.intercalate "; " collisions
         , lost = "the later term's whole definition, not merely its spelling — its \
                  \@desc does not reach the interview at all"
         }
     | not (null collisions) ]
 where
  metaTerms  = [ t | GlossRegexMeta t <- drops ]
  collisions = [ "`" <> t <> "` (folds onto `" <> w <> "`)" | GlossKeyCollision t w <- drops ]

bodyHasNumeric :: DACodeBody -> Bool
bodyHasNumeric = \case
  DAAssign e        -> exprHasNumeric e
  DAIfChain arms d  -> any (\(c, v) -> exprHasNumeric c || exprHasNumeric v) arms || exprHasNumeric d
  DAInstantiate _   -> False

exprHasNumeric :: DAExpr -> Bool
exprHasNumeric = \case
  DANum _      -> True
  DABin {}     -> True
  DACmp _ a b  -> exprHasNumeric a || exprHasNumeric b
  DAAnd a b    -> exprHasNumeric a || exprHasNumeric b
  DAOr a b     -> exprHasNumeric a || exprHasNumeric b
  DANot a      -> exprHasNumeric a
  DACond c t e -> exprHasNumeric c || exprHasNumeric t || exprHasNumeric e
  DAIsNone a   -> exprHasNumeric a
  _            -> False

exprHasInert :: Expr Resolved -> Bool
exprHasInert =
  getAny . foldMapOf (cosmosOf (gplate @(Expr Resolved))) \case
    Inert {} -> Any True
    _        -> Any False

-- ---------------------------------------------------------------------------
-- Reachability
-- ---------------------------------------------------------------------------

-- | Every identifier an expression references, as plain variable, applied
-- function (the 'L4.Export.collectReferencedUniques' pattern), or projected
-- field. Projection heads matter because a computed (@MEANS@) record field
-- arrives as @Proj@ whose field name resolves to the desugar-synthesized
-- selector decide — a top-level function that must be walked for
-- reachability like any other callee.
collectRefs :: Expr Resolved -> Set Unique
collectRefs =
  foldMapOf (cosmosOf (gplate @(Expr Resolved))) \case
    App _ r _  -> Set.singleton (getUnique r)
    Proj _ _ f -> Set.singleton (getUnique f)
    _          -> Set.empty

closureRefs :: Ctx -> Set Unique -> Set Unique
closureRefs ctx = go Set.empty . Set.toList
 where
  go seen [] = seen
  go seen (u : us)
    | u `Set.member` seen = go seen us
    | Just td <- Map.lookup u ctx.ctxTopByU =
        go (Set.insert u seen) (Set.toList (collectRefs td.tdBody) <> us)
    | otherwise = go seen us

-- ---------------------------------------------------------------------------
-- Assume questions and helper decides
-- ---------------------------------------------------------------------------

lowerAssumeQ :: Ctx -> Assume Resolved -> Either LowerError DAQuestion
lowerAssumeQ ctx a@(MkAssume ann _ _ mTy mTypically) = hardLF nm do
  ty   <- maybe (Left (LFFatal "ASSUME has no declared type; docassemble needs one to pick a datatype")) Right mTy
  kind <- classifyTy ctx ty
  case kind of
    PRecord _ _ -> Left (LFFatal "record-typed ASSUME is not supported in v1 — pass it as a GIVEN parameter instead")
    _ -> do
      ctl  <- controlOf kind nm
      dflt <- traverse (lowerDefaultLit ctx) mTypically
      let dsc = (getDesc <$> (ann ^. annDesc)) <|> typeDescOf ctx ty
      pure (mkQuestion (pyIdent nm) nm dsc ctl dflt)
 where
  nm = assumeName a

assumeName :: Assume Resolved -> Text
assumeName (MkAssume _ _ (MkAppForm _ r _ _) _ _) = resolvedToText r

-- | A reachable zero-parameter top-level DECIDE becomes one unprefixed
-- @code:@ block (R3). A blocked construct here hardens into an error: a
-- surviving export depends on this definition.
lowerHelperTop :: Ctx -> Env -> TopDecide -> Either LowerError [DACode]
lowerHelperTop _ctx env td = hardLF td.tdL4 do
  let env1 = env { envInlineStack = [td.tdU] }
  (env2, pcs, inner) <- processBindings env1 td.tdSan td.tdBody
  cb <- lowerTopBody env2 inner
  pure (map pcToCode pcs <> [mkCode td.tdAnns.defRef td.tdSan (Just td.tdL4) cb])

-- ---------------------------------------------------------------------------
-- Exported decisions
-- ---------------------------------------------------------------------------

data ExpUnit = MkExpUnit
  { euObjects   :: ![(Text, Text)]
  , euAttrCodes :: ![DACode]      -- ^ nested-record instantiations + computed fields
  , euQuestions :: ![DAQuestion]
  , euCodes     :: ![DACode]      -- ^ WHERE bindings, goal/scope/requirement
  , euDriver    :: !(Maybe DADriver)
  , euScreens   :: ![DAScreen]
  }

data ParamArt = MkParamArt
  { paObject     :: !(Maybe (Text, Text))
  , paCodes      :: ![DACode]
  , paQuestions  :: ![DAQuestion]
  , paVarEntry   :: !(Maybe (Unique, Text))
  , paRecEntry   :: !(Maybe (Unique, (Text, Unique)))
  , paMaybeEntry :: !(Maybe (Unique, MaybeRepr))
  }

lowerExport
  :: Ctx -> Env -> ExportedFunction
  -> Either LowerError (Either FidelityNote ExpUnit)
lowerExport ctx baseEnv ef =
  convert (run ())
 where
  fnL4 = ef.exportName
  MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) mGiveth) (MkAppForm _ fnRes _ _) body0 =
    ef.exportDecide
  goalSan = pyIdent fnL4
  -- An export's own `@ref` attaches to the TopDecl node, which
  -- 'ExportedFunction' does not carry, so it is read back off the module scan.
  exportCite =
    maybe Nothing (.tdAnns.defRef) (Map.lookup (getUnique fnRes) ctx.ctxTopByU)

  -- The default export drives the interview: skipping it would leave the
  -- interview without an endpoint, so a blocked default is a hard error.
  convert = \case
    Right unit -> Right (Right unit)
    Left (LFFatal m) -> Left (MkLowerError fnL4 m)
    Left (LFBlocked cd m lostTxt)
      | ef.exportIsDefault ->
          Left (MkLowerError fnL4 (m <> " (and this is the default export, which must drive the interview)"))
      | otherwise ->
          Right (Left MkFidelityNote
            { code = cd, severity = Blocking, element = fnL4
            , range = Nothing, message = m, lost = lostTxt })

  run () = do
    paramArts <- traverse (lowerParam ctx baseEnv) givens
    let envP = baseEnv
          { envVars = Map.union
              (Map.fromList (mapMaybe (.paVarEntry) paramArts)) baseEnv.envVars
          , envRecVars = Map.union
              (Map.fromList (mapMaybe (.paRecEntry) paramArts)) baseEnv.envRecVars
          , envMaybeVars = Map.union
              (Map.fromList (mapMaybe (.paMaybeEntry) paramArts)) baseEnv.envMaybeVars
          , envInlineStack = [getUnique fnRes]
          }
    (envB, pendings, inner) <- processBindings envP goalSan body0
    let retTy    = (\(MkGivethSig _ t) -> t) <$> mGiveth
        boolGoal = maybe False isBoolTy retTy
        whereCodes = map pcToCode pendings
        dsc = if Text.null ef.exportDescription then Nothing else Just ef.exportDescription
    (goalCodes, mDriver, screens) <- case inner of
      -- R4: the verdict seam. Scope and requirement are separate seekable
      -- variables; the driver is scope-first; the classical short-circuit is
      -- never the goal. A top-level implication is necessarily boolean, so
      -- the seam also fires when the GIVETH is absent.
      App _ r [scopeE, reqE]
        | maybe True isBoolTy retTy, resolvedToText r == "__IMPLIES__" -> do
        sb <- lowerTopBody envB scopeE
        qb <- lowerTopBody envB reqE
        let scopeV   = goalSan <> "_scope"
            reqV     = goalSan <> "_requirement"
            verdictV = goalSan <> "_verdict"
            evC = goalSan <> "_screen_complies"
            evI = goalSan <> "_screen_in_breach"
            evN = goalSan <> "_screen_not_applicable"
            -- The rule's own citation rides on the SCOPE block: the rule
            -- fired — it was decided whether it applies — as soon as scope is
            -- known, and on the NotApplicable path the requirement block never
            -- runs at all.
            codes =
              [ mkCode exportCite scopeV (Just (fnL4 <> " — scope"))       sb
              , mkCode Nothing    reqV   (Just (fnL4 <> " — requirement")) qb
              ]
        pure $ if ef.exportIsDefault
          then ( codes
               , Just (DASeamDriver ("driver_" <> goalSan) fnL4 scopeV reqV verdictV evC evI evN)
               , [ mkScreen evC fnL4 dsc "Complies"
                     "This rule applies to the situation described, and its requirement is satisfied." Nothing
                 , mkScreen evI fnL4 dsc "InBreach"
                     "This rule applies to the situation described, and its requirement is NOT satisfied." Nothing
                 , mkScreen evN fnL4 dsc "NotApplicable"
                     "This rule does not apply to the situation described; its requirement was never asked." Nothing
                 ] )
          else (codes, Nothing, [])
      _ | boolGoal -> do
            gb <- lowerTopBody envB inner
            let evH = goalSan <> "_screen_holds"
                evF = goalSan <> "_screen_fails"
                codes = [mkCode exportCite goalSan (Just fnL4) gb]
            pure $ if ef.exportIsDefault
              then ( codes
                   , Just (DABoolDriver ("driver_" <> goalSan) fnL4 goalSan evH evF)
                   , [ mkScreen evH fnL4 dsc "Holds"
                         "On the answers given, this decision evaluates TRUE." Nothing
                     , mkScreen evF fnL4 dsc "Fails"
                         "On the answers given, this decision evaluates FALSE." Nothing
                     ] )
              else (codes, Nothing, [])
        | otherwise -> do
            gb <- lowerTopBody envB inner
            let evR = goalSan <> "_screen_result"
                codes = [mkCode exportCite goalSan (Just fnL4) gb]
            pure $ if ef.exportIsDefault
              then ( codes
                   , Just (DAValueDriver ("driver_" <> goalSan) fnL4 goalSan evR)
                   , [ mkScreen evR fnL4 dsc "Result"
                         "On the answers given, the value of this decision is:" (Just goalSan) ]
                   )
              else (codes, Nothing, [])
    pure MkExpUnit
      { euObjects   = mapMaybe (.paObject) paramArts
      , euAttrCodes = concatMap (.paCodes) paramArts
      , euQuestions = concatMap (.paQuestions) paramArts
      , euCodes     = whereCodes <> goalCodes
      , euDriver    = mDriver
      , euScreens   = screens
      }

mkScreen :: Text -> Text -> Maybe Text -> Text -> Text -> Maybe Text -> DAScreen
mkScreen ev goalL4 dsc verdict explain showVar = MkDAScreen
  { sId = "ev_" <> ev, sEvent = ev, sGoalL4 = goalL4
  , sDesc = dsc, sVerdict = verdict, sExplain = explain, sShowVar = showVar
  -- Flipped once, in 'lowerModule', when the finished block list is known to
  -- carry at least one citation: a screen cannot see the helper blocks from
  -- here, and a module with no `@ref` keeps its v1 screen byte for byte.
  , sCites = False
  }

-- ---------------------------------------------------------------------------
-- Parameters and record fields (R2)
-- ---------------------------------------------------------------------------

lowerParam :: Ctx -> Env -> OptionallyTypedName Resolved -> Either LF ParamArt
lowerParam ctx env (MkOptionallyTypedName ann r mTy mTypically) = do
  ty   <- maybe (Left (LFFatal ("parameter `" <> l4 <> "` has no declared type"))) Right mTy
  kind <- classifyTy ctx ty
  case kind of
    PRecord ru rs -> do
      when (isJust mTypically) $
        Left (LFFatal ("TYPICALLY on record parameter `" <> l4 <> "` is not supported"))
      (attrCodes, qs) <- lowerRecordFields ctx env [ru] var rs
      pure MkParamArt
        { paObject = Just (var, "DAObject"), paCodes = attrCodes, paQuestions = qs
        , paVarEntry = Nothing, paRecEntry = Just (u, (var, ru))
        , paMaybeEntry = Nothing }
    _ -> do
      ctl  <- controlOf kind l4
      dflt <- traverse (lowerDefaultLit ctx) mTypically
      let dsc = (getDesc <$> (ann ^. annDesc)) <|> typeDescOf ctx ty
      pure MkParamArt
        { paObject = Nothing, paCodes = []
        , paQuestions = [mkQuestion var l4 dsc ctl dflt]
        , paVarEntry = Just (u, var), paRecEntry = Nothing
        , paMaybeEntry = (u,) <$> maybeReprOfTy ty }
 where
  l4  = resolvedToText r
  var = pyIdent l4
  u   = getUnique r

-- | One question per stored field, a @DAObject@ instantiation plus recursion
-- per nested record field. Computed (@MEANS@) fields never reach this
-- function: desugar strips them from the record and synthesizes selector
-- decides, which are inlined at each projection site ('lowerProj').
lowerRecordFields
  :: Ctx -> Env -> [Unique] -> Text -> RecordSpec
  -> Either LF ([DACode], [DAQuestion])
lowerRecordFields ctx env visited path rs = do
  parts <- traverse fieldArt rs.rsFields
  pure (concatMap fst parts, concatMap snd parts)
 where
  fieldArt f = do
    let attrVar = path <> "." <> f.fsSan
    kind <- classifyTy ctx f.fsTy
    case kind of
      PRecord ru rs' -> do
        when (ru `elem` visited) $
          Left (LFFatal ("recursive record nesting via field `" <> f.fsL4 <> "`"))
        when (isJust f.fsDefault) $
          Left (LFFatal ("TYPICALLY on record-typed field `" <> f.fsL4 <> "` is not supported"))
        (subCodes, subQs) <- lowerRecordFields ctx env (ru : visited) attrVar rs'
        let initCode = MkDACode
              { cId = "c_" <> attrVar, cVar = attrVar
              , cL4 = Just f.fsL4, cBody = DAInstantiate "DAObject", cDeps = []
              , cCite = Nothing }
        pure (initCode : subCodes, subQs)
      _ -> do
        ctl  <- controlOf kind f.fsL4
        dflt <- traverse (lowerDefaultLit ctx) f.fsDefault
        let dsc = f.fsDesc <|> typeDescOf ctx f.fsTy
        pure ([], [mkQuestion attrVar f.fsL4 dsc ctl dflt])

-- | Block ids are @q_@/@c_@ plus the docassemble variable name /verbatim/
-- (dots included — docassemble ids are free-form strings), so distinct
-- variables can never collide on id: collapsing @.@ and @_@ together used to
-- refuse a valid program (attribute path @p.foo_bar@ vs scalar @p_foo_bar@)
-- with a misleading "internal id collision".
mkQuestion :: Text -> Text -> Maybe Text -> DAFieldControl -> Maybe DAExpr -> DAQuestion
mkQuestion var l4 dsc ctl dflt = MkDAQuestion
  { qId = "q_" <> var, qVar = var, qLabel = l4, qText = l4
  , qHelp = dsc, qControl = ctl, qDefault = dflt }

-- ---------------------------------------------------------------------------
-- Type classification (R6, R8)
-- ---------------------------------------------------------------------------

data ParamKind
  = PBool | PNumber | PString | PDate
  | PMaybeBool | PMaybeString
  | PEnum EnumInfo
  | PRecord Unique RecordSpec

classifyTy :: Ctx -> Type' Resolved -> Either LF ParamKind
classifyTy ctx = \case
  TyApp _ n []
    | getUnique n == booleanUnique -> Right PBool
    | getUnique n == numberUnique  -> Right PNumber
    | getUnique n == stringUnique  -> Right PString
    | getUnique n == dateUnique    -> Right PDate
    | Just ei <- Map.lookup (getUnique n) ctx.ctxEnums   -> Right (PEnum ei)
    | Just rs <- Map.lookup (getUnique n) ctx.ctxRecords -> Right (PRecord (getUnique n) rs)
    | otherwise -> Left (LFFatal ("unsupported type `" <> resolvedToText n <> "` for a docassemble input (v1: BOOLEAN, NUMBER, STRING, DATE, nullary enums, records of these)"))
  TyApp _ n [inner]
    | getUnique n == maybeUnique -> do
        innerKind <- classifyTy ctx inner
        case innerKind of
          PBool   -> Right PMaybeBool
          PString -> Right PMaybeString
          PNumber -> Left (LFFatal "MAYBE NUMBER is refused in v1 (R8): an unanswered docassemble number submits as 0, so absence would be indistinguishable from a real answer (M4: paired is-known question)")
          PDate   -> Left (LFFatal "MAYBE DATE is refused in v1 (R8): an unanswered docassemble date submits as '', so absence would be indistinguishable from a real answer (M4: paired is-known question)")
          _       -> Left (LFFatal "unsupported MAYBE payload for a docassemble input (v1: MAYBE BOOLEAN and MAYBE STRING only)")
  Fun {}    -> Left (LFFatal "a function-typed value cannot be a docassemble input")
  ty        -> Left (LFFatal ("unsupported type shape for a docassemble input: " <> typeHead ty))
 where
  typeHead :: Type' Resolved -> Text
  typeHead = \case
    Type {}   -> "TYPE"
    TyApp _ n args -> resolvedToText n <> (if null args then "" else " OF …")
    Fun {}    -> "FUNCTION"
    Forall {} -> "FORALL"
    InfVar {} -> "inference variable"

controlOf :: ParamKind -> Text -> Either LF DAFieldControl
controlOf kind l4 = case kind of
  PBool        -> Right CtlYesNoRadio
  PNumber      -> Right CtlNumber
  PString      -> Right CtlText
  PDate        -> Right CtlDate
  PMaybeBool   -> Right CtlYesNoMaybe
  PMaybeString -> Right CtlTextOptional
  PEnum ei     ->
    case [ cn | (cn, ar) <- ei.eiCons, ar > 0 ] of
      []        -> Right (CtlRadio (map fst ei.eiCons))
      (bad : _) -> Left (LFFatal ("enum `" <> ei.eiName <> "` has payload constructor `" <> bad
                                   <> "`; payload constructors are refused in v1 (M4: `show if` follow-ups)"))
  PRecord _ _  -> Left (LFFatal ("internal: record-typed `" <> l4 <> "` reached scalar-control classification"))

typeDescOf :: Ctx -> Type' Resolved -> Maybe Text
typeDescOf ctx = \case
  TyApp _ n _ -> Map.lookup (getUnique n) ctx.ctxTypeDesc
  _           -> Nothing

-- | @TYPICALLY@ defaults must be literals (R7): numeric, string, boolean, or
-- a nullary enum constructor.
lowerDefaultLit :: Ctx -> Expr Resolved -> Either LF DAExpr
lowerDefaultLit ctx = \case
  Lit _ (NumericLit _ v) -> Right (DANum v)
  Lit _ (StringLit _ t)  -> Right (DAStrLit t)
  App _ r []
    | Just b <- boolLit (resolvedToText r) -> Right (DABoolLit b)
    | Just ci <- Map.lookup (getUnique r) ctx.ctxEnumCons
    , ci.ciArity == 0 -> Right (DAStrLit ci.ciName)
  _ -> Left (LFFatal "unsupported TYPICALLY default — v1 accepts literals and nullary enum constructors only")

-- ---------------------------------------------------------------------------
-- WHERE / LET bindings (R3)
-- ---------------------------------------------------------------------------

data PendingCode = MkPendingCode
  { pcVar  :: !Text
  , pcL4   :: !Text
  , pcBody :: !DACodeBody
  , pcCite :: !(Maybe Text)   -- ^ this binding's own @\@ref@ citation (M2)
  }

data BindEntry
  = BindVar !Unique !Text !Text !DefAnns !(Expr Resolved)
    -- ^ unique, L4 name, variable, its own annotations, body
  | BindFun !Unique !Text ![Unique] !(Expr Resolved)  -- ^ unique, L4 name, params, body

-- | Peel @WHERE@/@LET@ layers off the top of a definition body. Every
-- zero-parameter binding becomes one @code:@ block named
-- @\<prefix\>_\<binding\>@; function-valued bindings are registered for
-- inline application. All binding names enter scope before any body is
-- lowered, so bindings may reference each other in either order.
processBindings :: Env -> Text -> Expr Resolved -> Either LF (Env, [PendingCode], Expr Resolved)
processBindings env prefix expr0 = case expr0 of
  Where _ inner decls -> withDecls decls inner
  LetIn _ decls inner -> withDecls decls inner
  other               -> Right (env, [], other)
 where
  withDecls decls inner = do
    entries <- traverse classifyDecl decls
    let env1 = foldl' extendEnv env entries
    pcs <- concat <$> traverse (lowerBinding env1) entries
    (env2, morePcs, inner') <- processBindings env1 prefix inner
    pure (env2, pcs <> morePcs, inner')

  classifyDecl = \case
    LocalDecide localAnn d ->
      let (ps, b) = decideFunShape d
          nm      = resolvedToText (decideName d)
          u       = getUnique (decideName d)
      in Right $ if null ps
           then BindVar u nm (prefix <> "_" <> pyIdent nm) (decideAnns localAnn d) b
           else BindFun u nm (map getUnique ps) b
    LocalAssume _ a ->
      Left (LFFatal ("local ASSUME `" <> assumeName a
                      <> "` in WHERE is not supported in v1 — declare it at module level or pass it as a GIVEN"))

  extendEnv envAcc = \case
    BindVar u _ var _ _ -> envAcc { envVars = Map.insert u var envAcc.envVars }
    BindFun u _ ps b    -> envAcc { envFuns = Map.insert u (MkInlineFun u ps b) envAcc.envFuns }

  lowerBinding env1 = \case
    BindFun {} -> Right []  -- inlined at each application site (R3)
    BindVar _ nm var anns b -> do
      (env2, subPcs, innerB) <- processBindings env1 var b
      cb <- lowerTopBody env2 innerB
      pure (subPcs <> [MkPendingCode var nm cb anns.defRef])

pcToCode :: PendingCode -> DACode
pcToCode pc = mkCode pc.pcCite pc.pcVar (Just pc.pcL4) pc.pcBody

mkCode :: Maybe Text -> Text -> Maybe Text -> DACodeBody -> DACode
mkCode cite var mL4 cb = MkDACode
  { cId = "c_" <> var, cVar = var, cL4 = mL4
  , cBody = cb, cDeps = nubOrd (bodyVars cb), cCite = cite }

bodyVars :: DACodeBody -> [Text]
bodyVars = \case
  DAAssign e       -> exprVars e
  DAIfChain arms d -> concatMap (\(c, v) -> exprVars c <> exprVars v) arms <> exprVars d
  DAInstantiate _  -> []

exprVars :: DAExpr -> [Text]
exprVars = \case
  DAVar v      -> [v]
  DABin _ a b  -> exprVars a <> exprVars b
  DACmp _ a b  -> exprVars a <> exprVars b
  DAAnd a b    -> exprVars a <> exprVars b
  DAOr a b     -> exprVars a <> exprVars b
  DANot a      -> exprVars a
  DACond c t e -> exprVars c <> exprVars t <> exprVars e
  DAIsNone a   -> exprVars a
  _            -> []

-- ---------------------------------------------------------------------------
-- Bodies and expressions
-- ---------------------------------------------------------------------------

-- | The body of one @code:@ block. A top-level @CONSIDER@/@BRANCH@/@IF@
-- renders as an if/elif/else chain (R6); nested ones become Python
-- conditional expressions.
lowerTopBody :: Env -> Expr Resolved -> Either LF DACodeBody
lowerTopBody env e0 = case e0 of
  Consider _ scrut branches -> do
    (arms, d) <- considerArms env scrut branches
    pure (DAIfChain arms d)
  MultiWayIf _ guards oth -> do
    (arms, d) <- multiWayArms env guards oth
    pure (DAIfChain arms d)
  IfThenElse _ c t el ->
    (\c' t' e' -> DAIfChain [(c', t')] e')
      <$> lowerExpr env c <*> lowerExpr env t <*> lowerExpr env el
  _ -> DAAssign <$> lowerExpr env e0

considerArms
  :: Env -> Expr Resolved -> [Branch Resolved]
  -> Either LF ([(DAExpr, DAExpr)], DAExpr)
considerArms env scrut branches
  | Just repr <- scrutMaybeRepr env scrut = maybeArms env repr scrut branches
  | otherwise = do
      scrutE <- lowerExpr env scrut
      let whens  = [ (con, b) | MkBranch _ (When _ (PatApp _ con [])) b <- branches ]
          others = [ b | MkBranch _ (Otherwise _) b <- branches ]
      when (length whens + length others /= length branches) $
        Left (LFFatal "only nullary enum-constructor WHEN patterns (plus OTHERWISE) are supported in v1")
      d <- case others of
        (d0 : _) -> lowerExpr env d0
        []       -> Left (LFFatal "CONSIDER without an OTHERWISE cannot be compiled to docassemble (R6: the ==/elif chain needs a default arm)")
      arms <- for whens \(con, b) -> do
        cond <- enumTest env scrutE con
        v    <- lowerExpr env b
        pure (cond, v)
      pure (arms, d)

-- | The erased representation of a @MAYBE@ scrutinee, when there is one: a
-- bare @MAYBE@-typed parameter/ASSUME, or a projection whose field is
-- @MAYBE BOOLEAN@/@MAYBE STRING@ (R8).
scrutMaybeRepr :: Env -> Expr Resolved -> Maybe MaybeRepr
scrutMaybeRepr env = \case
  App _ r []     -> Map.lookup (getUnique r) env.envMaybeVars
  Proj _ inner f -> do
    (_, spec) <- resolvePath env inner
    fld <- find (\fs -> fs.fsL4 == resolvedToText f) spec.rsFields
    maybeReprOfTy fld.fsTy
  _ -> Nothing

-- | R8: a @CONSIDER@ over a @MAYBE@ input pattern-matches on /presence/. v1
-- accepts exactly one @WHEN JUST x@ arm plus one absence arm (@WHEN NOTHING@
-- or @OTHERWISE@). The absence test is the input's erased runtime
-- representation — @is None@ for @MAYBE BOOLEAN@ (@yesnomaybe@), @== ''@ for
-- @MAYBE STRING@ — and the @JUST@-bound variable reads the input itself.
maybeArms
  :: Env -> MaybeRepr -> Expr Resolved -> [Branch Resolved]
  -> Either LF ([(DAExpr, DAExpr)], DAExpr)
maybeArms env repr scrut branches = do
  scrutE <- lowerExpr env scrut
  scrutV <- case scrutE of
    DAVar v -> Right v
    _       -> Left (LFFatal "presence match (JUST/NOTHING) is supported only directly on a MAYBE input (R8)")
  let justs    = [ (pv, b) | MkBranch _ (When _ (PatApp _ con [pv])) b <- branches
                           , getUnique con == justUnique ]
      nothings = [ b | MkBranch _ (When _ (PatApp _ con [])) b <- branches
                     , getUnique con == nothingUnique ]
      others   = [ b | MkBranch _ (Otherwise _) b <- branches ]
  case (justs, nothings <> others) of
    ([(pv, jb)], [nb]) | length branches == 2 -> do
      -- Post-typecheck a binder is always PatVar (the scope checker rewrites
      -- out-of-scope nullary PatApps to PatVar, TypeCheck.hs inferPattern),
      -- so a PatApp payload here is a genuine constructor pattern — e.g.
      -- `WHEN JUST TRUE` — which is a match on the payload VALUE, not a
      -- binder. Treating it as a binder silently degraded the match to a
      -- mere presence test (a wrong verdict); it is refused instead.
      ju <- case pv of
        PatVar _ v -> Right (getUnique v)
        _          -> Left (LFFatal "the JUST pattern must bind a plain variable (v1); matching on the payload value (e.g. `WHEN JUST TRUE`) is not supported — bind a variable and compare it in the arm body")
      bodyJ <- lowerExpr env { envVars = Map.insert ju scrutV env.envVars } jb
      bodyN <- lowerExpr env nb
      let absent = case repr of
            ReprNone  -> DAIsNone scrutE
            ReprEmpty -> DACmp DAEq scrutE (DAStrLit "")
      pure ([(absent, bodyN)], bodyJ)
    _ -> Left (LFFatal "CONSIDER over a MAYBE value must have exactly one `WHEN JUST x` arm and one absence arm (`WHEN NOTHING` or OTHERWISE) (R8)")

enumTest :: Env -> DAExpr -> Resolved -> Either LF DAExpr
enumTest env scrutE con =
  case Map.lookup (getUnique con) env.envEnumCons of
    Just ci
      | ci.ciArity == 0 -> Right (DACmp DAEq scrutE (DAStrLit ci.ciName))
      | otherwise -> Left (LFFatal ("CONSIDER: constructor `" <> ci.ciName <> "` carries a payload; payload patterns are refused in v1"))
    Nothing -> Left (LFFatal ("CONSIDER: `" <> resolvedToText con <> "` is not an enum constructor (only enum CONSIDER is supported in v1)"))

multiWayArms
  :: Env -> [GuardedExpr Resolved] -> Expr Resolved
  -> Either LF ([(DAExpr, DAExpr)], DAExpr)
multiWayArms env guards oth = do
  d    <- lowerExpr env oth
  arms <- for guards \(MkGuardedExpr _ c b) ->
    (,) <$> lowerExpr env c <*> lowerExpr env b
  pure (arms, d)

lowerExpr :: Env -> Expr Resolved -> Either LF DAExpr
lowerExpr env = go
 where
  go = \case
    And _ a b       -> DAAnd <$> go a <*> go b
    Or _ a b        -> DAOr <$> go a <*> go b
    Not _ a         -> DANot <$> go a
    -- A *nested* implication reads classically (R4); only the top-level
    -- implication of an exported boolean decision is the seam, and that is
    -- intercepted in 'lowerExport' before this function ever sees it.
    Implies _ a b   -> (\x y -> DAOr (DANot x) y) <$> go a <*> go b
    Equals _ a b    -> DACmp DAEq  <$> go a <*> go b
    Leq _ a b       -> DACmp DALeq <$> go a <*> go b
    Geq _ a b       -> DACmp DAGeq <$> go a <*> go b
    Lt _ a b        -> DACmp DALt  <$> go a <*> go b
    Gt _ a b        -> DACmp DAGt  <$> go a <*> go b
    Plus _ a b      -> DABin DAAdd <$> go a <*> go b
    Minus _ a b     -> DABin DASub <$> go a <*> go b
    Times _ a b     -> DABin DAMul <$> go a <*> go b
    DividedBy _ a b -> DABin DADiv <$> go a <*> go b
    Modulo _ a b    -> DABin DAMod <$> go a <*> go b
    IfThenElse _ c t e -> DACond <$> go c <*> go t <*> go e
    Percent _ a     -> (\x -> DABin DADiv x (DANum 100)) <$> go a
    Lit _ (NumericLit _ v) -> Right (DANum v)
    Lit _ (StringLit _ t)  -> Right (DAStrLit t)
    Proj _ inner f  -> lowerProj env inner f
    App _ r args    -> lowerApp env go r args
    Consider _ scrut branches -> do
      (arms, d) <- considerArms env scrut branches
      pure (foldr (\(c, v) acc -> DACond c v acc) d arms)
    MultiWayIf _ guards oth -> do
      (arms, d) <- multiWayArms env guards oth
      pure (foldr (\(c, v) acc -> DACond c v acc) d arms)
    -- Inert prose scaffolding evaluates to the identity of its containing
    -- boolean operator, exactly as the L4 evaluator treats it; an Advisory
    -- note is raised per module ('moduleNotes').
    Inert _ _ ictx -> Right (DABoolLit (inertIdentity ictx))
    other -> Left (refuse other)

  inertIdentity = \case
    InertCtxAnd  -> True
    InertCtxOr   -> False
    InertCtxNone -> True

-- | @p's field@ (possibly nested) resolves to a dotted attribute path on a
-- record-typed variable; docassemble seeks each attribute independently.
--
-- A /computed/ (@MEANS@) field is not in 'rsFields' at all: desugar stripped
-- it from the record and synthesized a top-level selector decide
-- (@f _self MEANS …@) that the type checker resolved this projection's field
-- name to. That selector is a parameterized top decide, hence in 'envFuns',
-- and the projection lowers by inlining it applied to the record — sibling
-- references inside the @MEANS@ body are @Proj@s on @_self@ and resolve
-- against the same record path after substitution.
lowerProj :: Env -> Expr Resolved -> Resolved -> Either LF DAExpr
lowerProj env inner f =
  case resolvePath env inner of
    Just (path, spec) ->
      case find (\fs -> fs.fsL4 == resolvedToText f) spec.rsFields of
        Just fld -> Right (DAVar (path <> "." <> fld.fsSan))
        Nothing
          | Just selector <- Map.lookup (getUnique f) env.envFuns ->
              inlineApply env selector (resolvedToText f) [inner]
          | otherwise ->
              Left (LFFatal ("record `" <> spec.rsName <> "` has no field `" <> resolvedToText f <> "`"))
    Nothing -> Left (LFFatal "only projection off a record-typed parameter (or a nested record field of one) is supported in v1")

resolvePath :: Env -> Expr Resolved -> Maybe (Text, RecordSpec)
resolvePath env = \case
  App _ r [] -> do
    (path, ru) <- Map.lookup (getUnique r) env.envRecVars
    spec <- Map.lookup ru env.envRecords
    pure (path, spec)
  Proj _ inner f -> do
    (path, spec) <- resolvePath env inner
    fld <- find (\fs -> fs.fsL4 == resolvedToText f) spec.rsFields
    ru <- case fld.fsTy of
      TyApp _ n _ | Map.member (getUnique n) env.envRecords -> Just (getUnique n)
      _ -> Nothing
    spec' <- Map.lookup ru env.envRecords
    pure (path <> "." <> fld.fsSan, spec')
  _ -> Nothing

lowerApp
  :: Env -> (Expr Resolved -> Either LF DAExpr) -> Resolved -> [Expr Resolved]
  -> Either LF DAExpr
lowerApp env go r args = case args of
  []
    | Just b <- boolLit nm -> Right (DABoolLit b)
    | Just v <- Map.lookup u env.envVars -> Right (DAVar v)
    | Just (path, _) <- Map.lookup u env.envRecVars -> Right (DAVar path)
    | Just ci <- Map.lookup u env.envEnumCons ->
        if ci.ciArity == 0
          then Right (DAStrLit ci.ciName)
          else Left (LFFatal ("enum constructor `" <> nm <> "` carries a payload; payload constructors are refused in v1 (M4: `show if` follow-ups)"))
    | Map.member u env.envFuns ->
        Left (LFFatal ("higher-order use of function `" <> nm <> "` — only direct application can be inlined (v1 emits no Python module); refused by name (R3)"))
    | nm == "NOTHING" ->
        Left (LFFatal "`NOTHING` in a body: v1 supports MAYBE only as presence-erased inputs (R8), not as produced values")
    | otherwise ->
        Left (LFFatal ("unbound reference `" <> nm <> "` (recursion, prelude functions, and unsupported builtins are not available in v1)"))
  _ -> case builtinOp nm of
    Just mk -> traverse go args >>= mk
    Nothing
      | nm == "JUST" ->
          Left (LFFatal "`JUST` in a body: v1 supports MAYBE only as presence-erased inputs (R8), not as produced values")
      | Just ci <- Map.lookup u env.envEnumCons ->
          Left (LFFatal ("construction of enum payload `" <> ci.ciName <> "` is refused in v1 (M4: `show if` follow-ups)"))
      | Just f <- Map.lookup u env.envFuns -> inlineApply env f nm args
      | Map.member u env.envVars ->
          Left (LFFatal ("`" <> nm <> "` is not a function but is applied to arguments"))
      | otherwise ->
          Left (LFFatal ("cannot compile call to `" <> nm <> "` — v1 supports calls to in-module decisions and directly-applied WHERE bindings only"))
 where
  u  = getUnique r
  nm = resolvedToText r

-- | Beta-reduce a directly-applied function-valued binding at lower time
-- (R3): substitute the argument expressions for the parameters and lower the
-- result. The identity lambda @`not covered if` MEANS GIVEN x YIELD x@ in
-- rodentsAndVermin is the canonical case. Recursion cannot be inlined and is
-- refused by name.
inlineApply :: Env -> InlineFun -> Text -> [Expr Resolved] -> Either LF DAExpr
inlineApply env f nm args
  | length args /= length f.ifParams =
      Left (LFFatal ("`" <> nm <> "` applied to " <> tshow (length args)
                      <> " argument(s); it takes " <> tshow (length f.ifParams)))
  | f.ifU `elem` env.envInlineStack =
      Left (LFFatal ("recursive call to `" <> nm <> "` cannot be inlined (v1 emits no Python module)"))
    -- A function value passed as data (rather than a directly-applied
    -- callee) has no docassemble variable it could become: refuse by the
    -- function's own name (R3), before substitution renames it to the
    -- parameter it would have bound.
  | (badNm : _) <- [ resolvedToText r
                   | App _ r [] <- args, Map.member (getUnique r) env.envFuns ] =
      Left (LFFatal ("higher-order use of function `" <> badNm <> "` — it is passed as an \
                     \argument to `" <> nm <> "`, and only direct application can be \
                     \inlined (v1 emits no Python module); refused by name (R3)"))
  | otherwise =
      let sub   = Map.fromList (zip f.ifParams args)
          body' = substituteExpr sub f.ifBody
      in lowerExpr env { envInlineStack = f.ifU : env.envInlineStack } body'

-- | Substitute expressions for nullary references to the given uniques.
-- Uniques are globally unique, so there is no capture to avoid.
substituteExpr :: Map Unique (Expr Resolved) -> Expr Resolved -> Expr Resolved
substituteExpr sub = go
 where
  go e = case e of
    App _ r [] | Just repl <- Map.lookup (getUnique r) sub -> repl
    _ -> over (gplate @(Expr Resolved)) go e

-- | The builtin operators L4 desugars infix syntax into (post-typecheck,
-- @a AND b@ arrives as @App __AND__ [a, b]@).
builtinOp :: Text -> Maybe ([DAExpr] -> Either LF DAExpr)
builtinOp nm = case nm of
  "__PLUS__"    -> Just (bin DAAdd)
  "__MINUS__"   -> Just (bin DASub)
  "__TIMES__"   -> Just (bin DAMul)
  "__DIVIDE__"  -> Just (bin DADiv)
  "__MODULO__"  -> Just (bin DAMod)
  "__EQUALS__"  -> Just (cmp DAEq)
  "__LEQ__"     -> Just (cmp DALeq)
  "__GEQ__"     -> Just (cmp DAGeq)
  "__LT__"      -> Just (cmp DALt)
  "__GT__"      -> Just (cmp DAGt)
  "__AND__"     -> Just (logic2 DAAnd)
  "__OR__"      -> Just (logic2 DAOr)
  "__NOT__"     -> Just notOp
  "__IMPLIES__" -> Just impliesOp   -- nested: a ⇒ b ≡ (¬a) ∨ b, classical (R4)
  _             -> Nothing
 where
  bin op    = \case [a, b] -> Right (DABin op a b); xs -> arity 2 xs
  cmp op    = \case [a, b] -> Right (DACmp op a b); xs -> arity 2 xs
  logic2 f  = \case [a, b] -> Right (f a b);        xs -> arity 2 xs
  notOp     = \case [a]    -> Right (DANot a);      xs -> arity 1 xs
  impliesOp = \case [a, b] -> Right (DAOr (DANot a) b); xs -> arity 2 xs
  arity :: Int -> [DAExpr] -> Either LF DAExpr
  arity n xs = Left (LFFatal ("operator `" <> nm <> "` expected " <> tshow n
                               <> " argument(s), got " <> tshow (length xs)))

boolLit :: Text -> Maybe Bool
boolLit t = case Text.toLower t of
  "true"  -> Just True
  "false" -> Just False
  _       -> Nothing

-- | The refusal table (spec §5): deontic/ledger/IO constructs are 'Blocking'
-- — the target has no form for them at all; shape restrictions of the v1
-- fragment are plain errors.
refuse :: Expr Resolved -> LF
refuse = \case
  Regulative {} -> LFBlocked "DA-DEONTIC"
    "deontic/regulative rule (PARTY MUST/MAY/SHANT) has no docassemble form"
    "the obligation layer: breach, HENCE/LEST continuations and deadlines cannot ride in a single-user interview (v1 non-goal; docassemble roles are a plausible M-later mapping)"
  Event {} -> LFBlocked "DA-DEONTIC"
    "EVENT has no docassemble form"
    "the event/trace layer of the deontic machine"
  Breach {} -> LFBlocked "DA-DEONTIC"
    "BREACH has no docassemble form"
    "the breach verdict of the deontic machine"
  RAnd {} -> LFBlocked "DA-DEONTIC"
    "regulative AND has no docassemble form"
    "deontic composition"
  ROr {} -> LFBlocked "DA-DEONTIC"
    "regulative OR has no docassemble form"
    "deontic composition"
  Fetch {} -> LFBlocked "DA-IO"
    "FETCH has no docassemble form in v1"
    "outbound HTTP at interview runtime (docassemble's DAWeb exists but is deliberately unused, spec §4)"
  Post {} -> LFBlocked "DA-IO"
    "POST has no docassemble form in v1"
    "outbound HTTP at interview runtime"
  Env {} -> LFBlocked "DA-IO"
    "environment lookup has no docassemble form"
    "server-side environment access"
  Record {} -> LFBlocked "DA-LEDGER"
    "RECORD/COMMIT/ATTEST ledger write has no docassemble form"
    "the state-as-a-ledger layer"
  ReadCell {} -> LFBlocked "DA-LEDGER"
    "RECALL ledger read has no docassemble form"
    "the state-as-a-ledger layer"
  Lam {}      -> LFFatal "lambda outside a directly-applied WHERE binding cannot be emitted (v1 emits no Python module)"
  List {}     -> LFFatal "list literal — LIST OF is a later milestone (M4: DAList gathering)"
  Cons {}     -> LFFatal "list cons — LIST OF is a later milestone (M4)"
  Concat {}   -> LFFatal "string concatenation is not supported in v1"
  AsString {} -> LFFatal "string coercion is not supported in v1"
  AppNamed {} -> LFFatal "named-argument application is not supported in v1"
  Where {}    -> LFFatal "WHERE in expression position — WHERE is supported at the top of a definition body (R3), not nested inside an expression (v1)"
  LetIn {}    -> LFFatal "LET in expression position — supported at the top of a definition body only (v1)"
  _           -> LFFatal "unsupported construct for docassemble"

-- ---------------------------------------------------------------------------
-- Package hygiene: block ids and name collisions (R9)
-- ---------------------------------------------------------------------------

blockId :: DABlock -> Maybe Text
blockId = \case
  DAObjectsBlock _  -> Just "objects_main"
  DAQuestionBlock q -> Just q.qId
  DACodeBlock c     -> Just c.cId
  DADriverBlock d   -> Just (driverId d)
  DAScreenBlock s   -> Just s.sId

driverId :: DADriver -> Text
driverId = \case
  DASeamDriver i _ _ _ _ _ _ _ -> i
  DABoolDriver i _ _ _ _       -> i
  DAValueDriver i _ _ _        -> i

-- | The same question or code block reached from two exports (a shared
-- parameter) is emitted once; two /different/ blocks claiming one id is an
-- internal error surfaced rather than silently shadowed.
dedupById :: [DABlock] -> Either [LowerError] [DABlock]
dedupById = go Map.empty
 where
  go _ [] = Right []
  go seen (b : bs) = case blockId b of
    Just bid
      | Just prev <- Map.lookup bid seen ->
          if prev == b
            then go seen bs
            else Left [MkLowerError "" ("internal id collision: two different blocks share id `" <> bid <> "`")]
      | otherwise -> (b :) <$> go (Map.insert bid b seen) bs
    Nothing -> (b :) <$> go seen bs

-- | Docassemble variable names are a single global namespace: distinct L4
-- definitions that sanitise to the same name — or one name defined both by a
-- question and by a code block — would silently conflate (the OpenFisca
-- 'checkCollisions' discipline).
checkNameCollisions :: [DABlock] -> Either [LowerError] ()
checkNameCollisions blocks =
  case bad of
    []      -> Right ()
    (e : _) -> Left [e]
 where
  entries = concatMap entryOf blocks
  entryOf = \case
    DAQuestionBlock q -> [(q.qVar, ("question", q.qLabel))]
    DACodeBlock c     -> [(c.cVar, ("code", fromMaybe c.cVar c.cL4))]
    DAScreenBlock s   -> [(s.sEvent, ("event", s.sEvent))]
    DAObjectsBlock es -> [ (v, ("object", v)) | (v, _) <- es ]
    DADriverBlock d   -> case d of
      DASeamDriver _ _ _ _ verdictV _ _ _ -> [(verdictV, ("code", verdictV))]
      _                                   -> []
  byName = Map.fromListWith (<>) [ (v, [meta]) | (v, meta) <- entries ]
  bad =
    [ MkLowerError ""
        ( "name collision: `" <> v <> "` is produced by "
            <> Text.intercalate " and "
                 (nubOrd [ role <> " (L4 `" <> l4 <> "`)" | (role, l4) <- metas ])
            <> " — distinct definitions sharing one docassemble variable are unsafe; rename one" )
    | (v, metas) <- Map.toList byName
    , length (nubOrd metas) > 1
    ]

-- ---------------------------------------------------------------------------
-- Names
-- ---------------------------------------------------------------------------

decideName :: Decide Resolved -> Resolved
decideName (MkDecide _ _ (MkAppForm _ r _ _) _) = r

givenName :: OptionallyTypedName Resolved -> Resolved
givenName (MkOptionallyTypedName _ r _ _) = r

resolvedToText :: Resolved -> Text
resolvedToText = rawNameToText . rawName . getActual

-- | A stable provenance string: the source file's basename.
moduleSource :: Module Resolved -> Text
moduleSource (MkModule _ uri _) =
  let t = getUri (fromNormalizedUri uri)
  in case reverse (Text.splitOn "/" t) of
       (base : _) | not (Text.null base) -> base
       _                                 -> t

moduleTitleOf :: Module Resolved -> Text
moduleTitleOf mod' =
  let base = moduleSource mod'
  in fromMaybe base (Text.stripSuffix ".l4" base)

-- | Sanitise an L4 name into a snake_case interview variable. Total and
-- deterministic (the OpenFisca @pyIdent@ discipline) so definitions and
-- references stay in sync; collision-checked afterwards.
pyIdent :: Text -> Text
pyIdent raw =
  let cleaned = Text.map (\c -> if isIdentChar c then toLower c else ' ') raw
      parts   = Text.words cleaned
      joined  = Text.intercalate "_" parts
  in keywordSafe (ensureNonDigit (if Text.null joined then "v" else joined))
 where
  isIdentChar c = isAlphaNum c || c == '_'
  ensureNonDigit t = case Text.uncons t of
    Just (h, _) | isDigit h -> "v_" <> t
    _                       -> t
  keywordSafe t
    | t `Set.member` pyReserved = t <> "_"
    | otherwise                 = t

-- | Python keywords plus docassemble's own reserved interview names (@x@,
-- @i@, @j@, @k@ are claimed by generic-object and iterator machinery; the
-- rest are special interview variables) — a sanitised L4 name must shadow
-- none of them, so such names get a @_@ suffix.
--
-- The last group is M2's: the generated @l4runtime.py@ is loaded through
-- @modules: [.l4runtime]@, which docassemble execs as
-- @from \<pkg\>.l4runtime import *@ (@parse.py:8572@ at @1b6678384@), binding
-- every name in that module's 'runtimeExports' into the interview dict on
-- /every assemble pass/. An @__all__@ bounds which names are imported; it does
-- nothing to stop an interview variable from BEING one of them. Without this
-- group an @\@export@ spelled @L4 source text@ lowered to a goal variable
-- @l4_source_text@ that the star-import then clobbered with a function object
-- — truthy, so the packaged artifact asked no question at all and returned the
-- opposite verdict to the bare one, breaking the invariant (R11 decision 6)
-- that the two artifact shapes must mean the same thing, while the fidelity
-- report said @(nothing lost)@. The names are taken from 'runtimeExports' so
-- the two modules cannot drift apart, filtered to the ones 'pyIdent' can
-- actually produce (it lower-cases, and Python is case-sensitive). Reserving
-- them for the bare artifact too is deliberate: the two shapes must not
-- disagree about a variable's name either.
pyReserved :: Set Text
pyReserved = Set.fromList $
  [ "and","as","assert","async","await","break","class","continue","def","del"
  , "elif","else","except","false","finally","for","from","global","if","import"
  , "in","is","lambda","nonlocal","none","not","or","pass","raise","return","true"
  , "try","while","with","yield","match","case"
  -- docassemble reserved interview names:
  , "x","i","j","k","item","row_item","row_index","url_args","nav","role"
  , "role_needed","user","session","device_local","user_local","session_local"
  , "allow_cron","multi_user","menu_items","speak_text","track_location"
  , "incoming_email","daobject"
  ]
  <> [ n | n <- runtimeExports, Text.toLower n == n ]

-- | Sanitise an L4 record-field name into a @DAObject@ attribute. On top of
-- 'pyIdent', names that land in the DAObject class/instance namespace get a
-- @_@ suffix: normal Python attribute lookup finds the pre-existing (truthy)
-- method or instance attribute, @__getattr__@ never raises, docassemble
-- never backchains to the emitted question, and the method object rides into
-- the expression as @True@ — a silent wrong verdict. @pyReserved@ guards
-- only top-level variable names; attribute positions need this set instead.
attrIdent :: Text -> Text
attrIdent raw =
  let t = pyIdent raw
  in if t `Set.member` daObjectReserved then t <> "_" else t

-- | The @DAObject@ namespace, vendored from docassemble 1.10.7 (checkout
-- @1b6678384@): @dir(DAObject) | vars(DAObject('x'))@, probed 2026-08-16 in
-- this repo's round-trip venv (spec R10). Every entry is an attribute that
-- normal lookup finds on a fresh instance, so a generated attribute may
-- shadow none of them. Local evidence, never a build dep (spec §8.10).
daObjectReserved :: Set Text
daObjectReserved = Set.fromList
  [ "__class__","__delattr__","__dict__","__dir__","__doc__","__eq__"
  , "__format__","__ge__","__getattr__","__getattribute__","__getstate__"
  , "__gt__","__hash__","__init__","__init_subclass__","__le__","__lt__"
  , "__module__","__ne__","__new__","__reduce__","__reduce_ex__","__repr__"
  , "__setattr__","__sizeof__","__str__","__subclasshook__","__weakref__"
  , "_map_info","_mark_as_gathered_recursively","_reset_gathered_recursively"
  , "_set_instance_name_for_function","_set_instance_name_for_method"
  , "_set_instance_name_recursively"
  , "alternative","as_serializable","attr","attrList","attr_name"
  , "attribute_defined","copy_deep","copy_shallow","delattr","did_question"
  , "did_verb","do_question","does_verb","fix_instance_name"
  , "get_peer_relation","get_point_of_view","get_relation","getattr_fresh"
  , "has_nonrandom_instance_name","have_question","init","initializeAttribute"
  , "initialize_attribute","instanceName","invalidate_attr","is_are_you"
  , "is_peer_relation","is_relation","is_user","itself","object_name"
  , "object_possessive","possessive","pronoun","pronoun_objective"
  , "pronoun_or_name","pronoun_possessive","pronoun_subjective"
  , "raise_undefined_attribute_error","reInitializeAttribute"
  , "reinitialize_attribute","set_instance_name","set_peer_relationship"
  , "set_random_instance_name","set_relationship","subjective_pronoun_or_name"
  , "using","were_question","yourself_or_name"
  ]

tshow :: Show a => a -> Text
tshow = Text.pack . show

hardLF :: Text -> Either LF a -> Either LowerError a
hardLF fn = \case
  Left lf -> Left (MkLowerError fn (lfMessage lf))
  Right a -> Right a
