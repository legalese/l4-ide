-- | §8.4's witness gate for @l4 export catala@ (CATALA-EXPORT-SPEC §8.4;
-- VERIFICATION-BACKEND-LOWERING-SPEC R-V10).
--
-- For each exported decision whose body the Catala lowering turns into an
-- exception ladder, find concrete inputs for each combination of truth values
-- of the ladder's conditions, so that the emitted test scopes can call the real
-- emitted scope there and compare it with L4.
--
-- The search itself is not Catala's: it is "L4.Cli.Coverage", which also backs
-- a coverage report. What is Catala's is here: which decisions are ladders
-- ('ladderTargets'), how an answer is written for @catala interpret@, and that
-- a gate is handed to the lowering only when every combination is either
-- witnessed or proved impossible. Otherwise the decision keeps the exhaustive
-- grid, and the reason goes to stderr.
module L4.Cli.CatalaWitness
  ( witnessGates
  ) where

import Base
import qualified Data.Map.Strict as Map

import L4.Catala.Lower (LadderTarget (..), WitnessGate (..), WitnessRow (..), ladderTargets)
import L4.Evaluate.ValueLazy (Environment, NF (..))
import L4.EvaluateLazy (EvalConfig)
import L4.Syntax
import qualified LSP.L4.Rules as Rules

import L4.Cli.Coverage
import L4.Cli.Prove (Solver (..))

-- | The gates, keyed by decision, and a note per decision that has a ladder
-- but no gate.
witnessGates
  :: EvalConfig -> Rules.TypeCheckResult -> Environment -> Maybe Solver -> Int
  -> (NF -> Maybe Text) -> (NF -> Text)
  -> IO (Map Unique WitnessGate, [Text])
witnessGates evalConfig tc importEnv msolver secs jsonOf humanOf = do
  results <- for targets \lt -> do
    r <- coverTarget ce (coverTargetOf lt)
    pure (lt, r >>= gateOf)
  pure ( Map.fromList [ (lt.ltDecide, g) | (lt, Right g) <- results ]
       , [ "no witness gate for `" <> nameOf' lt.ltName <> "` (" <> why <> "); " <> fallback lt
         | (lt, Left why) <- results ] )
 where
  mods    = tc.module' : map (.module') (Rules.transitiveDependencies tc)
  targets = ladderTargets (drop 1 mods) tc.module'
  nameOf' = nameToText . getOriginal

  ce = CoverEnv
    { ceEval = evalConfig, ceTc = tc, ceImportEnv = importEnv
    , ceSolver = msolver, ceSolverSecs = secs
    , ceAnswer = \nf -> fmap (\j -> (j, humanOf nf)) (jsonOf nf)
    -- the lowering needs every combination decided; a leaf cross that leaves
    -- one undecided gives way to the rungs, which may not
    , ceFallbackOnUndecided = True
    }
  coverTargetOf lt = CoverTarget
    { ctName = lt.ltName, ctDecide = lt.ltDecl, ctParams = lt.ltParams
    , ctAppArgs = lt.ltAppArgs, ctRungs = lt.ltAtoms, ctReadsAssumes = lt.ltReadsAssumes }

  -- what the lowering does without a gate: the grid while it can, else Mode A
  fallback lt
    | length lt.ltAtoms <= 8 = "its ladder keeps the exhaustive grid"
    | otherwise = "past the grid's cap of 8 it is emitted in the boolean rendering (Mode A)"

  -- a gate is used only when every combination is witnessed or proved impossible
  gateOf c = case [ why | Bucket _ (Undecided why) <- c.cvBuckets ] of
    (why : _) -> Left why
    [] -> Right WitnessGate
      { wgRows =
          [ WitnessRow
              { wrAssignment = b.bkAssignment, wrArgs = r.rowArgs, wrArgsText = r.rowArgsText
              , wrExpected = fst r.rowAnswer, wrHuman = snd r.rowAnswer, wrFromSolver = r.rowFromSolver }
          | b <- c.cvBuckets, Witnessed rows <- [b.bkStatus], r <- rows ]
      , wgImpossible = [ b.bkAssignment | b <- c.cvBuckets, Impossible <- [b.bkStatus] ]
      , wgAtomText = map (.cpText) c.cvPoints
      , wgRungNote = case c.cvLevel of
          RungLevel why -> Just why
          LeafLevel -> Nothing
      }
