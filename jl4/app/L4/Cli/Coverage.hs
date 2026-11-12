{-# LANGUAGE PatternSynonyms #-}
-- | Coverage buckets for one decision, backend-neutral: what the Catala
-- witness gate ("L4.Cli.CatalaWitness") and a standalone coverage report both
-- stand on (CATALA-EXPORT-SPEC §8.4; VERIFICATION-BACKEND-LOWERING-SPEC R-V10).
--
-- A __cover point__ is a condition the decision branches on, and a __bucket__
-- is one combination of truth values of all the cover points. The cover points
-- are the /leaves/ of the rungs: the conditions that are not themselves made
-- of @AND@, @OR@ or @NOT@, as the ladder diagram and @l4 verify@ draw them, so
-- @a OR b@ is two cover points and a leaf used in two rungs is one. Each
-- bucket ends up in exactly one of three states:
--
-- * 'Witnessed': at least one input realises it, found among a fixed set of
--   candidates and confirmed by the jl4 evaluator, which also gives the
--   decision's answer there;
-- * 'Impossible': no input realises it, which a solver proved;
-- * 'Undecided': neither, with the reason.
--
-- Two oracles with fixed jobs, and neither is a second semantics of the rule:
--
-- * the jl4 evaluator decides which bucket a candidate input realises, and
--   what the decision answers at a witness;
-- * the solver only proves a bucket impossible, and finds a witness when no
--   candidate realises one (that witness is replayed through the evaluator
--   before it is used, and 'rowFromSolver' says where it came from).
--
-- Candidates come from a fixed set ('sampleValues': each literal the cover
-- points reach, one either side of it, zero; both Booleans; every
-- constructor), so the witnesses do not depend on which solver, or which
-- version of it, is installed.
--
-- __Leaf level, and when it is not used.__ The cross over leaves is the
-- finer model, and it is used unless one of these holds, in which case the
-- decision is covered at 'RungLevel' (the rung conditions as written), with
-- the reason in the result:
--
-- * the ladder diagram cannot break the rungs down, or a leaf has no
--   expression to evaluate;
-- * there are more leaves than 'atomLimit';
-- * a leaf raises at an input where its rung is decided without reaching it
--   (@x /= 0 AND 10 / x > 2@ at @x = 0@): that input would land in no leaf
--   bucket, and a cross over leaves that loses a reachable input is worse
--   than a coarser model that keeps it;
-- * the caller asked to fall back when some bucket is undecided
--   ('ceFallbackOnUndecided'), and one is.
module L4.Cli.Coverage
  ( CoverEnv (..)
  , CoverTarget (..)
  , Level (..)
  , CoverPoint (..)
  , Row (..)
  , BucketStatus (..)
  , Bucket (..)
  , Cover (..)
  , coverTarget
  , hasUndecided
  , atomLimit
  , perCombination
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import L4.Annotation (emptyAnno, getAnno, rangeOf)
import qualified L4.Decision.QueryPlan as QP
import L4.Evaluate.ValueLazy (Environment, NF (..), Value (..))
import L4.EvaluateLazy (EvalConfig, EvalDirectiveResult (..), EvalDirectiveValue (..), ReductionOutcome (..), execEvalExprInContextOfModule)
import L4.EvaluateLazy.Machine (pattern ValBool)
import L4.Parser.SrcSpan (SrcRange)
import L4.Print (prettyLayout)
import L4.Prove.Lower
import L4.Prove.Smt
import L4.Syntax
import qualified LSP.L4.Rules as Rules
import qualified LSP.L4.Viz.Ladder as LadderViz
import qualified LSP.L4.Viz.QueryPlan as VizQP
import qualified LSP.L4.Viz.VizExpr as VizExpr
import qualified Language.LSP.Protocol.Types as LSP

import L4.Cli.Prove (Solver (..), samplePointsUpTo)

-- | More cover points than this is 2^n buckets too many to decide one by one.
-- Counted in leaves; a decision past it is covered at rung level, and past it
-- there too it is not covered at all. (Assumed, not ruled.)
atomLimit :: Int
atomLimit = 12

-- | At most this many candidate inputs per decision are evaluated.
candidateLimit :: Integer
candidateLimit = 4096

-- | At most this many witnesses per bucket, in candidate order. More than one,
-- because the candidates for a number include the literal a condition compares
-- with as well as one either side of it, and only a witness AT the literal
-- shows an edit from @>@ to @>=@ (audit of #784, finding 7). (Assumed, not
-- ruled.)
perCombination :: Int
perCombination = 8

-- | What a coverage run needs from the file it reads.
data CoverEnv ans = CoverEnv
  { ceEval :: EvalConfig
  , ceTc :: Rules.TypeCheckResult
  , ceImportEnv :: Environment
  , ceSolver :: Maybe Solver
  , ceSolverSecs :: Int
  , ceAnswer :: NF -> Maybe ans
    -- ^ how the caller renders the decision's answer at a witness; 'Nothing'
    -- leaves the bucket undecided
  , ceFallbackOnUndecided :: Bool
    -- ^ cover at rung level when the leaf cross leaves any bucket undecided,
    -- for a caller that needs every bucket decided (the Catala gate)
  }

-- | One decision to cover: its rungs, the conditions it branches on.
data CoverTarget = CoverTarget
  { ctName :: Resolved
  , ctDecide :: Decide Resolved
  , ctParams :: [(Resolved, Maybe (Type' Resolved))]
    -- ^ each parameter's binding occurrences, with its declared type
  , ctAppArgs :: [Resolved]
  , ctRungs :: [Expr Resolved]
  , ctReadsAssumes :: Bool
  }

-- | What the cover points are.
data Level
  = LeafLevel
  | RungLevel Text
    -- ^ the rungs as written, and why the leaves could not be used
  deriving stock (Eq, Show)

data CoverPoint = CoverPoint
  { cpExpr :: Expr Resolved
  , cpText :: Text
  , cpAtomId :: Maybe Text
    -- ^ the id @l4 verify@ and the wizard give this leaf; 'Nothing' at rung level
  , cpRange :: Maybe SrcRange
  }

data Row ans = Row
  { rowArgs :: [Expr Resolved]
  , rowArgsText :: [Text]
  , rowAnswer :: ans
  , rowFromSolver :: Bool
  }

data BucketStatus ans
  = Witnessed [Row ans]
  | Impossible
  | Undecided Text

data Bucket ans = Bucket
  { bkAssignment :: [Bool]
    -- ^ one truth value per cover point, in order
  , bkStatus :: BucketStatus ans
  }

data Cover ans = Cover
  { cvLevel :: Level
  , cvPoints :: [CoverPoint]
  , cvBuckets :: [Bucket ans]
    -- ^ every combination, the first cover point varying fastest
  }

hasUndecided :: Cover ans -> Bool
hasUndecided c = or [ True | Bucket _ (Undecided _) <- c.cvBuckets ]

-- | Cover one decision. 'Left' says why not even the rungs could be covered.
coverTarget :: forall ans. CoverEnv ans -> CoverTarget -> IO (Either Text (Cover ans))
coverTarget ce t
  | t.ctReadsAssumes = pure (Left "it reads an ASSUME, which a witness input cannot supply")
  | otherwise = case traverse paramOf (zip t.ctParams (map Just t.ctAppArgs <> repeat Nothing)) of
      Nothing -> pure (Left "a parameter has no declared type")
      Just params -> do
        leaf <- leafLevel params
        case leaf of
          Right c
            | ce.ceFallbackOnUndecided, (why : _) <- [ w | Bucket _ (Undecided w) <- c.cvBuckets ] ->
                rungLevel params ("a combination of the leaves could not be decided: " <> why)
            | otherwise -> pure (Right c)
          Left why -> rungLevel params why
 where
  tc = ce.ceTc
  mods = tc.module' : map (.module') (Rules.transitiveDependencies tc)
  env = mkProveEnv mods (tc.entityInfo <> foldMap (.entityInfo) (Rules.transitiveDependencies tc))

  paramOf ((given, mty), mapp) = do
    ty <- mty
    let extra = [ a | Just a <- [mapp], getUnique a /= getUnique given ]
    pure (given : extra, ty)

  ---------------------------------------------------------------------------
  -- The two levels
  ---------------------------------------------------------------------------

  rungPoints =
    [ CoverPoint { cpExpr = r, cpText = oneLine (prettyLayout r), cpAtomId = Nothing, cpRange = rangeOf r }
    | r <- t.ctRungs ]

  rungLevel params why
    | length t.ctRungs > atomLimit =
        pure (Left (tshow (length t.ctRungs) <> " atomic conditions, past the witness gate's limit of " <> tshow atomLimit))
    | otherwise = case lowerAtoms env params t.ctRungs of
        Left w -> pure (Left w)
        Right space -> do
          r <- search params rungPoints space Nothing
          pure (fmap (Cover (RungLevel why) rungPoints) r)

  leafLevel params = case leavesOf of
    Left why -> pure (Left why)
    Right pts
      | null pts -> pure (Left "the rungs have no condition to cover")
      | length pts > atomLimit ->
          pure (Left (tshow (length pts) <> " leaf conditions, past the limit of " <> tshow atomLimit))
      | otherwise -> case lowerAtoms env params (map (.cpExpr) pts) of
          Left why -> pure (Left why)
          Right space -> do
            r <- search params pts space (Just t.ctRungs)
            pure (fmap (Cover LeafLevel pts) r)

  ---------------------------------------------------------------------------
  -- Leaves, as the ladder diagram draws them
  ---------------------------------------------------------------------------

  -- One diagram of the rungs joined by AND, so every leaf is keyed in one
  -- numbering (an effectful leaf is keyed by its occurrence, and two diagrams
  -- would both call theirs the first). The AND is only a frame: the leaves
  -- are the same whatever joins the rungs. It takes the annotation of the
  -- first rung, whose type says Boolean, which the diagram insists on.
  leavesOf :: Either Text [CoverPoint]
  leavesOf = case t.ctRungs of
    [] -> Left "the decision has no rung"
    r0 : rest ->
      let joined = foldr1 (And (getAnno r0)) (r0 : rest)
          framed = case t.ctDecide of
            MkDecide ann sig af _ -> MkDecide ann sig af joined
      in case LadderViz.doVisualize framed vizCfg of
          Left err -> Left ("the ladder diagram cannot break the rungs down: " <> LadderViz.prettyPrintVizError err)
          Right (info, vs) ->
            let (_, _, order) = VizQP.vizExprToBoolExpr info.funDecl.body
                ids = QP.atomIdByUnique info.funDecl.fnName.label (VizQP.buildQueryPlanCache info vs)
                point u = case LadderViz.getLeafExpr vs u of
                  Nothing -> Left "a leaf condition has no expression to evaluate"
                  Just e -> Right CoverPoint
                    { cpExpr = e, cpText = oneLine (prettyLayout e)
                    , cpAtomId = Map.lookup u ids, cpRange = rangeOf e }
            in fmap mergeById (traverse point order)

  -- A leaf used twice is one cover point: the first occurrence stands for it.
  mergeById pts = go Set.empty pts
   where
    go _ [] = []
    go seen (p : ps) = case p.cpAtomId of
      Just a | Set.member a seen -> go seen ps
             | otherwise -> p : go (Set.insert a seen) ps
      Nothing -> p : go seen ps

  -- no simplification: a cover point is what the author wrote
  vizCfg = LadderViz.mkVizConfig
    LSP.VersionedTextDocumentIdentifier { LSP._uri = LSP.fromNormalizedUri (moduleUriOf tc.module'), LSP._version = 1 }
    tc.module' tc.substitution False

  moduleUriOf (MkModule _ uri _) = uri

  ---------------------------------------------------------------------------
  -- Candidates, buckets, the solver
  ---------------------------------------------------------------------------

  -- 'Left' only for the leaf level's own precondition, 'Just rungs': every
  -- candidate whose rungs the evaluator decides must still have all its leaves
  -- decided, or the cross would lose an input the rung level keeps.
  search params pts space guardRungs = do
    let free = space.asSpace.obFree
        cands = samplePointsUpTo candidateLimit [ (fv, sampleValues space.asSpace fv.fvSort) | fv <- free ]
        vals = map (map snd) cands
        n = length pts
        exprs = map (.cpExpr) pts
    vectors <- atomVectors params exprs vals
    guarded <- case guardRungs of
      Nothing -> pure False
      Just rs -> do
        rv <- atomVectors params rs vals
        pure (or [ isJust r && isNothing l | (r, l) <- zip rv vectors ])
    if guarded
      then pure (Left "a condition inside a rung raises at an input where an earlier condition of the rung already decides it, so that input would belong to no combination of the separate conditions")
      else do
        let witnessesOf = Map.map (take perCombination . reverse) $ Map.fromListWith (<>)
              [ (bs, [map snd c]) | (c, Just bs) <- zip cands vectors ]
            combos = [ [ odd (k `div` (2 ^ i)) | i <- [0 .. n - 1] ] | k <- [0 .. (2 ^ n :: Integer) - 1] ]
        fmap Right $ for combos \bs -> case Map.lookup bs witnessesOf of
          Just argss -> Bucket bs <$> witnessed argss False
          Nothing -> viaSolver params exprs space bs

  -- The decision's answer at each witness.
  witnessed argss fromSolver = do
    rows <- for argss \args -> do
      r <- evalExpr (App emptyAnno t.ctName args)
      pure case r >>= ce.ceAnswer of
        Just a -> Right Row
          { rowArgs = args
          , rowArgsText = map (oneLine . prettyLayout . exactValue) args
          , rowAnswer = a, rowFromSolver = fromSolver }
        Nothing -> Left "L4 produced no Catala-renderable value at a witness"
    pure case [ why | Left why <- rows ] of
      (why : _) -> Undecided why
      [] -> Witnessed [ r | Right r <- rows ]

  -- A bucket no candidate realises: the solver says it is impossible, or gives
  -- a witness the evaluator must confirm.
  viaSolver params exprs space bs = Bucket bs <$> case ce.ceSolver of
    Nothing -> pure (Undecided "no candidate realises every combination, and no SMT solver was found to decide the rest")
    Just solver -> do
      out <- solver.solverRun ce.ceSolverSecs (space.asScript bs)
      case out of
        Left why -> pure (Undecided ("the solver could not decide a combination: " <> why))
        Right txt -> case parseSExprs txt of
          Right (answer : rest) -> case readCheckSat answer of
            Just CsUnsat -> pure Impossible
            Just CsSat | (SList pairs : _) <- rest -> do
              let values = Map.fromList [ (Text.dropAround (== '|') s, v) | SList [Atom s, v] <- pairs ]
                  lifted = for space.asSpace.obFree \fv ->
                    maybe (Left ("no value for " <> fv.fvName)) (liftModelValue space.asSpace fv.fvSort)
                          (Map.lookup (Text.dropAround (== '|') fv.fvSymbol) values)
              case lifted of
                Left why -> pure (Undecided why)
                Right args -> do
                  [v] <- atomVectors params exprs [args]
                  if v == Just bs
                    then witnessed [args] True
                    else pure (Undecided "the solver's witness for a combination does not realise it in L4 (an encoding defect)")
            _ -> pure (Undecided ("the solver said unknown for a combination" <> maybe "" ("; likely cause: " <>) space.asSpace.obNonLinear))
          _ -> pure (Undecided "unreadable solver output")

  -- Each candidate's values for the conditions, by the evaluator: 'Nothing'
  -- when one raises (or does not reduce to a Boolean) there. Evaluated in
  -- batches, one module evaluation per batch, and one by one only when a batch
  -- raises.
  atomVectors params atoms cands = concat <$> for (chunksOf 128 cands) \batch -> do
    r <- evalExpr (List emptyAnno [ bindAt params c (List emptyAnno atoms) | c <- batch ])
    case r >>= listOf of
      Just rows | length rows == length batch -> pure (map boolsOf rows)
      _ -> for batch \c -> do
        r1 <- evalExpr (bindAt params c (List emptyAnno atoms))
        pure (r1 >>= boolsOf)

  -- The parameters bound to a candidate's values, around an expression, at
  -- the parameters' own addresses.
  bindAt params vals body =
    LetIn emptyAnno
      [ LocalDecide emptyAnno
          (MkDecide emptyAnno (MkTypeSig emptyAnno (MkGivenSig emptyAnno []) Nothing)
                    (MkAppForm emptyAnno r [] Nothing) v)
      | ((rs, _), v) <- zip params vals, r <- rs ]
      body

  evalExpr e = do
    res <- execEvalExprInContextOfModule ce.ceEval tc.entityInfo e (ce.ceImportEnv, tc.module')
    pure case res of
      Just d | Reduction (Reduced nf) <- d.result -> Just nf
      _ -> Nothing

  listOf = \case
    MkNF v -> spine v
    Omitted -> Nothing
  spine = \case
    ValNil -> Just []
    ValCons hd (MkNF tl) -> (hd :) <$> spine tl
    _ -> Nothing
  boolsOf nf = listOf nf >>= traverse \case
    MkNF (ValBool b) -> Just b
    _ -> Nothing

chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf k xs = let (a, b) = splitAt k xs in a : chunksOf k b

oneLine :: Text -> Text
oneLine = Text.unwords . Text.words

tshow :: Show a => a -> Text
tshow = Text.pack . show
