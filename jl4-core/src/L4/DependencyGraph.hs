-- | The global dependency graph over a type-checked module and its import
-- closure (@specs\/todo\/GLOBAL-DEPENDENCY-GRAPH-SPEC.md@): one node per named
-- definition, one edge @A -> B@ per \"evaluating A may require evaluating B\",
-- entry-point roots, SCCs and reachability. One graph, several consumers:
-- cross-record computed-field cycle detection, dead-code identification,
-- tree-shaking, and the call-graph visualizer
-- (@specs\/todo\/CALL-GRAPH-MATERIALITY-SPEC.md@, D1).
--
-- The edge collector is a total 'Foldable' fold in the manner of
-- @freeRefs@ in "L4.Dmn.Lower" — a per-constructor whitelist walk is how that
-- collector once silently dropped @AppNamed@ heads and @WHERE@ bodies — but it
-- deviates from @freeRefs@ in four load-bearing ways:
--
-- 1. It folds the /whole/ declaration, not just the body. @GIVEN@ binders are
--    'Def's in the signature, so they subtract out exactly like @LET@\/@WHERE@
--    locals, lambda and pattern binders, and never surface as nodes or
--    dangling edges — this graph has no parameter node kind. (DMN folds the
--    body only precisely so that parameters come out free and mint
--    @inputData@; that is the wrong semantics here.)
--
-- 2. The declaration's own head is excepted from the bound set, so a
--    self-reference survives as a self-edge: Pass 2 counts a self-edge as a
--    cycle, and binding the head is how the DMN exporter once erased direct
--    recursion before any graph could see it. AKA aliases share the head's
--    'Unique', so the exception covers them for free.
--
-- 3. There is no @projFields@ subtraction. The spec's edge table demands that
--    @x's f@ produce an edge to the selector /and/ to whatever @x@ resolves
--    to, and under a total fold both fall out with no 'Proj' special case —
--    which also covers the @f x@ \/ @f OF x@ spelling of a computed-field
--    read, with no double-counting.
--
-- 4. Edge targets are filtered by membership in the global node map — the
--    owner-map trick of @buildGraph@ in "L4.Export.Document" — which drops
--    builtins, 'OutOfScope' sentinels and any residual local. An 'OutOfScope'
--    unique is never used as a node key.
--
-- Decisions this module owns (the spec is silent on them):
--
-- * /Intra-DECLARE attribution./ The type's head points at each constructor
--   it declares and at each stored-field selector, so a reachable type keeps
--   its whole schema (the tree-shaking consumer needs fields no rule happens
--   to project). Each constructor points at its argument selectors and at the
--   references in its argument types; each selector points at the references
--   in its own field type (and @TYPICALLY@ default). A record's constructor
--   additionally points at its type: a construction site references only the
--   constructor's 'Unique' (minted separately from the type's — see
--   @inferTypeDecl@ in "L4.TypeCheck"), and must keep the schema live.
--   Recursive types (@Tree HAS left IS A Tree@) therefore form SCCs;
--   'computedFieldCycles' ignores them because their members are never
--   'DepComputedField'. Deliberately absent: type head -> its computed-field
--   DECIDEs. A computed field's synthetic signature (@_self IS A R@) already
--   points at its owner type, so the reverse structural edge would put every
--   computed field into a two-node SCC with its record and turn
--   'computedFieldCycles' into noise.
--
-- * /Entry points come from the main module only./ A dependency's directives
--   run when that module is the one being run, not when its importer is;
--   rooting the importer's reachability at them would hide exactly the unused
--   imports Pass 3 exists to find.
--
-- * /@TIMEZONE@ expressions are roots ('EntryTimezone')./ The declaration is
--   not a definition, but it references names; a definition used only by it
--   must not be flagged dead.
--
-- * /The root set is always explicit./ 'reachableFrom' takes a 'RootSet'
--   rather than defaulting one, because entry-point roots (dead-code
--   semantics) and main-module roots (import-pruning semantics, the
--   @UnitGraph@ behaviour) answer different questions and a silent default
--   would decide between them by accident.
module L4.DependencyGraph
  ( -- * Types
    DepKind (..)
  , DepNodeInfo (..)
  , DepGraph (..)
  , EntryKind (..)
  , RootSet (..)
    -- * Construction
  , buildDepGraph
    -- * Analyses
  , reverseEdges
  , rootsOf
  , reachableFrom
  , unreachableFrom
  , closure
  , closureUpTo
  , cyclicSccs
  , computedFieldCycles
  ) where

import Base
import qualified Base.Text as Text
import Data.Graph (SCC (..), stronglyConnComp)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Optics ((^.))

import L4.Annotation (getAnno, rangeOf)
import L4.Export (ParsedDesc (..), isExportedDecide, parseDescText)
import L4.Parser.SrcSpan (SrcRange)
import L4.Syntax
import L4.TypeCheck.Types (CheckEntity (..), EntityInfo)

-- | What kind of definition a node stands for, per the spec's node table.
data DepKind
  = DepFunction      -- ^ top-level @DECIDE@\/@MEANS@
  | DepComputedField -- ^ the synthetic @DECIDE@ computed-field desugaring left behind
  | DepSelector      -- ^ stored record (or constructor-argument) field
  | DepConstructor   -- ^ a declared type, enum constructor, or record constructor
  | DepAssume        -- ^ @ASSUME@
  deriving stock (Eq, Ord, Show)

-- | Renderer-facing facts about one node. The key is the definition's
-- 'Unique'; one per definition suffices because AKA aliases and
-- section-qualified spellings share the primary definition's 'Unique'.
data DepNodeInfo = MkDepNodeInfo
  { kind :: !DepKind
  , name :: !Text
    -- ^ 'unqualifiedNameToText' of the defining occurrence — diagram labels
    -- drop section qualification (see the note on 'unqualifiedRawNameToText')
  , moduleUri :: !NormalizedUri
  , range :: !(Maybe SrcRange)
    -- ^ the defining name's range; a computed-field selector's points inside
    -- its @DECLARE@, since the synthetic @DECIDE@ reuses the field's 'Anno'
  , desc :: !(Maybe Text)
    -- ^ @\@desc@ text with the leading @export@\/@default@\/@nonexhaustive@
    -- flags stripped
  }
  deriving stock (Eq, Show)

-- | Which kind of root an entry point is.
data EntryKind
  = EntryEval      -- ^ @#EVAL@
  | EntryEvalTrace -- ^ @#EVALTRACE@
  | EntryCheck     -- ^ @#CHECK@
  | EntryAssert    -- ^ @#ASSERT@
  | EntryContract  -- ^ @#TRACE@
  | EntryExport    -- ^ @\@export@-flagged @DECIDE@ (decision service API)
  | EntryTimezone  -- ^ referenced from a @TIMEZONE IS@ expression
  deriving stock (Eq, Ord, Show)

-- | The graph: node side table, forward edges (total over 'nodes' — a leaf
-- maps to the empty set), and entry-point roots in source order.
data DepGraph = MkDepGraph
  { mainUri :: !NormalizedUri
  , nodes :: !(Map Unique DepNodeInfo)
  , edges :: !(Map Unique (Set Unique))
  , entryPoints :: ![(EntryKind, Unique)]
  }

-- | Where a reachability query starts. Always spelled out by the caller; see
-- the module haddock for why there is no default.
data RootSet
  = RootsEntryPoints        -- ^ dead-code semantics (Pass 3)
  | RootsMainModule         -- ^ import-pruning semantics (every main-module node)
  | RootsExplicit (Set Unique) -- ^ a caller-chosen slice
  deriving stock (Eq, Show)

-- ----------------------------------------------------------------------------
-- Construction
-- ----------------------------------------------------------------------------

-- | Build the graph for a main module plus its (transitive, deduplicated)
-- dependencies. The 'EntityInfo' is the merged one the type checker returns
-- for the main module; it is only consulted as a fallback classifier for
-- computed-field heads.
buildDepGraph :: EntityInfo -> Module Resolved -> [Module Resolved] -> DepGraph
buildDepGraph entityInfo mainModule deps =
  MkDepGraph
    { mainUri = uriOf mainModule
    , nodes = nodeMap
    , edges = edgeMap
    , entryPoints = mainEntryPoints nodeMap mainModule
    }
 where
  mods = mainModule : deps
  nodeMap =
    Map.fromList (concatMap (concatMap (declNodes entityInfo) . flatDecls) mods)
  edgeMap =
    Map.unionWith
      Set.union
      (Map.fromSet (const Set.empty) (Map.keysSet nodeMap))
      (Map.fromListWith
         Set.union
         (concatMap (concatMap (declEdges nodeMap) . flatDecls) mods))
  uriOf (MkModule _ uri _) = uri

-- | Every declaration of the module, descending through @SECTION@s. An
-- explicit recursion, never a @gplate@-based fold: the generic ones find
-- \"top-level\" @Decide@s anywhere, including @LocalDecide@s inside directive
-- expressions.
flatDecls :: Module Resolved -> [TopDecl Resolved]
flatDecls (MkModule _ _ sec) = go sec
 where
  go (MkSection _ _ _ ds) = concatMap one ds
  one = \case
    Section _ sub -> go sub
    d -> [d]

-- ----------------------------------------------------------------------------
-- Node pass
-- ----------------------------------------------------------------------------

declNodes :: EntityInfo -> TopDecl Resolved -> [(Unique, DepNodeInfo)]
declNodes entityInfo = \case
  Decide _ (MkDecide dAnn _ (MkAppForm afAnn n _ _) _) ->
    [mkNode (decideKind entityInfo n) [dAnn, afAnn] n]
  Declare _ (MkDeclare dAnn _ (MkAppForm afAnn n _ _) td) ->
    mkNode DepConstructor [dAnn, afAnn] n : typeDeclNodes td
  Assume _ (MkAssume aAnn _ (MkAppForm afAnn n _ _) _ _) ->
    [mkNode DepAssume [aAnn, afAnn] n]
  _ -> []

typeDeclNodes :: TypeDecl Resolved -> [(Unique, DepNodeInfo)]
typeDeclNodes = \case
  RecordDecl _ mCon fields ->
    [mkNode DepConstructor [] c | Just c <- [mCon]] <> map selectorNode fields
  EnumDecl _ cons -> concatMap conNodes cons
  SynonymDecl{} -> []
 where
  conNodes (MkConDecl cAnn c args) =
    mkNode DepConstructor [cAnn] c : map selectorNode args
  selectorNode (MkTypedName tnAnn f _ _ _) = mkNode DepSelector [tnAnn] f

mkNode :: DepKind -> [Anno] -> Resolved -> (Unique, DepNodeInfo)
mkNode k declAnnos r =
  ( u
  , MkDepNodeInfo
      { kind = k
      , name = unqualifiedNameToText (getOriginal r)
      , moduleUri = u.moduleUri
      , range = rangeOf (getActual r)
      , desc = firstDescOf (declAnnos <> [getAnno (getOriginal r)])
      }
  )
 where
  u = getUnique r

firstDescOf :: [Anno] -> Maybe Text
firstDescOf anns =
  listToMaybe
    [ d
    | ann <- anns
    , Just raw <- [ann ^. annDesc]
    , let d = (parseDescText (getDesc raw)).description
    , not (Text.null d)
    ]

-- | Is this @DECIDE@ head the synthetic selector computed-field desugaring
-- left behind? The principled witness is the checker's 'ComputedSelector'
-- stamp on the name's annotation (@isComputedSelectorKind@ in "L4.Dmn.Lower"
-- documents why a @\"_self\"@ name test is the wrong recognizer); the
-- 'EntityInfo' lookup covers a defining occurrence whose own annotation was
-- not stamped.
decideKind :: EntityInfo -> Resolved -> DepKind
decideKind entityInfo r
  | stamped || entitySays = DepComputedField
  | otherwise = DepFunction
 where
  stamped = case getAnno (getActual r) ^. annInfo of
    Just (TypeInfo _ (Just ComputedSelector)) -> True
    _ -> False
  entitySays = case Map.lookup (getUnique r) entityInfo of
    Just (_, KnownTerm _ ComputedSelector) -> True
    _ -> False

-- ----------------------------------------------------------------------------
-- Edge pass
-- ----------------------------------------------------------------------------

declEdges :: Map Unique DepNodeInfo -> TopDecl Resolved -> [(Unique, Set Unique)]
declEdges nodeMap = \case
  Decide _ d@(MkDecide _ _ (MkAppForm _ n _ _) _) -> [wholeDecl (toList d) n]
  Assume _ a@(MkAssume _ _ (MkAppForm _ n _ _) _ _) -> [wholeDecl (toList a) n]
  Declare _ d -> declareEdges nodeMap d
  _ -> []
 where
  wholeDecl rs n =
    let headU = getUnique n
        bound = Set.delete headU (Set.fromList [u | Def u _ <- rs])
    in (headU, targetsOf nodeMap bound rs)

-- | See the intra-DECLARE attribution note in the module haddock.
declareEdges :: Map Unique DepNodeInfo -> Declare Resolved -> [(Unique, Set Unique)]
declareEdges nodeMap d@(MkDeclare _ tysig (MkAppForm _ n _ _) td) =
  case td of
    RecordDecl _ mCon fields ->
      (headU, Set.fromList (map tnUnique fields) <> tgt (toList tysig))
        : [(getUnique c, Set.singleton headU) | Just c <- [mCon]]
        <> map fieldEdges fields
    EnumDecl _ cons ->
      (headU, Set.fromList [getUnique c | MkConDecl _ c _ <- cons] <> tgt (toList tysig))
        : concatMap conEdges cons
    SynonymDecl _ ty ->
      [(headU, tgt (toList ty) <> tgt (toList tysig))]
 where
  headU = getUnique n
  minted = Set.fromList (headU : map fst (typeDeclNodes td))
  bound = Set.fromList [u | Def u _ <- toList d] Set.\\ minted
  tgt = targetsOf nodeMap bound
  tnUnique (MkTypedName _ f _ _ _) = getUnique f
  fieldEdges tn@(MkTypedName _ f _ _ _) = (getUnique f, tgt (toList tn))
  conEdges cd@(MkConDecl _ c args) =
    (getUnique c, Set.fromList (map tnUnique args) <> tgt (toList cd))
      : map fieldEdges args

targetsOf :: Map Unique DepNodeInfo -> Set Unique -> [Resolved] -> Set Unique
targetsOf nodeMap bound rs =
  Set.fromList
    [ u
    | r@Ref{} <- rs
    , let u = getUnique r
    , not (Set.member u bound)
    , Map.member u nodeMap
    ]

-- ----------------------------------------------------------------------------
-- Entry points
-- ----------------------------------------------------------------------------

mainEntryPoints :: Map Unique DepNodeInfo -> Module Resolved -> [(EntryKind, Unique)]
mainEntryPoints nodeMap m = nubOrd (concatMap go (flatDecls m))
 where
  go = \case
    Directive _ d -> [(directiveKind d, u) | u <- knownRefs (toList d)]
    Timezone _ e -> [(EntryTimezone, u) | u <- knownRefs (toList e)]
    Decide _ d@(MkDecide _ _ (MkAppForm _ n _ _) _)
      | isExportedDecide d -> [(EntryExport, getUnique n)]
    _ -> []
  -- A directive's fold also yields locals it binds itself and names that are
  -- not definitions; membership in the node map is the filter for both.
  knownRefs rs = nubOrd [u | Ref _ u _ <- rs, Map.member u nodeMap]
  directiveKind = \case
    LazyEval{} -> EntryEval
    LazyEvalTrace{} -> EntryEvalTrace
    Check{} -> EntryCheck
    Contract{} -> EntryContract
    Assert{} -> EntryAssert

-- ----------------------------------------------------------------------------
-- Analyses
-- ----------------------------------------------------------------------------

-- | The transposed edge relation (also total over 'nodes'), for reverse
-- slices: who consumes this definition?
reverseEdges :: DepGraph -> Map Unique (Set Unique)
reverseEdges g =
  Map.unionWith
    Set.union
    (Map.fromSet (const Set.empty) (Map.keysSet g.nodes))
    (Map.fromListWith
       Set.union
       [ (tgt, Set.singleton src)
       | (src, tgts) <- Map.toList g.edges
       , tgt <- Set.toList tgts
       ])

rootsOf :: DepGraph -> RootSet -> Set Unique
rootsOf g = \case
  RootsEntryPoints -> Set.fromList (map snd g.entryPoints)
  RootsMainModule ->
    Map.keysSet (Map.filter (\i -> i.moduleUri == g.mainUri) g.nodes)
  RootsExplicit us -> Set.intersection us (Map.keysSet g.nodes)

reachableFrom :: DepGraph -> RootSet -> Set Unique
reachableFrom g roots = closure g.edges (rootsOf g roots)

unreachableFrom :: DepGraph -> RootSet -> Set Unique
unreachableFrom g roots = Map.keysSet g.nodes Set.\\ reachableFrom g roots

-- | Generic BFS closure, lifted from @closure@ in "L4.Export.Document".
closure :: Ord a => Map a (Set a) -> Set a -> Set a
closure = closureUpTo Nothing

-- | 'closure', stopping @depth@ steps out from the roots: depth 0 is the
-- roots themselves, depth 1 adds their direct targets, and so on. A negative
-- depth behaves like 0.
closureUpTo :: Ord a => Maybe Int -> Map a (Set a) -> Set a -> Set a
closureUpTo mdepth es = go mdepth Set.empty
 where
  go d seen frontier
    | Set.null frontier = seen
    | maybe False (<= 0) d = Set.union seen frontier
    | otherwise =
        let seen' = Set.union seen frontier
            next =
              Set.unions
                [Map.findWithDefault Set.empty i es | i <- Set.toList frontier]
        in go (subtract 1 <$> d) seen' (next Set.\\ seen')

-- | The cyclic strongly connected components: every SCC of two or more
-- nodes, and every single node with a self-edge (Pass 2's definition of a
-- cycle — 'stronglyConnComp' classifies a self-loop as 'CyclicSCC').
cyclicSccs :: DepGraph -> [[Unique]]
cyclicSccs g =
  [ cyc
  | CyclicSCC cyc <-
      stronglyConnComp
        [ (u, u, Set.toList (Map.findWithDefault Set.empty u g.edges))
        | u <- Map.keys g.nodes
        ]
  ]

-- | The cycles that pass through at least one computed field — the
-- error-grade subset of 'cyclicSccs': mutual recursion between plain
-- functions is valid L4, a cycle through a derived attribute is not.
computedFieldCycles :: DepGraph -> [[Unique]]
computedFieldCycles g = filter (any isComputedField) (cyclicSccs g)
 where
  isComputedField u = case Map.lookup u g.nodes of
    Just i -> i.kind == DepComputedField
    Nothing -> False
