{-# LANGUAGE OverloadedStrings #-}

-- | The state graph draws the path the evaluator takes when a permission
-- lapses.
--
-- A MAY not used by its deadline goes to its LEST, by default FULFILLED (the
-- Contract5 expiry in 'L4.EvaluateLazy.Machine'). The graph used to draw no
-- timeout edge for a MAY without LEST, so that path was missing from it.
module StateGraphLapseSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as Text
import Test.Hspec

import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import qualified L4.StateGraph as SG

-- | The one state graph of a module whose one rule, @r@, is the given body.
graphOf :: [Text] -> IO SG.StateGraph
graphOf body = case checkWithImports emptyVFS src of
  Left errs -> fail ("the module did not check:\n" <> Text.unpack (Text.unlines errs))
  Right r -> case SG.extractStateGraphs r.tcdModule of
    [g] -> pure g
    gs -> fail ("expected one state graph, got " <> show (length gs))
 where
  src = Text.unlines $
    [ "DECLARE Person IS ONE OF Seller, Buyer"
    , "DECLARE Action IS ONE OF pay, deliver"
    , ""
    , "GIVETH DEONTIC Person Action"
    , "r MEANS"
    ]
    <> map ("  " <>) body

-- | Each timeout edge, as the type of the state it ends in.
timeouts :: SG.StateGraph -> [SG.StateType]
timeouts g =
  [ s.stateType
  | t <- g.sgTransitions
  , t.transType == SG.LestTransition
  , t.transLabel.labelAction == "timeout"
  , s <- g.sgStates
  , s.stateId == t.transTo
  ]

spec :: Spec
spec = describe "the state graph of a permission" $ do
  it "draws a MAY without LEST lapsing to FULFILLED at its deadline" $ do
    g <- graphOf ["PARTY Buyer", "MAY pay", "WITHIN 10"]
    timeouts g `shouldBe` [SG.TerminalFulfilled]

  it "still takes HENCE only for the permission used" $ do
    g <- graphOf ["PARTY Buyer", "MAY pay", "WITHIN 10", "HENCE (PARTY Seller MUST deliver WITHIN 5)"]
    timeouts g `shouldMatchList` [SG.TerminalFulfilled, SG.TerminalBreach]

  it "draws a MAY's LEST where it has one" $ do
    g <- graphOf ["PARTY Buyer", "MAY pay", "WITHIN 10", "LEST BREACH"]
    timeouts g `shouldBe` [SG.TerminalBreach]

  it "draws no lapse for a MAY with no WITHIN, which never lapses" $ do
    g <- graphOf ["PARTY Buyer", "MAY pay"]
    timeouts g `shouldBe` []
