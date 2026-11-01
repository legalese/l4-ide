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
import Data.Char (isLower, isUpper, toLower, toUpper)
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
import L4.Nlg (daydateLiteral, simpleLinearizer, NlgFnInfo, nlgFnInfo, substituteNlgCall, renderNlgWith, normalizeWs, oxford)
import qualified L4.Nlg as Nlg
import L4.Syntax
import L4.Names (stripSectionBinderElaborations)
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
             (Maybe Text)                      -- ^ the window, with its own prepositions: "within 30",
                                               --   "within 30 of the join", "after 3, within 30 of that"
                                               --   (the re-anchored window, EVERY-EACH-QUANTIFIER-SPEC
                                               --   §5.1.2.2), "after 3", "before 30 June" (§5.1.2),
                                               --   "immediately" (WITHIN 0); 'Nothing' for no window
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
  , blockSourceModule :: !Text
  , blockImported     :: !Bool
  }
  deriving stock (Show, Generic)

data DocGroup = MkDocGroup
  { groupLabel  :: !(Maybe Text)
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
-- document, and the inputs of the rule itself.
data Reading = MkReading
  { rdHeralds    :: !NlgFnInfo
  , rdRules      :: !(Map.Map Unique RuleShape)
  , rdBoolFields :: !(Set.Set Unique)
  , rdSubjects   :: !(Set.Set Text)
    -- ^ How the enclosing rule's subjects read: an input of a user type that is
    -- the only one of its type. Passing one on says nothing a reader needs, and
    -- no other input could be confused with it.
  }

-- | What a call needs to know of the rule it calls.
data RuleShape = MkRuleShape
  { rsBoolean :: !Bool
  , rsInputs  :: ![Text]
  }

noReading :: Reading
noReading = MkReading Map.empty Map.empty Set.empty Set.empty

extractUnits :: Module Resolved -> [Unit]
extractUnits (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ _ decls) = concatMap goDecl decls
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
      reading = MkReading info (ruleShapes mods) (booleanFields mods) Set.empty
  in map (\u -> (mapUnitBody (normalizePositionalRecords ctors) . fixMixfixHeading headings $ u)
                  { uCalls = calls, uReading = reading })
       (extractUnits mainModule <> concatMap extractUnits deps)

-- | Every rule's shape, keyed by the definition a call resolves to.
ruleShapes :: [Module Resolved] -> Map.Map Unique RuleShape
ruleShapes mods = Map.fromList
  [ (getUnique n, MkRuleShape (returnsBoolean tysig) [ resolvedText a | a <- args ])
  | m <- mods
  , Decide _ (MkDecide _ tysig (MkAppForm _ n args _) _) <- topDeclsRec m
  ]

-- | The record fields of type BOOLEAN. Such a field states something about its
-- record, so a possessive is always the wrong way to read it.
booleanFields :: [Module Resolved] -> Set.Set Unique
booleanFields mods = Set.fromList
  [ getUnique n
  | m <- mods
  , Declare _ (MkDeclare _ _ _ (RecordDecl _ _ fields)) <- topDeclsRec m
  , MkTypedName _ n ty _ _ <- fields
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
  [ (getUnique con, [ n | MkTypedName _ n _ _ _ <- fields ])
  | m <- mods
  , Declare _ (MkDeclare _ _ _ (RecordDecl _ (Just con) fields)) <- topDeclsRec m
  ]

-- | All top-level declarations of a module, descending through @SECTION@s.
topDeclsRec :: Module Resolved -> [TopDecl Resolved]
topDeclsRec (MkModule _ _ sec) = go sec
 where
  go (MkSection _ _ _ _ ds) = concatMap (\d -> d : nested d) ds
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
-- module, 'L4.Relational.Lower' and @l4 nlg@ had three different answers for the
-- same bytes while two of them kept the same list of positions by hand
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
  let types = paramTypeMap tysig
      tok (MixfixKeyword kw) = rawNameToText kw
      tok (MixfixParam p)    =
        let pn = rawNameToText p
        in paramPhrase pn (Map.findWithDefault Nothing pn types)
  in normalizeWs (Text.unwords (map tok info.pattern))

-- | Each GIVEN parameter's name to its (optional) declared type.
paramTypeMap :: TypeSig Resolved -> Map.Map Text (Maybe (Type' Resolved))
paramTypeMap (MkTypeSig _ (MkGivenSig _ names) _) =
  Map.fromList [ (resolvedText r, mty) | MkOptionallyTypedName _ r mty _ <- names ]

-- | "a Person buyer" / "an Order item" — article + type + parameter name.
-- Falls back to the bare parameter name when no type is available.
paramPhrase :: Text -> Maybe (Type' Resolved) -> Text
paramPhrase pname mty = case mty >>= typeDisplay of
  Just ty -> withArticle ty <> " " <> cleanParam pname
  Nothing -> cleanParam pname
 where
  typeDisplay ty = case userTypeName ty of
    Just t  -> Just (spaceCamel t)
    Nothing -> case ty of
      TyApp _ n _ -> Just (nameToText (getActual n))   -- builtin, e.g. NUMBER
      _           -> Nothing

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
assumeApp (MkAssume _ _ (MkAppForm _ n _ _) _ _) = n

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
buildDocument cfg mainModule0 deps0 =
  MkDocument
    { docTitle    = title
    -- Number after pruning, so dropped (e.g. test-fixture) sections never
    -- consume a number — numbering always starts at § 1 and stays contiguous.
    , docSections = renumberSections "" (mainSections <> importedSections)
    }
 where
  -- A section binder's elaboration is machinery for the checker and the
  -- evaluator, not a provision of the document; rendering it would add a
  -- phantom ASSUME line under every heading whose source says GIVEN.
  mainModule = stripSectionBinderElaborations mainModule0
  deps       = map stripSectionBinderElaborations deps0
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
                     , sectionHeading = Just "Imported definitions"
                     , sectionGroups  = []
                     , sectionSubs    = secs
                     } ]
  importedModuleOrder = List.nub [ u.uModule | (i, u) <- indexed, not (isMain i) ]

-- | Build one section subtree, leaving 'sectionNumber' blank — numbering is a
-- separate post-pass ('renumberSections') run after empty sections are pruned.
toDocSection :: (Block -> Int) -> Map.Map Unique Block -> Section Resolved -> DocSection
toDocSection rankOf bmap (MkSection _ mName _ _ decls) =
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
bodyToSections rankOf bmap (MkSection _ _ _ _ decls) =
  let groupSecs =
        [ MkDocSection
            { sectionNumber  = ""
            , sectionHeading = Just (groupSectionHeading g)
            , sectionGroups  = [ g { groupLabel = Nothing } ]
            , sectionSubs    = []
            }
        | g <- groupByKind rankOf (orderedBlocks bmap decls) ]
      subSecs = [ toDocSection rankOf bmap s | Section _ s <- decls ]
  in groupSecs <> subSecs

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
    [ MkDocGroup { groupLabel = lbl, groupBlocks = bs }
    | (lbl, k, sortIt) <- [ (Just "Definitions", TypeUnit, True)
                          , (Just "Assumptions", AssumptionUnit, False)
                          , (Nothing, RuleUnit, False)
                          ]
    , let raw = filter (\b -> b.blockKind == k) blocks
          bs  = if sortIt then List.sortOn rankOf raw else raw
    , not (null bs)
    ]
  labelRules g = case g.groupLabel of
    Nothing -> g { groupLabel = Just "Provisions" }
    Just _  -> g

pruneSection :: DocSection -> Maybe DocSection
pruneSection s =
  let subs' = mapMaybe pruneSection s.sectionSubs
  in if null s.sectionGroups && null subs'
       then Nothing
       else Just s { sectionSubs = subs' }

directiveRefsOf :: Module Resolved -> Set.Set Unique
directiveRefsOf (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ _ decls) = Set.unions (map goDecl decls)
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
    any (\(MkOptionallyTypedName _ r _ _) -> nameToText (getActual r) == "_self") params
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
    , blockSourceModule = uriText u.uModule
    , blockImported     = True
    }

-- | The sentence a rule reads as, with its own inputs in the slots.
--
-- An @\@nlg@ on a rule adds to the rule: it says what the rule is about, and the
-- body still says how. So "the applicant qualifies for the grant" heads the
-- conditions. Only a rule whose body says nothing to the document's reader is
-- read as the sentence alone ('readsAsItsSentence').
unitSentence :: Unit -> Maybe Text
unitSentence u = case u.uDecl of
  UDecide d@(MkDecide _ tysig _ _)
    | not (readsAsItsSentence False u), Just nlg <- decideNlg d ->
        Just (renderNlgWith (Map.map inputPhrase (paramSubst tysig)) nlg)
  _ -> Nothing
 where
  inputPhrase t = Inert emptyAnno t InertCtxNone

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
    UAssume a@(MkAssume _ _ af _ _) -> (a ^. annoOf % annRefs) <> headRefs af
  headRefs af@(MkAppForm _ n _ _) = (af ^. annoOf % annRefs) <> (getActual n ^. annoOf % annRefs)

unitRendering :: Bool -> Unit -> (Text, Clause)
unitRendering imported u = case u.uDecl of
  UDecide d@(MkDecide _ tysig _ body)
    | Just nlg <- decideNlg d, readsAsItsSentence imported u ->
        ( if returnsBoolean tysig then "holds if" else "means"
        , CLeaf (renderNlgWith Map.empty nlg) )
    -- Otherwise rewrite the body up front (mixfix/maths/dates/numbers/params ->
    -- Inert leaves) so formula mode survives arithmetic that contains a mixfix
    -- call or a function like @exp@/@ln@. A top-level @WHERE@/@LET@ is peeled off
    -- first so its local definitions (which 'rewriteExpr' would otherwise drop)
    -- render as an attached "where:" block.
    | otherwise ->
        let subst              = paramSubst tysig
            reading            = u.uReading { rdSubjects = ruleSubjects subst tysig }
            -- Normalised first: until then an AND can sit inside a call's
            -- argument, and phrasing that argument would swallow the condition.
            (inner, locals)    = peelWhere (distributeCalls (carameliseExpr (clauseLayout body)))
            read'              = collapseTruth . rewriteWith reading . substParams subst
            (conn, mainClause) = decideRendering u.uCalls tysig (read' inner)
        in case mapMaybe (localDefClause reading u.uCalls subst) locals of
             []   -> (conn, mainClause)
             defs -> (conn, CWhere mainClause defs)
  UAssume _ -> ("is assumed to be given", CLeaf "")
  UDeclare (MkDeclare _ _ _ tyDecl) ->
    case tyDecl of
      RecordDecl _ _ (_ : _) -> ("consists of", declareClause tyDecl)
      EnumDecl _ cons
        | longEnum cons -> ("means one of", CFields [ (conName c, "") | c <- cons ])
      -- An opaque type says nothing about its values, so the sentence has
      -- no object: "Person is a kind of thing." (the @ASSUME@ spelling of the
      -- same declaration reads "Person is assumed to be given.").
      OpaqueDecl _           -> ("is a kind of thing", CLeaf "")
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
        (conn, clause) = decideRendering calls ltysig
                           (collapseTruth (rewriteWith reading (substParams subst (distributeCalls (carameliseExpr lbody)))))
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
               | MkOptionallyTypedName _ r mty _ <- names ]
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
      lowerOrdinary w = case Text.unpack w of
        (c : d : _) | isUpper c, isUpper d -> w
        _                                  -> Text.toLower w
  in Map.fromList [ (u, phraseOf pname mtn) | (u, pname, mtn) <- params ]

-- | The phrases of a rule's inputs that are the only one of their type.
ruleSubjects :: Map.Map Unique Text -> TypeSig Resolved -> Set.Set Text
ruleSubjects subst (MkTypeSig _ (MkGivenSig _ names) _) =
  let typed = [ (tn, getUnique r) | MkOptionallyTypedName _ r mty _ <- names, Just tn <- [mty >>= userTypeName] ]
      counts = Map.fromListWith (+) [ (tn, 1 :: Int) | (tn, _) <- typed ]
  in Set.fromList [ p | (tn, u) <- typed, Map.lookup tn counts == Just 1, Just p <- [Map.lookup u subst] ]

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
  lowerWord w = case Text.unpack w of
    (c : d : _) | isUpper c, isUpper d -> w
    _                                  -> Text.toLower w

connectorFor :: TypeSig Resolved -> Expr Resolved -> Text
connectorFor tysig body
  | returnsBoolean tysig = "holds if"
  | otherwise = case carameliseNode body of
      Consider{} -> "is determined by"
      And{}      -> "holds if"
      Or{}       -> "holds if"
      Not{}      -> "holds if"
      Equals{}   -> "holds if"
      Geq{}      -> "holds if"
      Leq{}      -> "holds if"
      Gt{}       -> "holds if"
      Lt{}       -> "holds if"
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
  OpaqueDecl _          -> CLeaf "a kind of thing"
 where
  recordField (MkTypedName _ n ty _mTypically Nothing)     = (resolvedText n, typeText ty)
  recordField (MkTypedName _ n ty _mTypically (Just expr)) =
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
  And{}              -> CAll (map toClause (flattenAnd e0))
  Or{}               -> CAny (map toClause (flattenOr e0))
  Concat _ es        -> CLeaf (textParts es)
  Cons{}
    | Just c <- listChainClause e0 -> c
  RAnd{}             -> CAll (map toClause (flattenAnd e0))
  ROr{}              -> CAny (map toClause (flattenOr e0))
  -- A ledger write with a HENCE is a step, and what follows it is a clause of
  -- its own, often an obligation: the write, and then the rest, as two entries.
  -- Folded into one sentence, an obligation after it read "and then party
  -- landlord must deliver has within 20".
  -- A run of such steps is one list.
  Record _ mParty cell val isOfficial (Just k) ->
    CAll ( CLeaf (inlineProse cell <> " is recorded as " <> inlineProse val <> ledgerOf mParty isOfficial)
         : case (carameliseNode k, toClause k) of
             (Record _ _ _ _ _ (Just _), CAll rest) -> rest
             (_, next)                             -> [next] )
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
    PatApp _ con [] | nameIs "NOTHING" con -> Just "absent"
                    | otherwise            -> Just (spaceCamel (resolvedText con))
    PatApp _ con [p] | nameIs "JUST" con   -> valueName p
    PatLit _ l                                   -> Just (patternText (PatLit emptyAnno l))
    _                                            -> Nothing
  test _ _ [] = Nothing
  test subj True [v]  = Just (subj <> " is " <> v)
  test subj False [v] = Just (subj <> " is not " <> v)
  test subj True vs   = Just (subj <> " is one of " <> oxford "or" vs)
  test subj False vs  = Just (subj <> " is not one of " <> oxford "or" vs)

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
    | nameIs "NOTHING" con -> "is absent"
    | nameIs "EMPTY" con   -> "is empty"
  PatApp _ con [p]
    | nameIs "JUST" con -> case p of
        PatVar _ v -> "is present, with the value " <> resolvedText v
        _          -> patternPredicate p
  PatVar _ v -> "is any value, called " <> resolvedText v
  PatCons _ a b -> "starts with " <> patternText a <> ", followed by " <> patternText b
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
  Equals _ a b         -> side a <> " is " <> side b
  Not _ inner          -> case carameliseNode inner of
    Equals _ a b -> side a <> " is not " <> side b
    n | isAndNode n -> notAllText (flattenAnd n)
      | isOrNode n  -> case oneOfParts n of
          Just (lhs, rhs) -> lhs <> " is not one of " <> oxford "or" rhs
          Nothing         -> noneOfText (flattenOr n)
    _            -> negated (condText inner)
  Geq _ a b            -> side a <> " is at least " <> side b
  Leq _ a b            -> side a <> " is at most " <> side b
  Gt _ a b             -> side a <> " is more than " <> side b
  Lt _ a b             -> side a <> " is less than " <> side b
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
joinCond conj parts
  | any isCompound parts = case (parts, map groupText parts) of
      (p : _, [x, y])
        | isCompound p -> x <> ", " <> conj <> " " <> y
        | otherwise    -> x <> " " <> conj <> " " <> y
      (_, xs) -> oxford conj xs
  | otherwise = Text.intercalate (" " <> conj <> " ") (map condText parts)

-- | A statement, denied in the way a drafter would. A clause with exactly one
-- verb that can take the negation takes it there; a single name is false; and
-- anything else keeps the long form, because the scope of a "not" placed inside
-- it would be a guess. "Must" is left out on purpose: "must not" is a prohibition
-- and not the denial of an obligation.
negated :: Text -> Text
negated t
  | Text.isInfixOf " not " padded = long
  | any (`Text.isInfixOf` padded) [" and ", " or ", " if "] = long
  | otherwise = case [ pair | pair@(v, _) <- negations, Text.isInfixOf v padded ] of
      [(v, n)] | Text.count v padded == 1 -> Text.strip (Text.replace v n padded)
      _ | length (Text.words t) == 1 -> t <> " is false"
        | otherwise                  -> long
 where
  padded = " " <> t <> " "
  long = "it is not the case that " <> t
  negations =
    [ (" is ", " is not "), (" are ", " are not "), (" was ", " was not ")
    , (" were ", " were not "), (" has ", " does not have "), (" have ", " do not have ")
    , (" may ", " may not "), (" can ", " cannot "), (" will ", " will not ")
    , (" does ", " does not "), (" do ", " do not ") ]

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
        [a, b] -> "both " <> a <> " and " <> b
        xs     -> "all of " <> oxford "and" xs
    | isCompound n, isOrNode n -> case map itemText (flattenOr n) of
        [a, b] -> "either " <> a <> " or " <> b
        xs     -> "any of " <> oxford "or" xs
  _ -> condText e

itemText :: Expr Resolved -> Text
itemText e
  | isCompound e = "(" <> condText e <> ")"
  | otherwise    = condText e

-- | The negation of an AND, which denies only that all of it holds.
notAllText :: [Expr Resolved] -> Text
notAllText parts = case map itemText parts of
  [a, b] -> "not both " <> a <> " and " <> b
  xs     -> "not all of " <> oxford "and" xs

-- | The negation of an OR, which denies each of its operands.
noneOfText :: [Expr Resolved] -> Text
noneOfText parts = case map itemText parts of
  [a, b] -> "neither " <> a <> " nor " <> b
  xs     -> "none of " <> oxford "or" xs

-- | Detect @x = A OR x = B OR …@ (same left side) and collapse to a membership.
oneOfText :: Expr Resolved -> Maybe Text
oneOfText e = do
  (lhs, rhs) <- oneOfParts e
  Just (lhs <> " is one of " <> oxford "or" rhs)

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
deonticClause (MkDeonton _ subj (MkAction _ modal actPat mprov) mopens mdue _join mhence mlest) =
  -- The @ONCE …@ join line is not rendered by this export: 'CDeontic' has no
  -- slot for it. That was written when the barrier/fork distinction had no
  -- run-time meaning at all; it now has one (phase 2, 2026-09-08), so the
  -- exported prose is missing a distinction the language draws. The limit is
  -- stated on the doc page for EVERY.
  CDeontic
    (subjectProse subj)
    (modalWord modal)
    (patternText actPat)
    (windowText mopens mdue)
    (fmap toClause mprov)
    (mhence >>= henceClause)
    (fmap consequence mlest)
 where
  -- The window as one phrase (EVERY-EACH-QUANTIFIER-SPEC §5.1.2): the
  -- opening edge, "after 3" / "after 3 of the join" / "after 30 June", then
  -- the closing edge, "within 30 of the join" / "before 30 June" — and,
  -- beside an opening edge, a bare "within 30" reads "within 30 of that",
  -- because it counts from the instant the window opened (re-anchor,
  -- §5.1.2.2).
  windowText mo md =
    case catMaybes [ fmap openingText mo, fmap (dueText (isJust mo)) md ] of
      []     -> Nothing
      phrases -> Just (Text.intercalate ", " phrases)
  openingText (MkOpening _ d ma) =
    "after " <> inlineProse d <> maybe "" (\ a -> " of " <> anchorProse a) ma
  -- The duration as prose, then the anchor when there is one (R-Q7,
  -- §5.1.1): "5 of the join", "5 of the deadline", "5 of closingDate".
  -- A deadline of zero leaves no time to act, which is not the same thing as
  -- no deadline at all: a rule with no WITHIN waits for ever. So an unanchored
  -- WITHIN 0 reads "immediately" (legalese/l4-ide#802), and is no longer left
  -- out; beside an opening edge it reads as written, "within 0 of that".
  dueText afterOpening = \ case
    MkDeadline _ d ma
      | isZeroLit d, Nothing <- ma, not afterOpening -> "immediately"
      | otherwise ->
          "within " <> inlineProse d
            <> maybe (if afterOpening then " of that" else "") (\ a -> " of " <> anchorProse a) ma
    MkBefore _ e -> "before " <> inlineProse e
  anchorProse = \ case
    AnchorJoin _     -> "the join"
    AnchorDeadline _ -> "the deadline"
    AnchorArming _   -> "the arming"
    AnchorAt _ e     -> inlineProse e
  henceClause h
    | isFulfilled h = Nothing
    | otherwise     = Just (consequence h)
  -- Who is in breach is part of the rule, so a BREACH BY says so. Without a BY
  -- the rule does not name anyone, and neither does this.
  consequence e = case e of
    Breach _ mParty mReason ->
      CLeaf (maybe "the obligation is breached" (\p -> inlineProse p <> " is in breach") mParty
               <> maybe "" (\r -> " because “" <> inlineProse r <> "”") mReason)
    Refuse _ msg ->
      CLeaf ("the model refuses to answer: “" <> inlineProse msg <> "”")
    _ -> toClause e

-- | The subject of a deontic clause as prose: the party, or the quantifier
-- read aloud (@every Tenant t who …@).
subjectProse :: Subject Resolved -> Text
subjectProse = \case
  Party _ party -> inlineProse party
  Every _ mCast v mRoll mFilter ->
    "every "
      <> maybe "" (\c -> nameToText (getActual c) <> " ") mCast
      <> nameToText (getActual v)
      <> maybe "" (\r -> " in " <> inlineProse r) mRoll
      <> maybe "" (\f -> case f of
                     Who _ e   -> " who " <> inlineProse e
                     Whose _ e -> " whose " <> inlineProse e) mFilter

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
              | i == (0 :: Int) || uniform = leafText t
              | otherwise                  = word op <> " " <> leafText t
        in Just (CChain lead (zipWith line [0 ..] terms))
  addWord o = if o == "-" then "minus" else "plus"
  mulWord o = if o == "÷" then "divided by" else "times"

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
    Times _ a b     -> bin 2 " × " a b
    DividedBy _ a b -> binRight 2 " ÷ " a b
    Modulo _ a b    -> binRight 2 " mod " a b
    Lit _ (NumericLit _ r) -> Just (4, numText r)
    Percent _ x     -> do (_, t) <- go x; Just (4, t <> "%")
    App _ n []      -> Just (4, resolvedText n)
    Inert _ t _     -> Just (4, t)   -- a substituted parameter phrase
    -- A refusal has no arithmetic reading; rendering it as prose inside a
    -- formula would read as a quantity. Bail out of formula mode entirely.
    Refuse{}        -> Nothing
    Proj _ a nm     -> do (_, t) <- go a; Just (4, t <> "'s " <> resolvedText nm)
    -- A non-arithmetic operand (a function call, projection chain, parameter …)
    -- becomes an inline atom rendered as prose, so a formula that mixes
    -- arithmetic with such terms still reads as "a + b × f(x)" rather than
    -- collapsing the whole expression back to nested "the sum of …" prose.
    other           -> Just (4, normalizeWs (simpleLinearizer other))
  bin p op a b = do
    (pa, ta) <- go a
    (pb, tb) <- go b
    Just (p, wrap p pa ta <> op <> wrap p pb tb)
  -- The right operand of a subtraction or a division keeps its brackets at equal
  -- precedence too: a − (b − c) is not a − b − c, and a ÷ (b × c) is not a ÷ b × c.
  binRight p op a b = do
    (pa, ta) <- go a
    (pb, tb) <- go b
    Just (p, wrap p pa ta <> op <> wrap (p + 1) pb tb)
  wrap parentP childP t = if childP < parentP then "(" <> t <> ")" else t

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
rewriteWith rd = transformOf (gplate @(Expr Resolved)) (rw . herald)
 where
  inert ann t = Inert ann t InertCtxNone
  herald = \case
    -- A date given as literals reads as the date, whatever its rule's sentence.
    App ann n args | Just (d, m, y) <- daydateLiteral n args -> inert ann (Text.unwords [d, m, y])
    App ann n args | nameIs "Date" n, Just t <- dateFromArgs args -> inert ann t
    App ann n args | Just t <- monthDateFromArgs n args -> inert ann t
    App ann n [f, xs] | Just t <- quantified n f xs -> inert ann t
    -- Joined lists read as one list, so a long chain of them can be laid out.
    App ann n [a, b] | resolvedText n == "append", fromPrelude n -> Cons ann a b
    App ann n args -> substituteNlgCall Nothing rd.rdHeralds (App ann n (map phrased args))
    e -> substituteNlgCall Nothing rd.rdHeralds e
  phrased a = Inert (a ^. annoOf) (leafText a) InertCtxNone
  rw = \case
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
    App ann n args@(_ : _) | Just txt <- interleaveMixfix n args -> inert ann txt
    -- A function whose name ends in a preposition reads "minimum of x and y",
    -- not the linearizer's "minimum of with x and y".
    App ann n args@(_ : _) | endsInPreposition n ->
      inert ann (resolvedText n <> " " <> oxford "and" (map leafText args))
    -- A call to a rule reads by what the rule returns.
    App ann n args@(_ : _) | Just shape <- Map.lookup (getUnique n) rd.rdRules ->
      inert ann (callPhrase rd n shape args)
    -- A boolean field access drops the possessive: "the car has four wheels".
    Proj ann a n | predicateField n ->
      inert ann (leafText a <> " " <> resolvedText n)
    Proj ann a n | Just t <- booleanFieldPhrase rd a n -> inert ann t
    -- A present value reads as the value.
    App _ n [x] | nameIs "JUST" n -> x
    -- Comma-group large integers.
    Lit ann (NumericLit _ r) | Just t <- groupedInt r -> inert ann t
    -- The constructs below exist on unstable and not on main, so the prose pass
    -- ported from legalese/l4-ide#802 had no word for them, and they fell to the
    -- linearizer, which echoes their keywords ("record balance is 100"). Each is
    -- said here instead; @jl4/tests-cli/fixtures/render-unstable-constructs.l4@
    -- pins every one.
    --
    -- A ledger write (STATE-AS-LEDGER) is the value it records, and says where.
    -- One with a HENCE is a step of a contract, and is left for 'toClause',
    -- which every HENCE and LEST reaches, to lay out with what follows it.
    Record ann mParty cell val isOfficial Nothing ->
      inert ann (leafText val <> ", recorded as " <> leafText cell <> ledgerOf mParty isOfficial)
    -- A ledger read is the value recorded there: the last one, which may be
    -- absent, or all of them.
    ReadCell ann mParty isOfficial mode cell -> inert ann $ case mode of
      RecallLast -> "the value last recorded as " <> leafText cell <> ledgerOf mParty isOfficial <> ", if any"
      RecallAll  -> "every value recorded as " <> leafText cell <> ledgerOf mParty isOfficial <> ", oldest first"
    -- A lifecycle noun as a value, in the words a deadline's anchor uses
    -- ('deonticClause', @anchorProse@).
    Lifecycle ann p -> inert ann $ case p of
      LifecycleJoin     -> "the join"
      LifecycleDeadline -> "the deadline"
      LifecycleArming   -> "the arming"
    -- A refusal is not a value, and says so in the author's words.
    Refuse ann msg -> inert ann ("the model refuses to answer: " <> leafText msg)
    e -> e

-- | Whose ledger a write or a read is on, after the cell's name: nothing for the
-- acting party's own.
ledgerOf :: Maybe (Expr Resolved) -> Bool -> Text
ledgerOf mParty isOfficial
  | isOfficial       = " in the official record"
  | Just q <- mParty = " in " <> leafText q <> "'s record"
  | otherwise        = ""

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
  Lam _ (MkGivenSig _ [MkOptionallyTypedName _ v _ _]) body
    | Just frame <- Map.lookup (resolvedText n) frames, fromPrelude n ->
        Just (frame (resolvedText v) (leafText xs) (leafText body))
  _ -> Nothing
 where
  frames = Map.fromList
    [ ("any",    \v l b -> "at least one item " <> v <> " of " <> l <> " is such that " <> b)
    , ("all",    \v l b -> "every item " <> v <> " of " <> l <> " is such that " <> b)
    , ("filter", \v l b -> "the items " <> v <> " of " <> l <> " such that " <> b)
    , ("map",    \v l b -> b <> ", for each item " <> v <> " of " <> l)
    , ("fmap",   \v l b -> b <> ", for each item " <> v <> " of " <> l)
    ]

-- | Is this name defined in the prelude, and not just named like something there?
fromPrelude :: Resolved -> Bool
fromPrelude r = "prelude.l4" `Text.isSuffixOf` uriText (getUnique r).moduleUri

-- | A call to a rule with no sentence of its own, read from what is known of it.
--
-- Each input is placed by what the sentence needs, in this order, so that an
-- argument can never end up saying something about the wrong party:
--
-- * A predicate with a leading verb takes its first argument as its subject,
--   even one the enclosing rule is about, because the sentence needs one.
--
-- * An input the rule's name mentions takes the argument in its place, so
--   @`the person left living descendants`@ on @d@ reads "d left living
--   descendants", and @`is a descendant of the ancestor`@ on @d@ and @p@ reads
--   "d is a descendant of p".
--
-- * An input that is just one of the enclosing rule's subjects is dropped. The
--   rule is already about it, and no other input could be mistaken for it.
--
-- * Anything left follows the name.
callPhrase :: Reading -> Resolved -> RuleShape -> [Expr Resolved] -> Text
callPhrase rd n shape args = case (leadVerb, inputs) of
  (True, (_, s) : more) -> leafText s <> " " <> placed more
  _                     -> placed inputs
 where
  name   = resolvedText n
  inputs = zip (shape.rsInputs <> repeat "") args
  placed ps =
    let (mentioned, others) = List.partition (mentions . fst) ps
        term = case mentioned of
          [] -> "`" <> name <> "`"
          _  -> List.foldl' fill name [ (p, leafText a) | (p, a) <- mentioned ]
    in trailing term [ leafText a | (_, a) <- others, not (isSubject a) ]
  mentions p = Text.length p > 1 && Text.isInfixOf (" " <> p <> " ") (" " <> name <> " ")
  -- An article on the input's name goes with it: the argument brings its own.
  fill t (p, a) =
    let padded = " " <> t <> " "
        withArticle' = " the " <> p <> " "
        slot = if withArticle' `Text.isInfixOf` padded then withArticle' else " " <> p <> " "
    in Text.strip (Text.replace slot (" " <> a <> " ") padded)
  leadVerb = shape.rsBoolean && case Text.words name of
    w : _ -> Text.toLower w `Set.member` predicateLeaders
    []    -> False
  isSubject = \case
    Inert _ t _ -> t `Set.member` rd.rdSubjects
    _           -> False
  trailing term = \case
    [] -> term
    xs | endsInPreposition n -> term <> " " <> oxford "and" xs
       | shape.rsBoolean     -> term <> " for " <> oxford "and" xs
    [x] | [_] <- Text.words name, isCapitalised name -> term <> " " <> x
        | length (Text.words name) <= 2              -> term <> " of " <> x
    xs | [_] <- Text.words name, isCapitalised name -> term <> " with " <> oxford "and" xs
       | otherwise                                  -> term <> " for " <> oxford "and" xs
  isCapitalised t = maybe False (isUpper . fst) (Text.uncons t)

-- | A BOOLEAN field that does not start with a verb. An adjective takes "is": "the
-- processing is necessary for …". Anything else states something of its own, so
-- it stands alone when the record is the rule's subject, and says which record it
-- is about when it might be another.
booleanFieldPhrase :: Reading -> Expr Resolved -> Resolved -> Maybe Text
booleanFieldPhrase rd a n
  | not (getUnique n `Set.member` rd.rdBoolFields) = Nothing
  | hasHerald, isSubject = Just field
  | hasHerald            = Just (field <> ", for " <> subject)
  | adjectival           = Just (subject <> " is " <> field)
  | verbLed              = Just (subject <> " " <> field)
  | isSubject            = Just field
  | otherwise            = Just (field <> ", for " <> subject)
 where
  subject = leafText a
  field = simpleLinearizer n
  hasHerald = isJust (getActual n ^. annoOf % annNlg) || isJust (getOriginal n ^. annoOf % annNlg)
  adjectival = case Text.words (resolvedText n) of
    w : _ -> Text.toLower w `Set.member` adjectiveLeaders
    []    -> False
  -- "resides in Singapore": a verb in the third person, which needs its subject.
  verbLed = case Text.words (resolvedText n) of
    w : _ : _ -> Text.isSuffixOf "s" w && not (Text.isSuffixOf "ss" w)
    _         -> False
  isSubject = case a of
    Inert _ t _ -> t `Set.member` rd.rdSubjects
    _           -> False

adjectiveLeaders :: Set.Set Text
adjectiveLeaders = Set.fromList
  [ "necessary", "required", "eligible", "entitled", "subject", "liable", "bound"
  , "carried", "made", "signed", "filed", "approved", "registered", "exempt", "valid"
  , "void", "deemed", "resident", "married", "living", "deceased", "active", "pending"
  , "responsible", "able", "unable", "permitted", "prohibited", "payable", "due" ]

interleaveMixfix :: Resolved -> [Expr Resolved] -> Maybe Text
interleaveMixfix n args =
  let toks  = Text.words (nameToText (getActual n))
      holes = length (filter (== "_") toks)
  in if holes >= 1 && holes == length args
       then Just (Text.unwords (fill toks args))
       else Nothing
 where
  fill [] _ = []
  fill (t : ts) as
    | t == "_" = case as of
        (a : rest) -> leafText a : fill ts rest
        []         -> t : fill ts as
    | otherwise = t : fill ts as

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
  ["of", "for", "to", "from", "into", "onto", "on", "in", "by", "at", "over"
  , "under", "between", "than", "as", "after", "before", "among", "amongst"
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
buildPlan cfg mainModule0 deps0 =
  MkExportPlan
    { planMainModule = uriText mainUri
    , planModules    = mainPlanModule : importedPlanModules
    }
 where
  -- As in 'buildDocument': the elaborations are not provisions.
  mainModule = stripSectionBinderElaborations mainModule0
  deps       = map stripSectionBinderElaborations deps0
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
documentTitleAndBody m@(MkModule _ _ root@(MkSection _ mName _ _ _)) =
  case mName of
    Just n  -> (resolvedText n, root)
    Nothing -> case leadingSection root of
      Just hs -> hs
      Nothing -> (titleCase (moduleLabel (moduleUri' m)), root)

-- | Heading + body for an imported module: its leading section marker (when
-- present before any code), otherwise the file name. Mirrors
-- 'documentTitleAndBody' but with a file-name (not title-cased) fallback.
importHeadingAndBody :: NormalizedUri -> Module Resolved -> (Text, Section Resolved)
importHeadingAndBody uri (MkModule _ _ root@(MkSection _ mName _ _ _)) =
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
importHasSectionTitle (MkModule _ _ root@(MkSection _ mName _ _ _)) =
  isJust mName || isJust (leadingSection root)

-- | If a section is just a single named subsection with no loose declarations
-- before it, return that subsection's name and the subsection itself — the
-- "first section marker" used as a title/heading.
leadingSection :: Section Resolved -> Maybe (Text, Section Resolved)
leadingSection (MkSection _ _ _ _ decls) =
  case (any isUnitDecl decls, [ s | Section _ s <- decls ]) of
    (False, [s@(MkSection _ (Just sn) _ _ _)]) -> Just (resolvedText sn, s)
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
  let (heading, MkSection _ _ _ _ decls) = importHeadingAndBody uri m
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
    ("MAYBE", [t]) -> typeText t <> ", if any"
    ("LIST", [t])  -> "list of " <> typeText t
    (name, [])     -> Map.findWithDefault (spaceCamel name) name builtinTypeGloss
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
  toJSON g = Aeson.object ["label" .= g.groupLabel, "blocks" .= g.groupBlocks]

instance Aeson.ToJSON DocSection where
  toJSON s = Aeson.object
    [ "number"      .= s.sectionNumber
    , "heading"     .= s.sectionHeading
    , "groups"      .= s.sectionGroups
    , "subsections" .= s.sectionSubs
    ]

instance Aeson.ToJSON Document where
  toJSON d = Aeson.object ["title" .= d.docTitle, "sections" .= d.docSections]

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
