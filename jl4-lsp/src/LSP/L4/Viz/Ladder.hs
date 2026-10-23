{-# LANGUAGE ViewPatterns, PatternSynonyms #-}

module LSP.L4.Viz.Ladder (
  -- * Viz Decide entrypoint
  doVisualize,

  -- * Inline Exprs (currently only inlines simple 'App of no args' exprs)
  inlineExprs,

  -- * VizConfig, VizState
  VizConfig (..),
  mkVizConfig,
  spellingOut,
  VizState,

  -- * Viz State helpers
  lookupAppExprMaker,
  getAtomDeps,
  InputRef (..),
  getAtomInputRefs,
  getRefusingAtoms,
  getUnreadableRefusals,
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
import qualified Data.Map.Strict as DataMap
import qualified Data.Set as Set
import qualified Data.List.NonEmpty as NE
import Optics.State.Operators ((<%=), (%=))
import Optics
import Control.Monad.Extra (unlessM)
import qualified Language.LSP.Protocol.Types as LSP

import qualified L4.TypeCheck as TC
import L4.Viz.Ladder (InputRef(..), generateAtomId)
import L4.Annotation
import L4.Syntax
import L4.Print (prettyLayout)
import qualified L4.Transform as Transform (simplify, spellOutConnectives, inlineLetsForViz, letInliningNodeBudget, clauseGroupLadderBudget, holdsGeneratedNodes, writtenAsClauses)
import LSP.L4.Viz.VizExpr
  ( ID (..), IRExpr,
    RenderAsLadderInfo (..),
  )
import qualified LSP.L4.Viz.VizExpr as V
import qualified LSP.L4.Viz.CustomProtocol as V (EvalAppRequestParams (..))
import LSP.L4.Viz.VizExpr (InertContext(..))
import L4.Desugar
import qualified L4.Refusal as Refusal

------------------------------------------------------
-- Monad
------------------------------------------------------

newtype Viz a = MkViz {getViz :: VizEnv -> VizState -> (Either VizError a, VizState)}
  deriving
    (Functor, Applicative, Monad, MonadState VizState, MonadError VizError, MonadReader VizEnv)
    via ReaderT VizEnv (ExceptT VizError (State VizState))

-- | A 'local' env
newtype VizEnv = MkVizEnv { localDecls :: [LocalDecl Resolved]}

mkVizConfig :: LSP.VersionedTextDocumentIdentifier -> Module Resolved -> TC.Substitution -> Bool -> VizConfig
mkVizConfig lspVerDocId module' substitution shouldSimplify =
  let moduleUri = toNormalizedUri lspVerDocId._uri
  in MkVizConfig
    { moduleUri
    , module'
    , verDocId = V.fromLspVerDocId lspVerDocId
    , substitution
    , shouldSimplify
    , spellOut = False
    }

-- | Draw each @IMPLIES@ and each Boolean @IF@ in connective position as the
-- @AND@, @OR@ and @NOT@ it stands for ('Transform.spellOutConnectives'). A rule is
-- otherwise drawn as written, where each is one leaf that names only the inputs
-- directly under it.
spellingOut :: VizConfig -> VizConfig
spellingOut cfg = cfg { spellOut = True }

data VizConfig = MkVizConfig
  { moduleUri      :: !NormalizedUri
  , module'        :: Module Resolved
  , verDocId       :: !V.VersionedDocId
  , substitution   :: !TC.Substitution
  , shouldSimplify :: !Bool
  , spellOut       :: !Bool
  }
  deriving stock (Show, Generic, Eq)


data VizState = MkVizState
  { cfg            :: !VizConfig
  , maxId          :: !ID
  , functionName   :: !Text
  -- ^ Name of the function being visualized (for atomId generation)
  , appExprMakers  :: IntMap (V.EvalAppRequestParams -> Expr Resolved)
  -- ^ Map from Unique of V.ID to eval-app-directive maker
  , defsForInlining :: IntMap (Expr Resolved)
  , atomDeps       :: IntMap IntSet
  , atomInputRefs  :: IntMap (Set InputRef)
  , refusingDefs   :: Refusal.AlwaysRefusing
  -- ^ The module's definitions that always refuse ("L4.Refusal"). Lazy: a pass
  -- that names no definition never computes it.
  , sometimesRefusingDefs :: Refusal.SometimesRefusing
  -- ^ The module's definitions that refuse on only some paths. Lazy, like
  -- 'refusingDefs'.
  , refusingAtoms  :: IntMap Text
  -- ^ Leaf id -> the reason it refuses with, for a leaf evaluation can only ever
  -- refuse at: a @REFUSE@, or a bare reference to a definition that always
  -- refuses. The query plan never asks one (R7).
  , unreadableRefusals :: [(Text, Text)]
  -- ^ Leaves that hold a refusal without being one, newest first: what the leaf
  -- says, and the reason it refuses with. A @CONSIDER@ arm, a comparison operand,
  -- a call, and a reference to a definition that refuses on only some paths are
  -- such leaves. The plan cannot order its questions around a refusal there.
  }
  deriving stock (Generic)

instance Show VizState where
  show MkVizState{cfg, maxId, functionName, appExprMakers, defsForInlining, atomDeps, atomInputRefs} =
    "MkVizState { cfg = " <> show cfg <>
    ", maxId = " <> show maxId <>
    ", functionName = " <> show functionName <>
    ", (keys of) appExprMakers =   " <> show (Map.keys appExprMakers) <>
    ", defsForInlining =  " <> show defsForInlining <>
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
    , atomDeps = Map.empty
    , atomInputRefs = Map.empty
    , refusingDefs = always
    , sometimesRefusingDefs = Refusal.sometimesRefusing always cfg.module'
    , refusingAtoms = Map.empty
    , unreadableRefusals = []
    }
  where
    always = Refusal.alwaysRefusing cfg.module'

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

collectDefsForInlining :: Viz (IntMap (Expr Resolved))
collectDefsForInlining = do
  cfg <- getVizCfg
  pure $ toMap (foldTopLevelDecides tryExtractDef cfg.module')
    where
      tryExtractDef :: Decide Resolved -> [(Unique, Expr Resolved)]
      tryExtractDef = foldDecides $ \ case
        DefForInlining uniq' definiens -> [(uniq', definiens)]
        _ -> []

      toMap :: [(Unique, Expr Resolved)] -> IntMap (Expr Resolved)
      toMap = Map.fromList . map (\(MkUnique _ k _, v) -> (k, v))

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

-- | The leaves evaluation can only refuse at, by leaf id, with the reason each
-- refuses with (see 'refusingAtoms').
getRefusingAtoms :: VizState -> IntMap Text
getRefusingAtoms vs = vs.refusingAtoms

-- | The leaves that hold a refusal without being one, in the order they were
-- drawn: what the leaf says, and the reason it refuses with (see
-- 'unreadableRefusals').
getUnreadableRefusals :: VizState -> [(Text, Text)]
getUnreadableRefusals vs = reverse vs.unreadableRefusals

getVizConfig :: VizState -> VizConfig
getVizConfig vs = vs.cfg

------------------------------------------------------
-- VizError
------------------------------------------------------

data VizError
  = InvalidProgramNoDecidesFound
  | InvalidDecideMustHaveBoolRetType
  | ClauseGroupTooLarge Int
    -- ^ a rule written as DECIDE clauses whose ladder has more nodes than this
  | ClauseGroupTooLong Int
    -- ^ a rule written as DECIDE clauses that, written out as the CONSIDER it
    -- stands for, has more expression nodes than this
    -- ('L4.Transform.letInliningNodeBudget')
  deriving stock (Eq, Generic, Show)
  deriving anyclass (NFData)

-- TODO: Incorporate context like the specific erroring rule and the src range too
prettyPrintVizError :: VizError -> Text
prettyPrintVizError = \ case
  InvalidProgramNoDecidesFound ->
    "The program isn't the right sort for visualization: there are no DECIDE rules that can be visualized."
  InvalidDecideMustHaveBoolRetType ->
    "Can only visualize, as a ladder diagram, a DECIDE that returns a boolean."
  ClauseGroupTooLarge budget ->
    "These clauses would draw a ladder of more than " <> Text.pack (show budget) <> " boxes, too many to show. Split the rule into smaller groups of clauses, or into named sub-rules."
  ClauseGroupTooLong budget ->
    "These clauses are too long to draw: written out as the CONSIDER they stand for, they come to more than " <> Text.pack (show budget) <> " parts. Split the rule into smaller groups of clauses, or into named sub-rules."

------------------------------------------------------
-- Entrypoint: Visualise
------------------------------------------------------

-- | Entrypoint: Generate boolean circuits of the given 'Decide'.
doVisualize :: Decide Resolved -> VizConfig -> Either VizError (RenderAsLadderInfo, VizState)
doVisualize decide cfg =
  let (result, vizState) = (vizProgram decide).getViz initialEnv initialVizState
  in case result of
    Left err         -> Left err
    Right ladderInfo -> Right (ladderInfo, vizState)
  where
    initialEnv = MkVizEnv { localDecls = [] }
    initialVizState = mkInitialVizState cfg

vizProgram :: Decide Resolved -> Viz RenderAsLadderInfo
vizProgram decide = MkRenderAsLadderInfo <$> getVerDocId <*> translateDecide decide

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
translateDecide asWritten@(MkDecide _ (MkTypeSig _ givenSig _) (MkAppForm _ funResolved appArgs _) body0) =
  do
    -- Asked before anything is read through: a rule that returns a number is
    -- not too large to draw, it is not a ladder at all.
    unlessM (hasBooleanType (getAnno body0)) $
      throwError InvalidDecideMustHaveBoolRetType
    -- A rule written as DECIDE clauses is drawn as the CONSIDER it stands for.
    -- Mirrors 'L4.Viz.Ladder.translateDecide'.
    let isClauseGroup = Transform.writtenAsClauses asWritten
        -- The limits apply to a group that has something to read through; one
        -- whose first clause names each input as the GIVEN does (or is @_@) has
        -- nothing, and is drawn as a rule written without clauses is.
        readsThrough = isClauseGroup && Transform.holdsGeneratedNodes body0
    body <- case Transform.inlineLetsForViz body0 of
      Right inlined -> pure inlined
      Left _ | readsThrough -> throwError (ClauseGroupTooLong Transform.letInliningNodeBudget)
             | otherwise    -> pure body0

    let funName = mkPrettyVizName funResolved
    assign #functionName funName.label
    assign #defsForInlining =<< collectDefsForInlining
    -- A bare reference to a name is a leaf keyed by the name's unique; every other
    -- leaf is keyed by a fresh id from 'getFresh'. Starting the fresh ids above
    -- every unique in the rule keeps the two ranges apart, so a fresh id cannot
    -- equal a name's unique and make two different propositions one variable.
    -- 'body' is the rule as it is drawn, so it holds any definition read into it.
    -- Mirrors 'L4.Viz.Ladder.translateDecide'.
    assign #maxId (MkID (maximum (0 : [u.unique | u <- toListOf (gplate @Unique) body])))
    shouldSimplify <- getShouldSimplify
    spelledOut     <- (.spellOut) <$> getVizCfg
    vid            <- getFresh
    -- Read after 'carameliseExpr', which is what turns a call to the IMPLIES
    -- function into the 'Implies' node, so that nothing else about the rule moves.
    -- Mirrors 'L4.Viz.Ladder.translateDecide'.
    let caramelised = carameliseExpr body
    vizBody        <- translateExpr shouldSimplify (if spelledOut then Transform.spellOutConnectives caramelised else caramelised)
    when (readsThrough && V.irExceeds Transform.clauseGroupLadderBudget vizBody) $
      throwError (ClauseGroupTooLarge Transform.clauseGroupLadderBudget)
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
        getResolved (MkOptionallyTypedName _ paramName _) = paramName

-- | Context for translating expressions - tracks whether we're inside And or Or
data TranslateContext = CtxAnd | CtxOr | CtxNone
  deriving (Eq, Show)

translateExpr :: Bool -> Expr Resolved -> Viz IRExpr
translateExpr True  =
  translateExpr False . Transform.simplify
translateExpr False = go CtxNone
  where
    go :: TranslateContext -> Expr Resolved -> Viz IRExpr
    go _ctx e =
      case e of
        Not _ negand -> do
          vid <- getFresh
          V.Not vid <$> go CtxNone negand
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
        Refuse _ msg -> makeLeaf e >>= refusingLeaf (Just (Refusal.refusalMessage msg))

        -- 'var'
        App _ resolved [] -> do
          vid <- getFresh
          let vname = mkPrettyVizName resolved
          case getUnique resolved of
            u | u == TC.trueUnique  -> pure $ V.TrueE vid vname
              | u == TC.falseUnique -> pure $ V.FalseE vid vname
            _ -> do
              recordUnreadableReference e resolved
              varLeaf vid vname resolved
            -- TODO: Check how exactly a function of no args, as opposed to a var, would be represented?
            -- There was some discussion of this at a meeting, but can't remember exactly what was said

        App appAnno _fnResolved args -> do
          fnOfAppIsFnFromBooleansToBoolean <- and <$> traverse hasBooleanType (appAnno : map getAnno args)
          -- for now, only translating App of boolean functions to V.App
          if fnOfAppIsFnFromBooleansToBoolean
            then do
              recordUnreadableRefusal e
              vid <- getFresh
              prepEvalAppMaker vid e
              let uniq = vid.id
                  label = prettyLayout e
                  vname = V.MkName uniq label
              refs <- freeInputRefsExpanded Set.empty e
              recordAtomInputRefs uniq refs
              functionName <- use #functionName
              let atomId = generateAtomId functionName label refs
              V.App vid vname <$> traverse (go CtxNone) args <*> pure atomId
            else
              leafFromExpr e

        _ -> do
          leafFromExpr e

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
  functionName <- use #functionName
  let atomId = generateAtomId functionName vname.label refs
  -- A rule of no inputs that always refuses is not a question: evaluation takes
  -- no answer for it, it forces the rule (R7). One that refuses on only some
  -- paths is not one either; see 'recordUnreadableReference'.
  refusing <- use #refusingDefs
  refusingLeaf (DataMap.lookup (getUnique resolved) refusing) $
    V.UBoolVar vid vname defaultUBoolVarValue canInline atomId

-- | Record a leaf as one evaluation can only refuse at, with the reason, if it
-- has one.
refusingLeaf :: Maybe Text -> IRExpr -> Viz IRExpr
refusingLeaf reason leaf = do
  case (reason, leaf) of
    (Just r, V.UBoolVar _ nm _ _ _) -> #refusingAtoms %= Map.insert nm.unique r
    _ -> pure ()
  pure leaf

-- | A leaf for an expression that is none of the shapes the ladder draws as
-- structure. A refusal inside it is one the plan cannot read.
leafFromExpr :: Expr Resolved -> Viz IRExpr
leafFromExpr expr = do
  recordUnreadableRefusal expr
  makeLeaf expr

-- | Record a leaf that holds a refusal without being one.
recordUnreadableRefusal :: Expr Resolved -> Viz ()
recordUnreadableRefusal expr = do
  always <- use #refusingDefs
  sometimes <- use #sometimesRefusingDefs
  case Refusal.refusalWithin always sometimes expr of
    Just reason -> #unreadableRefusals %= ((prettyLayout expr, reason) :)
    Nothing -> pure ()

-- | Record a bare reference to a definition that refuses on only some paths.
-- Whether it refuses turns on what the plan does not read, so the plan can
-- neither ask it as a question nor report its refusal.
recordUnreadableReference :: Expr Resolved -> Resolved -> Viz ()
recordUnreadableReference expr resolved = do
  sometimes <- use #sometimesRefusingDefs
  case DataMap.lookup (getUnique resolved) sometimes of
    Just reason -> #unreadableRefusals %= ((prettyLayout expr, reason) :)
    Nothing -> pure ()

makeLeaf :: Expr Resolved -> Viz IRExpr
makeLeaf expr = do
  vid <- getFresh
  tempUniqueTODO <- getFresh
  let uniq = tempUniqueTODO.id
  refs <- freeInputRefsExpanded Set.empty expr
  recordAtomInputRefs uniq refs
  functionName <- use #functionName
  let label = prettyLayout expr
      atomId = generateAtomId functionName label refs
  pure $
    V.UBoolVar
      vid
      (V.MkName uniq label)
      defaultUBoolVarValue
      defaultUBoolVarCanInline
      atomId

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

{- | We only really need a *uni*directional pattern synonym,
but the other direction might be useful for testing. -}
pattern DefForInlining :: Unique -> Expr Resolved -> Decide Resolved
pattern DefForInlining unique definiens <-
  MkDecide _ _ (MkAppForm _ (Def unique _) _ _) definiens
  where
    DefForInlining unique definiens =
      MkDecide emptyAnno
      (MkTypeSig emptyAnno (MkGivenSig emptyAnno []) Nothing)
      (MkAppForm emptyAnno (Def unique TC.emptyName) [] Nothing)
      definiens

{- | Given a @VizState@, a top-level @Decide Resolved@, and a bunch of Uniques,
inline refs to those Uniques in the Decide.

Note:
- Currently only inlines 'App of no args' exprs
- Currently requires that the definiens be in the same module as the ref.
Lifting this restriction is not hard, but it's also not totally obvious that that'd be good UX.
-}
inlineExprs :: VizState -> Decide Resolved -> [Int] -> Decide Resolved
inlineExprs vs = foldr (inlineExpr vs)

inlineExpr :: VizState -> Int -> Decide Resolved -> Decide Resolved
inlineExpr vs target = over decideBody $ transformOf (Optics.gplate @(Expr Resolved)) replace
  where
    replace :: Expr Resolved -> Expr Resolved
    replace expr =
      if isRefOfTarget expr
      then
      case Map.lookup target vs.defsForInlining of
        Just definiens -> definiens
        Nothing -> error "Programmer error: either isRefOfTarget has false positives or we aren't recording all the definienda"
      else expr

    isRefOfTarget :: Expr Resolved -> Bool
    isRefOfTarget = \ case
      App _ resolved _args ->
        case resolved of
          Ref _ uniq _ -> uniq.unique == target
          _            -> False
      -- TODO: Look into whether we should handle other cases too
      _                    -> False
