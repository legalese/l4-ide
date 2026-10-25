{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | @l4 explore@'s own mechanisms (REGULATIVE-LOWERING-SPEC.md §4, WP1), each
-- on a contract cut down to show it alone. The dinner-race fixtures and
-- their counts are pinned in @jl4/tests/LtsExplore.hs@; these are the
-- decisions those fixtures do not isolate:
--
--   1. a variable that is the whole action is enumerated from the
--      contract's action type, a constructor with a @NUMBER@ field is
--      refused BY NAME while its siblings are explored, and an act that
--      changes nothing is a self-loop;
--   2. the tick past a deadline reaches @FULFILLED@, a state with nothing
--      left to do gets one @terminal@ self-loop, and the clock bound turns
--      the tick into a count instead of an edge;
--   3. a variable that is an operand is enumerated from its constructor's
--      field type, through a record, and a constructor refused INSIDE a
--      field is named as itself, not as the record it sits in;
--   4. a cell read only by @RECALL@ keeps its latest entry, one read by
--      @RECALL ALL@ its whole history (which here never closes, so the depth
--      bound stops it, and says so); a cell nothing reads is dropped and
--      named; a cell kept by request ('keepCells') splits states it did not.
module LtsExploreSpec (spec) where

import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Lts.Explore
import L4.Lts.WhatIf (Rig (..))
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | Explore the named rule from 0, with these options and kept cells.
exploreSrc :: Text.Text -> Text.Text -> ExploreOptions -> [(Text.Text, Bool)] -> IO Graph
exploreSrc src name opts keep = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  r <- case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r -> pure r
  let rig = MkRig {rigConfig = cfg, rigEntityInfo = r.tcdEntityInfo, rigEnv = emptyEnvironment, rigModule = r.tcdModule}
      sites = keepCells keep (readSitesOf r.tcdModule [])
  start <- either (fail . Text.unpack) pure (startNamed r.tcdModule name 0)
  explore opts sites rig start >>= either (fail . Text.unpack) pure

counts :: Graph -> (Int, Int)
counts g = (g.gCoverage.cvStates, g.gCoverage.cvTransitions)

labels :: Graph -> [(Int, Text.Text, Int)]
labels g = [ (t.tnFrom, t.tnLabel, t.tnTo) | t <- g.gTransitions ]

-- 1. and 2.
machineSrc :: Text.Text
machineSrc = Text.unlines
  [ "DECLARE Who IS ONE OF W"
  , "DECLARE Move IS ONE OF"
  , "    tap HAS hard IS A BOOLEAN"
  , "    pay HAS amount IS A NUMBER"
  , "    stop"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`machine` MEANS"
  , "    PARTY W"
  , "    MAY   act"
  , "    WITHIN 10"
  , "    HENCE CONSIDER act"
  , "          WHEN tap h THEN `machine`"
  , "          WHEN pay n THEN `machine`"
  , "          WHEN stop  THEN FULFILLED"
  ]

-- 3.
ordersSrc :: Text.Text
ordersSrc = Text.unlines
  [ "DECLARE Who IS ONE OF W"
  , "DECLARE Size IS ONE OF small, large, custom HAS width IS A NUMBER"
  , "DECLARE Order HAS size IS A Size, rush IS A BOOLEAN"
  , "DECLARE Move IS ONE OF"
  , "    place HAS order IS AN Order"
  , "    quote HAS price IS A NUMBER"
  , "    cancel"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`a placing` MEANS PARTY W MAY place o WITHIN 10 HENCE FULFILLED"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`a quote` MEANS PARTY W MAY quote p WITHIN 10 HENCE FULFILLED"
  ]

-- 4. The guard reads `light` by RECALL (or RECALL ALL); `log` is only
--    ever written.
switchSrc :: Text.Text -> Text.Text -> Text.Text
switchSrc recall inputType = Text.unlines
  [ "DECLARE Who IS ONE OF W"
  , "DECLARE Move IS ONE OF flip, flop"
  , ""
  , "GIVEN light IS " <> inputType
  , "GIVETH A BOOLEAN"
  , "`ready` MEANS TRUE"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`switch` MEANS"
  , "    PARTY W"
  , "    MAY   act PROVIDED `ready` (" <> recall <> " W's `light`)"
  , "    WITHIN 0 OF 10"
  , "    HENCE CONSIDER act"
  , "          WHEN flip THEN RECORD `light` IS TRUE  HENCE RECORD `log` IS 1 HENCE `switch`"
  , "          WHEN flop THEN RECORD `light` IS FALSE HENCE `switch`"
  ]

spec :: Spec
spec = describe "l4 explore" do
  describe "1. a whole-action variable is enumerated; a NUMBER constructor is refused by name" do
    it "explores tap TRUE, tap FALSE and stop, refuses pay naming its field, and is not complete" do
      g <- exploreSrc machineSrc "machine" defaultExploreOptions []
      counts g `shouldBe` (2, 5)
      labels g `shouldBe`
        [ (0, "PARTY W DOES tap OF TRUE", 0)
        , (0, "PARTY W DOES tap OF FALSE", 0)
        , (0, "PARTY W DOES stop", 1)
        , (0, "time passes the deadline 10 (WAIT UNTIL 11)", 1)
        , (1, "terminal", 1)
        ]
      case g.gCoverage.cvRefused of
        [r] -> do
          (r.rfVariable, r.rfType, r.rfWhole, r.rfConstructor) `shouldBe` ("act", "Move", True, Just "pay")
          r.rfReason `shouldBe` "its field `amount` is a NUMBER, and a NUMBER has no finite set of values"
        other -> expectationFailure ("expected one refusal, got " <> show other)
      coverageComplete g.gCoverage `shouldBe` False
      coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "REFUSED 1: `act` of type Move, constructor `pay`"

  describe "2. ticks, terminal states and the clock bound" do
    it "the FULFILLED state is terminal, with one self-loop, and is marked so" do
      g <- exploreSrc machineSrc "machine" defaultExploreOptions []
      [ s.snId | s <- g.gStates, s.snTerminal ] `shouldBe` [1]
      [ t | t <- g.gTransitions, t.tnKind == EdgeTerminal ] `shouldBe` [MkTransition 1 "terminal" 1 EdgeTerminal]
    it "--until 10 does not take the tick to 11, counts it, and still ends at FULFILLED by stop" do
      g <- exploreSrc machineSrc "machine" defaultExploreOptions {eoUntil = Just 10} []
      counts g `shouldBe` (2, 4)
      g.gCoverage.cvBeyondClock `shouldBe` 1
      [ t | t <- g.gTransitions, t.tnKind == EdgeTick ] `shouldBe` []

  describe "3. an operand variable is enumerated from its field type" do
    it "lists the four Orders whose size is not custom, and names custom as the constructor refused" do
      g <- exploreSrc ordersSrc "a placing" defaultExploreOptions []
      counts g `shouldBe` (2, 6)
      [ l | (_, l, _) <- labels g, "place" `Text.isInfixOf` l ] `shouldBe`
        [ "PARTY W DOES place OF (Order OF small, TRUE)"
        , "PARTY W DOES place OF (Order OF small, FALSE)"
        , "PARTY W DOES place OF (Order OF large, TRUE)"
        , "PARTY W DOES place OF (Order OF large, FALSE)"
        ]
      case g.gCoverage.cvRefused of
        [r] -> do
          (r.rfVariable, r.rfType, r.rfWhole, r.rfConstructor) `shouldBe` ("o", "Order", False, Just "custom")
          r.rfReason `shouldBe` "it sits in `size` of `Order`, and its field `width` is a NUMBER, and a NUMBER has no finite set of values"
        other -> expectationFailure ("expected one refusal, got " <> show other)
    it "refuses an operand that is itself a NUMBER, naming the action's constructor, and explores nothing in its place" do
      g <- exploreSrc ordersSrc "a quote" defaultExploreOptions []
      [ l | (_, l, _) <- labels g, "quote" `Text.isInfixOf` l ] `shouldBe` []
      case g.gCoverage.cvRefused of
        [r] -> (r.rfVariable, r.rfType, r.rfWhole, r.rfConstructor) `shouldBe` ("p", "NUMBER", False, Just "quote")
        other -> expectationFailure ("expected one refusal, got " <> show other)

  describe "4. the ledger in the state" do
    it "a cell read by RECALL keeps its latest entry: three positions and their FULFILLED twins; the write-only cell is named" do
      g <- exploreSrc (switchSrc "RECALL" "A MAYBE BOOLEAN") "switch" defaultExploreOptions []
      counts g `shouldBe` (6, 12)
      coverageComplete g.gCoverage `shouldBe` True
      g.gCoverage.cvDropped `shouldBe` [("W", "log")]
      [ (c.lcCell, c.lcKeep, c.lcValues) | s <- take 3 g.gStates, c <- s.snLedger ] `shouldBe`
        [ ("light", KeptLatest, ["TRUE"]), ("light", KeptLatest, ["FALSE"]) ]
    it "a cell read by RECALL ALL keeps its whole history, which never closes here: the depth bound stops it and says so" do
      g <- exploreSrc (switchSrc "RECALL ALL" "A LIST OF BOOLEAN") "switch" defaultExploreOptions {eoMaxDepth = 3} []
      -- depth 3 holds 12 states: 8 still switching, which the bound cut,
      -- and 4 FULFILLED ones, which have nothing to cut and are terminal
      g.gCoverage.cvStops `shouldBe` [StopDepth 3 8]
      length [ () | s <- g.gStates, s.snDepth == 3, s.snTerminal ] `shouldBe` 4
      coverageComplete g.gCoverage `shouldBe` False
      coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "frontier NOT exhausted: 8 states at the depth bound 3 not expanded"
    it "a cell kept by request is no longer dropped, and splits the states it tells apart" do
      g <- exploreSrc (switchSrc "RECALL" "A MAYBE BOOLEAN") "switch" defaultExploreOptions [("log", False)]
      counts g `shouldBe` (8, 16)
      g.gCoverage.cvDropped `shouldBe` []
