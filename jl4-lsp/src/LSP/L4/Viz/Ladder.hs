{-# LANGUAGE ViewPatterns, PatternSynonyms, MultiWayIf, TupleSections #-}

module LSP.L4.Viz.Ladder (
  -- * Viz Decide entrypoint
  doVisualize,

  -- * Inline Exprs: a call to a rule of this module, at its own arity
  inlineExprs,

  -- * VizConfig, VizState
  VizConfig (..),
  mkVizConfig,
  withCallExpansions,
  stampMixfixCalls,
  expansionNodeBudget,
  VizState,

  -- * Viz State helpers
  lookupAppExprMaker,
  getAtomDeps,
  InputRef (..),
  getAtomInputRefs,
  getLeafExpr,
  getLeafKeys,
  getFreshLeaves,
  getVizConfig,

  -- * Conversion
  V.fromLspVerDocId,

  -- * Other helpers
  VizError (..),
  prettyPrintVizError
  ) where

import Base
import qualified Base.Text as Text
import Data.IntMap.Lazy (IntMap)
import qualified Data.IntMap.Lazy as Map
import Data.IntSet (IntSet)
import qualified Data.IntSet as IntSet
import qualified Data.Set as Set
import qualified Data.Map.Strict as DataMap
import qualified Data.List.NonEmpty as NE
import Optics.State.Operators ((<%=), (%=))
import Optics
import Control.Monad.Extra (unlessM)
import qualified Language.LSP.Protocol.Types as LSP

import qualified L4.TypeCheck as TC
import L4.Viz.Ladder (InputRef(..), collectTypicallyDefaults, seamLabel)
import L4.Viz.AtomKey (KeyEnv, mkKeyEnv, termKey, atomIdOfKey, withTypeExpander, withLocalsInScope, isEffectful)
import L4.Annotation
import L4.Syntax
import L4.Print (prettyLayout, mixfixCanonicalByUnique)
import qualified L4.Transform as Transform (simplify, Unfoldable (..), unfoldableDecide, unfoldOnce, substParams, inlineLocalBindings)
import qualified L4.Viz.GuardedRows as GR
import L4.Viz.GuardedRows (GuardedRows (..))
import LSP.L4.Viz.VizExpr
  ( ID (..), IRExpr,
    RenderAsLadderInfo (..),
  )
import qualified LSP.L4.Viz.VizExpr as V
import qualified LSP.L4.Viz.CustomProtocol as V (EvalAppRequestParams (..))
import LSP.L4.Viz.VizExpr (InertContext(..))
import L4.Desugar

------------------------------------------------------
-- Monad
------------------------------------------------------

newtype Viz a = MkViz {getViz :: VizEnv -> VizState -> (Either VizError a, VizState)}
  deriving
    (Functor, Applicative, Monad, MonadState VizState, MonadError VizError, MonadReader VizEnv)
    via ReaderT VizEnv (ExceptT VizError (State VizState))

-- | A 'local' env
data VizEnv = MkVizEnv
  { localDecls :: [LocalDecl Resolved]
  , expansionStack :: [Int]
  -- ^ Unique.unique of every rule whose call is being expanded around the
  -- current node, innermost first. A call to a rule already on it is not
  -- expanded again: that is recursion, and its expansion would not end.
  , expansionDepthLimit :: Int
  -- ^ How deeply expansions may nest in this pass (see 'doVisualize').
  }

initialVizEnv :: Int -> VizEnv
initialVizEnv depthLimit = MkVizEnv
  { localDecls = []
  , expansionStack = []
  , expansionDepthLimit = depthLimit
  }

mkVizConfig :: LSP.VersionedTextDocumentIdentifier -> Module Resolved -> TC.Substitution -> Bool -> VizConfig
mkVizConfig lspVerDocId module' substitution shouldSimplify =
  let moduleUri = toNormalizedUri lspVerDocId._uri
  in MkVizConfig
    { moduleUri
    , module'
    , verDocId = V.fromLspVerDocId lspVerDocId
    , substitution
    , shouldSimplify
    , expandCalls = False
    }

data VizConfig = MkVizConfig
  { moduleUri      :: !NormalizedUri
  , module'        :: Module Resolved
  , verDocId       :: !V.VersionedDocId
  , substitution   :: !TC.Substitution
  , shouldSimplify :: !Bool
  , expandCalls    :: !Bool
  -- ^ Attach to every call leaf the called rule's body, beta-reduced with the
  -- call's arguments ('V.UBoolVar' / 'V.App' @expansion@). Off by default. On
  -- only when an @l4.visualize@ request asks for it with @{"expandCalls": true}@
  -- ('LSP.L4.Actions.VisualiseOptions'); the IDE's "Show decision graph" lens does
  -- not, and @l4 verify@, the service and the REPL never do.
  }
  deriving stock (Show, Generic, Eq)

-- | Turn call expansions on (WHERE-INLINING-SPEC §10).
withCallExpansions :: VizConfig -> VizConfig
withCallExpansions cfg = cfg { expandCalls = True }

{- | Stamp every mixfix call in a module with its canonical pattern, so that the
ladder's labels print the call's full surface form.

A call leaf's label is 'prettyLayout' of the call. Without the stamp the
printer can emit only a mixfix name's HEAD keyword, so two operators sharing one
print alike: in @jl4/tests-cli/fixtures/batch-mixfix-shared-head.l4@ both
@`the will` w `is duly executed without` 3@ and @`the will` w `is revoked counting` 3@
arrived as @`the will` OF w, 3@ (measured 2026-10-06). The atomId was then a hash
of that label, so the two shared ONE atomId, and a client that links copies by
atomId answered both with one click: @X AND NOT Y@ could never come out TRUE.
The atomId is now the hash of the call's TERM ("L4.Viz.AtomKey", R3), which names
each operator by its own definition whatever it prints as; the stamp is what
keeps the two LABELS apart for the reader.

'L4.Print.restoreMixfixPatterns' does the same for printed MODULES, and stamps
only operators defined in the module, because an imported operator's surface
form does not re-parse standing alone (CLAUDE.md §3.2.2). A label is never
re-parsed, so this stamps every operator the registry knows; whether that
closes the cross-module case (smucclaw/l4-ide#968) is untested.

Only call sites are stamped; the printer reads the stamp from the 'App' node's
annotation, and nothing else changes, so Uniques, evaluation and the code
lens's own check are unaffected.
-}
stampMixfixCalls :: TC.MixfixRegistry -> Module Resolved -> Module Resolved
stampMixfixCalls reg = over (gplate @(Expr Resolved)) (transformOf (gplate @(Expr Resolved)) stamp)
  where
    canon = mixfixCanonicalByUnique reg
    stamp e = case e of
      App ann n es@(_ : _)
        | Just c <- DataMap.lookup (getUnique n) canon ->
            App (set annMixfixCanonical (Just c) ann) n es
      _ -> e

-- | How many IR nodes the expansions of ONE decision may add between them, all
-- nesting levels together. Expansion nests, and a rule that calls a rule twice
-- that calls a rule twice ... multiplies; this keeps the reply a size a reader
-- could take in. 'doVisualize' expands every call to the deepest uniform depth
-- that fits; a call below that depth keeps @expansion = Nothing@ and draws as a
-- plain leaf.
expansionNodeBudget :: Int
expansionNodeBudget = 2000


data VizState = MkVizState
  { cfg            :: !VizConfig
  , maxId          :: !ID
  , functionName   :: !Text
  -- ^ Name of the function being visualized (for atomId generation)
  , appExprMakers  :: IntMap (V.EvalAppRequestParams -> Expr Resolved)
  -- ^ Map from Unique of V.ID to eval-app-directive maker
  , defsForInlining :: IntMap (Unique, Transform.Unfoldable)
  -- ^ Unique.unique -> the definition's full unique and what a call to it
  -- unfolds into (parameters and body). Same-module definitions only.
  , expansionBodies :: IntMap (Maybe ([Unique], Expr Resolved))
  -- ^ What a call to each of 'defsForInlining' expands into, before its
  -- arguments are put in: the parameters, and the body with the definition's
  -- own WHERE definitions inlined into it; 'Nothing' for a definition whose
  -- body keeps a local binding after that (see 'expandCall'). Each entry is
  -- computed at most once per decision, and only for a rule that is called.
  , leafExprs :: IntMap (Expr Resolved)
  -- ^ Leaf variable id -> the source expression the leaf stands for. Lets a
  -- consumer ask what a leaf MEANS: `l4 verify` reads a call leaf through to the
  -- rule it calls (WHERE-INLINING-SPEC.md §9).
  , callLeafTargets :: IntMap Int
  -- ^ Leaf id -> Unique.unique of the definition it calls, for a leaf that is a
  -- call WITH arguments. Such a leaf gets a fresh id (two calls of one rule with
  -- different arguments are different questions), so 'inlineExprs' needs this to
  -- find which definition the reader asked to expand.
  , atomDeps       :: IntMap IntSet
  , atomInputRefs  :: IntMap (Set InputRef)
  , typicallyDefaults :: IntMap Bool
  -- ^ Unique.unique -> the binder's BOOLEAN TYPICALLY default (see 'collectTypicallyDefaults').
  , keyEnv :: KeyEnv
  -- ^ What names a leaf's term (R3, "L4.Viz.AtomKey"). Lazy: a pass that never
  -- forces an atomId never walks the module.
  , leafKeys :: IntMap Text
  -- ^ Leaf id -> the C1 key of its term. The query plan names its atoms from
  -- these ('LSP.L4.Viz.QueryPlan.buildQueryPlanCache'), so the diagram and the
  -- plan cannot disagree (smucclaw/l4-ide#935).
  , freshLeaves :: !Int
  -- ^ How many leaves keyed apart per occurrence ('keyLeaf') so far.
  , freshLeafIds :: IntSet
  -- ^ The ids of those leaves ('getFreshLeaves').
  , expansionNodes :: !Int
  -- ^ IR nodes the expansions so far have added (see 'expansionNodeBudget').
  , expansionOverBudget :: !Bool
  -- ^ This pass refused an expansion because 'expansionNodeBudget' was spent.
  , expansionCutByDepth :: !Bool
  -- ^ This pass refused an expansion only because of 'expansionDepthLimit'.
  }
  deriving stock (Generic)

instance Show VizState where
  show MkVizState{cfg, maxId, functionName, appExprMakers, defsForInlining, callLeafTargets, atomDeps, atomInputRefs} =
    "MkVizState { cfg = " <> show cfg <>
    ", maxId = " <> show maxId <>
    ", functionName = " <> show functionName <>
    ", (keys of) appExprMakers =   " <> show (Map.keys appExprMakers) <>
    ", defsForInlining =  " <> show defsForInlining <>
    ", callLeafTargets = " <> show callLeafTargets <>
    ", (keys of) atomDeps = " <> show (Map.keys atomDeps) <>
    ", (keys of) atomInputRefs = " <> show (Map.keys atomInputRefs) <> " }"

mkInitialVizState :: VizConfig -> VizState
mkInitialVizState cfg =
  MkVizState
    { cfg
    , maxId = MkID 0
    , functionName = ""
    , appExprMakers = Map.empty
    , defsForInlining = Map.empty
    , expansionBodies = Map.empty
    , leafExprs = Map.empty
    , callLeafTargets = Map.empty
    , atomDeps = Map.empty
    , atomInputRefs = Map.empty
    , typicallyDefaults = Map.empty
    , keyEnv = withTypeExpander (TC.applyFinalSubstitution cfg.substitution cfg.moduleUri) (mkKeyEnv cfg.module')
    , leafKeys = Map.empty
    , freshLeaves = 0
    , freshLeafIds = IntSet.empty
    , expansionNodes = 0
    , expansionOverBudget = False
    , expansionCutByDepth = False
    }

------------------------------------------------------
-- Monad ops
------------------------------------------------------

-- | 'Internal' helper: This should only be used by other Viz monad ops
getVizCfg :: Viz VizConfig
getVizCfg = use #cfg

getVerDocId :: Viz V.VersionedDocId
getVerDocId = do
  cfg <- getVizCfg
  pure cfg.verDocId

getExpandedType :: Type' Resolved -> Viz (Type' Resolved)
getExpandedType ty = do
  cfg <- getVizCfg
  pure $ TC.applyFinalSubstitution cfg.substitution cfg.moduleUri ty

getFresh :: Viz ID
getFresh = do
  #maxId <%= \(MkID n) -> MkID (n + 1)

getShouldSimplify :: Viz Bool
getShouldSimplify = do
  cfg <- getVizCfg
  pure cfg.shouldSimplify

{-# ANN prepEvalAppMaker ("HLINT: ignore Redundant lambda" :: String) #-}
{- | Assumes that the program is well-scoped and well-typed -}
prepEvalAppMaker :: V.ID -> Expr Resolved -> Viz ()
prepEvalAppMaker vid = \ case
  App appAnno appResolved _ -> do
    localDecls <- getLocalDecls
    let maker =
          \V.EvalAppRequestParams{args} ->
            Where emptyAnno
              (App appAnno appResolved $ map toBoolExpr args)
              localDecls
    #appExprMakers %= Map.insert vid.id maker
  _ -> pure ()

getLocalDecls :: Viz [LocalDecl Resolved]
getLocalDecls = do
  env <- ask
  pure env.localDecls

withLocalDecls :: [LocalDecl Resolved] -> Viz a -> Viz a
withLocalDecls newLocalDecls = local (\env -> env { localDecls = newLocalDecls <> env.localDecls })

recordAtomDeps :: V.Unique -> IntSet -> Viz ()
recordAtomDeps uniq deps =
  #atomDeps %= Map.insertWith (<>) uniq deps


recordAtomInputRefs :: V.Unique -> Set InputRef -> Viz ()
recordAtomInputRefs uniq refs = do
  recordAtomDeps uniq (IntSet.fromList (map (.rootUnique) (Set.toList refs)))
  #atomInputRefs %= Map.insertWith (<>) uniq refs

lookupLocalDecideBody :: Int -> Viz (Maybe (Expr Resolved))
lookupLocalDecideBody target = do
  localDecls <- getLocalDecls
  pure $
    listToMaybe $
      flip mapMaybe localDecls $ \case
        LocalDecide _ (MkDecide _ _ (MkAppForm _ n _ _) body) ->
          if (getUnique n).unique == target then Just body else Nothing
        _ -> Nothing

freeInputRefsExpanded :: Set Int -> Expr Resolved -> Viz (Set InputRef)
freeInputRefsExpanded visited expr = do
  expanded <- traverse expandOne (Set.toList (freeInputRefs expr))
  pure (Set.unions expanded)
 where
  expandOne :: InputRef -> Viz (Set InputRef)
  expandOne r =
    case r.path of
      _ : _ -> pure (Set.singleton r)
      [] ->
        if Set.member r.rootUnique visited
          then pure (Set.singleton r)
          else do
            lookupLocalDecideBody r.rootUnique >>= \case
              Nothing -> pure (Set.singleton r)
              Just body -> freeInputRefsExpanded (Set.insert r.rootUnique visited) body

-- | The source expression a leaf variable stands for, if it is a leaf.
getLeafExpr :: VizState -> Int -> Maybe (Expr Resolved)
getLeafExpr vs leaf = Map.lookup leaf vs.leafExprs

-- | The C1 key of every leaf's term, by leaf id ('L4.Viz.AtomKey'). Inside an
-- expansion that is the term AFTER the call's arguments were put in (R3).
getLeafKeys :: VizState -> IntMap Text
getLeafKeys vs = vs.leafKeys

-- | The leaves keyed apart per occurrence, because their value depends on when
-- they are evaluated ('L4.Viz.AtomKey.isEffectful'). Their keys are numbered in
-- drawing order within ONE diagram, so a consumer that joins the atoms of two
-- separately drawn diagrams by atomId must not join these.
getFreshLeaves :: VizState -> IntSet
getFreshLeaves vs = vs.freshLeafIds

defsForInliningOf :: Module Resolved -> IntMap (Unique, Transform.Unfoldable)
defsForInliningOf module' =
  toMap (foldTopLevelDecides (foldDecides tryExtractDef) module')
    where
      tryExtractDef :: Decide Resolved -> [(Unique, Transform.Unfoldable)]
      tryExtractDef = maybe [] pure . Transform.unfoldableDecide

      toMap :: [(Unique, Transform.Unfoldable)] -> IntMap (Unique, Transform.Unfoldable)
      toMap = Map.fromList . map (\(u@(MkUnique _ k _), v) -> (k, (u, v)))

hasDefForInlining :: Unique -> Viz Bool
hasDefForInlining (MkUnique _ uniq uniqUri) = do
  cfg             <- getVizCfg
  defsForInlining <- use #defsForInlining
  -- We don't want, e.g., to pick up on builtin Uniques, which can have the same Int unique as a user-defined Unique
  pure $ uniqUri == cfg.moduleUri && Map.member uniq defsForInlining

------------------------------------------------------
-- Viz state helpers
------------------------------------------------------

{- Consumers should use the following helpers to work with VizState.
I.e., I'm trying to hide the implementational details of VizState
(e.g. how VizConfig is related to VizState). -}

lookupAppExprMaker :: VizState -> V.ID -> Maybe (V.EvalAppRequestParams -> Expr Resolved)
lookupAppExprMaker vs vid = Map.lookup vid.id vs.appExprMakers

getAtomDeps :: VizState -> IntMap IntSet
getAtomDeps vs = vs.atomDeps

getAtomInputRefs :: VizState -> IntMap (Set InputRef)
getAtomInputRefs vs = vs.atomInputRefs


getVizConfig :: VizState -> VizConfig
getVizConfig vs = vs.cfg

------------------------------------------------------
-- VizError
------------------------------------------------------

data VizError
  = InvalidProgramNoDecidesFound
  | InvalidDecideMustHaveBoolRetType
  deriving stock (Eq, Generic, Show)
  deriving anyclass (NFData)

-- TODO: Incorporate context like the specific erroring rule and the src range too
prettyPrintVizError :: VizError -> Text
prettyPrintVizError = \ case
  InvalidProgramNoDecidesFound ->
    "The program isn't the right sort for visualization: there are no DECIDE rules that can be visualized."
  InvalidDecideMustHaveBoolRetType ->
    "Can only visualize, as a ladder diagram, a DECIDE that returns a boolean."

------------------------------------------------------
-- Entrypoint: Visualise
------------------------------------------------------

-- | Entrypoint: Generate boolean circuits of the given 'Decide'.
--
-- With call expansions on ('expandCalls'), the decision is translated with
-- expansions nested at most 1 deep, then 2, and so on, and the deepest pass whose
-- expansions fit in 'expansionNodeBudget' is the answer: every call is expanded to
-- the same depth, rather than the first calls in reading order eating the whole
-- budget and starving the rest. It stops when a pass expands everything there is
-- (no call was held back by the depth limit); the recursion guard in 'expandCall'
-- bounds that depth by the number of rules. What does not depend on the depth —
-- the fresh-id seed, the definitions calls unfold into with their WHERE
-- definitions inlined, the TYPICALLY defaults, all read off the whole module —
-- is computed once ('preparedState') and shared by every pass.
doVisualize :: Decide Resolved -> VizConfig -> Either VizError (RenderAsLadderInfo, VizState)
doVisualize decide cfg
  | cfg.expandCalls = deepen 1 (runAt 0)
  | otherwise = runAt 0
  where
    prepared = preparedState decide cfg

    runAt :: Int -> Either VizError (RenderAsLadderInfo, VizState)
    runAt depthLimit =
      let (result, vizState) = (vizProgram decide).getViz (initialVizEnv depthLimit) prepared
      in fmap (, vizState) result

    deepen :: Int -> Either VizError (RenderAsLadderInfo, VizState) -> Either VizError (RenderAsLadderInfo, VizState)
    deepen depthLimit best = case runAt depthLimit of
      Left err -> Left err
      Right r@(_, st)
        | st.expansionOverBudget -> best
        | not st.expansionCutByDepth -> Right r
        | otherwise -> deepen (depthLimit + 1) (Right r)

vizProgram :: Decide Resolved -> Viz RenderAsLadderInfo
vizProgram decide = MkRenderAsLadderInfo <$> getVerDocId <*> translateDecide decide

-- | The state a translation of this decision starts from.
preparedState :: Decide Resolved -> VizConfig -> VizState
preparedState (MkDecide _ (MkTypeSig _ givenSig _) (MkAppForm _ funResolved _ _) body) cfg =
  (mkInitialVizState cfg)
    { functionName = (mkPrettyVizName funResolved).label
    , defsForInlining = defs
    , expansionBodies = Map.map expansionBodyOf defs
    -- A leaf's variable is keyed by an Int. A bare reference to one of this
    -- module's names uses the name's unique; every other leaf gets a fresh id
    -- from 'getFresh'. Those were once two counters that both started near zero,
    -- so a fresh id could equal a name's unique and two different propositions
    -- became ONE variable: `n > 3 AND b` read as one atom, and `l4 verify`
    -- reported both conjuncts as vacuous — a false finding, from a tool whose
    -- findings are meant to be sound. Starting the fresh ids above every unique
    -- in the rule keeps the two ranges apart.
    --
    -- With expansions on, the bodies of OTHER rules get translated in this
    -- state too, so the seed must clear their uniques as well: take the module.
    , maxId = MkID (maximum (0 : [u.unique | u <- seedFrom]))
    , typicallyDefaults = collectTypicallyDefaults givenSig cfg.module'
    }
  where
    defs = defsForInliningOf cfg.module'
    -- Inlining a definition's locals before its parameters are substituted
    -- gives what inlining them after would: the parameters are free in the body
    -- and substitution is by unique, so nothing is captured.
    expansionBodyOf (_, Transform.MkUnfoldable ps rhs)
      | bindsLocally flat = Nothing
      | otherwise = Just (ps, flat)
      where flat = Transform.inlineLocalBindings rhs
    seedFrom
      | cfg.expandCalls = toListOf (gplate @Unique) cfg.module'
      | otherwise = toListOf (gplate @Unique) body

------------------------------------------------------
-- translateDecide, translateExpr
------------------------------------------------------

-- | Turn a single clause into a boolean circuit.
-- We support only a tiny subset of possible representations, in particular
-- only statements of the form:
--
-- @
--  GIVEN <variable>
--  DECIDE <variable> IF <boolean expression>
-- @
--
-- Moreover, only 'AND', 'OR' and variables are allowed in the '<boolean expression>'.
--
-- These limitations are arbitrary, mostly to make sure we have something to show rather
-- than being complete. So, feel free to lift these limitations at your convenience :)
--
-- Simple implementation: Translate Decide iff <= 1 Given
translateDecide :: Decide Resolved -> Viz V.FunDecl
translateDecide (MkDecide _ (MkTypeSig _ givenSig _) (MkAppForm _ funResolved appArgs _) body) =
  do
    unlessM (hasBooleanType (getAnno body)) $
      throwError InvalidDecideMustHaveBoolRetType

    -- functionName, defsForInlining, maxId and typicallyDefaults are already
    -- set ('preparedState').
    let funName = mkPrettyVizName funResolved
    shouldSimplify <- getShouldSimplify
    vid            <- getFresh
    vizBody        <- translateExpr shouldSimplify (carameliseExpr body)
    pure $ V.MkFunDecl
      vid
      -- didn't want a backtick'd name in the header
      funName
      (paramNamesFromGivens givenSig appArgs)
      vizBody
      where
        paramNamesFromGivens :: GivenSig Resolved -> [Resolved] -> [V.Name]
        paramNamesFromGivens (MkGivenSig _ optionallyTypedNames) args =
          let
            fromGivens = mkPrettyVizName . getResolved <$> optionallyTypedNames
            fromAppArgs = mkPrettyVizName <$> args
           in
            Map.elems $ Map.fromList [(p.unique, p) | p <- fromGivens <> fromAppArgs]

        -- TODO: I imagine there will be functionality for this kind of thing in a more central place soon;
        -- this can be replaced with that when that happens.
        getResolved :: OptionallyTypedName Resolved -> Resolved
        getResolved (MkOptionallyTypedName _ paramName _ _) = paramName

-- | Context for translating expressions - tracks whether we're inside And or Or
data TranslateContext = CtxAnd | CtxOr | CtxNone
  deriving (Eq, Show)

-- | The seam SURVIVES simplification — see 'L4.Viz.Ladder.translateExpr' for the
-- argument (DESIGN §25a). In short: 'Transform.simplify' exists to reach CNF, and
-- CNF's first act is to rewrite @P IMPLIES Q@ into @NOT P OR Q@, discarding the
-- scope/requirement split. So peel the top-level implication off first, simplify
-- each side on its own, and keep the connective.
translateExpr :: Bool -> Expr Resolved -> Viz IRExpr
translateExpr shouldSimplify = top
  where
    top :: Expr Resolved -> Viz IRExpr
    top = \case
      -- A DECIDE's WHERE block wraps the implication, so peel it before looking.
      Where _ e ds -> withLocalDecls ds (top e)
      Implies ann p q -> do
        vid <- getFresh
        V.Implies vid <$> side p <*> side q <*> pure (seamLabel ann)
      e -> side e

    side :: Expr Resolved -> Viz IRExpr
    side e = translateGo CtxNone (if shouldSimplify then Transform.simplify e else e)

-- | The body of 'translateExpr' below the seam. Top level, rather than local to
-- 'translateExpr', because a call leaf's expansion ('expandCall') is translated by
-- this very function, in the same state, so it is drawn exactly as the caller's
-- own nodes are.
translateGo :: TranslateContext -> Expr Resolved -> Viz IRExpr
translateGo = go
  where
    go :: TranslateContext -> Expr Resolved -> Viz IRExpr
    go _ctx e =
      case e of
        Not _ negand -> do
          vid <- getFresh
          V.Not vid <$> go CtxNone negand

        -- A NESTED implication: the two-sink form is top-level only (v1), since an
        -- implication buried in a conjunction has nowhere to hang its lamps. Fall
        -- back to the classical reading — still far better than the old behaviour,
        -- where this fell through to 'leafFromExpr' and the whole implication was
        -- swallowed into one opaque box.
        Implies _ p q -> do
          orId <- getFresh
          notId <- getFresh
          p' <- go CtxNone p
          q' <- go CtxNone q
          pure $ V.Or orId [V.Not notId p', q']

        And {} -> do
          vid <- getFresh
          V.And vid <$> traverse (go CtxAnd) (scanAnd e)
        Or {} -> do
          vid <- getFresh
          V.Or vid <$> traverse (go CtxOr) (scanOr e)
        Where _ e' ds ->
          withLocalDecls ds $
            go _ctx e' -- TODO: lossy

        -- Inert elements: grammatical scaffolding that evaluates to the identity
        -- for the containing operator (True for AND, False for OR)
        -- The context is already determined by desugaring; we just map to VizExpr's InertContext
        Inert _ txt coreCtx -> do
          vid <- getFresh
          let inertCtx = case coreCtx of
                InertCtxAnd  -> InertAnd   -- evaluates to True (AND identity)
                InertCtxOr   -> InertOr    -- evaluates to False (OR identity)
                InertCtxNone -> InertAnd   -- default to AND context (evaluates to True)
          pure $ V.InertE vid txt inertCtx

        -- A refusal is drawn as an ordinary leaf, labelled with its own source
        -- (@REFUSE "…"@). Explicit above the wildcard because the wildcard
        -- would first try 'normaliseGuarded' on it, and a refusal is not
        -- ladder STRUCTURE — it is a terminal. (Mirrors "L4.Viz.Ladder".)
        Refuse{} -> leafFromExpr e

        -- 'var'
        App _ resolved [] -> do
          vid <- getFresh
          cfg <- getVizCfg
          -- The URI the TYPECHECKER stamped on this module's names, not
          -- 'cfg.moduleUri': that comes from the document id a caller supplies,
          -- and a caller that passes a synthetic one (the service's query-plan
          -- tests do) would make every name look foreign.
          let thisModule = case cfg.module' of MkModule _ uri _ -> uri
          let vname = mkPrettyVizName resolved
          case getUnique resolved of
            u | u == TC.trueUnique  -> pure $ V.TrueE vid vname
              | u == TC.falseUnique -> pure $ V.FalseE vid vname
              -- A name from ANOTHER module cannot be keyed by its unique's Int:
              -- each module numbers its own names from the same starting point
              -- (an importer does not continue its dependencies' supply; see
              -- 'unionCheckStates' in "LSP.L4.Rules"), so two different imported
              -- names can share one. Such a leaf gets a fresh id like any compound
              -- leaf; atom coalescing still merges its occurrences by atomId.
              -- Reachable once calls into imported rules are unfolded.
              | u.moduleUri /= thisModule -> leafFromExpr e
            _ -> do
              #leafExprs %= Map.insert vname.unique e
              varLeaf vid vname resolved
            -- TODO: Check how exactly a function of no args, as opposed to a var, would be represented?
            -- There was some discussion of this at a meeting, but can't remember exactly what was said

        App appAnno fnResolved args -> do
          fnOfAppIsFnFromBooleansToBoolean <- and <$> traverse hasBooleanType (appAnno : map getAnno args)
          -- for now, only translating App of boolean functions to V.App
          if fnOfAppIsFnFromBooleansToBoolean
            then do
              vid <- getFresh
              prepEvalAppMaker vid e
              #leafExprs %= Map.insert vid.id e
              let uniq = vid.id
                  label = prettyLayout e
                  vname = V.MkName uniq label
              refs <- freeInputRefsExpanded Set.empty e
              recordAtomInputRefs uniq refs
              atomId <- keyLeaf uniq e
              args' <- traverse (go CtxNone) args
              expansion <- case fnResolved of
                Ref _ callee _ -> expandCall callee e
                _ -> pure Nothing
              pure (V.App vid vname args' atomId expansion)
            else
              leafFromExpr e

        -- A first-match guarded chain over BOOLEAN bodies -- @IF-THEN-ELSE@,
        -- @BRANCH@, @CONSIDER@ -- is ladder structure, not a leaf. Shared with the
        -- core visualiser via "L4.Viz.GuardedRows"; this module and
        -- "L4.Viz.Ladder" carry near-identical copies of 'translateExpr', so the
        -- expansion lives in neither. Every bail-out lands on 'leafFromExpr', i.e.
        -- the pre-existing behaviour.
        _ -> do
          isBool <- hasBooleanType (getAnno e)
          case GR.normaliseGuarded e of
            Just rows
              | isBool
              , not (any (GR.hasEffectfulNode . fst) rows.grRows) ->
                  GR.guardedToLadder getFresh (go CtxNone) rows
            _ -> leafFromExpr e

scanAnd :: Expr Resolved -> [Expr Resolved]
scanAnd (And _ e1 e2) =
  scanAnd e1 <> scanAnd e2
scanAnd e = [e]

scanOr :: Expr Resolved -> [Expr Resolved]
scanOr (Or _ e1 e2) =
  scanOr e1 <> scanOr e2
scanOr e = [e]

------------------------------------------------------
-- Leaf makers
------------------------------------------------------

defaultUBoolVarValue :: V.UBoolValue
defaultUBoolVarValue = V.UnknownV

defaultUBoolVarCanInline :: Bool
defaultUBoolVarCanInline = False

varLeaf :: V.ID -> V.Name -> Resolved -> Viz IRExpr
varLeaf vid vname resolved = do
  canInline <- case resolved of
    Ref _ uniq _ -> hasDefForInlining uniq
    Def uniq _ -> hasDefForInlining uniq
    _ -> pure False
  -- TODO: Prob need to do this `canInline` thing for things that aren't App of no args too?
  let target = (getUnique resolved).unique
  refs <-
    lookupLocalDecideBody target >>= \case
      Nothing -> pure (Set.singleton (MkInputRef vname.unique []))
      Just body -> freeInputRefsExpanded (Set.singleton vname.unique) body
  recordAtomInputRefs vname.unique refs
  atomId <- keyLeaf vname.unique (App emptyAnno resolved [])
  defaults <- use #typicallyDefaults
  let mTypically = Map.lookup (getUnique resolved).unique defaults
  -- A bare reference to a same-module rule of no parameters is a call too.
  expansion <-
    if canInline
      then expandCall (getUnique resolved) (App emptyAnno resolved [])
      else pure Nothing
  pure $ V.UBoolVar vid vname defaultUBoolVarValue canInline atomId mTypically expansion

leafFromExpr :: Expr Resolved -> Viz IRExpr
leafFromExpr expr = do
  vid <- getFresh
  tempUniqueTODO <- getFresh
  let uniq = tempUniqueTODO.id
  refs <- freeInputRefsExpanded Set.empty expr
  recordAtomInputRefs uniq refs
  #leafExprs %= Map.insert uniq expr
  -- A call with arguments to a rule defined in this module can be expanded in
  -- place: 'inlineExprs' substitutes the arguments for the parameters. The leaf
  -- keeps its fresh id, so remember which rule it calls.
  canInline <- case expr of
    App _ (Ref _ callee _) (_ : _) -> do
      known <- hasDefForInlining callee
      when known $ #callLeafTargets %= Map.insert uniq callee.unique
      pure known
    _ -> pure defaultUBoolVarCanInline
  expansion <-
    if canInline
      then case expr of
        App _ (Ref _ callee _) _ -> expandCall callee expr
        _ -> pure Nothing
      else pure Nothing
  atomId <- keyLeaf uniq expr
  let label = prettyLayout expr
  pure $
    V.UBoolVar
      vid
      (V.MkName uniq label)
      defaultUBoolVarValue
      canInline
      atomId
      Nothing  -- compound leaf: not a bare boolean binder, so no TYPICALLY prior
      expansion

------------------------------------------------------
-- Call expansions (WHERE-INLINING-SPEC §10)
------------------------------------------------------

{- | The expansion of one call leaf: the called rule's body with the call's
arguments put in place of its parameters, translated by 'translateGo' in the
CALLER's state.

That last part is the whole point. The function name stays the caller's, fresh
ids keep coming from the caller's counter (which starts above every unique in
the module when expansions are on, so no fresh id can equal a name's unique —
smucclaw/l4-ide#991), and a leaf is keyed exactly as the caller would key it.
So an argument inlined from the call IS the caller's leaf for that argument:
@a@ inlined from @limb a b@ has the caller's @a@'s unique, and so its atomId.

The callee's own WHERE definitions are inlined into the substituted body
('Transform.inlineLocalBindings', as @l4 verify@ does before it reads a call
through) before anything is drawn. They have to be. A local name has ONE unique
in every call of its rule, and stands for a different proposition in each, since
its definition has that call's arguments in it; drawn as a leaf it would be keyed
by its name, and then @ok WHERE ok MEANS p@ called with @a@ and with @b@ was one
atom, a local named @a@ meaning @NOT p@ was the caller's input @a@, and a callee's
@both@ was the caller's own @both@ (all measured 2026-10-05). Inlined, each such
leaf is drawn as what it says after substitution, keyed like any other.

A local that 'Transform.inlineLocalBindings' leaves in place — recursive, an
@ASSUME@, applied to one of its own parameters as a function, or referenced at
another arity — would bring back exactly that problem, so a call whose reduced
body still binds anything locally is not expanded at all.

Only the call itself is reduced — the step 'Transform.unfoldOnce' takes at the
root, without also rewriting calls inside the arguments, which keep their own
expansions. 'Nothing' when expansions are off, the callee is not a rule of this
module at this arity, the callee is already being expanded around this node
(recursion), the reduced body keeps a local binding (above), or this pass's
depth limit or the decision's 'expansionNodeBudget' says stop ('doVisualize'
then discards an over-budget pass).
-}
expandCall :: Unique -> Expr Resolved -> Viz (Maybe IRExpr)
expandCall callee call = do
  cfg <- getVizCfg
  env <- ask
  known <- hasDefForInlining callee
  bodies <- use #expansionBodies
  spent <- use #expansionNodes
  let reduced = case (call, join (Map.lookup callee.unique bodies)) of
        (App _ _ args, Just (ps, body))
          | length args == length ps -> Just (Transform.substParams (zip ps args) body)
        _ -> Nothing
  case reduced of
    Just body
      | cfg.expandCalls
      , known
      , callee.unique `notElem` env.expansionStack ->
          if
            | length env.expansionStack >= env.expansionDepthLimit -> do
                assign #expansionCutByDepth True
                pure Nothing
            | spent >= expansionNodeBudget -> do
                assign #expansionOverBudget True
                pure Nothing
            | otherwise -> do
                -- A definition's body is stored desugared (@AND@ as a function
                -- application); resugar it as 'translateDecide' does the caller's.
                let sweet = carameliseExpr body
                ir <- local (\e -> e { expansionStack = callee.unique : e.expansionStack }) $
                  translateGo CtxNone (if cfg.shouldSimplify then Transform.simplify sweet else sweet)
                -- Expansions nested inside @ir@ have charged for themselves.
                spentNow <- use #expansionNodes
                let total = spentNow + ownNodes ir
                assign #expansionNodes total
                when (total > expansionNodeBudget) $ assign #expansionOverBudget True
                pure (Just ir)
    _ -> pure Nothing

-- | Does a @WHERE@ or @LET … IN@ survive anywhere in this expression?
bindsLocally :: Expr Resolved -> Bool
bindsLocally = anyOf (cosmosOf (gplate @(Expr Resolved))) $ \case
  Where {} -> True
  LetIn {} -> True
  _ -> False

-- | IR nodes in an expression, not counting what sits inside expansions.
ownNodes :: IRExpr -> Int
ownNodes = \case
  V.And _ xs -> 1 + sum (map ownNodes xs)
  V.Or _ xs -> 1 + sum (map ownNodes xs)
  V.Not _ x -> 1 + ownNodes x
  V.Implies _ p q _ -> 1 + ownNodes p + ownNodes q
  V.App _ _ xs _ _ -> 1 + sum (map ownNodes xs)
  V.UBoolVar{} -> 1
  V.TrueE{} -> 1
  V.FalseE{} -> 1
  V.InertE{} -> 1

------------------------------------------------------
-- Name helpers
------------------------------------------------------

mkPrettyVizName :: Resolved -> V.Name
mkPrettyVizName = mkVizNameWith prettyLayout

-- It's not obvious to me that we want to be using
-- getOriginal (as getUniqueName does), instead of getActual,
-- but I'm going with this for now since it's what was used to translate the function name.
mkVizNameWith :: (Name -> Text) -> Resolved -> V.Name
mkVizNameWith printer (getUniqueName -> (MkUnique {unique}, name)) =
  V.MkName unique (printer name)

------------------------------------------------------
-- AtomId generation
------------------------------------------------------

-- | Key a leaf's term (R3, "L4.Viz.AtomKey"), remember the key under the leaf's
-- id for the query plan, and name its atom in this decision's diagram.
--
-- Inside an expansion the term is the callee's body with the call's arguments
-- already put in ('expandCall'), so a leaf is keyed in the CALLER's context: the
-- @a@ inlined from @limb a b@ is the caller's own @a@, and @limb a b@ and
-- @limb c d@ share no atom.
keyLeaf :: Int -> Expr Resolved -> Viz Text
keyLeaf uniq expr = do
  env <- use #keyEnv
  locals <- getLocalDecls
  let term = withLocalsInScope locals expr
      bareReference = case expr of
        App _ _ [] -> True
        _ -> False
  -- A leaf whose value depends on when it is evaluated (a ledger read, or a call
  -- to a rule that makes one) is C1's @fresh@: each occurrence is its own atom,
  -- numbered in drawing order so the number survives an edit elsewhere.
  key <-
    if not bareReference && isEffectful env term
      then do
        n <- #freshLeaves <%= (+ 1)
        #freshLeafIds %= IntSet.insert uniq
        pure (termKey env term <> "|occurrence " <> Text.pack (show n))
      else pure (termKey env term)
  #leafKeys %= Map.insert uniq key
  functionName <- use #functionName
  pure (atomIdOfKey functionName key)

------------------------------------------------------
-- Crude dependency tracking
------------------------------------------------------

freeInputRefs :: Expr Resolved -> Set InputRef
freeInputRefs expr =
  refsFromVars expr <> refsFromProjections expr
 where
  refsFromVars :: Expr Resolved -> Set InputRef
  refsFromVars =
    foldMapOf (Optics.gplate @(Expr Resolved)) $ \case
      App _ (Ref _ uniq _) [] -> Set.singleton (MkInputRef uniq.unique [])
      _ -> Set.empty

  refsFromProjections :: Expr Resolved -> Set InputRef
  refsFromProjections =
    foldMapOf (Optics.gplate @(Expr Resolved)) $ \case
      p@(Proj _ _ _) ->
        case projChain [] p of
          Nothing -> Set.empty
          Just r -> Set.singleton r
      _ -> Set.empty

  projChain :: [Text] -> Expr Resolved -> Maybe InputRef
  projChain acc = \case
    Proj _ base fieldResolved ->
      projChain (projectionSegments fieldResolved <> acc) base
    App _ (Ref _ uniq _) [] ->
      Just (MkInputRef uniq.unique acc)
    _ -> Nothing

  projectionSegments :: Resolved -> [Text]
  projectionSegments resolved =
    case rawName (getActual resolved) of
      QualifiedName qs n -> NE.toList qs <> [n]
      NormalName n -> [n]
      PreDef n -> [n]

------------------------------------------------------
-- Helpers for checking if an Expr has Boolean type
------------------------------------------------------

hasBooleanType :: Anno_ t Extension -> Viz Bool
hasBooleanType (Anno {extra = Extension {resolvedInfo = Just (TypeInfo ty _)}}) =
  isBooleanType ty
hasBooleanType _ = pure False

-- | Returns True iff the (expanded) Type Resolved is that of a L4 BOOLEAN
isBooleanType :: Type' Resolved -> Viz Bool
isBooleanType ty = do
  type' <- getExpandedType ty
  pure $ case type' of
    TyApp _ (Ref _ uniq _) [] ->
      uniq == TC.booleanUnique
    _ -> False

------------------------------------------------------
-- UBoolValue x L4 True/False conversion helpers
------------------------------------------------------

toBoolExpr :: V.UBoolValue -> Expr Resolved
toBoolExpr = \ case
  V.FalseV   -> App emptyAnno TC.falseRef []
  V.TrueV    -> App emptyAnno TC.trueRef []
  V.UnknownV -> error "impossible for now"

------------------------------------------------------
-- Inline Exprs
------------------------------------------------------

{- | Given a @VizState@, a top-level @Decide Resolved@, and a bunch of Uniques,
inline the calls to those Uniques in the Decide.

A Unique may name a definition directly (a leaf that is a bare reference, whose
id IS the definition's unique), or name a leaf that is a call with arguments (see
'callLeafTargets'). Either way every call to that definition /at its own arity/
is replaced by its body with the arguments put in place of the parameters
('Transform.unfoldOnce'). A reference at another arity — the rule passed as a
value — is left alone.

This used to replace @f x y@ by @f@'s bare body and drop the arguments; it was
masked only because the gesture was offered on bare references alone.

Note: requires that the definition be in the same module as the call. Lifting
this restriction is not hard, but it's also not totally obvious that that'd be
good UX.
-}
inlineExprs :: VizState -> Decide Resolved -> [Int] -> Decide Resolved
inlineExprs vs = foldr (inlineExpr vs)

inlineExpr :: VizState -> Int -> Decide Resolved -> Decide Resolved
inlineExpr vs target =
  case Map.lookup definition vs.defsForInlining of
    Just (u, unfoldable) -> over decideBody (Transform.unfoldOnce (DataMap.singleton u (withLocalsInlined unfoldable)))
    Nothing -> id
  where
    definition = Map.findWithDefault target target vs.callLeafTargets
    -- The definition's own WHERE definitions are inlined first, as 'expandCall'
    -- does and for the same reason: a local keeps ONE unique in every copy the
    -- unfolding makes, though each copy has that call's arguments in it, so two
    -- calls' copies of one local would be drawn as one proposition (found by
    -- adversarial review of smucclaw/l4-ide#1013). A local that cannot be
    -- inlined (a recursive one) still comes along as it is.
    withLocalsInlined (Transform.MkUnfoldable ps rhs) = Transform.MkUnfoldable ps (Transform.inlineLocalBindings rhs)
