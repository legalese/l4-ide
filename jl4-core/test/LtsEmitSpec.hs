{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The parts of @l4 explore --emit@ (REGULATIVE-LOWERING-SPEC.md §6.1,
-- WP3) that the dinner-race fixtures cannot reach, because no label of
-- theirs has the character or the name that triggers them. The emitted
-- files of the fixtures are pinned in @jl4/tests/LtsExplore.hs@.
--
--   1. the @.aut@ is one line per edge, in order, under a @des@ header of
--      the counts; a double quote in a label is written as a single quote,
--      since mCRL2's reader cannot escape one; a file in which that would
--      merge two labels, or turn one into @tau@, mCRL2's silent action, is
--      refused by name, not written;
--   2. an identifier is ASCII letters, digits and underscores, starting with
--      a letter, whatever the name it came from;
--   3. a fair act that is a self-loop in some states and moves in others is
--      fair on its moving edges only: @WF_vars(A /\ s' # s)@ in TLA+, and in
--      NuSMV its self-loops record another value, so that pausing on it
--      never counts as taking it, and its JUSTICE is enabled only where it
--      moves. No dinner fixture has such an act; @switch@ below does, twice.
module LtsEmitSpec (spec) where

import Data.Foldable (for_)
import qualified Data.Text as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Lts.Explore
import L4.Lts.Explore.Emit (EmitInput (..))
import L4.Lts.Explore.Emit.Aut (emitAut)
import L4.Lts.Explore.Emit.Model (EmAction (..), Fairness (..), Model (..), buildModel, identifier)
import L4.Lts.Explore.Emit.Smv (emitSmv)
import L4.Lts.Explore.Emit.Tla (TlaFiles (..), emitTla)
import L4.Lts.WhatIf (Rig (..))
import L4.TracePolicy (apiDefaultPolicy)

edge :: Int -> Text.Text -> Int -> Transition
edge i l j = MkTransition {tnFrom = i, tnLabel = l, tnTo = j, tnKind = EdgeAct}

-- | @flip@ records the light on, @flop@ off: each is a self-loop where the
-- light is already as it would leave it, and moves elsewhere.
switchSrc :: Text.Text
switchSrc = Text.unlines
  [ "DECLARE Who IS ONE OF W"
  , "DECLARE Move IS ONE OF flip, flop"
  , ""
  , "GIVEN light IS A MAYBE BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`ready` MEANS TRUE"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`switch` MEANS"
  , "    PARTY W"
  , "    MAY   act PROVIDED `ready` (RECALL W's `light`)"
  , "    WITHIN 0 OF 10"
  , "    HENCE CONSIDER act"
  , "          WHEN flip THEN RECORD `light` IS TRUE  HENCE `switch`"
  , "          WHEN flop THEN RECORD `light` IS FALSE HENCE `switch`"
  ]

switchModel :: IO Model
switchModel = do
  cfg <- resolveEvalConfig (Just (UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0))) apiDefaultPolicy
  r <- either (fail . ("typecheck failed: " <>) . show) pure (checkWithImports (vfsFromList []) switchSrc)
  let rig = MkRig {rigConfig = cfg, rigEntityInfo = r.tcdEntityInfo, rigEnv = emptyEnvironment, rigModule = r.tcdModule}
  start <- either (fail . Text.unpack) pure (startNamed r.tcdModule "switch" 0)
  g <- explore defaultExploreOptions {eoUntil = Just 10} (readSitesOf r.tcdModule []) rig start
         >>= either (fail . Text.unpack) pure
  pure (buildModel MkEmitInput
    { eiBase = "switch", eiSource = "switch.l4", eiGraph = g
    , eiProperties = [], eiLabels = mempty, eiFair = ["W"] })

spec :: Spec
spec = describe "l4 explore --emit" $ do
  describe "the .aut" $ do
    it "is a des header of the counts and one line per edge, in order" $
      emitAut 2 [edge 0 "PARTY World DOES `Bob's act`" 1, edge 1 "terminal" 1]
        `shouldBe` Right (Text.unlines
          [ "des (0,2,2)"
          , "(0,\"PARTY World DOES `Bob's act`\",1)"
          , "(1,\"terminal\",1)" ])

    it "writes a double quote in a label as a single quote, and a label over two lines on one" $
      emitAut 2 [edge 0 "PARTY World DOES pay \"rent\"" 1, edge 1 "time passes\n  the deadline" 1]
        `shouldBe` Right (Text.unlines
          [ "des (0,2,2)"
          , "(0,\"PARTY World DOES pay 'rent'\",1)"
          , "(1,\"time passes the deadline\",1)" ])

    it "refuses, naming both, two labels that would be written the same" $
      case emitAut 2 [edge 0 "pay \"rent\"" 1, edge 0 "pay 'rent'" 1] of
        Left why -> do
          why `shouldSatisfy` Text.isInfixOf "pay \"rent\""
          why `shouldSatisfy` Text.isInfixOf "pay 'rent'"
          why `shouldSatisfy` Text.isInfixOf "would merge them"
        Right t -> expectationFailure ("expected a refusal, got " <> show t)

    it "refuses a label that would be mCRL2's silent action" $
      case emitAut 1 [edge 0 "tau" 0] of
        Left why -> why `shouldSatisfy` Text.isInfixOf "silent action"
        Right t -> expectationFailure ("expected a refusal, got " <> show t)

  describe "identifiers" $
    it "are ASCII letters, digits and underscores, starting with a letter" $
      map identifier ["Alice's belief is stale", "`ledger records Bob's purchase`", "1st act", "été", "--"]
        `shouldBe` ["Alice_s_belief_is_stale", "ledger_records_Bob_s_purchase", "x_1st_act", "t", "x"]

  describe "a fair act that is a self-loop in some states" $
    it "is fair on its moving edges only, in TLA+ and in NuSMV" $ do
      m <- switchModel
      -- three states: the outset, the light on, the light off; each act
      -- moves from two of them and is a self-loop at the third
      m.mdStates `shouldBe` 3
      [ (a.eaIdent, a.eaFairness, a.eaStill, length [ () | (i, j) <- a.eaEdges, i == j ]) | a <- m.mdActions ]
        `shouldBe` [ ("W_flip", Fair, Just "W_flip_still", 1), ("W_flop", Fair, Just "W_flop_still", 1) ]
      let tla = (emitTla m).tfModule
          smv = emitSmv m
          selfLoopOf ident = [ i | a <- m.mdActions, a.eaIdent == ident, (i, j) <- a.eaEdges, i == j ]
          movesFrom ident = [ i | a <- m.mdActions, a.eaIdent == ident, (i, j) <- a.eaEdges, i /= j ]
      tla `shouldSatisfy` Text.isInfixOf "FairSpec == Spec /\\ WF_vars(W_flip /\\ s' # s) /\\ WF_vars(W_flop /\\ s' # s)\n"
      for_ ["W_flip", "W_flop"] \ ident -> do
        -- its self-loop records the other value, its moves its own
        [ l | l <- Text.lines smv, Text.pack ("next(act) = " <> ident <> "_still") `Text.isInfixOf` l ]
          `shouldBe` [ "   | (s = " <> tshow i <> " & next(s) = " <> tshow i <> " & next(act) = " <> Text.pack ident <> "_still)" | i <- selfLoopOf (Text.pack ident) ]
        -- and its JUSTICE is enabled where it moves, not where it pauses
        [ l | l <- Text.lines smv, "JUSTICE " `Text.isPrefixOf` l, Text.pack ("act = " <> ident <> ";") `Text.isSuffixOf` l ]
          `shouldBe` [ "JUSTICE !(s in {" <> Text.intercalate ", " (map tshow (movesFrom (Text.pack ident))) <> "}) | act = " <> Text.pack ident <> ";" ]
  where
    tshow = Text.pack . show
