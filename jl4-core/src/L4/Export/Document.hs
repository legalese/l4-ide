-- | Deterministic L4 -> document IR for the "Render" tab.
--
-- Walks a typechecked 'Module' (plus its resolved import dependencies) into a
-- 'Document': a hierarchical, presentation-neutral IR that the TypeScript layer
-- (and the @l4 render@ CLI) renders to HTML, Akoma Ntoso XML and PDF.
--
-- The body of each rule is a recursive 'Clause' tree, so nested
-- @IF/THEN/ELSE@, @CONSIDER@ case-splits, @AND@/@OR@ chains and deontic
-- @PARTY … MUST …@ rules render as an indented outline rather than one
-- run-on sentence.
--
-- Other behaviours: directives are never rendered; unreachable imported
-- material and directive-only test fixtures are dropped (unless
-- 'dropUnused' is off); L4 @SECTION@ nesting is preserved; the document
-- title is taken from the leading section.
module L4.Export.Document
  ( -- * Public IR
    Document (..)
  , DocSection (..)
  , DocGroup (..)
  , Block (..)
  , Clause (..)
  , UnitKind (..)
  , RenderedAs (..)
    -- * Plan
  , ExportPlan (..)
  , PlanModule (..)
  , PlanUnit (..)
    -- * Configuration
  , ExportConfig (..)
  , Disposition (..)
  , defaultExportConfig
  , hiddenImports
  , mixfixHeadingsFromRegistry
    -- * Names
  , spaceCamel
    -- * Entry points
  , buildDocument
  , buildPlan
  ) where

import Base

import qualified Base.Text as Text
import Data.Aeson ((.=))
import qualified Data.Aeson as Aeson
import Data.Char (isAlphaNum, isDigit, isLower, isUpper, toLower, toUpper)
import qualified Data.List as List
import Data.List.Split (chunksOf)
import qualified Data.Map.Strict as Map
import Data.Ratio (denominator, numerator)
import Data.Time (fromGregorianValid)
import qualified Data.Set as Set
import Optics (gplate, toListOf, (%), (^.))

import L4.Annotation (emptyAnno)
import L4.Desugar (carameliseExpr, carameliseNode)
import L4.Export (isExportedDecide)
import L4.Mixfix (MixfixInfo (..), MixfixPatternToken (..))
import L4.Nlg (Linearize, daydateLiteral, markedLinearizer, markFrame, possessiveOf, stripFrameMarks, NlgFnInfo, nlgFnInfo, substituteNlgCallMarked, renderNlgWith, normalizeWs, oxford)
import qualified L4.Nlg as Nlg
import L4.Syntax
import L4.TypeCheck.Types (CheckInfo (..), FunTypeSig (..), MixfixRegistry (..))
import L4.Utils.Ratio (prettyRatio)

-- ----------------------------------------------------------------------------
-- Configuration
-- ----------------------------------------------------------------------------

-- | What the document does with a unit from an imported module.
--
-- 'Hidden' is the one to reach for when a reader unticks an import. The module
-- stays in the dependency list, so a rule that calls it still reads its @\@nlg@
-- sentences and its records still have their fields; only its own text is left
-- out. Taking the module out of the list instead changes how the document's own
-- rules read.
data Disposition = Inline | Reference | Exclude | Hidden
  deriving stock (Eq, Show, Generic)

data ExportConfig = MkExportConfig
  { dropUnused         :: !Bool
  , moduleDispositions :: !(Map.Map NormalizedUri Disposition)
  , unitDispositions   :: !(Map.Map Unique Disposition)
  , mixfixHeadings     :: !(Map.Map Unique Text)
    -- ^ Precomputed prose headings for mixfix functions, keyed by the
    -- function's 'Unique'. Name resolution discards the mixfix pattern, so
    -- these are derived from the typechecker's 'MixfixRegistry' (via
    -- 'mixfixHeadingsFromRegistry') and threaded in by the caller.
  }
  deriving stock (Show, Generic)

defaultExportConfig :: ExportConfig
defaultExportConfig = MkExportConfig
  { dropUnused         = True
  , moduleDispositions = Map.empty
  , unitDispositions   = Map.empty
  , mixfixHeadings     = Map.empty
  }

-- | Hide every imported module but those a caller asks to show, by file name
-- without its extension. A document's own rules read the same either way.
hiddenImports :: (Text -> Bool) -> [Module Resolved] -> Map.Map NormalizedUri Disposition
hiddenImports shown deps = Map.fromList
  [ (uri, Hidden) | MkModule _ uri _ <- deps, not (shown (moduleLabel uri)) ]

-- ----------------------------------------------------------------------------
-- Public IR
-- ----------------------------------------------------------------------------

data UnitKind = RuleUnit | TypeUnit | AssumptionUnit
  deriving stock (Eq, Show, Generic)

data RenderedAs
  = RenderedInline
  | RenderedReference { forced :: !Bool }
  deriving stock (Eq, Show, Generic)

-- | The recursive body of a rule.
data Clause
  = CLeaf Text                                 -- ^ a terminal sentence (prose / formula)
  | CFields [(Text, Text)]                     -- ^ label/value rows (record decl or literal)
  | CAll [Clause]                              -- ^ all of the following hold (AND)
  | CAny [Clause]                              -- ^ any of the following holds (OR)
  | CIf [(Text, Clause)] (Maybe Clause)        -- ^ if c1 then …; else if c2 …; else …
  | CCases Text [(Text, Clause)]               -- ^ consider <subject>: when <pattern> -> …
  | CDeontic Text Text Text                    -- ^ party, modal, action
             (Maybe Text)                      -- ^ deadline
             (Maybe Clause)                    -- ^ provided-that
             (Maybe Clause)                    -- ^ hence (on compliance)
             (Maybe Clause)                    -- ^ lest (on breach)
  | CChain Text [Text]                         -- ^ a long arithmetic chain
                                               --   (sum/product/…): a lead-in
                                               --   ("the sum of the following")
                                               --   and one pre-rendered line per
                                               --   operand
  | CTable [Text] [[Clause]]                   -- ^ a list of same-typed records:
                                               --   column headings + rows of cells
  | CWhere Clause [(Text, Text, Clause)]       -- ^ a rule body, plus its local
                                               --   WHERE / LET definitions, each a
                                               --   (heading, connector, body) triple
  | CLed Text Clause                           -- ^ a list, led by these words
  | CLeadIn Text Clause                        -- ^ a list, led by the provision's
                                               --   own words, which replace the
                                               --   rule's connector
  | CLabel Text Clause                         -- ^ a list entry with the label the
                                               --   provision gives it
  deriving stock (Show, Generic)

data Block = MkBlock
  { blockId           :: !Text
  , blockKind         :: !UnitKind
  , blockHeading      :: !Text
  , blockSentence     :: !(Maybe Text)
    -- ^ The rule's @\@nlg@ sentence, read in place of the heading. The heading
    -- stays the rule's name, which is what a reference to it links by.
  , blockConnector    :: !Text        -- ^ "means", "holds if", "provides that", "equals"
  , blockBody         :: !Clause
  , blockRenderedAs   :: !RenderedAs
  , blockCitation     :: !(Maybe Text)
  , blockSources      :: ![Text]      -- ^ the rule's @\@ref@ citations
  , blockIsData       :: !Bool        -- ^ a constant, with no inputs and no logic
  , blockSourceModule :: !Text
  , blockImported     :: !Bool
  }
  deriving stock (Show, Generic)

data DocGroup = MkDocGroup
  { groupLabel  :: !(Maybe Text)
  , groupLead   :: !(Maybe Text)   -- ^ words that open the group
  , groupBlocks :: ![Block]
  }
  deriving stock (Show, Generic)

data DocSection = MkDocSection
  { sectionNumber  :: !Text
  , sectionHeading :: !(Maybe Text)
  , sectionGroups  :: ![DocGroup]
  , sectionSubs    :: ![DocSection]
  }
  deriving stock (Show, Generic)

data Document = MkDocument
  { docTitle    :: !Text
  , docSections :: ![DocSection]
  }
  deriving stock (Show, Generic)

-- ----------------------------------------------------------------------------
-- Plan IR
-- ----------------------------------------------------------------------------

data PlanUnit = MkPlanUnit
  { planId        :: !Text
  , planKind      :: !UnitKind
  , planHeading   :: !Text
  , planReachable :: !Bool
  , planDefault   :: !Disposition
  }
  deriving stock (Show, Generic)

data PlanModule = MkPlanModule
  { planModuleUri    :: !Text
  , planModuleLabel  :: !Text
  , planModuleIsMain :: !Bool
  , planUnits        :: ![PlanUnit]
  }
  deriving stock (Show, Generic)

data ExportPlan = MkExportPlan
  { planMainModule :: !Text
  , planModules    :: ![PlanModule]
  }
  deriving stock (Show, Generic)

-- ----------------------------------------------------------------------------
-- Internal: renderable units
-- ----------------------------------------------------------------------------

data UnitDecl
  = UDecide  (Decide Resolved)
  | UDeclare (Declare Resolved)
  | UAssume  (Assume Resolved)

data Unit = MkUnit
  { uPrimary :: !Unique
  , uModule  :: !NormalizedUri
  , uKind    :: !UnitKind
  , uHeading :: !Text
  , uDefs    :: !(Set.Set Unique)
  , uRefs    :: !(Set.Set Unique)
  , uDecl    :: !UnitDecl
  , uTopAnno :: !Anno
    -- ^ The declaration's outer annotation: a @\@ref@ written above a rule lands
    -- here, the first node it reaches, and not on the rule.
  , uCalls   :: !(Set.Set Unique)
    -- ^ The head of every rule that has a herald: a named-argument call to one of
    -- these is a call, not a record construction ('decideRendering'). Empty until
    -- 'allUnits' fills it.
  , uReading :: !Reading
    -- ^ What phrasing this unit's body needs to know of the rest of the document.
    -- Empty until 'allUnits' fills it.
  }

-- | What a rule's body is read against: the other rules and records of the
-- document.
--
-- This is what is known of them from their definitions, by type and by shape.
-- A rendering rule never looks for a verb or an adjective in a name to decide how
-- to read it: a name is the author's, and an author who wants other words for it
-- writes them as an @\@nlg@.
data Reading = MkReading
  { rdHeralds    :: !NlgFnInfo
  , rdRules      :: !(Map.Map Unique Bool)
    -- ^ Every rule, and whether it gives a BOOLEAN.
  , rdBoolFields :: !(Set.Set Unique)
  , rdBlanks     :: !(Set.Set Text)
    -- ^ How this rule's own inputs of a built-in type read, so that one in a slot
    -- of a pattern can read as a blank.
  }

noReading :: Reading
noReading = MkReading Map.empty Map.empty Set.empty Set.empty

extractUnits :: Module Resolved -> [Unit]
extractUnits (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ decls) = concatMap goDecl decls
  goDecl :: TopDecl Resolved -> [Unit]
  goDecl = \case
    Decide ann d  -> [mkUnit ann RuleUnit (decideApp d) (UDecide d)]
    Declare ann d -> [mkUnit ann TypeUnit (declareApp d) (UDeclare d)]
    Assume ann a  -> [mkUnit ann AssumptionUnit (assumeApp a) (UAssume a)]
    Section _ s -> goSection s
    Directive{} -> []
    Import{}    -> []
    Timezone{}  -> []
  mkUnit ann kind appHead decl =
    MkUnit
      { uPrimary = getUnique appHead
      , uModule  = (getUnique appHead).moduleUri
      , uKind    = kind
      , uHeading = resolvedText appHead
      , uDefs    = definedIn decl
      , uRefs    = referencedIn decl
      , uDecl    = decl
      , uTopAnno = ann
      , uCalls   = Set.empty
      , uReading = noReading
      }

-- | All renderable units across the open module and its dependencies, with
-- mixfix headings fixed up and @\@nlg@ calls expanded.
allUnits :: Map.Map Unique Text -> Module Resolved -> [Module Resolved] -> [Unit]
allUnits headings mainModule deps =
  let mods  = mainModule : deps
      info  = nlgFnInfo mods
      ctors = recordCtorFields mods
      -- Told apart from a record's constructor by what the head resolved to, not
      -- by its name: a record can be named like a rule that has a herald.
      calls = Map.keysSet info
      reading = MkReading info (ruleResults mods) (booleanFields mods) Set.empty
  in map (\u -> (mapUnitBody (normalizePositionalRecords ctors) . fixMixfixHeading headings $ u)
                  { uCalls = calls, uReading = reading })
       (extractUnits mainModule <> concatMap extractUnits deps)

-- | Every rule and whether it gives a BOOLEAN, keyed by the definition a call
-- resolves to.
ruleResults :: [Module Resolved] -> Map.Map Unique Bool
ruleResults mods = Map.fromList
  [ (getUnique n, returnsBoolean tysig)
  | m <- mods
  , Decide _ (MkDecide _ tysig (MkAppForm _ n _ _) _) <- topDeclsRec m
  ]

-- | The record fields of type BOOLEAN. Such a field states something about its
-- record, so a possessive is always the wrong way to read it.
booleanFields :: [Module Resolved] -> Set.Set Unique
booleanFields mods = Set.fromList
  [ getUnique n
  | m <- mods
  , Declare _ (MkDeclare _ _ _ (RecordDecl _ _ fields)) <- topDeclsRec m
  , MkTypedName _ n ty _ <- fields
  , typeNameText ty == "BOOLEAN"
  ]

-- | Apply a transform to a unit's DECIDE body (a no-op for other units).
mapUnitBody :: (Expr Resolved -> Expr Resolved) -> Unit -> Unit
mapUnitBody f u = case u.uDecl of
  UDecide (MkDecide a t af body) -> u { uDecl = UDecide (MkDecide a t af (f body)) }
  _ -> u

-- | The field-name references of each record, keyed by the 'Unique' of its
-- constructor, so a positional construction (@Bullet "A" "B"@) can be matched up
-- with its fields.
-- Keyed by the constructor and not by a name: a function can be named like a
-- record (the prelude's @range@ beside a record @range@), and a call to it is not
-- a construction. The constructor is not the declaring type name, which has a
-- 'Unique' of its own; the type checker records it in the 'RecordDecl'.
recordCtorFields :: [Module Resolved] -> Map.Map Unique [Resolved]
recordCtorFields mods = Map.fromList
  [ (getUnique con, [ n | MkTypedName _ n _ _ <- fields ])
  | m <- mods
  , Declare _ (MkDeclare _ _ _ (RecordDecl _ (Just con) fields)) <- topDeclsRec m
  ]

-- | All top-level declarations of a module, descending through @SECTION@s.
topDeclsRec :: Module Resolved -> [TopDecl Resolved]
topDeclsRec (MkModule _ _ sec) = go sec
 where
  go (MkSection _ _ _ ds) = concatMap (\d -> d : nested d) ds
  nested = \case Section _ s -> go s; _ -> []

-- | Rewrite a positional record construction (@App ctor [a, b]@) into the named
-- form (@AppNamed ctor [field IS a, …]@), so the table and record renderers —
-- which key off field names — recognise it the same as a @WITH@ literal.
normalizePositionalRecords :: Map.Map Unique [Resolved] -> Expr Resolved -> Expr Resolved
normalizePositionalRecords ctorFields
  | Map.null ctorFields = id
  | otherwise = transformOf (gplate @(Expr Resolved)) $ \case
      App ann ctor args
        | Just fnames <- Map.lookup (getUnique ctor) ctorFields
        , length fnames == length args ->
            AppNamed ann ctor [ MkNamedExpr ann f a | (f, a) <- zip fnames args ] Nothing
      e -> e

-- | The @\@nlg@ annotation attached to a DECIDE, wherever it landed.
--
-- One line now, because the search itself moved to 'L4.Nlg.decideNlg' — this
-- module and @l4 nlg@ had different answers for the same bytes, because the
-- list of positions to search was kept by hand in each place
-- (smucclaw\/l4-ide#972). The enclosing 'TopDecl'\'s annotation is not
-- available here, hence the 'Nothing'.
decideNlg :: Decide Resolved -> Maybe Nlg
decideNlg = Nlg.decideNlg Nothing

-- | Replace a mixfix function's heading with its precomputed prose form
-- (e.g. "a Person buyer may trade with a Person seller"). The map is keyed by
-- the function's 'Unique'; non-mixfix and absent units are left untouched.
fixMixfixHeading :: Map.Map Unique Text -> Unit -> Unit
fixMixfixHeading headings u = case Map.lookup u.uPrimary headings of
  Just h  -> u { uHeading = h }
  Nothing -> u

-- | Build the prose headings for every mixfix function in a typechecked
-- 'MixfixRegistry', keyed by the function's 'Unique'. Name resolution discards
-- the mixfix pattern from the AST the renderer sees, but the registry retains
-- it (alongside the checked 'TypeSig'), so each parameter slot can be rendered
-- as "a \<Type\> \<name\>" interleaved with the keyword segments — in the order
-- the author wrote them. Works for functions that are never referenced.
mixfixHeadingsFromRegistry :: MixfixRegistry -> Map.Map Unique Text
mixfixHeadingsFromRegistry reg = Map.fromList
  [ (getUnique nm, heading)
  | fts <- concat (Map.elems reg.byCanonicalName)
  , Just info <- [fts.mixfixInfo]
  , let heading = mixfixHeadingText fts.rtysig info
  , nm <- fts.name.names
  ]

-- | Interleave a mixfix pattern's keyword segments with its parameter slots,
-- each slot rendered as "a \<Type\> \<name\>" using the GIVEN type.
mixfixHeadingText :: TypeSig Resolved -> MixfixInfo -> Text
mixfixHeadingText tysig info =
  let slots = slotPhrases tysig
      tok (MixfixKeyword kw) = rawNameToText kw
      tok (MixfixParam p)    =
        let pn = rawNameToText p
        in Map.findWithDefault (blank pn) pn slots
  in normalizeWs (Text.unwords (map tok info.pattern))

-- | An input in a slot of a pattern, by what it is. One of a user's types reads as
-- the rule's body calls it. Any other is a blank to fill, in brackets, because
-- beside the words of the pattern its name reads as more of those words.
slotPhrases :: TypeSig Resolved -> Map.Map Text Text
slotPhrases sig = Map.fromList [ (resolvedText r, p) | (r, p) <- inputSlots sig ]

-- | The same, for the slots of a rule's own sentence, which go by the input.
sentenceSlots :: TypeSig Resolved -> Map.Map Unique (Expr Resolved)
sentenceSlots sig = Map.fromList
  [ (getUnique r, Inert emptyAnno p InertCtxNone) | (r, p) <- inputSlots sig ]

inputSlots :: TypeSig Resolved -> [(Resolved, Text)]
inputSlots sig@(MkTypeSig _ (MkGivenSig _ names) _) =
  [ (r, phrase)
  | MkOptionallyTypedName _ r mty <- names
  , let phrase = case (mty >>= userTypeName, Map.lookup (getUnique r) (paramSubst sig)) of
          (Just _, Just p) -> p
          _                -> blank (resolvedText r)
  ]

blank :: Text -> Text
blank t = "[" <> spaceCamel (cleanParam t) <> "]"

-- | "a Person", "an Award Participant".
withArticle :: Text -> Text
withArticle t = case Text.uncons t of
  Just (c, _) | toLower c `elem` ['a', 'e', 'i', 'o', 'u'] -> "an " <> t
  _                                                        -> "a " <> t

decideApp :: Decide Resolved -> Resolved
decideApp (MkDecide _ _ (MkAppForm _ n _ _) _) = n

declareApp :: Declare Resolved -> Resolved
declareApp (MkDeclare _ _ (MkAppForm _ n _ _) _) = n

assumeApp :: Assume Resolved -> Resolved
assumeApp (MkAssume _ _ (MkAppForm _ n _ _) _) = n

definedIn :: UnitDecl -> Set.Set Unique
definedIn = collectUniques (\case Def{} -> True; _ -> False)

referencedIn :: UnitDecl -> Set.Set Unique
referencedIn = collectUniques (\case Def{} -> False; _ -> True)

collectUniques :: (Resolved -> Bool) -> UnitDecl -> Set.Set Unique
collectUniques keep ud =
  Set.fromList [ getUnique r | r <- resolveds, keep r ]
 where
  resolveds = case ud of
    UDecide d  -> toList d
    UDeclare d -> toList d
    UAssume a  -> toList a

-- ----------------------------------------------------------------------------
-- Reachability
-- ----------------------------------------------------------------------------

data UnitGraph = MkUnitGraph
  { ugUnits :: !(Map.Map Int Unit)
  , ugEdges :: !(Map.Map Int (Set.Set Int))
  , ugMain  :: !(Set.Set Int)
  }

buildGraph :: NormalizedUri -> [Unit] -> UnitGraph
buildGraph mainUri units =
  MkUnitGraph
    { ugUnits = Map.fromList indexed
    , ugEdges = Map.fromList [ (i, depIndices u) | (i, u) <- indexed ]
    , ugMain  = Set.fromList [ i | (i, u) <- indexed, u.uModule == mainUri ]
    }
 where
  indexed = zip [0 ..] units
  owner = Map.fromList [ (u', i) | (i, u) <- indexed, u' <- Set.toList u.uDefs ]
  depIndices u = Set.fromList [ j | r <- Set.toList u.uRefs, Just j <- [Map.lookup r owner] ]

closure :: Map.Map Int (Set.Set Int) -> Set.Set Int -> Set.Set Int
closure edges = go Set.empty
 where
  go seen frontier
    | Set.null frontier = seen
    | otherwise =
        let seen'     = Set.union seen frontier
            next      = Set.unions [ Map.findWithDefault Set.empty i edges | i <- Set.toList frontier ]
            frontier' = next Set.\\ seen'
        in go seen' frontier'

reachableUnits :: UnitGraph -> Set.Set Int
reachableUnits g = closure g.ugEdges g.ugMain

-- | A define-before-use rank: a unit's transitive-dependency count. In a DAG a
-- dependency always has a strictly smaller count than its dependents, so
-- sorting by this yields a valid topological order.
rankByBlockId :: UnitGraph -> Map.Map Text Int
rankByBlockId g =
  Map.fromList
    [ (uniqueId u.uPrimary, Set.size (closure g.ugEdges (Set.singleton i)))
    | (i, u) <- Map.toList g.ugUnits ]

resolveDisposition :: ExportConfig -> Unit -> Disposition
resolveDisposition cfg u =
  case Map.lookup u.uPrimary cfg.unitDispositions of
    Just d  -> d
    Nothing -> Map.findWithDefault Inline u.uModule cfg.moduleDispositions

-- ----------------------------------------------------------------------------
-- Document construction
-- ----------------------------------------------------------------------------

buildDocument :: ExportConfig -> Module Resolved -> [Module Resolved] -> Document
buildDocument cfg mainModule deps =
  MkDocument
    { docTitle    = title
    -- Number after pruning, so dropped (e.g. test-fixture) sections never
    -- consume a number — numbering always starts at § 1 and stays contiguous.
    , docSections = renumberSections "" (ownSections <> importedSections <> schedules)
    }
 where
  (title, bodySection) = documentTitleAndBody mainModule
  mainUri = moduleUri' mainModule
  units   = allUnits cfg.mixfixHeadings mainModule deps
  graph   = buildGraph mainUri units
  reach   = reachableUnits graph
  ranks   = rankByBlockId graph
  rankOf b = Map.findWithDefault 0 b.blockId ranks
  indexed = Map.toList graph.ugUnits
  isMain i = Set.member i graph.ugMain
  kept i = isMain i || not cfg.dropUnused || Set.member i reach

  inlineSeeds =
    Set.union graph.ugMain $
      Set.fromList
        [ i | (i, u) <- indexed, not (isMain i), kept i, resolveDisposition cfg u == Inline ]
  required = closure graph.ugEdges inlineSeeds

  dirRefs = Set.unions (map directiveRefsOf (mainModule : deps))
  -- Everything reachable, through the dependency graph, from a unit that is not
  -- itself a bare instance value — i.e. the operative rules and every
  -- definition they actually use. A value object that falls outside this
  -- closure is referenced only by directives (and other such objects).
  operativeClosure = closure graph.ugEdges
    (Set.fromList [ i | (i, u) <- indexed, not (isInstanceValueUnit u) ])

  isFixture i u =
       cfg.dropUnused && isMain i
    && not (Set.disjoint u.uDefs dirRefs)
    && not (Set.member i operativeClosure)
    && isInstanceValueUnit u
    && not (isExportUnit u)

  renderUnit i u
    | isMain i =
        if isFixture i u || isComputedSelector u
          then Nothing
          else Just (inlineBlock False u)
    | not (kept i) = Nothing
    | otherwise =
        case resolveDisposition cfg u of
          Inline    -> Just (inlineBlock True u)
          Reference -> Just (referenceBlock False u)
          Exclude
            | Set.member i required -> Just (referenceBlock True u)
            | otherwise             -> Nothing
          Hidden -> Nothing

  blockByUnique :: Map.Map Unique Block
  blockByUnique = Map.fromList [ (u.uPrimary, b) | (i, u) <- indexed, Just b <- [renderUnit i u] ]

  -- The open document's own material. A flat module (no SECTION markers) still
  -- gets proper numbered sections: its definitions, assumptions and operative
  -- rules each become a top-level section ("§ 1 Definitions", "§ 2 Provisions",
  -- …) so they appear in the table of contents under a heading, rather than as
  -- unlabelled prose under the title.
  mainSections = mapMaybe pruneSection (bodyToSections rankOf blockByUnique bodySection)
  (ownSections, schedules) = withSchedules mainSections

  -- An imported module that carries its own section title renders directly as a
  -- top-level section (its own heading). Imports with no section title of their
  -- own — only a file name to go by — are collected under a single "Imported
  -- definitions" appendix, so that generic header appears only when it is
  -- actually needed to label otherwise-untitled material.
  modByUri = Map.fromList [ (moduleUri' md, md) | md <- mainModule : deps ]
  importedRendered =
    [ (importHasSectionTitle md, s)
    | uri <- importedModuleOrder
    , Just md <- [Map.lookup uri modByUri]
    , Just s  <- [pruneSection (buildImportSection rankOf blockByUnique uri md)]
    ]
  importedSections =
    [ s | (True, s) <- importedRendered ]
    <> case [ s | (False, s) <- importedRendered ] of
         []   -> []
         secs -> [ MkDocSection
                     { sectionNumber  = ""
                     , sectionHeading = Just (fw "Imported definitions")
                     , sectionGroups  = []
                     , sectionSubs    = secs
                     } ]
  importedModuleOrder = List.nub [ u.uModule | (i, u) <- indexed, not (isMain i) ]

-- | Build one section subtree, leaving 'sectionNumber' blank — numbering is a
-- separate post-pass ('renumberSections') run after empty sections are pruned.
toDocSection :: (Block -> Int) -> Map.Map Unique Block -> Section Resolved -> DocSection
toDocSection rankOf bmap (MkSection _ mName _ decls) =
  MkDocSection
    { sectionNumber  = ""
    , sectionHeading = fmap resolvedText mName
    , sectionGroups  = unlabelledIfAlone (groupByKind rankOf (orderedBlocks bmap decls))
    , sectionSubs    = [ toDocSection rankOf bmap s | Section _ s <- decls ]
    }

-- | A section's heading already frames its only group; a label would only repeat
-- it, as "Definitions:" under a heading with nothing but definitions.
unlabelledIfAlone :: [DocGroup] -> [DocGroup]
unlabelledIfAlone = \case
  [g] -> [g { groupLabel = Nothing }]
  gs  -> gs

-- | Turn the open document's body into top-level sections. Its directly-held
-- definitions / assumptions / rules each become a headed section (so they
-- carry a § number and a TOC entry); any explicit @SECTION@ markers follow as
-- further top-level sections.
bodyToSections :: (Block -> Int) -> Map.Map Unique Block -> Section Resolved -> [DocSection]
bodyToSections rankOf bmap (MkSection _ _ _ decls) =
  let groups = groupByKind rankOf (orderedBlocks bmap decls)
      (front, rules) = List.partition (\g -> g.groupLabel /= Just "Provisions" && isJust g.groupLabel) groups
      interpretation =
        [ MkDocSection
            { sectionNumber  = ""
            , sectionHeading = Just (fw "Interpretation")
            , sectionGroups  = map interpretationGroup front
            , sectionSubs    = []
            }
        | not (null front) ]
      groupSecs =
        [ MkDocSection
            { sectionNumber  = ""
            , sectionHeading = Just (fw (groupSectionHeading g))
            , sectionGroups  = [ g { groupLabel = Nothing } ]
            , sectionSubs    = []
            }
        | g <- rules ]
      subSecs = [ toDocSection rankOf bmap s | Section _ s <- decls ]
  in interpretation <> groupSecs <> subSecs
 where
  interpretationGroup g = g
    { groupLabel = Nothing
    , groupLead  = Just (fromMaybe "In this document, unless the context otherwise requires:" g.groupLead)
    }

-- | Section heading for a promoted body group: the group's own label, or
-- "Provisions" for the (unlabelled) operative-rules group.
groupSectionHeading :: DocGroup -> Text
groupSectionHeading g = fromMaybe "Provisions" g.groupLabel

orderedBlocks :: Map.Map Unique Block -> [TopDecl Resolved] -> [Block]
orderedBlocks bmap decls =
  [ b | td <- decls, Just u <- [primaryOfTopDecl td], Just b <- [Map.lookup u bmap] ]

primaryOfTopDecl :: TopDecl Resolved -> Maybe Unique
primaryOfTopDecl = \case
  Decide _ d  -> Just (getUnique (decideApp d))
  Declare _ d -> Just (getUnique (declareApp d))
  Assume _ a  -> Just (getUnique (assumeApp a))
  _           -> Nothing

-- | Assign contiguous section numbers top-down: "1", "2", … at the top level
-- and "1.1", "1.2", … within. Run after 'pruneSection' so dropped sections
-- leave no gaps.
renumberSections :: Text -> [DocSection] -> [DocSection]
renumberSections parent secs =
  [ s { sectionNumber = num, sectionSubs = renumberSections num s.sectionSubs }
  | (i, s) <- zip [(1 :: Int) ..] secs
  , let num = childNumber parent i
  ]

childNumber :: Text -> Int -> Text
childNumber parent i
  | Text.null parent = Text.pack (show i)
  | otherwise        = parent <> "." <> Text.pack (show i)

-- | Group into /Definitions/ (types, sorted define-before-use), /Assumptions/,
-- then operative rules. Empty groups are dropped.
--
-- The operative-rules group is normally unlabelled — when it is the section's
-- only material the section heading already frames it. But when it shares a
-- section with labelled Definitions/Assumptions groups it would otherwise
-- render as a second, header-less clause list whose numbering restarts at 1
-- (two "1." items with nothing between them). In that case we give it a
-- "Provisions" heading so each numbered list sits under its own label.
groupByKind :: (Block -> Int) -> [Block] -> [DocGroup]
groupByKind rankOf blocks =
  case groups of
    (_ : _ : _) -> map labelRules groups
    _           -> groups
 where
  groups =
    [ MkDocGroup { groupLabel = lbl, groupLead = lead, groupBlocks = bs }
    | (lbl, lead, k, sortIt) <-
        [ (Just "Definitions", Nothing, TypeUnit, True)
        , (Just "Assumptions", Just "The following are taken as given:", AssumptionUnit, False)
        , (Nothing, Nothing, RuleUnit, False)
        ]
    , let raw = filter (\b -> b.blockKind == k) blocks
          bs  = if sortIt then List.sortOn rankOf raw else raw
    , not (null bs)
    ]
  labelRules g = case g.groupLabel of
    Nothing -> g { groupLabel = Just "Provisions" }
    Just _  -> g

-- | Move a document's long tables of constant data to numbered Schedules at its
-- end, as an instrument prints them, and have each use of one say which Schedule
-- it is. The rules read better without the data in the way, and the data is still
-- there, whole.
withSchedules :: [DocSection] -> ([DocSection], [DocSection])
withSchedules secs =
  ( mapMaybe (pruneSection . referring . withoutData) secs
  , zipWith schedule [1 ..] tables )
 where
  tables = concatMap sectionTables secs
  sectionTables s = filter isSchedule (concatMap (.groupBlocks) s.sectionGroups) <> concatMap sectionTables s.sectionSubs
  isSchedule b = b.blockIsData && case b.blockBody of
    CTable{}                               -> True
    CChain "a list of the following" items -> length items >= arithChainMinTerms
    _                                      -> False
  withoutData s = s
    { sectionGroups = filter (not . null . (.groupBlocks))
        [ g { groupBlocks = filter (not . isSchedule) g.groupBlocks } | g <- s.sectionGroups ]
    , sectionSubs = map withoutData s.sectionSubs
    }
  references = zip (map (.blockHeading) tables) [1 :: Int ..]
  refer t = List.foldl' (\acc (h, i) -> Text.replace ("`" <> h <> "`") ("`" <> h <> "` (" <> fw "Schedule" <> " " <> showInt (fromIntegral i) <> ")") acc) t references
  referring s = s
    { sectionGroups = [ g { groupBlocks = [ b { blockBody = overClauseText refer b.blockBody } | b <- g.groupBlocks ] } | g <- s.sectionGroups ]
    , sectionSubs = map referring s.sectionSubs
    }
  schedule :: Integer -> Block -> DocSection
  schedule i b = MkDocSection
    { sectionNumber  = ""
    , sectionHeading = Just (fw "Schedule" <> " " <> showInt i <> ": " <> capitalised (spaceCamel b.blockHeading))
    , sectionGroups  = [ MkDocGroup { groupLabel = Nothing, groupLead = Nothing, groupBlocks = [b] } ]
    , sectionSubs    = []
    }
  capitalised t = maybe t (\(c, r) -> Text.cons (toUpper c) r) (Text.uncons t)

-- | Apply a change to every piece of a clause's text.
overClauseText :: (Text -> Text) -> Clause -> Clause
overClauseText f = go
 where
  go = \case
    CLeaf t -> CLeaf (f t)
    CFields fs -> CFields [ (k, f v) | (k, v) <- fs ]
    CAll cs -> CAll (map go cs)
    CAny cs -> CAny (map go cs)
    CIf chain els -> CIf [ (f c, go t) | (c, t) <- chain ] (fmap go els)
    CCases s brs -> CCases (f s) [ (p, go c) | (p, c) <- brs ]
    CDeontic p m a due prov h l -> CDeontic (f p) m (f a) (fmap f due) (fmap go prov) (fmap go h) (fmap go l)
    CChain lead items -> CChain lead (map f items)
    CTable cols rows -> CTable cols (map (map go) rows)
    CWhere body defs -> CWhere (go body) [ (h, c, go cl) | (h, c, cl) <- defs ]
    CLed lead body -> CLed (f lead) (go body)
    CLeadIn lead body -> CLeadIn lead (go body)
    CLabel label body -> CLabel label (go body)

pruneSection :: DocSection -> Maybe DocSection
pruneSection s =
  let subs' = mapMaybe pruneSection s.sectionSubs
  in if null s.sectionGroups && null subs'
       then Nothing
       else Just s { sectionSubs = subs' }

directiveRefsOf :: Module Resolved -> Set.Set Unique
directiveRefsOf (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ decls) = Set.unions (map goDecl decls)
  goDecl = \case
    Directive _ d -> Set.fromList (map getUnique (toList d))
    Section _ s   -> goSection s
    _             -> Set.empty

-- | A parameterless definition whose body is constant /data/ — a record or
-- list literal, a constructor application (e.g. @Date 15 5 2025@), or a bare
-- literal — as opposed to an operative rule (which has parameters or a body
-- with control flow / logic). Such units are the only ones eligible to be
-- dropped as directive-only fixtures.
isInstanceValueUnit :: Unit -> Bool
isInstanceValueUnit u = case u.uDecl of
  UDecide (MkDecide _ (MkTypeSig _ (MkGivenSig _ params) _) _ body)
    | null params -> case carameliseNode body of
        AppNamed{} -> True
        List{}     -> True
        App{}      -> True   -- a constructor application: Date d m y, an enum case, …
        Lit{}      -> True   -- a bare numeric / string literal
        _          -> False
  _ -> False

isExportUnit :: Unit -> Bool
isExportUnit u = case u.uDecl of
  UDecide d -> isExportedDecide d
  _         -> False

-- | A lifted computed-field selector — its GIVEN parameter is the implicit
-- @_self@. These are shown under their record, not as standalone rules.
isComputedSelector :: Unit -> Bool
isComputedSelector u = case u.uDecl of
  UDecide (MkDecide _ (MkTypeSig _ (MkGivenSig _ params) _) _ _) ->
    any (\(MkOptionallyTypedName _ r _) -> nameToText (getActual r) == "_self") params
  _ -> False

-- ----------------------------------------------------------------------------
-- Block rendering
-- ----------------------------------------------------------------------------

inlineBlock :: Bool -> Unit -> Block
inlineBlock imported u =
  let (connector, body) = unitRendering imported u
  in MkBlock
    { blockId           = uniqueId u.uPrimary
    , blockKind         = u.uKind
    , blockHeading      = u.uHeading
    , blockSentence     = if imported then Nothing else unitSentence u
    , blockConnector    = connector
    , blockBody         = body
    , blockRenderedAs   = RenderedInline
    , blockCitation     = Nothing
    , blockSources      = unitSources u
    , blockIsData       = not imported && isInstanceValueUnit u
    , blockSourceModule = uriText u.uModule
    , blockImported     = imported
    }

referenceBlock :: Bool -> Unit -> Block
referenceBlock isForced u =
  MkBlock
    { blockId           = uniqueId u.uPrimary
    , blockKind         = u.uKind
    , blockHeading      = u.uHeading
    , blockSentence     = Nothing
    , blockConnector    = ""
    , blockBody         = CLeaf ""
    , blockRenderedAs   = RenderedReference isForced
    , blockCitation     = Just ("as defined in " <> moduleLabel u.uModule)
    , blockSources      = []
    , blockIsData       = False
    , blockSourceModule = uriText u.uModule
    , blockImported     = True
    }

-- | An expression as text. The words the linearizer supplies stay marked, so a
-- writer can put them into the document's language.
simpleLinearizer :: Linearize a => a -> Text
simpleLinearizer = markedLinearizer

-- | Words of the rendering's own, as opposed to the author's.
fw :: Text -> Text
fw = markFrame

-- | The sentence a rule reads as, with its own inputs in the slots.
--
-- An @\@nlg@ on a rule adds to the rule: it says what the rule is about, and the
-- body still says how. So "the applicant qualifies for the grant" heads the
-- conditions. Only a rule whose body says nothing to the document's reader is
-- read as the sentence alone ('readsAsItsSentence').
unitSentence :: Unit -> Maybe Text
unitSentence u = case u.uDecl of
  UDecide d@(MkDecide _ tysig (MkAppForm _ n args _) _)
    | not (readsAsItsSentence False u), Just nlg <- decideNlg d ->
        Just (renderNlgWith (sentenceSlots tysig) nlg)
    -- A name that ends in a preposition is waiting for its inputs: "the rate for"
    -- says nothing until it has one. A mixfix heading already has them.
    | not (null args), endsInPreposition n, u.uHeading == resolvedText n ->
        Just (u.uHeading <> " " <> oxford (fw "and") (map (inputSlot tysig) args))
  _ -> Nothing
 where
  inputSlot sig a = Map.findWithDefault (blank (resolvedText a)) (resolvedText a) (slotPhrases sig)

-- | A rule whose body would not help a reader, so that its sentence stands in for
-- it: one imported from a library, and one defined by recursion, whose @CONSIDER@
-- is how a list is walked, not what the rule means. @filter@ reads "the items of
-- list for which f holds".
readsAsItsSentence :: Bool -> Unit -> Bool
readsAsItsSentence imported u = imported || Set.member u.uPrimary u.uRefs

-- | The rule's citations, wherever its @\@ref@ annotations landed: above the rule
-- on the declaration, or below the signature on the head. A @\@ref@ on an input
-- or a field cites that input or field, and is not the rule's.
unitSources :: Unit -> [Text]
unitSources u = map refCitation (u.uTopAnno ^. annRefs <> own)
 where
  own = case u.uDecl of
    UDecide d@(MkDecide _ _ af _)  -> (d ^. annoOf % annRefs) <> headRefs af
    UDeclare d@(MkDeclare _ _ af _) -> (d ^. annoOf % annRefs) <> headRefs af
    UAssume a@(MkAssume _ _ af _)  -> (a ^. annoOf % annRefs) <> headRefs af
  headRefs af@(MkAppForm _ n _ _) = (af ^. annoOf % annRefs) <> (getActual n ^. annoOf % annRefs)

unitRendering :: Bool -> Unit -> (Text, Clause)
unitRendering imported u = case u.uDecl of
  UDecide d@(MkDecide _ tysig _ body)
    | Just nlg <- decideNlg d, readsAsItsSentence imported u ->
        ( if returnsBoolean tysig then "if" else "means"
        , CLeaf (renderNlgWith (sentenceSlots tysig) nlg) )
    -- Otherwise rewrite the body up front (mixfix/maths/dates/numbers/params ->
    -- Inert leaves) so formula mode survives arithmetic that contains a mixfix
    -- call or a function like @exp@/@ln@. A top-level @WHERE@/@LET@ is peeled off
    -- first so its local definitions (which 'rewriteExpr' would otherwise drop)
    -- render as an attached "where:" block.
    | otherwise ->
        let subst              = paramSubst tysig
            reading            = u.uReading { rdBlanks = scalarInputs tysig }
            -- Normalised first: until then an AND can sit inside a call's
            -- argument, and phrasing that argument would swallow the condition.
            (inner, locals)    = peelWhere (distributeCalls (carameliseExpr (clauseLayout body)))
            read'              = collapseTruth . rewriteWith reading . substParams subst
            (conn, mainClause) = decideRendering u.uCalls tysig (read' inner)
        in case mapMaybe (localDefClause reading u.uCalls subst) locals of
             []   -> (conn, mainClause)
             defs -> (conn, CWhere mainClause defs)
  UAssume _ -> ("", CLeaf "")
  UDeclare (MkDeclare _ _ _ tyDecl) ->
    case tyDecl of
      RecordDecl _ _ (_ : _) -> ("consists of", declareClause tyDecl)
      EnumDecl _ cons
        | longEnum cons -> ("means one of", CFields [ (conName c, "") | c <- cons ])
      _                      -> ("means", declareClause tyDecl)
 where
  conName (MkConDecl _ n _) = spaceCamel (resolvedText n)
  -- Bullet a long enum, or one whose cases are long phrases, rather than
  -- running them all into one "one of …" sentence.
  longEnum cons =
    length cons > 5 || any (\c -> Text.length (conName c) > 24) cons

decideRendering :: Set.Set Unique -> TypeSig Resolved -> Expr Resolved -> (Text, Clause)
decideRendering calls tysig body
  | Just t <- nlgOf body =
      (connectorFor tysig body, CLeaf t)   -- an authored @nlg sentence wins
  | Regulative _ deon <- body =
      ("provides that", deonticClause deon)
  | Just (cols, rows) <- bodyAsTable body =
      ( maybe "means" (("means the following list of " <>) . spaceCamel) (listElemTypeName body)
      , tableClause cols rows )
  | Just items <- bodyAsValueList body =
      ("means", CChain "a list of the following" items)
  | Just c <- listChainClause body =
      ("means", c)
  -- A named-argument call to a rule that has a herald has the shape of a record
  -- construction and is not one: it reads as the herald with its arguments in a
  -- @where@ clause, as @l4 nlg@ prints it ('substituteNlgCalls' has put the herald
  -- on its head), not as "is a the gap with" and a list of fields. Told apart by
  -- what the head resolved to, not by its name or a herald on it: a record can be
  -- named like a rule that has a herald, and can carry a herald of its own, and
  -- its literal is still a record. A call to a rule WITHOUT a herald still reads
  -- as a construction.
  | Just (ctor, fields) <- bodyAsRecordLiteral body
  , not (isRuleCall calls body) =
      ("is " <> withArticle (spaceCamel ctor) <> " with", CFields (map fieldPair fields))
  | Just c <- arithChainClause body =
      ("equals", c)
  | Just f <- formulaText body =
      ("equals", CLeaf (normalizeWs f))
  | otherwise =
      (connectorFor tysig body, toClause body)
 where
  fieldPair (MkNamedExpr _ f v) = (resolvedText f, leafText v)

-- | Lay out a rule written as a list of clauses the way its clauses read.
--
-- The desugarer compiles the clauses to CONSIDERs ('PmConsider') that hand
-- the input to a local definition holding the later clauses ('PmFallthrough',
-- see 'L4.Parser.matchClauses') when they do not match. Read off as it stands,
-- that tree renders each such definition as a "where" entry, and loses every
-- one nested inside another, which is every one after the first. So:
--
-- * a definition of the later clauses that is read once, as it is whenever the
--   clauses test a single input, is put in place of the reading, and a
--   CONSIDER that then tests the same input in its OTHERWISE is merged into
--   its parent, so that the clauses read as one list of cases;
--
-- * one read more than once, which happens when clauses test several inputs,
--   is kept, and moved to the top, where 'peelWhere' renders it as a "where"
--   entry named for the clauses it holds.
--
-- Only nodes carrying the desugarer's marks are touched; any other rule is
-- returned unchanged.
clauseLayout :: Expr Resolved -> Expr Resolved
clauseLayout = hoist . transformOf (gplate @(Expr Resolved)) merge . transformOf (gplate @(Expr Resolved)) inline
 where
  inline = \case
    LetIn _ [LocalDecide _ (MkDecide dann _ (MkAppForm _ ft [] _) later)] e
      | isLaterClauses dann
      , length (filter (readsName ft) (everyExpr e)) <= 1 ->
          transformOf (gplate @(Expr Resolved)) (\x -> if readsName ft x then later else x) e
    e -> e
  merge = \case
    Consider ann s brs
      | isGenerated ann
      , Just (front, MkBranch _ (Otherwise _) (Consider ann' s' brs')) <- List.unsnoc brs
      , isGenerated ann'
      , sameInput s s' -> Consider ann s (front <> brs')
    e -> e
  hoist e = case [ d | LetIn _ ds _ <- everyExpr e, d <- ds, laterClausesDecl d ] of
    [] -> e
    ds -> LetIn emptyAnno ds (transformOf (gplate @(Expr Resolved)) unwrap e)
  unwrap = \case
    LetIn _ ds e | all laterClausesDecl ds -> e
    e -> e
  laterClausesDecl = \case
    LocalDecide _ (MkDecide dann _ _ _) -> isLaterClauses dann
    LocalAssume{} -> False
  isLaterClauses dann = case dann ^. annPmSynthetic of
    Just (PmFallthrough _) -> True
    _ -> False
  isGenerated ann = case ann ^. annPmSynthetic of
    Just (PmConsider{}) -> True
    _ -> False
  readsName n = \case
    Var _ r      -> getUnique r == getUnique n
    App _ r []   -> getUnique r == getUnique n
    _            -> False
  sameInput a b = case (a, b) of
    (App _ r [], App _ r' []) -> getUnique r == getUnique r'
    _ -> False
  everyExpr x = x : concatMap everyExpr (toListOf (gplate @(Expr Resolved)) x)

-- | Peel a top-level @WHERE@ / @LET … IN@ wrapper off a rule body, returning the
-- inner body and its local definitions. Only the rule's own top-level locals are
-- surfaced; @WHERE@s nested deeper in the body are still flattened away by
-- 'rewriteExpr'.
peelWhere :: Expr Resolved -> (Expr Resolved, [LocalDecl Resolved])
peelWhere = \case
  Where _ e ds -> (e, ds)
  LetIn _ ds e -> (e, ds)
  e            -> (e, [])

-- | Render one local @WHERE@/@LET@ binding as a (heading, connector, body)
-- triple. The enclosing rule's GIVEN parameters are in scope inside the binding,
-- so its parameter substitution is threaded in alongside the binding's own.
localDefClause :: Reading -> Set.Set Unique -> Map.Map Unique Text -> LocalDecl Resolved -> Maybe (Text, Text, Clause)
localDefClause reading calls outerSubst = \case
  LocalDecide _ d@(MkDecide _ ltysig _ lbody) ->
    let subst          = Map.union (paramSubst ltysig) outerSubst
        localReading   = reading { rdBlanks = reading.rdBlanks <> scalarInputs ltysig }
        (conn, clause) = decideRendering calls ltysig
                           (collapseTruth (rewriteWith localReading (substParams subst (distributeCalls (carameliseExpr lbody)))))
    in Just (resolvedText (decideApp d), conn, clause)
  LocalAssume{} -> Nothing

-- | Map each GIVEN parameter to a readable noun phrase. A short or generic name
-- of a record or enum takes its type's name, so @p@ reads "the payment" and
-- @scenario@ of a @Sell Scenario@ reads "the sell scenario". A name that says
-- more than the type does is the drafter's word for a role and is kept:
-- @`the applicant`@ of a @Person@ stays "the applicant". A scalar parameter
-- keeps its own name, spaced. Two parameters that would read alike are told
-- apart by their names.
paramSubst :: TypeSig Resolved -> Map.Map Unique Text
paramSubst (MkTypeSig _ (MkGivenSig _ names) _) =
  let params = [ (getUnique r, nameToText (getActual r), mty >>= userTypeName)
               | MkOptionallyTypedName _ r mty <- names ]
      dupTypes = Map.fromListWith (+) [ (tn, 1 :: Int) | (_, _, Just tn) <- params ]
      phraseOf pname = \case
        Just tn
          | not (namedByType pname tn) -> rolePhrase pname
          | Map.findWithDefault 0 tn dupTypes > 1 -> "the " <> noun tn <> " " <> cleanParam pname
          | otherwise                             -> "the " <> noun tn
        Nothing -> spaceCamel (cleanParam pname)
      -- Too short to mean anything, or just a word of the type's own name, when
      -- that name is short enough to say each time.
      namedByType pname tn =
        let typeWords = Text.words (Text.toLower (spaceCamel tn))
        in Text.length pname <= 2
             || (length typeWords <= 4 && all (`elem` typeWords) (Text.words (Text.toLower pname)))
      rolePhrase pname
        | Just rest <- Text.stripPrefix "The " pname = "the " <> rest
        | any (`Text.isPrefixOf` pname) ["the ", "a ", "an ", "this ", "that "] = pname
        | otherwise = "the " <> spaceCamel (cleanParam pname)
      noun = Text.unwords . map lowerOrdinary . Text.words . spaceCamel
      lowerOrdinary w = if keepsCapitals w then w else Text.toLower w
  in Map.fromList [ (u, phraseOf pname mtn) | (u, pname, mtn) <- params ]

substParams :: Map.Map Unique Text -> Expr Resolved -> Expr Resolved
substParams pm
  | Map.null pm = id
  | otherwise = transformOf (gplate @(Expr Resolved)) $ \case
      App ann n [] | Just phrase <- Map.lookup (getUnique n) pm -> Inert ann phrase InertCtxNone
      e -> e

-- | The name of a user-defined (non-builtin) nullary type constructor.
userTypeName :: Type' Resolved -> Maybe Text
userTypeName = \case
  TyApp _ n [] ->
    let t = nameToText (getActual n)
    in if t `elem` builtinTypeNames then Nothing else Just t
  _ -> Nothing

builtinTypeNames :: [Text]
builtinTypeNames =
  ["NUMBER", "INTEGER", "STRING", "BOOLEAN", "DATE", "TIME", "MONEY", "PERCENT", "LIST", "MAYBE"]

cleanParam :: Text -> Text
cleanParam = Text.map (\c -> if c == '_' then ' ' else c)

-- | Space a run-together name for a reader: @LoanState@ reads @Loan State@,
-- @EPApplication@ reads @EP Application@, and @dateOfBirth@, which starts in
-- lower case, reads @date of birth@. A name that is already spaced, or all in
-- capitals, is left as it is.
spaceCamel :: Text -> Text
spaceCamel t
  | Text.any (== ' ') t = t
  | otherwise           =
      let spaced = Text.words (Text.pack (go (Text.unpack t)))
      in Text.unwords $ case Text.uncons t of
           Just (c, _) | isLower c -> map lowerWord spaced
           _                       -> spaced
 where
  go (a : b : rest) | isLower a, isUpper b = a : ' ' : go (b : rest)
  go (a : b : c : rest) | isUpper a, isUpper b, isLower c = a : ' ' : go (b : c : rest)
  go (a : rest)     = a : go rest
  go []             = []
  -- An acronym inside the name keeps its capitals.
  lowerWord w = if keepsCapitals w then w else Text.toLower w

-- | An acronym or a code: EP, C1.
keepsCapitals :: Text -> Bool
keepsCapitals w = case Text.unpack w of
  c : d : _ -> isUpper c && (isUpper d || isDigit d)
  _         -> False

connectorFor :: TypeSig Resolved -> Expr Resolved -> Text
connectorFor tysig body
  | returnsBoolean tysig = "if"
  | otherwise = case carameliseNode body of
      Consider{} -> "is determined by"
      And{}      -> "if"
      Or{}       -> "if"
      Not{}      -> "if"
      Equals{}   -> "if"
      Geq{}      -> "if"
      Leq{}      -> "if"
      Gt{}       -> "if"
      Lt{}       -> "if"
      RAnd{}     -> "provides that"
      ROr{}      -> "provides that"
      _          -> "means"

returnsBoolean :: TypeSig Resolved -> Bool
returnsBoolean (MkTypeSig _ _ mGiveth) = case mGiveth of
  Just (MkGivethSig _ ty) -> typeNameText ty == "BOOLEAN"
  Nothing                 -> False

typeNameText :: Type' Resolved -> Text
typeNameText = \case
  TyApp _ n _ -> nameToText (getActual n)
  _           -> ""

-- | Is this a named-argument call to one of these rules?
isRuleCall :: Set.Set Unique -> Expr Resolved -> Bool
isRuleCall calls = \case
  AppNamed _ n _ _ -> getUnique n `Set.member` calls
  _                -> False

bodyAsRecordLiteral :: Expr Resolved -> Maybe (Text, [NamedExpr Resolved])
bodyAsRecordLiteral = \case
  AppNamed _ ctor nes _ -> Just (resolvedText ctor, nes)
  _                     -> Nothing

-- | The element type name of a @LIST@ of record literals — the constructor of
-- its first element (the rows share columns, so the type is uniform). Used to
-- caption a record-list table as "… the following list of <Type>".
listElemTypeName :: Expr Resolved -> Maybe Text
listElemTypeName e = case carameliseNode e of
  List _ (item : _) -> case carameliseNode item of
    AppNamed _ ctor _ _ -> Just (resolvedText ctor)
    _                   -> Nothing
  _ -> Nothing

-- | A @LIST@ of record literals that all share the same field columns: the
-- column headings and the per-row field-value expressions. Renders as a table.
bodyAsTable :: Expr Resolved -> Maybe ([Text], [[Expr Resolved]])
bodyAsTable e = case carameliseNode e of
  List _ items
    | Just recs@(firstRec : _) <- traverse asRecord items
    , let cols = map fst firstRec
    , not (null cols)
    , all (\r -> map fst r == cols) recs ->
        Just (cols, [ map snd r | r <- recs ])
  _ -> Nothing
 where
  asRecord ex = case carameliseNode ex of
    AppNamed _ _ nes _ -> Just [ (resolvedText f, v) | MkNamedExpr _ f v <- nes ]
    _                  -> Nothing

tableClause :: [Text] -> [[Expr Resolved]] -> Clause
tableClause cols rows = CTable cols [ map cellClause row | row <- rows ]

-- | A literal list of more than three (non-record) values — e.g. strings,
-- numbers, dates — renders as a bullet list rather than a comma-run sentence.
-- Lists of records are handled by 'bodyAsTable' (checked first), and short
-- lists stay inline.
bodyAsValueList :: Expr Resolved -> Maybe [Text]
bodyAsValueList e = case carameliseNode e of
  List _ items | length items >= arithChainMinTerms -> Just (map leafText items)
  _                                                  -> Nothing

-- | Render a table cell: a nested list-of-records becomes its own (nested)
-- table, a nested record a small field list, anything else a value — and a
-- reference to another defined list links to that list's table via the normal
-- cross-reference mechanism.
cellClause :: Expr Resolved -> Clause
cellClause v
  | Just (cols, rows) <- bodyAsTable v = tableClause cols rows
  | Just (_, fields) <- bodyAsRecordLiteral v =
      CFields [ (resolvedText f, leafText fv) | MkNamedExpr _ f fv <- fields ]
  | otherwise = CLeaf (leafText v)

declareClause :: TypeDecl Resolved -> Clause
declareClause = \case
  RecordDecl _ _ []     -> CLeaf "an empty record"
  RecordDecl _ _ fields -> CFields (map recordField fields)
  EnumDecl _ [c]        -> CLeaf (conName c)
  EnumDecl _ cons       -> CLeaf ("one of " <> oxford "or" (map conName cons))
  SynonymDecl _ ty      -> CLeaf (typeText ty)
 where
  recordField (MkTypedName _ n ty Nothing)     = (resolvedText n, typeText ty)
  recordField (MkTypedName _ n ty (Just expr)) =
    (resolvedText n, typeText ty <> ", computed as " <> leafText expr)
  conName (MkConDecl _ n _) = spaceCamel (resolvedText n)

-- ----------------------------------------------------------------------------
-- Expression -> Clause tree
-- ----------------------------------------------------------------------------

toClause :: Expr Resolved -> Clause
toClause e0
  | Just t <- nlgOf e0 = CLeaf t   -- an authored @nlg sentence wins
toClause e0 = case carameliseNode e0 of
  IfThenElse _ c t f -> buildIf [(condText c, toClause t)] f
  MultiWayIf _ gs o  ->
    CIf [ (condText gc, toClause gf) | MkGuardedExpr _ gc gf <- gs ] (Just (toClause o))
  Consider _ s brs   -> CCases (inlineProse s) (map branchPair brs)
  Regulative _ deon  -> deonticClause deon
  And{}              -> statuteList CAll (flattenAnd e0)
  Or{}               -> statuteList CAny (flattenOr e0)
  -- A negated list of three or more stays a list, and the denial leads it.
  Not _ inner
    | n <- carameliseNode inner, isAndNode n, ps@(_ : _ : _ : _) <- flattenAnd n ->
        CLed "it is not the case that all of the following hold" (CAll (map toClause ps))
    | n <- carameliseNode inner, isOrNode n, isNothing (oneOfText n), ps@(_ : _ : _ : _) <- flattenOr n ->
        CLed "none of the following holds" (CAny (map toClause ps))
  Concat _ es        -> CLeaf (textParts es)
  Cons{}
    | Just c <- listChainClause e0 -> c
  RAnd{}             -> CAll (map toClause (flattenAnd e0))
  ROr{}              -> CAny (map toClause (flattenOr e0))
  e | Just c <- arithChainClause e -> c
    | Just f <- formulaText e       -> CLeaf (normalizeWs f)
    | otherwise                     -> CLeaf (condText e)
 where
  buildIf acc f = case carameliseNode f of
    IfThenElse _ c2 t2 f2 -> buildIf (acc <> [(condText c2, toClause t2)]) f2
    MultiWayIf _ gs o     ->
      CIf (acc <> [ (condText gc, toClause gf) | MkGuardedExpr _ gc gf <- gs ]) (Just (toClause o))
    _                     -> CIf acc (Just (toClause f))
  branchPair (MkBranch _ lhs body) = (branchLhsText lhs, toClause body)

-- | A function applied to a single control-flow argument distributes over that
-- argument's branches: "the day before (CONSIDER … THEN x …)" lays out as a case
-- tree whose leaves are "the day before x", a readable outline rather than one
-- run-on line that inlines the whole nested CONSIDER. Done before the calls are
-- phrased, so that each leaf is phrased as a call of its own.
distributeCalls :: Expr Resolved -> Expr Resolved
distributeCalls = transformOf (gplate @(Expr Resolved)) $ \e -> case e of
  App ann n [arg]
    | isControlFlowExpr (carameliseNode arg) ->
        distributeIntoBranches (\leaf -> App ann n [leaf]) arg
  _ -> e

-- | Say a rule that only produces truth values as the condition it states.
-- @IF c THEN TRUE ELSE x@ is @c OR x@, and a CONSIDER whose every result is TRUE
-- or FALSE names the cases that are true. This is logic, not style: each rewrite
-- is an identity, and it is what lets such a rule read as a list of conditions.
collapseTruth :: Expr Resolved -> Expr Resolved
collapseTruth = transformOf (gplate @(Expr Resolved)) $ \e -> case carameliseNode e of
  IfThenElse ann c t f -> case (truthOf t, truthOf f) of
    (Just True,  Just False) -> c
    (Just False, Just True)  -> Not ann c
    (Just True,  _)          -> Or ann c f
    (Just False, _)          -> And ann (Not ann c) f
    (_,          Just False) -> And ann c t
    (_,          Just True)  -> Or ann (Not ann c) t
    _                        -> e
  Consider ann s brs | Just t <- considerAsTest s brs -> Inert ann t InertCtxNone
  _ -> e

truthOf :: Expr Resolved -> Maybe Bool
truthOf e = case carameliseNode e of
  App _ n [] | nameIs "TRUE" n  -> Just True
             | nameIs "FALSE" n -> Just False
  Var _ n    | nameIs "TRUE" n  -> Just True
             | nameIs "FALSE" n -> Just False
  _ -> Nothing

-- | A CONSIDER that only answers yes or no, on patterns that name a value, as a
-- test of its subject. With an OTHERWISE that says yes, the test is on the cases
-- that say no.
considerAsTest :: Expr Resolved -> [Branch Resolved] -> Maybe Text
considerAsTest s brs = do
  cases <- traverse caseOf brs
  let named b = [ p | (Just p, r) <- cases, r == b ]
      fallback = listToMaybe [ r | (Nothing, r) <- cases ]
      subject = inlineProse s
  case (named True, named False, fallback) of
    (_, _, Just True)    -> test subject False (named False)
    ([], _, _)           -> Nothing
    (yes, _, _)          -> test subject True yes
 where
  caseOf (MkBranch _ lhs body) = do
    r <- truthOf body
    case lhs of
      Otherwise _  -> Just (Nothing, r)
      When _ pat   -> (\p -> (Just p, r)) <$> valueName pat
  valueName = \case
    PatApp _ con [] | nameIs "NOTHING" con -> Just (fw "absent")
                    | otherwise            -> Just (spaceCamel (resolvedText con))
    PatApp _ con [p] | nameIs "JUST" con   -> valueName p
    PatLit _ l                                   -> Just (patternText (PatLit emptyAnno l))
    _                                            -> Nothing
  test _ _ [] = Nothing
  test subj True [v]  = Just (subj <> " " <> fw "is" <> " " <> v)
  test subj False [v] = Just (subj <> " " <> fw "is not" <> " " <> v)
  test subj True vs   = Just (subj <> " " <> fw "is one of" <> " " <> orList vs)
  test subj False vs  = Just (subj <> " " <> fw "is not one of" <> " " <> orList vs)

-- | The operands of a connective, with the statute's own text kept where it
-- belongs. An author can carry a provision's words among its conditions as inert
-- strings ("(1)" ... the condition), which change nothing when the rule runs. A
-- short one is the provision's own label for the operand after it. A longer one
-- first in the list is the words that lead into the list.
statuteList :: ([Clause] -> Clause) -> [Expr Resolved] -> Clause
statuteList mk parts = case parts of
  p : rest@(_ : _)
    | Just leadIn <- inertText p, isNothing (statutoryLabel p) ->
        CLeadIn (fromMaybe leadIn (Text.stripSuffix ":" (Text.strip leadIn))) (mk (entries rest))
  _ -> mk (entries parts)
 where
  entries = \case
    l : next : more
      | Just label <- statutoryLabel l -> CLabel label (toClause next) : entries more
    e : more -> entry e : entries more
    [] -> []
  entry e = case carameliseNode e of
    n | isAndNode n, l : body@(_ : _) <- flattenAnd n, Just label <- statutoryLabel l ->
          CLabel label (case body of
            [one] -> toClause one
            many  -> CAll (map toClause many))
    n -> toClause n

-- | The text of a string an author wrote among conditions. The rendering's own
-- phrases are inert too, but only an author's has a connective around it when the
-- rule is normalised.
inertText :: Expr Resolved -> Maybe Text
inertText e = case e of
  Inert _ t ctx | ctx /= InertCtxNone -> Just t
  _ -> Nothing

-- | An inert string that is a provision's label: (1), (a), (iv), 1., a).
statutoryLabel :: Expr Resolved -> Maybe Text
statutoryLabel e = do
  t <- Text.strip <$> inertText e
  let inner = Text.dropAround (`elem` ['(', ')', '.']) t
      marked = Text.isSuffixOf ")" t || Text.isSuffixOf "." t
  guard (marked && not (Text.null inner) && Text.length inner <= 5 && Text.all isAlphaNum inner)
  Just t

-- | The parts of a text built by joining, as the text they make: the words of a
-- literal, with each part that is worked out named where it falls.
textParts :: [Expr Resolved] -> Text
textParts = Text.unwords . map leafText

-- | A list written out item by item, as a list a reader can go down. Its last
-- item is left out when it is just the empty list that ends it.
listChainClause :: Expr Resolved -> Maybe Clause
listChainClause e
  | length items >= 3 = Just (CChain "a list of the following" (map leafText items))
  | otherwise         = Nothing
 where
  items = spine e
  spine x = case carameliseNode x of
    Cons _ a b -> a : spine b
    App _ n [] | nameIs "EMPTY" n -> []
    Var _ n    | nameIs "EMPTY" n -> []
    y -> [y]

-- | Whether an expression is a branching construct (so it should lay out as a
-- structured clause rather than inline prose).
isControlFlowExpr :: Expr Resolved -> Bool
isControlFlowExpr = \case
  Consider{}   -> True
  IfThenElse{} -> True
  MultiWayIf{} -> True
  _            -> False

-- | Push a wrapper (e.g. an enclosing function application) down to the result
-- leaves of a control-flow expression, preserving its branch structure. Sound
-- because L4 is pure: @f (IF c THEN x ELSE y) = IF c THEN f x ELSE f y@.
distributeIntoBranches :: (Expr Resolved -> Expr Resolved) -> Expr Resolved -> Expr Resolved
distributeIntoBranches wrap e = case carameliseNode e of
  Consider ann s brs ->
    Consider ann s [ MkBranch a lhs (distributeIntoBranches wrap b) | MkBranch a lhs b <- brs ]
  IfThenElse ann c t f ->
    IfThenElse ann c (distributeIntoBranches wrap t) (distributeIntoBranches wrap f)
  MultiWayIf ann gs o ->
    MultiWayIf ann
      [ MkGuardedExpr a gc (distributeIntoBranches wrap g) | MkGuardedExpr a gc g <- gs ]
      (distributeIntoBranches wrap o)
  leaf -> wrap leaf

branchLhsText :: BranchLhs Resolved -> Text
branchLhsText = \case
  When _ pat  -> patternPredicate pat
  Otherwise _ -> "otherwise"

-- | What a pattern says about the value it is matched against, as a predicate
-- on that value, so that a case can name its subject: "the unit type is Studio",
-- "the guarantor is absent", "the instalments start with first, followed by
-- rest". 'patternText' is the same pattern as a noun.
patternPredicate :: Pattern Resolved -> Text
patternPredicate = \case
  PatApp _ con []
    | nameIs "NOTHING" con -> fw "is absent"
    | nameIs "EMPTY" con   -> fw "is empty"
  PatApp _ con [p]
    | nameIs "JUST" con -> case p of
        PatVar _ v -> fw "is present, with the value" <> " " <> resolvedText v
        _          -> patternPredicate p
  PatVar _ v -> fw "is any value, called" <> " " <> resolvedText v
  PatCons _ a b -> fw "starts with" <> " " <> patternText a <> ", " <> fw "followed by" <> " " <> patternText b
  pat -> "is " <> patternText pat

flattenAnd :: Expr Resolved -> [Expr Resolved]
flattenAnd e = case carameliseNode e of
  And _ a b  -> flattenAnd a <> flattenAnd b
  RAnd _ a b -> flattenAnd a <> flattenAnd b
  x          -> [x]

flattenOr :: Expr Resolved -> [Expr Resolved]
flattenOr e = case carameliseNode e of
  Or _ a b  -> flattenOr a <> flattenOr b
  ROr _ a b -> flattenOr a <> flattenOr b
  x         -> [x]

-- | Render a boolean condition in plain legal English: comparisons use words
-- ("is", "is at least"); an OR of equalities on the same value collapses to
-- "… is one of A, B or C".
condText :: Expr Resolved -> Text
condText e
  | Just t <- nlgOf e = t
condText e = case carameliseNode e of
  Equals _ a b         -> side a <> " " <> fw "is" <> " " <> side b
  Not _ inner          -> case carameliseNode inner of
    Equals _ a b -> side a <> " " <> fw "is not" <> " " <> side b
    n | isAndNode n -> notAllText (flattenAnd n)
      | isOrNode n  -> case oneOfParts n of
          Just (lhs, rhs) -> lhs <> " " <> fw "is not one of" <> " " <> orList rhs
          Nothing         -> noneOfText (flattenOr n)
    n            -> notStatement (condText n)
  Geq _ a b            -> side a <> " " <> fw "is at least" <> " " <> side b
  Leq _ a b            -> side a <> " " <> fw "is at most" <> " " <> side b
  Gt _ a b             -> side a <> " " <> fw "is more than" <> " " <> side b
  Lt _ a b             -> side a <> " " <> fw "is less than" <> " " <> side b
  orChain@Or{}         -> case oneOfText orChain of
                            Just t  -> t
                            Nothing -> joinCond "or" (flattenOr orChain)
  ROr _ _ _            -> joinCond "or" (flattenOr e)
  And{}                -> joinCond "and" (flattenAnd e)
  RAnd _ _ _           -> joinCond "and" (flattenAnd e)
  e'                   -> inlineProse e'
 where
  side = inlineProse

-- | Join the operands of one connective.
--
-- An operand that is a compound of the OTHER connective has to say where it
-- starts and ends: @a AND (b OR c)@ printed flat is "a and b or c", which reads
-- as @(a AND b) OR c@ and states a different rule. So it reads "a and either b
-- or c", and @(a OR b) AND c@ reads "either a or b, and c". Two operands of
-- which the first is grouped take a comma, because nothing else marks where the
-- group ends; three or more are a comma list.
joinCond :: Text -> [Expr Resolved] -> Text
joinCond conj parts0
  | any isCompound parts = case (parts, map groupText parts) of
      (p : _, [x, y])
        | isCompound p -> x <> ", " <> fw conj <> " " <> y
        | otherwise    -> x <> " " <> fw conj <> " " <> y
      (_, xs) -> oxford (fw conj) xs
  | otherwise = Text.intercalate (" " <> fw conj <> " ") (map boundedCond parts)
 where
  parts = keepLabels parts0
  -- A statutory label belongs to what follows it, and no connective joins them.
  keepLabels = \case
    l : next : more
      | Just label <- statutoryLabel l ->
          Inert emptyAnno (label <> " " <> condText next) InertCtxNone : keepLabels more
    e : more -> e : keepLabels more
    [] -> []

-- | A statement denied. The negation stays outside the statement, because a
-- statement can be the author's words, and working a "not" into them would be a
-- guess at what they mean. An author who wants a negative wording writes a rule
-- for it, with an @\@nlg@.
notStatement :: Text -> Text
notStatement t
  | [_] <- Text.words t = t <> " " <> fw "is false"
  | otherwise           = fw "it is not the case that" <> " " <> t

andList, orList :: [Text] -> Text
andList = oxford (fw "and")
orList  = oxford (fw "or")

-- | A compound of AND or OR, unless it collapses to a single "is one of".
isCompound :: Expr Resolved -> Bool
isCompound e = case carameliseNode e of
  n | isAndNode n -> True
    | isOrNode n  -> isNothing (oneOfText n)
  _ -> False

isAndNode, isOrNode :: Expr Resolved -> Bool
isAndNode = \case And{} -> True; RAnd{} -> True; _ -> False
isOrNode  = \case Or{} -> True; ROr{} -> True; _ -> False

-- | An operand, delimited in words if it is a compound. Inside a group a further
-- compound is put in brackets, the only marking that stays clear at any depth.
groupText :: Expr Resolved -> Text
groupText e = case carameliseNode e of
  n | isCompound n, isAndNode n -> case map itemText (flattenAnd n) of
        [a, b] -> fw "both" <> " " <> a <> " " <> fw "and" <> " " <> b
        xs     -> fw "all of:" <> " " <> andList xs
    | isCompound n, isOrNode n -> case map itemText (flattenOr n) of
        [a, b] -> fw "either" <> " " <> a <> " " <> fw "or" <> " " <> b
        xs     -> fw "any of:" <> " " <> orList xs
  _ -> boundedCond e

itemText :: Expr Resolved -> Text
itemText e
  | isCompound e = "(" <> condText e <> ")"
  | otherwise    = boundedCond e

-- | An operand of a connective. "it is not the case that" reaches as far as the
-- sentence does, so in "it is not the case that a or b" a reader takes the denial
-- to cover both. Brackets say that it covers one.
--
-- A denied OR is open in the same way, though it does not start with those
-- words: "neither a nor b and c" reads as denying @b AND c@, and "n is not one of
-- 1 or 2 or b" as @b@ being one of the values, because only the start of each is
-- marked. It is told by its shape, a NOT over an OR, and not by its words.
--
-- So is an IMPLIES, an IF or a CONSIDER, which no word closes: "neither p nor q
-- implies r" also reads as @(NOT (p OR q)) IMPLIES r@, and "neither if q then r
-- else s nor p" puts the "nor" in the ELSE.
--
-- The same holds where such a condition fills a slot that a sentence's words
-- come after ('slotRunsOn').
boundedCond :: Expr Resolved -> Text
boundedCond e
  | runsOn e t = "(" <> t <> ")"
  | otherwise  = t
 where
  t = condText e

-- | Whether a condition, printed as @t@, has no word to close it: what
-- 'boundedCond' brackets.
runsOn :: Expr Resolved -> Text -> Bool
runsOn e t = "it is not the case that" `Text.isPrefixOf` stripFrameMarks t || deniedOr || unclosed
 where
  deniedOr = isNothing (nlgOf e) && case carameliseNode e of
    Not _ inner -> isOrNode (carameliseNode inner)
    _           -> False
  unclosed = isNothing (nlgOf e) && case carameliseNode e of
    Implies{}    -> True
    IfThenElse{} -> True
    MultiWayIf{} -> True
    Consider{}   -> True
    _            -> False

-- | Whether a condition, printed as @t@, would take in the words of a sentence
-- that go on after the slot it fills ('rewriteWith', 'interleaveMixfix'). What
-- 'runsOn' says, and an AND or an OR as well: "p or q is shown" is also how
-- @p OR (`shown` q)@ reads. Beside a connective an AND or an OR is set off in
-- words ('joinCond'); in a slot nothing sets it off. Told by the condition's
-- shape, and by where the slot is, not by what any word says.
slotRunsOn :: Expr Resolved -> Text -> Bool
slotRunsOn e t = runsOn e t || (isNothing (nlgOf e) && isCompound e)

-- | The negation of an AND, which denies only that all of it holds.
notAllText :: [Expr Resolved] -> Text
notAllText parts = case map itemText parts of
  [a, b] -> fw "it is not the case that both" <> " " <> a <> " " <> fw "and" <> " " <> b
  xs     -> fw "it is not the case that all of:" <> " " <> andList xs

-- | The negation of an OR, which denies each of its operands.
noneOfText :: [Expr Resolved] -> Text
noneOfText parts = case map itemText parts of
  [a, b] -> fw "neither" <> " " <> a <> " " <> fw "nor" <> " " <> b
  xs     -> fw "none of:" <> " " <> orList xs

-- | Detect @x = A OR x = B OR …@ (same left side) and collapse to a membership.
oneOfText :: Expr Resolved -> Maybe Text
oneOfText e = do
  (lhs, rhs) <- oneOfParts e
  Just (lhs <> " " <> fw "is one of" <> " " <> orList rhs)

-- | The shared left side of an OR of equalities, and the values it is compared to.
oneOfParts :: Expr Resolved -> Maybe (Text, [Text])
oneOfParts e = do
  pairs <- orEquals e
  case pairs of
    ((lhs0, r0) : rest)
      | not (null rest), all ((== lhs0) . fst) rest -> Just (lhs0, r0 : map snd rest)
    _ -> Nothing
 where
  orEquals x = case carameliseNode x of
    Or _ a b     -> (<>) <$> orEquals a <*> orEquals b
    ROr _ a b    -> (<>) <$> orEquals a <*> orEquals b
    Equals _ a b -> Just [(inlineProse a, inlineProse b)]
    _            -> Nothing

-- | A pattern as English: unwrap @JUST@, drop the @… has@ scaffolding for
-- nullary constructors.
patternText :: Pattern Resolved -> Text
patternText = \case
  PatApp _ con []  -> spaceCamel (resolvedText con)
  PatApp _ con [p] | nameToText (getActual con) == "JUST" -> patternText p
  PatApp _ con ps  -> spaceCamel (resolvedText con) <> " (" <> oxford "and" (map patternText ps) <> ")"
  PatVar _ v       -> resolvedText v
  PatLit _ l       -> litText l
  PatCons _ a b    -> patternText a <> " followed by " <> patternText b
  PatExpr _ ex     -> inlineProse ex
 where
  litText (NumericLit _ r) = prettyRatio r
  litText (StringLit _ t)  = t

-- ----------------------------------------------------------------------------
-- Deontic rules
-- ----------------------------------------------------------------------------

deonticClause :: Deonton Resolved -> Clause
deonticClause (MkDeonton _ party (MkAction _ modal actPat mprov) mdue mhence mlest) =
  CDeontic
    (inlineProse party)
    (modalWord modal)
    (patternText actPat)
    (dueText mdue)
    (fmap toClause mprov)
    (mhence >>= henceClause)
    (fmap consequence mlest)
 where
  -- A deadline of zero leaves no time to act, which is not the same thing as no
  -- deadline at all: a rule with no WITHIN waits for ever.
  dueText (Just d)
    | isZeroLit d = Just (fw "immediately")
    | otherwise   = Just (fw "within" <> " " <> inlineProse d)
  dueText Nothing = Nothing
  henceClause h
    | isFulfilled h = Nothing
    | otherwise     = Just (consequence h)
  -- Who is in breach is part of the rule, so a BREACH BY says so. Without a BY
  -- the rule does not name anyone, and neither does this.
  consequence e = case e of
    Breach _ mParty mReason ->
      CLeaf (maybe (fw "the obligation is breached") (\p -> inlineProse p <> " " <> fw "is in breach") mParty
               <> maybe "" (\r -> " " <> fw "because" <> " “" <> inlineProse r <> "”") mReason)
    _ -> toClause e

modalWord :: DeonticModal -> Text
modalWord = \case
  DMust    -> "must"
  DMay     -> "may"
  DMustNot -> "must not"
  DDo      -> "shall"

isZeroLit :: Expr Resolved -> Bool
isZeroLit = \case
  Lit _ (NumericLit _ r) -> r == 0
  _                      -> False

isFulfilled :: Expr Resolved -> Bool
isFulfilled = \case
  App _ n [] -> nameToText (getActual n) == "FULFILLED"
  _          -> False

-- | A non-structured leaf value: a formula if it is pure arithmetic, otherwise
-- prose.
leafText :: Expr Resolved -> Text
leafText e
  | isLogic (carameliseNode e) = condText e
  | otherwise                  = inlineProse e
 where
  isLogic = \case
    And{} -> True; Or{} -> True; Not{} -> True
    Equals{} -> True; Geq{} -> True; Leq{} -> True; Gt{} -> True; Lt{} -> True
    _ -> False

-- | A top-level arithmetic chain (a sum/product/… whose operator repeats) with
-- this many operands or more renders as a bulleted list rather than one long
-- formula line.
arithChainMinTerms :: Int
arithChainMinTerms = 4

-- | If an expression is a top-level additive (@+@/@−@) or multiplicative
-- (@×@/@÷@) chain of at least 'arithChainMinTerms' operands, lay it out as a
-- list: a lead-in plus one pre-rendered line per operand. A uniform chain (all
-- @+@, or all @×@) gets a "the sum of" / "the product of" lead and plain lines;
-- a mixed chain gets a neutral lead and an operator word ("plus", "minus",
-- "times", "divided by") in front of each line after the first.
arithChainClause :: Expr Resolved -> Maybe Clause
arithChainClause e = case carameliseNode e of
  Plus{}      -> chain (flattenChain additiveStep "+" e) "+" "the sum of the following" addWord
  Minus{}     -> chain (flattenChain additiveStep "+" e) "+" "the sum of the following" addWord
  Times{}     -> chain (flattenChain multStep "×" e) "×" "the product of the following" mulWord
  DividedBy{} -> chain (flattenChain multStep "×" e) "×" "the product of the following" mulWord
  _           -> Nothing
 where
  chain terms firstOp uniformLead word
    | length terms < arithChainMinTerms = Nothing
    | otherwise =
        let uniform = all ((== firstOp) . fst) terms
            lead    = if uniform then uniformLead else "the following"
            line i (op, t)
              | i == (0 :: Int) || uniform = term t
              | otherwise                  = word op <> " " <> term t
        in Just (CChain lead (zipWith line [0 ..] terms))
  -- A line holds one operand, and says where it ends, so the brackets an operand
  -- is given inside a formula ('rewriteWith') are not needed on it.
  term = unbracketed . leafText
  addWord o = if o == "-" then "minus" else "plus"
  mulWord o = if o == "÷" then "divided by" else "times"

-- | Text without the brackets round the whole of it, if it has them.
unbracketed :: Text -> Text
unbracketed t = case Text.uncons t of
  Just ('(', rest)
    | Just (inner, ')') <- Text.unsnoc rest, balanced (0 :: Int) (Text.unpack inner) -> inner
  _ -> t
 where
  balanced d []         = d == 0
  balanced d ('(' : cs) = balanced (d + 1) cs
  balanced d (')' : cs) = d > 0 && balanced (d - 1) cs
  balanced d (_ : cs)   = balanced d cs

-- | Walk the left spine of an operator chain into @(operator, operand)@ pairs,
-- leftmost first (its operator is the chain's identity, "+" or "×"). Right
-- operands are kept whole — only the same-precedence left spine is flattened, so
-- the result is faithful regardless of nesting.
flattenChain :: (Expr Resolved -> Maybe (Text, Expr Resolved, Expr Resolved))
             -> Text -> Expr Resolved -> [(Text, Expr Resolved)]
flattenChain step identityOp = go []
 where
  go acc e = case step (carameliseNode e) of
    Just (op, a, b) -> go ((op, b) : acc) a
    Nothing         -> (identityOp, e) : acc

additiveStep :: Expr Resolved -> Maybe (Text, Expr Resolved, Expr Resolved)
additiveStep = \case
  Plus _ a b  -> Just ("+", a, b)
  Minus _ a b -> Just ("-", a, b)
  _           -> Nothing

multStep :: Expr Resolved -> Maybe (Text, Expr Resolved, Expr Resolved)
multStep = \case
  Times _ a b     -> Just ("×", a, b)
  DividedBy _ a b -> Just ("÷", a, b)
  _               -> Nothing

-- ----------------------------------------------------------------------------
-- Formula mode (pure arithmetic -> symbols)
-- ----------------------------------------------------------------------------

-- | If the expression is /entirely/ arithmetic over numbers, variables and
-- projections — /and/ actually contains an arithmetic operator at the top (so a
-- bare variable or projection is left as prose) — render it with operator
-- symbols and minimal parentheses.
formulaText :: Expr Resolved -> Maybe Text
formulaText e
  | arithTop (carameliseNode e) = fmap snd (go e)
  | otherwise                   = Nothing
 where
  arithTop = \case
    Plus{} -> True; Minus{} -> True; Times{} -> True
    DividedBy{} -> True; Modulo{} -> True
    _ -> False
  go :: Expr Resolved -> Maybe (Int, Text)
  go expr = case carameliseNode expr of
    Plus _ a b      -> bin 1 " + " a b
    Minus _ a b     -> binRight 1 " − " a b
    Times _ a b     -> multiplicative False 2 " × " False a b
    DividedBy _ a b -> multiplicative False 2 " ÷ " True a b
    Modulo _ a b    -> multiplicative True 2 " mod " True a b
    Lit _ (NumericLit _ r) -> Just (4, numText r)
    Percent _ x     -> do (_, t) <- go x; Just (4, t <> "%")
    App _ n []      -> Just (4, resolvedText n)
    Inert _ t _     -> Just (4, t)   -- a substituted parameter phrase
    -- A refusal has no arithmetic reading; rendering it as prose inside a
    -- formula would read as a quantity. Bail out of formula mode entirely.
    Refuse{}        -> Nothing
    Proj _ a nm     -> do (_, t) <- go a; Just (4, possessiveOf t <> " " <> resolvedText nm)
    -- A non-arithmetic operand (a function call, projection chain, parameter …)
    -- becomes an inline atom rendered as prose, so a formula that mixes
    -- arithmetic with such terms still reads as "a + b × f(x)" rather than
    -- collapsing the whole expression back to nested "the sum of …" prose.
    other           -> Just (4, normalizeWs (simpleLinearizer other))
  bin p op a b = do
    (pa, ta) <- go a
    (pb, tb) <- go b
    Just (p, besideSum a (wrap p pa ta) <> op <> besideSum b (wrap p pb tb))
  -- The right operand of a subtraction or a division keeps its brackets at equal
  -- precedence too: a − (b − c) is not a − b − c, and a ÷ (b × c) is not a ÷ b × c.
  binRight p op a b = do
    (pa, ta) <- go a
    (pb, tb) <- go b
    Just (p, besideSum a (wrap p pa ta) <> op <> besideSum b (wrap (p + 1) pb tb))
  -- 'bin' and 'binRight' print only + and −. A mod binds tighter than either, so
  -- "a − b mod c" is a − (b mod c) by the formula's own rules; but "mod" is a word,
  -- and a reader can take it to cover "a − b". So a mod beside + or − is
  -- bracketed. Decided by the operator alone.
  besideSum x t = case carameliseNode x of
    Modulo{} -> "(" <> t <> ")"
    _        -> t
  wrap parentP childP t = if childP < parentP then "(" <> t <> ")" else t
  -- mod shares a level with × and ÷ but does not reassociate with either:
  -- a × (b mod c), (a × b) mod c and (a mod b) × c are three formulas, and flat
  -- "a × b mod c" can be read as more than one of them. So a mod that is an
  -- operand of × or ÷, and a × or ÷ that is an operand of mod, is bracketed on
  -- either side. Decided by the operators alone.
  multiplicative isMod p op strictRight a b = do
    (pa, ta) <- go a
    (pb, tb) <- go b
    let side x px tx q
          | mixesMod x = "(" <> tx <> ")"
          | otherwise  = wrap q px tx
    Just (p, side a pa ta p <> op <> side b pb tb (if strictRight then p + 1 else p))
   where
    mixesMod x = case carameliseNode x of
      Modulo{}    -> not isMod
      Times{}     -> isMod
      DividedBy{} -> isMod
      _           -> False

numText :: Rational -> Text
numText r = fromMaybe (prettyRatio r) (groupedInt r)

-- ----------------------------------------------------------------------------
-- AST rewrites for readability (dates, large numbers, implicit self)
-- ----------------------------------------------------------------------------

inlineProse :: Expr Resolved -> Text
inlineProse e = case nlgOf e of
  Just t  -> t
  Nothing ->
    let rewritten = rewriteExpr e
    in normalizeWs (fromMaybe (simpleLinearizer rewritten) (formulaText rewritten))

-- | An authored @\@nlg@ sentence on an expression, if present, takes precedence
-- over the structural rendering.
nlgOf :: Expr Resolved -> Maybe Text
nlgOf e = (normalizeWs . simpleLinearizer) <$> (e ^. annoOf % annNlg)

-- | A single bottom-up rewrite of an expression for readability. One pass (not
-- a chain) so an inner transform's 'Inert' result is in place before an outer
-- transform linearizes it.
rewriteExpr :: Expr Resolved -> Expr Resolved
rewriteExpr = rewriteWith noReading

-- | 'rewriteExpr' with what the document knows. Bottom-up, so a call's arguments
-- are already phrased when the call is, and a herald is spliced here and not
-- beforehand: spliced first, its arguments would miss every rewrite below and
-- print raw, in the middle of an otherwise readable sentence.
rewriteWith :: Reading -> Expr Resolved -> Expr Resolved
rewriteWith rd = go
 where
  -- 'transformOf', except that an arithmetic node also sees its operands as
  -- they were before they were rewritten ('groupOperands').
  go e = rw e (herald e (groupOperands e (over (gplate @(Expr Resolved)) go e)))
  inert ann t = Inert ann t InertCtxNone
  herald orig = \case
    -- A date given as literals reads as the date, whatever its rule's sentence.
    App ann n args | Just (d, m, y) <- daydateLiteral n args -> inert ann (Text.unwords [d, m, y])
    App ann n args | nameIs "Date" n, Just t <- dateFromArgs args -> inert ann t
    App ann n args | Just t <- monthDateFromArgs n args -> inert ann t
    App ann n [f, xs] | Just t <- quantified n f xs -> inert ann t
    -- Joined lists read as one list, so a long chain of them can be laid out.
    App ann n [a, b] | resolvedText n == "append", fromPrelude n -> Cons ann a b
    App ann n args
      | Just followed <- heraldSlots n args ->
          substituteNlgCallMarked rd.rdHeralds
            (App ann n (zipWith3 (\f o a -> asText (filler f o) a) followed (argsEndOpen orig args) args))
      | readsAsFunction n args -> substituteNlgCallMarked rd.rdHeralds (App ann n (map (asText leafText) args))
      | otherwise -> substituteNlgCallMarked rd.rdHeralds (App ann n (map (asText (argument leafText)) args))
    e -> substituteNlgCallMarked rd.rdHeralds e
  asText f a = Inert (a ^. annoOf) (f a) InertCtxNone
  -- An arithmetic argument is bracketed: printed as a formula it has no end, and
  -- "f2 for 2 and x − 3" also reads as @`f2` 2 x MINUS 3@. So does a sentence's
  -- slot: "twice (x − 3)". A maths function brackets its argument itself
  -- ("sqrt(x)"), and a present value reads as the value.
  argument f a
    | isArithmetic (carameliseNode a), isNothing (nlgOf a) = "(" <> f a <> ")"
    | otherwise = f a
  -- A sentence's slot. A condition with no closing word, in a slot the
  -- sentence's own words come after, is bracketed ('slotRunsOn'): "it is not
  -- the case that X is disclosed" is also how @NOT (`disclosed` X)@ reads. Told
  -- by where the slot is in the sentence, not by what its words say; in the last
  -- slot nothing follows it.
  --
  -- So is a call that ends with such a condition ('callEndsOpen'): with no
  -- brackets of its own, "fb for p and (q implies r) is shown" is also how
  -- @`fb` (p AND (`shown` (q IMPLIES r)))@ reads.
  filler followed open a
    | followed, slotRunsOn a t || open = "(" <> t <> ")"
    | otherwise                         = t
   where
    t = argument (slotText rd) a
  -- 'callEndsOpen' for each argument of a call, read from the call as it was
  -- before its arguments were rewritten.
  argsEndOpen orig args = case orig of
    App _ _ oargs | length oargs == length args -> map callEndsOpen oargs
    _ -> map (const False) args
  -- Whether a call, printed, ends with an argument that has no closing word, so
  -- that the call has none either and runs on into whatever follows it. A call
  -- that reads as f(x), or as a date, closes itself; a call with a sentence ends
  -- where the sentence does, unless its last slot holds such an argument; any
  -- other call ends with its last argument. Read from the shape of the call and
  -- of its sentence, not from any word.
  callEndsOpen o = isNothing (nlgOf o) && case carameliseNode o of
    App _ m margs@(_ : _)
      | isJust (daydateLiteral m margs) -> False
      | nameIs "Date" m, isJust (dateFromArgs margs) -> False
      | isJust (monthDateFromArgs m margs) -> False
      | [f, xs] <- margs, isJust (quantified m f xs) -> False
      | Just (nlg, inputs) <- Map.lookup (getUnique m) rd.rdHeralds, length inputs == length margs ->
          let bound = zip inputs margs
              refs  = Nlg.nlgRefs nlg
          in case [ x | (i, x) <- bound, i `notElem` refs ] of
               []       -> or [ endsOpen x | (i, x) <- bound, not (i `Set.member` Nlg.refsFollowedByWords nlg) ]
               leftover -> endsOpen (last leftover)
      | readsAsFunction m margs -> False
      | Just toks <- mixfixTokens m margs -> last toks == "_" && endsOpen (last margs)
      | otherwise -> endsOpen (last margs)
    _ -> False
  -- An argument that has no closing word: a condition that 'slotRunsOn', as it
  -- reads once rewritten, or a call that ends with one.
  endsOpen x = callEndsOpen x || slotRunsOn x' (leafText x')
   where
    x' = go x
  -- For each argument of a call whose sentence fits it, whether the sentence's
  -- words come after its slot.
  heraldSlots n args = case Map.lookup (getUnique n) rd.rdHeralds of
    Just (nlg, inputs)
      | length inputs == length args ->
          Just (map (`Set.member` Nlg.refsFollowedByWords nlg) inputs)
    _ -> Nothing
  -- A call that the f(x) clause in 'rw' prints, with its argument in brackets
  -- already: exactly one argument, a name in 'mathUnaryFns', and no sentence that
  -- the clause above would splice in first. The same conditions as that clause,
  -- so a rule that only shares the name ("round" with two inputs, or a "floor"
  -- or the library's "exp" with a sentence) is bracketed like any other call.
  -- JUST is a constructor, and reads as its value.
  readsAsFunction n args
    | nameIs "JUST" n = True
    | [_] <- args     = Map.member (nameToText (getActual n)) mathUnaryFns && not (heraldFits n args)
    | otherwise       = False
  heraldFits n args = case Map.lookup (getUnique n) rd.rdHeralds of
    Just (_, inputs) -> length inputs == length args
    Nothing          -> False
  -- An operand that is a call, a rule's sentence or an IF is printed as prose,
  -- and prose has no end: "f2 for 2 and x − 3" is also how @`f2` 2 (x MINUS 3)@
  -- would read, and "if c then 1 else 10 − x" how the IF with a subtraction in
  -- its ELSE would. So such an operand of an arithmetic operator is bracketed.
  -- It is told by the shape it had before it was rewritten, since rewritten it is
  -- 'Inert' text like any other leaf; a date written as literals, or a maths
  -- function, says where it ends and is not bracketed. No word of a name or a
  -- sentence is read.
  groupOperands orig new = case (carameliseNode orig, new) of
    (Plus _ a b,      Plus ann a' b')      -> Plus ann (operand a a') (operand b b')
    (Minus _ a b,     Minus ann a' b')     -> Minus ann (operand a a') (operand b b')
    (Times _ a b,     Times ann a' b')     -> Times ann (operand a a') (operand b b')
    (DividedBy _ a b, DividedBy ann a' b') -> DividedBy ann (operand a a') (operand b b')
    (Modulo _ a b,    Modulo ann a' b')    -> Modulo ann (operand a a') (operand b b')
    _ -> new
  operand o o'
    | opensAtEnd (carameliseNode o) =
        Inert (o' ^. annoOf) ("(" <> normalizeWs (simpleLinearizer o') <> ")") InertCtxNone
    | otherwise = o'
  opensAtEnd = \case
    App _ n args@(_ : _) ->
      isNothing (daydateLiteral n args)
        && not (nameIs "Date" n && isJust (dateFromArgs args))
        && isNothing (monthDateFromArgs n args)
        && not (readsAsFunction n args)
    AppNamed{}   -> True
    IfThenElse{} -> True
    MultiWayIf{} -> True
    Consider{}   -> True
    _            -> False
  isArithmetic = \case
    Plus{} -> True; Minus{} -> True; Times{} -> True; DividedBy{} -> True; Modulo{} -> True
    _ -> False
  rw orig = \case
    -- Drop WHERE / LET … IN binding wrappers; the body still reads.
    Where _ e _ -> e
    LetIn _ _ e -> e
    -- The implicit computed-field self.
    App ann n [] | nameIs "_self" n -> inert ann "it"
    Concat ann es -> inert ann (textParts es)
    -- Unary maths read as f(x), not "f with x".
    App ann n [x] | Just fn <- Map.lookup (nameToText (getActual n)) mathUnaryFns ->
      inert ann (fn <> "(" <> leafText x <> ")")
    -- Unary date/time component primitives read as "the year of x", not
    -- "DATE_YEAR with x". These appear in library bodies (and inlined calls).
    App ann n [x] | Just phrase <- Map.lookup (nameToText (getActual n)) builtinUnaryOf ->
      inert ann ("the " <> phrase <> " of " <> leafText x)
    -- Mixfix: interleave the arguments into the @_@ holes.
    App ann n args@(_ : _) | Just txt <- interleaveMixfix rd (argsEndOpen orig args) n args -> inert ann txt
    -- A function whose name ends in a preposition reads "minimum of x and y",
    -- not the linearizer's "minimum of with x and y".
    App ann n args@(_ : _) | endsInPreposition n ->
      inert ann (resolvedText n <> " " <> oxford "and" (map leafText args))
    -- A call to a rule reads by what the rule returns.
    App ann n args@(_ : _) | Just boolean <- Map.lookup (getUnique n) rd.rdRules ->
      inert ann (callPhrase n boolean args)
    -- A boolean field access drops the possessive: "the car has four wheels".
    Proj ann a n | predicateField n ->
      inert ann (leafText a <> " " <> resolvedText n)
    Proj ann a n | Just t <- booleanFieldPhrase rd a n -> inert ann t
    -- A present value reads as the value.
    App _ n [x] | nameIs "JUST" n -> x
    -- Comma-group large integers.
    Lit ann (NumericLit _ r) | Just t <- groupedInt r -> inert ann t
    e -> e

mathUnaryFns :: Map.Map Text Text
mathUnaryFns = Map.fromList
  [ ("exp", "exp"), ("ln", "ln"), ("log", "log"), ("sqrt", "sqrt")
  , ("abs", "abs"), ("floor", "floor"), ("ceiling", "ceil"), ("round", "round") ]

-- | Unary date/time-component builtins, rendered as "the <word> of <x>".
builtinUnaryOf :: Map.Map Text Text
builtinUnaryOf = Map.fromList
  [ ("DATE_YEAR", "year"), ("DATE_MONTH", "month"), ("DATE_DAY", "day")
  , ("DATETIME_DATE", "date"), ("DATETIME_TIME", "time")
  , ("DATETIME_TZ", "time zone")
  , ("TIME_HOUR", "hour"), ("TIME_MINUTE", "minute"), ("TIME_SECOND", "second")
  , ("DATETIME_SERIAL", "serial number"), ("TIME_SERIAL", "serial number")
  , ("DATE_SERIAL", "serial number") ]

-- | A list operation over a one-input function, said with the function's input
-- as the thing being talked about. "at least one item d of the family is such
-- that d is living" says what a herald with a slot for the function cannot,
-- because that slot would have to hold the condition and name its subject.
quantified :: Resolved -> Expr Resolved -> Expr Resolved -> Maybe Text
quantified n f xs = case carameliseNode f of
  Lam _ (MkGivenSig _ [MkOptionallyTypedName _ v _]) body
    | Just frame <- Map.lookup (resolvedText n) frames, fromPrelude n ->
        Just (frame (resolvedText v) (leafText xs) (leafText body))
  _ -> Nothing
 where
  frames = Map.fromList
    [ ("any",    \v l b -> fw "at least one item" <> " " <> v <> " " <> fw "of" <> " " <> l <> " " <> fw "is such that" <> " " <> b)
    , ("all",    \v l b -> fw "every item" <> " " <> v <> " " <> fw "of" <> " " <> l <> " " <> fw "is such that" <> " " <> b)
    , ("filter", \v l b -> fw "the items" <> " " <> v <> " " <> fw "of" <> " " <> l <> " " <> fw "such that" <> " " <> b)
    , ("map",    \v l b -> b <> ", " <> fw "for each item" <> " " <> v <> " " <> fw "of" <> " " <> l)
    , ("fmap",   \v l b -> b <> ", " <> fw "for each item" <> " " <> v <> " " <> fw "of" <> " " <> l)
    ]

-- | Is this name defined in the prelude, and not just named like something there?
fromPrelude :: Resolved -> Bool
fromPrelude r = "prelude.l4" `Text.isSuffixOf` uriText (getUnique r).moduleUri

-- | A call to a rule with no sentence of its own, read from what is known of it:
-- what it gives, and how many inputs it takes. The name stays whole, as the author
-- wrote it, and the arguments follow it.
callPhrase :: Resolved -> Bool -> [Expr Resolved] -> Text
callPhrase n boolean args
  | endsInPreposition n = term <> " " <> andList xs
  | boolean             = term <> " " <> fw "for" <> " " <> andList xs
  | otherwise = case (xs, Text.words name) of
      ([x], [_]) | isCapitalised -> term <> " " <> x
      ([x], ws) | length ws <= 2 -> term <> " " <> fw "of" <> " " <> x
      (_, [_]) | isCapitalised   -> term <> " " <> fw "with" <> " " <> andList xs
      _                          -> term <> " " <> fw "for" <> " " <> andList xs
 where
  name = resolvedText n
  term = "`" <> name <> "`"
  xs   = map leafText args
  isCapitalised = maybe False (isUpper . fst) (Text.uncons name)

-- | A BOOLEAN field states something of its record, so "the processing's the basis
-- is laid down by law" is never right. It reads as its own words, and says which
-- record it is about. An @\@nlg@ on the field is the author's whole wording.
booleanFieldPhrase :: Reading -> Expr Resolved -> Resolved -> Maybe Text
booleanFieldPhrase rd a n
  | not (getUnique n `Set.member` rd.rdBoolFields) = Nothing
  | hasHerald = Just field
  | otherwise = Just (field <> ", " <> fw "for" <> " " <> leafText a)
 where
  field = simpleLinearizer n
  hasHerald = isJust (getActual n ^. annoOf % annNlg) || isJust (getOriginal n ^. annoOf % annNlg)

-- | The phrases of a rule's inputs of a built-in type.
scalarInputs :: TypeSig Resolved -> Set.Set Text
scalarInputs (MkTypeSig _ (MkGivenSig _ names) _) = Set.fromList
  [ spaceCamel (cleanParam (resolvedText r))
  | MkOptionallyTypedName _ r mty <- names, isNothing (mty >>= userTypeName) ]

-- | A call whose name is a mixfix pattern with a hole for each argument: the
-- pattern's words.
mixfixTokens :: Resolved -> [Expr Resolved] -> Maybe [Text]
mixfixTokens n args =
  let toks  = Text.words (nameToText (getActual n))
      holes = length (filter (== "_") toks)
  in if holes >= 1 && holes == length args then Just toks else Nothing

-- | The arguments in a mixfix pattern's holes. Each comes with whether it is a
-- call that ends with a condition that has no closing word ('rewriteWith').
interleaveMixfix :: Reading -> [Bool] -> Resolved -> [Expr Resolved] -> Maybe Text
interleaveMixfix rd opens n args = do
  toks <- mixfixTokens n args
  Just (Text.unwords (fill toks (zip opens args)))
 where
  fill [] _ = []
  fill (t : ts) as
    | t == "_" = case as of
        (a : rest) -> hole (any (/= "_") ts) a : fill ts rest
        []         -> t : fill ts as
    | otherwise = t : fill ts as
  -- A hole that the pattern's own words come after, as a sentence's slot is
  -- ('slotRunsOn').
  hole followed (open, a)
    | followed, slotRunsOn a s || open = "(" <> s <> ")"
    | otherwise                         = s
   where
    s = slotText rd a


-- | An argument in a slot among an author's words: a pattern's, or a sentence's.
-- One that is just an input of the rule reads as a blank, as it does in the
-- rule's heading ('slotPhrases'). Any other reads as what it is.
slotText :: Reading -> Expr Resolved -> Text
slotText rd a = case a of
  Inert _ t _ | t `Set.member` rd.rdBlanks -> "[" <> t <> "]"
  _ -> leafText a

nameIs :: Text -> Resolved -> Bool
nameIs t r = nameToText (getActual r) == t

-- | A function whose name ends in a preposition, where "f with x" reads worse
-- than "f x" (e.g. "minimum of", "subject to CPF for").
endsInPreposition :: Resolved -> Bool
endsInPreposition r = case reverse (Text.words (nameToText (getActual r))) of
  (w : _) -> Text.toLower w `Set.member` prepositionWords
  []      -> False

prepositionWords :: Set.Set Text
prepositionWords = Set.fromList
  ["of", "for", "to", "from", "into", "onto", "on", "in", "by", "at"
  , "between", "than", "as", "after", "before", "among", "amongst"
  , "within", "per", "against", "upon", "about", "through", "during", "until"
  , "since", "with"]

-- | A field name that reads as a predicate, so its projection drops the
-- possessive: "the car has four wheels" rather than "the car's has four wheels".
predicateField :: Resolved -> Bool
predicateField r = case Text.words (nameToText (getActual r)) of
  (w : _) -> Text.toLower w `Set.member` predicateLeaders
  []      -> False

predicateLeaders :: Set.Set Text
predicateLeaders = Set.fromList
  ["is", "are", "was", "were", "has", "have", "had", "may", "must", "shall"
  , "can", "could", "should", "will", "does", "did", "do"]

-- | daydate's month helpers, @January 1 1972@, given as literals.
monthDateFromArgs :: Resolved -> [Expr Resolved] -> Maybe Text
monthDateFromArgs n [d, y] = do
  m <- List.lookup (resolvedText n) (zip (map monthName [1 .. 12]) [1 ..] <> zip (map (Text.take 3 . monthName) [1 .. 12]) [1 ..])
  dateFromArgs [d, Lit emptyAnno (NumericLit emptyAnno (fromInteger m)), y]
monthDateFromArgs _ _ = Nothing

dateFromArgs :: [Expr Resolved] -> Maybe Text
dateFromArgs [d, m, y]
  -- Only a day that exists. @Date@ rolls an out-of-range day forward, so printing
  -- 29 February 2025 for what is 1 March would state a date the rule does not.
  | Just di <- intLit d, Just mi <- intLit m, Just yi <- intLit y
  , isJust (fromGregorianValid yi (fromInteger mi) (fromInteger di)) =
      Just (showInt di <> " " <> monthName mi <> " " <> showInt yi)
dateFromArgs _ = Nothing

intLit :: Expr Resolved -> Maybe Integer
intLit (Lit _ (NumericLit _ r)) | denominator r == 1 = Just (numerator r)
intLit _ = Nothing

groupedInt :: Rational -> Maybe Text
groupedInt r
  | denominator r == 1, abs (numerator r) >= 10000 = Just (groupInt (numerator r))
  | otherwise = Nothing

groupInt :: Integer -> Text
groupInt n =
  let ds = show (abs n)
      grouped = reverse (List.intercalate "," (chunksOf 3 (reverse ds)))
  in Text.pack ((if n < 0 then "-" else "") <> grouped)

showInt :: Integer -> Text
showInt = Text.pack . show

monthName :: Integer -> Text
monthName = \case
  1 -> "January"; 2 -> "February"; 3 -> "March"; 4 -> "April"
  5 -> "May"; 6 -> "June"; 7 -> "July"; 8 -> "August"
  9 -> "September"; 10 -> "October"; 11 -> "November"; 12 -> "December"
  m -> "month " <> showInt m

-- ----------------------------------------------------------------------------
-- Plan construction
-- ----------------------------------------------------------------------------

buildPlan :: ExportConfig -> Module Resolved -> [Module Resolved] -> ExportPlan
buildPlan cfg mainModule deps =
  MkExportPlan
    { planMainModule = uriText mainUri
    , planModules    = mainPlanModule : importedPlanModules
    }
 where
  mainUri = moduleUri' mainModule
  units   = allUnits cfg.mixfixHeadings mainModule deps
  graph   = buildGraph mainUri units
  reach   = reachableUnits graph
  indexed = Map.toList graph.ugUnits
  isMain i = Set.member i graph.ugMain

  planUnitOf i u =
    MkPlanUnit
      { planId        = uniqueId u.uPrimary
      , planKind      = u.uKind
      , planHeading   = u.uHeading
      , planReachable = isMain i || Set.member i reach
      , planDefault   = if isMain i then Inline else resolveDisposition cfg u
      }

  mainPlanModule =
    MkPlanModule
      { planModuleUri    = uriText mainUri
      , planModuleLabel  = fst (documentTitleAndBody mainModule)
      , planModuleIsMain = True
      , planUnits        = [ planUnitOf i u | (i, u) <- indexed, isMain i ]
      }

  importedPlanModules =
    [ MkPlanModule
        { planModuleUri    = uriText uri
        , planModuleLabel  = moduleLabel uri
        , planModuleIsMain = False
        , planUnits        = us
        }
    | uri <- importedModuleOrder
    , let us = [ planUnitOf i u | (i, u) <- indexed, not (isMain i), u.uModule == uri ]
    , not (null us)
    ]
  importedModuleOrder = List.nub [ u.uModule | (i, u) <- indexed, not (isMain i) ]

-- ----------------------------------------------------------------------------
-- Title / small helpers
-- ----------------------------------------------------------------------------

-- | The document title and the section to render as its body. When the module
-- has no name of its own but wraps everything in a single leading @SECTION@,
-- that section's name becomes the title and its content is spliced up a level
-- (so a @§ Part 4@ wrapper titles the document and its @§§@ children become
-- the top-level sections). Otherwise the title is the title-cased file name.
documentTitleAndBody :: Module Resolved -> (Text, Section Resolved)
documentTitleAndBody m@(MkModule _ _ root@(MkSection _ mName _ _)) =
  case mName of
    Just n  -> (resolvedText n, root)
    Nothing -> case leadingSection root of
      Just hs -> hs
      Nothing -> (titleCase (moduleLabel (moduleUri' m)), root)

-- | Heading + body for an imported module: its leading section marker (when
-- present before any code), otherwise the file name. Mirrors
-- 'documentTitleAndBody' but with a file-name (not title-cased) fallback.
importHeadingAndBody :: NormalizedUri -> Module Resolved -> (Text, Section Resolved)
importHeadingAndBody uri (MkModule _ _ root@(MkSection _ mName _ _)) =
  case mName of
    Just n  -> (resolvedText n, root)
    Nothing -> case leadingSection root of
      Just hs -> hs
      Nothing -> (moduleLabel uri, root)

-- | Whether an imported module carries its own section title — a named module
-- root or a single leading section marker — as opposed to having nothing but a
-- file name to label it by. Drives whether it is wrapped under the generic
-- "Imported definitions" appendix.
importHasSectionTitle :: Module Resolved -> Bool
importHasSectionTitle (MkModule _ _ root@(MkSection _ mName _ _)) =
  isJust mName || isJust (leadingSection root)

-- | If a section is just a single named subsection with no loose declarations
-- before it, return that subsection's name and the subsection itself — the
-- "first section marker" used as a title/heading.
leadingSection :: Section Resolved -> Maybe (Text, Section Resolved)
leadingSection (MkSection _ _ _ decls) =
  case (any isUnitDecl decls, [ s | Section _ s <- decls ]) of
    (False, [s@(MkSection _ (Just sn) _ _)]) -> Just (resolvedText sn, s)
    _ -> Nothing
 where
  isUnitDecl = \case
    Decide{}  -> True
    Declare{} -> True
    Assume{}  -> True
    _         -> False

-- | Render an imported module as a section, preserving its own section markers.
buildImportSection
  :: (Block -> Int) -> Map.Map Unique Block -> NormalizedUri -> Module Resolved -> DocSection
buildImportSection rankOf bmap uri m =
  let (heading, MkSection _ _ _ decls) = importHeadingAndBody uri m
  in MkDocSection
    { sectionNumber  = ""
    , sectionHeading = Just heading
    , sectionGroups  = groupByKind rankOf (orderedBlocks bmap decls)
    , sectionSubs    = [ toDocSection rankOf bmap s | Section _ s <- decls ]
    }

titleCase :: Text -> Text
titleCase =
    Text.unwords
  . map cap
  . Text.words
  . Text.map (\c -> if c == '-' || c == '_' then ' ' else c)
 where
  cap w = case Text.uncons w of
    Just (c, rest) -> Text.cons (toUpper c) rest
    Nothing        -> w

resolvedText :: Resolved -> Text
resolvedText = nameToText . getActual

moduleUri' :: Module Resolved -> NormalizedUri
moduleUri' (MkModule _ uri _) = uri

uriText :: NormalizedUri -> Text
uriText u = (fromNormalizedUri u).getUri

moduleLabel :: NormalizedUri -> Text
moduleLabel u =
  let full = uriText u
      lastSeg = List.last (Text.splitOn "/" full)
  in fromMaybe lastSeg (Text.stripSuffix ".l4" lastSeg)

uniqueId :: Unique -> Text
uniqueId mu =
  Text.pack [mu.sort] <> ":" <> Text.pack (show mu.unique) <> ":" <> uriText mu.moduleUri

typeText :: Type' Resolved -> Text
typeText = \case
  TyApp _ n args -> case (resolvedText n, args) of
    ("MAYBE", [t]) -> typeText t <> ", " <> fw "if any"
    ("LIST", [t])  -> fw "list of" <> " " <> typeText t
    (name, [])     -> maybe (spaceCamel name) fw (Map.lookup name builtinTypeGloss)
    (name, _)      -> spaceCamel name <> " of " <> Text.intercalate ", " (map typeText args)
  Fun{}         -> "a function"
  Forall _ _ ty -> typeText ty
  Type{}        -> "a type"
  InfVar{}      -> "an inferred type"

-- | The built-in types, as a reader of a contract would name them.
builtinTypeGloss :: Map.Map Text Text
builtinTypeGloss = Map.fromList
  [ ("NUMBER", "number"), ("INTEGER", "whole number"), ("STRING", "text")
  , ("BOOLEAN", "yes or no"), ("DATE", "date"), ("TIME", "time")
  , ("DATETIME", "date and time"), ("MONEY", "amount of money")
  , ("PERCENT", "percentage") ]

-- ----------------------------------------------------------------------------
-- JSON
-- ----------------------------------------------------------------------------

instance Aeson.ToJSON UnitKind where
  toJSON = \case
    RuleUnit       -> Aeson.String "rule"
    TypeUnit       -> Aeson.String "type"
    AssumptionUnit -> Aeson.String "assumption"

instance Aeson.ToJSON Disposition where
  toJSON = \case
    Inline    -> Aeson.String "inline"
    Reference -> Aeson.String "reference"
    Exclude   -> Aeson.String "exclude"
    Hidden    -> Aeson.String "hidden"

instance Aeson.ToJSON RenderedAs where
  toJSON RenderedInline = Aeson.object ["kind" .= ("inline" :: Text)]
  toJSON (RenderedReference f) = Aeson.object ["kind" .= ("reference" :: Text), "forced" .= f]

instance Aeson.ToJSON Clause where
  toJSON = \case
    CLeaf t -> Aeson.object ["$type" .= ("leaf" :: Text), "text" .= t]
    CFields fs -> Aeson.object
      ["$type" .= ("fields" :: Text), "fields" .= map pair fs]
    CAll cs -> Aeson.object ["$type" .= ("all" :: Text), "clauses" .= cs]
    CAny cs -> Aeson.object ["$type" .= ("any" :: Text), "clauses" .= cs]
    CIf chain els -> Aeson.object
      ["$type" .= ("if" :: Text), "branches" .= map cond chain, "otherwise" .= els]
    CCases subj brs -> Aeson.object
      ["$type" .= ("cases" :: Text), "subject" .= subj, "cases" .= map cond brs]
    CDeontic party modal action due provided hence lest -> Aeson.object
      [ "$type" .= ("deontic" :: Text), "party" .= party, "modal" .= modal
      , "action" .= action, "deadline" .= due, "provided" .= provided
      , "hence" .= hence, "lest" .= lest ]
    CChain lead items -> Aeson.object
      [ "$type" .= ("chain" :: Text), "lead" .= lead, "items" .= items ]
    CTable cols rows -> Aeson.object
      [ "$type" .= ("table" :: Text), "columns" .= cols, "rows" .= rows ]
    CWhere body defs -> Aeson.object
      [ "$type" .= ("where" :: Text), "body" .= body, "definitions" .= map whereDef defs ]
    CLed lead body -> Aeson.object
      [ "$type" .= ("led" :: Text), "lead" .= lead, "body" .= body ]
    CLeadIn lead body -> Aeson.object
      [ "$type" .= ("leadIn" :: Text), "lead" .= lead, "body" .= body ]
    CLabel label body -> Aeson.object
      [ "$type" .= ("labelled" :: Text), "label" .= label, "body" .= body ]
   where
    pair (k, v) = Aeson.object ["label" .= k, "value" .= v]
    cond (c, cl) = Aeson.object ["condition" .= c, "clause" .= cl]
    whereDef (h, c, cl) = Aeson.object ["heading" .= h, "connector" .= c, "clause" .= cl]

instance Aeson.ToJSON Block where
  toJSON b = Aeson.object
    [ "id"           .= b.blockId
    , "kind"         .= b.blockKind
    , "heading"      .= b.blockHeading
    , "sentence"     .= b.blockSentence
    , "connector"    .= b.blockConnector
    , "body"         .= b.blockBody
    , "renderedAs"   .= b.blockRenderedAs
    , "citation"     .= b.blockCitation
    , "sources"      .= b.blockSources
    , "sourceModule" .= b.blockSourceModule
    , "imported"     .= b.blockImported
    ]

instance Aeson.ToJSON DocGroup where
  toJSON g = Aeson.object ["label" .= g.groupLabel, "lead" .= g.groupLead, "blocks" .= g.groupBlocks]

instance Aeson.ToJSON DocSection where
  toJSON s = Aeson.object
    [ "number"      .= s.sectionNumber
    , "heading"     .= s.sectionHeading
    , "groups"      .= s.sectionGroups
    , "subsections" .= s.sectionSubs
    ]

instance Aeson.ToJSON Document where
  toJSON d = unmarked (Aeson.object ["title" .= d.docTitle, "sections" .= d.docSections])
   where
    -- The marks are a matter between this module and the writers.
    unmarked = \case
      Aeson.String t -> Aeson.String (stripFrameMarks t)
      Aeson.Array a  -> Aeson.Array (fmap unmarked a)
      Aeson.Object o -> Aeson.Object (fmap unmarked o)
      v              -> v

instance Aeson.ToJSON PlanUnit where
  toJSON p = Aeson.object
    [ "id"                 .= p.planId
    , "kind"               .= p.planKind
    , "heading"            .= p.planHeading
    , "reachable"          .= p.planReachable
    , "defaultDisposition" .= p.planDefault
    ]

instance Aeson.ToJSON PlanModule where
  toJSON p = Aeson.object
    [ "uri"    .= p.planModuleUri
    , "label"  .= p.planModuleLabel
    , "isMain" .= p.planModuleIsMain
    , "units"  .= p.planUnits
    ]

instance Aeson.ToJSON ExportPlan where
  toJSON p = Aeson.object ["mainModule" .= p.planMainModule, "modules" .= p.planModules]
