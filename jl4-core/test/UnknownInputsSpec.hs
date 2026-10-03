{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | What evaluation answers with an input nobody supplied, case by case
-- (UNKNOWN-EVALUATION-SPEC §8 step 3). The corpus file
-- @jl4/examples/ok/unknown-inputs-lifted.l4@ pins the rows through its
-- goldens; this module pins, one directive at a time, the cases where the
-- answer must stay what it was before the step because some supplied value
-- would make it an error, and the cases that must still be decided.
module UnknownInputsSpec (spec) where

import Data.Foldable (toList)
import qualified Data.Text as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Evaluate.ValueLazy (Term (..))
import L4.EvaluateLazy
  ( AssertionOutcome (..)
  , EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , ReductionOutcome (..)
  , execEvalModuleWithEnv
  , resolveEvalConfig
  )
import L4.EvaluateLazy.Exceptions (prettyEvalException)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Print (prettyLayout)
import L4.TracePolicy (apiDefaultPolicy)

-- | A directive's outcome, as much of it as these tests compare.
data Outcome
  = Value Text.Text
  | Satisfied
  | Failed
  | Waits [Text.Text]
    -- ^ undetermined, waiting on these inputs, as its message names them
  | Errors Text.Text
  | Refuses
  deriving stock (Eq, Show)

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2025 1 1) (secondsToDiffTime 0)

-- | The outcome of each directive in a source, in order.
outcomes :: Text.Text -> IO [Outcome]
outcomes src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure (map (classify . (.result)) results)

classify :: EvalDirectiveValue -> Outcome
classify = \ case
  Assertion Holds              -> Satisfied
  Assertion Fails              -> Failed
  Assertion (FailsBecause _)   -> Failed
  Assertion (Refused _)        -> Refuses
  Assertion (Errored e)        -> Errors (Text.unlines (prettyEvalException e))
  Assertion (Undetermined ns)  -> Waits (map name (toList ns))
  Reduction (Reduced v)        -> Value (prettyLayout v)
  Reduction (ReducedRefused _) -> Refuses
  Reduction (ReducedErrored e) -> Errors (Text.unlines (prettyEvalException e))
  Reduction (ReducedUndetermined ns) -> Waits (map name (toList ns))
  where
    name = \ case
      TInput r _ -> prettyLayout r
      t          -> prettyLayout t

spec :: Spec
spec = describe "unknown inputs (UNKNOWN-EVALUATION-SPEC §8 step 3)" $ do

  -- A field of an unknown is a field path only when every value of the type
  -- has the field. Every Square makes each of these three an error, so none
  -- may be decided; step 3 first answered all three "satisfied".
  describe "a field of an unknown of a type with several constructors" $ do
    let shapes = Text.unlines
          [ "DECLARE Shape IS ONE OF"
          , "  Circle HAS radius IS A NUMBER"
          , "  Square HAS side IS A NUMBER"
          , "DECLARE Person HAS age IS A NUMBER"
          , "§ `Unknown`"
          , "    GIVEN s IS A Shape"
          , "          d IS A Person"
          ]
    it "stays Stuck on the unknown, as it was before the step" $ do
      os <- outcomes $ shapes <> Text.unlines
        [ "#ASSERT s's radius EQUALS s's radius"
        , "#ASSERT NOT ((s's radius GREATER THAN 0) AND FALSE)"
        , "#ASSERT (s's radius GREATER THAN 0) OR TRUE"
        ]
      os `shouldBe` replicate 3 (Waits ["s"])
    it "is a field path for a type with one constructor, which those decide" $ do
      os <- outcomes $ shapes <> Text.unlines
        [ "#ASSERT d's age EQUALS d's age"
        , "#ASSERT NOT ((d's age GREATER THAN 0) AND FALSE)"
        , "#ASSERT (d's age GREATER THAN 0) OR TRUE"
        , "#EVAL d's age GREATER THAN 0"
        ]
      os `shouldBe` [Satisfied, Satisfied, Satisfied, Waits ["d's age"]]
