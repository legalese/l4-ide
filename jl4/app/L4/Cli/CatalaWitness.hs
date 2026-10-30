{-# LANGUAGE PatternSynonyms #-}
-- | §8.4's witness gate for @l4 export catala@ (CATALA-EXPORT-SPEC §8.4;
-- VERIFICATION-BACKEND-LOWERING-SPEC R-V10).
--
-- For each exported decision whose body the Catala lowering turns into an
-- exception ladder, find one concrete input per combination of truth values of
-- the ladder's atomic conditions, so that the emitted test scopes can call the
-- real emitted scope there and compare it with L4.
--
-- Two oracles, with fixed jobs, and neither is a second semantics of the rule:
--
-- * the jl4 evaluator decides which combination a candidate input realises,
--   and what the decision's answer is at a witness;
-- * the solver only proves a combination impossible, and finds a witness when
--   no candidate realises one (that witness is replayed through the evaluator
--   before it is used, and the emitted prose says where it came from).
--
-- Candidates come from a fixed set ('sampleValues': each literal the atoms
-- reach, one either side of it, zero; both Booleans; every constructor), so the
-- witnesses, and hence the emitted text, do not depend on which solver, or
-- which version of it, is installed. A gate is handed to the lowering only when
-- every combination is either witnessed or proved impossible; otherwise the
-- decision keeps the exhaustive grid, and the reason goes to stderr.
module L4.Cli.CatalaWitness
  ( witnessGates
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map

import L4.Annotation (emptyAnno)
import L4.Catala.Lower (LadderTarget (..), WitnessGate (..), WitnessRow (..), ladderTargets)
import L4.Evaluate.ValueLazy (Environment, NF (..), Value (..))
import L4.EvaluateLazy (EvalConfig, EvalDirectiveResult (..), EvalDirectiveValue (..), ReductionOutcome (..), execEvalExprInContextOfModule)
import L4.EvaluateLazy.Machine (pattern ValBool)
import L4.Print (prettyLayout)
import L4.Prove.Lower
import L4.Prove.Smt
import L4.Syntax
import qualified LSP.L4.Rules as Rules

import L4.Cli.Prove (Solver (..), samplePointsUpTo)

-- | More atoms than this is 2^n combinations too many to emit a test scope
-- for each realisable one of; such a decision keeps today's behaviour.
-- (Assumed, not ruled.)
atomLimit :: Int
atomLimit = 12

-- | At most this many candidate inputs per decision are evaluated.
candidateLimit :: Integer
candidateLimit = 4096

-- | The gates, keyed by decision, and a note per decision that has a ladder
-- but no gate.
witnessGates
  :: EvalConfig -> Rules.TypeCheckResult -> Environment -> Maybe Solver -> Int
  -> (NF -> Maybe Text) -> (NF -> Text)
  -> IO (Map Unique WitnessGate, [Text])
witnessGates evalConfig tc importEnv msolver secs jsonOf humanOf = do
  results <- for targets \lt -> do
    r <- gateFor lt
    pure (lt, r)
  pure ( Map.fromList [ (lt.ltDecide, g) | (lt, Right g) <- results ]
       , [ "no witness gate for `" <> nameOf' lt.ltName <> "` (" <> why <> "); its ladder keeps the exhaustive grid"
         | (lt, Left why) <- results ] )
 where
  mods    = tc.module' : map (.module') (Rules.transitiveDependencies tc)
  env     = mkProveEnv mods (tc.entityInfo <> foldMap (.entityInfo) (Rules.transitiveDependencies tc))
  targets = ladderTargets (drop 1 mods) tc.module'
  nameOf' = nameToText . getOriginal

  gateFor lt
    | lt.ltReadsAssumes = pure (Left "it reads an ASSUME, which a witness input cannot supply")
    | length lt.ltAtoms > atomLimit =
        pure (Left (tshow (length lt.ltAtoms) <> " atomic conditions, past the witness gate's limit of " <> tshow atomLimit))
    | otherwise = case traverse paramOf (zip lt.ltParams (map Just lt.ltAppArgs <> repeat Nothing)) of
        Nothing -> pure (Left "a parameter has no declared type")
        Just params -> case lowerAtoms env params lt.ltAtoms of
          Left why -> pure (Left why)
          Right space -> search lt params space

  paramOf ((given, mty), mapp) = do
    ty <- mty
    let extra = [ a | Just a <- [mapp], getUnique a /= getUnique given ]
    pure (given : extra, ty)

  search lt params space = do
    let free = space.asSpace.obFree
        cands = samplePointsUpTo candidateLimit [ (fv, sampleValues space.asSpace fv.fvSort) | fv <- free ]
        n = length lt.ltAtoms
    vectors <- atomVectors params lt.ltAtoms (map (map snd) cands)
    let firstWitness = Map.fromListWith (\_ old -> old)
          [ (bs, map snd c) | (c, Just bs) <- zip cands vectors ]
        combos = [ [ odd (k `div` (2 ^ i)) | i <- [0 .. n - 1] ] | k <- [0 .. (2 ^ n :: Integer) - 1] ]
    decided <- for combos \bs -> case Map.lookup bs firstWitness of
      Just args -> pure (Right (Left (bs, args, False)))
      Nothing -> viaSolver params lt space bs
    case [ why | Left why <- decided ] of
      (why : _) -> pure (Left why)
      [] -> do
        rows <- for [ w | Right (Left w) <- decided ] \(bs, args, fromSolver) -> do
          r <- evalExpr (App emptyAnno lt.ltName args)
          pure case r of
            Just nf | Just j <- jsonOf nf ->
              Right WitnessRow
                { wrAssignment = bs, wrArgs = args
                , wrArgsText = map (oneLine . prettyLayout) args
                , wrExpected = j, wrHuman = humanOf nf, wrFromSolver = fromSolver }
            _ -> Left "L4 produced no Catala-renderable value at a witness"
        pure case [ why | Left why <- rows ] of
          (why : _) -> Left why
          [] -> Right WitnessGate
            { wgRows = [ r | Right r <- rows ]
            , wgImpossible = [ bs | Right (Right bs) <- decided ]
            , wgAtomText = map (oneLine . prettyLayout) lt.ltAtoms
            }

  -- A combination no candidate realises: the solver says it is impossible, or
  -- gives a witness the evaluator must confirm. 'Left' names why it is neither.
  viaSolver params lt space bs = case msolver of
    Nothing -> pure (Left "no candidate realises every combination, and no SMT solver was found to decide the rest")
    Just solver -> do
      out <- solver.solverRun secs (space.asScript bs)
      case out of
        Left why -> pure (Left ("the solver could not decide a combination: " <> why))
        Right txt -> case parseSExprs txt of
          Right (answer : rest) -> case readCheckSat answer of
            Just CsUnsat -> pure (Right (Right bs))
            Just CsSat | (SList pairs : _) <- rest -> do
              let values = Map.fromList [ (Text.dropAround (== '|') s, v) | SList [Atom s, v] <- pairs ]
                  lifted = for space.asSpace.obFree \fv ->
                    maybe (Left ("no value for " <> fv.fvName)) (liftModelValue space.asSpace fv.fvSort)
                          (Map.lookup (Text.dropAround (== '|') fv.fvSymbol) values)
              case lifted of
                Left why -> pure (Left why)
                Right args -> do
                  [v] <- atomVectors params lt.ltAtoms [args]
                  pure if v == Just bs
                    then Right (Left (bs, args, True))
                    else Left "the solver's witness for a combination does not realise it in L4 (an encoding defect)"
            _ -> pure (Left ("the solver said unknown for a combination" <> maybe "" ("; likely cause: " <>) space.asSpace.obNonLinear))
          _ -> pure (Left "unreadable solver output")

  -- Each candidate's atom values, by the evaluator: 'Nothing' when an atom
  -- raises (or does not reduce to a Boolean) there. Evaluated in batches, one
  -- module evaluation per batch, and one by one only when a batch raises.
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
    res <- execEvalExprInContextOfModule evalConfig tc.entityInfo e (importEnv, tc.module')
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
