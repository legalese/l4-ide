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
-- Candidates come from a fixed set ('sampleValues': each number literal
-- reached in lowering the cover points, the bodies of the rules they call
-- included, one either side of it, and zero; both Booleans; every
-- constructor, over its fields' samples, two levels deep), combined by
-- 'samplePointsUpTo', every combination up to 'candidateLimit' and a spread
-- past it. A witness found among them does not depend on which solver, or
-- which version of it, is installed; a bucket that no candidate realises
-- takes the solver's model as its witness ('viaSolver'), and that one does.
-- When some parameter's type has no sample within two levels (a record
-- nested three deep), the candidate set is empty, for every parameter, and
-- every witness is the solver's. (Corrected 2026-11-25; this said before
-- that the witnesses never depend on the solver.)
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
import L4.EvaluateLazy.Exceptions (LimitStopped (..), Refusal (..), isLimitStop, prettyEvalException)
import Control.Exception (handle, throwIO)
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
-- there too it is not covered at all. (Ruled, CATALA-EXPORT-SPEC §8.4.)
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
  , ceAnswer :: NF -> Either Text ans
    -- ^ how the caller renders the decision's answer at a witness; 'Left'
    -- says why it cannot, which is the reason the bucket is left undecided.
    -- An answer L4 could not compute (it raised an error) never gets here:
    -- the reason for that names L4's error, and is the same for every caller.
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
-- An evaluation stopped at a limit (ruled by Meng 2026-11-21, extending L2) is one such reason:
-- read as "raises", it would drop that input or blame a condition for it.
coverTarget :: CoverEnv ans -> CoverTarget -> IO (Either Text (Cover ans))
coverTarget ce t =
  handle (\ (LimitStopped why) -> pure (Left ("the evaluator stopped at a limit at an input it tried: " <> why)))
    (coverTargetWith ce t)

coverTargetWith :: forall ans. CoverEnv ans -> CoverTarget -> IO (Either Text (Cover ans))
coverTargetWith ce t
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

  -- The decision's answer at each witness. A witness where L4 gives no answer
  -- leaves the bucket undecided, and the reason says what L4 did there and
  -- at which input (smucclaw/l4-ide#1096).
  witnessed argss fromSolver = do
    rows <- for argss \args -> do
      r <- evalExpr (App emptyAnno t.ctName args)
      let argsText = map (oneLine . prettyLayout . exactValue) args
          at = maybe "" (" at " <>) (inputsText args)
      pure case r of
        Value nf -> case ce.ceAnswer nf of
          Right a -> Right Row
            { rowArgs = args, rowArgsText = argsText
            , rowAnswer = a, rowFromSolver = fromSolver }
          Left why -> Left why
        Raised err -> Left ("L4 raises an error" <> at <> ": \"" <> err <> "\"")
        NoValue why -> Left ("L4 gives no answer" <> at <> ": " <> why)
    pure case [ why | Left why <- rows ] of
      (why : _) -> Undecided why
      [] -> Witnessed [ r | Right r <- rows ]

  paramNames = [ nameToText (getOriginal r) | (r, _) <- t.ctParams ]

  -- The inputs of a witness, named, for a reason; 'Nothing' when the
  -- decision has none. A constructor value with more than one argument is
  -- put in parentheses, so that its fields do not read as more inputs.
  inputsText args
    | null args = Nothing
    | otherwise = Just (Text.intercalate ", " [ n <> " = " <> valueText v | (n, v) <- zip paramNames args ])
  valueText v = case exactValue v of
    e@(App _ _ (_ : _ : _)) -> "(" <> oneLine (prettyLayout e) <> ")"
    e -> oneLine (prettyLayout e)

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
  -- A batch is one evaluation, so its count is shared by every input in it:
  -- a batch stopped at a limit says nothing about any one of them, and each
  -- is tried on its own instead.
  atomVectors params atoms cands = concat <$> for (chunksOf 128 cands) \batch -> do
    r <- handle (\ (LimitStopped _) -> pure Nothing)
           (valueOf <$> evalExpr (List emptyAnno [ bindAt params c (List emptyAnno atoms) | c <- batch ]))
    case r >>= listOf of
      Just rows | length rows == length batch -> pure (map boolsOf rows)
      _ -> for batch \c -> do
        r1 <- evalExpr (bindAt params c (List emptyAnno atoms))
        pure (valueOf r1 >>= boolsOf)

  -- The parameters bound to a candidate's values, around an expression, at
  -- the parameters' own addresses.
  bindAt params vals body =
    LetIn emptyAnno
      [ LocalDecide emptyAnno
          (MkDecide emptyAnno (MkTypeSig emptyAnno (MkGivenSig emptyAnno []) Nothing)
                    (MkAppForm emptyAnno r [] Nothing) v)
      | ((rs, _), v) <- zip params vals, r <- rs ]
      body

  -- A stop at a limit is thrown, not returned: it is not "raises" (see
  -- 'coverTarget'), and it is checked before any other error.
  evalExpr e = do
    res <- execEvalExprInContextOfModule ce.ceEval tc.entityInfo e (ce.ceImportEnv, tc.module')
    case fmap (.result) res of
      Just (Reduction (Reduced nf)) -> pure (Value nf)
      Just (Reduction (ReducedErrored exc))
        | isLimitStop exc -> throwIO (LimitStopped (Text.unwords (prettyEvalException exc)))
        | otherwise -> pure (Raised (oneLine (Text.unwords (prettyEvalException exc))))
      Just (Reduction (ReducedRefused r)) -> pure (NoValue ("it refuses to answer: \"" <> oneLine r.message <> "\""))
      -- Neither of the last two is reached as the report stands, and no
      -- fixture can reach them: a decision that reads an ASSUME is not
      -- covered at all, and every input of a witness is given a value, so no
      -- answer waits on one; and the evaluator returns one result for the one
      -- directive it is given ('execEvalExprInContextOfModule'). They are
      -- named so that a change elsewhere shows up as a reason, not a silence.
      Just (Reduction (ReducedUndetermined _)) -> pure (NoValue "its answer waits on a value it was not given")
      _ -> pure (NoValue "the evaluator returned nothing")

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

-- | What the evaluator made of an expression: its value, the error it raised,
-- or why it gave neither.
data Evaluated
  = Value NF
  | Raised Text
  | NoValue Text

valueOf :: Evaluated -> Maybe NF
valueOf = \case
  Value nf -> Just nf
  _ -> Nothing

chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf k xs = let (a, b) = splitAt k xs in a : chunksOf k b

oneLine :: Text -> Text
oneLine = Text.unwords . Text.words

tshow :: Show a => a -> Text
tshow = Text.pack . show
