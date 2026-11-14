{-# LANGUAGE OverloadedStrings #-}

-- | How a #TRACE scales when an event is many windows late.
--
-- A rule after LEST counts from the deadline that was missed, so an event many
-- windows late is handed down one layer per window it is past
-- ('L4.EvaluateLazy.Machine', the Contract5 expiry NOTE). Two things made that
-- walk expensive; this pins the first with a time limit.
--
-- A rule that names itself on both sides of a RAND or ROR, @x RAND x@, doubled
-- at every layer: 2^30 copies of x at the last layer of the first case below,
-- where @main@, which started the LEST at the late event, answered in 0.02 s.
-- Both operands read the same events from the same moment, so the machine now
-- evaluates such an operand once ('L4.EvaluateLazy.Machine.sameRule').
module LateEventScaleSpec (spec) where

import Control.DeepSeq (force)
import Control.Exception (evaluate)
import Data.Text (Text)
import qualified Data.Text as Text
import System.Timeout (timeout)
import Test.Hspec

import L4.API (l4Eval)

-- | Seconds each case may take. Each runs in well under one with the fix.
budgetSeconds :: Int
budgetSeconds = 20

-- | A module with one rule @x@ and one #TRACE of it.
traced :: Text -> [Text] -> Text
traced rule events = Text.unlines $
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF tick"
  , ""
  , "GIVETH A DEONTIC Person Action"
  , "`x` MEANS"
  , "  " <> rule
  , ""
  , "#TRACE `x` AT 0 WITH"
  ] <> map ("  " <>) events

tick :: Text -> Text
tick at = "PARTY Alice DOES tick AT " <> at

-- | Evaluate within the budget, failing the test if it runs past it.
evalWithin :: Text -> IO Text
evalWithin src = do
  r <- timeout (budgetSeconds * 1000000) (l4Eval src >>= evaluate . force)
  case r of
    Nothing -> expectationFailure ("did not finish in " <> show budgetSeconds <> " s") >> pure ""
    Just out -> pure out

spec :: Spec
spec = describe "a #TRACE whose event is many windows late" $ do
  it "walks x RAND x under HENCE and LEST once per window, not twice" $ do
    out <- evalWithin $ traced "PARTY Alice MUST tick WITHIN 1 HENCE (`x` RAND `x`) LEST (`x` RAND `x`)"
      [tick "0", tick "30"]
    out `shouldSatisfy` Text.isInfixOf "\"success\":true"
    -- one obligation is left, due at 31: the copies of x are one rule
    Text.count "MUST tick" out `shouldBe` 1

  it "walks x RAND x under HENCE with LEST x across 14 events" $ do
    out <- evalWithin $ traced "PARTY Alice MUST tick WITHIN 1 HENCE (`x` RAND `x`) LEST `x`"
      [tick (Text.pack (show (10 * i :: Int))) | i <- [0 .. 13]]
    out `shouldSatisfy` Text.isInfixOf "\"success\":true"
    Text.count "MUST tick" out `shouldBe` 1

  it "walks x ROR x under a MAY's HENCE and LEST" $ do
    out <- evalWithin $ traced "PARTY Alice MAY tick WITHIN 1 HENCE (`x` ROR `x`) LEST (`x` ROR `x`)"
      [tick "0", tick "10", tick "20", tick "30"]
    out `shouldSatisfy` Text.isInfixOf "\"success\":true"
    Text.count "MAY tick" out `shouldBe` 1

