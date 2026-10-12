{-# LANGUAGE OverloadedRecordDot, OverloadedStrings #-}
-- | The key environment ('AtomKey.KeyEnv') walks the whole module. It is built once
-- per 'Ladder.VizConfig', so the decisions a caller draws from one config share
-- it; a config made per decision paid for the walk each time, which is quadratic
-- in the size of the file (@l4 verify@ on a 1,000-decision file took 8.1 s of
-- which 6.6 s was the walk; measured 2026-10-12).
--
-- "Built once" is asserted as sharing: the key environments of two passes are the
-- same heap object ('System.Mem.StableName'), not as a time. A config made afresh
-- is the control: its environment is a different object, so the check can tell
-- the two apart.
--
-- The other half is staleness. The environment describes the module the config
-- was made for, so pointing a config at a newer check of the document has to
-- rebuild it ('Ladder.retargetVizConfig', which @updateVizConfig@ uses); a record
-- update of @module'@ would not, and keys drawn through the old environment are
-- different keys.
module KeyEnvSharingSpec (spec) where

import Control.Exception (evaluate)
import Control.Monad (forM, forM_)
import qualified Data.IntMap.Strict as IntMap
import Data.List (nub, sort)
import qualified Data.Text as T
import System.Mem.StableName (makeStableName)

import L4.Syntax (Decide, Resolved, foldTopLevelDecides)
import LSP.L4.Rules (TypeCheckResult (..))
import qualified LSP.L4.Viz.Ladder as Ladder

import CheckSource (checkSource)

import Test.Hspec

-- | Three decisions, so that there is something to share between.
threeRules :: T.Text
threeRules = T.unlines
  [ "GIVEN p IS A BOOLEAN"
  , "      q IS A BOOLEAN"
  , "DECIDE alpha p q IF p AND NOT q"
  , ""
  , "GIVEN k IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "DECIDE beta k IF k > 3"
  , ""
  , "GIVEN a IS A BOOLEAN"
  , "DECIDE gamma a IF a OR NOT a"
  ]

drawn :: Ladder.VizConfig -> Decide Resolved -> IO Ladder.VizState
drawn cfg d = case Ladder.doVisualize d cfg of
  Right (_, st) -> pure st
  Left err -> fail ("could not draw: " <> T.unpack (Ladder.prettyPrintVizError err))

-- | The keys a decision's leaves were given, as a sorted list of texts.
keysOf :: Ladder.VizConfig -> Decide Resolved -> IO [T.Text]
keysOf cfg d = sort . IntMap.elems . Ladder.getLeafKeys <$> drawn cfg d

spec :: Spec
spec = do
  describe "the key environment of a VizConfig" $ do
    it "is shared by every decision drawn from the config, and not by a config made afresh" $ do
      (verId, tc) <- checkSource "key-env-sharing" threeRules
      -- the control comes from a second check, not a second call on the same
      -- arguments, which the compiler is free to merge into the first
      (verId2, tc2) <- checkSource "key-env-sharing-again" threeRules
      let cfg = Ladder.mkVizConfig verId tc.module' tc.substitution False
          fresh = Ladder.mkVizConfig verId2 tc2.module' tc2.substitution False
          decides = foldTopLevelDecides (\d -> [d]) tc.module'
          envName c d = drawn c d >>= evaluate . Ladder.getKeyEnv >>= makeStableName
      length decides `shouldBe` 3
      shared <- forM decides (envName cfg)
      length (nub shared) `shouldBe` 1
      -- a config derived from it keeps the environment: Verify draws a call's
      -- meaning without simplification, and the IDE with expansions
      derived <- forM decides (envName (Ladder.withSimplification True cfg))
      expanded <- forM decides (envName (Ladder.withCallExpansions cfg))
      (nub (derived <> expanded) == nub shared) `shouldBe` True
      -- the control: the check can tell two environments apart
      other <- forM (foldTopLevelDecides (\d -> [d]) tc2.module') (envName fresh)
      length (nub other) `shouldBe` 1
      (other == shared) `shouldBe` False

    it "is rebuilt when the config is pointed at another check of the document" $ do
      (verA, tcA) <- checkSource "key-env-retarget-a" threeRules
      (verB, tcB) <- checkSource "key-env-retarget-b" threeRules
      let cfgA = Ladder.mkVizConfig verA tcA.module' tcA.substitution False
          retargeted = Ladder.retargetVizConfig verB tcB.module' tcB.substitution cfgA
          fresh = Ladder.mkVizConfig verB tcB.module' tcB.substitution False
          decides = foldTopLevelDecides (\d -> [d]) tcB.module'
      forM_ decides \d -> do
        want <- keysOf fresh d
        want `shouldSatisfy` (not . null)
        keysOf retargeted d >>= (`shouldBe` want)
        -- the control, and what a stale environment would do: B's names are
        -- foreign to the environment of A, so they key differently
        stale <- keysOf cfgA d
        stale `shouldNotBe` want
